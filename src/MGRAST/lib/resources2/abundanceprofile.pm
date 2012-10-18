package resources2::abundanceprofile;

use Conf;
use CGI;
use JSON;

use MGRAST::Analysis;
use Babel::lib::Babel;

use POSIX qw(strftime);

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
  my $ach = new Babel::lib::Babel;
  my $sources = [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ];
  push(@$sources, map {$_->[0]} @{$ach->get_ontology_sources});
  push(@$sources, 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources});

  my $content = { 'name' => name(),
		  'url' => $cgi->url."/".name(),
		  'description' => "A profile in biom format that contains abundance counts",
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
				    'description' => "Returns a single data object.",
				    'method'      => "GET" ,
				    'type'        => "synchronous" ,  
				    'attributes'  => attributes(),
				    'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												   [ 'verbose', 'returns all metadata' ],
												   [ 'full', 'returns all references' ] ] ],
									  'type' => [ 'cv', [ ['organism', 'return organism data'],
											      ['function', 'return functional data'],
											      ['feature', 'return feature data'] ] ],
									  'source' => [ 'cv', [ [ "M5RNA", "comprehensive RNA database, type organism and feature only" ],
												[  "RDP", "RNA database, type organism and feature only" ],
												[ "Greengenes", "RNA database, type organism and feature only" ],
												[ "LSU", "RNA database, type organism and feature only" ],
												[ "SSU", "RNA database, type organism and feature only" ],
												[ "M5NR", "comprehensive protein database, type organism and feature only" ],
												[ "SwissProt", "protein database, type organism and feature only" ],
												[ "GenBank", "protein database, type organism and feature only" ],
												[ "IMG", "protein database, type organism and feature only" ],
												[ "SEED", "protein database, type organism and feature only" ],
												[ "TrEMBL", "protein database, type organism and feature only" ],
												[ "RefSeq", "protein database, type organism and feature only" ],
												[ "PATRIC", "protein database, type organism and feature only" ],
												[ "eggNOG", "protein database, type organism and feature only" ],
												[ "KEGG", "protein database, type organism and feature only" ],												
												[ "NOG", "ontology database, type function only" ],
												[ "COG", "ontology database, type function only" ],
												[ "KO", "ontology database, type function only" ],
												[ "GO", "ontology database, type function only" ],
												[ "Subsystems", "ontology database, type function only" ] ] ],
									},
						       'required'    => { "id" => [ "string", "unique object identifier" ] },
						       'body'        => {} } },
				]
		};
  
  return_data($content);
}


# name of the resource
sub name {
  return 'abundanceprofile';
}

# attributes of the resource
sub attributes {
  return { "id"                  => [ 'string', 'unique object identifier' ],
	   "format"              => [ 'string', 'format specification name' ],
	   "format_url"          => [ 'string', 'url to the format specification' ],
	   "type"                => [ 'string', 'type of the data in the return table (taxon, function or gene)' ],
	   "generated_by"        => [ 'string', 'identifier of the data generator' ],
	   "date"                => [ 'date', 'time the output data was generated' ],
	   "matrix_type"         => [ 'string', 'type of the data encoding matrix (dense or sparse)' ],
	   "matrix_element_type" => [ 'string', 'data type of the elements in the return matrix' ],
	   "shape"               => [ 'list', [ 'integer', 'list of the dimension sizes of the return matrix' ] ],
	   "rows"                => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
							      'metadata' => [ 'hash', 'key value pairs describing metadata' ] }, "rows object" ] ] ],
	   "columns"             => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
							      'metadata' => [ 'hash', 'list of metadata, contains the metagenome' ] }, "columns object" ] ] ],
	   "data"                => [ 'list', [ 'list', [ 'float', 'the matrix values' ] ] ] };
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
  my $job = $master->Job->init( { metagenome_id => $id });
  unless (ref($job)) {
    return_data({ "ERROR" => "id $id does not exists" }, 404);
  }

  # check rights
  unless ($job->public || $user->has_right(undef, 'view', 'metagenome', $job->metagenome_id)) {
    return_data({ "ERROR" => "insufficient permissions to view this data" }, 401);
  }

  # prepare data
  my $data = prepare_data($job);

  return_data($data)
}

# reformat the data into the requested output format
sub prepare_data {
  my ($data) = @_;

  # get database
  my $master = connect_to_datasource();

  my $params = {};
  $params->{type}   = $cgi->param('type') ? $cgi->param('type') : 'organism';
  $params->{source} = $cgi->param('source') ? $cgi->param('source') : (($params->{type} eq 'organism') ? 'M5NR' : (($params->{type} eq 'function') ? 'Subsystems': 'RefSeq'));
  
  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
    return_data({ "ERROR" => "could not connect to analysis database" }, 500);
  }
  my $id = $data->{metagenome_id};
  $mgdb->set_jobs([$id]);
  
  # validate type / source
  my $all_srcs = {};
  if ($params->{type} eq 'organism') {
    $all_srcs = { M5NR => 1, M5RNA => 1 };
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
  } elsif ($params->{type} eq 'function') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_ontology_sources};
  } elsif ($params->{type} eq 'feature') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
  } else {
    return_data({ "ERROR" => "Invalid type for profile call: ".$params->{type}." - valid types are ['function', 'organism', 'feature']" }, 400);
  }
  unless (exists $all_srcs->{ $params->{source} }) {
    return_data({ "ERROR" => "Invalid source for profile call of type ".$params->{type}.": ".$params->{source}." - valid types are [".join(", ", keys %$all_srcs)."]" }, 400);
  }

  my $values  = [];
  my $rows    = [];
  my $ttype   = '';
  my $columns = [ { id => 'abundance', metadata => { metagenome => 'mgm'.$id } },
		  { id => 'e-value', metadata => { metagenome => 'mgm'.$id } },
		  { id => 'percent identity', metadata => { metagenome => 'mgm'.$id } },
		  { id => 'alignment length', metadata => { metagenome => 'mgm'.$id } }
		];

  # get data
  if ($params->{type} eq 'organism') {
    $ttype = 'Taxon';
    my $strain2tax = $mgdb->ach->map_organism_tax_id();
    my ($md5_abund, $result) = $mgdb->get_organisms_for_sources([$params->{source}]);
    # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
    foreach my $row (@$result) {
      next unless (exists $strain2tax->{$row->[9]});
      my $tax_str = [ "k__".$row->[2], "p__".$row->[3], "c__".$row->[4], "o__".$row->[5], "f__".$row->[6], "g__".$row->[7], "s__".$row->[9] ];
      push(@$rows, { "id" => $strain2tax->{$row->[9]}, "metadata" => { "taxonomy" => $tax_str }  });
      push(@$values, [ toFloat($row->[10]), toFloat($row->[12]), toFloat($row->[14]), toFloat($row->[16]) ]);
    }
  }
  elsif ($params->{type} eq 'function') {
    $ttype = 'Function';
    my $function2ont = $mgdb->ach->get_all_ontology4source_hash($params->{source});
    my ($md5_abund, $result) = $mgdb->get_ontology_for_source($params->{source});
    # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
    foreach my $row (@$result) {
      next unless (exists $function2ont->{$row->[1]});
      my $ont_str = [ map { defined($_) ? $_ : '-' } @{$function2ont->{$row->[1]}} ];
      push(@$rows, { "id" => $row->[1], "metadata" => { "ontology" => $ont_str } });
      push(@$values, [ toFloat($row->[3]), toFloat($row->[5]), toFloat($row->[7]), toFloat($row->[9]) ]);
    }
  }
  elsif ($params->{type} eq 'feature') {
    $ttype = 'Gene';
    my $md52id = {};
    my $result = $mgdb->get_md5_data(undef, undef, undef, undef, 1);
    # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length
    my @md5s = map { $_->[1] } @$result;
    map { push @{$md52id->{$_->[1]}}, $_->[0] } @{ $mgdb->ach->md5s2ids4source(\@md5s, $params->{source}) };
    foreach my $row (@$result) {
      next unless (exists $md52id->{$row->[1]});
      push(@$rows, { "id" => $row->[1], "metadata" => { $params->{source}." ID" => $md52id->{$row->[1]} } });
      push(@$values, [ toFloat($row->[2]), toFloat($row->[3]), toFloat($row->[5]), toFloat($row->[7]) ]);
    }
  }
  
  my $obj  = { "id"                  => "mgm".$id,
	       "format"              => "Biological Observation Matrix 1.0",
	       "format_url"          => "http://biom-format.org",
	       "type"                => $ttype." table",
	       "generated_by"        => "MG-RAST revision ".$Conf::server_version,
	       "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
	       "matrix_type"         => "dense",
	       "matrix_element_type" => "float",
	       "shape"               => [ scalar(@$values), 4 ],
	       "rows"                => $rows,
	       "columns"             => $columns,
	       "data"                => $values };
    
  return $obj;
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

# helper method
sub toFloat {
  my ($x) = @_;
  return $x * 1.0;
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }

1;
