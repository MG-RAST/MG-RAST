package WebPage::PrivateOrganismPreferences;

use strict;
use warnings;

use base qw( WebPage );

use Conf;
use Data::Dumper;

1;

=pod

#TITLE PrivateOrganismPreferencesPagePm

=head1 NAME

PrivateOrganismPreferences - an instance of WebPage which handles preferences for private organisms

=head1 DESCRIPTION

Display a selection of accessible private organisms and offer the option of
computing similarities between them. Select which organisms should be in the
active set to always be included in FIGM.

=head1 METHODS

=over 4

=item * B<init> ()

Initialize the page

=cut

sub init {
  my $self = shift;
  
  $self->title('Private Organism Preferences');
  $self->application->register_component('Table', 'available_sims_table');
  $self->application->register_component('ListSelect', "ListSelect");
  $self->application->register_component('Ajax', 'PeerAjax');
  $self->application->register_action($self, 'set_peers', 'set_peers');
  $self->application->register_action($self, 'request_similarities', 'request_similarities');

}

=pod

=item * B<output> ()

Returns the html output of the PrivateOrganismPreferences page.

=cut

sub output {
  my ($self) = @_;

  # get some variables
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $user = $application->session->user();
  my $fig = $application->data_handle('FIG');

  # check if the current session has a user
  unless (defined($user)) {
    $application->add_message('warning', 'You must be logged in to see this page');
    return "<a href='?page=Login'>return to login page</a>";
  }

  # get the available RAST organisms
  my $rast = $application->data_handle('RAST');
  unless (ref($rast)) {
    $application->add_message('warning', "Could not connect to the private organism database, aborting.");
    return "";
  }
  my @jobs = $rast->Job->get_jobs_for_user_fast($user, 'view', 1);
  unless (scalar(@jobs)) {
    $application->add_message('info', "You currently do not have access to any private organisms.");
    return "";
  }
  my $jobs_hash = {};
  %$jobs_hash = map { $_->{id} => $_ } @jobs;

  # hash the available genomes
  my $genomes = {};
  %$genomes = map { $_->{genome_id} => $_->{id} } @jobs;

  # get the current peer preferences
  my $dbm = $application->dbmaster;
  my %peers;
  my $prefs = $dbm->Preferences->get_objects( { user => $user, name => 'PrivateOrganismPeer' } );
  foreach my $pref ( @$prefs ) {
    if ($genomes->{$pref->value}) {
      $peers{$genomes->{$pref->value}} = $pref->value;
    }
  }

  # construct the content
  my $content = "";

  # print current peers
  $content .= "<h2>Current Private Organism Peers</h2>";
  $content .= "<div style='width: 800px; text-align: justify;'>This is the list of private organism peers. This means that these organisms will be included in any comparison of organisms, such as a compared regions view or a subsystem diagram. Peers must have similarities computed between the entire group.<br><br>You can choose from the list of available organisms and click 'check requirements'. The neccessary amount of computation will be displayed and you can confirm or cancel the request.</div>";

  # get the available organisms  
  my $availables = [];
  foreach my $job (sort { $a->{id} <=> $b->{id} } @jobs) {
    push(@$availables, { value => $job->{id},
			 label => "Job ".$job->{id}.": ".$job->{genome_name} . " (" . $job->{genome_id} .")" });
  }

  # get the peer group
  my $peer_group = [];
  foreach my $peer (keys(%peers)) {
    push(@$peer_group, $peer);
  }

  # fill the list box
  my $list_select = $application->component('ListSelect');
  $list_select->data($availables);
  $list_select->preselection($peer_group);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->left_header('Available');
  $list_select->right_header('Peers');
  $list_select->name('peers');

  # add javascript for submitting the requested peer list
  $content .= $self->submit_js();

  # create the check_requirements form
  $content .= $application->component('PeerAjax')->output;
  $content .= $self->start_form('check_requirements');
  $content .= "<br>" . $list_select->output();
  $content .= "<br><input type='button' value='check requirements' onclick=\"submit_check('".$list_select->id."');\"><br>".$self->end_form()."<div id='result_div'></div>";

  return $content;
}

sub request_similarities {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;

  # check for the requests
  my @sim_requests = $cgi->param('sim_requests');

  # check if there is anything to do
  unless (scalar(@sim_requests)) {
    $application->add_message('warning', "no similarities were requested");
    return "";
  }

  my $jobs = {};
  foreach my $request (@sim_requests) {
    my ($job1, $job2) = $request =~ /(.*)-(.*)/;
    $jobs->{$job1} = 1;
    $jobs->{$job2} = 1;
  }
  my $joblist = join(" ", keys(%$jobs));
  my $command = $Conf::bin."/rp_request_peer_sims $joblist";

  if (open(P, "$command 2>&1 |"))
  {
      local $/;
      undef $/;
      my $res = <P>;
      if (close(P))
      {
	  $application->add_message('info', "Similarity calculations have been sucessfully requested for jobs $joblist");
      }
      else
      {
	  my $b = $!;
	  my $q = $?;
	  if ($b)
	  {
	      warn "error closing pipe from $command: $b";
	      warn $res;
	      $application->add_message('info', "An error was encountered requesting similarity calculations for jobs $joblist: $b");
	  }
	  else
	  {
	      warn "error status from $command: $q";
	      warn $res;
	      $application->add_message('info', "An error was encountered requesting similarity calculations for jobs $joblist: $q");
	  }
      }
  }
  else
  {
      my $b = $!;
      warn "error opening pipe from $command: $b";
      $application->add_message('info', "An error was encountered requesting similarity calculations for jobs $joblist: $b");
  }	  

  return "";
}

sub set_peers {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  # check if we have a user
  unless (defined($user)) {
    $application->add_message('warning', "Cannot set peer group without a user, aborting.");
    return;
  }

  # get the current preferences from the db
  my $dbm = $application->dbmaster;
  my %peer_prefs_hash = map { $_->value => $_ } @{$dbm->Preferences->get_objects( { user => $user, name => 'PrivateOrganismPeer' } )};

  # get the new preferences from cgi
  my @new_peers = $cgi->param('peers');

  # get the available RAST organisms
  my $rast = $application->data_handle('RAST');
  unless (ref($rast)) {
    $application->add_message('warning', "Could not connect to the private organism database, aborting.");
    return "";
  }
  
  # map the genome ids to job ids
  my $jobs_hash = {};
  my $genomes_hash = {};
  foreach my $j (@new_peers) {
    my $job = $rast->Job->init( { id => $j } );
    if (ref($job)) {
      $jobs_hash->{$job->id} = $job;
      $genomes_hash->{$job->id} = $job->genome_id;
    }
  }  
  
  # hash the peers
  my %new_peers_hash = map { $_ => 1 } @new_peers;
  
  # delete unwanted preferences
  foreach my $pref_id (keys(%peer_prefs_hash)) {
    unless ($new_peers_hash{$jobs_hash->{$pref_id}}) {
      my $pref = $peer_prefs_hash{$pref_id};
      $pref->delete;
    }
  }

  # create new preferences
  foreach my $peer (@new_peers) {
    unless (exists($peer_prefs_hash{$genomes_hash->{$peer}})) {
      $dbm->Preferences->create( { user => $user,
				   name => 'PrivateOrganismPeer',
				   value => $genomes_hash->{$peer} } );
    }
  }

  $application->add_message('info', "Your peer group has been set to your new selection.");

  return "";
}

sub required_rights {
  my ($self) = @_;

  my $user = '-';
  if ($self->application->session->user) {
    $user = $self->application->session->user->_id;
  }
  
  return [ [ 'edit', 'user', $user ] ];
}

sub sim_status {
  my ($self, $job1, $job2) = @_;

  my $command = $Conf::bin."/rp_peer_sim_status ".$job1." ".$job2;
  my $status = `$command`;
  chomp $status;

  return $status;
}

sub check_requirements {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $content = "";

  # get the peers list
  my @peers = $cgi->param('peers');
  
  # get the available RAST organisms
  my $rast = $application->data_handle('RAST');
  unless (ref($rast)) {
    return "Could not connect to the private organism database, aborting.";
  }

  my $jobs_hash = {};
  foreach my $j (@peers) {
    my $job = $rast->Job->init( { id => $j } );
    if (ref($job)) {
      $jobs_hash->{$job->id} = $job;
    }
  }

  # check the sim status
  my $sim_status = {};
  foreach my $j2 (@peers) {
    my $job = $jobs_hash->{$j2};
    foreach my $jid (@peers) {
      next if ($jid == $job->id);
      my $cgid = $jobs_hash->{$jid}->genome_id;
      my $sim_dir = $job->org_dir."/sims";
      if (opendir(DIR, $sim_dir)) {
	closedir(DIR);
	if ( -f $sim_dir."/".$cgid.".queued" ) {
	  $sim_status->{$job->genome_id}->{$cgid} = "queued";
	} elsif ( -f $sim_dir."/".$cgid.".in_progress" ) {
	  $sim_status->{$job->genome_id}->{$cgid} = "in_progress";
	} elsif ( -f $sim_dir."/".$cgid ) {
	  $sim_status->{$job->genome_id}->{$cgid} = "complete";
	} else {
	  $sim_status->{$job->genome_id}->{$cgid} = "missing";
	}
      } else {
	mkdir $sim_dir;
	$sim_status->{$job->genome_id}->{$cgid} = "missing";
      }
    }    
  }

  # start the return content
  $content .= "<h2>Similarities for current selection</h2>";
  $content .= "<div style='width: 800px; text-align: justify;'>The following table represents the current status of  similarity computations for your peer selection.</div>";

  # create columns
  my $sim_cols = [ '' ];
  my $sim_data = [];
  my $ready_to_set = 1;
  my $need_compute = {};
  foreach my $job1 (@peers) {
    next unless (defined($jobs_hash->{$job1}));
    push(@$sim_cols, { name => $jobs_hash->{$job1}->genome_id, tooltip => $jobs_hash->{$job1}->genome_name });

    my $row = [ { data => "<span style='color: white; font-weight: bold;'>".$jobs_hash->{$job1}->genome_id."</span>", tooltip => $jobs_hash->{$job1}->genome_name, highlight => '#688FC5' } ];
    foreach my $job2 (@peers) {
      if ($jobs_hash->{$job1}->genome_id eq $jobs_hash->{$job2}->genome_id) {
	push(@$row, { data => 'n/a', highlight => '#B9B9B9' });
      } else {
	my $status = $sim_status->{$jobs_hash->{$job1}->genome_id}->{$jobs_hash->{$job2}->genome_id};
	my $color = '#ffffff';
	if ($status eq 'queued') {
	  $ready_to_set = 0;
	  $color = "#1E78DC";
	} elsif ($status eq 'in_progress') {
	  $ready_to_set = 0;
	  $color = "#FFBE1E";
	  $status = "in progress";
	} elsif ($status eq 'missing') {
	  $ready_to_set = 0;
	  $need_compute->{$job1."-".$job2} = 1;
	  $color = "#FF1E1E";
	  $status = "computation required";
	} elsif ($status eq 'complete') {
	  $color = "#3CA53C";
	}
	push(@$row, { data => $status, highlight => $color });
      }
    }
    push(@$sim_data, $row);
  }

  # check if we should offer to compute or if we can already set peers
  if ($ready_to_set) {
    my $peer_string = join('', map { '<input type="hidden" name="peers" value="'.$_.'">' } @peers);
    $content .= "<p style='width: 800px; text-align: justify;'>All required similarities are available. To set your peers to the current selection click 'set peers'.</p>" .$self->start_form('set_peers_form', { action => 'set_peers'}).$peer_string."<input type='submit' value='set peers'>".$self->end_form();
  } else {
    if (scalar(keys(%$need_compute))) {
      my $need_compute_string = join('', map { "<input type='hidden' name='sim_requests' value='".$_."'>"; } keys(%$need_compute));
      my $num = scalar(keys(%$need_compute))/2;
      $num = ($num > 1) ? "are $num similarity computations necessary for your selection which have" : "is $num similarity computation necessary for your selection which has";
      $content .= "<p style='width: 800px; text-align: justify;'>There $num not yet been requested. Once they are completed, you can set your peers to your current selection. You may also remove organisms with missing computations to change your selection now. To request those computations click 'request computation'.</p>".$self->start_form('request_computation_form', { action => 'request_similarities' }).$need_compute_string."<input type='submit' value='request computation'>".$self->end_form();
      } else {
	$content .= "<p style='width: 800px; text-align: justify;'>The computations for the current selection are not yet completed. You can wait for the computations to complete or remove organisms with incomplete computations from the list. You can then change your peer group selection.</p>";
      }
  }

  # get the sims table
  my $sims_table = $application->component('available_sims_table');
  $sims_table->columns($sim_cols);
  $sims_table->data($sim_data);
  $content .= $sims_table->output()."<br>";

  # return requirements
  return $content;
}

sub submit_js {
  return qq~<script>
function submit_check (id) {
  var select = document.getElementById('list_select_list_b_' + id);
  var param_string = "";
  for (i=0;i<select.options.length;i++) {
    param_string += 'peers=' + select.options[i].value + '&';
  }
  execute_ajax('check_requirements', 'result_div', param_string, 'checking...');
}
</script>
~;
}
