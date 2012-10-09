package resources2::sequences;

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
		    'description' => "A set of genomic sequences of a metagenome annotated by a specified source",
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
				    { 'name'        => "md5",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => { "sequence_type" => [ "cv", [ [ "dna", "return DNA sequences" ],
													 [ "protein", "return protein sequences" ] ] ] },
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => { "md5" => [ "list string", "list of md5 identifiers" ] } } },
				    { 'name'        => "annotation",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => { "data_type" => [ "cv", [ [ "organism", "return organism data" ],
												     [ "function", "return function data" ],
												     [ "ontology", "return ontology data" ] ] ],
									    "sequence_type" => [ "cv", [ [ "dna", "return DNA sequences" ],
													 [ "protein", "return protein sequences" ] ] ],
									    "organism" => [ "string", "organism name" ],
									    "source" => [ "cv", [ [ "RDP", "" ],
												  [ "Greengenes", "" ],
												  [ "LSU", "" ],
												  [ "SSU", "" ],
												  [ "NOG", "" ],
												  [ "COG", "" ],
												  [ "KO", "" ],
												  [ "GO", "" ],
												  [ "Subsystems", "" ],
												  [ "SwissProt", "" ],
												  [ "GenBank", "" ],
												  [ "IMG", "" ],
												  [ "SEED", "" ],
												  [ "TrEMBL", "" ],
												  [ "RefSeq", "" ],
												  [ "PATRIC", "" ],
												  [ "eggNOG", "" ],
												  [ "KEGG", "" ] ] ] },
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => { "function" => [ "list string", "list of functions to filter by" ] } } }
				  ]
		  };

    return_data($content);
}


# name of the resource
sub name {
  return 'sequences';
}

# attributes of the resource
sub attributes {
  return { "id"              => [ 'string', 'unique object identifier' ],
	   "data"            => [ 'hash list string', 'a hash of data_type to list of sequences' ],
	   "version"         => [ 'integer', 'version of the object' ],
	   "url"             => [ 'uri', 'resource location of this object instance' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  if (! $id && scalar(@$rest)) {
    return_data({ "ERROR" => "invalid id format: ".$rest->[0] }, 400);
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $job = $master->Job->init( {metagenome_id => $id} );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
      my $data = prepare_data($job);
      return_data([$data]);
    } else {
      return_data({ "ERROR" => "insufficient permissions to view this data" }, 401);
    }
  } else {
    return_data({ "ERROR" => "id $id does not exists" }, 404);
  }
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
  }
  my $seq = 'dna';
  if ($cgi->param('seq')) {
    $seq = $cgi->param('seq');
  }
  my $source;
  if ($cgi->param('source')) {
    @$source = $cgi->param('source');
  }
  my $anns;
  if ($cgi->param('organism')) {
    @$anns = $cgi->param('organism');
  }
  if ($cgi->param('function')) {
    @$anns = $cgi->param('function');
  }
  my $md5s;
  if ($cgi->param('md5')) {
    @$md5s = $cgi->param('md5');
  }
  
  my $master = connect_to_datasource();
  use MGRAST::Analysis;
  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
    return_data({ "ERROR" => "resource database offline" }, 503);
  }
  $mgdb->set_jobs([$data->{metagenome_id}]);
  
  my $content;
  if (ref $md5s) {
    $content = $mgdb->sequences_for_md5s($data->{metagenome_id}, $seq, $md5s);
  } else {
    $content = $mgdb->sequences_for_annotation($data->{metagenome_id}, $seq, $type, $source, $anns);
  }

  my $object = { id => "mgm".$data->{metagenome_id},
		 data => $content,
		 url => $cgi->url.'/sequences/'.$data->{metagenome_id},
		 version => 1 };
  
  return $object;
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
      if ($attributes->{$order}->[0] eq 'integer' || $attributes->{$order}->[0] eq 'float') {
	@$data = sort { $a->{$order} <=> $b->{$order} } @$data;
      } else {
	@$data = sort { $a->{$order} cmp $b->{$order} } @$data;
      }
      @$data = @$data[$offset..($offset + $limit - 1)];
      $data = { "limit" => $limit,
		"offset" => $offset,
		"total_count" => $total_count,
		"order" => $order,
		"next" => $next,
		"prev" => $prev,
		"data" => $data };

    } else {
      return_data({ "ERROR" => "invalid sort order, there is not attribute $order" }, 400);
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
