package WebComponent::PhyloTree;

# PhyloTree - component to create phylogenetic tree views

use strict;
use warnings;

use base qw( WebComponent );

1;

use Conf;
use GD;
use GD::Polyline;
use WebComponent::WebGD;
use Math::Trig;
use WebColors;

use Data::Dumper;

use constant PI => 4 * atan2 1, 1;
use constant RAD => 2 * PI / 360;

=pod

=head1 NAME

PhyloTree - component to create phylogenetic tree views

=head1 DESCRIPTION

Creates an inline image for a phylogenetic tree view

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->{color_set} = $self->define_colors;
  $self->{colors} = [];
  $self->{image} = undef;
  $self->{nodes} = {};
  $self->{name_level_map} = {};
  $self->application->register_component('Hover', 'PhyloTreeHoverComponent'.$self->id());
  $self->application->register_component('PieChart', 'HoverPie'.$self->id());

  $self->{total_value} = 0;

  $self->{size} = 800;
  $self->{data} = undef;
  $self->{depth} = 4;
  $self->{level_distance} = 40;
  $self->{coloring_method} = "abundance";
  $self->{title_space} = 300;
  $self->{node_size} = 12;

  $self->{show_titles} = 1;
  $self->{shade_titles} = 0;
  $self->{font_size} = 15;
  $self->{show_leaf_weight} = 1;
  $self->{leaf_weight_type} = 'bar';
  $self->{leaf_weight_space} = 0;
  $self->{link_action} = "";
  $self->{color_leafs_only} = 0;
  $self->{enable_click} = 0;
  $self->{sample_names} = [ 'A', 'B' ];
  $self->{reroot_id} = undef;
  $self->{reroot_field} = undef;
  $self->{legend} = "";
  $self->{style} = "";
  $self->{show_sample_colors} = 1;

  $self->{show_tooltip} = 1;

  return $self;
}

=item * B<output> ()

Returns the html output of the PhyloTree component.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $leaf_weight_width = $cgi->param('leaf_weight_width') || 2;
  my $sample_names = $self->sample_names;

  unless (defined($self->data())) {
    return "no data passed to PhyloTree component";
  }

  # parse the input data
  $self->parse_data;

  # check for rerooting
  if ($self->reroot_id) {
    $self->reroot();
  }

  # get the hover component
  my $hover_component = $self->application->component('PhyloTreeHoverComponent'.$self->id());
  
  # initialize image
  $self->image();

  # make space for the titles
  my $title_space = 0;
  if ($self->show_titles) {
    $title_space = $self->title_space;
  }

  # make space for the leaf weights
  my $leaf_weight_space = 0;
  if ($self->show_leaf_weight) {
    $leaf_weight_space = $self->{leaf_weight_space} || $self->level_distance;
  }

  # get font
  my $courier = "$Conf::SITE/fonts/Verdana.ttf";  

  my $thick = $self->{thick} || 3;
  $self->image->setThickness($thick);

  # get the pie
  my $pie = $application->component("HoverPie".$self->id);
  $pie->show_tooltip(0);
  $pie->size(100);

  # initialize imagemap array
  my @map_spots = ();
  my $depth = $self->depth;
  my $circumference = $self->size * 2 * PI;
  my $level_distance = $self->level_distance * 2;
  my $radius = $self->size();
  my $leafs = $self->nodes_for_level($depth - 1);
  my $num_leafs = scalar(@$leafs) + $self->num_root_level;
  my $leaf_distance = ($circumference - ($circumference % $num_leafs)) / $num_leafs;
  my $curr_pos = 0;
  my $factor = 360 / $num_leafs;
  my $rim = 0;
  my $last_parent = "";
  my $parent_pos = {};
  my $last_root = "";
  my $div = "";

  $leaf_weight_width = $factor / 2.5;

  # parse level positions
  my $level_positions = [];
  foreach my $leaf (@$leafs) {
    if ($leaf->{root} ne $last_root) {
      $last_root = $leaf->{root};
      $curr_pos++;
    }
    my $a1 = 270.2 + ($factor * $curr_pos) - $leaf_weight_width;
    my $a2 = 270.2 + ($factor * ($curr_pos + 1)) - $leaf_weight_width;

    my @node_lineage = split /; /, $leaf->{lineage};
    for (my $i=0; $i<scalar(@node_lineage); $i++) {
      if (defined($level_positions->[$i])) {
	if (exists($level_positions->[$i]->{ $node_lineage[$i] })) {
	  $level_positions->[$i]->{ $node_lineage[$i] }->[1] = $a2;
	} else {
	  $level_positions->[$i]->{ $node_lineage[$i] } = [ $a1, $a2 ];
	}
      } else {
	$level_positions->[$i] = { $node_lineage[$i] => [ $a1, $a2 ] };
      }
    }

    $curr_pos++;
  }
  $last_root = "";
  $curr_pos = 0;

  my $legend = "";
  
  # title shading
  if ($self->shade_titles) {
    my $shading_level = $self->shade_titles - 1;
    my $shading_elements = $self->nodes_for_level($shading_level);
    my $inner = $self->size() - $title_space - 4;
    my $outer = $self->size() - 1;
    my $cols = $self->shading_colors;

    $legend = "<div id='pt_legend_".$self->id."'><table>";

    for (my $ii=0; $ii<scalar(@$shading_elements); $ii++) {
      my $elem = $shading_elements->[$ii];
      my $poly = myrim($radius, $radius, $inner, $outer, $level_positions->[$shading_level]->{$elem->{name}}->[0], $level_positions->[$shading_level]->{$elem->{name}}->[1]);
      $self->image->filledPolygon($poly, $cols->[$ii % scalar(@$cols)]);
      my $item_id = 'shading_hover_'.$elem->{name};
      $hover_component->add_tooltip($item_id, $elem->{name});

      my $rgb_cols = [ @{WebColors::get_palette('circle')}, @{WebColors::get_palette('excel')} ];
      $legend .= "<tr><td><div style='width: 10px; height: 10px; background-color: rgb(".join(",", @{$rgb_cols->[$ii % scalar(@$rgb_cols)]}).");'></div></td><td> ".$elem->{name} . "</td></tr>";

      push(@map_spots, "<area shape='poly' coords='".join(",", map { int($_->[0] / 2).",".int($_->[1] / 2) } $poly->vertices)."' id='$item_id' onmouseover='hover(event, \"$item_id\", \"".$hover_component->id()."\");'>");
    }
    
    $legend .= "</table></div>";
    $self->legend($legend);
  }

  # draw leafs
  foreach my $leaf (@$leafs) {    
    if ($leaf->{root} ne $last_root) {
      $last_root = $leaf->{root};
      $curr_pos++;
    }
    my $angle = 270 + ($factor * $curr_pos);
    my $inner = $self->size() * 2 - ($rim * ($level_distance)) - $level_distance - $radius - 15 - $title_space - $leaf_weight_space;
    my $outer = $self->size() * 2 - ($rim * ($level_distance)) - $radius - 15 - $title_space - $leaf_weight_space;
    
    my $color = $self->get_color($leaf);
    
    my ($x1, $y1) = getxypos($angle, $inner);
    my ($x2, $y2) = getxypos($angle, $outer);
    $x1 += $radius;
    $y1 += $radius;
    $x2 += $radius;
    $y2 += $radius;
    unless ($leaf->{empty}) {
      if ($self->color_leafs_only) {
	$self->image->line($x1, $y1, $x2, $y2, $self->colors->[1]);
      } else {
	$self->image->line($x1, $y1, $x2, $y2, $color);
      }

      # show titles
      if ($self->show_titles) {
	my $title = $self->size() * 2 - ($rim * ($level_distance)) - $radius - $title_space;
	my $angle2 = $angle;
	my ($x3, $y3) = getxypos($angle2 + 0.5, $title);
	my $leaf_disp_name = $leaf->{name};
	my @bounds = GD::Image->stringFT($self->colors->[1],$courier,$self->font_size,0,0,0,$leaf_disp_name);
	while (($bounds[2] - $bounds[0]) > ($title_space - 5)) {
	  chop $leaf_disp_name;
	  @bounds = GD::Image->stringFT($self->colors->[1],$courier,$self->font_size,0,0,0,$leaf_disp_name);
	}
	if ($angle2 > 450) {
	  my $tl = $bounds[2] - $bounds[0];
	  ($x3, $y3) = getxypos($angle2 - 0.5, $title + $tl);
	  $angle2 += 180;
	}
	$x3 += $radius;
	$y3 += $radius;
	my $str_col = $self->colors->[1];
        my $bright = 0;
	map { if ($_ > 200) { $bright = 1; } } $self->image->rgb($self->image->getPixel($x3,$y3));
	if ($self->shade_titles && ! $bright) {
	  $str_col = $self->colors->[0];
	}
	$self->image->stringFT($str_col,$courier,$self->font_size,(360 - $angle2)*RAD,$x3,$y3,$leaf_disp_name);
      }

      # show leaf weights
      if ($self->show_leaf_weight) {
	if ($self->coloring_method eq 'split') {
	  if ($self->leaf_weight_type eq 'bar') {
	    my $lws = $self->get_leaf_height($leaf);
	    my $lww = $leaf_weight_width * 2 / scalar(@$lws) - 0.1;
	    for (my $ii=0; $ii<scalar(@$lws); $ii++) {
	      my $poly = new GD::Polygon;
	      my ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * $ii) + ($ii * 0.1), $outer + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * $ii) + ($ii * 0.1), $outer + $lws->[$ii] + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * ($ii+1)) + ($ii * 0.1), $outer + $lws->[$ii] + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * ($ii+1)) + ($ii * 0.1), $outer + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      $self->image->filledPolygon($poly,$self->leaf_colors->[$ii]);
	    }
	  } elsif ($self->leaf_weight_type eq 'stack') {
	    my $lws = $self->get_leaf_height($leaf);
	    my $lww = $leaf_weight_width * 2 - 0.1;
	    my $cstart = 0;
	    my $cend = 0;
	    for (my $ii=0; $ii<scalar(@$lws); $ii++) {
	      $cstart = $cend;
	      $cend = $cstart + $lws->[$ii];
	      my $poly = new GD::Polygon;
	      my ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + 15 + $cstart);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + $cend + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width + $lww, $outer + $cend + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width + $lww, $outer + 15 + $cstart);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      $self->image->filledPolygon($poly,$self->leaf_colors->[$ii]);
	    }
	  }
	} else {
	  my $c = $self->colors->[3];
	  my $poly = new GD::Polygon;
	  my $leaf_height = $self->get_leaf_height($leaf);
	  my ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + 15);
	  $x3 += $radius;
	  $y3 += $radius;
	  $poly->addPt($x3,$y3);
	  ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + 15 + $leaf_height);
	  $x3 += $radius;
	  $y3 += $radius;
	  $poly->addPt($x3,$y3);
	  ($x3, $y3) = getxypos($angle + $leaf_weight_width, $outer + 15 + $leaf_height);
	  $x3 += $radius;
	  $y3 += $radius;
	  $poly->addPt($x3,$y3);
	  ($x3, $y3) = getxypos($angle + $leaf_weight_width, $outer + 15);
	  $x3 += $radius;
	  $y3 += $radius;
	  $poly->addPt($x3,$y3);
	  $self->image->filledPolygon($poly,$c);
	}
      }
      
      # add map spot
      my $item_id = "node_".$self->id."_".$leaf->{id};
      my $v = $leaf->{value};
      if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	my $vnew = "";
	for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
	  $vnew .= "<br>&nbsp;&nbsp;<b>".$sample_names->[$ii].":</b> ".$v->[$ii];
	}
	$v = $vnew;
      }
      my $info = "<b>hits:</b> ".$v."<br><b>lineage:</b> ".$leaf->{lineage};

      my $d = [];
      if (scalar(@{$leaf->{children}}) && ! $self->{nodes}->{$leaf->{children}->[0]}->{empty}) {
	if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	  my $dt = [];
	  $info .= "<table><tr>";
	  for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
	    my $dtcurr = 0;
	    @$d = map { $self->{nodes}->{$_}->{value}->[$hh] } @{$leaf->{children}};
	    foreach my $dv (@$d) {
	      $dtcurr += $dv;
	    }
	    $dt->[$hh] = $dtcurr;
	    $pie->data($d);
	    $pie->output();
	    if ($hh % 4 == 0) {
	      $info .= "</tr><tr>";
	    }
	    $info .= "<td>".$sample_names->[$hh]."<img src='".$pie->image->image_src()."'></td>";
	  }
	  $info .= "</tr></table>";
	  $info .= "<table><tr><th width=10></th><th>Name</th>";
	  for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
	    $info .= "<th>Hits ".$sample_names->[$hh]."</th>";
	  }
	  $info .= "</tr>";
	  my $ii = 0;
	  foreach my $n (@{$leaf->{children}}) {
	    $info .= "<tr><td style='background-color: rgb(".($pie->color_set->[$ii + 6]->[0]||0).",".($pie->color_set->[$ii + 6]->[1]||0).",".($pie->color_set->[$ii + 6]->[2]||0).");'>&nbsp;</td><td>".$self->{nodes}->{$n}->{name}."</td>";
	    for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
	      my $percent = "0";
	      if ($self->{nodes}->{$n}->{value}->[$hh]) {
		$percent = sprintf("%.2f", $self->{nodes}->{$n}->{value}->[$hh] / $dt->[$hh] * 100 );
	      }
	      $info .= "<td>".$self->{nodes}->{$n}->{value}->[$hh]." (" . $percent . "\%)</td>";
	    }
	    $info .= "</tr>";
	    $ii++;
	  }
	  $info .= "</table>";
	} else {
	  @$d = map { $self->{nodes}->{$_}->{value} } @{$leaf->{children}};
	  my $dt = 0;
	  foreach my $dv (@$d) {
	    $dt += $dv;
	  }
	  $pie->data($d);
	  $pie->output();
	  $info .= "<table><tr><td><img src='".$pie->image->image_src()."'></td><td>";
	  $info .= "<table><tr><th width=10></th><th>Name</th><th>Hits</th></tr>";
	  my $ii = 0;
	  foreach my $n (@{$leaf->{children}}) {
	    my $percent = "0";
	    if ($self->{nodes}->{$n}->{value}) {
	      $percent = sprintf("%.2f", $self->{nodes}->{$n}->{value} / $dt * 100 );
	    }
	    $info .= "<tr><td style='background-color: rgb(".($pie->color_set->[$ii + 6]->[0] || "0").",".($pie->color_set->[$ii + 6]->[1] || "0").",".($pie->color_set->[$ii + 6]->[2] || "0").");'>&nbsp;</td><td>".($self->{nodes}->{$n}->{name} || "" )."</td><td>".($self->{nodes}->{$n}->{value} || "")." (" . $percent . "\%)</td></tr>";
	    $ii++;
	  }
	  $info .= "</table></td></tr></table>";
	}
      }
      
      $hover_component->add_tooltip($item_id, "<table><tr><th>".$leaf->{name}."</th></tr><tr><td>".$info."</td></tr></table>");
      my $href = "";
      if ($self->link_action) {
	my $node_attrib = $leaf->{lineage};
	$node_attrib =~ s/; /\|/g;
	$href = "href='?page=".$self->application->page->name."&node=".$leaf->{id}."&node_attrib=".$node_attrib."&".$self->link_action."'";
      }
      my $onclick = "";
      if ($self->enable_click) {
	my $nids = [ $leaf->{id} ];
	my $cn = $leaf;
	while ($cn->{parent}) {
	  $cn = $self->{nodes}->{$cn->{parent}};
	  push(@$nids, $cn->{id});
	}
	my $reroot = '';
	if ($self->reroot_field) {
	  $reroot = qq~document.getElementById("~.$self->reroot_field.qq~").value="~.$leaf->{id}.qq~";~;
	}
	$onclick = qq~ onclick='~.$reroot.qq~show_detail_info("~ . $hover_component->id . qq~", "~ . $self->id . qq~", "~ . join('|', @$nids) . qq~", this);'~;
      }
      my $mouseover = " onmouseover='hover(event, \"$item_id\", \"".$hover_component->id()."\");'";
      if (! $self->show_tooltip) {
	$mouseover = "";
      }
      push(@map_spots, "<area style='cursor: pointer;' shape='circ' coords='".int($x2/2).",".int($y2/2).",".int($self->{node_size} / 4)."' id='$item_id'$mouseover $href$onclick>");
      $self->image->setThickness($self->{thick2} || 1);
      $self->image->filledEllipse($x2, $y2, $self->{node_size}, $self->{node_size}, $self->colors->[0]);
      $self->image->ellipse($x2, $y2, $self->{node_size}, $self->{node_size}, $self->colors->[1]);
      $self->image->setThickness($thick);
    }
    
    my $curr_parent = $leaf->{parent};
    if ($curr_parent && $curr_parent ne $last_parent) {
      # draw a parent line
      my $start = $angle;
      my $num_siblings = scalar(@{$self->{nodes}->{$leaf->{parent}}->{children}}) - 1;
      my $stop = 270 + ($factor * ($curr_pos + $num_siblings));
      $color = $self->get_color($self->{nodes}->{$curr_parent});
      if ($num_siblings) {
	if ($self->color_leafs_only) {
	  myarc($self->image, $radius, $radius, $inner, $start, $stop, $self->colors->[1]);
	} else {
	  myarc($self->image, $radius, $radius, $inner, $start, $stop, $color);
	}
	$angle = $start + (($stop - $start) / 2);
      }
      $outer = $inner;
      $inner = $inner - $level_distance;
      ($x1, $y1) = getxypos($angle, $inner);
      ($x2, $y2) = getxypos($angle, $outer);
      $x1 += $radius;
      $y1 += $radius;
      $x2 += $radius;
      $y2 += $radius;
      $parent_pos->{$curr_parent} = [$x1, $y1, $x2, $y2, $angle];
      $last_parent = $curr_parent;
    }
    $curr_pos++;
  }

  for ($rim=1;$rim<($depth+1);$rim++) {
    $last_parent = "";
    my $curr_num_nodes = 0;
    my $nodes = $self->nodes_for_level($depth - $rim - 1);
    foreach my $node (@{$nodes}) {

      my $color = $self->get_color($node);
      my $p = $parent_pos->{$node->{id}};
      next unless $p;
      unless ($node->{empty}) {
	
	if ($self->color_leafs_only) {
	  $self->image->line($p->[0], $p->[1], $p->[2], $p->[3], $self->colors->[1]);
	} else {
	  $self->image->line($p->[0], $p->[1], $p->[2], $p->[3], $color);
	}
	
	# add map spot
	my $item_id = "node_".$self->id."_".$node->{id};
	my $v = $node->{value};
	if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	  my $vnew = "";
	  for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
	    $vnew .= "<br>&nbsp;&nbsp;<b>".$sample_names->[$ii].":</b> ".$v->[$ii];
	  }
	  $v = $vnew;
	}
	my $info = "<b>hits:</b> ".$v."<br><b>lineage:</b> ".$node->{lineage};

	my $d = [];
	if (scalar(@{$node->{children}}) && ! $self->{nodes}->{$node->{children}->[0]}->{empty}) {
	  if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	    my $dt = [];
	    $info .= "<table><tr>";
	    for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
	      my $dtcurr = 0;
	      @$d = map { $self->{nodes}->{$_}->{value}->[$hh] } @{$node->{children}};
	      foreach my $dv (@$d) {
		$dtcurr += $dv;
	      }
	      $dt->[$hh] = $dtcurr;
	      $pie->data($d);
	      $pie->output();
	      if ($hh % 4 == 0) {
		$info .= "</tr><tr>";
	      }
	      $info .= "<td>".$sample_names->[$hh]."<img src='".$pie->image->image_src()."'></td>";
	    }
	    $info .= "</tr></table>";
	    $info .= "<table><tr><th width=10></th><th>Name</th>";
	    for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
	      $info .= "<th>Hits ".$sample_names->[$hh]."</th>";
	    }
	    $info .= "</tr>";
	    my $ii = 0;
	    foreach my $n (@{$node->{children}}) {
	      $info .= "<tr><td style='background-color: rgb(".($pie->color_set->[$ii + 6]->[0]||0).",".($pie->color_set->[$ii + 6]->[1]||0).",".($pie->color_set->[$ii + 6]->[2]||0).");'>&nbsp;</td><td>".$self->{nodes}->{$n}->{name}."</td>";
	      for (my $hh=0; $hh<scalar(@{$self->sample_names}); $hh++) {
		my $percent = "0";
		if ($self->{nodes}->{$n}->{value}->[$hh]) {
		  $percent = sprintf("%.2f", $self->{nodes}->{$n}->{value}->[$hh] / $dt->[$hh] * 100 );
		}
		$info .= "<td>".$self->{nodes}->{$n}->{value}->[$hh]." (" . $percent . "\%)</td>";
	      }
	      $info .= "</tr>";
	      $ii++;
	    }
	    $info .= "</table>";
	  } else {
	    @$d = map { $self->{nodes}->{$_}->{value} } @{$node->{children}};
	    my $dt = 0;
	    foreach my $dv (@$d) {
	      $dt += $dv;
	    }
	    $pie->data($d);
	    $pie->output();
	    $info .= "<table><tr><td><img src='".$pie->image->image_src()."'></td><td>";
	    $info .= "<table><tr><th width=10></th><th>Name</th><th>Hits</th></tr>";
	    my $ii = 0;
	    foreach my $n (@{$node->{children}}) {
	      my $percent = "0";
	      if ($self->{nodes}->{$n}->{value}) {
		$percent = sprintf("%.2f", $self->{nodes}->{$n}->{value} / $dt * 100 );
	      }
	      $info .= "<tr><td style='background-color: rgb(".($pie->color_set->[$ii + 6]->[0] || "0").",".($pie->color_set->[$ii + 6]->[1] || "0").",".($pie->color_set->[$ii + 6]->[2] || "0").");'>&nbsp;</td><td>".($self->{nodes}->{$n}->{name} || "")."</td><td>".($self->{nodes}->{$n}->{value} || "")." (" . $percent . "\%)</td></tr>";
	      $ii++;
	    }
	    $info .= "</table></td></tr></table>";
	  }
	} else {
	  # show titles
	  if ($self->show_titles) {
	    my $angle = $p->[4];
	    my $title = $self->size() * 2 - ($rim * ($level_distance)) - $radius - $title_space;
	    my ($x3, $y3) = getxypos($angle + 0.5, $title);
	    if ($angle > 450) {
	      my @bounds = GD::Image->stringFT($self->colors->[1],$courier,$self->font_size,0,0,0,$node->{name});
	      my $tl = $bounds[2] - $bounds[0];
	      ($x3, $y3) = getxypos($angle - 0.5, $title + $tl);
	      $angle += 180;
	    }
	    $x3 += $radius;
	    $y3 += $radius;
	    $self->image->stringFT($self->colors->[1],$courier,$self->font_size,(360 - $angle)*RAD,$x3,$y3,$node->{name});
	  }

	  # show leaf weights
	  if ($self->show_leaf_weight) {
	    my $outer = sqrt((abs($radius - $p->[2])*abs($radius - $p->[2])) + (abs($radius - $p->[3])*abs($radius - $p->[3])));
	    my $angle = $p->[4];
	    if ($self->coloring_method eq 'split') {
	      if ($self->leaf_weight_type eq 'bar') {
		my $lws = $self->get_leaf_height($node);
		my $lww = $leaf_weight_width * 2 / scalar(@$lws) - 0.1;
		for (my $ii=0; $ii<scalar(@$lws); $ii++) {
		  my $poly = new GD::Polygon;
		  my ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * $ii) + ($ii * 0.1), $outer + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * $ii) + ($ii * 0.1), $outer + $lws->[$ii] + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * ($ii+1)) + ($ii * 0.1), $outer + $lws->[$ii] + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width + ($lww * ($ii+1)) + ($ii * 0.1), $outer + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  $self->image->filledPolygon($poly,$self->leaf_colors->[$ii]);
		}
	      } elsif ($self->leaf_weight_type eq 'stack') {
		my $lws = $self->get_leaf_height($node);
		my $lww = $leaf_weight_width * 2 - 0.1;
		my $cstart = 0;
		my $cend = 0;
		for (my $ii=0; $ii<scalar(@$lws); $ii++) {
		  $cstart = $cend;
		  $cend = $cstart + $lws->[$ii];
		  my $poly = new GD::Polygon;
		  my ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + 15 + $cstart);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + $cend + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width + $lww, $outer + $cend + 15);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  ($x3, $y3) = getxypos($angle - $leaf_weight_width + $lww, $outer + 15 + $cstart);
		  $x3 += $radius;
		  $y3 += $radius;
		  $poly->addPt($x3,$y3);
		  $self->image->filledPolygon($poly,$self->leaf_colors->[$ii]);
		}
	      }
	    } else {
	      my $poly = new GD::Polygon;
	      my ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle - $leaf_weight_width, $outer + $leaf_weight_space);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle + $leaf_weight_width, $outer + $leaf_weight_space);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      ($x3, $y3) = getxypos($angle + $leaf_weight_width, $outer + 15);
	      $x3 += $radius;
	      $y3 += $radius;
	      $poly->addPt($x3,$y3);
	      $self->image->filledPolygon($poly,$self->get_color($node));
	    }
	  }
	}

	$hover_component->add_tooltip($item_id, "<table><tr><th>".$node->{name}."</th></tr><tr><td>".$info."</td></tr></table>");
	my $href = "";
	if ($self->link_action) {
	  my $node_attrib = $node->{lineage};
	  $node_attrib =~ s/; /\|/g;
	  $href = "href='?page=".$self->application->page->name."&node=".$node->{id}."&node_attrib=".$node_attrib."&".$self->link_action."'";
	}

	my $onclick = "";
	if ($self->enable_click) {
	  my $nids = [ $node->{id} ];
	  my $cn = $node;
	  while ($cn->{parent}) {
	    $cn = $self->{nodes}->{$cn->{parent}};
	    push(@$nids, $cn->{id});
	  }
	  my $reroot = '';
	  if ($self->reroot_field) {
	    $reroot = qq~document.getElementById("~.$self->reroot_field.qq~").value="~.$node->{id}.qq~";~;
	  }
	  $onclick = qq~ onclick='~.$reroot.qq~show_detail_info("~ . $hover_component->id . qq~", "~ . $self->id . qq~", "~ . join('|', @$nids) . qq~", this);'~;
	}
	
	my $mouseover = " onmouseover='hover(event, \"$item_id\", \"".$hover_component->id()."\");'";
	if (! $self->show_tooltip) {
	  $mouseover = "";
	}
	push(@map_spots, "<area style='cursor: pointer;' shape='circ' coords='".int($p->[2]/2).",".int($p->[3]/2).",".int($self->{node_size} / 4)."' id='$item_id'$mouseover $href$onclick>");
	$self->image->setThickness($self->{thick2} || 1);
	$self->image->filledEllipse($p->[2], $p->[3], $self->{node_size}, $self->{node_size}, $self->colors->[0]);
	$self->image->ellipse($p->[2], $p->[3], $self->{node_size}, $self->{node_size}, $self->colors->[1]);
	$self->image->setThickness($thick);
      }

      if ($rim < ($depth - 1)) {
	my $curr_parent = $node->{parent};
	if ($curr_parent ne $last_parent) {
	  my $siblings = $self->siblings($node->{id});
	  my $num_siblings = scalar(@$siblings);
	  my $start = $p->[4];
	  my $last_sibling = $siblings->[scalar(@$siblings) - 1];
	  my $stop = $parent_pos->{$last_sibling->{id}}->[4];
	  my $angle = $start + (abs($stop - $start) / 2);
	  my $inner = $self->size() * 2 - ($rim * ($level_distance)) - $level_distance - $radius - 15 - $title_space - $leaf_weight_space;
	  my $outer = $self->size() * 2 - ($rim * ($level_distance)) - $radius - 15 - $title_space - $leaf_weight_space;
	  $color = $self->get_color($self->{nodes}->{$curr_parent});
	  if ($self->color_leafs_only) {
	    myarc($self->image, $radius, $radius, $inner, $start, $stop, $self->colors->[1]);
	  } else {
	    myarc($self->image, $radius, $radius, $inner, $start, $stop, $color);
	  }
	  $outer = $inner;
	  $inner = $inner - $level_distance;
	  my ($x1, $y1) = getxypos($angle, $inner);
	  my ($x2, $y2) = getxypos($angle, $outer);
	  $x1 += $radius;
	  $y1 += $radius;
	  $x2 += $radius;
	  $y2 += $radius;
	  $parent_pos->{$curr_parent} = [$x1, $y1, $x2, $y2, $angle];
	  $last_parent = $curr_parent;
	}
      }
      $curr_num_nodes++;
    }
  }

  # sample color legend
  if ($self->{show_sample_colors}) {
    my $mid = $self->{size};
    my $left = $mid - 50;
    my $num_samples = scalar(@$sample_names);
    my $top = $mid - ($num_samples * 15);
    for (my $ii=0;$ii<$num_samples;$ii++) {
      $self->image->filledRectangle($left,$top - 20,$left+20,$top, $self->leaf_colors->[$ii]);
      $self->image->stringFT($self->colors->[1],$courier,$self->font_size,0,$left + 25,$top,$sample_names->[$ii]);
      $top += 30;
    }
  }

  # do anti-aliasing
  my $i2 = new WebGD($self->size(), $self->size(), 1);
  my $white = $i2->colorResolve(255,255,255);
  $i2->transparent($white);
  $i2->copyResampled($self->image,0,0,0,0,$self->size(), $self->size(),$self->size() * 2,$self->size() * 2);

  # create inline gif
  my $style = $self->style;
  my $map = "<map name='imap_circtree_".$self->id."'>".join("\n", @map_spots)."</map>";
  my $image = qq~<img style="border: none; z-index: 1;$style" src="~ . $i2->image_src()  . qq~" usemap="#imap_circtree_~ . $self->id . qq~">~.$map.$hover_component->output()."<br>".$div;

  if ($self->enable_click) {
    $image = "<table style='width: 1500px;'><tr><td>".$image."</td><td><div id='phylo_detail_".$self->id."'></div></td></tr></table>";
  }

  return $image;
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/PhyloTree.js"];
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
    $self->{image} = new WebGD($self->size() * 2, $self->size() * 2, 1);
    foreach my $triplet (@{$self->color_set}) {
      push(@{$self->colors}, $self->image->colorResolve($triplet->[0], $triplet->[1], $triplet->[2]));
    }
    $self->{image}->filledRectangle(0,0,$self->size() * 2 - 1, $self->size() * 2 - 1, $self->colors->[0]);
  }
  return $self->{image};
}

sub shading_colors {
  my ($self) = @_;
  
  unless (defined($self->{shading_colors})) {
    my $shades = [];
    my $triplets = [ @{WebColors::get_palette('circle')}, @{WebColors::get_palette('excel')} ];
    foreach my $triplet (@$triplets) {
      push(@$shades, $self->image->colorAllocate($triplet->[0], $triplet->[1], $triplet->[2]));
    }
    $self->{shading_colors} = $shades;
  }
  
  return $self->{shading_colors};
}

sub leaf_colors {
  my ($self) = @_;
  
  unless (defined($self->{leaf_colors})) {
    my $shades = [];
    my $triplets = [ @{WebColors::get_palette('excel')} ];
    foreach my $triplet (@$triplets) {
      push(@$shades, $self->image->colorAllocate($triplet->[0], $triplet->[1], $triplet->[2]));
    }
    $self->{leaf_colors} = $shades;
  }
  
  return $self->{leaf_colors};
}

# tree functions
sub nodes_for_level {
  my ($self, $level) = @_;

  my $nodes;
  @$nodes = sort { $a->{lineage} cmp $b->{lineage} } map { $self->{nodes}->{$_} } grep { $self->{nodes}->{$_}->{level} == $level } keys(%{$self->{nodes}});

  return $nodes;
}

sub siblings {
  my ($self, $id) = @_;

  my $node = $self->{nodes}->{$id};
  my $siblings = [];
  if ($node->{level}) {
    my $ids = $self->{nodes}->{$node->{parent}}->{children};
    foreach my $i (@$ids) {
      push(@$siblings, $self->{nodes}->{$i});
    }
  } else {
    $siblings = $self->nodes_for_level(0);
  }
  @$siblings = sort { $a->{lineage} cmp $b->{lineage} } @$siblings;

  return $siblings;
}

sub reroot {
  my ($self) = @_;

  my $id = $self->reroot_id();

  my $root_node = $self->{nodes}->{$id};
  $root_node->{parent} = 0;
  my $level = $root_node->{level};
  $self->depth($self->depth - $level);
  $root_node->{level} -= $level;
  my $new_nodes = { $id => $root_node } ;
  foreach my $sn (@{$root_node->{children}}) {
    $self->{nodes}->{$sn}->{level} -= $level;
    $new_nodes->{$sn} = $self->{nodes}->{$sn};
    $new_nodes = $self->build_reroot($new_nodes, $self->{nodes}->{$sn}, $level);
  }

  $self->{nodes} = $new_nodes;

  return 1;
}

sub build_reroot {
  my ($self, $new_nodes, $node, $level) = @_;

  foreach my $sn (@{$node->{children}}) {
    $self->{nodes}->{$sn}->{level} -= $level;
    $new_nodes->{$sn} = $self->{nodes}->{$sn};
    $new_nodes = $self->build_reroot($new_nodes, $self->{nodes}->{$sn}, $level);
  }  

  return $new_nodes;
}

# image processing functions
sub myarc {
  my ($im,$x_off,$y_off,$radius,$a1,$a2,$color) = @_;
  my $astep = 0.1/$radius * 180/PI;
  if ($astep < 0.01) {
    $astep = 0.01;
  }
  for(my $a=$a1;$a<=$a2;$a+=$astep) {
    my ($x, $y) = getxypos($a,$radius);
    $x += $x_off;
    $y += $y_off;
    $im->setPixel($x,$y,$color);
  }
}

# returns the polygon object for a rim
sub myrim {
  my ($x_off, $y_off, $radius_1, $radius_2, $a1, $a2) = @_;

  my $astep = 0.1/$radius_1 * 180/PI;
  if ($astep < 0.01) {
    $astep = 0.01;
  }

  my $poly = new GD::Polygon;
  unless (defined($a1) && defined($a1)) { return $poly; }

  for(my $a=$a1;$a<=$a2;$a+=$astep) {
    my ($x, $y) = getxypos($a,$radius_1);
    $x += $x_off;
    $y += $y_off;
    $poly->addPt($x, $y);
  }

  $astep = 0.1/$radius_2 * 180/PI;
  if ($astep < 0.01) {
    $astep = 0.01;
  }

  for(my $a=$a2;$a>=$a1;$a-=$astep) {
    my ($x, $y) = getxypos($a,$radius_2);
    $x += $x_off;
    $y += $y_off;
    $poly->addPt($x, $y);
  }  

  return $poly;
}

# given an angle, get the xy position for a certain radius
sub getxypos {
  return ( $_[1] * cos(deg2rad($_[0])),
	   $_[1] * sin(deg2rad($_[0])) );
}

sub size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{size} = $size;
  }

  return $self->{size};
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub depth {
  my ($self, $depth) = @_;

  if (defined($depth)) {
    $self->{depth} = $depth;
  }

  return $self->{depth};
}

sub level_distance {
  my ($self, $level_distance) = @_;

  if (defined($level_distance)) {
    $self->{level_distance} = $level_distance;
  }

  return $self->{level_distance};
}

sub coloring_method {
  my ($self, $method) = @_;

  if (defined($method)) {
    $self->{coloring_method} = $method;
    if ($method eq 'difference' or $method eq 'split') {
      $self->{total_value} = [];
      for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
	push(@{$self->{total_value}}, 0);
      }
    }
  }
  
  return $self->{coloring_method};
}

sub get_color {
  my ($self, $node) = @_;

  my $color = $self->colors->[1];
  my $color_scale = {};
  for (my $i=0;$i<102;$i++) {
    $color_scale->{$i} = $self->colors->[$i + 5];
  }

  if ($self->coloring_method eq "domain") {
    if ($node->{root} eq 'Bacteria') {
      $color = $self->colors->[2];
    } elsif ($node->{root} eq 'Eukaryota') {
      $color = $self->colors->[3];
    } elsif ($node->{root} eq 'Archaea') {
      $color = $self->colors->[4];
    }
  } elsif ($self->coloring_method eq 'abundance') {
    my $x = ($node->{value} > 1) ? int(48 / log($self->{total_value}) * log($node->{value})) : $node->{value};
    $color = $color_scale->{$x};
  } elsif ($self->coloring_method eq 'difference') {
    my $aval = 1;
    my $bval = 0;
    if ($self->{total_value}->[1] > $self->{total_value}->[0]) {
      $bval = 1;
      $aval = 0;
    }
    my $factor = $self->{total_value}->[$aval] / $self->{total_value}->[$bval];
    my $a = $node->{value}->[$bval] * $factor;
    my $b = $node->{value}->[$aval];
    my $val;
    if ($a>$b) {
      if ($b == 0) {
	$val = 100;
      } else {
	$val = int(100 / ($a / ($a - $b)));
      }
    } elsif ($b>$a) {
      if ($a == 0) {
	$val = -100;
      } else {
	$val = 0 - int(100 / ($b / ($b - $a)));
      }
    } else {
      $val = 0;
    }
    $color = $self->colors->[56 + $val + 100];
  } elsif ($self->coloring_method eq 'split') {
    my $x = ($node->{value}->[0] > 1) ? int(48 / log($self->{total_value}->[0]) * log($node->{value}->[0])) : $node->{value}->[0];
    my $color_a = $color_scale->{$x};
    $x = ($node->{value}->[1] > 1) ? int(48 / log($self->{total_value}->[1]) * log($node->{value}->[1])) : $node->{value}->[1];
    my $color_b = $color_scale->{$x + 51};

    return ($color_a, $color_b);
  }

  return $color;
}

sub get_leaf_height {
  my ($self, $node) = @_;
  
  my $height = $self->{leaf_weight_space} || $self->level_distance;
  $height -= 5;
  
  if ($self->coloring_method eq 'abundance') {
    $height = ($node->{value} > 1) ? int($height / log($self->{total_value}) * log($node->{value})) : 1;
  } elsif ($self->coloring_method eq 'split') {
    my $heights = [];
    for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
      my $height = ($node->{value}->[$ii] > 1) ? int($height / log($self->{total_value}->[$ii]) * log($node->{value}->[$ii])) : $node->{value}->[$ii];
      push(@$heights, $height);
    }
    if ($self->leaf_weight_type eq 'stack') {
      my $sumheight = 0;
      foreach my $x (@$heights) {
	$sumheight += $x;
      }
      foreach my $x (@$heights) {
	if ($sumheight * $x > 0) {
	  $x = int(($height - 5) / $sumheight * $x);
	} else {
	  $x = 0;
	}
      }
    }
    return $heights;
  }

  return $height;
}

sub define_colors {
  my ($self) = @_;

  # white, black and r,g,b
  my $colors = [
		[255,255,255],
		[0,0,0],
		[0,0,255],
		[255,0,0],
		[0,155,0],
	       ];

  # red shading
  for (my $i=255; $i>0; $i-=5) {
    push(@$colors, [255,$i,$i]);
  }

  # blue shading
  for (my $i=255; $i>0; $i-=5) {
    push(@$colors, [$i,$i,255]);
  }

  # green over yellow to red
  for (my $i=0; $i<100; $i++) {
    push(@$colors, [int($i * 2.5),155 + $i,0]);
  }
  push(@$colors, [255,255,0]);
  for (my $i=0; $i<100; $i++) {
    push(@$colors, [255 - $i,255 - int($i * 2.5),0]);
  }
 
  return $colors
}

sub parse_data {
  my ($self) = @_;

  # parse the data
  my $data = $self->data();
  my $count = 1;
  my $num_root_level = 0;
  foreach my $d (@$data) {
    my $i = 0;
    my $parent = 0;
    foreach my $l (@$d) {
      my $name;
      my $level;
      $level = $i;
      $name  = $l || '';
      if (exists($self->{name_level_map}->{$level."_".$name})) {
	$parent = $self->{name_level_map}->{$level."_".$name};
      } else {
	$self->{name_level_map}->{$level."_".$name} = $count;
	if ($i>0) {
	  push(@{$self->{nodes}->{$parent}->{children}}, $count);
	}
	my $value = 0;
	if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	  $value = [];
	  for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
	    push(@$value, 0);
	  }
	}
	my $info = "";
	my $last = 0;
	my $root = $name;
	my $lineage = $name;
	if (($i + 2) == scalar(@$d)) {
	  $value = $d->[$i + 1];
	  $last = 1;
	  if ($parent) {
	    if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	      for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
		$self->{nodes}->{$parent}->{value}->[$ii] += $value->[$ii];
		$self->{total_value}->[$ii] += $value->[$ii];
	      }
	      my $curr = $parent;
	      while ($self->{nodes}->{$curr}->{parent}) {
		for (my $ii=0; $ii<scalar(@{$self->sample_names}); $ii++) {
		  $self->{nodes}->{$self->{nodes}->{$curr}->{parent}}->{value}->[$ii] += $value->[$ii];
		}
		$curr = $self->{nodes}->{$curr}->{parent};
	      }
	    } else {
	      $self->{nodes}->{$parent}->{value} += $value;
	      $self->{total_value} += $value;
	      my $curr = $parent;
	      while ($self->{nodes}->{$curr}->{parent}) {
		$self->{nodes}->{$self->{nodes}->{$curr}->{parent}}->{value} += $value;
		$curr = $self->{nodes}->{$curr}->{parent};
	      }
	    }
	  }
	}
	if ($parent) {
	  $root = $self->{nodes}->{$parent}->{name};
	  $lineage = $lineage || '';
	  $lineage = $root ? $root."; ".$lineage : $lineage;
	  my $curr = $parent;
	  while ($self->{nodes}->{$curr}->{parent}) {
	    $root = $self->{nodes}->{$self->{nodes}->{$curr}->{parent}}->{name};
	    $lineage = $root ? $root."; ".$lineage : $lineage;
	    $curr = $self->{nodes}->{$curr}->{parent};
	  }
	} else {
	  $num_root_level++;
	}
	$self->{nodes}->{$count} = { name => $name,
				     level => $level,
				     id => $count,
				     parent => $parent,
				     value => $value,
				     children => [],
				     root => $root,
				     lineage => $lineage,
				     info => $info };
	$parent = $count;
	$count++;
	if ($last) {
	  last;
	}
      }
      $i++;
    }
    $i++;
    while ($i < $self->depth) {
      my $value = 0;
      if (($self->coloring_method eq 'difference') || ($self->coloring_method eq 'split')) {
	$value = [0,0];
      }
      $self->{nodes}->{$count} = { empty => 1,
				   root => $self->{nodes}->{$parent}->{root},
				   level => $i,
				   name => "",
				   id => $count,
				   parent => $parent,
				   value => $value,
				   children => [],
				   lineage => $self->{nodes}->{$parent}->{lineage}.";;" };
      push(@{$self->{nodes}->{$parent}->{children}}, $count);
      $parent = $count;
      $count++;
      $i++;
    }
  }
  
  $self->num_root_level($num_root_level);

  return;
}

sub num_root_level {
  my ($self, $val) = @_;

  if (defined($val)) {
    $self->{num_root_level} = $val;
  }

  return $self->{num_root_level};
}

sub show_arcs {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_arcs} = $show;
  }

  return $self->{show_arcs};
}

sub show_titles {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_titles} = $show;
  }

  return $self->{show_titles};
}

sub font_size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{font_size} = $size * 2;
  }

  return $self->{font_size};
}

sub show_leaf_weight {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_leaf_weight} = $show;
  }

  return $self->{show_leaf_weight};
}

sub link_action {
  my ($self, $action) = @_;

  if (defined($action)) {
    $self->{link_action} = $action;
  }

  return $self->{link_action};
}

sub color_leafs_only {
  my ($self, $color) = @_;

  if (defined($color)) {
    $self->{color_leafs_only} = $color;
  }
  
  return $self->{color_leafs_only};
}

sub enable_click {
  my ($self, $enable) = @_;

  if (defined($enable)) {
    $self->{enable_click} = $enable;
  }

  return $self->{enable_click};
}

sub title_space {
  my ($self, $space) = @_;

  if (defined($space)) {
    $self->{title_space} = $space;
  }

  return $self->{title_space};
}

sub node_size {
  my ($self, $size) = @_;

  if (defined($size)) {
    $self->{node_size} = $size;
  }

  return $self->{node_size};
}

sub leaf_weight_space {
  my ($self, $space) = @_;

  if (defined($space)) {
    $self->{leaf_weight_space} = $space;
  }

  return $self->{leaf_weight_space};
}

sub shade_titles {
  my ($self, $shade) = @_;

  if (defined($shade)) {
    $self->{shade_titles} = $shade;
  }

  return $self->{shade_titles};
}

sub sample_names {
  my ($self, $names) = @_;

  if (defined($names)) {
    $self->{sample_names} = $names;
  }

  return $self->{sample_names};
}

sub reroot_id {
  my ($self, $id) = @_;

  if (defined($id)) {
    $self->{reroot_id} = $id;
  }

  return $self->{reroot_id};
}

sub reroot_field {
  my ($self, $id) = @_;

  if (defined($id)) {
    $self->{reroot_field} = $id;
  }

  return $self->{reroot_field};
}

sub leaf_weight_type {
  my ($self, $type) = @_;

  if (defined($type)) {
    $self->{leaf_weight_type} = $type;
  }

  return $self->{leaf_weight_type};
}

sub show_tooltip {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_tooltip} = $show;
  }

  return $self->{show_tooltip};
}

sub legend {
  my ($self, $legend) = @_;
  
  if (defined($legend)) {
    $self->{legend} = $legend;
  }

  return $self->{legend};
}

sub style {
  my ($self, $style) = @_;

  if (defined($style)) {
    $self->{style} = $style;
  }

  return $self->{style};
}

sub show_sample_colors {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_sample_colors} = $show;
  }

  return $self->{show_sample_colors};
}
