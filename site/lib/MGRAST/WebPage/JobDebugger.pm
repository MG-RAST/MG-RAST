package MGRAST::WebPage::JobDebugger;

use strict;
use warnings;

use POSIX;
use File::Basename;

use base qw( WebPage );
use WebConfig;

use MGRAST::MGRAST qw( get_menu_job );

1;


=pod

=head1 NAME

JobDebugger - an instance of WebPage which displays debug information on a job

=head1 DESCRIPTION

Job Debugger page 

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Job Debugger");

  $self->app->register_component('Ajax', 'Ajax');

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

  my $content = '<h1>Job Debugger</h1>';

  my $job = $self->data('job');
   
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=Jobs'>Back to the Jobs Overview</a></p>";
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=JobDetails&job=".$job->id."'>Back to the Job Details</a></p>";
    
  # job details
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Job Information</p>";
  $content .= "<table>";
  $content .= "<tr><th>Name - ID:</th><td>".$job->genome_id." - ".$job->genome_name."</td></tr>";
  $content .= "<tr><th>Type:</th><td>".$job->type."</td></tr>";
  $content .= "<tr><th>Job:</th><td> #".$job->id."</td></tr>";    
  $content .= "<tr><th>Directory:</th><td>".$job->dir."</td></tr>";
  $content .= "<tr><th>User:</th><td>".$job->owner->login."</td></tr>";
  $content .= "<tr><th>Active:</th><td>".$job->active."</td></tr>";
  $content .= "<tr><th>To be deleted:</th><td>".$job->to_be_deleted."</td></tr>";
  $content .= "</table>";
    
  # error and report files
  $content .= $self->app->component('Ajax')->output;
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Error and report files</p>";
  
  # get files
  my $job_dir = $job->dir;
  my $org_dir = $job->org_dir;
  my @files = <$job_dir/rp.errors/*.stderr>;
  push(@files, <$org_dir/*.report>);
  @files = map { basename($_) } sort @files;
  
  if (@files) {
    $content .= $self->start_form('files', 1);
    $content .= $self->app->cgi->popup_menu( -name => 'files',
					     -id => 'filename',
					     -values=> \@files, );
    $content .= "<input type='button' value=' Load File ' onclick='execute_ajax(\"load_file\",\"file_content\",\"files\",\"Loading file, please wait.\");'";
    my $url = $self->application->url."?page=ShowErrorFile&job=".$job->id;
    $content .= "<input type='button' value=' Load in new window ' onclick='window.open(\"$url&file=\"+document.getElementById(\"filename\").options[document.getElementById(\"filename\").selectedIndex].value,\"_blank\");'>";
    $content .= $self->end_form;
    $content .= "<div id='file_content'></div>\n";
  }
  else {
    $content .= "<p>No files available.</p>";
  }

  # meta xml 
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>MetaXML Dump</p>";
  $content .= "<table>";
  for my $key (sort $job->metaxml->get_metadata_keys()) {
    my $value = $job->metaxml->get_metadata($key);
    if (ref($value) eq 'ARRAY') {
      $value = join(', ',@$value);
    }
    $value = '' unless (defined $value);
    $content .= "<tr><th>".$key."</th><td>".$value."</td></tr>";
  }
  $content .= "</table>";
  
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>MetaXML Log</p>";
  $content .= "<table>";
  for my $ent (@{$job->metaxml->get_log()}) {
    my ($type, $ltype, $ts, $entry) = @$ent;
    next unless $type eq 'log_entry';
    $ts = strftime('%c', localtime $ts);
    $ltype =~ s,.*/,,;
    $entry = join('&nbsp;&nbsp; || &nbsp;&nbsp;',@$entry) if (ref($entry) eq 'ARRAY');
    $content .= "<tr><th>".$ts."</th><th>".$ltype."</th><td>".$entry."</td></tr>";
  }
  $content .= "</table>";
  
    
  return $content;
  
}


=pod

=item * B<supported_rights>()

Returns a reference to the array of supported rights

=cut

sub supported_rights {
  return [ [ 'debug', '*', '*' ],
	 ];
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


=pod

=item * B<load_file>()

Ajax method to load and display the content of a file

=cut

sub load_file {
  my $self = shift;

  my $job = $self->data('job');
  my $file = $self->app->cgi->param('files');
  
  my $content = "<p> &raquo <a href='metagenomics.cgi?page=JobDebugger&job=".
    $job->id."'>Hide this error report</a></p>";
	
  my $path = $job->org_dir."/$file";
  -f $path or $path = $job->dir."/rp.errors/$file";
  
  # check filesize 
  my $size = -s $path;
  if ($size > 65536) {
    return "<p>File is too large. Please use the console to look at $path.</p>";
  }
  if ($size == 0) {
    return "<p>File is empty.</p>";
  }

  if (open(F, "<$path")) {
    $content .= "<pre style='overflow: scroll; width: 680px;'>\n";
    my @fc = <F>;
    $content .= join('',@fc);
    $content .= "</pre>\n";
    close(F);
  }
  else {
    $content .= "File $file not found in job ".$job->id."\n";
  }  
  
  return $content;

}

