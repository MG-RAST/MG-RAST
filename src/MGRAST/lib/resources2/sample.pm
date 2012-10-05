package resources2::sample;

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
		    'description' => "A metagenomic sample from some environment.",
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
				      'parameters'  => { 'options'     => { 'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'created', 'return data objects ordered by creation date' ],
												 [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ],												 [ 'version' , 'return data objects ordered by version' ] ] ] },
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
  return 'sample';
}

# attributes of the resource
sub attributes {
  return { "id"              => [ 'string', 'unique object identifier' ],
	   "name"            => [ 'string', 'human readable identifier' ],
	   "libraries"       => [ 'list reference library', 'a list of references to the related library objects' ],
	   "metagenomes"     => [ 'list reference metagenome', 'a list of references to the related metagenome objects' ],
	   "project"         => [ 'reference project', 'reference to the project of this sample' ],
	   "env_package"     => [ 'object', 'environmental package' ],
	   "metadata"        => [ 'hash', 'key value pairs describing metadata' ],
	   "created"         => [ 'date', 'time the object was first created' ],
	   "version"         => [ 'integer', 'version of the object' ],
	   "url"             => [ 'uri', 'resource location of this object instance' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my (undef, $id) = $rest->[0] =~ /^(mgs)?(\d+)$/;
  if (! $id && scalar(@$rest)) {
    return_data({ "ERROR" => "invalid id format: ".$rest->[0] }, 400);
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $sample = $master->MetaDataCollection->init( { ID => $id } );
  unless (ref($sample)) {
    return_data({ "ERROR" => "id $id does not exists" }, 404);
  }

  # prepare data
  my $data = prepare_data([ $sample ]);

  return_data($data->[0])
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  # get database
  my $master = connect_to_datasource();
  my $dbh = $master->db_handle();

  my $samples_hash = {};
  my $sample_map = {};
  my $job_sam_map = {};
  my $job_sample = $dbh->selectall_arrayref("SELECT sample, metagenome_id, public FROM Job");
  map { $job_sam_map->{$_->[0]} = 1 }  @$job_sample;
  map { $sample_map->{$_->[0]} = { ID => $_->[1], name => $_->[2], entry_date => $_->[3] } } @{$dbh->selectall_arrayref("SELECT _id, ID, name, entry_date FROM MetaDataCollection WHERE type='sample'")};
  
  # add libraries with job: public or rights
  map { $samples_hash->{"mgl".$sample_map->{$_->[0]}} = $sample_map->{$_->[0]} } grep { ($_->[2] == 1) || exists($rights{$_->[1]}) || exists($rights{'*'}) } @$job_sample;
  # add libraries with no job
  map { $samples_hash->{"mgl".$sample_map->{$_}} = $sample_map->{$_} } grep { ! exists $job_sam_map->{$_} } keys %$library_map;
  my $samples = [];
  @$samples = map { $samples_hash->{$_} } keys(%$samples_hash);

  # prepare data to the correct output format
  my $data = prepare_data($samples);

  # check for pagination
  $data = check_pagination($data);

  return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  use MGRAST::Metadata;
  my $mddb  = MGRAST::Metadata->new();

  my $objects = [];
  foreach my $sample (@$data) {    
    my $obj   = {};
    $obj->{id}       = "mgs".$sample->{ID};
    $obj->{name}     = $sample->{name};
    $obj->{url}      = $cgi->url.'/sample/'.$obj->{id};
    $obj->{version}  = 1;
    $obj->{created}  = $sample->{entry_date};
    
    if ($cgi->param('verbosity')) {
      if ($cgi->param('verbosity') eq 'full') {
    my $mdata = $sample->data();
	my $name  = $sample->name ? $sample->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : (exists($mdata->{sample_id}) ? $mdata->{sample_id} : ''));
	my $proj  = $sample->project;
	my $epack = $sample->children('ep');
	my @jobs  = grep { $_->{public} || exists($rights{$_->{metagenome_id}}) || exists($rights{'*'}) } @{ $sample->jobs };
	my $env_package = undef;
	if (@$epack) {
	  my $edata = $epack->[0]->data;
	  $edata->{sample_name} = $name;
	  $edata = $cgi->param('template') ? $mddb->add_template_to_data($epack->[0]->ep_type, $edata) : $edata;
	  $env_package = { id       => "mge".$epack->[0]->ID,
			   name     => $epack->[0]->name || "mge".$epack->[0]->ID,
			   type     => $epack->[0]->ep_type,
			   created  => $epack->[0]->entry_date,
			   metadata => $edata };
	}
	$obj->{project}  = $proj ? "mgp".$proj->{id} : undef;
	$obj->{env_package} = $env_package;
	@{ $obj->{libraries} } = map { "mgl".$_->{ID} } @{ $sample->children('library') };
	@{ $obj->{metagenomes} } = map { "mgm".$_->{metagenome_id} } @jobs;
      }
      if (($cgi->param('verbosity') eq 'verbose') || ($cgi->param('verbosity') eq 'full')) {
    my $mdata = $sample->data();
	if ($cgi->param('template')) {
	  $mdata = $mddb->add_template_to_data('sample', $mdata);
	}
	$obj->{metadata} = $mdata;
	
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
    
    # only reply if this is not a notification
    if (defined($json_rpc_id)) { 
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
    }
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
