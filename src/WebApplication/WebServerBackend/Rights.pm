package WebServerBackend::Rights;

# WebServerBackend::Rights - object to represent rights in the web application

# $Id: Rights.pm,v 1.4 2008-02-21 17:36:56 paarmann Exp $

use strict;
use warnings;

1;


=pod

=head1 NAME

WebServerBackend::Rights - object to represent rights in the web application

=head1 DESCRIPTION

This package contains methods to extend the automatically generated methods 
of the Rights object.

=head1 METHODS

=over 4

=item * B<data_id_readable> ()

This method returns a human readable, short name of the data_id that
is referenced by this Right. If no 'translation' was found it will 
fallback to the raw data_id.

=cut

sub data_id_readable {
  my $self = shift;
  my $id = $self->data_id || '';

  # check if data_type is *
  if ($self->data_type eq '*') {
    return '';
  }
 
  # Scopes
  elsif ($self->data_type eq 'scope') {
    return 'all' if ($id eq '*');
    my $scope = $self->_master->Scope->get_objects({'_id' => $id});
    if (scalar(@$scope)) {
      return $scope->[0]->name_readable;
    }
    else {
      die "Unable to find scope $id.";
    }
  }

  # Users
  elsif ($self->data_type eq 'user') {
    return 'all' if ($id eq '*');
    my $user = $self->_master->User->get_objects({'_id' => $id});
    if (scalar(@$user)) {
      return $user->[0]->lastname.', '.$user->[0]->firstname;
    }
    else {
      die "Unable to find user $id.";
    }
  }
  
  # Genome
  elsif ($self->data_type eq 'genome') {
    return 'all' if ($id eq '*');
    # somehow fetch the full name
    return $id; 
  }

  # Subsystem
  elsif ($self->data_type eq 'subsystem') {
    return 'all' if ($id eq '*');
    $id =~ s/_/ /g;
    return $id;
  }
  
  # data types with only the '*' as data id
  elsif ($self->data_type eq 'registration_mail' or
	 $self->data_type eq 'problem_list') {
    return '';
  }

  return $id;

} 



=pod

=item * B<check_database> (I<fix>)

This method checks the primary attributes, the scope, as well as some of the
data types and data ids. It prints to STDERR if problems are identified. 
If the optional I<fix> is provided and true, the method will delete broken
right entries from the database.
Currently this is used by the script wa_user_check.pl.

=cut

sub check_database {
  my ($self, $fix) = @_;
  my $id = $self->_id();

  # check primary attributes
  unless($self->data_type) {
    print STDERR "[FATAL] Right $id is missing a data type.\n";
  }

  unless($self->data_id) {
    print STDERR "[FATAL] Right $id is missing a data id.\n";
  }


  # check if the scope exists
  my $scope;
  eval {
    $scope = $self->scope;
  };
  if ($@) {
    print STDERR "[FATAL] Right $id references a non existant scope.\n";
    $scope = undef;
  }

  # unless both exist this right is broken anyway
  unless($scope) {
    if($fix) {
      print STDERR "[FIX].. deleting right $id.\n";
      $self->delete;
      return 0;
    }
  }


  # check if it is a user right
  if ($self->data_type eq 'user') {
    unless ($self->data_id eq '*' or
	    scalar(@{$self->_master->User->get_objects({ _id => $self->data_id })})) {
      print STDERR "[FATAL] Right $id has non existant user as data id.\n";
      if($fix) {
	print STDERR "[FIX].. deleting right $id.\n";
	$self->delete;
	return 0;
      }
    }
  }
 
  # check if it is a scope right
  elsif ($self->data_type eq 'scope') {
    unless ($self->data_id eq '*' or
	    scalar(@{$self->_master->Scope->get_objects({ _id => $self->data_id })})) {
      print STDERR "[FATAL] Right $id has non existant scope as data id.\n";
      if($fix) {
	print STDERR "[FIX].. deleting right $id.\n";
	$self->delete;
	return 0;
      }
    }
  }

  # finally, is it a genome right?
  elsif ($self->data_type eq 'genome') {
    
    require FIG;
    my $fig = FIG->new();
    if($fig->genome_version($self->data_id)) {
      print STDERR "[WARN] Right $id concerns a public genome in SEED.\n";
    }

  }

  return 1;

}
