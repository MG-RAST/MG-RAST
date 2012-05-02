package WebComponent::ComparedRegions;

# ComparedRegions - component for a compares regions view

# $Id: ComparedRegions.pm,v 1.9 2009-02-05 07:33:30 parrello Exp $

use strict;
use warnings;

use FIG;
use Data::Dumper;

use base qw( WebComponent );

1;


=pod

#TITLE ComparedRegionsComponent

=head2 NAME

ComparedRegions - component for a compared regions view

=head2 DESCRIPTION

WebComponent for a compared regions view

=head2 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('GenomeDrawer','compared_region_drawer');
  $self->application->register_component('Table', 'compared_region_table');
  $self->application->register_component('TabView', 'compared_region_tabview');
  
  $self->{fig} = undef;
  $self->{table} = "";
  $self->{focus} = undef;
  $self->{region_size} = 16000;
  $self->{number_of_genomes} = 5;
  $self->{coupling_threshold} = 4;
  $self->{evalue} = 1.0e-20;
  return $self;
}

=item * B<output> ()

Returns the html output of the ComparedRegions component.

=cut

sub output {
  my ($self) = @_;
  # check parameters
  my $application = $self->application();
  my $fig = $self->fig();
  my $peg = $self->focus();
  my $region_size = $self->region_size();
  my $number_of_genomes = $self->number_of_genomes();
  my $threshold = $self->coupling_threshold();
  my $gd = $self->application->component('compared_region_drawer');
  my $table = $application->component('compared_region_table');
  my $table_data = [];
  # get the n pegs closest to the one passed
  my @closest_pegs = $self->get_closest_pegs();
  # add the selected peg to the list
  unshift(@closest_pegs, $peg);

  # store all features
  my $data = [];
  my $sup_data = [];
  my $all_genes = [];

  # iterate over the returned pegs
  foreach my $curr (@closest_pegs) { 

    # get the location
    my $loc = $fig->feature_location($curr);

    # get contig, begin and end
    my ($contig, $beg, $end) = $fig->boundaries_of($loc);

    # if there is no contig, begin or end, the data is corrupt, skip it
    if ($contig && $beg && $end) {
      my $mid = int(($beg + $end) / 2);
      my $min = int($mid - ($region_size / 2));
      my $max = int($mid + ($region_size / 2));
      my $features = [];
      my $feature_ids;

      # get the features in the defined region for each gene in the list
      ($feature_ids, undef, undef) = $fig->genes_in_region($fig->genome_of($curr),$contig,$min,$max);

      # push the focus peg to the beginning of the list
      @$feature_ids = sort { ($a ne $curr) <=> ($b ne $curr) } @$feature_ids; 

      # make sure the focus gene always points right
      my $dir = 0;
      if ($beg > $end) {
	$dir = 1;
      }
      push(@$sup_data, { dir => $dir, min => $min, max => $max, curr => $curr, mid => $mid, contig => $contig });
      push(@$data, $feature_ids);
      push(@$all_genes, @$feature_ids);
    }
  }

  # get cluster information
  my $clusters = $self->cluster_genes($all_genes, $peg);

  my $i = 0;
  foreach my $line (@$data) {
    
    # retrive supplementary data
    my $curr = $sup_data->[$i]->{curr};
    my $dir = $sup_data->[$i]->{dir};
    my $min = $sup_data->[$i]->{min};
    my $max = $sup_data->[$i]->{max};
    my $mid = $sup_data->[$i]->{mid};
    my $contig = $sup_data->[$i]->{contig};

    # get functional coupling
    my $coupled = { $curr => 1 };
    foreach my $fid (@$line) {
      my @couples = $fig->coupled_to($fid);
      if (scalar(@couples)) {
	foreach my $couple (@couples) {
	  if ($couple->[1] > $threshold) {
	    if (($couple->[0] eq $curr) || ($coupled->{$couple->[0]})) {
	      $coupled->{$fid} = $couple->[1];
	    }
	  }
	}
      }
    }
    
    # if the coupled hash contains only one entry (the focus peg) empty it
    if (scalar(keys(%$coupled)) < 2) {
      $coupled = {};
    }

    my $features = [];

    # get genome name
    my $genome_id = $fig->genome_of($curr);
    my $genome_name = $fig->genus_species($genome_id);

    # get the properties of the feature and push it into the current line for the GenomeDrawer
    my @table_entries_line;
    foreach my $fid (@$line) {
      $fid =~ /(glimmer|critica)/;
      if ($1) {
	next if ($1 eq 'glimmer' || $1 eq 'critica');
      }
      my $floc = $fig->feature_location($fid);
      my ($contig1, $beg1, $end1) = $fig->boundaries_of($fig->feature_location($fid));
      $beg1 = &in_bounds($min,$max,$beg1);
      $end1 = &in_bounds($min,$max,$end1);
      my ($beg1b, $end1b) = ($beg1, $end1);
      if ($dir) {
	($end1b, $beg1b) = ($max - $end1 + $min, $max - $beg1 + $min);
      }
      
      my $func = $fig->function_of($fid);
      my $color = $clusters->{$fid} || -1;
      if ($fid eq $curr) {
	$color = 0;
      }

      my $item  = { 'start'   => $beg1b,
		    'end'     => $end1b,
		    'title'   => 'Feature',
		    'type'    => 'arrow',
		    'zlayer'  => 2,
		    'onclick' => "location='".$application->url."?page=Annotation&feature=$fid'",
		    'description' => [ { title => 'ID', value => $fid },
				       { title => 'Function', value => $func || "" },
				       { title => 'Start', value => $beg1 },
				       { title => 'Stop', value => $end1 },
				       { title => 'Length', value => abs($beg1 - $end1)."bp" },
				       { title => 'Group', value => $color }],
		    'color'   => $color };

      push(@$features, $item);

      # push a background shading if this is functionally coupled
      my $is_fc = "";
      if ($coupled->{$fid}) {
# 	push(@$features, { 'start'   => $beg1b,
# 			   'end'     => $end1b,
# 			   'type'    => 'bigbox',
# 			   'zlayer'  => 1,
# 			   'color'   => -1 });
 	$is_fc = $coupled->{$fid};
      }

      # write information into tabular format
      my $fid_end = $fid;
      $fid_end =~ s/^fig\|\d+\.\d+\.//;
      push(@table_entries_line, [ $genome_name, "<a href='".$application->url."?page=Annotation&feature=$fid'>".$fid_end."</a>", $beg1, $end1, $func || "", $is_fc, $color ]);
    }
    @table_entries_line = sort { $a->[2] <=> $b->[2] } @table_entries_line;
    push(@$table_data, @table_entries_line);
    
    my $lines = $self->resolve_overlays($features);
    
    # add the line to the genome drawer
    my $short_name = $genome_name;
    $short_name =~ s/^(\w)\S+/$1\./;
    $short_name = substr($short_name, 0, 15);
    my $config = { 'title' => $genome_name,
		   'short_title' => $short_name,
		   'basepair_offset' => $mid - int($region_size / 2 ) };
    my $al_config = { 'basepair_offset' => $mid - int($region_size / 2 ),
		      'no_middle_line'  => 1 };
    $gd->add_line( $lines->[0], $config );
    if (scalar(@$lines) > 1) {
      my $first = 1;
      foreach my $add_line (@$lines) {
	if ($first) {
	  $first = 0;
	  next;
	}
	$gd->add_line( $add_line, $al_config );
      }
    }

    $i++;
  }

  my $visual = "";
  $visual .= $application->page->start_form('cr_form', { feature => $self->focus() });
  $visual .= "<table>";
  $visual .= "<tr><th>Number of Genomes</th><td><input type='text' name='num_genomes' value='".$self->number_of_genomes()."'></td></tr>";
  $visual .= "<tr><th>Region Size (bp)</th><td><input type='text' name='region_size' value='".$self->region_size()."'></td><td><input type='button' class='button' onclick='execute_ajax(\"compared_region\", \"cr\", \"cr_form\");' value='update graphic'></td></tr>";
  $visual .= "</table>";
  $visual .= $application->page->end_form();
  $gd->width(700);
  $gd->window_size($region_size);
  $gd->show_legend(1);
  $visual .= $gd->output();

  my $tabular = "";
  $table->show_export_button( { strip_html => 1 } );
  $table->columns( [ { name => 'Genome', sortable => 1, filter => 1, operator => 'like', operand => $fig->genome_of($self->focus()) },
		     { name => 'ID', sortable => 1 },
		     { name => 'Start', sortable => 1 },
		     { name => 'Stop', sortable => 1 },
		     { name => 'Function', sortable => 1, filter => 1 },
		     { name => 'FC', sortable => 1, filter => 1, tooltip => 'functionally coupled' },
		     { name => 'Group', sortable => 1, filter => 1, operator => 'combobox' } ] );
  $table->data( $table_data );
  $tabular = $table->output();

  my $tv = $application->component('compared_region_tabview');
  $tv->width(800);
  $tv->add_tab('Visual Region Information', $visual);
  $tv->add_tab('Tabular Region Information', $tabular);

  # return the data
  return $tv->output();
}

# returns a hash that contains a cluster number for each of the genes passed
sub cluster_genes {
  my ($self, $all_pegs, $peg) = @_;

  my $fig = $self->fig();

  my @color_sets = ();
  my %seen;
  my $conn = $self->get_connections_by_similarity($all_pegs);
  my $x;
  my $pegI;
  for (my $i=0; $i < @$all_pegs; $i++) {
    if ($all_pegs->[$i] eq $peg) {
      $pegI = $i;
    }
    if (! $seen{$i}) {
      my $cluster = [$i];
      $seen{$i} = 1;
      for (my $j=0; ($j < @$cluster); $j++) {
	$x = $conn->{$cluster->[$j]};
	foreach my $k (@$x) {
	  if (! $seen{$k}) {
	    push(@$cluster,$k);
	    $seen{$k} = 1;
	  }
	}
      }
      
      if ((@$cluster > 1) || ($cluster->[0] eq $pegI)) {
	push(@color_sets, $cluster);
      }
    }
  }
  my $i;
  for ($i=0; ($i < @color_sets) && (! &in($pegI, $color_sets[$i])); $i++) {}
  my $red_set = $color_sets[$i];
  splice(@color_sets,$i,1);
  @color_sets = sort { @$b <=> @$a } @color_sets;
  unshift(@color_sets, $red_set);
  
  my $color_sets = {};
  for ($i=0; ($i < @color_sets); $i++) {
    foreach $x (@{$color_sets[$i]}) {
      $color_sets->{$all_pegs->[$x]} = $i;
    }
  }
  
  return $color_sets;
}

# returns the n closest pegs, sorted by taxonomy
sub get_closest_pegs {
  my ($self) = @_;
  my $fig = $self->fig();
  my $peg = $self->focus();
  my $n = $self->number_of_genomes();
  my $evalue = $self->evalue();

  my($id2, $d, $peg2, $i);
  my @closest = map { $id2 = $_->id2; ($id2 =~ /^fig\|/) ? $id2 : () } $fig->sims($peg,&FIG::max(20,$n*4),$evalue,"fig",&FIG::max(20,$n*4));

  if (@closest >= ($n-1)) { 
    $#closest = $n-2 ;
  }
  my %closest = map { $_ => 1 } @closest;
  
  # there are dragons flying around...
  my @pinned_to = grep { ($_ ne $peg) && (! $closest{$_}) } $fig->in_pch_pin_with($peg);
  my $g1 = $fig->genome_of($peg);
  @pinned_to = map {$_->[1] } sort { $a->[0] <=> $b->[0] } map { $peg2 = $_; $d = $fig->crude_estimate_of_distance($g1,$fig->genome_of($peg2)); [$d,$peg2] } @pinned_to;
  
  if (@closest == ($n-1)) {
    $#closest = ($n - 2) - &FIG::min(scalar @pinned_to,int($n/2));
    for ($i=0; ($i < @pinned_to) && (@closest < ($n-1)); $i++) {
      if (! $closest{$pinned_to[$i]}) {
	$closest{$pinned_to[$i]} = 1;
	push(@closest,$pinned_to[$i]);
      }
    }
  }

  if ($fig->possibly_truncated($peg)) {
    push(@closest, &possible_extensions($fig, $peg, \@closest));
  }
  @closest = $fig->sort_fids_by_taxonomy(@closest);

  return @closest;
}

sub get_connections_by_similarity {
  my ($self, $all_pegs) = @_;
  
  my $fig = $self->fig();

  my($i,$j,$tmp,$peg,%pos_of);
  my($sim,%conn,$x,$y);
  
  for ($i=0; ($i < @$all_pegs); $i++) {
    $tmp = $fig->maps_to_id($all_pegs->[$i]);
    push(@{$pos_of{$tmp}},$i);
    if ($tmp ne $all_pegs->[$i]) {
      push(@{$pos_of{$all_pegs->[$i]}},$i);
    }
  }
  foreach $y (keys(%pos_of)) {
    $x = $pos_of{$y};
    for ($i=0; ($i < @$x); $i++) {
      for ($j=$i+1; ($j < @$x); $j++) {
	push(@{$conn{$x->[$i]}},$x->[$j]);
	push(@{$conn{$x->[$j]}},$x->[$i]);
      }
    }
  }
  
  for ($i=0; ($i < @$all_pegs); $i++) {
    my @sims = $fig->sims( $all_pegs->[$i], 500, 1.0e-5, "raw" );
    foreach $sim (@sims) {
      if (defined($x = $pos_of{$sim->id2})) {
	foreach $y (@$x) {
	  push(@{$conn{$i}},$y);
	}
      }
    }
  }
  return \%conn;
}

sub possible_extensions {
  my($fig, $peg, $closest_pegs) = @_;
  my($g,$sim,$id2,$peg1,%poss);
  
  $g = $fig->genome_of($peg);
  
  foreach $peg1 (@$closest_pegs) {
    if ($g ne $fig->genome_of($peg1)) {
      foreach $sim ($fig->sims($peg1,500,1.0e-5,"all")) {
	$id2 = $sim->id2;
	if (($id2 ne $peg) && ($id2 =~ /^fig\|$g\./) && $fig->possibly_truncated($id2)) {
	  $poss{$id2} = 1;
	}
      }
    }
  }
  return keys(%poss);
}

# helper functions
sub in_bounds {
    my($min,$max,$x) = @_;

    if     ($x < $min)     { return $min }
    elsif  ($x > $max)     { return $max }
    else                   { return $x   }
}

sub in {
  my($x,$xL) = @_;
  my($i);
  
  for ($i=0; ($i < @$xL) && ($x != $xL->[$i]); $i++) {}
  return ($i < @$xL);
}

# data r/w methods
sub fig {
  my ($self, $fig) = @_;

  if (defined($fig)) {
    $self->{fig} = $fig;
  }

  return $self->{fig};
}

sub focus {
  my ($self, $focus) = @_;

  if (defined($focus)) {
    $self->{focus} = $focus;
  }

  return $self->{focus};
}

sub region_size {
  my ($self, $region_size) = @_;

  if (defined($region_size)) {
    $self->{region_size} = $region_size;
  }

  return $self->{region_size};
}

sub number_of_genomes {
  my ($self, $number_of_genomes) = @_;

  if (defined($number_of_genomes)) {
    $self->{number_of_genomes} = $number_of_genomes;
  }

  return $self->{number_of_genomes};
}

sub coupling_threshold {
  my ($self, $coupling_threshold) = @_;

  if (defined($coupling_threshold)) {
    $self->{coupling_threshold} = $coupling_threshold;
  }

  return $self->{coupling_threshold};
}

sub evalue {
  my ($self, $evalue) = @_;

  if (defined($evalue)) {
    $self->{evalue} = $evalue;
  }

  return $self->{evalue};
}

sub resolve_overlays {
  my ($self, $features) = @_;

  my $lines = [ [ ] ];
  foreach my $feature (@$features) {
    my $resolved = 0;
    my $fs = $feature->{start};
    my $fe = $feature->{end};
    if ($fs > $fe) {
      my $x = $fs;
      $fs = $fe;
      $fe = $x;
    }
    foreach my $line (@$lines) {
      my $conflict = 0;
      foreach my $item (@$line) {
	my $is = $item->{start};
	my $ie = $item->{end};
	if ($is > $ie) {
	  my $x = $is;
	  $is = $ie;
	  $is = $x;
	}
	if ((($fs < $ie) && ($fs > $is)) || (($fe < $ie) && ($fe > $is)) || (($fs < $is) && ($fe > $ie))){
	  $conflict = 1;
	}
      }
      unless ($conflict) {
	push(@$line, $feature);
	$resolved = 1;
	last;
      }
    }
    unless ($resolved) {
      push(@$lines, [ $feature ]);
    }
  }

  return $lines;
}
