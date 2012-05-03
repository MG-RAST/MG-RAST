use CGI;
use JSON;

use FIG_Config;

use WebApplicationDBHandle;
use DBMaster;

# create cgi and json objects
my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

# initialize user database
my ($dbmaster, $error) = WebApplicationDBHandle->new();
my $authentication_available = 1;

if ($error) {
    $authentication_available = 0;
    
    if ($FIG_Config::api_fatal_on_no_auth_db) {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: authentication database offline";
	exit 0;
    }
}

# get request method
$ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
my $request_method = $ENV{'REQUEST_METHOD'};

# get REST parameters
my $abs = $cgi->url(-relative=>1);
if ($abs !~ /\.cgi/) {
    $abs = $cgi->url(-base=>1);
}
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\/?//;
my @rest_parameters = split m#/#, $rest;
map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);

# get the resource
my $resource = shift @rest_parameters;

# get CGI parameters
my @cgi_names = $cgi->param;
my $cgi_parameters = {};
%$cgi_parameters = map { $_ => $cgi->param($_) } @cgi_names;

# get resource list
my $resources = [];
my $resources_hash = {};
my $resource_path = $FIG_Config::api_resource_path;
if (! $resource_path) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource directory not found";
    exit 0;
}
if (opendir(my $dh, $resource_path)) {
    my @res = grep { -f "$resource_path/$_" } readdir($dh);
    closedir $dh;
    @$resources = map { my ($r) = $_ =~ /^(.*)\.pm$/; $r; } @res;
    %$resources_hash = map { $_ => 1 } @$resources;

} else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource directory offline";
    exit 0;
}

# check for auth parameter and aquire request body
my $request_body;
my $auth;
if ($ENV{'REQUEST_METHOD'} eq "POST") {
    $request_body = $cgi->param('POSTDATA');
    unless ($request_body) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: POST without data";
	exit 0;
    }
    $request_body = $json->decode($request_body);
    if (exists($request_body->{auth})) {
	$auth = $request_body->{auth};
    } else {
	$auth = $cgi->param('auth');
    }
} elsif ($ENV{'REQUEST_METHOD'} eq "GET") {
    $auth = $cgi->param('auth');
} elsif ($ENV{'REQUEST_METHOD'} eq "PUT") {
    $request_body = $cgi->param('PUTDATA');
    unless ($request_body) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: PUT without data";
	exit 0;
    }
    $request_body = $json->decode($request_body);
    if (exists($request_body->{auth})) {
	$auth = $request_body->{auth};
    } else {
	$auth = $cgi->param('auth');
    }
}

# check authentication
my $user;
if ($auth && $authentication_available) {
    my $preference = $dbmaster->Preferences->get_objects( { value => $auth } );
    if (scalar(@$preference)) {
	my $u = $preference->[0]->user;
	my $tdate = $dbmaster->Preferences->get_objects( { user => $u, name => 'WebServiceKeyTdate' } );
	if (scalar(@$tdate)) {
	    if (($tdate->[0]->{value} > time) || $u->has_right(undef, 'edit', 'user', '*')) {
		$user = $u;
	    } else {
		print $cgi->header(-type => 'text/plain',
				   -status => 401,
				   -Access_Control_Allow_Origin => '*' );
		print "ERROR: Authentication failed - WebServiceKey timed out";
		exit 0;
	    }
	} else {
	    my $timeout = 86400;
	    my $tdate = time + $timeout;
	    $dbmaster->Preferences->create( { user => $u, name => 'WebServiceKeyTdate', value => $tdate } );
	    $user = $u;
	}
    } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Authentication failed - invalid WebServiceKey";
	exit 0;	
    }
}

# if a resource is passed, call the resources module
if ($resource) {
    if ($resources_hash->{$resource}) {
	my $query = "use resources::$resource; resources::".$resource."::request( { 'rest_parameters' => \\\@rest_parameters, 'cgi_parameters' => \$cgi_parameters, 'request_method' => \$request_method, 'request_body' => \$request_body, 'user' => \$user } );";
	eval $query;
	if ($@) {
	    print $cgi->header(-type => 'text/plain',
			       -status => 500,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: resource request failed\n";
	    print "$@\n";
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: resource '$resource' does not exist";
	exit 0;
    }
}
# we are called without a resource, return API information
else {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    my $content = { id => 'MG-RAST',
		    documentation => 'http://dev.metagenomics.anl.gov/Html/api.html',
		    contact => 'mg-rast@mcs.anl.gov',
		    resources => $resources,
		    url => $cgi->url."/" };
    print $json->encode($content);
    exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
