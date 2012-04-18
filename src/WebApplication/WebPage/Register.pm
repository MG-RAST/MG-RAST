package WebPage::Register;

# Register - an instance of WebPage which handles user registration

# $Id: Register.pm,v 1.10 2011-06-13 09:35:45 paczian Exp $

use strict;
use warnings;

use base qw( WebPage );

1;

=pod

#TITLE RegisterPagePm

=head1 NAME

Register - an instance of WebPage which handles user registration

=head1 DESCRIPTION

Display a register form and handles user registration by sending a
request mail and putting an entry into the user db.

=head1 METHODS

=over 4

=item * B<init> ()

Initialise the page

=cut

sub init {
  my $self = shift;
  $self->title('User Registration');
  $self->application->register_component('Register', 'Register');
}

=pod

=item * B<output> ()

Returns the html output of the Register page.

=cut

sub output {
  my ($self) = @_;
  my $application = $self->application();

  my $reg = $application->component('Register');

  my $content = '<h2>Register for this service</h2>';
  $content .= '<table><tr><td>'.$reg->output.'</td><td><ul><li style="margin-bottom: 5px;">If you register for the first time, choose <b>New Account</b>. Please enter your first and last name as well as your email address into the fields below. Then please select your country and choose a login name. It\'s recommended to use only letters and digits for your login name, without spaces. After an administrator has approved your account, you will receive an email confirming your account approval, and explaining how to login and set your password.</li><li style="margin-bottom: 5px;">If you already have an account for one of our other services, choose <b>Existing Account</b>. Please enter your <b>login</b> and <b>email</b> of that account.</li><li>If your group administrator has given you a group name, please enter it in the group name field, otherwise leave this field blank.</li></ul></td></tr></table>';

  return $content;

}

sub supported_rights {
  return [ [ 'view', 'registration_mail', '*' ] ];
}
