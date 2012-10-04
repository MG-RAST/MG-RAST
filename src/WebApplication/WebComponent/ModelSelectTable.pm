package WebComponent::ModelSelectTable;

# ModelSelectTable - a table for viewing and selecting metabolic models in the SEED

use strict;
use warnings;
use base qw( WebComponent );
use Conf;

1;

=pod
=head1 NAME
ModelSelectTable - a table for viewing and selecting metabolic models in the SEE
=head1 DESCRIPTION
WebComponent for the ModelSelectTable
=cut

sub new {
  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Table', 'ModelSelectTable');

  return $self;
}

=item * B<output> ()
Returns the html output of the ModelSelect component.
=cut

sub output {
    my ($self,$SelectedModel,$CheckedModels) = @_;

    my $application = $self->application();
    my $user = $application->session->user();
    my $cgi = $application->cgi();
	my $figmodel = $application->data_handle('FIGMODEL');

    #Checking input parameters
    if (!defined($SelectedModel) || $SelectedModel eq "0" || $SelectedModel eq "" || $SelectedModel eq "NONE") {
        $SelectedModel = undef;
    }
    if (!defined($CheckedModels) || $CheckedModels eq "0" || $CheckedModels eq "" || $CheckedModels eq "NONE") {
        $CheckedModels = undef;
    }

    # get the table component
    my $table = $application->component('ModelSelectTable');

    #Setting the table columns based on the table type
    my $ColumnArray;
    my $CurrentColumn = 0;
	$ColumnArray->[$CurrentColumn] = { name => 'Name', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterName' ) || "" };
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { 'name' => 'Compare'};
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Organism', filter => 1, sortable => 1, width => '200', operand => $cgi->param( 'filterOrganism' ) || "" };
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Genome ID', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterGenomeID' ) || "" };
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Class', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterClass' ) || "" };
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Genes', tooltip => 'Genes associated with reactions/total genes in organism', sortable => 1, width => '100'};
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Reactions', sortable => 1, width => '100'};
	$CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Gap filling reactions', sortable => 1, width => '100'};
	$CurrentColumn++;
	$ColumnArray->[$CurrentColumn] = { name => 'Compounds', sortable => 1, width => '100'};
    $CurrentColumn++;
	$ColumnArray->[$CurrentColumn] = { name => 'Source', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterSource' ) || "" };
	$CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'SBML download link', width => '100'};
    $CurrentColumn++;
    $ColumnArray->[$CurrentColumn] = { name => 'Version', sortable => 1, width => '100'};
    $CurrentColumn++;
	$ColumnArray->[$CurrentColumn] = { name => 'Last update', sortable => 1, width => '100'};
    $CurrentColumn++;

	#Get the list of models the user may view
	my $username = "NONE";
	if (defined($user)) {
	  $username = $user->login();
	}
	my @ModelList;
	my @ModelIDList;
	for (my $i=0; $i < $figmodel->number_of_models(); $i++) {
	  my $model = $figmodel->get_model($i);
	  if (defined($model) && $model->source() ne "MGRAST") {
		if ($model->rights($username) == 1) {
		  push(@ModelList,$model);
		}
	  }
	}

	# sort models alphabetically by name
	@ModelList = sort { lc($a->name()) cmp lc($b->name()) } @ModelList;

    #Filling in table of model data
    my $ModelDataTable;
    for (my $i=0; $i < @ModelList; $i++) {
        push(@ModelIDList,$ModelList[$i]->id());
		for (my $j=0; $j < @{$ColumnArray};$j++) {
            $ModelDataTable->[$i]->[$j] = "";
			if ($ColumnArray->[$j]->{name} eq "Compare") {
                $ModelDataTable->[$i]->[$j] = "CHECKBOX:".$i;
            } elsif ($ColumnArray->[$j]->{name} eq "Name") {
				$ModelDataTable->[$i]->[$j] = $figmodel->CreateLink($ModelList[$i]->id(),"model");
            } elsif ($ColumnArray->[$j]->{name} eq "Organism") {
				$ModelDataTable->[$i]->[$j] = $ModelList[$i]->name();
            } elsif ($ColumnArray->[$j]->{name} eq "Genome ID") {
				$ModelDataTable->[$i]->[$j] = $figmodel->GenomeLink($ModelList[$i]->genome());
			} elsif ($ColumnArray->[$j]->{name} eq "Source") {
				if ($ModelList[$i]->source() =~ m/^PMID\d+/) {
				  $ModelDataTable->[$i]->[$j] = $figmodel->CreateLink($ModelList[$i]->source(),"pubmed");
				} else {
				  $ModelDataTable->[$i]->[$j] = $ModelList[$i]->source();
				}
			} elsif ($ColumnArray->[$j]->{name} eq "SBML download link") {
				  $ModelDataTable->[$i]->[$j] = $figmodel->CreateLink("download","SBML",$ModelList[$i]->id());
			} elsif (defined($ModelList[$i]->stats())) {
				if ($ColumnArray->[$j]->{name} eq "Class" && defined($ModelList[$i]->stats()->{"Class"})) {
				  $ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Class"}->[0];
				} elsif ($ColumnArray->[$j]->{name} eq "Genes" && defined($ModelList[$i]->stats()->{"Total genes"})) {
					if (defined($ModelList[$i]->stats()->{"Genes with reactions"})) {
						$ModelDataTable->[$i]->[$j] = $figmodel->CreateLink($ModelList[$i]->stats()->{"Genes with reactions"}->[0],"genelist",$ModelList[$i]->id())."/".$figmodel->CreateLink($ModelList[$i]->stats()->{"Total genes"}->[0],"genelist",$ModelList[$i]->genome());
					} else {
						$ModelDataTable->[$i]->[$j] = "??/".$figmodel->CreateLink($ModelList[$i]->stats()->{"Total genes"}->[0],"genelist",$ModelList[$i]->genome());
					}
				} elsif ($ColumnArray->[$j]->{name} eq "Reactions" && defined($ModelList[$i]->stats()->{"Number of reactions"})) {
					$ModelDataTable->[$i]->[$j] = $figmodel->CreateLink($ModelList[$i]->stats()->{"Number of reactions"}->[0],"reactionlist",$ModelList[$i]->id());
				} elsif ($ColumnArray->[$j]->{name} eq "Compounds" && defined($ModelList[$i]->stats()->{"Metabolites"})) {
					$ModelDataTable->[$i]->[$j] = $figmodel->CreateLink($ModelList[$i]->stats()->{"Metabolites"}->[0],"compoundlist",$ModelList[$i]->id());
				} elsif ($ColumnArray->[$j]->{name} eq "Transporters" && defined($ModelList[$i]->stats()->{"Transport reaction"})) {
					$ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Transport reaction"}->[0];
				} elsif ($ColumnArray->[$j]->{name} eq "Gap filling reactions" && defined($ModelList[$i]->stats()->{"Gap filling reactions"})) {
					$ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Gap filling reactions"}->[0];
				} elsif ($ColumnArray->[$j]->{name} eq "Build date" && defined($ModelList[$i]->stats()->{"Build date"})) {
					$ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Build date"}->[0];
				} elsif ($ColumnArray->[$j]->{name} eq "Gap fill date" && defined($ModelList[$i]->stats()->{"Gap fill date"})) {
					$ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Gap fill date"}->[0];
				} elsif ($ColumnArray->[$j]->{name} eq "Version") {
					my $BuildMessage = "";
					my $GapFillMessage = "";
					if (defined($ModelList[$i]->stats()->{"Gap fill date"})) {
						if ($ModelList[$i]->stats()->{"Gap fill date"}->[0] =~ m/^\d+$/) {
						  $GapFillMessage = " Latest model gapfilling: ".FIGMODEL::Date($ModelList[$i]->stats()->{"Gap fill date"}->[0]);
						} else {
						  $GapFillMessage = " Latest model gapfilling: ".$ModelList[$i]->stats()->{"Gap fill date"}->[0];
						}
					}
					if (defined($ModelList[$i]->stats()->{"Build date"})) {
						if ($ModelList[$i]->stats()->{"Build date"}->[0] =~ m/^\d+$/) {
						  $BuildMessage = "Latest model reconstruction: ".FIGMODEL::Date($ModelList[$i]->stats()->{"Build date"}->[0]);
						} else {
						  $BuildMessage = "Latest model reconstruction: ".$ModelList[$i]->stats()->{"Build date"}->[0];
						}
					}
					$ModelDataTable->[$i]->[$j] = "<span title='".$BuildMessage.$GapFillMessage."'>".$ModelList[$i]->stats()->{"Version"}->[0].".".$ModelList[$i]->stats()->{"Gap fill version"}->[0]."</span>";
				} elsif ($ColumnArray->[$j]->{name} eq "Last update") {
					$ModelDataTable->[$i]->[$j] = "Unknown";
					my $UpdateType = "Gap filling";
					if (defined($ModelList[$i]->stats()->{"Gap fill date"})) {
					  if (defined($ModelList[$i]->stats()->{"Build date"})) {
						$ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Gap fill date"}->[0];
						if ($ModelList[$i]->stats()->{"Build date"}->[0] > $ModelList[$i]->stats()->{"Gap fill date"}->[0]) {
						  $UpdateType = "Reconstruction";
						  $ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Build date"}->[0];
						}
					  }
					} elsif (defined($ModelList[$i]->stats()->{"Build date"})) {
					  $ModelDataTable->[$i]->[$j] = $ModelList[$i]->stats()->{"Build date"}->[0];
					}
					if ($ModelDataTable->[$i]->[$j] =~ m/^\d+$/) {
					  $ModelDataTable->[$i]->[$j] = FIGMODEL::Date($ModelDataTable->[$i]->[$j]);
					}
					if ($ModelDataTable->[$i]->[$j] ne "Unknown") {
					  $ModelDataTable->[$i]->[$j] = "<span title='Model ".$UpdateType." was performed'>".$ModelDataTable->[$i]->[$j]."</span>";
					}
				}
			}
        }
    }

    #Setting table options
    $table->columns($ColumnArray);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->data($ModelDataTable);

    return $table->output();
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/ModelSelectTable.js"];
}
