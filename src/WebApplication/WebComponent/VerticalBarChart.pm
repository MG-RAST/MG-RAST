package WebComponent::VerticalBarChart;

# BarChart - component to create bar charts

# $Id: VerticalBarChart.pm,v 1.19 2011-12-01 21:53:17 tharriso Exp $

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

  $self->application->register_component('Hover', 'VerticalBarChartHover'.$self->id());

  $self->{bar_color_set} = $self->bar_color_set_default;
  $self->{color_set} = WebColors::get_palette('special');
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{height} = 0;
  $self->{width} = 500;
  $self->{data} = undef;
  $self->{datasets} = [];
  $self->{supersets} = [];
  $self->{supersets2} = [];
  $self->{subsets} = [];
  $self->{data_groups} = {}; # hash: dataset pos (for y pos) => group title
  $self->{dividers} = {};    # hash: dataset pos (for y pos above dataset)
  $self->{show_percent} = 0;
  $self->{title_onclicks} = undef;
  $self->{title_hovers} = undef;
  $self->{data_onclicks} = undef;
  $self->{rotate_colors} = undef;
  $self->{error_bars} = [];
  $self->{scale_step} = undef;
  $self->{show_counts} = undef;
  $self->{hide_scale} = 0;

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

  # transmogrify data
  foreach my $set (@$data) {
    if (ref($set)) {
      foreach my $subset (@$set) {
	if (! ref($subset)) {
	  $subset = [ $subset ];
	}
      }
    } else {
      $set = [ [ $set ] ];
    }
  }

  # calculate percent data
  my $totals = [];
  my $absolute_data = [];
  for (my $i=0; $i<scalar(@$data); $i++) {
    $absolute_data->[$i] = [];
    for (my $h=0; $h<scalar(@{$data->[$i]}); $h++) {
      $absolute_data->[$i]->[$h] = [];
      for (my $j=0; $j<scalar(@{$data->[$i]->[$h]}); $j++) {
	$absolute_data->[$i]->[$h]->[$j] = $data->[$i]->[$h]->[$j] || 0;
	$totals->[$h] += ($data->[$i]->[$h]->[$j]||0);
      }
    }
  }

  if ($self->show_percent) {
    for (my $i=0; $i<scalar(@$data); $i++) {
      for (my $h=0; $h<scalar(@{$data->[$i]}); $h++) {
	for (my $j=0; $j<scalar(@{$data->[$i]->[$h]}); $j++) {
	  $data->[$i]->[$h]->[$j] = sprintf("%.2f", ($data->[$i]->[$h]->[$j]||0) / ($totals->[$h]||1) * 100);
	}
      }
    }
  }

  # precalculate values
  my $numsets = scalar(@$data);
  my $max = 0;
  my $height = 0;
  my $bar_height = 6;
  my $bar_padding = 1;
  my $set_padding = 8;
  my $padding_y = 25;
  foreach my $set (@$data) {
    foreach my $subset (@$set) {
      my $val = 0;
      map { $val += ($_||0); } @$subset;
      if ($val > $max) {
	$max = $val;
      }
      $height += $bar_height + $bar_padding;
    }
    $height -= $bar_padding;
    $height += $set_padding;
  }
  if ($max == 0) {
    $max = 1;
  }
  $height -= $set_padding;
  $height += $padding_y;
  $self->height($height);

  my $max_group_length = 0;
  my $max_text_length  = 0;
  my $max_num_length   = 0;
  my $font_char_width  = 6;
  my $font_char_height = 12;
  foreach my $dataset (@{$self->datasets}) {
    if (length($dataset) > $max_text_length) {
      $max_text_length = length($dataset);
    }
  }
  foreach my $title (values %{$self->data_groups}) {
    if (length($title) > $max_group_length) {
      $max_group_length = length($title);
    }
  }
  foreach my $total (@$totals) {
    if (length($total) > $max_num_length) {
      $max_num_length = length($total);
    }
  }

  $max_text_length = $max_group_length ? $max_text_length + $max_group_length + 5 : $max_text_length;
  my $padding_x  = 5 + ($font_char_width * $max_text_length);
  my $padding_x2 = $self->show_counts ? 8 + ($font_char_width * $max_num_length) : 0;

  my $width = $self->width();
  my $im = $self->image();
  my $colors = $self->colors();
  my $white = $colors->[0];
  my $black = $colors->[1];
  my $gray = $colors->[2];
  my $bar_colors = $self->bar_colors();

  my @map_spots;
  my $hover = $self->application->component('VerticalBarChartHover'.$self->id());

  my $scale_x = $max / ($width - $padding_x - $padding_x2); 

  # draw lines
  my $scale_width = 50;
  if ($self->scale_step) {
    $scale_width = int(($width - $padding_x - $padding_x2) / ($max / $self->scale_step));
  }
  $im->line($padding_x,0,$padding_x,$height - $padding_y,$black);
  my $num_value_bars = int(($width-$padding_x-$padding_x2) / $scale_width);
  for (my $i=0; $i<=$num_value_bars; $i++) {
    if ($i>0) {
      $im->line($padding_x+($i * $scale_width),0,$padding_x+($i * $scale_width),$height - $padding_y,$gray);
    }
    my $num = int($i * $scale_width * $scale_x);
    if ($max == 1) {
      $num = sprintf("%.2f", $i * $scale_width * $scale_x);
    }
    if ($self->scale_step) {
      $num = $i * $self->scale_step;
    }
    if ($self->show_percent) {
      $num .= "%";
    }
    unless ($self->hide_scale) {
      $im->string(gdSmallFont, $padding_x+($i * $scale_width) - (int(length($num) / 2 * $font_char_width)), $height - $padding_y + 2, $num, $black);
    }
  }

  # draw bars
  my $old_y_pos  = 0;
  my $curr_y_pos = 0;
  for (my $i=0; $i<$numsets; $i++) {

    # calculate title position
    my $text_y_pos = $curr_y_pos + int((((scalar(@{$data->[$i]}) * ($bar_height + $bar_padding)) - $bar_padding) / 2) - ($font_char_height / 2));
    $old_y_pos = $text_y_pos;

    # draw group title
    if (exists $self->data_groups->{$i}) {
      $im->string(gdSmallFont, 8, $text_y_pos, $self->data_groups->{$i}, $black);
    }

    # draw divider
    if (($old_y_pos > 0) && (exists $self->dividers->{$i})) {
      $im->dashedLine(15, $old_y_pos + int(($text_y_pos-$old_y_pos) / 2), $padding_x, $old_y_pos + int(($text_y_pos-$old_y_pos) / 2), $black);
    }

    # draw title
    $im->string(gdSmallFont, ($max_text_length - length($self->datasets->[$i])) * $font_char_width, $text_y_pos, $self->datasets->[$i], $black);

    # add click-event to title
    if (defined($self->title_onclicks) && defined($self->title_onclicks->[$i])) {
      push(@map_spots, "<area style='cursor: pointer;' shape='rect' coords='".int(($max_text_length - length($self->datasets->[$i])) * $font_char_width).",".$text_y_pos.",".int($max_text_length * $font_char_width).",".($text_y_pos+$font_char_height)."' onclick='".$self->title_onclicks->[$i]."'>");
    }

    # add hover text to title
    if (defined($self->title_hovers) && defined($self->title_hovers->[$i])) {
      push(@map_spots, "<area style='cursor: help;' shape='rect' coords='".int(($max_text_length - length($self->datasets->[$i])) * $font_char_width).",".$text_y_pos.",".int($max_text_length * $font_char_width).",".($text_y_pos+$font_char_height)."' title='".$self->title_hovers->[$i]."'>");
    }

    # draw bars for this set
    for (my $h=0; $h<scalar(@{$data->[$i]}); $h++) {
      my $x1 = $padding_x + 1;
      my $y1 = $curr_y_pos;
      my $y2 = $y1 + $bar_height;
      my $bar_total = 0;

      # draw subbars for this bar
      for (my $j=0; $j<scalar(@{$data->[$i]->[$h]}); $j++) {
	$bar_total += ($self->{show_percent} ? $absolute_data->[$i]->[$h]->[$j] : $data->[$i]->[$h]->[$j]);
	my $x2 = $x1 + (($data->[$i]->[$h]->[$j] || 0) / $scale_x);
	my $bc = $self->rotate_colors ? $self->bar_colors->[$j % 6]->[$h] : $self->bar_colors->[$h % 6]->[$j];
	$im->filledRectangle($x1, $y1, $x2, $y2, $bc);
	if ($data->[$i]->[$h]->[$j] > 0) {
	  if ((@{$self->supersets2} > 0) && ($h == 1)) {
	    $hover->add_tooltip("bar_$i\_$h\_$j", "<b>".$self->datasets->[$i]." - ". $self->subsets->[$h].($self->supersets2->[$j] ? " - ".$self->supersets2->[$j] : "") . ":</b> ".($data->[$i]->[$h]->[$j] || 0).($self->{show_percent} ? "% (".$absolute_data->[$i]->[$h]->[$j].")" : ""));
	  } else {
	    $hover->add_tooltip("bar_$i\_$h\_$j", "<b>".$self->datasets->[$i]." - ". $self->subsets->[$h].($self->supersets->[$j] ? " - ".$self->supersets->[$j] : "") . ":</b> ".($data->[$i]->[$h]->[$j] || 0).($self->{show_percent} ? "% (".$absolute_data->[$i]->[$h]->[$j].")" : ""));
	  }
	  my $onclick = "";
	  if ($self->data_onclicks && $self->data_onclicks->[$i]->[$h]->[$j]) {
	    $onclick = " onclick='".$self->data_onclicks->[$i]->[$h]->[$j]."' style='cursor: pointer;'";
	  }
	  push(@map_spots, "<area shape='rect' coords='$x1,$y1,$x2,$y2'$onclick onmouseover='hover(event, \"bar_$i\_$h\_$j\", \"".$hover->id."\");'>");
	}
	$x1 = $x2;
      }
      if ($self->show_counts) {
	$im->string(gdSmallFont, $x1 + 5 + int(length($bar_total) / $font_char_width), $y1 - (0.5 * $bar_height), $bar_total, $black);
      }
      $curr_y_pos += $bar_height + $bar_padding;
    }
    $curr_y_pos += $set_padding - $bar_padding;
    $old_y_pos = $text_y_pos;
  }

  # create image map
  my $map = "<map name='imap_vbarchart_".$self->id."'>\n".join("\n", @map_spots)."\n</map>";
  
  # create html
  my $chart = qq~<img src="~ . $self->image->image_src()  . qq~" usemap="#imap_vbarchart_~ . $self->id . qq~">~.$map.$hover->output();
    
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
    my $bcols = [];
    foreach my $col (@{$self->bar_color_set}) {
      my $scols = [];
      foreach my $shade (@$col) {
	push(@$scols, $self->image->colorResolve($shade->[0], $shade->[1], $shade->[2]));
      }
      push(@$bcols, $scols);
    }
    $self->bar_colors($bcols);
  }

  return $self->{image};
}

sub bar_color_set_default {
  my ($self) = @_;
  
  return [
	  [ [ 0, 0, 255 ], [ 153, 153, 255 ], [ 25, 25, 255 ], [ 128, 128, 255 ], [ 51, 51, 255 ], [ 102, 102, 255 ], [ 0, 0, 255 ], [ 153, 153, 255 ], [ 25, 25, 255 ], [ 128, 128, 255 ], [ 51, 51, 255 ], [ 102, 102, 255 ] ], # blue
	  [ [ 0, 255, 0 ], [ 153, 255, 153 ], [ 25, 255, 25 ], [ 128, 255, 128 ], [ 51, 255, 51 ], [ 102, 255, 102 ],[ 0, 255, 0 ], [ 153, 255, 153 ], [ 25, 255, 25 ], [ 128, 255, 128 ], [ 51, 255, 51 ], [ 102, 255, 102 ] ], # green
	  [ [ 255, 0, 0 ], [ 255, 153, 153 ], [ 255, 25, 25 ], [ 255, 128, 128 ], [ 255, 51, 51 ], [ 255, 102, 102 ], [ 255, 0, 0 ], [ 255, 153, 153 ], [ 255, 25, 25 ], [ 255, 128, 128 ], [ 255, 51, 51 ], [ 255, 102, 102 ] ], # red
	  [ [ 188, 0, 255 ], [ 255, 154, 229 ], [ 195, 26, 255 ], [ 255, 128, 222 ], [ 202, 51, 255 ], [ 255, 102, 215 ], [ 188, 0, 255 ], [ 255, 154, 229 ], [ 195, 26, 255 ], [ 255, 128, 222 ], [ 202, 51, 255 ], [ 255, 102, 215 ] ], # purple
	  [ [ 0, 255, 188 ], [ 154, 229, 255 ], [ 26, 255, 195 ], [ 128, 222, 255 ], [ 51, 255, 202 ], [ 102, 215, 255 ], [ 0, 255, 188 ], [ 154, 229, 255 ], [ 26, 255, 195 ], [ 128, 222, 255 ], [ 51, 255, 202 ], [ 102, 215, 255 ] ], # cyan
	  [ [ 255, 188, 0 ], [ 229, 255, 154 ], [ 255, 195, 26 ], [ 222, 255, 128 ], [ 255, 202, 51 ], [ 215, 255, 102 ], [ 255, 188, 0 ], [ 229, 255, 154 ], [ 255, 195, 26 ], [ 222, 255, 128 ], [ 255, 202, 51 ], [ 215, 255, 102 ] ], # orange
	  [ [ 0, 0, 255 ], [ 153, 153, 255 ], [ 25, 25, 255 ], [ 128, 128, 255 ], [ 51, 51, 255 ], [ 102, 102, 255 ], [ 0, 0, 255 ], [ 153, 153, 255 ], [ 25, 25, 255 ], [ 128, 128, 255 ], [ 51, 51, 255 ], [ 102, 102, 255 ] ], # blue
	  [ [ 0, 255, 0 ], [ 153, 255, 153 ], [ 25, 255, 25 ], [ 128, 255, 128 ], [ 51, 255, 51 ], [ 102, 255, 102 ], [ 0, 255, 0 ], [ 153, 255, 153 ], [ 25, 255, 25 ], [ 128, 255, 128 ], [ 51, 255, 51 ], [ 102, 255, 102 ] ], # green
	  [ [ 255, 0, 0 ], [ 255, 153, 153 ], [ 255, 25, 25 ], [ 255, 128, 128 ], [ 255, 51, 51 ], [ 255, 102, 102 ], [ 255, 0, 0 ], [ 255, 153, 153 ], [ 255, 25, 25 ], [ 255, 128, 128 ], [ 255, 51, 51 ], [ 255, 102, 102 ] ], # red
	  [ [ 188, 0, 255 ], [ 255, 154, 229 ], [ 195, 26, 255 ], [ 255, 128, 222 ], [ 202, 51, 255 ], [ 255, 102, 215 ], [ 188, 0, 255 ], [ 255, 154, 229 ], [ 195, 26, 255 ], [ 255, 128, 222 ], [ 202, 51, 255 ], [ 255, 102, 215 ] ], # purple
	  [ [ 0, 255, 188 ], [ 154, 229, 255 ], [ 26, 255, 195 ], [ 128, 222, 255 ], [ 51, 255, 202 ], [ 102, 215, 255 ], [ 0, 255, 188 ], [ 154, 229, 255 ], [ 26, 255, 195 ], [ 128, 222, 255 ], [ 51, 255, 202 ], [ 102, 215, 255 ] ], # cyan
	  [ [ 255, 188, 0 ], [ 229, 255, 154 ], [ 255, 195, 26 ], [ 222, 255, 128 ], [ 255, 202, 51 ], [ 215, 255, 102 ], [ 255, 188, 0 ], [ 229, 255, 154 ], [ 255, 195, 26 ], [ 222, 255, 128 ], [ 255, 202, 51 ], [ 215, 255, 102 ] ], # orange
	 ];
}

sub bar_color_set {
  my ($self, $colors) = @_;

  if (defined($colors)) {
    $self->{bar_color_set} = $colors;
  }
  
  return $self->{bar_color_set};
}

sub bar_colors {
  my ($self, $colors) = @_;
  
  if (defined($colors)) {
    $self->{bar_colors} = $colors;
  }

  return $self->{bar_colors};
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
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

sub datasets {
  my ($self, $sets) = @_;

  if (defined($sets)) {
    $self->{datasets} = $sets;
  }

  return $self->{datasets};
}

sub subsets {
  my ($self, $sets) = @_;

  if (defined($sets)) {
    $self->{subsets} = $sets;
  }

  return $self->{subsets};
}

sub supersets {
  my ($self, $sets) = @_;

  if (defined($sets)) {
    $self->{supersets} = $sets;
  }

  return $self->{supersets};
}

sub supersets2 {
  my ($self, $sets) = @_;

  if (defined($sets)) {
    $self->{supersets2} = $sets;
  }

  return $self->{supersets2};
}

sub data_groups {
  my ($self, $groups) = @_;

  if (defined($groups)) {
    $self->{data_groups} = $groups;
  }

  return $self->{data_groups};
}

sub dividers {
  my ($self, $divs) = @_;

  if (defined($divs)) {
    $self->{dividers} = $divs
  }
  
  return $self->{dividers};
}

sub title_onclicks {
  my ($self, $onclicks) = @_;

  if (defined($onclicks)) {
    $self->{title_onclicks} = $onclicks;
  }

  return $self->{title_onclicks};
}

sub data_onclicks {
  my ($self, $onclicks) = @_;

  if (defined($onclicks)) {
    $self->{data_onclicks} = $onclicks;
  }

  return $self->{data_onclicks};
}

sub title_hovers {
  my ($self, $hovers) = @_;

  if (defined($hovers)) {
    $self->{title_hovers} = $hovers;
  }

  return $self->{title_hovers};
}

sub legend {
  my ($self) = @_;

  my $subsets = $self->{subsets}; #mgs
  my $supersets = $self->{supersets}; #source
  my $supersets2 = $self->{supersets2};

  my $font_char_width = 6;
  my $font_char_height = 12;
  my $x_buffer = 3;
  my $y_buffer = 3;

  my $maxlen_subsets = 0;
  foreach my $subset (@$subsets) {
    if (length($subset) > $maxlen_subsets) {
      $maxlen_subsets = length($subset);
    }
  }
  my $maxlen_supersets = 0;
  my $total_length_supersets = 0;
  foreach my $superset ((@$supersets, @$supersets2)) {
    if (length($superset) > $maxlen_supersets) {
      $maxlen_supersets = length($superset);
    }
  }

  my $x_offset = ($maxlen_subsets * $font_char_width) + $x_buffer;
  my $width = ($maxlen_supersets * $font_char_width * scalar(@$supersets)) + (scalar(@$supersets) * $x_buffer) + $x_offset;
  my $height = (scalar(@$subsets) + 1) * ($font_char_height + $y_buffer);
  if (@$supersets2 > 0) { $height += $font_char_height + $y_buffer; }

  my $legend_image = new WebGD($width, $height);
  my $white = $legend_image->colorResolve(255,255,255);
  my $black = $legend_image->colorResolve(0,0,0);
  my $bcols = [];
  foreach my $col (@{$self->bar_color_set}) {
    my $scols = [];
    foreach my $shade (@$col) {
      push(@$scols, $legend_image->colorResolve($shade->[0], $shade->[1], $shade->[2]));
    }
    push(@$bcols, $scols);
  }

  for (my $i=0; $i<scalar(@$subsets); $i++) {
    $legend_image->string(gdSmallFont, 0, ($i+1) * ($font_char_height + $y_buffer), $subsets->[$i], $black);
  }
  for (my $i=0; $i<scalar(@$supersets); $i++) {
    $legend_image->string(gdSmallFont, $x_offset + ($i * $font_char_width * $maxlen_supersets) + ($x_buffer * $i), 0, $supersets->[$i], $black);
  }
  for (my $i=0; $i<scalar(@$supersets); $i++) {
    for (my $h=0; $h<scalar(@$subsets); $h++) {
      my $y1 = ($h+1) * ($font_char_height + $y_buffer);
      my $x1 = $x_offset + ($i * $font_char_width * $maxlen_supersets) + ($x_buffer * $i);
      my $x2 = $x1 + ($font_char_width * $maxlen_supersets);
      my $y2 = $y1 + $font_char_height;
      my $bc = $self->rotate_colors ? $bcols->[$i % 6]->[$h] : $bcols->[$h % 6]->[$i];
      $legend_image->filledRectangle($x1, $y1, $x2, $y2, $bc);
    }
  }
  if (@$supersets2 > 0) {
    for (my $i=0; $i<scalar(@$supersets2); $i++) {
      $legend_image->string(gdSmallFont, $x_offset + ($i * $font_char_width * $maxlen_supersets) + ($x_buffer * $i), $height - $font_char_height - $y_buffer, $supersets2->[$i], $black);
    }
  }

  return "<img src='" . $legend_image->image_src()  . "'>";
}

sub show_percent {
  my ($self, $sp) = @_;

  if (defined($sp)) {
    $self->{show_percent} = $sp;
  }

  return $self->{show_percent};
}

sub rotate_colors {
  my ($self, $rc) = @_;

  if (defined($rc)) {
    $self->{rotate_colors} = $rc;
  }
  return $self->{rotate_colors};
}

sub error_bars {
  my ($self, $bars) = @_;

  if (defined($bars)) {
    $self->{error_bars} = $bars;
  }

  return $self->{error_bars};
}

sub scale_step {
  my ($self, $step) = @_;

  if (defined($step)) {
    $self->{scale_step} = $step;
  }

  return $self->{scale_step};
}

sub show_counts {
  my ($self, $counts) = @_;

  if (defined($counts)) {
    $self->{show_counts} = $counts;
  }

  return $self->{show_counts};
}

sub hide_scale {
  my ($self, $scale) = @_;

  if (defined($scale)) {
    $self->{hide_scale} = $scale;
  }

  return $self->{hide_scale};
}
