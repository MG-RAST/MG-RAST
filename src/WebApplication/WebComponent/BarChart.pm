package WebComponent::BarChart;

# BarChart - component to create bar charts

# $Id: BarChart.pm,v 1.12 2011-06-13 09:43:11 paczian Exp $

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

BarChart - component to create bar charts

=head1 DESCRIPTION

Creates an inline image for a bar chart with mouseover/onlick regions

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Hover', 'BarChartHover'.$self->id());

  $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{height} = 400;
  $self->{width} = 800;
  $self->{data} = undef;
  $self->{show_tooltip} = 1;
  $self->{show_titles} = 1;
  $self->{show_values} = 1;
  $self->{value_type} = 'absolute';
  $self->{value_colors} = [];
  $self->{show_axes} = 1;
  $self->{show_x_axis} = 1;
  $self->{show_y_axis} = 1;
  $self->{show_bar_frames} = 1;
  $self->{titles} = [];
  $self->{onclicks} = [];
  $self->{x_padding} = 30;
  $self->{y_padding} = 30;
  $self->{bar_padding} = 2;
  $self->{hover_content} = 'x';

  return $self;
}

=item * B<output> ()

Returns the html output of the BarChart component.

=cut

sub output {
  my ($self) = @_;

  my $data = $self->data();
  
  unless (defined($data) && scalar(@$data)) {
    return "BarChart called without data";
  }

  my $height = $self->height();
  my $width = $self->width();
  my $im = $self->image();
  my $colors = $self->colors();
  my $white = $colors->[0];
  my $black = $colors->[1];
  my @map_spots;
  my $hover = $self->application->component('BarChartHover'.$self->id());

  # precalculate values
  my $num_bars = scalar(@$data);
  my $bar_padding = $self->bar_padding;
  my $pane_width = $width - $self->x_padding;
  my $pane_height = $height - $self->y_padding;
  my $bar_width = int($pane_width / $num_bars);
  my $max_y = 0;
  foreach my $val (@{$self->data()}) {
    my $value = $val;
    if (ref($val) eq "ARRAY") {
      $value = 0;
      foreach my $val_part (@$val) {
	if (ref($val_part) eq "HASH") {
	  push(@{$self->titles()}, $val_part->{title});
	  if ($val_part->{color}) {
	    push(@{$self->value_colors()}, $val_part->{color});
	  } else {
	    push(@{$self->value_colors()}, 0);
	  }
	  $val_part = $val_part->{data};
	} else {
	  push(@{$self->titles()}, "");
	}
	$value += $val_part;
      }
    } else {
      if (ref($val) eq "HASH") {
	push(@{$self->titles()}, $val->{title});
	$value = $val->{data};
	if ($val->{color}) {
	  push(@{$self->value_colors()}, $val->{color});
	} else {
	  push(@{$self->value_colors()}, 0);
	}
      } else {
	push(@{$self->titles()}, "");
      }
    }
    if ($value > $max_y) {
      $max_y = $value;
    }
  }
  if ($max_y == 0) {
    $max_y = 1;
  }
  my $factor = $pane_height / $max_y;
  my $show_scale = 1;

  # check for scale
  if ($self->show_axes()) {
      
    # draw scales
    # y-lines
    my $h = 2;
    my $num_y_scales = int(($height - $self->y_padding) / 15) + 1;
    if ($self->show_y_axis) {
      $im->line($self->x_padding,0,$self->x_padding,$height - $self->y_padding,$black);
      for (my $i = 0; $i < $num_y_scales; $i++) {
	$im->line($self->x_padding - (5 * $h),$height - $self->y_padding - (15 * $i), $self->x_padding, $height - $self->y_padding - (15 * $i), $black);
	if ($h == 1) {
	  $h = 2;
	} else {
	  $h = 1;
	  $im->string(gdTinyFont, 2, $height - $self->y_padding - (15 * $i) - 3, int($max_y / $num_y_scales * $i), $black);
	}
      }
    }
      
    # x-lines
    $h = 2;
    my $curr_scale = 1;
    if ($self->show_x_axis) {
      $im->line($self->x_padding,$height - $self->y_padding,$width,$height - $self->y_padding,$black);
      for (my $i = 0; $i < $num_bars; $i++) {
	if ($show_scale == $curr_scale) {
	  $curr_scale = 1;
	  $im->line($self->x_padding + (($bar_width) * $i) + int($bar_width / 2), $height - $self->y_padding + (5 * $h), $self->x_padding + (($bar_width) * $i) + int($bar_width / 2), $height - $self->y_padding, $black);
	  if ($h == 1) {
	    $h = 2;
	  } else {
	    $h = 1;
	  }
	} else {
	  $curr_scale++;
	}
      }
    }
  }

  # draw titles
  if ($self->show_titles()) {
    my $h = 2;
    my $curr_scale = 1;
    for (my $i = 0; $i < $num_bars; $i++) {
	
      # check if column gets a title
      if ($show_scale == $curr_scale) {
	$curr_scale = 1;

	# format column title
	my $column = "";
	if (scalar(@{$self->titles}) > 10) {
	  $column = substr($self->titles->[$i], 0, 4);
	} else {
	  $column = substr($self->titles->[$i], 0, 10);
	}
	  
	# draw column title
	if ($h == 1) {
	  $h = 2;
	  $im->string(gdTinyFont, $self->x_padding + (($bar_width) * $i) + int($bar_width / 2) - 6, $height - $self->y_padding + 6, $column, $black);
	} else {
	  $h = 1;
	  $im->string(gdTinyFont, $self->x_padding + (($bar_width) * $i) + int($bar_width / 2) - 6, $height - $self->y_padding + 15, $column, $black);
	}
      } else {
	$curr_scale++;
      }
    }
  }

  # draw data
  my $j = 0;
  my $curr_offset = ($self->x_padding || 0) + 1;
  foreach my $val (@$data) {
    
    # draw bar
    
    # check bar type
    if (ref($val) eq "ARRAY") {
      my $vertical_offset = 0;
      my $i = 3;
      foreach my $part (@$val) {
	my $color = $colors->[$i];
	if ($self->value_colors->[$j]) {
	  $color = $im->colorResolve($self->value_colors->[$j]->[0],$self->value_colors->[$j]->[1],$self->value_colors->[$j]->[2]);
	}
	my $x1 = int($bar_padding + $curr_offset);
	my $y1 = int($height - $self->y_padding - ($part * $factor) - $vertical_offset);
	my $x2 = int($curr_offset + $bar_width);
	my $y2 = int($height - $self->y_padding - $vertical_offset);
	$im->filledRectangle( $x1, $y1, $x2 - 2, $y2, $color);
	$im->rectangle( $x1, $y1, $x2 - 2, $y2, $black);
	$i++;
	$vertical_offset += $part * $factor;
	if ($self->show_tooltip) {
	  if ($self->hover_content eq 'x') {
	    $hover->add_tooltip("bar_$j", $self->titles->[$j]);
	  } else {
	    $hover->add_tooltip("bar_$j", $part);
	  }
	}
	my $onclick = "";
	if (scalar(@{$self->onclicks})) {
	  if ($self->onclicks->[$j]) {
	    $onclick = "onclick='".$self->onclicks->[$j]."' style='cursor: pointer;'";
	  }
	}
	push(@map_spots, "<area shape='rect' coords='$x1,$y1,$x2,$y2' onmouseover='hover(event, \"bar_$j\", \"".$hover->id."\");'$onclick>");
	$j++;
      }
    } else {
      if (ref($val) eq 'HASH') {
	$val = $val->{data};
      }
      my $x1 = int($bar_padding + $curr_offset);
      my $y1 = int($height - $self->y_padding - ($val * $factor));
      my $x2 = int($curr_offset + $bar_width);
      my $y2 = int($height - $self->y_padding);
      my $color = $colors->[3];
      if ($self->value_colors->[$j]) {
	$color = $im->colorResolve($self->value_colors->[$j]->[0],$self->value_colors->[$j]->[1],$self->value_colors->[$j]->[2]);
      }
      $im->filledRectangle( $x1, $y1, $x2, $y2 - 1, $color);
      if ($self->show_bar_frames()) {
	$im->rectangle( $x1, $y1, $x2, $y2, $black);
      }
      if ($self->show_tooltip) {
	if ($self->hover_content eq 'x') {
	  $hover->add_tooltip("bar_$j", $self->titles->[$j]);
	} else {
	  $hover->add_tooltip("bar_$j", $val);
	}
      }
      my $onclick = "";
      if (scalar(@{$self->onclicks})) {
	if ($self->onclicks->[$j]) {
	  $onclick = "onclick='window.top.location=\"".$self->onclicks->[$j]."\";' style='cursor: pointer;'";
	}
      }
      push(@map_spots, "<area shape='rect' coords='$x1,$y1,$x2,$y2' onmouseover='hover(event, \"bar_$j\", \"".$hover->id."\");'$onclick>");
      $j++;
    }

    # check for drawing of values into / onto bars
    if ($self->show_values()) {
	
      # check for minimum bar width
      if ($bar_width > 9) {
	  
	# check for bar type
	if (ref($val) eq "ARRAY") {
	  my $vertical_offset = 0;
	  my $rest = 100;
	  my $numvals = scalar(@$val);
	  my $curr = 1;
	  foreach my $part (@$val) {
	    my $part_value = $part;
	    if (($self->value_type() eq 'percent') || ($self->value_type() eq 'both')) {
	      $part_value = int(100 / $max_y * $part);
	      if ($part_value == 0) {
		$part_value = 1;
	      }
	      $rest -= $part_value;
	      if ($curr == $numvals) {
		$part_value += $rest;
	      }
	      $part_value .= "%";
	    }

	    $im->string(gdMediumBoldFont, $curr_offset + 1 + $bar_padding + (($bar_width - $bar_padding) / 2) - 10, $height - $self->y_padding - (int($part * $factor / 2) + 5) - $vertical_offset, $part_value, $white);
	    if ($self->value_type() eq 'both') {
	      $im->string(gdMediumBoldFont, $curr_offset + 1 + $bar_padding + (($bar_width - $bar_padding) / 2) - 15, $height - $self->y_padding - (int($part * $factor / 2) + 5) - $vertical_offset + 10, $part, $white);
	    }
	    $vertical_offset += $part * $factor;	    
	    $curr++;
	  }
	} else {
	  my $value = $val;
	  if ($self->value_type() eq 'percent') {
	    $value = int(100 / $max_y * $val) . "%";
	  }
	  # check whether to write into or onto the bar
	  if (($val * $factor) > (10 + (length($val) * 6))) {	      
	    $im->stringUp(gdSmallFont, $curr_offset + 3 + $bar_padding + (($bar_width - $bar_padding) / 2) - 10, $height - $self->y_padding - (int($val * $factor) - 3 - (length($val) * 6)), $value, $black);
	  } else {
	    $im->stringUp(gdSmallFont, $curr_offset + 3 + $bar_padding + (($bar_width - $bar_padding) / 2) - 10, $height - $self->y_padding - (int($val * $factor) + 5), $value, $black);
	  }
	}
      }
    }

    $curr_offset += $bar_width;
  }

  # create image map
  my $map = "<map name='imap_barchart_".$self->id."'>\n".join("\n", @map_spots)."\n</map>";
  
  # create html
  my $chart = qq~<img src="~ . $self->image->image_src()  . qq~" usemap="#imap_barchart_~ . $self->id . qq~">~.$map.$hover->output();
    
  # return html
  return $chart;
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

sub onclicks {
  my ($self, $onclicks) = @_;

  if (defined($onclicks)) {
    $self->{onclicks} = $onclicks;
  }

  return $self->{onclicks};
}

sub value_colors {
  my ($self, $colors) = @_;

  if (defined($colors)) {
    $self->{value_colors} = $colors;
  }

  return $self->{value_colors};
}

sub x_padding {
  my ($self, $padding) = @_;

  if (defined($padding)) {
    $self->{x_padding} = $padding;
  }

  return $self->{x_padding};
}

sub y_padding {
  my ($self, $padding) = @_;

  if (defined($padding)) {
    $self->{y_padding} = $padding;
  }

  return $self->{y_padding};
}

sub bar_padding {
  my ($self, $padding) = @_;

  if (defined($padding)) {
    $self->{bar_padding} = $padding;
  }
  
  return $self->{bar_padding};
}

sub show_x_axis {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_x_axis} = $show;
  }

  return $self->{show_x_axis};
}

sub show_y_axis {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_y_axis} = $show;
  }

  return $self->{show_y_axis};
}

sub show_tooltip {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_tooltip} = $show;
  }

  return $self->{show_tooltip};
}

sub hover_content {
  my ($self, $hover) = @_;

  if (defined($hover)) {
    $self->{hover_content} = $hover;
  }

  return $self->{hover_content};
}
