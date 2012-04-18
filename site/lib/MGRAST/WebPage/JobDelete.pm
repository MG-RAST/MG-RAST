package MGRAST::WebPage::JobDelete;

use strict;
use warnings;

use POSIX;

use base qw( WebPage );
use WebConfig;

use MGRAST::MGRAST qw( get_menu_job );

1;


=pod

=head1 NAME

JobDelete - an instance of WebPage which allows to delete a job

=head1 DESCRIPTION

Job Delete page 

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Delete a job");

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

}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $content = '<h1>Delete a job</h1>';

  my $job = $self->data('job');
  
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=Jobs'>Back to the Jobs Overview</a></p>";
  unless ($self->application->cgi->param('confirm')) {
    $content .= "<p> &raquo <a href='metagenomics.cgi?page=JobDetails&job=".$job->id."'>Back to the Job Details</a></p>";
  }
    
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Job Information</p>";
  $content .= "<table>";
  $content .= "<tr><th>Name - ID:</th><td>".$job->genome_id." - ".$job->genome_name."</td></tr>";
  $content .= "<tr><th>Type:</th><td>".$job->type."</td></tr>";
  $content .= "<tr><th>Job:</th><td> #".$job->id."</td></tr>";    
  $content .= "<tr><th>User:</th><td>".$job->owner->login."</td></tr>";
  $content .= "</table>";
    
  if ($self->application->cgi->param('confirm')) {
    
    $job->mark_for_deletion();
    $content .= "<p><strong>This job has been deleted.</strong></p>";    

  }
  else {
    $content .= "<p><strong>To confirm the deletion of this job, please click the button.</p>";
    $content .= $self->start_form('delete', { job => $job->id } );
    $content .= "<p><input type='submit' name='confirm' value=' Delete this job '></p>";
    $content .= $self->end_form();
  }
    
 
  return $content;
  
}


=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  my $rights = [ [ 'login' ] ];
  push @$rights, [ 'delete', 'metagenome', $_[0]->data('job')->genome_id ]
    if ($_[0]->data('job'));
      
  return $rights;
}



