package WebComponent::ToggleButton;

# ToggleButton - component for a set of toggle buttons

use strict;
use warnings;

use WebConfig;

use base qw( WebComponent );

1;


=pod

=head1 NAME

ToggleButton - component for a set of toggle buttons

=head1 DESCRIPTION

WebComponent for a set of toggle buttons

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{buttons} = [];
  $self->{name} = 'toggle';
  $self->{default_button} = 0;
  $self->{toggle_type} = 'value';
  $self->{action} = "";

  return $self;
}

=item * B<output> ()

Returns the html output of the Info component.

=cut

sub output {
  my ($self) = @_;

  # initialize content
  my $content = "";

  # get the buttons
  my $buttons = $self->{buttons} ;
  
  # create the value field
  $content .= "<input type='hidden' id='togglevalue_".$self->id()."' name='" . $self->name() . "' value='" . $buttons->[$self->default_button()]->[1] . "'>";

  # iterate over the buttons and add a div for each
  my $i = 0;
  foreach my $button (@$buttons) {
    my $action = "";
    if ($self->toggle_type() eq 'value') {
      $action = "\"" . $button->[1] . "\"";
    } else {
      $action = "\"" . $button->[1] . "\", " .$self->action();
    }

    # check if the button is pressed or not
    my $class = 'toggle_unselected';
    if ($i == $self->default_button()) {
      $class = 'toggle_selected';
    }
    $content .= "<a class='$class' name='toggle_".$self->id()."' id='toggle_".$i."_".$self->id()."' onclick='tiggle(\"".$i."\", \"".$self->id()."\", $action);'>".$button->[0]."</a>\n";
    $i++;
  }

  # return the content
  return $content;
}

=item * B<add_button> (I<title>, I<param>)

Adds a new button to the toggle array.
I<title> will be the string printed into the button,
I<param> will be the value given either to the cgi param when this
button is pressed in toggle_type = 'value' mode, or to the javascript to be
executed upon pressing the button in 'action' mode.

=cut

sub add_button {
  my ($self, $title, $param) = @_;

  unless (defined($title)) {
    $title = "";
  }

  unless (defined($param)) {
    $param = "";
  }

  push(@{$self->{buttons}}, [$title, $param]);

  return 1;
}

=item * B<default_button> (I<index>)

Gets / Sets which button is initially pressed.

=cut

sub default_button {
  my ($self, $index) = @_;

  if (defined($index)) {
    $self->{default_button} = $index;
  }

  return $self->{default_button};
}

=item * B<name> (I<name>)

Gets / Sets the name of the cgi parameter this toggle component will produce.
This is only required if used in toggle_type = value.

=cut

sub name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name} = $name;
  }

  return $self->{name};
}

=item * B<action> (I<action>)

Gets / Sets the name of the javascript function to be executed.
This is only required if used in toggle_type = action.

=cut

sub action {
  my ($self, $action) = @_;

  if (defined($action)) {
    $self->{action} = $action;
  }

  return $self->{action};
}

=item * B<toggle_type> (I<type>)

Gets / Sets what type of toggle button this is.
I<type> can be either 'value', indicating that toggling the button will change the value of
the toggle component or 'action', meaning that toggling the button will execute a javascript
function.

=cut

sub toggle_type {
  my ($self, $type) = @_;

  if (defined($type)) {
    $self->{toggle_type} = $type;
  }

  return $self->{toggle_type};
}

sub require_css {
  return "$Conf::cgi_url/Html/ToggleButton.css";
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/ToggleButton.js"];
}
