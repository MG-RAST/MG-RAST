package MGRAST::WebPage::MetagenomeSubsetDownload;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use URI::Escape;

use WebComponent::WebGD;

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset is_public_metagenome dataset_is_metabolic );

1;


=pod

=head1 NAME

MetagenomeSubsetDownload - an instance of WebPage which downloads the metagenome 
blast information belonging to a given classification

=head1 DESCRIPTION

For any given classification (like a subsystem category or a taxonomy node)
retrieve BLAST hit data from the database.

NB: The table displayed on the MetagenomeSubset page limits the export (as well as the display)
to 10,000 entries, MetagenomeSubsetDownload will export the entire dataset.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Sequence Subset');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # load the settings for this type
  &get_settings_for_dataset($self);

  # sanity check on job
  if ($id) { 
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless ($job) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);
    
    # init the metagenome database
    my $mgdb = MGRAST::MetagenomeAnalysis->new($job);
    unless ($mgdb) {
      $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      return 1;
    }
    $mgdb->query_load_from_cgi($self->app->cgi, $self->data('dataset'));
    $self->data('mgdb', $mgdb);
  }

  return 1;
}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;
  my $cgi = $self->app->cgi;

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  unless($metagenome) {
    $self->application->error('No metagenome id given.');
  }

  # get parameters
  my $rank = $self->app->cgi->param('rank') || 0;
  my $taxonomy = $self->app->cgi->param('get') || '';
  $taxonomy = uri_unescape($taxonomy);
  my $filter_taxa = $self->data('mgdb')->split_taxstr($taxonomy);
  my $get = [];
  foreach (my $i=0; $i<=$rank; $i++) {
    push @$get, $filter_taxa->[$i];
  }
  my $genome = $self->app->cgi->param('genome') || '';

  # write title + intro
  my $metagenome_name = $self->data('job')->genome_name;
  my $metagenome_id   = $self->data('job')->genome_id;

  # get the data
  my $filter = $self->data('mgdb')->join_taxstr($get);
  my $data;
  unless($genome){
    $data = $self->data('mgdb')->get_sequence_subset($self->data('dataset'), $filter);
  } else {
    $data = $self->data('mgdb')->get_sequence_subset_genome($genome);
  }

  my $dataset = $self->data('dataset');
  my $params_text = "Based on: $dataset\n";

  my $evalue = $cgi->param('evalue');
  if ( defined($evalue) and $evalue ne '' ) {
      $params_text .= "Maximum E-Value: $evalue\n";
  }

  my $align_len = $cgi->param('align_len');
  if ( $align_len ) {
      $params_text .= "Minimum alignment length: $align_len\n";
  }

  my $identity = $cgi->param('identity');
  if ( $identity ) {
      $params_text .= "Minimum percent identity: $identity\n";
  }
 
  print "Content-Type:application/x-download\n";  
  print "Content-Disposition:attachment;filename=sequence_subset.txt\n\n";

  print "MG-RAST Download: Sequence Subset from Metagenome '$metagenome_name' ($metagenome_id)\n\n";
  print $params_text, "\n";
  print join("\t", 'Sequence ID', 'Alignment length', 'E-value', 'Percentage identity', 'Bit score', 'Fragment start', 'Fragment end', 'Taxonomy assignment', 'Best hit ID'), "\n\n";

  foreach my $row (@$data) {
    if ($self->data('dataset') =~ /Silva:ssu/) {
	my $ssu_id = $row->[2];
	($ssu_id) = $row->[2] =~ m/(.*?)\./;
	$row->[2] = $ssu_id;
    }
    elsif ($self->data('dataset') =~ /Silva:lsu/) {
	my $lsu_id = $row->[2];
	($lsu_id) = $row->[2] =~ m/(.*?)\./;
	$row->[2] = $lsu_id;	
    }

    my $taxa = $self->data('mgdb')->split_taxstr($row->[3]);
    my $evalue = sprintf("%2.2e", $self->data('mgdb')->log2evalue($row->[4]));
    $row->[3] = $self->data('mgdb')->key2taxa($taxa->[scalar(@$taxa)-1]);

    print join("\t", $row->[0],$row->[1],$evalue,$row->[6],$row->[5],$row->[7],$row->[8],$row->[3],$row->[2]) . "\n";
  }

  exit;
}

