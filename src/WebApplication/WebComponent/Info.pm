package WebComponent::Info;

# Info - component for a collapsable info field

use strict;
use warnings;

use WebConfig;

use base qw( WebComponent );

1;


=pod

=head1 NAME

Info - component for a collapsable info field

=head1 DESCRIPTION

WebComponent for a collapsable info field

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{content} = "";
  $self->{width} = "70%";
  $self->{default} = 1;
  $self->{title} = undef;

  return $self;
}

=item * B<output> ()

Returns the html output of the Info component.

=cut

sub output {
  my ($self) = @_;

  my $class_1 = "info_button_show";
  my $class_2 = "info_show";
  unless ($self->default()) {
    $class_1 = "info_button_hide";
    $class_2 = "info_hide";
  }

  my $title = '';
  if (defined($self->title)) {
    $title = "<td style='padding-top: 3px;padding-right: 2px;'>" . $self->title . "</td>";
  }

  my $info = qq~<div style="width: ~ . $self->width() . qq~; padding: 0px; margin-bottom: 5px;"><table class="info"><tr><td class='info'><div onclick="info_field('~ . $self->id() . qq~');" id="info_button_~ . $self->id() . qq~" class="$class_1"><img src='~.IMAGES.qq~wac_infobulb.png'></div></td><td class='info'><div id="info_~ . $self->id() . qq~" class="$class_2">~ . $self->content() . qq~</div></td>~ . $title . qq~</tr></table></div>~;

  return $info;
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

=item * B<content> (I<content>)

Getter / Setter for the content attribute.
This determines the content of the component.

=cut

sub content {
  my ($self, $content) = @_;

  if (defined($content)) {
    $self->{content} = $content;
  }

  return $self->{content};
}

=item * B<default> (I<default>)

Getter / Setter for the default attribute.
This determines whether the info component is initially expanded or collapsed.

=cut

sub default {
  my ($self, $default) = @_;

  if (defined($default)) {
    $self->{default} = $default;
  }

  return $self->{default};
}

=item * B<title> (I<title>)

Getter / Setter for the title attribute.
This determines whether the info component will have a title to the right of it
when collapsed.

=cut

sub title {
  my ($self, $title) = @_;

  if (defined($title)) {
    $self->{title} = $title;
  }

  return $self->{title};
}

sub require_css {
  return "$Conf::cgi_url/Html/Info.css";
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/Info.js"];
}
