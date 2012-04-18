package DBMaster;

# DBMaster - db master module to access a db space

# $Id: DBMaster.pm,v 1.14 2011-02-11 04:52:16 chenry Exp $

use strict;
use warnings;

use DBI;

use DBObjectCache;
use PPOBackend;

1;

=pod

=head1 NAME

DBMaster - db master module to access a db space

=head1 HOW TO USE

use DBMaster;

my $master = DBMaster->new(-database => 'my_database_name');

my $master = DBMaster->new(-database => 'my_database_file',
                           -backend  => 'SQLite')


=head1 METHODS

=over 4

=item * B<new> (-backend  => I<backend_type, 
                -database => I<database_name>)

Creates a new DB master instance using the database backend type given in 
I<backend_type> reading the database I<database_name>. I<backend_type> can be
omitted and will default to 'MySQL'. I<database_name> is mandatory and has to 
be a database which is managed by the database generator and located on the 
current database host.
 
A DB master is responsible for connecting to the database management system and 
for performing the necessary checks to initialise the database. 
Once created it is used to invoke objects which are part of its database space 
(refer to DBObject for more detailed information).

MySQL

The MySQL backend will try to connect to a mysql server running on localhost using 
the default port, user 'root' and no password. It understand the following additional
parameters to change this behaviour.

Either -host => hostname or $ENV{DBHOST} will change the host,
-port => port or $ENV{DBPORT} will change the port,
set -user => username or $ENV{DBUSER} to change the database user, 
together with -password => password or $ENV{DBPWD} the clear text password.

SQLite

The SQLite Backend does not take any additional parameters. It expects to find the 
database file I<database_name> accessible from where it is running under it's process
user id.

=cut

sub new {
  my $class = shift;
  my %params = @_;

  unless ($params{-database}) {
    die "No database name given.";
  }

  # init params
  $params{-backend} = ($params{-backend}) ? $params{-backend} : 'MySQL';
  $params{-host} = ($ENV{'DBHOST'}) ? $ENV{'DBHOST'} : 'localhost'
    unless ($params{-host});
  $params{-port} = ($ENV{'DBPORT'}) ? $ENV{'DBPORT'} : undef
    unless ($params{-port});
  $params{-user} = ($ENV{'DBUSER'}) ? $ENV{'DBUSER'} : 'root'
    unless ($params{-user});
  $params{-password} = ($ENV{'DBPWD'}) ? $ENV{'DBPWD'} : ''
    unless ($params{-password});
  # try to fetch from object cache

  my $self;

  $self = &cache()->master_from_cache($params{-backend}, $params{-database});
  
  if (ref $self) {

    # reconnect to the backend
    $self->{'backend'} = PPOBackend->new(%params);

  } else {

    # init object hash
    $self = { 'backend' => PPOBackend->new(%params),
	      'module_name' => undef,
	      'classes' => {},
	      'password' => $params{-password},
	      'user' => $params{-user},
	      'references_dbs' => {},
	      'references_idx' => {},
	      'no_object_cache' => 0,
	    };
    bless ($self,$class);

    # register types with databases
    $self->register_db_classes();
    
    # initialise references
    $self->init_db_references();
    
    # add master to object_cache 
    $self->cache->master_to_cache($self);

  }

  return $self;
  
}

sub no_object_cache {
  my ($self, $no) = @_;

  if (defined($no)) {
    $self->{no_object_cache} = $no;
  }

  return $self->{no_object_cache};
}

=pod

=item * B<cache> ()

Returns a reference to the DBObjectCache (class method)

=cut

sub cache {
  my $cache = DBObjectCache->init();
  unless (ref $cache) {
    die "Unable to init DBObjectCache.";
  }
  return $cache;
}


=pod

=item * B<register_db_classes> ()

Reads all the class names which are supported by this database and sets the module name. 
This method is usually called internally. 

=cut

sub register_db_classes {
  my ($self) = @_;

  # fetch module space name from database
  my ($module) = $self->backend->get_row( $self->backend->get_table_name('_metainfo'),
					  [ 'info_value' ], "info_name='module_name'" );
  $self->{'module_name'} = $module;
  unless ($module) {
    die "Unable to read module_name from table '_metainfo'.";
  }
  
  # require the object base
  my $objbase = $module.'::ObjectBase';
  {
    no strict;
    eval "require $objbase;";
    die "Failed on require $objbase: $@" if ($@);
  }
  
  # fetch class names from database
  my $objects = $self->backend->get_rows( $self->backend->get_table_name('_objects'), [ 'object' ] );
  
  unless (scalar(@$objects)) {
    die "No object class names found in table '_objects'.";
  }

  foreach (@$objects) {
    my $object_class_name = $_->[0];
    if (exists($self->{'classes'}->{$object_class_name})) {
      die "Duplicate class name '$object_class_name'.";
    }
    else {
      $self->{'classes'}->{$object_class_name} = 1;
    }
  }

  return $self;

}

=pod

=item * B<init_db_references> ()

Initialises the mapping table for references to objects (within one databases 
and across databases). This method is usually called internally. 

=cut

sub init_db_references {
  my ($self) = @_;

  # fetch reference map from database
  my $refs = $self->backend->get_rows( $self->backend->get_table_name('_references'),
				       [ '_id', '_database', '_backend_type', '_backend_data' ] );

  # populate internal reference mapping table
  foreach (@$refs) {
    my ($id, $database, $backend_type, $backend_data) = @$_;
    if (exists($self->{'references_dbs'}->{$id})) {
      die "Duplicate database reference mapping '$id' to '$database'.";
    }
    else {
      $self->{'references_dbs'}->{$id} = { database => $database,
					   backend_type => $backend_type,
					   backend_data => $backend_data,
					 };
      $self->{'references_idx'}->{$backend_type} = {} 
	unless (exists ($self->{'references_idx'}->{$backend_type}));
      $self->{'references_idx'}->{$backend_type}->{$database} = $id;
    }
  }

  return $self;
}


=pod

=item * B<translate_ref_to_ids> ()

Return an id tuple matching this object reference. The tuple consists of 
the internal database/backend id and the internal object id. 

Return value of the method is a list.

=cut

sub translate_ref_to_ids {
  my ($self, $object) = @_;

  unless ($object->isa('DBObject')) {
    die "No DBObject reference given: ".ref($object).".";
  }

  my $database = $object->_master->database;
  my $b_type   = $object->_master->backend->type;
  my $b_data   = $object->_master->backend->connect_data;

  unless (exists($self->{'references_idx'}->{$b_type}) and
	  exists($self->{'references_idx'}->{$b_type}->{$database})) {
    
    my $new = $self->backend->insert_row($self->backend->get_table_name('_references'),
					 { '_database'     => $database,
					   '_backend_type' => $b_type,
					   '_backend_data' => $b_data, 
					 });

    $self->{'references_dbs'}->{$new} = { database => $database,
					  backend_type => $b_type,
					  backend_data => $b_data,
					};

    $self->{'references_idx'}->{$b_type} = {} 
      unless (exists ($self->{'references_idx'}->{$b_type}));
    $self->{'references_idx'}->{$b_type}->{$database} = $new;
  
  }

  return ( $self->{'references_idx'}->{$b_type}->{$database}, $object->_id );

}


=pod

=item * B<fetch_by_ref> (I<db_id>, I<class>, I<object_id>)

Fetches an object by the specified reference tuple. I<db_id> is the internal id 
of the databse, I<class> the name of the object class and I<object_id> the 
internal object id. 

=cut

sub fetch_by_ref {
  my ($self, $db_id, $class, $obj_id) = @_;

  return undef unless ( $db_id and $class and $obj_id );
  
  unless (exists $self->{'references_dbs'}->{$db_id}) {
    die "Unknown database reference id: '$db_id'.";
  }
  
  my $fetch = undef;

  my $database = $self->{'references_dbs'}->{$db_id}->{'database'};
  my $backend_type = $self->{'references_dbs'}->{$db_id}->{'backend_type'};
  my $backend_data = $self->{'references_dbs'}->{$db_id}->{'backend_data'};

  # check if object url can be handled by the current master
  if ($self->backend->type eq $backend_type and
      $self->database eq $database) {
    $fetch = $self->$class->new()->get_objects({ '_id' => $obj_id });
  }
  # object to be fetched requires another master
  else {
    my $master = DBMaster->new(-database => $database,
			       -backend  => $backend_type,
			       -user => $self->{user},
			       -password => $self->{password},
			       -connect_data => $backend_data );
    $fetch = $master->$class->new()->get_objects({ '_id' => $obj_id });
  }

  # check result
  if (ref($fetch) eq 'ARRAY') {
    return $fetch->[0];
  }
  return undef;

}


=pod

=item * B<db_handle> ()

Returns the reference to the DBI handle which is connected to the database host 
of this DBMaster 

=cut

sub db_handle {
  return $_[0]->{'backend'}->dbh;
}

=pod

=item * B<backend> ()

Returns the reference to the DBI handle which is connected to the database host 
of this DBMaster 

=cut

sub backend {
  return $_[0]->{'backend'};
}


=pod

=item * B<database> ()

Returns the name of the database   

=cut

sub database {
  return $_[0]->backend->database;
}

=pod

=item * B<module_name> ()

Returns the name of the module which is associated with the database

=cut

sub module_name {
  return $_[0]->{'module_name'};
}


=pod

=item * B<knows_class> (I<object_class_name>)

Returns reference to self (true) if the object class I<object_class_name> is 
part of the database and thus handled by this DBMaster, otherwise undef. 
I<object_class_name> is mandatory.

=cut

sub knows_class {
  my ($self, $object_class_name) = @_;

  if (defined $object_class_name and $self->{'classes'}->{$object_class_name}) {
    return $self;
  }
  return undef;
}


=pod

=back

=head1 INTERNAL METHODS

Internal or overwritten default perl methods. Do not use from outside!

=over 4

=item * B<AUTOLOAD> (I<dbobject_type>)

This version of AUTOLOAD allows convenient calls of DBObject packages through the 
DB master. It ensures that all DBObjects are initialised the correct way and have 
knowledge of their master and database connection.

The method automatically requires the proper package and creates an object instance 
by calling new. It returns the reference to the newly created object. Thus you can 
immediately call another method on it.

=cut

sub AUTOLOAD {
  my $self = shift;
  my $type = ref($self)
    or die "$self is not an object";
  
  # assemble package name from AUTOLOAD call
  my $name = our $AUTOLOAD;
  return if $AUTOLOAD =~ /::DESTROY$/;
  $name =~ s/.*://;   # strip fully-qualified portion
  my $package = $self->module_name.'::'.$name;

  # check if class is supported by master
  unless ($self->knows_class($name)) {
    die "Unsupported object class '$name' in database '".$self->database."'.";
  }

  # use package 
  {
    no strict;
    eval "require $package;";  
    die "Failed on require $package: $@" if ($@);
  }

  # create the object
  my $object = $package->new($self); 
  unless (ref $object) {
    die "Unable to initialise object '$object'.";
  }

  return $object;

}  


=pod

=item * B<DESTROY> ()

Disconnects from database before destroying the DBMaster object.

=cut

sub DESTROY {
  if (ref $_[0]->backend) {
    $_[0]->backend->disconnect();
  }
}


