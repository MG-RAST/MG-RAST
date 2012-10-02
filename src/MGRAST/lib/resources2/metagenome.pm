package resources2::metagenome;

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
		    'description' => "A metagenome is an analyzed set sequences from a sample of some environment",
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
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ] ] ],
									    'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'created', 'return data objects ordered by creation date' ],
												 [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ],
												 [ 'sequence_type' , 'return data objects ordered by sequence type' ],
												 [ 'file_size' , 'return data objects ordered by file size' ],
												 [ 'version' , 'return data objects ordered by version' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns a standard subselection of metadata' ],
												     [ 'full', 'returns all connected metadata' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				  ]
		  };

    return_data($content);
}


# name of the resource
sub name {
  return 'metagenome';
}

# attributes of the resource
sub attributes {
  return { "id"              => [ 'string', 'unique object identifier' ],
	   "name"            => [ 'string', 'human readable identifier' ],
	   "sequence_type"   => [ 'string', 'sequencing type' ],
	   "file_size"       => [ 'integer', 'sequence file size in bytes' ],
	   "library"         => [ 'reference library', 'reference to the related library object' ],
	   "sample"          => [ 'reference sample', 'reference to the related sample object' ],
	   "primary_project" => [ 'reference project', 'reference to the primary project object' ],
	   "metadata"        => [ 'hash', 'key value pairs describing metadata' ],
	   "created"         => [ 'date', 'time the object was first created' ],
	   "version"         => [ 'integer', 'version of the object' ],
	   "url"             => [ 'uri', 'resource location of this object instance' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  if (! $id && scalar(@$rest)) {
    return_data("ERROR: invalid id format: ".$rest->[0], 400);
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $job = $master->Job->get_objects( { metagenome_id => $id });
  if (scalar(@$job)) {
    $job = $job->[0];
  } else {
    return_data("ERROR: id $id does not exists", 404);
  }

  # check rights
  unless ($job->public || $user->has_right(undef, 'view', 'metagenome', $job->metagenome_id)) {
    return_data("ERROR: insufficient permissions to view this data", 401);
  }

  # prepare data
  my $data = prepare_data([ $job ]);

  return_data($data)
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  # get database
  my $master = connect_to_datasource();

  my $jobs = [];

  # get all user rights
  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();    
  my $staruser = ($user && $user->has_right(undef, 'view', 'metagenome', '*')) ? 1 : 0;
  
  # get all items the user has access to
  if ($staruser) {
    $jobs = $master->Job->get_objects( { viewable => 1 } );
  } else {
    $jobs = $master->Job->get_public_jobs();
    foreach my $key (keys %rights) {
      push(@$jobs, $master->Job->get_objects( { metagenome_id => $key })->[0]);
    }
  }

  # prepare data to the correct output format
  my $data = prepare_data($jobs);

  # check for pagination
  $data = check_pagination($data);

  return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  my $jobdata = {};
  if ($cgi->param('verbosity') && $cgi->param('verbosity') ne 'minimal') {
    my $jids = [];
    @$jids = map { $_->{metagenome_id} } @$data;
    use MGRAST::Metadata;
    my $mddb = MGRAST::Metadata->new();
    $jobdata = $mddb->get_jobs_metadata_fast($jids, 1);
  }

  my $objects = [];
  foreach my $job (@$data) {
    my $obj  = {};	
    $obj->{id}       = "mgm".$job->{metagenome_id};
    $obj->{name}     = $job->{name};
    $obj->{url}      = $cgi->url.'/metagenome/'.$obj->{id};
    $obj->{created}  = $job->{created_on};
    
    if ($cgi->param('verbosity') && scalar(@$data) == 1) {
      if ($cgi->param('verbosity') eq 'full') {
	$obj->{metadata} = $jobdata->{$job->{metagenome_id}};
      }
      if ($cgi->param('verbosity') eq 'verbose' || $cgi->param('verbosity') eq 'full') {
	if ($jobdata->{$job->{metagenome_id}}) {
	  if ($jobdata->{$job->{metagenome_id}}->{project}) {
	    $obj->{project_name} = $jobdata->{$job->{metagenome_id}}->{project}->{name} || "";
	    if ($jobdata->{$job->{metagenome_id}}->{project}->{data}) {
	      
	      $obj->{PI} = ($jobdata->{$job->{metagenome_id}}->{project}->{data}->{PI_firstname} || "")." ".($jobdata->{$job->{metagenome_id}}->{project}->{data}->{PI_lastname} || "");
	    }
	  }
	  if ($jobdata->{$job->{metagenome_id}}->{sample} && $jobdata->{$job->{metagenome_id}}->{sample}->{data}) {
	    $obj->{country} = $jobdata->{$job->{metagenome_id}}->{sample}->{data}->{country} || "";
	    $obj->{biome} = $jobdata->{$job->{metagenome_id}}->{sample}->{data}->{biome} || "";
	    $obj->{location} = $jobdata->{$job->{metagenome_id}}->{sample}->{data}->{location} || "";
	  }
	}
	$obj->{sample}   = $job->{sample} ? [ "mgs".$job->sample->ID, $cgi->url."sample/mgs".$job->sample->ID ] : undef;
	$obj->{library}  = $job->{library} ? [ "mgl".$job->library->ID, $cgi->url."/library/mgl".$job->library->ID ] : undef;
      } elsif ($cgi->param('verbosity') ne 'minimal') {
	return_data("ERROR: invalid value for option verbosity", 400);
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
    return_data("ERROR: resource database offline", 503);
  } else {
    return $master;
  }
}

# check if pagination parameters are used
sub check_pagination {
  my ($data) = @_;

  if ($cgi->param('limit')) {
    my $limit = $cgi->param('limit');
    my $offset = $cgi->param('offset') || 0;
    my $order = $cgi->param('order') || "created";
    my $total_count = scalar(@$data);
    my $additional_params = "";
    my @params = $cgi->param;
    foreach my $param (@params) {
      next if ($param eq 'offset');
      $additional_params .= $param."=".$cgi->param($param)."&";
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
      if ($attributes->{$order}->[0] eq 'integer' || $attributes->{$order}->[0] eq 'float') {
	@$data = sort { $a->{$order} <=> $b->{$order} } @$data;
      } else {
	@$data = sort { $a->{$order} cmp $b->{$order} } @$data;
      }
      @$data = @$data[$offset..($offset + $limit)];
      $data = { "limit" => $limit,
		"offset" => $offset,
		"total_count" => $total_count,
		"order" => $order,
		"next" => $next,
		"prev" => $prev,
		"data" => $data };

    } else {
      return_data("ERROR: invalid sort order, there is not attribute $order", 400);
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
    $format = "text/plain";
    $status = $error;
  }

  # check for remote procedure call
  if ($json_rpc) {
    
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
		  result => $data,
		  id => $json_rpc_id };
      }

      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode($data);
      exit 0;
    #} else {
      #exit;
    #}
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
