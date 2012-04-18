package WebPage::Login;

# Login - an instance of WebPage which handles user authentication

# $Id: Login.pm,v 1.10 2008-09-03 21:01:25 parrello Exp $

use strict;
use warnings;

use base qw( WebPage );

1;

=pod

#TITLE LoginPagePm

=head1 NAME

Login - an instance of WebPage which handles user authentication

=head1 DESCRIPTION

Display a login form and handle user authentication

=head1 METHODS

=over 4

=item * B<init> ()

Initialise the page

=cut

sub init {
  my $self = shift;
  $self->title('User Authentication');
  $self->application->register_component('Login', 'Login');
}

=pod

=item * B<output> ()

Returns the html output of the Login page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $login = $application->component('Login');

  my $html = $login->output();
  $html .= "<br>&raquo; <a href='".$application->url."?page=Register'>Register a new account</a>";
  $html .= "<br>&raquo; <a href='".$application->url."?page=RequestNewPassword'>Forgot your password?</a>";

  return $html;
}

sub supported_rights {
  return [ [ 'login', '*', '*' ] ];
}
