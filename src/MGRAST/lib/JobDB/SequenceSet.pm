package JobDB::SequenceSet;

use strict;
use warnings;

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
      die("Index error. Non-unique return value for unique index.");
    }
  }
  
  die("There must be a unique index on the combination of attributes passed.");
}

sub get_objects {
  my ($self, $values, $user) = @_;

  # although this is technically a class method...
  # check that we are called as object method (via DBMaster)
  unless (ref $self) {
    die("Not called as an object method.");
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
	die("Object class ".ref($self)." has no attribute '$key'.");
      }
    }
  }
 
  my $objects = [];

  # fetch non-array attributes from database
  my $data = $self->get_data($values, $user);
  foreach my $result (@$data) {
    # create a new object from result hash
    my $object = $package->_new_from_hash($self->_master, $result);    
    push(@$objects, $object);
  }
  
  return $objects;
}

sub get_data {
  my ($self, $values, $user) = @_;

  my $data = [];
  unless ($values) {
    $values = {};
  }

  my ($pref, $mgid, $job, $stageid, $stagenum);
  
  if ($values && $values->{id} && ref($values->{id}) ne 'ARRAY') {
    ($pref, $mgid, $stageid, $stagenum) = $values->{id} =~ /^(mgm)?([\d\.]+)-(\d+)-(\d+)$/;

    
    
    $job = $self->_master->Job->get_objects( { metagenome_id => $mgid } );
    if (scalar(@$job)) {
      $job = $job->[0];
      unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
	$job = undef;
      }
    } else {
      $job = undef;
    }
  }

  unless (defined $job) {
    my ($pref, $id) = $values->{id} =~ /^(mgm)?(\d+\.\d+)$/;
    if ($id) {
      $job = $self->_master->Job->get_objects( { metagenome_id => $id } );
      if (scalar(@$job)) {
	return $self->get_all_sets($id, $user);
      }
    } else {
      return [];
    }
  }

  my $adir = $job->analysis_dir;
  my $stagefilename;
  if (opendir(my $dh, $adir)) {
    my @stagefiles = grep { /^$stageid.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
    closedir $dh;
    $stagefilename = $stagefiles[$stagenum - 1];
  } else {
    return [];
  }

  if (open(FH, "<$adir/$stagefilename")) {
    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . (stat("$adir/$stagefilename"))[7] . "\n";
    print "Content-Disposition:attachment;filename=$stagefilename\n\n";
    while (<FH>) {
      print $_;
    }
    close FH;
  }

  exit 0;
}

sub get_all_sets {
  my ($self, $mgid, $user) = @_;

  $mgid =~ s/^mgm(.*)$/$1/;
  my $job = $self->_master->Job->get_objects( { metagenome_id => $mgid } );
  if (scalar(@$job)) {
    $job = $job->[0];
    unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
      $job = undef;
    }
  } else {
    $job = undef;
  }

  unless (defined $job) {
    return [];
  }

  my $adir = $job->analysis_dir;
  my $stages = [];
  if (opendir(my $dh, $adir)) {
    my @stagefiles = grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
    closedir $dh;
    my $stagehash = {};
    foreach my $sf (@stagefiles) {
      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
      next unless ($stageid && $stagename && $stageresult);
      if (exists($stagehash->{$stageid})) {
	$stagehash->{$stageid}++;
      } else {
	$stagehash->{$stageid} = 1;
      }
      push(@$stages, { id => "mgm".$mgid."-".$stageid."-".$stagehash->{$stageid},
		       stage_id => $stageid,
		       stage_name => $stagename,
		       stage_type => $stageresult,
		       file_name => $sf });
    }
    return $stages;
  } else {
    return [];
  }
}

sub AUTOLOAD {
  my $self = shift;
  
  unless (ref $self) {
    die("Not called as an object method.");
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
	  die("Unable to fetch attribute '$call' of " . ref($self) . " id " . $self->{_id} . " from db '".$self->_master->{references_dbs}->{$self->{'_'.$call.'_db'}}->{database}."' of type '".$refclass."' with id ".$self->{$call}.".");
	}
	$self->{$call} = $object;
      }
      
    }
    
    return $self->{$call};
    
  }
  else {
    die("Object class ".ref($self)." has no attribute '$call'.");
  }
  
}
