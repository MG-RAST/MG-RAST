package MGRAST::WebPage::MGRASTAdmin;

use base qw( WebPage );

use strict;
use warnings;

use Data::Dumper;
use WebComponent::WebGD;

use WebConfig;
use Conf;

use MGRAST::Analysis;
use MGRAST::Metadata;
use MGRAST::MGRASTStatistics;

1;

=pod

=head1 NAME

Admin - an instance of WebPage which shows users, jobs and status info

=head1 DESCRIPTION

Displays users, jobs and status info

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  # get the display jobs options -- default is 'all_jobs' which will include 'deleted' and 'no_sims_found' jobs, display_jobs = active will skip these
  my $display_jobs = $self->application->cgi->param('display_jobs') || 'all_jobs';
  $self->data('display_jobs', $display_jobs);

  $self->title("System Statistics");

  $self->application->register_component('Table', 'user_table');
  $self->application->register_component('Table', 'ujobs_table');
  $self->application->register_component('Table', 'alljobs_table');
  $self->application->register_component('Table', 'month_jobs_table');
  $self->application->register_component('Table', 'today_jobs_table');
  $self->application->register_component('Table', 'today_jobs_table_2');
  $self->application->register_component('Table', 'incomplete_jobs_table');
  $self->application->register_component('Table', 'incomplete_jobs_table_2');
  $self->application->register_component('Table', 'pipeline_jobs_table');
  $self->application->register_component('Table', 'pipeline_jobs_table_2');
  $self->application->register_component('Table', 'today_users_table');
  $self->application->register_component('Table', 'organization_table');
  $self->application->register_component('Table', 'average_size_table');
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('Table', 'FundingSources');
  $self->application->register_component('Table', 'FundingSourcesClean');
  $self->application->register_component('Table', 'JobsMonthCompleted');
  $self->application->register_component('Table', 'JobsMonthSubmitted');

  my $email_mapping = {
		       "cdc.gov"     => "CDC" ,
		       "dhec.sc.gov" =>	"DHEC",
		       "anl.gov"     =>	"DOE" ,
		       "lnl.gov"     => "DOE" ,
		       "lanl.gov"    => "DOE" ,
		       "lbl.gov"     => "DOE" ,
		       "nrel.gov"    => "DOE" ,
		       "ornl.gov"    => "DOE" ,
		       "pnl.gov"     => "DOE" ,
		       "sandia.gov"  => "DOE" ,
		       "doe.gov"     =>	"DOE" ,
		       "epa.gov"     => "EPA" ,
		       "fda.hhs.gov" =>	"FDA" ,
		       "nih.gov"     =>	"NIH" ,
		       "noaa.gov"    =>	"NOAA",
		       "usda.gov"    =>	"USDA",
		       "usgs.gov"    =>	"USGS",
		       "va.gov"      =>	"VA"
		      };
  $self->data('mapping' , $email_mapping);

  my $mgstat = MGRAST::MGSTATS->new();
  unless ($mgstat) {
      $self->app->add_message('warning', "Unable to retrieve the metagenome statistics database.");
      return 1;
  }

  $self->{mgstat} = $mgstat;

  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the MetagenomeSelect page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $dbmaster    = $application->dbmaster;
  my $user        = $application->session->user;
  my $cgi         = $application->cgi;

  my $mgrast_dbh  = $self->application->data_handle('MGRAST')->db_handle;
  my $user_dbh    = $user->_master->db_handle;

  # check for MGRAST
  my $html = '<i>' . &formatted_date . '</i>';

  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
      $html .= "<h2>The MG-RAST is currently offline. You are the admin, fix it!</h2>";
      return $html;
  }
  $self->{mgrast} = $mgrast;

  $html .= $application->component('ajax')->output();

  # create array with strings for last thirtyone days
  my $thirtyone_days = [];
  for (my $i=30; $i>-1; $i--) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time-($i * 86400));
    $year += 1900;
    $mon++;
    $mon = sprintf("%02d", $mon);
    $mday = sprintf("%02d", $mday);
    push(@$thirtyone_days, "$year-$mon-$mday");
  }

  # 24 months
  my $tfmonths = {};
  my (undef,undef,undef,undef,$mon,$year) = localtime(time);
  $year += 1900;
  $mon++;
  for (my $i=0; $i<48; $i++) {
    my $ym = $year."-".sprintf("%02d", $mon);
    $tfmonths->{$ym} = 47 - $i;
    $mon--;
    if ($mon == 0) {
      $year--;
      $mon = 12;
    }
  }
  
  my $fourtyeightcols = [];
  my $rev_ym = {};
  %$rev_ym = reverse(%$tfmonths);
  for (my $i=0; $i<48; $i++) {
    push(@$fourtyeightcols, $rev_ym->{$i});
  }

  if ($cgi->param('exp')) {
    my $average_size_table = $application->component('average_size_table');
    my $ast_data = [ [ split /\|/, $cgi->param('exp') ] ];
    my $ast_cols = [];
    for (my $i=0; $i<48; $i++) {
      push(@$ast_cols, { visible => 0, name => $rev_ym->{$i} });
    }
    $average_size_table->data($ast_data);
    $average_size_table->columns($ast_cols);
    $average_size_table->export_excel();
  }

  my $mgusers    = $self->{mgstat}->user();
  my $mgorgs     = $self->{mgstat}->organization();
  my $mgjobs     = $self->{mgstat}->job();
  my $mgprojects = $self->{mgstat}->project();

  my $pipeline_job_ids = {};
  my $pipeline_jobs = $self->{mgstat}->pipeline_jobs_count();

  my $data = [];
  my $countries = {};
  my $current_countries = {};

  # current users
  my $today_users_registered = $self->{mgstat}->active_users($thirtyone_days->[30]. ' 00:00:00');
  
  my %page_count;
  foreach my $_id_user ( @$today_users_registered )
  {
      my $page = $mgusers->{$_id_user}{last_page} || 'Home';
      $page_count{$page}++;
  }

  my $data_page_count = [];
  @$data_page_count = map {[$_, $page_count{$_}]} keys %page_count;
  
  # count new users
  foreach my $_id_user (@$today_users_registered) {
      my $_id_org  = $mgusers->{$_id_user}{organization}[-1] || '';   # choose a single organization
      my $org      = $mgorgs->{$_id_org}{name} || '';
      my $country  = $mgorgs->{$_id_org}{country} || '';

      if ( $country eq 'UK' ) 
      {
	  $country = 'GB';
      }

      if ( $country )
      {
	  if ( exists($current_countries->{$country}) ) {
	      $current_countries->{$country}++;
	  } else {
	      $current_countries->{$country} = 1;
	  }
      }
  }

  my $new_users = {};
  foreach my $date ( @$thirtyone_days )
  {
      $new_users->{$date} = 0;
  }

  foreach my $_id_user ( sort {$a <=> $b} keys %$mgusers ) 
  {
      my $_id_org  = $mgusers->{$_id_user}{organization}[-1] || '';   # choose a single organization

      my $n_jobs = scalar @{ $mgusers->{$_id_user}{job} };

      my $bp = 0;
      foreach my $_id_job ( @{ $mgusers->{$_id_user}{job} } )
      {
	  $bp += $mgjobs->{$_id_job}{bp};
      }

      push @$data, [ 
		     $mgusers->{$_id_user}{firstname}, 
		     $mgusers->{$_id_user}{lastname}, 
		     $mgusers->{$_id_user}{login}, 
		     $mgusers->{$_id_user}{email}, 
		     $mgusers->{$_id_user}{entry_date}, 
		     $mgorgs->{$_id_org}{name},
		     $mgusers->{$_id_user}{funding_source},
		     $mgorgs->{$_id_org}{country},
		     $n_jobs,
		     $bp,
		     $mgusers->{$_id_user}{last_page_timestamp},
		     "<input type='button' onclick='execute_ajax(\"user_details\", \"user_details\", \"user=".$mgusers->{$_id_user}{login}."\");' value='details'>" 
		   ];
      
      my $org      = $mgorgs->{$_id_org}{name} || '';
      my $country  = $mgorgs->{$_id_org}{country} || '';
      
      if ( $country eq 'UK' ) 
      {
	  $country = 'GB';
      }
      
      if ($country) {
	  if (exists($countries->{$country})) {
	      $countries->{$country}++;
	  } else {
	      $countries->{$country} = 1;
	  }
      }
      
      # count new users
      for (my $i=0; $i<31; $i++) {
	  my $curr = $thirtyone_days->[$i];
	  if ($mgusers->{$_id_user}{entry_date} =~ /^$curr/) {
	      $new_users->{$curr}++;
	      last;
	  }
      }
  }

  my $ut = $application->component('user_table');
  $ut->show_top_browse(1);
  $ut->show_bottom_browse(1);
  $ut->show_clear_filter_button(1);
  $ut->show_select_items_per_page(1);
  $ut->items_per_page(15);
  $ut->data($data);
  $ut->show_column_select(1);
  $ut->columns( [ { name => 'firstname', filter => 1, sortable => 1 },
		  { name => 'lastname', filter => 1, sortable => 1 },
		  { name => 'login', filter => 1, sortable => 1 },
		  { name => 'email', filter => 1, sortable => 1 },
		  { name => 'date registered', filter => 1, sortable => 1 },
		  { name => 'organization', filter => 1, sortable => 1 },
		  { name => 'funding source', filter => 1, sortable => 1, visible => 0 },
		  { name => 'country', filter => 1, sortable => 1 },
		  { name => '# jobs', filter => 1, sortable => 1, operators => ['equal', 'less', 'more']}, # operator => 'more' },
		  { name => 'bp', filter => 1, sortable => 1, operators => ['equal', 'less', 'more']}, # operator => 'more' },
		  { name => 'last access', filter => 1, sortable => 1 },
		  { name => 'details', filter => 1, sortable => 1 }, ] );


#  return $ut->output();
  my @jobs = ();
  my $jobsizehash = {};
  my $deletedjobshash = {};
  my $deadjobshash = {};


  # jobs section
  my $finished = [];

#viz

  my $jdata = [];
  my $upload_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

  my $incomplete_job_id     = {};
  my $incomplete_jobs_bp    = {};
  my $incomplete_jobs_count = {};

  my $pipeline_job_id     = {};
  my $pipeline_jobs_bp    = {};
  my $pipeline_jobs_count = {};

  my $last_month_jobs_bp    = {};
  my $last_month_jobs_count = {};
  foreach my $date ( @$thirtyone_days )
  {
      foreach my $status ( 'error', 'done', 'deleted', 'running' )
      {
	  $last_month_jobs_bp->{$date}{$status}    = 0;
	  $last_month_jobs_count->{$date}{$status} = 0;
      }
  }
  
  my $today_job_id     = {};
  my $today_jobs_bp    = {};
  my $today_jobs_count = {};
  foreach my $hour ( 0..23 )
  {
      foreach my $status ( 'error', 'done', 'deleted', 'running' )
      {
	  $today_jobs_bp->{$hour}{$status}    = 0;
	  $today_jobs_count->{$hour}{$status} = 0;
      }
  }
  
  my $upload_stats_new = [];
  for (my $i=0; $i<31; $i++) 
  {
      my($curr) = ($thirtyone_days->[$i] =~ /^\d{4}-(.+)/);
      push @$upload_stats_new, [$curr, 0];
  }

  my $broken_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $finished_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $processing_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $average_size_stats = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];
  my $average_size_stats_filtered = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];
  my $average_size_stats_filtered2 = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];

  my $size_distribution = [[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0]];

  my $bp_today = 0;
  my $bp_week  = 0;
  my $bp_month = 0;

  my %job_date;

  foreach my $_id_job ( keys %$mgjobs ) 
  {
      if ( $self->data('display_jobs') eq 'active' )
      {
	  # skip dead and deleted jobs when the 'active' option is selected
	  if ( $mgjobs->{$_id_job}{dead} || $mgjobs->{$_id_job}{deleted} )
	  {
	      next;
	  }
      }

      my $_id_user = $mgjobs->{$_id_job}{owner};
      my $_id_org  = $mgjobs->{$_id_job}{organization}[-1] || '';

      my $last_stage = $self->{mgstat}->job2lastpipelinestage($_id_job);
      my($last_stage_name, $last_stage_timestamp, $last_stage_status) = @$last_stage;

      $last_stage_name      ||= '';
      $last_stage_timestamp ||= '';
      $last_stage_status    ||= '';
      
      my $name_text = '';
      if ( $last_stage_name eq 'done' and $last_stage_status eq 'completed' )
      {
          # link dataset name to overview page if job is completed
	  $name_text = qq(<a href='?page=MetagenomeOverview&metagenome=$mgjobs->{$_id_job}{metagenome_id}' target='_blank'>$mgjobs->{$_id_job}{name}</a>);
      }
      else
      {
	  $name_text = $mgjobs->{$_id_job}{name};
      }

      # link to project page(s)
      my $project_links = [];
      my $_id_projects  = $self->{mgstat}->job2project($_id_job);

      if ( @$_id_projects )
      {
	  foreach my $_id_project ( @$_id_projects )
	  {
	      my $id_project = $mgprojects->{$_id_project}{id};

	      # some weirdness in database Project table, need to check that $id_project is found
	      if ( $id_project )
	      {
		  push @$project_links, qq(<a href='?page=MetagenomeProject&project=$id_project' target='_blank'>$id_project</a>);
	      }
	  }
      }

      my $project_link = scalar @$project_links ? join(', ', @$project_links) : '';

      push @$jdata, [ 
		      $mgjobs->{$_id_job}{created_on}, 
		      $mgjobs->{$_id_job}{metagenome_id}, 
		      $mgjobs->{$_id_job}{job_id},
		      $name_text,
		      $mgjobs->{$_id_job}{bp}, 
		      $mgjobs->{$_id_job}{sequence_type}, 
		      $mgjobs->{$_id_job}{viewable},
		      $mgjobs->{$_id_job}{public},
		      $mgjobs->{$_id_job}{server_version}, 
		      $project_link,
		      $mgusers->{$_id_user}{firstname}, 
		      $mgusers->{$_id_user}{lastname}, 
		      $mgusers->{$_id_user}{login}, 
		      $mgusers->{$_id_user}{email},
		      $mgusers->{$_id_user}{funding_source},
		      $mgorgs->{$_id_org}{name} || '',
		      $mgorgs->{$_id_org}{country} || '',
		      $last_stage_name, 
		      $last_stage_status, 
		      $last_stage_timestamp, 
		      "<input type='button' value='status' onclick='execute_ajax(\"job_details\", \"job_details\", \"job=".$mgjobs->{$_id_job}{job_id}."\");'>",
		    ];

      my ($jyear_month) = $mgjobs->{$_id_job}{created_on} =~ /^(\d+\-\d+)/;
      if (exists($tfmonths->{$jyear_month})) {
	  if ($mgjobs->{$_id_job}{bp} > 5000000 && $mgjobs->{$_id_job}{bp} < 50000000) {
	      $average_size_stats_filtered->[$tfmonths->{$jyear_month}]->[0]++;
	      $average_size_stats_filtered->[$tfmonths->{$jyear_month}]->[1] += $mgjobs->{$_id_job}{bp};
	      $size_distribution->[$tfmonths->{$jyear_month}]->[1] += $mgjobs->{$_id_job}{bp};
	  } elsif ($mgjobs->{$_id_job}{bp} > 50000000) {
	      $average_size_stats_filtered2->[$tfmonths->{$jyear_month}]->[0]++;
	      $average_size_stats_filtered2->[$tfmonths->{$jyear_month}]->[1] += $mgjobs->{$_id_job}{bp};
	      $size_distribution->[$tfmonths->{$jyear_month}]->[2] += $mgjobs->{$_id_job}{bp};
	  } else {
	      $average_size_stats->[$tfmonths->{$jyear_month}]->[0]++;
	      $average_size_stats->[$tfmonths->{$jyear_month}]->[1] += $mgjobs->{$_id_job}{bp};
	      $size_distribution->[$tfmonths->{$jyear_month}]->[0] += $mgjobs->{$_id_job}{bp};
	  }
      }

      my $t1 = $mgjobs->{$_id_job}{created_on};
      my $t2 = $mgjobs->{$_id_job}{done_timestamp} || $mgjobs->{$_id_job}{error_timestamp} || $mgjobs->{$_id_job}{dead_timestamp} || $mgjobs->{$_id_job}{deleted_timestamp} || $thirtyone_days->[30]. ' 23:59:59';

      if ( $self->{mgstat}->dates_overlap($t1,$t2,@$thirtyone_days[0,30]) )
      {
	  for (my $i=0; $i<31; $i++) 
	  {
	      my $curr = $thirtyone_days->[$i];
	      if ( ($self->{mgstat}->compare_dates($t1,$curr) eq 'before' and $self->{mgstat}->compare_dates($t2,$curr) eq 'after') or
		   (($t1 =~ /^$curr/) and ($t2 =~ /^$curr/)) )
	      {
		  $processing_stats->[$i] += $mgjobs->{$_id_job}{bp};
	      }
	  }
      }

      # count uploaded bp
      my $upload_stage = $self->{mgstat}->jobstage($_id_job, 'upload');
      my($upload_stage_name, $upload_stage_timestamp, $upload_stage_status) = @$upload_stage;

      $upload_stage_status ||= '';

      if ( ($upload_stage_status eq 'completed') and ($self->{mgstat}->compare_dates($upload_stage_timestamp, $thirtyone_days->[0]) eq 'after') )
      {
	for (my $i=0; $i<31; $i++) {
	  my $curr = $thirtyone_days->[$i];
	  if ($upload_stage_timestamp =~ /^$curr/) {
	    $upload_stats->[$i] += $mgjobs->{$_id_job}{bp};
	    $upload_stats_new->[$i][1] += $mgjobs->{$_id_job}{bp};
	    push @{ $job_date{$curr} }, $_id_job;
	    last;
	  }
	}
      }

      
      my($creation_date) = split(/\s+/, $mgjobs->{$_id_job}{created_on});
      
      if ( exists $last_month_jobs_bp->{$creation_date} )
      {
	  if ( $mgjobs->{$_id_job}{done} )
	  {
	      $last_month_jobs_bp->{$creation_date}{done} += $mgjobs->{$_id_job}{bp};
	      $last_month_jobs_count->{$creation_date}{done} += 1;
	  }
	  elsif ( $mgjobs->{$_id_job}{deleted} or $mgjobs->{$_id_job}{dead} )
	  {
	      $last_month_jobs_bp->{$creation_date}{deleted} += $mgjobs->{$_id_job}{bp};
	      $last_month_jobs_count->{$creation_date}{deleted} += 1;
	  }
	  elsif ( $mgjobs->{$_id_job}{error} )
	  {
	      $last_month_jobs_bp->{$creation_date}{error} += $mgjobs->{$_id_job}{bp};
	      $last_month_jobs_count->{$creation_date}{error} += 1;
	  }
	  else
	  {
	      # this should get jobs which are either running or stalled with last stage status completed or running

	      my $ls_status = '';
	      if ( $last_stage_status eq 'completed' )
	      {
		  $ls_status = 'running';
	      }
	      else
	      {
		  $ls_status = $last_stage_status;
	      }

	      $last_month_jobs_bp->{$creation_date}{$ls_status} += $mgjobs->{$_id_job}{bp};
	      $last_month_jobs_count->{$creation_date}{$ls_status} += 1;
	  }
      }

      my $todays_date = $self->{mgstat}->todays_date();

      if ( $mgjobs->{$_id_job}{done} )
      {
	  # don't count
      }
      elsif ( $mgjobs->{$_id_job}{deleted} or $mgjobs->{$_id_job}{dead} )
      {
	  # don't count
      }
      else
      {
	  my $job_id = $mgjobs->{$_id_job}{job_id};

	  $pipeline_job_id->{$job_id} = 1;
	  $pipeline_jobs_count->{$last_stage_name}{$last_stage_status}++;
	  $pipeline_jobs_bp->{$last_stage_name}{$last_stage_status} += $mgjobs->{$_id_job}{bp};
	  
	  if ( $creation_date ne $todays_date )
	  {
	      $incomplete_job_id->{$job_id} = 1;

	      if ( $mgjobs->{$_id_job}{error} )
	      {
		  $incomplete_jobs_bp->{$creation_date}{error} += $mgjobs->{$_id_job}{bp};
		  $incomplete_jobs_count->{$creation_date}{error} += 1;
	      }
	      else
	      {
		  # this should get jobs which are either running or stalled with last stage status completed or running
		  
		  my $ls_status = '';
		  if ( $last_stage_status eq 'completed' )
		  {
		      $ls_status = 'running';
		  }
		  else
		  {
		      $ls_status = $last_stage_status;
		  }
		  
		  $incomplete_jobs_bp->{$creation_date}{$ls_status} += $mgjobs->{$_id_job}{bp};
		  $incomplete_jobs_count->{$creation_date}{$ls_status} += 1;
	      }
	  }
      }

      # count broken jobs
      if ( ($last_stage_status eq 'error') and ($self->{mgstat}->compare_dates($last_stage_timestamp, $thirtyone_days->[0]) eq 'after') )
#      if ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'error') {
      {
	for (my $i=0; $i<31; $i++) {
	  my $curr = $thirtyone_days->[$i];
	  if ( $last_stage_timestamp =~ /^$curr/ ) 
#	  if ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0] =~ /^$curr/) {
	  {
	    $broken_stats->[$i]++;
	    # $processing_stats->[$i] -= $mgjobs->{$_id_job}{bp};
	    last;
	  }
	}
      }
      
      # count finished bp
      elsif ( $last_stage_name eq 'done' && $last_stage_status eq 'completed' && ($self->{mgstat}->compare_dates($last_stage_timestamp, $thirtyone_days->[0]) eq 'after') ) {
#      elsif ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[1] eq 'done' && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'completed') {
	  for (my $i=0; $i<31; $i++) {
	      my $curr = $thirtyone_days->[$i];
	      if ( $last_stage_timestamp =~ /^$curr/) {
		  $finished_stats->[$i] += $mgjobs->{$_id_job}{bp};

		  if ( $i <= 29 )
		  {
		      $bp_month += $mgjobs->{$_id_job}{bp};

		      if ( $i >= 23 )
		      {
			  $bp_week += $mgjobs->{$_id_job}{bp};
		      }
		  }
		  else
		  {
		      $bp_today += $mgjobs->{$_id_job}{bp};
		  }
		  # $processing_stats->[$i] -= $mgjobs->{$_id_job}{bp};
		  last;
	      }
	  }
      }
  }


  foreach my $_id_job ( @{ $self->{mgstat}->jobs_created_today() } )
  {
      my $job_id = $mgjobs->{$_id_job}{job_id};
      $today_job_id->{$job_id} = 1;

      my($hour) = int( substr($mgjobs->{$_id_job}{created_on}, 11, 2) );

      if ( $mgjobs->{$_id_job}{done} )
      {
	  $today_jobs_bp->{$hour}{done} += $mgjobs->{$_id_job}{bp};
	  $today_jobs_count->{$hour}{done} += 1;
      }
      elsif ( $mgjobs->{$_id_job}{deleted} or $mgjobs->{$_id_job}{dead} )
      {
	  $today_jobs_bp->{$hour}{deleted} += $mgjobs->{$_id_job}{bp};
	  $today_jobs_count->{$hour}{deleted} += 1;
      }
      elsif ( $mgjobs->{$_id_job}{error} )
      {
	  $today_jobs_bp->{$hour}{error} += $mgjobs->{$_id_job}{bp};
	  $today_jobs_count->{$hour}{error} += 1;
      }
      else
      {
	  # this should get jobs which are either running or stalled with last stage status completed or running
	  
	  my $last_stage = $self->{mgstat}->job2lastpipelinestage($_id_job);

	  my $ls_status = '';
	  if ( @$last_stage )
	  {
	      my($last_stage_name, $last_stage_timestamp, $last_stage_status) = @$last_stage;
	      
	      if ( $last_stage_status eq 'completed' )
	      {
		  $ls_status = 'running';
	      }
	      else
	      {
		  $ls_status = $last_stage_status;
	      }
	  }
	  else
	  {
	      $ls_status = 'unknown';
	  }
	  
	  $today_jobs_bp->{$hour}{$ls_status} += $mgjobs->{$_id_job}{bp};
	  $today_jobs_count->{$hour}{$ls_status} += 1;
      }
  }      

  # format to gbp
  for (my $i=0; $i<31; $i++) {
    $upload_stats->[$i] ? $upload_stats->[$i] = sprintf("%.2f", $upload_stats->[$i] / 1000000000) : 1;
    $upload_stats_new->[$i][1] ? $upload_stats_new->[$i][1] = sprintf("%.2f", $upload_stats_new->[$i][1] / 1000000000) : 1;
    $finished_stats->[$i] ? $finished_stats->[$i] = sprintf("%.2f", $finished_stats->[$i] / 1000000000) : 1;
    $processing_stats->[$i] ? $processing_stats->[$i] = sprintf("%.2f", $processing_stats->[$i] / 1000000000) : 1;
  }

  for (my $i=0; $i<48; $i++) {
    my $sum_i = $size_distribution->[$i]->[0] + $size_distribution->[$i]->[1] + $size_distribution->[$i]->[2];
    if ($sum_i) {
      $size_distribution->[$i]->[0] = sprintf("%.2f", $size_distribution->[$i]->[0] / $sum_i * 100);
      $size_distribution->[$i]->[1] = sprintf("%.2f", $size_distribution->[$i]->[1] / $sum_i * 100);
      $size_distribution->[$i]->[2] = sprintf("%.2f", $size_distribution->[$i]->[2] / $sum_i * 100);
    }
    if ($average_size_stats->[$i]->[0] > 0) {
      $average_size_stats->[$i] = sprintf("%.2f", ($average_size_stats->[$i]->[1] / $average_size_stats->[$i]->[0]) / 1000000);
    } else {
      $average_size_stats->[$i] = 0;
    }
    if ($average_size_stats_filtered->[$i]->[0] > 0) {
      $average_size_stats_filtered->[$i] = sprintf("%.2f", ($average_size_stats_filtered->[$i]->[1] / $average_size_stats_filtered->[$i]->[0]) / 1000000);
    } else {
      $average_size_stats_filtered->[$i] = 0;
    }
    if ($average_size_stats_filtered2->[$i]->[0] > 0) {
      $average_size_stats_filtered2->[$i] = sprintf("%.2f", ($average_size_stats_filtered2->[$i]->[1] / $average_size_stats_filtered2->[$i]->[0]) / 1000000);
    } else {
      $average_size_stats_filtered2->[$i] = 0;
    }
  }



  @$jdata = sort {$b->[0] cmp $a->[0]} @$jdata;



  my $jt = $application->component('alljobs_table');
  $jt->show_top_browse(1);
  $jt->show_bottom_browse(1);
  $jt->show_clear_filter_button(1);
  $jt->show_select_items_per_page(1);
  $jt->items_per_page(15);
  $jt->data($jdata);
  $jt->show_column_select(1);
  $jt->columns( [ { name => 'created', filter => 1, sortable => 1 },
		  { name => 'mgid', filter => 1, sortable => 1 },
		  { name => 'jid', filter => 1, sortable => 1 },
		  { name => 'name', filter => 1, sortable => 1 },
		  { name => 'size', filter => 1, sortable => 1 },
		  { name => 'sequence type', filter => 1, operator => 'combobox', visible => 0 },
		  { name => 'viewable', filter => 1, operator => 'combobox' },
		  { name => 'public', filter => 1, operator => 'combobox' },
		  { name => 'version', filter => 1, sortable => 1, operator => 'combobox', visible => 0 },
		  { name => 'project', filter => 1, sortable => 1, visible => 0 },
		  { name => 'firstname', filter => 1, sortable => 1 },
		  { name => 'lastname', filter => 1, sortable => 1 },
		  { name => 'login', filter => 1, sortable => 1, visible => 0 },
		  { name => 'email', filter => 1, sortable => 1, visible => 0 },
		  { name => 'funding source', filter => 1, sortable => 1 },
		  { name => 'organization', filter => 1, sortable => 1, visible => 0 },
		  { name => 'country', filter => 1, operator => 'combobox', visible => 0 },
		  { name => 'last stage', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'last stage status', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'last stage time', filter => 1, sortable => 1 },
		  { name => 'status file' } ] );

  my $odata = [];
  foreach my $_id_org ( keys %$mgorgs )
  {
      my $n_users = exists $mgorgs->{$_id_org}{user}? scalar @{ $mgorgs->{$_id_org}{user} } : 0;
      my $bp = 0;
      foreach my $_id_job ( @{ $mgorgs->{$_id_org}{job} } )
      {
	  $bp += $mgjobs->{$_id_job}{bp};
      }

      push @$odata, [
		     $mgorgs->{$_id_org}{name}, 
		     $mgorgs->{$_id_org}{country}, 
		     $n_users,
		     $bp
		     ];
		     
  }

  my $ot = $application->component('organization_table');
  $ot->show_top_browse(1);
  $ot->show_bottom_browse(1);
  $ot->show_clear_filter_button(1);
  $ot->show_select_items_per_page(1);
  $ot->items_per_page(15);
  $ot->data($odata);
  $ot->columns( [ { name => 'name', filter => 1, sortable => 1 },
		  { name => 'country', filter => 1, sortable => 1 },
		  { name => '# users', filter => 1, sortable => 1 },
		  { name => 'bp', filter => 1, sortable => 1 },
		  ] );

  my $gbp_today = sprintf("%.0f", $bp_today/1000000000);
  my $gbp_week  = sprintf("%.0f", $bp_week/1000000000);
  my $gbp_month = sprintf("%.0f", $bp_month/1000000000);

  my $gbp_week_daily  = sprintf("%.0f", $gbp_week/7);
  my $gbp_month_daily = sprintf("%.0f", $gbp_month/30);

  $gbp_week  = $self->add_commas($gbp_week);
  $gbp_month = $self->add_commas($gbp_month);

# use below to hide the div
#   $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"pspeed\").style.display==\"none\"){document.getElementById(\"pspeed\").style.display=\"\";}else{document.getElementById(\"pspeed\").style.display=\"none\";}'>&raquo; Processing Speed</h2><div id='pspeed' style='display: ;'>".$gmeter_table."</div>";
  $html .= $self->google_gauge('gauge_1', $gbp_today);
  $html .= $self->google_gauge('gauge_2', $gbp_week_daily);
  $html .= $self->google_gauge('gauge_3', $gbp_month_daily);

  $html .= "
<h2>&raquo; Jobs completed</h2>
<table width='100%'>
  <tr>
    <td align='center' width='33%'><b>Today</b></td>
    <td align='center' width='34%'><b>Last 7 days<br>($gbp_week Gbp)</b></td>
    <td align='center' width='33%'><b>Last 30 days<br>($gbp_month Gbp)</b></td>
  </tr>
  <tr>
    <td align='center'><div id='gauge_1'></div></td>
    <td align='center'><div id='gauge_2'></div></td>
    <td align='center'><div id='gauge_3'></div></td>
  </tr>
  <tr>
    <td align='center'>Gbp today</td>
    <td align='center'>Gbp/day</td>
    <td align='center'>Gbp/day</td>
  </tr>
</table>
";


  my $month_jobs_count = 0;
  my $month_jobs_bp    = 0;
  my $month_jobs       = [];

  foreach my $date ( @$thirtyone_days )
  {
      $month_jobs_count += $last_month_jobs_count->{$date}{error} + $last_month_jobs_count->{$date}{running} + $last_month_jobs_count->{$date}{done};
      $month_jobs_bp    += $last_month_jobs_bp->{$date}{error} + $last_month_jobs_bp->{$date}{running} + $last_month_jobs_bp->{$date}{done};
      push @$month_jobs, [
			  $date,
			  $last_month_jobs_count->{$date}{error},
			  $last_month_jobs_count->{$date}{running},
			  $last_month_jobs_count->{$date}{done},
			  $self->bp2gbp( $last_month_jobs_bp->{$date}{error} ),
			  $self->bp2gbp( $last_month_jobs_bp->{$date}{running} ),
			  $self->bp2gbp( $last_month_jobs_bp->{$date}{done} ),
			  ];
  }

  my $month_jobs_gbp = $self->bp2gbp($month_jobs_bp);
  $month_jobs_count  = $self->add_commas($month_jobs_count);

  my $month_jobs_table = $application->component('month_jobs_table');
  $month_jobs_table->items_per_page(31);
  $month_jobs_table->data($month_jobs);

  $month_jobs_table->columns( 
			      [ 
				{ name => 'creation date' },
				{ name => '# jobs, error' },
				{ name => '# jobs, running' },
				{ name => '# jobs, done' },
				{ name => 'gbp, error' },
				{ name => 'gbp, running' },
				{ name => 'gbp, done' },
			      ] 
			    );

  $html .= $self->google_columnchart_month_jobs('columnchart_month_jobs', $last_month_jobs_bp, $last_month_jobs_count);

  my $month_jobs_chart .= "
<table>
<tr>
<td align='left'>
<form><input id='columnchart_month_jobs_button' type='button' value='switch to job count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='columnchart_month_jobs'></div>
</td>
</tr>
</table>
";
  $html .= "<h2>&raquo; Jobs created in the last month, $month_jobs_gbp Gbp in $month_jobs_count jobs</h2>\n";
  $html .= $self->input_button('month_jobs_chart_button', 'month_jobs_chart', 'show chart', 'hide chart');
  $html .= $self->input_button('month_jobs_table_button', 'month_jobs_table', 'show daily jobs table', 'hide daily jobs table');
  $html .= "<div id='month_jobs_chart' style='display:none'>".$month_jobs_chart."</div>\n";
  $html .= "<div id='month_jobs_table' style='display:none'>".$month_jobs_table->output()."</div>\n";


  my $t_jobs_count = 0;
  my $t_jobs_bp    = 0;
  my $t_jobs       = [];

  my $curr_hour = (localtime(time))[2];

  foreach my $hour ( 0..$curr_hour )
  {
      $t_jobs_count += $today_jobs_count->{$hour}{error} + $today_jobs_count->{$hour}{running} + $today_jobs_count->{$hour}{done};
      $t_jobs_bp    += $today_jobs_bp->{$hour}{error} + $today_jobs_bp->{$hour}{running} + $today_jobs_bp->{$hour}{done};
      push @$t_jobs, [
			  $hour . '-' . ($hour+1),
			  $today_jobs_count->{$hour}{error},
			  $today_jobs_count->{$hour}{running},
			  $today_jobs_count->{$hour}{done},
			  $self->bp2gbp( $today_jobs_bp->{$hour}{error} ),
			  $self->bp2gbp( $today_jobs_bp->{$hour}{running} ),
			  $self->bp2gbp( $today_jobs_bp->{$hour}{done} ),
			  ];
  }

  my $t_jobs_gbp = $self->bp2gbp($t_jobs_bp);
  $t_jobs_count  = $self->add_commas($t_jobs_count);

  my $today_jobs_table = $application->component('today_jobs_table');
  $today_jobs_table->items_per_page(24);
  $today_jobs_table->data($t_jobs);

  $today_jobs_table->columns( 
			      [ 
				{ name => 'creation time' },
				{ name => '# jobs, error' },
				{ name => '# jobs, running' },
				{ name => '# jobs, done' },
				{ name => 'gbp, error' },
				{ name => 'gbp, running' },
				{ name => 'gbp, done' },
			      ] 
			    );

  my $t2_data = [];
  foreach my $row ( @$jdata )
  {
      my $job_id = $row->[2];
      if ( exists $today_job_id->{$job_id} )
      {
 	  push @$t2_data, $row;
      }
  }

  my $today_jobs_table_2 = $application->component('today_jobs_table_2');
  $today_jobs_table_2->show_top_browse(1);
  $today_jobs_table_2->show_bottom_browse(1);
  $today_jobs_table_2->show_clear_filter_button(1);
  $today_jobs_table_2->show_select_items_per_page(1);
  $today_jobs_table_2->items_per_page(15);
  $today_jobs_table_2->data($t2_data);
  $today_jobs_table_2->show_column_select(1);
  $today_jobs_table_2->columns( [ { name => 'created', filter => 1, sortable => 1 },
				  { name => 'mgid', filter => 1, sortable => 1 },
				  { name => 'jid', filter => 1, sortable => 1 },
				  { name => 'name', filter => 1, sortable => 1 },
				  { name => 'size', filter => 1, sortable => 1 },
				  { name => 'sequence type', filter => 1, operator => 'combobox', visible => 0 },
				  { name => 'viewable', filter => 1, operator => 'combobox' },
				  { name => 'public', filter => 1, operator => 'combobox' },
				  { name => 'version', filter => 1, sortable => 1, operator => 'combobox', visible => 0 },
				  { name => 'project', filter => 1, sortable => 1, visible => 0 },
				  { name => 'firstname', filter => 1, sortable => 1 },
				  { name => 'lastname', filter => 1, sortable => 1 },
				  { name => 'login', filter => 1, sortable => 1, visible => 0 },
				  { name => 'email', filter => 1, sortable => 1, visible => 0 },
				  { name => 'funding source', filter => 1, sortable => 1 },
				  { name => 'organization', filter => 1, sortable => 1, visible => 0 },
				  { name => 'country', filter => 1, operator => 'combobox', visible => 0 },
				  { name => 'last stage', filter => 1, sortable => 1, operator => 'combobox' },
				  { name => 'last stage status', filter => 1, sortable => 1, operator => 'combobox' },
				  { name => 'last stage time', filter => 1, sortable => 1 },
				  { name => 'status file' } ] );

  $html .= $self->google_columnchart_today_jobs('columnchart_today_jobs', $today_jobs_bp, $today_jobs_count);
  my $today_jobs_chart .= "
<table>
<tr>
<td align='left'>
<form><input id='columnchart_today_jobs_today_button' type='button' value='switch to job count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='columnchart_today_jobs'></div>
</td>
</tr>
</table>
";

  $html .= "<h2>&raquo; Jobs created today, $t_jobs_gbp Gbp in $t_jobs_count jobs</h2>\n";

  $html .= $self->input_button('today_jobs_chart_button', 'today_jobs_chart', 'show chart', 'hide chart');
  $html .= $self->input_button('today_hourly_jobs_table_button', 'today_hourly_jobs_table', 'show hourly jobs table', 'hide hourly jobs table');
  $html .= $self->input_button('today_jobs_table_button', 'today_jobs_table', 'show jobs table', 'hide jobs table');
  $html .= "<div id='today_jobs_chart' style='display:none'>".$today_jobs_chart."</div>\n";
  $html .= "<div id='today_jobs_table' style='display:none'>".$today_jobs_table_2->output()."</div>\n";
  $html .= "<div id='today_hourly_jobs_table' style='display:none'>".$today_jobs_table->output()."</div>\n";

   if ( keys %$incomplete_jobs_bp )
   {
       my $i_jobs_count = 0;
       my $i_jobs_bp    = 0;
       my $i_jobs       = [];

       foreach my $date ( sort keys %$incomplete_jobs_bp )
       {
	   $incomplete_jobs_count->{$date}{error}   ||= 0;
	   $incomplete_jobs_count->{$date}{running} ||= 0;

	   $incomplete_jobs_bp->{$date}{error}      ||= 0;
	   $incomplete_jobs_bp->{$date}{running}    ||= 0;
       }

       foreach my $date ( sort keys %$incomplete_jobs_bp )
       {
	   $i_jobs_count += $incomplete_jobs_count->{$date}{error} + $incomplete_jobs_count->{$date}{running};
	   $i_jobs_bp    += $incomplete_jobs_bp->{$date}{error} + $incomplete_jobs_bp->{$date}{running};
	   push @$i_jobs, [
			   $date,
			   $incomplete_jobs_count->{$date}{error},
			   $incomplete_jobs_count->{$date}{running},
			   $self->bp2gbp( $incomplete_jobs_bp->{$date}{error} ),
			   $self->bp2gbp( $incomplete_jobs_bp->{$date}{running} ),
			   ];
      }

       my $i_jobs_gbp = $self->bp2gbp($i_jobs_bp);
       $i_jobs_count  = $self->add_commas($i_jobs_count);
       
       my $incomplete_jobs_table = $application->component('incomplete_jobs_table');
       my $n_rows = scalar keys %$incomplete_jobs_bp;
       $incomplete_jobs_table->items_per_page($n_rows);
       $incomplete_jobs_table->data($i_jobs);
       
       $incomplete_jobs_table->columns( 
					[ 
					  { name => 'creation date' },
					  { name => '# jobs, error' },
					  { name => '# jobs, running' },
					  { name => 'gbp, error' },
					  { name => 'gbp, running' },
					  ] 
					);

       my $i2_data = [];
       foreach my $row ( @$jdata )
       {
	   my $job_id = $row->[2];
	   if ( exists $incomplete_job_id->{$job_id} )
	   {
	       push @$i2_data, $row;
	   }
       }
       
       my $incomplete_jobs_table_2 = $application->component('incomplete_jobs_table_2');
       $incomplete_jobs_table_2->show_top_browse(1);
       $incomplete_jobs_table_2->show_bottom_browse(1);
       $incomplete_jobs_table_2->show_clear_filter_button(1);
       $incomplete_jobs_table_2->show_select_items_per_page(1);
       $incomplete_jobs_table_2->items_per_page(15);
       $incomplete_jobs_table_2->data($i2_data);
       $incomplete_jobs_table_2->show_column_select(1);
       $incomplete_jobs_table_2->columns( [ { name => 'created', filter => 1, sortable => 1 },
					    { name => 'mgid', filter => 1, sortable => 1 },
					    { name => 'jid', filter => 1, sortable => 1 },
					    { name => 'name', filter => 1, sortable => 1 },
					    { name => 'size', filter => 1, sortable => 1 },
					    { name => 'sequence type', filter => 1, operator => 'combobox', visible => 0 },
					    { name => 'viewable', filter => 1, operator => 'combobox' },
					    { name => 'public', filter => 1, operator => 'combobox' },
					    { name => 'version', filter => 1, sortable => 1, operator => 'combobox', visible => 0 },
					    { name => 'project', filter => 1, sortable => 1, visible => 0 },
					    { name => 'firstname', filter => 1, sortable => 1 },
					    { name => 'lastname', filter => 1, sortable => 1 },
					    { name => 'login', filter => 1, sortable => 1, visible => 0 },
					    { name => 'email', filter => 1, sortable => 1, visible => 0 },
					    { name => 'funding source', filter => 1, sortable => 1 },
					    { name => 'organization', filter => 1, sortable => 1, visible => 0 },
					    { name => 'country', filter => 1, operator => 'combobox', visible => 0 },
					    { name => 'last stage', filter => 1, sortable => 1, operator => 'combobox' },
					    { name => 'last stage status', filter => 1, sortable => 1, operator => 'combobox' },
					    { name => 'last stage time', filter => 1, sortable => 1 },
					    { name => 'status file' } ] );
       
       
       my $div_id = 'columnchart_incomplete_jobs';
       $html .= $self->google_columnchart_incomplete_jobs($div_id, $incomplete_jobs_bp, $incomplete_jobs_count);
       
       my $incomplete_jobs_chart = "
<table>
<tr>
<td align='left'>
<form><input id='columnchart_incomplete_jobs_button' type='button' value='switch to job count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='$div_id'></div>
</td>
</tr>
</table>
";

       $html .= "<h2>&raquo; Incomplete jobs by creation date (excluding today), $i_jobs_gbp Gbp in $i_jobs_count jobs</h2>\n";

       $html .= $self->input_button('incomplete_jobs_chart_button', 'incomplete_jobs_chart', 'show chart', 'hide chart');
       $html .= $self->input_button('incomplete_daily_jobs_table_button', 'incomplete_daily_jobs_table', 'show daily jobs table', 'hide daily jobs table');
       $html .= $self->input_button('incomplete_jobs_table_button', 'incomplete_jobs_table', 'show jobs table', 'hide jobs table');
       $html .= "<div id='incomplete_jobs_chart' style='display:none'>".$incomplete_jobs_chart."</div>\n";
       $html .= "<div id='incomplete_jobs_table' style='display:none'>".$incomplete_jobs_table_2->output()."</div>\n";
       $html .= "<div id='incomplete_daily_jobs_table' style='display:none'>".$incomplete_jobs_table->output()."</div>\n";
  }
  else
  {
      $html = "<h2>&raquo; Incomplete jobs by creation date, excluding today</h2>\n";
      $html .= "<h3>No incomplete jobs</h3>\n";
  }

  my $p_jobs_count = 0;
  my $p_jobs_bp    = 0;
  my $p_jobs       = [];
  
  foreach my $stage ( @{ $self->{mgstat}->pipeline_stages_ordered() } )
  {
      $pipeline_jobs_count->{$stage}{error}     ||= 0;
      $pipeline_jobs_count->{$stage}{running}   ||= 0;
      $pipeline_jobs_count->{$stage}{completed} ||= 0;

      $pipeline_jobs_bp->{$stage}{error}        ||= 0;
      $pipeline_jobs_bp->{$stage}{running}      ||= 0;
      $pipeline_jobs_bp->{$stage}{completed}    ||= 0;
  }

  foreach my $stage ( @{ $self->{mgstat}->pipeline_stages_ordered() } )
  {
      $p_jobs_count += $pipeline_jobs_count->{$stage}{error} + $pipeline_jobs_count->{$stage}{running} + $pipeline_jobs_count->{$stage}{completed};
      $p_jobs_bp    += $pipeline_jobs_bp->{$stage}{error} + $pipeline_jobs_bp->{$stage}{running} + $pipeline_jobs_bp->{$stage}{completed};
      push @$p_jobs, [
		      $stage,
		      $pipeline_jobs_count->{$stage}{error},
		      $pipeline_jobs_count->{$stage}{running},
		      $pipeline_jobs_count->{$stage}{completed},
		      $self->bp2gbp( $pipeline_jobs_bp->{$stage}{error} ),
		      $self->bp2gbp( $pipeline_jobs_bp->{$stage}{running} ),
		      $self->bp2gbp( $pipeline_jobs_bp->{$stage}{completed} ),
		      ];
  }

  my $p_jobs_gbp = $self->bp2gbp($p_jobs_bp);
  $p_jobs_count  = $self->add_commas($p_jobs_count);
  
  my $pipeline_jobs_table = $application->component('pipeline_jobs_table');
  my $n_rows = scalar @$p_jobs;
  $pipeline_jobs_table->items_per_page($n_rows);
  $pipeline_jobs_table->data($p_jobs);
  
  $pipeline_jobs_table->columns( 
				 [ 
				   { name => 'pipeline stage' },
				   { name => '# jobs, error' },
				   { name => '# jobs, running' },
				   { name => '# jobs, completed' },
				   { name => 'gbp, error' },
				   { name => 'gbp, running' },
				   { name => 'gbp, completed' },
				   ] 
				 );

  my $p2_data = [];
  foreach my $row ( @$jdata )
  {
      my $job_id = $row->[2];
      if ( exists $pipeline_job_id->{$job_id} )
      {
 	  push @$p2_data, $row;
      }
  }

  my $pipeline_jobs_table_2 = $application->component('pipeline_jobs_table_2');
  $pipeline_jobs_table_2->show_top_browse(1);
  $pipeline_jobs_table_2->show_bottom_browse(1);
  $pipeline_jobs_table_2->show_clear_filter_button(1);
  $pipeline_jobs_table_2->show_select_items_per_page(1);
  $pipeline_jobs_table_2->items_per_page(15);
  $pipeline_jobs_table_2->data($p2_data);
  $pipeline_jobs_table_2->show_column_select(1);
  $pipeline_jobs_table_2->columns( [ { name => 'created', filter => 1, sortable => 1 },
				     { name => 'mgid', filter => 1, sortable => 1 },
				     { name => 'jid', filter => 1, sortable => 1 },
				     { name => 'name', filter => 1, sortable => 1 },
				     { name => 'size', filter => 1, sortable => 1 },
				     { name => 'sequence type', filter => 1, operator => 'combobox', visible => 0 },
				     { name => 'viewable', filter => 1, operator => 'combobox' },
				     { name => 'public', filter => 1, operator => 'combobox' },
				     { name => 'version', filter => 1, sortable => 1, operator => 'combobox', visible => 0 },
				     { name => 'project', filter => 1, sortable => 1, visible => 0 },
				     { name => 'firstname', filter => 1, sortable => 1 },
				     { name => 'lastname', filter => 1, sortable => 1 },
				     { name => 'login', filter => 1, sortable => 1, visible => 0 },
				     { name => 'email', filter => 1, sortable => 1, visible => 0 },
				     { name => 'funding source', filter => 1, sortable => 1 },
				     { name => 'organization', filter => 1, sortable => 1, visible => 0 },
				     { name => 'country', filter => 1, operator => 'combobox', visible => 0 },
				     { name => 'last stage', filter => 1, sortable => 1, operator => 'combobox' },
				     { name => 'last stage status', filter => 1, sortable => 1, operator => 'combobox' },
				     { name => 'last stage time', filter => 1, sortable => 1 },
				     { name => 'status file' } ] );

  $html .= $self->google_columnchart_pipeline_jobs('columnchart_pipeline_jobs', $pipeline_jobs);
  my $pipeline_jobs_chart = "
<table>
<tr>
<td align='left'>
<form><input id='columnchart_pipeline_jobs_button' type='button' value='switch to job count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='columnchart_pipeline_jobs'></div>
</td>
</tr>
</table>
";

  $pipeline_jobs_table_2->show_export_button({title => 'export', strip_html => 1});

  $html .= "<h2>&raquo; Incomplete jobs by pipeline stage (including today), $p_jobs_gbp Gbp in $p_jobs_count jobs</h2>\n";
  $html .= $self->input_button('pipeline_jobs_chart_button', 'pipeline_jobs_chart', 'show chart', 'hide chart');
  $html .= $self->input_button('pipeline_jobs_stage_table_button', 'pipeline_jobs_stage_table', 'show job stage table', 'hide job stage table');
  $html .= $self->input_button('pipeline_jobs_table_button', 'pipeline_jobs_table', 'show job table', 'hide job table');
  $html .= "<div id='pipeline_jobs_chart' style='display:none'>".$pipeline_jobs_chart."</div>\n";
  $html .= "<div id='pipeline_jobs_table' style='display:none'>".$pipeline_jobs_table_2->output()."</div>\n";
  $html .= "<div id='pipeline_jobs_stage_table' style='display:none'>".$pipeline_jobs_table->output()."</div>\n";


  my $total_new_users;
  foreach my $curr_date ( keys %$new_users )
  {
      $total_new_users += $new_users->{$curr_date};
  }

  my $new_users_chart = "<div id='columnchart_new_users'></div>\n";
  $html .= $self->google_columnchart_new_users('columnchart_new_users', $new_users);

  $html .= "<h2>&raquo; New users in last month ($total_new_users)</h2>\n";
  $html .= $self->input_button('new_users_chart_button', 'new_users_chart', 'show chart', 'hide chart');
  $html .= "<div id='new_users_chart' style='display:none'>".$new_users_chart."</div>\n";


  $html .= $self->google_piechart('today_users_chart', "Registered users\\' last page today", ['Page', 'Count'], $data_page_count, 20);

  my $tu_data = [];
  foreach my $_id_user ( sort { lc $mgusers->{$a}->{lastname} cmp lc $mgusers->{$b}->{lastname} ||lc  $mgusers->{$a}->{firstname} cmp lc $mgusers->{$b}->{firstname} } @$today_users_registered )
  {
      my $page = $mgusers->{$_id_user}{last_page} || 'Home';
      push @$tu_data, [$mgusers->{$_id_user}->{firstname}, $mgusers->{$_id_user}->{lastname}, $page];
  }

  my $today_users_table = $application->component('today_users_table');
  $today_users_table->show_top_browse(1);
  $today_users_table->show_bottom_browse(1);
  $today_users_table->show_clear_filter_button(1);
  $today_users_table->show_select_items_per_page(1);
  $today_users_table->items_per_page(15);
  $today_users_table->data($tu_data);
  $today_users_table->columns( [ 
				 { name => 'first name', filter => 1, sortable => 1 },
				 { name => 'last name', filter => 1, sortable => 1 },
				 { name => 'last page accessed today', filter => 1, sortable => 1, operator => 'combobox' }, 
				 ] );

  $html .= "<h2>&raquo; Registered users online today (" . scalar(@$today_users_registered) . ")</h2>\n";
  $html .= $self->input_button('today_users_chart_button', 'today_users_chart', 'show chart', 'hide chart');
  $html .= $self->input_button('today_users_table_button', 'today_users_table', 'show table', 'hide table');
  $html .= "<div id='today_users_chart' style='display:none'></div>\n";
  $html .= "<div id='today_users_table' style='display:none'>".$today_users_table->output()."</div>\n";

  $html .= $self->google_geochart_users('geochart_users', $countries, $current_countries);
  my $users_map = "
<table>
<tr>
<td align='left'>
<form><input id='geochart_users_button' type='button' value='switch to todays users'></input></form>
</td>
</tr>
<tr>
<td>
<div id='geochart_users'></div>
</td>
</tr>
</table>
";

  $html .= "<h2>&raquo; Registered users map (only users registered with organization)</h2>\n";
  $html .= $self->input_button('users_map_button', 'users_map', 'show map', 'hide map');
  $html .= "<div id='users_map' style='display:none'>".$users_map."</div>\n";

  # job list output
  $jt->show_export_button({title => 'export', strip_html => 1});

  $html .= "<h2>&raquo; All jobs (" . $self->add_commas( scalar @$jdata ) . ")</h2>\n";
  $html .= $self->input_button('all_jobs_table_button', 'all_jobs_table', 'show table', 'hide table');
  $html .= "<div id='all_jobs_table' style='display:none'>".$jt->output()."</div>\n";

  # user list output
  $html .= "<h2>&raquo; All users (" . $self->add_commas( scalar @$data ) . ")</h2>\n";
  $html .= $self->input_button('all_users_table_button', 'all_users_table', 'show table', 'hide table');
  $html .= "<div id='all_users_table' style='display:none'>".$ut->output()."</div>\n";

  # organization list output
  $html .= "<h2>&raquo; All organizations (" . $self->add_commas( scalar @$odata ) . ")</h2>\n";
  $html .= $self->input_button('all_organizations_table_button', 'all_organizations_table', 'show table', 'hide table');
  $html .= "<div id='all_organizations_table' style='display:none'>".$ot->output()."</div>\n";

  ### funding sources user and job
  my $table_b = $self->application->component('FundingSourcesClean');
  my $data_b  = $self->{mgstat}->get_funding_user_jobs(); # fund, number of users, number of jobs, sum of job bp

  my @fund_usr = map { [$_->[0], $_->[1]] } @$data_b;
  my @fund_job = map { [$_->[0], $_->[2]] } @$data_b;
  my @fund_bps = map { [$_->[0], sprintf("%.1f", ($_->[3] * 1.0)/1000000000)] } @$data_b;
  
  my($pie_usr, $div_usr) = &get_piechart('funding_source_user_chart', 'Users per funding source', ['Organization', 'Users'], \@fund_usr, 0, 800);
  my($pie_job, $div_job) = &get_piechart('funding_source_job_chart',  'Jobs per funding source',  ['Organization', 'Jobs'],  \@fund_job, 20, 800);
  my($pie_gbp, $div_gbp) = &get_piechart('funding_source_gbp_chart',  'Gbp per funding source',   ['Organization', 'Gbp'],  \@fund_bps, 20, 800);
  #my $div_b = "<table><tr><td>$div_usr</td><td>$div_job</td><td>$div_bps</td></tr></table>";
  #my $div_b = "$div_usr\n$div_job\n$div_bps\n";

  $table_b->width(850);
  if ( scalar(@$data_b) > 25 ) {
    $table_b->show_top_browse(1);
    $table_b->show_bottom_browse(1);
    $table_b->show_clear_filter_button(1);
    $table_b->items_per_page(25);
    $table_b->show_select_items_per_page(1); 
  }
  $table_b->columns([ { name => 'Funding Source', sortable => 1, filter => 1},
		      { name => 'Users', sortable  => 1 },
		      { name => 'Jobs', sortable  => 1 },
		      { name => 'Basepairs', sortable => 1 }
		    ]);
  $table_b->data($data_b);
#  $table_b->show_export_button({title => 'export', strip_html => 1});
  
  ### job counts

  my %month_counts_completed;   # completed AND viewable, i.e. completed and not deleted
  my %month_counts_submitted;   # all jobs submitted -- includes incomplete, and deleted jobs

  foreach my $rec ( @$jdata )
  {
      my($creation_date, $bp, $seq_type, $viewable, $public, $last_stage_name, $last_stage_status, $last_stage_timestamp) = @$rec[0,4,5,6,7,17,18,19];

      if ( $creation_date =~ /^20(\d\d-\d\d)/ )
      {
	  my $month = $1;

	  $month_counts_submitted{$month}{all}{bp}   += $bp;
	  $month_counts_submitted{$month}{all}{jobs} += 1;
	  if ( $public )
	  {
	      $month_counts_submitted{$month}{public}{bp} += $bp;
	      $month_counts_submitted{$month}{public}{jobs} += 1;
	  }

	  if ( $self->data('display_jobs') eq 'active' and 
	       $last_stage_name eq 'done' and $last_stage_status eq 'completed' and $viewable == 1 )
	  {
	      $month_counts_completed{$month}{all}{bp}   += $bp;
	      $month_counts_completed{$month}{all}{jobs} += 1;
	      if ( $public )
	      {
		  $month_counts_completed{$month}{public}{bp} += $bp;
		  $month_counts_completed{$month}{public}{jobs} += 1;
	      }
	  }
      }
  }

  # leaving out public job counts for now
  my $data_c = [];

  if ( $self->data('display_jobs') eq 'active' )
  {
      foreach my $month ( sort keys %month_counts_completed )
      {
	  my $all_gbp = sprintf("%.2f", $month_counts_completed{$month}{all}{bp}/1000000000);
	  #my $pub_gbp = sprintf("%.2f", $month_counts_completed{$month}{public}{bp});
	  
	  push @$data_c, [$month, $month_counts_completed{$month}{all}{jobs}, $all_gbp];
      }
  }

  my $data_d = [];

  foreach my $month ( sort keys %month_counts_submitted )
  {
      my $all_gbp = sprintf("%.2f", $month_counts_submitted{$month}{all}{bp}/1000000000);
      #my $pub_gbp = sprintf("%.2f", $month_counts_completed{$month}{public}{bp});
      
      push @$data_d, [$month, $month_counts_submitted{$month}{all}{jobs}, $all_gbp];
  }

  my $table_c;
  if ( $self->data('display_jobs') eq 'active' )
  {
      $table_c = $self->application->component('JobsMonthCompleted');
#  my $data_c  = $mgrast_dbh->selectall_arrayref("select substring(created_on,1,7) as Date, count(job_id) as Jobs from Job where job_id is not NULL group by Date");
#  my ($pie_c, $div_c) = &get_piechart("pie_c", "Jobs per Month", ['Month', 'Jobs'], $data_c, 20);

      $table_c->width(850);
      if ( scalar(@$data_c) > 25 ) {
	  $table_c->show_top_browse(1);
	  $table_c->show_bottom_browse(1);
	  $table_c->items_per_page(25);
	  $table_c->show_select_items_per_page(1); 
      }
      $table_c->columns([ { name => 'Month', sortable => 1 },
			  { name => 'Jobs Completed', sortable => 1 },
			  { name => 'Size (Gbp)', sortable => 1 },
			  ]);    
      $table_c->data($data_c);
      $table_c->show_export_button({title => 'export', strip_html => 1});
  }

  my $table_d = $self->application->component('JobsMonthSubmitted');

  $table_d->width(850);
  if ( scalar(@$data_d) > 25 ) {
    $table_d->show_top_browse(1);
    $table_d->show_bottom_browse(1);
    $table_d->items_per_page(25);
    $table_d->show_select_items_per_page(1); 
  }
  $table_d->columns([ { name => 'Month', sortable => 1 },
		      { name => 'Jobs Submitted', sortable => 1 },
		      { name => 'Size (Gbp)', sortable => 1 },
		    ]);    
  $table_d->data($data_d);
  $table_d->show_export_button({title => 'export', strip_html => 1});

  $html .= $pie_usr . $pie_job . $pie_gbp;

  $html .= "<h2>&raquo; Funding sources (" . scalar(@$data_b) . ")</h2>\n";
  $html .= $self->input_button('funding_source_user_chart_button', 'funding_source_user_chart', 'show user chart', 'hide user chart');
  $html .= $self->input_button('funding_source_job_chart_button', 'funding_source_job_chart', 'show job chart', 'hide job chart');
  $html .= $self->input_button('funding_source_gbp_chart_button', 'funding_source_gbp_chart', 'show gbp chart', 'hide gbp chart');
  $html .= $self->input_button('funding_source_table_button', 'funding_source_table', 'show table', 'hide table');
  $html .= "<div id='funding_source_table' style='display:none'>" . $table_b->output . "</div>\n";
  $html .= $div_usr;
  $html .= $div_job;
  $html .= $div_gbp;

  my $all_jobs_completed_chart = '';
  if ( $self->data('display_jobs') eq 'active' )
  {
      my $div_id    = 'columnchart_all_jobs_completed';
      my $button_id = 'columnchart_all_jobs_completed_button';
      $html .= $self->google_columnchart_all_jobs($div_id, $data_c, $button_id);
      
      $all_jobs_completed_chart = "
<table>
<tr>
<td align='left'>
<form><input id='$button_id' type='button' value='switch to jobs completed count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='$div_id'></div>
</td>
</tr>
</table>
";
  }

  my $div_id    = 'columnchart_all_jobs_submitted';
  my $button_id = 'columnchart_all_jobs_submitted_button';
  $html .= $self->google_columnchart_all_jobs($div_id, $data_d, $button_id);

  my $all_jobs_submitted_chart = "
<table>
<tr>
<td align='left'>
<form><input id='$button_id' type='button' value='switch to jobs submitted count chart'></input></form>
</td>
</tr>
<tr>
<td>
<div id='$div_id'></div>
</td>
</tr>
</table>
";

  $html .= "<h2>&raquo; Monthly Jobs History (based on creation date)</h2>\n";

  if ( $self->data('display_jobs') eq 'active' )
  {
      $html .= $self->input_button('all_jobs_completed_chart_button', 'all_jobs_completed_chart', 'show jobs completed chart', 'hide jobs completed chart');
      $html .= $self->input_button('monthly_jobs_completed_table_button', 'monthly_jobs_completed_table', 'show jobs completed table', 'hide jobs completed table');
  }

  $html .= $self->input_button('all_jobs_submitted_chart_button', 'all_jobs_submitted_chart', 'show jobs submitted chart', 'hide jobs submitted chart');
  $html .= $self->input_button('monthly_jobs_submitted_table_button', 'monthly_jobs_submitted_table', 'show jobs submitted table', 'hide jobs submitted table');

  if ( $self->data('display_jobs') eq 'active' )
  {
      $html .= "<div id='all_jobs_completed_chart' style='display:none'>".$all_jobs_completed_chart."</div>\n";
      $html .= "<div id='monthly_jobs_completed_table' style='display:none'>" . $table_c->output . "</div>\n";
  }

  $html .= "<div id='all_jobs_submitted_chart' style='display:none'>".$all_jobs_submitted_chart."</div>\n";
  $html .= "<div id='monthly_jobs_submitted_table' style='display:none'>" . $table_d->output . "</div>\n";

  $html .= "<br><br><br>";
  
  return $html;
}

sub input_button {
    my($self, $id, $div_id, $text_1, $text_2) = @_;

    my $color_1 = '#000000';
    my $color_2 = '#045A8D';
    
    return qq(<input type='button' value='$text_1' id='$id' onclick='if(document.getElementById("$div_id").style.display=="none"){document.getElementById("$div_id").style.display=""; document.getElementById("$id").value="$text_2"; document.getElementById("$id").style.color="$color_2";}else{document.getElementById("$div_id").style.display="none"; document.getElementById("$id").value="$text_1"; document.getElementById("$id").style.color="$color_1";}'>\n);
}

sub googleviz {
    my($self, $div_name, $chart_title, $x_name, $y_name, $y_log_scale, $color, $data) = @_;

    my $n_data_points = scalar @$data;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var data = new google.visualization.DataTable();
    data.addColumn('string', 'Hour');
    data.addColumn('number', '$y_name');
    data.addRows($n_data_points);
END

    for (my $i=0; $i<$n_data_points; $i++)
    #for (my $i=0; $i<=23; $i++)
    {
	my($txt, $val) = ('', '');
	if ( ref($data->[$i]) eq 'ARRAY' )
	{
	    ($txt,$val) = @{ $data->[$i] } ;
	}
	else
	{
	    $txt = $i;
	    $val = $data->[$i];
	}

	$js .= <<END;
    data.setValue($i, 0, '$txt');
    data.setValue($i, 1, $val);
END
    }
    
    $js .= <<END;
    var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
    chart.draw(data, {width: 500, 
                      height: 240, 
                      legend: 'none',
END

    if ( $y_log_scale )
    {
	$js .= <<END;
                      vAxis: {logScale: 'true'}
END
    }

    if ( $color )
    {
	$js .= <<END;
                      colors: ['$color'],
END
    }

    $js .= <<END;
                      title: '$chart_title',
                      hAxis: {showTextEvery: 2},
                     });
  }
</script>
END

    return $js;
}

sub google_columnchart_bp {
    my($self, $div_name, $data) = @_;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var data = new google.visualization.DataTable();
    data.addColumn('string', 'Date');
    data.addColumn('number', 'done');
    data.addColumn('number', 'running');
    data.addColumn('number', 'deleted');
    data.addColumn('number', 'error');
    data.addRows([
END
    
    foreach my $date ( sort keys %$data )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;
	
	my $gbp_done    = $self->bp2gbp($data->{$date}{done});
	my $gbp_running = $self->bp2gbp($data->{$date}{running});
	my $gbp_deleted = $self->bp2gbp($data->{$date}{deleted});
	my $gbp_error   = $self->bp2gbp($data->{$date}{error});

	$js .= "['$d', $gbp_done, $gbp_running, $gbp_deleted,  $gbp_error],\n";
    }

    $js .= <<END;
		  ]);

    var options = {
title: 'Basepairs uploaded',
width: 800,
height: 400,
hAxis: {title: 'Date', showTextEvery: 2},
vaxis: {title: 'bp'},
isStacked: 1,
};		  

    var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
    chart.draw(data, options);
  }
</script>
END

    return $js;
}

sub google_columnchart_month_jobs {
    my($self, $div_name, $jobs_bp, $jobs_count) = @_;
    
    my $jobs_bp_total    = 0;
    my $jobs_count_total = 0;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChartfunc);

    function drawChartfunc() {
  var data1 = [['date', 'done', 'running', 'deleted', 'error'],
END

  foreach my $date ( sort keys %$jobs_bp )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;
	
	my $gbp_done    = $self->bp2gbp($jobs_bp->{$date}{done});
	my $gbp_running = $self->bp2gbp($jobs_bp->{$date}{running});
	my $gbp_deleted = $self->bp2gbp($jobs_bp->{$date}{deleted});
	my $gbp_error   = $self->bp2gbp($jobs_bp->{$date}{error});

	$js .= "['$d', $gbp_done, $gbp_running, $gbp_deleted,  $gbp_error],\n";
	$jobs_bp_total += $jobs_bp->{$date}{done} + $jobs_bp->{$date}{running} + $jobs_bp->{$date}{deleted} + $jobs_bp->{$date}{error};
    }

    $js .= <<END;
  ];

  var data2 = [['date', 'done', 'running', 'deleted', 'error'],
END

    foreach my $date ( sort keys %$jobs_count )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;
	
	$js .= "['$d', $jobs_count->{$date}{done}, $jobs_count->{$date}{running}, $jobs_count->{$date}{deleted}, $jobs_count->{$date}{error}],\n";
	$jobs_count_total += $jobs_count->{$date}{done} + $jobs_count->{$date}{running} + $jobs_count->{$date}{deleted} + $jobs_count->{$date}{error};
    }

    $jobs_bp_total    = $self->bp2gbp($jobs_bp_total);	       
    $jobs_count_total = $self->add_commas($jobs_count_total);
	       
    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
height: 700,
width: 1200,
colors: ['#1A9641', '#A6D96A', '#FDAE61', '#D7191C'],
hAxis: {title: 'Job Creation Date', textStyle: {fontSize:11}, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 10}, viewWindowMode: 'maximized', textStyle: {fontSize:11}},
isStacked: 1,
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
  var button = document.getElementById('columnchart_month_jobs_button');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'job size' : 'job count') + ' chart';
      });

      options['title'] = (current ? 'Number of jobs created ($jobs_count_total)' : 'Size of jobs created in Gbp ($jobs_bp_total)');

      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;
  drawChart();
  }
}
</script>
END

    return $js;
}

sub google_columnchart_today_jobs {
    my($self, $div_name, $jobs_bp, $jobs_count) = @_;

    my $jobs_bp_total    = 0;
    my $jobs_count_total = 0;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChartfunc);

    function drawChartfunc() {
  var data1 = [['hour', 'done', 'running', 'deleted', 'error'],
END

    foreach my $hour ( sort {$a <=> $b} keys %$jobs_bp )
    {		
	my $gbp_done    = $self->bp2gbp($jobs_bp->{$hour}{done});
	my $gbp_running = $self->bp2gbp($jobs_bp->{$hour}{running});
	my $gbp_deleted = $self->bp2gbp($jobs_bp->{$hour}{deleted});
	my $gbp_error   = $self->bp2gbp($jobs_bp->{$hour}{error});

	my $txt = join('-', $hour, $hour+1);
	$js .= "['$txt', $gbp_done, $gbp_running, $gbp_deleted,  $gbp_error],\n";

	$jobs_bp_total += $jobs_bp->{$hour}{done} + $jobs_bp->{$hour}{running} + $jobs_bp->{$hour}{deleted} + $jobs_bp->{$hour}{error};
    }

    $js .= <<END;
  ];

  var data2 = [['hour', 'done', 'running', 'deleted', 'error'],
END

    foreach my $hour ( sort {$a <=> $b} keys %$jobs_count )
    {		
	my $txt = join('-', $hour, $hour+1);
	$js .= "['$txt', $jobs_count->{$hour}{done}, $jobs_count->{$hour}{running}, $jobs_count->{$hour}{deleted}, $jobs_count->{$hour}{error}],\n";
	$jobs_count_total += $jobs_count->{$hour}{done} + $jobs_count->{$hour}{running} + $jobs_count->{$hour}{deleted} + $jobs_count->{$hour}{error};
    }

    $jobs_bp_total    = $self->bp2gbp($jobs_bp_total);	       
    $jobs_count_total = $self->add_commas($jobs_count_total);
	       
    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
height: 700,
width: 1200,
colors: ['#1A9641', '#A6D96A', '#FDAE61', '#D7191C'],
hAxis: {title: 'Job Creation Time (today)', textStyle: {fontSize:11}, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 10}, viewWindowMode: 'maximized', textStyle: {fontSize:11}},
isStacked: 1,
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
  var button = document.getElementById('columnchart_today_jobs_today_button');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'job size' : 'job count') + ' chart';
      });

      options['title'] = (current ? 'Number of jobs created ($jobs_count_total)' : 'Size of jobs created in Gbp ($jobs_bp_total)');
      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;
  drawChart();
  }
}
</script>
END

    return $js;
}

sub google_columnchart_incomplete_jobs {
    my($self, $div_name, $jobs_bp, $jobs_count) = @_;
    
    my $jobs_bp_total    = 0;
    my $jobs_count_total = 0;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChartfunc);

    function drawChartfunc() {
  var data1 = [['date', 'running', 'error'],
END

  foreach my $date ( sort keys %$jobs_bp )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;

	$jobs_bp->{$date}{running} ||= 0;
	$jobs_bp->{$date}{error}   ||= 0;

	my $gbp_running = $self->bp2gbp($jobs_bp->{$date}{running});
	my $gbp_error   = $self->bp2gbp($jobs_bp->{$date}{error});

	$js .= "['$d', $gbp_running, $gbp_error],\n";
	$jobs_bp_total += $jobs_bp->{$date}{running} + $jobs_bp->{$date}{error};
    }

    $js .= <<END;
  ];

  var data2 = [['date', 'running', 'error'],
END

    foreach my $date ( sort keys %$jobs_count )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;

	$jobs_count->{$date}{running} ||= 0;
	$jobs_count->{$date}{error}   ||= 0;
	
	$js .= "['$d', $jobs_count->{$date}{running}, $jobs_count->{$date}{error}],\n";
	$jobs_count_total += $jobs_count->{$date}{running} + $jobs_count->{$date}{error};
    }

    $jobs_bp_total    = $self->bp2gbp($jobs_bp_total);	       
    $jobs_count_total = $self->add_commas($jobs_count_total);
	       
    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
height: 700,
width: 1200,
colors: ['#A6D96A', '#D7191C'],
hAxis: {title: 'Job Creation Date (non-contiguous)', textStyle: {fontSize:11}, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 1}, viewWindowMode: 'maximized', textStyle: {fontSize:11}},
isStacked: 1,
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
  var button = document.getElementById('columnchart_incomplete_jobs_button');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'job size' : 'job count') + ' chart';
      });

      options['title'] = (current ? 'Number of incomplete jobs ($jobs_count_total) excluding today' : 'Size of incomplete jobs in Gbp ($jobs_bp_total) excluding today');

      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;
  drawChart();
  }
}
</script>
END

    return $js;
}

sub google_columnchart_pipeline_jobs {
    my($self, $div_name, $pipeline_jobs) = @_;

    my $complete_jobs_bp      = $pipeline_jobs->{done}{completed}{bp};
    my $complete_jobs_count   = $pipeline_jobs->{done}{completed}{count};
    my $incomplete_jobs_bp    = 0;
    my $incomplete_jobs_count = 0;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChartfunc);

    function drawChartfunc() {
  var data1 = [['stage', 'error', 'running', 'completed'],
END

    foreach my $stage ( @{ $self->{mgstat}->pipeline_stages_ordered() } )
    {
	my @val = ();
	foreach my $status ( 'error', 'running', 'completed' )
	{
	    my $bp = $pipeline_jobs->{$stage}{$status}{bp} || 0;
	    $incomplete_jobs_bp += $bp;

	    if ( $stage eq 'done' and $status eq 'completed' )
	    {
		push @val, 0;
	    }
	    else
	    {
		push @val, $bp;
	    }
	}
	
	$js .= "['$stage', " . join(', ', @val) . "],\n";
    }

    $incomplete_jobs_bp -= $complete_jobs_bp;

    $js .= <<END;
  ];

  var data2 = [['stage', 'error', 'running', 'completed'],
END

    foreach my $stage ( @{ $self->{mgstat}->pipeline_stages_ordered() } )
    {
	my @val = ();
	foreach my $status ( 'error', 'running', 'completed' )
	{
	    my $job_count = $pipeline_jobs->{$stage}{$status}{count} || 0;
	    $incomplete_jobs_count += $job_count;

	    if ( $stage eq 'done' and $status eq 'completed' )
	    {
		push @val, 0;
	    }
	    else
	    {
		push @val, $job_count;
	    }
	}
	
	$js .= "['$stage', " . join(', ', @val) . "],\n";
    }

    $incomplete_jobs_count -= $complete_jobs_count;

    my $complete_jobs_gbp   = $self->bp2gbp($complete_jobs_bp);	       
    my $incomplete_jobs_gbp = $self->bp2gbp($incomplete_jobs_bp);	       

    $complete_jobs_count   = $self->add_commas($complete_jobs_count);
    $incomplete_jobs_count = $self->add_commas($incomplete_jobs_count);
	       
    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
height: 700,
width: 1200,
colors: ['#D7191C', '#A6D96A', '#1A9641'],
hAxis: {title: 'Pipeline Stage', textStyle: {fontSize:11}, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 1}, viewWindowMode: 'maximized', textStyle: {fontSize:11}, logScale: true},
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
  var button = document.getElementById('columnchart_pipeline_jobs_button');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'job size' : 'job count') + ' chart';
      });

      options['title'] = (current ? 'Number of jobs in the pipeline ($incomplete_jobs_count)' : 'Size of jobs in the pipeline in basepairs ($incomplete_jobs_gbp Gbp)');

      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;

  if (current) {
      options.vAxis.logScale = false;
  } else {
      options.vAxis.logScale = true;
  }

  drawChart();
  }
}
</script>
END

    return $js;
}

sub google_columnchart_new_users {
    my($self, $div_id, $new_users) = @_;

    my $new_users_total = 0;
 
    my $js = <<END;
    <script type="text/javascript">
    google.load("visualization", "1", {packages:["corechart"]});
    google.setOnLoadCallback(drawChart);
    function drawChart() {
        var data = new google.visualization.DataTable();
        data.addColumn('string', 'date');
        data.addColumn('number', 'new users');
        data.addRows([
END

    foreach my $date ( sort keys %$new_users )
    {		
	my $d = substr($date, 5, 5);
	$d =~ s/^0*//;
	
	$js .= "['$d', $new_users->{$date}],\n";
	$new_users_total += $new_users->{$date};
    }

    $js .= <<END;		      
        ]);

  var options = {
title: 'New users registered',
height: 700,
width: 1200,
colors: ['#2B83BA'],
hAxis: {title: 'Date', textStyle: {fontSize:11}, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 1}, viewWindowMode: 'maximized'},
};		  
        var chart = new google.visualization.ColumnChart(document.getElementById('$div_id'));
        chart.draw(data, options);
    }
    </script>
END

    return $js;
}

sub google_columnchart_all_jobs {
    my($self, $div_name, $data, $button_id) = @_;
    
    #  @$data_c = [ [$month, $n_jobs, $n_gbp], [...], ...]

    my $jobs_gbp_total   = 0;
    my $jobs_count_total = 0;

    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChartfunc);

    function drawChartfunc() {
  var data1 = [['month', 'size (Gbp)'],
END

  foreach my $rec ( @$data )
  {
      my($month, $n_jobs, $n_gbp) = @$rec;
      
      $js .= "['$month', $n_gbp],\n";
      $jobs_gbp_total   += $n_gbp;
      $jobs_count_total += $n_jobs;
  }
	       
  $js .= <<END;
  ];

  var data2 = [['month', '# jobs'],
END

    foreach my $rec ( @$data )
    {		
	my($month, $n_jobs, $n_gbp) = @$rec;
	
	$js .= "['$month', $n_jobs],\n";
    }
	       
#colors: ['#1A9641', '#A6D96A', '#FDAE61', '#D7191C'],


    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
height: 700,
width: 1200,
colors: ['#1A9641', '#D7191C', '#A6D96A'],
hAxis: {title: 'Job Creation Date', textStyle: {fontSize:11}, showTextEvery: 3, slantedText: true},
vAxis: {viewWindow: {min: 0, max: 1}, viewWindowMode: 'maximized', textStyle: {fontSize:11}, logScale: 'true'},
isStacked: 1,
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.ColumnChart(document.getElementById('$div_name'));
  var button = document.getElementById('$button_id');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'job size' : 'job count') + ' chart';
      });

      options['title'] = (current ? 'Number of jobs ($jobs_count_total)' : 'Size of jobs in Gbp ($jobs_gbp_total)');

      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;
  drawChart();
  }
}
</script>
END

    return $js;
}

sub google_geochart_users {
    my($self, $div_name, $countries, $current_countries) = @_;
    
    my $js = <<END;
<script type="text/javascript">
  google.load("visualization", "1", {packages:["geochart"]});
  google.setOnLoadCallback(drawGeoMap);

    function drawGeoMap() {
  var data1 = [['country', 'users'],
END

  foreach my $country ( keys %$countries )
    {		
	$js .= "['$country', $countries->{$country}],\n";
    }

    $js .= <<END;
  ];

  var data2 = [['country', 'users'],
END

  foreach my $country ( keys %$current_countries )
    {		
	$js .= "['$country', $current_countries->{$country}],\n";
    }

    $js .= <<END;
  ];

  var data = [];
  data[0] = google.visualization.arrayToDataTable(data1);		   
  data[1] = google.visualization.arrayToDataTable(data2);		   

  var options = {
width: 1000,
keepAspectRatio: true,
animation:{
  duration: 1000,
  easing: 'out'
  },
};		  

  var current = 0;
  var chart = new google.visualization.GeoChart(document.getElementById('$div_name'));
  var button = document.getElementById('geochart_users_button');

  function drawChart() {
    // Disabling the button while the chart is drawing.
    button.disabled = true;
    google.visualization.events.addListener(chart, 'ready',
      function() {
        button.disabled = false;
        button.value = 'switch to ' + (current ? 'all users' : 'todays users');
      });

      options['title'] = (current ? 'Number of users' : 'Number of users');

      chart.draw(data[current], options);
  }

  drawChart();

  button.onclick = function() {
  current = 1 - current;
  drawChart();
  }
}
</script>
END

    return $js;
}

sub bp2gbp {
    my($self, $bp) = @_;

    if ( defined $bp )
    {
	my $gbp = $bp/1000000000;
	$gbp =~ s/\.0*$//;
	
	if ( $gbp =~ /^\d+$/ || $gbp == 0 )
	{
	    return $gbp;
	}
	elsif ( $gbp >= 1 ) 
	{
	    return sprintf("%.2f", $gbp);
	} 
	else 
	{
	    return sprintf("%.2e", $gbp);
	}
    }
    else
    {
	return undef;
    }
}

sub google_gauge {
    my($self, $div_name, $value) = @_;

    my $js = <<END;
<script type='text/javascript'>
  google.load('visualization', '1', {packages:['gauge']});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var data = new google.visualization.DataTable();
    data.addColumn('number');
    data.addRows([
                   [$value],
		 ]);

    var options = {
	            width: 300, height: 175,
	            minorTicks: 1,
	            majorTicks: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
	          };

    var chart = new google.visualization.Gauge(document.getElementById('$div_name'));
    chart.draw(data, options);
  }
</script>
END

    return $js;
}

sub job_details {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $jid = $cgi->param('job');
  my $dbmaster = $application->dbmaster;
  my $mgrast = $application->data_handle('MGRAST');

  unless ($jid) {
    return "no job selected";
  }

  my $job = $mgrast->Job->init( { job_id => $jid } );
  my $stages = $mgrast->Job->get_stages_fast($jid);

  if (open(FH, $job->dir."/logs/pipeline.log")) {
    my $log = "";
    while (<FH>) {
      $log = $_.$log;
    }
    close FH;
    return "<pre>".$log."</pre>";
  } else {
    return "could not open pipeline logfile: $! @!";
  }
}

sub user_details {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $ulogin = $cgi->param('user');
  my $dbmaster = $application->dbmaster;
  my $mgrast = $application->data_handle('MGRAST');

  unless ($ulogin) {
    return "no user selected";
  }

  my $user = $dbmaster->User->init( { login => $ulogin } );

  unless (ref($user)) {
    return "user $ulogin not found in the database";
  }

  my $html = "<strong>Details for ".$user->firstname." ".$user->lastname."</strong><br>";

  $html .= "<table><tr><th>login</th><td>".$user->{login}."</td></tr>";
  $html .= "<tr><th>e-mail</th><td>".$user->{email}."</td></tr>";
  $html .= "<tr><th>registered</th><td>".$user->{entry_date}."</td></tr>";
  $html .= "</table>";

  $html .= "<br><input type='button' value='impersonate' onclick='window.top.location=\"?page=AccountManagement&action=impersonate_user&login=".$user->{login}."\";'>";

  my $ujobs_table = $application->component('ujobs_table');
  my $urights = $dbmaster->Rights->get_objects( { scope => $user->get_user_scope, data_type => 'metagenome' } );
  my $data = [];
  my $js = {};
  foreach my $right (@$urights) {
    next unless ($right->{data_id});
    unless (exists($js->{$right->{data_id}})) {
      $js->{$right->{data_id}} = [ $right->{data_id}, 'no', 'no', 'no', 0, 'yes' ];
    }
    if ($right->{name} eq 'edit') {
      $js->{$right->{data_id}}->[2] = 'yes';
    } elsif ($right->{name} eq 'view') {
      $js->{$right->{data_id}}->[1] = 'yes';
    }
  }
  my @jobinfo = $mgrast->Job->get_jobs_for_user_fast($user, 'view');
  foreach my $info (@jobinfo) {
    next unless ($info->{metagenome_id});
    unless (exists($js->{$info->{metagenome_id}})) {
      $js->{$info->{metagenome_id}} = [ $info->{metagenome_id}, 'yes', 'yes', 'no', 0, 'no' ];
    }
    $js->{$info->{metagenome_id}}->[3] = $info->{viewable} ? 'yes' : 'no';
    if ($info->{viewable}) {
      $js->{$info->{metagenome_id}}->[0] = "<a href='?page=MetagenomeOverview&metagenome=".$info->{metagenome_id}."' target=_blank>".$info->{metagenome_id}."</a>";
    }
    $js->{$info->{metagenome_id}}->[4] = $info->{job_id};
  }
  @$data = sort { $b->[4] <=> $a->[4] } values(%$js);
  $ujobs_table->show_top_browse(1);
  $ujobs_table->show_bottom_browse(1);
  $ujobs_table->show_clear_filter_button(1);
  $ujobs_table->items_per_page(20);
  $ujobs_table->show_select_items_per_page(1);
  $ujobs_table->columns( [ { name => 'mgid', filter => 1, sortable => 1 }, { name => 'view', filter => 1, sortable => 1  , operator => 'combobox'}, { name => 'edit', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'viewable', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'jid', filter => 1, sortable => 1 }, { name => 'explicit', filter => 1, sortable => 1, operator => 'combobox' } ] );
  $ujobs_table->data($data);

  my $ujobs_out = scalar(@$data) ? $ujobs_table->output() : 'no access to private metagenomes';

  $html .= "<br><br><br><strong>Access to Metagenomes</strong><br>".$ujobs_out;

  return $html;
}

sub add_commas {
    my($self, $n) = @_;
    # from perl cookbook

    if ( defined $n )
    {
	my $text = reverse $n;
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $text;
    }
}

sub get_piechart {
  my($id, $title, $cols, $data, $left, $width) = @_;

  my $display = [];

# pie slices less than half a degree get lumped into the 'Other' category in the chart by google, we are going to bypass that
  my $total = 0;
  foreach my $rec ( @$data )
  {
      $total += $rec->[1];
  }
  my $cutoff = $total/720;  

  my $other = 0;
  foreach my $rec ( sort {$b->[1] <=> $a->[1]} @$data )
  {
      my $value = $rec->[1] || 0;

      if ( $value > $cutoff )
      {
	  push @$display, $rec;
      }
      else
      {
	  $other += $value;
      }
  }

  push @$display, ['other', sprintf("%.1f", $other)];
  
  $width ||= 500;
  my $rows = "";
  foreach my $rec ( @$display )
  {
      $rows .= 'data.addRow(["' . $rec->[0] . '", ' . $rec->[1] . "]);\n";
  }

  my $pie  = qq~
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart","geochart"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var data  = new google.visualization.DataTable();
        data.addColumn('string', '$cols->[0]');
        data.addColumn('number', '$cols->[1]');
        $rows
        var chart = new google.visualization.PieChart(document.getElementById('$id'));
        chart.draw(data, {width: $width, height: $width, chartArea: {left:$left, width:"90%"}, title: '$title'});
      }
    </script>
~;

  return ($pie, "<div id='$id' style='display:none'></div>");
}

sub google_piechart {
  my ($self, $div_id, $title, $cols, $data, $left) = @_;

  my $num  = scalar @$data;
  my $rows = join("\n", map { qq(data.addRow(["$_->[0]", $_->[1]]);) } sort { $b->[1] <=> $a->[1] } @$data);
  my $js   = qq~
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart","geochart"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var data  = new google.visualization.DataTable();
        data.addColumn('string', '$cols->[0]');
        data.addColumn('number', '$cols->[1]');
        $rows
        var chart = new google.visualization.PieChart(document.getElementById('$div_id'));
        chart.draw(data, {width: 800, height: 800, chartArea: {left:$left, width:"100%"}, title: '$title'});
      }
    </script>
~;

  return $js;
}

sub formatted_date {
    
    my %long = (
		'Mon' => 'Monday',
		'Tue' => 'Tuesday',
		'Wed' => 'Wednesday',
		'Thu' => 'Thursday',
		'Fri' => 'Friday',
		'Sat' => 'Saturday',
		'Sun' => 'Sunday',
 		'Jan' => 'January',
 		'Feb' => 'February',
 		'Mar' => 'March',
 		'Apr' => 'April',
 		'May' => 'May',
 		'Jun' => 'June',
 		'Jul' => 'July',
 		'Aug' => 'August',
 		'Sep' => 'September',
 		'Oct' => 'October',
 		'Nov' => 'November',
 		'Dec' => 'December',
		);

    my($day, $month, $date, $time, $year) = split(/\s+/, scalar localtime);
    
    $day   = exists $long{$day}? $long{$day} : $day;
    $month = exists $long{$month}? $long{$month} : $month;
    
    return "$time $day, $date $month $year, CST";
}

sub require_css {
  return [ ];
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/MGRASTAdmin.js", "$Conf::cgi_url/Html/rgbcolor.js", "https://www.google.com/jsapi" ];
}

sub required_rights {
  return [ [ 'edit', 'user', '*' ] ];
}
