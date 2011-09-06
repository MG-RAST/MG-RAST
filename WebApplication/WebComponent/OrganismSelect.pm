package WebComponent::OrganismSelect;

# OrganismSelect - select box for organisms

use strict;
use warnings;

use base qw( WebComponent );

use FIG;



=pod

=head1 NAME

OrganismSelect - a select box for organisms

=head1 DESCRIPTION

WebComponent for an organism select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('FilterSelect', 'OrgSelect'.$self->id);
  $self->{multiple} = 0;
  $self->{blacklist} = {};
  $self->{name} = 'organism';

  return $self;
}

=item * B<output> ()

Returns the html output of the OrganismSelect component.

=cut

my $sequenceID = 0;

sub output {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user();
  my $fig = $application->data_handle('FIG');
  my $retVal;

  my $sprout = $fig->{sprout};
  if ($sprout) {
    my $name = $self->name;
    # A complete hack here, because I'm getting desperate. We use the Sprout Genome
    # control if we have one.
    $retVal = $sprout->GenomeMenu(name => $name, multiSelect => $self->multiple,
                                  id => "${name}_GM_$sequenceID");
    $sequenceID++;
  } else {

    my $genome_info = $fig->genome_info();
    my $genomes  = [];
    my $handled = {};

    # hash the attributes
    foreach my $genome (@$genome_info) {
      $handled->{$genome->[0]} = 1;
      unless ($self->blacklist->{$genome->[0]}) {
        push(@$genomes, { id         => $genome->[0],
                          name       => $genome->[1],
                          size_dna   => $genome->[2],
                          maindomain => $genome->[3],
                          pegs       => $genome->[4],
                          rnas       => $genome->[5],
                          complete   => $genome->[6],
                          taxonomy   => $genome->[7] });
      }
    }

    # get the list of public genomes
    my $rast = $application->data_handle('RAST');
    if ($rast && $user) {
      my @jobs = $rast->Job->get_jobs_for_user_fast($user, 'view', 1);
      foreach my $j (@jobs) {
	next if $handled->{$j->{genome_id}};
	unless ($self->blacklist->{$j->{genome_id}}) {
	  push(@$genomes, { id         => $j->{genome_id},
			    name       => "Private: ".$j->{genome_name},
			    size_dna   => $j->{bp_count},
			    maindomain => 'Bacteria',
			    pegs       => 0,
			    rnas       => 0,
			    complete   => 1,
			    taxonomy   => '' });
	}
      }
    }
    
    # sort list alphabetically
    @$genomes = sort { ($b->{name} =~ /^Private\: /) cmp ($a->{name} =~ /^Private\: /) || lc($a->{name}) cmp lc($b->{name}) } @$genomes;
    
    # initialize the infos for the select box
    my $values = [];
    my $labels = [];
    my $attributes = [ { name => 'Domains',
                         possible_values => [ [ 'Archaea', 1 ],
                                              [ 'Bacteria', 1 ],
                                              [ 'Environmental Sample', 0 ],
                                              [ 'Eukaryota', 1 ],
                                              [ 'Plasmid', 0 ],
                                              [ 'Virus', 0 ] ],
                         values => [] },
                       { name => 'Completeness',
                         possible_values => [ [ 'complete', 1 ],
                                              [ 'incomplete', 0 ],
                                              [ 'fragment', 0 ] ],
                         values => [] },
                       { name => 'genome id',
                         sort_attribute => 1,
                         values => [] },
                       { name => 'phylogeny',
                         sort_attribute => 1,
                         values => [] },
                     ];
  
    # initialize select box
    my $select_box = $application->component('OrgSelect'.$self->id);
    $select_box->name($self->name());
    if ($self->width()) {
      $select_box->width($self->width);
    }
    $select_box->multiple($self->multiple());
    
    # put public organisms into the list
    my $d2l = { 'Archaea' => 'A',
                'Bacteria' => 'B',
                'Environmental Sample' => 'S',
                'Eukaryota' => 'E',
                'Plasmid' => 'P',
                'Virus' => 'V' };
    my $statistics = { 'Archaea' => 0,
                       'Bacteria' => 0,
                       'Environmental Sample' => 0,
                       'Eukaryota' => 0,
                       'Plasmid' => 0,
                       'Virus' => 0 };
    foreach my $genome (@$genomes) {
      $statistics->{$genome->{maindomain}}++;
      push(@$values, $genome->{id});
      push(@$labels, $genome->{name} . " [" . $d2l->{$genome->{maindomain}} . "] (" . $genome->{id} . ")");
      push(@{$attributes->[0]->{values}}, $genome->{maindomain});
      my $complete = 'incomplete';
      if ($genome->{complete} eq 1) {
        $complete = 'complete';
      } elsif ($genome->{complete} eq 2) {
        $complete = 'fragment';
      }
      push(@{$attributes->[1]->{values}}, $complete);
      push(@{$attributes->[2]->{values}}, $genome->{id});
      push(@{$attributes->[3]->{values}}, $genome->{taxonomy});
    }
    $self->statistics($statistics);
    
    # fill the select box
    $select_box->values($values);
    $select_box->labels($labels);
    $select_box->attributes($attributes);
    $select_box->size(11);
  
    # build the content of the component
    $select_box->auto_place_attribute_boxes(0);
    $retVal = "<table><tr><td>".$select_box->output()."</td><td>";
    my $boxes = $select_box->get_attribute_boxes();
    $retVal .= $boxes->{Completeness}.$boxes->{sort}."</td><td>".$boxes->{Domains};
    $retVal .= "</td></tr></table>";
  }
  return $retVal;
}

sub statistics {
  my ($self, $statistics) = @_;

  if (defined($statistics)) {
    $self->{statistics} = $statistics;
  }

  return $self->{statistics};
}

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

sub name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name} = $name;
  }

  return $self->{name};
}

sub multiple {
  my ($self, $multiple) = @_;

  if (defined($multiple)) {
    $self->{multiple} = $multiple;
  }

  return $self->{multiple};
}

sub blacklist {
  my ($self, $blacklist) = @_;

  if (defined($blacklist)) {
    $self->{blacklist} = $blacklist;
  }

  return $self->{blacklist};
}

1;
