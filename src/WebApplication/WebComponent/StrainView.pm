package WebComponent::StrainView;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

StrainView - view currently selected strain

=head1 DESCRIPTION

WebComponent for a strain select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('TabView', 'StrainTV');
  $self->application->register_component('IntervalTable', 'interval_table');
  $self->application->register_component('GeneTable', 'strain_view_gene_table');
  $self->application->register_component('GrowthData', 'growth_display');
  $self->application->register_component('RollerBlind', 'strain_view_rb');
  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {

  my ($self) = @_;

  my $html = "";

  # Getting various application objects 
  my $application = $self->application();
  my $model = $application->data_handle('FIGMODEL');
  my $user = $application->session->user;
  my $cgi = $application->cgi();
  my $CGI_Page = $cgi->param( 'page' );

  # getting web components
  my $interval_table = $application->component('interval_table');
  my $strain_tv = $application->component('StrainTV');
  my $growth_display = $application->component('growth_display');
  my $gene_table = $application->component('strain_view_gene_table');

  # getting the strain data
  my $StrainTable = $model->GetDBTable("STRAIN TABLE");
  my $SimulationTable = $model->GetDBTable("STRAIN SIMULATIONS");
  my $IntervalTable = $model->GetDBTable("INTERVAL TABLE");
 
  # Get CGI parameters 
  my $Strain = $cgi->param( 'id' );
  # Configer that Strain was provided (should be done by WebPage, but check again to be sure) 
  unless(defined($Strain)) { 
	$application->redirect('StrainSelect');
	$application->add_message('info', "No strain selected, please select a strain to view.");
	$application->do_redirect();
	exit;
  }

  my $row = $StrainTable->get_row_by_key($Strain, "ID");
  unless($row) {
	$application->add_message('Warning', "No interval with ID $Strain.");
	exit;
  }

  # Get simulation results
  my $sim = $SimulationTable->get_row_by_key($Strain, 'ID');
  # Get growth output.
  my $growthstr = $growth_display->output($Strain);
   
  my $Intervals = $row->{'INTERVALS'};
  my $IntervalTabText .= $interval_table->output(900, 0, join(',', @{$Intervals})); 

  my $PredictionsTabText = "Will eventually predict fitness of new strains; suggest changes.";
  if(defined($sim->{'PREDICTIONS'})) { $PredictionsTabText = join(',', @{$sim->{'PREDICTIONS'}}); }

  my $GeneInformationTabText = $gene_table->output(900, 'figstr|224308.1.'.$Strain);
  my $DiscussionTabText = "Will eventually have a comment system for discussions.";
  
  # Configure the Tab View element
  $strain_tv->width(900);
  $strain_tv->height(400);
  $strain_tv->add_tab('Gene Information', $GeneInformationTabText);
  $strain_tv->add_tab('Intervals knocked out', $IntervalTabText);
  $strain_tv->add_tab('Predictions', $PredictionsTabText);
  $strain_tv->add_tab('Discussion', $DiscussionTabText);

  my $genomeSize = 4214814;
  my $geneCount  = 0;
  my $rxnCount = 0;
  foreach my $interval (@{$Intervals}) {
	  my $intervalRow = $IntervalTable->get_row_by_key($interval, 'ID');
	  unless(defined($intervalRow)) { next; }
	  my $start = $intervalRow->{'START'}->[0];
	  my $stop  = $intervalRow->{'END'}->[0];
	  $genomeSize = $genomeSize - ($stop - $start);
	  my $genes = $model->genes_of_interval($start,$stop,'224308.1');
	  $geneCount += @{$genes};
  }

  # Existing strain selected, find strain, load, print data
  $html .= "<h2>Strain " . $Strain . "</h2>";
  $html .= "<div style='padding-left: 10px;'>";
  $html .= "<a href='seedviewer.cgi?page=StrainViewer&id=".$Strain.
		"&act=NEW' >Create new strain using this one</a><br/>";
  $html .= "<table>";
  $html .= "<tr><th>Strain Size / Genome Size</th><td>". ($genomeSize/1000) .
			' / 4214.814 Kbp</td></tr>';
  $html .= '<tr><th>Intervals</th><td>'.@{$Intervals}.'</td></tr>';
  $html .= '<tr><th>Genes knocked out</th><td>'.$geneCount.'</td></tr>';
  $html .= '<tr><th>Reactions knocked out</th><td>'.$rxnCount.'</td></tr>';
  $html .= "<tr><th>Growth</th><td>" . $growthstr . "</td></tr>";
  $html .= "</table>";
  $html .= "</div>";
  $html .= "<div style='clear: right;'>" . $strain_tv->output() . "</div>";
  return $html;
}
