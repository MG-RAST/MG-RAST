#!/usr/bin/perl

use CGI;
use JSON;
use Conf;
use Data::Dumper;
use URI::Escape;

# create cgi and json objects
my $cgi  = new CGI;
my $json = new JSON;
$json = $json->utf8();

# get request method
$ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
my $request_method = $ENV{'REQUEST_METHOD'};

if (lc($request_method) eq 'options') {
  print $cgi->header(-Access_Control_Allow_Origin => '*',
		     -status => 200,
		     -type => 'text/plain',
		     -Access_Control_Allow_Methods => 'POST, GET, OPTIONS',
		     -Access_Control_Allow_Headers => 'AUTH'
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
my @rest_parameters = split m#/#, $rest;
map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);

# get the resource
my $resource = shift @rest_parameters;

# get resource list
my $resources = [];
my $resource_path = $Conf::api_resource_path."2";
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
  @$resources = map { my ($r) = $_ =~ /^(.*)\.pm$/; $r ? $r: (); } @res;  
  @$resources = map { $_ eq 'resource' ? () : $_; } @$resources;
} else {
  if ($cgi->param('POSTDATA') && ! $resource) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( { jsonrpc => "2.0",
			   id => undef,
			   error => {  code => -32603,
				       message => "Internal error",
				       data => "resource directory offline" } } );
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource directory offline";
    exit 0;
  }
}

# check for json rpc
my $json_rpc = $cgi->param('POSTDATA') || $cgi->param('keywords');
$cgi->delete('POSTDATA');
my $json_rpc_id;
my $rpc_request;
my $submethod;
if ($json_rpc && ! $resource) {
  eval { $rpc_request = $json->decode($json_rpc) };
  if ($@) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( { jsonrpc => "2.0",
			   id => undef,
			   error => {  code => -32700,
				       message => "Parse error",
				       data => $@ } } );
    exit 0;
  }
  
  #    if ($rpc_request->{jsonrpc} && $rpc_request->{jsonrpc} eq "2.0" && $rpc_request->{method}) {
  $json_rpc_id = $rpc_request->{id};
  my $params = $rpc_request->{params};
  if (ref($params) eq 'ARRAY' && ref($params->[0]) eq 'HASH') {
    $params = $params->[0];
  }
  unless (ref($params) eq 'HASH') {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( { jsonrpc => "2.0",
			   id => undef,
			   error => {  code => -32602,
				       message => "Invalid params",
				       data => "only named parameters are accepted" } } );
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

# check for authentication
my $user;
if ($cgi->http('HTTP_AUTH') || $cgi->param('auth')) {
  use Auth;
  $user = Auth::authenticate($cgi->http('HTTP_AUTH') || $cgi->param('auth'));
  unless($user) {
    print $cgi->header( -type => 'application/json',
	                -status => 401,
    	                -Access_Control_Allow_Origin => '*' );
    print "{ \"ERROR\": \"auth parameter did not authenticate\" }";
    exit 0;
  }
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
    my $package = "resources2::".$resource;
    {
        no strict;
        eval "require $package;";
        $error = $@;
    }
    if ($error) {
        print $cgi->header( -type => 'application/json',
    		                -status => 500,
    		                -Access_Control_Allow_Origin => '*' );
        print "{ \"ERROR\": \"resource '$resource' does not exist\" }";
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
			                    -Access_Control_Allow_Origin => '*' );
            print "ERROR: resource request failed\n$@\n";
            exit 0;
        }
    }
}
# we are called without a resource, return API information
else {
  my @resource_objects = map { { 'name' => $_, 'url' => $cgi->url.'/'.$_ } } sort @$resources;
  my $content = { version => 1,
		  service => 'MG-RAST',
		  url => $cgi->url,
		  documentation => $cgi->url.'/api.html',
		  description => "RESTful Metagenomics RAST object and resource API\nFor usage note that required parameters need to be passed as path parameters, optional parameters need to be query parameters. If an optional parameter has a list of option values, the first displayed will be used as default.",
		  contact => 'mg-rast@mcs.anl.gov',
		  resources => \@resource_objects };
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
