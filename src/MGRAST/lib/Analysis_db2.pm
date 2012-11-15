package MGRAST::Analysis_db2;

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
  my ($class, $job_dbh, $dbh) = @_;

  # get ach object
  my $ach = new Babel::lib::Babel;
  
  # get memcache object
  my $memd = new Cache::Memcached {'servers' => [$Conf::web_memcache || "kursk-2.mcs.anl.gov:11211"], 'debug' => 0, 'compress_threshold' => 10_000};
  
  # connect to database

  unless ($dbh){
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

  }
  unless ($job_dbh && ref($job_dbh)) {
    warn "Unable to connect to job_cache database\n";
    return undef;
  }
  $dbh->{pg_expand_array} = 1;

  # create object
  my $self = { dbh     => $dbh,     # job data db_handle
	           ach     => $ach,     # ach/babel object
	           jcache  => $job_dbh, # job cache db_handle
	           memd    => $memd,    # memcached handle
	           jobs    => [],       # array: job_id	           
	           job_map => {},       # hash: mg_id => job_id
	           mg_map  => {},       # hash: job_id => mg_id
	           #jrna    => {},       # hash: job_id => rna_only
	           expire  => $Conf::web_memcache_expire || 172800, # use config or 48 hours
	           version => $Conf::m5nr_annotation_version || 1,
	           jtbl    => { md5          => 'job_md5s',
	                        ontology     => 'job_ontologies',
	                        function     => 'job_functions',
	                        organism     => 'job_organisms',
	                        rep_organism => 'job_rep_organisms',
	                        lca          => 'job_lcas' },
	           atbl    => { ontology     => 'ontologies',
	                        function     => 'functions',
	                        organism     => 'organisms_ncbi',
	                        rep_organism => 'organisms_ncbi' }
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

sub memd {
  my ($self) = @_;
  return $self->{memd};
}

sub jobs {
  my ($self) = @_;
  return $self->{jobs};
}

sub qjobs {
  my ($self) = @_;
  return "job IN (".join(',', @{$self->{jobs}}).")";
}

sub job_map {
  my ($self) = @_;
  return $self->{job_map};
}

sub mg_map {
  my ($self) = @_;
  return $self->{mg_map};
}

sub expire {
  my ($self) = @_;
  return $self->{expire};
}

sub version {
  my ($self) = @_;
  return $self->{version};
}

sub qver {
  my ($self) = @_;
  return "version = ".$self->{version};
}

sub jtbl {
  my ($self) = @_;
  return $self->{jtbl};
}

sub atbl {
  my ($self) = @_;
  return $self->{atbl};
}

sub has_job {
  my ($self, $mgid) = @_;
  return exists($self->job_map->{$mgid}) ? 1 : 0;
}

# add values to $self->{jobs} based on metagenome_id list
sub add_jobs {
  my ($self, $mgids) = @_;
  my @new_mg  = grep { ! $self->has_job($_) } @$mgids;
  my $new_map = $self->get_jobid_map(\@new_mg);
  %{ $self->{job_map} } = ( %{$self->{job_map}}, %$new_map );
  $self->set_data();
}

# set values for $self->{jobs} and $self->{jtbl} based on metagenome_id list
sub set_jobs {
  my ($self, $mgids, $jids) = @_;
  if (defined($jids)) {
    $self->{job_map} = $self->get_jobid_map($mgids, 1);
  } else {
    $self->{job_map} = $self->get_jobid_map($mgids);
  }
  $self->set_data();
}

sub set_data {
    my ($self) = @_;
    my %rev = reverse %{$self->{job_map}};
    $self->{mg_map} = \%rev;
    $self->{jobs} = values %{$self->{job_map}};
#    $self->{jrna} = $self->get_rna_state();
}

# populate obj with all public jobs
sub set_public_jobs {
  my ($self) = @_;
  my $mgids = $self->jcache->selectcol_arrayref("SELECT metagenome_id FROM Job WHERE public = 1 AND viewable = 1");
  if ($mgids && (@$mgids > 0)) {
    $self->set_jobs($mgids);
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

#sub get_rna_state {
#    my ($self) = @_;
#    my $jobs  = {};
#    my $where = $self->get_where_str(["rna_only IS TRUE", $self->qjobs, $self->qver]);
#    my $rows  = $self->dbh->selectcol_arrayref("SELECT job FROM job_info".$where);
#    %$jobs    = map { $_, 0 } values %{$self->{jobs}};
#    if ($rows && (@$rows > 0)) {
#        map { $jobs->{$_} = 1 } @$rows;
#    }
#    return $jobs;
#}

sub get_seq_count {
  my ($self, $mgid) = @_;
  my $sql  = "SELECT js.value FROM JobStatistics js, Job j WHERE j._id = js.job AND js.tag = 'sequence_count_raw' AND j.metagenome_id = '$mgid'";
  my $rows = $self->jcache->selectcol_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub get_all_job_ids {
  my ($self, $type) = @_;
  my $query = "SELECT DISTINCT job FROM job_info WHERE loaded IS TRUE AND ".$self->qver;
#  if ($type eq 'rna') {
#    $query .= " AND rna_only IS TRUE";
#  } elsif ($type eq 'protein') {
#    $query .= " AND rna_only IS FALSE";
#  }
  my $rows = $self->dbh->selectcol_arrayref($query);
  return ($rows && (@$rows > 0)) ? $rows : [];
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
# misc
####################

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

sub get_table_cols {
  my ($self, $table) = @_;
  my $sql  = "SELECT a.attname FROM pg_attribute a, pg_class c WHERE c.oid = a.attrelid AND a.attnum > 0 AND c.relname = '$table'";
  my $cols = $self->dbh->selectcol_arrayref($sql);
  return ($cols && (@$cols > 0)) ? $cols : [];
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
# All functions conducted on annotation tables
####################

sub get_annotation_map {
    my ($self, $type, $anns, $src) = @_;
    
    my $tbl = exists($self->atbl->{$type}) ? $self->atbl->{$type} : '';
    unless ($tbl && $anns && @$anns) { return {}; }
    
    my $amap = {};
    my $sql  = "SELECT _id, name FROM $tbl WHERE name IN (".join(",", map {$self->dbh->quote($_)} @$anns).")";
    if ($src && ($type eq 'ontology')) {
        $sql .= " AND type = ".$self->dbh->quote($src);
    }
    my $tmp  = $self->dbh->selectall_arrayref($sql);
    if ($tmp && @$tmp) {
        %$amap = map { $_->[0], $_->[1] } @$tmp;
    }
    return $amap;    
}

sub get_annotations4level {
    my ($self, $type, $level, $src, $get_ids) = @_;

    my $tbl = exists($self->atbl->{$type}) ? $self->atbl->{$type} : '';
    unless ($tbl && $level) { return {}; }

    my $key  = $get_ids ? '_id' : 'name';
    my $anns = {};
    my $qsrc = ($src && ($type eq 'ontology')) ? " WHERE type = ".$self->dbh->quote($src) : "";
    my @cols = grep { $_ eq $level } @{ $self->get_table_cols($tbl) };

    if (@cols == 1) {
        my $rows = $self->dbh->selectall_arrayref("SELECT DISTINCT $key, $level FROM ".$tbl.$qsrc);
        if ($rows && (@$rows > 0)) {
            %$anns = map { $_->[0], $_->[1] } grep { $_->[1] && ($_->[1] =~ /\S/) } @$rows;
        }
    }
    return $anns;
}

####################
# All functions conducted on individual job
####################

sub get_sources {
    my ($self, $mgid, $type) = @_;

    $self->set_jobs([$mgid]);
    my $where = $self->get_where_str([$self->qver, "job = ".$self->job_map->{$mgid}]);

    if ($type && exists($self->jtbl->{$type})) {
        my $srcs  = $self->dbh->selectcol_arrayref("SELECT DISTINCT source FROM ".$self->jtbl->{$type}.$where." ORDER BY source");
        return $srcs;
    } else {
        my $total = {};
        while ( my ($type, $name) = each %{$self->jtbl} ) {
            next if ($type =~ /^(md5|lca)$/);
            my $srcs = $self->dbh->selectcol_arrayref("SELECT DISTINCT source FROM ".$name.$where);
            map { $total->{$_} = 1 } @$srcs;
        }
        return [ sort keys %$total ];
    }
    # [ source ]
}

sub md5_abundance_for_annotations {
    my ($self, $mgid, $type, $srcs, $anns) = @_;

    $self->set_jobs([$mgid]);
    my $job = $self->job_map->{$mgid};
    my $tbl = exists($self->jtbl->{$type}) ? $self->jtbl->{$type} : '';
    unless ($tbl) { return {}; }

    my $amap = {};
    if ($anns && @$anns) {
        $amap = $self->get_annotation_map($type, $anns);
        if (scalar(keys %$amap)) { return {}; }
    }
  
    my $data  = {};
    my $qsrc  = ($srcs && @$srcs) ? "t.source IN (".join(",", map {$self->dbh->quote($_)} @$srcs).")" : '';
    my $qids  = (scalar(keys %$amap) > 0) ? "t.id IN (".join(",", keys %$amap).")" : '';
    my $where = $self->get_where_str(["t.".$self->qver, "m.".$self->qver, "t.job = $job", "m.job = $job", "m.md5 = ANY(t.md5s)", $qsrc, $qids]);
    my $sql   = "SELECT DISTINCT t.id, m.md5, m.abundance FROM $tbl t, job_md5s m".$where;
    my $rows  = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
        map { $data->{ $amap->{$_->[0]} }->{$_->[1]} = $_->[2] } @$rows;
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
    } elsif ($type eq 'protein') {
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
    } else {
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

    my $jtbl = exists($self->jtbl->{$type}) ? $self->jtbl->{$type} : '';
    my $atbl = exists($self->atbl->{$type}) ? $self->atbl->{$type} : '';
    unless ($jtbl && $atbl) { return []; }

    my $jobs  = {};
    my $qsrc  = ($srcs && @$srcs) ? "j.source IN (".join(",", map {$self->dbh->quote($_)} @$srcs).")" : "";
    my $qann  = "a.name ".($exact ? '= ' : '~* ').$self->dbh->quote($ann);
    my $where = $self->get_where_str(['j.'.$self->qver, "j.id = a._id", $qsrc, $qann]);
    my $rows  = $self->dbh->selectcol_arrayref("SELECT DISTINCT j.job FROM $jtbl j, $atbl a".$where);
    unless ($rows && (@$rows > 0)) {
        return [];
    }
    # [ mgid ]
    return [ keys %{$self->get_jobid_map($rows, 1)} ];
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
    while ( my ($mg, $j) = each %{$self->job_map} ) {
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

    my $w_md5s = ($md5s && (@$md5s > 0)) ? "md5 IN (".join(",", map {"'$_'"} @$md5s).")" : "";
    my $where  = $self->get_where_str([$w_md5s, $self->qver, $self->qjobs, $eval, $ident, $alen, "seek IS NOT NULL", "length IS NOT NULL"]);
    my $data   = {};
    my $seqs   = [];

    unless ($w_md5s || $eval || $ident || $alen) { return $self->all_read_sequences(); }

    my $sql  = "SELECT job, md5, seek, length FROM ".$self->jtbl->{md5}.$where." ORDER BY job, seek";
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
        map { push @{ $data->{$_->[0]} }, [$_->[1], $_->[2], $_->[3]] } @$rows;
    }
    while ( my ($j, $info) = each %$data ) {
        open(FILE, "<" . $self->sim_file($j)) || next;
        foreach my $set (@$info) {
	        my ($md5, $seek, $len) = @$set;
	        my $rec = '';
	        seek(FILE, $seek, 0);
	        read(FILE, $rec, $len);
	        chomp $rec;
	        foreach my $line ( split(/\n/, $rec) ) {
	            my @tabs = split(/\t/, $line);
	            if (@tabs == 13) {
	                push @$seqs, { md5 => $md5, id => $self->mg_map->{$j}."|".$tabs[0], sequence => $tabs[12] };
	            }
	        }
        }
        close FILE;
    }
    return $seqs;
}

sub get_abundance_for_organism_source {
    my ($self, $org, $src) = @_;

    my $qorg  = "a.name = ".$self->dbh->quote($org);
    my $qsrc  = "j.source = ".$self->dbh->quote($src);
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qorg, $qsrc]);
    my $sql   = "SELECT SUM(j.abundance) FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    my $sum   = $self->dbh->selectcol_arrayref($sql);
    return ($sum && (@$sum > 0)) ? $sum->[0] : 0;
}

sub get_organism_abundance_for_source {
    my ($self, $src) = @_;

    my $qsrc  = "j.source = ".$self->dbh->quote($src);
    my $data  = {};
        my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qsrc]);
    my $sql   = "SELECT a.name, SUM(j.abundance) FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where." GROUP BY a.name";
    my $rows  = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
        %$data = map { $_->[0], $_->[1] } @$rows;
    }
    # org => abund
    return $data;
}

sub get_organisms_with_contig_for_source {
    my ($self, $src, $num, $len) = @_;

    my $job_orgs = $self->get_organism_abundance_for_source($src);
    my @job_ctgs = map { [$_->[0], $_->[1], $job_orgs->{$_->[1]}] } grep { exists $job_orgs->{$_->[1]} } @{ $self->ach->get_organism_with_contig_list($num, $len) };
    return \@job_ctgs;
}

sub get_md5_evals_for_organism_source {
    my ($self, $org, $src) = @_;

    my $data  = {};
    my $qorg  = "a.name = ".$self->dbh->quote($org);
    my $qsrc  = "j.source = ".$self->dbh->quote($src);
    my $where = $self->get_where_str(['j.'.$self->qver, 'm.'.$self->qver, 'j.'.$self->qjobs, 'm.'.$self->qjobs, "j.id = a._id", "m.md5 = ANY(j.md5s)", $qorg, $qsrc]);
    my $sql  = "SELECT DISTINCT m.md5, m.evals FROM ".$self->jtbl->{md5}." m, ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
        foreach my $r (@$rows) {
            my ($md5, $evals) = @$r;
            if (exists $data->{$md5}) {
	            for (my $i=0; $i<@$evals; $i++) { $data->{$md5}->[$i] += $evals->[$i]; }
            } else {
	            $data->{$md5} = $evals;
            }
        }
    }
    # md5 => [ eval ]
    return $data;
}

sub get_md5_data_for_organism_source {
    my ($self, $org, $src, $eval) = @_;

    my $qorg  = "a.name = ".$self->dbh->quote($org);
    my $qsrc  = "j.source = ".$self->dbh->quote($src);
    my $qeval = (defined($eval) && ($eval =~ /^\d+$/)) ? "m.exp_avg <= ".($eval * -1) : "";
    my $where = $self->get_where_str([ 'j.'.$self->qver, 'm.'.$self->qver, 'j.'.$self->qjobs, 'm.'.$self->qjobs, "j.id = a._id",
                                       "m.md5 = ANY(j.md5s)", $qorg, $qsrc, $qeval, "m.seek IS NOT NULL", "m.length IS NOT NULL"]);
    my $sql  = "SELECT DISTINCT m.job,m.md5,m.abundance,m.exp_avg,m.exp_stdv,m.ident_avg,m.ident_stdv,m.len_avg,m.len_stdv,m.seek,m.length FROM " .
                $self->jtbl->{md5}." m, ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where." ORDER BY m.seek";
    my $rows = $self->dbh->selectall_arrayref($sql);
    if ($rows && (@$rows > 0)) {
        map { $_->[0] = $self->mg_map->{$_->[0]} } @$rows;
        return $rows;
    } else {
        return [];
    }
    # [ mgid, md5, abund, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length ]
}

sub get_rarefaction_curve {
    my ($self, $srcs, $get_alpha) = @_;

    unless ($srcs && @$srcs) { $srcs = []; }

    my $raw_data  = {};  # mgid => species => abundance
    my $mg_alpha  = {};  # mgid => alpha diversity
    my $mg_rare   = {};  # mgid => [ rare-x, rare-y ]
    my $mg_abund  = $self->get_abundance_for_tax_level('tax_species', undef, $srcs);  # [mgid, species, abundance]
    my $cache_key = 'rarefaction'.join(':', @$srcs);

    map { $raw_data->{$_->[0]}->{$_->[1]} = $_->[2] } @$mg_abund;
  
    # calculate alpha diversity
    if ($get_alpha) {
        foreach my $mg (keys %$raw_data) {
            my $cdata = $self->memd->get($mg.$cache_key."alpha");
            unless ($cdata) {
	            my $h1  = 0;
	            my $sum = sum values %{$raw_data->{$mg}};
	            unless ($sum) {
	                $mg_alpha->{$mg} = 0;
	                $self->memd->set($mg.$cache_key."alpha", 0, $self->expire);
	                next;
	            }
	            foreach my $num (values %{$raw_data->{$mg}}) {
	                my $p = $num / $sum;
	                if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
	            }
	            $mg_alpha->{$mg} = 2 ** $h1;
	            $self->memd->set($mg.$cache_key."alpha", $mg_alpha->{$mg}, $self->expire);
            } else {
                $mg_alpha->{$mg} = $cdata;
            }
        }
        # mgid => alpha-diver
        return $mg_alpha;
    }

    # calculate rarefaction (x, y)
    foreach my $mg (keys %$raw_data) {
        my $cdata = $self->memd->get($mg.$cache_key."curve");
        unless ($cdata) {
            my @nums = sort {$a <=> $b} values %{$raw_data->{$mg}};
            my $k    = scalar @nums;
            my $nseq = $self->get_seq_count($mg);
            my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
            unless ($nseq) {
	            $mg_rare->{$mg} = [];
	            $self->memd->set($mg.$cache_key."curve", [], $self->expire);
	            next;
            }
            for (my $n = 0; $n < $nseq; $n += $size) {
	            my $coeff = $self->nCr2ln($nseq, $n);
	            my $curr  = 0;
	            map { $curr += exp( $self->nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
	            push @{ $mg_rare->{$mg} }, [ $n, $k - $curr ];
            }
            $self->memd->set($mg.$cache_key."curve", $mg_rare->{$mg}, $self->expire);
        } else {
            $mg_rare->{$mg} = $cdata;
        }
    }
    # mgid => [ x, y ]
    return $mg_rare;
}

sub get_abundance_for_tax_level {
    my ($self, $level, $names, $srcs, $value) = @_;

    my $name_map = $self->get_annotations4level("organism", $level, undef, 1);
    my $src_str  = @$srcs ? join("", @$srcs) : '';
    return $self->get_abundance_for_hierarchy($name_map, "organism", $level.$src_str, $srcs, $value);
}

sub get_abundance_for_ontol_level {
    my ($self, $level, $names, $src, $value) = @_;
  
    my $name_map = $self->get_annotations4level("ontology", $level, $src, 1);
    return $self->get_abundance_for_hierarchy($name_map, "ontology", $level.$src, [$src], $value);
}

sub get_abundance_for_hierarchy {
    my ($self, $name_map, $type, $key, $srcs, $value) = @_;

    unless ($value) { $value = "abundance"; }
    my $data  = [];
    my $qsrcs = (@$srcs > 0) ? "source IN (".join(",", map {"'$_'"} @$srcs).")" : "";
    my $cache_key = $value.$type.$key;

    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $cdata = $self->memd->get($mg.$cache_key);
        if ($cdata) { push @$data, @$cdata; }
        else        { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    # get for jobs
    my $hier  = {};
    my $curr  = 0;
    my $where = $self->get_where_str([$self->qver, "job IN (".join(",", @$jobs).")", $qsrcs]);
    my $sql   = "SELECT DISTINCT job, id, md5s FROM ".$self->jtbl->{organism}.$where." ORDER BY job";
    my ($job, $id, $md5);
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        ($job, $id, $md5) = @$row;
        next unless(exists $name_map->{$id});
        unless ($curr) { $curr = $job; }
        if ($curr != $job) {
            my %md5s  = map { $_->[0], $_->[1] } @{ $self->dbh->selectall_arrayref("SELECT md5, $value FROM ".$self->jtbl->{md5}." WHERE ".$self->qver." AND job=".$curr) };
            my $cdata = [];
            foreach my $h (sort keys %$hier) {
                my $num   = 0;
            	my $count = 0;
            	map { $num += $md5s{$_}; $count += 1; } grep { exists $md5s{$_} } keys %{ $hier->{$h} };
            	if (($value ne "abundance") && ($count > 0)) {
            	    $num = ($num * 1.0) / $count;
            	}
            	push @$data, [ $self->mg_map->{$curr}, $h, $num ];
            	push @$cdata, [ $self->mg_map->{$curr}, $h, $num ];
            }
            $self->memd->set($self->mg_map->{$curr}.$cache_key, $cdata, $self->expire);
            # reset
            $hier = {};
            $curr = $job;
        }
        map { $hier->{$name_map->{$id}}{$_} = 1 } @$md5;
    }
    # get last job
    if (scalar(keys %$hier) > 0) {
        my %md5s  = map { $_->[0], $_->[1] } @{ $self->dbh->selectall_arrayref("SELECT md5, $value FROM ".$self->jtbl->{md5}." WHERE ".$self->qver." AND job=".$job) };
        my $cdata = [];
        foreach my $h (sort keys %$hier) {
            my $num   = 0;
        	my $count = 0;
        	map { $num += $md5s{$_}; $count += 1; } grep { exists $md5s{$_} } keys %{ $hier->{$h} };
        	if (($value ne "abundance") && ($count > 0)) {
        	    $num = ($num * 1.0) / $count;
        	}
        	push @$data, [ $self->mg_map->{$job}, $h, $num ];
        	push @$cdata, [ $self->mg_map->{$job}, $h, $num ];
        }
        $self->memd->set($self->mg_map->{$job}.$cache_key, $cdata, $self->expire);
    }

    return $data;
    # [ mgid, taxa_name, abundance ]
}

sub get_abundance_for_set {
    my ($self, $set, $type, $srcs) = @_;

    unless ($set && (@$set > 0) && exists($self->jtbl->{$type})) { return {}; }

    my $data = {};
    foreach my $mg (keys %{$self->job_map}) {
        map { $data->{$mg}{$_} = [ 0 ] } @$set;
    }
    my $qterm = "a.name IN (".join(", ", map { $self->dbh->quote($_) } @$set).")";
    my $qsrcs = (@$srcs > 0) ? "j.source IN (".join(",", map {"'$_'"} @$srcs).")" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qsrcs, $qterm]);
    my $sql   = "SELECT DISTINCT j.job, a.name, j.abundance FROM ".$self->jtbl->{$type}." j, ".$self->atbl->{$type}." a".$where;

    map { push @{ $data->{ $self->mg_map->{$_->[0]} }{$_->[1]} }, $_->[2] } @{ $self->dbh->selectall_arrayref($sql) };
    my $results = {};
    foreach my $mg (keys %$data) {
        map { $results->{$mg}{$_} = max @{ $data->{$mg}{$_} } } keys %{$data->{$mg}};
    }

    return $results;
    # mgid => annotation => abundance
}

sub get_rank_abundance {
    my ($self, $limit, $type, $srcs) = @_;
    
    unless ($limit && exists($self->jtbl->{$type})) { return []; }
    
    my $data  = {};
    my $qsrcs = (@$srcs > 0) ? "j.source IN (" . join(",", map {"'$_'"} @$srcs) . ")" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qsrcs]);
    my $sql   = "SELECT DISTINCT j.job, a.name, j.abundance FROM ".$self->jtbl->{$type}." j, ".$self->atbl->{$type}." a".$where;
    
    map { push @{ $data->{ $self->mg_map->{$_->[0]} }{$_->[1]} }, $_->[2] } @{ $self->dbh->selectall_arrayref($sql) };
    my $results = {};
    foreach my $mg (keys %$data) {
        my @ranked = map { [ $_, max @{$data->{$mg}{$_}} ] } keys %{$data->{$mg}};
        @ranked    = sort { ($b->[1] <=> $a->[1]) || ($a->[0] cmp $b->[0]) } @ranked;
        $results->{$mg} = [ @ranked[0..($limit-1)] ];
    }

    return $results;
    # mgid => [ annotation, abundance ]
}

sub get_set_rank_abundance {
    my ($self, $limit, $type, $srcs, $all) = @_;

    unless ($limit && exists($self->jtbl->{$type})) { return []; }
  
    my $qsrcs = (@$srcs > 0) ? "j.source IN (" . join(",", map {"'$_'"} @$srcs) . ")" : "";
    my $qjobs = $all ? '' : 'j.'.$self->qjobs;
    my $where = $self->get_where_str(['j.'.$self->qver, $qjobs, "j.id = a._id", $qsrcs]);
    my $qlim  = "LIMIT ".($limit * scalar(@$srcs));
    my $sql   = "SELECT DISTINCT a.name SUM(j.job) FROM ".$self->jtbl->{$type}." j, ".$self->atbl->{$type}." a".$where." GROUP BY j.job ORDER BY SUM(j.job) DESC ".$limit;
    my $data  = $self->dbh->selectall_arrayref($sql);
    
    return ($data && @$data) ? $data : [];
    map { $data->{$_->[1]} += 1 } @{ $self->dbh->selectall_arrayref($sql) };
    my @results = map { [$_, $data->{$_}] } keys %$data;
    @results    = sort { ($b->[1] <=> $a->[1]) || ($a->[0] cmp $b->[0]) } @results;
    @results    = @results[0..($limit-1)];
  
    return \@results;
    # [ annotation, job_count ]
}

sub get_global_rank_abundance {
    my ($self, $limit, $type, $src) = @_;
    return $self->get_set_rank_abundance($limit, $type, [$src], 1)
}

sub search_organisms {
    my ($self, $text) = @_;

    my $cache_key = "org_search".quotemeta($text);
    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $cdata = $self->memd->get($mg.$cache_key);
        if ($cdata) { $data->{$mg} = $cdata; }
        else        { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", "a.name ~* ".$self->dbh->quote($text)]);
    my $sql   = "SELECT DISTINCT j.job, j.source, a.name, j.abundance FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        push @{ $data->{ $self->mg_map->{$row->[0]} } }, @$row[1,2,3];
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return $data;
    # mgid => [ source, organism, abundance ]
}

sub get_organisms_unique_for_source {
    my ($self, $source, $eval, $ident, $alen) = @_;

    my $all_orgs    = {};
    my $mg_org_data = {};
    # mgid => org => [ count_md5s, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, [md5s] ]
    my $mg_md5_data = $self->get_md5_data(undef, $eval, $ident, $alen, 1, $source);
    # [ mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, rep_org_id ]

    foreach my $row (@$mg_md5_data) {
        my $org = $row->[9];
        $all_orgs->{$org} = 1;
        if (exists $mg_org_data->{$row->[0]}{$org}) {
            $mg_org_data->{$row->[0]}{$org}[0] += 1;
            $mg_org_data->{$row->[0]}{$org}[1] += $row->[2];
            $mg_org_data->{$row->[0]}{$org}[2] += $row->[3];
            $mg_org_data->{$row->[0]}{$org}[3] += $row->[4];
            $mg_org_data->{$row->[0]}{$org}[4] += $row->[5];
            $mg_org_data->{$row->[0]}{$org}[5] += $row->[6];
            $mg_org_data->{$row->[0]}{$org}[6] += $row->[7];
            $mg_org_data->{$row->[0]}{$org}[7] += $row->[8];
            push @{ $mg_org_data->{$row->[0]}{$org}[8] }, $row->[1];
        } else {
            $mg_org_data->{$row->[0]}{$org} = [ 1, @$row[2..8], [$row->[1]] ];
        }
    }

    my $tax = {};
    my $sql = "SELECT _id,COALESCE(tax_domain,'unassigned') AS txd,COALESCE(tax_phylum,'unassigned') AS txp,COALESCE(tax_class,'unassigned') AS txc,".
              "COALESCE(tax_order,'unassigned') AS txo,COALESCE(tax_family,'unassigned') AS txf,COALESCE(tax_genus,'unassigned') AS txg,".
              "COALESCE(tax_species,'unassigned') AS txs,name FROM ".$self->atbl->{organism}." WHERE _id IN (".join(',', keys %$all_orgs).")";
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $oid = pop @$row;
        $tax->{$oid} = $row;
    }
    
    my $result = [];
    foreach my $mgid (keys %$mg_org_data) {
        foreach my $oid (keys %{$mg_org_data->{$mgid}}) {
            my $stats = $mg_org_data->{$mgid}{$oid};
            my $total = $stats->[0];
            my $abund = $stats->[1];
            my $md5s  = $stats->[8];
            my ($ea, $es, $ia, $is, $la, $ls) = (($stats->[2] / $total),($stats->[3] / $total),($stats->[4] / $total),($stats->[5] / $total),($stats->[6] / $total),($stats->[7] / $total));
            if (exists $tax->{$oid}) {
	            push @$result, [ $mgid, @{$tax->{$oid}}, $abund, $ea, $es, $ia, $is, $la, $ls, $md5s ];
            }
        }
    }
    return $result;
    # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub get_organisms_for_sources {
    my ($self, $sources, $eval, $ident, $alen) = @_;
    return $self->get_organisms_for_md5s([], $sources, $eval, $ident, $alen);
}

sub get_organisms_for_md5s {
    my ($self, $md5s, $sources, $eval, $ident, $alen) = @_;

    my $cache_key = "org";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($sources) ? join(";", @$sources) : ":";

    my $data  = {};
    my $jobs  = [];
    my %mdata = ();
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->job_map} ) {
            my $c = $self->memd->get($mg.$cache_key);
            my $m = $self->memd->get($mg.$cache_key."md5s");
            if ($c && $m) {
                $data->{$mg} = $c;
                $mdata{$mg}  = $m;
            } else {
                push @$jobs, $j;
            }
        }
    }
  
    my %md5_set = map {$_, 1} @$md5s;
    my $mg_md5_abund = $self->get_md5_abundance();
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $qsrcs = ($sources && (@$sources > 0)) ? "j.source IN (" . join(",", map {"'$_'"} @$sources) . ")" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $tax = "COALESCE(a.tax_domain,'unassigned') AS txd,COALESCE(a.tax_phylum,'unassigned') AS txp,COALESCE(a.tax_class,'unassigned') AS txc,".
              "COALESCE(a.tax_order,'unassigned') AS txo,COALESCE(a.tax_family,'unassigned') AS txf,COALESCE(a.tax_genus,'unassigned') AS txg,".
              "COALESCE(a.tax_species,'unassigned') AS txs,a.name";
    my $sql = "SELECT DISTINCT j.job,j.source,$tax,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s FROM ".
              $self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;

    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $sub_abund = 0;
        my $mg = $self->mg_map($row->[0]);
        if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row->[17]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;
	    } else {
	        $sub_abund = $row->[10];
	    }
	    push @{$data->{$mg}}, [ $mg, @$row[1..10], $sub_abund, @$row[11..16], join(";", @{$row->[17]}) ];
	    map { $mdata{$mg}{$_} = $mg_md5_abund->{$mg}{$_} } grep { exists $mg_md5_abund->{$mg}{$_} } @{$row->[17]};
    }
    unless ($qmd5s) {
        foreach my $mg (keys %$data) {
	        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
	        $self->memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->expire);
	    }
    }
    
    return (\%mdata, [ map { @$_ } values %$data ]);
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

    my $cache_key = "ontol_search".quotemeta($text);
    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", "a.name ~* ".$self->dbh->quote($text)]);
    my $sql   = "SELECT DISTINCT j.job, j.source, a.name, j.abundance FROM ".$self->jtbl->{ontology}." j, ".$self->atbl->{ontology}." a".$where;
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        push @{ $data->{ $self->mg_map->{$row->[0]} } }, @$row[1,2,3];
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return $data;
    # mgid => [ source, organism, abundance ]
}

sub get_ontology_for_source {
    my ($self, $source, $eval, $ident, $alen) = @_;
    return $self->get_ontology_for_md5s([], $source, $eval, $ident, $alen);
}

sub get_ontology_for_md5s {
    my ($self, $md5s, $source, $eval, $ident, $alen) = @_;
    
    my $cache_key = "ontol";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($source) ? $source : ":";

    my $data  = {};
    my $jobs  = [];
    my %mdata = ();
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->job_map} ) {
            my $c = $self->memd->get($mg.$cache_key);
            my $m = $self->memd->get($mg.$cache_key."md5s");
            if ($c && $m) {
                $data->{$mg} = $c;
                $mdata{$mg}  = $m;
            } else {
                push @$jobs, $j;
            }
        }
    }

    my %md5_set = map {$_, 1} @$md5s;
    my $mg_md5_abund = $self->get_md5_abundance();
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $level = "COALESCE(a.level4, a.level3) as annotation";
    my $qsrcs = ($source) ? "source = '$source'" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,a.name,$level,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s FROM ".
              $self->jtbl->{ontology}." j, ".$self->atbl->{ontology}." a".$where;

    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $sub_abund = 0;
        my $mg = $self->mg_map($row->[0]);
	    if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row->[10]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;        
	    } else {
	        $sub_abund = $row->[3];
	    }
	    push @{$data->{$mg}}, [ $mg, @$row[1..3], $sub_abund, @$row[4..9], join(";", @{$row->[10]}) ];
	    map { $mdata{$mg}{$_} = $mg_md5_abund->{$mg}{$_} } grep { exists $mg_md5_abund->{$mg}{$_} } @{$row->[10]};
    }
    unless ($qmd5s) {
        foreach my $mg (keys %$data) {
	        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
	        $self->memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->expire);
	    }
    }

    return (\%mdata, [ map { @$_ } values %$data ]);
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
    my $cache_key = "func";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($sources) ? join(";", @$sources) : ":";

    my $data  = {};
    my $jobs  = [];
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->job_map} ) {
            my $c = $self->memd->get($mg.$cache_key);
            if ($c) { $data->{$mg} = $c; }
            else    { push @$jobs, $j; }
        }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }

    my %md5_set = map {$_, 1} @$md5s;
    my $mg_md5_abund = ($qmd5s) ? $self->get_md5_abundance() : {};
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $qsrcs = (@$sources > 0) ? "j.source in (" . join(",", map {"'$_'"} @$sources) . ")" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,j.source,a.name,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s FROM ".
              $self->jtbl->{function}." j, ".$self->atbl->{function}." a".$where;        

    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $sub_abund = 0;
        my $mg = $self->mg_map($row->[0]);
        
        if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row->[10]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;        
	    } else {
	        $sub_abund = $row->[3];
	    }
	    push @{$data->{$mg}}, [ $mg, @$row[1..3], $sub_abund, @$row[4..9], join(";", @{$row->[10]}) ];
    }
    unless ($qmd5s) {
        foreach my $mg (keys %$data) {
	        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
	    }
    }

    return [ map { @$_ } values %$data ];
    # mgid, source, function, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub get_lca_data {
    my ($self, $eval, $ident, $alen) = @_;
    
    my $cache_key = "lca";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";

    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
    
    my $where = $self->get_where_str([$self->qver, "job IN (".join(",", @$jobs).")", $eval, $ident, $alen]);
    my $sql   = "SELECT DISTINCT job,lca,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv FROM ".$self->jtbl->{lca}.$where;

    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $mg  = $self->mg_map($row->[0]);
        my @tax = ('-','-','-','-','-','-','-','-');
        my @lca = split(/;/, $row->[1]);
        for (my $i=0; $i<@lca; $i++) {
    	    $tax[$i] = $lca[$i];
        }
        push @{$data->{$mg}}, [ $mg, @tax, @$row[2..8] ];
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }
    
    return [ map { @$_ } values %$data ];
    # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
}

sub get_md5_data {
    my ($self, $md5s, $eval, $ident, $alen, $ignore_sk, $rep_org_src) = @_;

    my $cache_key = "md5data";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";

    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";
  
    my $qmd5s = ($md5s && (@$md5s > 0)) ? "j.md5 IN (" . join(",", map {"'$_'"} @$md5s) . ")" : "";
    my $qseek = $ignore_sk ? "" : "j.seek IS NOT NULL AND j.length IS NOT NULL";
    my $qrep  = $rep_org_src ? "j.md5=r.md5 AND r.source='$rep_org_src'" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", $qrep, $qmd5s, $eval, $ident, $alen, $qseek]);
    my $cseek = $ignore_sk ? "" : ",j.seek,j.length";
    my $crep  = $rep_org_src ? ",r.organism" : "";
    my $sql   = "SELECT DISTINCT j.job,j.md5,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv${cseek}${crep} FROM ".
                $self->jtbl->{md5}." j".($rep_org_src ? ", md5_organism_unique r" : "").$where.($ignore_sk ? "" : " ORDER BY job, seek");
    
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {        
        my $j  = pop @$row;
        my $mg = $self->mg_map($j);
        push @{ $data->{$mg} }, [ $mg, @$row ];
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return [ map { @$_ } values %$data ];
    # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, (seek, length || rep_org_id)
}

sub get_md5_abundance {
    my ($self, $eval, $ident, $alen, $md5s) = @_;

    my $cache_key = "md5abund";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";

    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
  
    my $qmd5s = ($md5s && (@$md5s > 0)) ? "md5 IN (" . join(",", map {"'$_'"} @$md5s) . ")" : "";
    my $where = $self->get_where_str([$self->qver, "job IN (".join(",", @$jobs).")", $qmd5s, $eval, $ident, $alen]);
    my $sql   = "SELECT DISTINCT job, md5, abundance FROM ".$self->jtbl->{md5}.$where;

    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        $data->{ $self->mg_map($row->[0]) }{$row->[1]} = $row->[2];
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return $data;
    # mgid => md5 => abundance
}

sub get_org_md5 {
    my ($self, $eval, $ident, $alen, $sources) = @_;
    
    my $cache_key = "orgmd5";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($sources) ? join(";", @$sources) : ":";

    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $qsrcs = ($sources && (@$sources > 0)) ? "j.source IN (" . join(",", map {"'$_'"} @$sources) . ")" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,a.name,j.md5s FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $mg = $self->mg_map($row->[0]);
        map { $data->{$mg}{$row->[1]}{$_} = 1 } @{ $row->[2] };
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return $data;
    # mgid => org => { md5 }
}

sub get_ontol_md5 {
    my ($self, $eval, $ident, $alen, $source) = @_;

    my $cache_key = "ontolmd5";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($source) ? $source : ":";
    
    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->job_map} ) {
        my $c = $self->memd->get($mg.$cache_key);
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";
    
    my $qsrcs = ($source) ? "j.source = '$source'" : "";
    my $where = $self->get_where_str(['j.'.$self->qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,a.name,j.md5s FROM ".$self->jtbl->{ontology}." j, ".$self->atbl->{ontology}." a".$where;
    
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        my $mg = $self->mg_map($row->[0]);
        map { $data->{$mg}{$row->[1]}{$_} = 1 } @{ $row->[2] };
    }
    foreach my $mg (keys %$data) {
        $self->memd->set($mg.$cache_key, $data->{$mg}, $self->expire);
    }

    return $data;
    # mgid => id => { md5 }
}

sub get_md5s_for_tax_level {
    my ($self, $level, $names) = @_;

    my $data = {};
    my $all  = ($names && (@$names > 0)) ? 0 : 1;
    my $name_map = $self->ach->get_organisms4level($level, $names);
    
    my $qname = $all ? "" : "a.name IN (".join(",", map {$self->dbh->quote($_)} keys %$name_map).")";
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qname]);
    my $sql   = "SELECT a.name, j.md5s FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        next if ( $all && (! exists $name_map->{$row->[0]}) );
        map { $data->{$_} = 1 } @{$row->[1]};
    }
    return [ keys %$data ];
    # [ md5 ]
}

sub get_md5s_for_organism {
    my ($self, $name) = @_;
    
    my $data  = {};
    my $qname = "a.name = ".$self->dbh->quote($name);
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qname]);
    my $sql   = "SELECT j.md5s FROM ".$self->jtbl->{organism}." j, ".$self->atbl->{organism}." a".$where;
    foreach my $md5s (@{ $self->dbh->selectcol_arrayref($sql) }) {
        map { $data->{$_} = 1 } @$md5s;
    }
    return [ keys %$data ];
    # [ md5 ]
}

sub get_md5s_for_ontol_level {
    my ($self, $source, $level, $names) = @_;

    my $data = {};
    my $all  = ($names && (@$names > 0)) ? 0 : 1;
    my $name_map = $self->ach->get_ids4level($source, $level, $names);

    my $qname = $all ? "" : "a.name IN (".join(",", map {$self->dbh->quote($_)} keys %$name_map).")";
    my $qsrc  = ($source) ? "j.source = ".$self->dbh->quote($source) : "";
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qname, $qsrc]);
    my $sql   = "SELECT a.name, j.md5s FROM ".$self->jtbl->{ontology}." j, ".$self->atbl->{ontology}." a".$where;
    
    foreach my $row (@{ $self->dbh->selectall_arrayref($sql) }) {
        next if ( $all && (! exists $name_map->{$row->[0]}) );
        map { $data->{$_} = 1 } @{$row->[1]};
    }
    return [ keys %$data ];
    # [ md5 ]
}

sub get_md5s_for_ontology {
    my ($self, $name, $source) = @_;

    my $data  = {};
    my $qname = "a.name = ".$self->dbh->quote($name);
    my $qsrc  = ($source) ? "j.source = ".$self->dbh->quote($source) : "";
    my $where = $self->get_where_str(['j.'.$self->qver, 'j.'.$self->qjobs, "j.id = a._id", $qname, $qsrc]);
    my $sql   = "SELECT j.md5s FROM ".$self->jtbl->{ontology}." j, ".$self->atbl->{ontology}." a".$where;
    foreach my $md5s (@{ $self->dbh->selectcol_arrayref($sql) }) {
        map { $data->{$_} = 1 } @$md5s;
    }
    return [ keys %$data ];
    # [ md5 ]
}
