package resources::abundance_profile;

use MGRAST::Analysis;
use WebServiceObject;
use Babel::lib::Babel;

use CGI;
use JSON;
use POSIX qw(strftime);

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "metagenomic abundance profile",
		  'parameters'  => { "id" => "string",
				     "type" => [ "organism", "function", "feature" ],
				     "source" => { "protein"  => [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ],
						   "ontology" => [ map {$_->[0]} @{$ach->get_ontology_sources} ],
						   "rna"      => [ 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources} ]
						 }
				   },
		  'defaults' => { "source" => "M5NR (organism), or Subsystems (function), or RefSeq (feature)",
				  "type"   => "organism"
				},
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

  if (scalar(@$rest) && $rest->[0] eq 'available_sources') {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($mgdb->get_sources);
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
    print "ERROR: abundance profile call requires at least an id parameter";
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

  # set params
  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }
  $params->{type}   = $cgi->param('type') ? $cgi->param('type') : 'organism';
  $params->{source} = $cgi->param('source') ? $cgi->param('source') :
    (($params->{type} eq 'organism') ? 'M5NR' : (($params->{type} eq 'function') ? 'Subsystems': 'RefSeq'));

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }
  $mgdb->set_jobs([$id]);

  # validate type / source
  my $all_srcs = {};
  if ($params->{type} eq 'organism') {
    $all_srcs = { M5NR => 1, M5RNA => 1 };
    map { $all_srcs->{$_} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_} = 1 } @{$mgdb->ach->get_rna_sources};
  } elsif ($params->{type} eq 'function') {
    map { $all_srcs->{$_} = 1 } @{$mgdb->ach->get_ontology_sources};
  } elsif ($params->{type} eq 'feature') {
    map { $all_srcs->{$_} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_} = 1 } @{$mgdb->ach->get_rna_sources};
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for profile call: ".$params->{type}." - valid types are ['function', 'organism', 'feature']";
    exit 0;
  }
  unless (exists $all_srcs->{ $params->{source} }) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid source for profile call of type ".$params->{type}.": ".$params->{source}." - valid types are [".join(", ", keys %$all_srcs)."]";
    exit 0;
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

  my $data = { "id"                  => "mgm".$id,
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

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;

}

sub toFloat {
  my ($x) = @_;
  return $x * 1.0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
