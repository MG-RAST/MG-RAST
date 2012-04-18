package WebComponent::GeneTable;

# ModelSelect - select box for models

use strict;
use warnings;

use base qw( WebComponent );

#use FIGMODEL;

1;


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
  $self->application->register_component('ObjectTable','GeneTable');
  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {
	my ($self,$Width,$IDList) = @_;
    #Getting web application objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');
    #Formating the IDList as an array reference
	my $FinalList;
	if (defined($IDList) && $IDList ne 'ARRAY') {
		push(@{$FinalList},split(/,/,$IDList));
	} elsif (defined($IDList)) {
		$FinalList = $IDList;
	}
    #Adding models to the IDList
	if (defined($cgi->param('model'))) {
		push(@{$FinalList},split(/,/,$cgi->param('model')));
	}
	#Assembling the genomes for the input models
	my $genomeHash;
	for (my $i=0; $i < @{$FinalList}; $i++) {
		my $mdl = $figmodel->get_model($FinalList->[$i]);
		if (!defined($genomeHash->{$mdl->genome()})) {
			$genomeHash->{$mdl->genome()}->{genome} = $mdl->genomeObj();
		}
		push(@{$genomeHash->{$mdl->genome()}->{model}},$FinalList->[$i]);
	}
    #Setting table objects
    my $table = $application->component('GeneTable');
    $table->set_type("feature");
    my $geneList;
    my @genomeList = keys(%{$genomeHash});
    for (my $i=0; $i < @genomeList; $i++) {
    	my $featureTbl = $genomeHash->{$genomeList[$i]}->{genome}->feature_table(undef,$genomeHash->{$genomeList[$i]}->{model});
    	for (my $j=0; $j < $featureTbl->size(); $j++) {
    		my $row = $featureTbl->get_row($j);
    		if ($row->{ID}->[0] =~ m/peg/) {
    			push(@{$geneList},$row);
    		}
    	}
    }
    if (!defined($geneList) || @{$geneList} == 0) {
    	return "<p>No genes in table</p>";
	}
	$table->set_objects($geneList);
    #Setting table columns
    my $columns = [
	    { function => 'FIGMODELweb:create_feature_link', call => 'THIS', name => 'Gene ID', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterGeneID' ) || "" },
	    #{ call => 'HASH:ALIASES', name => 'Alias', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterAlias' ) || "" },
	    { call => 'HASH:MIN LOCATION', name => 'Start (BP)', sortable => 1, width => '50'},
	    { call => 'HASH:LENGTH', name => 'Length (BP)', sortable => 1, width => '50'},
	    { call => 'HASH:DIRECTION', name => 'Direction', sortable => 1, width => '50'},
	    { delimiter => '<br>', call => 'HASH:ROLES', name => 'Functional Assignment', filter => 1, sortable => 1, width => '350', operand => $cgi->param( 'filterRole' ) || "" },
	    { function => 'FIGMODELweb:format_essentiality', delimiter => '<br>', call => 'THIS', name => 'Essentiality', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterEssentiality' ) || "" }
    ];
    if (@genomeList > 1) {
    	unshift(@{$columns},{ function => 'FIGMODELweb:create_genome_link', call => 'HASH:GENOME', name => 'Genome', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterGenomeID' ) || "" });
    }
    foreach my $model (@{$FinalList}) {
    	push(@{$columns},{ function => 'FIGMODELmodel('.$model.'):feature_web_data', call => 'THIS', name => $model, filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filter'.$model ) || "" });
    }
    #Specifying table settings
    my $sortColumn = "Start (BP)";
    if (@{$FinalList} > 1) {
    	$sortColumn = "Genome";
    }  
    $table->add_columns($columns);
    $table->set_table_parameters({
    	show_export_button => "1",
    	sort_column => $sortColumn,
    	width => $Width,
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    return $table->output();
}

sub base_table {
  my ($self) = @_;
  return $self->application()->component('GeneTable')->base_table();
}