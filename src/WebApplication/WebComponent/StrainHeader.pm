package WebComponent::StrainHeader;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;
use WebColors;

1;

=pod

=head1 NAME

StrainHeader - an introductory summary of strain development information

=head1 DESCRIPTION

An intorductory paragraph summarizing strain development information.

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application()->register_component('IntervalDraw', 'str_hdr_interval_draw');
  $self->application()->register_component('GrowthData', 'str_hdr_growth_data');

  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {
  my ($self) = @_;

  #Getting various packages
  my $application = $self->application();
  my $model = $application->data_handle('FIGMODEL');
  my $user = $application->session->user;
  my $cgi = $application->cgi();

  my $Strain = $cgi->param( 'id' );

  #get the interval_draw component
  my $interval_draw = $application->component('str_hdr_interval_draw');
  my $growth_data = $application->component('str_hdr_growth_data');

  #define the strain and interval table
  my $StrainTableModel = $model->database()->GetDBTable("STRAIN TABLE");
  my $IntervalTable = $model->database()->GetDBTable("INTERVAL TABLE");

  #Get header parameters
  my $strainCount = $self->getStrainCount($StrainTableModel);
  my $intervalCount = $self->getIntervalCount($IntervalTable);

  my ($min_strain_ID, $min_strain_interval_count, $min_strain_KO_size) = $self->getMinimalStrain($StrainTableModel, $IntervalTable);

  my $html .= "<span style='float: left; padding: 5px;'><h3>Summary</h3>";
  $html .= "<p style='max-width: 300px;'>There are " . $strainCount . " strains created from " .
		 $intervalCount . " interval knockouts. The smallest viable strain is " .
		"<a href='seedviewer.cgi?page=StrainViewer&id=$min_strain_ID'>".$min_strain_ID."</a>".
		", containing " . $min_strain_interval_count . " interval knockouts, resulting" .
		" in the removal of " . $min_strain_KO_size/1000 . "Kbp. Select a strain from the".
		" tree below or the table at the bottom.</p>"; #, a " . $min_strain_Percent .
#		"% reduction in geneome size.";
  $html .= $growth_data->keyNodeColor()."</span>";
  #$html .= join(',', @{$growth_data->ColorType('green', 'array')});
  # 28, 134, 53
  my $IDs = '';
  if(defined($Strain)) {
  	my $row = $StrainTableModel->get_row_by_key($Strain, 'ID');
	if(defined($row)) {
  		$IDs = join(',', @{$row->{'INTERVALS'}});
	}
  }
  $html .= "<span style='float: left; width: 800px;'>".$interval_draw->output(800, $IDs)."</span>";
  return $html;
}

sub getStrainCount {
	my ($self, $StrainTable) = @_;
    my @IDs = $StrainTable->get_hash_column_keys("ID");
    return @IDs;
}
sub getIntervalCount {
	my ($self, $IntervalTable) = @_;
    my @IDs = $IntervalTable->get_hash_column_keys("ID");
    return @IDs;
}

sub getMinimalStrain {
	my ($self, $StrainTable, $IntervalTable) = @_;
#Loading the data table listing the reactions in the model or in the database
    my $min_strain_ID = '';
    my $min_strain_KO_size = 0;
    my $min_strain_interval_count = 0;
    my $row = 0;
    my @IDs = $StrainTable->get_hash_column_keys("ID");
	foreach my $ID (@IDs) {
		my $rowhash = $StrainTable->get_row_by_key($ID, 'ID');
		my $intervalIDs = $rowhash->{'INTERVALS'};
		if(defined($intervalIDs)) {
			my $curr_KO_sum = 0;
			my $curr_ID = $ID;
			my $curr_interval_count = 0;
			foreach my $id (@{$intervalIDs}) {
				$curr_interval_count++;
				my $intervalRow = $IntervalTable->get_row_by_key($id, 'ID');
				if(defined($intervalRow)) {
					my $start = $intervalRow->{'START'}->[0];
					my $end   = $intervalRow->{'END'}->[0];
					$curr_KO_sum += ($end - $start);
				}
			}
			if($curr_KO_sum > $min_strain_KO_size) {
				$min_strain_KO_size = $curr_KO_sum;
				$min_strain_ID		= $curr_ID;
				$min_strain_interval_count = $curr_interval_count; }
		}
  }

  return ($min_strain_ID, $min_strain_interval_count, $min_strain_KO_size);
}

sub require_css {
	return './Html/StrainViewer.css';
}
