package WebComponent::Heatmap;

use strict;
use warnings;

use base qw( WebComponent );

1;

use WebComponent::WebGD;
use GD;
use Math::Trig;

use WebColors;

=pod

=head1 NAME

Heatmap - component to draw heatmaps

=head1 DESCRIPTION

Creates an inline image for display of heatmaps

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Hover', 'HeatmapHoverComponent'.$self->id());
  
  $self->{width} = 800;
  $self->{height} = 800;
  $self->{cell_size} = 25;
  $self->{legend_size} = 100;
  $self->{colors} = [];
  $self->{data} = [];

  return $self;
}

=item * B<output> ()

Returns the html output of the GenomeDrawer component.

=cut

sub output {
  my ($self) = @_;

  # check for minimum input requirements
  unless ($self->data) {
    return "heatmap called without data";
  }

  # calculate width and height
  $self->width($self->legend_size + (scalar(@{$self->data}) * $self->cell_size) + 1);
  $self->height($self->legend_size + (scalar(@{$self->data->[0]}) * $self->cell_size));

  # initialize image
  $self->image();
  
  # get the hover component
  my $hover_component = $self->application->component('HeatmapHoverComponent'.$self->id());

  # start the image map
  my $unique_map_id = int(rand(100000));
  my $map = "<map name='imap_".$self->id."_".$unique_map_id."'>";
  my @maparray;

  # set offsets
  my $x_offset = $self->legend_size;
  my $y_offset = 1;
  $self->image->rectangle(0,0,$self->width - 1, $self->height - 1, $self->colors->[1]);

  # iterate over the data
  my $y = 0;
  foreach my $col (@{$self->data}) {
    my $x = 0;

    # draw condition legend
    if ($self->legend) {    
	$self->image->stringUp(gdSmallFont,$x_offset + ($y * $self->cell_size) + 5,$self->height - 5,$self->legend->{conditions}->[$y], $self->colors->[1]);
      }
    foreach my $cell (@$col) {
      # draw feature legend
      if ($y == 0 && $self->legend) {    
	$self->image->string(gdSmallFont,5,6 + $y_offset + ($x * $self->cell_size),$self->legend->{features}->[$x], $self->colors->[1]);
     }
      
      # calculate color
      my $color = $self->colors->[1];
      if ($cell < 0) {
	$color = $self->colors->[11 + abs($cell)];
      } elsif ($cell > 0) {
	$color = $self->colors->[1 + $cell];
      }
      
      # calculate x-y positions
      my $x1 = $x_offset + ($self->cell_size * $y);
      my $y1 = $y_offset + ($self->cell_size * $x);
      my $x2 = $x_offset + ($self->cell_size * ($y + 1));
      my $y2 = $y_offset + ($self->cell_size * ($x + 1));

      # create image map entry
      if ($self->legend) {
	my $cell_id = "cell_info_".$x."_".$y;
	$hover_component->add_tooltip($cell_id, "<table><tr><th>Feature</th><td>".$self->legend->{features}->[$x]."</td></tr><tr><th>Condition</th><td>".$self->legend->{conditions}->[$y]."</td></tr><tr><th>Value</th><td>".$cell."</td></tr></table>");
	push(@maparray, '<area shape="rect" coords="'.join(",", $x1, $y1, $x2, $y2).'" onmouseover="hover(event, \''.$cell_id.'\', \''.$hover_component->id().'\');" id="'.$cell_id.'">');
      }

      # draw spot on image
      $self->image->filledRectangle($x1,$y1,$x2,$y2,$color);
      $x++;
    }
    $y++;
  }

  # finish image map
  $map .= join("\n", @maparray);
  $map .= "</map>";
    
  # create html
  my $image = '<img usemap="#imap_' . $self->id . '_'.$unique_map_id.'" style="border: none;" src="' . $self->image->image_src()  . '">'.$map.$hover_component->output();

 return $image;
}


=item * B<image> (I<image>)

Getter / Setter for the image.

=cut

sub image {
  my ($self) = @_;

  unless (defined($self->{image})) {
    $self->{image} = new WebGD($self->width() , $self->height());
    foreach my $triplet (@{$self->color_set}) {
      push(@{$self->colors}, $self->image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
    }
  }

  return $self->{image};
}

=item * B<width> (I<width>)

Getter / Setter for the width of the image.

=cut

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

=item * B<height> ()

Getter / Setter for the height of the image.

=cut

sub height {
  my ($self, $height) = @_;

  if (defined($height)) {
    $self->{height} = $height;
  }

  return $self->{height};
}

sub color_set {
  my ($self) = @_;

  my $colors = [ [ 255, 255, 255 ],
	      [ 0, 0, 0 ] ];
  
  for (my $i=1; $i<11; $i++) {
    push(@$colors, [ $i * 25, 0, 0 ]);
  }
  for (my $i=1; $i<11; $i++) {
    push(@$colors, [ 0, $i * 25, 0 ]);
  }
  
  return $colors;
}

sub colors {
  my ($self) = @_;

  return $self->{colors};
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub cell_size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{cell_size} = $size;
  }

  return $self->{cell_size};
}

sub legend {
  my ($self, $legend) = @_;

  if (defined($legend)) {
    $self->{legend} = $legend;
  }

  return $self->{legend};
}

sub legend_size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{legend_size} = $size;
  }

  return $self->{legend_size};
}
