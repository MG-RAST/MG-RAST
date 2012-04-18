package WebComponent::IntervalTable;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

IntervalTable - A table of available intervals

=head1 DESCRIPTION

WebComponent for a strain select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('Table', 'iv_table');
  $self->application->register_component('GrowthData', 'iv_growth');

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
  my $html;
  my @IDs;
  my $tabledata;
  #define the global strain table
  my $IntervalTableModel = $model->database()->GetDBTable("INTERVAL TABLE");
  my $IntervalRank       = $model->database()->GetDBTable("INTERVAL RANK");

  #CGI Parameters
  if(defined($IDList) ) {
    #Parsing the ID list
	@IDs = split(/,/,$IDList); # split on commas; 11232,523523,...

  } else { # if no list is passed, return all strains
    @IDs = $IntervalTableModel->get_hash_column_keys("ID");
  }

  #Scaning through and storing model, genome, and reaction IDs found
  my @ColumnNames = ('ID', 'RANK', 'START', 'END', 'GENE COUNT', 'GENES', 'GROWTH', 'CONFLICT');

  #Creating the basic table object that is the foundation of this object
  my $interval_table = $application->component('iv_table');
  my $interval_growth = $application->component('iv_growth');
  #Setting the table columns based on the table type
  my $ColumnArray = $self->make_column_array();

#Loading the data table listing the reactions in the model or in the database
  my $rowhash;
  my $row = 0;
  my $i;
  foreach my $ID (@IDs) {
	$rowhash = $IntervalTableModel->get_row_by_key($ID, 'ID');
	if(!defined($rowhash)) {
		$application->add_message('warning', "Unknown interval ID " . $ID . " was not listed.");
		next;
	}
	for ($i = 0; $i < @ColumnNames; $i++) {
		if('ID' eq $ColumnNames[$i]) {
			my $data = $rowhash->{$ColumnNames[$i]};
			unless(defined($data)) {
				$tabledata->[$row]->[$i] = "";
				next;
			}
			my $link = join(',', @{$data});
			$tabledata->[$row]->[$i] = "<a href='seedviewer.cgi?page=IntervalViewer&id=".
										$link."' >".$link."</a>";

		} elsif('RANK' eq $ColumnNames[$i]) {
			my $x = $IntervalRank->get_row_by_key($rowhash->{'ID'}->[0], 'Interval');
			if(defined($x)) { $tabledata->[$row]->[$i] = $x->{'Rank'}->[0]; }
			else { $tabledata->[$row]->[$i] = ''; }
		} elsif('GENE COUNT' eq $ColumnNames[$i]) {
			my $count = $self->get_interval_gene_count($ID);
			$tabledata->[$row]->[$i] = $count;

		} elsif('GENES' eq $ColumnNames[$i]) {
			my $gene_html = $self->get_interval_genes_html($ID);
			$tabledata->[$row]->[$i] = $gene_html;

		} elsif('GROWTH' eq $ColumnNames[$i]) {
			my $growthdata .= $interval_growth->output($ID);
			if(defined($growthdata)) {
				$tabledata->[$row]->[$i] = $growthdata;
			} else { $tabledata->[$row]->[$i] = '' }

		} elsif('CONFLICT' eq $ColumnNames[$i]) {
			$tabledata->[$row]->[$i] = $interval_growth->conflictCount($ID);
		} else {
			my $data;
			# Rest besides select
			if(defined($data = $rowhash->{$ColumnNames[$i]})) {
				$tabledata->[$row]->[$i] = join(',', @{$data});
			} else { $tabledata->[$row]->[$i] = ""; }
		}
	}
	$row++;
  }
  #Filling out the table object
  #$reaction_table->show_export_button(0);
  $interval_table->columns($ColumnArray);
  $interval_table->items_per_page(50);
  $interval_table->show_select_items_per_page(0);
  $interval_table->show_top_browse(1);
  $interval_table->show_bottom_browse(1);
  $interval_table->data($tabledata);
  $interval_table->width($Width);

  $html .= $interval_table->output();
  #$html .= '<input type="hidden" id="column_names" value="'.$ColumnNames.'">'."\n";
  #$html .= '<input type="hidden" id="selected_models" value="'.$SelectedModels.'">'."\n";
  #$html .= '<input type="hidden" id="selected_organism" value="'.$SelectedOrganism.'">'."\n";
  return $html;
}

sub make_column_array {
	my ($self, $pagename) = @_;
	my $ColumnArray;
  	my $application = $self->application();
  	my $cgi = $application->cgi();
  		push(@{$ColumnArray}, { name => 'Interval', filter => 1, sortable => 1,
			width => '50', operand => $cgi->param( 'filterIntervalID' ) || "" });
		push(@{$ColumnArray}, { name => 'Rank', filter => 0, sortable => 1,
			width => '50', operand => $cgi->param( 'filterRank' ) || "" });
  		push(@{$ColumnArray}, { name => 'Start', filter => 0, sortable => 1,
			width => '100', operand => $cgi->param( 'filterStart' ) || "" });
  		push(@{$ColumnArray}, { name => 'Stop', filter => 0, sortable => 1,
			 width => '100', operand => $cgi->param( 'filterStop' ) || "" });
  		push(@{$ColumnArray}, { name => 'Gene Count', filter => 0, sortable => 1,
			 width => '50', operand => $cgi->param( 'filterGeneCount' ) || "" });
  		push(@{$ColumnArray}, { name => 'Genes', filter => 1, sortable => 0,
			 width => '600', operand => $cgi->param( 'filterGenes' ) || "" });
  		push(@{$ColumnArray}, { name => 'Growth', filter => 0, sortable => 0,
			width => '300', operand => $cgi->param( 'filterGrowth' ) || "" });
  		push(@{$ColumnArray}, { name => 'Prediction Conflict', filter => 0, sortable => 1,
			width => '50', operand => $cgi->param( 'filterConflict' ) || "" });
	return $ColumnArray;
}

sub get_interval_gene_count {
	my ($self, $ID) = @_;
	unless(defined($ID)) { return "no args passed"; }
	my $model = $self->application->data_handle('FIGMODEL');
	my $fig = $self->application->data_handle('FIG');
	my $genomeID = "224308.1";
	my $IntervalTable = $model->database()->GetDBTable("INTERVAL TABLE");
	my $row = $IntervalTable->get_row_by_key($ID, "ID");
	unless(defined($row)) { return "no interval found"; }
	my $genes = $row->{"GENES"};
	# If we already have the list of genes, just return the number of
	# elements in that list, otherwise, we must first construct the list.
	if(defined($genes)) { return "got blank"; }
	else {
		my $start = $row->{"START"}->[0];
		my $end = $row->{"END"}->[0];
		unless(defined($start) && defined($end) && defined($fig)) { return "what happened?"; }
		my $features = $fig->all_features_detailed_fast($genomeID, $start, $end);
		my $featureIDs;
		unless(defined($features)) { return "no features found"; }
		foreach my $feature (@{$features}) {
			push(@{$featureIDs}, $feature->[0]);
		}

		# Now save results to table
		#my $LockedIntervalTable = $model->LockDBTable("INTERVAL TABLE");
		#my $new_row = $row;
		#$new_row->{'GENES'} = join(';', @{$featureIDs});
		#$LockedIntervalTable->replace_row($row, $new_row);
		#$LockedIntervalTable->save();
		#$model->UnlockDBTable("INTERVAL TABLE");
		# and return the gene count
		return @{$featureIDs};
	}
}

sub get_interval_genes_html {
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
	else {
		my $start = $row->{"START"}->[0];
		my $end = $row->{"END"}->[0];
		unless(defined($start) && defined($end) && defined($fig)) { return "what happened?"; }
		my $features = $fig->all_features_detailed_fast($genomeID, $start, $end);
		my $featureIDs;
		unless(defined($features)) { return "no features found"; }
		my $outstr;
		foreach my $feature (@{$features}) {
			my $featureID = $feature->[0];
			my $featureSTR = $featureID;
			$featureSTR =~ s/^(fig\|\d+\.\d*\.)//;	# fig|83333.1.peg.1234 becomes
													# peg.1234
			$outstr .= '<a href="linkin.cgi?id='.$featureID.'">'.$featureSTR."</a> ";
		}
		return $outstr;

	}
}
