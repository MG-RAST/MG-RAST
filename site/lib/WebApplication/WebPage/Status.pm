package WebPage::Status;

use base qw( WebPage );

1;

=pod

=head1 NAME

Status - an instance of WebPage which checks for correct WebApplication Setup

=head1 DESCRIPTION

Display a status page to see whether WebApplication is configured correctly

=head1 METHODS

=over 4

=item * B<output> ()

Returns the html output of the Status page.

=cut

sub output {
  my ($self) = @_;

  my $html = '';

  $self->application->menu->add_category('Test');
  $self->application->menu->add_entry('Test', 'Entry 1', 'http://www.google.de');

  $self->application->add_message('info', 'Status: up and running');

  $self->application->component('test_component1')->data('This is a test of the test component');

  $html .= $self->application->component('test_component1')->output;

  $html .= "<hr />";

  $html .= $self->start_form;
  $html .= "<input type='hidden' name='action' value='page_test_action'>";
  $html .= "Enter text to display as a warning message<br />";
  $html .= "<input type='text' name='display_text' value='testtext'><br />";
  $html .= "<input type='submit' class='button' value='perform'><br />";
  $html .= $self->end_form;

  return $html;

}

=item * B<required_rights> ()

Returns a reference to an array of right tuples this page requires to be displayed.

=cut

sub required_rights {
  return [ [ 'login' ] ];
}

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->application->register_component('TestComponent', 'test_component1');
  $self->application->register_action($self, 'perform_test_action', 'page_test_action');

  return 1;
}

=item * B<perform_test_action> ()

Example of an action.

=cut

sub perform_test_action {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  $application->add_message('warning', $cgi->param('display_text'));

  return 1;
}
