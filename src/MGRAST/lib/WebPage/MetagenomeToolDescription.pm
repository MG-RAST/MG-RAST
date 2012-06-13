package MGRAST::WebPage::MetagenomeToolDescription;

# $Id: MetagenomeToolDescription.pm,v 1.3 2010-11-19 12:41:52 paczian Exp $

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;

use MGRAST::MGRAST qw( get_menu_metagenome );

1;

=pod

=head1 NAME

MetagenomeSelect - an instance of WebPage which lets the user select a metagenome

=head1 DESCRIPTION

Display an metagenome select box

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('MG-RAST Tool Description');
  $self->require_css(CSS_PATH.'rast_home.css');

  # register components
  $self->application->register_component('FilterSelect', 'MGSelect');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);


  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the OrganismSelect page.

=cut

sub output {
  my ($self) = @_;

  my $id = $self->application->cgi->param('metagenome') || '';
  my $html = "";
 
  $html .= "<div style='float: left; width: 200px; height: 170px; background-color:#86D392; border:2px solid #5DA668;'>";
  $html .= "<div style='font-size: 1.1em; text-align: center;'><b>Navigation</b></div>";
  $html .= "<div style='padding: 10px 0px 0px 10px;'>";
  $html .= "<em><b>Metagenome »</b></em>";
  $html .= "<div style='padding: 0px 0px 20px 20px;'>";
  $html .= "<a href='#seq_profile'><em>Sequence Profile</em></a><br>";
  $html .= "<a href='#blast'><em>BLAST</em></a><br>";
  $html .= "</div>";

  $html .= "<em><b>Compare Metagenomes »</b></em>";
  $html .= "<div style='padding: 0px 0px 20px 20px;'>";
  $html .= "<a href='#heat_map'><em>Heap Map</em></a><br>";
  $html .= "<a href='#recruit_plot'><em>Recruitment Plot</em></a><br>";
  $html .= "<a href='#kegg_map'><em>KEGG Map</em></a><br>";
  $html .= "</div>";
  $html .= "</div>";
  $html .= "</div>";

  $html .= "<div style='font-size: 1.6em; padding-left: 220px; margin-top: 25px;'><b>About MG-RAST tools</b></div>";
  $html .= "<div style='height: 140px; padding-left: 220px; padding-top: 10px; width: 800;'>MG-RAST contains a variety of comparative and visualization tools to assist in the analysis of metagenomic sequences. These tools allow for phylogenetic and metabolic comparisons between your sample and one or more other metagenomes, as well as metabolic comparisons with a single bacterial species.  Overview descriptions of the tools are found below with links to actual tools.  Further detail may be found on the tool pages.</div>";


  # Fragment Profile
  $html .= "<h3><a name='seq_profile'/><em>Metagenome » <a href='metagenomics.cgi?page=MetagenomeProfile&metagenome=$id'>Sequence Profile</a></em></h3>";
  $html .= "<img style='height: 250px;float: right; padding: 0px 0px 20px 20px;' src='./Html/MGRAST-SequenceProfile.jpg' alt='Sequence Profile'>";
  $html .= "<div style='padding: 0 0 15 15; width: 600; text-align: justify'>";
  $html .= "<span style='font-size:1.0em'><b>Metabolic Profile with Subsystem</b></span><br>";
  $html .= "<p>MG-RAST has computed your metabolic profile based on <a href=\" http://www.theseed.org/wiki/Glossary#Subsystem\" target=\"_blank\">Subsystems</a> from the sequences from your metagenome sample. You can modify the parameters of the calculated metabolic profile including e-value, p-value , percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sequence characteristics of your sample. We recommend a minimal alignment length of 50bp be used with all RNA databases.</p>";
  $html .= "<p>Pie charts provide actual counts of sequences that hit a given functional role based on the Subsystem database from the SEED. Subsystems are in a functional hierarchy (eg. Carbohydrates --> Fermentation --> Butanol Biosynthesis (high-level category to subsystem level)) and you can select to view results at 3 levels within that hierarchy. These selections are also represented in the Tabular View.</p>";

  $html .= "<span style='font-size: 1.0em'><b>Phylogenetic Profile based on RDP</b></span><br>";

  $html .= "<p>MG-RAST computes phylogenetic profile base on various RNA databases (RDP, GREENGENES, Silva, and European Ribosomal) the SEED database. RDP is used as a default database to show the taxonomic distributions. You can modify the parameters of the calculated phylogenetic profile including e-value, p-value , percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sample and sequence characteristics of your metagenome.  The SEED database provides an alternative way to identify taxonomies in the sample. Protein encoding genes are BLASTed against the SEED database and the taxonomy of the best hit is used to compile taxonomies of the sample.</p>";
  $html .= "<p>Pie charts provide actual counts of sequences that hit a given taxonomy based on a given database. You can select a given group to get more detailed information up to 4 taxonomic nodes (including species level). These selections are represented in the Tabular View.</p></div>";

  $html .= "<h3><a name='blast'/><em>Metagenome » <a href='metagenomics.cgi?page=MetagenomeBlastRun&metagenome=$id'>BLAST</a></em></h3>";
  $html .= "<img style='height: 200px;float:right' src='./Html/MGRAST-Blast.jpg' alt='Blast'>";
  $html .= "<div style='padding: 0 0 15 15;width: 600; text-align: justify; height: 175px;'>";
  $html .= "<p>Curious if a sequence of interest matches one in your sample? Use the BLAST tool to find out.</p>";
  $html .= "</div>";

  # Heat map
  $html .= "<h3><a name='heat_map'/><em>Compare Metagenomes » <a href='metagenomics.cgi?page=MetagenomeComparison&metagenome=$id'>Heat Map</a></em></h3>";
  $html .= "<img style='height: 155px; float: right;' src='./Html/MGRAST-HeatMap.jpg' alt='Heat Map'>";
  $html .= "<div style='padding: 0 0 15 15;width: 600; text-align: justify; height: 200px;'>";
  $html .= "<p>You can compare your metagenome analysis results (metabolic and phylogeny) with those of other metagenomes. This allows you to compare the prevalence (relative abundance) of different subsystems or taxonomies in different samples. Values can either be actual counts or normalized values. How are the counts normalized? Using the metabolic profile as an example,  the number of sequences in a subsystem are divided by the total number of sequences in a subsystem. This allows for correction based on the sample size. The caveat is that the numbers tend to be small because there will be a few sequences in each metagenome in a subsystem, but a lot of sequences overall.</p>";
  $html .= "</div>";

  # Recruitment plot
  $html .= "<h3><a name='recruit_plot'/><em>Compare Metagenomes » <a href='metagenomics.cgi?page=MetagenomeRecruitmentPlot&metagenome=$id'>Recruitment Plot</a></em></h3>";
  $html .= "<img  style='height: 200px; float: right;' src='./Html/MGRAST-RecruitmentPlot.jpg' alt='Recruitment plot'>";
  $html .= "<div style='padding: 0 0 15 15;width: 600; text-align: justify; height: 200px;'>";
  $html .= "<p>You can compare metabolism of your sample with the metabolic reconstructions from bacterial genomes.  Using the organisms predicted to be in you sample, you can see the metagenome coverage of a given bacteria.</p>";
  $html .= "<p>You can modify the parameters of the fragments included in the plot by e-value, p-value , percent identity and minimum alignment length.</p>";
  $html .= "</div>";

  # KEGG map
  $html .= "<h3><a name='kegg_map'/><em>Compare Metagenomes » <a href='metagenomics.cgi?page=Kegg&organism=$id'>KEGG Map</a></em></h3>";
  $html .= "<img style='height: 175px; float: right;' src='./Html/MGRAST-KEGG.jpg' alt='KEGG map'>";
  $html .= "<div style='padding: 0 0 15 15;width: 600; text-align: justify; height: 250px;'>";
  $html .= "<p>Besides the Metabolic Reconstruction based on Subsystems, MG-RAST also enables uses to view their sample on KEGG maps and compare with others. Mapping of functional roles to KEGG maps was done using functional assignments from analysis against the SEED.  Absolute counts are provided for each KEGG map. These maps are hierarchical, just like the Subsystems, which allows you to compare the sample on various levels.</p>";
  $html .= "</div>";
  return $html;

}
