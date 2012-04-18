package MGRAST::WebPage::JobPriority;

use base qw( WebPage );

1;

use strict;
use warnings;
use WebConfig;
use MGRAST::MGRAST qw( get_menu_job );

=pod

=head1 NAME

JobPriority - an instance of WebPage to change the priority of a job

=head1 DESCRIPTION

Change the priority of a job for the backend

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Change the job priority');
  $self->application->register_action($self, 'change_priority', 'change_priority');

  # sanity check on job
  my $id = $self->application->cgi->param('job') || '';
  my $job;
  eval { $job = $self->app->data_handle('MGRAST')->Job->init({ id => $id }); };
  unless ($job) {
    $self->app->error("Unable to retrieve the job '$id'.");
  }
  $self->data('job', $job);

  # add links
  &get_menu_job($self->app->menu, $job);
  
  return 1;
}

=item * B<output> ()

Returns the html output of the DelegateRights page.

=cut

sub output {
  my ($self) = @_;

  my $job = $self->data('job');

  my $content = "<h1>Change the job priority</h1>";

  # short job info
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=JobDetails&job=".$job->id."'>Back to the Job Details</a></p>";
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=Jobs'>Back to the Jobs Overview</a></p>";
  
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Job Information</p>";
  $content .= "<table>";
  $content .= "<tr><th>Name - ID:</th><td>".$job->genome_id." - ".$job->genome_name."</td></tr>";
  $content .= "<tr><th>Type:</th><td>".$job->type."</td></tr>";
  $content .= "<tr><th>Job:</th><td> #".$job->id."</td></tr>";    
  $content .= "<tr><th>User:</th><td>".$job->owner->login."</td></tr>";
  $content .= "</table>";


  # change form
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Job Priority</p>";
  $content .= '<p style="width: 70%;">To change the priority of the job please select the priority below and confirm by clicking the button:</p>';
  $content .= $self->start_form('share_job', { job => $job->id,
					       action => 'change_priority' });
  my $prio = $job->priority;
  $content .= "<p><strong>Select job priority: </strong>";
  $content .= $self->app->cgi->popup_menu(-name    => 'priority',
					  -values  => [ 'low', 'medium', 'high' ],
					  -default => $prio,
					 );
  $content .= "<input type='submit' name='change_priority' value=' Set '></p>";
  $content .= $self->end_form;

  return $content;


}


=pod

=item * B<change_priority>()

Action method to change the priority of the selected job

=cut

sub change_priority {
  my ($self) = @_;

  my $job = $self->data('job');

  # get the priority
  my $prio = $self->app->cgi->param('priority');
  unless($job->is_valid_priority($prio)) {
    $self->app->add_message('warning', 'There has been an error: invalid job priority given, aborting.');
    return 0;
  }

  # set it
  $job->priority($prio);
  $self->app->add_message('info', "Set the priority of this job to '$prio'.");

  return 1;

}


=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  my $rights = [ [ 'login' ],
		 [ 'debug' ], ];
  push @$rights, [ 'edit', 'metagenome', $_[0]->data('job')->genome_id ]
    if ($_[0]->data('job'));
      
  return $rights;
}

