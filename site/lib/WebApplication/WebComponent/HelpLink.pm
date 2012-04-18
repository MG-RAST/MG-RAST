package WebComponent::HelpLink;

# HelpLink - component for a help link

use strict;
use warnings;

use base qw( WebComponent );

1;


=pod

=head1 NAME

HelpLink - component for a help link

=head1 DESCRIPTION

WebComponent for a help link

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{title} = undef;
  $self->{text} = "";
  $self->{page} = undef;
  $self->{wiki} = "http://www.theseed.org/wiki/";
  $self->{disable_link} = undef;
  $self->{hover_width} = undef;

  $self->application->register_component('Hover', 'help_hover'.$self->id);

  return $self;
}

=item * B<output> ()

Returns the html output of the Info component.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $help_hover = $application->component('help_hover'.$self->id);

  unless (defined($self->page())) {
    $self->page($self->title());
  }
  my $helptext = "";
  if (defined($self->title)) {
    $helptext = "<table><tr><th>" . $self->title() . "</th></tr><tr><td>" . $self->text() . "</td></tr></table>";
  } else {
    $helptext = $self->text();
  }
  $help_hover->add_tooltip( 'info_hover'.$self->id(), $helptext, $self->hover_width() );

  my $href = ($self->disable_wiki_link) ? '' : ' href="' . $self->wiki() . $self->page() . '"';

  my $help = $help_hover->output().'<a style="text-decoration: none; cursor: help;" '. $href . ' target="help"><sup style="font-weight: normal; font-stretch: narrower; color: black;" id="info_hover' . $self->id() . '" onmouseover="hover(event, \'info_hover' . $self->id() . '\', \'' . $help_hover->id() . '\');">[?]</sup></a>';

  return $help;
}


=item * B<disable_wiki_link> (I<bool>)

If set to true, the link to the wiki will be disabled. 
Set to false by default.

=cut

sub disable_wiki_link {
  if (defined $_[1]) {
    $_[0]->{disable_link} = $_[1];
  }
  return $_[0]->{disable_link};
}


=item * B<title> (I<title>)

Getter / Setter for the title attribute.
The word being explained with the help link.

=cut

sub title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{title} = $title;
  }

  return $self->{title};
}

=item * B<text> (I<text>)

Getter / Setter for the text attribute.
A short explanatory text.

=cut

sub text {
  my ($self, $text) = @_;

  if (defined($text)) {
    $self->{text} = $text;
  }

  return $self->{text};
}

=item * B<page> (I<page>)

Getter / Setter for the page attribute.
The wiki page to link to.

=cut

sub page {
  my ($self, $page) = @_;

  if (defined($page)) {
    $self->{page} = $page;
  }

  return $self->{page};
}

=item * B<wiki> (I<url>)

Getter / Setter for the wiki attribute.
The base url of the wiki to link to.

=cut

sub wiki {
  my ($self, $url) = @_;

  if (defined($url)) {
    $self->{wiki} = $url;
  }

  return $self->{wiki};
}

=item * B<hover_width> (I<width>)

Getter / Setter for the hover_width attribute.
The width of the hover info box in pixels.

=cut

sub hover_width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{hover_width} = $width;
  }

  return $self->{hover_width};
}
