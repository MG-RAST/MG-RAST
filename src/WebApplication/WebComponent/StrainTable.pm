package WebComponent::StrainTable;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

StrainTable - A table of available intervals

=head1 DESCRIPTION

WebComponent for a strain select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('Table', 'StrainTable');
  $self->application->register_component('GrowthData', 'Growth');

  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {
  my ($self,$Width,$TableIndex,$IDList) = @_;

  #Setting the table index
  if (!defined($TableIndex)) {
    $TableIndex = 0;
  }

  #Getting various packages
  my $application = $self->application();
  my $model = $application->data_handle('FIGMODEL');
  my $user = $application->session->user;
  my $cgi = $application->cgi();
  my @IDs;
  my $tabledata;
  #define the global strain table
  my $StrainTableModel = $model->database()->GetDBTable("STRAIN TABLE");

  #CGI Parameters
  if(defined($IDList) ) {
    #Parsing the ID list
	@IDs = split(/,/,$IDList); # split on commas; 11232,523523,...
  } else { # if no list is passed, return all strains
    @IDs = $StrainTableModel->get_hash_column_keys("ID");
  }

  #Scaning through and storing model, genome, and reaction IDs found
  #my @ColumnNames = ('ID', 'INTERVALS', 'GENES', 'DATE', 'BASE', 'GROWTH', 'PHENOTYPE');
  my @ColumnNames = ('ID', 'INTERVALS', 'GENES', 'BASE', 'GROWTH', 'PREDICTION CONFLICTS', 'PHENOTYPE');

  #Creating the basic table object that is the foundation of this object
  my $strain_table = $application->component('StrainTable');
  my $GrowthDisplay = $application->component('Growth');
  #Setting the table columns based on the table type
  my $ColumnArray = $self->make_column_array($cgi->param( 'page' ));

#Loading the data table listing the reactions in the model or in the database
  my $rowhash;
  my $row = 0;
  for(my $j=0; $j< $StrainTableModel->size(); $j++) {
	$rowhash = $StrainTableModel->get_row($j);
	my $ID = $rowhash->{'ID'}->[0];
	my $i;
	for ($i = 0; $i < (@ColumnNames); $i++) {
		my $data = "";
		if('ID' eq $ColumnNames[$i] || 'BASE' eq $ColumnNames[$i] ) {
			$data = $rowhash->{$ColumnNames[$i]}->[0];
			if(defined($data) && $data ne 'None') {
				$tabledata->[$row]->[$i] = "<a href='seedviewer.cgi?page=StrainViewer&id=".
					$data."' >".$data."</a>";
			} else { $tabledata->[$row]->[$i] = 'None'; }
		} elsif('INTERVALS' eq $ColumnNames[$i] ) {
			my @links;
			my $intervalIDs = $rowhash->{$ColumnNames[$i]};
			if(defined($intervalIDs)) {
				foreach my $id (@{$rowhash->{$ColumnNames[$i]}}) {
					push(@links, "<a href='seedviewer.cgi?page=IntervalViewer&id=".
						$id."' >".$id."</a>");
				}
				$tabledata->[$row]->[$i] = join(', ', @links);
			}
		} elsif('GENES' eq $ColumnNames[$i] ) {
			$tabledata->[$row]->[$i] = $self->get_strain_gene_count($ID);
		} elsif('GROWTH' eq $ColumnNames[$i] ) {
			$tabledata->[$row]->[$i] = $GrowthDisplay->output($ID);
		} elsif('PREDICTION CONFLICTS' eq $ColumnNames[$i]) {
			$tabledata->[$row]->[$i] = $GrowthDisplay->conflictCount($ID);
		} else {
			$data = $rowhash->{$ColumnNames[$i]};
			if(defined($data)) { $tabledata->[$row]->[$i] = join(',', @{$data}) }
			else { $tabledata->[$row]->[$i] = "" }
		}
	}
	$row++;
  }

  #Filling out the table object
  #$reaction_table->show_export_button(0);
  $strain_table->columns($ColumnArray);
  $strain_table->items_per_page(25);
  $strain_table->show_select_items_per_page(0);
  $strain_table->show_top_browse(1);
  $strain_table->show_bottom_browse(0);
  $strain_table->data($tabledata);
  $strain_table->width($Width);

  return $strain_table->output();
  #$html .= '<input type="hidden" id="column_names" value="'.$ColumnNames.'">'."\n";
  #$html .= '<input type="hidden" id="selected_models" value="'.$SelectedModels.'">'."\n";
  #$html .= '<input type="hidden" id="selected_organism" value="'.$SelectedOrganism.'">'."\n";
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/ModelTable.js"];
}


sub make_column_array {
	my ($self, $pagename) = @_;
	my $ColumnArray;
  	my $application = $self->application();
  	my $cgi = $application->cgi();
  		push(@{$ColumnArray}, { name => 'Strain', filter => 1, sortable => 1,
			width => '100', operand => $cgi->param( 'filterIntervalID' ) || "" });
  		push(@{$ColumnArray}, { name => 'Intervals', filter => 1, sortable => 0,
			width => '200', operand => $cgi->param( 'filterStart' ) || "" });
		push(@{$ColumnArray}, { name => 'Gene KO Count', filter => 0, sortable => 1,
			width => '20', operand => $cgi->param( 'filterGeneCount') || ""});
		#push(@{$ColumnArray}, { name => 'Date Added', filter => 0, sortable =>1,
		#	 width => '100', operand => $cgi->param( 'filterDate') || ""});
		push(@{$ColumnArray}, { name => 'Base Strain', filter => 1, sortable =>0,
			 width => '100', operand => $cgi->param( 'filterBase') || ""});
  		push(@{$ColumnArray}, { name => 'Growth', filter => 0, sortable => 0,
			 width => '200', operand => $cgi->param( 'filterStop' ) || "" });
		push(@{$ColumnArray}, { name => 'Prediction Conflict', filter => 0, sortable => 1,
			width => '10', operands => $cgi->param( 'filterConflict') || "" });
  		push(@{$ColumnArray}, { name => 'Phenotype', filter => 0, sortable => 0,
			width => '20', operand => $cgi->param( 'filterGrowth' ) || "" });
	return $ColumnArray;
}

sub get_strain_gene_count {
	my ($self, $ID) = @_;
	unless(defined($ID)) { return "Unknown error."; }
	my $model = $self->application->data_handle('FIGMODEL');
	my $fig = $self->application->data_handle('FIG');
	my $genomeID = "224308.1";
	my $StrainTable = $model->database()->GetDBTable("STRAIN TABLE");
	my $IntervalTable = $model->database()->GetDBTable("INTERVAL TABLE");
	my $row = $StrainTable->get_row_by_key($ID, "ID");
	unless(defined($row)) { return "Error: unknown strain."; }
	my $intervals = $row->{'INTERVALS'};
	unless(defined($intervals)) { return "Unknown error."; }
	my $returnedFeatureIDs;
	foreach my $interval (@{$intervals}) {
		my $featureIDs;
		my $interval_row = $IntervalTable->get_row_by_key($interval, "ID");
		unless(defined($interval_row)) { next; }
		my $genes = $interval_row->{'GENES'};
		if(defined($genes)) { return $genes }
		else {
			my $start = $interval_row->{'START'}->[0];
			my $end = $interval_row->{'END'}->[0];
			unless(defined($start) && defined($end) && defined($fig)) {
				return "Unknown error."; }
			my $features = $fig->all_features_detailed_fast($genomeID, $start, $end);
			unless(defined($features)) { next; }
			foreach my $feature (@{$features}) {
				push(@{$returnedFeatureIDs}, $feature->[0]); # Push the ID onto the list
			}

			# Save Features to Interval Table
			# Append $featureIDs to $returnedFeatureIDs
		}
	}
	return @{$returnedFeatureIDs};
}
