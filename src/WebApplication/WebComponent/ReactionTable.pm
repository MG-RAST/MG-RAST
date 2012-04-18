package WebComponent::ReactionTable;
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
	$self->application->register_component('ObjectTable','ReactionObjectTable'.$self->id);
	return $self;
}

=item * B<output> ()
Returns the html output of the ModelSelect component.
=cut
sub output {
	my ($self,$Width,$idList) = @_;
	my $application = $self->application();
	my $cgi = $application->cgi();
	my $figmodel = $application->data_handle('FIGMODEL');
	if (!defined($Width)) {
		$Width = 800;	
	}
	#Getting reaction objects and placing them in a hash
	my $rxnHash;
	my $rxns = $figmodel->database()->get_objects("reaction");
	for (my $i=0; $i < @{$rxns}; $i++) {
		$rxnHash->{$rxns->[$i]->id()} = $rxns->[$i];
	}
	#Filtering by the input list of reaction IDs
	my $objectList;
	if (defined($idList)) {
		if (ref($idList) ne "ARRAY") {
			my @array = split(/,/,$idList);
			push(@{$idList},@array);
		}
		for (my $i=0; $i < @{$idList}; $i++) {
			if (defined($rxnHash->{$idList->[$i]})) {
				push(@{$objectList},$rxnHash->{$idList->[$i]});
			}
		}
		$rxnHash = {};
		for (my $i=0; $i < @{$objectList}; $i++) {
			$rxnHash->{$objectList->[$i]->id()} = $objectList->[$i];
		}
	} else {
		$objectList = $rxns;
	}
	#Filtering by the selected models
	my $modelList = $figmodel->web()->get_selected_models();
	if (defined($modelList)) {
		$objectList = [];
		my $newRxnHash;
		for (my $i=0; $i < @{$modelList}; $i++) {
			my $tbl = $modelList->[$i]->reaction_table();
			for (my $j=0; $j < $tbl->size(); $j++) {
				my $id = $tbl->get_row($j)->{LOAD}->[0];
				if (defined($rxnHash->{$id})) {
					$newRxnHash->{$id} = $rxnHash->{$id};
				} elsif ($id =~ m/bio\d\d\d\d\d/) {
					my $obj = $figmodel->database()->get_object("bof",{id=>$id});
					if (defined($obj)) {
						$newRxnHash->{$id} = $obj;
					}
				}
			}
		}
		foreach my $key (keys(%{$newRxnHash})) {
			push(@{$objectList},$newRxnHash->{$key});
		}
	}
	#Creating and configuring the object table
	my $tbl = $application->component('ReactionObjectTable'.$self->id);
    $tbl->set_type("reaction");
	$tbl->set_objects($objectList);
    #Setting table columns
    my $columns = [
	    { call => 'FUNCTION:id', name => 'Reaction', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionID' ) || "" },
	    { call => 'FUNCTION:name', name => 'Name', filter => 1, sortable => 1, width => '150', operand => $cgi->param( 'filterReactionName' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_equation', call => 'THIS', name => 'Equation', filter => 1, sortable => 1, width => '300', operand => $cgi->param( 'filterReactionEquation' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_roles', call => 'FUNCTION:id', name => 'Roles', filter => 1, sortable => 1, width => '150', operand => $cgi->param( 'filterReactionRoles' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_subsystems', call => 'FUNCTION:id', name => 'Subsystems', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterReactionSubsys' ) || "" },
	    { input => {type => "reaction"}, function => 'FIGMODELweb:display_keggmaps', call => 'FUNCTION:id', name => 'KEGG maps', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterReactionKEGGmap' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_enzymes', call => 'THIS', name => 'Enzyme', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionEnzyme' ) || "" },
	    { input => {-delimiter => ",", object => "rxnals", function => "REACTION", type => "KEGG"}, function => 'FIGMODELweb:display_alias', call => 'FUNCTION:id', name => 'KEGG RID', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionKEGGID' ) || "" },
	];
	my $modelString = "";
	my $selectedOrganism = "none";
    if (defined($modelList)) {
	    if (@{$modelList} == 1) {
	    	push(@{$columns},{ function => 'FIGMODELmodel('.$modelList->[0]->id().'):reaction_notes', call => 'FUNCTION:id', name => "Notes", filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterNotes' ) || "" });	
	    }
	    $selectedOrganism = $modelList->[0]->genome();
	    foreach my $model (@{$modelList}) {
	    	if (length($modelString) > 0) {
	    		$modelString .= ",";	
	    	}
	    	$modelString .= $model->id();
	    	push(@{$columns},{ input => {type => "reaction",model => $model->id()}, function => 'FIGMODELweb:table_model_column', call => 'FUNCTION:id', name => $model->id(), filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filter'.$model->id() ) || "" });
	    }
    }
    if (defined($cgi->param('fluxIds'))) {
		my @fluxes = split(/,/,$cgi->param('fluxIds'));
		for (my $i=0; $i < @fluxes; $i++) {
			push(@{$columns},{ input => {fluxid=>$fluxes[$i]}, function => 'FIGMODELweb:display_reaction_flux', call => 'FUNCTION:id', name => "Flux #".($i+1), filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterNotes' ) || "" });	
		}
	} 
    #Specifying table settings
    $tbl->add_columns($columns);
    $tbl->set_table_parameters({
    	show_column_select => "1",
    	enable_upload => "1",
    	show_export_button => "1",
    	sort_column => "Reaction",
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
  return $self->application()->component('ReactionObjectTable'.$self->id)->base_table();
}

1;