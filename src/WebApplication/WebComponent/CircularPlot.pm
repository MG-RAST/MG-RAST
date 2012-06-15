package WebComponent::CircularPlot;

# PieChart - component to create pie charts

# $Id: CircularPlot.pm,v 1.5 2008-09-05 14:41:12 paczian Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;

use GD;
use GD::Polyline;
use WebComponent::WebGD;
use Math::Trig;
use WebColors;

use gjocolorlib;

use constant PI => 4 * atan2 1, 1;
use constant RAD => 2 * PI / 360;

=pod

=head1 NAME

CircularPlot - component to create circular genome plots

=head1 DESCRIPTION

Creates a circular genome plote

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Hover', 'HoverTooltips');
  
  $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{size} = 700;
  $self->{data} = [];
  $self->{total} = 1;

  return $self;
}

=item * B<output> ()

Returns the html output of the CircularPlot component.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();

  my $data = $self->data();
  
  # initialize image
  $self->image();

  # draw data
  my $half = int($self->size / 2) - 1;
  my $total = $self->total();
  my $factor = 360 / $total;
  my $rim = 0;
  my $arc_width = 25;
  my $arc_padding = 5;
  my $image = "";
  my $map = [];
  foreach my $rim_data (@$data) {
    foreach my $val (@$rim_data) {
      
      # calculate degrees
      my $angle = 180 - ($factor * $val->[0]);
      
      # determine color
      my $color;
      my $mod = 1 / 255;
      if ($val->[2] =~ /#/) {
	my ($r, $g, $b) = html2rgb($val->[2]);
	$r = $r / $mod;
	$g = $g / $mod;
	$b = $b / $mod;
	$color = $self->image->colorResolve($r, $g, $b);
      } else {
	$color = $self->colors->[3 + $val->[2]];
      }
      
      my $inner = $self->size() - ($rim * ($arc_width + $arc_padding)) - $arc_width - $half - 15;
      my $outer = $self->size() - ($rim * ($arc_width + $arc_padding)) - $half - 15;
      my $x1 = $half + ($inner * sin( RAD * $angle));
      my $y1 = $half + ($inner * cos( RAD * $angle));
      my $x2 = $half + ($outer * sin( RAD * $angle));
      my $y2 = $half + ($outer * cos( RAD * $angle));
      $self->image->line($x1, $y1, $x2, $y2, $color);
    }
    
    $rim++;
  }

  for (my $deg = 1; $deg<361; $deg++) {
    my $coords = "$half,$half,";
    my $x = int($half + ($half * sin( RAD * (180 - $deg))));
    my $y = int($half + ($half * cos( RAD * (180 - $deg))));
    $coords .= $x.",".$y.",";
    $x = int($half + ($half * sin( RAD * (180 - $deg + 1))));
    $y = int($half + ($half * cos( RAD * (180 - $deg + 1))));
    $coords .= $x.",".$y;
    my $pos = int($deg / $factor);
    push(@$map, "<area shape='poly' coords='".$coords."' id='".$self->id."_slice_".$deg."' title='$pos' onclick='navigate_plot(\"".$self->id."\", \"$pos\", \"$deg\");'>");
  }

  $image .= "<map name=\"circplot_map_" . $self->id . "\">".join("\n", @$map)."</map>".qq~<img id="plot_img_~ . $self->id . qq~" style="border: none;" usemap="#circplot_map_~ . $self->id . qq~" src="~ . $self->image->image_src() ."\"><img src=\"$Conf::cgi_url/Html/dot.gif\" id='plot_dot_".$self->id."' onload='navigate_plot(\"".$self->id."\", \"1\", \"1\");' style='position: relative;'>";

  return $image;
}


=item * B<colors> ()

Getter for the colors attribute.

=cut

sub colors {
  my ($self) = @_;

  return $self->{colors};
}

=item * B<color_set> (I<color_set>)

Getter / Setter for the set of colors used.

=cut

sub color_set {
  my ($self, $color_set) = @_;

  if (defined($color_set)) {
    $self->{color_set} = $color_set;
  }

  return $self->{color_set};
}

=item * B<image> (I<image>)

Getter / Setter for the image.

=cut

sub image {
  my ($self) = @_;

  unless (defined($self->{image})) {
    $self->{image} = new WebGD($self->size(), $self->size());
    foreach my $triplet (@{$self->color_set}) {
      push(@{$self->colors}, $self->image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
    }
  }

  return $self->{image};
}

=item * B<size> (I<size>)

Getter / Setter for the size of the piechart in pixels.

=cut

sub size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{size} = $size;
  }

  return $self->{size};
}

=item * B<data> (I<data>)

Getter / Setter for the data of the PieChart.

=cut

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub total {
  my ($self, $total) = @_;

  if (defined($total)) {
    $self->{total} = $total;
  }

  return $self->{total};
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/CircularPlot.js"];
}
