package WebServerBackend::UserHasScope;

# WebServerBackend::UserHasScope - association between Users and Scopes

# $Id: UserHasScope.pm,v 1.2 2008-02-21 17:35:09 paarmann Exp $

use strict;
use warnings;

1;

=pod

=head1 NAME

WebServerBackend::UserHasScope - association between Users and Scopes

=head1 DESCRIPTION

This package contains methods to extend the automatically generated methods 
of the UserHasScope object.

=head1 METHODS

=over 4

=item * B<check_database> (I<fix>)

This method checks the wether both scope and user exist and prints to STDERR if 
problems are identified. If the optional I<fix> is provided and true, the method
will remove UserHasScope objects that are referencing a non-existant user or
scope. Currently this is used by the script wa_scope_check.pl.

=cut

sub check_database {
  my ($self, $fix) = @_;
  my $id = $self->_id();

  # check if the user exists
  my $user;
  eval {
    $user = $self->user;
  };
  if ($@) {
    print STDERR "[FATAL] UserHasScope $id references a non existant user.\n";
    $user = undef;
  }

  # check if the scope exists
  my $scope;
  eval {
    $scope = $self->scope;
  };
  if ($@) {
    print STDERR "[FATAL] UserHasScope $id references a non existant scope.\n";
    $scope = undef;
  }
  
  unless($user and $scope) {
    if($fix) {
      print STDERR "[FIX].. deleting association UserHasScope $id.\n";
      $self->delete();
    }
  }

  return 1;

}
