package WebComponent::StrainTree;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

StrainTree - a tree of the strain lineage

=head1 DESCRIPTION

This component displays a horizontal tree of strains.

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('Tree', 'StrainTree');
  $self->application->register_component('GrowthData', 'strain_tree_growth_data');
  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {

  my ($self, $IDs) = @_;
  unless(defined($IDs)) { $IDs = '' };
  my $html = "<h3>Strain Lineage</h3>";

  # Getting various application objects
  my $application = $self->application();
  my $model = $application->data_handle('FIGMODEL');
  my $user = $application->session->user;
  my $cgi = $application->cgi();
  my $CGI_Page = $cgi->param( 'page' );

  # getting web components
  my $tree = $application->component('StrainTree');

  # getting the strain data
  my $StrainTable = $model->database()->GetDBTable('STRAIN TABLE');
  my $top = $self->getOrphans($StrainTable);
  foreach my $strain (@{$top}) {
	my $data = $self->getChildren($StrainTable, $strain);
	my $ID = shift(@{$data});
	my $node = $tree->add_node( { 'label' => $self->labelNodeID($ID, $IDs), 'expanded' => 1 } );
	foreach my $child (@{$data}) {
    	$self->makeTree($node, $child, $IDs);
  	}
  }
  $html .= $tree->output();
  return $html;
}

sub makeTree {
	my ($self, $tree, $data, $IDs) = @_;
	my $ID = shift(@{$data});
	my $newNode = $tree->add_child( {'label' => $self->labelNodeID($ID, $IDs), 'expanded' => 1} );
	foreach my $child (@{$data}) {
		$self->makeTree($newNode, $child);
	}
	return $tree;
}

sub getOrphans {
	my ($self, $StrainTable) = @_;
	my @rows = $StrainTable->get_rows_by_key('None', 'BASE');
	my @Orphans;
	foreach my $row (@rows) {
		push(@Orphans, $row->{'ID'}->[0]);
	}
	return \@Orphans;
}

sub getChildren {
	my ($self, $StrainTable, $ID) = @_;
	my $Tree;
	push(@{$Tree}, $ID);
	my @rows = $StrainTable->get_rows_by_key($ID, 'BASE');
	unless(@rows) { return \@{$Tree}}
	foreach my $row (@rows) {
		my $childID = $row->{'ID'}->[0];
		my $childTree = $self->getChildren($StrainTable, $childID);
		push(@{$Tree}, $childTree);
	}
	return $Tree;
}

sub labelNodeID {
	my ($self, $ID, $IDs) = @_;
	#my @CurrIDs = split(',', $IDs);
	my $GrowthDisplay = $self->application->component('strain_tree_growth_data');
	my $color = $GrowthDisplay->treeNodeColor($ID);
#	foreach my $currID (@CurrIDs) {
	#	if($currID == $ID) { $color = 'rgb(204,0,51)'; }
#	}
	return "<a style='color: $color; font-weight: bold; text-decoration: none;'".
		" href='seedviewer.cgi?page=StrainViewer&id=$ID'>$ID</a>".
		"    <a title='Create new strain using $ID as a base.'".
		" style='color: $color; text-decoration: none;'".
		"href='seedviewer.cgi?page=StrainViewer&id=$ID&act=NEW'>+</a>";
	}
