package WebComponent::TestComponent;

# TestComponent - component to demonstrate the component system

use strict;
use warnings;

use base qw( WebComponent );

use Data::Dumper;

1;


=pod

=head1 NAME

TestComponent - component to demonstrate the component system

=head1 DESCRIPTION

WebComponent for demonstration of the component system

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_action($self, 'perform_test_action', $self->get_trigger('test_action'));
  $self->application->register_component('Ajax', 'testcomponent'.$self->id.'a');
  $self->{data} = '';

  return $self;
}


=item * B<output> ()

Returns the html output of the Login component.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $a = $application->component('testcomponent'.$self->id.'a');
  my $content = $a->output;

  my $test = "TestComponent|".$self->{_id};
  $content .= "<input type='button' onclick='execute_ajax(\"test_ajax_function\", \"result\", \"a=b\", \"toasting...\", 0, null, \"$test\");' value='toast'>";
  $content .= "<div style='border: 1px solid black;' id='result'></div>";

  return $content;
}

=item * B<perform_test_action> ()

Executes an example action of this component.

=cut

sub perform_test_action {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  $application->add_message('info', $cgi->param('display_text'));

  return 1;
}

=item * B<data> ()

Sets the data attribute of this component to the passed value.

=cut

sub data {
  my ($self, $data) = @_;

  $self->{data} = $data;

  return 1;
}

sub test_ajax_function {
  my ($self) = @_;

  return "<pre>".Dumper($self->application->cgi)."</pre>";
}
