use CGI;
use JSON;
use Conf;
use Data::Dumper;
use URI::Escape;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

# create cgi and json objects
my $cgi  = new CGI;
my $json = new JSON;
$json = $json->utf8();

my %private_resources = ( 'job'      => 1,
                          'notebook' => 1,
                          'pipeline' => 1,
                          'resource' => 1,
                          'status'   => 1,
                          'user'     => 1 );

# get request method
$ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
my $request_method = $ENV{'REQUEST_METHOD'};

if (lc($request_method) eq 'options') {
  print $cgi->header(-Access_Control_Allow_Origin => '*',
		     -status => 200,
		     -type => 'text/plain',
		     -charset => 'UTF-8',
		     -Access_Control_Allow_Methods => 'POST, GET, OPTIONS, PUT, DELETE',
		     -Access_Control_Allow_Headers => 'AUTH, AUTHORIZATION, CONTENT-TYPE'
		    );
  print "";
  exit 0;
}

# get REST parameters
my $abs = $cgi->url(-relative=>1);
if ($abs !~ /\.cgi/) {
  $abs = $cgi->url(-base=>1);
}
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\/?//;
$rest =~ s/^\///;
$rest =~ s/^\d+//;
$rest =~ s/^\///;
$rest =~ s/^api\.cgi//;
$rest =~ s/^\///;

my @rest_parameters = split m#/#, $rest;
map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);

# get the resource
my $resource = shift @rest_parameters;

# get resource list
my $resources = [];
my $resource_path = $Conf::api_resource_path;
if (! $resource_path) {
  print $cgi->header(-type => 'text/plain',
		     -status => 500,
		     -charset => 'UTF-8',
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode( {"ERROR"=> "resource directory not found"} );
  exit 0;
}

if (opendir(my $dh, $resource_path)) {
  my @res = grep { -f "$resource_path/$_" } readdir($dh);
  closedir $dh;
  @$resources = map { my ($r) = $_ =~ /^(.*)\.pm$/; $r ? $r: (); } grep { $_ =~ /^[a-zA-Z](.*)\.pm$/ } @res;
  @$resources = grep { ! exists($private_resources{$_}) } @$resources;
} else {
  if ($cgi->param('POSTDATA') && ! $resource) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -charset => 'UTF-8',
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( { jsonrpc => "2.0",
			   id => undef,
			   error => { code => -32603,
				      message => "Internal error",
				      data => "resource directory offline" }
			 } );
    exit 0;
  } else {
    print $cgi->header( -type => 'text/plain',
			-status => 500,
			-charset => 'UTF-8',
			-Access_Control_Allow_Origin => '*' );
	print $json->encode( {"ERROR"=> "resource directory offline"} );
    exit 0;
  }
}

# check for json rpc
my $json_rpc = $cgi->param('POSTDATA') || $cgi->param('keywords');

# no resource, process as json rpc
if ($json_rpc && (! $resource)) {
    $cgi->delete('POSTDATA');
    my ($rpc_request, $submethod);
    eval { $rpc_request = $json->decode($json_rpc) };
    if ($@) {
        print $cgi->header( -type => 'application/json',
			    -status => 200,
			    -charset => 'UTF-8',
			    -Access_Control_Allow_Origin => '*' );
        print $json->encode( { jsonrpc => "2.0",
                               id => undef,
                               error => { code => -32700,
				                          message => "Parse error",
				                          data => $@ }
				            } );
        exit 0;
    }
  
    my $json_rpc_id = $rpc_request->{id};
    my $params = $rpc_request->{params};
    if (ref($params) eq 'ARRAY' && ref($params->[0]) eq 'HASH') {
        $params = $params->[0];
    }
    unless (ref($params) eq 'HASH') {
        print $cgi->header( -type => 'application/json',
			    -status => 200,
			    -charset => 'UTF-8',
			    -Access_Control_Allow_Origin => '*' );
        print $json->encode( { jsonrpc => "2.0",
			                   id => undef,
			                   error => { code => -32602,
				                          message => "Invalid params",
				                          data => "only named parameters are accepted" }
				            } );
        exit 0;
    }
    foreach my $key (keys(%$params)) {
        if ($key eq 'id') {
            @rest_parameters = ( $params->{$key} );
        } else {
            $cgi->param($key, $params->{$key});
        }
    }
    (undef, $request_method, $resource, $submethod) = $rpc_request->{method} =~ /^(\w+\.)?(get|post|delete|put)_(\w+)_(\w+)$/;
    $json_rpc = 1;
}
# this is not json rpc, normal data POST
else {
    $json_rpc = undef;
}

# check for authentication
my $user;
if ($cgi->http('HTTP_AUTH') || $cgi->param('auth') || $cgi->http('HTTP_Authorization') || $cgi->param('authorization')) {
    eval {
        require Auth;
        Auth->import();
        my $message;
        ($user, $message) = Auth::authenticate($cgi->http('HTTP_AUTH') || $cgi->param('auth') || $cgi->http('HTTP_Authorization') || $cgi->param('authorization'));
        unless($user) {
	  unless ($message eq "valid kbase user") {
            print $cgi->header( -type => 'application/json',
				-status => 401,
				-charset => 'UTF-8',
    	                        -Access_Control_Allow_Origin => '*' );
            print $json->encode( {"ERROR"=> "authentication failed - $message"} );
            exit 0;
	  }
        }
    };
}

# print google analytics
use GoogleAnalytics;
my $debug = undef;
if($user) {
  GoogleAnalytics::track_page_view($user->_id, $debug);
} else {
  GoogleAnalytics::track_page_view("anonymous", $debug);
}

# if a resource is passed, call the resources module
if ($resource) {
    my $error   = '';
    my $package = $Conf::api_resource_dir."::".$resource;
    {
        no strict;
        eval "require $package;";
        $error = $@;
    }
    if ($error) {
      print STDERR $error."\n";
      print $cgi->header( -type => 'application/json',
			  -status => 500,
			  -charset => 'UTF-8',
			  -Access_Control_Allow_Origin => '*' );
      print $json->encode( {"ERROR"=> "resource '$resource' does not exist"} );
      exit 0;
    } else {
      # check for kbase ids
      if (scalar(@rest_parameters)) {
	      $rest_parameters[0] = uri_unescape($rest_parameters[0]);
	      $rest_parameters[0] =~ s/^kb\|(.+)$/$1/;
      }

      # create params hash
      my $params= { 'rest_parameters' => \@rest_parameters,
		    'method'          => $request_method,
		    'user'            => $user,
		    'json_rpc'        => $json_rpc,
		    'json_rpc_id'     => $json_rpc_id,
		    'submethod'       => $submethod,
		    'cgi'             => $cgi,
		    'resource'        => $resource
		  };
        eval {
            my $resource_obj = $package->new($params);
            $resource_obj->request();
        };
        if ($@) {
	  print $cgi->header( -type => 'text/plain',
			      -status => 500,
			      -charset => 'UTF-8',
			      -Access_Control_Allow_Origin => '*' );
	  print $json->encode( {"ERROR"=> "resource request failed\n$@\n"} );
	  exit 0;
        }
    }
}
# we are called without a resource, return API information
else {
  my $cgi_url = $Conf::url_base ? $Conf::url_base : $cgi->url;
  $cgi_url =~ s/^(.*)\/$/$1/;
  $cgi_url =~ s/^(.*)\/api.cgi$/$1/;
  my @res = map {{ 'name' => $_, 'url' => ($Conf::url_base || $cgi->url).'/'.$_ , 'documentation' => $cgi_url.'/api.html#'.$_}} sort @$resources;
  my $content = { version => 1,
		  service => 'MG-RAST',
		  url => ($Conf::url_base || $cgi->url),
		  documentation => $cgi_url.'/api.html',
		  description => "<p>The MG-RAST API covers most of the functionality available through the MG-RAST website, with access to annotations, analyses, metadata and access to the MG-RAST user inbox to view contents as well as upload files. All sequence data and data products from intermediate stages in the analysis pipeline are available for download. Other resources provide services not available through the website, e.g. the m5nr resource lets you query the m5nr database.</p><p>Each query to the API is represented as a URI beginning with \"http://api.metagenomics.anl.gov/\" and has a defined structure to pass the requests and parameters to the API server.</p><p>The URI queries can be used from the command line, e.g. using curl, in a browser, or incorporated in a shell script or program.</p><p>Each URI has the form</p><pre>\"http://api.metagenomics.anl.gov/{version}/{resourcepath}?{querystring}\"</pre><p>The {version} value (currently '1') explicitly directs the request to a specific version of the API, if it is omitted the latest API version will be used.</p><p>The resource path is constructed from the path parameters listed below to define a specific resource and the optional query string is used to filter the results obtained for the resource. For example:</p><pre>http://api.metagenomics.anl.gov/1/annotation/sequence/mgm4447943.3?evalue=10&type=organism&source=SwissProt</pre><p>In this example the resource path \"annotation/sequence/mgm4447943.3\" defines a request for the annotated sequences for the MG-RAST job with ID 4447943.3.</p><p>The optional query string \"evalue=10&type=organism&source=SwissProt\" modifies the results by setting an evalue cutoff, annotation type and database source.</p><p>The API provides an authentication mechanism for access to private MG-RAST jobs and users' inbox. The 'auth_key' (or 'webkey') is a 25 character long string  (e.g. 'j6FNL61ekNarTgqupMma6eMx5') which is used by the API to identify an MG-RAST user account and determine access rights to metagenomes. Note that the auth_key is valid for a limited time after which queries using the key will be rejected. You can create a new auth_key or view the expiration date and time of an existing auth_key on the MG-RAST website. An account can have only one valid auth_key and creating a new key will invalidate an existing key.</p><p>All public data in MG-RAST is available without an auth_key. All API queries for private data which either do not have an auth_key or use an invalid or expired auth_key will get a \"insufficient permissions to view this data\" response.</p><p>The auth_key can be included in the query string like:</p><pre>\nhttp://api.metagenomics.anl.gov/1/annotation/sequence/mgm4447943.3?evalue=10&type=organism&source=SwissProt&auth=j6FNL61ekNarTgqupMma6eMx5</pre><p>or in a request using curl like:</p><pre>curl -X GET -H \"auth: j6FNL61ekNarTgqupMma6eMx5\" \"http://api.metagenomics.anl.gov/1/annotation/sequence/mgm4447943.3?evalue=10&type=organism&source=SwissProt\"</pre><p>Note that for the curl command the quotes are necessary for the query to be passed to the API correctly.</p><p>If an optional parameter passed through the query string has a list of values only the first will be used. When multiple values are required, e.g. for multiple md5 checksum values, they can be passed to the API like:</p><pre>curl -X POST -d '{\"data\":[\"000821a2e2f63df1a3873e4b280002a8\",\"15bf1950bd9867099e72ea6516e3d602\"]}' \"http://api.metagenomics.anl.gov/m5nr/md5\"</pre><p>In some cases, the data requested is in the form of a list with a large number of entries. In these cases the limit and offset parameters can be used to step through the list, for example:</p><pre>http://api.metagenomics.anl.gov/1/project?order=name&limit=20&offset=100</pre><p>will limit the number of entries returned to 20 with an offset of 100. If these parameters are not provided default values of limit=10 and offset=0 are used. The returned JSON structure will contain the 'next' and 'prev' (previous) URIs to simplify stepping through the list.</p><p>The data returned may be plain text, compressed gzipped files or a JSON structure.</p><p>Most API queries are 'synchronous' and results are returned immediately. Some queries may require a substantial time to compute results, in these cases you can select the asynchronous option by adding '&asynchronous=1' to the end of the query string. This query will then return a URL which will return the query results when they are ready.</p>",
		  contact => 'mg-rast@mcs.anl.gov',
		  resources => \@res };
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -charset => 'UTF-8',
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
