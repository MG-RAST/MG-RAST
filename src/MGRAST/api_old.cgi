use CGI;
use JSON;

use LWP::Simple;

use Data::Dumper;

use WebApplicationDBHandle;
use DBMaster;

use WebServiceObject;
use WebServiceSpecial;

use JobDB::Analysis;

# initialize databases
my ($dbmaster, $error) = WebApplicationDBHandle->new();

# create cgi and json objects
my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

# get parameters
my $abs = $cgi->url(-base=>0);
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\/?//;
my $get_objects = "get_objects";

my @rest = split m#/#, $rest;

map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);
$ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;

my $request_body;
my $auth;

unless (scalar(@rest)) {
    print $cgi->redirect('http://dev.metagenomics.anl.gov/Html/api.html');
    exit 0;
}

if ($ENV{'REQUEST_METHOD'} eq "POST") {
    $request_body = $cgi->param('POSTDATA');
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
    $auth = $request_body->{auth};
    unless ($auth) {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: PUT without required authentication";
	exit 0;
    }
}

# check authentication
my $user;
if ($auth) {
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

my $object_type = shift @rest;

# connect to the object database
my ($object_master, $WSOerror) = WebServiceObject::db_connect();
if ($WSOerror) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Connection to object database failed - $WSOerror";
    exit 0;
}

# check special cases
if (WebServiceSpecial::cases->{$object_type}) {

    my $query;
    my $rbd;
    if ($ENV{'REQUEST_METHOD'} eq 'PUT') {
	if (WebServiceSpecial::writable->{$object_type}) {
	    $rbd = $request_body->{data};
	    $query = "&WebServiceSpecial::$object_type(\$rbd, \$object_master, \$user, 'create');";
	} else {
	    print $cgi->header(-type => 'text/plain',
			       -status => 403,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Creation failed - object type $object_type is readonly";
	    exit 0;
	}
    } else {
	if ($request_body) {
	    $rbd = $request_body->{data};
	}
	$query = "&WebServiceSpecial::$object_type(\\\@rest, \$object_master, \$user, \$rbd);";
    }
    eval $query;
    if ($@) {
	print STDERR "$@\n";
    }
    exit 0;
}

my ($first, $rem) = $object_type =~ /^(\w)(\w+)$/;
$object_type = uc($first).$rem;

# validate object type
my $result;
my $query;
if ($object_type) {
    $query = "\$result = \$object_master->knows_class($object_type);";
    eval $query;
    if (! defined($result) ) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid parameters - invalid object type: $object_type";
	exit 0;
    }
    $query = "\$result = \$object_master->$object_type->_webserviceable();";
    eval $query;
    unless ($result) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid parameters - object type $object_type not allowed for webservice";
	exit 0;
    }
    elsif ($result == 2) {
	$get_objects = "_webservice_get_objects";
    }
} else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid parameters - missing object type";
    exit 0;
}

# this is a POST or PUT with a request body
if ($request_body) {
    if ($ENV{'REQUEST_METHOD'} eq "POST") {
	unless (ref($request_body) eq 'HASH' && exists($request_body->{query}) && ref($request_body->{query}) eq 'ARRAY') {
	    print $cgi->header(-type => 'text/plain',
			       -status => 400,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Invalid request body for POST - parameter 'query' must be defined and an array of query parameters";
	    exit 0;
	}
	my $select_params = {};
	my $allowed_operators = { 'like' => 1,
				  '!=' => 1,
				  '=' => 1,
				  '<' => 1,
				  '>' => 1,
				  '<=' => 1,
				  '>=' => 1 };
	foreach my $row (@{$request_body->{query}}) {
	    if ($allowed_operators->{$row->[2]}) {
		$select_params->{$row->[0]} = [ $row->[1], $row->[2] ];
	    } else {
		print $cgi->header(-type => 'text/plain',
				   -status => 400,
				   -Access_Control_Allow_Origin => '*' );
		print "ERROR: Invalid query operator '".$row->[2]."' - allowed operators are [ 'like', '!=', '=', '<', '>', '<=', '>=' ]";
		exit 0;
	    }
	}
	$query = "\$result = \$object_master->$object_type->$get_objects(\$select_params, \$user);";
	eval $query;
    } elsif ($ENV{'REQUEST_METHOD'} eq "PUT") {
	unless (ref($request_body) eq 'HASH' && exists($request_body->{data}) && ref($request_body->{data}) eq 'ARRAY') {
	    print $cgi->header(-type => 'text/plain',
			       -status => 400,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Invalid request body for PUT - parameter 'data' must be defined and an array of data objects";
	    exit 0;
	}
	
	unless (WebServiceSpecial::writable->{$object_type}) {
	    print $cgi->header(-type => 'text/plain',
			       -status => 403,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Creation failed - object type $object_type is readonly";
	    exit 0;
	}

	# create the data objects
	my $data_objects = $request_body->{data};
	my $intermediate_result;
	my $errors = [];
	foreach my $data_object (@$data_objects) {
	    $query = "\$intermediate_result = \$object_master->$object_type->create(\$data_object, \$user);";
	    eval $query;
	    unless ($intermediate_result) {
		push(@$errors, $data_object);
	    } else {
		push(@$result, $intermediate_result);
	    }
	}
	print $cgi->header(-type => 'application/json',
			   -status => 200,
			   -Access_Control_Allow_Origin => '*' );
	print $json->encode( { 'success' => $result, 'errors' => $errors } );
	exit 0;
    }
}

# get all object ids
elsif (scalar(@rest) == 0) {
    $query = "\$result = \$object_master->$object_type->$get_objects(undef, \$user);";
    eval $query;
    if ($@) {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: $@";
	exit 0;
    }
    my $ids = [];
    my $about = "";
    if (ref($result) && ref($result) eq 'ARRAY' && scalar(@$result)) {
	@$ids = map { $_->{id} } @$result;
	$about = $result->[0]->{about};
    }

    if ($cgi->param('callback')) {
	print $cgi->header(-type => 'application/json',
			   -status => 200,
			   -Access_Control_Allow_Origin => '*' );
	print "data_return('$object_type', ".$json->encode( { 'about' => $about, lc($object_type)."s" => $ids } ).");";
	exit 0;
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( { 'about' => $about, lc($object_type)."s" => $ids } );
    exit 0;
}

my $id;
my $method;
my $params = {};
if (scalar(@rest) == 1) {
    $id = shift @rest;
} elsif (scalar(@rest) == 2) {
    $id = shift @rest;
    $method = shift @rest;
} elsif (scalar(@rest)) {
    $method = shift @rest;

    # hashify params
    for (my $i=0; $i<scalar(@rest); $i+=2) {
	$params->{$rest[$i]} = $rest[$i+1];
    }
}

if ( $ENV{'REQUEST_METHOD'} =~/head/i ) {
    if ($id) {
	$query = "\$result = \$object_master->$object_type->$get_objects({ id => \"$id\"}, \$user);";
	eval $query;
	if (ref($result) && ref($result) eq 'ARRAY' && scalar(@$result)) {
	    print $cgi->header(-type => 'text/plain',
			       -status => 200,
			       -Access_Control_Allow_Origin => '*' );
	    print "1";
	    exit 0;
	} else {
	    print $cgi->header(-type => 'text/plain',
			       -status => 200,
			       -Access_Control_Allow_Origin => '*' );
	    print "0";
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid parameters for HEAD: missing ID";
	exit 0;
    }
}

if ($id && $method) {
    $query = "\$result = \$object_master->$object_type->$method(\$id, \$user);";
    eval $query;
    unless (ref($result)) {
	print $cgi->header(-type => 'text/plain',
			   -status => 204,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: object retrieval failed for object $object_type method $method id $id";
	print STDERR "$@ $!\n";
	exit 0;
    }    
} elsif ($id) {
    $query = "\$result = \$object_master->$object_type->$get_objects({ id => \"$id\"}, \$user);";
    eval $query;
    unless (ref($result) && ref($result) eq 'ARRAY' && scalar(@$result)) {
	print $cgi->header(-type => 'text/plain',
			   -status => 204,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: object retrieval failed for object $object_type id $id";
	print STDERR "$@ $!\n";
	exit 0;
    }
} elsif ($method && lc($method) eq 'query') {
    $query = "\$result = \$object_master->$object_type->$get_objects({".join(", ", map { $_ . " => \"" . $params->{$_} ."\"" } keys(%$params))."}, \$user);";
    eval $query;
} elsif ($method) {
    $query = "\$result = \$object_master->$object_type->$method(\$params, \$user);";
    eval $query;
    if ($@) {
	print STDERR $@."\n";
    }
    exit 0;
}

if ($@) {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print Dumper($@);
    exit 0;
}

if (ref($result)) {
    unless (ref($result) eq 'ARRAY') {
	$result = [ $result ];
    }
    my $printable = [];
    foreach my $obj (@$result) {
	my $plain_obj = {};
	foreach my $k (keys(%$obj)) {
	    if ($k !~ /^_/) {
		if (ref($obj->{$k}) eq 'ARRAY') {
		    $plain_obj->{$k} = [];
		    foreach my $nested (@{$obj->{$k}}) {
			if (ref($nested) eq 'HASH') {
			    my $nested_obj = {};
			    foreach my $k2 (keys(%$nested)) {
				if ($k2 eq '_id') {
				    $nested_obj->{$k2} = $nested->{$k2};
				} elsif ($k2 !~ /^_/) {
				    $nested_obj->{$k2} = $nested->{$k2};
				}
			    }
			}
			push(@{$plain_obj->{$k}}, $nested);
		    }
		} else {
		    $plain_obj->{$k} = $obj->{$k};
		}
	    }
	}
	push(@$printable, $plain_obj);
    }

    if (scalar(@$printable) == 1) {
	$printable = $printable->[0];
    }

    if ($cgi->param('callback')) {
	print $cgi->header(-type => 'application/json',
			   -status => 200,
			   -Access_Control_Allow_Origin => '*' );
	print "data_return('$object_type', ".$json->encode( $printable ).", '$object_type');";
	exit 0;
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( $printable );
    exit 0;
} else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "invalid query";
    exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
