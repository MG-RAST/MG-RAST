package DBObjectCache;

# DBObjectCache - object cache manager for PPO

# $Id: DBObjectCache.pm,v 1.4 2007-12-13 21:22:07 paarmann Exp $

use strict;
use warnings;

use constant SIZE => 65535;

my $object_cache;

1;

=pod

=head1 NAME

DBObjectCache - object cache manager for PPO

=head1 OBJECT CACHE

The Persistent Perl Objects utilise an object cache which limits each instance 
of DBMaster or DBObject to one perl object representation. Querying or dereferencing
objects will automatically update the internal cache and hand out an existing object
if present.

=head1 METHODS

=over 4

=item * B<init> ()

Returns the reference to the global object cache.

=cut

sub init {

  unless (defined $object_cache) {
    my $class = shift;
    my $this = { '_cache' => {},
	         'recent' => [],
	       };
    $object_cache = bless $this, $class;
  }

  return $object_cache;
}


=pod

=item * B<master_to_cache> (I<DBMaster>)

Stores a DBMaster in the cache and initialises the cache for that database.

=cut

sub master_to_cache {
  my ($self, $master) = @_;

  unless (ref $master and $master->isa('DBMaster')) {
    die 'No DBMaster given.';
  }

  unless (exists $self->{'_cache'}->{$master->backend->type}) {
    $self->{'_cache'}->{$master->backend->type} = {};
  }

  unless (exists $self->{'_cache'}->{$master->backend->type}->{$master->database} and
	  ref $self->{'_cache'}->{$master->backend->type}->{$master->database}->{'master'}) {
    $self->{'_cache'}->{$master->backend->type}->{$master->database} = {};
    $self->{'_cache'}->{$master->backend->type}->{$master->database}->{'master'} = $master;
  }
  
}


=pod

=item * B<master_from_cache> ()

If possible, returns a DBMaster for that database from the cache. 
Returns undef else.

=cut

sub master_from_cache {
  my ($self, $backend, $database) = @_;

  unless (defined $backend) {
    die 'No backend type given.';
  }

  unless (defined $database) {
    die 'No database name given.';
  }
  
  if (exists $self->{'_cache'}->{$backend} and
      exists $self->{'_cache'}->{$backend}->{$database} and
      ref $self->{'_cache'}->{$backend}->{$database}->{'master'}) {
    return $self->{'_cache'}->{$backend}->{$database}->{'master'};
  }
  
  return undef;
}


=pod

=item * B<object_to_cache> (I<DBObject>)

Stores an object in the cache.

=cut

sub object_to_cache {
  my ($self, $object) = @_;
  
  unless (ref $object and $object->isa('DBObject')) {
    die 'No DBObject given.';
  }
  
  my $backend = $object->_master->backend->type;
  my $db = $object->_master->database();

  unless (exists $self->{'_cache'}->{$backend} and
	  exists $self->{'_cache'}->{$backend}->{$db}) {
    die 'Object cache not initialised for this database.';
  }

  my $class = $object->_class();
  unless (exists $self->{'_cache'}->{$backend}->{$db}->{$class}) {
    $self->{'_cache'}->{$backend}->{$db}->{$class} = {};
  }

  my $id = $object->_id();
  unless ($id && ref($self->{'_cache'}->{$backend}->{$db}->{$class}->{$id})) {
    $self->{'_cache'}->{$backend}->{$db}->{$class}->{$id} = $object;

    if (scalar(@{$self->{'recent'}}) > SIZE) {
      $self->delete_object(shift @{$self->{'recent'}});
    }
    push @{$self->{'recent'}}, $object;

  }
  
}


=pod

=item * B<object_from_cache> (I<database_name>, I<class>, I<id>)

If possible, returns the object described by the unique triplet database name, 
class and id. Else it returns undef.

=cut

sub object_from_cache {
  my ($self, $master, $class, $id) = @_;

  unless (defined $master and $master->isa('DBMaster')) {
    die 'No DBMaster given given.';
  }

  unless (defined $class) {
    die 'No class name given.';
  }

  unless (defined $id) {
    die 'No object id given.';
  }
  

  my $backend = $master->backend->type;
  my $db = $master->database();

  unless (exists $self->{'_cache'}->{$backend} and
	  exists $self->{'_cache'}->{$backend}->{$db} and
	  exists $self->{'_cache'}->{$backend}->{$db}->{$class} and
	  ref $self->{'_cache'}->{$backend}->{$db}->{$class}->{$id}
	 ) {
    return $self->{'_cache'}->{$backend}->{$db}->{$class}->{$id};
  }
  
  return undef;
}


=pod

=item * B<delete_object> (I<DBObject>)

Deletes an object from the cache.

=cut

sub delete_object {
  my ($self, $object) = @_;
  
  unless (ref $object and $object->isa('DBObject')) {
    die 'No DBObject given.';
  }
  
  my $backend = $object->_master->backend->type;
  my $db = $object->_master->database();

  unless (exists $self->{'_cache'}->{$backend} and
	  exists $self->{'_cache'}->{$backend}->{$db}) {
    die 'Object cache not initialised for this database.';
  }
  
  my $class = $object->_class();
  my $id = $object->_id();

  if ($id && exists($self->{'_cache'}->{$backend}->{$db}->{$class}) && exists($self->{'_cache'}->{$backend}->{$db}->{$class}->{$id})) {
      delete $self->{'_cache'}->{$backend}->{$db}->{$class}->{$id};
  }
}
