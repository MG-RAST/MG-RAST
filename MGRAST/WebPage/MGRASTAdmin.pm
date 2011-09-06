package MGRAST::WebPage::MGRASTAdmin;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use Data::Dumper;

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
  $self->application->register_component('Ajax', 'ajax');

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

  # check for MGRAST
  my $html = "";
  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
      $html .= "<h2>The MG-RAST is currently offline. You are the admin, fix it!</h2>";
      return $html;
  }
  $self->{mgrast} = $mgrast;

  $html .= $application->component('ajax')->output();

  # users section
  my $users = $dbmaster->User->get_objects();
  my $uhash = {};
  %$uhash = map { $_->{_id} => $_ } @$users;
  my $data = [];
  foreach my $u (@$users) {
    push(@$data, [ $u->{firstname}, $u->{lastname}, $u->{login}, $u->{email}, $u->{entry_date}, "<input type='button' onclick='execute_ajax(\"user_details\", \"user_details\", \"user=".$u->{login}."\");' value='details'>" ]);
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

  $html .= "<h2>User List</h2><table><tr><td>".$ut->output()."</td><td><div id='user_details'></div></td></tr></table>";

  # jobs section
  my @jobs = $mgrast->Job->get_jobs_for_user_fast($user);
  my $jdata = [];
  @$jdata = sort { $b->[0] cmp $a->[0] } map { [ $_->{created_on}, $_->{metagenome_id}, $_->{job_id}, $_->{name}, $_->{size}, $_->{server_version}, $_->{viewable}, $uhash->{$_->{owner}}->{firstname}, $uhash->{$_->{owner}}->{lastname}, $uhash->{$_->{owner}}->{email}, "<input type='button' value='status' onclick='execute_ajax(\"job_details\", \"job_details\", \"job=".$_->{job_id}."\");'>" ] } @jobs;
  my $jt = $application->component('alljobs_table');
  $jt->show_top_browse(1);
  $jt->show_bottom_browse(1);
  $jt->show_select_items_per_page(1);
  $jt->items_per_page(15);
  $jt->data($jdata);
  $jt->columns( [ { name => 'created', filter => 1, sortable => 1 },
		  { name => 'mgid', filter => 1, sortable => 1 },
		  { name => 'jid', filter => 1, sortable => 1 },
		  { name => 'name', filter => 1, sortable => 1 },
		  { name => 'size', filter => 1, sortable => 1 },
		  { name => 'version', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'viewable', filter => 1, sortable => 1, operator => 'combobox' },
		  { name => 'firstname', filter => 1, sortable => 1 },
		  { name => 'lastname', filter => 1, sortable => 1 },
		  { name => 'email', filter => 1, sortable => 1 },
		  { name => 'status' } ] );
  $html .= "<h2>Job List</h2>".$jt->output()."<br><br><div id='job_details'></div>";

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

sub require_css {
  return [ ];
}

sub require_javascript {
  return [ ];
}

sub required_rights {
  return [ [ 'edit', 'user', '*' ] ];
}
