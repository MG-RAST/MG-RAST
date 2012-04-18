package WebComponent::CompoundTable;
use strict;
use warnings;
use base qw( WebComponent );

=pod
=head1 NAME
ModelSelect - a select box for models
=head1 DESCRIPTION
WebComponent for a model select box
=head1 METHODS
=over 4
=item * B<new> ()
Called when the object is initialized. Expands SUPER::new.
=cut
sub new {
	my $self = shift->SUPER::new(@_);
	$self->application->register_component('ObjectTable','CompoundObjectTable'.$self->id);
	return $self;
}

=item * B<output> ()
Returns the html output of the ModelSelect component.
=cut
sub output {
	my ($self,$idList,$Width,$TableIndex) = @_;
	my $application = $self->application();
	my $figmodel = $application->data_handle('FIGMODEL');
	my $cgi = $application->cgi();
	#Setting the table index
	if (!defined($TableIndex)) {
		$TableIndex = 0;
	}
	if (!defined($Width)) {
		$Width = 800;
	}
	#Getting reaction objects and placing them in a hash
	my $cpdHash;
	my $cpds = $figmodel->database()->get_objects("compound");
	for (my $i=0; $i < @{$cpds}; $i++) {
		$cpdHash->{$cpds->[$i]->id()} = $cpds->[$i];
	}
	#Filtering by the input list of reaction IDs
	my $objectList;
	if (defined($idList)) {
		if (ref($idList) ne "ARRAY") {
			my @array = split(/,/,$idList);
			push(@{$idList},@array);
		}
		for (my $i=0; $i < @{$idList}; $i++) {
			if (defined($cpdHash->{$idList->[$i]})) {
				push(@{$objectList},$cpdHash->{$idList->[$i]});
			}
		}
		$cpdHash = {};
		for (my $i=0; $i < @{$objectList}; $i++) {
			$cpdHash->{$objectList->[$i]->id()} = $objectList->[$i];
		}
	} else {
		$objectList = $cpds;
	}
	#Filtering by the selected models
	my $modelList = $figmodel->web()->get_selected_models();
	if (defined($modelList)) {
		$objectList = [];
		my $newCpdHash;
		for (my $i=0; $i < @{$modelList}; $i++) {
			my $tbl = $modelList->[$i]->compound_table();
			for (my $j=0; $j < $tbl->size(); $j++) {
				my $id = $tbl->get_row($j)->{DATABASE}->[0];
				if (defined($cpdHash->{$id})) {
					$newCpdHash->{$id} = $cpdHash->{$id};
				}
			}
		}
		foreach my $key (keys(%{$newCpdHash})) {
			push(@{$objectList},$newCpdHash->{$key});
		}
	}
	#Creating and configuring the object table
	my $tbl = $application->component('CompoundObjectTable'.$self->id);
    $tbl->set_type("compound");
	$tbl->set_objects($objectList);
	#Setting table columns
    my $columns = [
	    { call => 'FUNCTION:id', name => 'Compound', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterCompoundID' ) || "" },
	    { input => {-delimiter => ",<br>", object => "cpdals", function => "COMPOUND", type => "name"}, function => 'FIGMODELweb:display_alias', call => 'FUNCTION:id', name => 'Name', filter => 1, sortable => 1, width => '200', operand => $cgi->param( 'filterCompoundName' ) || "" },
	    { call => 'FUNCTION:formula', name => 'Formula', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterCompoundFormula' ) || "" },
	    { call => 'FUNCTION:mass', name => 'Mass', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterCompoundMass' ) || "" },
	    { input => {type => "compound"}, function => 'FIGMODELweb:display_keggmaps', call => 'FUNCTION:id', name => 'KEGG maps', filter => 1, sortable => 1, width => '200', operand => $cgi->param( 'filterCompoundKEGGmap' ) || "" },
	    { input => {-delimiter => ",", object => "cpdals", function => "COMPOUND", type => "KEGG"}, function => 'FIGMODELweb:display_alias', call => 'FUNCTION:id', name => 'KEGG CID', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterCompoundKEGGID' ) || "" },
	];
	my $modelString = "";
	my $selectedOrganism = "none";
    if (defined($modelList)) {
	    $selectedOrganism = $modelList->[0]->genome();
	    foreach my $model (@{$modelList}) {
	    	if (length($modelString) > 0) {
	    		$modelString .= ",";	
	    	}
	    	$modelString .= $model->id();
	    	push(@{$columns},{ input => {type => "compound",model => $model->id()}, function => 'FIGMODELweb:table_model_column', call => 'FUNCTION:id', name => $model->id(), filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filter'.$model->id() ) || "" });
	    }
    }
    if (defined($cgi->param('fluxIds'))) {
		#my @fluxes = split(/,/,$cgi->param('fluxIds'));
		#for (my $i=0; $i < @fluxes; $i++) {
		#	push(@{$columns},{ input => {fluxid=>$fluxes[$i]}, function => 'FIGMODELweb:display_compound_flux', call => 'THIS', name => $fluxes[$i], filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filter'.$fluxes[$i] ) || "" });	
		#}
	}
  	#Specifying table settings
    $tbl->add_columns($columns);
    $tbl->set_table_parameters({
    	show_column_select => "1",
    	enable_upload => "1",
    	show_export_button => "1",
    	sort_column => "Compound",
    	width => $Width,
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    my $html = "";
    if (defined($modelList)) {
    	$html .= '<input type="hidden" id="selected_models" value="'.$modelString.'">'."\n";	
    }
    $html .= '<input type="hidden" id="selected_organism" value="'.$selectedOrganism.'">'."\n";
    return $html.$tbl->output();
}

sub base_table {
	my ($self) = @_;
	return $self->application()->component('CompoundObjectTable'.$self->id)->base_table();
}

1;