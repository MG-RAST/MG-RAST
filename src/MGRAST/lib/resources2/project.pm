package resources2::project;

use Conf;
use CGI;
use JSON;

# STATUS CODES
#
# Success
# 200 OK
# 201 Created
# 204 No Content
#
# Client Error
# 400 Bad Request
# 401 Unauthorized
# 404 Not Found
# 416 Requested range not satisfiable
#
# Server Error
# 500 Internal Server Error
# 501 Not Implemented
# 503 Service Unavailable

# global variables
my $cgi;
my $json = new JSON;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;
my $rest;
my $user;
my $format = "application/json";

my $json_rpc = 0;
my $json_rpc_id = undef;
my $error_messages = { 400 => "Bad Request",
		       401 => "Unauthorized",
		       404 => "Not Found",
		       416 => "Request range not satisfiable",
		       500 => "Internal Server Error",
		       501 => "Not Implemented",
		       503 => "Service Unavailable",
		       -32602 => "Invalid params",
		       -32603 => "Internal error" };

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my $content = { 'name' => name(),
		    'url' => $cgi->url."/".name(),
		    'description' => "A project is a composition of samples, libraries and metagenomes being analyzed in a global context.",
		    'type' => 'object',
		    'documentation' => $Conf::html_url.'/api.html#'.name(),
		    'requests' => [ { 'name'        => "info",
				      'request'     => $cgi->url."/".name() ,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $cgi->url."/".name() ,				      
				      'description' => "Returns a set of data matching the query criteria.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "next"   => [ "uri", "link to the previous set or null if this is the first set" ],
							 "prev"   => [ "uri", "link to the next set or null if this is the last set" ],
							 "order"  => [ "string", "name of the attribute the returned data is ordered by" ],
							 "data"   => [ "list", [ "object", attributes() ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ],
									    'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				     ]
				 };

    return_data($content);
}


# name of the resource
sub name {
  return 'project';
}

# attributes of the resource
sub attributes {
  return { "id"              => [ 'string', 'unique object identifier' ],
	   "name"            => [ 'string', 'human readable identifier' ],
	   "libraries"       => [ 'list reference library', 'a list of references to the related library objects' ],
	   "samples"         => [ 'list reference sample', 'a list of references to the related sample objects' ],
	   "analyzed"        => [ 'list reference metagenome', 'a list of references to the related metagenome objects' ],
	   "description"     => [ 'string', 'a short, comprehensive description of the project' ],
	   "funding_source"  => [ 'string', 'the official name of the source of funding of this project' ],
	   "pi"              => [ 'string', 'the first and last name of the principal investigator of the project' ],
	   "metadata"        => [ 'hash', 'key value pairs describing metadata' ],
	   "created"         => [ 'date', 'time the object was first created' ],
	   "version"         => [ 'integer', 'version of the object' ],
	   "url"             => [ 'uri', 'resource location of this object instance' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my (undef, $id) = $rest->[0] =~ /^(mgp)?(\d+)$/;
  if (! $id && scalar(@$rest)) {
    return_data({ "ERROR" => "invalid id format: ".$rest->[0] }, 400);
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $project = $master->Project->init( { id => $id });
  unless (ref($project)) {
    return_data({ "ERROR" => "id $id does not exists" }, 404);
  }

  # check rights
  unless ($project->public || $user->has_right(undef, 'view', 'project', $id)) {
    return_data({ "ERROR" => "insufficient permissions to view this data" }, 401);
  }

  # prepare data
  my $data = prepare_data([ $project ]);
  $data = $data->[0];

  return_data($data)
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  # get database
  my $master = connect_to_datasource();

  my $projects = [];

  # get all user rights
  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();    
  my $staruser = ($user && $user->has_right(undef, 'view', 'project', '*')) ? 1 : 0;

  # check pagination
  my $limit = $cgi->param('limit') || 10;
  my $offset = $cgi->param('offset') || 0;
  my $order = $cgi->param('order') || "id";
  
  # get all items the user has access to
  if ($staruser) {
    $projects = $master->Project->get_objects( { $order => [ undef, "_id IS NOT NULL ORDER BY $order LIMIT $limit OFFSET $offset" ] } );
  } else {
    $projects = $master->Project->get_objects( { $order => [ undef, "public=1 AND _id IS NOT NULL ORDER BY $order LIMIT $limit OFFSET $offset" ] } );
    foreach my $key (keys %rights) {
      push(@$projects, $master->Project->init( { id => $key } ));
    }
  }

  # prepare data to the correct output format
  my $data = prepare_data($projects);

  # check for pagination
  $data = check_pagination($data);

  return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  my $objects = [];
  foreach my $project (@$data) {    
    my $obj  = {};
    $obj->{id}             = "mgp".$project->id;
    $obj->{name}           = $project->name;
    $obj->{pi}             = $project->pi;
    $obj->{version}        = 1;
    $obj->{url}            = $cgi->url.'/project/'.$obj->{id};
    $obj->{created}        = "";
    
    if ($cgi->param('verbosity')) {
      if ($cgi->param('verbosity') eq 'full') {
	my @jobs      = map { "mgm".$_ } @{ $project->all_metagenome_ids };
	my @colls     = @{ $project->collections };
	my @samples   = map { "mgs".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
	my @libraries = map { "mgl".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
	
	$obj->{analyzed}       = \@jobs;	
	$obj->{samples}        = \@samples;
	$obj->{libraries}      = \@libraries;
      }
      if (($cgi->param('verbosity') eq 'verbose') || ($cgi->param('verbosity') eq 'full')) {
	my $metadata  = $project->data();
	my $desc = $metadata->{project_description} || $metadata->{study_abstract} || " - ";
	my $fund = $metadata->{project_funding} || " - ";
	$obj->{metadata}       = $metadata;
	$obj->{description}    = $desc;
	$obj->{funding_source} = $fund;	
      } elsif ($cgi->param('verbosity') ne 'minimal') {
	return_data({ "ERROR" => "invalid value for option verbosity" }, 400);
      }
    }
    
    push(@$objects, $obj);      
  }

  return $objects;
}

###################################################
# generic functions - do not edit below this line #
###################################################

# get a connection to the datasource
sub connect_to_datasource {
  use WebServiceObject;

  my ($master, $error) = WebServiceObject::db_connect();
  if ($error) {
    return_data({ "ERROR" => "resource database offline" }, 503);
  } else {
    return $master;
  }
}

# check if pagination parameters are used
sub check_pagination {
  my ($data) = @_;

  if ($cgi->param('limit') || $cgi->param('order')) {
    my $limit = $cgi->param('limit') || 10;
    my $offset = $cgi->param('offset') || 0;
    my $order = $cgi->param('order') || "id";
    my $total_count = scalar(@$data);
    my $additional_params = "";
    my @params = $cgi->param;
    foreach my $param (@params) {
      next if ($param eq 'offset');
      $additional_params .= $param."=".$cgi->param($param)."&";
    }
    if (length($additional_params)) {
      chop $additional_params;
    }
    my $prev_offset = $offset - $limit;
    if ($prev_offset < 0) {
      $prev_offset = 0;
    }
    my $prev = $offset ? $cgi->url."/".name()."?$additional_params&offset=$prev_offset" : undef;
    my $next_offset = $offset + $limit;
    my $next = ($offset < $total_count) ? $cgi->url."/".name()."?$additional_params&offset=$next_offset" : undef;
    my $attributes = attributes();
    if (exists($attributes->{$order})) {
      $data = { "limit" => $limit,
		"offset" => $offset,
		"total_count" => $total_count,
		"order" => $order,
		"next" => $next,
		"prev" => $prev,
		"data" => $data };

    } else {
      return_data({ "ERROR" => "invalid sort order, there is no attribute $order" }, 400);
    }
  }
   
  return $data;
}

# method initially called from the api module
sub request {
  my ($params) = @_;

  $cgi = $params->{cgi};
  $rest = $params->{rest_parameters} || [];
  $user = $params->{user};
  my @parameters = $cgi->param;

  if ($params->{json_rpc}) {
    $json_rpc = $params->{json_rpc};
    if (exists($params->{json_rpc_id})) {
      $json_rpc_id = $params->{json_rpc_id};
    }
  }

  # check for parameters
  if (scalar(@$rest) == 0 && (scalar(@parameters) == 0 || (scalar(@parameters) == 1 && $parameters[0] eq 'keywords')) ) {
    info();
  }

  # check for id
  if (scalar(@$rest)) {
    instance();
  } else {
    query();
  }
}

# print the actual data output
sub return_data {
  my ($data, $error) = @_;

  # default status is OK
  my $status = 200;  
  
  # if the result is an empty array, status is 204
  if (ref($data) eq "ARRAY" && scalar(@$data) == 0) {
    $status = 204;
  }

  # if an error is passed, change the return format to text 
  # and change the status code to the error code passed
  if ($error) {
    $format = "application/json";
    $status = $error;
  }

  # check for remote procedure call
  if ($json_rpc) {
    
    # check to comply to Bob Standards
    unless (ref($data) eq 'ARRAY') {
      $data = [ $data ];
    }

    # only reply if this is not a notification
    #if (defined($json_rpc_id)) { 
      if ($error) {

	my $error_code = $status;
	if ($status == 400) {
	  $status = -32602;
	} elsif ($status == 500) {
	  $status = -32603;
	}

	# there was an error
	$data = { jsonrpc => "2.0",
		  error => { code => $error_code,
			     message => $error_messages->{$status},
			     data => $data },
		  id => $json_rpc_id };

      } else {
	
	# normal result
	$data = { jsonrpc => "2.0",
		  result => [$data],
		  id => $json_rpc_id };
      }

      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode($data);
      exit 0;
    #} else { exit; }
  } else {
    
    # check for JSONP
    if ($cgi->param('callback')) {
      if ($format ne "application/json") {
	$data = { 'data' => $data };
      }
      $format = "application/json";
      
      print $cgi->header(-type => $format,
			 -status => $status,
			 -Access_Control_Allow_Origin => '*' );
      print $cgi->param('callback')."(".$json->encode($data).");";
      exit 0;
    }  
    # normal return
    else {
      print $cgi->header(-type => $format,
			 -status => $status,
			 -Access_Control_Allow_Origin => '*' );
      if ($format eq 'application/json') {
	print $json->encode($data);
      } else {
	print $data;
      }
      exit 0;
    }
  }
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }

1;
