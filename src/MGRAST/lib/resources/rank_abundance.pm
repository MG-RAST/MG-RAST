package resources::rank_abundance;

use MGRAST::MetagenomeAnalysis2;
use WebServiceObject;

use CGI;
use JSON;
use POSIX qw(strftime);

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "metagenomic rank abundance",
		  'parameters'  => { "id" => "string",
				     "limit" => "int",
				     "term" => "string",
				     "type" => [ "organism", "function" ],
				     "source" => { "protein" => [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ],
						   "rna"     => [ 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources} ]
						 }
				   },
		  'defaults' => { "limit" => 10,
				  "term" => [],
				  "type" => 'organism',
				  "source" => 'M5NR'
				}
		  'return_type' => "application/json" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};
  my $user = $params->{user};
  my ($master, $error) = WebServiceObject::db_connect();
  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }

  unless (scalar(@$rest) >= 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: rank abundance call requires at least an id parameter";
    exit 0;
  }
  
  my $id = shift @$rest;  
  (undef, $id) = $id =~ /^(mgm)?(\d+\.\d+)$/;
  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for profile call";
    exit 0;
  }
  
  my $job = $master->Job->init( {metagenome_id => $id} );
  unless ($job && ref($job)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Unknown id in profile call: ".$rest->[0];
    exit 0;
  }
  
  unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient permissions for profile call for id: ".$rest->[0];
    exit 0;
  }

  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }
  if ($cgi->param('limit'))  { $params->{limit}  = $cgi->param('limit'); }
  if ($cgi->param('type'))   { $params->{type}   = $cgi->param('type'); }
  if ($cgi->param('source')) { $params->{source} = $cgi->param('source'); }

  my $limit  = ($params->{limit})  ? $params->{limit}  : 10;
  my $type   = ($params->{type})   ? $params->{type}   : 'organism';
  my $source = ($params->{source}) ? $params->{source} : 'M5NR';
  my @term   = $cgi->param('term') || ();  

  my $mgdb = MGRAST::MetagenomeAnalysis2->new( $master->db_handle );
  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }
  $mgdb->set_jobs([$id]);

  if (scalar(@$rest) && $rest->[0] eq 'available_sources') {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($mgdb->get_sources);
    exit 0;
  }

  my $data;
  if ($type eq 'organism') {
    if 
    
    my $data = $mgdb->get_abundance_for_set($set, $type, $sources);
    # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    
    my $values = [];
    my $tax = [];
    foreach my $row (@$result) {
      if (! $strain2tax->{$row->[9]}) {
	next;
      }
      my $tax_str = [ "k__".$row->[2], "p__".$row->[3], "c__".$row->[4], "o__".$row->[5], "f__".$row->[6], "g__".$row->[7], "s__".$row->[9] ];
      push(@$tax, { "id" => $strain2tax->{$row->[9]}, "metadata" => { "taxonomy" => $tax_str }  });
      push(@$values, [ int($row->[10]) ]);
    }
    
    $data = { "id"                  => "mgm".$id,
	      "format"              => "Biological Observation Matrix 0.9.1",
	      "format_url"          => "http://biom-format.org",
	      "type"                => "Taxon table",
	      "generated_by"        => "MG-RAST revision ".$FIG_Config::server_version,
	      "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
	      "matrix_type"         => "dense",
	      "matrix_element_type" => "int",
	      "shape"               => [ scalar(@$values), 1 ],
	      "rows"                => $tax,
	      "columns"             => [ { "id" => $id, "metadata" => undef } ],
	      "data"                => $values };

  } elsif ($type eq 'function') {

    my $function2ont = $ach->get_all_ontology4source_hash($source);
    my ($md5_abund, $result) = $mgdb->get_ontology_for_source($source);
    # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    
    my $values = [];
    my $numrows = scalar(@$result);
    my $ont = [];
    foreach my $row (@$result) {
      next unless ($function2ont->{$row->[1]});
      my $ont_str = [ map { defined($_) ? $_ : '-' } @{$function2ont->{$row->[1]}} ];
      push(@$ont, { "id" => $row->[1], "metadata" =>  { "ontology" => $ont_str }  });
      push(@$values, [ int($row->[3]) ]);
    }
    
    $data = { "id"                  => "mgm".$id,
	      "format"              => "Biological Observation Matrix 0.9.1",
	      "format_url"          => "http://biom-format.org",
	      "type"                => "Function table",
	      "generated_by"        => "MG-RAST revision ".$FIG_Config::server_version,
	      "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
	      "matrix_type"         => "dense",
	      "matrix_element_type" => "int",
	      "shape"               => [ scalar(@$values), 1 ],
	      "rows"                => $ont,
	      "columns"             => [ { "id" => $id, "metadata" => undef } ],
	      "data"                => $values };

  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for profile call: ".$type." - valid types are [ 'organism', 'function' ]";
    exit 0;
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;

}

sub TO_JSON { return { %{ shift() } }; }

1;
