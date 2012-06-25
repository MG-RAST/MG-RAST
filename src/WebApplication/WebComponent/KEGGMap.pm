package WebComponent::KEGGMap;

use strict;
use warnings;

use base qw( WebComponent );

1;

use File::Temp;

use Conf;
use WebComponent::WebGD;
use WebColors;

=pod

=head1 NAME

KEGGMap - a component to access KEGG maps and print them

=head1 DESCRIPTION

WebComponent to access KEGG maps and print them

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('Hover', 'KeggMapHover'.$self->id);

  $self->{maps} = [];
  $self->{map_names} = {};
  $self->{map_ids} = {};
  $self->{map_coordinates} = {};
  $self->{reaction_coordinates} = {};
  $self->{compound_coordinates} = {};
  $self->{ec_coordinates} = {};
  $self->{kegg_link} = "http://www.genome.jp/dbget-bin/show_pathway?";
  $self->{kegg_base_path} = $Conf::kegg || "$Conf::mgrast_data/kegg";
  $self->{kegg_base_path} .= "/pathway/map/";
  $self->{error} = '';
  $self->{highlights} = [];
  $self->{area} = 1;

  unless ($self->initialize_kegg_data()) {
    return undef;
  }
  
  $self->{map_id} = $self->maps(0);
  $self->{map_name} = $self->map_names($self->maps(0));

  return $self;
}

=item * B<output> ()

Returns the html output of the KEGGMap component.

=cut

sub output {
  my ($self) = @_;

  # initialize objects
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $hover = $application->component('KeggMapHover'.$self->id);
    
  # load the reaction, ec numbers, and compounds for the map
  $self->ec_coordinates;
  $self->reaction_coordinates;
  $self->compound_coordinates;   
  $self->map_coordinates;
   
  # open map file
  my $image;
  my $image_base = $self->kegg_base_path."map".$self->map_id;
  my $image_file = $image_base.".png";
  if (-f $image_file) {
    $image = WebGD->newFromPng($image_file, 1);
  } else {
    $image_base .= ".gif";
    my $tmp = File::Temp->new( TEMPLATE => 'keggXXXXX',
			       DIR => $Conf::temp,
			       SUFFIX => '.png');
    $image_file = $tmp->filename;
    my $convert = $Conf::ext_bin."/convert";
    `$convert -transparent white $image_base $image_file`;
    if (-f $image_file) {
      $image = WebGD->newFromPng($image_file, 1);
    }
  }
  unless ($image) {
    $self->error("Could not open KEGG map image: $!");
    return "";
  }

  # color map and create image map
  my $unique = int(rand(100000));
  my $image_map = "<map name='kegg_map_imap_" . $self->id() . $unique . "'>";
  my %coords_to_highlights;

  foreach my $highlight ( @{$self->highlights} ) 
  {
    # figure out which kind of id we have
    my $id = $highlight->{id};
    my $coordinates;
    if ($self->ec_coordinates && $self->ec_coordinates->{$id}) {
      $coordinates = $self->ec_coordinates->{$id}
    } elsif ($self->reaction_coordinates && $self->reaction_coordinates->{$id}) {
      $coordinates = $self->reaction_coordinates->{$id};
    } elsif ($self->compound_coordinates && $self->compound_coordinates->{$id}) {
      $coordinates = $self->compound_coordinates->{$id};
    } elsif ($self->map_coordinates && $self->map_coordinates->{$id}) {
      $coordinates = $self->map_coordinates->{$id};
    } elsif ($self->map_ids->{$id} && $self->map_coordinates->{$self->map_ids->{$id}}) {
      $coordinates = $self->map_coordinates->{$self->map_ids->{$id}};
    } else {
      if ($self->{verbose}) {
	print STDERR "unrecognized id in KEGGMap: $id\n";
      }
      next;
    }

    # determine if the user wants to filter coordinates for a particular ec or reaction
    my $reaction = $highlight->{reaction};
    my $ec = $highlight->{ec};
    my @ec_coordinates;
    if (ref($ec) eq 'ARRAY') {
		@ec_coordinates = map { @{$self->ec_coordinates->{$_}} if exists $self->ec_coordinates->{$_} } @$ec;
    } elsif (defined($ec) && defined($self->ec_coordinates->{$ec})) {
		@ec_coordinates = @{$self->ec_coordinates->{$ec}};
    }

    # iterate through the coordinates for the id
  coords: foreach my $coords (@$coordinates) 
  {
      next unless (@$coords);

      # if they've specified a particular EC or reaction, check that the coordinates match
      # Check that the EC is actually in the map - sometimes KEGG uses protein names
      my $coords_string = stringify_coords($coords);

      if ($ec && @ec_coordinates > 1)
      {
	  my $found_match = 0;

	  foreach my $ec_coords (@ec_coordinates)
	  {
	      if ($coords_string eq stringify_coords($ec_coords)) {
		  $found_match = 1;
		  last;
	      }
	  }

	  next coords unless $found_match;
      }
      elsif ($reaction) 
      {
	  my $found_match = 0;

	  foreach my $reaction_coords (@{$self->reaction_coordinates->{$reaction}})
	  {
	      if ($coords_string eq stringify_coords($reaction_coords)) {
		  $found_match = 1;
		  last;
	      }
	  }

	  next coords unless $found_match;
      }

      if (exists $coords_to_highlights{$coords_string})
      {
	  # merge the highlights as well as possible
	  my $existing_highlight = $coords_to_highlights{$coords_string};
	  $existing_highlight->{filled} = $highlight->{filled} if exists $highlight->{filled};
	  # keep the existing highlight color unless it is just white
	  my $existing_color=$existing_highlight->{color};
	  if ($existing_color)
	  {
	      if (ref($existing_color) eq 'ARRAY') 
	      {
		  if (((ref($existing_color->[0]) ne 'ARRAY') && (scalar @{$existing_color} == 3) && $existing_color->[0] == 255 && $existing_color->[1] == 255 && $existing_color->[2] == 255) ||
		      ((ref($existing_color->[0]) eq 'ARRAY') && (scalar @{$existing_color} == 1) && (scalar @{$existing_color->[0]} == 3) && $existing_color->[0]->[0] == 255 && $existing_color->[0]->[1] == 255 && $existing_color->[0]->[2] == 255))
		  {
		      $existing_highlight->{color} = $highlight->{color} if $highlight->{color};
		  }
	      }
	      elsif ($existing_color eq "white")
	      {
		  $existing_highlight->{color} = $highlight->{color} if $highlight->{color};	  
	      }
	  }
	  if ($highlight->{border}) { $existing_highlight->{border} = $highlight->{border} unless $existing_highlight->{border};}
	  if ($highlight->{link}) 
	  { 
	      if ($existing_highlight->{link}) {
		  # NEED TO CREATE A POP-UP THAT ALLOWS SELECTION OF EITHER LINK
	      }
	      else {
		  $existing_highlight->{link} = $highlight->{link};
	      }
	  }
	  if ($highlight->{target}) { $existing_highlight->{target} = $highlight->{target} unless $existing_highlight->{target};}
	  $existing_highlight->{tooltip} .= "<br><br>".$highlight->{tooltip};
      }
      else {
	  $coords_to_highlights{$coords_string} = $highlight;
      }
    }
}

  foreach my $coord_string (keys %coords_to_highlights)
  {
      my ($x1, $y1, $x2, $y2) = split ":", $coord_string;
      my $highlight = $coords_to_highlights{$coord_string};
      my $blue = $image->colorResolve(0,0,255);
      my $green = [ 0, 255, 0 ];

      # by default, fill the coordinates
      unless (exists($highlight->{filled}) && ! $highlight->{filled}) {

	# convert colors from name to rgb
	if ($highlight->{color}) {
	  if (ref($highlight->{color}) eq 'ARRAY') {
	    if ((ref($highlight->{color}->[0]) ne 'ARRAY') && ($highlight->{color}->[0] !~ /\d/)) {
	      foreach my $col (@{$highlight->{color}}) {
		$col = WebColors::color_to_rgb($col);
	      }
	    }
	  } elsif ($highlight->{color} !~ /\d/) {
	    $highlight->{color} = WebColors::color_to_rgb($highlight->{color});
	  }
	}

	# check if there are multiple colors
	if ($highlight->{color} && ref ($highlight->{color}->[0]) eq 'ARRAY') {
	  my $i = 1;
	  my $num_parts = scalar(@{$highlight->{color}});
	  my $begin = $x1 + 1;
	  my $end = $x2 - 1;
	  my $len = int(($end - $begin) / $num_parts);
	  foreach my $color (@{$highlight->{color}}) {
	    if ($i == $num_parts) {
	      $end = $x2 - 1;
	    } else {
	      $end = $begin + $len;
	    }
	    my $im_col =  $image->colorAllocateAlpha($color->[0], $color->[1], $color->[2], 300);
	    $image->filledRectangle($begin, $y1 + 1, $end, $y2 - 1, $im_col);
	    $begin = $end + 1;
	    $i++;
	  }
	} else {
	  my $color = $highlight->{color} || $green;
	  $color = $image->colorAllocateAlpha($color->[0], $color->[1], $color->[2], 300);
	  $image->filledRectangle($x1 + 1, $y1 + 1, $x2 - 1, $y2 - 1 , $color);
	}
      }
      # otherwise draw a blue box
      else {
	$image->rectangle($x1, $y1, $x2, $y2, $blue);
      }
      if (exists($highlight->{border})) {
	  my $color = $highlight->{border};
	  if ($color !~ /\d/) {
	      $color = WebColors::color_to_rgb($color);
	  }

	  for (my $i=0; $i<3; $i++) {
	      $image->rectangle($x1-$i, $y1-$i, $x2+$i, $y2+$i, $image->colorResolve(@{$color}));
	  }
      }
      if ($self->area()) {
	my $target = "";
	if (exists($highlight->{target})) {
	  $target = " target='".$highlight->{target}."'";
	}
	my $link = "";
	if (exists($highlight->{link})) {
	  $link = " href='".$highlight->{link}."'";
	}
	my $over = "";
	if (exists($highlight->{tooltip})) {
	  # need unique hover_id for id/ec/reaction combination
	  my $hover_id = $highlight->{id};
	  $hover_id .= $highlight->{reaction} if exists $highlight->{reaction};
	  $hover_id .= $highlight->{ec} if exists $highlight->{ec};
	  $over = " onmouseover='hover(event, \"".$hover_id."\", \"".$hover->id."\");'";
	  $hover->add_tooltip($hover_id, $highlight->{tooltip});
	}
	$image_map .= "<area shape='rect' coords='".join(",", $x1, $y1, $x2, $y2)."' $over$link$target>";
    }
  }
  $image_map .= "</map>";

  my $html = "<img src='".$image->image_src()."' usemap=#kegg_map_imap_".$self->id.$unique.">".$image_map.$hover->output();

  return $html;
}

sub map_coordinates {
  my($self, $name_or_id) = @_;

  # check name / id
  my $map_id;
  if ($name_or_id) {
    if ($self->map_ids($name_or_id)) {
      $map_id = $self->map_ids($name_or_id);
    } elsif ($self->map_names($name_or_id)) {
      $map_id = $name_or_id;
    } else {
      $self->error("Map name or id not found.");
      return undef;
    }
  } else {
    $map_id = $self->map_id;
  }
  
  # check cache
  unless (exists($self->{map_coordinates}->{$map_id})) {
    
    # load coordinates
    my $coords = {};
    
    my $file = $self->kegg_base_path . 'map' . $map_id . '.conf';
    if (open(COORDS, "<$file")) {
      
      while ( <COORDS> ) {
	my $line = $_;
	chomp $line;
	if ( $line =~ /rect\s\((\d+),(\d+)\)\s+\((\d+),(\d+)\).+map(\d+)\.html/ ) {
	  push(@{$coords->{$5}}, [$1,$2,$3,$4]);
	}
      }
      close(COORDS);
      
      $self->{map_coordinates}->{$map_id} = $coords;
    } else {
      $self->error("Could not open coordinates file: $!");
    }
    
    return $self->{map_coordinates}->{$map_id};
  } else {
    $self->error("Could not open coordinates file: $!");
  }
  
  return $self->{map_coordinates}->{$map_id};
}

sub ec_coordinates {
  my($self, $name_or_id) = @_;

  # check name / id
  my $map_id;
  if ($name_or_id) {
    if ($self->map_ids($name_or_id)) {
      $map_id = $self->map_ids($name_or_id);
    } elsif ($self->map_names($name_or_id)) {
      $map_id = $name_or_id;
    } else {
      $self->error("Map name or id not found.");
      return undef;
    }
  } else {
    $map_id = $self->map_id;
  }
  
  # check cache
  unless (exists($self->{ec_coordinates}->{$map_id})) {
    
    # load coordinates
    my $coords = {};
    
    my $file = $self->kegg_base_path . 'map' . $map_id . '_ec.coord';
    if (open(COORDS, "<$file")) {
      
      while ( <COORDS> ) {
	my $line = $_;
	chomp $line;
	my($ec, $x1, $y1, $x2, $y2) = split(/\s+/, $line);
	push(@{$coords->{$ec}}, [$x1,$y1,$x2,$y2]);
      }
      close(COORDS);
      
      $self->{ec_coordinates}->{$map_id} = $coords;
    } else {
      $self->error("Could not open coordinates file: $!");
    }
    
    return $self->{ec_coordinates}->{$map_id};
  } else {
    $self->error("Could not open coordinates file: $!");
  }
  
  return $self->{ec_coordinates}->{$map_id};
}

sub reaction_coordinates {
  my($self, $name_or_id) = @_;
  
  # check name / id
  my $map_id;
  if ($name_or_id) {
    if ($self->map_ids($name_or_id)) {
      $map_id = $self->map_ids($name_or_id);
    } elsif ($self->map_names($name_or_id)) {
      $map_id = $name_or_id;
    } else {
      $self->error("Map name or id not found.");
      return undef;
    }
  } else {
    $map_id = $self->map_id;
  }
  
  # check cache
  unless (exists($self->{reaction_coordinates}->{$map_id})) {
    
    # load coords
    my $coords = {};
    
    my $file = $self->kegg_base_path . 'map' . $map_id . '_rn.coord';
    if (open(COORDS, "<$file")) {
      
      while ( <COORDS> ) {
	my $line = $_;
	chomp $line;
	my($rxn, $x1, $y1, $x2, $y2) = split(/\s+/, $line);
	push(@{$coords->{$rxn}}, [$x1,$y1,$x2,$y2]);
      }
      close(COORDS);
      
      $self->{reaction_coordinates}->{$map_id} = $coords;
    } else {
      $self->error("Could not open coordinates file: $!");
    }
  }
    
  return $self->{reaction_coordinates}->{$map_id};
}
  
sub compound_coordinates {
  my($self, $name_or_id) = @_;
  
  # check name / id
  my $map_id;

  if ($name_or_id) {
    if ($self->map_ids($name_or_id)) {
      $map_id = $self->map_ids($name_or_id);
    } elsif ($self->map_names($name_or_id)) {
      $map_id = $name_or_id;
    } else {
      $self->error("Map name or id not found.");
      return undef;
    }
  } else {
    $map_id = $self->map_id;
  }
  
  # check cache
  unless (exists($self->{compound_coordinates}->{$map_id})) {
    
    # load coords
    my $coords = {};
    
    my $file = $self->kegg_base_path . 'map' . $map_id . '_cpd.coord';
    if (open(COORDS, "<$file")) {
      
      while ( <COORDS> ) {
	my $line = $_;
	chomp $line;
	my($cpd, $x1, $y1, $x2, $y2) = split(/\s+/, $line);
	push(@{$coords->{$cpd}}, [$x1,$y1,$x2,$y2]);
      }
      close(COORDS);
      
      $self->{compound_coordinates}->{$map_id} = $coords;
    } else {
      $self->error("Could not open coordinates file: $!");
    }
  }
  
  return $self->{compound_coordinates}->{$map_id};
}

sub kegg_link {
  my ($self, $link) = @_;
    
  if (defined($link)) {
    $self->{kegg_link} = $link;
  }
  
  return $self->{kegg_link};
}

sub kegg_base_path {
  my ($self, $path) = @_;

  if (defined($path)) {
    $self->{kegg_base_path} = $path;
  }
  
  return $self->{kegg_base_path};
}

sub maps {
  my ($self, $index) = @_;

  if (defined($index)) {
    return $self->{maps}->[$index];
  }

  return $self->{maps};
}

sub map_names {
  my ($self, $map_id) = @_;

  if (defined($map_id)) {
    return $self->{map_names}->{$map_id};
  }

  return $self->{map_names};
}

sub map_ids {
  my ($self, $map_name) = @_;

  if (defined($map_name)) {
    return $self->{map_ids}->{$map_name};
  }
  
  return $self->{map_ids};
}

sub map_id {
  my ($self, $map) = @_;

  if (defined($map)) {
    $self->{map_id} = $map;
  }

  return $self->{map_id};
}

sub map_name {
  my ($self, $map_name) = @_;

  if (defined($map_name)) {
    return $self->{map_name} = $map_name;
  }

  return $self->{map_name};
}

sub error {
  my ($self, $error) = @_;

  if (defined($error)) {
    $self->{error} = $error;
  }

  return $self->{error};
}

sub initialize_kegg_data {
  my ($self) = @_;

  # load the kegg map index
  my $path = $self->kegg_base_path. "../map_title.tab";
  if (open(FH, $path)) {
    while (<FH>) {
      chomp;
      my ($id, $name) = split /\t/;
      push(@{$self->{maps}}, $id);
      $self->{map_names}->{$id} = $name;
      $self->{map_ids}->{$name} = $id;
    }
    close FH;
  } else {
    print STDERR "Could not open map title file ($path): $!\n";
    return 0;
  }

  return 1;
}

sub highlights {
  my ($self, $highlights) = @_;

  if (defined($highlights)) {
    $self->{highlights} = $highlights;
  }
  
  return $self->{highlights};
}

sub area {
  my ($self, $area) = @_;

  if (defined($area)) {
    $self->{area} = $area;
  }
  
  return $self->{area};
}

sub stringify_coords {
    my ($coords) = @_;
    return $coords->[0].":".$coords->[1].":".$coords->[2].":".$coords->[3];
}
