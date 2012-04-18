package WebComponent::LeftArrow;

# LeftArrow - component to create Line charts

# $Id: LeftArrow.pm,v 1.1 2007-11-12 16:53:11 arodri7 Exp $

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

LeftArrow - component to create Line charts

=head1 DESCRIPTION

Creates an inline image for a line chart with mouseover/onlick regions

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    #$self->application->register_component('Hover', 'LeftArrowHover'.$self->id());

    $self->{color_set} = WebColors::get_colors();
    $self->{colors} = [];
    $self->{image} = undef;
    $self->{height} = 50;
    $self->{width} = 250;
    $self->{show_titles} = 1;
    $self->{show_values} = 1;

    return $self;
}

=item * B<output> ()

Returns the html output of the LeftArrow component.

=cut

sub output {
    my ($self) = @_;

    my $padding = 20; # width / height of axes
    my $height = $self->height();
    my $width = $self->width();
    my $im = $self->image();
    my $colors = $self->colors();
    my $color_count=68;
    my @map_spots;
    my %speed = ( '4' => 1,
		  '3' => 10,
		  '2' => 100,
		  '1' => 1000,
		  '0' => 10000 );

    for (my $n=0; $n<=4; $n++) {
        my $arrowControl = new GD::Polyline;
	my $x1=10+(41*$n); my $y1=0;
	my $x2=0+(41*$n); my $y2=10;
	my $x3=10+(41*$n); my $y3=20;
	my $x4=50+(41*$n); my $y4=20;
	my $x5=40+(41*$n); my $y5=10;
	my $x6=50+(41*$n); my $y6=0;

        $arrowControl->addPt($x1,$y1);
        $arrowControl->addPt($x2,$y2);
        $arrowControl->addPt($x3,$y3);
        $arrowControl->addPt($x4,$y4);
        $arrowControl->addPt($x5,$y5);
        $arrowControl->addPt($x6,$y6);
        #$arrowControl->scale(2, 2);
        #$arrowControl->offset(41 * $n,0);
        $im->filledPolygon($arrowControl,$colors->[$color_count]);
	$color_count--;
	push(@map_spots, "<area shape='polygon' coords='$x1,$y1,$x2,$y2,$x3,$y3,$x4,$y4,$x5,$y5,$x6,$y6' onmouseover='javascript:move_side(\"codon_scroll\", -$speed{$n});' onMouseOut='javascript:stop_move(\"codon_scroll\");'>");
    }

    # create image map
    my $map = "<map name='imap_leftarrow_".$self->id."'>\n".join("\n", @map_spots)."\n</map>";

    # create html
    my $graph = qq~<img src="~ . $self->image->image_src()  . qq~" usemap="#imap_leftarrow_~ . $self->id . qq~">~.$map;

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
