package MGRAST_jobcache::Job;

use strict;
use Data::Dumper;

use FIG_Config;
use DirHandle;
use File::Basename;
use IO::File;
use Fcntl ':flock';

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
	return undef;
  }

  # check if the user has the right to see this job
  unless ($job->public) {
    my $user = $job->_master->{_user};
    unless ($user->has_right(undef, 'view', 'metagenome', $job->genome_id)) {
      return undef;
    }
 }
  
  return $job;
}

sub reserve_job {
  my ($self, $master, $user) = @_;
  
  unless (ref($master)) {
    die "reserve_job called without a dbmaster reference";
  }

  unless (ref($user)) {
    die "reserve_job called without a user";
  }

  my $dbh = $master->db_handle;
  my $sth = $dbh->prepare("SELECT max(id), max(genome_id) FROM Job");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();

  my $job_id = $result->[0];
  my $genome_id = $result->[1];
  $job_id++;
  $genome_id += 1;

  my $jobsdir = $FIG_Config::mgrast_jobs;
  while (-d $jobsdir.'/'.$job_id) {
    $job_id++;
  }
  my $jobdir = $jobsdir.'/'.$job_id;  
  mkdir $jobdir;
  
  my $job = $master->Job->create( { owner => $user, id => $job_id, genome_id => $genome_id } );

  my $dbm = DBMaster->new(-database => $FIG_Config::webapplication_db,
			  -backend => $FIG_Config::webapplication_backend,
			  -host => $FIG_Config::webapplication_host,
			  -user => $FIG_Config::webapplication_user,
			 );
     
  # check rights
  my $rights = [ 'view', 'edit', 'delete' ];
  foreach my $right_name (@$rights) {
    unless(scalar(@{$dbm->Rights->get_objects({ scope       => $user->get_user_scope,
												data_type   => 'metagenome',
												data_id     => $genome_id,
												name        => $right_name,
												granted     => 1,
											  }) })
		  ) {
      my $right = $dbm->Rights->create({ scope       => $user->get_user_scope,
										 data_type   => 'metagenome',
										 data_id     => $genome_id,
										 name        => $right_name,
										 granted     => 1,
									   });
      unless (ref $right) {
		die "Unable to create Right $right_name - metagenome - $genome_id.";
      }
    }
  } 
  return $job;
}

=pod 

=item * B<directory> ()

Returns the full path the job directory (without a trailing slash).

=cut

sub directory {
  return $FIG_Config::mgrast_jobs.'/'.$_[0]->id;
}

=pod 

=item * B<download_dir> ()

Returns the full path the download directory inside the job (without a trailing slash).

=cut

sub download_dir {
  return $_[0]->directory.'/download';
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

=item * B<project> ()

Returns the name of the project

=cut

sub project {
  return;
}

=pod

=item * B<get_jobs_for_user> (I<user>, I<right>, I<viewable>)

Returns the Jobs objects the user I<user> has access to. Access to a job is defined
by the right to edit a genome of a certain genome_id. In the context of the RAST
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
    if ($j->genome_id){
      if (defined $ids{$j->genome_id}){
	delete $ids{$j->genome_id};
      }
    }
  }

  foreach (keys %ids){
    my $tmp_j;
    if($_){
      $tmp_j = $self->_master->Job->init({ genome_id => $_ });
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
    
    unless (ref $user_or_scope and 
	    ( $user_or_scope->isa("WebServerBackend::User") or
	     $user_or_scope->isa("WebServerBackend::Scope"))
	   ) {
	print STDERR "No user or scope given in method get_jobs_for_user.\n";
	die "No user or scope given in method get_jobs_for_user.\n";
    }
    
    my $right_to = $user_or_scope->has_right_to(undef, $right || 'edit', 'metagenome');
    # print Dumper($right_to);

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
	$job_cond .= " AND genome_id IN ( " . join(", ", map { "'$_'" } @g) . ")";
    }
    

    my $dbh = $self->_master()->db_handle();

    my $res = $dbh->selectall_arrayref(qq(SELECT j.id, j.type, j.genome_id, j.genome_name, j.project_name,
					  	j.genome_bp_count, j.size, j.genome_contig_count, j.server_version,
					  	j.last_modified, j.created_on, j.owner, j._owner_db, j.viewable,
					  	s.stage, s.status, j._id
					  FROM Job j JOIN Status s ON s.job = j._id
					  WHERE $job_cond
					  ORDER BY j.id DESC));
    my $ent = shift(@$res);
    my @out;
    while ($ent)
    {
	my($cur, $cur_type, $cur_genome, $cur_name, $cur_proj, $cur_bp_count, $cur_size, $cur_contig_count, $cur_server_version, $cur_last_mod, $cur_created, $cur_owner, $cur_owner_db, $jviewable, undef, undef, $jid) = @$ent;
	my $stages = {};

	while ($ent and $ent->[0] eq $cur)
	{
	    my($id, $type, $genome, $name, $proj, $bp, $size, $contig, $vers, $last_mod, $created, $owner, $owner_db, $view, $stage, $stat) = @$ent;

	    $stages->{$stage} = $stat;
	    $ent = shift(@$res);
	}
	push(@out, {
		    id => $cur,
		    type => $cur_type,
		    genome_id => $cur_genome,
		    genome_name => $cur_name,
		    project_name => $cur_proj,
		    last_modified => $cur_last_mod,
		    created_on => $cur_created,
		    status => $stages,
		    owner => $cur_owner,
		    owner_db => $cur_owner_db,
		    bp_count => $cur_bp_count,
		    size => $cur_size,
		    contig_count => $cur_contig_count,
		    server_version => $cur_server_version,
		    viewable => $jviewable,
		    _id => $jid
	});
    }
    return @out;
}

=pod

=item * B<delete> ()

Need to rewrite

=cut

sub delete {
  return;
}

1;
