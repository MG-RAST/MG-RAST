package MGRAST::WebPage::Statistics;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use Global_Config;

use Data::Dumper;

1;

=pod

=head1 NAME

Statistics - an instance of WebPage which displays MGRAST job statistics

=head1 DESCRIPTION

Display MGRAST job statistics

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Statistics');
  $self->application->register_component('Table', 'result_table');
  $self->application->register_component('BarChart', 'bc1');
  $self->application->register_component('BarChart', 'bc2');
  $self->application->register_component('BarChart', 'bc3');
  $self->application->register_component('BarChart', 'bc4');

  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the Statistics page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  unless ($application->session->user && $application->session->user->is_admin($application->backend)) {
    return "<p>You are lacking the rights to view this page.</p>";
  }

  my $content = "<h3>Statistics</h3>";

  my $check_status = [];
  @$check_status = $self->app->data_handle('MGRAST')->Job->get_jobs_for_user_fast($self->application->session->user);
  my $broken = {};
  foreach my $job (@$check_status) {
    unless ($self->check_status($job)) {
      $broken->{$job->{id}} = 1;
    }
  }

  my $cached = {};
  if (open(FH, $Global_Config::mgrast_jobs."/statistics")) {
    while (<FH>) {
      chomp;
      my ($id, $start, $stop, $bp) = split /\t/;
      if ($broken->{$id}) {
	$stop = -1;
      }
      $cached->{$id} = { start => $start,
			 stop => $stop,
			 bp => $bp };
    }
    close FH;
  }

  my $dbh = $self->app->data_handle('MGRAST');
  my $jobs = $dbh->Job->get_objects();
  my $new = [];
  my $not_done = [];
  my $juser_ids = [];
  foreach my $job (@$jobs) {
    unless (exists($cached->{$job->{id}})) {
      push(@$new, $job);
    } else {
      unless ($cached->{$job->{id}}->{stop}) {
	push(@$not_done, $job);
      }
    }
  }

  my $jobs_by_id = {};
  %$jobs_by_id = map { $_->{id} => $_ } @$jobs;

  foreach my $job (@$not_done) {
    if (-f $job->dir."/DONE" && ! -f $job->dir."/DELETED") {
      push(@$new, $job);
    }
  }

  foreach my $job (@$new) {
    next if -f $job->dir."/DELETED";
    my $stop = 0;
    my $start = 0;
    my $bp = 0;
    if (-f $job->dir."/DONE") {
      $stop = (stat($job->dir."/DONE"))[10];
    }
    if ($cached->{$job->{id}}) {
      $start = $cached->{$job->{id}}->{start};
      $bp = $cached->{$job->{id}}->{bp};
    } else {
      $start = $job->metaxml->get_metadata('upload.timestamp') || 0;
      $bp = $job->metaxml->get_metadata('preprocess.count_raw.total') || 0;
    }
    if ($broken->{$job->{id}}) {
      $stop = -1;
    }
    $cached->{$job->{id}} = { start => $start,
			      stop => $stop,
			      bp => $bp };
  }

  if (scalar(@$new)) {
    if (open(FH, ">".$Global_Config::mgrast_jobs."/statistics")) {
      foreach my $key (keys(%$cached)) {
	print FH join("\t", ( $key, $cached->{$key}->{start}, $cached->{$key}->{stop}, $cached->{$key}->{bp}))."\n";
      }
      close FH;
    }
  }

  my $t = $application->component('result_table');
  $t->show_column_select(1);
  $t->show_export_button(1);
  $t->columns( [ { name => 'job', filter => 1 }, { name => 'size', sortable => 1, filter => 1, operators => [ 'more', 'less' ] }, { name => 'uploaded', sortable => 1, filter => 1, operators => [ 'less', 'more', 'like' ] }, { name => 'finished', , sortable => 1, filter => 1, operators => [ 'less', 'more', 'like' ] }, { name => 'user', filter => 1 }, { name => 'user entry date', sortable => 1, filter => 1, operators => [ 'less', 'more', 'like' ] }, { name => 'user org', filter => 1 }, { name => 'country', filter => 1, operator => 'combobox' } ] );
  my $data = [];
  my $keys = [];
  @$keys = sort { $a <=> $b } keys(%$cached);
  my $total_submitted = 0;
  my $total_done = 0;
  my $total_bp_submitted = 0;
  my $total_bp_done = 0;
  my $submitted_last_30_days = 0;
  my $completed_last_30_days = 0;
  my $submitted_bp_last_30_days = 0;
  my $completed_bp_last_30_days = 0;
  my $nbroken = 0;
  my $bp_broken = 0;
  my $now_minus_30 = time - 2592000;
  foreach my $key (@$keys) {
    my $s = $cached->{$key}->{bp};
    while ($s =~ m/\d{4}/) {
      $s =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
    }
    my $stop = $cached->{$key}->{stop};
    if ($stop == -1) {
      $stop = '0 error';
    } elsif ($stop == 0) {
      $stop = '0 incomplete';
    } else {
      my @t = localtime($stop);
      $t[4]++;
      if ($t[4] < 10) { $t[4] = "0".$t[4]; }
      if ($t[2] < 10) { $t[2] = "0".$t[2]; }
      if ($t[1] < 10) { $t[1] = "0".$t[1]; }
      if ($t[0] < 10) { $t[0] = "0".$t[0]; }
      $stop = (1900 + $t[5])."-".$t[4]."-".$t[3]." ".$t[2].":".$t[1].":".$t[0];
    }
    my $start = $cached->{$key}->{start};
    if ($start == 0) {
      $start = '0 failed';
      $stop = '0 upload failed';
      $broken->{$key} = 1;
    } else {
      my @t = localtime($start);
      $t[4]++;
      if ($t[4] < 10) { $t[4] = "0".$t[4]; }
      if ($t[2] < 10) { $t[2] = "0".$t[2]; }
      if ($t[1] < 10) { $t[1] = "0".$t[1]; }
      if ($t[0] < 10) { $t[0] = "0".$t[0]; }
      $start = (1900 + $t[5])."-".$t[4]."-".$t[3]." ".$t[2].":".$t[1].":".$t[0];
    }
    my $user_entry_date = '0';
    my $user_name = '- no user found -';
    my $user_org = '-';
    my $country = '-';
    if ($jobs_by_id->{$key} && $jobs_by_id->{$key}->owner) {
      $user_entry_date = $jobs_by_id->{$key}->owner->entry_date;
      $user_name = $jobs_by_id->{$key}->owner->firstname . " " . $jobs_by_id->{$key}->owner->lastname;
      $user_org = $application->dbmaster->OrganizationUsers->get_objects( { user => $jobs_by_id->{$key}->owner } );
      if (scalar(@$user_org)) {
	$country = $user_org->[0]->organization->country();
	$user_org = $user_org->[0]->organization->name();
      } else {
	$user_org = '-';
      }
    }
    push(@$data, [ $key, $s, $start, $stop, $user_name, $user_entry_date, $user_org, $country ]);

    next unless $start;    

    # statistics
    $total_submitted++;
    $total_bp_submitted += $cached->{$key}->{bp};
    if ($cached->{$key}->{stop}) {
      $total_done++;
      $total_bp_done += $cached->{$key}->{bp};
    }
    if ($cached->{$key}->{start} > $now_minus_30) {
      $submitted_last_30_days++;
      $submitted_bp_last_30_days += $cached->{$key}->{bp};
      if ($cached->{$key}->{stop}) {
	$completed_last_30_days++;
	$completed_bp_last_30_days += $cached->{$key}->{bp};
      }
    }
    if ($broken->{$key}) {
      $nbroken++;
      $bp_broken += $cached->{$key}->{bp};
    }
  }
  my $bp_in_queue = $total_bp_submitted - $total_bp_done - $bp_broken;

  my $speed = int($completed_bp_last_30_days / 2592000);
  my $trip = int($completed_bp_last_30_days / 1000000);
  my $mileage = int($total_bp_done / 1000000);
  my $togo = int($bp_in_queue / 1000000);
  if (open(FH, ">".$Global_Config::mgrast_jobs."/statistics_short")) {
    print FH join("\t", ( $speed, $mileage, $trip, $togo ));
    close FH;
  }

  while ($bp_in_queue =~ m/\d{4}/) {
    $bp_in_queue =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }
  while ($total_bp_submitted =~ m/\d{4}/) {
    $total_bp_submitted =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }
  while ($total_bp_done =~ m/\d{4}/) {
    $total_bp_done =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }
  while ($submitted_bp_last_30_days =~ m/\d{4}/) {
    $submitted_bp_last_30_days =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }
  while ($completed_bp_last_30_days =~ m/\d{4}/) {
    $completed_bp_last_30_days =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }
  while ($bp_broken =~ m/\d{4}/) {
    $bp_broken =~ s/^(\d+)(\d{3})(.*)$/$1,$2$3/;
  }

  $content .= "<table>";
  $content .= "<tr><td>total #jobs submitted</td><td>$total_submitted</td></tr>";
  $content .= "<tr><td>total #jobs done</td><td>$total_done</td></tr>";
  $content .= "<tr><td>total #bp submitted</td><td>$total_bp_submitted</td></tr>";
  $content .= "<tr><td>total #bp done</td><td>$total_bp_done</td></tr>";
  $content .= "<tr><td>total #jobs submitted in the last 30 days</td><td>$submitted_last_30_days</td></tr>";
  $content .= "<tr><td>total #jobs done in the last 30 days</td><td>$completed_last_30_days</td></tr>";
  $content .= "<tr><td>total #bp submitted in the last 30 days</td><td>$submitted_bp_last_30_days</td></tr>";
  $content .= "<tr><td>total #bp done in the last 30 days</td><td>$completed_bp_last_30_days</td></tr>";
  $content .= "<tr><td>total #bp in queue</td><td>$bp_in_queue</td></tr>";
  $content .= "<tr><td>broken jobs</td><td>$nbroken</td></tr>";
  $content .= "<tr><td>bp of broken jobs</td><td>$bp_broken</td></tr>";
  $content .= "</table>";

  $content .= "<br><table><tr><td>";
  my $bc1 = $application->component('bc1');
  $bc1->width(300);
  $bc1->height(300);
  my $bc1_data = [];
  my $sum_month = 0;
  my $month = "2009-04";
  # [ $key, $s, $start, $stop, $user_name, $user_entry_date, $user_org, $country ]
  my $data_ref = [];
  @$data_ref = sort { $a->[3] cmp $b->[3] } @$data;
  foreach my $row (@$data_ref) {
    next if ($row->[3] lt $month);
    my ($m) = $row->[3] =~ /^(\d+\-\d+)/;
    if ($m eq $month) {
      $sum_month++;
    } else {
      my ($mon) = $month =~ /^\d+\-(\d+)/;
      push(@$bc1_data, { title => $mon, data => $sum_month });
      ($month) = $row->[3] =~ /^(\d+\-\d+)/;
      $sum_month = 1;
    }
  }
  my ($mon) = $month =~ /^\d+\-(\d+)/;
  push(@$bc1_data, { title => $mon, data => $sum_month });
  $bc1->data($bc1_data);
  $content .= "<h3>jobs finished per month</h3>";
  $content .= $bc1->output();
  $content .= "</td><td>";
  my $bc2 = $application->component('bc2');
  $bc2->width(300);
  $bc2->height(300);
  my $bc2_data = [];
  $sum_month = 0;
  $month = "2009-04";
  # [ $key, $s, $start, $stop, $user_name, $user_entry_date, $user_org, $country ]
  foreach my $row (@$data_ref) {
    next if ($row->[3] lt $month);
    next unless ($row->[1] =~ /^[\d,]+$/);
    my ($m) = $row->[3] =~ /^(\d+\-\d+)/;
    if ($m eq $month) {
      my $val = $row->[1];
      $val =~ s/,//g;
      $sum_month += $val;
    } else {
      my ($mon) = $month =~ /^\d+\-(\d+)/;
      if ($sum_month) {
	$sum_month = sprintf('%.2f', $sum_month / 1000000000);
      }
      push(@$bc2_data, { title => $mon, data => $sum_month });
      ($month) = $row->[3] =~ /^(\d+\-\d+)/;
      my $val = $row->[1];
      $val =~ s/,//g;
      $sum_month = $val;
    }
  }
  ($mon) = $month =~ /^\d+\-(\d+)/;
  if ($sum_month) {
    $sum_month = sprintf('%.2f', $sum_month / 1000000000);
  }
  push(@$bc2_data, { title => $mon, data => $sum_month });
  $bc2->data($bc2_data);
  $content .= "<h3>gbp finished per month</h3>";
  $content .= $bc2->output();

  $content .= "</td><td>";
  my $bc4 = $application->component('bc4');
  my $bc4_data = [];
  @$data_ref = sort { $a->[2] cmp $b->[2] } @$data;
  $bc4->width(300);
  $bc4->height(300);
  $sum_month = 0;
  $month = "2009-04";
  foreach my $row (@$data_ref) {
    next if ($row->[2] lt $month);
    next unless ($row->[1] =~ /^[\d,]+$/);
    my ($m) = $row->[2] =~ /^(\d+\-\d+)/;
    if ($m eq $month) {
      my $val = $row->[1];
      $val =~ s/,//g;
      $sum_month += $val;
    } else {
      my ($mon) = $month =~ /^\d+\-(\d+)/;
      if ($sum_month) {
	$sum_month = sprintf('%.2f', $sum_month / 1000000000);
      }
      push(@$bc4_data, { title => $mon, data => $sum_month });
      ($month) = $row->[2] =~ /^(\d+\-\d+)/;
      my $val = $row->[1];
      $val =~ s/,//g;
      $sum_month = $val;
    }
  }
  ($mon) = $month =~ /^\d+\-(\d+)/;
  if ($sum_month) {
    $sum_month = sprintf('%.2f', $sum_month / 1000000000);
  }
  push(@$bc4_data, { title => $mon, data => $sum_month });
  $bc4->data($bc4_data);

  $content .= "<h3>gbp uploaded per month</h3>";
  $content .= $bc4->output();

  $content .= "</td></tr><tr><td colspan=2>";

  my $bc3 = $application->component('bc3');
  $bc3->width(600);
  $bc3->height(300);
  my $bc3_data = [];
  my $sums_org = {};
  $month = "2009-04";
  # [ $key, $s, $start, $stop, $user_name, $user_entry_date, $user_org, $country ]
  foreach my $row (@$data_ref) {
    next if ($row->[3] lt $month);
    next unless ($row->[1] =~ /^[\d,]+$/);
    my $val = $row->[1];
    $val =~ s/,//g;
    if (exists($sums_org->{$row->[6]})) {
      $sums_org->{$row->[6]} += $val;
    } else {
      $sums_org->{$row->[6]} = $val;
    }
  }
  foreach my $key (keys(%$sums_org)) {
    my $t = $key;
    if ($key eq '-') {
      $t = 'unknown';
    }
    my $v = $sums_org->{$key};
    if ($v) {
      $v = sprintf("%.2f", $v / 1000000000);
    }
    push(@$bc3_data, { title => $t, data => $v });
  }
  @$bc3_data = sort { $b->{data} <=> $a->{data} } @$bc3_data;
  @$bc3_data = splice(@$bc3_data, 0, 40);
  $bc3->data($bc3_data);
  $content .= "<h3>top 40 in gbp per organization since 2009-04</h3>";
  $content .= $self->google_map($bc3_data);
  $content .= "<br><br><br><br>";
  $content .= $bc3->output();

  $content .= "</td></tr></table>";

  $t->data($data);
  $t->items_per_page(25);
  $t->show_top_browse(1);
  $t->show_bottom_browse(1);
  $t->show_select_items_per_page(1);
  $content .= $t->output();
  
  return $content;
}

sub check_status {
  my ($self, $job) = @_;

  my $revsort = { 0 => 'status.uploaded',
		  1 => 'status.preprocess',
		  2 => 'status.sims',
		  3 => 'status.check_sims',
		  4 => 'status.create_seed_org',
		  5 => 'status.export',
		  6 => 'status.final' };
  
  unless ($job->{viewable}) {
    my $state    = '';
    my $n_stages = 7;
    
    for (my $i = 0; $i < $n_stages; $i++) {
	my $stage  = $revsort->{$i};
	my $status = $job->{status}->{$stage} || 'not_started';
	
	$state .= $stage . $status;
	
	my $stage_number = $i + 1;
	
	if ($status ne 'not_started') {
	  if ($status eq 'error') {
	    return 0;
	  }
	}
      }
  }

  return 1;
}

sub google_map {
  my ($self, $top40) = @_;

  my $master = $self->application->dbmaster;

  my $html = "";
  my $max = 0;
  foreach my $t (@$top40) {
    if ($t->{data} > $max) {
      $max = $t->{data};
    }
  }
  my $norm = 100 / $max;

  my $orgs = $master->Organization->get_objects();
  my $orgs_hash = {};
  %$orgs_hash = map { $_->{name} => $_ } @$orgs;
  my @org_locations;
  foreach my $top (@$top40) {
    if (exists($orgs_hash->{$top->{title}}) && $orgs_hash->{$top->{title}}->location && $orgs_hash->{$top->{title}}->location ne "0.00, 0.00") {
      push(@org_locations, $orgs_hash->{$top->{title}}->location.", ".$top->{title}.", ".int($top->{data} * $norm));
    }
  }

  $html .= "<input type='hidden' id='org_locations' value='".join(";", @org_locations)."'>".'<script type="text/javascript" src="http://maps.google.com/maps/api/js?sensor=false"></script>
<script type="text/javascript">
  function initialize() {
     var latlng = new google.maps.LatLng(26.115986, 8.437500);
     var myOptions = {
       zoom: 2,
       center: latlng,
       mapTypeId: google.maps.MapTypeId.HYBRID,
       mapTypeControl: false,
       disableDefaultUI: true
     };
   var map = new google.maps.Map(document.getElementById("map"), myOptions);
   var locs = document.getElementById("org_locations").value.split(";");
   for (i=0; i<locs.length; i++) {
     var loc = locs[i].split(", ");
     var scaledHeight = loc[3];
     var mimg = new google.maps.MarkerImage("./Html/barred.gif", new google.maps.Size(20,scaledHeight), null, null, new google.maps.Size(20,100));
     var mark = new google.maps.Marker({ title:loc[2],
                                         icon:mimg,
                                         position: new google.maps.LatLng(loc[0], loc[1]),
                                         map: map });
  }
}

</script>';

  $html .= qq~<div id="map" style="width: 800px; height: 600px"></div><img src='./Html/clear.gif' onload='initialize();'>~;

  return $html;
}
