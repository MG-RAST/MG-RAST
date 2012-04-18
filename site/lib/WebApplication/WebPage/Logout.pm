package WebPage::Logout;

# Logout - webpage to logout authenticated users

# $Id: Logout.pm,v 1.3 2009-10-23 20:04:03 jared Exp $

use strict;
use warnings;

use base qw( WebPage );

1;


=pod

=head1 NAME

Logout - logout of authenticated users

=head1 DESCRIPTION

WebPage to provide a logout action

=head1 METHODS

=over 4

=item * B<init> ()

Initialise the page

=cut

sub init {
  my $self = shift;

  $self->omit_from_session(1);

  my $app = $self->application;

  $app->cgi->param('page', $app->default);

  $app->{session} = $app->dbmaster->UserSession->create($app->cgi, 1);

  $app->add_message('info', 'You have been logged out.', 15);

  $app->redirect($app->default);

}


=item * B<output> ()

Returns the html output of the Logout page

=cut

sub output {
  my ($self) = @_;

  # redirect to default in init()
  return '';

}

