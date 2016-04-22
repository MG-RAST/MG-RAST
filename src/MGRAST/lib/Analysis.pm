package MGRAST::Analysis;

use strict;
use warnings;
no warnings('once');

use Auth;
use Conf;

use List::Util qw(max min sum first);
use List::MoreUtils qw(natatime);
use DBI;
use JSON;
use Data::Dumper;
use MIME::Base64;
use LWP::UserAgent;
use Cache::Memcached;
use File::Temp qw/ tempfile tempdir /;

1;

sub new {
  my ($class, $job_dbh, $dbh, $version) = @_;

  # get ach object if have lib
  # my $ach = undef;
  # eval {
  #     require Babel::lib::Babel;
  #     Babel::lib::Babel->import();
  #     $ach = new Babel::lib::Babel;
  # };
  
  # get memcache object
  my $memd = undef;
  eval {
      require Cache::Memcached;
      Cache::Memcached->import();
      $memd = new Cache::Memcached {'servers' => $Conf::web_memcache, 'debug' => 0, 'compress_threshold' => 10_000};
  };
  
  # connect to database
  unless ($dbh) {
    eval {
      my $host     = $Conf::mgrast_dbhost;
      my $database = $Conf::mgrast_db;
      my $user     = $Conf::mgrast_dbuser;
      my $password = $Conf::mgrast_dbpass;
      
      $dbh = DBI->connect("DBI:Pg:dbname=$database;host=$host", $user, $password, 
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

  # set sources
  my $srcs  = $dbh->selectall_hashref("SELECT * FROM sources", "name");
  my %idsrc = map { $srcs->{$_}{_id}, $_ } keys %$srcs;
  my %srcid = map { $_, $srcs->{$_}{_id} } keys %$srcs;
  
  # get mgrast token
  #my $mgrast_token = undef;
  #if ($Conf::mgrast_oauth_name && $Conf::mgrast_oauth_pswd) {
  #    my $key = encode_base64($Conf::mgrast_oauth_name.':'.$Conf::mgrast_oauth_pswd);
  #    my $rep = Auth::globus_token($key);
  #    $mgrast_token = $rep ? $rep->{access_token} : undef;
  #}
  #### changed because globus has hard time handeling multiple tokens
  my $mgrast_token = "mgrast ".$Conf::mgrast_oauth_token || undef;
  
  # set json handle
  my $agent = LWP::UserAgent->new;
  my $json = JSON->new;
  $json = $json->utf8();
  $json->max_size(0);
  $json->allow_nonref;
  
  # create object
  my $self = { dbh      => $dbh,     # job data db_handle
	          # ach      => $ach,     # ach/babel object
	           api      => $Conf::api_url || "http://api.metagenomics.anl.gov",
	           jcache   => $job_dbh, # job cache db_handle
	           agent    => $agent,   # LWP agent handle
	           memd     => $memd,    # memcached handle
	           json     => $json,    # json handle
	           chunk    => 2500,     # max # md5s to query at once
	           jobs     => [],       # array: job_id
	           job_map  => {},       # hash: mg_id => job_id
	           mg_map   => {},       # hash: job_id => mg_id
	           name_map => {},       # hash: mg_id => job_name
	           type_map => {},       # hash: mg_id => seq_type
	           stat_map => {},       # hash: mg_id => statistics
	           sources  => $srcs,    # hash: source_name => { col => value }
	           id_src   => \%idsrc,  # hash: source_id => source_name
   	           src_id   => \%srcid,  # hash: source_name => source_id
	           expire   => $Conf::web_memcache_expire || 172800, # use config or 48 hours
	           version  => $version || $Conf::m5nr_annotation_version || 1,
	           mgrast_token => $mgrast_token,
	           jtbl => { md5      => 'job_md5s',
	                     ontology => 'job_ontologies',
	                     function => 'job_functions',
	                     organism => 'job_organisms',
	                     lca      => 'job_lcas' },
	           atbl => { md5      => 'md5s',
	                     ontology => 'ontologies',
	                     function => 'functions',
	                     organism => 'organisms_ncbi' }
	         };
  bless $self, $class;
  return $self;
}

sub DESTROY {
   my ($self) = @_;
   if ($self->{dbh})    { $self->{dbh}->disconnect; }
   #if ($self->{ach})    { $self->{ach}->DESTROY; }
   if ($self->{jcache}) { $self->{jcache}->disconnect; }
}

sub _dbh {
  my ($self) = @_;
  return $self->{dbh};
}
#sub ach {
#  my ($self) = @_;
#  return $self->{ach};
#}
sub _api {
  my ($self) = @_;
  return $self->{api};
}
sub _jcache {
  my ($self) = @_;
  return $self->{jcache};
}
sub _agent {
  my ($self) = @_;
  return $self->{agent};
}
sub _memd {
  my ($self) = @_;
  return $self->{memd};
}
sub _json {
  my ($self) = @_;
  return $self->{json};
}
sub _chunk {
  my ($self) = @_;
  return $self->{chunk};
}
sub _jobs {
  my ($self) = @_;
  return $self->{jobs};
}
sub _qjobs {
  my ($self) = @_;
  return "job IN (".join(',', @{$self->{jobs}}).")";
}
sub _job_map {
  my ($self) = @_;
  return $self->{job_map};
}
sub _mg_map {
  my ($self) = @_;
  return $self->{mg_map};
}
sub _name_map {
  my ($self) = @_;
  return $self->{name_map};
}
sub _type_map {
  my ($self) = @_;
  return $self->{type_map};
}
sub _id_src {
  my ($self) = @_;
  return $self->{id_src};
}
sub _src_id {
  my ($self) = @_;
  return $self->{src_id};
}
sub _sources {
  my ($self) = @_;
  return $self->{sources};
}
sub _expire {
  my ($self) = @_;
  return $self->{expire};
}
sub _version {
  my ($self) = @_;
  return $self->{version};
}
sub _mgrast_token {
  my ($self) = @_;
  return $self->{mgrast_token};
}
sub _qver {
  my ($self) = @_;
  return "version = ".$self->{version};
}
sub _jtbl {
  my ($self) = @_;
  return $self->{jtbl};
}
sub _atbl {
  my ($self) = @_;
  return $self->{atbl};
}
sub _has_job {
  my ($self, $mgid) = @_;
  return exists($self->_job_map->{$mgid}) ? 1 : 0;
}

# add values to $self->{jobs} based on metagenome_id list
sub add_jobs {
  my ($self, $mgids) = @_;
  if ($mgids && scalar(@$mgids)) {
    my @new_mg  = grep { ! $self->_has_job($_) } @$mgids;
    my $new_map = $self->_get_jobid_map(\@new_mg);
    %{ $self->{job_map} } = ( %{$self->{job_map}}, %$new_map );
    $self->_set_data();
  }
}

# set values for $self->{jobs} and $self->{jtbl} based on metagenome_id list
sub set_jobs {
  my ($self, $mgids, $jids) = @_;
  $self->{name_map} = {};
  $self->{type_map} = {};
  if (defined($jids)) {
    $self->{job_map} = $self->_get_jobid_map($mgids, 1);
  } else {
    $self->{job_map} = $self->_get_jobid_map($mgids);
  }
  $self->_set_data();
}

# populate obj with all public jobs
sub set_public_jobs {
  my ($self) = @_;
  my $mgids = $self->_jcache->selectcol_arrayref("SELECT metagenome_id FROM Job WHERE public = 1 AND viewable = 1");
  if ($mgids && (@$mgids > 0)) {
    $self->set_jobs($mgids);
  }
}

sub _set_data {
    my ($self) = @_;
    my %rev = reverse %{$self->{job_map}};
    $self->{mg_map} = \%rev;
    @{$self->{jobs}} = values %{$self->{job_map}};
}

sub _get_jobid_map {
  my ($self, $mgids, $jids, $no_names) = @_;
  unless ($mgids && scalar(@$mgids)) {
    return {};
  }
  my $hash = {};
  my $list = join(",", map {"'$_'"} @$mgids);
  my $rows;
  if ($jids) {
    $rows = $self->_jcache->selectall_arrayref("SELECT metagenome_id, job_id, name, sequence_type FROM Job WHERE job_id IN ($list) AND viewable = 1");
  } else {
    $rows = $self->_jcache->selectall_arrayref("SELECT metagenome_id, job_id, name, sequence_type FROM Job WHERE metagenome_id IN ($list) AND viewable = 1");
  }
  unless ($no_names) {
      map { $self->{name_map}->{$_->[0]} = $_->[2] } @$rows;
      map { $self->{type_map}->{$_->[0]} = $_->[3] } @$rows;
  }
  if ($rows && (@$rows > 0)) {
    %$hash = map { $_->[0], $_->[1] } @$rows;
  }
  return $hash;
}

sub _get_seq_count {
  my ($self, $mgid) = @_;
  my $sql  = "SELECT js.value FROM JobStatistics js, Job j WHERE j._id = js.job AND js.tag = 'sequence_count_raw' AND j.metagenome_id = '$mgid'";
  my $rows = $self->_jcache->selectcol_arrayref($sql);
  return ($rows && (@$rows > 0)) ? $rows->[0] : 0;
}

sub get_all_job_ids {
    my ($self) = @_;
    my $data = [];
    my $sth = $self->_dbh->prepare("SELECT DISTINCT job FROM job_info WHERE loaded IS TRUE AND ".$self->_qver);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$data, $row[0];
    }
    $sth->finish;
    $self->_dbh->commit;
    return $data;
}

####################
# misc
####################

sub _get_where_str {
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

sub _run_fraggenescan {
  my ($self, $fasta) = @_;

  unless ($Conf::run_fraggenescan) {
    return "";
  }
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

sub _get_table_cols {
    my ($self, $table) = @_;
    my $data = [];
    my $sth = $self->_dbh->prepare("SELECT a.attname FROM pg_attribute a, pg_class c WHERE c.oid = a.attrelid AND a.attnum > 0 AND c.relname = ?");
    $sth->execute($table) or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$data, $row[0];
    }
    $sth->finish;
    $self->_dbh->commit;
    return $data;
}

####################
# data / statistics from shock
####################

sub _mg_stats {
    my ($self, $mgid) = @_;
    unless (exists $self->{stat_map}{$mgid}) {
        my $mgstats = $self->_get_mg_stats($mgid);
        if (! %$mgstats) {
            print STDERR "no statistics available for $mgid\n";
        }
        $self->{stat_map}{$mgid} = $mgstats;
    }
    return $self->{stat_map}{$mgid};
}

sub _get_mg_stats {
    my ($self, $mgid) = @_;
    
    # get node
    my $stat_node = $self->stat_node($mgid);
    unless ($stat_node && exists($stat_node->{id})) {
        return {};
    }
    # get content
    my $stats = {};
    eval {
        my @args = ('Authorization', $self->_mgrast_token);
        my $get = $self->_agent->get($Conf::shock_url.'/node/'.$stat_node->{id}.'?download', @args);
        $stats = $self->_json->decode( $get->content );
    };
    if ($@ || (! $stats) || (exists($stats->{error}) && $stats->{error})) {
        return {};
    }
    return $stats;
}

sub stat_node {
    my ($self, $mgid) = @_;
    return $self->_get_mg_node($mgid, 'data_type=statistics');
}

sub sims_node {
    my ($self, $mgid) = @_;
    $self->_get_mg_node($mgid, 'data_type=similarity&stage_name=filter.sims');
}

sub _get_mg_node {
    my ($self, $mgid, $type) = @_;
    
    my $response = undef;
    my $query = '?query&limit=1&type=metagenome&'.$type.'&id=mgm'.$mgid;
    eval {
        my @args = ('Authorization', $self->_mgrast_token);
        my $get = $self->_agent->get($Conf::shock_url.'/node'.$query, @args);
        $response = $self->_json->decode( $get->content );
    };
    if ( $@ || (! ref($response)) ||
         (exists($response->{error}) && $response->{error}) ||
         (! $response->{data}) ||
         (scalar(@{$response->{data}}) == 0) ) {
        return {};
    }
    return $response->{data}[0];
}

sub _get_sim_record {
    my ($self, $node_id, $seek, $length) = @_;
    
    unless ($node_id && defined($seek) && defined($length)) {
        return '';
    }
    my $data = '';
    eval {
        my @args = ('Authorization', $self->_mgrast_token);
        my $url = $Conf::shock_url.'/node/'.$node_id.'?download&seek='.$seek.'&length='.$length;
        my $get = $self->_agent->get($url, @args);
        $data = $get->content;
    };
    if ($@ || (! $data)) {
        return '';
    }
    return $data;
}

sub get_source_stats {
    my ($self, $mgid) = @_;
    my $stats = $self->_mg_stats($mgid);
    return exists($stats->{source}) ? $stats->{source} : {};
    # source => type => [#, #, #, #, #]
}

sub get_taxa_stats {
    my ($self, $mgid, $taxa) = @_;
    my $stats = $self->_mg_stats($mgid);
    if (exists $stats->{taxonomy}) {
        return exists($stats->{taxonomy}{$taxa}) ? $stats->{taxonomy}{$taxa} : [];
    } else {
        return [];
    }
    # [ name, abundance ]
}

sub get_ontology_stats {
    my ($self, $mgid, $source) = @_;
    my $stats = $self->_mg_stats($mgid);
    if (exists $stats->{ontology}) {
        return exists($stats->{ontology}{$source}) ? $stats->{ontology}{$source} : [];
    } else {
        return [];
    }
    # [ top level name, abundance ]
}

sub get_rarefaction_coords {
    my ($self, $mgid) = @_;
    my $stats = $self->_mg_stats($mgid);
    return exists($stats->{rarefaction}) ? $stats->{rarefaction} : [];
    # [ x, y ]
}

sub get_qc_stats {
    my ($self, $mgid, $type) = @_;
    my $stats = $self->_mg_stats($mgid);
    if (exists $stats->{qc}) {
        return exists($stats->{qc}{$type}) ? $stats->{qc}{$type} : {};
    } else {
        return {};
    }
}

sub get_histogram_nums {
    my ($self, $mgid, $type, $stage) = @_;
    my $stats = $self->_mg_stats($mgid);
    if ($stage && ($stage eq 'qc')) {
        $stage = 'post_qc';
    } else {
        $stage = 'upload';
    }
    if ($type eq 'len' && exists($stats->{length_histogram}) && exists($stats->{length_histogram}{$stage})) {
        return $stats->{length_histogram}{$stage};
    } elsif ($type eq 'gc' && exists($stats->{gc_histogram}) && exists($stats->{gc_histogram}{$stage})) {
        return $stats->{gc_histogram}{$stage};
    } else {
        return [];
    }
    # [ value, count ]
}

sub get_md5_sims {
  # $md5_seeks = [md5, seek, length]
  my ($self, $jobid, $md5_seeks) = @_;

  my $sims = {};
  my $sim_node = $self->sims_node($self->_mg_map->{$jobid});
  if ($md5_seeks && (@$md5_seeks > 0) && $sim_node && exists($sim_node->{id})) {
    @$md5_seeks = sort { $a->[1] <=> $b->[1] } @$md5_seeks;
    foreach my $set (@$md5_seeks) {
      my ($md5, $seek, $length) = @$set;
      my $rec = $self->_get_sim_record($sim_node->{id}, $seek, $length);
      chomp $rec;
      $sims->{$md5} = [ split(/\n/, $rec) ];
    }
  }
  return $sims;
  # md5 => [sim lines]
}

####################
# Math Functions
####################

# log of N choose R 
sub _nCr2ln {
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
        $c = $self->_gammaln($n + 1) - $self->_gammaln($r + 1) - $self->_gammaln($n - $r); 
    } else {
        $c = -1000;
    }
    return $c;
}

# This is Stirling's formula for gammaln, used for calculating nCr
sub _gammaln {
    my ($self, $x) = @_;

    unless ($x > 0) { return 0; }
    my $s = log($x);
    return log(2 * 3.14159265458) / 2 + $x * $s + $s / 2 - $x;
}

####################
# All functions conducted on annotation tables
####################

sub get_hierarchy {
    my ($self, $type, $src, $use_taxid, $get_ids, $max_lvl) = @_;
    
    my $tbl = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    my $col = $self->_get_table_cols($tbl);
    unless ($tbl && @$col) { return {}; }
    unless ($max_lvl) { $max_lvl = ''; }
    if (($max_lvl eq 'level4') && ($src =~ /^[NC]OG$/)) { $max_lvl = 'level3'; }
    
    my @cols = ();
    my $hier = {};
    my $key  = $get_ids ? '_id' : 'name';
    my $pref = ($type eq 'ontology') ? 'level' : 'tax_';
    
    foreach my $c ( grep {$_ =~ /^$pref/} @$col ) {
        next if ($c eq 'tax_kingdom');  # ncbi hack
        next if (($c eq 'level4') && ($src =~ /^[NC]OG$/)); # n|cog hack
        if ($c ne $max_lvl) {
          push @cols, $c;
        }
        else {
          push @cols, $c;
          $key = $c;
          last;
        }
    }
    if (($type eq 'organism') && $use_taxid && (! $max_lvl)) {
        $key = 'ncbi_tax_id';
    }
    push @cols, $key;
    
    my $sql = "SELECT DISTINCT ".join(", ", @cols)." FROM ".$self->_atbl->{$type};
    if (($type eq 'ontology') && $src) {
        $sql .= " WHERE source = ".$self->_src_id->{$src};
    }
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $id = pop @row;
        next unless ($id && ($id =~ /\S/));
        map { $_ = $_ ? $_ : "-" } @row;
        $hier->{$id} = \@row;
    }
    $sth->finish;
    $self->_dbh->commit;
    return $hier;
    # { end_node => [ hierachy of node ] }
}

sub get_hierarchy_slice {
    my ($self, $type, $source, $parent_name, $child_level) = @_;
    
    my $tbl = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    my $col = $self->_get_table_cols($tbl);
    unless ($tbl && @$col && $parent_name && $child_level && grep(/^$child_level$/, @$col)) {
        return [];
    }
    my $child_index = first { $col->[$_] eq $child_level } 0..$#{$col};
    # level does not exist
    unless ($child_index) {
        return [];
    }
    # no parent available
    if (($child_level eq 'tax_domain') || ($child_level eq 'level1')) {
        return [];
    }
    my $parent_index = $child_index - 1;
    # ncbi hack
    if ($child_level eq 'tax_phylum') {
        $parent_index -= 1;
    }
    my $sql = "SELECT DISTINCT ".$col->[$child_index]." FROM ".$self->_atbl->{$type}." WHERE ".$col->[$parent_index]." = ".$self->_dbh->quote($parent_name);
    if (($type eq 'ontology') && $source) {
        $sql .= " AND source = ".$self->_src_id->{$source};
    }
    my $data = [];
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$data, $row[0];
    }
    $sth->finish;
    $self->_dbh->commit;
    return $data;
}

sub _get_annotation_map {
    my ($self, $type, $anns, $src) = @_;

    my $tbl = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    unless ($tbl && $anns && @$anns) { return {}; }
    
    my $col  = ($type eq 'md5') ? 'md5' : 'name';    
    my $amap = {};
    my $iter = natatime $self->_chunk, @$anns;
    
    while (my @curr = $iter->()) {
        my $sql = "SELECT _id, $col FROM $tbl WHERE $col IN (".join(",", map {$self->_dbh->quote($_)} @curr).")";
        if ($src && ($type eq 'ontology')) {
            $sql .= " AND source = ".$self->_src_id->{$src};
        }
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            $amap->{$row[0]} = $row[1];
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    return $amap;
    # _id => name
}

sub _get_annotations4level {
    my ($self, $type, $level, $src, $get_ids) = @_;

    my $tbl = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    unless ($tbl && $level) { return {}; }

    my $key  = $get_ids ? '_id' : 'name';
    my $anns = {};
    my $qsrc = ($src && ($type eq 'ontology')) ? "source = ".$self->_src_id->{$src} : "";
    my @cols = grep { $_ eq $level } @{ $self->_get_table_cols($tbl) };

    if (@cols == 1) {
        my $where = $self->_get_where_str([$qsrc, "$level IS NOT NULL"]);
        my $sth = $self->_dbh->prepare("SELECT DISTINCT $key, $level FROM ".$tbl.$where);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            if ($row[1] && ($row[1] =~ /\S/)) {
                $anns->{$row[0]} = $row[1];
            }
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    return $anns;
    # (_id || name) => annot
}

sub _search_annotations {
    my ($self, $type, $text) = @_;

    unless (exists($self->_jtbl->{$type}) && exists($self->_atbl->{$type})) { return {}; }

    my $cache_key = $type."_search_".quotemeta($text);
    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->_job_map} ) {
        my $cdata = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
        if ($cdata) { $data->{$mg} = $cdata; }
        else        { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }

    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", "a.name ~* ".$self->_dbh->quote($text)]);
    my $sql = "SELECT DISTINCT j.job, j.source, a.name, j.abundance FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @{ $data->{ $self->_mg_map->{$row[0]} } }, [ $self->_id_src->{$row[1]}, @row[2,3] ];
    }
    $sth->finish;
    
    if ($self->_memd) {
        foreach my $mg (keys %$data) {
            $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
        }
    }
    $self->_dbh->commit;
    return $data;
    # mgid => [ source, organism, abundance ]
}

sub annotation_for_md5s {
    my ($self, $md5s, $srcs, $taxid) = @_;
    
    unless ($md5s && @$md5s) { return []; }
    
    my $data = [];
    my $qsrc = ($srcs && @$srcs && !(@$srcs == 1 && $srcs->[0] eq 'M5NR')) ? " AND a.source IN (".join(",", map { $self->_src_id->{$_} } @$srcs).")" : '';
    my $tid  = $taxid ? ", o.ncbi_tax_id" : "";
    my %umd5 = map {$_, 1} @$md5s;
    my $iter = natatime $self->_chunk, keys %umd5;

    while (my @curr = $iter->()) {
        my $sql = "SELECT DISTINCT a.md5, a.id, m.md5, f.name, o.name, a.source$tid FROM md5_annotation a ".
                  "INNER JOIN md5s m ON a.md5 = m._id ".
                  "LEFT OUTER JOIN functions f ON a.function = f._id ".
                  "LEFT OUTER JOIN organisms_ncbi o ON a.organism = o._id ".
                  "WHERE a.md5 IN (".join(",", @curr).")".$qsrc;
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            $row[5] = $self->_id_src->{$row[5]};
            push @$data, \@row;
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    # [ md5_id, id, md5, function, organism, source, (tax_id) ]
    return $data;
}

sub decode_annotation {
    my ($self, $type, $ids) = @_;
    
    unless ($ids && @$ids) { return {}; }
    my $data = {};
    my $col  = ($type eq 'md5') ? 'md5' : 'name';
    my %uids = map {$_, 1} @$ids;
    my $iter = natatime $self->_chunk, keys %uids;
    
    while (my @curr = $iter->()) {
        my $sql = "SELECT _id, $col FROM ".$self->_atbl->{$type}." WHERE _id IN (".join(',', @curr).")";
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            $data->{$row[0]} = $row[1];
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    return $data;
    # id => name
}

sub type_for_md5s {
    my ($self, $md5s, $get_id) = @_;
    
    unless ($md5s && @$md5s) { return {}; }
    my $data = {};
    my %umd5 = map {$_, 1} @$md5s;
    my $iter = natatime $self->_chunk, keys %umd5;
    
    while (my @curr = $iter->()) {
        my $sql = "SELECT _id, md5, is_protein FROM md5s WHERE _id IN (".join(',', @curr).")";
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            if ($get_id) {
                $data->{$row[0]} = [ $row[1], $row[2] ? 'protein' : 'rna' ];
            } else {
                $data->{$row[1]} = $row[2] ? 'protein' : 'rna';
            }
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    return $data;
    # md5 => 'protein'|'rna' OR _id => [md5, 'protein'|'rna']
}

sub organisms_for_taxids {
    my ($self, $tax_ids) = @_;

    unless ($tax_ids && (@$tax_ids > 0)) { return {}; }
    my $data = {};
    my $list = join(",", grep {$_ =~ /^\d+$/} @$tax_ids);
    my $sth = $self->_dbh->prepare("SELECT _id, name FROM ".$self->_atbl->{organism}." WHERE ncbi_tax_id in ($list)");
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        $data->{$row[0]} = $row[1];
    }
    $sth->finish;
    $self->_dbh->commit;
    return $data;
    # org_id => org_name
}

sub sources_for_type {
    my ($self, $type) = @_;
    my @set = map { [$_->{name}, $_->{description}] } grep { $_->{type} eq $type } values %{$self->_sources};
    return \@set;
}

sub link_for_source {
    my ($self, $src) = @_;
    return (exists($self->_sources->{$src}) && $self->_sources->{$src}{link}) ? $self->_sources->{$src}{link} : '';
}

####################
# All functions conducted on individual job
####################

sub delete_job {
    my ($self, $job) = @_;
    
    my $delete_hdl;
    eval {
      my $host     = $Conf::mgrast_write_dbhost;
      my $database = $Conf::mgrast_db;
      my $user     = $Conf::mgrast_dbuser;
      my $password = $Conf::mgrast_dbpass;
      
      $delete_hdl = DBI->connect("DBI:Pg:dbname=$database;host=$host", $user, $password, 
			  { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			    die "database connect error.";
    };
    if ($@) {
      warn "Unable to connect to metagenomics database: $@\n";
      return 0;
    }
    
    my $all = $delete_hdl->selectcol_arrayref("SELECT DISTINCT version FROM job_info WHERE job = ".$job);
    eval {
        $delete_hdl->do("DELETE FROM job_info WHERE job = ".$job);
        foreach my $tbl (values %{$self->_jtbl}) {
            $delete_hdl->do("DELETE FROM $tbl WHERE version IN (".join(",", @$all).") AND job = ".$job);
        }
    };
    $delete_hdl->commit;
    $delete_hdl->disconnect;
    
    if ($@) {
        return 0;
    } else {
        return 1;
    }
}

sub get_sources {
    my ($self, $mgid, $type) = @_;

    $self->set_jobs([$mgid]);
    my $where = $self->_get_where_str([$self->_qver, "job = ".$self->_job_map->{$mgid}]);

    if ($type && exists($self->_jtbl->{$type})) {
        my $srcs  = $self->_dbh->selectcol_arrayref("SELECT DISTINCT source FROM ".$self->_jtbl->{$type}.$where);
        @$srcs = sort map { $self->_id_src->{$_} } @$srcs;
        $self->_dbh->commit;
        return $srcs;
    } else {
        my $total = {};
        while ( my ($type, $name) = each %{$self->_jtbl} ) {
            next if ($type =~ /^(md5|lca)$/);
            my $srcs = $self->_dbh->selectcol_arrayref("SELECT DISTINCT source FROM ".$name.$where);
            map { $total->{ $self->_id_src->{$_} } = 1 } @$srcs;
        }
        $self->_dbh->commit;
        return [ sort keys %$total ];
    }
    # [ source ]
}

sub md5_abundance_for_annotations {
    my ($self, $mgid, $type, $srcs, $anns) = @_;
    
    $self->set_jobs([$mgid]);
    my $job = $self->_job_map->{$mgid};
    my $tbl = exists($self->_jtbl->{$type}) ? $self->_jtbl->{$type} : '';
    unless ($tbl) { return {}; }

    my $amap = {};
    if ($anns && @$anns) {
        $amap = $self->_get_annotation_map($type, $anns);
        unless (scalar(keys %$amap)) { return {}; }
    }
  
    my $mdata = [];
    my $md5s  = {};
    my $data  = {};
    my $qsrc  = ($srcs && @$srcs) ? "source IN (".join(",", map { $self->_src_id->{$_} } @$srcs).")" : '';
    my $qids  = (scalar(keys %$amap) > 0) ? "id IN (".join(",", keys %$amap).")" : '';
    
    my $where = $self->_get_where_str([$self->_qver, "job = $job", $qsrc, $qids]);
    my $sth = $self->_dbh->prepare("SELECT id, md5s FROM ".$tbl.$where);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$mdata, \@row;
    }
    $sth->finish;

    unless ($mdata && (@$mdata > 0)) {
        return $data;
    }
    my %unique_md5s = ();
    foreach my $m (@$mdata) {
        map { $unique_md5s{$_} = 1 } @{$m->[1]};
        map { $data->{ $amap->{$m->[0]} }->{$_} = 0 } @{$m->[1]};
    }
    
    $where = $self->_get_where_str([$self->_qver, "job = $job", "md5 IN (".join(",", keys %unique_md5s).")"]);
    $sth = $self->_dbh->prepare("SELECT md5, abundance FROM ".$self->_jtbl->{md5}.$where);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        $md5s->{$row[0]} = $row[1];
    }
    $sth->finish;

    foreach my $ann (keys %$data) {
        map { $data->{$ann}{$_} = $md5s->{$_} } grep { exists $md5s->{$_} } keys %{$data->{$ann}};
    }
    $self->_dbh->commit;
    # annotation_text => md5_integer => abundance
    return $data;
}

sub sequences_for_md5s {
    my ($self, $mgid, $type, $md5s, $return_read_id_flag) = @_;

    $self->set_jobs([$mgid]);
    my $data = {};
    my $seqs = $self->md5s_to_read_sequences($md5s);
    unless ($seqs && @$seqs) { return {}; }

    if ($type eq 'dna') {
        foreach my $set (@$seqs) {
            if($return_read_id_flag == 1) {
		        push @{ $data->{$set->{md5}} }, ["mgm".$set->{id}, $set->{sequence}];
	        } else {
		        push @{ $data->{$set->{md5}} }, $set->{sequence};
	        }
        }
    } elsif ($type eq 'protein') {
        my $fna = '';
        map { $fna .= ">".$_->{md5}."|".$_->{id}."\n".$_->{sequence}."\n" } @$seqs;
        my $faa = $self->_run_fraggenescan($fna);
        unless ($faa) { return {}; }
        my @seqs = split(/\n/, $faa);
        for (my $i=0; $i<@seqs; $i += 2) {
            if ($seqs[$i] =~ /^>(\S+)/) {
	            my $id  = $1;
	            my $seq = $seqs[$i+1];
	            $id =~ /^(\w+)?\|(.*)/;
	            my $md5 = $1;
		        my $read_id = $2;
		        if ($return_read_id_flag == 1) {
		            push @{ $data->{$md5} }, ["mgm".$read_id, $seq];
		        } else {
		            push @{ $data->{$md5} }, $seq;
	            }
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
    my $ann = $self->md5_abundance_for_annotations($mgid, $ann_type, $srcs, $anns); # annotation_text => md5_integer => abundance
    foreach my $a (keys %$ann) {
        map { $md5s->{$_} = 1; } keys %{$ann->{$a}};
    }
    unless (scalar(keys(%$md5s))) {
        return $data;
    }
  
    my $seqs = $self->sequences_for_md5s($mgid, $seq_type, [keys %$md5s], 1);
    my $md5_ints_to_strings = $self->_get_annotation_map('md5', [keys %$seqs]);
    foreach my $a (keys %$ann) {
        foreach my $m (keys %{$ann->{$a}}) {
            next unless (exists $seqs->{$md5_ints_to_strings->{$m}});
            map { push @{$data->{$a}}, $_ } @{$seqs->{$md5_ints_to_strings->{$m}}};
        }
    }
    # ann => [ seq list ]
    return $data;
}

sub metagenome_search {
    my ($self, $type, $srcs, $ann, $exact) = @_;

    my $jtbl = exists($self->_jtbl->{$type}) ? $self->_jtbl->{$type} : '';
    my $atbl = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    unless ($jtbl && $atbl) { return []; }

    my $jobs  = [];
    my $qsrc  = ($srcs && @$srcs) ? "j.source IN (".join(",", map { $self->_src_id->{$_} } @$srcs).")" : "";
    my $qann  = "a.name ".($exact ? '= ' : '~* ').$self->_dbh->quote($ann);
    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.id = a._id", $qsrc, $qann]);
    
    my $sth = $self->_dbh->prepare("SELECT DISTINCT j.job FROM $jtbl j, $atbl a".$where);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$jobs, $row[0];
    }
    $sth->finish;
    unless ($jobs && (@$jobs > 0)) {
        return [];
    }
    # [ mgid ]
    return [ keys %{$self->_get_jobid_map($jobs, 1, 1)} ];
}

####################
# All functions conducted on jobs list
####################

=pod

=item * B<md5s_to_read_sequences> (I<md5s>, I<eval>, I<ident>)

Retrieve the [ {id , sequence} ] from the metagenome job directory for I<md5s> with I<eval>.

=cut 

sub md5s_to_read_sequences {
    my ($self, $md5s, $eval, $ident, $alen) = @_;
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

    my %mg_sims = map { $_, $self->sims_node($_) } keys %{$self->_job_map};
    my $seqs = [];
    my %umd5 = map {$_, 1} @$md5s;
    my $iter = natatime $self->_chunk, keys %umd5;

    while (my @curr = $iter->()) {    
        my $w_md5s = "md5 IN (".join(",", map {"'$_'"} @curr).")";
        my $where = $self->_get_where_str([$self->_qver, $self->_qjobs, $eval, $ident, $alen, $w_md5s, "seek IS NOT NULL", "length IS NOT NULL"]);
        my $data = {};
        
        my $sql = "SELECT job, seek, length FROM ".$self->_jtbl->{md5}.$where." ORDER BY job, seek";
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            push @{ $data->{$self->_mg_map->{$row[0]}} }, [$row[1], $row[2]];
        }
        $sth->finish;
        
        while ( my ($m, $info) = each %$data ) {
            next unless (exists($mg_sims{$m}) && $mg_sims{$m} && exists($mg_sims{$m}{id}));
            foreach my $set (@$info) {
	            my ($seek, $len) = @$set;
	            my $rec = $self->_get_sim_record($mg_sims{$m}{id}, $seek, $len);
	            chomp $rec;
	            foreach my $line ( split(/\n/, $rec) ) {
	                my @tabs = split(/\t/, $line);
	                if (@tabs == 13) {
	                    push @$seqs, { md5 => $tabs[1], id => $m."|".$tabs[0], sequence => $tabs[12] };
	                }
	            }
            }
        }
    }
    $self->_dbh->commit;
    return $seqs;
}

sub get_abundance_for_organism_source {
    my ($self, $org, $src) = @_;

    my $qorg  = "a.name = ".$self->_dbh->quote($org);
    my $qsrc  = "j.source = ".$self->_src_id->{$src};
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "j.id = a._id", $qorg, $qsrc]);
    my $sql   = "SELECT SUM(j.abundance) FROM ".$self->_jtbl->{organism}." j, ".$self->_atbl->{organism}." a".$where;
    my $sum   = $self->_dbh->selectcol_arrayref($sql);
    $self->_dbh->commit;
    return ($sum && (@$sum > 0)) ? $sum->[0] : 0;
}

sub get_organism_abundance_for_source {
    my ($self, $src) = @_;

    my $data  = {};
    my $where = $self->_get_where_str([$self->_qver, $self->_qjobs, "source = ".$self->_src_id->{$src}]);
    my $sql = "SELECT id, abundance FROM ".$self->_jtbl->{organism}.$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        $data->{$row[0]} = $row[1];
    }
    $sth->finish;
    $self->_dbh->commit;
    # org_id => abund
    return $data;
}

# sub get_organisms_with_contig_for_source {
#     my ($self, $src, $num, $len) = @_;
# 
#     if ($self->ach) {
#         my $job_orgs = $self->get_organism_abundance_for_source($src);
#         my @job_ctgs = map { [$_->[0], $_->[1], $job_orgs->{$_->[0]}] }
#                             grep { exists $job_orgs->{$_->[0]} }
#                                 @{ $self->ach->get_organism_with_contig_list($num, $len) };
#         # [ org_id, org_name, abundance ]
#         return \@job_ctgs;
#     } else {
#         return [];
#     }
# }

sub get_md5_evals_for_organism_source {
    my ($self, $org, $src) = @_;

    my $data = {};
    my $umd5 = {};
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "a.name=".$self->_dbh->quote($org), "j.source=".$self->_src_id->{$src}, "j.id = a._id"]);
    my $sql = "SELECT j.md5s FROM ".$self->_jtbl->{organism}." j, ".$self->_atbl->{organism}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        foreach my $md5_id (@{$row[0]}) {
            $umd5->{$md5_id} = 1;
        }
    }
    $sth->finish;
    
    if (scalar(keys %$umd5) == 0) {
        return $data;
    }
    my $iter = natatime $self->_chunk, keys %$umd5;
    while (my @curr = $iter->()) {
        $where = $self->_get_where_str([$self->_qver, $self->_qjobs, "md5 IN (".join(",", @curr).")"]);
        $sql = "SELECT md5, evals FROM ".$self->_jtbl->{md5}.$where;
        $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            for (my $i=0; $i<@{$row[1]}; $i++) {
                $data->{$row[0]}->[$i] += $row[1][$i];
            }
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    # md5 => [ eval ]
    return $data;
}

sub get_md5_data_for_organism_source {
    my ($self, $org, $src, $eval) = @_;

    my $data = [];
    my $umd5 = {};
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "a.name=".$self->_dbh->quote($org), "j.source=".$self->_src_id->{$src}, "j.id = a._id"]);
    my $sql = "SELECT j.md5s FROM ".$self->_jtbl->{organism}." j, ".$self->_atbl->{organism}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        foreach my $md5_id (@{$row[0]}) {
            $umd5->{$md5_id} = 1;
        }
    }
    $sth->finish;
    
    if (scalar(keys %$umd5) == 0) {
        return $data;
    }
    my $iter = natatime $self->_chunk, keys %$umd5;    
    while (my @curr = $iter->()) {
        $where  = $self->_get_where_str([$self->_qver, $self->_qjobs, "md5 IN (".join(",", @curr).")", "seek IS NOT NULL", "length IS NOT NULL"]);
        $sql = "SELECT DISTINCT job,md5,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv,seek,length FROM ".$self->_jtbl->{md5}.$where;
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            push @$data, [ $self->_mg_map->{$row[0]}, @row[1..10] ];
        }
        $sth->finish;
    }
    $self->_dbh->commit;
    return $data;
    # [ mgid, md5, abund, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length ]
}

sub get_rarefaction_curve {
    my ($self, $srcs, $get_alpha, $level) = @_;

    unless ($srcs && @$srcs) { $srcs = []; }
    unless ($level) { $level = 'species'; }

    my $raw_data  = {};  # mgid => tax level => abundance
    my $mg_alpha  = {};  # mgid => alpha diversity
    my $mg_rare   = {};  # mgid => [ rare-x, rare-y ]
    my $mg_abund  = $self->get_abundance_for_tax_level('tax_'.$level, undef, $srcs);  # [mgid, tax level, abundance]
    my $cache_key = 'rarefaction'.$level.join(':', @$srcs);

    map { $raw_data->{$_->[0]}->{$_->[1]} = $_->[2] } @$mg_abund;
  
    # calculate alpha diversity
    if ($get_alpha) {
        foreach my $mg (keys %$raw_data) {
            my $cdata = $self->_memd ? $self->_memd->get($mg.$cache_key."alpha") : undef;
            unless ($cdata) {
	            my $h1  = 0;
	            my $sum = sum values %{$raw_data->{$mg}};
	            unless ($sum) {
	                $mg_alpha->{$mg} = 0;
	                $self->_memd->set($mg.$cache_key."alpha", 0, $self->_expire);
	                next;
	            }
	            foreach my $num (values %{$raw_data->{$mg}}) {
	                my $p = $num / $sum;
	                if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
	            }
	            $mg_alpha->{$mg} = 2 ** $h1;
	            if ($self->_memd) {
	                $self->_memd->set($mg.$cache_key."alpha", $mg_alpha->{$mg}, $self->_expire);
                }
            } else {
                $mg_alpha->{$mg} = $cdata;
            }
        }
        # mgid => alpha-diver
        return $mg_alpha;
    }

    # calculate rarefaction (x, y)
    foreach my $mg (keys %$raw_data) {
        my $cdata = $self->_memd ? $self->_memd->get($mg.$cache_key."curve") : undef;
        unless ($cdata) {
            my @nums = sort {$a <=> $b} values %{$raw_data->{$mg}};
            my $k    = scalar @nums;
            my $nseq = $self->_get_seq_count($mg);
            my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
            unless ($nseq) {
	            $mg_rare->{$mg} = [];
	            $self->_memd->set($mg.$cache_key."curve", [], $self->_expire);
	            next;
            }
            for (my $n = 0; $n < $nseq; $n += $size) {
	            my $coeff = $self->_nCr2ln($nseq, $n);
	            my $curr  = 0;
	            map { $curr += exp( $self->_nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
	            push @{ $mg_rare->{$mg} }, [ $n, $k - $curr ];
            }
            if ($self->_memd) {
                $self->_memd->set($mg.$cache_key."curve", $mg_rare->{$mg}, $self->_expire);
            }
        } else {
            $mg_rare->{$mg} = $cdata;
        }
    }
    # mgid => [ x, y ]
    return $mg_rare;
}

sub get_abundance_for_tax_level {
    my ($self, $level, $names, $srcs, $value, $md5s, $eval, $ident, $alen) = @_;
    my $name_map = $self->_get_annotations4level("organism", $level, undef, 1);
    my $src_str  = ($srcs && (@$srcs > 0)) ? join("", @$srcs) : '';
    return $self->_get_abundance_for_hierarchy($name_map, "organism", $level.$src_str, $srcs, $value, $md5s, $eval, $ident, $alen);
}

sub get_abundance_for_ontol_level {
    my ($self, $level, $names, $src, $value, $md5s, $eval, $ident, $alen) = @_;
    my $name_map = $self->_get_annotations4level("ontology", $level, $src, 1);
    return $self->_get_abundance_for_hierarchy($name_map, "ontology", $level.$src, [$src], $value, $md5s, $eval, $ident, $alen);
}

sub _get_abundance_for_hierarchy {
    my ($self, $name_map, $type, $key, $srcs, $value, $md5s, $eval, $ident, $alen) = @_;

    unless ($value) { $value = "abundance"; }
    my $cache_key = $value.$type.$key;
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";

    my $data  = [];
    my $jobs  = [];
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $cdata = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            if ($cdata) { push @$data, @$cdata; }
            else        { push @$jobs, $j; }
        }
    }
    unless (@$jobs) { return $data; }
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";

    # get for jobs
    my ($job, $id, $md5);
    my %md5_set = $qmd5s ? map {$_, 1} @$md5s : ();
    my $hier  = {};
    my $curr  = 0;
    my $qsrcs = ($srcs && (@$srcs > 0)) ? "source IN (".join(",", map { $self->_src_id->{$_} } @$srcs).")" : "";
    my $where = $self->_get_where_str([$self->_qver, "job IN (".join(",", @$jobs).")", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT job, id, md5s FROM ".$self->_jtbl->{$type}.$where." ORDER BY job";
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        ($job, $id, $md5) = @row;
        next unless(exists $name_map->{$id});
        unless ($curr) { $curr = $job; }
        if ($curr != $job) {
            my $cdata = [];
            my %md5s = ();
            my $ssth = $self->_dbh->prepare("SELECT md5, $value FROM ".$self->_jtbl->{md5}." WHERE ".$self->_qver." AND job=".$curr);
            $ssth->execute() or die "Couldn't execute statement: " . $ssth->errstr;
            while (my @srow = $ssth->fetchrow_array()) {
                $md5s{$srow[0]} = $srow[1];
            }
            $ssth->finish;
            foreach my $h (sort keys %$hier) {
                my $num   = 0;
            	my $count = 0;
            	map { $num += $md5s{$_}; $count += 1; } grep { exists $md5s{$_} } keys %{ $hier->{$h} };
            	if (($value ne "abundance") && ($count > 0)) {
            	    $num = ($num * 1.0) / $count;
            	}
            	push @$data, [ $self->_mg_map->{$curr}, $h, $num ];
            	push @$cdata, [ $self->_mg_map->{$curr}, $h, $num ];
            }
            if ($self->_memd) {
                $self->_memd->set($self->_mg_map->{$curr}.$cache_key, $cdata, $self->_expire);
            }
            # reset
            $hier = {};
            $curr = $job;
        }
        if ($qmd5s) {
            map { $hier->{$name_map->{$id}}{$_} = 1 } grep { exists $md5_set{$_} } @$md5;
        } else {
            map { $hier->{$name_map->{$id}}{$_} = 1 } @$md5;
        }
    }
    $sth->finish;
    # get last job
    if (scalar(keys %$hier) > 0) {
        my $cdata = [];
        my %md5s = ();
        my $ssth = $self->_dbh->prepare("SELECT md5, $value FROM ".$self->_jtbl->{md5}." WHERE ".$self->_qver." AND job=".$job);
        $ssth->execute() or die "Couldn't execute statement: " . $ssth->errstr;
        while (my @srow = $ssth->fetchrow_array()) {
            $md5s{$srow[0]} = $srow[1];
        }
        $ssth->finish;
        foreach my $h (sort keys %$hier) {
            my $num   = 0;
        	my $count = 0;
        	map { $num += $md5s{$_}; $count += 1; } grep { exists $md5s{$_} } keys %{ $hier->{$h} };
        	if (($value ne "abundance") && ($count > 0)) {
        	    $num = ($num * 1.0) / $count;
        	}
        	push @$data, [ $self->_mg_map->{$job}, $h, $num ];
        	push @$cdata, [ $self->_mg_map->{$job}, $h, $num ];
        }
        if ($self->_memd) {
            $self->_memd->set($self->_mg_map->{$job}.$cache_key, $cdata, $self->_expire);
        }
    }
    $self->_dbh->commit;
    return $data;
    # [ mgid, taxa_name, abundance ]
}

sub get_abundance_for_set {
    my ($self, $set, $type, $srcs) = @_;

    unless ($set && (@$set > 0) && exists($self->_jtbl->{$type})) { return {}; }

    my $data = {};
    foreach my $mg (keys %{$self->_job_map}) {
        map { $data->{$mg}{$_} = [ 0 ] } @$set;
    }
    my $qterm = "a.name IN (".join(", ", map { $self->_dbh->quote($_) } @$set).")";
    my $qsrcs = (@$srcs > 0) ? "j.source IN (".join(",", map { $self->_src_id->{$_} } @$srcs).")" : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "j.id = a._id", $qsrcs, $qterm]);
    my $sql = "SELECT DISTINCT j.job, a.name, j.abundance FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @{ $data->{ $self->_mg_map->{$row[0]} }{$row[1]} }, $row[2];
    }
    $sth->finish;
    my $results = {};
    foreach my $mg (keys %$data) {
        map { $results->{$mg}{$_} = max @{ $data->{$mg}{$_} } } keys %{$data->{$mg}};
    }
    $self->_dbh->commit;
    return $results;
    # mgid => annotation => abundance
}

sub get_rank_abundance {
    my ($self, $limit, $type, $srcs) = @_;
    
    unless ($limit && exists($self->_jtbl->{$type})) { return []; }
    
    my $data  = {};
    my $qsrcs = (@$srcs > 0) ? "j.source IN (" . join(",", map { $self->_src_id->{$_} } @$srcs) . ")" : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "j.id = a._id", $qsrcs]);
    my $sql = "SELECT DISTINCT j.job, a.name, j.abundance FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @{ $data->{ $self->_mg_map->{$row[0]} }{$row[1]} }, $row[2];
    }
    $sth->finish;
    my $results = {};
    foreach my $mg (keys %$data) {
        my @ranked = map { [ $_, max @{$data->{$mg}{$_}} ] } keys %{$data->{$mg}};
        @ranked    = sort { ($b->[1] <=> $a->[1]) || ($a->[0] cmp $b->[0]) } @ranked;
        $results->{$mg} = [ @ranked[0..($limit-1)] ];
    }
    $self->_dbh->commit;
    return $results;
    # mgid => [ annotation, abundance ]
}

sub get_set_rank_abundance {
    my ($self, $limit, $type, $srcs, $all) = @_;

    unless ($limit && exists($self->_jtbl->{$type})) { return []; }
  
    my $data  = [];
    my $qsrcs = (@$srcs > 0) ? "j.source IN (" . join(",", map { $self->_src_id->{$_} } @$srcs) . ")" : "";
    my $qjobs = $all ? '' : 'j.'.$self->_qjobs;
    my $where = $self->_get_where_str(['j.'.$self->_qver, $qjobs, "j.id = a._id", $qsrcs]);
    my $qlim  = "LIMIT ".($limit * scalar(@$srcs));
    my $sql = "SELECT DISTINCT a.name, SUM(j.job) FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where." GROUP BY j.job ORDER BY SUM(j.job) DESC ".$limit;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        push @$data, \@row;
    }
    $sth->finish;
    $self->_dbh->commit;
    return $data;
    # [ annotation, job_count ]
}

sub get_global_rank_abundance {
    my ($self, $limit, $type, $src) = @_;
    return $self->get_set_rank_abundance($limit, $type, [$src], 1)
}

sub search_organisms {
    my ($self, $text) = @_;
    return $self->_search_annotations('organism', $text);
}

sub get_organisms_unique_for_source {
    my ($self, $source, $eval, $ident, $alen, $with_taxid) = @_;

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
    if (scalar(keys %$all_orgs) == 0) {
        return [];
    }

    my $ctax = $with_taxid ? ',ncbi_tax_id' : '';
    my $qtax = $with_taxid ? " AND ncbi_tax_id IS NOT NULL" : '';
    my $tax = {};
    my $tid = {};
    my $sql = "SELECT _id,COALESCE(tax_domain,'unassigned') AS txd,COALESCE(tax_phylum,'unassigned') AS txp,COALESCE(tax_class,'unassigned') AS txc,".
              "COALESCE(tax_order,'unassigned') AS txo,COALESCE(tax_family,'unassigned') AS txf,COALESCE(tax_genus,'unassigned') AS txg,".
              "COALESCE(tax_species,'unassigned') AS txs,name$ctax FROM ".$self->_atbl->{organism}." WHERE _id IN (".join(',', keys %$all_orgs).")$qtax";
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $oid = shift @row;
        if ($with_taxid) {
            my $t = pop @row;
            $tid->{$oid} = $t;
        }
        $tax->{$oid} = \@row;
    }
    $sth->finish;

    my $result = [];
    foreach my $mgid (keys %$mg_org_data) {
        foreach my $oid (keys %{$mg_org_data->{$mgid}}) {
            my $stats = $mg_org_data->{$mgid}{$oid};
            my $total = $stats->[0];
            my $abund = $stats->[1];
            my $md5s  = $stats->[8];
            my ($ea, $es, $ia, $is, $la, $ls) = (($stats->[2] / $total),($stats->[3] / $total),($stats->[4] / $total),($stats->[5] / $total),($stats->[6] / $total),($stats->[7] / $total));
            if (exists $tax->{$oid}) {
                my $data = [ $mgid, @{$tax->{$oid}}, $abund, $ea, $es, $ia, $is, $la, $ls, $md5s ];
                if ($with_taxid) {
                    if (exists $tid->{$oid}) {
                        push @$data, $tid->{$oid};
                    } else {
                        next;
                    }
                }
	            push @$result, $data;
            }
        }
    }
    $self->_dbh->commit;
    return $result;
    # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub get_organisms_for_sources {
    my ($self, $sources, $eval, $ident, $alen, $with_taxid) = @_;
    return $self->get_organisms_for_md5s([], $sources, $eval, $ident, $alen, $with_taxid);
}

sub get_organisms_for_md5s {
    my ($self, $md5s, $sources, $eval, $ident, $alen, $with_taxid) = @_;

    my $cache_key = "org".($with_taxid ? 'tid' : '');
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($sources) ? join(";", @$sources) : ":";

    my $data  = {};
    my $jobs  = [];
    my %mdata = ();
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            my $m = $self->_memd ? $self->_memd->get($mg.$cache_key."md5s") : undef;
            if ($c && $m) {
                $data->{$mg} = $c;
                $mdata{$mg}  = $m;
            } else {
                push @$jobs, $j;
            }
        }
    }
    unless (@$jobs) { return (\%mdata, [ map { @$_ } values %$data ]); }

    my %md5_set = ($md5s && (@$md5s > 0)) ? map {$_, 1} @$md5s : ();
    my $mg_md5_abund = $self->get_md5_abundance($eval, $ident, $alen);
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $ctax  = $with_taxid ? ',a.ncbi_tax_id' : '';
    my $qtax  = $with_taxid ? "a.ncbi_tax_id IS NOT NULL" : '';
    my $qsrcs = ($sources && (@$sources > 0)) ? "j.source IN (" . join(",", map { $self->_src_id->{$_} } @$sources) . ")" : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen, $qtax]);
    my $tax = "COALESCE(a.tax_domain,'unassigned') AS txd,COALESCE(a.tax_phylum,'unassigned') AS txp,COALESCE(a.tax_class,'unassigned') AS txc,".
              "COALESCE(a.tax_order,'unassigned') AS txo,COALESCE(a.tax_family,'unassigned') AS txf,COALESCE(a.tax_genus,'unassigned') AS txg,".
              "COALESCE(a.tax_species,'unassigned') AS txs,a.name";
    my $sql = "SELECT DISTINCT j.job,j.source,$tax,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s$ctax FROM ".
              $self->_jtbl->{organism}." j, ".$self->_atbl->{organism}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $sub_abund = 0;
        my $mg = $self->_mg_map->{$row[0]};
        if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row[17]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;
	    } else {
	        $sub_abund = $row[10];
	    }
	    my $drow = [ $mg, $self->_id_src->{$row[1]}, @row[2..10], $sub_abund, @row[11..16], join(";", @{$row[17]}) ];
	    if ($with_taxid) { push @$drow, $row[18]; }
	    push @{$data->{$mg}}, $drow;
	    map { $mdata{$mg}{$_} = $mg_md5_abund->{$mg}{$_} } grep { exists $mg_md5_abund->{$mg}{$_} } @{$row[17]};
    }
    $sth->finish;
    if ((! $qmd5s) && $self->_memd) {
        foreach my $mg (keys %$data) {
	        $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
	        $self->_memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->_expire);
	    }
    }
    $self->_dbh->commit;
    return (\%mdata, [ map { @$_ } values %$data ]);
    # mgid => md5 => abundance
    # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub search_ontology {
    my ($self, $text) = @_;
    return $self->_search_annotations('ontology', $text);
}

sub get_ontology_for_source {
    my ($self, $source, $eval, $ident, $alen) = @_;
    return $self->get_ontology_for_md5s([], $source, $eval, $ident, $alen);
}

sub get_ontology_for_md5s {
    my ($self, $md5s, $source, $eval, $ident, $alen) = @_;

    unless ($source) {
        return ({}, [])
    }
    
    my $cache_key = "ontol".$source;
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";

    my $data  = {};
    my $jobs  = [];
    my %mdata = ();
    my $qmd5s = ($md5s && (@$md5s > 0)) ? 1 : 0;
    
    if ($qmd5s) {
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            my $m = $self->_memd ? $self->_memd->get($mg.$cache_key."md5s") : undef;
            if ($c && $m) {
                $data->{$mg} = $c;
                $mdata{$mg}  = $m;
            } else {
                push @$jobs, $j;
            }
        }
    }
    unless (@$jobs) { return (\%mdata, [ map { @$_ } values %$data ]); }

    my %md5_set = $qmd5s ? map {$_, 1} @$md5s : ();
    my $mg_md5_abund = $self->get_md5_abundance($eval, $ident, $alen);
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $level = "COALESCE(a.level4, a.level3) as annotation";
    my $qsrcs = "a.source = ".$self->_src_id->{$source};
    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,a.name,$level,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s FROM ".
              $self->_jtbl->{ontology}." j, ".$self->_atbl->{ontology}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $sub_abund = 0;
        my $mg = $self->_mg_map->{$row[0]};
	    if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row[10]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;        
	    } else {
	        $sub_abund = $row[3];
	    }
	    push @{$data->{$mg}}, [ $mg, @row[1..3], $sub_abund, @row[4..9], join(";", @{$row[10]}) ];
	    map { $mdata{$mg}{$_} = $mg_md5_abund->{$mg}{$_} } grep { exists $mg_md5_abund->{$mg}{$_} } @{$row[10]};
    }
    $sth->finish;
    if ((! $qmd5s) && $self->_memd) {
        foreach my $mg (keys %$data) {
	        $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
	        $self->_memd->set($mg.$cache_key."md5s", $mdata{$mg}, $self->_expire);
	    }
    }
    $self->_dbh->commit;
    return (\%mdata, [ map { @$_ } values %$data ]);
    # mgid => md5 => abundance
    # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
}

sub search_functions {
    my ($self, $text) = @_;
    return $self->_search_annotations('function', $text);
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
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            if ($c) { $data->{$mg} = $c; }
            else    { push @$jobs, $j; }
        }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }

    my %md5_set = $qmd5s ? map {$_, 1} @$md5s : ();
    my $mg_md5_abund = $qmd5s ? $self->get_md5_abundance($eval, $ident, $alen) : {};
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $qsrcs = (@$sources > 0) ? "j.source in (" . join(",", map { $self->_src_id->{$_} } @$sources) . ")" : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT j.job,j.source,a.name,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv,j.md5s FROM ".
              $self->_jtbl->{function}." j, ".$self->_atbl->{function}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $sub_abund = 0;
        my $mg = $self->_mg_map->{$row[0]};
        
        if ($qmd5s) {
            my @has_md5 = grep { exists $md5_set{$_} } @{$row[10]};
            next unless ((@has_md5 > 0) && exists($mg_md5_abund->{$mg}));
            map { $sub_abund += $mg_md5_abund->{$mg}{$_} } grep { exists($mg_md5_abund->{$mg}{$_}) } @has_md5;        
	    } else {
	        $sub_abund = $row[3];
	    }
	    push @{$data->{$mg}}, [ $mg, $self->_id_src->{$row[1]}, @row[2,3], $sub_abund, @row[4..9], join(";", @{$row[10]}) ];
    }
    $sth->finish;
    if ((! $qmd5s) && $self->_memd) {
        foreach my $mg (keys %$data) {
	        $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
	    }
    }
    $self->_dbh->commit;
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
    while ( my ($mg, $j) = each %{$self->_job_map} ) {
        my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }
    
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
    
    my $where = $self->_get_where_str([$self->_qver, "job IN (".join(",", @$jobs).")", $eval, $ident, $alen]);
    my $sql = "SELECT DISTINCT job,lca,abundance,exp_avg,exp_stdv,ident_avg,ident_stdv,len_avg,len_stdv FROM ".$self->_jtbl->{lca}.$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $mg  = $self->_mg_map->{$row[0]};
        my @tax = ('-','-','-','-','-','-','-','-');
        my @lca = split(/;/, $row[1]);
        for (my $i=0; $i<@lca; $i++) {
    	    $tax[$i] = $lca[$i];
        }
        push @{$data->{$mg}}, [ $mg, @tax, @row[2..8] ];
    }
    $sth->finish;
    if ($self->_memd) {
        foreach my $mg (keys %$data) {
            $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
        }
    }
    $self->_dbh->commit;
    return [ map { @$_ } values %$data ];
    # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
}

sub get_md5_data {
    my ($self, $md5s, $eval, $ident, $alen, $ignore_sk, $rep_org_src) = @_;

    my $cache_key = "md5data";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= $rep_org_src ? $rep_org_src : ":";

    my $data = {};
    my $jobs = [];
    if ($md5s && (@$md5s > 0)) {
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            if ($c) { $data->{$mg} = $c; }
            else    { push @$jobs, $j; }
        }
    }
    unless (@$jobs) { return [ map { @$_ } values %$data ]; }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";
  
    my %umd5s = ($md5s && (@$md5s > 0)) ? map {$_, 1} @$md5s : ();
    my $qmd5s = ($md5s && (@$md5s > 0)) ? "j.md5 IN (" . join(",", keys %umd5s) . ")" : "";
    my $qseek = $ignore_sk ? "" : "j.seek IS NOT NULL AND j.length IS NOT NULL";
    my $qrep  = $rep_org_src ? "j.md5=r.md5 AND r.source=".$self->_src_id->{$rep_org_src} : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", $qrep, $qmd5s, $eval, $ident, $alen, $qseek]);
    my $cseek = $ignore_sk ? "" : ",j.seek,j.length";
    my $crep  = $rep_org_src ? ",r.organism" : "";
    my $sql   = "SELECT DISTINCT j.job,j.md5,j.abundance,j.exp_avg,j.exp_stdv,j.ident_avg,j.ident_stdv,j.len_avg,j.len_stdv${cseek}${crep} FROM ".
                $self->_jtbl->{md5}." j".($rep_org_src ? ", md5_organism_unique r" : "").$where.($ignore_sk ? "" : " ORDER BY job, seek");
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $j  = shift @row;
        my $mg = $self->_mg_map->{$j};
        push @{ $data->{$mg} }, [ $mg, @row ];
    }
    $sth->finish;
    if ($self->_memd) {
        foreach my $mg (keys %$data) {
            $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
        }
    }
    $self->_dbh->commit;
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
    if ($md5s && (@$md5s > 0)) {
        $jobs = $self->_jobs;
    } else {
        while ( my ($mg, $j) = each %{$self->_job_map} ) {
            my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
            if ($c) { $data->{$mg} = $c; }
            else    { push @$jobs, $j; }
        }
    }
    unless (@$jobs) { return $data; }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
  
    if ($md5s && (@$md5s > 0)) {
        my %umd5 = map {$_, 1} @$md5s;
        my $iter = natatime $self->_chunk, keys %umd5;
        while (my @curr = $iter->()) {
            my $qmd5s = "md5 IN (".join(",", map {"'$_'"} @curr).")";
            my $where = $self->_get_where_str([$self->_qver, "job IN (".join(",", @$jobs).")", $qmd5s, $eval, $ident, $alen]);
            my $sql = "SELECT DISTINCT job, md5, abundance FROM ".$self->_jtbl->{md5}.$where;
            my $sth = $self->_dbh->prepare($sql);
            $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
            while (my @row = $sth->fetchrow_array()) {
                $data->{ $self->_mg_map->{$row[0]} }{$row[1]} = $row[2];
            }
            $sth->finish;
        }
    } else {
        my $where = $self->_get_where_str([$self->_qver, "job IN (".join(",", @$jobs).")", $eval, $ident, $alen]);
        my $sql = "SELECT DISTINCT job, md5, abundance FROM ".$self->_jtbl->{md5}.$where;
        my $sth = $self->_dbh->prepare($sql);
        $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
        while (my @row = $sth->fetchrow_array()) {
            $data->{ $self->_mg_map->{$row[0]} }{$row[1]} = $row[2];
        }
        $sth->finish;        
    }
    if ($self->_memd) {
        foreach my $mg (keys %$data) {
            $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
        }
    }
    $self->_dbh->commit;
    return $data;
    # mgid => md5 => abundance
}

sub get_org_md5 {
    my ($self, $eval, $ident, $alen, $sources, $use_id, $use_taxid) = @_;
    return $self->_get_annotation_md5('organism', $eval, $ident, $alen, $sources, $use_id, $use_taxid);
}

sub get_ontol_md5 {
    my ($self, $eval, $ident, $alen, $source, $use_id) = @_;
    return $self->_get_annotation_md5('ontology', $eval, $ident, $alen, [$source], $use_id);
}

sub get_func_md5 {
    my ($self, $eval, $ident, $alen, $sources, $use_id) = @_;
    return $self->_get_annotation_md5('function', $eval, $ident, $alen, $sources, $use_id);
}

sub _get_annotation_md5 {
    my ($self, $type, $eval, $ident, $alen, $sources, $use_id, $use_taxid) = @_;
    
    my $cache_key = $type."md5";
    $cache_key .= defined($eval) ? $eval : ":";
    $cache_key .= defined($ident) ? $ident : ":";
    $cache_key .= defined($alen) ? $alen : ":";
    $cache_key .= defined($sources) ? join(";", @$sources) : ":";
    $cache_key .= defined($use_id) ? ':1' : ":0";
    $cache_key .= defined($use_taxid) ? ':1' : ":0";

    my $data = {};
    my $jobs = [];
    while ( my ($mg, $j) = each %{$self->_job_map} ) {
        my $c = $self->_memd ? $self->_memd->get($mg.$cache_key) : undef;
        if ($c) { $data->{$mg} = $c; }
        else    { push @$jobs, $j; }
    }
    unless (@$jobs) { return $data; }
  
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "j.exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "j.ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "j.len_avg >= $alen"    : "";

    my $key = $use_id ? 'j.id' : 'a.name';
    my $tid = '';
    if (($type eq 'organism') && $use_taxid) {
        $key = 'a.ncbi_tax_id';
        $tid = 'a.ncbi_tax_id IS NOT NULL';
    }
    my $qsrcs = ($sources && (@$sources > 0)) ? "j.source IN (" . join(",", map { $self->_src_id->{$_} } @$sources) . ")" : "";
    my $sql;
    if ($use_id && (! $use_taxid)) {
        my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", $qsrcs, $eval, $ident, $alen]);
        $sql = "SELECT DISTINCT j.job,$key,j.md5s FROM ".$self->_jtbl->{$type}." j".$where;
    } else {
        my $where = $self->_get_where_str(['j.'.$self->_qver, "j.job IN (".join(",", @$jobs).")", "j.id = a._id", $qsrcs, $eval, $ident, $alen, $tid]);
        $sql = "SELECT DISTINCT j.job,$key,j.md5s FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    }
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        my $mg = $self->_mg_map->{$row[0]};
        map { $data->{$mg}{$row[1]}{$_} = 1 } @{ $row[2] };
    }
    $sth->finish;
    if ($self->_memd) {
        foreach my $mg (keys %$data) {
            $self->_memd->set($mg.$cache_key, $data->{$mg}, $self->_expire);
        }
    }
    $self->_dbh->commit;
    return $data;
    # mgid => annotation/id => { md5 }
}

sub get_md5s_for_tax_level {
    my ($self, $level, $names, $source) = @_;
    return $self->_get_md5s_for_annotation_level('organism', $level, $names, $source);
}

sub get_md5s_for_ontol_level {
    my ($self, $source, $level, $names) = @_;
    return $self->_get_md5s_for_annotation_level('ontology', $level, $names, $source);
}

sub _get_md5s_for_annotation_level {
    my ($self, $type, $level, $names, $src) = @_;

    my $md5s = {};
    my $tbl  = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    my @cols = grep { $_ eq $level } @{ $self->_get_table_cols($tbl) };
    unless ($tbl && $level && (@cols == 1)) { return {}; }

    my $qsrc  = ($src) ? "j.source=".$self->_src_id->{$src} : "";
    my $qlvl  = ($names && (@$names > 0)) ? "a.$level IN (".join(",", map {$self->_dbh->quote($_)} @$names).")" : "a.$level IS NOT NULL AND a.$level != ''";
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "j.id = a._id", $qsrc, $qlvl]);
    my $sql = "SELECT j.md5s FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        map { $md5s->{$_} = 1 } @{$row[0]};
    }
    $sth->finish;
    $self->_dbh->commit;
    return [ keys %$md5s ];
    # [ md5 ]
}

sub get_md5s_for_organism {
    my ($self, $names, $source) = @_;
    return $self->_get_md5s_for_annotation('organism', $names, $source);
}

sub get_md5s_for_ontology {
    my ($self, $names, $source) = @_;
    return $self->_get_md5s_for_annotation('ontology', $names, $source);
}

sub get_md5s_for_function {
    my ($self, $names, $source) = @_;
    return $self->_get_md5s_for_annotation('function', $names, $source);
}

sub _get_md5s_for_annotation {
    my ($self, $type, $names, $src) = @_;
    
    my $md5s = {};
    my $tbl  = exists($self->_atbl->{$type}) ? $self->_atbl->{$type} : '';
    unless ($tbl && $names && @$names) { return {}; }
    
    my $qname = "a.name IN (".join(",", map {$self->_dbh->quote($_)} @$names).")";
    my $qsrc  = ($src) ? "j.source=".$self->_src_id->{$src} : "";
    my $where = $self->_get_where_str(['j.'.$self->_qver, 'j.'.$self->_qjobs, "j.id = a._id", $qname, $qsrc]);
    my $sql = "SELECT j.md5s FROM ".$self->_jtbl->{$type}." j, ".$self->_atbl->{$type}." a".$where;
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    while (my @row = $sth->fetchrow_array()) {
        map { $md5s->{$_} = 1 } @{$row[0]};
    }
    $sth->finish;
    $self->_dbh->commit;
    return [ keys %$md5s ];
    # [ md5 ]
}

# return fasta text
sub get_m5nr_sequences_from_md5s {
    my ($self, $md5s) = @_;
    
    unless ($md5s && (@$md5s > 0)) {
        return "";
    }
    
    my $response = "";
    my $url   = $self->_api."/m5nr/md5";
    my $pdata = $self->_json->encode({
        version  => $self->_version,
        sequence => 1,
        format   => 'fasta',
        data     => $md5s
    });

    eval {
        my $post = $self->_agent->post($url, Content => $pdata);
        $response = $post->content;
    };
    if ($@ || (! $response)) {
        return "";
    } elsif ($response =~ /ERROR/) {
        return "";
    }
    return $response;
}

sub get_taxa_to_level {
    my ($self, $taxa) = @_;
    
    my $data = {};
    my $response = undef;
    my $url = $self->_api."/m5nr/taxonomy?version=".$self->_version."&min_level=".$taxa;
    
    eval {
        my $get = $self->_agent->get($url);
        $response = $self->_json->decode($get->content);
    };
    if ($response && $response->{data} && @{$response->{data}}) {
        foreach my $set ( @{$response->{data}} ) {
            unless (exists $set->{$taxa}) {
                next;
            }
            $data->{$set->{$taxa}} = [];
            foreach my $name (('domain', 'phylum', 'class', 'order', 'family', 'genus', 'species')) {
                if ($name eq $taxa) {
                    last;
                }
                if (exists $set->{$name}) {
                    push @{ $data->{$set->{$taxa}} }, $set->{$name};
                } else {
                    push @{ $data->{$set->{$taxa}} }, "";
                }
            }
        }
    }
    # taxa => [ hierarchy from domain to one higher than taxa ]
    return $data;
}

