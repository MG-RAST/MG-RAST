package WebComponent::FilterSelect;

# FilterSelect - component for a list filtered by an infix search

# $Id: FilterSelect.pm,v 1.15 2011-06-13 09:44:01 paczian Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;


=pod

=head1 NAME

FilterSelect - component for a list filtered by an infix search

=head1 DESCRIPTION

WebComponent for a list filtered by an infix search

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->{html_id} = $self->id(); 
  $self->{values} = [];
  $self->{labels} = [];
  $self->{name} = "filter_select";
  $self->{attributes} = [];
  $self->{size} = 8;
  $self->{width} = 300;
  $self->{multiple} = 0;
  $self->{dropdown} = 0;
  $self->{auto_place_attribute_boxes} = 1;
  $self->{attribute_boxes} = {};
  $self->{default} = undef;
  $self->{initial_text} = '';

  return $self;
}

=item * B<output> ()

Returns the html output of the FilterSelect component.

=cut

sub output {
  my ($self) = @_;

  # no values, no select box
  unless ($self->values) {
    die "Filter Select called without values";
  }

  # check for attributes
  my $values_string = join("~", @{$self->values});
  $values_string =~ s/'/#/g;
  my $labels_string = join("~", @{$self->labels});
  $labels_string =~ s/'/#/g;
  my $attribute_values = [];
  my $attribute_names = [];
  my $attribute_types = [];
  my $sort_attributes = [];
  foreach my $attribute (@{$self->attributes}) {
    push(@$attribute_values, join("~", map { defined($_) ? $_ : '' } @{$attribute->{values}}));
    push(@$attribute_names, $attribute->{name});
    if ($attribute->{sort_attribute}) {
      push(@$sort_attributes, $attribute->{name});
      push(@$attribute_types, 'sort');
    } else {
      push(@$attribute_types, 'filter');
    }
  }
  $attribute_values = join("|", @$attribute_values);
  $attribute_types = join("~", @$attribute_types);
  $attribute_names = join("~", @$attribute_names);
  $attribute_values =~ s/'//g;

  # create hidden fields
  my $default_value = "";
  if (defined($self->default())) {
    $default_value = $self->default();
  }
  my $select = "<input type='hidden' value='" . $values_string . "' id='filter_select_values_" . $self->html_id() . "'>\n";
  $select .= "<input type='hidden' value='" . $labels_string . "' id='filter_select_labels_" . $self->html_id() . "'>\n";
  $select .= "<input type='hidden' value='$default_value' id='filter_select_default_" . $self->html_id() . "'>\n";

  # check if attribute fields are neccessary
  if (scalar(@{$self->attributes})) {
    $select .= "<input type='hidden' value='" . $attribute_names . "' id='filter_select_attribute_names_" . $self->html_id() . "'>\n";
    $select .= "<input type='hidden' value='" . $attribute_values . "' id='filter_select_attribute_values_" . $self->html_id() . "'>\n";
    $select .= "<input type='hidden' value='" . $attribute_types . "' id='filter_select_attribute_types_" . $self->html_id() . "'>\n";
  }

  my $default_text = "start typing to narrow selection";
  if ($self->dropdown()) {
    $select .= "<input type='hidden' value='yes' id='filter_select_dropdown_" . $self->html_id() . "'>\n";
    $default_text = "click to view and type to filter";
  }
  if (defined($self->{initialtext})) {
  	$default_text = $self->{initialtext};
  }
  
  # create the input field and the select box
  my $multiple = "";
  if ($self->multiple) {
    $multiple = " multiple=multiple";
  }
  $select .= "<input type='hidden' id='filter_initial_text_" . $self->html_id() . "' value='$default_text'>\n";
  $select .= "<input type='text' style='width: " . $self->width() . "px;' name='" . $self->name() . "_text' onkeydown='textbox_key_down(event, \"" . $self->html_id() . "\");' onkeyup='textbox_key_up(event, \"" . $self->html_id() . "\");' id='filter_select_textbox_" . $self->html_id() . "' value='".$default_text."'><br/>\n";

  # hide the select if dropdown
  $select .= "<div id='filter_select_" . $self->html_id() . "_div'" . ($self->dropdown() ? " style='display:none; position:absolute;'" : "") . ">";

  $select .= "<select style='width: " . $self->width() . "px;' name='" . $self->name() . "'$multiple id='filter_select_" .  $self->html_id(). "' size='" . $self->size() . "'>";
  $select .= "</select></div>";

  # we have attributes, display the attribute filter
  my $attribute_boxes = {};
  if (scalar(@{$self->attributes})) {
    foreach my $attribute (@{$self->attributes}) {
      my $attribute_box = "";

      # sort attributes are handled differently
      next if $attribute->{sort_attribute};

      # start the fieldset for this attribute
      $attribute_box .= "<td><fieldset><legend>".$attribute->{name}."</legend><table>";
      
      # check whether this is exclusive or not
      my $type = "checkbox";
      if ($attribute->{exclusive}) {
	$type = "radio";
	$attribute_box .= "<optgroup>";
      }

      # create options for every possible value of the attribute
      foreach my $possible_value (@{$attribute->{possible_values}}) {
	my $checked = " checked=checked";
	if (ref($possible_value)) {
	  unless ($possible_value->[1]) {
	    $checked = "";
	  }
	  $possible_value = $possible_value->[0];
	}
	
	$attribute_box .= "<tr><td style='white-space: nowrap;'><input type='$type'$checked value='$possible_value' name='filter_select_" . $self->html_id() . "_" . $attribute->{name} . "' onchange='perform_attribute_filter(\"" . $self->html_id() . "\");'>$possible_value</td></tr>";
      }

      # close optgroup if this is exclusive
      if ($attribute->{exclusive}) {
	$attribute_box .= "</optgroup>";
      }
      
      # close attribute fieldset
      $attribute_box .= "</table></fieldset>";
      $attribute_boxes->{$attribute->{name}} = $attribute_box;
    }

    # check if we have any sort attributes
    my $sort_box = "";
    if (scalar(@$sort_attributes)) {
      $sort_box .= "<fieldset><legend>sort</legend><table><optgroup>";
      $sort_box .= "<tr><td style='white-space: nowrap;'><input type='radio' checked=checked value='alphabetical' name='filter_select_" . $self->html_id() . "_sort' onclick='perform_attribute_sort(\"alphabetical\", \"" . $self->html_id() . "\");'>alphabetical</td></tr>";
      foreach my $attribute (@$sort_attributes) {
	$sort_box .= "<tr><td><input type='radio' value='$attribute' name='filter_select_" . $self->html_id() . "_sort' onclick='perform_attribute_sort(\"" . $attribute . "\", \"" . $self->html_id() . "\");'>$attribute</td></tr>";
      }
      $sort_box .= "</optgroup></table></fieldset>";
      $attribute_boxes->{sort} = $sort_box;
    }
    $self->{attribute_boxes} = $attribute_boxes;
  }
  if ($self->auto_place_attribute_boxes()) {
    $select = "<table><tr><td>".$select."</td>";
    foreach my $key (sort(keys(%$attribute_boxes))) {
      $select .= "<td>".$attribute_boxes->{$key}."</td>";
    }
    $select .= "</tr></table>";
  }
  $select .= "<img src='$Conf::cgi_url/Html/clear.gif' onload='initialize_filter_select(\"" . $self->html_id() . "\");' />";
  
  return $select;
}

=item * B<values> (I<values>)

Getter / Setter for the values attribute.
These correspond to the values in the list part of the component.

=cut

sub values {
  my ($self, $values) = @_;

  if (defined($values)) {
    $self->{values} = $values;
  }

  return $self->{values};
}

=item * B<labels> (I<labels>)

Getter / Setter for the labels attribute.
These correspond to the labels in the list part of the component.

=cut

sub labels {
  my ($self, $labels) = @_;

  if (defined($labels)) {
    $self->{labels} = $labels;
  }

  return $self->{labels};
}

=item * B<get_attribute_boxes> ()

Getter for the attribute_boxes attribute.
Returns a hash of the attribute boxes.

=cut

sub get_attribute_boxes {
  my ($self) = @_;

  return $self->{attribute_boxes};
}

=item * B<auto_place_attribute_boxes> (I<boolean>)

Getter / Setter for the auto_place_attribute_filters attribute.
If this is true (default) the attribute filters will be placed
automatically. Set this to false and call get_attribute_boxes to
place them manually.

=cut

sub auto_place_attribute_boxes {
  my ($self, $value) = @_;

  if (defined($value)) {
    $self->{auto_place_attribute_boxes} = $value;
  }

  return $self->{auto_place_attribute_boxes};
}

=item * B<multiple> (I<multiple>)

Getter / Setter for the multiple attribute.
Determines whether this is a multiple select box or not.

=cut

sub multiple {
  my ($self, $multiple) = @_;

  if (defined($multiple)) {
    $self->{multiple} = $multiple;
  }

  return $self->{multiple};
}

=item * B<attributes> (I<attributes>)

Getter for the attributes attribute.
This is an array of attributes for values. Each entry represents an attribute-
type and must consist of an array with an entry for every value of the select
box.

=cut

sub attributes {
  my ($self, $attributes) = @_;

  if (defined($attributes)) {
    $self->{attributes} = $attributes;
  }

  return $self->{attributes};
}

=item * B<add_attribute> (I<name>, I<values>, I<possible_values>)

Adds an attribute to the attribute array. The name will be the text
displayed on the attribute filter box. The values must have one entry
for every item of the selet box. Possible values is an array that
determines the possible values of an attribute. If an entry in possible
values is an array, the first entry will determine the value, the second
a boolean whether this should be initially checked or not. Default is
checked.

=cut

sub add_attribute {
  my ($self, $attribute) = @_;

  push(@{$self->{attributes}}, $attribute);
       
  return $self->{attributes};
}

=item * B<name> (I<name>)

Getter / Setter for the name attribute.
This corresponds to the name of the cgi paramter the selection of this
component will end up in.

=cut

sub name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name} = $name;
  }
  
  return $self->{name};
}

=item * B<size> (I<size>)

Getter / Setter for the size attribute.
This is the length of the list part of the component.

=cut

sub size {
  my ($self, $size) = @_;
  
  if (defined($size)) {
    $self->{size} = $size;
  }
  
  return $self->{size};
}

=item * B<width> (I<width>)

Getter / Setter for the width attribute.
This determines the width of the component in pixels.

=cut

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

sub default {
  my ($self, $default) = @_;

  if (defined($default)) {
    $self->{default} = $default;
  }

  return $self->{default};
}

sub initial_text {
  my ($self, $initialtext) = @_;

  if (defined($initialtext)) {
    $self->{initialtext} = $initialtext;
  }

  return $self->{initialtext};
}

sub dropdown {
  my ($self, $dropdown) = @_;
  
  if (defined($dropdown)) {
    $self->{dropdown} = $dropdown;
  }

  return $self->{dropdown};
}

sub html_id {
    my ($self, $value) = @_;
    if($value) {
        $self->{html_id} = $value;
    }
    return $self->{html_id};
} 
    

sub require_javascript {
  return ["$Conf::cgi_url/Html/FilterSelect.js"];
}
