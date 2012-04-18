package WebComponent::RightArrow;

# RightArrow - component to create Line charts

# $Id: RightArrow.pm,v 1.1 2007-11-12 16:55:11 arodri7 Exp $

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

RightArrow - component to create Line charts

=head1 DESCRIPTION

Creates an inline image for a line chart with mouseover/onlick regions

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    #$self->application->register_component('Hover', 'RightArrowHover'.$self->id());

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

Returns the html output of the RightArrow component.

=cut

sub output {
    my ($self) = @_;

    my $padding = 20; # width / height of axes
    my $height = $self->height();
    my $width = $self->width();
    my $im = $self->image();
    my $colors = $self->colors();
    my $color_count=64;
    my @map_spots;

    my %speed = ( '0' => 1,
                  '1' => 10,
                  '2' => 100,
                  '3' => 1000,
                  '4' => 10000 );

    for (my $n=0; $n<=4; $n++) {
        my $arrowControl = new GD::Polyline;

        my $x1=0+(41*$n); my $y1=0;
        my $x2=10+(41*$n); my $y2=10;
        my $x3=0+(41*$n); my $y3=20;
        my $x4=40+(41*$n); my $y4=20;
        my $x5=50+(41*$n); my $y5=10;
        my $x6=40+(41*$n); my $y6=0;

        $arrowControl->addPt($x1,$y1);
        $arrowControl->addPt($x2,$y2);
        $arrowControl->addPt($x3,$y3);
        $arrowControl->addPt($x4,$y4);
        $arrowControl->addPt($x5,$y5);
        $arrowControl->addPt($x6,$y6);
        #$arrowControl->scale(1, 1);
        #$arrowControl->offset(41 * $n,0);
        $im->filledPolygon($arrowControl,$colors->[$color_count]);
	$color_count++;
	push(@map_spots, "<area shape='polygon' coords='$x1,$y1,$x2,$y2,$x3,$y3,$x4,$y4,$x5,$y5,$x6,$y6' onmouseover='javascript:move_side(\"codon_scroll\", $speed{$n});' onMouseOut='javascript:stop_move(\"codon_scroll\");'>");

    }

    # create image map
    my $map = "<map name='imap_rightarrow_".$self->id."'>\n".join("\n", @map_spots)."\n</map>";

    # create html
    my $graph = qq~<img src="~ . $self->image->image_src()  . qq~" usemap="#imap_rightarrow_~ . $self->id . qq~">~.$map;

    # return html
    return $graph;

}


sub NewImage {
    my $image = new GD::Image (500,300);

    my $white  = $image->colorAllocate(255,255,255);
    my $black  = $image->colorAllocate(  0,  0,  0);
    my $grey   = $image->colorAllocate(128,128,128);
    my $red    = $image->colorAllocate(255,  0,  0);
    my $orange = $image->colorAllocate(255,196,  0);
    my $green  = $image->colorAllocate(  0,255,  0);
    my $blue   = $image->colorAllocate(  0,  0,255);
    my $cyan   = $image->colorAllocate(  0,255,255);
    my $purple = $image->colorAllocate(206,  0,165);

    my $brush_width = 2;
    my $brush_color = [255,128,0];
    my $brush = new GD::Image($brush_width,$brush_width);
    $brush->transparent($brush->colorAllocate(255,255,255));
    $brush->filledRectangle(0,0,$brush_width,$brush_width,$brush->colorAllocate(@$brush_color));
    my $brush1 = $brush;

    $brush_width = 3;
    $brush_color = [206,0,165];
    $brush = new GD::Image($brush_width,$brush_width);
    $brush->transparent($brush->colorAllocate(255,255,255));
    $brush->filledRectangle(0,0,$brush_width,$brush_width,$brush->colorAllocate(@$brush_color));
    my $brush2 = $brush;

    $image->setBrush($brush1);

    $image;
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
