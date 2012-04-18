package MGRAST::WebPage::MetagenomeFeatures;

# $Id: MetagenomeFeatures.pm,v 1.3 2010-11-19 12:41:52 paczian Exp $

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;

use MGRAST::MGRAST qw( get_menu_metagenome is_public_metagenome );

1;

=pod

=head1 NAME

MetagenomeFeatures - a WebPage which shows all features (ORFS) called for this metagenome

=head1 DESCRIPTION

Feature list page for a metagenome

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Features');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  # sanity check on job
  if ($id) { 
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless ($job) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);
  }

  # register components
  $self->application->register_component('Table', 'FeatureTable');

  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # write title
  my $html = "<h1>Metagenome Features</h1>\n";

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  unless($metagenome) {
    $self->application->add_message('warning', 'No metagenome id given.');
    return "<h2>An error has occured:</h2>\n".
      "<p><em>No metagenome id given.</em></p>";
  }

  # get the job and a FIGV
  my $job = $self->data('job');
  my $fig = $self->application->data_handle('FIG');

  # check if we have a valid fig
  unless ($fig) {
    $self->application->add_message('warning', 'Invalid organism id');
    return "";
  }

  $html .= "<p>&raquo; <a href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome'>Back to Metagenome Overview</a></p>";

  # get sequence data
  my $org_id = $self->app->cgi->param('metagenome');
  my $project_name = $job->project || $job->genome_name;
  my $project_desc = $job->metaxml->get_metadata('project.description') || 'No description available.';
  my $timestamp = $job->metaxml->get_metadata('upload.timestamp') || '';
  my $seqs_num = $job->metaxml->get_metadata('preprocess.count_proc.num_seqs');


  ### TODO
  # GO Terms?
  # Reactions?


  # get features from the database
  my $features = $fig->all_features_detailed_fast($org_id);
  
  # get the subsystem information
  my $subsystem_info = $fig->get_genome_subsystem_data($org_id);
  my $ss_hash = {};
  map { unless(exists($ss_hash->{$_->[2]})) { $ss_hash->{$_->[2]} = {} }; my $sn = $_->[0]; $sn =~ s/_/ /g; $ss_hash->{$_->[2]}->{$_->[0]} = "<a href='metagenomics.cgi?page=Subsystems&subsystem=".$_->[0]."'>".$sn."</a>" } @$subsystem_info;

  # map data to needed format
  # Feature ID (0), Type (1), Contig (2), Start (3), Stop (4), Length (5), Function (6), EC(7)
  my @data = map { my $id = $_->[0];
		    my $loc = FullLocation->new($fig, $org_id, $_->[1]);
		    $_->[3] = ($_->[3] ne 'peg') ? $_->[3] : 'CDS';
		    my $length = 0;
		    map { $length += $_->Length } @{$loc->Locs};
		    my @ec; 
		    while($_->[6] and $_->[6] =~ /\(EC (\d+\.\d+\.\d+\.\d+)\)/g) { 
		      push @ec, "<a href='http://www.genome.jp/dbget-bin/www_bget?ec:$1' target=outbound>$1</a>";
		    }
		    [ $_->[0], uc($_->[3]), $loc->Contig, $loc->Begin, $loc->EndPoint, $length, $_->[6], scalar(@ec) ? join(', <br>', @ec) : '' ] 
		  } @$features;

  # fill the table data
  my @table_data = map { [ "<a href='metagenomics.cgi?page=Annotation&feature=".$_->[0]."'>".$_->[0]."</a>", 
			   $_->[1],
			   "<a href='metagenomics.cgi?page=MetagenomeSequence&metagenome=".$org_id."&sequence=".$_->[2]."'>".$_->[2]."</a>",  
			   $_->[3], $_->[4], $_->[5], 
			   $_->[7],
			   $_->[6] || '', 
			   ($ss_hash->{$_->[0]}) ? join(',<br> ', values(%{$ss_hash->{$_->[0]}})) : "none" ] } 
    sort { my ($a1, $a2, $a3) = $a->[0] =~ /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/; 
	   my ($b1, $b2, $b3) = $b->[0] =~ /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/; 
	   $a1 <=> $b1 || $a2 cmp $b2 || $a3 <=> $b3 } @data;
  
  # create feature table
  my $ftable = $self->application->component('FeatureTable');
  $ftable->show_select_items_per_page(1);
  $ftable->items_per_page(15);
  $ftable->show_top_browse(1);
  $ftable->show_bottom_browse(1);
  $ftable->show_export_button({ strip_html => 1 });
  $ftable->show_clear_filter_button(1);
  $ftable->width(980);
  $ftable->columns( [ { 'name' => 'Feature ID', 'sortable' => 1, 'filter' => 1, 'width' => '110', 'operator' => 'equal' },
		      { 'name' => 'Type', 'sortable' => 1, 'filter' => 1, 'operator' => 'combobox', 'width' => '60' },
		      { 'name' => 'Contig', 'sortable' => 1, 'filter' => 1, 'width' => '80' },
		      { 'name' => 'Start', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '75' },
		      { 'name' => 'Stop', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '75' },
		      { 'name' => 'Length', 'sortable' => 1, 'filter' => 1, 'operators' => [ 'less', 'more' ], 'width' => '75' },
		      { 'name' => 'EC', 'sortable' => 1, 'filter' => 1 },
		      { 'name' => 'Function', 'sortable' => 1, 'filter' => 1 },
		      { 'name' => 'Subsystem(s)', 'sortable' => 1, 'filter' => 1, 'operand' => '' } ] );
  
  $ftable->data(\@table_data);


  # add general organism data and info box
  $html .= "<div>";
  $html .= "<table>";
  $html .= "<tr><th>Metagenome</th><td>".$job->genome_name." (".$job->genome_id.")</td></tr>";
  $html .= "<tr><th>Project:</th><td>".$project_name."</td></tr>";
  $html .= "<tr><th>Description:</th><td>".$project_desc."</td></tr>";
  $html .= "<tr><th>Uploaded on:</th><td>".localtime($timestamp)."</td></tr>";
  $html .= "<tr><th>Total no. of sequences</th><td>$seqs_num</td></tr>";
  $html .= "<tr><th>Number of called features:</th><td>".scalar(@table_data)."</td></tr>";
  $html .= "</table></div>\n";

  
  # information text
  $html .= "<p>Insert short blurb about ORF calling</p>";
  

  # add table
  $html .= "<div>".$ftable->output()."</div>";

  return $html;

}
