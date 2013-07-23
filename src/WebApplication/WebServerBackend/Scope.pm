package WebServerBackend::Scope;

# WebServerBackend::Scope - object to represent scopes in the web application

# $Id: Scope.pm,v 1.6 2008-02-21 17:35:09 paarmann Exp $

use strict;
use warnings;

1;

=pod

=head1 NAME

WebServerBackend::Scope - object to represent scopes in the web application

=head1 DESCRIPTION

This package contains methods to extend the automatically generated methods 
of the Scope object.

=head1 METHODS

=over 4

=item * B<users> ()

This method returns an array reference of all User objects that have this Scope.

=cut

sub users {
  my ($self) = @_;

  my @users = map { $_->user() } @{$self->_master->UserHasScope->get_objects({ 'scope' => $self, 'granted' => 1 })};
  return \@users;

}


=pod

=item * B<rights> (I<granted>)

Returns an array reference to all Rights that given to this Scope. If the
optional parameter I<granted> is given, the query will include this value
in the get_objects call of the Rights.

=cut

sub rights {
  my ($self, $granted) = @_;

  my $master = $self->_master();
  my $rights = [];
 
  if (defined($granted)) {
    push(@$rights, @{$master->Rights->get_objects({ 'scope' => $self, 'granted' => $granted })});
  } else {
    push(@$rights, @{$master->Rights->get_objects({ 'scope' => $self })});
  }

  return $rights;
}


=pod

=item * B<has_right_to> (I<application>, I<right>, I<data_type>)

This method return the data ids of the given data_type I<data_type> this scope 
has the right (I<right>) to in this application (I<application>). If the list
of data ids contains the place holder '*' it will be returned as the first
entry of the list. I<application> may be undefined.

=cut

sub has_right_to {
  my ($self, $application, $right, $data_type) = @_;
						     
  # sanity check parameters
  if ($application) {
    unless (ref $application && $application->isa('WebApplication')) {
      die "Method Scope->has_right_to called without a valid application parameter.\n";
    }
  }
  unless ($right) {
    die "Method Scope->has_right_to called without the parameter right.\n";
  }
  unless ($data_type) {
    die "Method Scope->has_right_to called without the parameter data_type.\n";
  }

  my $rights = $self->_master->Rights->get_objects({ name => $right,
						     data_type => $data_type,
						     application => $application,
						     scope => $self,
						     granted => 1,
						   });

  my @data = map { $_->data_id } @$rights;
  @data = sort { return ($a ne '*'); } @data;
  return \@data;

}


=pod

=item * B<is_user_scope> ()

Returns true if this scope is an user scope.

=cut

sub is_user_scope {
  return if ($_[0]->name =~ /^user\:(.*)$/);
}


=pod

=item * B<name_readable> ()

This method returns a human readable, short name of the Scope. If no
'translation' was found it will fallback to the raw name of the Scope.

=cut

sub name_readable {
  my $self = shift;
  my $name = $self->name;
  
  # user scopes
  if ($name =~ /^user\:(.*)$/) {
    my $user = $self->_master->User->init({ login => $1 });
    if (ref $user) {
      return "User: ".$user->lastname.", ".$user->firstname;
    }
    else {
      die "Found a user scope without a user: $name";
    }
  }

  # Reviewer
  elsif ($self->description && $self->description =~ /^Reviewer_/) {
    my $num = scalar(@{$self->_master->UserHasScope->get_objects( { scope => $self } )});
    return "Reviewer Access ($num registered)";
  }

  # Admin 
  elsif ($name eq 'Admin') {
    return "Software Administrators (".$self->application->name.")";
  }

  # Core_Annotators
  elsif ($name eq 'Core_Annotators') {
    return "Core SEED Annotators";
  }
  
  # AdminGroup, DeveloperGroup, WriterGroup
  elsif ($name eq 'AdminGroup' or
	 $name eq 'DeveloperGroup' or
	 $name eq 'WriterGroup' ) {
    return "TWiki Group $name";
  }

  # CGAT school_teacher
  elsif ($name eq 'school_teacher') {
    return "CGAT Teacher Group";
  }

  # Public
  elsif ($name eq 'Public') {
    return "Public Data Scope";
  }
  
  # DataMasterGenome
  elsif ($name eq 'DataMasterGenome') {
    return "Data Administrator (Genomes)";
  }

  return $name;

}


=pod

=item * B<check_database> (I<fix>)

This method checks the primary attributes and wether the scope has any members.
It prints to STDERR if possible problems are identified. If the optional I<fix> 
is provided and true, the method will do remove user scopes without members.
Currently this is used by the script wa_scope_check.pl.

=cut

sub check_database {
  my ($self, $fix) = @_;
  my $id = $self->_id();

  # check primary attributes
  unless($self->name) {
    print STDERR "[FATAL] Scope $id is missing a name.\n";
  }

  my $name = $self->name || '<undefined>';

  unless($self->description) {
    print STDERR "[WARN] Scope $id ($name) is missing a description.\n";
  }

  
  # check if anyone has that scope
  my $has = $self->_master->UserHasScope->get_objects({ scope => $self });
  unless (scalar(@$has)) {
    print STDERR "[FATAL] Scope $id ($name) has no members.\n";

    if($fix) {
      if ($name =~ /^user:/) {
	print STDERR "[FIX] .. deleting user scope without user object.\n";
	$self->delete;
	return 0;
      }
    }
  }

  return 1;

}
