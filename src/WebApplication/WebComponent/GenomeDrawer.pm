package WebComponent::GenomeDrawer;

# GenomeDrawer - component to create abstract images of the chromosome

# $Id: GenomeDrawer.pm,v 1.37 2011-06-13 09:45:27 paczian Exp $

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

GenomeDrawer - component to create abstract images of the chromosome

=head1 DESCRIPTION

Creates an inline image for abstract chromosome visualization

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Hover', 'GenomeDrawerHoverComponent'.$self->id());
  
  $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
  $self->{lines} = [];
  $self->{image} = undef;
  $self->{show_legend} = 0;
  $self->{legend_width} = 110;
  $self->{width} = 800;
  $self->{colors} = [];
  $self->{line_height} = 28;
  $self->{height} = undef;
  $self->{display_titles} = 0;
  $self->{window_size} = 50000;
  $self->{scale} = undef;
  $self->{line_select} = 0;
  $self->{select_positions} = {};
  $self->{select_checks} = {};

  return $self;
}

=item * B<output> ()

Returns the html output of the GenomeDrawer component.

=cut

sub output {
  my ($self) = @_;

  # initialize image
  $self->image();
  
  # get the hover component
  my $hover_component = $self->application->component('GenomeDrawerHoverComponent'.$self->id());

  # create image map
  my $unique_map_id = int(rand(100000));
  my $map = "<map name='imap_".$self->id."_".$unique_map_id."'>";
  my @maparray;

  # Create some tiles to shade colors in case the requested colors exceeds the finite set
  my @tiles       = $self->tiles();
  my $n_tiles     = scalar @tiles;
  my $n_colors    = scalar @{$self->colors};
  my $n_sp_colors = scalar @{WebColors::get_palette('special')};
  my $shift       = 3;  # shift item color by this amount to skip special colors
  
  # draw lines
  my $i = 0;
  my $y_offset = 0;
  my $x_offset = $self->show_legend() * $self->legend_width();
  foreach my $line (@{$self->lines}) {
    my $lh = $line->{config}->{line_height} || $self->line_height;
    $self->{lh} = $lh;

    # draw center line
    unless ($line->{config}->{no_middle_line}) {
      $self->image->line($x_offset, $y_offset + 3 + ($lh / 2), $self->width + $x_offset, $y_offset + 3 + ($lh / 2), $self->colors->[1]);
    }

    # check for legend
    if ($self->show_legend) {
      
      # check for description of line
      if (defined($line->{config}->{short_title}) && !defined($line->{config}->{title})) {
	$line->{config}->{title} = $line->{config}->{short_title};
      }
      if (defined($line->{config}->{title})) {
	my $short_title = undef;
	if (defined($line->{config}->{short_title})) {
	  $short_title = $line->{config}->{short_title};
	}
	my $onclick = " ";
	if (defined($line->{config}->{title_link})) {
	  $onclick .= "onclick=\"" . $line->{config}->{title_link} . "\"";
	}
	
	my $line_id = "line_".$i."_info";
	unless ($line->{config}->{no_title_hover}) {
	  $hover_component->add_tooltip($line_id, "<table><tr><th>".($line->{config}->{hover_title}||'Organism')."</th></tr><tr><td>".$line->{config}->{title}."</td></tr></table>");
	  my $tooltip = "onmouseover='hover(event, \"$line_id\", \"".$hover_component->id()."\");' ";
	  
	  if (defined($short_title) || defined($line->{config}->{title_link})) {
	    push(@maparray, '<area shape="rect" coords="' . join(',', 2, $y_offset, $x_offset, $y_offset + $lh) . "\" " . $tooltip . $onclick . ' id="'.$line_id.'">');
	  } else {
	    $short_title = $line->{config}->{title};
	  }
	}
	
	# check for checkbox space
	my $checkbox_space = 2;
	if ($self->line_select) {
	  $checkbox_space = 14;
	  $self->select_positions->{$line->{config}->{select_id}} = [ $y_offset, $i ];
	}
	$self->image->string(gdSmallFont, $checkbox_space, $y_offset + ($lh / 2) - 4, $short_title, $self->colors->[1]);
      }
    }

    # sort items according to z-layer
    if (defined($line->{data}->[0]->{zlayer})) {
      my @sortline = sort { $a->{zlayer} <=> $b->{zlayer} } @{$line->{data}};
      $line->{data} = \@sortline;
    }

    # draw items
    my $h = 0;
    foreach my $item (@{$line->{data}}) {
      next unless defined($item->{start}) && defined($item->{end});
	    
      # set to default fill and frame color
      $item->{fillcolor} = $self->colors->[4];
      $item->{framecolor} = $self->colors->[1];

      # check for multi-coloring
      if (defined($item->{color})) {
	if (ref($item->{color}) eq 'ARRAY') {
	  $item->{fillcolor} = $self->image->colorResolve($item->{color}->[0], $item->{color}->[1], $item->{color}->[2]);
	} else {
	    my($color_index, $tile_index) = &color_indices($item->{color}, $n_colors, $n_sp_colors, $n_tiles, $shift);
	    $item->{fillcolor} = $self->colors->[$color_index];
 
	    if ( defined($tile_index) )
	    {
		$item->{tile} = $tiles[$tile_index];
	    }
	}
      }
      unless (defined($line->{config}->{basepair_offset})) {
	$line->{config}->{basepair_offset} = 0;
      }
      $item->{start_scaled} = ($item->{start} - $line->{config}->{basepair_offset}) * $self->scale();
      $item->{end_scaled} = ($item->{end} - $line->{config}->{basepair_offset}) * $self->scale();
      my $i_start = $item->{start_scaled};
      my $i_end = $item->{end_scaled};
      if ($i_start > $i_end) {
	my $x = $i_start;
	$i_start = $i_end;
	$i_end = $x;
      }

      # determine type of item to draw
      unless (defined($item->{type})) {
	$self->draw_box($y_offset, $item);
      } elsif ($item->{type} eq "box") {
	$self->draw_box($y_offset, $item);
      } elsif ($item->{type} eq "arrow") {
	$self->draw_arrow($y_offset, $item);
      } elsif ($item->{type} eq "smallbox") {
	$self->draw_smallbox($y_offset, $item);
      } elsif ($item->{type} eq "smallbox_noborder") {
	$self->draw_smallbox($y_offset, $item, 1);
      } elsif ($item->{type} eq "bigbox") {
	$self->draw_bigbox($y_offset, $item);
      } elsif ($item->{type} eq "bigbox_noborder") {
	$self->draw_bigbox($y_offset, $item, 1);
      } elsif ($item->{type} eq "ellipse") {
	$self->draw_ellipse($y_offset, $item);
      } elsif ($item->{type} eq "line") {
	$self->draw_line($y_offset, $item);
      } elsif ($item->{type} eq "diamond") {
	$self->draw_diamond($y_offset, $item);
      } elsif ($item->{type} eq "hline") {
	$self->draw_hline($y_offset, $item);
      }

      # add item to image map
      my $menu = "";
      my $info = "";
      if (defined($item->{description})) {
	$info = "<table>";
	foreach my $desc_item (@{$item->{description}}) {
	  if (defined($desc_item->{value})) {
	    $desc_item->{value} =~ s/'/`/g;
	    $desc_item->{value} =~ s/"/``/g;
	    if (defined($desc_item->{title})) {
	      $info .= "<tr><td style=&quot;vertical-align: top; padding-right: 10px;&quot;><b>" . $desc_item->{title} . "</b></td><td>" . $desc_item->{value} . "</td></tr>";
	    }
	  }
	}
	$info .= "</table>";
      }
      
      my $item_id = "item_".$i."_".$h;
      my $tooltip = "onmouseover='hover(event, \"$item_id\", \"".$hover_component->id()."\");' ";
      if (defined($item->{links_list})) {

	my $menu_entries = [];
	my $menu_links = [];
	foreach my $link (@{$item->{links_list}}) {
	  push(@$menu_entries, $link->{link_title});
	  push(@$menu_links, $link->{link});
	}
	$hover_component->add_menu($item_id, $menu_entries, $menu_links);
	$tooltip .= "onclick='hover(event, \"$item_id\", \"".$hover_component->id()."\");' ";
      }
      
      unless (defined($item->{title})) {
	$item->{title} = "";
      }

      if ($info) {
	$hover_component->add_tooltip($item_id, "<table><tr><th>".$item->{title}."</th></tr><tr><td>".$info."</td></tr></table>");
      }
	    
      my $onclick = " ";
      if ($item->{onclick}) {
	$onclick .= "onclick=\"" . $item->{onclick} . "\" ";
      }

      my $href = "";
      if ($item->{href}) {
	$href = ' href="'.$item->{href}.'"';
      }
      
      my $x1 = int($x_offset + $i_start);
      my $y1 = int($y_offset);
      my $x2 = int($x_offset + $i_end);
      my $y2 = int($y_offset + $lh);

      push(@maparray, '<area shape="rect"'.$href.' coords="' . join(',', $x1, $y1, $x2, $y2) . "\" " . $tooltip . $onclick . 'id="'.$item_id.'">');
      $h++;
    }
	
    # calculate y-offset
    $y_offset =  $y_offset + $lh;
	
    # increase counter
    $i++;
  }

  # finish image map
  $map .= join("\n", reverse(@maparray));
  $map .= "</map>";
    
  # create html
  my $image = '<img usemap="#imap_' . $self->id . '_'.$unique_map_id.'" style="border: none;" src="' . $self->image->image_src()  . '" id="genome_drawer_img_'.$self->id.'">'.$map.$hover_component->output();
  
  # check for checkboxes
  if ($self->line_select) {
    my $i = 0;
    my $checkboxes = "";
    my @select_ids = sort { $self->select_positions->{$a}->[1] <=> $self->select_positions->{$b}->[1] } keys(%{$self->select_positions});
    foreach my $select_id (@select_ids) {
      my $yadd = int(($i - ($i % 57)) / 57) * 14;
      my $ymove = $self->height - $self->select_positions->{$select_id}->[0] - 9 + $yadd;
      my $xmove = ($i % 57) * 14 + 3;
      my $checked = " checked=checked";
      if (defined($self->select_checks->{$select_id})) {
	unless ($self->select_checks->{$select_id}) {
	  $checked = "";
	}
      }
      $checkboxes .= "<input type='checkbox' id='feature$i' name='feature' value='".$select_id."'$checked style='width: 14px; height: 14px; margin: 0px; padding: 0px; position: relative; top: -".$ymove."px; left: -".$xmove."px;'>";
      $i++;
    }
    $image = "<br>" . $image . "<br>" . $checkboxes;
  }
  
  return $image;
}

sub color_indices {
    my($item_color, $n_colors, $n_sp_colors, $n_tiles, $shift) = @_;

    # Set the index number of the color used from the colors array
    # $shift is added to skip some special colors
    my $color_index = $item_color + $shift;

    # Set the index number of the tile used (shading) from the tiles array
    # Set $tile_index to undef for no tile
    my $tile_index = undef;

    if ( $color_index >= $n_colors )
    {
	# If color index exceeds the number of colors available, use tiling (shading) to differentiate identical colors
	
	# Set color index to skip special colors and cycle over remaining colors
	$color_index = $n_sp_colors + ($item_color + $shift - $n_colors)%($n_colors - $n_sp_colors);
	
	# Set tile index to increase by 1 every time the non-special colors are all utilized
	# N.B. This is done modulo $n_tiles, so the tiling will cycle over the available tiles, this will
	# occur when there are ~ 50 colors * (5 + 1) tiles = 300 distinct color/tile pairs, at which point 
	# the image is going to be pretty messy anyway. 
	# If it becomes necessary to handle this correctly, add extra tiles with colored (non-black) shading.
	# The 'tile' subroutine will handle this.
	$tile_index  = int(($item_color + $shift - $n_colors)/($n_colors - $n_sp_colors))%$n_tiles;
    }

    return ($color_index, $tile_index);
}

# draw an arrow
sub draw_arrow {
  my ($self, $y_offset, $item) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $labelcolor = $item->{labelcolor} || $self->colors->[1];
  my $x_offset   = $self->show_legend() * $self->legend_width();
  
  # optional parameters
  my $arrow_height     = $self->{lh};
  my $arrow_head_width = 9;
  my $label            = "";
  if ($self->display_titles()) {
    $label = $item->{label};
  }
  unless (defined($label)) {
    $label = "";
  }
  my $linepadding = 10;
  
  # precalculations
  my $direction = 1;
  if ($start > $end) {
    $direction = 0;
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  if ($start < 0) {
    $start = 0;
  }
  if ($end < 0) {
    return ($im, $start, $end);
  }
  $arrow_height = $arrow_height - $linepadding;
  $ypos = $ypos + 8;
  my $boxpadding = $arrow_height / 5;
  my $fontheight = 12;
  
  # draw arrow
  my $arrowhead = new GD::Polygon;
  
  # calculate x-pos for title
  my $string_start_x_right = $x_offset + $start + (($end - $start - $arrow_head_width) / 2) - (length($label) * 6 / 2);
  my $string_start_x_left = $x_offset + $start + (($end - $start + $arrow_head_width) / 2) - (length($label) * 6 / 2);
  
  # check for arrow direction
  if ($direction) {
    
    # draw arrow box
    if ($arrow_head_width < ($end - $start)) {
      $im->rectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding + 1, $framecolor);
      $im->setThickness(1);
    } else {
      $arrow_head_width = $end - $start;
    }
    
    # calculate arrowhead
    $arrowhead->addPt($x_offset + $end - $arrow_head_width, $ypos);
    $arrowhead->addPt($x_offset + $end, $ypos + ($arrow_height / 2));
    $arrowhead->addPt($x_offset + $end - $arrow_head_width, $ypos + $arrow_height);
    
    # draw label
    $im->string(gdSmallFont, $string_start_x_right, $ypos + $boxpadding - $fontheight - 2, $label, $labelcolor);
    
    # draw arrowhead
    $im->filledPolygon($arrowhead, $fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledPolygon($arrowhead, gdTiled);
    }
    $im->polygon($arrowhead, $framecolor);
    $im->setThickness(1);
    
    # draw arrow content
    $im->filledRectangle($x_offset + $start + 1,$ypos + $boxpadding + 1,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding,$fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledRectangle($x_offset + $start + 1,$ypos + $boxpadding + 1,$x_offset + $end - $arrow_head_width,$ypos + $arrow_height - $boxpadding,gdTiled);
    }
    
  } else {
    
    # draw arrow box
    if ($arrow_head_width < ($end - $start)) {
      $im->rectangle($x_offset + $start + $arrow_head_width,$ypos + $boxpadding,$x_offset + $end,$ypos + $arrow_height - $boxpadding + 1, $framecolor);
      $im->setThickness(1);
    } else {
      $arrow_head_width = $end - $start;
    }
    
    # calculate arrowhead
    $arrowhead->addPt($x_offset + $start + $arrow_head_width, $ypos);
    $arrowhead->addPt($x_offset + $start, $ypos + ($arrow_height / 2));
    $arrowhead->addPt($x_offset + $start + $arrow_head_width, $ypos + $arrow_height);
    
    # draw label
    $im->string(gdSmallFont, $string_start_x_left, $ypos + $boxpadding - $fontheight - 2, $label, $labelcolor);
    # draw arrowhead
    $im->filledPolygon($arrowhead, $fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledPolygon($arrowhead, gdTiled);
    }
    $im->polygon($arrowhead, $framecolor);
    $im->setThickness(1);
    
    # draw arrow content
    $im->filledRectangle($x_offset + $start + $arrow_head_width - 1,$ypos + $boxpadding + 1,$x_offset + $end - 1,$ypos + $arrow_height - $boxpadding,$fillcolor);
    if ( $item->{tile} ) {
	$im->setTile($item->{tile}); 
	$im->filledRectangle($x_offset + $start + $arrow_head_width - 1,$ypos + $boxpadding + 1,$x_offset + $end - 1,$ypos + $arrow_height - $boxpadding,gdTiled);
    }
  }
  
  return ($im, $start, $end);
}

# draw a diamon
sub draw_diamond {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset + 5;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $labelcolor = $item->{labelcolor} || $self->colors->[1];
  my $x_offset   = $self->show_legend() * $self->legend_width();
  
  # optional parameters
  my $item_height = $self->{lh} - 5;

  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  my $len = ($end - $start) / 2;

  # draw the diamond
  my $diamond = new GD::Polygon;
  $diamond->addPt($x_offset + $start, $ypos + ($item_height / 2));
  $diamond->addPt($x_offset + $start + ($len / 2), $ypos + $item_height);
  $diamond->addPt($x_offset + $end, $ypos + ($item_height / 2));
  $diamond->addPt($x_offset + $start + ($len / 2), $ypos);
  $im->filledPolygon($diamond, $fillcolor);

  return ($im, $start, $end);
}

# draw a small box
sub draw_smallbox {
  my ($self, $y_offset, $item, $noborder) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();
  
  # optional parameters
  my $linepadding = 10;
  my $box_height = $self->{lh} - 2 - $linepadding;
  $ypos = $ypos + 10;
  my $boxpadding = $box_height / 5;
  $box_height = $box_height - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  
  # draw box content
  $im->filledRectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end,$ypos + $box_height - $boxpadding + 2,$fillcolor);
  if ( $item->{tile} ) {
      $im->setTile($item->{tile}); 
      $im->filledRectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end,$ypos + $box_height - $boxpadding + 2,gdTiled);
  }

  # draw box
  unless (defined($noborder)) {
    $im->rectangle($x_offset + $start,$ypos + $boxpadding,$x_offset + $end,$ypos + $box_height - $boxpadding + 2, $framecolor);
  }
    
  return ($im, $start, $end);
}

# draw a big box
sub draw_bigbox {
  my ($self, $y_offset, $item, $noborder) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();
  
  
  # optional parameters
  my $box_height = $self->{lh} - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }

  # draw box content
  $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,$fillcolor);
  if ( $item->{tile} ) {
      $im->setTile($item->{tile}); 
      $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,gdTiled);
  }

  # draw box
  unless ($noborder) {
    $im->rectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height, $framecolor);
  }
  
  return ($im, $start, $end);
}

# draw a box
sub draw_box {
  my ($self, $y_offset, $item) = @_;
  
  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();
  
  # optional parameters
  my $box_height = $self->{lh} - 2;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  
  $ypos = $ypos + 8;
  $box_height = $box_height - 8;
  
  # draw box
  $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,$fillcolor);
  if ( $item->{tile} ) {
      $im->setTile($item->{tile}); 
      $im->filledRectangle($x_offset + $start,$ypos,$x_offset + $end,$ypos + $box_height,gdTiled);
  }
  $im->rectangle($x_offset + $start - 1,$ypos,$x_offset + $end + 1,$ypos + $box_height, $framecolor);
  
  return ($im, $start, $end);
}

sub draw_hline {
  my ($self, $yoffset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $yoffset;
  my $im         = $self->image;
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();
  my $labelcolor = $item->{labelcolor} || $self->colors->[1];
  my $fontheight = $item->{label} ? 12 : 6;
  if ($start < 0) {
    $start = 0;
  }
  
  # optional parameters
  my $height = $self->{lh};
  $im->line($x_offset + $start,$ypos + ($self->{lh}/2) + 3,$x_offset + $end,$ypos + ($self->{lh}/2) + 3, $framecolor);

  # check for label
  if ($item->{label}) {
    my $off = int((length($item->{label}) * 6) / 2);
    $im->string(gdSmallFont, $x_offset + $start - $off, $ypos, $item->{label}, $labelcolor);
  }

  return ($im, $start, $end);
}

# draw a line (it has to be drawn somewhere...)
sub draw_line {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset;
  my $im         = $self->image;
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();
  my $labelcolor = $item->{labelcolor} || $self->colors->[1];
  my $fontheight = $item->{label} ? 12 : 6;
  
  # optional parameters
  my $height = $self->{lh};
  $im->line($x_offset + $start,$ypos + $fontheight,$x_offset + $start,$ypos + $self->{lh}, $framecolor);

  # check for label
  if ($item->{label}) {
    my $off = int((length($item->{label}) * 6) / 2);
    $im->string(gdSmallFont, $x_offset + $start - $off, $ypos, $item->{label}, $labelcolor);
  }
  
  return ($im, $start, $end);
}

# draw a ellipse
sub draw_ellipse {
  my ($self, $y_offset, $item) = @_;

  # required parameters
  my $start      = $item->{start_scaled};
  my $end        = $item->{end_scaled};
  my $ypos       = $y_offset + 5;
  my $im         = $self->image;
  my $fillcolor  = $item->{fillcolor};
  my $framecolor = $item->{framecolor};
  my $x_offset   = $self->show_legend() * $self->legend_width();

  my $lineheight = $self->{lh} - 5;
  
  # precalculations
  if ($start > $end) {
    my $x = $start;
    $start = $end;
    $end = $x;
  }
  my $length = $end - $start;
  $im->filledEllipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, $fillcolor);
  if ( $item->{tile} ) {
      $im->setTile($item->{tile}); 
      $im->filledEllipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, gdTiled);
  }
  $im->ellipse($x_offset + $start + ($length / 2), $ypos + ($lineheight / 2) + 1, $length, $lineheight - 6, $framecolor);
  
  return ($im, $start, $end);
}

sub add_line {
  my ($self, $data, $config) = @_;

  unless ($config) {
    $config = { };
  }
  
  push(@{$self->{lines}}, { 'data' => $data, 'config' => $config });

  return 1;
}

=item * B<lines> ()

Getter for the lines attribute.

=cut

sub lines {
  my ($self) = @_;

  return $self->{lines};
}

=item * B<clear_lines> ()

Empties the lines array.

=cut

sub clear_lines {
  my ($self) = @_;

  $self->{lines} = [];
  $self->{image} = undef;

  return 1;
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

=item * B<tiles> (I<tiles>)

Setter for the tiles.

=cut

sub tiles {
    my($self) = @_;
 
    # Return a number of tiles with transparent background and black foreground
   
    return ( 
	     $self->tile('nw_diagonal'),
	     $self->tile('ne_diagonal'),
	     $self->tile('vertical'),
	     $self->tile('horizontal'),
	     $self->tile('stipple'),

	     # tiles with white shading, 
	     $self->tile('nw_diagonal', [0,0,0], [255,255,255], 1),
	     $self->tile('ne_diagonal', [0,0,0], [255,255,255], 1),
	     $self->tile('vertical',    [0,0,0], [255,255,255], 1),
	     $self->tile('horizontal',  [0,0,0], [255,255,255], 1),
	     $self->tile('stipple',     [0,0,0], [255,255,255], 1),
	     );
}

sub tile {
    my($self, $type, $bg, $fg, $trans) = @_;

    # The background and foreground colors as well as the background transparency can set

    # Set default background color to white and foreground color to black if they are not defined
    $bg ||= [255,255,255];
    $fg ||= [  0,  0,  0];

    # Set default to transparent background
    $trans ||= 1;

    my $tile = new GD::Image(3,3);
    my $background = $tile->colorAllocate(@$bg);
    my $foreground = $tile->colorAllocate(@$fg);

    # Make background color transparent if requested
    $trans && $tile->transparent($background);

    if ( $type eq 'nw_diagonal' ) {
	$tile->line(0,2,2,0,$foreground);
    } elsif ( $type eq 'ne_diagonal' ) {
	$tile->line(0,0,2,2,$foreground);
    } elsif ( $type eq 'vertical' ) {
	$tile->line(1,0,1,2,$foreground);
    } elsif ( $type eq 'horizontal' ) {
	$tile->line(1,0,2,0,$foreground);
    } elsif ( $type eq 'stipple' ) {
	$tile->setPixel(1,1,$foreground);
    }

    return $tile;
}

=item * B<image> (I<image>)

Getter / Setter for the image.

=cut

sub image {
  my ($self) = @_;

  unless (defined($self->{image})) {
    $self->{image} = new WebGD($self->width() + ($self->show_legend() * $self->legend_width()), $self->height());
    foreach my $triplet (@{$self->color_set}) {
      push(@{$self->colors}, $self->image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
    }
  }

  return $self->{image};
}

=item * B<window_size> (I<window_size>)

Getter / Setter for the windows size of the graphic part of the image in basepairs.

=cut

sub window_size {
  my ($self, $window_size) = @_;

  if (defined($window_size)) {
    $self->{window_size} = $window_size;
  }

  return $self->{window_size};
}

=item * B<show_legend> (I<show_legend>)

Getter / Setter for whether to show the image legend.

=cut

sub show_legend {
  my ($self, $show_legend) = @_;

  if (defined($show_legend)) {
    $self->{show_legend} = $show_legend;
  }

  return $self->{show_legend};
}

=item * B<legend_width> (I<legend_width>)

Getter / Setter for the legend_width.

=cut

sub legend_width {
  my ($self, $legend_width) = @_;

  if (defined($legend_width)) {
    $self->{legend_width} = $legend_width;
  }

  return $self->{legend_width};
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

Getter for the height of the image.

=cut

sub height {
  my ($self) = @_;

  my $height = 0;
  foreach my $line (@{$self->lines}) {
    my $lh = $line->{config}->{line_height} || $self->line_height();
    $height += $lh;
  }
  unless ($height) {
    $height = $self->line_height();
  }

  return $height;
}

=item * B<line_height> (I<line_height>)

Getter / Setter for the line height of the image.

=cut

sub line_height {
  my ($self, $line_height) = @_;

  if (defined($line_height)) {
    $self->{line_height} = $line_height;
  }

  return $self->{line_height};
}

=item * B<max> (I<max>)

Getter / Setter for the max base of the image.

=cut

sub max {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max} = $max;
  }

  return $self->{max};
}

=item * B<min> (I<min>)

Getter / Setter for the min base of the image.

=cut

sub min {
  my ($self, $min) = @_;

  if (defined($min)) {
    $self->{min} = $min;
  }

  return $self->{min};
}

=item * B<display_titles> (I<display_titles>)

Getter / Setter for the display titles attribute of the image.

=cut

sub display_titles {
  my ($self, $disp) = @_;

  if (defined($disp)) {
    $self->{display_titles} = $disp;
  }

  return $self->{display_titles};
}

=item * B<add_color> (I<color>)

Adds a new color to the image and returns it's index.
I<color> must be an array reference with r/g/b values.

=cut

sub add_color {
  my ($self, $color) = @_;

  if (defined($color)) {
    push(@{$self->colors}, $self->image->colorResolve($color->[0], $color->[1], $color->[2]));
    return scalar(@{$self->colors}) -1;
  }

  return undef;
}


=item * B<scale> ()

Getter for the scale factor of the image.

=cut

sub scale {
  my ($self) = @_;

  unless (defined($self->{scale})) {
    $self->{scale} = $self->width() / $self->window_size();
  }

  return $self->{scale};
}

sub line_select {
  my ($self, $ls) = @_;

  if (defined($ls)) {
    $self->{line_select} = $ls;
  }

  return $self->{line_select};
}

sub select_positions {
  my ($self) = @_;

  return $self->{select_positions};
}

sub select_checks {
  my ($self, $checks) = @_;

  if (defined($checks)) {
    $self->{select_checks} = $checks;
  }

  return $self->{select_checks};
}
