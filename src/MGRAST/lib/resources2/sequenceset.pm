package resources::sequenceset;

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
		    'description' => "A set / subset of genomic sequences of a metagenome from a specific stage in its analysis",
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
				    { 'name'        => "instance",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a single sequence file.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => {} } },
				    { 'name'        => "setlist",
				      'request'     => $cgi->url."/".name()."/{ID}",
				      'description' => "Returns a list of sets for the given id.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => attributes(),
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => {} } },
				  ]
		  };

    return_data($content);
}


# name of the resource
sub name {
  return 'sequenceset';
}

# attributes of the resource
sub attributes {
  return { "data" => [ 'file', 'requested sequence file' ] };
}

# the resource is called with an id parameter
sub instance {
  # check id format
  my ($pref, $mgid, $stageid, $stagenum) = $rest->[0] =~ /^(mgm)?([\d\.]+)-(\d+)-(\d+)$/;
  if (! $mgid && scalar(@$rest)) {
    ($pref, $mgid) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
    if (! $mgid) {
      return_data("ERROR: invalid id format: ".$rest->[0], 400);
    } else {
      setlist($mgid);
    }
  }

  # get database
  my $master = connect_to_datasource();
  
  # get data
  my $job = $master->Job->init( { metagenome_id => $mgid } );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
      my $filedir  = '';
      my $filename = '';
      if ($stageid eq "050") {
	$filedir = $job->download_dir;
	if (opendir(my $dh, $filedir)) {
	  my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$filedir/$_" } readdir($dh);
	  closedir $dh;
	  $filename = $rawfiles[$stagenum - 1];
	} else {
	  return_data("ERROR: could open job directory", 404);
	}
      } else {
	$filedir = $job->analysis_dir;
	if (opendir(my $dh, $filedir)) {
	  my @stagefiles = sort grep { /^$stageid.*(fna|faa)(\.gz)?$/ && -f "$filedir/$_" } readdir($dh);
	  closedir $dh;
	  $filename = $stagefiles[$stagenum - 1];
	}
      }
      
      unless ("$filedir/$filename" && (-s "$filedir/$filename")) {
	return_data("ERROR: could not access analysis directory", 404);
      }
      if (open(FH, "<$filedir/$filename")) {
	print "Content-Type:application/x-download\n";  
	print "Access-Control-Allow-Origin: *\n";
	print "Content-Length: " . (stat("$filedir/$filename"))[7] . "\n";
	print "Content-Disposition:attachment;filename=$filename\n\n";
	while (<FH>) {
	  print $_;
	}
	close FH;
	exit 0;
      } else {
	return_data("ERROR: could not access requested file", 404);
      }
    } else {
      return_data("ERROR: insufficient permissions to view this data", 401);
    }
  } else {
    return_data("ERROR: id $id does not exists", 404);
  }
}

sub setlist {
  my ($mgid) = @_;

  # get database
  my $master = connect_to_datasource();

  my $job = $master->Job->init( { metagenome_id => $mgid } );
  if ($job && ref($job)) {
    unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
      return_data("ERROR: insufficient permissions to view this data", 401);
    }
  } else {
    return_data("ERROR: id $id does not exists", 404);
  }

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
  } else {
    return_data("ERROR: job directory could not be opened", 404);
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
  } else {
    return_data("ERROR: job directory could not be opened", 404);
  }
  if (@$stages > 0) {
    return_data($stages);
  } else {
    return_data("ERROR: no stagefiles found", 404);
  }
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
