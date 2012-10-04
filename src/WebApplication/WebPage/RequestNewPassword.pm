package WebPage::RequestNewPassword;

# RequestNewPassword - WebPage to request a password reset

# $Id: RequestNewPassword.pm,v 1.2 2008-04-29 21:08:15 parrello Exp $

use strict;
use warnings;

use base qw( WebPage );

1;

=pod

#TITLE RequestNewPasswordPagePm

=head1 NAME

RequestNewPassword - WebPage to request a password reset

=head1 DESCRIPTION

Display a form to request a new password for an account

=head1 METHODS

=over 4

=item * B<init> ()

Initialise the page

=cut

sub init {
  my $self = shift;
  $self->title('Request a new password');
  $self->application->register_component('RequestNewPassword', 'RequestNewPassword');
  $self->omit_from_session(1);
}

=pod

=item * B<output> ()

Returns the html output of the Register page.

=cut

sub output {
  
  my $content = '<h1>Request a new password</h2>';
  $content .= '<p>Please enter both the login name and the email address of your account to request a new password. You will then shortly receive an email with your new password. We recommend that you change your new password as soon as you receive this mail.</p>';
  
  $content .= shift->application->component('RequestNewPassword')->output;
  
  return $content;

}

