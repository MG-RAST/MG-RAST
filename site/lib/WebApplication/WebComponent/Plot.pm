package WebComponent::Plot;

# Plot - component to do a x/y plot

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

PieChart - component to create pie charts

=head1 DESCRIPTION

Creates an inline image for a pie chart with mouseover/onlick regions

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{height} = 700;
  $self->{width} = 900;
  $self->{data} = undef;
  $self->{max_x} = 0;
  $self->{max_y} = 0;
  $self->{name_x} = "";
  $self->{name_y} = "";

  return $self;
}

=item * B<output> ()

Returns the html output of the BarChart component.

=cut

sub output {
  my ($self) = @_;

  my $data = $self->data();
  
  unless (defined($data) && scalar(@$data)) {
    return "Plot called without data";
  }

  my $x_padding = 100;
  my $y_padding = 50;
  my $height = $self->height();
  my $width = $self->width();
  my $im = $self->image();
  my $colors = $self->colors();
  my $white = $colors->[0];
  my $black = $colors->[1];

  # precalculate values
  my $num_bars = scalar(@$data);
  my $bar_padding = 2;
  my $pane_width = $width - $x_padding;
  my $pane_height = $height - $y_padding;
  my $bar_width = int($pane_width / $num_bars);
  my $max_y = $self->max_y;
  my $max_x = $self->max_x;
  my $y_factor = $pane_height / $max_y;
  my $x_factor = $pane_width / $max_x;

  # draw grid
  $im->line($x_padding,0,$x_padding,$height - $y_padding,$black);
  $im->line($x_padding,$height - $y_padding,$width,$height - $y_padding,$black);
  
  # draw scales
  # y-lines
  my $h = 2;
  my $num_y_scales = int(($height - $y_padding) / 15) + 1;
  for (my $i = 0; $i < $num_y_scales; $i++) {
    $im->line($x_padding - (5 * $h),$height - $y_padding - (15 * $i), $x_padding, $height - $y_padding - (15 * $i), $black);
    if ($h == 1) {
      $h = 2;
    } else {
      $h = 1;
      $im->string(gdSmallFont, 30, $height - $y_padding - (15 * $i) - 7, int($max_y / $num_y_scales * $i), $black);
    }
  }
  $im->stringUp(gdMediumBoldFont, 5, ($height - $y_padding) / 2 + (5 * (length($self->name_x) / 2)), $self->name_x, $black);
  
  # x-lines
  $h = 2;
  my $num_x_scales = int(($width - $x_padding) / 50) + 1;
  for (my $i = 0; $i < $num_x_scales; $i++) {
    $im->line($x_padding + (50 * $i), $height - $y_padding + (5 * $h), $x_padding + (50 * $i), $height - $y_padding, $black);

    if ($h == 1) {
      $h = 2;
    } else {
      $h = 1;
      $im->string(gdSmallFont, $x_padding + (50 * $i), $height - $y_padding + 10, int($max_x / $num_x_scales * $i), $black);
    }
  }
  $im->string(gdMediumBoldFont, $x_padding + (($width - $x_padding) / 2) - ((length($self->name_y) / 2) * 5), $height - $y_padding + 30, $self->name_y, $black);
  
  # draw data
  my $color = $colors->[3];
  foreach my $val (@$data) {
    $im->setPixel(($val->[0] * $x_factor) + $x_padding, $height - ($val->[1] * $y_factor) - $y_padding, $color)
  }

  # create html
  my $chart = qq~<img src="~ . $self->image->image_src()  . qq~" id="dotplot">~;
    
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

sub max_y {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max_y} = $max;
  }

  return $self->{max_y};
}

sub max_x {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max_x} = $max;
  }

  return $self->{max_x};
}

sub name_x {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name_x} = $name;
  }

  return $self->{name_x};
}

sub name_y {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name_y} = $name;
  }
  
  return $self->{name_y};
}
