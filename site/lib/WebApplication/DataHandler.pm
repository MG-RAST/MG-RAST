package DataHandler;

# DataHandler - abstract data handler used by the web application

# $Id: DataHandler.pm,v 1.1 2007-10-26 19:56:07 paarmann Exp $

use strict;
use warnings;


=pod

=head1 NAME

DataHandler - abstract data handler

=head1 DESCRIPTION

This module is the abstract DataHandler class used by the web application
framework. A data handler is a wrapper to retrieve a certain data source. 

Using a data handler is done by requesting the handle from the application.
Depending on the type of data this may be a PPO database or a FIG/FIGV
object.

=head1 METHODS

=over 4

=item * B<new> (I<application>)

Creates a new instance of the DataHandler object. The constructor requires
a reference to the web application object.

=cut

sub new {
    my ($class, $application) = @_;

    # check application
    unless (ref $application and $application->isa("WebApplication")) {
      die "Invalid application in __PACKAGE__ new.";
    }
    
    my $self = { 'application' => $application, 
	       };
    bless $self, $class;

    return $self;
}


=pod

=item * B<application> ()

Returns the reference to the application object

=cut

sub application {
  return $_[0]->{'application'};
}


=pod

=item * B<handle> ()

Returns the enclosed data handle

=cut

sub handle {
  die "Abstract method 'handle' must be implemented in __PACKAGE__.\n";
}



1;
