package MGRAST::Analysis;

use strict;
use warnings;
no warnings('once');

use List::Util qw(max min sum first);
use Conf;
use DBI;
use Data::Dumper;
use Babel::lib::Babel;

use Cache::Memcached;
use File::Temp qw/ tempfile tempdir /;

1;

sub new {
  my ($class, $job_dbh) = @_;

  # get ach object
  my $ach = new Babel::lib::Babel;
  
  # connect to database
  my $dbh;
  eval {
    my $dbms     = $Conf::mgrast_dbms;
    my $host     = $Conf::mgrast_dbhost;
    my $database = $Conf::mgrast_db;
    my $user     = $Conf::mgrast_dbuser;
    my $password = $Conf::mgrast_dbpass;

    $dbh = DBI->connect("DBI:$dbms:dbname=$database;host=$host", $user, $password, 
			{ RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			  die "database connect error.";
  };
  if ($@) {
    warn "Unable to connect to metagenomics database: $@\n";
    return undef;
  }
  unless ($job_dbh && ref($job_dbh)) {
    warn "Unable to connect to job_cache database\n";
    return undef;
  }
  $dbh->{pg_expand_array} = 1;

  # create object
  my $self = { dbh    => $dbh,     # job data db_handle
	       ach    => $ach,     # ach/babel object
	       jcache => $job_dbh, # job cache db_handle
	       jobs   => {},       # hash: mg_id => job_id
	       tables => {},       # hash: job_id => table_type => table_name
	       search => 'data_summary',  # nameof search table in dbh
	       expire => $Conf::web_memcache_expire || 172800 # use config or 48 hours
	     };
  bless $self, $class;
  return $self;
}

 sub DESTROY {
   my ($self) = @_;

   if ($self->{dbh})    { $self->{dbh}->disconnect; }
   if ($self->{ach})    { $self->{ach}->DESTROY; }
   if ($self->{jcache}) { $self->{jcache}->disconnect; }
}

sub dbh {
  my ($self) = @_;
  return $self->{dbh};
}

sub ach {
  my ($self) = @_;
  return $self->{ach};
}

sub jcache {
  my ($self) = @_;
  return $self->{jcache};
}

sub jobs {
  my ($self) = @_;
  return $self->{jobs};
}

sub expire {
  my ($self) = @_;
  return $self->{expire};
}

sub has_job {
  my ($self, $mgid) = @_;
  return exists($self->jobs->{$mgid}) ? 1 : 0;
}

# add values to $self->{jobs} and $self->{tables} based on metagenome_id list
sub add_jobs {
  my ($self, $mgids) = @_;

  my @new_mg  = grep { ! $self->has_job($_) } @$mgids;
  my $new_map = $self->get_jobid_map(\@new_mg);

  %{ $self->{jobs} }   = ( %{$self->{jobs}}, %$new_map );
  %{ $self->{tables} } = ( %{$self->{tables}}, %{$self->get_jobs_tables([values %$new_map])} );
}

# set values for $self->{jobs} and $self->{tables} based on metagenome_id list
sub set_jobs {
  my ($self, $mgids, $jids) = @_;

  if (defined($jids)) {
    $self->{jobs} = $self->get_jobid_map($mgids, 1);
  } else {
    $self->{jobs} = $self->get_jobid_map($mgids);
  }
  $self->{tables} = $self->get_jobs_tables([values %{$self->{jobs}}]);
}

# populate obj with all public jobs
sub set_public_jobs {
  my ($self) = @_;

  my $mgids = $self->jcache->selectcol_arrayref("SELECT metagenome_id FROM Job WHERE public = 1 AND viewable = 1");
  if ($mgids && (@$mgids > 0)) {
    $self->set_jobs($mgids);
  }
  else {
    $self->{jobs}   = {};
    $self->{tables} = {};
  }
}

sub get_jobid_map {
  my ($self, $mgids, $jids) = @_;

  unless (scalar(@$mgids)) {
    return {};
  }

  my $hash = {};
  my $list = join(",", map {"'$_'"} @$mgids);
  my $rows;
  if ($jids) {
    $rows = $self->jcache->selectall_arrayref("SELECT metagenome_id, job_id FROM Job WHERE job_id IN ($list) AND viewable = 1");
  } else {
    $rows = $self->jcache->selectall_arrayref("SELECT metagenome_id, job_id FROM Job WHERE metagenome_id IN ($list) AND viewable = 1");
  }
  if ($rows && (@$rows > 0)) {
    %$hash = map { $_->[0], $_->[1] } @$rows;
  }
  return $hash;
}

sub get_jobs_tables {
  my ($self, $jobs) = @_;

  my $all  = {};
  my $tbls = {};

  return $tbls unless (scalar @$jobs);

  my $list = join(",", @$jobs);
  my $rows = $self->dbh->selectall_arrayref("select job_id, table_type, seq_db_name, seq_db_version, table_name from job_tables where job_id in ($list) and loaded is true");
  if ($rows && (@$rows > 0)) {
    foreach (@$rows) { $all->{ $_->[0] }->{ $_->[1] }->{ $_->[2] }->{ $_->[3] } = $_->[4]; }
  }
  ## select 'M5NR' if multiple dbs, select highest 
  foreach my $j (keys %$all) {
    foreach my $t (keys %{$all->{$j}}) {
      my @dbs = keys %{$all->{$j}{$t}};
      my $db  = (exists $all->{$j}{$t}{M5NR}) ? "M5NR" : $dbs[0];
      my $ver = (sort {$b cmp $a} keys %{$all->{$j}{$t}{$db}})[0];
      $tbls->{$j}{$t} = $all->{$j}{$t}{$db}{$ver};
    }
  }
  return $tbls;
}

sub get_seq_count {
  my ($self, $mgid) = @_;

  my $sql  = "select js.value from JobStatistics js, Job j where j._id = js.job and js.tag = 'sequence_count_raw' and j.metagenome_id = '$mgid'";
  my $rows = $self->jcache->selectcol_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

####################
# Dir / File path
####################

sub job_dir {
  my ($self, $job) = @_;
  return $job ? $Conf::mgrast_jobs . "/" . $job : '';
}

sub analysis_dir {
  my ($self, $job) = @_;
  return $job ? $self->job_dir($job) . "/analysis" : '';
}

sub fasta_file {
  my ($self, $job) = @_;

  unless ($job) { return ''; }
  my $base = $self->job_dir($job) . "/raw/" . $job;

  if ((-s "$base.fna") || (-s "$base.fna.gz")) {
    return "$base.fna";
  }
  elsif ((-s "$base.fastq") || (-s "$base.fastq.gz")) {
    return "$base.fastq";
  }
  else {
    return '';
  }
}

sub sim_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/900.loadDB.sims.filter.seq" : '';
}

sub source_stats_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/900.loadDB.source.stats" : '';
}

sub taxa_stats_file {
  my ($self, $job, $taxa) = @_;
  return $job ? $self->analysis_dir($job) . "/999.done.$taxa.stats" : '';
}

sub ontology_stats_file {
  my ($self, $job, $source) = @_;
  return $job ? $self->analysis_dir($job) . "/999.done.$source.stats" : '';
}

sub rarefaction_stats_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/999.done.rarefaction.stats" : '';
}

sub qc_stats_file {
  my ($self, $job, $type) = @_;
  return $job ? $self->analysis_dir($job) . "/075.$type.stats" : '';
}

sub length_hist_file {
  my ($self, $job, $stage) = @_;

  if (lc($stage) eq 'raw') {
    return $self->fasta_file($job) ? $self->fasta_file($job) . ".lens" : '';
  }
  elsif (lc($stage) eq 'qc') {
    return $job ? $self->analysis_dir($job) . "/299.screen.passed.fna.lens" : '';
  }
  else {
    return '';
  }
}

sub gc_hist_file {
  my ($self, $job, $stage) = @_;

  if (lc($stage) eq 'raw') {
    return $self->fasta_file($job) ? $self->fasta_file($job) . ".gcs" : '';
  }
  elsif (lc($stage) eq 'qc') {
    return $job ? $self->analysis_dir($job) . "/299.screen.passed.fna.gcs" : '';
  }
  else {
    return '';
  }
}

####################
# Table names
####################

sub org_tbl {
  my ($self, $job) = @_;
  return (exists $self->{tables}{$job}{organism}) ? $self->{tables}{$job}{organism} : '';
}

sub func_tbl {
  my ($self, $job) = @_;
  return (exists $self->{tables}{$job}{function}) ? $self->{tables}{$job}{function} : '';
}

sub md5_tbl {
  my ($self, $job) = @_;
  return (exists $self->{tables}{$job}{protein}) ? $self->{tables}{$job}{protein} : '';
}

sub ontol_tbl {
  my ($self, $job) = @_;
  return (exists $self->{tables}{$job}{ontology}) ? $self->{tables}{$job}{ontology} : '';
}

sub lca_tbl {
  my ($self, $job) = @_;
  return (exists $self->{tables}{$job}{lca}) ? $self->{tables}{$job}{lca} : '';
}

####################
# misc
####################

sub get_all_job_ids {
  my ($self) = @_;

  my @jobs  = ();
  my $query = $self->dbh->prepare("select distinct(job_id) from job_tables where loaded is TRUE");
  $query->execute();
  my $rows = $query->fetchall_arrayref;
  if ($rows && (@$rows > 0)) {
    @jobs = map { $_->[0] } @$rows;
  }
  return \@jobs;
}

sub get_where_str {
  my ($self, $items) = @_;

  my @text;
  unless ($items && (@$items > 0)) { return ""; }
  foreach my $i (@$items) {
    if ($i && ($i =~ /\S/)) {
      push @text, $i;
    }
  }
  if (@text == 1) {
    return " WHERE " . $text[0];
  } elsif (@text > 1) {
    return " WHERE " . join(" AND ", @text);
  } else {
    return "";
  }
}

sub run_fraggenescan {
  my ($self, $fasta) = @_;

  my ($infile_hdl, $infile_name) = tempfile("fgs_in_XXXXXXX", DIR => $Conf::temp, SUFFIX => '.fna');
  print $infile_hdl $fasta;
  close $infile_hdl;

  my $fgs_cmd = $Conf::run_fraggenescan." -genome=$infile_name -out=$infile_name.fgs -complete=0 -train=454_30";
  `$fgs_cmd`;
  my $output = "";
  if (open(FH, "<".$infile_name.".fgs.faa")) {
    while (<FH>) {
      $output .= $_;
    }
    close FH;
  }
  unlink($infile_name, $infile_name.".fgs.faa", $infile_name.".fgs.ffn", $infile_name.".fgs.out");
  return $output;
}

####################
# data from files
####################

sub get_source_stats {
  my ($self, $jobid) = @_;

  my $data = {};
  my $file = $self->source_stats_file($jobid);
  unless ($file && (-s $file)) { return $data; }

  open(FILE, "<$file") || return $data;
  while (my $line = <FILE>) {
    chomp $line;
    my @parts  = split(/\t/, $line);
    my $source = shift @parts;
    if (@parts == 10) {
      $data->{$source}->{evalue}  = [ @parts[0..4] ];
      $data->{$source}->{identity} = [ @parts[5..9] ];
    }
  }
  close(FILE);

  return $data;
  # source => type => [#, #, #, #, #]
}

sub file_to_array {
  my ($self, $file) = @_;
  
  my $data = [];
  unless ($file && (-s $file)) { return $data; }
  
  open(FILE, "<$file") || return $data;
  while (my $line = <FILE>) {
    chomp $line;
    my @parts = split(/\t/, $line);
    push @$data, [ @parts ];
  }
  close(FILE);

  return $data;
}

sub get_taxa_stats {
  my ($self, $jobid, $taxa) = @_;
  return $self->file_to_array( $self->taxa_stats_file($jobid, $taxa) );
  # [ name, abundance ]
}

sub get_ontology_stats {
  my ($self, $jobid, $source) = @_;
  return $self->file_to_array( $self->ontology_stats_file($jobid, $source) );
  # [ top level name, abundance ]
}

sub get_rarefaction_coords {
  my ($self, $jobid) = @_;
  return $self->file_to_array( $self->rarefaction_stats_file($jobid) );
  # [ x, y ]
}

sub get_qc_stats {
  my ($self, $jobid, $type) = @_;
  return $self->file_to_array( $self->qc_stats_file($jobid, $type) );
  # matrix
}

sub get_histogram_nums {
  my ($self, $jobid, $type, $stage) = @_;

  $stage   = $stage ? $stage : 'raw';
  my $file = "";

  if ($type eq 'len') {
    $file = $self->length_hist_file($jobid, $stage);
  } elsif ($type eq 'gc') {
    $file = $self->gc_hist_file($jobid, $stage);
  }
  return $self->file_to_array($file);
  # [ value, count ]
}

sub get_md5_sims {
  # $md5_seeks = [md5, seek, length]
  my ($self, $jobid, $md5_seeks) = @_;

  my $sims = {};
  if ($md5_seeks && (@$md5_seeks > 0)) {
    @$md5_seeks = sort { $a->[1] <=> $b->[1] } @$md5_seeks;
    open(FILE, "<" . $self->sim_file($jobid)) || return {};
    foreach my $set ( @$md5_seeks ) {
      my ($md5, $seek, $length) = @$set;
      my $rec = '';
      my %tmp = ();
      seek(FILE, $seek, 0);
      read(FILE, $rec, $length);
      chomp $rec;
      
      $sims->{$md5} = [ split(/\n/, $rec) ];
    }
    close FILE;
  }
  return $sims;
  # md5 => [sim lines]
}

####################
# Math Functions
####################

# log of N choose R 
sub nCr2ln {
  my ($self, $n, $r) = @_;

  my $c = 1;
  if ($r > $n) {
    return $c;
  }
  if (($r < 50) && ($n < 50)) {
    map { $c = ($c * ($n - $_)) / ($_ + 1) } (0..($r-1));
    return log($c);
  }
  if ($r <= $n) {
    $c = $self->gammaln($n + 1) - $self->gammaln($r + 1) - $self->gammaln($n - $r); 
  } else {
    $c = -1000;
  }
  return $c;
}

# This is Stirling's formula for gammaln, used for calculating nCr
sub gammaln {
  my ($self, $x) = @_;

  unless ($x > 0) { return 0; }
  my $s = log($x);
  return log(2 * 3.14159265458) / 2 + $x * $s + $s / 2 - $x;
}

####################
# All functions conducted on individual job
####################

sub get_sources {
  my ($self, $mgid, $type) = @_;

  $self->set_jobs([$mgid]);
  my $job = $self->jobs->{$mgid};

  if ($type && exists($self->{tables}{$job}{$type})) {
    my $srcs = $self->dbh->selectcol_arrayref("SELECT DISTINCT source FROM ".$self->{tables}{$job}{$type}." ORDER BY source");
    return $srcs;
  }
  else {
    my $total = {};
    while ( my ($type, $name) = each %{$self->{tables}{$job}} ) {
      next if ($type =~ /^(protein|lca)$/);
      my $srcs = $self->dbh->selectcol_arrayref("SELECT DISTINCT source FROM $name");
      map { $total->{$_} = 1 } @$srcs;
    }
    return [ sort keys %$total ];
  }
}

sub md5_abundance_for_annotations {
  my ($self, $mgid, $type, $srcs, $anns) = @_;

  $self->set_jobs([$mgid]);
  my $job = $self->jobs->{$mgid};
  my $tbl = exists($self->{tables}{$job}{$type}) ? $self->{tables}{$job}{$type} : '';
  unless ($tbl) { return {}; }

  my ($name, $where);
  if    ($type eq 'organism') { $name = "t.organism"; }
  elsif ($type eq 'function') { $name = "t.function"; }
  elsif ($type eq 'ontology') { $name = "t.id"; }
  else  { return {}; }
  
  my $data = {};
  my $qsrc = ($srcs && @$srcs) ? " AND t.source IN (".join(",", map {$self->dbh->quote($_)} @$srcs).")" : '';
  my $qann = ($anns && @$anns) ? " AND $name IN (".join(",", map {$self->dbh->quote($_)} @$anns).")" : '';
  my $sql  = "SELECT distinct $name, p.md5, p.abundance FROM $tbl t, ".$self->{tables}{$job}{protein}." p WHERE p.md5 = ANY(t.md5s)".$qsrc.$qann;
  my $rows = $self->dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
    map { $data->{$_->[0]}->{$_->[1]} = $_->[2] } @$rows;
  }
  # ann => md5 => abundance
  return $data;  
}

sub sequences_for_md5s {
  my ($self, $mgid, $type, $md5s) = @_;

  $self->set_jobs([$mgid]);
  my $data = {};
  my $seqs = $self->md5s_to_read_sequences($md5s);
  unless ($seqs && @$seqs) { return {}; }

  if ($type eq 'dna') {
    foreach my $set (@$seqs) {
      push @{ $data->{$set->{md5}} }, $set->{sequence};
    }
  }
  elsif ($type eq 'protein') {
    my $fna = '';
    map { $fna .= ">".$_->{md5}."|".$_->{id}."\n".$_->{sequence}."\n" } @$seqs;
    my $faa = $self->run_fraggenescan($fna);
    unless ($faa) { return {}; }
    my @seqs = split(/\n/, $faa);
    for (my $i=0; $i<@seqs; $i += 2) {
      if ($seqs[$i] =~ /^>(\S+)/) {
	my $id  = $1;
	my $seq = $seqs[$i+1];
	$id =~ /^(\w+)?\|/;
	my $md5 = $1;
	push @{ $data->{$md5} }, $seq;
      }
    }
  }
  else {
    return {};
  }
  # md5 => [ seq list ]
  return $data;
}

sub sequences_for_annotation {
  my ($self, $mgid, $seq_type, $ann_type, $srcs, $anns) = @_;

  my $data = {};
  my $md5s = {};
  my $ann  = $self->md5_abundance_for_annotations($mgid, $ann_type, $srcs, $anns);  # ann => md5 => abundance
  foreach my $a (keys %$ann) {
    map { $md5s->{$_} = 1; } keys %{$ann->{$a}};
  }
  
  unless (scalar(keys(%$md5s))) {
    return $data;
  }
  
  my $seqs = $self->sequences_for_md5s($mgid, $seq_type, [keys %$md5s]);  # md5 => [ seq list ]
  foreach my $a (keys %$ann) {
    foreach my $m (keys %{$ann->{$a}}) {
      next unless (exists $seqs->{$m});
      map { push @{$data->{$a}}, $_ } @{$seqs->{$m}};
    }
  }
  # ann => [ seq list ]
  return $data;
}

sub metagenome_search {
  my ($self, $type, $srcs, $ann, $exact) = @_;

  my $jobs = {};
  my $qann = $self->dbh->quote($ann);

  my $qsrc = ($srcs && @$srcs) ? " AND source IN (".join(",", map {$self->dbh->quote($_)} @$srcs).")" : '';

  my $opr  = $exact ? '=' : '~*';
  my $rows = $self->dbh->selectcol_arrayref("SELECT jobs FROM ".$self->{search}." WHERE type = '$type' AND name $opr $qann".$qsrc);

  if ($rows && (@$rows > 0)) {
    foreach my $row (@$rows) {
      map { $jobs->{$_} = 1 } @$row;
    }
  }

  return [ keys %{$self->get_jobid_map([keys %$jobs], 1)} ];
}

####################
# All functions conducted on jobs list
####################

=pod

=item * B<all_read_sequences>

Retrieve all the [ {id , sequence} ] from the metagenome job directory.

=cut 

sub all_read_sequences {
  my ($self) = @_;

  my $seqs = [];
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    open(FILE, "<" . $self->sim_file($j)) || next;
    while (my $line = <FILE>) {
      chomp $line;
      my @tabs = split(/\t/, $line);
      if (@tabs == 13) {
	push @$seqs, { id => "$mg|$tabs[0]", sequence => $tabs[12] };
      }
    }
    close FILE;
  }
  return $seqs;
}

=pod

=item * B<md5s_to_read_sequences> (I<md5s>, I<eval>, I<ident>)

Retrieve the [ {id , sequence} ] from the metagenome job directory for I<md5s> with I<eval>.

=cut 

sub md5s_to_read_sequences {
  my ($self, $md5s, $eval, $ident, $alen) = @_;

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5 IN (" . join(",", map {"'$_'"} @$md5s) . ")" : "";
  my $where  = $self->get_where_str([$w_md5s, $eval, $ident, $alen, "seek IS NOT NULL", "length IS NOT NULL"]);
  my $seqs   = [];

  unless ($w_md5s || $eval || $ident || $alen) { return $self->all_read_sequences(); }

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $sql  = "SELECT md5, seek, length FROM " . $self->md5_tbl($j) . "$where ORDER BY seek";
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
      open(FILE, "<" . $self->sim_file($j)) || next;
      foreach my $row (@$rows) {
	my ($md5, $seek, $len) = @$row;
	my $rec = '';
	seek(FILE, $seek, 0);
	read(FILE, $rec, $len);
	chomp $rec;
	foreach my $line ( split(/\n/, $rec) ) {
	  my @tabs = split(/\t/, $line);
	  if (@tabs == 13) {
	    push @$seqs, { md5 => $md5, id => "$mg|$tabs[0]", sequence => $tabs[12] };
	  }
	}
      }
      close FILE;
    }
    $self->dbh->commit();
  }
  return $seqs;
}

sub get_abundance_for_organism_source {
  my ($self, $organism, $source) = @_;

  my $qorg = $self->dbh->quote($organism);
  my $qsrc = $self->dbh->quote($source);
  my @sqls = ();
  my $num  = 0;

  foreach my $j (values %{$self->jobs}) {
    if ($self->org_tbl($j)) {
      push @sqls, "SELECT abundance FROM " . $self->org_tbl($j) . " WHERE organism = $qorg AND source = $qsrc";
    }
  }
  if (@sqls > 0) {
    my $rows = $self->dbh->selectcol_arrayref( join(" UNION ALL ", @sqls) );
    if ($rows && (@$rows > 0)) {
      map { $num += $_ } @$rows;
    }
  }
  return $num;
}

sub get_organism_abundance_for_source {
  my ($self, $source) = @_;

  my $qsrc = $self->dbh->quote($source);
  my @sqls = ();
  my $data = {};

  foreach my $j (values %{$self->jobs}) {
    if ($self->org_tbl($j)) {
      push @sqls, "SELECT organism, abundance FROM " . $self->org_tbl($j) . " WHERE source = $qsrc";
    }
  }
  if (@sqls > 0) {  
    my $rows = $self->dbh->selectall_arrayref( join(" UNION ALL ", @sqls) );
    if ($rows && (@$rows > 0)) {
      map { $data->{$_->[0]} += $_->[1] } @$rows;
    }
  }
  return $data;
}

sub get_organisms_with_contig_for_source {
  my ($self, $source, $num, $len) = @_;

  my $job_orgs = $self->get_organism_abundance_for_source($source);
  my @job_ctgs = map { [$_->[0], $_->[1], $job_orgs->{$_->[1]}] } grep { exists $job_orgs->{$_->[1]} } @{ $self->ach->get_organism_with_contig_list($num, $len) };
  return \@job_ctgs;
}

sub get_md5_evals_for_organism_source {
  my ($self, $organism, $source) = @_;

  my $qorg = $self->dbh->quote($organism);
  my $qsrc = $self->dbh->quote($source);
  my @sqls = ();

  foreach my $j (values %{$self->jobs}) {
    push @sqls, "SELECT distinct p.md5, p.evals FROM " . $self->org_tbl($j) . " o, " . $self->md5_tbl($j) .
                " p WHERE p.md5 = ANY(o.md5s) AND o.organism = $qorg AND o.source = $qsrc";
  }
  my $data = {};
  my $rows = $self->dbh->selectall_arrayref( join(" UNION ALL ", @sqls) );
  if ($rows && (@$rows > 0)) {
    foreach my $r (@$rows) {
      my ($md5, $evals) = @$r;
      if (exists $data->{$md5}) {
	for (my $i=0; $i<@$evals; $i++) { $data->{$md5}->[$i] += $evals->[$i]; }
      }
      else {
	$data->{$md5} = $evals;
      }
    }
  }
  return $data;
}

sub get_md5_data_for_organism_source {
  my ($self, $organism, $source, $eval) = @_;

  my $w_org  = "o.organism = " . $self->dbh->quote($organism);
  my $w_src  = "o.source = " . $self->dbh->quote($source);
  my $w_eval = (defined($eval) && ($eval =~ /^\d+$/)) ? "p.exp_avg <= " . ($eval * -1) : "";
  my $where  = $self->get_where_str([$w_org, $w_src, $w_eval, " p.md5 = ANY(o.md5s)", "p.seek IS NOT NULL", "p.length IS NOT NULL"]);
  my @data   = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    unless ($self->md5_tbl($j) && $self->org_tbl($j)) { next; }
    my $sql = "SELECT distinct p.md5,p.abundance,p.exp_avg,p.exp_stdv,p.ident_avg,p.ident_stdv,p.len_avg,p.len_stdv,p.seek,p.length " .
              "FROM " . $self->org_tbl($j) . " o, " . $self->md5_tbl($j) . " p" . $where . " ORDER BY p.seek";
    my $tmp = $self->dbh->selectall_arrayref($sql);
    if ($tmp && (@$tmp > 0)) {
      foreach my $row ( @$tmp ) {
	push @data, [ $mg, @$row ];
      }
    }
    $self->dbh->commit();
  }

  return \@data;
}

sub get_rarefaction_curve {
  my ($self, $sources, $get_alpha) = @_;

  unless ($sources && @$sources) { $sources = []; }

  my $raw_data = {};  # mgid => species => abundance
  my $mg_alpha = {};  # mgid => alpha diversity
  my $mg_rare  = {};  # mgid => [ rare-x, rare-y ]
  my $mg_abund = $self->get_abundance_for_tax_level('tax_species', [], $sources);  # [mgid, species, abundance]

  map { $raw_data->{$_->[0]}->{$_->[1]} = $_->[2] } @$mg_abund;
  
  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = 'rarefaction'.join(':', @$sources);

  # calculate alpha diversity
  if ($get_alpha) {
    foreach my $mg (keys %$raw_data) {
      my $cdata = $memd->get($mg.$cache_key."alpha");
      unless ($cdata) {
	my $h1  = 0;
	my $sum = sum values %{$raw_data->{$mg}};
	unless ($sum) {
	  $mg_alpha->{$mg} = 0;
	  $memd->set($mg.$cache_key."alpha", 0, $self->expire);
	  next;
	}
	foreach my $num (values %{$raw_data->{$mg}}) {
	  my $p = $num / $sum;
	  if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
	}
	$mg_alpha->{$mg} = 2 ** $h1;
	$memd->set($mg.$cache_key."alpha", $mg_alpha->{$mg}, $self->expire);
      }
      else {
	$mg_alpha->{$mg} = $cdata;
      }
    }
    $memd->disconnect_all;
    return $mg_alpha;
  }

  # calculate rarefaction (x, y)
  foreach my $mg (keys %$raw_data) {
    my $cdata = $memd->get($mg.$cache_key."curve");
    unless ($cdata) {
      my @nums = sort {$a <=> $b} values %{$raw_data->{$mg}};
      my $k    = scalar @nums;
      my $nseq = $self->get_seq_count($mg);
      my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
      unless ($nseq) {
	$mg_rare->{$mg} = [];
	$memd->set($mg.$cache_key."curve", [], $self->expire);
	next;
      }
      for (my $n = 0; $n < $nseq; $n += $size) {
	my $coeff = $self->nCr2ln($nseq, $n);
	my $curr  = 0;
	map { $curr += exp( $self->nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
	push @{ $mg_rare->{$mg} }, [ $n, $k - $curr ];
      }
      $memd->set($mg.$cache_key."curve", $mg_rare->{$mg}, $self->expire);
    }
    else {
      $mg_rare->{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;
  
  return $mg_rare;
}

sub get_abundance_for_tax_level {
  my ($self, $level, $names, $sources, $value) = @_;

  unless ($sources && @$sources) { $sources = []; }
  my $all = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_organisms4level($level, $names);
  my $src_str  = @$sources ? join("", @$sources) : '';
  return $self->get_abundance_for_hierarchy($name_map, "organism", $level.$src_str, $all, $sources, $value);
}

sub get_abundance_for_ontol_level {
  my ($self, $level, $names, $source, $value) = @_;

  my $all = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_ids4level($source, $level, $names);
  return $self->get_abundance_for_hierarchy($name_map, "id", $level.$source, $all, [$source], $value);
}

sub get_abundance_for_hierarchy {
  my ($self, $name_map, $type, $key, $all, $sources, $value) = @_;

  unless ($value) { $value = "abundance"; }
  my $data   = [];
  my $w_type = $all ? "" : "$type in (" . join(",", map {$self->dbh->quote($_)} keys %$name_map) . ")";
  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $where  = $self->get_where_str([$w_type, $w_srcs]);

  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = $value.$type.$key;

  # get for jobs
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $all ? $memd->get($mg.$cache_key) : undef;
    unless ($cdata) {
      my $table = ($type eq "organism") ? $self->org_tbl($j) : (($type eq "id") ? $self->ontol_tbl($j) : "");
      unless ($table && $self->md5_tbl($j)) { next; }
      $cdata = [];
      my $md5s = {};
      my $hier = {};
      my $sql  = "select distinct $type, md5s from $table" . $where;
      my $tmp  = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp)) {
	foreach my $row ( @$tmp ) {
	  if ( exists $name_map->{$row->[0]} ) {
	    foreach my $md5 ( @{$row->[1]} ) {
	      unless ($all) { $md5s->{$md5} = 0; }
	      $hier->{ $name_map->{$row->[0]} }->{$md5} = 1;
	    }
	  }
	}
      }

      my $w_md5s = ($all || (scalar(keys %$md5s) == 0)) ? "" : " where md5 in (" . join(",", map {"'$_'"} keys %$md5s) . ")";
      $sql = "select md5, $value from " . $self->md5_tbl($j) . $w_md5s;
      $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp)) {
	foreach my $row ( @$tmp ) {
	  $md5s->{ $row->[0] } = $row->[1];
	}
      }
      
      foreach my $h (sort keys %$hier) {
	my $num   = 0;
	my $count = 0;
	map { $num += $md5s->{$_}; $count += 1; } grep { exists $md5s->{$_} } keys %{ $hier->{$h} };
	if (($value ne "abundance") && ($count > 0)) {
	  $num = ($num * 1.0) / $count;
	}
	push @$data, [ $mg, $h, $num ];
	push @$cdata, [ $mg, $h, $num ];
      }
      $self->dbh->commit();

      if ($all) {
	$memd->set($mg.$cache_key, $cdata, $self->expire);
      }
    } else {
      push @$data, @$cdata;
    }
  }
  $memd->disconnect_all;

  return $data;
  # mgid, taxa_name, abundance
}

sub get_abundance_for_set {
  my ($self, $set, $type, $sources) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }
  unless ($set && (@$set > 0)) { return {}; }

  my $data   = {};
  my $m5_map = {};
  my $get_m5nr  = first {$_ =~ /^m5nr$/i} @$sources;
  my $get_m5rna = first {$_ =~ /^m5rna$/i} @$sources;

  if ($get_m5nr) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("protein") };
  }
  if ($get_m5rna) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("rna") };
  }
  if ($get_m5nr || $get_m5rna) {
    @$sources = grep { (! exists $m5_map->{$_}) && ($_ !~ /(m5nr|m5rna)/i) } @$sources;
    push @$sources, keys %$m5_map;
  }
  my $term_list = join(", ", map { $self->dbh->quote($_) } @$set);
  my $w_srcs = (@$sources > 0) ? " and source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $table = '';
    if ($type eq 'organism') {
      $table = $self->org_tbl($j) || '';
    } elsif ($type eq 'function') {
      $table = $self->func_tbl($j) || '';
    }
    unless ($table) { next; }
    my $sql = "select distinct $type, abundance from $table where $type in ($term_list)".$w_srcs;
    my $tmp = $self->dbh->selectall_arrayref($sql);

    map { $data->{$mg}{$_} = [ 0 ] } @$set;
    if ($tmp && (@$tmp > 0)) {
      map { push @{ $data->{$mg}{$_->[0]} }, $_->[1] } @$tmp;
    }
    $self->dbh->commit();
  }

  my $results = {};
  foreach my $mg (keys %$data) {
    foreach my $name (keys %{$data->{$mg}}) {
      $results->{$mg}{$name} = max @{ $data->{$mg}{$name} };
    }
  }
  
  return $results;
  # mgid => annotation => abundance
}

sub get_rank_abundance {
  my ($self, $limit, $type, $sources) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }

  my $data   = {};
  my $m5_map = {};
  my $get_m5nr  = first {$_ =~ /^m5nr$/i} @$sources;
  my $get_m5rna = first {$_ =~ /^m5rna$/i} @$sources;

  if ($get_m5nr) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("protein") };
  }
  if ($get_m5rna) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("rna") };
  }
  if ($get_m5nr || $get_m5rna) {
    @$sources = grep { (! exists $m5_map->{$_}) && ($_ !~ /(m5nr|m5rna)/i) } @$sources;
    push @$sources, keys %$m5_map;
  }
  my $w_srcs = (@$sources > 0) ? " where source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $table = '';
    if ($type eq 'organism') {
      $table = $self->org_tbl($j) || '';
    } elsif ($type eq 'function') {
      $table = $self->func_tbl($j) || '';
    }
    unless ($table && ($limit > 0)) { next; }
    my $sql = "select distinct $type, abundance from $table";
    if ($w_srcs) {
      $sql .= $w_srcs;
    }
    $sql .= " order by abundance desc limit ".($limit * scalar(@$sources));
    my $tmp = $self->dbh->selectall_arrayref($sql);
    if ($tmp && (@$tmp > 0)) {
      map { push @{ $data->{$mg}{$_->[0]} }, $_->[1] } @$tmp;
    }
    $self->dbh->commit();
  }
  
  my $results = {};
  foreach my $mg (keys %$data) {
    foreach my $name (keys %{$data->{$mg}}) {
      push @{ $results->{$mg} }, [ $name, max @{$data->{$mg}{$name}} ];
    }
    @{$results->{$mg}} = sort { ($b->[1] <=> $a->[1]) || ($a->[0] cmp $b->[0]) } @{$results->{$mg}};
    @{$results->{$mg}} = @{$results->{$mg}}[0..($limit-1)];
  }
  
  return $results;
  # mgid => [ annotation, abundance ]
}

sub get_global_rank_abundance {
  my ($self, $limit, $type, $source) = @_;

  my $data = {};
  if ((! $source) || ($source =~ /^m5nr$/i)) {
    $source = 'M5NR';
  }
  my $w_src = "source = '$source'";
  if ($source =~ /^m5rna$/i) {
    $w_src = "source in (".join(", ", map {"'$_'"} keys %{$self->ach->sources4type("rna")}).")";
  }

  my %jobs = map {$_, 1 } values %{$self->jobs};
  my $sql  = "select name, jobs from data_summary where type = '$type' and $w_src";
  my $tmp  = $self->dbh->selectall_arrayref($sql);
  if ($tmp && (@$tmp > 0)) {
    foreach my $row ( @$tmp ) {
      my $jnum = 0;
      map { $jnum += 1 } grep { exists $jobs{$_} } @{$row->[1]};
      $data->{$row->[0]} += $jnum;
    }
  }

  return $data;
  # annotation => job_count
}

sub search_organisms {
  my ($self, $text) = @_;

  my %data = ();
  my $memd = new Cache::Memcached {'servers' => [ $Conf::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "org_search".quotemeta($text);
  
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->org_tbl($j)) { next; }
      $cdata  = [];
      my $sql = "select distinct source,organism,abundance from ".$self->org_tbl($j)." where organism ~* ".$self->dbh->quote($text);
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  push @{ $data{$mg} }, $row;
	  push @$cdata, $row;
	}
      }
      $self->dbh->commit();
      $memd->set($mg.$cache_key, $cdata, $self->expire);
    } else {
      $data{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;

  return \%data;
  # mgid => [ source, organism, abundance ]
}

sub get_organisms_for_sources {
  my ($self, $sources, $eval, $ident, $alen) = @_;
  return $self->get_organisms_for_md5s([], $sources, $eval, $ident, $alen);
}

sub get_organisms_for_md5s {
  my ($self, $md5s, $sources, $eval, $ident, $alen) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }

  my %md5_set   = map {$_, 1} @$md5s;
  my $m5_map    = {};
  my $get_m5nr  = first {$_ =~ /^m5nr$/i} @$sources;
  my $get_m5rna = first {$_ =~ /^m5rna$/i} @$sources;
  my $mg_md5_abund = $self->get_md5_abundance();

  if ($get_m5nr) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("protein") };
  }
  if ($get_m5rna) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("rna") };
  }
  if ($get_m5nr || $get_m5rna) {
    @$sources = grep { (! exists $m5_map->{$_}) && ($_ !~ /(m5nr|m5rna)/i) } @$sources;
    push @$sources, keys %$m5_map;
  }
  #return (undef, $sources);
  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "org";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($sources) ? join(";", @$sources) : ":";
  
  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5s && '{" . join(",", map {qq("$_")} @$md5s) . "}'" : "";
  my $where  = $self->get_where_str([$w_md5s, $w_srcs, $eval, $ident, $alen]);
  my @data   = ();
  my %mdata  = ();
  my %all_orgs = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = ($md5s && (@$md5s > 0)) ? undef : $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->org_tbl($j)) { next; }
      $cdata = [];
      my $corgs = {};
      my %orgs  = ();
      my $md5n  = exists($mg_md5_abund->{$mg}) ? $mg_md5_abund->{$mg} : {};
      my $sql   = "select distinct source,organism,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv,md5s from " . $self->org_tbl($j) . $where;
      my $tmp   = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  $all_orgs{ $row->[1] } = 1;
	  $corgs->{ $row->[1] } = 1;
	  if ($get_m5nr || $get_m5rna) {
	    my $src = exists($m5_map->{$row->[0]}) ? ($get_m5nr ? 'M5NR' : 'M5RNA') : $row->[0];
	    push @{ $orgs{$src}{$row->[1]} }, [ @$row[2..9] ];
	    map { $mdata{$mg}{$_} = $md5n->{$_} } grep { exists $md5n->{$_} } @{$row->[9]};
	  }
	  else {
	    my $sub_abund = 0;
	    if ($w_md5s && (scalar(keys %$md5n) > 0)) {
	      map { $sub_abund += $md5n->{$_} } grep { exists($md5n->{$_}) && exists($md5_set{$_}) } @{$row->[9]};
	    } else {
	      $sub_abund = $row->[2];
	    }
	    push @data, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	    push @$cdata, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	    map { $mdata{$mg}{$_} = $md5n->{$_} } grep { exists $md5n->{$_} } @{$row->[9]};
	  }
	}
      }
      if ($get_m5nr || $get_m5rna) {
	foreach my $s (keys %orgs) {
	  foreach my $o (keys %{$orgs{$s}}) {
	    my ($tot,$sub,$ea,$es,$ia,$is,$la,$ls) = (0,0,0,0,0,0,0,0);
	    my $ct = scalar @{$orgs{$s}{$o}};
	    my @md5s = ();
	    foreach my $r (@{$orgs{$s}{$o}}) {
	      $ea += $r->[1];
	      $es += $r->[2];
	      $ia += $r->[3];
	      $is += $r->[4];
	      $la += $r->[5];
	      $ls += $r->[6];
	      push @md5s, @{$r->[7]};
	    }
	    my %uniq = map {$_, 1} @md5s;
	    map { $sub += $md5n->{$_} } grep { exists($md5n->{$_}) && exists($md5_set{$_}) } keys %uniq;
	    map { $tot += $md5n->{$_} } grep { exists($md5n->{$_}) } keys %uniq;
	    push @data, [ $mg, $s, $o, $tot, $sub, sprintf("%.3f",($ea/$ct)),
			  sprintf("%.3f",($es/$ct)), sprintf("%.3f",($ia/$ct)), sprintf("%.3f",($is/$ct)),
			  sprintf("%.3f",($la/$ct)), sprintf("%.3f",($ls/$ct)), join(";",keys %uniq) ];
	    push @$cdata, [ $mg, $s, $o, $tot, $sub, sprintf("%.3f",($ea/$ct)),
			  sprintf("%.3f",($es/$ct)), sprintf("%.3f",($ia/$ct)), sprintf("%.3f",($is/$ct)),
			  sprintf("%.3f",($la/$ct)), sprintf("%.3f",($ls/$ct)), join(";",keys %uniq) ];
	  }
	}
      }
      unless ($md5s && (@$md5s > 0)) {
	$memd->set($mg.$cache_key, $cdata, $self->expire);
	$memd->set($mg.$cache_key."orgs", [ keys %$corgs ], $self->expire);
	$memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->expire);
      }
    } else {
      push @data, @$cdata;
      my $o = $memd->get($mg.$cache_key."orgs");
      my $m = $memd->get($mg.$cache_key."md5s");
      if ($o) {
	map { $all_orgs{$_} = 1 } @$o;
      }
      if ($m) {
	map { $mdata{$mg}{$_} = $m->{$_} } keys %$m;
      }
    }
  }
  $memd->disconnect_all;

  my $taxons = $self->ach->get_taxonomy4orgs([keys %all_orgs]);
  my $result = [];
  my @no_tax = ('unassigned', 'unassigned', 'unassigned', 'unassigned', 'unassigned', 'unassigned', 'unassigned');

  foreach my $row (@data) {
    if (exists $taxons->{$row->[2]}) {
      push @$result, [ @$row[0,1], @{$taxons->{$row->[2]}}, @$row[2..11] ];
    } else {
      push @$result, [ @$row[0,1], @no_tax, @$row[2..11] ];
    }
  }

  return (\%mdata, $result);
  # mgid => md5 => abundance
  # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

########################################
##   ONTOLOGY MAP
##
##   To get complete ontology use:
##      ach->get_all_ontology4source_hash($source)
##          where $source is Subsystems, KO, COG, NOG
##   or use:
##      ach->subsystem_hash()
##      ach->kegg_hash()
##      ach->cog_hash()
##      ach->nog_hash()
##
##   subsystem/ko return:  id => [ level1, level2, level3, annotation ]
##   cog/nog return:       id => [ level1, level2, annotation ]
##
########################################

sub search_ontology {
  my ($self, $text) = @_;

  my %data = ();
  my $memd = new Cache::Memcached {'servers' => [ $Conf::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "ontol_search".quotemeta($text);
  
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->ontol_tbl($j)) { next; }
      $cdata  = [];
      my $sql = "select distinct source,annotation,abundance from ".$self->ontol_tbl($j)." where source != 'GO' and annotation ~* ".$self->dbh->quote($text);
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  push @{ $data{$mg} }, $row;
	  push @$cdata, $row;
	}
      }
      $self->dbh->commit();
      $memd->set($mg.$cache_key, $cdata, $self->expire);
    } else {
      $data{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;

  return \%data;
  # mgid => [ source, annotation, abundance ]
}

sub get_ontology_for_source {
  my ($self, $source, $eval, $ident, $alen) = @_;
  return $self->get_ontology_for_md5s([], $source, $eval, $ident, $alen);
}

sub get_ontology_for_md5s {
  my ($self, $md5s, $source, $eval, $ident, $alen) = @_;

  my $memd = new Cache::Memcached {'servers' => [ $Conf::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "ontol";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($source) ? $source : ":";
  
  my $mg_md5_abund = $self->get_md5_abundance();
  my %md5_set = map {$_, 1} @$md5s;

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_srcs = ($source) ? "source = '$source'" : "";
  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5s && '{" . join(",", map {qq("$_")} @$md5s) . "}'" : "";
  my $where  = $self->get_where_str([$w_md5s, $w_srcs, $eval, $ident, $alen]);
  my @data   = ();
  my %mdata  = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = ($md5s && (@$md5s > 0)) ? undef : $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->ontol_tbl($j)) { next; }
      $cdata = [];
      my $md5n = exists($mg_md5_abund->{$mg}) ? $mg_md5_abund->{$mg} : {};
      my $sql  = "select distinct id,annotation,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv,md5s from " . $self->ontol_tbl($j) . $where;
      my $tmp  = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my $sub_abund = 0;
	  if ($w_md5s && (scalar(keys %$md5n) > 0)) {
	    map { $sub_abund += $md5n->{$_} } grep { exists($md5n->{$_}) && exists($md5_set{$_}) } @{$row->[9]};
	  } else {
	    $sub_abund = $row->[2];
	  }
	  push @data, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	  push @$cdata, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	  map { $mdata{$mg}{$_} = $md5n->{$_} } grep { exists $md5n->{$_} } @{$row->[9]};
	}
      }
      $self->dbh->commit();

      unless ($md5s && (@$md5s > 0)) {
	$memd->set($mg.$cache_key, $cdata, $self->expire);
	$memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->expire);
      }
    } else {
      push @data, @$cdata;
      my $m = $memd->get($mg.$cache_key."md5s");
      if ($m) {
	map { $mdata{$mg}{$_} = $m->{$_} } keys %$m;
      }
    }

  }
  $memd->disconnect_all;

  return (\%mdata, \@data);
  # mgid => md5 => abundance
  # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub get_functions_for_sources {
  my ($self, $sources, $eval, $ident, $alen) = @_;
  return $self->get_functions_for_md5s([], $sources, $eval, $ident, $alen);
}

sub get_functions_for_md5s {
  my ($self, $md5s, $sources, $eval, $ident, $alen) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }

  my $mg_md5_abund = ($md5s && (@$md5s > 0)) ? $self->get_md5_abundance($eval, $ident, $alen, $md5s) : {};
  my %md5_set = map {$_, 1} @$md5s;

  my $memd = new Cache::Memcached {'servers' => [ $Conf::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "func";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($sources) ? join(";", @$sources) : ":";

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5s && '{" . join(",", map {qq("$_")} @$md5s) . "}'" : "";
  my $where  = $self->get_where_str([$w_md5s, $w_srcs, $eval, $ident, $alen]);
  my @data   = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = ($md5s && (@$md5s > 0)) ? undef : $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->func_tbl($j)) { next; }
      $cdata = [];
      my $md5n = exists($mg_md5_abund->{$mg}) ? $mg_md5_abund->{$mg} : {};
      my $sql  = "select distinct source,function,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv,md5s from " . $self->func_tbl($j) . $where;
      my $tmp  = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my $sub_abund = 0;
	  if ($w_md5s && (scalar(keys %$md5n) > 0)) {
	    map { $sub_abund += $md5n->{$_} } grep { exists($md5n->{$_}) && exists($md5_set{$_}) } @{$row->[9]};
	  } else {
	    $sub_abund = $row->[2];
	  }
	  push @data, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	  push @$cdata, [ $mg, @$row[0..2], $sub_abund, @$row[3..8], join(";", @{$row->[9]}) ];
	}
      }
      $self->dbh->commit();
      
      unless ($md5s && (@$md5s > 0)) {
	$memd->set($mg.$cache_key, $cdata, $self->expire);
      }
    } else {
      push @data, @$cdata;
    }
  }
  $memd->disconnect_all;

  return \@data;
  # mgid, source, function, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub get_lca_data {
  my ($self, $eval, $ident, $alen) = @_;

  my $memd = new Cache::Memcached {'servers' => [ $Conf::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "lca";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $where = $self->get_where_str([$eval, $ident, $alen]);
  my @data  = ();
  
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->lca_tbl($j)) { next; }
      $cdata  = [];
      my $sql = "select distinct lca,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv from " . $self->lca_tbl($j) . $where;
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my @tax = ('-','-','-','-','-','-','-','-');
	  my @lca = split(/;/, $row->[0]);
	  for (my $i=0; $i<@lca; $i++) {
	    $tax[$i] = $lca[$i];
	  }
	  push @data, [ $mg, @tax, @$row[1..7] ];
	  push @$cdata, [ $mg, @tax, @$row[1..7] ];
	}
      }
      $self->dbh->commit();
      $memd->set($mg.$cache_key, $cdata, $self->expire);
    } else {
      push @data, @$cdata;
    }
  }
  $memd->disconnect_all;
  
  return \@data;
  # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
}

sub get_md5_data {
  my ($self, $md5s, $sources, $eval, $ident, $alen) = @_;

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
  
  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5 IN (" . join(",", map {"'$_'"} @$md5s) . ")" : "";
  my $where  = $self->get_where_str([$w_srcs, $w_md5s, $eval, $ident, $alen, "seek IS NOT NULL", "length IS NOT NULL"]);
  my @data   = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    unless ($self->md5_tbl($j)) { next; }
    my $sql = "select distinct md5,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv,seek,length from " . $self->md5_tbl($j) . $where . " ORDER BY seek";
    my $tmp = $self->dbh->selectall_arrayref($sql);
    if ($tmp && (@$tmp > 0)) {
      foreach my $row ( @$tmp ) {
	push @data, [ $mg, @$row ];
      }
    }
    $self->dbh->commit();
  }
  return \@data;
  # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length
}

sub get_md5_abundance {
  my ($self, $eval, $ident, $alen, $md5s) = @_;

  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "md5";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
  
  my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5 IN (" . join(",", map {"'$_'"} @$md5s) . ")" : "";
  my $where  = $self->get_where_str([$w_md5s, $eval, $ident, $alen]);
  my $data   = {};

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = ($md5s && (@$md5s > 0)) ? undef : $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->md5_tbl($j)) { next; }
      my $sql = "select md5, abundance from " . $self->md5_tbl($j) . $where;
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  $data->{$mg}->{$row->[0]} = $row->[1];
	}
      }
      $self->dbh->commit();

      unless ($md5s && (@$md5s > 0)) {
	$memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
      }
    } else {
      $data->{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;

  return $data;
  # mgid => md5 => abundance
}

sub get_org_md5 {
  my ($self, $eval, $ident, $alen, $sources) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }
  my $m5_map    = {};
  my $get_m5nr  = first {$_ =~ /^m5nr$/i} @$sources;
  my $get_m5rna = first {$_ =~ /^m5rna$/i} @$sources;

  if ($get_m5nr) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("protein") };
  }
  if ($get_m5rna) {
    map { $m5_map->{$_} = 1 } keys %{ $self->ach->sources4type("rna") };
  }
  if ($get_m5nr || $get_m5rna) {
    @$sources = grep { (! exists $m5_map->{$_}) && ($_ !~ /(m5nr|m5rna)/i) } @$sources;
    push @$sources, keys %$m5_map;
  }

  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "orgmd5";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($sources) ? join(";", @$sources) : ":";

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $where  = $self->get_where_str([$w_srcs, $eval, $ident, $alen]);
  my $data   = {};

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->org_tbl($j)) { next; }
      my $sql = "select distinct organism, md5s from " . $self->org_tbl($j) . $where;
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my ($org, $md5s) = @$row;
	  foreach my $m ( @$md5s ) {
	    $data->{$mg}->{$org}->{$m} = 1;
	  }
	}
      }
      $self->dbh->commit();
      $memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    } else {
      $data->{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;

  return $data;
  # mgid => org => { md5 }
}

sub get_ontol_md5 {
  my ($self, $eval, $ident, $alen, $source) = @_;

  my $memd = new Cache::Memcached {'servers' => [ $Conf::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "ontolmd5";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($source) ? $source : ":";

  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_src = ($source) ? "source = '$source'" : "";
  my $where = $self->get_where_str([$w_src, $eval, $ident, $alen]);
  my $data  = {};

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key);
    unless ($cdata) {
      unless ($self->ontol_tbl($j)) { next; }
      my $sql = "select distinct id, md5s from " . $self->ontol_tbl($j) . $where;
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my ($id, $md5s) = @$row;
	  foreach my $m ( @$md5s ) {
	    $data->{$mg}->{$id}->{$m} = 1;
	  }
	}
      }
      $self->dbh->commit();
      $memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    } else {
      $data->{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;

  return $data;
  # mgid => id => { md5 }
}

sub get_md5s_for_tax_level {
  my ($self, $level, $names) = @_;

  my $md5s = {};
  my $all  = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_organisms4level($level, $names);

  foreach my $j (values %{$self->jobs}) {
    my $ot = $self->org_tbl($j);
    if ($ot) {
      my $where = $all ? "" : " where organism in (" . join(",", map {$self->dbh->quote($_)} keys %$name_map) . ")";
      my $sql   = "select distinct organism, md5s from " . $ot . $where;
      my $rows  = $self->dbh->selectall_arrayref($sql);
      if ($rows && (@$rows)) {
	foreach my $r (@$rows) {
	  if ( $all && (! exists $name_map->{$r->[0]}) ) { next; }
	  foreach my $m (@{$r->[1]}) {
	    $md5s->{$m} = 1;
	  }
	}
      }
    }
  }
  return [ keys %$md5s ];
}

sub get_md5s_for_organism {
  my ($self, $name) = @_;

  my $md5s = [];
  foreach my $j (values %{$self->jobs}) {
    my $ot = $self->org_tbl($j);
    if ($ot) {
      my $row = $self->dbh->selectrow_arrayref("select md5s from $ot where organism = ".$self->dbh->quote($name));
      if ($row && (@$row > 0)) {
	@$md5s = @{$row->[0]};
      }
    }
  }
  return $md5s;
}

sub get_md5s_for_ontol_level {
  my ($self, $source, $level, $names) = @_;

  my $md5s = {};
  my $all  = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_ids4level($source, $level, $names);

  foreach my $j (values %{$self->jobs}) {
    my $ot = $self->ontol_tbl($j);
    if ($ot) {
      my $where = $all ? "" : " and id in (" . join(",", map {$self->dbh->quote($_)} keys %$name_map) . ")";
      my $sql   = "select distinct id, md5s from $ot where source = '$source'" . $where;
      my $rows  = $self->dbh->selectall_arrayref($sql);
      if ($rows && (@$rows)) {
	foreach my $r (@$rows) {
	  if ( $all && (! exists $name_map->{$r->[0]}) ) { next; }
	  foreach my $m (@{$r->[1]}) {
	    $md5s->{$m} = 1;
	  }
	}
      }
    }
  }
  return [ keys %$md5s ];
}

sub get_md5s_for_ontology {
  my ($self, $name, $source) = @_;

  my $md5s = [];
  foreach my $j (values %{$self->jobs}) {
    my $ot = $self->ontol_tbl($j);
    if ($ot) {
      my $row = $self->dbh->selectrow_arrayref("select md5s from $ot where source = '$source' and annotation = ".$self->dbh->quote($name));
      if ($row && (@$row > 0)) {
	@$md5s = @{$row->[0]};
      }
    }
  }
  return $md5s;
}
