package WebColors;

1;

use strict;
use warnings;

=pod

=head1 NAME

WebColors - returns different color sets for consistant color usage in the web

=head1 DESCRIPTION

Web colors has a set of color palettes for different purposes. These palettes are
represented by sets RGB values.

=head1 METHODS

=over 4


=item * B<hsl_to_rgb> ()

Converts a HSL (Hue, Saturation, Lightness) representation of color into
a RGB representation. See en.wikipedia.org/wiki/HSL_and_HSV for formula.
Input is a reference to a list of numbers [$h, $s, $l] where $h ranges
from [0, 360), and both $s and $l range from [0,1]. Output is a reference
to a list of numbers [$r, $g, $b] each ranging from [0, 256)

=cut

sub hsl_to_rgb {
	my ($hsl) = @_;
	if(@{$hsl} != 3) { return undef; }
	my ($h, $s, $l) = @{$hsl};
	if($s == 0) { return [$l, $l, $l] }
	$h = ($h % 360) / 360;
	my ($q, $p, $rgb);
	if( $l < 0.5 ) { $q = $l * (1 + $s); }
	else { $q = $l + $s - ($l * $s); }
	$p = 2 * $l - $q;
	push(@{$rgb}, $h + (1/3));
	push(@{$rgb}, $h);	
	push(@{$rgb}, $h - (1/3));
	for(my $z=0; $z<@{$rgb}; $z++){
		if($rgb->[$z] < 0) { $rgb->[$z] = $rgb->[$z] + 1 } 
		elsif($rgb->[$z] > 1) { $rgb->[$z] = $rgb->[$z] - 1 } 
			
		if($rgb->[$z] < (1/6)) { $rgb->[$z] = $p + (($q-$p)*6*$rgb->[$z]); }
		elsif($rgb->[$z] < 0.5) { $rgb->[$z] = $q; }
		elsif($rgb->[$z] < (2/3)) { $rgb->[$z] = $p + (($q-$p)*6*((2/3) - $rgb->[$z])); }
		else { $rgb->[$z] = $p; }
		# Scale rgb values into 256 range and round.	
		$rgb->[$z] = int( 0.5 + (255 * $rgb->[$z]));
	}
	return $rgb;
}

=item * B<rgb_to_hsl> ()

Converts a RGB representation of color into a HSL representation.
See en.wikipedia.org/wiki/HSL_and_HSV for formula.
Input is a reference to a list of numbers [$r, $g, $b] each in range
[0, 256). Output is a reference to a list of numbers [$h, $s, $l]
where $h ranges from [0, 360), and both $s and $l range from [0,1].

=cut

sub rgb_to_hsl {
	my ($rgb) = @_;
	if(@{$rgb} != 3) { return undef; }
	my $max = 0;
	my $min = 1;
	for(my $i=0; $i<@{$rgb}; $i++) {
		$rgb->[$i] /= 256; # scale into [0,1]
		$min = $rgb->[$i] if $rgb->[$i] < $min;
		$max = $rgb->[$i] if $rgb->[$i] > $max;	
	}
	my ($r, $g, $b) = @{$rgb};
	my ($h, $s, $l);
	if( $max == $min ) {
		$h = 0;
	} elsif( $max == $r ) {
		$h = (60 * ($g - $b) / ($max - $min) + 360) % 360;
	} elsif( $max == $g ) {
		$h = (60 * ($b - $r) / ($max - $min)) + 120;
	} else { $h = (60 * ($r - $g) / ($max - $min)) + 240; }
	
	$l = 0.5 * ( $max + $min );
	
	if( $max == $min ) { 
		$s = 0;
	} elsif( $l <= 0.5 ) {
		$s = ($max - $min) / ($max + $min);
	} else { 
		$s = ($max - $min) / (2 - ($max + $min));
	}
	return [$h, $s, $l];	
}
	
=item * B<get_colors> ()

The first implemented color method, still in here for backward compatability.
You should be using get_palette instead.

=cut

sub get_colors {

  my $colors =  [ [ 255, 255, 255 ],
		  [ 0, 0, 0 ],
		  [ 235, 5, 40 ],
		  [ 200, 200, 200 ],
		  [ 50, 255, 50 ],
		  [ 60, 60, 190 ],
		  [ 145, 175, 160 ],
		  [ 224, 133, 15 ],
		  [ 0, 0, 155 ],
		  [ 255, 221, 0 ],
		  [ 0, 155, 155 ],
		  [ 200, 100, 200 ],
		  [ 27, 133, 52 ],
		  [ 135, 65, 65 ],
		  [ 0, 90, 255 ],
		  [ 95, 100, 100 ],
		  [ 80, 210, 150 ],
		  [ 225, 250, 160 ],
		  [ 170, 30, 145 ],
		  [ 255, 215, 125 ],
		  [ 140, 165, 210 ],
		  [ 160, 15, 250 ],
		  [ 45, 155, 185 ],
		  [ 170, 205, 120 ],
		  [ 30, 60, 190 ],
		  [ 115, 175, 160 ],
		  [ 194, 133, 15 ],
		  [ 0, 0, 125 ],
		  [ 225, 221, 0 ],
		  [ 255, 0, 0 ],
		  [ 0, 255, 0 ],
		  [ 0, 0, 255 ],
		  [ 255, 255, 0 ],
		  [ 0, 255, 255 ],
		  [ 255, 0, 255 ],
		  [ 255, 127, 0 ],
		  [ 255, 0, 127 ],
		  [ 0, 255, 127 ],
		  [ 127, 0, 255 ],
		  [ 127, 255, 0 ],
		  [ 0, 127, 255 ],
		  [ 255, 127, 127 ],
		  [ 127, 255, 127 ],
		  [ 127, 127, 255 ],
		  [ 0, 0, 127 ],
		  [ 127, 0, 0 ],
		  [ 0, 127, 0 ],
		  [ 127, 127, 0 ],
		  [ 127, 0, 127 ],
		  [ 0, 127, 127 ],
		  [ 255, 127, 255 ],
		  [ 255, 255, 127 ],
		  [ 127, 255, 255 ],
		  [ 223, 1, 17],
		  [ 255, 32, 0],
		  [ 255, 51, 0],
		  [ 255, 102, 0],
		  [ 255, 153, 0],
		  [ 255, 204, 0],
		  [ 255, 255, 0],
		  [ 204, 255, 0],
		  [ 102, 255, 0],
		  [ 0, 255, 0],
		  [ 102, 102, 255],
		  [173, 216, 230],
		  [135, 206, 250],
		  [30, 144, 255],
		  [0, 0, 255],
		  [0, 0, 139] ];
  
  return $colors;
}

=item * B<get_palette> ()

When passed the name of a palette, will return it. A palette is a set of
RGB values. Current options are

'special' - special colors like white, black, background shading, highlighting and such.

'vitamins' - 10 vital colors, well suited for a scale. Ranged from red to blue

'many' - 46 hopefully distiguishable colors for e.g. piecharts, arrowsets

'many_except_gray' - same as 'many', except gray is removed so it can be used for other purposes
=cut

sub get_palette {
  my ($name) = @_;

  if ($name eq 'special') {
    return [ [ 255, 255, 255 ], # white
	     [ 0, 0, 0 ],       # black
	     [ 200, 200, 200 ], # background shading
	     [ 235, 5, 40 ],    # highlight
	     [ 60, 60, 190 ],   # foreground
	     [ 50, 255, 50 ]];  # special
  }
  
  elsif ($name eq 'vitamins') {
    return [ [ 223, 1, 17],
	     [ 255, 32, 0],
	     [ 255, 51, 0],
	     [ 255, 102, 0],
	     [ 255, 153, 0],
	     [ 255, 204, 0],
	     [ 255, 255, 0],
	     [ 204, 255, 0],
	     [ 102, 255, 0],
	     [ 0, 255, 0] ];
  }

  elsif ($name eq 'many') {
    return [ [ 224, 133, 15 ],
	     [ 0, 0, 155 ],
	     [ 255, 221, 0 ],
	     [ 0, 155, 155 ],
	     [ 200, 100, 200 ],
	     [ 27, 133, 52 ],
	     [ 135, 65, 65 ],
	     [ 0, 90, 255 ],
	     [ 95, 100, 100 ],
	     [ 80, 210, 150 ],
	     [ 225, 250, 160 ],
	     [ 170, 30, 145 ],
	     [ 255, 215, 125 ],
	     [ 140, 165, 210 ],
	     [ 160, 15, 250 ],
	     [ 45, 155, 185 ],
	     [ 170, 205, 120 ],
	     [ 30, 60, 190 ],
	     [ 115, 175, 160 ],
	     [ 194, 133, 15 ],
	     [ 0, 0, 125 ],
	     [ 225, 221, 0 ],
	     [ 255, 0, 0 ],
	     [ 0, 255, 0 ],
	     [ 0, 0, 255 ],
	     [ 255, 255, 0 ],
	     [ 0, 255, 255 ],
	     [ 255, 0, 255 ],
	     [ 255, 127, 0 ],
	     [ 255, 0, 127 ],
	     [ 0, 255, 127 ],
	     [ 127, 0, 255 ],
	     [ 127, 255, 0 ],
	     [ 0, 127, 255 ],
	     [ 255, 127, 127 ],
	     [ 127, 255, 127 ],
	     [ 127, 127, 255 ],
	     [ 0, 0, 127 ],
	     [ 127, 0, 0 ],
	     [ 0, 127, 0 ],
	     [ 127, 127, 0 ],
	     [ 127, 0, 127 ],
	     [ 0, 127, 127 ],
	     [ 255, 127, 255 ],
	     [ 255, 255, 127 ],
	     [ 127, 255, 255 ] ];
  }
  elsif ($name eq 'many_except_gray' || $name eq 'many_except_grey') {
    return [ [ 224, 133, 15 ],
	     [ 0, 0, 155 ],
	     [ 255, 221, 0 ],
	     [ 0, 155, 155 ],
	     [ 200, 100, 200 ],
	     [ 27, 133, 52 ],
	     [ 135, 65, 65 ],
	     [ 0, 90, 255 ],
	     [ 80, 210, 150 ],
	     [ 225, 250, 160 ],
	     [ 170, 30, 145 ],
	     [ 255, 215, 125 ],
	     [ 140, 165, 210 ],
	     [ 160, 15, 250 ],
	     [ 45, 155, 185 ],
	     [ 170, 205, 120 ],
	     [ 30, 60, 190 ],
	     [ 115, 175, 160 ],
	     [ 194, 133, 15 ],
	     [ 0, 0, 125 ],
	     [ 225, 221, 0 ],
	     [ 255, 0, 0 ],
	     [ 0, 255, 0 ],
	     [ 0, 0, 255 ],
	     [ 255, 255, 0 ],
	     [ 0, 255, 255 ],
	     [ 255, 0, 255 ],
	     [ 255, 127, 0 ],
	     [ 255, 0, 127 ],
	     [ 0, 255, 127 ],
	     [ 127, 0, 255 ],
	     [ 127, 255, 0 ],
	     [ 0, 127, 255 ],
	     [ 255, 127, 127 ],
	     [ 127, 255, 127 ],
	     [ 127, 127, 255 ],
	     [ 0, 0, 127 ],
	     [ 127, 0, 0 ],
	     [ 0, 127, 0 ],
	     [ 127, 127, 0 ],
	     [ 127, 0, 127 ],
	     [ 0, 127, 127 ],
	     [ 255, 127, 255 ],
	     [ 255, 255, 127 ],
	     [ 127, 255, 255 ] ];
  }
  elsif ($name eq 'gradient') {
    return [[204,34,0],
	    [238,85,0],
	    [204,102,0],
	    [204,153,0],
	    [187,204,0],
	    [119,204,0],
	    [34,204,0], 
	    [0,204,187],
	    [0,170,204],
	    [0,119,204],
	    [0,68,204]];
  }
  elsif ($name eq 'excel') {
    return [[255,0,0],
	    [0,128,0],
	    [0,0,128],
	    [128,128,0],
	    [128,0,128],
	    [192,192,192],
	    [128,128,128],
	    [153,153,255],
	    [153,51,102],
	    [255,255,204],
	    [102,0,102],
	    [255,128,128],
	    [0,102,204],
	    [204,204,255],
	    [255,0,255],
	    [255,255,0],
	    [0,255,255],
	    [128,0,128],
	    [128,0,0],
	    [0,128,128],
	    [0,0,255],
	    [0,204,204],
	    [204,255,255],
	    [204,255,204],
	    [255,255,153],
	    [153,204,255],
	    [255,153,204],
	    [204,153,255],
	    [255,204,153],
	    [51,102,255],
	    [51,204,204],
	    [153,204,0],
	    [255,204,0],
	    [255,153,0],
	    [255,102,0],
	    [102,102,153],
	    [150,150,150],
	    [0,51,102],
	    [51,153,102],
	    [0,51,0],
	    [51,51,0],
	    [153,51,0],
	    [153,51,102],
	    [51,51,153],
	    [51,51,51]];
  }
  elsif ($name eq 'varied') {
    return [
		  #[ 255,250,100 ], #yellow
		  [ 100,149,237 ], #pale blue
		  [ 178,54,54 ], #brick red
		  [ 60,179,113 ], #foam green
		  [ 205,133,63 ], #pale orange
		  [ 0,255,255 ], #aqua
		  [ 128,0,128 ] #purple
        ];
  }
  elsif ($name eq 'circle') {
    return [
	    [ 255, 0, 0],
	    [ 255, 108, 0 ],
	    [ 255, 168, 0 ],
	    [ 255, 228, 0 ],
	    [ 228, 255, 0 ],
	    [ 156, 255, 0 ],
	    [ 54, 255, 0 ],
	    [ 0, 255, 192 ],
	    [ 0, 228, 255 ],
	    [ 0, 144, 255 ],
	    [ 0, 84, 255 ],
	    [ 18, 0, 255 ],
	    [ 102, 0, 255 ],
	    [ 174, 0, 255 ],
	    [ 246, 0, 255 ],
	    [ 255, 0, 162 ],
	    [ 143, 0, 0 ],
	    [ 143, 64, 0 ],
	    [ 143, 121, 0 ],
	    [ 124, 143, 0 ],
	    [ 64, 143, 0 ],
	    [ 0, 143, 67 ],
	    [ 0, 138, 143 ],
	    [ 0, 87, 143 ],
	    [ 0, 10, 143 ],
	    [ 50, 0, 143 ],
	    [ 108, 0, 143 ],
	    [ 143, 0, 118 ]
	   ];
  }

  return undef;
}

sub color_to_rgb {
  my ($color) = @_;

  my $mapping = { aliceblue => [ 240,248,255 ],
		  darkslategray => [ 47,79,79 ],
		  lightsalmon => [ 255,160,122 ],
		  palevioletred => [ 219,112,147 ],
		  antiquewhite => [ 250,235,215 ],
		  darkturquoise => [ 0,206,209 ],
		  lightseagreen => [ 32,178,170 ],
		  papayawhip => [ 255,239,213 ],
		  aqua => [ 0,255,255 ],
		  darkviolet => [ 148,0,211 ],
		  lightskyblue => [ 135,206,250 ],
		  peachpuff => [ 255,239,213 ],
		  aquamarine => [ 127,255,212 ],
		  deeppink => [ 255,20,147 ],
		  lightslategray => [ 119,136,153 ],
		  peru => [ 205,133,63 ],
		  azure => [ 240,255,255 ],
		  deepskyblue => [ 0,191,255 ],
		  lightsteelblue => [ 176,196,222 ],
		  pink => [ 255,192,203 ],
		  beige => [ 245,245,220 ],
		  dimgray => [ 105,105,105 ],
		  lightyellow => [ 255,255,224 ],
		  plum => [ 221,160,221 ],
		  bisque => [ 255,228,196 ],
		  dodgerblue => [ 30,144,255 ],
		  lime => [ 0,255,0 ],
		  powderblue => [ 176,224,230 ],
		  black => [ 0,0,0 ],
		  firebrick => [ 178,34,34 ],
		  limegreen => [ 50,205,50 ],
		  purple => [ 128,0,128 ],
		  blanchedalmond => [ 255,255,205 ],
		  floralwhite => [ 255,250,240 ],
		  linen => [ 250,240,230 ],
		  red => [ 255,0,0 ],
		  blue => [ 0,0,255 ],
		  forestgreen => [ 34,139,34 ],
		  magenta => [ 255,0,255 ],
		  rosybrown => [ 188,143,143 ],
		  blueviolet => [ 138,43,226 ],
		  fuchsia => [ 255,0,255 ],
		  maroon => [ 128,0,0 ],
		  royalblue => [ 65,105,225 ],
		  brown => [ 165,42,42 ],
		  gainsboro => [ 220,220,220 ],
		  mediumaquamarine => [ 102,205,170 ],
		  saddlebrown => [ 139,69,19 ],
		  burlywood => [ 222,184,135 ],
		  ghostwhite => [ 248,248,255 ],
		  mediumblue => [ 0,0,205 ],
		  salmon => [ 250,128,114 ],
		  cadetblue => [ 95,158,160 ],
		  gold => [ 255,215,0 ],
		  mediumorchid => [ 186,85,211 ],
		  sandybrown => [ 244,164,96 ],
		  chartreuse => [ 127,255,0 ],
		  goldenrod => [ 218,165,32 ],
		  mediumpurple => [ 147,112,219 ],
		  seagreen => [ 46,139,87 ],
		  chocolate => [ 210,105,30 ],
		  gray => [ 128,128,128 ],
		  mediumseagreen => [ 60,179,113 ],
		  seashell => [ 255,245,238 ],
		  coral => [ 255,127,80 ],
		  green => [ 0,128,0 ],
		  mediumslateblue => [ 123,104,238 ],
		  sienna => [ 160,82,45 ],
		  cornflowerblue => [ 100,149,237 ],
		  greenyellow => [ 173,255,47 ],
		  mediumspringgreen => [ 0,250,154 ],
		  silver => [ 192,192,192 ],
		  cornsilk => [ 255,248,220 ],
		  honeydew => [ 240,255,240 ],
		  mediumturquoise => [ 72,209,204 ],
		  skyblue => [ 135,206,235 ],
		  crimson => [ 220,20,60 ],
		  hotpink => [ 255,105,180 ],
		  mediumvioletred => [ 199,21,133 ],
		  slateblue => [ 106,90,205 ],
		  cyan => [ 0,255,255 ],
		  indianred => [ 205,92,92 ],
		  midnightblue => [ 25,25,112 ],
		  slategray => [ 112,128,144 ],
		  darkblue => [ 0,0,139 ],
		  indigo => [ 75,0,130 ],
		  mintcream => [ 245,255,250 ],
		  snow => [ 255,250,250 ],
		  darkcyan => [ 0,139,139 ],
		  ivory => [ 255,240,240 ],
		  mistyrose => [ 255,228,225 ],
		  springgreen => [ 0,255,127 ],
		  darkgoldenrod => [ 184,134,11 ],
		  khaki => [ 240,230,140 ],
		  moccasin => [ 255,228,181 ],
		  steelblue => [ 70,130,180 ],
		  darkgray => [ 169,169,169 ],
		  lavender => [ 230,230,250 ],
		  navajowhite => [ 255,222,173 ],
		  tan => [ 210,180,140 ],
		  darkgreen => [ 0,100,0 ],
		  lavenderblush => [ 255,240,245 ],
		  navy => [ 0,0,128 ],
		  teal => [ 0,128,128 ],
		  darkkhaki => [ 189,183,107 ],
		  lawngreen => [ 124,252,0 ],
		  oldlace => [ 253,245,230 ],
		  thistle => [ 216,191,216 ],
		  darkmagenta => [ 139,0,139 ],
		  lemonchiffon => [ 255,250,205 ],
		  olive => [ 128,128,0 ],
		  tomato => [ 253,99,71 ],
		  darkolivegreen => [ 85,107,47 ],
		  lightblue => [ 173,216,230 ],
		  olivedrab => [ 107,142,35 ],
		  turquoise => [ 64,224,208 ],
		  darkorange => [ 255,140,0 ],
		  lightcoral => [ 240,128,128 ],
		  orange => [ 255,165,0 ],
		  violet => [ 238,130,238 ],
		  darkorchid => [ 153,50,204 ],
		  lightcyan => [ 224,255,255 ],
		  orangered => [ 255,69,0 ],
		  wheat => [ 245,222,179 ],
		  darkred => [ 139,0,0 ],
		  lightgoldenrodyellow => [ 250,250,210 ],
		  orchid => [ 218,112,214 ],
		  white => [ 255,255,255 ],
		  darksalmon => [ 233,150,122 ],
		  lightgreen => [ 144,238,144 ],
		  palegoldenrod => [ 238,232,170 ],
		  whitesmoke => [ 245,245,245 ],
		  darkseagreen => [ 143,188,143 ],
		  lightgrey => [ 211,211,211 ],
		  palegreen => [ 152,251,152 ],
		  yellow => [ 255,255,0 ],
		  darkslateblue => [ 72,61,139 ],
		  lightpink => [ 255,182,193 ],
		  paleturquoise => [ 175,238,238 ],
		  yellowgreen => [ 154,205,50 ] };

  return $mapping->{$color};
}

sub rgb_to_hex
{
    # expect an array reference of three values between 0 and 255
    my ($rgb) = @_;
    my $hex_string = "";

    foreach my $val (@$rgb)
    {
	if ($val == 0) {
	    $hex_string .= "00";
	}
	else {
	    my $hex = "0123456789ABCDEF";
	    $hex_string .= substr($hex, ($val-($val%16))/16 , 1);
	    $hex_string .= substr($hex, ($val%16) , 1);
	}
    }

    return $hex_string;
}
