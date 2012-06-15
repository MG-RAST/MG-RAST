package MGRAST::WebPage::MGRASTAdmin;

use base qw( WebPage );

use strict;
use warnings;
no warnings qw(uninitialized);

use WebComponent::WebGD;
use WebConfig;
use Data::Dumper;
use Config;
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

  $self->title("Admin");

  $self->application->register_component('Table', 'user_table');
  $self->application->register_component('Table', 'ujobs_table');
  $self->application->register_component('Table', 'alljobs_table');
  $self->application->register_component('Table', 'organization_table');
  $self->application->register_component('Table', 'average_size_table');
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('Table', 'FundingSources');
  $self->application->register_component('Table', 'FundingSourcesClean');
  $self->application->register_component('Table', 'JobsMonth');

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
  my $html = "";
  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
      $html .= "<h2>The MG-RAST is currently offline. You are the admin, fix it!</h2>";
      return $html;
  }
  $self->{mgrast} = $mgrast;

  $html .= $application->component('ajax')->output();

  # thirtyone days
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

# users section
#  my $dbh = $dbmaster->db_handle;
#  my $sth = $dbh->prepare("SELECT User._id, User.firstname, User.lastname, User.login, User.email, User.entry_date, Organization.country FROM User LEFT OUTER JOIN (Organization, OrganizationUsers) ON Organization._id=OrganizationUsers.organization AND User._id=OrganizationUsers.user");
#  $sth->execute;
#  my $users = $sth->fetchall_arrayref();

  my $mgusers = $self->{mgstat}->user();
  my $mgorgs  = $self->{mgstat}->organization();
  my $mgjobs  = $self->{mgstat}->job();

  my $jobs_created_today_count     = $self->{mgstat}->jobs_created_today_count();
  my $jobs_created_today_24h_count = $self->{mgstat}->jobs_created_today_24h_count();
  my $jobs_created_today_bp        = $self->{mgstat}->jobs_created_today_bp();
  my $jobs_created_today_24h_bp    = $self->{mgstat}->jobs_created_today_24h_bp();

  my $jobs_completed_today_count     = $self->{mgstat}->jobs_completed_today_count();
  my $jobs_completed_today_24h_count = $self->{mgstat}->jobs_completed_today_24h_count();
  my $jobs_completed_today_bp        = $self->{mgstat}->jobs_completed_today_bp();
  my $jobs_completed_today_24h_bp    = $self->{mgstat}->jobs_completed_today_24h_bp();
  
  my $js_jobs_today_1 = $self->googleviz('div_jobs_today_1', "# jobs created today: $jobs_created_today_count", 'hour', '# jobs', 0, '', $jobs_created_today_24h_count);
  my $js_jobs_today_2 = $self->googleviz('div_jobs_today_2', 'bp for jobs created today: ' . $self->add_commas($jobs_created_today_bp), 'hour', 'bp', 0, 'green', $jobs_created_today_24h_bp);

  my $js_jobs_today_3 = $self->googleviz('div_jobs_today_3', "# jobs completed today: $jobs_completed_today_count", 'hour', '# jobs', 0, '', $jobs_completed_today_24h_count);
  my $js_jobs_today_4 = $self->googleviz('div_jobs_today_4', 'bp for jobs completed today: ' . $self->add_commas($jobs_completed_today_bp), 'hour', 'bp', 0, 'green', $jobs_completed_today_24h_bp);

  my $qwe = "<table><tr>\n";
  $qwe .= "<td>$js_jobs_today_1\n<div id='div_jobs_today_1'></div></td>\n";
  $qwe .= "<td>$js_jobs_today_2\n<div id='div_jobs_today_3'></div></td>\n";
  $qwe .= "</tr>\n";

  $qwe .= "<tr>\n";
  $qwe .= "<td>$js_jobs_today_3\n<div id='div_jobs_today_2'></div></td>\n";
  $qwe .= "<td>$js_jobs_today_4\n<div id='div_jobs_today_4'></div></td>\n";
  $qwe .= "</tr>\n";
  $qwe .= "</table>\n";


  my $pipeline_jobs = $self->{mgstat}->pipeline_jobs_count();

  $qwe .= "<table><tr><th rowspan=2 valign='middle'>Pipeline Stage</th><th colspan=2 align='center'>Status 'error'</th><th colspan=2 align='center'>Status 'running'</th><th colspan=2 align='center'>Status 'completed'</th></tr>\n";
  $qwe .= "<tr><th># jobs</th><th align='center'>bp</th><th># jobs</th><th align='center'>bp</th><th># jobs</th><th align='center'>bp</th>\n";
  foreach my $stage ( @{ $self->{mgstat}->pipeline_stages_ordered() } )
  {
      $qwe .= "<tr><th>$stage</th>\n";

      foreach my $status ( 'error', 'running', 'completed' )
      {
	  $qwe .= "<td align='right'>$pipeline_jobs->{$stage}{$status}{count}</td><td align='right'>" . $self->add_commas($pipeline_jobs->{$stage}{$status}{bp}) . "</td>\n";
      }
      
      $qwe .= "</tr>";
  }

  $qwe .= "</table><p>\n";
  
  my $uhash = {};
#  %$uhash = map { $_->[0] => $_ } @$users;
  my $data = [];
  my $countries = {};
  my $current_countries = {};

#  my $recent_users = $self->{mgstat}->recent_user_page($thirtyone_days->[30]. ' 00:00:00');

  # current users
#  my $today_users_registered = $user_dbh->selectall_arrayref("select user, current_page from UserSession where timestamp > '".$thirtyone_days->[30]." 00:00:00' and user is not null");
  my $today_users_registered = $self->{mgstat}->active_users($thirtyone_days->[30]. ' 00:00:00');
  
#  my $today_users = $user_dbh->selectall_arrayref("select count(*) from UserSession where timestamp > '".$thirtyone_days->[30]." 00:00:00'");
  my $n_today_users = "blah"; #$self->{mgstat}->number_of_recent_users($thirtyone_days->[30]. ' 00:00:00');

  my %page_count;
  foreach my $_id_user ( @$today_users_registered )
  {
      my $page = $mgusers->{$_id_user}{last_page} || 'Home';
      $page_count{$page}++;
  }

  my $data_page_count = [];
  @$data_page_count = map {[$_, $page_count{$_}]} sort {$page_count{$b} <=> $page_count{$a}} keys %page_count;
  
  my ($pie_pc, $div_pc) = &get_piechart("pie_pc", "Page Counts:", ['Page', 'Count'], $data_page_count, 20);

  my $user_html .= "<b>Registered users online today: " . scalar(@$today_users_registered) . "</b>";
  $user_html .= $div_pc;
#  $user_html .= "<br>".join("<br>", map { $mgusers->{$_}->{firstname}." ".$mgusers->{$_}->{lastname}." last on page ".($mgusers->{$_}->{last_page} || "Home") } sort { lc $mgusers->{$a}->{lastname} cmp lc $mgusers->{$b}->{lastname} ||lc  $mgusers->{$a}->{firstname} cmp lc $mgusers->{$b}->{firstname} } @$today_users_registered);

  $user_html .= "<table border='0' cellspacing='0' cellpadding='0'>\n";
  foreach my $_id_user ( sort { lc $mgusers->{$a}->{lastname} cmp lc $mgusers->{$b}->{lastname} ||lc  $mgusers->{$a}->{firstname} cmp lc $mgusers->{$b}->{firstname} } @$today_users_registered )
  {
      my $page = $mgusers->{$_id_user}{last_page} || 'Home';
      $user_html .= "<tr><td>$mgusers->{$_id_user}->{firstname}</td><td>$mgusers->{$_id_user}->{lastname}</td><td>last on page</td><td>&nbsp;&nbsp;&nbsp;$page</td></tr>\n";
  }
  $user_html .= "</table>";

#  $user_html .= "<br>".join("<br>", map { $mgusers->{$_}->{firstname}." ".$mgusers->{$_}->{lastname}." last on page ".($mgusers->{$_}->{last_page} || "Home") } sort { lc $mgusers->{$a}->{lastname} cmp lc $mgusers->{$b}->{lastname} ||lc  $mgusers->{$a}->{firstname} cmp lc $mgusers->{$b}->{firstname} } @$today_users_registered);

#  $user_html .= "<br>".join("<br>", map { $uhash->{$_->[0]}->[1]." ".$uhash->{$_->[0]}->[2]." last on page ".($_->[1] || "Home") } sort { $uhash->{$a->[0]}->[2] cmp $uhash->{$b->[0]}->[2] || $uhash->{$a->[0]}->[1] cmp $uhash->{$b->[0]}->[1] } @$today_users_registered);

  # count new users
  foreach my $_id_user (@$today_users_registered) {
      my $_id_org  = $mgusers->{$_id_user}{organization}[-1];   # choose a single organization
      my $org      = $mgorgs->{$_id_org}{name};
      my $country  = $mgorgs->{$_id_org}{country};

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

  my $user_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

  foreach my $_id_user ( sort {$a <=> $b} keys %$mgusers ) 
  {
      my $_id_org  = $mgusers->{$_id_user}{organization}[-1];   # choose a single organization

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
      
      my $org      = $mgorgs->{$_id_org}{name};
      my $country  = $mgorgs->{$_id_org}{country};
      
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
	      $user_stats->[$i]++;
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

  my $upload_stats_new = [];
  for (my $i=0; $i<31; $i++) 
  {
      my($curr) = ($thirtyone_days->[$i] =~ /^\d{4}-(.+)/);
      push @$upload_stats_new, [$curr, 0];
  }

#  my $upload_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
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

#  my $total_in_queue = 0;
  foreach my $_id_job ( keys %$mgjobs ) 
  {
      next if ($mgjobs->{$_id_job}{dead} || $mgjobs->{$_id_job}{deleted});

      my $_id_user = $mgjobs->{$_id_job}{owner};
      my $_id_org  = $mgjobs->{$_id_job}{organization}[-1];

      my $last_stage = $self->{mgstat}->job2lastpipelinestage($_id_job);
      my($last_stage_name, $last_stage_timestamp, $last_stage_status) = @$last_stage;

      push @$jdata, [ 
		      $mgjobs->{$_id_job}{created_on}, 
		      $mgjobs->{$_id_job}{metagenome_id}, 
		      $mgjobs->{$_id_job}{job_id}, 
		      $mgjobs->{$_id_job}{name}, 
		      $mgjobs->{$_id_job}{bp}, 
		      $mgjobs->{$_id_job}{sequence_type}, 
		      $mgjobs->{$_id_job}{viewable},
		      $mgjobs->{$_id_job}{public},
		      $mgjobs->{$_id_job}{server_version}, 
		      $mgjobs->{$_id_job}{project_name}, 
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

      # count total in queue
#      if ( $last_stage_status ne 'error'    &&
#	   ! ($last_stage_name eq 'done' && $last_stage_status eq 'completed') &&
#	   ! $mgjobs->{$_id_job}{deleted} &&
#	   ! $mgjobs->{$_id_job}{dead}    &&
#	   (($last_stage_timestamp cmp $thirtyone_days->[0]) < 0) )
#      {
#    if (scalar(@{$job->{timed_stati}}) && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2]) {
#      if (!($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'error') && !($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[1] eq 'done' && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'completed') && ! exists($deletedjobshash->{$job->{_id}}) && ! exists($deadjobshash->{$job->{_id}})) {
#	if (($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0] cmp $thirtyone_days->[0]) < 0) {
#	  $total_in_queue += $mgjobs->{$_id_job}{bp};
#      }

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

      # count processing bp
#      for (my $i=0; $i<31; $i++) {
#	  my $curr = $thirtyone_days->[$i];

	  
#	  if ($upload_stage_timestamp =~ /^$curr/) {
	  #    $upload_stats->[$i] += $mgjobs->{$_id_job}{bp};
#	      last;
#	  }
#      }

      # count uploaded bp
      my $upload_stage = $self->{mgstat}->jobstage($_id_job, 'upload');
      my($upload_stage_name, $upload_stage_timestamp, $upload_stage_status) = @$upload_stage;

      if ( ($upload_stage_status eq 'completed') and ($self->{mgstat}->compare_dates($upload_stage_timestamp, $thirtyone_days->[0]) eq 'after') )
#      if ($job->{timed_stati}->[0]->[1] eq 'upload' && $job->{timed_stati}->[0]->[2] eq 'completed') {
      {
	for (my $i=0; $i<31; $i++) {
	  my $curr = $thirtyone_days->[$i];
	  if ($upload_stage_timestamp =~ /^$curr/) {
	    $upload_stats->[$i] += $mgjobs->{$_id_job}{bp};
	    $upload_stats_new->[$i][1] += $mgjobs->{$_id_job}{bp};
	    last;
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

  # format to gbp
  for (my $i=0; $i<31; $i++) {
    #$processing_stats->[$i] += $total_in_queue;
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

  @$jdata = sort { $b->[0] cmp $a->[0] } @$jdata;
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
  $ot->show_column_select(1);
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

  my $gmeter_val_today = sprintf("%.0f", ($gbp_today*2/3));
  my $gmeter_val_week  = sprintf("%.0f", ($gbp_week_daily*2/3));
  my $gmeter_val_month = sprintf("%.0f", ($gbp_month_daily*2/3));

  $gbp_week  = $self->add_commas($gbp_week);
  $gbp_month = $self->add_commas($gbp_month);

  my $gmeter_today = qq(<img alt="Processing Speed: $gbp_today Gbp today" src="https://chart.googleapis.com/chart?chtt=Today&chs=300x200&cht=gom&chls=2|10&chd=t:$gmeter_val_today&chl=$gbp_today+Gbp&chxt=x,y&chxr=1,0,150,25">);

my $gmeter_week = qq(<img alt="Processing Speed: $gbp_week Gbp/day in last 7 days" src="https://chart.googleapis.com/chart?chtt=Last+7+days+($gbp_week Gbp)&chs=300x200&cht=gom&chls=2|10&chd=t:$gmeter_val_week&chl=$gbp_week_daily+Gbp/day&chxt=x,y&chxr=1,0,150,25">);

my $gmeter_month = qq(<img alt="Processing Speed: $gbp_month Gbp/day in last 7 days" src="https://chart.googleapis.com/chart?chtt=Last+30+days+($gbp_month Gbp)&chs=300x200&cht=gom&chls=2|10&chd=t:$gmeter_val_month&chl=$gbp_month_daily+Gbp/day&chxt=x,y&chxr=1,0,150,25">);

  my $bpup = $self->googleviz('dash_0_new', 'Basepairs uploaded in Gbp', 'day', 'uploaded', 0, 'green', $upload_stats_new);

  # organization list output
  my $gmeter_table = "
<table>
<tr>
<td>
  $gmeter_today
</td>
<td>
    $gmeter_week
</td>
<td>
  $gmeter_month
</td>
</tr>
</table>
";

  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"pspeed\").style.display==\"none\"){document.getElementById(\"pspeed\").style.display=\"\";}else{document.getElementById(\"pspeed\").style.display=\"none\";}'>&raquo; Processing Speed</h2><div id='pspeed' style='display: none;'>".$gmeter_table."<br><br><div id='organization_details'></div></div>";

  $html .= "<table><tr><td>" . $bpup . "<div id='dash_0_new'></div></td></tr></table>\n";

  # dashboard output
  $html .= "<div id='jobs'>$qwe</div><div id='dashboard'><input type='button' id='dash_0_button' value='show 30 days' onclick='switch_days(\"0\");'><table><tr><td><div id='dash_0'></div><div id='dash_0_b'></div></td><td><div id='dash_1'></div><div id='dash_1_b'></div></td><td id='dash_5' rowspan=7>$user_html</td></tr><tr><td><div id='dash_2'></div><div id='dash_2_b'></div></td><td><div id='dash_3'></div><div id='dash_3_b'></div></td></tr><tr><td><div id='dash_4'></div><div id='dash_4_b'></div></td></tr><tr><td id='dash_6' colspan=2></td></tr><tr><td id='dash_7' colspan=2></td></tr><tr><td id='dash_8' colspan=2></td></tr><tr><td id='dash_11' colspan=2></td></tr><tr><td colspan=2><h3>All Users with Organizations</h3></td><td><h3>Current Users with Organizations</h3></td></tr><tr><td id='dash_9' colspan=2></td><td id='dash_10' colspan=2></td></tr></table><input type='button' value='export to excel' onclick='window.top.location=\"?page=MGS&exp=".join("|", @$average_size_stats_filtered2)."\";'></div>";

  foreach my $day (@$thirtyone_days) {
    $day =~ s/^\d+-(.+)/$1/;
  }

  $html .= "<input type='hidden' id='thirty_days_dates' value='".join(";", @$thirtyone_days[1..30])."'>";

  # upload stats output
  #$html .= "<h2>Gbp uploaded</h2><div id='upload_stats'></div>";

  $html .= "<input type='hidden' id='upload_stats_data' value='".join(";", @$upload_stats[1..30])."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"upload\", \"Gbp\");'>";

  # jobs broken output
  #$html .= "<h2>jobs /w error status</h2><div id='broken_stats'></div>";
  $html .= "<input type='hidden' id='broken_stats_data' value='".join(";", @$broken_stats[1..31])."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"broken\", \"Job\");'>";

  # gbp finished output
  #$html .= "<h2>Gbp finished</h2><div id='finished_stats'></div>";
  $html .= "<input type='hidden' id='finished_stats_data' value='".join(";", @$finished_stats[1..31])."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"finished\", \"Gbp\");'>";

  # gbp processing output
  #$html .= "<h2>Gbp processing</h2><div id='processing_stats'></div>";
  $html .= "<input type='hidden' id='processing_stats_data' value='".join(";", @$processing_stats[1..31])."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"processing\", \"Gbp\");'>";

  # new users output
  #$html .= "<h2>new users</h2><div id='user_stats'></div>";
  $html .= "<input type='hidden' id='user_stats_data' value='".join(";", @$user_stats[1..31])."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"user\", \"user\");'>";

  # upload average size
  $html .= "<input type='hidden' id='average_size_data' value='".join(";", @$average_size_stats)."'>";
  $html .= "<input type='hidden' id='average_size_filtered_data' value='".join(";", @$average_size_stats_filtered)."'>";
  $html .= "<input type='hidden' id='average_size_filtered2_data' value='".join(";", @$average_size_stats_filtered2)."'>";
  $html .= "<input type='hidden' id='average_size_cols' value='".join(";", @$fourtyeightcols)."'>";

  # upload size contribution
  $html .= "<input type='hidden' id='size_distribution' value='".join(";", map { $_->[0]."|".$_->[1]."|".$_->[2] } @$size_distribution)."'>";

  # country distribution
  my $auc = [];
  @$auc = keys(%$countries);
  my $aun = [];
  foreach my $co (@$auc) {
    push(@$aun, $countries->{$co});
  }
  $html .= "<input type='hidden' id='all_users_countries' value='".join(";", @$auc)."'>";
  $html .= "<input type='hidden' id='all_users_nums' value='".join(";", @$aun)."'>";

  my $nuc = [];
  @$nuc = keys(%$current_countries);
  my $nun = [];
  foreach my $co (@$nuc) {
    push(@$nun, $current_countries->{$co});
  }
  $html .= "<input type='hidden' id='curr_users_countries' value='".join(";", @$nuc)."'>";
  $html .= "<input type='hidden' id='curr_users_nums' value='".join(";", @$nun)."'>";

  # load dashboard
  $html .= '<script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
      google.setOnLoadCallback(load_dashboard);
</script>';

  # job list output
  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"jlist\").style.display==\"none\"){document.getElementById(\"jlist\").style.display=\"\";}else{document.getElementById(\"jlist\").style.display=\"none\";}'>&raquo; Job List</h2><div id='jlist' style='display: none;'>".$jt->output()."<br><br><div id='job_details'></div></div>";

  # user list output
  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"ulist\").style.display==\"none\"){document.getElementById(\"ulist\").style.display=\"\";}else{document.getElementById(\"ulist\").style.display=\"none\";}'>&raquo; User List</a></h2><div id='ulist' style='display: none;'><table><tr><td>".$ut->output()."</td><td><div id='user_details'></div></td></tr></table></div>";

  # organization list output
  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"olist\").style.display==\"none\"){document.getElementById(\"olist\").style.display=\"\";}else{document.getElementById(\"olist\").style.display=\"none\";}'>&raquo; Organization List</h2><div id='olist' style='display: none;'>".$ot->output()."<br><br><div id='processing_speed'></div></div>";

  ### funding sources counts
  my $table_a = $self->application->component('FundingSources');
#  my $data_a  = $user_dbh->selectall_arrayref("select value, count(*) from Preferences where name = 'funding_source' group by value");
  
  my $fs2user_count = $self->{mgstat}->funding_source2user_count();
  my $data_a = [];

  foreach my $fs ( keys %$fs2user_count ) 
  {
      push @$data_a, [$fs, $fs2user_count->{$fs}];
  }

  @$data_a = sort { $a->[0] cmp $b->[0] } @$data_a;
  my ($pie_a, $div_a) = &get_piechart("pie_a", "Funding Sources", ['Organization', 'Count'], $data_a, 20);
  
  $table_a->width(850);
  if ( scalar(@$data_a) > 25 ) {
    $table_a->show_top_browse(1);
    $table_a->show_bottom_browse(1);
    $table_a->show_clear_filter_button(1);
    $table_a->items_per_page(25);
    $table_a->show_select_items_per_page(1); 
  }
  $table_a->columns([ { name => 'Funding Source', sortable => 1, filter => 1 },
		      { name => 'Count', sortable => 1 }
		    ]);
  $table_a->data($data_a);
  $table_a->show_export_button({title => 'export', strip_html => 1});


  ### funding sources user and job
  my $table_b = $self->application->component('FundingSourcesClean');
  my $data_b  = $self->{mgstat}->get_funding_user_jobs(); # fund, user, job, bp

  my @fund_usr = map { [$_->[0], $_->[1]] } @$data_b;
  my @fund_job = map { [$_->[0], $_->[2]] } @$data_b;
  my @fund_bps = map { [$_->[0], sprintf("%.3f", ($_->[3] * 1.0)/1000000000)] } @$data_b;
  
  my ($pie_usr, $div_usr) = &get_piechart("pie_usr", "Users per funding source", ['Organization', 'Users'], \@fund_usr, 0);
  my ($pie_job, $div_job) = &get_piechart("pie_job", "Jobs per funding source", ['Organization', 'Jobs'], \@fund_job, 20);
  my ($pie_bps, $div_bps) = &get_piechart("pie_bps", "Gbps per funding source", ['Organization', 'Gbps'], \@fund_bps, 20);
  my $div_b = "<table><tr><td>$div_usr</td><td>$div_job</td><td>$div_bps</td></tr></table>";
  
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
  $table_b->show_export_button({title => 'export', strip_html => 1});
  
  ### job counts
  my $data_c  = $mgrast_dbh->selectall_arrayref("select substring(created_on,1,7) as Date, count(job_id) as Jobs from Job where job_id is not NULL group by Date");
  my $table_c = $self->application->component('JobsMonth');
  my ($pie_c, $div_c) = &get_piechart("pie_c", "Jobs per Month", ['Month', 'Jobs'], $data_c, 20);
  
  $table_c->width(850);
  if ( scalar(@$data_c) > 25 ) {
    $table_c->show_top_browse(1);
    $table_c->show_bottom_browse(1);
    $table_c->show_clear_filter_button(1);
    $table_c->items_per_page(25);
    $table_c->show_select_items_per_page(1); 
  }
  $table_c->columns([ { name => 'Period', sortable => 1 },
		      { name => 'Jobs', sortable => 1 }
		    ]);    
  $table_c->data($data_c);
  $table_c->show_export_button({title => 'export', strip_html => 1});
  
  $html .= $pie_pc . $pie_a . $pie_usr . $pie_job . $pie_bps . $pie_c;
  $html .= "<h3><a onclick='if(document.getElementById(\"fund\").style.display==\"none\"){document.getElementById(\"fund\").style.display=\"\"}else{document.getElementById(\"fund\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Funding Sources</a></h3><div id='fund' style='display: none;'>" . $table_a->output . $div_a . "</div>";
  $html .= "<h3><a onclick='if(document.getElementById(\"fstat\").style.display==\"none\"){document.getElementById(\"fstat\").style.display=\"\"}else{document.getElementById(\"fstat\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Funding Stats</a></h3><div id='fstat' style='display: none;'>" . $table_b->output . $div_b . "</div>";
  $html .= "<h3><a onclick='if(document.getElementById(\"muse\").style.display==\"none\"){document.getElementById(\"muse\").style.display=\"\"}else{document.getElementById(\"muse\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Monthly Job Usage</a></h3><div id='muse' style='display: none;'>" . $table_c->output . $div_c . "</div>";
  $html .= "<br><br><br>";
  
  return $html;
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
  my ($id, $title, $cols, $data, $left) = @_;

  my $num  = scalar @$data;
  my $rows = join("\n", map { qq(data.addRow(["$_->[0]", $_->[1]]);) } sort { $b->[1] <=> $a->[1] } @$data);
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
        chart.draw(data, {width: 300, height: 300, chartArea: {left:$left, width:"90%"}, title: '$title'});
      }
    </script>
~;

  return ($pie, "<div id='$id'></div>");
}

sub require_css {
  return [ ];
}

sub require_javascript {
  return [ "$Config::cgi_url/Html/MGRASTAdmin.js", "$Config::cgi_url/Html/rgbcolor.js", "https://www.google.com/jsapi" ];
}

sub required_rights {
  return [ [ 'edit', 'user', '*' ] ];
}
