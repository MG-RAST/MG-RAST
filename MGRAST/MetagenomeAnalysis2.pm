package MGRAST::MetagenomeAnalysis2;

use strict;
use warnings;
no warnings('once');

use List::Util qw(max min sum first);
use Global_Config;
use DBI;
use Data::Dumper;
use Babel::lib::Babel;

use Cache::Memcached;

1;

sub new {
  my ($class, $job_dbh) = @_;

  # get ach object
  my $ach = new Babel::lib::Babel;
  
  # connect to database
  my $dbh;
  eval {
    my $dbms     = $Global_Config::mgrast_dbms;
    my $host     = $Global_Config::mgrast_dbhost;
    my $database = $Global_Config::mgrast_db;
    my $user     = $Global_Config::mgrast_dbuser;
    my $password = $Global_Config::mgrast_dbpass;

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
	       tables => {}        # hash: job_id => table_type => table_name
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
# Internal Functions
####################

sub job_dir {
  my ($self, $job) = @_;
  return $job ? $Global_Config::mgrast_jobs . "/" . $job : '';
}

sub analysis_dir {
  my ($self, $job) = @_;
  return $job ? $self->job_dir($job) . "/analysis" : '';
}

sub fasta_file {
  my ($self, $job) = @_;
  return $job ? $self->job_dir($job) . "/raw/" . $job . ".fna" : '';
}

sub sim_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/900.loadDB.sims.filter.seq" : '';
}

sub source_stats_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/900.loadDB.source.stats" : '';
}

sub domain_stats_file {
  my ($self, $job) = @_;
  return $job ? $self->analysis_dir($job) . "/999.done.domain.stats" : '';
}

sub length_hist_file {
  my ($self, $job, $stage) = @_;

  if (lc($stage) eq 'raw') {
    return $job ? $self->fasta_file($job) . ".lens" : '';
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
    return $job ? $self->fasta_file($job) . ".gcs" : '';
  }
  elsif (lc($stage) eq 'qc') {
    return $job ? $self->analysis_dir($job) . "/299.screen.passed.fna.gcs" : '';
  }
  else {
    return '';
  }
}

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

=pod

=item * B<get_source_stats> (I<jobid>)

Retrieve the source stats for job id. Returns hash: source => type => [#, #, #, #, #]
  source: name of source
  type: 'evalue' or 'identity'
  #: abundance count for each of the 5 ranges

=cut 

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
}

=pod

=item * B<get_domain_stats> (I<jobid>)

Retrieve the domain stats for job id. Returns list: [ domain, # ]
  domain: name of domain
  #: abundance count

=cut 

sub get_domain_stats {
  my ($self, $jobid) = @_;

  my $data = [];
  my $file = $self->domain_stats_file($jobid);
  unless ($file && (-s $file)) { return $data; }

  open(FILE, "<$file") || return $data;
  while (my $line = <FILE>) {
    chomp $line;
    my @parts = split(/\t/, $line);
    push @$data, [ $parts[0], $parts[1] ];
  }
  close(FILE);

  return $data;
}

=pod

=item * B<get_histogram_nums> (I<jobid>)

Retrieve the histogram numbers for job id and type. Returns list: [ value, count ]
   type: length | gc

=cut 

sub get_histogram_nums {
  my ($self, $jobid, $type, $stage) = @_;

  my $file = "";
  my $data = [];
  $stage   = $stage ? $stage : 'raw';

  if ($type eq 'len') {
    $file = $self->length_hist_file($jobid, $stage);
  } elsif ($type eq 'gc') {
    $file = $self->gc_hist_file($jobid, $stage);
  } else {
    return $data;
  }
  unless ($file && (-s $file)) { return $data; }

  open(FILE, "<$file") || return $data;
  while (my $line = <FILE>) {
    chomp $line;
    my @parts = split(/\t/, $line);
    push @$data, [ $parts[0], $parts[1] ];
  }
  close(FILE);

  return $data;
}

=pod

=item * B<get_md5_sims> (I<jobid> I<md5 seeks>)

Input: [md5, seek, length]
Return: md5 => [sim lines]

=cut

sub get_md5_sims {
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

=pod

=item * B<reads_to_sequences> (I<ids>)

Retrieve the [ {id , sequence} ] from the metagenome job directory for I<ids>.

=cut

sub reads_to_sequences {
  my ($self, $ids) = @_;
  
  my $seqs   = [];
  my @recs   = [];
  my $id_str = join(",", map { (/^\d+$/) ? "lcl|$_" : $_ } @$ids);

  foreach my $j (values %{$self->jobs}) {
    my $fcmd   = "fastacmd -d " . $self->fasta_file($j) . " -s \"$id_str\" -l 0 -p F";
    my @result = `$fcmd 2>&1`;
    chomp @result;
    push @recs, @result;
  }

  my $head = "";
  my $seq  = "";
  foreach my $line (@recs) {
    if ((! $line) || ($line =~ /^\s+$/) || ($line =~ /^\[fastacmd\]/)) { next; }
    if ($line =~ /^>(\S+)/) {
      if ($seq && $head) { push @$seqs, { id => $head, sequence => $seq }; }
      $head = $1;
      $seq  = "";
    }
    else {
      $seq .= $line;
    }
  }
  push @$seqs, { id => $head, sequence => $seq };

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
  my $w_eval = (defined($eval) && ($eval =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  my $where  = $self->get_where_str([$w_org, $w_src, $w_eval, " p.md5 = ANY(o.md5s)", "seek IS NOT NULL", "length IS NOT NULL"]);
  my @data   = ();

  while ( my ($mg, $j) = each %{$self->jobs} ) {
    unless ($self->md5_tbl($j) && $self->org_tbl($j)) { next; }
    my $sql = "SELECT distinct p.md5,p.abundance,p.exp_avg,p.exp_stdv,p.ident_avg,p.ident_stdv,p.len_avg,p.len_stdv,p.seek,p.length " .
              "FROM " . $self->org_tbl($j) . " o, " . $self->md5_tbl($j) . " p" . $where . " ORDER BY seek";
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
  my ($self, $sources, $eval, $ident, $alen) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }

  my $raw_data = {};  # mgid => [ abundance ]
  my $mg_rare  = {};  # mgid => [ rare-x, rare-y ]
  my $get_m5nr = first {$_ =~ /^m5nr$/i} @$sources;

  if ($get_m5nr) {
    my $m5nr_map = $self->ach->sources4type("protein");
    @$sources = grep { (! exists $m5nr_map->{$_}) && ($_ !~ /m5nr/i) } @$sources;
    push @$sources, keys %$m5nr_map;
  }

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "rare";
  $cache_key .= defined($eval) ? $eval : ":";
  $cache_key .= defined($ident) ? $ident : ":";
  $cache_key .= defined($alen) ? $alen : ":";
  $cache_key .= defined($sources) ? join(";", @$sources) : ":";
  
  $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
  $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
  $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

  my $w_srcs = (@$sources > 0) ? "source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
  my $where  = $self->get_where_str([$w_srcs, $eval, $ident, $alen]);
  
  # get data set
  while ( my ($mg, $j) = each %{$self->jobs} ) {
    my $cdata = $memd->get($mg.$cache_key."orgs");
    unless ($cdata) {
      unless ($self->org_tbl($j)) { next; }
      my $set = {};
      my $sql = "select distinct organism, abundance from " . $self->org_tbl($j) . $where;
      my $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp > 0)) {
	foreach my $row ( @$tmp ) {
	  my @names = split(/ /, $row->[0]);
	  my $index = (scalar(@names) > 1) ? "$names[0] $names[1]" : $row->[0];
	  
	  if (exists $set->{$index}) {
	    $set->{$index} += $row->[1];
	  } else {
	    $set->{$index} = $row->[1];
	  }
	}
      }
      foreach my $num (values %$set) {
	push @{ $raw_data->{$mg} }, $num;
      }
      $memd->set($mg.$cache_key."orgs", $raw_data->{$mg}, 172800);
      
    } else {
      $raw_data->{$mg} = $cdata;
    }
  }

  # calculate rarefaction (x, y)
  foreach my $mg (keys %$raw_data) {
    my $cdata = $memd->get($mg.$cache_key."calc");
    unless ($cdata) {
      my @nums = sort {$a <=> $b} @{$raw_data->{$mg}};
      my $k    = scalar @nums;
      my $nseq = $self->get_seq_count($mg);
      
      unless ($nseq) { $mg_rare->{$mg} = []; next; }
      
      for (my $n = 0; $n < $nseq; $n += 100) {
	my $coeff = $self->nCr2ln($nseq, $n);
	my $curr  = 0;
	map { $curr += exp( $self->nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
	push @{ $mg_rare->{$mg} }, [ $n, $k - $curr ];
      }
      $memd->set($mg.$cache_key."calc", $mg_rare->{$mg}, 172800);

    } else {
      $mg_rare->{$mg} = $cdata;
    }
  }
  $memd->disconnect_all;
  
  return $mg_rare;
}

sub get_abundance_for_tax_level {
  my ($self, $level, $names) = @_;

  my $all = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_organisms4level($level, $names);
  return $self->get_abundance_for_hierarchy($name_map, "organism", $level, $all);
}

sub get_abundance_for_ontol_level {
  my ($self, $source, $level, $names) = @_;

  my $all = ($names && (@$names > 0)) ? 0 : 1;
  my $name_map = $self->ach->get_ids4level($source, $level, $names);
  return $self->get_abundance_for_hierarchy($name_map, "id", $level.$source, $all);
}

sub get_abundance_for_hierarchy {
  my ($self, $name_map, $type, $key, $all) = @_;

  my $data  = [];
  my $where = $all ? "" : " where $type in (" . join(",", map {$self->dbh->quote($_)} keys %$name_map) . ")";

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "abund".$type.$key;

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
      $sql = "select md5, abundance from " . $self->md5_tbl($j) . $w_md5s;
      $tmp = $self->dbh->selectall_arrayref($sql);
      if ($tmp && (@$tmp)) {
	foreach my $row ( @$tmp ) {
	  $md5s->{ $row->[0] } = $row->[1];
	}
      }
      
      foreach my $h (sort keys %$hier) {
	my $num = 0;
	map { $num += $md5s->{$_} } grep { exists $md5s->{$_} } keys %{ $hier->{$h} };
	push @$data, [ $mg, $h, $num ];
	push @$cdata, [ $mg, $h, $num ];
      }
      $self->dbh->commit();

      if ($all) {
	$memd->set($mg.$cache_key, $cdata, 172800);
      }
    } else {
      push @$data, @$cdata;
    }
  }
  $memd->disconnect_all;

  return $data;
  # mgid, taxa_name, abundance
}

sub get_organisms_for_sources {
  my ($self, $sources, $eval, $ident, $alen) = @_;
  return $self->get_organisms_for_md5s([], $sources, $eval, $ident, $alen);
}

sub get_organisms_for_md5s {
  my ($self, $md5s, $sources, $eval, $ident, $alen) = @_;

  unless ($sources && (@$sources > 0)) { $sources = []; }

  my %md5_set  = map {$_, 1} @$md5s;
  my $m5nr_map = {};
  my $get_m5nr = first {$_ =~ /^m5nr$/i} @$sources;
  my $mg_md5_abund = $self->get_md5_abundance();

  if ($get_m5nr) {
    $m5nr_map = $self->ach->sources4type("protein");
    @$sources = grep { (! exists $m5nr_map->{$_}) && ($_ !~ /m5nr/i) } @$sources;
    push @$sources, keys %$m5nr_map;
  }

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
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
	  if ($get_m5nr) {
	    my $src = exists($m5nr_map->{$row->[0]}) ? 'M5NR' : $row->[0];
	    push @{ $orgs{$src}{$row->[1]} }, [ @$row[2..9] ];
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
      if ($get_m5nr) {
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
	$memd->set($mg.$cache_key, $cdata, 172800);
	$memd->set($mg.$cache_key."orgs", [ keys %$corgs ], 172800);
	$memd->set($mg.$cache_key."md5s", $mdata{$mg}, 172800);
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

sub get_ontology_for_source {
  my ($self, $source, $eval, $ident, $alen) = @_;
  return $self->get_ontology_for_md5s([], $source, $eval, $ident, $alen);
}

sub get_ontology_for_md5s {
  my ($self, $md5s, $source, $eval, $ident, $alen) = @_;

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
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
	$memd->set($mg.$cache_key, $cdata, 172800);
	$memd->set($mg.$cache_key."md5s", $mdata{$mg}, 172800);
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

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::analysis_memcache || "140.221.76.21:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
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
	$memd->set($mg.$cache_key, $cdata, 172800);
      }
    } else {
      push @data, @$cdata;
    }
  }
  $memd->disconnect_all;

  return \@data;
  # mgid, source, function, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
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

  my $memd = new Cache::Memcached {'servers' => [ $Global_Config::web_memcache || "kursk-2.mcs.anl.gov:11211" ], 'debug' => 0, 'compress_threshold' => 10_000, };
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
	$memd->set($mg.$cache_key, $data->{$mg}, 172800);
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
  my ($self) = @_;

  my $data = {};
  my @sqls = ();
  foreach my $j (values %{$self->jobs}) {
    my $ot = $self->org_tbl($j);
    if ($ot) {
      push @sqls, "select distinct organism, md5s from " . $ot;
    }
  }
  if (@sqls > 0) {
    my $rows = $self->dbh->selectall_arrayref( join(" UNION ", @sqls) );
    if ($rows && (@$rows > 0)) {
      foreach my $r ( @$rows ) {
	my ($org, $md5s) = @$r;
	foreach my $m ( @$md5s ) {
	  $data->{$org}->{$m} = 1;
	}
      }
    }
  }
  return $data;
  # org => { md5 }
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
