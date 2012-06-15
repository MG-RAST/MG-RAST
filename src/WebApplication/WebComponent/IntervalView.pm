package WebComponent::IntervalView;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

IntervalView

=head1 DESCRIPTION

Webcomponent for viewing existing intervals

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
	my $self = shift->SUPER::new(@_);
		
	$self->application->register_component('Ajax', 'page_ajax');
	$self->application->register_component('TabView', 'IntervalTV');
	$self->application->register_component('StrainTable', 'strain_table');
	$self->application->register_component('GrowthData', 'interval_growth');
	$self->application->register_component('GeneTable', 'gene_table');
	$self->application->register_component('TabView', 'prediction_tv');
	$self->application->register_component('CompoundTable', 'cpd_table');
	$self->application->register_component('ReactionTable', 'rxn_table');
	#$self->application->register_component('Comments', 'interval_discussion');
	return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {
	my ($self, $intervalID) = @_;

	my $html = "<a href='seedviewer.cgi?page=IntervalViewer'>&lt;&lt; Back to interval list</a>";

	#Getting various packages
	my $application = $self->application();
	my $model = $application->data_handle('FIGMODEL');
	my $user;
	if(defined($user = $application->session()->user())) { $user = $user->login(); }
	else { my $user = ""; }

	my $cgi = $application->cgi();

	my $ajax = $application->component('page_ajax');
	$html .= $ajax->output();
	
		#get interval table
	my $strain_table = $application->component('strain_table');
	my $interval_tv = $application->component('IntervalTV');
	my $interval_growth = $application->component('interval_growth');
	my $gene_table = $application->component('gene_table');

	#define the global strain table
	my $StrainModel = $model->database()->GetDBTable("STRAIN TABLE");
	my $IntervalModel = $model->database()->GetDBTable("INTERVAL TABLE");

	# CONFIRM CGI intevalID passed
	unless(defined($intervalID)) {
        $intervalID = $cgi->param("id");
	}
	# CONFIRM that such an interval exists
	my $interval = $IntervalModel->get_row_by_key($intervalID, "ID");
	unless(defined($interval)) {
		$application->redirect('IntervalSelect');
		$application->add_message('warning', "Unknown interval ".$intervalID.
			"; please select a valid interval.");
		$application->do_redirect();
	}
	# CONFIRM THAT interval is owned by $user or public
	my $intervalOwner = $interval->{'OWNER'}->[0];
	if(defined($intervalOwner)) {
		if($intervalOwner ne $user) {
			$application->redirect('IntervalSelect');
			$application->add_message('warning', "Unknown interval ".$intervalID.
				"; please select a valid interval.");
			$application->do_redirect();
		}
	} # otherwise owner = "", public.

	my $MainText;
	my $StrainTabText;
	my $gintervalthstr = join(',', @{$interval->{'GROWTH'}});
	my $start = join(',', @{$interval->{'START'}});
	my $end = join(',', @{$interval->{'END'}});
	my $growth = $interval_growth->output($intervalID);
	# Existing strain selected, find strain, load, print data
	$MainText .= "<h2>Interval " . $intervalID . "</h2>";
	$MainText .= "<div style='padding-left: 10px;'>";
	$MainText .= "<table><tr><th>Start</th><td>" . $start . "</td></tr>";
	$MainText .= "<tr><th>End</th><td>" . $end . "</td></tr>";
	$MainText .= "<tr><th>Growth</th><td>".$growth."</td></tr>";
	$MainText .= "</table>";
	$MainText .= "</div>";
	
	my $gene_list = $self->get_interval_genes_list($intervalID);
	my $GeneTabText = $gene_table->output(900, join(',',@{$gene_list}).",iBsuNew");
	
	my @CollectedStrainIDs;
	my $strainID;
	my @Rows = $StrainModel->get_rows_by_key($intervalID, "INTERVALS");
	foreach my $row (@Rows) {
		$strainID = "";
		$strainID = $row->{"ID"};
		if(defined($strainID)) { push(@CollectedStrainIDs, join(',', @{$strainID})) }
	}
	if(@CollectedStrainIDs == 0) {
		$StrainTabText .= "There are currently no strains using this interval.";
	} else {
		my $CollectedStrainIDsStr = join(',', @CollectedStrainIDs);
		$StrainTabText .= $strain_table->output(900, 0, $CollectedStrainIDsStr);
	}

	my $PredictionTabText = "Our simulations provide predictions on coessential reactions".
		" missing from the strain and offer additional media conditions that may support".
		" growth";
	my $SimulationTable = $model->database()->GetDBTable('STRAIN SIMULATIONS');
	my $sim = $SimulationTable->get_row_by_key($intervalID, 'ID');
	my $rxnSubTabText;
	my $cpdSubTabText;
	my $prediction_tv = $application->component('prediction_tv');
	my $tableMark = 'XX';
	# rescue media compounds
	if(defined($sim->{'RESCUE_MEDIA'}) and $sim->{'RESCUE_MEDIA'}->[0] ne 'NONE') {
		my $cpd_table = $application->component('cpd_table');
		my $cpdIds;
		for( my $i = 0; $i < @{$sim->{'MEDIA'}}; $i++) {
			my $mediaName = $sim->{'MEDIA'}->[$i];
			my $data;
			for( my $j = 0; $j < @{$sim->{'RESCUE_MEDIA'}}; $j++) {
				my @cpds = split('/', $sim->{'RESCUE_MEDIA'}->[$j]);
				foreach my $cpd (@cpds) {
					$data->{$cpd} = $tableMark;
					$cpdIds->{$cpd} = $cpd;
				}
			}
			$cpd_table->add_column({ name => $mediaName, position => 1,
					sortable => '1', filter => '0', data => $data });
		}
		$cpdSubTabText = $cpd_table->output(join(',', keys %{$cpdIds}), 900, 0);
		$prediction_tv->add_tab('Rescue Media', $cpdSubTabText);
	}
	# coessential reactions
	if(defined($sim->{'COESSENTIAL_REACTIONS'})) {
		my $rxn_table = $application->component('rxn_table');
		my $rxnIds;
		$rxnIds->{'iBsuNew'} = 'iBsuNew';
		for( my $i = 0; $i < @{$sim->{'MEDIA'}}; $i++) {
			my $mediaName = $sim->{'MEDIA'}->[$i];
			my $data;
			for( my $j = 0; $j < @{$sim->{'COESSENTIAL_REACTIONS'}}; $j++) {
				my @rxns = split(',', $sim->{'COESSENTIAL_REACTIONS'}->[$j]);
				foreach my $rxn (@rxns) {
					unless(defined($rxnIds->{substr($rxn, 1)})) {
						$rxnIds->{substr($rxn, 1)} = substr($rxn, 1);
					}
					my $mark = substr($rxn, 0, 1);
					if( $mark eq '+' ) { $mark = '=>'; }
					elsif( $mark eq '-') { $mark = '<='; }
					$data->{substr($rxn, 1)} = $mark;
				}
			}
			$rxn_table->add_column({ name => $mediaName, position => 1, width => 10,
					sortable => '1', filter => '0', data => $data });
		}
		$rxnSubTabText = $rxn_table->output(900, join(',', keys %{$rxnIds}));
		$prediction_tv->add_tab('Coessential reactions', $rxnSubTabText);
	}
	$prediction_tv->width(900);
	$prediction_tv->height(400);
	$PredictionTabText .= $prediction_tv->output();

	# discussion tab
	#my $interval_discussion = $application->component('interval_discussion');
	#$interval_discussion->title('Discussion');
	#$interval_discussion->ajax($ajax);
	#$interval_discussion->width(900);
	#my $interval_discussion_id = 'figint|224308.1.'.$intervalID;
	#my $DiscussionTabText = $interval_discussion->output($interval_discussion_id);
	
	$html .= $MainText; # Add the main info before tab view
	$interval_tv->width(900);
	$interval_tv->height(400);
	$interval_tv->add_tab('Gene Information', $GeneTabText);
	$interval_tv->add_tab('Related Strains', $StrainTabText);
	$interval_tv->add_tab('Predictions', $PredictionTabText);
	#$interval_tv->add_tab('Discussion', $DiscussionTabText);
	$html .= $interval_tv->output();
	
	return $html;
}

sub require_javascript {
	return ["$Conf::cgi_url/Html/ModelTable.js"];
}

sub get_interval_genes_list {
	my ($self, $ID) = @_;
	
	unless(defined($ID)) { return "Unknown error."; }
	my $model = $self->application->data_handle('FIGMODEL');
	my $fig = $self->application->data_handle('FIG');
	my $genomeID = "224308.1";
	my $IntervalTable = $model->database()->GetDBTable("INTERVAL TABLE");
	my $row = $IntervalTable->get_row_by_key($ID, "ID");
	unless(defined($row)) { return "Error: no interval found."; }
	my $genes = $row->{"GENES"};
	# If we already have the list of genes, just return the number of
	# elements in that list, otherwise, we must first construct the list.
	if(defined($genes)) { return "Error: no features found."; }

	my $start = $row->{"START"}->[0];
	my $end = $row->{"END"}->[0];
	unless(defined($start) && defined($end) && defined($fig)) { return "what happened?"; }
	my $features = $fig->all_features_detailed_fast($genomeID, $start, $end);
	my $featureIDs;
	unless(defined($features)) { return "no features found"; }
	foreach my $feature (@{$features}) {
		my $featureID = $feature->[0];
		push(@{$featureIDs}, $featureID);
	}
	return $featureIDs;
}
