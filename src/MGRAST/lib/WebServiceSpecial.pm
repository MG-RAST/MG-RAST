package WebServiceSpecial;

use strict;
use warnings;
use CGI;
use JSON;
use Data::Dumper;

use POSIX qw(strftime);

use Babel::lib::Babel;
use MGRAST::Analysis;

sub cases {
  return { 'sequences' => 1,
	   'annotation' => 1,
	   'abundance_profile' => 1,
	   'profile' => 1,
	   'reads' => 1,
	   'matrix' => 1,
	   'stats' => 1,
	   'subset' => 1,
	   'query' => 1,
	   'metadata' => 1,
	   'pipeline_info' => 1,
	   'user_inbox' => 1,
	   'reference_genomes' => 1,
	   'available_resources' => 1,
	   'widgets' => 1,

	   'remote_pipeline_result' => 1,
	 };
}

sub writable {
  return { 'remote_pipeline_result' => 1 };
}

1;

sub remote_pipeline_result {
  my ($body, $master, $user) = @_;

  my $cgi = new CGI;

  if ($user && $user->login eq 'mobedac') {
    if ($body->{analysis_system} && $body->{libraries} && ref($body->{libraries}) eq 'ARRAY' && scalar (@{$body->{libraries}})) {
      my $infile = $body->{analysis_system}."_".join("_", @{$body->{libraries}});
      if (open FH, ">/homes/paczian/public/mobedac_remote/$infile") {
	print FH Dumper $body;
	close FH;
	print $cgi->header(-type => 'text/plain',
			   -status => 201,
			   -Access_Control_Allow_Origin => '*' );
	print "data received successfully";
	exit 0;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 507,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: storing object failed";
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid parameters, requires analysis_system and libraries";
    }
  } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: authentication failed";    
  }
}

sub widgets {
  my ($rest) = @_;

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my @widgets = ();
  my $adir = "/homes/paczian/public/widgets";
  if (opendir(my $dh, $adir)) {
    @widgets = grep { -f "$adir/$_" } readdir($dh);
    closedir $dh;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not open widgets directory";
    exit 0;
  }
  my $widget_hash = {};
  %$widget_hash = map { $_ => 1 } @widgets;

  if (scalar(@$rest)) {
    if ($widget_hash->{$rest->[0]}) {
      if (open(FH, "<$adir/".$rest->[0])) {
	print $cgi->header(-type => 'application/javascript',
			   -status => 200,
			   -Access_Control_Allow_Origin => '*' );
	while (<FH>) {
	  print $_;
	}
	exit 0;
	close FH;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: reading widget failed";
	exit 0;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid widget requested";
      exit 0;
    }
  }

  my $data = { id => 'MGRAST',
	       url => 'http://api.metagenomics.anl.gov/widgets/',
	       description => 'Metagenome RAST Widget provider',
	       widgets => \@widgets };
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );

  print $json->encode( $data );
  exit 0;
}

sub available_resources {
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my $data = { id => 'MGRAST',
	       url => 'http://api.metagenomics.anl.gov/',
	       description => 'Metagenome RAST JSON-REST API',
	       resources => [ 'sequences',
			      'annotation',
			      'abundance_profile',
			      'metagenome',
			      'project',
			      'sample',
			      'library',
			      'subset',
			      'sequenceSet',
			      'sequences',
			      'matrix' ] };
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );

  print $json->encode( $data );
  exit 0;
}

sub subset {
  my ($rest, $master, $user, $create) = @_;

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my $id = shift @$rest;

  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: missing id in sequences call: ".$id;
    exit 0;
  }

  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
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
    my @funcs = $cgi->param('function');
    if (ref($anns)) {
      push(@$anns, @funcs);
    } else {
      $anns = \@funcs;
    }
  }
  
  my $job = $master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$job)) {
    $job = $job->[0];
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {

      my $mgdb = MGRAST::Analysis->new( $master->db_handle );
      $mgdb->set_jobs([$id]);
      
      my $content = $mgdb->md5_abundance_for_annotations($id, $type, $source, $anns);
      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode($content);
      exit 0;

    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid authentication for id ".$id;
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not retrive job data from database for id ".$id;
    exit 0;
  }
}

sub reads {
  my ($rest, $master, $user, $create) = @_;

  my $cgi = new CGI;

  unless (scalar(@$rest) == 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for reads call";
    exit 0;
  }

  my ($mgid) = $rest->[0] =~ /^mgm(\d+\.\d+)$/;

  unless ($mgid) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for reads call: ".$rest->[0];
    exit 0;  
  }

  my $job = $master->Job->get_objects( { metagenome_id => $mgid } );
  if (scalar(@$job)) {
    $job = $job->[0];
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $mgid))) {
      $job->download(0);
    } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 401,
		       -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid authentication for id ".$rest->[0];
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not retrive job data from database for id ".$rest->[0];
    exit 0;
  }
  
  exit 0;
}

sub sequences {
  my ($rest, $master, $user, $create) = @_;

  my $cgi = new CGI;
  
  my $id = shift @$rest;

  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: missing id in sequences call: ".$id;
    exit 0;
  }

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
  if ($cgi->param('md5s')) {
    @$md5s = $cgi->param('md5s');
  }

  my $job = $master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$job)) {
    $job = $job->[0];
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {

      my $mgdb = MGRAST::Analysis->new( $master->db_handle );
      $mgdb->set_jobs([$id]);
      
      my $json = new JSON;
      $json = $json->utf8();
      my $content;
      if (ref $md5s) {
	$content = $mgdb->sequences_for_md5s($id, $seq, $md5s);
      } else {
	$content = $mgdb->sequences_for_annotation($id, $seq, $type, $source, $anns);
      }

      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode($content);
      exit 0;

    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid authentication for id ".$id;
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not retrive job data from database for id ".$id;
    exit 0;
  }
}

sub annotation {
  my ($rest, $master, $user, $create) = @_;

  my $ach = new Babel::lib::Babel;
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my $sources;
  if ($cgi->param('namespace')) {
    $sources = [ $cgi->param('namespace') ];
  }

  unless ($sources) {
    $sources = $ach->sources;
    my $source_list = [];
    @$source_list = map { $_ } keys(%$sources);
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($source_list);
    exit 0;
  }

  unless (scalar(@$rest)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for annotation call";
    exit 0;
  }
  
  my $md5s = [ shift @$rest ];
  
  my $stuff = $ach->md5s2idfunc4sources($md5s, $sources);
  my $org = $ach->md5s2organisms($md5s);
  if (scalar(@$org)) {
    $org = $org->[0]->[0];
  } else {
    $org = "unknown";
  }

  unless (scalar(keys(%$stuff))) {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: md5 not found";
    exit 0;
  }
  my $data = { md5 => $md5s->[0],
	       source => $stuff->{$md5s->[0]}->[0]->[0],
	       FID => $stuff->{$md5s->[0]}->[0]->[1],
	       function => $stuff->{$md5s->[0]}->[0]->[2],
	       organism => $org };	  

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub abundance_profile {
  my ($rest, $master, $user, $create) = @_;
  
  if ($create) {
    &create_profile($rest, $master, $user);
    exit 0;
  }

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  unless (scalar(@$rest) >= 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: abundance profile call requires at least an id parameter";
    exit 0;
  }

  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;

  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for profile call: ".$rest->[0];
    exit 0;
  }

  my $job_object = $master->Job->get_objects( { metagenome_id => $id } );
  unless ($job_object) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Unknown id in profile call: ".$rest->[0];
    exit 0;
  }

  $job_object = $job_object->[0];

  unless ($job_object->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient permissions for profile call for id: ".$rest->[0];
    exit 0;
  }

  shift @$rest;

  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }

  my $source = 'RefSeq';
  if ($params->{source}) {
    $source = $params->{source};
  } elsif ($cgi->param('source')) {
    $source = $cgi->param('source');
  }

  if ($cgi->param('type')) {
    $params->{type} = $cgi->param('type');
  }

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  $mgdb->set_jobs([$id]);

  my $ach = new Babel::lib::Babel;

  if (scalar(@$rest) && $rest->[0] eq 'available_sources') {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($mgdb->get_sources);
    exit 0;
  }

  my $data;

  if (! $params->{type} || ($params->{type} && $params->{type} eq 'organism')) {
    my $strain2tax = {};
    
    my $dbh = $ach->dbh;
    my $rows = $dbh->selectall_arrayref("select name, ncbi_tax_id from organisms_ncbi");
    %$strain2tax = map { $_->[0] => $_->[1] } @$rows;

    my ($md5_abund, $result) = $mgdb->get_organisms_for_sources([$source]);
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
    
    $data = { "id"                  => $id,
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

  } elsif ($params->{type} && $params->{type} eq 'ontology') {

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
    
    $data = { "id"                  => $id,
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
    print "ERROR: Invalid type for profile call: ".$params->{type}." - valid types are [ 'taxonomy', 'ontology' ]";
    exit 0;
  }

  if ($cgi->param('callback')) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print "data_return('".$params->{type}."', ".$json->encode( $data ).");";
    exit 0;
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub create_profile {
  my ($data, $master, $user) = @_;

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  unless (ref($data) eq 'ARRAY') {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid parameters for profile creation - must be an array of objects not ".ref($data);
    exit 0;
  }

  my $objects = [];
  my $count = 0;
  my $errors = [];
  foreach my $d (@$data) {
    $count++;

    unless (ref($d) eq 'HASH' && $d->{table_desc} && ref($d->{table_desc}) eq 'HASH' && $d->{table_desc}->{id}) {
      push(@$errors, "ERROR: Invalid object structure in profile creation for record $count - must be QIIME_MGRAST_dataformat_v0.1");
      next;
    }

    my $id = $d->{table_desc}->{id};
    unless ($user && $user->has_right(undef, 'edit', 'metagenome', $id)) {
      push(@$errors, "ERROR: Insufficient rights for profile creation for record $count, ID $id");
      next;
    }

    my $job = $master->Job->get_objects( { metagenome_id => $id } );
    unless (ref($job)) {
      push(@$errors, "ERROR: Could not retrieve job associated with id $id for record $count from the database");
      next;
    }
    $job = $job->[0];

    my $dir = $job->directory;
    unless (-d $dir) {
      push(@$errors, "ERROR: Could open job directory associated with id $id for record $count from the database");
      next;
    }

    if (open(FH, ">$dir/profile.txt")) {
      print FH Dumper($d);
      close FH;
      push(@$objects, $d);
    } else {
      push(@$errors, "ERROR: Could write profile file for id $id, record $count");
      next;
    }
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  if (scalar(@$errors)) {
    print "There were errors in the profile creation:\n";
    print join("\n", @$errors)."\n\n";
  }
  if (scalar(@$objects)) {
    print $json->encode($objects);
  }
  exit 0;
}

sub matrix {
  my ($rest, $master, $user, $create) = @_;
  
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();
  
  unless (scalar(@$rest)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for matrix call";
    exit 0;
  }

  my $raw_ids = [];
  my $ids = [];
  @$raw_ids = split /;/, $rest->[0];
  my $id_pos = {};
  my $x = 0;
  foreach my $raw_id (@$raw_ids) {
    my (undef, $id) = $raw_id =~ /^(mgm)?(\d+\.\d+)$/;
    if ($id) {
      push(@$ids, $id);
      $id_pos->{$id} = $x;
      $x++;
    }
  }

  unless (scalar(@$ids)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for profile call: ".$rest->[0];
    exit 0;
  }

  if (scalar(@$ids) < 30) {
    foreach my $id (@$ids) {
      my $job_object = $master->Job->get_objects( { metagenome_id => $id } );
      unless ($job_object) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Unknown id in matrix call: ".$id;
	exit 0;
      }
      
      unless ($job_object->[0]->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Insufficient permissions for matrix call for id: ".$id;
	exit 0;
      }
    }
  } else {
    my $allowed = {};
    if ($user) {
      my $hrt = $user->has_right_to(undef, 'view', 'metagenome');
      %$allowed = map { $_ => 1 } @$hrt;
    }
    my $public = $master->Job->get_objects( { public => 1 } );
    foreach my $pj (@$public) {
      $allowed->{$pj->{metagenome_id}} = 1;
    }
    foreach my $id (@$ids) {
      unless ($allowed->{$id}) {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Insufficient permissions for matrix call for id: ".$id;
	exit 0;
      }
    }
  }

  shift @$rest;

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  $mgdb->set_jobs($ids);

  my $ach = new Babel::lib::Babel;

  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }

  my $source = 'RefSeq';
  if ($params->{source}) {
    $source = $params->{source};
  } elsif ($params->{type} && $params->{type} eq 'ontology') {
    $source = $params->{source} || 'Subsystems';
  }

  my $data;
  my ($md5_abund, $result);

  if (! $params->{type} || ($params->{type} && $params->{type} eq 'taxonomy')) {
    ($md5_abund, $result) = $mgdb->get_organisms_for_sources([$source]);   
  } elsif ($params->{type} && $params->{type} eq 'ontology') {
    ($md5_abund, $result) = $mgdb->get_ontology_for_source($source);
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for matrix call: ".$params->{type}." - valid types are [ 'taxonomy', 'ontology' ]";
    exit 0;
  }

  if ($params->{format} && $params->{format} eq 'plain') {
    my $mg_pos = {};
    for (my $i=0;$i<scalar(@$ids);$i++) {
      $mg_pos->{$ids->[$i]} = $i;
    }
    unless (defined($params->{result_column})) {
      $params->{result_column} = 'abundance';
    }
    unless (defined($params->{show_hierarchy})) {
      $params->{show_hierarchy} = 0;
    }
    my $first_val_cell = 1;
    my $row_hash = {};
    if (! $params->{type} || ($params->{type} && $params->{type} eq 'taxonomy')) {
      # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
      my $colmapping = { 'abundance' => 10,
			 'evalue'   => 12,
			 'length'   => 16,
			 'identity' => 14 };

      my $levelmapping = { 'domain'  => 2,
			   'phylum'  => 3,
			   'class'   => 4,
			   'order'   => 5,
			   'family'  => 6,
			   'genus'   => 7,
			   'species' => 8,
			   'strain'  => 9 };

      unless (defined($params->{group_level})) {
	$params->{group_level} = 'strain';
      }

      my $value_col = $colmapping->{$params->{result_column}};
      my $group_col = $levelmapping->{$params->{group_level}};
      my $tax_hash = {};
      if ($params->{show_hierarchy}) {
	$first_val_cell += $group_col - 2;
      }
      foreach my $row (@$result) {
	unless (defined($tax_hash->{$row->[$group_col]})) {
	  $tax_hash->{$row->[$group_col]} = [];
	  for (my $i=2; $i<=$group_col; $i++) {
	    push(@{$tax_hash->{$row->[$group_col]}}, $row->[$i]);
	  }
	}
	if (! exists($row_hash->{$row->[$group_col]})) {
	  my $new_row = [];
	  if ($params->{show_hierarchy}) {
	    push(@$new_row, @{$tax_hash->{$row->[$group_col]}});
	  } else {
	    push(@$new_row, $row->[$group_col]);
	  }
	  if ($params->{result_column} eq 'abundance') {
	    push(@$new_row, map { 0 } @$ids);
	  } else {
	    push(@$new_row, map { "0;0" } @$ids);
	  }
	  $row_hash->{$row->[$group_col]} = $new_row;
	}
	if ($params->{result_column} eq 'abundance') {
	  $row_hash->{$row->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}] += $row->[$value_col];
	} else {
	  my ($v, $n) = split /;/, $row_hash->{$row->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}];
	  $row_hash->{$row->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}] = ((($row->[$value_col] * $row->[10]) + ($v * $n)) / ($n + $row->[10])).";".($n+$row->[10]);
	}
      }
      
    } else {
      # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
      my $function2ont = $ach->get_all_ontology4source_hash($source);

      my $colmapping = { 'abundance' => 3,
			 'evalue  ' => 5,
			 'length'   => 9,
			 'identity' => 7 };

      my $levelmapping = { 'level1'   => 0,
			   'level2'   => 1,
			   'level3'   => 2,
			   'function' => 3 };

      unless (defined($params->{group_level})) {
	$params->{group_level} = 'function';
      }

      my $value_col = $colmapping->{$params->{result_column}};
      my $group_col = $levelmapping->{$params->{group_level}};
      my $ont_hash = {};
      if ($params->{show_hierarchy}) {
	$first_val_cell += $group_col;
      }
      foreach my $row (@$result) {
	unless (defined($ont_hash->{$function2ont->{$row->[1]}->[$group_col]})) {
	  $ont_hash->{$function2ont->{$row->[1]}->[$group_col]} = [];
	  for (my $i=0; $i<=$group_col; $i++) {
	    push(@{$ont_hash->{$row->[$group_col]}}, $function2ont->{$row->[1]}->[$i]);
	  }
	}

	if (! exists($row_hash->{$function2ont->{$row->[1]}->[$group_col]})) {
	  my $new_row = [];
	  if ($params->{show_hierarchy}) {
	    push(@$new_row, @{$ont_hash->{$function2ont->{$row->[1]}->[$group_col]}});
	  } else {
	    push(@$new_row, $function2ont->{$row->[1]}->[$group_col]);
	  }
	  if ($params->{result_column} eq 'abundance') {
	    push(@$new_row, map { 0 } @$ids);
	  } else {
	    push(@$new_row, map { "0;0" } @$ids);
	  }
	  $row_hash->{$function2ont->{$row->[1]}->[$group_col]} = $new_row;
	}
	if ($params->{result_column} eq 'abundance') {
	  $row_hash->{$function2ont->{$row->[1]}->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}] += $row->[$value_col];
	} else {
	  my ($v, $n) = split /;/, $row_hash->{$function2ont->{$row->[1]}->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}];
	  $row_hash->{$function2ont->{$row->[1]}->[$group_col]}->[$first_val_cell + $mg_pos->{$row->[0]}] = ((($row->[$value_col] * $row->[3]) + ($v * $n)) / ($n + $row->[3])).";".($n+$row->[3]);
	}
      }
    }
    foreach my $key (sort(keys(%$row_hash))) {
      if ($params->{result_column} ne 'abundance') {
	my $len = scalar(@$ids) + $first_val_cell;
	for (my $i=$first_val_cell; $i<$len; $i++) {
	  ($row_hash->{$key}->[$i], undef) = split /;/, $row_hash->{$key}->[$i];
	}
      }
      push(@$data, $row_hash->{$key});
    }

    my $header = [];
    for (my $i=0;$i<$first_val_cell; $i++) {
      push(@$header, "");
    }
    for (my $i=0;$i<scalar(@$ids); $i++) {
      push(@$header, $ids->[$i]);
    }
    
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print join("\t", @$header)."\n";
    print join("\n", map { join("\t", @$_) } @$data);
    exit 0;
  } else {

    if (! $params->{type} || ($params->{type} && $params->{type} eq 'taxonomy')) {
      my $value_index = 10;
      my $strain2tax = {};
      my $dbh = $ach->dbh;
      my $rows = $dbh->selectall_arrayref("select name, ncbi_tax_id from organisms_ncbi");
      %$strain2tax = map { $_->[0] => $_->[1] } @$rows;
      
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      
      my $values = [];
      my $numrows = scalar(@$result);
      my $tax = [];
      my $taxa = {};
      my $pos = 0;
      foreach my $row (@$result) {
	if (! $strain2tax->{$row->[9]}) {
	  next;
	}
	unless (exists($taxa->{$strain2tax->{$row->[9]}})) {
	  my $tax_str = [ "k__".$row->[2], "p__".$row->[3], "c__".$row->[4], "o__".$row->[5], "f__".$row->[6], "g__".$row->[7], "s__".$row->[9] ];
	  push(@$tax, { "id" => $strain2tax->{$row->[9]}, "metadata" =>  { "taxonomy" => $tax_str }  });
	  $taxa->{$strain2tax->{$row->[9]}} = $pos;
	  $pos++;
	}
	push(@$values, [ int($taxa->{$strain2tax->{$row->[9]}}), $id_pos->{$row->[0]}, int($row->[10]) ]);
      }
      
      $data = { "id"                  => undef ,
		"format"              => "Biological Observation Matrix 0.9.1",
		"format_url"          => "http://biom-format.org",
		"type"                => "Taxon table",
		"generated_by"        => "MG-RAST revision ".$FIG_Config::server_version,
		"date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		"matrix_type"         => "sparse",
		"matrix_element_type" => "int",
		"shape"               => [ $pos, scalar(@$ids) ],
		"rows"                => $tax,
		"columns"             => [ map { { "id" => $_, "metadata" => undef } } @$ids ],
		"data"                => $values };

    } else {

      my $value_index = 3;
      my $function2ont = $ach->get_all_ontology4source_hash($source);

      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      my $values = [];
      my $numrows = scalar(@$result);
      my $ont = [];
      my $pos = 0;
      my $ontol = {};
      foreach my $row (@$result) {
	next unless ($function2ont->{$row->[1]});
	my $function = $row->[1];
	unless (exists($ontol->{$function})) {
	  my $ont_str = [ map { defined($_) ? $_ : '-' } @{$function2ont->{$row->[1]}} ];
	  push(@$ont, { "id" => $row->[1], "metadata" =>  { "ontology" => $ont_str }  });
	  $ontol->{$function} = $pos;
	  $pos++;
	}
	push(@$values, [ $ontol->{$function}, $id_pos->{$row->[0]}, int($row->[3]) ]);
      }
      
      $data = { "id"                  => undef ,
		"format"              => "Biological Observation Matrix 0.9.1",
		"format_url"          => "http://biom-format.org",
		"type"                => "Function table",
		"generated_by"        => "MG-RAST revision ".$FIG_Config::server_version,
		"date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		"matrix_type"         => "sparse",
		"matrix_element_type" => "int",
		"shape"               => [ $pos, scalar(@$ids) ],
		"rows"                => $ont,
		"columns"             => [ map { { "id" => $_, "metadata" => undef } } @$ids ],
		"data"                => $values };
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($data);
    exit 0;
  }

}

sub profile {  
  my ($rest, $master, $user) = @_;

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  unless (scalar(@$rest)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for profile call";
    exit 0;
  }

  my $id = $rest->[0];

  my $strain2tax = {};
  my $ach = new Babel::lib::Babel;
  my $dbh = $ach->dbh;
  my $rows = $dbh->selectall_arrayref("select name, ncbi_tax_id from organisms_ncbi");
  %$strain2tax = map { $_->[0] => $_->[1] } @$rows;

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  $mgdb->set_jobs([$id]);
  my ($md5_abund, $result) = $mgdb->get_organisms_for_sources(['RefSeq']);
  # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  my $values = [];
  foreach my $row (@$result) {
      push(@$values, [ $strain2tax->{$row->[9]}, $row->[2], $row->[3], $row->[4], $row->[5], $row->[6], $row->[7], $row->[8], $row->[9], $row->[10], $row->[12], $row->[14], $row->[16] ]);
  }

  my $data = [ { "type" => "profile",
		 "id" => $id,
		 "columns" => [ 'id', 'domain', 'phylum', 'class', 'order', 'family', 'genus', 'species', 'strain', 'abundance', 'evalue', 'identity', 'alength' ],
		 "values" => $values } ];

  if ($cgi->param('callback')) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print "data_return('profile', ".$json->encode( $data ).");";
    exit 0;
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub stats {
  my ($rest, $master, $user) = @_;

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my $id = shift @$rest;

  my ($pref, $mgid, $job, $stat_type);
  
  if ($id) {
    ($pref, $mgid, $stat_type) = $id =~ /^(mgm)?([\d\.]+)-(.+)$/;

    if ($mgid) {
      $job = $master->Job->get_objects( { metagenome_id => $mgid } );
      if (scalar(@$job)) {
	$job = $job->[0];
	unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
	  print $cgi->header(-type => 'text/plain',
			     -status => 401,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: Insufficient permissions for stats call for id: ".$id;
	  exit 0;
	}
	
	# get the defined stats file
	my $adir = $job->analysis_dir;
	my $stagefilename;
	if (opendir(my $dh, $adir)) {
	  my @stagefiles = grep { /$stat_type\.txt$/ && -f "$adir/$_" } readdir($dh);
	  closedir $dh;
	  $stagefilename = $stagefiles[0];
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: could not find stats file";
	  exit 0;
	}
	if (open(FH, "$adir/$stagefilename")) {

	  if ($cgi->param('callback')) {
	    my $rows = [];
	    while (<FH>) {
	      chomp;
	      my @row = split /\t/;
	      push(@$rows, \@row);
	    }
	    
	    print $cgi->header(-type => 'application/json',
			       -status => 200,
			       -Access_Control_Allow_Origin => '*' );
	    print "data_return('stats', ".$json->encode( [ { id => $mgid."-".$stat_type, data => $rows } ] ).");";
	    exit 0;
	  }


	  print "Content-Type:application/x-download\n";  
	  print "Content-Length: " . (stat("$adir/$stagefilename"))[7] . "\n";
	  print "Content-Disposition:attachment;filename=$stagefilename\n\n";
	  while (<FH>) {
	    print;
	  }
	  close FH;
	}
	  
	exit 0;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 404,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: could not find metagenome for id: ".$id;
	exit 0;
      }
    } else {
      my ($pref, $mgid) = $id =~ /^(mgm)?(\d+\.\d+)$/;
      if ($mgid) {
	$job = $master->Job->get_objects( { metagenome_id => $mgid } );
	if (scalar(@$job)) {
	  $job = $job->[0];
	  unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
	    print $cgi->header(-type => 'text/plain',
			       -status => 401,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Insufficient permissions for stats call for id: ".$id;
	    exit 0;
	  }
	  
	  # get the available stats files
	  my $adir = $job->analysis_dir;
	  my $stages = [];
	  if (opendir(my $dh, $adir)) {
	    my @stagefiles = grep { /^.*\.txt$/ && -f "$adir/$_" } readdir($dh);
	    closedir $dh;
	    foreach my $sf (@stagefiles) {
	      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.txt$/;
	      next unless ($stageid && $stagename && $stageresult);
	      push(@$stages, { id => "mgm".$mgid."-".$stageresult,
			       stat_type => $stageresult,
			       file_name => $sf });
	    }
	  } else {
	    $stages = [];
	  }
	  if ($cgi->param('callback')) {
	    print $cgi->header(-type => 'application/json',
			       -status => 200,
			       -Access_Control_Allow_Origin => '*' );
	    print "data_return('stats', ".$json->encode( [ { id => $mgid, data => $stages, type => 'stats' } ] ).");";
	    exit 0;
	  }

	  print $cgi->header(-type => 'application/json',
			     -status => 200,
			     -Access_Control_Allow_Origin => '*' );
	  print $json->encode($stages);
	  exit 0;
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: Could not access metagenome: ".$id;
	  exit 0;	
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid id format for stats call: ".$id;
	exit 0;
      }
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient parameters for stats call";
    exit 0;
  }
}

sub query {
  my ($rest, $master, $user, $create) = @_;
  
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();
    
  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
  }
  my $source;
  if ($cgi->param('source')) {
    @$source = $cgi->param('source');
  }
  my $ann;
  if (scalar(@$rest)) {
    $ann = shift @$rest;
  }
  if ($cgi->param('annotation')) {
    $ann = $cgi->param('annotation');
  }
  
  my $exact = 1;
  if ($cgi->param('partial')) {
    $exact = 0;
  }
  
  unless (defined($ann)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient parameters for query call";
    exit 0;
  }

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  
  my $content = $mgdb->metagenome_search($type, $source, $ann, $exact);

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub pipeline_info {
  my ($rest, $master, $user) = @_;
  
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();
  
  my $id = shift @$rest;
  
  my $job = $master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$job)) {
    $job = $job->[0];
    unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Insufficient permissions for stats call for id: ".$id;
      exit 0;
    }
    
    my $data = [];
    my $adir = $job->analysis_dir;
    my $info = {};
    $info->{id} = $id;
    $info->{type} = "pipeline_info";

    # basic file info
    if (open(FH, "$adir/../raw/".$job->{job_id}.".fastq.stats")) {
      my $stage = {};
      while (<FH>) {
	chomp;
	my ($name, $value) = split /\t/;
	$stage->{$name} = $value;
      }
      close FH;
      $info->{upload} = $stage;
    } else {
      print STDERR "error: $@ $!\n";
    }

    # go through the stages
    if (opendir(my $dh, $adir)) {
      my @statsfiles = grep { /\.stats$/ && -f "$adir/$_" } readdir($dh);
      closedir $dh;
      
      foreach my $sf (@statsfiles) {
	my ($num, $nam, $typ) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)/;
	if ($num < 200) {
	  if ($num eq "075") {
	    if (open(FH, "$adir/$sf")) {
	      my $drisee = {};
	      my $header = <FH>;
	      my $global = <FH>;
	      chomp $global;
	      my @globald = split /\t/, $global;
	      $drisee->{global} = \@globald;
	      $header = <FH>;
	      my $drisee_data = [];
	      while (<FH>) {
		chomp;
		my @row = split /\t/;
		push(@$drisee_data, \@row);
	      }
	      $drisee->{data} = $drisee_data;
	      close FH;
	      $info->{drisee} = $drisee;
	    }	    
	  } else {
	    if (open(FH, "$adir/$sf")) {
	      my $stage = {};
	      while (<FH>) {
		chomp;
		my ($name, $value) = split /\t/;
		$stage->{$name} = $value;
	      }
	      close FH;
	      unless (exists($info->{$nam})) {
		$info->{$nam} = {};
	      }
	      $info->{$nam}->{$typ} = $stage;
	    }
	  }
	}
      }
    }

    push(@$data, $info);

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print "data_return('pipeline_info', ".$json->encode( $data ).");";
  }
}

sub user_inbox {
  my ($rest, $master, $user) = @_;
  
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  use Digest::MD5 qw(md5_base64);
  my $basedir = "/homes/paczian/public/upload_test/";
  my $dir = $basedir.md5_base64($user->login)."/";
 
  if (scalar(@$rest)) {
    my $action = shift @$rest;
    if ($action eq 'del') {
      foreach my $file (@$rest) {
	if (-f "$dir$file") {
	  `rm $dir$file`;
	}
      }
    }

    if ($action eq 'unpack') {
      foreach my $file (@$rest) {
	if (-f "$dir$file") {
	  if ($file =~ /\.tar\.gz$/) {
	    `tar -xzf $dir$file -C $dir`;
	  } elsif ($file =~ /\.(gz|zip)$/) {
	    `unzip -d $dir $dir$file`;
	  }
	}
      }
    } 
  }

  my $data = [ { type => 'user_inbox', id => $user->login, files => [] }];
  if (opendir(my $dh, $dir)) {
    my @ufiles = grep { /^[^\.]/ && -f "$dir/$_" } readdir($dh);
    closedir $dh;
    
    foreach my $ufile (@ufiles) {
      push(@{$data->[0]->{files}}, $ufile);
    }
  }

  @{$data->[0]->{files}} = sort { lc $a cmp lc $b } @{$data->[0]->{files}};
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print "data_return('user_inbox', ".$json->encode( $data ).");";
}

sub reference_genomes {
  my ($rest, $master, $user) = @_;
  
  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();

  my $ach = new Babel::lib::Babel;
  my $dbh = $ach->dbh;
  my $orgs = $dbh->selectcol_arrayref("SELECT DISTINCT name FROM organisms_ncbi WHERE tax_domain='Bacteria'");
  my $data = [ { type => 'reference_genomes', id => 1, genomes => $orgs } ];
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print "data_return('reference_genomes', ".$json->encode( $data ).");";
}

sub metadata {
  my ($rest, $master, $user) = @_;

  my $cgi  = new CGI;
  my $json = new JSON;
  my $data = {};
  $json = $json->utf8();

  unless (scalar(@$rest)) {
    print $cgi->header(-type => 'text/plain', -status => 400, -Access_Control_Allow_Origin => '*');
    print "ERROR: missing metadata request type";
    exit 0;
  }
  my $type = shift @$rest;

  if ($type eq 'template') {
    my $objs = $master->MetaDataTemplate->get_objects();
    foreach my $o (@$objs) {
      my $info = { qiime_tag  => $o->qiime_tag,
		   mgrast_tag => $o->mgrast_tag,
		   definition => $o->definition,
		   required   => $o->required,
		   mixs       => $o->mixs,
		   type       => $o->type };
      $data->{$o->category_type}{$o->category}{$o->tag} = $info;
    }
  }
  elsif ($type eq 'cv') {
    my $objs = $master->MetaDataCV->get_objects();
    foreach my $o (@$objs) {
      if ($o->type eq 'select') {
	push @{ $data->{$o->type}{$o->tag} }, $o->value;
      }
      else {
	$data->{$o->type}{$o->tag} = $o->value;
      }
    }
  }
  else {
    print $cgi->header(-type => 'text/plain', -status => 400, -Access_Control_Allow_Origin => '*');
    print "ERROR: invalid metadata request type: ".$type;
    exit 0;
  }

  print $cgi->header(-type => 'application/json', -status => 200, -Access_Control_Allow_Origin => '*');
  print $json->encode($data);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }
