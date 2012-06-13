package resources::matrix;

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
  my $content = { 'description' => "metagenomic matrix",
		  'parameters' => { "id" => "string",
				    "source" => { "protein"  => [ 'm5nr', map {$_->[0]} @{$ach->get_protein_sources} ],
						  "ontology" => [ map {$_->[0]} @{$ach->get_ontology_sources} ],
						  "rna"      => [ 'm5rna', map {$_->[0]} @{$ach->get_rna_sources} ]
						},
				    "type" => [ "function", "organism" ],
				    "format" => [ "plain", "biome" ],
				    "result_column" => [ "abundance","evalue","length","identity" ],
				    "group_level" => { "function" => ['level1','level2','level3','function'],
						       "organism" => ['domain','phylum','class','order','family','genus','species','strain'] },
				    "show_hierarchy" => "boolean" },
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
      
      unless ($job_object->[0]->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
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

  my $source = 'M5NR';
  if ($params->{source}) {
    $source = $params->{source};
  } elsif ($params->{type} && $params->{type} eq 'function') {
    $source = $params->{source} || 'Subsystems';
  }

  my $data;
  my ($md5_abund, $result);

  if (! $params->{type} || ($params->{type} && $params->{type} eq 'organism')) {
    ($md5_abund, $result) = $mgdb->get_organisms_for_sources([$source]);   
  } elsif ($params->{type} && $params->{type} eq 'function') {
    ($md5_abund, $result) = $mgdb->get_ontology_for_source($source);
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for matrix call: ".$params->{type}." - valid types are [ 'function', 'organism' ]";
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
    if (! $params->{type} || ($params->{type} && $params->{type} eq 'organism')) {
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
    
    print $cgi->header(-type => 'text/plain',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print join("\t", @$header)."\n";
    print join("\n", map { join("\t", @$_) } @$data);
    exit 0;
  } else {
    if (! $params->{type} || ($params->{type} && $params->{type} eq 'organism')) {
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
      
      $data = { "id"                  => join(";", map { "mgm".$_ } @$ids) ,
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
      
      $data = { "id"                  => join(";", map { "mgm".$_ } @$ids),
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

sub TO_JSON { return { %{ shift() } }; }

1;
