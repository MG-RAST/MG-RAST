#
# Annotation clearinghouse client code.
#
# The contrib dir is where the expert annotations are stored; it is separate
# from the main clearinghouse data directory since the clearinghouse data
# will be replaced on a regular basis.
#

package Babel::lib::Babel;

use strict;
use warnings;

use Conf;
use Data::Dumper;
use List::MoreUtils qw(natatime);
use Digest::MD5;
use DBI;

#
# Construct from directory containing an anno clearinghouse.
#
sub new {
    my ($class,  $dbh , $user , $readonly , $current_dir, $contrib_dir, $nr) = @_;  

    # check 
    if (! $dbh) {
      $dbh = DBI->connect("DBI:$Conf::babel_dbtype:dbname=$Conf::babel_db;host=$Conf::babel_dbhost", $Conf::babel_dbuser, '');
#      if (! $dbh) { print STDERR "Error: " . DBI->error . "\n"; }
    }
    $contrib_dir = 0 unless ($contrib_dir and -d $contrib_dir);
    $current_dir = 0 unless ($current_dir and -d $current_dir);

    my $self = {
		current_dir => $current_dir || "/mcs/bio/ach/data/md5nr/current",
		contrib_dir => $contrib_dir || "/mcs/bio/ach/data/contrib",
		dbh         => $dbh || undef,
		nr          => $nr || "md5nr",
		readonly    => 0 || $readonly,
		user        => $user,
		debug       => 0
	       };
    
    bless $self, $class;
    return $self;
}

sub DESTROY {
  my ($self) = @_;
  if ($self->dbh) {
    $self->dbh->disconnect();
  }
}

# database handle
sub dbh{
  my ($self) = @_;
  return $self->{dbh};
}

# directory for all nr files 
sub nr_dir{
   my ($self) = @_;
   return $self->{current_dir};
}

sub nr{
  my ($self) = @_;
  return $self->{current_dir} . "/" . $self->{nr};
}

sub user{
  my ($self , $user) = @_;
  $self->{user} = $user if ($user and ref $user);
  return $self->{user};
}

sub debug{
  my ($self , $debug) = @_;
  $self->{debug} = $debug if (defined $debug and $debug =~/^\d+$/);
  return $self->{debug};
}

sub get_columns4table {
  my ($self, $table) = @_;

  my $sql  = "SELECT a.attname FROM pg_attribute a, pg_class c WHERE c.oid = a.attrelid AND a.attnum > 0 AND c.relname = '$table'";
  my $cols = $self->dbh->selectcol_arrayref($sql);
  return ($cols && (@$cols > 0)) ? $cols : [];
}

#
# md52... section
#

sub md52type {
  my ($self, $md5) = @_;
  my $data = $self->md5s2type([$md5]);
  return exists($data->{$md5}) ? $data->{$md5} : '';
}

sub md5s2type {
  my ($self, $md5s) = @_;

  my $data = {};
  my $rnas = {};
  my $list = join(",", map {$self->dbh->quote($_)} @$md5s);
  my $rows = $self->dbh->selectcol_arrayref("select md5 from md5_rna where md5 in ($list)");
  if ($rows && (@$rows > 0)) {
    %$rnas = map { $_, 1 } @$rows;
  }
  map { $data->{$_} = exists($rnas->{$_}) ? 'rna' : 'protein' } @$md5s;
  return $data;
}

sub md52id {
  my ($self, $md5) = @_;
  return $self->md5s2ids([$md5]);
}

sub md5s2ids {
  my ($self, $md5s) = @_;

  my $list = join(",", map {$self->dbh->quote($_)} @$md5s);
  my $statement = "select id, md5 from md5_protein where md5 in ($list)";
  my $rows = $self->dbh->selectall_arrayref($statement);  
  return ($rows && ref($rows)) ? $rows : [];
}

sub md5s2idfunc4sources {
  my ($self, $md5s, $srcs) = @_;

  my $data = {};
  my @sqls = ();
  unless ($md5s && (@$md5s > 0) && $srcs && (@$srcs > 0)) { return $data; }
  
  my $sources  = $self->sources;
  my %src_map  = map {$sources->{$_}{_id}, $_} grep {exists $sources->{$_}} @$srcs;
  my %types    = map {$sources->{$_}{type}, 1} grep {exists $sources->{$_}} @$srcs;
  my $md5_list = join(",", map {$self->dbh->quote($_)} @$md5s);
  my $src_list = join(",", keys %src_map);

  foreach my $t (keys %types) {
    push @sqls, "select distinct md5, source, id, function from md5_$t where md5 in ($md5_list) and source in ($src_list)";
  }
  unless (@sqls > 0) { return $data; }

  my $rows = $self->dbh->selectall_arrayref( join(" UNION ", @sqls) );
  if ($rows && (@$rows > 0)) {
    my %funcs = map { $_->[3], 1 } grep {$_->[3] && ($_->[3] =~ /^\d+$/)} @$rows;
    my $tmp   = $self->dbh->selectall_arrayref("select _id, name from functions where _id in (" . join(",", keys %funcs) . ")");
    if ($tmp && (@$tmp > 0)) {
      my %func_map = map { $_->[0], $_->[1] } @$tmp;
      foreach my $r (@$rows) {
	if ( $r->[3] && exists($src_map{$r->[1]}) && exists($func_map{$r->[3]}) ) {
	  push @{ $data->{$r->[0]} }, [ $src_map{$r->[1]}, $r->[2], $func_map{$r->[3]} ];
	}
      }
    }
  }
  return $data;
}

sub md52function {
  my ($self, $md5) = @_;

  my $statement = "select functions.name, md5_protein.md5 from md5_protein, functions where md5_protein.md5 = '$md5' and functions._id = md5_protein.function";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return $rows;
}

sub md52set {
  my ($self, $md5) = @_;
  return $self->md5s2sets([$md5]);
}

sub md5s2sets {
  my ($self, $md5s) = @_;

  unless (ref($md5s) && (scalar @$md5s)) {
    return [];
  }

  # need to handle case of function being null
  my $sql = qq(select d.id, d.md5, d.function, o.name, s.name
               from md5_protein d, organisms_ncbi o, sources s
               where d.organism = o._id and d.source = s._id);
  if (@$md5s == 1) {
    $sql .= " and d.md5 = " . $self->dbh->quote($md5s->[0]);
  } else {
    $sql .= " and d.md5 in (" . join(",", map {$self->dbh->quote($_)} @$md5s) . ")";
  }
  
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
      my %funcs = map { $_->[2], 1 } grep { $_->[2] } @$rows;
      my $fmap  = {};
      if (scalar(keys %funcs) > 0) {
          my $fsql = "select _id, name from functions where _id in (".join(",", keys %funcs).")";
          %$fmap = map { $_->[0], $_->[1] } @{ $self->dbh->selectall_arrayref($fsql) };
      }
      map { $_->[2] = ($_->[2] && exists($fmap->{$_->[2]})) ? $fmap->{$_->[2]} : 'unknown' } @$rows;
      return $rows
  } else {
      return [];
  }
}

sub md52org {
  my ($self, $md5) = @_;
  return $self->md5s2organisms([$md5]);
}

sub md5s2organisms {
  my ($self, $md5s) = @_;

  my $list = join(",", map {$self->dbh->quote($_)} @$md5s);
  my $statement = "select o.name, d.md5 from md5_protein d, organisms_ncbi o where d.md5 in ($list) and d.organism = o._id";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub md5s2organisms_unique {
  my ($self, $md5s, $source) = @_;

  my $data = {};
  my $size = 10000;
  my $iter = natatime $size, @$md5s;

  while (my @curr = $iter->()) {
    my $list = join(",", map {$self->dbh->quote($_)} @curr);
    my $sql  = "select md5, organism from md5_organism_unique where md5 in ($list) and source = ".$self->dbh->quote($source);
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
      map { $data->{$_->[0]} = $_->[1] } @$rows;
    }
  }
  return $data;
  # md5 => organism
}

sub md52taxonomy {
  my ($self, $md5s , $source) = @_;

  unless($source and $source =~/\d+/){
    my $s =  $self->sources->{$source} ;
    $source =  ref $s ?  $s->{_id} : 0 ; 
  }

  my $list = join(",", map {$self->dbh->quote($_)} @$md5s);
  my $sql  = qq(select distinct p.md5, o.tax_domain, o.tax_phylum, o.tax_class, o.tax_order, o.tax_family, o.tax_genus, o.tax_species, o.name , p.source
                from organisms_ncbi o, md5_protein p where p.organism = o._id and p.md5 in ($list) order by p.md5 , o.tax_domain );

  $sql  = qq(select distinct p.md5, o.tax_domain, o.tax_phylum, o.tax_class, o.tax_order, o.tax_family, o.tax_genus, o.tax_species, o.name , p.source
                from organisms_ncbi o, md5_protein p where p.organism = o._id and p.md5 in ($list) and p.source = $source order by p.md5 , o.tax_domain ) if ($source);

  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub md52id4source {
  my ($self, $md5, $source) = @_;
  return $self->md5s2ids4source([$md5]);
}

sub md5s2ids4source {
  my ($self, $md5s, $source) = @_;
  
  my $srcs = $self->sources;
  unless (ref($md5s) && (scalar @$md5s) && $source) {
    return [];
  }
  unless ($srcs->{$source} && ($srcs->{$source}{type} =~ /^(protein|rna|ontology)$/)) {
    return [];
  }

  my $sid  = $srcs->{$source}{_id};
  my $data = [];
  my $size = 10000;
  my $iter = natatime $size, @$md5s;

  while (my @curr = $iter->()) {
    my $list = join(",", map {$self->dbh->quote($_)} @curr);
    my $sql  = "select id, md5 from md5_".$srcs->{$source}{type}." where md5 in ($list) and source = $sid";
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
      push @$data, @$rows;
    }
  }
  return $data;
  # [ id, md5 ]
}

sub md5s2sets4source {
  my ($self, $md5s, $source) = @_;

  unless (ref($md5s) && (scalar @$md5s) && $source) {
    return [];
  }

  my $sql  = '';
  my $srcs = $self->sources;
  
  if ($srcs->{$source} && ($srcs->{$source}{type} eq 'ontology')) {
    $sql = "select d.id, d.md5, f.name from md5_ontology d, functions f, sources s " .
           "where d.function = f._id and d.source = s._id and s.name = '$source'";
  }
  elsif ($srcs->{$source} && ($srcs->{$source}{type} =~ /^(protein|rna)$/)) {
    $sql = "select d.id, d.md5, f.name, o.name from md5_".$srcs->{$source}{type}." d, functions f, organisms_ncbi o, sources s " .
           "where d.function = f._id and d.organism = o._id and d.source = s._id and s.name = '$source'";
  }
  else {
    return [];
  }
  if (@$md5s == 1) {
    $sql .= " and d.md5 = " . $self->dbh->quote($md5s->[0]);
  } else {
    $sql .= " and d.md5 in (" . join(",", map {$self->dbh->quote($_)} @$md5s) . ")";
  }
  
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub md52sequence {
  my ($self, $md5) = @_;

  my $nr   = $self->nr;
  my $seq  = '';
  my @recs = `fastacmd -d $nr -s \"lcl|$md5\" -l 0 2>&1`;
  if ((@recs < 2) || (! $recs[0]) || ($recs[0] =~ /^\s+$/) || ($recs[0] =~ /^\[fastacmd\]/)) {
    return "";
  }
  return $recs[1];
}

sub md5s2sequences {
  my ($self, $md5s, $obj) = @_;

  my $nr   = $self->nr;
  my $seqs = '';
  my $list = join(",", map { (/^\d+$/) ? "lcl|$_" : $_ } @$md5s);
  my @recs = `fastacmd -d $nr -s \"$list\" -l 0 2>&1`;

  foreach (@recs) {
    if ((! $_) || ($_ =~ /^\s+$/) || ($_ =~ /^\[fastacmd\]/)) { next; }
    $seqs .= $_;
  }
  if ($obj) {
    my @fasta = split(/\n/, $seqs);
    my $seq_set = [];
    for (my $i=0; $i<@fasta; $i += 2) {
        if ($fasta[$i] =~ /^>(\S+)/) {
            my $id = $1;
            $id    =~ s/^lcl\|//;
            push @$seq_set, [ $id, $fasta[$i+1] ];
        }
    }
     return $seq_set;
  }
  return $seqs || $list;
}

sub md5s2ontologyset {
  my ($self, $md5s) = @_;

  unless (ref($md5s) && (scalar @$md5s)) {
    return [];
  }

  my $sql = qq(select o.id, o.md5, f.name, s.name
               from md5_ontology o, functions f, sources s
               where o.function = f._id and o.source = s._id);
  if (@$md5s == 1) {
    $sql .= " and o.md5 = '" . $md5s->[0] . "'";
  } else {
    $sql .= " and o.md5 in (" . join(",", map {$self->dbh->quote($_)} @$md5s) . ")";
  }
  
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && ref($rows)) ? $rows : [];
}

#
# ontology section
#

sub get_ontology_table {
  my ($self, $source) = @_;

  my $sources = $self->sources4type('ontology');
  if (exists $sources->{$source}) {
    return lc('ontology_' . $sources->{$source}->{source});
  } else {
    return '';
  }
}

sub get_ontology4source {
  my ($self, $id, $source) = @_;

  my $hash = $self->get_ontology4source_hash([$id], $source);
  return (exists $hash->{$id}) ? $hash->{$id} : [];
}

sub get_ontology4source_hash {
  my ($self, $ids, $source) = @_;

  my $table = $self->get_ontology_table($source);
  unless ($table && $ids && (@$ids > 0)) { return {}; }

  my $data = {};
  my $cols = $self->get_columns4table($table);
  my $sql  = "select " . join(",", ('id', grep {$_ =~ /^level/} @$cols)) . " from $table where id in (" . join(",", map {$self->dbh->quote($_)} @$ids) . ")";
  if ($table =~ /eggnog$/i) {
    $sql .= " and type = '$source'";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows) {
    foreach my $r (@$rows) {
      my $id = shift @$r;
      $data->{$id} = $r;
    }
  }
  return $data;
}

sub get_all_ontology4source_hash {
  my ($self, $source) = @_;

  my $table = $self->get_ontology_table($source);
  unless ($table) { return {}; }

  my $data = {};
  my $cols = $self->get_columns4table($table);
  my $sql  = "select " . join(",", ('id', grep {$_ =~ /^level/} @$cols)) . " from $table";
  if ($table =~ /eggnog$/i) {
    $sql .= " where type = '$source'";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows) {
    foreach my $r (@$rows) {
      my $id = shift @$r;
      $data->{$id} = $r;
    }
  }
  return $data;
}

sub subsystem_hash {
  my ($self) = @_;
  return $self->get_all_ontology4source_hash("Subsystems");
}

sub kegg_hash {
  my ($self) = @_;
  return $self->get_all_ontology4source_hash("KO");
}

sub cog_hash {
  my ($self) = @_;
  return $self->get_all_ontology4source_hash("COG");
}

sub nog_hash {
  my ($self) = @_;
  return $self->get_all_ontology4source_hash("NOG");
}

sub get_level4ontology {
  my ($self, $source, $level) = @_;

  my $table = $self->get_ontology_table($source);
  unless ($table) { return []; }

  my $list = [];
  my @cols = grep { $_ eq $level } @{ $self->get_columns4table($table) };
  if (@cols == 1) {
    my $rows = $self->dbh->selectcol_arrayref("SELECT $level FROM $table");
    if ($rows && (@$rows > 0)) {
      my %uniq = map { $_, 1 } grep { $_ && ($_ =~ /\S/) } @$rows;
      @$list   = sort keys %uniq;
    }
  }
  return $list;
}

sub get_level4ontology_full {
  my ($self, $source, $level, $no_join) = @_;
  
  my $table = $self->get_ontology_table($source);
  unless ($table) { return []; }
  
  my $sets = {};
  my @cols = ();
  my $hasl = 0;
  
  foreach my $col ( sort grep {$_ =~ /^level/} @{$self->get_columns4table($table)} ) {
    if ($col ne $level) {
      push @cols, $col;
    }
    else {
      push @cols, $col;
      $hasl = 1;
      last;
    }
  }

  if ($hasl && scalar(@cols)) {
    my $rows = $self->dbh->selectall_arrayref("SELECT DISTINCT ".join(", ", @cols)." FROM $table");
    if ($rows && (@$rows > 0)) {
      if ($no_join) {
	map { $sets->{$_->[-1]} = $_ } grep { $_->[-1] && ($_->[-1] =~ /\S/) } @$rows;
      } else {
	map { $sets->{$_->[-1]} = join(";", @$_) } grep { $_->[-1] && ($_->[-1] =~ /\S/) } @$rows;
      }
    }
  }
  return $sets;
}

sub get_ids4level {
  my ($self, $source, $level, $names) = @_;

  my $table = $self->get_ontology_table($source);
  unless ($table) { return {}; }

  my $ids   = {};
  my $where = ($names && (@$names > 0)) ? " where $level in (" . join(",", map {$self->dbh->quote($_)} @$names) . ")" : "";
  my @cols  = grep { $_ eq $level } @{ $self->get_columns4table($table) };

  if (@cols == 1) {
    my $rows = $self->dbh->selectall_arrayref("SELECT distinct id, $level FROM $table" . $where);
    if ($rows && (@$rows > 0)) {
      %$ids = map { $_->[0], $_->[1] } grep { $_->[1] && ($_->[1] =~ /\S/) } @$rows;
    }
  }
  return $ids;
}

#
# org2... section
#

sub org2md5 {
  my ($self, $org, $regexp) = @_;

  $org =~ s/'/\\'/g;
  my $statement = "select d.md5, o.name from md5_protein d, organisms_ncbi o where o._id = d.organism";

  if ($regexp) {
    $org =~ s/\|/\\\\\|/g;
    $statement .= " and o.name ~* '$org'";
  }
  else {
    $statement .= " and o.name = '$org'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub organisms2md5s {
  my ($self, $orgs) = @_;
  
  my $list = join(",", map {$self->dbh->quote($_)} @$orgs);
  my $statement = "select d.md5, o.name from organisms_ncbi o, md5_protein d where o.name in ($list) and d.organism = o._id";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}


sub org2id {
  my ($self, $org, $regexp) = @_;

  $org =~ s/'/\\'/g;
  my $statement = "select d.id, o.name from md5_protein d, organisms_ncbi o where o._id = d.organism";

  if ($regexp) {
    $org =~ s/\|/\\\\\|/g;
    $statement .= " and o.name ~* '$org'";
  }
  else {
    $statement .= " and o.name = '$org'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub org2function {
  my ($self, $org, $regexp) = @_;

  $org =~ s/'/\\'/g;
  my $statement = "select f.name, o.name from md5_protein d, organisms_ncbi o, functions f where o._id = d.organism and f._id = d.function";

  if ($regexp) {
    $org =~ s/\|/\\\\\|/g;
    $statement .= " and o.name ~* '$org'";
  }
  else {
    $statement .= " and o.name = '$org'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub organisms2sets {
  my ($self, $orgs, $regex) = @_;
  
  my $sql = qq(select d.id, d.md5, f.name, o.name, s.name
               from md5_protein d, functions f, organisms_ncbi o, sources s
               where d.function = f._id and d.organism = o._id and d.source = s._id);
  if ($regex) {
    $sql .= " and (" . join(" or ", map {"o.name ~* " . $self->dbh->quote($_)} @$orgs) . ")";
  } elsif (@$orgs == 1) {
    $sql .= " and o.name = " . $self->dbh->quote($orgs->[0]);
  } else {
    $sql .= " and o.name in (" . join(",", map {$self->dbh->quote($_)} @$orgs) . ")";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && ref($rows)) ? $rows : [];
}

sub org2contignum {
  my ($self, $org, $len) = @_;

  my $sql;
  if ($org =~ /^\d+$/) {
    $sql = "select count(c.name) from contigs c where c.organism = $org";
  } else {
    $sql = "select count(c.name) from contigs c, organisms_ncbi o where o._id = c.organism and o.name = " . $self->dbh->quote($org);
  }
  if ($len && ($len =~ /^\d+$/)) {
    $sql .= " and c.length > $len";
  }
  my $rows = $self->dbh->selectcol_arrayref($sql);
  return ($rows && (@$rows == 1)) ? $rows->[0] : 0;
}

sub org2contigs {
  my ($self, $org) = @_;

  my $sql;
  if ($org =~ /^\d+$/) {
    $sql = "select name, length from contigs where organism = $org";
  } else {
    $sql = "select c.name, c.length from contigs c, organisms_ncbi o where o._id = c.organism and o.name = " . $self->dbh->quote($org);
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub org2contig_data {
  my ($self, $org, $get_func) = @_;

  my $sql;
  # org is index, return md5 as index
  if ($org =~ /^\d+$/) {
    if ($get_func) {
      $sql = qq(select c.name, m._id, d.id, f.name, ic.low, ic.high, ic.strand, c.length
                from id2contig ic, contigs c, md5_protein d, md5s m, functions f
                where (ic.id=d.id) and (ic.contig=c._id) and (c.organism=$org) and (m.md5=d.md5) and (d.function=f._id) order by c.name, ic.low);
    } else {
      $sql = qq(select c.name, m._id, d.id, ic.low, ic.high, ic.strand, c.length
                from id2contig ic, contigs c, md5_protein d, md5s m
                where (ic.id=d.id) and (ic.contig=c._id) and (c.organism=$org) and (m.md5=d.md5) order by c.name, ic.low);
    }
  # org is text, return md5 as text
  } else {
    my $qorg = $self->dbh->quote($org);
    if ($get_func) {
      $sql = qq(select c.name, d.md5, d.id, f.name, ic.low, ic.high, ic.strand, c.length
                from id2contig ic, contigs c, organisms_ncbi o, md5_protein d, functions f
                where (ic.id=d.id) and (ic.contig=c._id) and (c.organism=o._id) and (o.name=$qorg) and (d.function=f._id) order by c.name, ic.low);
    } else {
      $sql = qq(select c.name, d.md5, d.id, ic.low, ic.high, ic.strand, c.length
                from id2contig ic, contigs c, organisms_ncbi o, md5_protein d
                where (ic.id=d.id) and (ic.contig=c._id) and (c.organism=o._id) and (o.name=$qorg) order by c.name, ic.low);
    }
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub organism {
  my ($self, $org, $regexp) = @_;
 
  my $rows;
  my $qorg = $org;
  if ($regexp) {
    $qorg =~ s/'/\\'/g;
    $qorg =~ s/\|/\\\\\|/g;
    $rows = $self->dbh->selectcol_arrayref("select organisms_ncbi.name from organisms_ncbi where organisms_ncbi.name ~* '$qorg'");
  }
  return ($rows && (@$rows > 0)) ? $rows : [$org];
}

sub get_organism_from_index {
  my ($self, $id) = @_;

  my $rows = $self->dbh->selectcol_arrayref("select name from organisms_ncbi where _id = $id");
  return ($rows && (@$rows == 1)) ? $rows->[0] : '';
}

sub get_organism_list {
  my ($self) = @_;
 
  my $rows = $self->dbh->selectcol_arrayref("select name from organisms_ncbi group by name");
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub get_organism_with_contig_list {
  my ($self, $num, $len) = @_;

  my $sql = "select o._id, o.name from organisms_ncbi o, contigs c where o._id = c.organism";
  if ($len && ($len =~ /^\d+$/)) {
    $sql .= " and c.length > $len";
  }
  $sql .= " group by o._id, o.name";
  if ($num && ($num =~ /^\d+$/)) {
    $sql .= " having count(c.name) < $num";
  }

  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub get_organism_info {
  my ($self, $org, $regexp) = @_;
 
  $org =~ s/'/\\'/g;
  my $statement = "select ncbi_tax_id, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name from organisms_ncbi where ";

  if ($regexp) {
    $org =~ s/\|/\\\\\|/g;
    $statement .= "name ~* '$org'";
  }
  else {
    $statement .= "name = '$org'";
  }
  my $rows = $self->dbh->selectrow_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub get_taxonomy4taxids {
  my ($self, $tax_ids) = @_;

  unless ($tax_ids && (@$tax_ids > 0)) { return {}; }
  my $data = {};
  my $list = join(",", @$tax_ids);
  my $sql  = "select ncbi_tax_id,tax_domain,tax_phylum,tax_class,tax_order,tax_family,tax_genus,tax_species,name from organisms_ncbi where ncbi_tax_id in ($list)";
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], [ @$_[1..8] ] } @$rows;
  }
  return $data;
}

sub get_taxonomy4orgs {
  my ($self, $orgs) = @_;

  unless ($orgs && (@$orgs > 0)) { return {}; }
  my $data = {};
  my $list = join(",", map {$self->dbh->quote($_)} @$orgs);
  my $sql  = "select name,tax_domain,tax_phylum,tax_class,tax_order,tax_family,tax_genus,tax_species from organisms_ncbi where name in ($list) and ncbi_tax_id is not NULL";
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], [ @$_[1..7] ] } @$rows;
  }
  return $data;
}

sub get_organisms4taxids {
  my ($self, $tax_ids) = @_;

  unless ($tax_ids && (@$tax_ids > 0)) { return []; }
  my $list = join(",", grep {$_ =~ /^\d+$/} @$tax_ids);
  my $rows = $self->dbh->selectcol_arrayref("SELECT name FROM organisms_ncbi WHERE ncbi_tax_id in ($list)");
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub get_organism_tax_id {
  my ($self, $org) = @_;

  my $qorg = $self->dbh->quote($org);
  my $rows = $self->dbh->selectcol_arrayref("SELECT ncbi_tax_id FROM organisms_ncbi WHERE name = $qorg");
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub map_organism_tax_id {
  my ($self) = @_;
  my $data = {};
  my $rows = $self->dbh->selectall_arrayref("SELECT name, ncbi_tax_id FROM organisms_ncbi");
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], $_->[1] } grep { $_->[1] } @$rows;
  }
  return $data;
}

sub get_taxonomy4level {
  my ($self, $level) = @_;

  my $list = [];
  my @cols = grep { $_ eq $level } @{ $self->get_columns4table("organisms_ncbi") };
  if (@cols == 1) {
    my $rows = $self->dbh->selectcol_arrayref("SELECT $level FROM organisms_ncbi");
    if ($rows && (@$rows > 0)) {
      my %uniq = map { $_, 1 } grep { $_ && ($_ =~ /\S/) } @$rows;
      @$list   = sort keys %uniq;
    }
  }
  return $list;
}

sub get_taxonomy4level_full {
  my ($self, $level, $no_join) = @_;
    
  my $sets = {};
  my @cols = ();
  my $hasl = 0;
  
  foreach my $col ( grep {$_ =~ /^tax_/} @{$self->get_columns4table("organisms_ncbi")} ) {
    next if ($col eq 'tax_kingdom');
    if ($col ne $level) {
      push @cols, $col;
    }
    else {
      push @cols, $col;
      $hasl = 1;
      last;
    }
  }

  if ($hasl && scalar(@cols)) {
    my $rows = $self->dbh->selectall_arrayref("SELECT DISTINCT ".join(", ", @cols)." FROM organisms_ncbi");
    if ($rows && (@$rows > 0)) {
      if ($no_join) {
	map { $sets->{$_->[-1]} = $_ } grep { $_->[-1] && ($_->[-1] =~ /\S/) } @$rows;
      } else {
	map { $sets->{$_->[-1]} = join(";", @$_) } grep { $_->[-1] && ($_->[-1] =~ /\S/) } @$rows;
      }
    }
  }
  return $sets;
}

sub get_organisms4level {
  my ($self, $level, $names) = @_;

  my $orgs  = {};
  my $where = ($names && (@$names > 0)) ? " where $level in (" . join(",", map {$self->dbh->quote($_)} @$names) . ")" : "";
  my @cols  = grep { $_ eq $level } @{ $self->get_columns4table("organisms_ncbi") };

  if (@cols == 1) {
    my $rows = $self->dbh->selectall_arrayref("SELECT distinct name, $level FROM organisms_ncbi" . $where);
    if ($rows && (@$rows > 0)) {
      %$orgs = map { $_->[0], $_->[1] } grep { $_->[1] && ($_->[1] =~ /\S/) } @$rows;
    }
  }
  return $orgs;
}

#
# contig2.. section
#

sub get_contig_count_4_organism {
  my ($self, $org) = @_;

  my $sql;
  if ($org =~ /^\d+$/) {
    $sql = "select count(name) from contigs where organism = $org";
  } else {
    $sql = "select count(c.name) from contigs c, organisms_ncbi o where o._id=c.organism and o.name = " . $self->dbh->quote($org);
  }
  my $rows = $self->dbh->selectcol_arrayref($sql);
  return ($rows && (@$rows == 1)) ? $rows->[0] : 0;
}

sub contig2locs {
  my ($self, $contig) = @_;

  my $qctg = $self->dbh->quote($contig);
  my $sql  = "select ic.low, ic.high, ic.strand from id2contig ic, contigs c where ic.contig = c._id and c.name = $qctg order by ic.low";
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

#
# function2... section
#

sub function2md5 {
  my ($self, $func, $regexp) = @_;
 
  $func =~ s/'/\\'/g;
  my $statement = "select f.name, d.md5 from functions f, md5_protein d where d.function = functions._id";
 
  if ($regexp) {
    $func =~s/\|/\\\\\|/g;
    $statement .= " and f.name ~* '$func'";
  }
  else {
    $statement .= " and f.name = '$func'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub functions2md5s {
  my ($self, $funcs, $regexp) = @_;
  
  my $list = join(",", map {$self->dbh->quote($_)} @$funcs);
  my $statement = "select d.md5, f.name from functions f, md5_protein d where f.name in ($list) and d.function = f._id";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub functions2sets {
  my ($self, $funcs, $regex) = @_;

  my $sql = qq(select d.id, d.md5, f.name, o.name, s.name
               from md5_protein d, functions f, organisms_ncbi o, sources s
               where d.function = f._id and d.organism = o._id and d.source = s._id);
  if ($regex) {
    $sql .= " and (" . join(" or ", map {"f.name ~* " . $self->dbh->quote($_)} @$funcs) . ")";
  } elsif (@$funcs == 1) {
    $sql .= " and f.name = " . $self->dbh->quote($funcs->[0]);
  } else {
    $sql .= " and f.name in (" . join(",", map {$self->dbh->quote($_)} @$funcs) . ")";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && ref($rows)) ? $rows : [];
}

sub function2id {
   my ($self, $func, $regexp) = @_;

   $func =~ s/'/\\'/g;
   my $statement = "select d.id, f.name from md5_protein d, functions f where f._id = d.function";
   if ($regexp) {
     $func =~s/\|/\\\\\|/g;
     $statement .= " and fs.name ~* '$func'";
   }
   else {
     $statement .= " and f.name = '$func'";
   }
   my $rows = $self->dbh->selectall_arrayref($statement);
   return ($rows && ref($rows)) ? $rows : [];
}

sub function2org {
  my ($self, $func, $regexp) = @_;
  
  $func =~s/'/\\'/g;
  my $statement = "select o.name, f.name from md5_protein d, organisms_ncbi o, functions f where o._id = d.organism and f._id = d.function";

  if ($regexp) {
    $func =~ s/\|/\\\\\|/g;
    $statement .= " and f.name ~* '$func'";
  }
  else {
    $statement .= " and f.name = '$func'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub function {
  my ($self, $func, $regexp) = @_;
 
  my $rows;
  my $qfunc = $func;
  if ($regexp) {
    $qfunc =~ s/'/\\'/g;
    $qfunc =~ s/\|/\\\\\|/g;
    $rows = $self->dbh->selectcol_arrayref("select name from functions where name ~* '$qfunc'");
  }
  return ($rows && (@$rows > 0)) ? $rows : [$func];
}

sub get_function_list {
  my ($self, $source) = @_;
 
  my $sql  = "select name from functions";
  my $rows = $self->dbh->selectcol_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub get_function_set_4_source {
  my ($self, $source) = @_;
 
  my %func = ();
  my $qsrc = $self->dbh->quote($source);
  my $sql  = "select d.md5, f.name, d.function from functions f, md5_protein d, sources s where f._id = d.function and s._id = d.source and s.name = $qsrc";
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

# id2... Section

sub id2org {
  my ($self, $id, $regexp) = @_;

  $id =~s/'/\\'/g;
  my $statement = "select o.name, d.id from md5_protein d, organisms_ncbi o where o._id = d.organism";
  if ($regexp) {
    $id =~s/\|/\\\\\|/g;
    $statement .= " and d.id ~* '$id'";
  }
  else {
    $statement .= " and d.id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub id2md5 {
  my ($self, $id, $regexp) = @_;
 
  $id =~ s/'/\\'/g;
  my $statement = "select md5, id from md5_protein";
 
  if ($regexp) {
    $id =~ s/\|/\\\\\|/g;
    $statement .= " where id ~* '$id'";
  }
  else {
    $statement .= " where id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub ids2md5s {
  my ($self, $ids) = @_;

  my $list = join(",", map {$self->dbh->quote($_)} @$ids);
  my $statement = "select md5, id from md5_protein where id in ($list)";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub id2function {
  my ($self, $id, $regexp) = @_;

  $id =~ s/'/\\'/g;
  my $statement = "select f.name, d.id from md5_protein d, functions f where f._id = d.function";

  if ($regexp) {
    $id =~ s/\|/\\\\\|/g;
    $statement .= " and d.id ~* '$id'";
  }
  else {
    $statement .= " and d.id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub ids2function {
  my ($self, $ids) = @_;

  my $list = join(",", map {$self->dbh->quote($_)} @$ids);
  my $statement = "select f.name, d.id from md5_protein d, functions f where d.id in ($list) and d.function=f._id";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub id2function_organism {
  my ($self, $id, $regexp) = @_;

  $id =~ s/'/\\'/g;
  my $statement = "select f.name, o.name, d.id from md5_protein d, functions f, organisms_ncbi o where f._id = d.function and o._id = d.organism";

  if ($regexp) {
    $id =~ s/\|/\\\\\|/g;
    $statement .= " and d.id ~* '$id'";
  }
  else {
    $statement .= " and d.id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub id {
  my ($self, $id, $regexp) = @_;

  my $rows;
  my $qid = $id;
  if ($regexp) {
    $id =~ s/'/\\'/g;
    $id =~ s/\|/\\\\\|/g;
    $rows = $self->dbh->selectcol_arrayref("select id from md5_protein where id ~* '$qid'");
  }
  return ($rows && (@$rows > 0)) ? $rows : [$id];
}

sub id2set {
  my ($self, $id, $regexp) = @_;

  $id =~ s/'/\\'/g;
  my $sql = qq(select d.id, d.md5, f.name, o.name, s.name
               from md5_protein d, functions f, organisms_ncbi o, sources s
               where d.function = f._id and d.organism = o._id and d.source = s._id);
  if ($regexp) {
    $sql .= " and d.id ~* '$id'";
  } else {
    $sql .= " and d.id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && ref($rows)) ? $rows : [];
}

sub ids2sets {
  my ($self, $ids) = @_;
  
  my $sql = qq(select d.id, d.md5, f.name, o.name, s.name
               from md5_protein d, functions f, organisms_ncbi o, sources s
               where d.function = f._id and d.organism = o._id and d.source = s._id);
  if (@$ids == 1) {
    $sql .= " and d.id = " . $self->dbh->quote($ids->[0]);
  } else {
    $sql .= " and d.id in (" . join(",", map {$self->dbh->quote($_)} @$ids) . ")";
  }
  my $rows = $self->dbh->selectall_arrayref($sql);
  return ($rows && ref($rows)) ? $rows : [];
}

sub ids2organisms {
  my ($self, $ids) = @_;
  
  my $list = join(",", map {$self->dbh->quote($_)} @$ids);
  my $statement = "select o.name, d.md5 from md5_protein d, organisms_ncbi o where d.id in ($list) and d.organism = o._id";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub id2id4source {
  my ($self, $id, $source, $regexp) = @_;
  
  $id =~ s/'/\\'/g;
  my $statement = "select d.id, d.md5 from md5_protein d, sources s where d.source = s._id and s.name='$source'";

  if ($regexp) {
    $statement .= " and d.id ~* '$id'";
  } else {
    $statement .= " and d.id = '$id'";
  }
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub id2sequence {
  my ($self, $id) = @_;

  my $set = $self->id2md5($id);
  my $md5 = $set->[0][0];
  return $self->md52sequence($md5);
}

sub ids2sequences {
  my ($self, $ids, $obj) = @_;

  my $md5seq = {};
  my $md5id  = $self->ids2md5s($ids);
  my %md5s   = map { $_->[0], 1 } @$md5id;
  my @fasta  = split(/\n/, $self->md5s2sequences( [keys %md5s] ));

  for (my $i=0; $i<@fasta; $i += 2) {
    if ($fasta[$i] =~ /^>(\S+)/) {
      my $id = $1;
      $id    =~ s/^lcl\|//;
      $md5seq->{$id} = $fasta[$i+1];
    }
  }
  my @seq_set = map { [$_->[1], $md5seq->{$_->[0]}] } grep { exists($md5seq->{$_->[0]}) } @$md5id;
  if ($obj) {
      return \@seq_set;
  } else {
      return join("\n", map { ">".$_->[0]."\n".$_->[1] } @seq_set)."\n";
  }
}

#
# SOURCE part
#

sub download_info_from_file {
  my ($self, $dfile) = @_;

  unless ($dfile && (-s $dfile)) { return {}; }

  my %sources = ();
  open(DFILE, "<$dfile") || return {};
  while (my $line = <DFILE>) {
    chomp $line;
    my ($name, $path, $file, $date) = split(/\t/, $line);

    if ($name && $path && $date) {
      push @{ $sources{$name} }, {download_path => $path, download_file => $file, download_date => $date};
    }
  }
  close DFILE;

  return \%sources;
}

sub source_info_from_file {
  my ($self, $sfile) = @_;

  unless ($sfile && (-s $sfile)) { return {}; }

  my %sources = ();
  open(SFILE, "<$sfile") || return {};
  while (my $line = <SFILE>) {
    chomp $line;
    my ($name, $source, $version, $desc, $title, $type, $url, $link) = split(/\t/, $line);

    if (! $title) { $title = $desc; }
    if ($name && $source && $type && $url) {
      $sources{$name} = {source => $source, version => $version, description => $desc, type => $type, url => $url, title => $title, link => $link};
    }
  }
  close SFILE;

  return \%sources;
}

sub source2ids {
  my ($self, $source) = @_;
 
  my $statement = "select distinct d.id from md5_protein d, sources s where d.source=s._id and s.name='$source'";
  my $rows = $self->dbh->selectcol_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub source2md5s {
  my ($self, $source) = @_;
 
  my $statement = "select distinct d.md5 from md5_protein d, sources s where d.source=s._id and s.name='$source'";
  my $rows = $self->dbh->selectcol_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub source2sets {
  my ($self, $source) = @_;
 
  my $statement = "select d.id, d.md5, f.name from md5_protein d, sources s, functions f where d.source=s._id and s.name='$source' and f._id=d.function";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && ref($rows)) ? $rows : [];
}

sub sources {
  my ($self) = @_;
  
  my $statement = "select * from sources"; 
  my $hash = $self->dbh->selectall_hashref($statement , "name");
  return ($hash && ref($hash)) ? $hash : {};
}

sub get_source_links {
  my ($self, $sources) = @_;

  my $data = {};
  my $srcs = join(",", map {$self->dbh->quote($_)} @$sources);
  my $rows = $self->dbh->selectall_arrayref("select name, link from sources where name in ($srcs)");
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], $_->[1] } grep { $_->[1] } @$rows;
  }
  return $data;
}

sub get_protein_sources {
  my ($self) = @_;

  my $sources = $self->sources4type("protein");
  my @result  = map { [$_->{name}, $_->{description}] } values %$sources;
  return \@result;
}

sub get_rna_sources {
  my ($self) = @_;

  my $sources = $self->sources4type("rna");
  my @result  = map { [$_->{name}, $_->{description}] } values %$sources;
  return \@result;
}

sub get_ontology_sources {
  my ($self) = @_;

  my $sources = $self->sources4type("ontology");
  my @result  = map { [$_->{name}, $_->{description}] } values %$sources;
  return \@result;
}

sub types4sources {
  my ($self, $sources) = @_;

  my $data = {};
  my $srcs = join(",", map {$self->dbh->quote($_)} @$sources);
  my $rows = $self->dbh->selectall_arrayref("select type, name from sources where name in ($srcs)");
  if ($rows && (@$rows > 0)) {
    foreach (@$rows) { push @{ $data->{$_->[0]} }, $_->[1]; }
  }
  return $data;
}

sub sources4type {
  my ($self, $type) = @_;

  my $statement = "select * from sources";
  if ($type) { $statement .= " where type = '$type'"; }

  my $hash = $self->dbh->selectall_hashref($statement , "name");
  return ($hash && ref($hash)) ? $hash : {};
}

sub is_source {
  my ($self, $id) = @_;

  unless ($id) { return 0; }
  my $statement = "select count(*) from sources where _id = $id";
  my $rows = $self->dbh->selectcol_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub source_stats4md5 {
  my ($self) = @_;

  my $statement = qq(SELECT source, COUNT(md5) FROM (
SELECT DISTINCT source, md5 FROM md5_protein UNION
SELECT DISTINCT source, md5 FROM md5_ontology UNION
SELECT DISTINCT source, md5 FROM md5_rna ) AS x GROUP BY source);

  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4md5uniq {
  my ($self) = @_;

  my $data = [];
  foreach my $tbl (('md5_protein', 'md5_ontology', 'md5_rna')) {
    my $sql = qq(SELECT source, COUNT(DISTINCT md5) FROM $tbl WHERE md5 IN (
SELECT md5 FROM (SELECT md5, COUNT(source) AS num FROM (SELECT DISTINCT md5, source FROM $tbl) AS x GROUP BY md5) AS y WHERE num=1) GROUP BY source);
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
      foreach (@$rows) { push @$data, $_; }
    }
  }
  return $data;
}

sub source_stats4pid {
  my ($self) = @_;

  my $statement = "select source, count(distinct id) from md5_protein group by source";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4oid {
  my ($self) = @_;

  my $statement = "select source, count(distinct id) from md5_ontology group by source";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4rid {
  my ($self) = @_;

  my $statement = "select source, count(distinct id) from md5_rna group by source";
  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4func {
  my ($self) = @_;
  
  my $statement = qq(SELECT source, COUNT(function) FROM (
SELECT DISTINCT source, function FROM md5_protein UNION
SELECT DISTINCT source, function FROM md5_ontology UNION
SELECT DISTINCT source, function FROM md5_rna ) AS x GROUP BY source);

  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4org {
  my ($self) = @_;

  my $statement = qq(SELECT source, COUNT(organism) FROM (
SELECT DISTINCT source, organism FROM md5_protein UNION
SELECT DISTINCT source, organism FROM md5_rna ) AS x GROUP BY source);

  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4org_tax {
  my ($self) = @_;

  my $statement = qq(SELECT x.source, COUNT(o._id) FROM (
SELECT DISTINCT source, organism FROM md5_protein UNION
SELECT DISTINCT source, organism FROM md5_rna ) AS x, organisms_ncbi o
WHERE x.organism = o._id AND o.ncbi_tax_id IS NOT NULL GROUP BY x.source);

  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

sub source_stats4contig {
  my ($self) = @_;

  my $statement = qq(SELECT x.source, COUNT(distinct i.contig) FROM (
SELECT DISTINCT source, id FROM md5_protein ) AS x, id2contig i
WHERE x.id = i.id GROUP BY x.source);

  my $rows = $self->dbh->selectall_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows : [];
}

#
# Sequence
#

sub sequence2md5 {
  my ($self, $sequence) = @_;
  
  $sequence =~ s/\s+//sg;
  my $md5 = Digest::MD5::md5_hex( uc $sequence );
  return $md5;
}

sub sequence2set {
  my ($self, $sequence) = @_;
  my $md5 = $self->sequence2md5($sequence);
  return $self->md52set($md5);
}

#
# get counts
#

sub get_total_count {
  my ($self, $type) = @_;

  my $statement = "select count from counts where type='$type'";
  my $rows = $self->dbh->selectcol_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub get_source_count {
  my ($self, $type, $src) = @_;

  my $statement = "select $type from sources where name='$src'";
  my $rows = $self->dbh->selectcol_arrayref($statement);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub count4md5s4source {
  my ($self, $source, $type) = @_;

  if ($type && ($type =~ /^uniq$/i)) {
    return $self->get_source_count('uniq_md5s', $source);
  } else {
    return $self->get_source_count('md5s', $source);
  }
}

sub count4md5s {
  my ($self, $type) = @_;

  if ($type && ($type =~ /^protein$/i)) {
    return $self->get_total_count('protein_md5s');
  }
  elsif ($type && ($type =~ /^rna$/i)) {
    return $self->get_total_count('rna_md5s');
  }
  else {
    return $self->get_total_count('md5s');
  }
}

sub count4ids4source {
  my ($self, $source, $type) = @_;

  if ($type && ($type =~ /^protein$/i)) {
    return $self->get_source_count('protein_ids', $source);
  }
  elsif ($type && ($type =~ /^ontology$/i)) {
    return $self->get_source_count('ontology_ids', $source);
  }
  elsif ($type && ($type =~ /^rna$/i)) {
    return $self->get_source_count('rna_ids', $source);
  }
  else {
    return 0;
  }
}

sub count4ids {
  my ($self, $type) = @_;

  if ($type && ($type =~ /^protein$/i)) {
    return $self->get_total_count('protein_ids');
  }
  elsif ($type && ($type =~ /^ontology$/i)) {
    return $self->get_total_count('ontology_ids');
  }
  elsif ($type && ($type =~ /^rna$/i)) {
    return $self->get_total_count('rna_ids');
  }
  else {
    return 0;
  }
}

sub count4functions4source {
   my ($self, $source) = @_;
   return $self->get_source_count('functions', $source);
}

sub count4functions {
  my ($self) = @_;
  return $self->get_total_count('functions');
}

sub count4organisms4source {
  my ($self, $source) = @_;
  return $self->get_source_count('organisms', $source);
}

sub count4organisms {
  my ($self) = @_;
  return $self->get_total_count('organisms');
}

#############################
# analysis
#############################

=item * B<lca> ()

Computes the LCA (lowest common ancestor) for a set of md5s.


=cut
sub lca {
  my ($self , $md5s , $caching , $source ) = @_ ;

  $source     = "RefSeq" unless (defined $source) ;
  my $nr_md5s = scalar @$md5s ; 
  my @search_list ;
  my @seen ;

  print STDERR "Processing " . scalar @$md5s . " md5s!\n" if ($self->debug) ; 

  # caching get reduce search set
  if ($caching){
    foreach my $md5 (@$md5s){
      unless (exists $self->{md5cache}->{$md5} and  $self->{md5cache}->{$md5}->{lineage}) {
	push @search_list , $md5 ;
      }
      else{
	push @seen , @{ $self->{md5cache}->{$md5}->{lineage} } ;
      }
    }
  }
  else{
    @search_list = @$md5s ; 
  }

  print STDERR "Searching lineage for " . scalar @search_list . " md5s\n" if ($self->debug);
  # get sets and organism id

  my $taxa = $self->md52taxonomy(\@search_list , $source) ;
  
  unless(@$taxa or @seen){
    print STDERR "No hit in ach for " . join ("," , @search_list) . " and source $source\n" ; 
    return [] ;
  }
  
  
  # get lineage for new md5s
  #p.md5, o.tax_domain, o.tax_phylum, o.tax_class, o.tax_order, o.tax_family, o.tax_genus, o.tax_species, o.name , p.source
  my @lineages ;

  foreach my $result (@$taxa){
    #print STDERR join "\t" , "Processing:" , @$result , "\n" ,  if ( $self->debug );
    push @lineages ,  [ @$result[1..8] ] ;
    push @{ $self->{md5cache}->{ $result->[8] }->{lineage} }  ,[ @$result[1..8] ] if ($caching); 
    print STDERR join "\t" , '---' , "LIN:" , ( map { $_ || '-' } @$result ) , "\n" ;
  }
  

  push @lineages , @seen ;
 

  # count unique terms for every note
  my $coverage = {} ;

  foreach my $lineage (@lineages){
    print STDERR join "\t:" , @$lineage   if ( $self->debug );
    
    if (@$lineage and $lineage->[0]){
      for (my $i=0 ; $i< scalar @$lineage ; $i++ ){
	$coverage->{ $i }->{ $lineage->[ $i ] }++ if ( $lineage->[ $i ] );
      }      
    }
  }
  
  my $pos = 0 ;
  my $max = 0 ;
  
  # get common node
  foreach my $key (sort { $a <=> $b } keys %$coverage){
    
    my $tmp = scalar keys %{ $coverage->{$key}};
    if ( $tmp <= $max or not $max){
      $max = $tmp ;
      $pos = $key ;
    }
    
  }
  
  my @lca ;
 
  if ( keys %{$coverage->{$pos}} > 1 ){
    print STDERR "Multiple LCAs: " . join "\t" , keys %{$coverage->{$pos}} ,"Position $pos" , "\n";
  }
  elsif( keys %{$coverage->{$pos}} == 1 ) {
    
      #print join "\t" , $pos , $nr_md5s , (map { keys %{ $coverage->{ $_ } } } (1 .. $pos) ) , $source , "\n" ;
      @lca = map { keys %{ $coverage->{ $_ } } } (0 .. $pos) ;
      push @lca , ( map { '-' } ( $pos + 1 .. 7 ) ) if ($pos < 7);
      push @lca , ($pos + 1) ;
    }
  else{
    print STDERR "No LCA ($pos)\n" ;
  }
  

  return \@lca ;
}


1;
