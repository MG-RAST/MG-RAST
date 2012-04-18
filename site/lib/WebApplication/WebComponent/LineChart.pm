package WebComponent::LineChart;

# LineChart - component to create Line charts

# $Id: LineChart.pm,v 1.1 2007-11-12 16:55:49 arodri7 Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;

use GD;
use GD::Polyline;
use Math::Trig;
use WebComponent::WebGD;
use WebColors;

use constant PI => 4 * atan2 1, 1;
use constant RAD => 2 * PI / 360;

=pod

=head1 NAME

LineChart - component to create Line charts

=head1 DESCRIPTION

Creates an inline image for a line chart with mouseover/onlick regions

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    #$self->application->register_component('Hover', 'LineChartHover'.$self->id());

    $self->{color_set} = WebColors::get_colors();
    $self->{colors} = [];
    $self->{image} = undef;
    $self->{height} = 200;
    $self->{width} = 800;
    $self->{data} = undef;
    $self->{show_tooltip} = 1;
    $self->{show_titles} = 1;
    $self->{show_values} = 1;
    $self->{value_type} = 'absolute';
    $self->{show_axes} = 1;
    $self->{show_line_frames} = 1;
    $self->{titles} = [];
    $self->{step_size} = 5;
    $self->{window_size} = 50;
    $self->{length} = undef;

    return $self;
}

=item * B<output> ()

Returns the html output of the LineChart component.

=cut

sub output {
    my ($self) = @_;

    my $data = $self->data();
  
    unless (defined($data)) {
	return "LineChart called without data";
    }

    my $padding = 20; # width / height of axes
    my $height = $self->height();
    my $width = $self->width();
    my $seqlength = $self->length();
    my $window_size = $self->window_size();
    my $im = $self->image();
    my $colors = $self->colors();
    # 67 => blue, 2 => red, ? => green, 1 => black
    my %line_colors = ( 0 => $colors->[67],
			1 => $colors->[2],
			2 => $colors->[4],
			3 => $colors->[1]);
    my @map_spots;
    #my $hover = $self->application->component('BarChartHover'.$self->id());


    my $color_count=0;
    foreach my $val (@{$self->data()}) {
	foreach my $val_part (@$val) {
	    my $count=0;
	    my $polyline = new GD::Polyline;
	    my $point_total = scalar(@$val_part);
	    my $x_scale = (($seqlength-($window_size*3))/($point_total-1));
	    foreach my $plot_point (@$val_part){
		$polyline->addPt($count*$x_scale*8.081, abs($plot_point-100)*2);
		#print STDERR "FRAME: $color_count, X: $count, Y: " . abs($plot_point-100) . "\n";
		$count++;
	    }
	    $polyline->offset(($window_size*3/2)*8.0815,0);

	    if ($color_count == 3){
		$im->setStyle($line_colors{$color_count},$line_colors{$color_count},$line_colors{$color_count},$line_colors{$color_count},
			      $line_colors{$color_count},$line_colors{$color_count},$line_colors{$color_count},$line_colors{$color_count},
			      gdTransparent,gdTransparent);
		$im->polyline($polyline,gdStyled);
	    }
	    else{
		$im->polyline($polyline,$line_colors{$color_count});
	    }

	    if ($color_count < 3){
		my $ring_node = new GD::Polygon;
		
		$ring_node->addPt( 0, 0);
		$ring_node->addPt(2, 0);
		$ring_node->addPt(2,2);
		$ring_node->addPt( 0,2);
		
		for my $ring_vertex ($polyline->vertices()) {
		    $ring_node->offset($ring_node->centroid(-1));
		    $ring_node->offset(@$ring_vertex);
		    $im->filledPolygon($ring_node,$line_colors{$color_count});
		}
	    }

	    $color_count++;
	}
    }

    # create html
    my $graph = qq~<img src="~ . $self->image->image_src()  . qq~">~;

    # return html
    return $graph;

}

sub sum {
    my $array = shift;
  
    my $sum = 0;
    foreach (@$array) {
	$sum += $_;
    }

    return $sum;
}

sub width {
    my ($self, $width) = @_;

    if (defined($width)) {
	$self->{width} = $width;
    }

    return $self->{width};
}

sub height {
    my ($self, $height) = @_;

    if (defined($height)) {
	$self->{height} = $height;
    }

    return $self->{height};
}

sub image {
    my ($self) = @_;

    unless (defined($self->{image})) {
	$self->{image} = new WebGD($self->width(), $self->height());
	foreach my $triplet (@{$self->color_set}) {
	    push(@{$self->colors}, $self->image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
	}
    }

    return $self->{image};
}

sub data {
    my ($self, $data) = @_;

    if (defined($data)) {
	$self->{data} = $data;
    }

    return $self->{data};
}

sub show_axes {
    my ($self, $show_axes) = @_;

    if (defined($show_axes)) {
	$self->{show_axes} = $show_axes;
    }

    return $self->{show_axes};
}

sub show_titles {
    my ($self, $show_titles) = @_;

    if (defined($show_titles)) {
	$self->{show_titles} = $show_titles;
    }

    return $self->{show_titles};
}

sub show_values {
    my ($self, $show_values) = @_;

    if (defined($show_values)) {
	$self->{show_values} = $show_values;
    }

    return $self->{show_values};
}

sub value_type {
    my ($self, $value_type) = @_;

    if (defined($value_type)) {
	$self->{value_type} = $value_type;
    }

    return $self->{value_type};
}

sub show_bar_frames {
    my ($self, $show_bar_frames) = @_;
  
    if (defined($show_bar_frames)) {
	$self->{show_bar_frames} = $show_bar_frames;
    }
  
    return $self->{show_bar_frames};
}

sub colors {
    my ($self, $colors) = @_;
  
    if (defined($colors)) {
	$self->{colors} = $colors;
    }

    return $self->{colors};
}

sub color_set {
    my ($self, $color_set) = @_;

    if (defined($color_set)) {
	$self->{color_set} = $color_set;
    }

    return $self->{color_set};
}

sub titles {
    my ($self, $titles) = @_;

    if (defined($titles)) {
	$self->{titles} = $titles;
    }

    return $self->{titles};
}

sub window_size {
    my ($self, $window_size) = @_;

    if (defined($window_size)) {
	$self->{window_size} = $window_size;
    }

    return $self->{window_size};
}

sub step_size {
    my ($self, $step_size) = @_;

    if (defined($step_size)) {
	$self->{step_size} = $step_size;
    }

    return $self->{step_size};
}

sub length {
    my ($self, $length) = @_;

    if (defined($length)) {
	$self->{length} = $length;
    }

    return $self->{length};
}
