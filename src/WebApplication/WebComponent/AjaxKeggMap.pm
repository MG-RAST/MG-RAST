package WebComponent::AjaxKeggMap;

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

AjaxKeggMap - a component for creating browse-able reloading Kegg maps 

=head1 DESCRIPTION

Creates a kegg map with ajax links to reload different maps. Can be extened
by other components to have additional information printed on the map.

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
  my $self = shift->SUPER::new(@_);
  $self->application->register_component('KEGGMap', 'base_map'.$self->id);
  $self->{base_map} = $self->application->component('base_map'.$self->id);
  $self->{parent_map} = $self->application->component('base_map'.$self->id);
  $self->{ajaxComponent} = undef;
  $self->{'ajaxFunction'} = { 	fn => 'redraw', target => 'kegg_map_target'.$self->id, 
								Cgi => '',
								loading_text => 'Loading KEGG pathway...',
								post_hook => 'post_hook',
								componentId => '' };
  return $self;
}
=item * B<setup> ()

Peform setup for this map object, populating data stores

This one requires CGI 'pathway' = mapId
=cut

sub setup {
	my ($self) = @_;
	
	# Inital stuff
	my $parent = $self->application->component('base_map'.$self->id);
	my $cgi = $self->application->cgi();
	my $mapId = $cgi->param('pathway');
	if(defined($mapId)) { 
		$mapId = $parent->map_id($mapId); 
	} else { $mapId = $parent->map_id(); }

	# Do parent setup stuff	
		
		# NONE FOR BASE MAP
		
	# Do my stuff, e.g. add links to other maps
	my @mapHighlights;
	my $mapLinks = $self->{parent_map}->map_coordinates($mapId);

	my $keggdata = $self->application->data_handle('FIGMODEL')->database()->get_table("KEGGMAPDATA");

    foreach my $linkId (keys %{$mapLinks}) {

	my $param = 'pathway=' . $linkId; 
	my $link = $self->ajax_call($param);

	# if the cgi parameter "mapInNewTab" is set then open links in a new tab.
	# set the value to be the TabView id to open in the right tab component
	if($cgi->param("mapInNewTab")) {
	    my $tabViewId = $cgi->param("mapInNewTab");
	    my $ajaxHash = $self->{'ajaxFunction'};
	    my $mapData = $keggdata->get_row_by_key($linkId, "ID");
	    my $mapName;
	    if (defined($mapData)) {
		$mapName = $mapData->{'NAME'}->[0];
	    } else {
		$mapName = $linkId;
	    }

	    $link = "javascript:addTab(\"$linkId\", \"" . $mapName . "\", \"$tabViewId\", \"" . $ajaxHash->{"fn"} . "\", \"" . $ajaxHash->{"Cgi"} . "&pathway=$linkId&component=" . $ajaxHash->{"componentId"} . "&mapInNewTab=$tabViewId" . "\");";
	}
	
        my $highlight = { 	'id' => $linkId, 'link' => $link,
							'color' => [255,255,255] };
        push(@mapHighlights, $highlight);
    }
	$self->highlights(\@mapHighlights);
	return 0;
}


=item * B<highlights> ()

Geter / setter for highlight data that usees the base class
to store data and replaces conflicting highlights with
newer highlight commands...

=cut
sub highlights {
	my ($self, $newHighlights) = @_;
	# If got new highlights, add them to the base object's array of highlights
	if ( defined($newHighlights)) {
		# get the base object's array
		my $oldHighlights = $self->{parent_map}->highlights();
		unless(defined($oldHighlights)) { warn 'undefined map base or highlight function!'; }
		my $newHighlightLookup = {};
		for(my $i = 0; $i <  @{$newHighlights}; $i++) {
			# Construct a lookup by 'id' of the highlights to add.
			$newHighlightLookup->{$newHighlights->[$i]->{id}} = $i;
		}
		for(my $i = 0; $i < @{$oldHighlights}; $i++) {
			my $currKey = $oldHighlights->[$i]->{id};
			# If we find a conflict between an old highlight and a new one
			if(defined(my $j = $newHighlightLookup->{$currKey})) {
				# replace old with new and remove new from lookup hash 
				$oldHighlights->[$i] = $newHighlights->[$j];
				delete $newHighlightLookup->{$currKey};
			}
		}
		foreach my $key (keys %{$newHighlightLookup}) {
			# for all of those highlights that weren't already added, add them...
			push(@{$oldHighlights}, $newHighlights->[$newHighlightLookup->{$key}]);
		}
	}
	# Always return the current highlight set. 
	return $self->{parent_map}->highlights();
}


=item * B<ajax_call> ()
Returns the proper ajax string for this component. Takes an argument
which is ether a reference to a hash of the same structure as
$self->{'ajaxFunction'} or a scalar which is appended to the current
CGI. Returns the string.
=cut
sub ajax_call {
	my ($self, $argument) = @_;
	my $ajaxHash = $self->{'ajaxFunction'};
	my $cgi;
	if(defined($argument) and ref($argument) eq 'HASH') {
		$ajaxHash = $argument;
		$cgi = $ajaxHash->{'Cgi'}	
	} elsif(defined($argument)) {
		if($ajaxHash->{'Cgi'} ne '') { $cgi = $ajaxHash->{'Cgi'} .'&'. $argument; }
		else { $cgi = $argument; }
	}
	return "javascript:execute_ajax(\"".$ajaxHash->{'fn'}."\", \"".$ajaxHash->{'target'}.
			"\", \"$cgi\", \"".$ajaxHash->{'loading_text'}."\", 0, \"".
			$ajaxHash->{'post_hook'}."\", \"".$ajaxHash->{'componentId'}."\");";
}
			
=item * B<ajax> ()
Sets and gets ajax component.
=cut
sub ajax {
	my ($self, $ajax) = @_;
	if(defined($ajax)) {
		$self->{ajax} = $ajax;			
	}
	return $self->{ajax};
}

=item * B<base_map> ()
Gets the base KEGGMap component.
=cut
sub base_map {
	my ($self) = @_;
	return $self->{base_map};
}

=item * B<output> ()

Returns the html output of the KEGGMap component.

=cut

sub output {
	my ($self) = @_;
	unless(defined($self->{ajax})) {
		warn "Must provide an ajax component to AjaxKeggMap";
		return '';
	}
	my $html = "<div id='".$self->{'ajaxFunction'}->{'target'}."'>";	
	$html .= $self->redraw() . "</div>";
	$html .= "<script type='text/javascript'>function post_hook () {}</script>";
	return $html;
}

sub redraw {
	my ($self) = @_;
	$self->setup();
	my $html = $self->base_map()->output();
	return $html;
}



