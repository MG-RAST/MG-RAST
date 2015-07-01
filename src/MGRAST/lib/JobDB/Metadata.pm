package JobDB::Metadata;

use strict;
use warnings;
use Conf;

1;

sub _webserviceable {
  return 1;
}

sub create {
  die "object type is read only";
}

sub delete {
  die "object type is read only";
}

sub set_attributes {
  die "object type is read only";
}

sub init {
  my ($self, $attributes) = @_;

  my @keys = keys(%$attributes);
  if ($self->is_index(\@keys)) {
    my $objects = $self->get_objects($attributes);
    if (scalar(@$objects) == 1) {
      return $objects->[0];
    } 
    elsif (scalar(@$objects) == 0) {
      return undef;
    } 
    else {
      Confess("Index error. Non-unique return value for unique index.");
    }
  }
  
  Confess("There must be a unique index on the combination of attributes passed.");
}

sub get_objects {
  my ($self, $values) = @_;

  # although this is technically a class method...
  # check that we are called as object method (via DBMaster)
  unless (ref $self) {
    Confess("Not called as an object method.");
  }

  my $package = $self->_master->module_name."::".$self->_class;

  # if called with _id as value try to query cache first
  if (exists $values->{'_id'}) {
    my $obj = $self->_master->cache->object_from_cache( $self->_master, 
							$self->_class, 
							$values->{'_id'}
						      );
    return [ $obj ] if (ref $obj and $obj->isa($package));
  }
  
  # check if values are passed for selection
  unless (defined($values)) {
    $values = {};
  } 
  elsif (ref($values) ne "HASH") {
    die "Second argument must be a hash";
  }
  
  if (scalar(keys(%$values)) > 0) {
    foreach my $key (keys(%$values)) {

      # check if attribute exists
      unless ($key eq '_id' or $self->_knows_attribute($key)) {
	Confess("Object class ".ref($self)." has no attribute '$key'.");
      }
    }
  }
 
  my $objects = [];

  # fetch non-array attributes from database
  my $data = $self->get_data($values);
  foreach my $result (@$data) {

    # try to retrieve a cached version
    my $object = $self->_master->cache->object_from_cache( $self->_master, 
							   $self->_class, 
							   $result->{'_id'}
							 );
    
    unless (ref $object and $object->isa($package)) {
      
      # create a new object from result hash
      $object = $package->_new_from_hash($self->_master, $result);
      
      # update object cache
      unless ($self->_master->no_object_cache) {
	$self->_master->cache->object_to_cache($object);
      }
    }
    
    push(@$objects, $object);
  }
  
  return $objects;
}

sub get_data {
  my ($self, $values) = @_;

  my $data = [];
  unless ($values) {
    $values = {};
  }

  my $params = { public => 1 };
  
  if ($values && $values->{id} && ref($values->{id}) ne 'ARRAY') {
    my ($id) = $values->{id} =~ /mgm(.*)/;
    $params->{metagenome_id} = $id;
  }

  my $jobs = $self->_master->Job->get_objects( $params );
  foreach my $job (@$jobs) {
    my $obj = {};
    $obj->{_id} = $job->{_id};
    $obj->{id} = "mgm".$job->{metagenome_id};
    $obj->{about} = "mobedac metagenome";
    $obj->{name} = $job->{name};
    $obj->{url} = $Conf::cgi_url.'linkin.cgi?id='.$obj->{id};
    $obj->{version} = $job->{server_version};
    $obj->{creation} = $job->{created_on};
#    $obj->{sample} = $job->sample->{ID};

    push(@$data, $obj);
  }
  
  my $filtered_data = [];
  foreach my $obj (@$data) {
    my $fits = 1;
    foreach my $key (keys(%$values)) {
      next if ($key eq 'id' && ref($values->{id}) ne 'ARRAY');
      if (ref($values->{$key}) eq 'ARRAY') {
	if ($values->{$key}->[1] eq 'like') {
	  $values->{$key}->[0] =~ s/\%/\.\*/g;
	  my $x = $values->{$key}->[0];
	  if ($values->{$key}->[0] !~ /$x/) {
	    $fits = 0;
	    last;
	  }
	} elsif ($values->{$key}->[1] eq '!=') {
	  if ($obj->{$key} eq $values->{$key}->[0]) {
	    $fits = 0;
	    last;
	  }
	} elsif ($values->{$key}->[1] eq '=') {
	  if ($obj->{$key} ne $values->{$key}->[0]) {
	    $fits = 0;
	    last;
	  }
	} elsif ($values->{$key}->[1] eq '<') {
	  if ($values->{$key}->[0] =~ /^[+-]?(?=\.?\d)\d*\.?\d*(?:e[+-]?\d+)?\z/i) {
	    if ($obj->{$key} > $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  } else {
	    if ($obj->{$key} gt $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  }
	} elsif ($values->{$key}->[1] eq '>') {
	  if ($values->{$key}->[0] =~ /^[+-]?(?=\.?\d)\d*\.?\d*(?:e[+-]?\d+)?\z/i) {
	    if ($obj->{$key} < $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }	  
	  } else {
	    if ($obj->{$key} lt $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  }
	} elsif ($values->{$key}->[1] eq '<=') {
	  if ($values->{$key}->[0] =~ /^[+-]?(?=\.?\d)\d*\.?\d*(?:e[+-]?\d+)?\z/i) {
	    if ($obj->{$key} >= $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  } else {
	    if ($obj->{$key} ge $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  }
	} elsif ($values->{$key}->[1] eq '>=') {
	  if ($values->{$key}->[0] =~ /^[+-]?(?=\.?\d)\d*\.?\d*(?:e[+-]?\d+)?\z/i) {
	    if ($obj->{$key} <= $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  } else {
	    if ($obj->{$key} le $values->{$key}->[0]) {
	      $fits = 0;
	      last;
	    }
	  }
	} else {
	  next;
	}
      } else {
	if ($obj->{$key} ne $values->{$key}) {
	  $fits = 0;
	  last;
	}
      }
    }
    if ($fits) {
      push(@$filtered_data, $obj);
    }
  }
  
 return $filtered_data;
}

sub AUTOLOAD {
  my $self = shift;
  
  unless (ref $self) {
    Confess("Not called as an object method.");
  }

  # assemble method call from AUTOLOAD call
  my $call = our $AUTOLOAD;
  return if $AUTOLOAD =~ /::DESTROY$/;
  $call =~ s/.*://;  

  # check if DBObject contains the attribute called $call
  if ($self->_knows_attribute($call)) {

    # register AUTOLOADS for scalar attributes
    if ($self->attributes->{$call}->[0] == DB_SCALAR) {
      no strict "refs";   
      *$AUTOLOAD = sub { $_[0]->set_attributes({ $call => $_[1] }) if ($_[1]); return $_[0]->{$call} };
    }
    
    # check if array attribute is already initialised
    elsif ($self->attributes->{$call}->[0] == DB_ARRAY_OF_SCALARS or
	   $self->attributes->{$call}->[0] == DB_ARRAY_OF_OBJECTS) {
      unless (exists($self->{$call})) {
	$self->{$call} = [];
	tie @{$self->{$call}}, 'DBSQLArray', $self, $call;
      }
    }
    
    # check if the object attribute already contains the object
    elsif ($self->attributes->{$call}->[0] == DB_OBJECT) {

      if (defined $self->{$call} and 
	  ref($self->{$call}) ne $self->attributes->{$call}->[1]) {
	
	my ($refclass) = ($self->attributes->{$call}->[1] =~ /\w+::(\w+)/);
	
	# resolve object
	my $object = $self->_master->fetch_by_ref( $self->{'_'.$call.'_db'}, $refclass, $self->{$call} );
	unless (ref $object) {
	  Confess("Unable to fetch attribute '$call' of " . ref($self) . " id " . $self->{_id} . " from db '".$self->_master->{references_dbs}->{$self->{'_'.$call.'_db'}}->{database}."' of type '".$refclass."' with id ".$self->{$call}.".");
	}
	$self->{$call} = $object;
      }
      
    }
    
    return $self->{$call};
    
  }
  else {
    Confess("Object class ".ref($self)." has no attribute '$call'.");
  }
  
}
