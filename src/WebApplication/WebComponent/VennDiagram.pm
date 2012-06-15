package WebComponent::VennDiagram;

# VennDiagram - component for showing the intersection of two lists in a venn diagram

# $Id: VennDiagram.pm

use strict;
use warnings;

use URI::Escape;
use GD;
use GD::Polyline;
use Math::Trig;
use WebComponent::WebGD;
use WebColors;
use base qw( WebComponent );
use Data::Dumper;

1;

use constant PI => 4 * atan2 1, 1;
use constant RAD => 2 * PI / 360;

=pod

=head1 NAME

    DisplayListSelect - component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display

=head1 DESCRIPTION

component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display.

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    $self->application->register_component('Hover', 'VennDiagramHover'.$self->id());

    $self->{colors} = [];
    $self->{color_set} = [ @{WebColors::get_palette('special')}, @{WebColors::get_palette('many')} ];
    $self->{image} = undef;
    $self->{linked_component} = undef;
    #$self->{linked_column_id} = undef;
    $self->{linked_columns} = undef;
    $self->{height} = 400;
    $self->{width} = 400;
    $self->{data} = undef;

    return $self;
}

=item * B<output> ()

Returns the html output of the LineChart component.

=cut

sub output {
    my ($self) = @_;
    my $cgi = new CGI;

    my $data = $self->data();
    unless (defined($data)) {
	return "xy Chart called without data";
    }

    return if (scalar @{$self->data()} == 1);
    return if (scalar @{$self->data()} > 3);

    my $height = $self->height();
    my $width = $self->width();
    my $padding = 40;

    my $hover = $self->application->component('VennDiagramHover'.$self->id());

    my $image = $self->image();
    my $diagColors = {1=> $self->colors->[4], 2=> $self->colors->[3]};
    my $black  = $image->colorAllocate(  0,  0,  0);
    my $red    = $image->colorAllocate(255,  0,  0);
    my $gold  = $image->colorAllocate(255, 215, 0);
    
    # create a new polyline
    my $polylines;
    my $legends;
    my ($linked_component, $linked_component_id, $linked_column_id, $linked_columns);
    
    if ($self->linked_component) {
	$linked_component = $self->linked_component;
	$linked_component_id = $linked_component->id();
	#$linked_column_id = $self->linked_column_id;
	$linked_columns = $self->linked_columns;
    }

    # figure out the intersections and associations of the points
    my $map = [];
    my $data_count = scalar @{$self->data()};
    my ($conjunto, $titles, $conjuntoCounts);
    my $number = 1;

    foreach my $set (@{$self->data()}) {
	$titles->{$number} = $set->[0];
	my $seen = {};
	for (my $i=1;$i<scalar(@$set);$i++) {
	    $seen->{$set->[$i]}++;
	    next if ($seen->{$set->[$i]} > 1);
	    if (defined ($conjunto->{$set->[$i]})) {
		$conjunto->{$set->[$i]} .= "I";
		$conjunto->{$set->[$i]} .= $number;
	    }
	    else{
		$conjunto->{$set->[$i]} = $number;
	    }
	}
	$number++;
    }
    
    my $sets;
    foreach my $value (sort {$conjunto->{$a} cmp $conjunto->{$b}} keys %$conjunto){
	push (@{$sets->{$conjunto->{$value}}}, $value);
    }
 
    # draw the circles
    my $count = 1;
    my $radius = ($height/2)*.6;
    my $filter_labels;
    my $filter_values;
    my ($map_coords,$mapHash,$areas) = &get_coords($width,$height,$radius,$data_count,$image,$black) if ($data_count < 4);
    my $intersection;
    if ($data_count ==1 ){
      $image->arc(($width/2), $height/2, 2*$radius, 2*$radius,0,360,$diagColors->{$count});
    }
    elsif ($data_count == 2){
      while ($count <= $data_count){
	$image->arc(($width/2)+(($width/8)), $height/2, 2*$radius, 2*$radius,0,360,$diagColors->{$count});
	$image->arc(($width/2)+(($width/8)*(-1)), $height/2, 2*$radius, 2*$radius,0,360,$diagColors->{$count});
	
	if (defined $linked_component){
#	  print STDERR "LINKED_COL: " . $linked_columns->{$titles->{$count}} . "\n";
	  $filter_labels->{$linked_columns->{$titles->{$count}}+1} = $titles->{$count};
	  push(@$intersection, $linked_columns->{$titles->{$count}}+1);
	  push(@$filter_values, $linked_columns->{$titles->{$count}}+1);
	  $filter_labels->{'Unique to ' . $linked_columns->{$titles->{$count}}} = 'Unique to ' . $titles->{$count};
	  push(@$filter_values, 'Unique to ' . $linked_columns->{$titles->{$count}});
	}
	else{
	  $filter_labels->{$titles->{$count}} = $titles->{$count}; 
	  push(@$intersection, $titles->{$count});
	  push (@$filter_values, $titles->{$count});
	}
	$count++;
      }
      push(@$filter_values, join "_I_", @$intersection);
      $filter_labels->{join "_I_", @$intersection} = 'intersection';
    }
    elsif ($data_count == 3){
	my $pt = ((2*($width/8))**2 - ($width/8)**2)**(1/2);
	$image->arc(($width/2)-($width/8), ($height/2)+($height/8),2*$radius, 2*$radius,0,360,$diagColors->{1});
	$image->arc(($width/2)+($width/8), ($height/2)+($height/8), 2*$radius, 2*$radius,0,360,$diagColors->{2});
	$image->arc(($width/2), (($height/2)+($height/8))-$pt, 2*$radius, 2*$radius,0,360,$gold);
	
	for (my $count=1;$count<=3;$count++){
	    if (defined $linked_component){
		$filter_labels->{$linked_columns->{$titles->{$count}}} = $titles->{$count};
		push(@$intersection, $linked_columns->{$titles->{$count}});
		push(@$filter_values, $linked_columns->{$titles->{$count}});
		$filter_labels->{'Unique to ' . $linked_columns->{$titles->{$count}}} = 'Unique to ' . $titles->{$count};
		push(@$filter_values, 'Unique to ' . $linked_columns->{$titles->{$count}});
	    }
	    else{
		$filter_labels->{$titles->{$count}} = $titles->{$count};
		push(@$intersection, $titles->{$count});
		push (@$filter_values, $titles->{$count});
	    }
	}
	push(@$filter_values, join "_I_", @$intersection);
	$filter_labels->{join "_I_", @$intersection} = 'intersection ' . join ", ", values %$titles;
    }
    elsif ($data_count == 4){
	$image->arc(($width/2)-($width/8), ($height/2)+($height/8),2*$radius, 2*$radius,0,360,$diagColors->{1});
	#$image->fill(($width/2)-($width/8), ($height/2)+($height/8),$diagColors->{1});	
	$image->arc(($width/2)-($width/8), ($height/2)+($height/8),4, 4,0,360,$diagColors->{1});

	$image->arc(($width/2)+($width/8), ($height/2)+($height/8), 2*$radius, 2*$radius,0,360,$diagColors->{2});
	#$image->fill(($width/2)+($width/8), ($height/2)+($height/8),$diagColors->{2});
	$image->arc(($width/2)+($width/8), ($height/2)+($height/8), 4,4,0,360,$diagColors->{2});

	$image->arc(($width/2)-($width/8), ($height/2)-($height/8),2*$radius, 2*$radius,0,360,$diagColors->{1});
	#$image->fill(($width/2)-($width/8), ($height/2)-($height/8),$diagColors->{1});
	$image->arc(($width/2)-($width/8), ($height/2)-($height/8),4, 4,0,360,$diagColors->{1});

	$image->arc(($width/2)+($width/8), ($height/2)-($height/8), 2*$radius, 2*$radius,0,360,$diagColors->{2});
	#$image->fill(($width/2)+($width/8), ($height/2)-($height/8),$diagColors->{2});
	$image->arc(($width/2)+($width/8), ($height/2)-($height/8), 4,4,0,360,$diagColors->{2});

	return "<img src=" . $self->image->image_src().">";
    }

    push(@$filter_values,"_U_");
    $filter_labels->{"_U_"} = 'all';
    my $hover_id;
#    foreach my $group (sort {$sets->{$a} cmp $sets->{$b}} keys %$sets){
    foreach my $group (sort {$areas->{$a} cmp $areas->{$b}} keys %$areas){
      my $color = $black;
      my $hash = $mapHash->{$group};
      my $area = $areas->{$group}->{area};
      my $fill_color = $areas->{$group}->{fill_color};
      my @setCoordsY;
      if (defined $areas->{$group}->{Yrange}){
	my $Yrange = $areas->{$group}->{Yrange};
	
	foreach my $key (sort {$a<=>$b} keys %$hash){
	  push @setCoordsY, $key if ( ($key >= $Yrange->[0]) && ($key <= $Yrange->[1]) );
	}
      }
      else {
	@setCoordsY = sort {$a<=>$b} keys %$hash;
      }
      
      my $range = scalar(@setCoordsY);
      
      # figure out the spacing
      my ($count);
      if (defined $sets->{$group}){
	  $count = scalar @{$sets->{$group}};
      }
      else{
	  $count = 1;
      }
      my $padding = int( (($area*.90) / $count)**.5);
      
      (my $ptCount = my $xptCount = my $yptCount = 0);
#      $yptCount=$padding;
      $yptCount = 5;
      my $loopCount = 0;
      my $firstY = $setCoordsY[$yptCount];
      my @firstxrange = sort {$a<=>$b} @{$hash->{$firstY}};
      my $firstX = sprintf ("%.2f", ($firstxrange[0]+10) + ($xptCount * $padding));
      $image->fill($firstX,$firstY,$image->colorAllocate(@$fill_color));

      foreach my $value (@{$sets->{$group}}){
	my $yPos = $setCoordsY[$yptCount];
	my @xrange = sort {$a<=>$b} @{$hash->{$yPos}};
	my $xPos = sprintf ("%.2f", ($xrange[0]+10) + ($xptCount * $padding));
	$xptCount++;
	if (($xPos+5) + $padding > $xrange[scalar (@xrange) - 1]-1){
	  $xptCount = 0;
	  $yptCount += $padding;
	  if ($yptCount >= $range){
	    $yptCount = int(1 + ($padding/2));
	  }
	}
	
	if ($xPos>$xrange[scalar (@xrange) - 1]-1){
	  $xPos = sprintf ("%.2f", ($xrange[0]+$xrange[scalar (@xrange) - 1])/2);
	}
	
#	$image->fill($xPos,$yPos,$image->colorAllocate(@$fill_color)) if ($loopCount == 0);
	$image->arc($xPos, $yPos, 2, 2,0,360,$color);
	
	# add a hover to the point
	my $group_title = "intersection";
	$group_title = $titles->{$group} if (defined $titles->{$group});
	$hover->add_tooltip( "hover_$value", $group_title . ": " . $value );
	$hover_id = $hover->id;
	
	my $push_code = "<area shape='circle' coords='$xPos,$yPos,2' id='$value' title='$value' onmouseover='hover(event, \"hover_" . $value . "\", " . $hover->id . ");' ";
	$push_code .= "onClick='search_linked_component(event, \"" . $value . "\", " . $linked_component_id . ", \"" . 'table_' . $linked_component_id . '_operand_' . $linked_columns->{'max_level'} . "\", " . ($linked_columns->{start_col}-1) . ");'" if ( (defined $linked_component) && (defined $linked_columns) );
	$push_code .= ">";
	
	push(@$map, $push_code);
	$loopCount++;
      }
    }
    
    # create html with the graph's title
    my $combobox;
    if (defined ($linked_component)){
      $combobox .= "<b>Show in table: </b>";
      $combobox .= $cgi->popup_menu(-name     => 'filter_metagenomes' . $hover_id,
				    -id       => 'filter_metagenomes' . $hover_id ,
				    -values   => $filter_values,
				    -labels   => $filter_labels,
				    -onChange => 'filter_metagenome_table("filter_metagenomes' . $hover_id .'", ' . $linked_component_id . ', ' . $data_count . ',' . $linked_columns->{add_block} . ', ' . $linked_columns->{first_stat} . ')',
				    -default  => '_U_'
				   );
    }

#    $self->application->register_component('HelpLink', 'GroupFilterHelp' . $hover_id);
#    my $VennHelp = $self->application->component('GroupFilterHelp' . $hover_id);
#    $VennHelp->hover_width(200);
#    $VennHelp->disable_wiki_link(1);
#    $VennHelp->title('Venn Diagram Filter');
#    $VennHelp->text('You can select which section of the Venn diagram to view on the table below by selecting the appropiate section in this dropdown menu.');
#    $combobox .=  $VennHelp->output();
    
#    my $summary_table;
#    if ($data_count == 2){
#	$summary_table .= "<table>";
#	$summary_table .= "<tr><td></td><td>" . $titles->{1} . "</td><td>" . $titles->{2} , "</td></tr>";
#	$summary_table .= "<tr><td>" . $titles->{1} . "</td><td>" .
#	$summary_table .= "</td></tr></table>";
#    }

    my $graph = qq~<table><tr><td colspan='2' align='center'><b>~ . qq~</b></td></tr><tr><td><img src="~ . $self->image->image_src()  . qq~" usemap="#vennD_map~ . $hover_id . qq~"><map name="vennD_map~ . $hover_id . qq~">~.join("\n", @$map).qq~</map>~ . $hover->output() . qq~</td><td align='center' style='vertical-align:middle;'>$combobox</td></tr></table>~;

    # return html
    return $graph;

}

sub get_coords {
    my ($width, $height, $radius, $circles,$image,$black) = @_;

    # figure out the area of intersection and sizes of circles
    # declare the center for each of the circles j1,j2, k
    my $k = ($height/2);

    # establish the coordenates for the intersection area and non-intersection
    my $coords = {};
    my $mapHash = {};
    my $area = {};
    if ($circles == 1){
      my $k = ($height/2);
      my $j = ($width/2);      
      $area->{1}->{area} =  sprintf ("%.2f", PI*($radius**2));
      $area->{1}->{fill_color} = [230, 230, 250];
      my (@half1, @half2);
      for (my $deg=0;$deg<=180;$deg+=.5){
	my ($x,$y1,$y2);
	$y1 = int (($radius * sin(RAD * $deg) ) + $k);
	$y2 = int (($radius * sin(RAD * -$deg) ) + $k);
	$x = ($radius * cos(RAD * $deg) ) + $j;
	push (@half1, $y1); push (@half2, $y2);
	foreach ($y1, $y2){
	  if ( (defined @{$mapHash->{1}->{$_}}) && (scalar @{$mapHash->{1}->{$_}} > 1)){
	    $mapHash->{1}->{$_}->[1] = $x;
	  }
	  else{
	    push (@{$mapHash->{1}->{$_}}, $x);
	  }
	}
      }
      push (@{$coords->{1}}, (@half1, reverse(@half2)) );
    }
    elsif ($circles == 2){

      # figure out the area of intersection and sizes of circles
      # declare the center for each of the circles j1,j2, k
      my $k = ($height/2);
      my $j2 = ($width/2) + ($width/8);
      my $j1 = ($width/2) - ($width/8);
      my $c = (($j2-$j1)**2 + ($k-$k)**2)**(1/2);
      my $q = 2 * (acos($c/(2*$radius)));
      my $int_A = sprintf ("%.2f", ($radius**2) * ($q -  sin($q)));
      my $circA = sprintf ("%.2f", (PI*($radius**2)) - $int_A); 

      $area->{1}->{fill_color} = [230, 230, 250];
      $area->{2}->{fill_color} = [255, 228, 225];
      $area->{'1I2'}->{fill_color} = [216, 191, 216];

      for(my $i=1;$i<=3;$i++){
	if ($i == 1){
	  my (@half1, @half2);
	  for (my $deg=0;$deg<=180;$deg+=.5){
	    my ($x,$y1,$y2,$j,$tempDeg);
	    if  ($deg<=60){
	      $tempDeg=180-$deg;
	      $j = ($width/2)+($width/8);
	    }
	    else{
	      $j = ($width/2) - ($width/8);
	      $tempDeg = $deg;
	    }
	    $y1 = int (($radius * sin(RAD * $tempDeg) ) + $k);
	    $y2 = int (($radius * sin(RAD * -$tempDeg) ) + $k);
	    $x = ($radius * cos(RAD * $tempDeg) ) + $j;
	    push (@half1, $y1); push (@half2, $y2);
	    foreach ($y1, $y2){
	      if ( (defined @{$mapHash->{$i}->{$_}}) && (scalar @{$mapHash->{$i}->{$_}} > 1)){
		$mapHash->{$i}->{$_}->[1] = $x;
	      }
	      else{
		push (@{$mapHash->{$i}->{$_}}, $x);
	      }
	    }
	  }
	  push (@{$coords->{$i}}, (@half1, reverse(@half2)) );
	  $area->{$i}->{area} = $circA;
	}
	elsif ($i == 2) {
	  for (my $deg=0;$deg<=360;$deg++){
	    my ($x, $y, $j, $tempDeg);
	    if (($deg <=240) && ($deg>=120)){
	      $tempDeg = 180-$deg;
	      $j = ($width/2) - ($width/8);
	    }
	    else {
	      $j = ($width/2) + ($width/8);
			$tempDeg = $deg;
	    }
	    $x = ($radius * cos(RAD * $tempDeg) ) + $j;
	    $y = int (($radius * sin(RAD * $tempDeg) ) + $k);
	    if ( (defined @{$mapHash->{$i}->{$y}}) && (scalar @{$mapHash->{$i}->{$y}} > 1)){
	      $mapHash->{$i}->{$y}->[1] = $x;
	    }
	    else{
	      push (@{$mapHash->{$i}->{$y}}, $x);
	    }
	    push (@{$coords->{$i}}, (sprintf("%.2f",$x), sprintf("%.2f",$y)));
	  }
	  $area->{$i}->{area} = $circA;
	}
	elsif ($i == 3){
	  my (@half_1, @half_2);
	  for (my $deg=120;$deg<=240;$deg++){
	    my ($x, $y);
	    my $j2 = ($width/2) + ($width/8);
	    my $j1 = ($width/2) - ($width/8);
	    my $y_tmp = int ($radius * sin(RAD * $deg) );
	    $y = $y_tmp + $k;
	    next if (defined @{$mapHash->{'1I2'}->{$y}});
	    $x = (($radius**2 - $y_tmp**2) ** (1/2));
	    my $x2 = $j2 - $x;
	    my $x1 = $j1 + $x;
	    push(@half_1, $x2);
	    push(@half_2, $x1);
	    
	    push (@{$mapHash->{'1I2'}->{$y}}, ($x2, $x1));
	    
	  }
	  push (@{$coords->{'1I2'}}, (@half_1, reverse(@half_2)) );
	  $area->{'1I2'}->{area} = $int_A;
	}
      }
    }

    # the way the mappings and points are calculated from previous (two circles) because it was done in 
    # different times, I need to update the way the others are done.
    elsif ($circles == 3){
      # find the areas of the circles
      my $c = ($width/4);
      my $q = 2 * (acos($c/(2*$radius)));
      my $int_A = sprintf ("%.2f", ($radius**2) * ($q -  sin($q)));
      my $circA = sprintf ("%.2f", (PI*($radius**2)));

      my $var = ((3*($radius**2)) - ($c**2)/2 - $c*((3*($radius**2) - (3*($c**2)/4))**(.5)) )**(.5);
      my $int_3 = sprintf ("%.2f", (((3**(.5)/4)*($var**2)) + (3*($radius**(2) * (asin(($var/(2*$radius)))) - (($var/4)*(((4*($radius**2))-($var**2)))**(.5))))));

      my $int_2 = $int_A - $int_3;
      ($area->{1}->{area} = $area->{2}->{area} = $area->{3}->{area} = $circA - $int_A - $int_2);
      ($area->{'1I2'}->{area} = $area->{'1I3'}->{area} = $area->{'2I3'}->{area} = $int_2);
      $area->{'1I2I3'}->{area} = $int_3;

      my $points;
      my $circles;
      # trace one circle and find the other circles by rotating it and translating it
      my $k1 = ($height/2)+($height/8);
      my $minY = int($k1 + ($radius * sin(RAD * -90) ));
      my $maxY = int($k1 + ($radius * sin(RAD *  90) ));

      for (my $y1=$minY;$y1<=$maxY;$y1++){
	my $j1 = ($width/2) - ($width/8);
	my $y_tmp = $y1 - $k1;
	my $x1a = int ($j1 + ((($radius**2) - ($y_tmp**2))**(.5)));
	my $x1b = int ($j1 - ((($radius**2) - ($y_tmp**2))**(.5)));

	push (@{$circles->{'1a'}}, [$x1a,$y1]);
	push (@{$circles->{'1b'}}, [$x1b,$y1]);
	push (@{$points->{$x1a . "-" . $y1}}, '1');
	push (@{$points->{$x1b . "-" . $y1}}, '1');
	#$image->arc($x1a,$y1,4, 4,0,360,$black);
	#$image->arc($x1b,$y1,4, 4,0,360,$black);

	# figure out the positions by translation of the circles (180)
	#my $x2a = int ($x1a + ($c));
	#my $x2b = int ($x1b + ($c));
	#my $y2 = $y1;
	my $x2a = int ( ((cos(RAD * (180)) * $x1a) + (sin(RAD * (180)) * $y1)) + ($width));
	my $x2b = int ( ((cos(RAD * (180)) * $x1b) + (sin(RAD * (180)) * $y1)) + ($width));
	my $y2 = int ( ((sin(RAD * (180)) * $x1a) - (cos(RAD * (180)) * $y1)));
	push (@{$circles->{'2a'}}, [$x2a,$y2]);
	push (@{$circles->{'2b'}}, [$x2b,$y2]);
	push (@{$points->{$x2a . "-" . $y2}}, '2');
	push (@{$points->{$x2b . "-" . $y2}}, '2');
	#$image->arc($x2a,$y2,4, 4,0,360,$black);
	#$image->arc($x2b,$y2,4, 4,0,360,$black);

	# rotation of 90 degrees
	my $x3a = int ($x2a - ($c/2));
	my $x3b = int ($x2b - ($c/2));
	my $y3 = int ($y2 - ($c*7/8));
	my $x3c = int ($x1a + ($c/2));
	my $x3d = int ($x1b + ($c/2));
	#my $x3a = int(((cos(RAD * (90)) * $x1a) - (sin(RAD * (90)) * $y1)) + ($c/2) + $width);
	#my $x3b = int(((cos(RAD * (90)) * $x1b) + (sin(RAD * (90)) * $y1)) + ($c/2) + $width);
	#my $y3 = int(((sin(RAD * (90)) * $x1a) + (cos(RAD * (90)) * $y1)) + ($c/8) );
	push (@{$circles->{'3a'}}, ([$x3a,$y3],[$x3d,$y3]));
	push (@{$circles->{'3b'}}, ([$x3b,$y3],[$x3c,$y3]));
	push (@{$points->{$x3a . "-" . $y3}}, '3');
	push (@{$points->{$x3b . "-" . $y3}}, '3');
	push (@{$points->{$x3d . "-" . $y3}}, '3');
	push (@{$points->{$x3c . "-" . $y3}}, '3');
	#$image->arc($x3a,$y3,4, 4,0,360,$black);
	#$image->arc($x3b,$y3,4, 4,0,360,$black);
	
      }
      push(@{$circles->{1}}, (@{$circles->{'1a'}}, reverse @{$circles->{'1b'}}));
      push(@{$circles->{2}}, (@{$circles->{'2a'}}, reverse @{$circles->{'2b'}}));
      @{$circles->{2}} = reverse @{$circles->{2}}; # reverse the direction of the circle to go in the same direction of 1st circle
      push(@{$circles->{3}}, (@{$circles->{'3a'}}, reverse @{$circles->{'3b'}}));
      @{$circles->{3}} = reverse @{$circles->{3}}; # reverse the direction of the circle

#      my $polyline = new GD::Polyline;
#      foreach my $pt (@{$circles->{'3'}}){
#	  $polyline->addPt($pt->[0],$pt->[1]);
#      }
#      $image->polydraw($polyline,$black);

      # find the intersection pts
      my $ipts;
      foreach my $pt (keys %$points){
#	print STDERR "XY: $pt, " . join ("-", sort @{$points->{$pt}}) . "\n" if ($pt =~ /\-141/);
	my @saw;
	@{$points->{$pt}} = grep(!$saw[$_]++, @{$points->{$pt}});
	next if (scalar(@{$points->{$pt}}) < 2);
	push @{$ipts->{join ("-", sort @{$points->{$pt}})}}, $pt;
	my ($x, $y) = split (/-/, $pt);
#	print STDERR "X,Y $pt: " . join ("-", sort @{$points->{$pt}}) . "\n";
	#$image->string(gdSmallFont,$x,$y,"  " . scalar @{$ipts->{join ("-", sort @{$points->{$pt}})}} - 1 . ": " . $pt, $black);
      }
      #return (undef, undef, undef);
      
      # get the mappings for each section
      my $tracePts;
      $tracePts->{1} = [['1', IndexOf($ipts->{'1-2'}->[1],$circles->{1}), IndexOf($ipts->{'1-3'}->[1],$circles->{1})],
			['3', IndexOf($ipts->{'1-3'}->[1],$circles->{3}), IndexOf($ipts->{'2-3'}->[1],$circles->{3})],
			['2', IndexOf($ipts->{'2-3'}->[1],$circles->{2}), IndexOf($ipts->{'1-2'}->[1],$circles->{2})] ];
      $area->{1}->{fill_color} = [230, 230, 250];
      my @values = split(/-/, $ipts->{'1-3'}->[1]);
      $area->{1}->{Yrange} = [$values[1], GetYCoord($circles->{1},'y','max') ];
      

      $tracePts->{2} = [['2', IndexOf($ipts->{'2-3'}->[0],$circles->{2}), IndexOf($ipts->{'1-2'}->[1],$circles->{2})],
			['1', IndexOf($ipts->{'1-2'}->[1],$circles->{1}), IndexOf($ipts->{'1-3'}->[0],$circles->{1})],
			['3', IndexOf($ipts->{'1-3'}->[0],$circles->{3}), IndexOf($ipts->{'2-3'}->[0],$circles->{3})] ];
      $area->{2}->{fill_color} = [255, 228, 225];
      @values = split(/-/, $ipts->{'2-3'}->[0]);
      $area->{2}->{Yrange} = [$values[1], GetYCoord($circles->{2},'y','max') ];

      $tracePts->{3} = [['3', IndexOf($ipts->{'1-3'}->[1],$circles->{3}), IndexOf($ipts->{'2-3'}->[0],$circles->{3}),'origin'],
			['2', IndexOf($ipts->{'2-3'}->[0],$circles->{2}), IndexOf($ipts->{'1-2'}->[0],$circles->{2}),'origin'],
			['1', IndexOf($ipts->{'1-2'}->[0],$circles->{1}), IndexOf($ipts->{'1-3'}->[1],$circles->{1}),'origin'] ];
      $area->{3}->{fill_color} = [240, 230, 140];
      $area->{3}->{Yrange} = [GetYCoord($circles->{3},'y','min') , GetYCoord($circles->{2},'y','min') ];

      $tracePts->{'1I2'} = [['1', IndexOf($ipts->{'1-3'}->[0],$circles->{1}), IndexOf($ipts->{'1-2'}->[1],$circles->{1})],
			    ['2', IndexOf($ipts->{'1-2'}->[1],$circles->{2}), IndexOf($ipts->{'2-3'}->[1],$circles->{2})],
			    ['3', IndexOf($ipts->{'2-3'}->[1],$circles->{3}), IndexOf($ipts->{'1-3'}->[0],$circles->{3})] ];
      $area->{'1I2'}->{fill_color} = [216, 191, 216];
      @values = split(/-/, $ipts->{'1-2'}->[1]);
      $area->{'1I2'}->{Yrange} = [GetYCoord($circles->{3},'y','max'), $values[1] ];
      
      $tracePts->{'1I3'} = [['1', IndexOf($ipts->{'1-3'}->[1],$circles->{1}), IndexOf($ipts->{'1-2'}->[0],$circles->{1}),'origin'],
			    ['2', IndexOf($ipts->{'1-2'}->[0],$circles->{2}), IndexOf($ipts->{'2-3'}->[1],$circles->{2})],
			    ['3', IndexOf($ipts->{'2-3'}->[1],$circles->{3}), IndexOf($ipts->{'1-3'}->[1],$circles->{3})] ];
      $area->{'1I3'}->{fill_color} = [154, 205, 50];
      @values = split(/-/, $ipts->{'2-3'}->[1]);
      $area->{'1I3'}->{Yrange} = [GetYCoord($circles->{1},'y','min'), $values[1] ];

      $tracePts->{'2I3'} = [['2', IndexOf($ipts->{'1-2'}->[0],$circles->{2}), IndexOf($ipts->{'2-3'}->[0],$circles->{2}),'origin'],
			    ['3', IndexOf($ipts->{'2-3'}->[0],$circles->{3}), IndexOf($ipts->{'1-3'}->[0],$circles->{3})],
			    ['1', IndexOf($ipts->{'1-3'}->[0],$circles->{1}), IndexOf($ipts->{'1-2'}->[0],$circles->{1})] ];
      $area->{'2I3'}->{fill_color} = [244, 164, 96];
      @values = split(/-/, $ipts->{'1-3'}->[0]);
      $area->{'2I3'}->{Yrange} = [GetYCoord($circles->{2},'y','min'), $values[1] ];

      $tracePts->{'1I2I3'} = [['3', IndexOf($ipts->{'1-3'}->[0],$circles->{3}), IndexOf($ipts->{'2-3'}->[1],$circles->{3})],
			      ['2', IndexOf($ipts->{'2-3'}->[1],$circles->{2}), IndexOf($ipts->{'1-2'}->[0],$circles->{2})],
			      ['1', IndexOf($ipts->{'1-2'}->[0],$circles->{1}), IndexOf($ipts->{'1-3'}->[0],$circles->{1})] ];
      $area->{'1I2I3'}->{fill_color} = [192, 192, 192];
      @values = split(/-/, $ipts->{'1-2'}->[0]);
      $area->{'1I2I3'}->{Yrange} = [$values[1], GetYCoord($circles->{3},'y','max', 3)];

      foreach my $group (keys %$tracePts){
	foreach my $pts (@{$tracePts->{$group}}){
	  #print STDERR "GROUP: $group, CIRCLE " . $pts->[0] . " PTS: " . $pts->[1] . " & ". $pts->[2] . "\n";
	  my @circle_pts = @{$circles->{$pts->[0]}};

	  if ( ($pts->[1] < $pts->[2]) && (!defined($pts->[3])) ){
	    push(@{$coords->{$group}}, @circle_pts[$pts->[1] .. $pts->[2]]);
	    #$image->string(gdSmallFont,$circle_pts[$pts->[1]]->[0],$circle_pts[$pts->[1]]->[1] , $pts->[1], $black) if ($pts->[0] eq '3');
	    #$image->string(gdSmallFont,$circle_pts[$pts->[2]]->[0],$circle_pts[$pts->[2]]->[1] , $pts->[2], $black) if ($pts->[0] eq '3');
	  }
	  elsif (($pts->[2] < $pts->[1]) && (!defined($pts->[3])) ){
	    push(@{$coords->{$group}}, @circle_pts[reverse $pts->[2] .. $pts->[1]]);
	    #$image->string(gdSmallFont,$circle_pts[$pts->[1]]->[0],$circle_pts[$pts->[1]]->[1] , $pts->[1], $black) if ($pts->[0] eq '3');
	    #$image->string(gdSmallFont,$circle_pts[$pts->[2]]->[0],$circle_pts[$pts->[2]]->[1] , $pts->[2], $black) if ($pts->[0] eq '3');
	  }
	  elsif ( ($pts->[3] eq 'origin') && ($pts->[2]<$pts->[1]) ){
	    my $array_size = scalar (@circle_pts) - 1;
	    push(@{$coords->{$group}}, @circle_pts[$pts->[1] .. $array_size]);
	    push(@{$coords->{$group}}, @circle_pts[0 .. $pts->[2]]);
	  }
	  elsif ( ($pts->[3] eq 'origin') && ($pts->[1]<$pts->[2]) ){
	    my $array_size = scalar (@circle_pts) - 1;
	    push(@{$coords->{$group}}, @circle_pts[reverse 0 .. $pts->[1]]);
	    push(@{$coords->{$group}}, @circle_pts[reverse $pts->[2] .. $array_size]);
	  }
	}
	
#	my $polyline = new GD::Polyline;
#	if ($group eq "3"){
#	  foreach my $pt (@{$coords->{$group}}){
#	    $image->arc($pt->[0],$pt->[1],4, 4,0,360,$black);
#	    $polyline->addPt($pt->[0],$pt->[1]);
#	  }
#	  $image->polydraw($polyline,$black);
#	}
	
	# fill in the $mapHash variable
	foreach my $pts (@{$coords->{$group}}){
	  push (@{$mapHash->{$group}->{$pts->[1]}}, $pts->[0]);
	}
      }
    }

    return ($coords, $mapHash, $area);
}


sub IndexOf {     # pass in value, array reference
   my ( $value, $arrayref ) = @_;
   my @values =  split (/-/, $value);
   foreach my $i ( 0 .. @$arrayref-1 )  {
      return $i if ( ($arrayref->[$i]->[0] == $values[0]) && ($arrayref->[$i]->[1] == $values[1]) );
   }
}

sub GetYCoord {
    my ($circleArray, $axis, $position, $circle) = @_;
    my $i;
    
    if ($axis eq 'x') {$i=0}
    else {$i=1}

    my @axisPts;
    foreach my $pt (@$circleArray){
	push @axisPts, $pt->[$i];
    }
    my @sortedPts = sort {$a<=>$b} @axisPts;
    
    if ($position eq 'max'){
	return pop( @sortedPts);
    }
    else{
	return shift (@sortedPts);
    }
}

sub require_javascript {
    return ["$Conf::cgi_url/Html/VennDiagram.js"];
}

#sub require_css {
#    return "$Conf::cgi_url/Html/VennDiagram.css";
#}

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

sub linked_component {
    my ($self, $linked_component) = @_;

    if (defined($linked_component)) {
        $self->{linked_component} = $linked_component;
    }

    return $self->{linked_component};
}


#sub linked_column_id {
#    my ($self, $linked_column_id) = @_;
#
#    if (defined($linked_column_id)) {
#        $self->{linked_column_id} = $linked_column_id;
#    }
#
#    return $self->{linked_column_id};
#}

sub linked_columns {
    my ($self, $linked_columns) = @_;

    if (defined($linked_columns)) {
        $self->{linked_columns} = $linked_columns;
    }

    return $self->{linked_columns};
}

sub show_titles {
    my ($self, $show_titles) = @_;

    if (defined($show_titles)) {
	$self->{show_titles} = $show_titles;
    }

    return $self->{show_titles};
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

sub title {
    my ($self, $title) = @_;

    if (defined($title)) {
	$self->{title} = $title;
    }

    return $self->{title};
}

