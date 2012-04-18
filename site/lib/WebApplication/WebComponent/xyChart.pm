package WebComponent::xyChart;

# xyChart - component to create Line charts

# $Id: xyChart.pm,v 1.1 2008-08-04 15:36:01 arodri7 Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;

use GD;
use GD::Polyline;
use Math::Trig;
use WebComponent::WebGD;
use WebColors;

=pod

=head1 NAME

xyChart - component to create xy graphs

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

    $self->{colors} = [];
    $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
    $self->{image} = undef;
    $self->{legend_image} = undef;
    $self->{legend_height} = 20;
    $self->{height} = 200;
    $self->{width} = 400;
    $self->{legend_width} = 20;
    $self->{data} = undef;
    $self->{show_tooltip} = 1;
    $self->{show_titles} = 1;
    $self->{show_values} = 1;
    $self->{type} = 'absolute';
    $self->{show_axes} = 1;
    $self->{x_axis} = 'scalar';
    $self->{x_axis_title} = 'x-axis title';
    $self->{y_axis} = 'scalar';
    $self->{y_axis_title} = 'y-axis title';    
    $self->{show_line_frames} = 1;
    $self->{title} = undef;
    $self->{legend} = 0;

    return $self;
}

=item * B<output> ()

Returns the html output of the LineChart component.

=cut

sub output {
    my ($self) = @_;

    my $data = $self->data();
    unless (defined($data)) {
	return "xy Chart called without data";
    }

    my $height = $self->height();
    my $width = $self->width();
    my $padding = 40;

#    #my $hover = $self->application->component('BarChartHover'.$self->id());

    my $image = $self->image();
    my $black  = $image->colorAllocate(  0,  0,  0);
    my $red    = $image->colorAllocate(255,  0,  0);
        
    # create a new polyline
    my $polylines;
    my $legends;
    
    # figure out the max points in the x and y axis
    my (@x, @y);
    foreach my $val (@{$self->data()}) {
	foreach my $val_part (@$val) {
	    #foreach my $plot_point (@$val_part){
		next if ($val_part->[0] =~ /\D/);
		push (@x, $val_part->[0]);
		push (@y, $val_part->[1]);
	    #}
	}
    }
    
    # check the type of graph (absolute, or percent)
    my ($max_x, $max_y);
    if ($self->type eq 'absolute'){
	$max_x = &axis_max(\@x, $self->x_axis);
	$max_y = &axis_max(\@y, $self->y_axis);
    }
    elsif ($self->type eq 'percent'){
        $max_x = &axis_max(\@x, $self->x_axis);
        $max_y = 1;
    }
    
    #### add the graph points
    my $count = 0;
    my $legend_table = "<table>";

    foreach my $val (@{$self->data()}) {
	my $polyline = new GD::Polyline;
	foreach my $val_part (@$val) {
	    if (($val_part->[0] eq 'name') && ($self->legend) ){
		my $legend_image = $self->legend_image();
		my $legend_line = new GD::Polyline;
		$legend_line->addPt(0,$self->legend_height/3);
		$legend_line->addPt($self->legend_width,$self->legend_height/3);
		$legend_image->polydraw($legend_line, $self->colors->[$count + 6]);
		$legend_table .= qq~<tr><td><img src="~ . $self->legend_image->image_src()  . qq~"></td><td style="font-size:7pt;">~ . $val_part->[1] . qq~</td></tr>~;
	    }
	    elsif ($val_part->[0] !~ /\D/){
		my $x = &axis_value($val_part->[0], $self->x_axis, $width, $padding, $max_x);
		my $y = &axis_value($val_part->[1], $self->y_axis, $height, $padding, $max_y);
		$polyline->addPt($x, abs($height - $y));
	    }
	}
	$polylines->{$count}->{poly} = $polyline;
	$polylines->{$count}->{color} = $self->colors->[$count + 6];
	$count++;
    }
    $legend_table .= "</table>";

    # add x-axis
    my $x_axis = new GD::Polyline;
    $x_axis->addPt(($padding+0),abs($padding-($height)));
    for(my $i=1;$i<=10;$i++){
	$x_axis->addPt($padding+($i*(($width-2*$padding) / 10)), abs($padding-($height)));
	$x_axis->addPt($padding+($i*(($width-2*$padding) / 10)), abs($padding-($height+5)));
	$x_axis->addPt($padding+($i*(($width-2*$padding) / 10)), abs($padding-($height-5)));
	$x_axis->addPt($padding+($i*(($width-2*$padding) / 10)), abs($padding-($height)));
	if ($self->x_axis eq 'scalar'){
	    $image->string(gdSmallFont,$padding+($i*(($width-2*$padding) / 10))-10,($height-($padding*(3/4))), $i*($max_x/10),$black);
	}
	elsif ($self->x_axis eq 'log'){
	    $image->string(gdSmallFont,$padding+($i*(($width-2*$padding) / 10))-10,($height-($padding*(3/4))), 10,$black);
	    $image->string(gdTinyFont, $padding+($i*(($width-2*$padding) / 10))+13-10, ($height-($padding*(3/4))), $i-1,$black);
	}
    }
    $image->string(gdMediumBoldFont,$padding+($width/3),($height-($padding*(1/2))), $self->x_axis_title, $black);
    $image->polydraw($x_axis,$black);

    # add y-axis
    my $y_axis = new GD::Polyline;
    $y_axis->addPt($padding,abs($padding-($height)));
    for (my $i=1;$i<=10;$i++){
	$y_axis->addPt($padding  , (($height-$padding)-($i*(($height-2*$padding)/10))));
	$y_axis->addPt($padding-5, (($height-$padding)-($i*(($height-2*$padding)/10))));
	$y_axis->addPt($padding+5, (($height-$padding)-($i*(($height-2*$padding)/10))));
	$y_axis->addPt($padding  , (($height-$padding)-($i*(($height-2*$padding)/10))));
	if ($self->y_axis eq 'scalar'){
	    $image->string(gdSmallFont, $padding*(2/5), (($height-$padding)-($i*(($height-2*$padding)/10)))-10, $i*($max_y/10),$black);
	}
	elsif ($self->y_axis eq 'log'){
	    $image->string(gdSmallFont, $padding*(2/5), (($height-$padding)-($i*(($height-2*$padding)/10)))-10, 10,$black);
	    $image->string(gdTinyFont, ($padding*(2/5))+13, (($height-$padding)-($i*(($height-2*$padding)/10)))-10, $i-1,$black);
	}
    }
    $image->stringUp(gdMediumBoldFont,2/5,$padding+($height/2), $self->y_axis_title, $black);
    $image->polydraw($y_axis,$black);

    # draw the polylines
    foreach my $key (keys %$polylines){
	$image->polydraw($polylines->{$key}->{poly},$polylines->{$key}->{color});
    }

    # create html with the graph's title
    my $graph = qq~<table style="border-width:1px;border-color:blue;border-style:solid;"><tr><td colspan='2' align='center'><b>~ . $self->title  . qq~</b></td></tr><tr><td><img src="~ . $self->image->image_src()  . qq~"></td><td>$legend_table</td></tr></table>~;

    # return html
    return $graph;

}

sub axis_value {
    my ($raw, $type, $range, $padding, $max_value) = @_;

    my $value;
    if ($type eq 'scalar'){
	$value = $padding + $raw*(($range-(2*$padding))/$max_value);
    }
    elsif ($type eq 'log'){
	$value = $padding + ((log($raw)/log(10))*(($range-(2*$padding))/$max_value));
	$value += ($range-$padding)/10;
    }
    return $value;
}

sub axis_max {
    my ($pts, $type) = @_;

    my @axis_pts = sort {$b<=>$a} @$pts;
    
    my $max;
    if ($type eq 'log'){
	$max = log($axis_pts[0])/log(10);
    }
    elsif ($type eq 'scalar'){
	$max = $axis_pts[0];
    }
    
    my @digits = split (//,$max);
    my $count = 0;
    my $number;
    foreach my $d (@digits){
	last if ($d eq ".");
	if ($count == 0){
	    $number = $d+1;
	}
	else{
	    $number .= 0;
	}
	$count++;
    }

    while ($number%10 != 0){
	$number++;
    }
    return $number;
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

sub legend_width {
    my ($self, $legend_width) = @_;

    if (defined($legend_width)) {
	$self->{legend_width} = $legend_width;
    }

    return $self->{legend_width};
}

sub legend_height {
    my ($self, $legend_height) = @_;

    if (defined($legend_height)) {
	$self->{legend_height} = $legend_height;
    }

    return $self->{legend_height};
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

sub legend_image {
    my ($self) = @_;

    unless (defined($self->{legend_image})) {
	$self->{legend_image} = new WebGD($self->legend_width(), $self->legend_height());
	foreach my $triplet (@{$self->color_set}) {
	    push(@{$self->colors}, $self->legend_image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
	}
    }

    return $self->{legend_image};
}

sub data {
    my ($self, $data) = @_;

    if (defined($data)) {
	$self->{data} = $data;
    }

    return $self->{data};
}


sub x_axis {
    my ($self, $x_axis) = @_;

    if (defined($x_axis)) {
	$self->{x_axis} = $x_axis;
    }

    return $self->{x_axis};
}

sub x_axis_title {
    my ($self, $title) = @_;

    if (defined($title)) {
	$self->{x_axis_title} = $title;
    }

    return $self->{x_axis_title};
}

sub y_axis {
    my ($self, $y_axis) = @_;

    if (defined($y_axis)) {
	$self->{y_axis} = $y_axis;
    }

    return $self->{y_axis};
}

sub y_axis_title {
    my ($self, $title) = @_;

    if (defined($title)) {
	$self->{y_axis_title} = $title;
    }

    return $self->{y_axis_title};
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

sub type {
    my ($self, $type) = @_;

    if (defined($type)) {
	$self->{type} = $type;
    }

    return $self->{type};
}

sub title {
    my ($self, $title) = @_;

    if (defined($title)) {
	$self->{title} = $title;
    }

    return $self->{title};
}

sub legend {
    my ($self, $legend) = @_;

    if (defined($legend)) {
	$self->{legend} = $legend;
    }

    return $self->{legend};
}

sub length {
    my ($self, $length) = @_;

    if (defined($length)) {
	$self->{length} = $length;
    }

    return $self->{length};
}
