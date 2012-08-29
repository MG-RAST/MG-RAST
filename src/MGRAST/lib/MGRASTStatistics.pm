package MGRAST::MGSTATS;

use strict;
use warnings;
use Data::Dumper;

use Conf;
use DBI;

1;

# in command line scripts invoke using:
# use WebApplicationDBHandle;
# my ($dbmaster, $error) = WebApplicationDBHandle->new();
# fail if error found

sub new {
  my($class, $job_dbh, $user_dbh) = @_;

  unless ( $job_dbh && ref($job_dbh) )
  {
      eval {
	  $job_dbh = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobDB',
				    -host     => $Conf::mgrast_jobcache_host,
				    -user     => $Conf::mgrast_jobcache_user,
				    -password => $Conf::mgrast_jobcache_password || "");
      };
      
      if ($@) {
	  warn "Unable to connect to MGRAST jobcache database: $@\n";
	  $job_dbh = undef;
      }
  }

  unless ( $user_dbh && ref($user_dbh) )
  {
      eval {
	  $user_dbh = DBMaster->new( -database => $Conf::webapplication_db || 'WebAppBackend',
				     -host     => $Conf::webapplication_host,
				     -user     => $Conf::webapplication_user,
				     -password => $Conf::webapplication_password || "");
      };
      
      if ($@) {
	  warn "Unable to connect to MGRAST jobcache database: $@\n";
	  $user_dbh = undef;
      }
  }

  my $self = { 
               job_dbh  => $job_dbh,
	       user_dbh => $user_dbh,
	     };

  bless ($self, $class);
  return $self;
}

sub job_dbh {
    my ($self) = @_;
    return $self->{job_dbh};
}

sub user_dbh {
    my ($self) = @_;
    return $self->{user_dbh};
}

sub user {
    my($self, $_id) = @_;

    # collect all user information

    if ( not exists $self->{user} )
    {
	my $dbh   = $self->user_dbh->db_handle();
	my $sql   = "SELECT _id,firstname,lastname,login,email,entry_date FROM User";
	$self->{user} = $dbh->selectall_hashref($sql, '_id');
    
	foreach my $_id_user ( keys %{ $self->{user} } )
	{
	    $self->{user}{$_id_user}{organization}   = $self->user2organization($_id_user);
	    $self->{user}{$_id_user}{funding_source} = $self->user2funding_source($_id_user);
	    $self->{user}{$_id_user}{job}            = $self->user2job($_id_user);

	    my $session = $self->user2session($_id_user);
	    $self->{user}{$_id_user}{last_page}           = $session->{current_page} || '';
	    $self->{user}{$_id_user}{last_page_date}      = $session->{date}         || '';
	    $self->{user}{$_id_user}{last_page_timestamp} = $session->{timestamp}    || '';
	}
    }

    if ( defined $_id )
    {
	return (exists $self->{user}{$_id})? $self->{user}{$_id} : {};
    }
    else
    {
	return $self->{user};
    }
}

sub job {
    my($self, $_id) = @_;

    # collect all job information

    if ( not exists $self->{job} )
    {
	my $dbh = $self->job_dbh->db_handle();

	my $sql = "SELECT _id,owner,viewable,job_id,primary_project,current_stage,server_version,name,metagenome_id,created_on,public,sample,sequence_type FROM Job WHERE job_id IS NOT NULL";
	$self->{job} = $dbh->selectall_hashref($sql, '_id');

	foreach my $_id_job ( keys %{ $self->{job} } )
	{
	    my $_id_user = $self->{job}{$_id_job}{owner};
	    $self->{job}{$_id_job}{organization}    = $self->user2organization($_id_user);
	    $self->{job}{$_id_job}{bp}              = $self->job_bp($_id_job);
	    $self->{job}{$_id_job}{done}            = $self->job_done($_id_job);
	    $self->{job}{$_id_job}{done_timestamp}  = $self->job_done_timestamp($_id_job);
	    $self->{job}{$_id_job}{deleted}         = $self->job_deleted($_id_job);
	    $self->{job}{$_id_job}{deleted_timestamp} = $self->job_deleted_timestamp($_id_job);
	    $self->{job}{$_id_job}{dead}            = $self->job_dead($_id_job);
	    $self->{job}{$_id_job}{dead_timestamp}  = $self->job_dead_timestamp($_id_job);
	    $self->{job}{$_id_job}{error}           = $self->job_error($_id_job);
	    $self->{job}{$_id_job}{error_timestamp} = $self->job_error_timestamp($_id_job);
	    $self->{job}{$_id_job}{pipeline_stage}  = $self->job2pipelinestage($_id_job);
	}
    }

    if ( defined $_id )
    {
	return (exists $self->{job}{$_id})? $self->{job}{$_id} : {};
    }
    else
    {
	return $self->{job};
    }
}

sub project {
    my($self, $_id) = @_;

    # collect project information

    if ( not exists $self->{project} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT _id,public,name,type,id FROM Project";
	$self->{project} = $dbh->selectall_hashref($sql, '_id');
    }

    if ( defined $_id )
    {
	return (exists $self->{project}{$_id})? $self->{project}{$_id} : {};
    }
    else
    {
	return $self->{project};
    }
}

sub organization {
    my($self, $_id) = @_;

    # collect all organization information

    if ( not exists $self->{organization} )
    {
	my $dbh = $self->user_dbh->db_handle();
	my $sql = "SELECT _id,name,country,abbreviation,location FROM Organization";
	$self->{organization} = $dbh->selectall_hashref($sql, '_id');

	foreach my $_id_organization ( keys %{ $self->{organization} } )
	{
	    $self->{organization}{$_id_organization}{user} = $self->organization2user($_id_organization);

	    foreach my $_id_user ( @{ $self->{organization}{$_id_organization}{user} } )
	    {
		push @{ $self->{organization}{$_id_organization}{job} }, @{ $self->user2job($_id_user) };
	    }
	}
    }

    if ( defined $_id )
    {
	return (exists $self->{organization}{$_id})? $self->{organization}{$_id} : {};
    }
    else
    {
	return $self->{organization};
    }
}

sub user_value {
    my($self, $_id, $key) = @_;

    # return the value for the key

    my $hash = $self->user($_id);
    return (exists $hash->{$key})? $hash->{$key} : 'not found';
}

sub job_value {
    my($self, $_id, $key) = @_;

    # return the value for the key

    my $hash = $self->job($_id);
    return (exists $hash->{$key})? $hash->{$key} : 'not found';
}

sub organization_value {
    my($self, $_id, $key) = @_;

    # return the value for the key

    my $hash = $self->organization($_id);
    return (exists $hash->{$key})? $hash->{$key} : 'not found';
}

sub organizationuser {
    my($self) = @_;

    # return a array reference with the organization _id and the user _id from the OrganizationUsers table

    if ( not exists $self->{organizationuser} )
    {
	my $dbh = $self->user_dbh->db_handle();
	my $sql = "SELECT organization,user FROM OrganizationUsers";
	$self->{organizationuser} = $dbh->selectall_arrayref($sql);
    }	

    return $self->{organizationuser};
}

sub user2organization {
    my($self, $_id) = @_;

    if ( not exists $self->{user2organization} )
    {
	my %hash;
	foreach my $rec ( @{ $self->organizationuser() } )
	{
	    my($organization,$user) = @$rec;
	    push @{ $hash{$user} }, $organization;
	}

	$self->{user2organization} = \%hash;
    }

    if ( defined $_id )
    {
	return $self->{user2organization}{$_id} || [];
    }
    else
    {
	return $self->{user2organization};
    }
}

sub organization2user {
    my($self, $_id) = @_;

    if ( not exists $self->{organization2user} )
    {
	my %hash;
	foreach my $rec ( @{ $self->organizationuser() } )
	{
	    my($organization,$user) = @$rec;
	    push @{ $hash{$organization} }, $user;
	}

	$self->{organization2user} = \%hash;
    }

    if ( defined $_id )
    {
	return $self->{organization2user}{$_id} || [];
    }
    else
    {
	return $self->{organization2user};
    }
}

sub user2session {
    my($self, $_id) = @_;

    # only registered users will be selected since 'user is not NULL' is specified

    if ( not exists $self->{user2session} )
    {
	my $dbh = $self->user_dbh->db_handle();
	my $sql = "SELECT substring(timestamp,1,10) AS date,timestamp,user,current_page FROM UserSession WHERE user IS NOT NULL";
	$self->{user2session} = $dbh->selectall_hashref($sql, 'user');
    }
    
    if ( defined ($_id) )
    {
	return $self->{user2session}{$_id} || {};
    }
    else
    {
	return $self->{user2session};
    }
}

sub active_users {
    my($self, $t1, $t2) = @_;

    my $session = $self->user2session();

    $t1 ||= $self->todays_date() . ' 00:00:00';
    $t2 ||= '';

    my @active_users = grep {($session->{$_}{timestamp} cmp $t1) >= 0} keys %$session;
    
    if ( $t2 )
    {
	@active_users = grep {($session->{$_}{timestamp} cmp $t2) <= 0} @active_users;
    }

    return \@active_users;
}

sub recent_user_page {
    my($self, $t1, $t2) = @_;

    $t1 ||= $self->todays_date() . ' 00:00:00';
    $t2 ||= '';

    if ( not exists $self->{recent_user_page}{$t1.$t2} ) 
    {
	my $dbh = $self->user_dbh->db_handle();
	my $sql = "SELECT user,current_page FROM UserSession WHERE timestamp > '$t1'";

	if ( $t2 )
	{
	    $sql .= " AND timestamp < '$t2'";
	}

	$self->{recent_user_page}{$t1.$t2} = $dbh->selectall_arrayref($sql);
    }
    
    return $self->{recent_user_page}{$t1.$t2};
}

sub number_of_recent_users {
    my($self, $t1, $t2) = @_;

    $t1 ||= $self->todays_date() . ' 00:00:00';
    $t2 ||= '';

    return scalar @{ $self->recent_user_page($t1,$t2) };
}

sub public_jobs {
    my($self) = @_;

    # return _id of public jobs which are viewable

    my $public = [];
    use Data::Dumper;

    if ( exists $self->{job} )
    {
	foreach my $_id_job ( keys %{ $self->{job} } )
	{
	    if ( ($self->{job}{$_id_job}{public} == 1) and ($self->{job}{$_id_job}{viewable} == 1) )
	    {
		push @$public, $_id_job;
	    }
	}
    }
    else
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT _id from Job where public=1 and viewable=1";
	$public = $dbh->selectcol_arrayref($sql)
    }

    return $public;
}

sub public_jobs_count {
    my($self) = @_;

    # return integer count of public jobs which are viewable

    return @{ $self->public_jobs() };
}

sub public_jobs_bp {
    my($self) = @_;

    # return bp count of public jobs which are viewable
    
    my $bp   = 0;
    my $jobs = $self->job();

    foreach my $_id_job ( @{ $self->public_jobs() } )
    {
	$bp += $jobs->{$_id_job}{bp};
    }

    return $bp;
}

sub jobs_created_today {
    my($self) = @_;

    if ( ! exists $self->{jobs_created_today} )
    {
	$self->{jobs_created_today} = [];

	my $today = $self->todays_date();
	my $jobs  = $self->job();
	
	foreach my $_id_job ( keys %$jobs )
	{
	    if ( $self->compare_dates($jobs->{$_id_job}{created_on},$today) eq 'after' )
	    {
		push @{ $self->{jobs_created_today} }, $_id_job;
	    }
	}
    }

    return $self->{jobs_created_today};
}

sub jobs_created_today_count {
    my($self) = @_;

    return scalar @{ $self->jobs_created_today() };
}

sub jobs_created_today_bp {
    my($self) = @_;

    my $jobs = $self->job();
    my $bp   = 0;

    foreach my $_id_job ( @{ $self->jobs_created_today() } )
    {
	$bp += $jobs->{$_id_job}{bp};
    }

    return $bp;
}

sub jobs_created_today_24h {
    my($self) = @_;

    # split jobs created today into 24 sets by creation time

    if ( ! exists $self->{jobs_created_today_24h} )
    {
	for (my $i=0; $i<24; $i++)
	{
	    $self->{jobs_created_today_24h}[$i] = [];
	}

	my $jobs = $self->job();

	foreach my $_id_job ( @{ $self->jobs_created_today() } )
	{
	    my($hour) = ($jobs->{$_id_job}{created_on} =~ /\d\s0{0,1}(\d{1,2})/);
	    push @{ $self->{jobs_created_today_24h}[$hour] }, $_id_job;
	}
    }

    return $self->{jobs_created_today_24h};
}

sub jobs_created_today_24h_count {
    my($self) = @_;
    
    if ( ! exists $self->{jobs_created_today_24h_count} )
    {
	$self->{jobs_created_today_24h_count} = [(0) x 24];

	my $jobs = $self->job();
	my $jobs_created_today_24h = $self->jobs_created_today_24h();
	
	for (my $i=0; $i<=23; $i++)
	{
	    $self->{jobs_created_today_24h_count}[$i] = scalar @{ $jobs_created_today_24h->[$i] };
	}
    }

    return $self->{jobs_created_today_24h_count};
}

sub jobs_created_today_24h_bp {
    my($self) = @_;
    
    if ( ! exists $self->{jobs_created_today_24h_bp} )
    {
	$self->{jobs_created_today_24h_bp} = [(0) x 24];
	
	my $jobs = $self->job();
	my $jobs_created_today_24h = $self->jobs_created_today_24h();
	
	for (my $i=0; $i<=23; $i++)
	{
	    foreach my $_id_job ( @{ $jobs_created_today_24h->[$i] } )
	    {
		$self->{jobs_created_today_24h_bp}[$i] += $jobs->{$_id_job}{bp};
	    }
	}
    }
	
    return $self->{jobs_created_today_24h_bp};
}

sub jobs_completed_today {
    my($self) = @_;

    if ( ! exists $self->{jobs_completed_today} )
    {
	$self->{jobs_completed_today} = [];

	my $today = $self->todays_date();
	my $jobs  = $self->job();
	
	foreach my $_id_job ( keys %$jobs )
	{
	    if ( $jobs->{$_id_job}{done} and ($self->compare_dates($jobs->{$_id_job}{done_timestamp},$today) eq 'after') )
	    {
		push @{ $self->{jobs_completed_today} }, $_id_job;
	    }
	}
    }

    return $self->{jobs_completed_today};
}

sub jobs_completed_today_count {
    my($self) = @_;

    return scalar @{ $self->jobs_completed_today() };
}

sub jobs_completed_today_bp {
    my($self) = @_;

    my $jobs = $self->job();
    my $bp   = 0;

    foreach my $_id_job ( @{ $self->jobs_completed_today() } )
    {
	$bp += $jobs->{$_id_job}{bp};
    }

    return $bp;
}

sub jobs_completed_today_24h {
    my($self) = @_;

    if ( ! exists $self->{jobs_completed_today_24h} )
    {
	for (my $i=0; $i<24; $i++)
	{
	    $self->{jobs_completed_today_24h}[$i] = [];
	}

	my $jobs = $self->job();

	foreach my $_id_job ( @{ $self->jobs_completed_today() } )
	{
	    my($hour) = ($jobs->{$_id_job}{done_timestamp} =~ /\d\s0{0,1}(\d{1,2})/);
	    push @{ $self->{jobs_completed_today_24h}[$hour] }, $_id_job;
	}
    }

    return $self->{jobs_completed_today_24h};
}

sub jobs_completed_today_24h_count {
    my($self) = @_;
    
    if ( ! exists $self->{jobs_completed_today_24h_count} )
    {
	$self->{jobs_completed_today_24h_count} = [(0) x 24];

	my $jobs = $self->job();
	my $jobs_completed_today_24h = $self->jobs_completed_today_24h();
	
	for (my $i=0; $i<=23; $i++)
	{
	    $self->{jobs_completed_today_24h_count}[$i] = scalar @{ $jobs_completed_today_24h->[$i] };
	}
    }

    return $self->{jobs_completed_today_24h_count};
}

sub jobs_completed_today_24h_bp {
    my($self) = @_;
    
    if ( ! exists $self->{jobs_completed_today_24h_bp} )
    {
	$self->{jobs_completed_today_24h_bp} = [(0) x 24];
	
	my $jobs = $self->job();
	my $jobs_completed_today_24h = $self->jobs_completed_today_24h();
	
	for (my $i=0; $i<=23; $i++)
	{
	    foreach my $_id_job ( @{ $jobs_completed_today_24h->[$i] } )
	    {
		$self->{jobs_completed_today_24h_bp}[$i] += $jobs->{$_id_job}{bp};
	    }
	}
    }
	
    return $self->{jobs_completed_today_24h_bp};
}

sub job_directory_size {
    my($self, $job_id) = @_;

    # note that job_id is used here, not _id from JobDB.Job table

    my $du = `du -sb $Conf::mgrast_jobs/$job_id/`;

    if ( $du =~ /^(\d+)/ )
    {
	return $1;
    }
    else
    {
	return 'directory not found';
    }
}

sub todays_date {
    my($self) = @_;

    my($mday,$mon,$year) = (localtime)[3,4,5];
    $year += 1900;
    $mon++;
    $mon  = sprintf("%02d", $mon);
    $mday = sprintf("%02d", $mday);
    
    return "$year-$mon-$mday";
}

sub pipeline_stages {
    my($self) = @_;

    if ( not exists $self->{pipeline_stages} )
    {
	my $dbh = $self->job_dbh->db_handle();
	
	my $sql = "SELECT DISTINCT stage FROM PipelineStage";
	$self->{pipeline_stages} = $dbh->selectcol_arrayref($sql);
    }

    return $self->{pipeline_stages};
}

sub pipeline_stages_ordered {
    my($self) = @_;

    return [
	    'qc',
	    'upload',
	    'preprocess',
	    'dereplication',
	    'screen',
	    'genecalling',
	    'usearch',
	    'cluster_rna97',
	    'rna',
	    'cluster_aa90',
	    'loadAWE',
	    'sims',
	    'loadDB',
	    'done',
	    'unknown',
	    ];
}

sub pipeline_jobs_count {
    my($self) = @_;

    my %hash;
    foreach my $stage ( @{ $self->pipeline_stages() } )
    {
	foreach my $status ( 'completed', 'running', 'error' )
	{
	    $hash{$stage}{$status}{count} = 0;
	    $hash{$stage}{$status}{bp}    = 0;
	}
    }

    my $jobs = $self->job();

     foreach my $_id_job ( keys %$jobs )
     {
	 my($stage, $timestamp, $status) = @{ $self->job2lastpipelinestage($_id_job) };
	 
	 # some jobs do not have entries in the PipelineStage table
	 if ( $stage )
	 {
	     if ( $stage eq 'done' and $status eq 'completed' )
	     {
		 # job is done, include deleted jobs in count
		 $hash{$stage}{$status}{count}++;
		 $hash{$stage}{$status}{bp} += $jobs->{$_id_job}{bp};
	     }
	     else
	     {
		 if ( (! $jobs->{$_id_job}{deleted}) and (! $jobs->{$_id_job}{dead}) )
		 {
		     # job processing incomplete,
		     # include only jobs which have not been deleted and are not dead
		     $hash{$stage}{$status}{count}++;
		     $hash{$stage}{$status}{bp} += $jobs->{$_id_job}{bp};
		 }
	     }
	 }
     }

     return \%hash;
}

sub compare_dates {
    my($self, $t1, $t2) = @_;

    my $cmp = $t1 cmp $t2;
    if ( $cmp == -1 )
    {
	# $t1 before $t2
        return 'before';
    }
    elsif ( $cmp == 1 )
    {
	# $t1 after $t2
        return 'after';
    }
    else
    {
        return 'equal';
    }
}

sub dates_overlap {
    my($self, $t1, $t2, $t3, $t4) = @_;

    if ( ($self->compare_dates($t2,$t3) eq 'before') or ($self->compare_dates($t4,$t1) eq 'before') )
    {
	return 0;
    }
    else
    {
	return 1;
    }
}

sub job2user {
    my($self, $_id) = @_;

    if ( not exists $self->{job2user} )
    {
	my %hash = ();
	my $job  = $self->job();
	foreach my $_id_job ( keys %$job )
	{
	    $hash{$_id_job} = $job->{$_id_job}{owner};
	}

	$self->{job2user} = \%hash;
    }

    if ( defined $_id )
    {
	return (exists $self->{job2user}{$_id})? $self->{job2user}{$_id} : '';
    }
    else
    {
	return $self->{job2user};
    }
}


sub user2job {
    my($self, $_id) = @_;

    if ( not exists $self->{user2job} )
    {
	my %hash = ();
	my $job  = $self->job();
	foreach my $_id_job ( keys %$job )
	{
	    my $_id_owner = $job->{$_id_job}{owner};
	    push @{ $hash{$_id_owner} }, $_id_job;
	}

	$self->{user2job} = \%hash;
    }

    if ( defined $_id )
    {
	return (exists $self->{user2job}{$_id})? $self->{user2job}{$_id} : [];
    }
    else
    {
	return $self->{user2job};
    }
}

sub job_bp {
    my($self, $_id) = @_;

    if ( not exists $self->{job_bp} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT job,value FROM JobStatistics WHERE tag='bp_count_raw'";

	foreach my $rec ( @{ $dbh->selectall_arrayref($sql) } )
	{
	    my($j,$bp) = @$rec;
	    $self->{job_bp}{$j} = $bp;
	}
    }

    if ( defined $_id )
    {
	return (exists $self->{job_bp}{$_id})? $self->{job_bp}{$_id} : 0;
    }
    else
    {
	return $self->{job_bp};
    }
}

sub job_deleted_all {
    my($self) = @_;

    if ( not exists $self->{job_deleted_all} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT job,timestamp FROM JobAttributes WHERE tag='deleted'";
	foreach my $rec ( @{ $dbh->selectall_arrayref($sql) } )
	{
	    my($j, $t) = @$rec;
	    $self->{job_deleted_all}{$j} = $t;
	}
    }

    return $self->{job_deleted_all};
}

sub job_deleted {
    my($self, $_id) = @_;

    my $job_deleted_all = $self->job_deleted_all();

    if ( exists $job_deleted_all->{$_id} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub job_deleted_timestamp {
    my($self, $_id) = @_;

    my $job_deleted_all = $self->job_deleted_all();

    if ( exists $job_deleted_all->{$_id} )
    {
	return $job_deleted_all->{$_id};
    }
    else
    {
	return '';
    }
}

sub job_dead_all {
    my($self) = @_;

    if ( not exists $self->{job_dead_all} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT job,timestamp FROM JobAttributes WHERE tag='no_sims_found'";
	foreach my $rec ( @{ $dbh->selectall_arrayref($sql) } )
	{
	    my($j, $t) = @$rec;
	    $self->{job_dead_all}{$j} = $t;
	}
    }

    return $self->{job_dead_all};
}

sub job_dead {
    my($self, $_id) = @_;

    my $job_dead_all = $self->job_dead_all();

    if ( exists $job_dead_all->{$_id} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub job_dead_timestamp {
    my($self, $_id) = @_;

    my $job_dead_all = $self->job_dead_all();

    if ( exists $job_dead_all->{$_id} )
    {
	return $job_dead_all->{$_id};
    }
    else
    {
	return '';
    }
}

sub job_done {
    my($self, $_id) = @_;

    foreach my $stage ( @{ $self->job2pipelinestage($_id) } )
    {
	if ( $stage->[0] eq 'done' and $stage->[2] eq 'completed' )
	{
	    return 1;
	}
    }

    return 0;
}

sub job_done_timestamp {
    my($self, $_id) = @_;

    foreach my $stage ( @{ $self->job2pipelinestage($_id) } )
    {
	if ( $stage->[0] eq 'done' and $stage->[2] eq 'completed' )
	{
	    return $stage->[1];
	}
    }

    return '';
}

sub job_error {
    my($self, $_id) = @_;
    
    my $last_stage = $self->job2lastpipelinestage($_id);
    if ( @$last_stage == 3 and $last_stage->[2] eq 'error' )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub job_error_timestamp {
    my($self, $_id) = @_;
    
    my $last_stage = $self->job2lastpipelinestage($_id);
    if ( @$last_stage == 3 and $last_stage->[2] eq 'error' )
    {
	return $last_stage->[1];
    }
    else
    {
	return '';
    }
}

sub job_error_stagename {
    my($self, $_id) = @_;
    
    my $last_stage = $self->job2lastpipelinestage($_id);
    if ( @$last_stage == 3 and $last_stage->[2] eq 'error' )
    {
	return $last_stage->[0];
    }
    else
    {
	return '';
    }
}

sub job_count {
    my($self) = @_;
    
    my $sql   = "SELECT substring(created_on,1,7) AS Date, count(job_id) AS Jobs FROM Job WHERE job_id IS NOT NULL GROUP BY Date";
    my $count = $self->job_dbh->selectall_arrayref($sql);
    return $count;
}

sub pipelinestage {
    my($self) = @_;

    if ( not exists $self->{pipelinestage} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT stage,timestamp,status,job FROM PipelineStage WHERE job IS NOT NULL ORDER BY timestamp ASC";
	$self->{pipelinestage} = $dbh->selectall_arrayref($sql);
    }
    
    return $self->{pipelinestage};    
}

sub job2pipelinestage {
    my($self, $_id) = @_;

    if ( not exists $self->{job2pipelinestage} )
    {
	my %hash;
	foreach my $stage ( @{ $self->pipelinestage() } )
	{
	    my($name, $timestamp, $status, $job) = @$stage;
	    push @{ $hash{$job} }, [$name, $timestamp, $status];
	}

	$self->{job2pipelinestage} = \%hash;
    }

    if ( defined $_id )
    {
	return (exists $self->{job2pipelinestage}{$_id})? $self->{job2pipelinestage}{$_id} : [];
    }
    else
    {
	return $self->{job2pipelinestage};
    }
}

sub jobstage {
    my($self, $_id, $stage_name) = @_;

    my $stages = $self->job2pipelinestage($_id);
    
    foreach my $stage ( @$stages )
    {
	my($name, $timestamp, $status) = @$stage;
	if ( $name eq $stage_name )
	{
	    return $stage;
	}
    }

    return [];
}


sub job2lastpipelinestage {
    my($self, $_id) = @_;

    my $done = $self->jobstage($_id, 'done');

    if ( @$done )
    {
	return $done;
    }
    else
    {
	my $stages = $self->job2pipelinestage($_id);
	return $stages->[-1] || [];
    }
}

sub projectjob {
    my($self) = @_;

    # ProjectJob table gives mapping: project <--> job

    if ( not exists $self->{projectjob} )
    {
	my $dbh = $self->job_dbh->db_handle();
	my $sql = "SELECT project,job FROM ProjectJob";
	$self->{projectjob} = $dbh->selectall_arrayref($sql);
    }
    
    return $self->{projectjob};    
}

sub job2project {
    my($self, $_id) = @_;

    if ( not exists $self->{job2project} )
    {
	my %hash;
	foreach my $rec ( @{ $self->projectjob() } )
	{
	    my($_id_project, $_id_job) = @$rec;
	    push @{ $hash{$_id_job} }, $_id_project;
	}

	$self->{job2project} = \%hash;
    }

    if ( defined $_id )
    {
	return (exists $self->{job2project}{$_id})? $self->{job2project}{$_id} : [];
    }
    else
    {
	return $self->{job2project};
    }
}

sub user_funding_source {
    my($self) = @_;

    if ( not exists $self->{user_funding_source} )
    {
	my $dbh = $self->user_dbh->db_handle();
	my $sql = "SELECT value,user FROM Preferences WHERE name='funding_source'";
	$self->{user_funding_source} = $dbh->selectall_arrayref($sql);
    }
    
    return $self->{user_funding_source};
}

sub user2funding_source {
    my($self, $_id) = @_;

    if ( not exists $self->{user2funding_source} )
    {
	my %hash;
	foreach my $rec ( @{ $self->user_funding_source() } )
	{
	    my($fs, $u) = @$rec;
	    $hash{$u}   = $fs;
	}

	$self->{user2funding_source} = \%hash;
    }
    
    if ( defined $_id )
    {
	return $self->{user2funding_source}{$_id} || '';
    }
    else
    {
	return $self->{user2funding_source};
    }
}

sub funding_source2user {
    my($self) = @_;

    if ( not exists $self->{funding_source2user} )
    {
	my %hash;
	foreach my $rec ( @{ $self->user_funding_source() } )
	{
	    my($fs, $u) = @$rec;
	    push @{ $hash{$fs} }, $u;
	}

	$self->{funding_source2user} = \%hash;
    }

    return $self->{funding_source2user};
}

sub funding_source2user_count {
    my($self) = @_;

    if ( not exists $self->{funding_source2user_count} )
    {
	my %hash;
	foreach my $rec ( @{ $self->user_funding_source() } )
	{
	    my($fs, $u) = @$rec;
	    $hash{$fs}++;
	}

	$self->{funding_source2user_count} = \%hash;
    }

    return $self->{funding_source2user_count};
}

sub get_funding_users {
    my($self) = @_;

    my $funding_users = $self->user_dbh->selectall_arrayref("SELECT value,count(*) FROM Preferences WHERE name='funding_source' GROUP BY value");
    return $funding_users;
}

sub get_funding_source {
    my($self) = @_;

    my $sql = "SELECT value,count(*) FROM Preferences WHERE name='funding_source' GROUP BY value";
    my $funding_source = $self->user_dbh->selectall_arrayref($sql);
    return $funding_source;
}

sub email2fundingsource {
    my($self) = @_;

    if ( not exists $self->{email2fundingsource} )
    {
	$self->{email2fundingsource} = {
	                                 "cdc.gov"     => "CDC" ,
					 "dhec.sc.gov" => "DHEC",
					 "anl.gov"     => "DOE" ,
					 "lnl.gov"     => "DOE" ,
					 "lanl.gov"    => "DOE" ,
					 "lbl.gov"     => "DOE" ,
					 "nrel.gov"    => "DOE" ,
					 "ornl.gov"    => "DOE" ,
					 "pnl.gov"     => "DOE" ,
					 "sandia.gov"  => "DOE" ,
					 "doe.gov"     => "DOE" ,
					 "epa.gov"     => "EPA" ,
					 "fda.hhs.gov" => "FDA" ,
					 "nih.gov"     => "NIH" ,
					 "noaa.gov"    => "NOAA",
					 "usda.gov"    => "USDA",
					 "usgs.gov"    => "USGS",
					 "va.gov"      => "VA",
					 };
    }

    return $self->{email2fundingsource};
}

sub get_funding_user_jobs {
    my($self) = @_;

    my $users = $self->user();
    my $jobs  = $self->job();

    my $fuj = {};
    my $fs2user = $self->funding_source2user();

    foreach my $_id_user ( keys %$users )
    {
	my $fs = $users->{$_id_user}{funding_source};

	if ( ! $fs )
	{
	    # funding source not found in database, try and deduce funding from email address
	    while ( my ($ext, $code) = each %{ $self->email2fundingsource() } ) 
	    {
		if ( $users->{$_id_user}{email} =~ /$ext$/ ) 
		{
		    $fs = $code;
		    last;
		}
	    }

	    $fs = $fs? uc $fs : 'UNKNOWN';
	    push @{ $fs2user->{$fs} }, $_id_user;
	}
    }
	
    foreach my $fs ( sort keys %$fs2user )
    {
	foreach my $_id_user ( @{ $fs2user->{$fs} } )
	{
	    $fuj->{$fs}{users}++;

	    foreach my $_id_job ( @{ $users->{$_id_user}{job} } )
	    {
		if ( $jobs->{$_id_job}{done} )
		{
		    # count all completed jobs, including ones which were deleted after completion
		    $fuj->{$fs}{jobs}++;
		    $fuj->{$fs}{bp_count_raw} += $jobs->{$_id_job}{bp};
		}
	    }
	}

	$fuj->{$fs}{users}        ||= 0;
	$fuj->{$fs}{jobs}         ||= 0;
	$fuj->{$fs}{bp_count_raw} ||= 0;
    }

    my @res = map { [ $_, $fuj->{$_}{users}, 
		          $fuj->{$_}{jobs}, 
		          $fuj->{$_}{bp_count_raw} ] } map {$_->[0]} sort {$a->[1] cmp $b->[1]} map {[$_, uc($_)]} keys %$fuj;

    return \@res;
}

sub get_funding_user_jobs_old {
    my($self) = @_;
    
    my $users = $self->user();
    my $orgs  = $self->organization();
    my $jobs  = $self->job();

    my $fuj   = {};

    foreach my $_id_user ( keys %$users )
    {
	my $fund = $users->{$_id_user}{funding_source};

	if ( ! $fund )
	{
	    # funding source not found in database, try and deduce funding from email address
	    while ( my ($ext, $code) = each %{ $self->email2fundingsource() } ) 
	    {
		if ( $users->{$_id_user}{email} =~ /$ext$/ ) 
		{
		    $fund = $code;
		    last;
		}
	    }
	}

	$fund = $fund? uc $fund : 'UNKNOWN';

	$fuj->{$fund}{users}++;
	
	foreach my $_id_job ( @{ $users->{$_id_user}{job} } )
	{
	    if ( $jobs->{$_id_job}{done} )
	    {
		# count all completed jobs, including ones which were deleted after completion
		$fuj->{$fund}{jobs}++;
		$fuj->{$fund}{bp_count_raw} += $jobs->{$_id_job}{bp};
	    }
	}
    }

    my @res = map { [ $_, $fuj->{$_}{users}, 
		          $fuj->{$_}{jobs}, 
		          $fuj->{$_}{bp_count_raw} ] } sort keys %$fuj;

    return \@res;
}

sub get_funding_user_jobs_older {
    my ($self, $mapping) = @_;
    
    # REWRITE USING $self->job(), $self->user(), etc.

    my $lf = {};
    my $job_data  = $self->job_dbh->selectall_arrayref("select owner, _id from Job where owner is not NULL");
    my $user_data = $self->user_dbh->selectall_arrayref("select _id, email from User");
    my $fund_data = $self->user_dbh->selectall_arrayref("select user, value from Preferences where name = 'funding_source'");
    my $stat_data = $self->job_dbh->selectall_arrayref("select job, value from JobStatistics where tag = 'bp_count_raw' and value is not NULL and value > 0");
    unless ($user_data && $fund_data && $job_data) { return $lf; }

    my %user_jobs  = ();
    my %user_email = map { $_->[0], $_->[1] } @$user_data;
    my %user_fund  = map { $_->[0], uc($_->[1]) } @$fund_data;
    my %job_stats  = ($stat_data && (@$stat_data > 0)) ? map { $_->[0], $_->[1] } @$stat_data : ();

    map { push @{ $user_jobs{$_->[0]} }, $_->[1] } @$job_data;

    foreach my $user (keys %user_email) {
      if (($user == 122) || ($user == 7232)) { next; }  # skip Wilke

      my $fund = exists($user_fund{$user}) ? $user_fund{$user} : '';
      my $jobs = exists($user_jobs{$user}) ? $user_jobs{$user} : [];
      my $bps  = 0;
      map { $bps += $job_stats{$_} } grep { exists $job_stats{$_} } @$jobs;
      
      my $has_fund = 0;
      if ($fund) {
	$lf->{$fund}{users}++;
	$lf->{$fund}{jobs} += scalar(@$jobs);
	$lf->{$fund}{bp_count_raw} += $bps;
	$has_fund = 1;
      }
      else {
	while ( my ($ext, $code) = each %$mapping ) {
	  if ( $user_email{$user} =~ /$ext$/ ) {
	    $lf->{$code}{users}++;
	    $lf->{$code}{jobs} += scalar(@$jobs);
	    $lf->{$code}{bp_count_raw} += $bps;
	    $has_fund = 1;
	  }
	}
      }
    }
    
    my @res = map { [ $_, $lf->{$_}{users}, $lf->{$_}{jobs}, $lf->{$_}{bp_count_raw} ] } sort keys %$lf;
    return \@res;
}


