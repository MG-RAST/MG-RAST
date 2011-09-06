package WebComponent::GrowthData;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;
use WebColors;

1;

=pod

=head1 NAME

Growth Data
=head1 DESCRIPTION

Print growth information for intervals on different media conditions.

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  return $self;
}

=item * B<output> ()
Takes: $self, $ID - either an interval or a strain ID
Returns the html output of the ModelSelect component.

=cut

sub output {
  my ($self, $ID) = @_;
  my $MPAList = $self->getMediaPredictedActual($ID);
  my $html = "";
  $html .= "<table>";
  foreach my $MPA (@{$MPAList}) {
	my $Media     = $MPA->{'MEDIA'};
	my $Predicted = $MPA->{'PREDICTED'};
	my $Actual    = $MPA->{'ACTUAL'};

	my $Acolor = $self->colorLookup($Actual);
	my $Pcolor = $self->colorLookup($Predicted);
	my $PrintPredicted;
	my $PrintActual;

	$html .= "<tr>";
	$html .= "<td>" . $Media . ":</td>";
	# Format Predicted value as unknown or x.xx float string
	if( $Predicted == -1 ) { $PrintPredicted = "Unknown";}
	else { $PrintPredicted = sprintf("%1.2f", $Predicted); }

	# Format Actual value as unknown ?.?? or x.xx float string
	if( $Actual == -1 ) { $PrintActual = "Unknown"; }
	else { $PrintActual = sprintf("%1.2f", $Actual); }

	$html .= "<td style='color:" . $Acolor . "; font-weight: bold;'>" .
		"<span title='Actual Growth'>" . $PrintActual . "</span></td>";
	$html .= "<td style='color:" . $Pcolor . "; font-weight: bold;'>" .
		"<span title='Predicted Growth'>" . $PrintPredicted . "</span></td>";
    $html .= "</tr>";
  }
  $html .= "</table>";
  return $html;
}

sub colorLookup {
	my ($self, $growth) = @_;
	my $color = [127, 127, 127];
	if ( $growth < 0 ) { $color = [127, 127, 127]; }
	elsif( $growth > 0.5 ) {
		$growth = 2 * ($growth - 0.5); # rescale
		$color = [204 - ($growth * 204), 204, 51];
	} elsif ( $growth < 0.5 ) {
		$growth = 2 * $growth;
		$color = [204, (204 * $growth), 51];
	} else { $color = [204, 204, 51]; }
	return $self->toHex($color);
#	if    ( $growth == -1  )  {$color = "grey"}
#	elsif ( $growth <= 0.1 )  {$color = "red" }
#	elsif ( $growth <= 0.4 )  {$color = "#FFA824" }
#	elsif ( $growth <  0.8 )  {$color = "#AADD00" }
#	elsif ( $growth >= 0.8 )  {$color = "#006400"}
}

sub ColorType {
	my ($self, $color, $type, $shift) = @_;
	unless(defined($shift)) { $shift = 1; }
	my $array = { blue => [ 61,72,139 ],
					green => [ 27,133,52 ],
					orange => [ 224,133,15 ],
					purple => [ 160,15,250 ],
					red => [ 204,0,52 ],
					grey => [ 95,100,100 ]};

	my $colors = $array->{$color};
	if($shift != 1) {
		$colors = WebColors::rgb_to_hsl($colors);
		$colors->[2] += $shift/100;
		$colors = WebColors::hsl_to_rgb($colors);
	}
	if($type eq 'hex') { return $self->toHex($colors); }
	else {  return $colors; }
}

sub toHex {
	my ($self, $RGBarray) = @_;
	my $hexstr = "#";
	foreach my $value (@{$RGBarray}) {
		$value = $value % 256; # scale to 8-bit values
		$hexstr .= sprintf('%02x', $value);
	}
	return $hexstr;
}

sub MPAColorType {
	my ($self, $Predicted, $Actual) = @_;
	if($Actual >= 0.01) {
		# True Positive
		if($Predicted >= 0.01) { return "blue"; }
		# False Negative
		elsif($Predicted <= 0.01) { return "green"; }
	}
	elsif($Actual <= 0.01) {
		# False Positive
		if($Predicted >= 0.01) { return "orange"; }
		# True Negative
		elsif($Predicted <= 0.01) { return "purple"; }
	# None Found
	} else { return "grey" }
}

sub conflictCount {
	my ($self, $ID) = @_;
    my $count = 0;
    my $model = $self->application()->data_handle('FIGMODEL');
    my $StrainTable = $model->database()->GetDBTable('STRAIN TABLE');
    my $IntervalTable = $model->database()->GetDBTable('INTERVAL TABLE');
    my $GrowthTable = $model->database()->GetDBTable('STRAIN SIMULATIONS');
    my $type;
    my $StrainOrIntervalRow;
    # Sainity Checking on ID
    my $StrainRow = $StrainTable->get_row_by_key($ID, 'ID');
    my $IntervalRow = $IntervalTable->get_row_by_key($ID, 'ID');
    # There can only be ONE.
    if(defined($StrainRow) && !defined($IntervalRow)) {
    	# Found a strain
    	$type = 'strain';
    	$StrainOrIntervalRow = \%{$StrainRow};
    } elsif (!defined($StrainRow) && defined($IntervalRow)) {
    	# Found an interval
    	$type = 'interval';
    	$StrainOrIntervalRow = \%{$IntervalRow};
    } else {
     	return " ";
    }

    # Get Growth Data, sorted by date
    $GrowthTable->sort_rows('TIME');
    my $GrowthRow = $GrowthTable->get_row_by_key($ID, 'ID');
    unless(defined($GrowthRow)) {
    	return " ";
    }
    my $GrowthArray = $GrowthRow->{'MEDIA'};
    for(my $i=0; $i < @{$GrowthArray}; $i++) {
	    my $Media     = $GrowthRow->{'MEDIA'}->[$i];
		my $Actual = undef;
	    my $Predicted = $GrowthRow->{'GROWTH'}->[$i];

	    my $growth_array = $StrainOrIntervalRow->{'GROWTH'};
	    foreach my $growth_str (@{$growth_array}) {
		    my @data_array = split(':', $growth_str);
		    if($data_array[0] eq $Media) {
			    $Actual = $data_array[1];
			    last;
		    }
		}
		unless(defined($Actual)) { next; }
		if( $Actual > 0 && $Predicted == 0) {
			$count += 1;
		} elsif( $Actual == 0 && $Predicted > 0) {
			$count += 1;
		} else {
		}
	}
	return $count;
}
sub treeNodeColor {
	my ($self, $ID) = @_;
	my $MPAList = $self->getMediaPredictedActual($ID);
	my $color = "grey";
	unless(defined($MPAList)) {
		return $color;
	}
	foreach my $MPA (@{$MPAList}) {
		my $Media     = $MPA->{'MEDIA'};
		my $Predicted = $MPA->{'PREDICTED'};
		my $Actual    = $MPA->{'ACTUAL'};
		if($Media eq 'ArgonneLBMedia') {
			$color = $self->MPAColorType($Predicted, $Actual);
			$color = $self->ColorType($color, 'hex');
			return $color;
		}
	}
	return $color;
}

sub intervalNodeColor {
	my ($self, $ID) = @_;
	my $MPAList = $self->getMediaPredictedActual($ID);
	my $color = [ 95,100,100 ];
	unless(defined($MPAList)) { return $color; }
	foreach my $MPA (@{$MPAList}) {
		my $Media     = $MPA->{'MEDIA'};
		my $Predicted = $MPA->{'PREDICTED'};
		my $Actual    = $MPA->{'ACTUAL'};
		if($Media eq 'ArgonneLBMedia') {
			$color = $self->MPAColorType($Predicted, $Actual);
			$color = $self->ColorType($color, 'array');
			return $color;
		}
	}
	return $color;
}

sub keyNodeColor {
	my ($self) = @_;
	my $html = "<table>";
	my $colorBox = sub {
		my ($color) = @_;
		return "<div style='width: 10px; height: 10px; padding: 1px; background-color: $color'/>";
	};
	my @colors = ('blue', 'green', 'orange', 'purple', 'grey', 'red');
	my @descriptions = ('Correctly predicted growth', 'Failed to predict growth',
				'Failed to predict no growth', 'Correctly predicted no growth', 'No observations',
				'Currently Selected Strain or Interval');
	for(my $i=0; $i<@colors; $i++) {
		my $hex = $self->ColorType($colors[$i], 'hex');
		$html .= "<tr><td>".$hex->$colorBox."</td><td>".$descriptions[$i]."</td></tr>";
	}
	return $html . "</table>";
}

sub getMediaPredictedActual {
	my ($self, $ID) = @_;
	my @MediaPredictedActualList;
    my $model = $self->application()->data_handle('FIGMODEL');
	my $StrainTable = $model->database()->GetDBTable('STRAIN TABLE');
	my $IntervalTable = $model->database()->GetDBTable('INTERVAL TABLE');
	my $GrowthTable = $model->database()->GetDBTable('STRAIN SIMULATIONS');

	my $type;
	my $StrainOrIntervalRow;
	# Sainity Checking on ID
	my $StrainRow = $StrainTable->get_row_by_key($ID, 'ID');
	my $IntervalRow = $IntervalTable->get_row_by_key($ID, 'ID');
	# There can only be ONE.
	if(defined($StrainRow) && !defined($IntervalRow)) {
		# Found a strain
		$type = 'strain';
		$StrainOrIntervalRow = \%{$StrainRow};
	} elsif (!defined($StrainRow) && defined($IntervalRow)) {
		# Found an interval
		$type = 'interval';
		$StrainOrIntervalRow = \%{$IntervalRow};
	} else { return undef; } # Could not find $ID, fail.

    # Get Growth Data, sorted by date
  	$GrowthTable->sort_rows('TIME');
  	my $GrowthRow = $GrowthTable->get_row_by_key($ID, 'ID');
  	unless(defined($GrowthRow)) {
		return undef;
  	}
	my @GrowthNames = ('Unknown', 'No Growth', 'Very Slow', 'Slow', 'Normal', 'Fast');
    my $GrowthArray = $GrowthRow->{'MEDIA'};
	for(my $i=0; $i < @{$GrowthArray}; $i++) {
		my $Media     = $GrowthRow->{'MEDIA'}->[$i];
		my $Predicted = $GrowthRow->{'GROWTH'}->[$i];

		my $Actual = undef;
		my $growth_array = $StrainOrIntervalRow->{'GROWTH'};
		foreach my $growth_str (@{$growth_array}) {
			my @data_array = split(':', $growth_str);
			if($data_array[0] eq $Media) {
				$Actual = $data_array[1];
				last;
			}
		}
		unless(defined($Actual)) { $Actual = -1; }
		push(@MediaPredictedActualList, {'MEDIA' => $Media, 'PREDICTED' => $Predicted, 'ACTUAL' => $Actual});
	}
	return \@MediaPredictedActualList;
}
