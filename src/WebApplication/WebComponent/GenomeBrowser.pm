package WebComponent::GenomeBrowser;

# GenomeDrawer - component to create abstract images of the chromosome

# $Id: GenomeBrowser.pm,v 1.23 2009-07-17 11:30:01 paczian Exp $

use strict;
use warnings;

use DBMaster;
use FIG;
use Conf;
use BasicLocation;

use base qw( WebComponent );

1;

=pod

=head1 NAME

GenomeBrowser - component to create abstract images of the chromosome

=head1 DESCRIPTION

Creates an inline image for abstract chromosome visualization

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{width} = 800;
  $self->{highlight} = {};
  $self->{window_size} = undef;
  $self->{offset} = undef;
  $self->{data} = [];
  $self->{coloring} = 'none';
  $self->{contig_length} = "";

  $self->application->register_component('GenomeDrawer', 'GenomeBrowserGD'.$self->id());

  return $self;
}

=item * B<output> ()

Returns the html output of the GenomeBrowser component.

=cut

sub output {
  my ($self) = @_;

  # initialize application and cgi
  my $application = $self->application();
  my $cgi = $application->cgi();
  
  # check for form parameters
  my $window_size = $self->window_size() || $cgi->param('window_size') || 16000;
  if (defined($cgi->param('mid'))) {
    $self->offset($cgi->param('mid') - int($window_size / 2));
  }
  my $offset = $self->offset() || $cgi->param('offset') || 1;
  $offset--;
  if ($offset < 0) {
    $offset = 0;
  }

  # get the data
  # 0 Feature	1 Type	2 Contig	3 Start	4 Stop	5 Length	6 Function	7 Subsystem
  my $features = $self->data();

  # map the data into the needed format
  my @line_data;
  foreach my $f (@$features) {
    unless (defined($f->[8])) {
      $f->[8] = $f->[3];
    }
    unless (defined($f->[9])) {
      $f->[9] = $f->[4];
    }
    my $note = '';
    if ($f->[5] != $f->[9] - $f->[8] + 1) {
      $note = "wrap_around";
    }
    push(@line_data, { 'id' => $f->[0], 'start' => $f->[3], 'end' => $f->[4], 'type' => 'smallbox_noborder', 'title' => $f->[1] .' Feature '.$f->[0], 'description' => [ { 'title' => 'Type', 'value' => $f->[1] }, { 'title' => 'Contig', 'value' => $f->[2] }, { 'title' => 'Start', 'value' => $f->[3] }, { 'title' => 'Stop', 'value' => $f->[4] }, { 'title' => 'Length', 'value' => $f->[5]."bp" }, { 'title' => 'Function', 'value' => $f->[6] }, { 'title' => 'Subsystem', 'value' => $f->[7] } ], note => $note });
  }

  # check display style of the different feature types
  if ($window_size < 40001) {
    foreach my $item (@line_data) {
      if ($item->{'description'}->[0]->{'value'} eq 'CDS') {
	$item->{'type'} = 'arrow';
      }
    }
  }

  # check for ss coloring
  if ($self->coloring eq 'subsystem') {
    my $subsystem_colors = { 'none' => 1 };
    foreach my $item (@line_data) {
      unless (exists($subsystem_colors->{$item->{'description'}->[6]->{'value'}})) {
	$subsystem_colors->{$item->{'description'}->[6]->{'value'}} = scalar(keys(%$subsystem_colors)) + 2;
      }
      $item->{color} = $subsystem_colors->{$item->{'description'}->[6]->{'value'}};
    }
  }

  # check for highlighting
  foreach my $item (@line_data) {
    if (defined($item->{'id'}) && $self->highlight->{$item->{id}}) {
      $item->{color} = 0;
    }
    if ($item->{description}->[0]->{value} eq 'user defined') {
      $item->{color} = 0;
    }
  }

  # create onclicks
  foreach my $item (@line_data) {
    if (defined($item->{'id'})) {
      $item->{'onclick'} = "focus_feature('0', '', '".$item->{'id'}."');";
    }
  }

  # divide the data into the different strands
  my $line_data_plus_0 = [];
  my $line_data_plus_1 = [];
  my $line_data_plus_2 = [];
  my $line_data_neutral = [];
  my $line_data_minus_0 = [];
  my $line_data_minus_1 = [];
  my $line_data_minus_2 = [];

  # check for contig-end spanning features
  my @line_data2;
  foreach my $item (@line_data) {
    if ($item->{'note'}) {
      $item->{note} = undef;
      my %itemb = %{$item};
      if ($item->{start} < $item->{end}) {
	$itemb{end} = 1;
	$item->{start} = $self->{contig_length};
      } else {
	$itemb{start} = 1;
	$item->{end} = $self->{contig_length};
      }
      push(@line_data2, $item);
      push(@line_data2, \%itemb);
    } else {
      push(@line_data2, $item);
    }
  }
  @line_data = @line_data2;

  # fill the lines
  my $feature_types;
  foreach my $item (@line_data) {
    $feature_types->{$item->{'description'}->[0]->{'value'}} = 1;
    if (($item->{'description'}->[0]->{'value'} ne 'CDS') && ($item->{'description'}->[0]->{'value'} ne 'ORF')) {
      push(@$line_data_neutral, $item);
    } elsif ($item->{'start'} < $item->{'end'}) {
      my $frame = $item->{'start'} % 3;
      if ($frame == 1) {
	push(@$line_data_plus_0, $item);
      } elsif ($frame == 2) {
	push(@$line_data_plus_1, $item);
      } else {
	push(@$line_data_plus_2, $item);
      }
    } else {
      my $frame = $item->{'end'} % 3;
      if ($frame == 1) {
	push(@$line_data_minus_0, $item);
      } elsif ($frame == 2) {
	push(@$line_data_minus_1, $item);
      } else {
	push(@$line_data_minus_2, $item);
      }
    }
  }

  # create a scale
  my $scale_items = [ { type => 'line', start => $offset, end => $offset } ];
  my $diff = int($window_size / 20);
  my $curr = $offset;
  for (my $p=0; $p<20; $p++) {
    $curr += $diff;
    if ($p % 2) {
      push(@$scale_items, { type => 'line', start => $curr, end => $curr });
    } else {
      push(@$scale_items, { type => 'line', start => $curr, end => $curr, label => $curr });
    }
  }
  push(@$scale_items, { type => 'line', start => $offset + $window_size - 1, end => $offset + $window_size - 1 });

  # get the genome drawer component
  my $gd = $application->component('GenomeBrowserGD'.$self->id());

  # set genome drawer parameters
  $gd->window_size($window_size);
  $gd->width($self->width());
  $gd->show_legend(1);
  $gd->legend_width(30);

  # add a line for each strand
  $gd->add_line($line_data_plus_2, { 'basepair_offset' => $offset, short_title => '+3', no_title_hover => 1 });
  $gd->add_line($line_data_plus_1, { 'basepair_offset' => $offset, short_title => '+2', no_title_hover => 1 });
  $gd->add_line($line_data_plus_0, { 'basepair_offset' => $offset, short_title => '+1', no_title_hover => 1 });
  $gd->add_line($line_data_neutral, { 'basepair_offset' => $offset, 'line_height' => 20 });
  $gd->add_line($line_data_minus_0, { 'basepair_offset' => $offset, short_title => '-1', no_title_hover => 1 });
  $gd->add_line($line_data_minus_1, { 'basepair_offset' => $offset, short_title => '-2', no_title_hover => 1 });
  $gd->add_line($line_data_minus_2, { 'basepair_offset' => $offset, short_title => '-3', no_title_hover => 1 });
  $gd->add_line($scale_items, { basepair_offset => $offset, line_height => 20 });
  
  # return the output
  return $gd->output();
}

sub highlight {
  my ($self, $highlight) = @_;

  if (defined($highlight)) {
    $self->{highlight}->{$highlight} = 1;
  }
  
  return $self->{highlight};
}

sub window_size {
  my ($self, $window_size) = @_;

  if (defined($window_size)) {
    $self->{window_size} = $window_size;
  }

  return $self->{window_size};
}

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

sub offset {
  my ($self, $offset) = @_;

  if (defined($offset)) {
    $self->{offset} = $offset;
  }

  return $self->{offset};
}

sub data {
  my ($self, $data) = @_;
  
  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub coloring {
  my ($self, $coloring) = @_;

  if (defined($coloring)) {
    $self->{coloring} = $coloring;
  }

  return $self->{coloring};
}
