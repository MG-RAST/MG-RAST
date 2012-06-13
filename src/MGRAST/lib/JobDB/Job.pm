package JobDB::Job;

use strict;
use Data::Dumper;

use FIG_Config;
use DirHandle;
use File::Basename;
use IO::File;
use Fcntl ':flock';
use MGRAST::Metadata;

=pod

=head1 NAME

Job - MGRAST job access module

=head1 DESCRIPTION

TODO

=head1 METHODS

=over 4

=item * B<init> ()

Initialise a new instance of the Job object.

=cut

sub init {
  my $self = shift;

  # check if we are called properly
  unless (ref $self) {
    die "Not called as an object method.";
  }

  # parameters for the Job->init() call
  my $data = $_[0];
  unless (ref $data eq 'HASH') {
    die "Init without a parameters hash.";
  }

  my $job = $self->SUPER::init(@_);
  unless (ref $job) {
    print STDERR "Job init call failed.\n";
    return undef;
  }

  # # check if the user has the right to see this job
  unless ($job->public) {
    unless ( $job->_master->{_user} && $job->_master->{_user}->has_right(undef, 'view' , 'metagenome', $job->metagenome_id  ) ){
      return undef;
    }
  }
  return $job;
}

sub name {
  my ($self , $value) = @_ ;
  
  if ($value){
    $self->SUPER::name($value);
  }
  else{
    my $name = '';
    unless ($self->SUPER::name()){
      my $sample = $self->sample ;
      if ($sample and ref $sample){
	$name = join ";" , @{ $sample->data('sample_name') } ;
	$self->SUPER::name($name) if ($name) ;
      }
    }
  }

  return $self->SUPER::name() || 'unknown';
}

sub initialize {
  my ($self, $user, $data) = @_;

  my $master = $self->_master();
  unless (ref($master)) {
    print STDRER "reserve_job called without a dbmaster reference";
    return undef;
  }
  unless (ref($user)) {
    print STDRER "reserve_job called without a user";
    return undef;
  }

  my $dbh = $master->db_handle;
  my $max = $dbh->selectrow_arrayref("SELECT max(job_id + 0), max(metagenome_id + 0) FROM Job");
  my $job_id  = $max->[0] + 1;
  my $mg_id   = $max->[1] + 1;
  my $options = { owner => $user, job_id => $job_id, metagenome_id => $mg_id, server_version => 3 };
  my $params  = {};
 
  if (ref($data) eq "HASH") {
    $params = $data;
  }
  elsif ((! ref($data)) && (-s $data)) {
    my @lines = `cat $data`;
    chomp @lines;
    foreach my $line (@lines) {
      my ($k, $v) = split(/\t/, $line);
      $params->{$k} = $v;
    }
  }
  
  my $job_keys  = ['name','file','file_size','file_checksum','sequence_type'];
  my $stat_keys = ['bp_count','sequence_count','average_length','standard_deviation_length','length_min','length_max','average_gc_content','standard_deviation_gc_content','average_gc_ratio','standard_deviation_gc_ratio','ambig_char_count','ambig_sequence_count','average_ambig_chars','drisee_score'];

  foreach my $key (@$job_keys) {
    if (exists $params->{$key}) {
      if ($key =~ /^file_(size|checksum)/) {
	$options->{$key.'_raw'} = $params->{$key};
      } else {
	$options->{$key} = $params->{$key};
      }
    }
  }

  # Connect to User/Rights DB
  my $dbm = DBMaster->new(-database => $FIG_Config::webapplication_db,
			  -backend  => $FIG_Config::webapplication_backend,
			  -host     => $FIG_Config::webapplication_host,
			  -user     => $FIG_Config::webapplication_user,
			 );
  # check rights
  my $rights = ['view', 'edit', 'delete'];
  foreach my $right_name (@$rights) {
    my $objs = $dbm->Rights->get_objects({ scope     => $user->get_user_scope,
					   data_type => 'metagenome',
					   data_id   => $mg_id,
					   name      => $right_name,
					   granted   => 1 });
    unless (@$objs > 0) {
      my $right = $dbm->Rights->create({ scope     => $user->get_user_scope,
					 data_type => 'metagenome',
					 data_id   => $mg_id,
					 name      => $right_name,
					 granted   => 1 });
      unless (ref $right) {
	print STDRER "Unable to create Right $right_name - metagenome - $mg_id.";
	return undef;
      }
    }
  }

  ### now create job
  my $job = $master->Job->create($options);
  unless (ref $job) {
    print STDRER "Can't create job\n";
    return undef;
  }
  
  # store raw stats
  foreach my $key (@$stat_keys) {
    if (exists $params->{$key}) {
      $master->JobStatistics->create({ job => $job, tag => $key.'_raw', value => $params->{$key} });
    } elsif (exists $params->{$key.'_raw'}) {
      $master->JobStatistics->create({ job => $job, tag => $key.'_raw', value => $params->{$key.'_raw'} });
    }
  }

  # store attributes
  my $used_keys = {};
  map { $used_keys->{$_} = 1 } @$job_keys;
  map { $used_keys->{$_} = 1 } @$stat_keys;
  map { $used_keys->{$_.'_raw'} = 1 } @$stat_keys;
  
  foreach my $key (keys %$params) {
    next if (exists $used_keys->{$key});
    $key =~ s/\s+/_/g;
    $params->{$key} =~ s/\s+/_/g;
    $master->JobAttributes->create({ job => $job, tag => $key, value => $params->{$key} });
  }
  $job->set_filter_options();

  return $job;
}

sub reserve_job {
  my ($self, $user, $options, $stats) = @_;

  my $data = {};
  if (ref $options) {
    map { $data->{$_} = $options->{$_}; } keys %$options;
  }
  if (ref $stats) {
    map { $data->{$_} = $stats->{$_}; } keys %$stats;
  }
  return $self->initalize($user, $data);
}

sub has_checksum {
  my ($self, $checksum, $user) = @_;
  my $dbh = $self->_master->db_handle;
  my $md5 = $dbh->selectcol_arrayref("SELECT count(*) FROM Job WHERE file_checksum_raw='$checksum'".(($user && ref($user)) ? " AND owner=".$user->_id : ""));
  return ($md5 && @$md5 && ($md5->[0] > 0)) ? 1 : 0;  
}

sub finish_upload {
  my ($self, $file, $file_format) = @_ ;
  
  # create_and_submit_job -j <job_number> -f <sequence_file> [ -p <pipeline_name> -o <pipeline_options> --fastq --rna_only ]
  # set options 
  my $opts   = $self->set_job_options;
  my $format = ($file_format =~ /fastq/) ? "--fastq" : '' ;
  my $cmd    = $FIG_Config::create_job;
  my $params = " -j " . $self->job_id . " -f $file -o '$opts' $format";

  print STDERR "Calling $cmd $params\n";
  
  if ($cmd and -f $cmd) {
    my $output = `$cmd $params`;
    print STDERR $output;
    return $output;
  }
  else {
    print STDERR "Can't find $cmd\n";
    return 0;
  }
}

=pod 

=item * B<directory> ()

Returns the full path the job directory (without a trailing slash).

=cut

sub directory {
  my ($self) = @_;
  return $FIG_Config::mgrast_jobs.'/'.$self->job_id;
}

sub dir {
  my ($self) = @_;
  return $self->directory;
}

=pod 

=item * B<download_dir> ()

Returns the full path the download directory inside the job (without a trailing slash).

=cut

sub download_dir {
    my ($self, $stage) = @_ ;
    if ($stage) {
	return $self->directory.'/analysis/';
    }
    return $self->directory.'/raw/';
}

=pod 

=item * B<analysis_dir> ()

Returns the full path the analysis directory inside the job (without a trailing slash).

=cut

sub analysis_dir {
  my ($self) = @_;
  unless (-d $self->directory.'/analysis') {
    chdir($self->directory) or 
      die("Unable to change directory to ".$self->directory.": $!");
    mkdir "analysis", 0777 or 
      die("Unable to create directory analysis in ".$self->directory.": $!");
  }
  return $self->directory.'/analysis';
}

=pod

=item * B<download> ()

Returns the name of the project

=cut

sub download {
  my ($self , $stage_id , $file) = @_;

  if ($file) {
    if (open(FH, $self->download_dir($stage_id) . "/" . $file)) {
      print "Content-Type:application/x-download\n";  
      # print "Content-Length: " . length($content) . "\n";
      print "Content-Disposition:attachment;filename=".$self->metagenome_id. "." . $file ."\n\n";
      #print "<file name='".$self->metagenome_id. "." . $file ."'>";
      while (<FH>) {
	print $_ ;
      }
      return ( 1 , "" ) ;
    }
    else{
      return ( 0 , "Could not open download file " . $self->download_dir($stage_id) ."'$file'" );
    }
  }
  elsif (defined $stage_id){
    # Download uploaded files
    unless ($stage_id){ 
      
      opendir(DIR ,  $self->download_dir() ) ;
      while (my $file = readdir DIR ){
	next unless ($file =~/\.fna|\.fasta|\.sff|\.fastq|\.txt/) ;
	print STDERR "Downloading file $file";
	$self->download( '' , $file);
      }
      
    }
    
    return ( 1 , "" ) ;
  }
  else{
    # return list of download files
  }
  
  return 1;
}

=pod

=item * B<get_jobs_for_user> (I<user>, I<right>, I<viewable>)

Returns the Jobs objects the user I<user> has access to. Access to a job is defined
by the right to edit a genome of a certain metagenome_id. In the context of the RAST
server this method checks the 'edit - genome' rights of a user. Optionally, you can
change this by providing the parameter I<right> and setting it to eg. 'view'.
If present and true, the parameter I<viewable> restricts the query to jobs marked 
as viewable.

Please note you may not longer pass a scope to this function.

=cut

sub get_jobs_for_user {
  my ($self, $user, $right, $viewable) = @_;

  unless (ref $self) {
    die "Call method via the DBMaster.\n";
  }
 
  unless (ref $user and ( $user->isa("WebServerBackend::User"))) {
    print STDERR "No user given in method get_jobs_for_user.\n";
    die "No user given in method get_jobs_for_user.\n";
  }
  
  my $get_options = {};
  $get_options->{viewable} = 1 if ($viewable);
  my $right_to = $user->has_right_to(undef, $right || 'edit', 'metagenome');

  # check if first right_to is place holder
  if (scalar(@$right_to) and $right_to->[0] eq '*') {
    return $self->_master->Job->get_objects($get_options);
  } 
  
  $get_options->{owner} = $user;
  my $jobs = $self->_master->Job->get_objects($get_options);
  
  my %ids = map { $_ => 1 } @$right_to;
  foreach my $j (@$jobs){
    if ($j->metagenome_id){
		if (defined $ids{$j->metagenome_id}){
			delete $ids{$j->metagenome_id};
		}
    }
  }

  foreach (keys %ids){
	  my $tmp_j;
	  if($_){
		  $tmp_j = $self->_master->Job->init({ metagenome_id => $_ });
	  }
	  if($tmp_j){
		  if($viewable){
			  next unless $tmp_j->viewable;
		  } 
		  push @$jobs, $tmp_j;
	  } 
  }
  
  return $jobs;
}

sub get_jobs_for_user_fast {
    my ($self, $user_or_scope, $right, $viewable) = @_;
    
    unless (ref $self) {
	die "Call method via the DBMaster.\n";
    }
    
    unless (ref $user_or_scope and  ( $user_or_scope->isa("WebServerBackend::User") or $user_or_scope->isa("WebServerBackend::Scope"))) {
		print STDERR "No user or scope given in method get_jobs_for_user.\n";
		die "No user or scope given in method get_jobs_for_user.\n";
    }
    
    my $right_to = $user_or_scope->has_right_to(undef, $right || 'edit', 'metagenome');
    my $job_cond = "";

    if ($viewable) {
      $job_cond .= " AND viewable = 1";
    }
    unless (@$right_to and $right_to->[0] eq '*') {
      my @g = grep { $_ ne '*' } @$right_to;
      if (@g == 0) { return (); }
      $job_cond .= " AND metagenome_id IN ( " . join(", ", map { "'$_'" } @g) . ")";
    }

    my $dbh  = $self->_master()->db_handle();
    my $skip = $dbh->selectcol_arrayref(qq(SELECT DISTINCT job FROM JobAttributes WHERE tag='deleted' OR tag='no_sims_found'));
    if ($skip && @$skip) {
      $job_cond .= " AND j._id NOT IN (".join(",", @$skip).")";
    }
    my $res = $dbh->selectall_arrayref(qq(SELECT j.job_id, j.metagenome_id, j.name,
					  	j.file_size_raw, j.server_version,
					  	j.created_on, j.owner, j._owner_db, j.viewable, j.sequence_type,
					  	s.stage, s.status, s.timestamp, j._id
					  FROM Job j, PipelineStage s
					  WHERE s.job=j._id $job_cond
					  ORDER BY j.job_id DESC, s.timestamp ASC));
    my $ent = shift(@$res);
    my @out;
    while ($ent)
    {
		my($cur, $cur_genome, $cur_name, $cur_size, $cur_server_version, $cur_created, $cur_owner, $cur_owner_db, $jviewable, $jsequence_type, undef, undef, undef, $jid) = @$ent;
		my $stages = {};
		my $timed_stati = [];
		while ($ent and $ent->[0] eq $cur)
		{
			my($id, $genome, $name, $size, $vers, $created, $owner, $owner_db, $view, $type, $stage, $stat, $ts) = @$ent;
			
			$stages->{$stage} = $stat;
			push(@$timed_stati, [ $ts, $stage, $stat ]);
			$ent = shift(@$res);
		}
		push(@out, {
			    job_id => $cur,
			    metagenome_id => $cur_genome,
			    name => $cur_name,
			    project_name => '',
			    created_on => $cur_created,
			    status => $stages,
			    owner => $cur_owner,
			    owner_db => $cur_owner_db,
			    size => $cur_size,
			    server_version => $cur_server_version,
			    viewable => $jviewable,
			    _id => $jid,
			    sequence_type => $jsequence_type,
			    timed_stati => $timed_stati
			 });
    }
    return @out;
}

# new method section

=pod

=item * B<stats> ()

Returns a hash of all stats keys and values for a job. 
If a key is given , returns only hash of specified key, value pair.
Sets a value if key and value is given (return true or false if works)

=cut

sub stats {
  my ($self, $tag, $value) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth;
  
  if (defined($value) and $tag) {
    my $jstat = $self->_master->JobStatistics->get_objects( { job   => $self,
							      tag   => $tag,
							      value => $value
							    });
    if (ref $jstat and scalar @$jstat) {
      $jstat->[0]->value($value);
    }
    else{
      $jstat = $self->_master->JobStatistics->create( { job   => $self,
							tag   => $tag,
							value => $value
						      });
    }
    return 1;
  }
  elsif ($tag) {
    $sth = $dbh->prepare("SELECT tag , value FROM JobStatistics where job=".$self->_id." and tag='$tag'");
  }
  else {
    $sth = $dbh->prepare("SELECT tag , value FROM JobStatistics where job=".$self->_id);
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash   = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
  return $rhash;
}

sub get_deleted_jobs {
  my ($self) = @_;

  my $del  = $self->_master->JobAttributes->get_objects({tag => 'deleted'});
  my @jobs = map { $_->job } @$del;

  return \@jobs;
}

sub get_bad_jobs {
  my ($self) = @_;

  my $bad  = $self->_master->JobAttributes->get_objects({tag => 'no_sims_found'});
  my @jobs = map { $_->job } @$bad;

  return \@jobs;
}

=pod

=item * B<stage> ()

Returns a hash of all stages and current status for a given job id.

=cut

sub get_stages_fast {
  my ($self, $jobid) = @_;

  unless (ref $self) {
    die "Call method via the DBMaster.\n";
  }

  my $dbh = $self->_master()->db_handle();
  my $sth = $dbh->prepare("SELECT stage, status FROM PipelineStage where job=$jobid");
  $sth->execute;

  my $rhash = {};
  my $rows  = $sth->fetchall_arrayref();
  if ($rows && (@$rows > 0)) {
    %$rhash = map { $_->[0], $_->[1] } @$rows;
  }
  return $rhash;
}

sub stage_info {
  my ($self, $tag, $value) = @_;
  
  $self->stage($tag, $value);
}

=pod

=item * B<stage> ()

Returns a hash of all stages and current status for a job.
If a stage is given, returns only hash of specified stage, current status.
Insert or update a status if stage and status is given.

=cut

sub stage {
  my ($self, $tag, $value) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth;
  
  if ($value and $tag) {
    my $jstat = $self->_master->PipelineStage->get_objects( { job    => $self,
							      stage  => $tag,
							      status => $value,
							    });
    # update existing stage-status
    if ( ref($jstat) and scalar(@$jstat) ) {
      my $time = $self->get_timestamp();
      $jstat->[0]->value($value);
      $jstat->[0]->timestamp($time);
    }
    # insert new stage-status
    else{ 
      $jstat = $self->_master->PipelineStage->create( { job    => $self,
							stage  => $tag,
							status => $value,
						      });
    }
    return { $tag => $value };
  }
  
  # get current status for input stage
  elsif ($tag) {
    $sth = $dbh->prepare("SELECT stage, status FROM PipelineStage where job=" . $self->_id . " and stage='$tag'");
  }
  else {
    $sth = $dbh->prepare("SELECT stage, status FROM PipelineStage where job=" . $self->_id);
  }
  $sth->execute;

  my $results = $sth->fetchall_arrayref();
  my $rhash = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results;
  
  return $rhash;
}

=pod

=item * B<data> ()

Returns a hash of all attribute keys and values for a job. 
If a key is given , returns only hash of specified key, value pair.
Sets a value if key and value is given (return true or false if works)

=cut

sub data {
  my ($self, $tag, $value) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth;
  
  if (defined($value) and $tag) {

    if (ref $value){
      print STDERR "ERROR: invalid value type for $tag  ($value) \n";
      print STDERR Dumper $value;
      return 0;
    }
    my $jstat = $self->_master->JobAttributes->get_objects( { job   => $self,
							      tag   => $tag,
							      value => $value
							    });
    if (ref $jstat and scalar @$jstat) {
      $jstat->[0]->value($value);
    }
    else {
      $jstat = $self->_master->JobAttributes->create( { job   => $self,
							tag   => $tag,
							value => $value
						      });
    }
    return 1;
  }
  elsif ($tag) {
    $sth = $dbh->prepare("SELECT tag, value FROM JobAttributes where job=". $self->_id ." and tag='$tag'");
  }
  else {
    $sth = $dbh->prepare("SELECT tag, value FROM JobAttributes where job=". $self->_id);
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash   = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results;
  
  return $rhash;
}

=pod

=item * B<set_filter_options> ()

job function that checks JobAttributes for a given set of tags,
if exist then creates new tag 'filter_options' with concatanated string,
returns filter_options string

=cut

sub set_filter_options {
  my ($self) = @_;

  my $flags = { filter_ln    => [ 'min_ln', 'max_ln' ],
		filter_ambig => [ 'max_ambig' ],
		dynamic_trim => [ 'min_qual', 'max_lqb' ]
	      };
  my %tags = map { $_, 1 } map { ($_, @{$flags->{$_}}) } keys %$flags;
  my @opts = ();
  my $data = $self->data();
  my $skip = 1;

  foreach my $t ( keys %tags ) {
    $tags{$t} = exists($data->{$t}) ? $data->{$t} : 0;
  }

  foreach my $f ( keys %$flags ) {
    if ( $tags{$f} ) {
      $skip = 0;
      push @opts, $f;
      foreach my $s ( @{$flags->{$f}} ) { push @opts, "$s=" . $tags{$s}; }
    }
  }
  my $opts_string = $skip ? 'skip' : join(":", @opts);
  $self->data('filter_options', $opts_string);

  # reset job option string
  $self->set_job_options();

  return $opts_string;
}

=pod

=item * B<set_job_options> ()

job function that creates an options string based upon all tag / value pairs
in JobAttributes for job and sets $job->{options} to its value.
format: tag1=value1&tag2=value2 ...
returns options string

=cut

sub set_job_options {
  my ($self) = @_;

  my $job_data = $self->data();
  my @job_opts = ();

  while ( my ($t, $v) = each %$job_data ) {
    push @job_opts, "$t=$v";
  }
  my $opts_string  = join("&", @job_opts);
  $self->options($opts_string);

  return $opts_string;
}

sub env_package {
  my ($self) = @_;

  if ($self->sample) {
    my $eps = $self->sample->children('ep');
    if ($eps && @$eps) {
      return $eps->[0];
    }
  }
  return undef;
}

######################
# MIxS metadata methods
#####################

sub enviroment {
  my ($self) = @_;
  unless (defined $self->sample) { return []; }
  my $results = {};
  foreach my $type (('biome', 'feature', 'material')) {
    foreach my $val (@{$self->sample->value_set($type)}) {
      $val =~ s/^envo:\s?//i;
      $results->{$val} = 1;
    }
  }
  return [keys %$results];
}

sub biome {
  my ($self) = @_;
  unless (defined $self->sample) { return ''; }
  my $results = {};
  foreach my $val (@{$self->sample->value_set('biome')}) {
    $val =~ s/^envo:\s?//i;
    $results->{$val} = 1;
  }
  return (scalar(keys %$results) > 0) ? join(", ", keys %$results) : '';
}

sub feature {
  my ($self) = @_;
  unless (defined $self->sample) { return ''; }
  my $results = {};
  foreach my $val (@{$self->sample->value_set('feature')}) {
    $val =~ s/^envo:\s?//i;
    $results->{$val} = 1;
  }
  return (scalar(keys %$results) > 0) ? join(", ", keys %$results) : '';
}

sub material {
  my ($self) = @_;
  unless (defined $self->sample) { return ''; }
  my $results = {};
  foreach my $val (@{$self->sample->value_set('material')}) {
    $val =~ s/^envo:\s?//i;
    $results->{$val} = 1;
  }
  return (scalar(keys %$results) > 0) ? join(", ", keys %$results) : '';
}

sub seq_method {
  my ($self) = @_;
  my $sm_mdata = $self->get_metadata_value('seq_meth', 'library');
  my $sm_guess = $self->data('sequencing_method_guess');
  return $sm_mdata ? $sm_mdata : (exists($sm_guess->{sequencing_method_guess}) ? $sm_guess->{sequencing_method_guess} : '');
}

sub seq_type {
  my ($self) = @_;
  my $guess = $self->sequence_type || '';
  my $input = $self->get_metadata_value('investigation_type', 'library');
  ## calculated takes precidence over inputed
  $input = ($input =~ /metagenome/i) ? 'WGS' : (($input =~ /mimarks/i) ? 'Amplicon' : '');
  return $guess ? $guess : $input;
}

sub pubmed {
  my ($self) = @_;
  my $ids = $self->external_ids();
  return $ids->{pubmed_id} ? $ids->{pubmed_id} : '';
}

sub external_ids {
  my ($self) = @_;
  my $id_set = {};
  foreach my $id (("project", "ncbi", "greengenes")) {
    my $val = $self->get_metadata_value($id."_id", 'primary_project');
    $id_set->{$id} = $val;
  }
  foreach my $id (("pubmed", "gold")) {
    my $val = $self->get_metadata_value($id."_id", 'library');
    $id_set->{$id} = $val;
  }
  return $id_set;
}

sub location {
  my ($self) = @_;
  my $location = $self->get_metadata_value('location', 'sample');
  return $location;
}

sub country {
  my ($self) = @_;  
  my $country = $self->get_metadata_value('country', 'sample');
  $country =~ s/^(gaz|country):\s?//i;
  return $country;
}

sub geo_loc_name {
  my ($self) = @_;
  my $region   = [];
  my $location = $self->location;
  my $county   = $self->country;
  foreach my $md (($county, $location)) {
    if ($md) { push @$region, $md; }
  }
  return $region;
}

sub lat_lon {
  my ($self) = @_;
  my $lat = $self->get_metadata_value('latitude', 'sample');
  my $lon = $self->get_metadata_value('longitude', 'sample');
  return ($lat && $lon) ? [$lat, $lon] : [];
}

sub collection_date {
  my ($self) = @_;
  my $time_set = [];
  foreach my $tag (('collection_date', 'collection_time', 'collection_timezone')) {
    last if (($tag eq 'collection_timezone') && (@$time_set == 0));
    my $val = $self->get_metadata_value($tag, 'sample');
    if ($val) { push @$time_set, $val; }
  }
  return join(" ", @$time_set);
}

sub env_package_type {
  my ($self) = @_;
  return $self->get_metadata_value('env_package', 'sample');
}

sub get_metadata_value {
  my ($self, $tag, $type) = @_;
  unless (defined $self->$type) { return ''; }
  my $data = $self->$type->data($tag);
  return exists($data->{$tag}) ? $data->{$tag} : '';
}

sub jobs_mixs_metadata_fast {
  my ($self, $mgids) = @_;
  my $data = {};
  map { $data->{$_->{metagenome_id}} = $_ } @{ $self->fetch_browsepage_viewable(undef, $mgids) };
  return $data;
}

######################
# Class methods
#####################

sub fetch_browsepage_in_progress {
	my ($self, $user, $count_only) = @_;
	my %stage_to_pos = ( 'upload' => 3,
			     'preprocess' => 4,
			     'dereplication' => 5,
			     'screen' => 6,
			     'genecalling' => 7,
			     'cluster_aa90' => 8,
			     'loadAWE' => 9,
			     'sims' => 10,
			     'loadDB' => 11,
			     'done' => 12 );

	my $selopt = "( viewable = 0 or viewable is null ) and metagenome_id is not null";
	if (ref $user and ( $user->isa("WebServerBackend::User"))) {
		unless ($user->has_star_right('edit', 'metagenome')){
			$selopt .= ' and metagenome_id in ("';
			my @userjobs = $self->get_jobs_for_user_fast($user, 'edit');
			unless ( scalar @userjobs > 0 ) {
				return [];
			}
			$selopt .= join('","', map { $_->{'metagenome_id'} } @userjobs).'")';
		}
	} else {
		return [];
	}

	# get job info
	my $statement = "select _id, job_id, name, metagenome_id from Job where ".$selopt;
	my $dbh = $self->_master()->db_handle();
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	my $jobdata = $sth->fetchall_arrayref();
	$sth->finish;

	# get jobs to skip
	my $statement = "select job from JobAttributes where tag='deleted' or tag='no_sims_found'";
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	my %skip = map { $_->[0], 1 } @{ $sth->fetchall_arrayref() };
	$sth->finish;

	if ($count_only) {
	  my $num = 0;
	  map { $num += 1 } grep { ! exists $skip{$_->[0]} } @$jobdata;
	  return $num;
	} 
	return [] unless scalar @$jobdata;

	# get job stages
	my $data = {};
	my $statement = "select job, stage, status from PipelineStage where job in (".join(',',  map { $_->[0] } @$jobdata).") order by job";
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	while(my @row = $sth->fetchrow_array()){
	        next if (exists $skip{$row[0]});
		if(exists $data->{$row[0]}){
			$data->{$row[0]}->[$stage_to_pos{$row[1]}] = $row[2];
		} else {
			$data->{$row[0]} = [];
			$data->{$row[0]}->[$stage_to_pos{$row[1]}] = $row[2];
		}
	}
	$sth->finish;

	foreach my $jobrow (@$jobdata){
	        next if (exists $skip{$jobrow->[0]});
		$data->{$jobrow->[0]}->[0] = $jobrow->[1];
		$data->{$jobrow->[0]}->[1] = $jobrow->[2];
		$data->{$jobrow->[0]}->[2] = $jobrow->[3];
	}

	my $return_results = [];
	foreach my $k (sort keys %$data){
		push @$return_results, $data->{$k}; 
	}
	return $return_results;
}

sub fetch_browsepage_viewable {
  my ($self, $user, $mgids) = @_;
  my $mddb = MGRAST::Metadata->new();
  my $jobselopt = "";
  my $user_id = ""; 
  
  if ($mgids && (@$mgids > 0)) {
    $jobselopt = "viewable=1 and metagenome_id in (".join(",", map {"'$_'"} @$mgids).")";
  }
  elsif (ref $user and ( $user->isa("WebServerBackend::User"))) {
    $user_id = $user->_id();
    if ($user->has_star_right('view', 'metagenome')) {
      $jobselopt = "viewable=1";
    } else {
      my $userjobs = $user->has_right_to(undef, 'view', 'metagenome');
      if ($userjobs->[0] eq '*') {
	$jobselopt = "viewable=1";
      } elsif ( @$userjobs > 0 ) {
	$jobselopt = "viewable=1 and (public=1 or metagenome_id in (".join(",", map {"'$_'"} @$userjobs)."))";
      } else {
	$jobselopt = "viewable=1 and public=1";
      }
    }
  } else {
    $jobselopt = "viewable=1 and public=1";
  }
  
  # metadata
  my $data = [];
  my $dbh  = $self->_master()->db_handle();
  my $jsql = "select _id, job_id, metagenome_id, name, public, owner, sequence_type from Job where job_id is not null and ".$jobselopt;
  my $jobs = $dbh->selectall_arrayref($jsql);
  my @jids = map { $_->[1] } @$jobs;
  my $jmd  = $mddb->get_jobs_metadata_fast(\@jids);

  my $tags = ['bp_count_raw','sequence_count_raw','average_length_raw', 'drisee_score_raw', 'alpha_diversity_shannon'];
  my $ssql = "select job, tag, value from JobStatistics where job in (".join(",", map {$_->[0]}  @$jobs).") and tag in (".join(",", map {"'$_'"} @$tags).")";
  my $tmp  = $dbh->selectall_arrayref($ssql);
  my $stat = {};
  map { $stat->{$_->[0]}{$_->[1]} = $_->[2] } @$tmp;

  foreach my $job (@$jobs) { #_id, job_id, metagenome_id, name, public, owner, sequence_type
    my $row = { '_id'             => $job->[0],
		'job_id'          => $job->[1],
		'metagenome_id'   => $job->[2],
		'name'            => $job->[3] || '',
		'public'          => ($job->[4]) ? 1 : 0,
		'shared'          => ($job->[4]) ? '' : ($job->[5] eq $user_id) ? 0 : 1,
		'bp_count'        => $stat->{$job->[0]}{bp_count_raw} || 0,
		'sequence_count'  => $stat->{$job->[0]}{sequence_count_raw} || 0,
		'average_length'  => $stat->{$job->[0]}{average_length_raw} || '',
		'drisee'          => $stat->{$job->[0]}{drisee_score_raw} || '',
		'alpha_diversity' => $stat->{$job->[0]}{alpha_diversity_shannon} || ''
	      };
    if (exists $jmd->{$job->[1]}{project}) {
      my $proj = $jmd->{$job->[1]}{project};
      $proj->{id} =~ s/^mgp//;
      $row->{project}      = $proj->{name};
      $row->{project_id}   = $proj->{id};
      $row->{pi}           = exists($proj->{data}{PI_lastname}) ? $proj->{data}{PI_lastname} : '';
      $row->{pi_firstname} = exists($proj->{data}{PI_firstname}) ? $proj->{data}{PI_firstname} : '';
      $row->{pi_email}     = exists($proj->{data}{PI_email}) ? $proj->{data}{PI_email} : '';
    }
    if (exists $jmd->{$job->[1]}{sample}) {
      my $samp = $jmd->{$job->[1]}{sample};
      my $dt = [];
      foreach my $tag (('collection_date', 'collection_time', 'collection_timezone')) {
	my $val = exists($samp->{data}{$tag}) ? $samp->{data}{$tag} : '';
	if ($val) { push @$dt, $val; }
      }
      $row->{collection_date} = (@$dt > 0) ? join(' ', @$dt) : '';
      $row->{biome}       = exists($samp->{data}{biome}) ? $samp->{data}{biome} : '';
      $row->{feature}     = exists($samp->{data}{feature}) ? $samp->{data}{feature} : '';
      $row->{material}    = exists($samp->{data}{material}) ? $samp->{data}{material} : '';
      $row->{env_package} = exists($samp->{data}{env_package}) ? $samp->{data}{env_package} : (exists($jmd->{$job->[1]}{env_package}) ? $jmd->{$job->[1]}{env_package}{type} : '');
      $row->{altitude}    = exists($samp->{data}{altitude}) ? $samp->{data}{altitude} : (exists($samp->{data}{elevation}) ? $samp->{data}{elevation} : '');
      $row->{depth}       = exists($samp->{data}{depth}) ? $samp->{data}{depth} : '';
      $row->{location}    = exists($samp->{data}{location}) ? $samp->{data}{location} : '';
      $row->{country}     = exists($samp->{data}{country}) ? $samp->{data}{country} : '';
      $row->{latitude}    = exists($samp->{data}{latitude}) ? $samp->{data}{latitude} : '';
      $row->{longitude}   = exists($samp->{data}{longitude}) ? $samp->{data}{longitude} : '';
      $row->{temperature} = exists($samp->{data}{temperature}) ? $samp->{data}{temperature} : '';
      $row->{ph}          = exists($samp->{data}{ph}) ? $samp->{data}{ph} : '';
    }
    if (exists $jmd->{$job->[1]}{library}) {
      my $lib = $jmd->{$job->[1]}{library};
      $row->{'sequencing method'} = exists($lib->{data}{seq_meth}) ? $lib->{data}{seq_meth} : '';
      $row->{sequence_type}       = $lib->{type} ? $lib->{type} : $job->[6];
    }
    push(@$data, $row);
  }
  
  return $data;
}

sub last_id {
    my ($self) = @_;

    my $dbh = $self->_master()->db_handle();
    my $sth = $dbh->prepare("SELECT max(job_id), max(metagenome_id + 0) FROM Job");
    $sth->execute;
    my $result = $sth->fetchrow_arrayref();
    return ( $result->[0] || "0" ,  $result->[1] || "0") ;
}

sub count_recent {
  my ($self , $days) = @_;
  $days = 30 if (!$days);
  my $dbh = $self->_master()->db_handle();
  my $sth = $dbh->prepare("select count(_id) from Job where created_on > current_timestamp - interval ".$days." day");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();
  return ( $result->[0] ) ;
}

sub count_total_bp {
  my ($self) = @_;
  my $dbh = $self->_master()->db_handle();
  my $sth = $dbh->prepare("select sum(value) from JobStatistics where tag = 'bp_count_raw'");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();
  return ( $result->[0] ) ;
}

sub in_projects {
  my ($self, $public) = @_;
  
  my $pub_option = "";
  if ((defined $public) && ($public == 0)) {
    $pub_option = "(Job.public = 0 or Job.public is NULL)";
  } else {
    $pub_option = "Job.public = 1";
  }
  
  my $dbh = $self->_master()->db_handle();
  
  my $statement = "select metagenome_id, name, sequence_type, file_size_raw, public, viewable from Job where $pub_option and exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id)";
  my $sth = $dbh->prepare($statement);
  $sth->execute;
  my $data = $sth->fetchall_arrayref();
  return $data;
}

sub without_project {
  my ($self, $public) = @_;

  my $pub_option = "";
  if ((defined $public) && ($public == 0)) {
    $pub_option = "(Job.public = 0 or Job.public is NULL)";
  } else {
    $pub_option = "Job.public = 1";
  }

  my $dbh = $self->_master()->db_handle();

  my $statement = "select metagenome_id, name, sequence_type, file_size_raw, public, viewable from Job where $pub_option and not exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id)";
  my $sth = $dbh->prepare($statement);
  $sth->execute;
  my $data = $sth->fetchall_arrayref();
  return $data;
}



sub count_total_sequences {
  my ($self) = @_;
  my $dbh = $self->_master()->db_handle();
  my $sth = $dbh->prepare("select sum(value) from JobStatistics where tag = 'sequence_count_raw'");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();
  return ( $result->[0] );
}

sub count_all {
 my ($self , $user) = @_;
 
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(_id) from Job where job_id is not null");
 $sth = $dbh->prepare("SELECT count(_id) FROM Job where owner=".$user->_id." and job_id is not null") if ($user and ref $user);
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] );
}

sub count_public {
 my ($self) = @_;
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(*) FROM Job where public and viewable");
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] );
}

sub count_public_wgs {
 my ($self) = @_;
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(*) FROM Job where public and viewable and sequence_type = 'WGS' ");
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] );
}

sub count_public_amplicon {
 my ($self) = @_;
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(*) FROM Job where public and viewable and sequence_type = 'Amplicon'");
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] );
}

sub get_timestamp {
  my ($self, $time) = @_;

  unless ($time) {
    $time = time;
  }
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
  return sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
}

#################
# delete methods
#################

sub delete {
  my ($self) = @_;

  # get a web app master
  my $webapp_dbm = DBMaster->new(-database => $FIG_Config::webapplication_db,
                                 -backend => $FIG_Config::webapplication_backend,
                                 -host => $FIG_Config::webapplication_host,
                                 -user => $FIG_Config::webapplication_user,
                                );

  # get the job master
  my $dbm = $self->_master();
  unless (ref($webapp_dbm)) {
    die "Could not initialize WebApplication DBMaster in Job->delete";
  }
  
  # delete all rights to the job
  my $job_rights = $webapp_dbm->Rights->get_objects( { data_type => 'metagenome',
                                                       data_id => $self->metagenome_id } );
  foreach my $right (@$job_rights) {
    $right->delete();
  }
  
  # delete all pipeline stages
  my $pipeline_stages = $dbm->PipelineStage->get_objects( { job => $self } );
  foreach my $pipeline_stage (@$pipeline_stages) {
    $pipeline_stage->delete();
  }

  # delete all job statistics
  my $statistics = $dbm->JobStatistics->get_objects( { job => $self } );
  foreach my $statistic (@$statistics) {
    $statistic->delete();
  }

  # delete all references to projects
  my $projectjobs = $dbm->ProjectJob->get_objects( { job => $self } );
  foreach my $projectjob (@$projectjobs) {
    $projectjob->delete();
  }

  # delete all attributes
  my $jobattributes = $dbm->JobAttributes->get_objects( { job => $self } );
  foreach my $jobattribute (@$jobattributes) {
    $jobattribute->delete();
  }

  # delete all jobgroup references
  my $jobgroupjobs = $dbm->JobgroupJob->get_objects( { job => $self } );
  foreach my $jobgroupjob (@$jobgroupjobs) {
    $jobgroupjob->delete();
  }

  # delete the job directory
  if (-d $self->directory) {
    my $dir = $self->directory;
    `rm -rf $dir`;
    if (-d $dir) {
      die "Could not delete job directory $dir: $@";
    }
  }

  # delete self
  $self->SUPER::delete(@_);
  return 1;
}

1;
