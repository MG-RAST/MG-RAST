package WebComponent::ListSelect;

use strict;
use warnings;

use base qw( WebComponent );

use Conf;

1;

=pod

=head1 NAME

ListSelect - component for two lists with buttons to move entries from one to another

=head1 DESCRIPTION

WebComponent for two lists with buttons to move entries from one to another

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{data} = undef;
  $self->{filter} = 0;
  $self->{multiple} = 0;
  $self->{left_header} = undef;
  $self->{right_header} = undef;
  $self->{preselection} = [];
  $self->{show_reset} = 0;
  $self->{sorted} = 0;
  $self->{name} = 'ListSelect';
  $self->{add_button_title} = "->";
  $self->{remove_button_title} = "<-";
  $self->{reset_button_title} = "clear selection";
  $self->{size} = 8;
  $self->{multiple} = 0;
  $self->{max_width_list} = 0;
  $self->{max_selections} = 0;
  $self->{group_names} = [];
  $self->{initial_group} = 0;
  $self->{types} = undef;

  return $self;
}

=item * B<output> ()

Returns the html output of the ListSelect component.

=cut

sub output {
  my ($self) = @_;

  # initialize variables
  my $content = "";

  # store preselection data
  $content .= "<input type='hidden' id='list_select_preselect_".$self->id."' value='".join('~@', @{$self->preselection})."'>";

  # check for sorting of the labels
  if ($self->sorted) {
    my $data = $self->data;
    @$data = sort { $a->{label} cmp $b->{label} } @$data;
    $self->data($data);
  }
  $content .= "<input type='hidden' id='list_select_sorted_".$self->id."' value='".$self->sorted."'>";

  # set maximum selections
  $content .= "<input type='hidden' id='list_select_max_selections_".$self->id."' value='".$self->max_selections."'>";

  # check if we are using groups
  my $data_string;
  if (scalar(@{$self->group_names})) {
    my $str_coll = [];
    foreach my $str (@{$self->data}) {
      push(@$str_coll, join('~@', map { $_->{type} ? $_->{label} .= "~#" . $_->{type} : 1; $_->{value} . "~#" . $_->{label} } @$str));
    }
    $data_string = join('~~', @$str_coll);
    $content .= "<input type='hidden' id='list_select_uses_groups_".$self->id."' value='1'>";
    $content .= "<select id='list_select_set_select_".$self->id."' onfocus='this.SaveValue=this.value; return true;' onchange='list_select_change_current_data_set(\"".$self->id."\");'>";
    my $i=0;
    foreach my $entry (@{$self->group_names}) {
      my $sel = "";
      if ($i==$self->initial_group) {
	$sel = " selected=selected";
      }
      $content .= "<option value='$i'$sel>$entry</option>";
      $i++;
    }
    $content .= "</select>";
  } else {
    $content .= "<input type='hidden' id='list_select_uses_groups_".$self->id."' value='0'>";
    $data_string = join('~@', map { $_->{type} ? $_->{label} .= "~#" . $_->{type} : 1; $_->{value} . "~#" . $_->{label} } @{$self->data});
  }

  # check for type mapping
  if ($self->types) {
    foreach my $type (@{$self->types}) {
      $content .= "$type <input type='checkbox' name='$type' checked=checked id='ls_types_".$type."_".$self->id."' value='$type' onclick='list_select_reset(\"".$self->id."\");'> ";
    }
    $content .= "<br>";
  }

  # store the list data
  $data_string =~ s/\'/\&\#39\;/g;
  $content .= "<input type='hidden' id='list_select_data_".$self->id."' value='".$data_string."'>";

  # create the surrounding table
  $content .= "<table>";

  # check for headers
  if ($self->left_header || $self->right_header) {
    my $left = $self->left_header ? "<th>".$self->left_header."</th>" : "<td></td>";
    my $right = $self->right_header ? "<th>".$self->right_header."</th>" : "<td></td>";
    $content .= "<tr>$left<td></td>$right</tr>";
  }

  # check whether multiple selection is allowed
  my $multiple = "";
  if ($self->multiple) {
    $multiple = " multiple=multiple";
  }

  # check for filter
  if ($self->filter) {
    #onchange='list_select_update(event, \"" . $self->id() . "\");' 
    $content .= "<tr><td><input type='text' style='width: 250px;' id='list_select_filter_".$self->id."' onkeyup='list_select_check_backspace(event, \"" . $self->id() . "\");' value='start typing to narrow selection'></td></tr>";
  }

  # print left list
  my $maxwidth = "";
  if ($self->{max_width_list}) {
    $maxwidth = " style='width: ".$self->{max_width_list}."px;'";
  }
  $content .= "<tr><td><select id='list_select_list_a_".$self->id."' size='".$self->size."'$multiple$maxwidth></select></td>";

  # print buttons
  $content .= "<td>";
  $content .= "<input type='button' value='".$self->add_button_title."' onclick='list_select_add(\"".$self->id."\");'><br>";
  $content .= "<input type='button' value='".$self->remove_button_title."' onclick='list_select_remove(\"".$self->id."\");'>";
  if ($self->show_reset) {
    $content .= "<br><input type='button' value='".$self->reset_button_title."' onclick='list_select_reset(\"".$self->id."\");'>";
  }
  $content .= "</td>";
  
  # print right list
  $content .= "<td><select id='list_select_list_b_".$self->id."' name='".$self->name."' size='".$self->size."'$multiple$maxwidth></select></td></tr>";

  # close the surrounding table
  $content .= "</table>";

  # initialize the list select
  $content .= "<img src='$Conf::cgi_url/Html/clear.gif' onload='initialize_list_select(\"".$self->id."\");'>";
  
  # return the content
  return $content;
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub filter {
  my ($self, $filter) = @_;

  if (defined($filter)) {
    $self->{filter} = $filter;
  }

  return $self->{filter};
}

sub left_header {
  my ($self, $header) = @_;

  if (defined($header)) {
    $self->{left_header} = $header;
  }

  return $self->{left_header};
}

sub right_header {
  my ($self, $header) = @_;

  if (defined($header)) {
    $self->{right_header} = $header;
  }

  return $self->{right_header};
}

sub preselection {
  my ($self, $preselection) = @_;

  if (defined($preselection)) {
    $self->{preselection} = $preselection;
  }

  return $self->{preselection};
}

sub show_reset {
  my ($self, $reset) = @_;

  if (defined($reset)) {
    $self->{show_reset} = $reset;
  }

  return $self->{show_reset};
}

sub sorted {
  my ($self, $sorted) = @_;

  if (defined($sorted)) {
    $self->{sorted} = $sorted;
  }

  return $self->{sorted};
}

sub name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name} = $name;
  }

  return $self->{name};
}

sub add_button_title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{add_button_title} = $title;
  }

  return $self->{add_button_title};
}

sub remove_button_title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{remove_button_title} = $title;
  }

  return $self->{remove_button_title};
}

sub reset_button_title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{reset_button_title} = $title;
  }

  return $self->{reset_button_title};
}

sub size {
  my ($self, $size) = @_;
  
  if (defined($size)) {
    $self->{size} = $size;
  }

  return $self->{size};
}

sub multiple {
  my ($self, $multiple) = @_;

  if (defined($multiple)) {
    $self->{multiple} = $multiple;
  }

  return $self->{multiple};
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/ListSelect.js"];
}

sub max_selections {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max_selections} = $max;
  }

  return $self->{max_selections};
}

sub group_names {
  my ($self, $names) = @_;

  if (defined($names)) {
    $self->{group_names} = $names;
  }

  return $self->{group_names};
}

sub initial_group {
  my ($self, $initial) = @_;

  if (defined($initial)) {
    $self->{initial_group} = $initial;
  }

  return $self->{initial_group};
}

sub types {
  my ($self, $types) = @_;

  if (defined($types)) {
    $self->{types} = $types;
  }

  return $self->{types}
}
