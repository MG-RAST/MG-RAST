package MGRAST::WebPage::DownloadFile;

use strict;
use warnings;

use base qw( WebPage );
use WebConfig;

use File::Basename;
1;


=pod

=head1 NAME

DownloadFile - an instance of WebPage provides a file download

=head1 DESCRIPTION

Download File page 

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Download File");
  $self->omit_from_session(1);

  # sanity check on job
  my $id = $self->application->cgi->param('job') || '';
  my $job;
  eval { $job = $self->app->data_handle('MGRAST')->Job->init({ id => $id }); };
  unless ($job) {
    $self->app->error("Unable to retrieve the job '$id'.");
  }
  $self->data('job', $job);

}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $job = $self->data('job');
  my $base = $self->app->cgi->param('file');
  if ($base =~ m,/,)
  {
    $self->app->error("Unable to find file for job ".$job->id.": $base");
    return;
  }
  my $file = $job->download_dir . "/$base";
  my $filename = $base;

  if (! -f $file )
  {
      if ( $base =~ /.gbk.gz$/ ) {
	  $file = $job->directory() . "/$base";
	  $filename = $base;
      } elsif ( $base eq 'contigs' ) {
	  $file = $job->directory() . '/rp/' . $job->genome_id . "/$base";
	  $filename = $job->genome_id . "_dna.fasta";
      } elsif ( $base eq $job->genome_id . '.fasta' ) {
	  my @seq = grep {/\.unformatted$/} glob($job->directory() . "/raw/*");
	  if ( @seq == 1 ) {
	      $file = $seq[0];
	      $filename = $base;
	  } else {
	      $self->app->error("Unable to find submitted sequence file for job " . $job->id);
	      return;
	  }
      } elsif ( $base eq $job->genome_id . '.qual') {
	  my @qual = grep {/\.qual$/} glob($job->directory() . "/raw/*");
	  if ( @qual == 1 ) {
	      $file = $qual[0];
	      $filename = $base;
	  } else {
	      $self->app->error("Unable to find submitted sequence quality file for job " . $job->id);
	      return;
	  }
      } elsif ( $base eq 'tbl' ) {
	  $file = $job->directory() . '/rp/' . $job->genome_id . "/Features/peg/$base";
	  $filename = $job->genome_id . "_aa_locations.txt";
      } elsif ( $base eq 'fasta' ) {
	  $file = $job->directory() . '/rp/' . $job->genome_id . "/Features/peg/$base";
	  $filename = $job->genome_id . "_aa.fasta";
      } elsif ( $base eq 'assigned_functions' ) {
	  $file = $job->directory() . '/rp/' . $job->genome_id . '/assigned_functions';
	  $filename = $job->genome_id . "_assigned_functions.txt";
      } elsif ( $base eq 'bindings' ) {
	  $file = $job->directory() . '/rp/' . $job->genome_id . '/Subsystems/bindings';
	  $filename = $job->genome_id . "_aa_subsystems.txt";
      }
  }

  if (-f $file) {
    open(FILE, $file) or 
      $self->app->error("Unable open export file for job ".$job->id.": $filename");
    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . (stat($file))[7] . "\n";
    print "Content-Disposition:attachment;filename=$filename\n\n";
    while(<FILE>) {
      print $_;
    }
    close(FILE);
    exit;
  }
  else {
    $self->app->error("Unable open find file for job ".$job->id.": $file");
  }

  return;

}




