package MGRAST::WebPage::MGRASTAdmin;

use base qw( WebPage );

use strict;
use warnings;
no warnings qw(uninitialized);

use WebConfig;
use Data::Dumper;
use FIG_Config;

use MGRAST::MGRAST qw( :DEFAULT );
use MGRAST::MetagenomeAnalysis2;
use MGRAST::Metadata;

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
  
  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the MetagenomeSelect page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $dbmaster = $application->dbmaster;
  my $user = $application->session->user;
  my $cgi  = $application->cgi;

  my $mgrast_dbh = $self->application->data_handle('MGRAST')->db_handle;
  my $user_dbh   = $user->_master->db_handle;

  # check for MGRAST
  my $html = "";
  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
      $html .= "<h2>The MG-RAST is currently offline. You are the admin, fix it!</h2>";
      return $html;
  }
  $self->{mgrast} = $mgrast;

  $html .= $application->component('ajax')->output();

  # thirty days
  my $thirty_days = [];
  for (my $i=29; $i>-1; $i--) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time-($i * 86400));
    $year += 1900;
    $mon++;
    $mon = sprintf("%02d", $mon);
    $mday = sprintf("%02d", $mday);
    push(@$thirty_days, "$year-$mon-$mday");
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
  my $dbh = $dbmaster->db_handle;
  my $sth = $dbh->prepare("SELECT User._id, User.firstname, User.lastname, User.login, User.email, User.entry_date, Organization.country FROM User LEFT OUTER JOIN (Organization, OrganizationUsers) ON Organization._id=OrganizationUsers.organization AND User._id=OrganizationUsers.user");
  $sth->execute;
  my $users = $sth->fetchall_arrayref();
  my $uhash = {};
  %$uhash = map { $_->[0] => $_ } @$users;
  my $data = [];
  my $countries = {};
  my $current_countries = {};

  # current users
  my $today_users_registered = $user_dbh->selectall_arrayref("select user, current_page from UserSession where timestamp > '".$thirty_days->[29]." 00:00:00' and user is not null");
  my $today_users = $user_dbh->selectall_arrayref("select count(*) from UserSession where timestamp > '".$thirty_days->[29]." 00:00:00'");
  my $user_html .= "<b>Users online today:</b> ".$today_users->[0]->[0]." (".scalar(@$today_users_registered)." Registered)";
  $user_html .= "<br>".join("<br>", map { $uhash->{$_->[0]}->[1]." ".$uhash->{$_->[0]}->[2]." last on page ".($_->[1] || "Home") } sort { $uhash->{$a->[0]}->[2] cmp $uhash->{$b->[0]}->[2] || $uhash->{$a->[0]}->[1] cmp $uhash->{$b->[0]}->[1] } @$today_users_registered);

  # count new users
  foreach my $u (@$today_users_registered) {
    if ($uhash->{$u->[0]}->[6]) {
      if (exists($current_countries->{$uhash->{$u->[0]}->[6]})) {
	$current_countries->{$uhash->{$u->[0]}->[6]}++;
      } else {
	$current_countries->{$uhash->{$u->[0]}->[6]} = 1;
      }
    }
  }
  
  my $user_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  foreach my $u (@$users) { # $u->{firstname}, $u->{lastname}, $u->{login}, $u->{email}, $u->{entry_date}
    push(@$data, [ $u->[1], $u->[2], $u->[3], $u->[4], $u->[5], "<input type='button' onclick='execute_ajax(\"user_details\", \"user_details\", \"user=".$u->[3]."\");' value='details'>" ]);

    if ($u->[6]) {
      if (exists($countries->{$u->[6]})) {
	$countries->{$u->[6]}++;
      } else {
	$countries->{$u->[6]} = 1;
      }
    }

    # count new users
    for (my $i=0; $i<30; $i++) {
      my $curr = $thirty_days->[$i];
      if ($u->[5] =~ /^$curr/) {
	$user_stats->[$i]++;
	last;
      }
    }
  }
  my $ut = $application->component('user_table');
  $ut->show_top_browse(1);
  $ut->show_bottom_browse(1);
  $ut->show_select_items_per_page(1);
  $ut->items_per_page(15);
  $ut->data($data);
  $ut->columns( [ { name => 'firstname', filter => 1, sortable => 1 },
		  { name => 'lastname', filter => 1, sortable => 1 },
		  { name => 'login', filter => 1, sortable => 1 },
		  { name => 'email', filter => 1, sortable => 1 },
		  { name => 'date registered', filter => 1, sortable => 1 },
		  { name => 'details', filter => 1, sortable => 1 }, ] );

  # jobs section
  my $finished = [];
  my @jobs = $mgrast->Job->get_jobs_for_user_fast($user);
  
  my $dbh2 = $mgrast->db_handle;
  my $sth2 = $dbh2->prepare("SELECT job, value FROM JobStatistics WHERE tag='bp_count_raw'");
  $sth2->execute;
  my $jobsizes = $sth2->fetchall_arrayref();
  my $jobsizehash = {};
  %$jobsizehash = map { $_->[0] => $_->[1] } @$jobsizes;

  $sth2 = $dbh2->prepare("SELECT job FROM JobAttributes WHERE tag='deleted'");
  $sth2->execute;
  my $deletedjobs = $sth2->fetchall_arrayref();
  my $deletedjobshash = {};
  %$deletedjobshash = map { $_->[0] => 1 } @$deletedjobs;

  $sth2 = $dbh2->prepare("SELECT job FROM JobAttributes WHERE tag='no_sims_found'");
  $sth2->execute;
  my $deadjobs = $sth2->fetchall_arrayref();
  my $deadjobshash = {};
  %$deadjobshash = map { $_->[0] => 1 } @$deadjobs;

  my $jdata = [];
  my $upload_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $broken_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $finished_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $processing_stats = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  my $average_size_stats = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];
  my $average_size_stats_filtered = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];
  my $average_size_stats_filtered2 = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]];

  my $size_distribution = [[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0]];

  my $total_in_queue = 0;
  foreach my $job (@jobs) {
    $job->{size} = $jobsizehash->{$job->{_id}};
    push(@$jdata, [ $job->{created_on}, $job->{metagenome_id}, $job->{job_id}, $job->{name}, $job->{size}, $job->{server_version}, $job->{viewable}, $uhash->{$job->{owner}}->[1], $uhash->{$job->{owner}}->[2], $uhash->{$job->{owner}}->[3], $job->{project_name}, $job->{sequence_type}, $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[1], $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2], $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0], "<input type='button' value='status' onclick='execute_ajax(\"job_details\", \"job_details\", \"job=".$job->{job_id}."\");'>" ]);

    my ($jyear_month) = $job->{created_on} =~ /^(\d+\-\d+)/;
    if (exists($tfmonths->{$jyear_month})) {
      if ($job->{size} > 5000000 && $job->{size} < 50000000) {
	$average_size_stats_filtered->[$tfmonths->{$jyear_month}]->[0]++;
	$average_size_stats_filtered->[$tfmonths->{$jyear_month}]->[1] += $job->{size};
	$size_distribution->[$tfmonths->{$jyear_month}]->[1] += $job->{size};
      } elsif ($job->{size} > 50000000) {
	$average_size_stats_filtered2->[$tfmonths->{$jyear_month}]->[0]++;
	$average_size_stats_filtered2->[$tfmonths->{$jyear_month}]->[1] += $job->{size};
	$size_distribution->[$tfmonths->{$jyear_month}]->[2] += $job->{size};
      } else {
	$average_size_stats->[$tfmonths->{$jyear_month}]->[0]++;
	$average_size_stats->[$tfmonths->{$jyear_month}]->[1] += $job->{size};
	$size_distribution->[$tfmonths->{$jyear_month}]->[0] += $job->{size};
      }
    }
    if (scalar(@{$job->{timed_stati}}) && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2]) {
      # count total in queue
      if (!($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'error') && !($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[1] eq 'done' && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'completed') && ! exists($deletedjobshash->{$job->{_id}}) && ! exists($deadjobshash->{$job->{_id}})) {
	if (($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0] cmp $thirty_days->[0]) < 0) {
	  $total_in_queue += $job->{size};
	}
      }

      # count uploaded bp
      if ($job->{timed_stati}->[0]->[1] eq 'upload' && $job->{timed_stati}->[0]->[2] eq 'completed') {
	for (my $i=0; $i<30; $i++) {
	  my $curr = $thirty_days->[$i];
	  if ($job->{timed_stati}->[0]->[0] =~ /^$curr/) {
	    $upload_stats->[$i] += $job->{size};
	    last;
	  }
	}
      }
      
      # count broken jobs
      if ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'error') {
	for (my $i=0; $i<30; $i++) {
	  my $curr = $thirty_days->[$i];
	  if ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0] =~ /^$curr/) {
	    $broken_stats->[$i]++;
	    $processing_stats->[$i] -= $job->{size};
	    last;
	  }
	}
      }
      
      # count finished bp
      elsif ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[1] eq 'done' && $job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[2] eq 'completed') {
	for (my $i=0; $i<30; $i++) {
	  my $curr = $thirty_days->[$i];
	  if ($job->{timed_stati}->[scalar(@{$job->{timed_stati}})-1]->[0] =~ /^$curr/) {
	    $finished_stats->[$i] += $job->{size};
	    $processing_stats->[$i] -= $job->{size};
	    last;
	  }
	}
      }
    }
  }

  # format to gbp
  for (my $i=0; $i<30; $i++) {
    $processing_stats->[$i] += $total_in_queue;
    $upload_stats->[$i] ? $upload_stats->[$i] = sprintf("%.2f", $upload_stats->[$i] / 1000000000) : 1;
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
  $jt->show_select_items_per_page(1);
  $jt->items_per_page(15);
  $jt->data($jdata);

  $jt->show_column_select(1);
  $jt->columns( [ { name => 'created', filter => 1, sortable => 1 },
		  { name => 'mgid', filter => 1, sortable => 1 },
		  { name => 'jid', filter => 1, sortable => 1 },
		  { name => 'name', filter => 1, sortable => 1 },
		  { name => 'size', filter => 1, sortable => 1 },
		  { name => 'version', filter => 1, sortable => 1, operator => 'combobox', visible => 0 },
		  { name => 'viewable', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'firstname', filter => 1, sortable => 1 },
		  { name => 'lastname', filter => 1, sortable => 1 },
		  { name => 'email', filter => 1, sortable => 1, visible => 0 },
		  { name => 'project', filter => 1, sortable => 1, visible => 0 },
		  { name => 'sequence type', filter => 1, operator => 'combobox' },
		  { name => 'last stage', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'last stage status', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'last stage time', filter => 1, sortable => 1 },
		  { name => 'status file' } ] );

  if ($cgi->param('jtable_excel_export')) {
    $jt->export_excel();
    exit;
  }

  # dashboard output
  $html .= "<div id='dashboard'><input type='button' id='dash_0_button' value='show 30 days' onclick='switch_days(\"0\");'><table><tr><td><div id='dash_0'></div><div id='dash_0_b'></div></td><td><div id='dash_1'></div><div id='dash_1_b'></div></td><td id='dash_5' rowspan=7>$user_html</td></tr><tr><td><div id='dash_2'></div><div id='dash_2_b'></div></td><td><div id='dash_3'></div><div id='dash_3_b'></div></td></tr><tr><td><div id='dash_4'></div><div id='dash_4_b'></div></td></tr><tr><td id='dash_6' colspan=2></td></tr><tr><td id='dash_7' colspan=2></td></tr><tr><td id='dash_8' colspan=2></td></tr><tr><td id='dash_11' colspan=2></td></tr><tr><td colspan=2><h3>All Users with Organizations</h3></td><td><h3>Current Users with Organizations</h3></td></tr><tr><td id='dash_9' colspan=2></td><td id='dash_10' colspan=2></td></tr></table></div>"; #<input type='button' value='export to excel' onclick='window.top.location=\"?page=MGRASTAdmin&exp=".join("|", @$average_size_stats_filtered2)."\";'>

  foreach my $day (@$thirty_days) {
    $day =~ s/^\d+-(.+)/$1/;
  }

  $html .= "<input type='hidden' id='thirty_days_dates' value='".join(";", @$thirty_days)."'>";

  # upload stats output
  #$html .= "<h2>Gbp uploaded</h2><div id='upload_stats'></div>";
  $html .= "<input type='hidden' id='upload_stats_data' value='".join(";", @$upload_stats)."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"upload\", \"Gbp\");'>";

  # jobs broken output
  #$html .= "<h2>jobs /w error status</h2><div id='broken_stats'></div>";
  $html .= "<input type='hidden' id='broken_stats_data' value='".join(";", @$broken_stats)."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"broken\", \"Job\");'>";

  # gbp finished output
  #$html .= "<h2>Gbp finished</h2><div id='finished_stats'></div>";
  $html .= "<input type='hidden' id='finished_stats_data' value='".join(";", @$finished_stats)."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"finished\", \"Gbp\");'>";

  # gbp processing output
  #$html .= "<h2>Gbp processing</h2><div id='processing_stats'></div>";
  $html .= "<input type='hidden' id='processing_stats_data' value='".join(";", @$processing_stats)."'>";
  #$html .= "<img src='./Html/clear.gif' onload='stat_graph(\"processing\", \"Gbp\");'>";

  # new users output
  #$html .= "<h2>new users</h2><div id='user_stats'></div>";
  $html .= "<input type='hidden' id='user_stats_data' value='".join(";", @$user_stats)."'>";
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
  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"jlist\").style.display==\"none\"){document.getElementById(\"jlist\").style.display=\"\";}else{document.getElementById(\"jlist\").style.display=\"none\";}'>&raquo; Job List</a></h2><div id='jlist' style='display: none;'><input type='button' value='export to excel' onclick='window.top.location=\"?page=MGRASTAdmin&jtable_excel_export=1\";'>".$jt->output()."<br><br><div id='job_details'></div></div>";

  # user list output
  $html .= "<h2><a style='cursor: pointer; color: blue;' onclick='if(document.getElementById(\"ulist\").style.display==\"none\"){document.getElementById(\"ulist\").style.display=\"\";}else{document.getElementById(\"ulist\").style.display=\"none\";}'>&raquo; User List</a></h2><div id='ulist' style='display: none;'><table><tr><td>".$ut->output()."</td><td><div id='user_details'></div></td></tr></table></div>";

  ### funding sources counts
  my $table_a = $self->application->component('FundingSources');
  my $data_a  = $user_dbh->selectall_arrayref("select value, count(*) from Preferences where name = 'funding_source' group by value");
  
  @$data_a = sort { $a->[0] cmp $b->[0] } @$data_a;
  my ($pie_a, $div_a) = &get_piechart("pie_a", "Funding Sources", ['Organization', 'Count'], $data_a, 20);
  
  $table_a->width(850);
  if ( scalar(@$data_a) > 25 ) {
    $table_a->show_top_browse(1);
    $table_a->show_bottom_browse(1);
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
  my $data_b  = $self->get_funding_user_jobs($mgrast_dbh, $user_dbh); # fund, user, job, bp
  
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
    $table_b->items_per_page(25);
    $table_b->show_select_items_per_page(1); 
  }
  $table_b->columns([ { name => 'Funding Source', sortable => 1, filter => 1},
		      { name => 'Users', sortable  => 1 , filter => 1 },
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
    $table_c->items_per_page(25);
    $table_c->show_select_items_per_page(1); 
  }
  $table_c->columns([ { name => 'Period', sortable => 1 },
		      { name => 'Jobs', sortable => 1 }
		    ]);    
  $table_c->data($data_c);
  $table_c->show_export_button({title => 'export', strip_html => 1});
  
  $html .= $pie_a . $pie_usr . $pie_job . $pie_bps . $pie_c;
  $html .= "<h3><a onclick='if(document.getElementById(\"fund\").style.display==\"none\"){document.getElementById(\"fund\").style.display=\"\"}else{document.getElementById(\"fund\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Funding Sources</a></h3><div id='fund' style='display: none;'>" . $table_a->output . $div_a . "</div>";
  $html .= "<h3><a onclick='if(document.getElementById(\"fstat\").style.display==\"none\"){document.getElementById(\"fstat\").style.display=\"\"}else{document.getElementById(\"fstat\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Funding Stats</a></h3><div id='fstat' style='display: none;'>" . $table_b->output . $div_b . "</div>";
  $html .= "<h3><a onclick='if(document.getElementById(\"muse\").style.display==\"none\"){document.getElementById(\"muse\").style.display=\"\"}else{document.getElementById(\"muse\").style.display=\"none\"}' style='color: blue; cursor: pointer;'>&raquo; Monthly Job Usage</a></h3><div id='muse' style='display: none;'>" . $table_c->output . $div_c . "</div>";
  $html .= "<br><br><br>";
  
  ######

  return $html;
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
  $ujobs_table->items_per_page(20);
  $ujobs_table->show_select_items_per_page(1);
  $ujobs_table->columns( [ { name => 'mgid', filter => 1, sortable => 1 }, { name => 'view', filter => 1, sortable => 1  , operator => 'combobox'}, { name => 'edit', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'viewable', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'jid', filter => 1, sortable => 1 }, { name => 'explicit', filter => 1, sortable => 1, operator => 'combobox' } ] );
  $ujobs_table->data($data);

  my $ujobs_out = scalar(@$data) ? $ujobs_table->output() : 'no access to private metagenomes';

  $html .= "<br><br><br><strong>Access to Metagenomes</strong><br>".$ujobs_out;

  return $html;
}

sub get_funding_user_jobs {
    my ($self, $job_dbh, $user_dbh) = @_;
    
    my $lf = {};
    my $job_data  = $job_dbh->selectall_arrayref("select owner, _id from Job where owner is not NULL");
    my $user_data = $user_dbh->selectall_arrayref("select _id, email from User");
    my $fund_data = $user_dbh->selectall_arrayref("select user, value from Preferences where name = 'funding_source'");
    my $stat_data = $job_dbh->selectall_arrayref("select job, value from JobStatistics where tag = 'bp_count_raw' and value is not NULL and value > 0");
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
	while ( my ($ext, $code) = each %{$self->data('mapping')} ) {
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
  return [ "$FIG_Config::cgi_url/Html/MGRASTAdmin.js", "$FIG_Config::cgi_url/Html/rgbcolor.js", "https://www.google.com/jsapi" ];
}

sub required_rights {
  return [ [ 'edit', 'user', '*' ] ];
}
