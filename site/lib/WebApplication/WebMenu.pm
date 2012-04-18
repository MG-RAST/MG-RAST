package WebMenu;

# WebMenu - manage menu for the WeApplication framework

# $Id: WebMenu.pm,v 1.13 2009-10-12 18:58:32 jared Exp $

use strict;
use warnings;


=pod

=head1 NAME

WebMenu - manage menu for the WeApplication framework

=head1 SYNOPSIS

use WebMenu;

my $menu = WebMenu->new();

$menu->add_category("Edit");

$menu->add_entry("Edit", "Copy", "copy.cgi");

$menu->add_entry("Edit", "Paste", "paste.cgi", "_blank");

$menu->output();


=head1 DESCRIPTION

The WebMenu module defines a mechanism to build a menu structure by defining 
categories (top level menu entries) and optional links, as well as sub entries 
for each of the categories (consisting of a entry name, an url and an optional 
browser target.

The html output of the menu consists of an unordered list of lists, ie. a two 
level hierarchy of html links (<a href> tags) embedded in <ul> tags representing 
categories and their entries.

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the WebMenu object. 

=cut

sub new {
    my $class = shift;
    
    my $self = { home => undef,
		 entries => {},
		 categories => [],
		 categories_index => {},
		 search => 0,
		 style => 'vertical',
    };
    bless $self, $class;
    
    return $self;
}


=pod
    
=item * B<flush> ()

Flushes all categories and entries from the menu (leaving it empty).

=cut

sub flush {
    my $self = shift;
    $self->{home} = undef;
    $self->{entries} = {};
    $self->{categories} = [];
    $self->{categories_index} = {};
    $self->{search} = 0;
    return $self;
}


=pod
    
=item * B<home> (I<url>)

Returns the link of the home page. If the optional parameter I<url> is given, 
home will be set. I<url> may be undef.

=cut

sub home {
    my $self = shift;
    if (scalar(@_)) {
	$self->{home} = $_[0];
    }
    return $self->{home};
}


=pod
    
=item * B<add_category> (I<category>, I<url>, I<target>, I<right>)

Adds a category to the menu. I<category> is mandatory and expects the name of the 
menu category. I<url> is optional and will add a link to the category name in the menu. 
I<target> is optional and defines a href target for that link. The optional I<right>
parameter specifies the right a user must have to be able to see this category.

=cut

sub add_category {
    my ($self, $category, $url, $target, $right, $order) = @_;
    
    unless ($category) {
	die 'No category given.';
    }

    unless ($order) {
      $order = scalar(@{$self->{categories}});
    }

    if (exists($self->{categories_index}->{$category})) {
	die "Trying to add category '$category' which already exists.";
    }

    $url = '' unless ($url);
    $target = '' unless ($target);
    
    # update the category index
    $self->{categories_index}->{$category} = scalar(@{$self->{categories}});
    
    # add the category and link
    push @{$self->{categories}}, [ $category, $url, $target, $right, $order ];

    # init the entries array for that category
    $self->{entries}->{$category} = [];

    return $self;
}


=pod
    
=item * B<delete_category> (I<category>)

Deletes a category from the menu. I<category> is mandatory and expects the 
name of the menu category. If the category does not exist a warning is printed.

=cut

sub delete_category {
    my ($self, $category) = @_;
    
    unless ($category) {
	die 'No category given.';
    }

    my $i = $self->{categories_index}->{$category};
    if ($i) {
	splice @{$self->{categories}}, $i, 1;
	delete $self->{categories_index}->{$category};
	delete $self->{entries}->{$category}
    }
    else {
	warn "Trying to delete non-existant category '$category'.";
    }

    return $self;
}


=pod
    
=item * B<get_categories> ()

Returns the names of all categories (in a random order).

=cut

sub get_categories {
    return keys(%{$_[0]->{categories_index}});
}

=pod
    
=item * B<search> (I<search_component>)

Getter / Setter for the search component of the menu

=cut

sub search {
  my ($self, $search) = @_;

  if (defined($search)) {
    $self->{search} = $search;
  }

  return $self->{search};
}

=pod

=item * B<add_entry> (I<category>, I<entry>, I<url>, I<right>)

Adds an entry and link to a existing category of the menu. I<category>, I<entry> 
and I<url> are mandatory. I<category> expects the name of the menu category. 
I<entry> can be any string, I<url> expects a url. I<target> is optional and 
defines a href target for that link.
The optional I<right> parameter specifies the right a user must have to 
be able to see this category.

=cut

sub add_entry {
    my ($self, $category, $entry, $url, $target, $right) = @_;
    
    unless ($category and $entry){# and $url) {
	die "Missing parameter ('$category', '$entry', '$url').";
    }

    unless (exists($self->{categories_index}->{$category})) {
	die "Trying to add to non-existant category '$category'.";
    }
    
    $target = '' unless ($target);

    push @{$self->{entries}->{$category}}, [ $entry, $url, $target, $right ];

    return $self;
}

=pod

=item * B<output> (I<application>)

Returns the html output of the menu. I<application> must be a reference to the
application this menu is being printed in. This is only neccessary if rights
are required for any category to be displayed.

=cut

sub output {
  my ($self, $application) = @_;

  return '' unless scalar(@{$self->{categories}});

  my $html = "";

  if ($self->style eq 'vertical') {
    $html = $self->output_vertical($application);
  } elsif ($self->style eq 'horizontal') {
    $html = $self->output_horizontal($application);
  }

  return $html;
}

sub output_vertical {
  my ($self, $application) = @_;

  my $html = "<div id='menu'>\n";
  $html .= "\t<ul id='nav'>\n";

  my @ordered_categories = sort { $a->[4] <=> $b->[4] } @{$self->{categories}};
  foreach (@ordered_categories) {
    
    my ($cat, $c_url, $c_target, $right, $order) = @$_;

    # check if a right is required to see this category
    if (defined($right)) {
      unless (defined($application) && ref($application) eq 'WebApplication') {
	die "When using rights for a menu category, an application reference must be passed.";
      }
      next unless ($application->session->user && 
		   $application->session->user->has_right($application, @$right));
    }

    my $url = ($c_url) ? qq~href="$c_url"~ : '';
    my $target = ($c_target) ? qq~target="$c_target"~ : '';
    
    $html .= qq~\t\t<li><div><a $url $target>$cat</a></div>\n~;
    
    if (scalar(@{$self->{entries}->{$cat}})) {

      $html .= "\t\t<ul>\n";

      foreach (@{$self->{entries}->{$cat}}) {

	my ($entry, $e_url, $e_target, $e_right) = @$_;
	
	# check if a right is required to see this category
	if (defined($e_right)) {
	  unless (defined($application) && ref($application) eq 'WebApplication') {
	    die "When using rights for a menu category, an application reference must be passed.";
	  }
	  next unless ($application->session->user && 
		       $application->session->user->has_right($application, @$e_right));
	}

	if ($e_url) {
	  my $target = ($e_target) ? qq~target="$e_target"~ : '';
	  $html .= qq~\t\t\t<li><a href="$e_url" $target>$entry</a></li>\n~;
	} else {
	  $html .= qq~\t\t\t<li><span>$entry</span></li>\n~;
	}
      }
	
      $html .= "\t\t</ul>\n";
      
    }

    $html .= "\t\t</li>\n";
  
  }

  $html .= "\t</ul>\n";

  $html .= "</div>\n";

  return $html;
}

sub output_horizontal {
  my ($self, $application) = @_;

  my $html = "<table class='menu_table'><tr class='menu_cats'>";

  my @ordered_categories = sort { $a->[4] <=> $b->[4] } @{$self->{categories}};
  my $i = 0;
  foreach (@ordered_categories) {
    
    my ($cat, $c_url, $c_target, $right, $order) = @$_;

    # check if a right is required to see this category
    if (defined($right)) {
      unless (defined($application) && ref($application) eq 'WebApplication') {
	die "When using rights for a menu category, an application reference must be passed.";
      }
      next unless ($application->session->user && 
		   $application->session->user->has_right($application, @$right));
    }
    
    $html .= qq~<td class='menu_cat_inactive' onclick='activate_menu_cat("$i");' id='menu_cat_$i'>$cat</td>~;
    $i++;
  }
  $html .= "<td class='menu_filler'>&nbsp</td></tr></table>";

  $i = 0;
  foreach (@ordered_categories) {
    
    my ($cat, $c_url, $c_target, $right, $order) = @$_;
    
    # check if a right is required to see this category
    if (defined($right)) {
      unless (defined($application) && ref($application) eq 'WebApplication') {
	die "When using rights for a menu category, an application reference must be passed.";
      }
      next unless ($application->session->user && 
		   $application->session->user->has_right($application, @$right));
    }
    if (scalar(@{$self->{entries}->{$cat}})) {

      $html .= "<table id='menu_cat_bar_$i' class='menu_cat_bar_inactive'><tr>";

      foreach (@{$self->{entries}->{$cat}}) {

	my ($entry, $e_url, $e_target, $e_right) = @$_;
	
	# check if a right is required to see this category
	if (defined($e_right)) {
	  unless (defined($application) && ref($application) eq 'WebApplication') {
	    die "When using rights for a menu category, an application reference must be passed.";
	  }
	  next unless ($application->session->user && 
		       $application->session->user->has_right($application, @$e_right));
	}

	if ($e_url) {
	  my $target = ($e_target) ? qq~target="$e_target"~ : '';
	  $html .= qq~<td class='menu_item'><a href="$e_url" $target>$entry</a></td>~;
	} else {
	  $html .= qq~<td class='menu_item'><span>$entry</span></td>~;
	}
      }
	
      $html .= "<td class='menu_item_filler'></td></tr></table>";
      
    }
    $i++;
  }

  $html .= qq~
<script>
function activate_menu_cat (which) {
  for (i=0; i<1000; i++) {
    var cat_bar = document.getElementById('menu_cat_bar_'+i);
    var cat = document.getElementById('menu_cat_'+i);
    if (cat_bar) {
      if (i == which) {
        cat_bar.className = 'menu_cat_bar_active';
        cat.className = 'menu_cat_active';
      } else {
        cat_bar.className = 'menu_cat_bar_inactive';
        cat.className = 'menu_cat_inactive';
      }
    } else {
      break;
    }
  }
}
</script>
~;

  return $html;
}

sub style {
  my ($self, $style) = @_;

  if (defined($style)) {
    $self->{style} = $style;
  }

  return $self->{style};
}

1;
