package WebComponent::Hover;

# Hover - component for a HoverMenu or HoverTooltip

use strict;
use warnings;

use base qw( WebComponent );

use Digest::MD5 qw( md5_hex );

1;


=pod

=head1 NAME

Hover - component for a HoverMenu or HoverTooltip

=head1 DESCRIPTION

WebComponent for a HoverMenu or HoverTooltip

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{tooltips} = [];
  $self->{menus} = [];
  $self->{redundancies} = {};
  $self->{content_md5s} = {};

  return $self;
}

=item * B<output> ()

Returns the html output of the Hover component.

=cut

sub output {
  my ($self) = @_;

  my $hover = "";

  # calculate the redundancies string
  my $redundancies_string = join( '~#', map { join( '~@', @{$self->redundancies->{$_}} ) } keys %{$self->redundancies});
  $hover .= "<input type='hidden' id='hover_redundancies_".$self->id."' value='".$redundancies_string."'>";

  foreach my $tooltip (@{$self->tooltips()}) {
    $hover .= "<span style='display: none;' id='tooltip_" . $self->id . "_" . $tooltip->{id} . "'>" . $tooltip->{content} . "</span>\n";
    if (defined($tooltip->{width})) {
      $hover .= "<input type='hidden' id='tooltip_width_" . $self->id . "_" . $tooltip->{id} . "' value='" . $tooltip->{width} . "'>\n";
    }
    if (defined($tooltip->{timeout})) {
      $hover .= "<input type='hidden' id='tooltip_timeout_" . $self->id . "_" . $tooltip->{id} . "' value='" . $tooltip->{timeout} . "'>\n";
    }
  }

  foreach my $menu (@{$self->menus()}) {
    $hover .= "<span style='display: none;' id='menu_titles_" . $self->id . "_" . $menu->{id} . "'>" . join('~#', @{$menu->{titles}}) . "</span>\n";
    $hover .= "<span style='display: none;' id='menu_links_" . $self->id . "_" . $menu->{id} . "'>" . join('~#', @{$menu->{links}}) . "</span>\n";
    if (defined($menu->{width})) {
      $hover .= "<input type='hidden' id='menu_width_" . $self->id . "_" . $menu->{id} . "' value='" . $menu->{width} . "'>\n";
    }
    if (defined($menu->{timeout})) {
      $hover .= "<input type='hidden' id='menu_timeout_" . $self->id . "_" . $menu->{id} . "' value='" . $menu->{timeout} . "'>\n";
    }
  }

  return $hover;
}

=item * B<tooltips> ()

Getter for the tooltips attribute.
This is a container for all tooltips to be stored in this component.

=cut

sub tooltips {
  my ($self) = @_;

  return $self->{tooltips};
}

=item * B<redundancies> ()

Getter for the redundancies attribute.
This is a container for all redundant tooltip ids.

=cut

sub redundancies {
  my ($self) = @_;

  return $self->{redundancies};
}

=item * B<menus> ()

Getter for the menus attribute.
This is a container for all menus to be stored in this component.

=cut

sub menus {
  my ($self) = @_;

  return $self->{menus};
}

=item * B<add_tooltip> (I<id>, I<content>)

Adds a tooltip to the tooltips container.
B<id> must be the html-id of the object the tooltip is to be connected to.
B<content> holds the HTML to be show in the tolltip.

=cut

sub add_tooltip {
  my ($self, $id, $content, $width, $timeout) = @_;

  if (defined($id) && defined($content)) {
    my $digest = md5_hex($content);
    if (exists $self->redundancies->{$digest}) {
      push(@{$self->redundancies->{$digest}}, $id);
    } else {
      $self->redundancies->{$digest} = [ $id ];
      push(@{$self->{tooltips}}, { id => $id, content => $content, width => $width, timeout => $timeout });
    }
  }

  return 1;
}

=item * B<add_menu> (I<id>, I<titles>, I<links>)

Adds a menu to the menus container.
B<id> must be the html-id of the object the menu is to be connected to.
B<titles> is an array reference, holding the titles of the menu entries
to be shown in the menu. B<links> is an array reference, holding the urls
the according menu entries should link to.

=cut

sub add_menu {
  my ($self, $id, $titles, $links, $width, $timeout) = @_;

  if (defined($id) && defined($titles) && defined($links)) {
    push(@{$self->{menus}}, { id => $id, titles => $titles, links => $links, width => $width, timeout => $timeout });
  }

  return 1;
}

sub require_css {
  return "$Conf::cgi_url/Html/Hover.css";
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/Hover.js"];
}
