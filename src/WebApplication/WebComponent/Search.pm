package WebComponent::Search;

# Search - component for a search box

use strict;
use warnings;

use base qw( WebComponent );

1;


=pod

=head1 NAME

Search - component for a search box

=head1 DESCRIPTION

WebComponent for a search box

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{categories} = {};
  $self->{default_category} = '';
  $self->{width} = "100px";
  $self->{button} = 0;
  $self->{button_title} = 'Find';
  $self->{db} = undef;
  $self->{result_type} = 'table';

  $self->application->register_action($self, 'search_result', 'search_result');
  $self->application->register_component('Table', 'search_result_table'.$self->id);

  return $self;
}

=item * B<output> ()

Returns the html output of the Info component.

=cut

sub output {
  my ($self) = @_;

  unless (defined($self->db)) {
    return "no search database given";
  }

  my $search = $self->application->page->start_form('search_form', 1);
  $search .= "<input type='hidden' name='action' value='search_result'>";

  # check whether we have categories
  if (scalar(keys(%{$self->categories}))) {
    $search .= "<select name='search_query_category'>";
    my @categories = sort { $self->categories->{$a}->{order} <=> $self->categories->{$b}->{order} } keys(%{$self->categories()});
    foreach my $category (@categories) {
      my $selected = "";
      if ($category eq $self->default_category()) {
	$selected = " selected=selected";
      }
      $search .= "<option value='" . $category . "'$selected>" . $category . "</option>";
    }
    $search .= "</search>";
  }
  
  # create the input field
  $search .= "<input type='text' name='search_query_string' style='width: " . $self->width() . ";'>";

  # check if we want a button
  if ($self->button()) {
    $search .= "<input type='submit' class='button' value='" . $self->button_title() . "'>";
  }

  $search .= "</form>";

  return $search;
}

=item * B<add_category> (I<title>, I<type>, I<attribute>, I<sort_order>)

Getter / Setter for the width attribute.
This determines the width of the component as used by the css width attribute.

=cut

sub add_category {
  my ($self, $title, $type, $attribute, $target, $sort_order) = @_;

  if (defined($category_title)) {
    unless (defined($type)) {
      $type = $category_title;
    }
    unless (defined($sort_order)) {
      $sort_order = scalar(keys(%{$self->{categories}}));
    }
    unless (defined($attribute)) {
      $attribute = 'name';
    }
    unless (defined($target)) {
      $target = $type;
    }
    $self->{categories}->{$category_title}->{order} = $sort_order;
    $self->{categories}->{$category_title}->{type} = $type;
    $self->{categories}->{$category_title}->{attribute} = $attribute;
    $self->{categories}->{$category_title}->{target} = $target;
  }

  return 1;
}

=item * B<categories> ()

Getter for the categories attribute.

=cut

sub categories {
  my ($self) = @_;

  return $self->{categories};
}

=item * B<width> (I<width>)

Getter / Setter for the width attribute.
This determines the width of the component as used by the css width attribute.

=cut

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

=item * B<default_category> (I<category_title>)

Getter / Setter for the default_category attribute.
This determines which category is initially selected.

=cut

sub default_category {
  my ($self, $category) = @_;

  if (defined($category)) {
    $self->{default_category} = $category;
  }

  return $self->{default_category};
}

=item * B<button> (I<boolean>)

Getter / Setter for the button attribute.
This determines whether a search button will be displayed as part of the component.

=cut

sub button {
  my ($self, $button) = @_;

  if (defined($button)) {
    $self->{button} = $button;
  }

  return $self->{button};
}

=item * B<db> (I<dbmaster>)

Getter / Setter for the db attribute.
This database will be used to perform the search on.

=cut

sub db {
  my ($self, $db) = @_;

  if (defined($db)) {
    $self->{db} = $db;
  }

  return $self->{db};
}

=item * B<result_type> (I<type>)

Getter / Setter for the result_type attribute.
This may be either 'table' or 'objects' which determines whether the
search_result method will return an html table or PPO objects. Default is
'table'.

=cut

sub result_type {
  my ($self, $type) = @_;

  if (defined($type)) {
    $self->{result_type} = $type;
  }

  return $self->{result_type};
}

=item * B<button_title> (I<button_title>)

Getter / Setter for the button_title attribute.
This determines the caption of the search button.

=cut

sub button_title {
  my ($self, $button_title) = @_;

  if (defined($button_title)) {
    $self->{button_title} = $button_title;
  }

  return $self->{button_title};
}

sub require_css {
  return undef;
}

sub require_javascript {
  return [];
}

=item * B<search_result> ()

Executes a search and returns the result

=cut

sub search_result {
  my ($self) = @_;

  my $result_table = $self->application->component('search_result_table'.$self->id());
  my $cgi = $self->application->cgi();

  my $search = $cgi->param('search_query_string');
  my $category = $cgi->param('search_query_category');
  my $object_type = $self->categories->{$category}->{type};
  my $attribute = $self->categories->{$category}->{attribute};
  my $objects = $self->db->$object_type->get_objects( { $attribute => [ "%".$search."%", "like"] } );

  if ($self->result_type() eq 'table') {
    my $result = "<h2>Results for '<i>" . $search . "</i>' in $category</h2>";
    if (scalar(@$objects)) {
      my $columns = [];
      my $atts = $objects->[0]->attributes();
      foreach my $att (keys(%$atts)) {
	if ($atts->{$att}->[0] == 1) {
	  push(@$columns, $att);
	} 
      }
      $result_table->columns($columns);
      my $data = [];
      my $url = $self->application->url() . "?page=" . $self->categories->{$category}->{target} . "&id=";
      foreach my $object (@$objects) {
	my $line = [];
	foreach my $col (@$columns) {
	  my $cell = $object->$col();
	  if ($col eq $attribute) {
	    $cell = "<a href='$url$cell'>$cell</a>";
	  }
	  push(@$line, $cell);
	}
	push(@$data, $line);
      }
      $result_table->data($data);
      $result .= $result_table->output();
    } else {
      $result .= "No results found.";
    }
    
    return $result;
  } else {
    return $objects;
  }
}
