package WebComponent::PieChart;

# PieChart - component to create pie charts

# $Id: PieChart.pm,v 1.19 2011-04-05 16:51:43 tharriso Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;

use GD;
use GD::Polyline;
use WebComponent::WebGD;
use Math::Trig;
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

  $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('excel')}, @{WebColors::get_palette('many')} ];
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{size} = 400;
  $self->{data} = undef;
  $self->{show_tooltip} = 1;
  $self->{show_legend} = 0;
  $self->{show_percent} = 0;
  $self->{legend_width} = 200;
  $self->application->register_component('Hover', 'PieChartHoverComponent'.$self->id());

  return $self;
}

=item * B<output> ()

Returns the html output of the PieChart component.

=cut

sub output {
  my ($self) = @_;

  unless (defined($self->data())) {
    return "no data passed to PieChart component";
  }

  my $data = $self->data();
  
  # get the hover component
  my $hover_component;
  eval { $hover_component = $self->application->component('PieChartHoverComponent'.$self->id()); };
  
  # initialize image
  $self->image();

  # determine total data value
  my $total = 0;
  foreach (@$data) {
    unless (ref($_) eq 'HASH') {
      $_ = { data => $_ };
    }
    $total += $_->{data};
  }

  if ($total == 0) {
    return "PieChart called with no values.";
  }

  # initialize image map array
  my @map_spots;

  # draw data
  my $currdeg = 270;
  my $half = int($self->size / 2) - 1;
  my $i = 0;
  foreach my $val (@$data) {

    # draw legend
    if ($self->show_legend) {
      $self->image->filledRectangle($self->size + 20, $i * 20 + 20, $self->size + 35, $i * 20  + 35, $self->colors->[$i + 6] || [51,51,51]);
      my $title = $self->show_percent ? sprintf("%.2f", ($val->{data}/$total) * 100).'%' : "(".$val->{data}.'/'.$total.")";
      if ($val->{title}) {
	$title = $val->{title} . ' ' . $title;
      }
      $self->image->string(gdSmallFont,$self->size + 40,$i * 20  + 21,$title,$self->colors->[1]);
    }
    
    # calculate degrees
    my $deg = (360 / $total) * $val->{data};
    if ($deg < 1) {
      $i++;
      next;
    }

    # add image map hotspot (start at middle)
    my $coords = $half.",".$half.",";

    # add the start point on the rim
    my $start_deg = $currdeg - 270;
    my $x = int($half + ($half * sin( RAD * $start_deg)));
    my $y = int($half - ($half * cos( RAD * $start_deg)));
    $coords .= $x.",".$y.",";

    # create intermediate points every 5 degrees
    my $h = int($deg / 5);
    for (my $i=0; $i<$h; $i++) {
      my $inter_deg = $start_deg + (($i + 1) * 5);
      $x = int($half + ($half * sin( RAD * $inter_deg)));
      $y = int($half - ($half * cos( RAD * $inter_deg)));
      $coords .= $x.",".$y.",";      
    }

    # add the end point on the rim
    my $end_deg = $start_deg + $deg;
    $x = int($half + ($half * sin( RAD * $end_deg)));
    $y = int($half - ($half * cos( RAD * $end_deg)));
    $coords .= $x.",".$y;

    my $slice_id = "pie_".$self->id()."_slice_$i";

    # check for tooltip
    my $tooltip = "";
    if ($self->show_tooltip()) {
      unless ($val->{tooltip}) {
	$val->{tooltip} = $val->{data}.' / '.$total;
      }

      $hover_component->add_tooltip($slice_id, "<table><tr><th>".$val->{title}."</th></tr><tr><td>".$val->{tooltip}."</td></tr></table>");
      $tooltip = "onmouseover='hover(event, \"$slice_id\", \"".$hover_component->id."\");'";
    }

    # check for event
    my $event = "";
    if ($val->{onclick}) {
      $event = "onclick='" . $val->{onclick} . "'";
    }

    push(@map_spots, "<area shape='poly' coords='" . $coords . "' id='$slice_id' $event $tooltip>");
    
    # check for rounding error
    if (($i + 1) == scalar(@$data)) {
      $deg = 630 - $currdeg;
    }
    
    # draw arc
    my $colorSet = $self->colors->[$i + 6] || [51,51,51];
    $self->image->filledArc($half, $half, $self->size(), $self->size(), $currdeg, $deg + $currdeg, $colorSet);

    # increase counter and starting degree value
    $i++;
    $currdeg += $deg;
  }

  # create inline gif
  my $map = "<map name='imap_piechart_".$self->id."'>".join("\n", @map_spots)."</map>";
  my $image = qq~<img style="border: none;" src="~ . $self->image->image_src()  . qq~" usemap="#imap_piechart_~ . $self->id . qq~">~.$map.($hover_component ? $hover_component->output() : "");

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
    my $width = $self->size();
    if ($self->show_legend) {
      $width += $self->legend_width;
    }
    $self->{image} = new WebGD($width, $self->size());
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

=item * B<show_tooltip> (I<show_tooltip>)

Getter / Setter for the boolean to show/not show a tooltip when hovering a pie slice.

=cut

sub show_tooltip {
  my ($self, $show_tooltip) = @_;

  if (defined($show_tooltip)) {
    $self->{show_tooltip} = $show_tooltip;
  }

  return $self->{show_tooltip};
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

sub show_legend {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_legend} = $show;
  }

  return $self->{show_legend};
}

sub show_percent {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_percent} = $show;
  }

  return $self->{show_percent};
}

sub legend_width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{legend_width} = $width;
  }

  return $self->{legend_width};
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/PopupTooltip.js"];
}
