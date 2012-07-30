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

my $value_idx = {abundance => {function => 3, organism => 10, feature => 2},
		 exp_avg   => {function => 5, organism => 12, feature => 3},
		 len_avg   => {function => 7, organism => 14, feature => 5},
		 ident_avg => {function => 9, organism => 16, feature => 7}
		};
my $value_type = {abundance => 'abundance', evalue => 'exp_avg', length => 'len_avg', identity => 'ident_avg'};
my $func_hier  = ['level1','level2','level3','function'];
my $org_hier   = ['domain','phylum','class','order','family','genus','species','strain'];
my $type_set   = ["function", "organism", "feature"];
my $format_set = ["plain", "biome"];
my $org2tax    = {};

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "metagenomic matrix",
		  'parameters' => { "id"     => "one or more metagenome or project ids joined by ';'",
				    "source" => { "organism protein"  => [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ],
						  "function ontology" => [ map {$_->[0]} @{$ach->get_ontology_sources} ],
						  "organism rna"      => [ 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources} ]
						},
				    "type"   => $type_set,
				    "format" => $format_set,
				    "result_type" => [ keys %$value_type ],
				    "group_level" => { "function" => $func_hier,
						       "organism" => $org_hier },
				    "show_hierarchy" => "boolean"
				  },
		  'defaults' => { "source"         => "M5NR (organism), or Subsystems (function), or RefSeq (feature)",
				  "type"           => "organism",
				  "format"         => "biom",
				  "result_type"    => "abundance",
				  "group_level"    => "strain (organism) or function (function)",
				  "show_hierarchy" => "false"
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
  if (($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') || (scalar(@$rest) == 0)) {
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

  # get input id set
  my $id_str = shift @$rest;
  my @ids    = split(/;/, $id_str);
  my $mgids  = {};
  my $seen   = {};

  # get user viewable
  my %p_rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();
  my %m_rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();
  map { $p_rights{$_} = 1 } @{ $master->Project->get_public_projects(1) };
  map { $m_rights{$_} = 1 } @{ $master->Job->get_public_jobs(1) };

  # get unique list of mgids based on user rights and inputed ids
  foreach my $id (@ids) {
    next if (exists $seen->{$id});
    if ($id =~ /^mgm(\d+\.\d+)$/) {
      if (exists($m_rights{'*'}) || exists($m_rights{$1})) {
	$mgids->{$1} = 1;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Insufficient permissions in matrix call for id: ".$id;
	exit 0;
      }
    } elsif ($id =~ /^mgp(\d+)$/) {
      if (exists($p_rights{'*'}) || exists($p_rights{$1})) {
	my $proj = $master->Project->init( {id => $1} );
	foreach my $mgid (@{ $proj->metagenomes(1) }) {
	  next unless (exists($m_rights{'*'}) || exists($m_rights{$mgid}));
	  $mgids->{$mgid} = 1;
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Insufficient permissions in matrix call for id: ".$id;
	exit 0;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Unknown id in matrix call: ".$id;
      exit 0;
    }
    $seen->{$id} = 1;
  }
  if (scalar(keys %$mgids) == 0) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: No valid ids submitted and/or found: ".$id_str;
    exit 0;
  }

  # initialize analysis obj with mgids
  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }
  $mgdb->set_jobs([ keys %$mgids ]);

  # get params from rest pairs
  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }

  # params may be cgi params
  $params->{type}   = $cgi->param('type') ? $cgi->param('type') : 'organism';
  $params->{format} = $cgi->param('format') ? $cgi->param('format') : 'biom';
  $params->{source} = $cgi->param('source') ? $cgi->param('source') :
    (($params->{type} eq 'organism') ? 'M5NR' : (($params->{type} eq 'function') ? 'Subsystems': 'RefSeq'));
  $params->{result_type}    = $cgi->param('result_type') ? $cgi->param('result_type') : 'abundance';
  $params->{group_level}    = $cgi->param('group_level') ? $cgi->param('group_level') : (($params->{type} eq 'organism') ? 'strain' : 'function');
  $params->{show_hierarchy} = $cgi->param('show_hierarchy') ? 1 : 0;
  my $type  = $params->{type};
  my $src   = $params->{source};
  my $rtype = $params->{result_type};
  my $glvl  = $params->{group_level};
  my $all_srcs  = {};
  my $leaf_node = 0;

  # validate controlled vocabulary params
  if (exists $value_type->{$rtype}) {
    $rtype = $value_type->{$rtype};
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid result_type for matrix call: ".$rtype." - valid types are [".join(", ", keys %$value_type)."]";
    exit 0;
  }
  if ($type eq 'organism') {
    $all_srcs = { M5NR => 1, M5RNA => 1 };
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
    if ( grep(/^$glvl$/, @$org_hier) ) {
      $glvl = 'tax_'.$glvl;
      if ($glvl eq 'tax_strain') {
	$glvl = 'name';
	$leaf_node = 1;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid group_level for matrix call of type ".$type.": ".$glvl." - valid types are [".join(", ", @$org_hier)."]";
      exit 0;
    }
  } elsif ($type eq 'function') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_ontology_sources};
    if ( grep(/^$glvl$/, @$func_hier) ) {
      if ($glvl eq 'function') {
	$glvl = ($src =~ /^[NC]OG$/) ? 'level3' : 'level4';
      }
      if ( ($glvl eq 'level4') || (($src =~ /^[NC]OG$/) && ($glvl eq 'level3')) ) {
	$leaf_node = 1;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid group_level for matrix call of type ".$type.": ".$glvl." - valid types are [".join(", ", @$func_hier)."]";
      exit 0;
    }
  } elsif ($type eq 'feature') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for matrix call: ".$type." - valid types are [".join(", ", @$type_set)."]";
    exit 0;
  }
  unless (exists $all_srcs->{$src}) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid source for matrix call of type ".$type.": ".$src." - valid types are [".join(", ", keys %$all_srcs)."]";
    exit 0;
  }

  # get data
  my $md52id  = {};
  my $ttype   = '';
  my $mtype   = '';
  my $matrix  = []; # [ row <annotation>, col <mgid>, value ]
  my $col_idx = $value_idx->{$rtype}{$type};

  if ($type eq 'organism') {
    $ttype = 'Taxon';
    $mtype = 'taxonomy';
    if ($leaf_node) {
      my (undef, $info) = $mgdb->get_organisms_for_sources([$src]);
      # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
      @$matrix = map {[ $_->[9], $_->[0], toNum($_->[$col_idx], $rtype) ]} @$info;
      map { $org2tax->{$_->[9]} = [ @$_[2..9] ] } @$info;
    } else {
      @$matrix = map {[ $_->[1], $_->[0], toNum($_->[2], $rtype) ]} @{$mgdb->get_abundance_for_tax_level($glvl, undef, [$src], $rtype)};
      # mgid, hier_annotation, value
    }
  }
  elsif ($type eq 'function') {
    $ttype = 'Function';
    $mtype = 'ontology';
    if ($leaf_node) {
      my (undef, $info) = $mgdb->get_ontology_for_source($src);
      # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
      @$matrix = map {[ $_->[1], $_->[0], toNum($_->[$col_idx], $rtype) ]} @$info;
    } else {
      @$matrix = map {[ $_->[1], $_->[0], toNum($_->[2], $rtype) ]} @{$mgdb->get_abundance_for_ontol_level($glvl, undef, $src, $rtype)};
      # mgid, hier_annotation, value
    }
  }
  elsif ($type eq 'feature') {
    $ttype = 'Gene';
    $mtype = $src.' ID';
    my $info = $mgdb->get_md5_data(undef, undef, undef, undef, 1);
    # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length
    my %md5s = map { $_->[1], 1 } @$info;
    map { push @{$md52id->{$_->[1]}}, $_->[0] } @{ $mgdb->ach->md5s2ids4source([keys %md5s], $src) };
    @$matrix = map {[ $_->[1], $_->[0], toNum($_->[$col_idx], $rtype) ]} grep {exists $md52id->{$_->[1]}} @$info;
  }

  @$matrix = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @$matrix;
  my $row_ids = sorted_hash($matrix, 0);
  my $col_ids = sorted_hash($matrix, 1);

  # produce output
  if ($params->{format} eq 'biom') {
    my $brows = [];
    my $bcols = [];
    my $r_map = ($type eq 'feature') ? $md52id : get_hierarchy($mgdb, $type, $glvl, $src, $leaf_node);
    foreach my $rid (sort {$row_ids->{$a} <=> $row_ids->{$b}} keys %$row_ids) {
      my $rmd = exists($r_map->{$rid}) ? { $mtype => $r_map->{$rid} } : undef;
      push @$brows, { id => $rid, metadata => $rmd };
    }
    foreach my $cid (sort {$col_ids->{$a} <=> $col_ids->{$b}} keys %$col_ids) {
      push @$bcols, { id => 'mgm'.$cid, metadata => undef };
    }
    my $bdata = { "id"                  => join(";", map { $_->{id} } @$bcols),
		  "format"              => "Biological Observation Matrix 1.0",
		  "format_url"          => "http://biom-format.org",
		  "type"                => $ttype." table",
		  "generated_by"        => "MG-RAST revision ".$Conf::server_version,
		  "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		  "matrix_type"         => "sparse",
		  "matrix_element_type" => "int",
		  "shape"               => [ scalar(keys %$row_ids), scalar(keys %$col_ids) ],
		  "rows"                => $brows,
		  "columns"             => $bcols,
		  "data"                => index_sparse_matrix($matrix, $row_ids, $col_ids)
		};
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($bdata);
    exit 0;
  }
  elsif ($params->{format} eq 'plain') {
    my $hier_map = $params->{show_hierarchy} ? get_hierarchy($mgdb, $type, $glvl, $src, $leaf_node) : {};
    my $m_dense  = sparse_to_dense($matrix, $row_ids, $col_ids);
    my @row_head = sort {$row_ids->{$a} <=> $row_ids->{$b}} keys %$row_ids;
    my @col_head = sort {$col_ids->{$a} <=> $col_ids->{$b}} keys %$col_ids;
    print $cgi->header(-type => 'text/plain',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print "\t".join("\t", @col_head)."\n";
    my $rnum = 0;
    foreach my $mrow (@$m_dense) {
      my $rname = exists($hier_map->{$row_head[$rnum]}) ? join(';', @{$hier_map->{$row_head[$rnum]}}) : $row_head[$rnum];
      print $rname."\t".join("\t", @$mrow)."\n";
      $rnum += 1;
    }
    exit 0;
  }
  else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid format for matrix call: ".$params->{format}." - valid formats are [".join(", ", @$format_set)."]";
    exit 0;
  }
}

sub get_hierarchy {
  my ($mgdb, $type, $level, $src, $leaf_node) = @_;
  if ($type eq 'organism') {
    if ($leaf_node) {
      return $org2tax;
    } else {
      return $mgdb->ach->get_taxonomy4level_full($level, 1);
    }
  } elsif ($type eq 'function') {
    if ($leaf_node) {
      return $mgdb->ach->get_all_ontology4source_hash($src);
    } else {
      return $mgdb->ach->get_level4ontology_full($src, $level, 1);
    }
  } else {
    return {};
  }
}

sub sparse_to_dense {
  my ($matrix, $rows, $cols) = @_;
  my $nrows  = scalar(keys %$rows);
  my $ncols  = scalar(keys %$cols);
  my @dense  = map { [ map { 0 } 1..$ncols ] } 1..$nrows;
  foreach my $pos (@$matrix) {
    my ($r, $c, $v) = @$pos;
    $dense[ $rows->{$r} ][ $cols->{$c} ] = $v;
  }
  return \@dense;
}

sub index_sparse_matrix {
  my ($matrix, $rows, $cols) = @_;
  my $sparse = [];
  foreach my $pos (@$matrix) {
    my ($r, $c, $v) = @$pos;
    push @$sparse, [ $rows->{$r}, $cols->{$c}, $v ];
  }
  return $sparse;
}

sub sorted_hash {
  my ($array, $idx) = @_;
  my $pos = 0;
  my $out = {};
  my @sub = sort map { $_->[$idx] } @$array;
  foreach my $x (@sub) {
    next if (exists $out->{$x});
    $out->{$x} = $pos;
    $pos += 1;
  }
  return $out;
}

sub toNum {
  my ($x, $type) = @_;
  if ($type eq 'abundance') {
    return int($x);
  } else {
    return $x * 1.0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
