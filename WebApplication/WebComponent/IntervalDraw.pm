package WebComponent::IntervalDraw;

use strict;
use warnings;

use base qw( WebComponent );

use FIGMODEL;

1;

=pod

=head1 NAME

IntervalTable - A table of available intervals

=head1 DESCRIPTION

WebComponent for a strain select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->application->register_component('GenomeDrawer', 'interval_GD');
  $self->application->register_component('GrowthData', 'interval_draw_growth_data');

  return $self;
}

=item * B<output> ()

Returns the html output of the ModelSelect component.

=cut

sub output {
  my ($self,$width, $IDList) = @_;
  my $html;

  #Getting various packages
  my $application = $self->application();
  my $model = $application->data_handle('FIGMODEL');
  my $cgi = $application->cgi();
  #define the global strain table
  my $IntervalTableModel = $model->database()->GetDBTable("INTERVAL TABLE");
  my $StrainTableModel = $model->database()->GetDBTable("STRAIN TABLE");
  my @IDs;
  if(defined($IDList) ) {
    #Parsing the ID list
	@IDs = split(/,/,$IDList); # split on commas; 11232,523523,...
  }
  $IntervalTableModel->sort_rows('END');

  #Creating the basic table object that is the foundation of this object
  my $interval_gd = $application->component('interval_GD');
  my $growth_data = $application->component('interval_draw_growth_data');

  #Loading the data table listing the reactions in the model or in the database

  my $TwoDList;
  my $CurrentRow = 0;
  my $CurrentRowMembers;
  my $Done;
  for( my $j=0; $j < $IntervalTableModel->size(); $j++) {
  	my $Row = $IntervalTableModel->get_row($j);
  	if(!defined($Row->{"PARENT"}->[0])) {
		$CurrentRowMembers->{$Row->{"ID"}->[0]} = 1;
		$Done->{$Row->{"ID"}->[0]} = 1;
		push(@{$TwoDList->[$CurrentRow]},$Row);
  	}
  }

  my $Continue = 1;
  my $NewRowMembers;
  while($Continue == 1) {
	$CurrentRow++;
	$NewRowMembers = {};
	$Continue = 0;
	for (my $j=0; $j < $IntervalTableModel->size(); $j++) {
		my $Row = $IntervalTableModel->get_row($j);
		my $ID = $Row->{"ID"}->[0];
		my $Parent = $Row->{"PARENT"}->[0];

		if( !defined($Done->{$ID}) ) {
			if( defined($Parent) && defined($CurrentRowMembers->{$Parent}) ) {
				$NewRowMembers->{$ID} = 1;
				$Done->{$ID} = 1;
				push(@{$TwoDList->[$CurrentRow]},$Row);
			} else {
				$Continue = 1;
			}
	  	}
	}
	$CurrentRowMembers = $NewRowMembers;
  }


  my $min_start = undef;
  my $max_end = 0;
  my $interval_lines = undef;
  my $interval_order = 0;

  for(my $j=0; $j < @{$TwoDList}; $j++) {
	for(my $k=0; $k < @{$TwoDList->[$j]}; $k++) {
		my $rowhash = $TwoDList->[$j]->[$k];

		# Get relevant data from rowhash
		my $ID = $rowhash->{'ID'}->[0];
		my $start = $rowhash->{'START'}->[0];
		my $end   = $rowhash->{'END'}->[0];

		# Set the hover-description information
		my $description;
		push(@{$description}, {'title' => 'ID', 'value' => $ID});
		push(@{$description}, {'title' => 'Growth', 'value' => $growth_data->output($ID)});
		push(@{$description}, {'title' => 'Start', 'value' => $start});
		push(@{$description}, {'title' => 'End', 'value' => $end});
		my $link_list;
		push(@{$link_list}, {'link' => 'seedviewer.cgi?page=IntervalViewer&id='.$ID,
								'link_title' => 'Jump to page for interval '.$ID});

		# Set the hash for this interval to be drawn
		my $color = $growth_data->intervalNodeColor($ID);
		for(my $k=0; $k < @IDs; $k++) {
			if($IDs[$k] == $ID) { $color = [204, 0, 52]; }
		}
		my $box_hash = {'start' => $start, 'end' => $end, 'type' => 'smallbox',
			'color' => $color, 'zlayer' => 1, 'label' => $ID,
			'description' => $description, 'links_list' => $link_list};

		unless( defined($interval_lines->[$j]) ) {
			my $new_line;
			push(@{$new_line}, $box_hash);
			push(@{$interval_lines}, $new_line);
		}
		push(@{$interval_lines->[$j]}, $box_hash);

		# Update the bounds of the line
		unless(defined($min_start)) { $min_start = $start; }
		if($min_start > $start) { $min_start = $start; }
		if($max_end < $end) { $max_end = $end; }
		$interval_order++;
	}
  }

  $interval_gd->width(6200);
  $interval_gd->show_legend(1);
  $interval_gd->window_size(($max_end - $min_start + 500));
  $interval_gd->line_height(35);
  $interval_gd->display_titles(1);
  my $title = 'Primary Intervals';
  for(my $i=0; $i < @{$interval_lines}; $i++) {
	my $line_config = {'title' => $title, 'basepair_offset' => 0};
	$interval_gd->add_line($interval_lines->[$i], $line_config);
	$title = "split ".($i + 1);
  }
  $html .= "<div class='IntervalDragWrapper' style='width: " . $width . ";'>";
  $html .= "<h3>Interval Plot</h3>";
  $html .= "<div class='IntervalDraggable' style='overflow-x: scroll; overflow-y: hidden;'>";
  $html .= $interval_gd->output();
  $html .= "</div></div>";
  return $html;
}

sub require_javascript {
	return ['./Html/IntervalDraw.js', './Html/ui.draggable.js', './Html/jquery-1.3.2.min.js'];
}
