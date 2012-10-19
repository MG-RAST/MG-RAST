package resources2::library;

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
		    'description' => "A library of metagenomic samples from some environment",
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
							 "data"   => [ "list", [ "object", [ attributes(), "list of the library objects" ] ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ] ] ],
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
  return 'library';
}

# attributes of the resource
sub attributes {
  return { "id"              => [ 'string', 'unique object identifier' ],
	   "name"            => [ 'string', 'human readable identifier' ],
	   "sequencesets"    => [ 'list', [ 'reference sequenceset', 'a list of references to the related sequence sets' ] ],
	   "metagenome"      => [ 'reference metagenome', 'reference to the related metagenome object' ],
	   "sample"          => [ 'reference sample', 'reference to the related sample object' ],
	   "project"         => [ 'reference project', 'reference to the project object' ],
	   "metadata"        => [ 'hash', 'key value pairs describing metadata' ],
	   "created"         => [ 'date', 'time the object was first created' ],
	   "version"         => [ 'integer', 'version of the object' ],
	   "url"             => [ 'uri', 'resource location of this object instance' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my (undef, $id) = $rest->[0] =~ /^(mgl)?(\d+)$/;
  if (! $id && scalar(@$rest)) {
    return_data({ "ERROR" => "invalid id format: ".$rest->[0] }, 400);
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $library = $master->MetaDataCollection->init( { ID => $id } );
  unless (ref($library)) {
    return_data({ "ERROR" => "id $id does not exists" }, 404);
  }

  # prepare data
  my $data = prepare_data([ $library ]);
  $data = $data->[0];

  return_data($data)
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  # get database
  my $master = connect_to_datasource();
  my $dbh = $master->db_handle();
  
  my $libraries_hash = {};
  my $library_map = {};
  my $job_lib_map = {};
  my $job_library = $dbh->selectall_arrayref("SELECT library, metagenome_id, public FROM Job");
  map { $job_lib_map->{$_->[0]} = 1 }  @$job_library;
  map { $library_map->{$_->[0]} = { id => $_->[1], name => $_->[2], entry_date => $_->[3] } } @{$dbh->selectall_arrayref("SELECT _id, ID, name, entry_date FROM MetaDataCollection WHERE type='library'")};
  
  # add libraries with job: public or rights
  map { $libraries_hash->{"mgl".$library_map->{$_->[0]}} = $library_map->{$_->[0]} } grep { ($_->[2] == 1) || exists($rights{$_->[1]}) || exists($rights{'*'}) } @$job_library;
  # add libraries with no job
  map { $libraries_hash->{"mgl".$library_map->{$_}} = $library_map->{$_} } grep { ! exists $job_lib_map->{$_} } keys %$library_map;
  my $libraries = [];
  @$libraries = map { $libraries_hash->{$_} } keys(%$libraries_hash);

  # check limit
  my $limit = $cgi->param('limit') || 10;
  my $offset = $cgi->param('offset') || 0;
  my $order = $cgi->param('order') || "id";
  @$libraries = sort { $a->{$order} cmp $b->{$order} } @$libraries;
  my $total = scalar(@$libraries);
  @$libraries = @$libraries[$offset..($offset+$limit-1)];

  # prepare data to the correct output format
  my $data = prepare_data($libraries);

  # check for pagination
  $data = check_pagination($data, $total);

  return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  my $mddb;
  my $master = connect_to_datasource();
  if ($cgi->param('verbosity') && $cgi->param('verbosity') ne 'minimal') {
    use MGRAST::Metadata;
    my $mddb = MGRAST::Metadata->new();
  }
  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();

  my $objects = [];
  foreach my $library (@$data) {
    if ($library->{ID}) { $library->{id} = $library->{ID}; }
    my $obj  = {};
    $obj->{id}       = "mgl".$library->{id};
    $obj->{name}     = $library->{name};
    $obj->{url}      = $cgi->url.'/library/'.$obj->{id};
    $obj->{version}  = 1;
    $obj->{created}  = $library->{entry_date};
    
    if ($cgi->param('verbosity')) {
      if ($cgi->param('verbosity') ne 'minimal' && ref($library) ne 'JobDB::MetaDataCollection') {
	$library =  $master->MetaDataCollection->init( { ID => $library->{id} } );
      }
      if ($cgi->param('verbosity') eq 'full') {
	my $proj   = $library->project;
	my @jobs   = grep { $_->public || exists($rights{$_->metagenome_id}) || exists($rights{'*'}) } @{ $library->jobs };
	my $libjob = (@jobs > 0) ? $jobs[0] : undef;
	my $sample = ref($library->parent) ? $library->parent : undef;
	$obj->{project}  = $proj ? "mgp".$proj->{id} : undef;
	$obj->{sample}   = $sample ? "mgs".$sample->{ID} : undef;
	$obj->{reads}    = $libjob ? "mgm".$libjob->metagenome_id : undef;
	$obj->{metagenome} = $libjob ? "mgm".$libjob->metagenome_id : undef;
	$obj->{sequence_sets} = $libjob ? get_sequence_sets($libjob) : [];

      }
      if ($cgi->param('verbosity') eq 'verbose' || $cgi->param('verbosity') eq 'full') {
	my $mdata  = $library->data();
	my $name   = $library->name ? $library->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : '');
	if ($cgi->param('template')) {
	  $mdata = $mddb->add_template_to_data($library->lib_type, $mdata);
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
  my ($data, $total) = @_;

  if ($total) {
    my $limit = $cgi->param('limit') || 10;
    my $offset = $cgi->param('offset') || 0;
    my $order = $cgi->param('order') || "id";
    my $total_count = $total || scalar(@$data);
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
			     data => $data->[0] },
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

sub get_sequence_sets {
  my ($job) = @_;
  
  my $mgid = $job->metagenome_id;
  my $rdir = $job->download_dir;
  my $adir = $job->analysis_dir;
  my $stages = [];
  if (opendir(my $dh, $rdir)) {
    my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
    closedir $dh;
    my $fnum = 1;
    foreach my $rf (@rawfiles) {
      my ($jid, $ftype) = $rf =~ /^(\d+)\.(fna|fastq)(\.gz)?$/;
      push(@$stages, { id => "mgm".$mgid."-050-".$fnum,
		       stage_id => "050",
		       stage_name => "upload",
		       stage_type => $ftype,
		       file_name => $rf });
      $fnum += 1;
    }
  }
  if (opendir(my $dh, $adir)) {
    my @stagefiles = sort grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
    closedir $dh;
    my $stagehash = {};
    foreach my $sf (@stagefiles) {
      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
      next unless ($stageid && $stagename && $stageresult);
      if (exists($stagehash->{$stageid})) {
	$stagehash->{$stageid}++;
      } else {
	$stagehash->{$stageid} = 1;
      }
      push(@$stages, { id => "mgm".$mgid."-".$stageid."-".$stagehash->{$stageid},
		       stage_id => $stageid,
		       stage_name => $stagename,
		       stage_type => $stageresult,
		       file_name => $sf });
    }
  }
  return $stages;
}


# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }

1;
