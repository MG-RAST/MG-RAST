package JobDB::Job;

use strict;
use Data::Dumper;

use Global_Config;
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
#    print STDERR Dumper $self ;
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

sub name{
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

sub reserve_job {
  my ($self, $user , $options , $stats) = @_;
  
  my $master = $self->_master();
  unless (ref($master)) {
    die "reserve_job called without a dbmaster reference";
  }
  
  unless (ref($user)) {
    die "reserve_job called without a user";
  }
  
  my $dbh = $master->db_handle;
  my $sth = $dbh->prepare("SELECT max(job_id + 0), max(metagenome_id + 0) FROM Job");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();

  my $job_id        = $result->[0] + 1;
  my $metagenome_id = $result->[1] + 1;
  
  
  
  my $job = $master->Job->create( { owner => $user, job_id => $job_id, metagenome_id => $metagenome_id , server_version => 3 } );

  unless(ref $job){
    print STDRER "Can't create job for: { owner => $user, job_id => $job_id, metagenome_id => $metagenome_id , server_version => 3 }\n";
    exit;
  }

  # Connect to User/Rights DB
  my $dbm = DBMaster->new(-database => $Global_Config::webapplication_db,
			  -backend  => $Global_Config::webapplication_backend,
			  -host     => $Global_Config::webapplication_host,
			  -user     => $Global_Config::webapplication_user,
			 );
     
  # check rights
  my $rights = [ 'view', 'edit', 'delete' ];
  foreach my $right_name (@$rights) {
    unless( scalar( @{ $dbm->Rights->get_objects({ scope       => $user->get_user_scope,
						   data_type   => 'metagenome',
						   data_id     => $metagenome_id,
						   name        => $right_name,
						   granted     => 1,
						 }) 
		     }))
      {
	my $right = $dbm->Rights->create({ scope       => $user->get_user_scope,
					   data_type   => 'metagenome',
					   data_id     => $metagenome_id,
					   name        => $right_name,
					   granted     => 1,
					 });
	unless (ref $right) {
	  die "Unable to create Right $right_name - metagenome - $metagenome_id.";
	}
      }
  }
  
  # store raw stats
  if ($stats and ref $stats){
    foreach my $s (keys %$stats) {
      $job->stats( $s.'_raw', $stats->{$s} );
    }
  }

  # store options
  if ($options and ref $options){
    my $default =  $Global_Config::mgrast_pipeline_default_options ;
    foreach my $opt (keys %$options){
      $default->{ $opt } = $options->{ $opt} ;
    }

    foreach my $opt (keys %$default){
      $job->data( $opt, $default->{$opt} );
    }
  }
  $self->set_filter_options();
    
  return $job;
}


sub finish_upload {
  my ($self , $file , $pipeline , $file_format) = @_ ;
  
  # set options 
  my $opts   = $self->set_job_options ;
  my $format = ($file_format =~ /fastq/) ? "--fastq" : '' ;
  my $cmd     = $Global_Config::create_job_qiime;
  #my $cmd    = $Global_Config::create_job;

  #  -j <job_number> -f <sequence_file> [ -p <pipeline_name> -o <pipeline_options> --fastq --rna_only ]
  my $params  = " -j " . $self->job_id . " -f $file -p $pipeline -o '$opts' $format";

  print STDERR "Calling $cmd\n";
  
  if ($cmd and -f $cmd){
    my $output = `$cmd $params` ;
    print STDERR $output ;
    return $output ;
  }
  else{
    print STDERR "Can't find $cmd\n";
    return 0 ;
  }
}

sub create_job{
  my ($self , $file) = @_ ;
  #my $cmd = $Global_Config::Pipeline . "/create_job -j $id -u $file -f $file " ;
}

sub submit {
  my ($self , $sequence_type) = @_ ;
  #my $cmd = $Global_Config::Pipeline . "/submit_stages -j $id $pipeline " ;  
}

=pod 

=item * B<directory> ()

Returns the full path the job directory (without a trailing slash).

=cut

sub directory {
  return $Global_Config::mgrast_jobs.'/'.$_[0]->job_id;
}

sub dir{
  my ($self) = @_;
  return $self->directory ;
}

=pod 

=item * B<download_dir> ()

Returns the full path the download directory inside the job (without a trailing slash).

=cut

sub download_dir {
    my ($self , $stage) = @_ ;
    if ($stage){
	return $_[0]->directory.'/analysis/';
    }
    return $_[0]->directory.'/raw/';
}


=pod 

=item * B<analysis_dir> ()

Returns the full path the analysis directory inside the job (without a trailing slash).

=cut

sub analysis_dir {
  unless (-d $_[0]->directory.'/analysis') {
    chdir($_[0]->directory) or 
      die("Unable to change directory to ".$_[0]->directory.": $!");
    mkdir "analysis", 0777 or 
      die("Unable to create directory analysis in ".$_[0]->directory.": $!");
  }
  return $_[0]->directory.'/analysis';
}

=pod

=item * B<downloads> ()

Returns the name of the project

=cut

sub downloads {
  return [];
}

=pod

=item * B<download> ()

Returns the name of the project

=cut

sub download {
  my ($self , $stage_id , $file) = @_;


  if ($file){
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
    print STDERR "Found defined stage '$stage_id' '$file'\n";
    
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

=item * B<project> ()

Returns the name of the project

=cut

sub project {
  return;
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

    my $job_cond = "true";

    if ($viewable)
    {
		$job_cond .= " AND viewable = 1";
    }
    if (@$right_to and $right_to->[0] eq '*')
    {
    }
    else
    {
		my @g = grep { $_ ne '*' } @$right_to;
		if (@g == 0)
		{
			return ();
		}
		$job_cond .= " AND metagenome_id IN ( " . join(", ", map { "'$_'" } @g) . ")";
    }
    

    my $dbh = $self->_master()->db_handle();
    my $res = $dbh->selectall_arrayref(qq(SELECT j.job_id, j.metagenome_id, j.name, p.name,
					  	j.file_size_raw, j.server_version,
					  	j.created_on, j.owner, j._owner_db, j.viewable, j.sequence_type,
					  	s.stage, s.status, j._id
					  FROM Job j LEFT JOIN (PipelineStage s, Project p) ON (s.job = j._id AND p._id = j.Project)
					  WHERE $job_cond
					  ORDER BY j.job_id DESC));
    my $ent = shift(@$res);
    my @out;
    while ($ent)
    {
		my($cur, $cur_genome, $cur_name, $cur_proj, $cur_size, $cur_server_version, $cur_created, $cur_owner, $cur_owner_db, $jviewable, $jsequence_type, undef, undef, $jid) = @$ent;
		my $stages = {};
		
		while ($ent and $ent->[0] eq $cur)
		{
			my($id, $genome, $name, $proj, $size, $vers, $created, $owner, $owner_db, $view, $stage, $stat) = @$ent;
			
			$stages->{$stage} = $stat;
			$ent = shift(@$res);
		}
		push(@out, {
			    job_id => $cur,
			    metagenome_id => $cur_genome,
			    name => $cur_name,
			    project_name => $cur_proj,
			    created_on => $cur_created,
			    status => $stages,
			    owner => $cur_owner,
			    owner_db => $cur_owner_db,
			    size => $cur_size,
			    server_version => $cur_server_version,
			    viewable => $jviewable,
			    _id => $jid,
			    sequence_type => $jsequence_type
			 });
    }
    return @out;
}

# new method section

=pod

=item * B<stats> ()

Returns a hash of all stats keys and values for a job. 
If a key is given , returns only hash of specified 
key , value pair. Sets a value if key and value is given

=cut

sub stats {
  my ( $self , $tag , $value ) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth ;
  
  if (defined($value) and $tag){
    my $jstat = $self->_master->JobStatistics->get_objects( { job   => $self ,
							      tag   => $tag  ,
							      value => $value ,
							    });
    if ( ref $jstat and scalar @$jstat ){
      $jstat->[0]->value($value) ;
    }
    else{
      $jstat = $self->_master->JobStatistics->create( { job   => $self ,
							tag   => $tag  ,
							value => $value ,
						      });
    }

    return { $tag => $value } ;
  }
  elsif( $tag ){
    $sth = $dbh->prepare("SELECT tag , value FROM JobStatistics where job='". $self->_id ."' and tag='$tag'") ;

    $sth->execute;
    my $results = $sth->fetchall_arrayref();
    if (ref $results and scalar @$results == 1){ 
      return $results->[0]->[1] ;
    }
    else { 
      return map { $_->[1] } @$results  ;
    }
    
  }
  else{
    $sth = $dbh->prepare("SELECT tag , value FROM JobStatistics where job='". $self->_id ."'");
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
  return $rhash;
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
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
  return $rhash;
}

=pod

=item * B<data> ()

Returns a hash of all stats keys and values for a job. 
If a key is given , returns only hash of specified 
key , value pair. Sets a value if key and value is given

=cut

sub data {
  my ( $self , $tag , $value ) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth ;
  
  if (defined($value) and $tag){

    if (ref $value){
      print STDERR "ERROR: invalid value type for $tag  ($value) \n" ;
      print STDERR Dumper $value ;
      return 0 ;
    }
    my $jstat = $self->_master->JobAttributes->get_objects( { job   => $self ,
							      tag   => $tag  ,
							      value => $value ,
							    });
    if ( ref $jstat and scalar @$jstat ){
      $jstat->[0]->value($value) ;
    }
    else{
      $jstat = $self->_master->JobAttributes->create( { job   => $self ,
							tag   => $tag  ,
							value => $value ,
						      });
    }

    return { $tag => $value } ;
  }
  elsif( $tag ){
    $sth = $dbh->prepare("SELECT tag, value FROM JobAttributes where job='". $self->_id ."' and tag='$tag'") ;
    $sth->execute;
    my $results = $sth->fetchall_arrayref();
    return map { $_->[1] } @$results ;
  }
  else{
    $sth = $dbh->prepare("SELECT tag, value FROM JobAttributes where job='". $self->_id ."'");
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
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

  foreach my $t ( keys %tags ) {
    $tags{$t} = exists($data->{$t}) ? $data->{$t} : 0;
  }

  foreach my $f ( keys %$flags ) {
    if ( $tags{$f} ) {
      push @opts, $f;
      foreach my $s ( @{$flags->{$f}} ) { push @opts, "$s=" . $tags{$s}; }
    }
  }
  my $opts_string = join(":", @opts);
  $self->data('filter_options', $opts_string);

  # reset job option string
  $self->set_job_options();

  return $opts_string;
}

=pod

=item * B<set_filter_options> ()

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

=pod

=item * B<biome> ()

Returns biome for a job

=cut

sub biome {
  my ($self) = @_;
  my @biomes ;
  push @biomes , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "biome-information_envo_lite" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_biome" }) } , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_feature" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_matter" }) };
  my @results = grep { $_ =~ /\S/ } map { $_->value } @biomes;
  
  return (join ";" , @results ) || 'unknown' ;
}

sub biomes {
  my ($self) = @_;
  my @biomes ;
  push @biomes , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "biome-information_envo_lite" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_biome" }) } , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_feature" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "env_matter" }) };
  my $biome = {} ;
  map { $biome->{ $_->value || 'unknown' }++ } @biomes;
  
  return [ keys %$biome ]  ;
}

sub pubmed {
  my ($self) = @_;
  my @obj ;
  push @obj , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "external-ids_pubmed_id" })  };
  my @results = grep { $_ =~ /\S/ } map { $_->value } @obj;
  
  return \@results ;
}


sub location {
  my ($self) = @_;
  my @locations ;
  push @locations , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "sample-origin_location" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "specific_location" }) } ;
  my @results = grep { $_ =~ /\S/ } map { $_->value } @locations;
  
  return (join ";" , @results ) || '-' ;
}

sub country {
  my ($self) = @_;
  my @country ;
  push @country , @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "sample-origin_country" }) } ,  @{ $self->_master->MetaDataEntry->get_objects({ job => $self, tag => "country" }) } ;
  my @results = grep { $_ =~ /\S/ } map { $_->value } @country;
  
  return (join ";" , @results ) || '-' ;
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
						 'loadDB_ALL' => 10,
						 'done' => 11 );

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

	my $statement = "select _id, job_id, name, metagenome_id from Job where ".$selopt;

	my $dbh = $self->_master()->db_handle();
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	my $jobdata = $sth->fetchall_arrayref();
	$sth->finish;
	
	if ($count_only){
	  return scalar @$jobdata;
	} 

	my $data = {};
	my $statement = "select job, stage, status from PipelineStage where job in (".join(',',  map { $_->[0] } @$jobdata).") order by job";
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	while(my @row = $sth->fetchrow_array()){
		if(exists $data->{$row[0]}){
			$data->{$row[0]}->[$stage_to_pos{$row[1]}] = $row[2];
		} else {
			$data->{$row[0]} = [];
			$data->{$row[0]}->[$stage_to_pos{$row[1]}] = $row[2];
		}
	}
	$sth->finish;

	foreach my $jobrow (@$jobdata){
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
	my ($self, $user) = @_;
	my $mddb = MGRAST::Metadata->new();
	my $md_data = {};
	my $pi_data = {};
	my $jobselopt = "";
	my $projselopt = "";
	my $user_id = ""; 

	if (ref $user and ( $user->isa("WebServerBackend::User"))) {
		$user_id = $user->_id();
		if ($user->has_star_right('view', 'metagenome')){
			$jobselopt = 'viewable=1';
			$projselopt = 'Job.viewable=1';
		} else {
			$jobselopt = 'viewable=1 and ( public=1 or metagenome_id in ("';
			$projselopt = 'Job.viewable=1 and ( Job.public=1 or Job.metagenome_id in ("';
			my @userjobs = $self->get_jobs_for_user_fast($user, 'view');
			my $mgids = join '","', map { $_->{'metagenome_id'} } @userjobs;
			$jobselopt .= $mgids.'"))';
			$projselopt .= $mgids.'"))';
		}
	} else {
		$jobselopt = 'viewable=1 and public=1';
		$projselopt = 'Job.viewable=1 and Job.public=1';		
	}

	# metadata
	my $statement = "select tag, value, job from MetaDataEntry join Job on Job._id=MetaDataEntry.job where tag in ('env_biome', 'biome-information_envo_lite', 'sample-origin_altitude', 'sample-origin_depth', 'sample-origin_location', 'sample-origin_ph', 'sample-origin_country', 'sample-origin_temperature', 'sequencing_sequencing_method') and job is not null and ".$jobselopt;


	my $dbh = $self->_master()->db_handle();
	my $sth = $dbh->prepare($statement);
	$sth->execute;
	while(my @row = $sth->fetchrow_array) {
		unless (exists($md_data->{$row[2]})) {
			$md_data->{$row[2]} = [];
		}
		push @{$md_data->{$row[2]}}, \@row;
	}
	$sth->finish;

	# pi data
	$statement = "select j, value, tag from (select job as j, ProjectJob.project as p from ProjectJob join Job on Job._id=job where ".$jobselopt.") as t1 join ProjectMD on ProjectMD.project=p where tag='PI_lastname'";
	
	$sth = $dbh->prepare($statement);
	$sth->execute;
	while(my @row = $sth->fetchrow_array) {
		unless (exists($pi_data->{$row[0]})) {
			$pi_data->{$row[0]} = [];
		}
		push @{$pi_data->{$row[0]}}, \@row;
	}
	$sth->finish;

	# project and job data
	$statement = "select Job._id, Job.name, t1.name, Job.metagenome_id, t1.id, Job.job_id, Job.public, Job.owner, Job.sequence_type from Job left join (select Project.name, job, Project.id from ProjectJob join Project on Project._id=ProjectJob.project) as t1 on Job._id=t1.job where ".$projselopt;
	
	my $project_data = [];
	$sth = $dbh->prepare($statement);
	$sth->execute;
	while(my @row = $sth->fetchrow_array) {
		push @$project_data, \@row;
	}
	$sth->finish;

	my $md_list = { 'biome-information_envo_lite' => 'biome',
					'env_biome' => 'biome',
					'sample-origin_altitude' => 'altitude',
					'sample-origin_depth' => 'depth',
					'sample-origin_location' => 'location',
					'sample-origin_ph' => 'ph',
					'sample-origin_country' => 'country',
					'sample-origin_temperature' => 'temperature',
					'sequencing_sequencing_method' => 'sequencing method', 
					'PI_lastname' => 'pi' };
	
	my $data = [];
	foreach my $job (@$project_data) {
        # [ 'job_id', 'metagenome_id', 'name', 'project', 'project_id', 'biome', 'altitude', 'depth', 'location', 'ph', 'country', 'temperature', 'sequencing method', 'PI',  public, shared]
		my $row = { 'job_id' => $job->[5], 
					'metagenome_id' => $job->[3], 
					'name' =>  $job->[1], 
					'project' => $job->[2] || "", 
					'project_id' => $job->[4] || "",
					'public' => ($job->[6]) ? 1 : 0,
					'shared' => ($job->[6]) ? '' : ($job->[7] eq $user_id) ? 0 : 1,
					'sequence_type' => $job->[8] };
		
		if (exists($md_data->{$job->[0]})) {
			foreach my $m (@{$md_data->{$job->[0]}}) {
				if ($m->[1] ne "" && $md_list->{$m->[0]}) {
					unless ( exists $row->{$md_list->{$m->[0]}} ) {
						$row->{$md_list->{$m->[0]}} = $mddb->unencode_value($m->[0], $m->[1]);
					} else {
						$row->{$md_list->{$m->[0]}} .= ", ".$mddb->unencode_value($m->[0], $m->[1])
					}
				}
			}
		}
		if (exists($pi_data->{$job->[0]})) {
			foreach my $m (@{$pi_data->{$job->[0]}}) {
				if ($m->[1] ne "" && $md_list->{$m->[2]}) {
					unless (exists $row->{$md_list->{$m->[2]}}) {
						$row->{$md_list->{$m->[2]}} = $mddb->unencode_value($m->[2], $m->[1]);
					} else {
						$row->{$md_list->{$m->[2]}} .= ", ".$mddb->unencode_value($m->[2], $m->[1]);
					}
				}
			}
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


sub in_projects{
  my ($self , $public ) = @_;
  
  unless(defined $public and $public =~/1|0/){
    $public = 1 ;
  }
  
  my $dbh = $self->_master()->db_handle();
  
  my $statement = "select metagenome_id , name , sequence_type , file_size_raw , public , viewable from Job where Job.public = $public and exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id )";
  my $sth = $dbh->prepare($statement);
  $sth->execute;
  my $data = $sth->fetchall_arrayref();
  return $data ;
}

sub without_project{
  my ($self , $public ) = @_;

  unless(defined $public and $public =~/1|0/){
    $public = 1 ;
  }

  my $dbh = $self->_master()->db_handle();

  my $statement = "select metagenome_id , name , sequence_type , file_size_raw , public , viewable from Job where Job.public = $public and not exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id )";
  my $sth = $dbh->prepare($statement);
  $sth->execute;
  my $data = $sth->fetchall_arrayref();
  return $data ;
}



sub count_total_sequences {
  my ($self) = @_;
  my $dbh = $self->_master()->db_handle();
  my $sth = $dbh->prepare("select sum(value) from JobStatistics where tag = 'sequence_count_raw'");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();
  return ( $result->[0] ) ;
}

sub count_all {
 my ($self , $user) = @_;
 
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(_id) from Job where job_id is not null");
 $sth = $dbh->prepare("SELECT count(_id) FROM Job where owner=".$user->_id." and job_id is not null") if ($user and ref $user);
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] ) ;
}

sub count_public {
 my ($self) = @_;
 my $dbh = $self->_master()->db_handle();
 my $sth = $dbh->prepare("SELECT count(*) FROM Job where public and viewable");
 $sth->execute;
 my $result = $sth->fetchrow_arrayref();
 return ( $result->[0] ) ;
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
  my $webapp_dbm = DBMaster->new(-database => $Global_Config::webapplication_db,
                                 -backend => $Global_Config::webapplication_backend,
                                 -host => $Global_Config::webapplication_host,
                                 -user => $Global_Config::webapplication_user,
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

  # delete all metadata
  my $metadataentries = $dbm->MetaDataEntry->get_objects( { job => $self } );

  foreach my $metadataentry (@$metadataentries) {
    $metadataentry->delete();
  }

  # delete all jobgroup references
  my $jobgroupjobs = $dbm->JobgroupJob->get_objects( { job => $self } );

  foreach my $jobgroupjob (@$jobgroupjobs) {
    $jobgroupjob->delete();
  }

  # delete all metadata collections
  my $metadatacollections = $dbm->MetaDataCollection->get_objects( { job => $self } );

  foreach my $metadatacollection (@$metadatacollections) {
    $metadatacollection->delete();
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
