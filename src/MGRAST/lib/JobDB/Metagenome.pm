package JobDB::Metagenome;

use strict;
use warnings;

1;

sub _webserviceable {
  return 1;
}

sub create {
  die "object type Metagenome is read only";
}

sub delete {
  die "object type Metagenome is read only";
}

sub set_attributes {
  die "object type Metagenome is read only";
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
  my ($self, $values, $user) = @_;

  my $data = [];
  unless ($values) {
    $values = {};
  }

  my $params = {};
  
  if ($values && $values->{id}) {
    if (ref($values->{id}) eq 'ARRAY') {
      my ($pref, $id) = $values->{id}->[0] =~ /(mgm)?(.*)/;
      $params->{metagenome_id} = [ $id, $values->{id}->[1] ];
    } else {
      my ($pref, $id) = $values->{id} =~ /(mgm)?(.*)/;
      $params->{metagenome_id} = $id;
    }
  }
  
  use CGI;
  $CGI::LIST_CONTEXT_WARN = 0;
  $CGI::Application::LIST_CONTEXT_WARN = 0;
  my $cgi = new CGI;
  my $url_base = $cgi->url;

  my $jobs = $self->_master->Job->get_objects( $params );
  foreach my $job (@$jobs) {
    next unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id})));
    my $obj = {};
    $obj->{_id} = $job->{_id};
    $obj->{id} = "mgm".$job->{metagenome_id};
    $obj->{about} = "metagenome";
    $obj->{name} = $job->{name};
    $obj->{url} = $url_base.'/metagenome/'.$obj->{id};
    $obj->{version} = 1;
    $obj->{created} = $job->{created_on};
    $obj->{sample} = $job->sample ? "mgs".$job->sample->{ID} : undef;
    $obj->{sample} =~ s/^(.*)\..+/$1/;
    
    if (scalar(keys(%$values))) {
      $obj->{library} = $job->sample ? "mgl".$job->sample->{ID} : undef;

      my $pjs = $self->_master->ProjectJob->get_objects( { job => $job } );
      $obj->{project} = scalar(@$pjs) ? "mgp".$pjs->[0]->project->{id} : undef;

      # get metadata
      my $metadata_entries = $self->_master->MetaDataEntry->get_objects( { job => $job } );
      my $metadata = {};
      foreach my $md (@$metadata_entries) {
	$metadata->{$md->{tag}} = $md->{value};
      }
      $obj->{metadata} = $metadata;
    }

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

sub comprehensive_list {
  my ($self) = @_;

  my $jobs = $self->_master->Job->fetch_browsepage_viewable();
  
  use CGI;
  my $cgi = new CGI;
  if ($cgi->param('scope')) {
    my $jg = $self->_master->Jobgroup->get_objects( { name => $cgi->param('scope') } );
    if (scalar(@$jg)) {
      $jg = $jg->[0];
      my $pjs = $self->_master->JobgroupJob->get_objects( { jobgroup => $jg } );
      my $pjh = {};
      %$pjh = map { $_->{job} => 1 } @$pjs;
      @$jobs = map { $pjh->{$_->{_id}} ? $_ : () } @$jobs;
    }
  }

  
  my $mg_list = [];
  @$mg_list = map { { type => 'metagenome',
		      id => $_->{metagenome_id},
		      name => $_->{name},
		      sequence_type => $_->{sequence_type},
		      sequence_method => $_->{sequence_method},
		      server_version => $_->{server_version},
		      file_size_raw => $_->{file_size_raw},
		      viewable => $_->{viewable}, 
		      job_id => $_->{job_id},
		      project => $_->{project},
		      project_id => $_->{project_id},
		      biome => $_->{biome},
		      pi => $_->{pi},
		      pi_firstname => $_->{pi_firstname},
		      pi_email => $_->{pi_email},
		      ph => $_->{ph},
		      country => $_->{country} } }  @$jobs;
  return $mg_list;
}

sub statistics {
  my ($self, $id, $user) = @_;

  $id =~ s/mgm//;

  my $job;
  my $jobs = $self->_master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$jobs)) {
    $job = $jobs->[0];
  } else {
    return [];
  }

  unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
    return [];
  }
  
  my $data = {};

  my $jstats = $self->_master->JobStatistics->get_objects( { job => $job } );
  foreach my $stat (@$jstats) {
    $data->{$stat->{tag}} = $stat->{value};
  }

  return $data;
}

sub analysis {
  my ($self, $id, $user) = @_;

  my $cgi = new CGI;

  $id =~ s/mgm//;

  my $job = $self->_master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$job)) {
    $job = $job->[0];
    unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
      print $cgi->header('text/plain');
      print "ERROR: Insufficient permissions for analysis call for id: ".$id;
      exit 0;
    }
  } else {
    return [];
  }

  # get the defined stats file
  my $adir = $job->analysis_dir;
  if (opendir(my $dh, $adir)) {
    my @allfiles = grep { -f "$adir/$_" } readdir($dh);
    closedir $dh;
    my $stages = {};
    foreach my $f (@allfiles) {
      my ($stageid, $stagename, $result_type, $ending) = $f =~ /(\d+)\.([^\.]+)\.([^\.]+)\.(.+)/;
      next unless ($stageid && $stagename && $result_type && $ending);
      next if (($ending eq "fna.gz") || ($ending eq "faa.gz"));

      if ($cgi->param('file')) {
	my $fn = $cgi->param('file');
	if ($f =~ /$fn/) {
	  if (open(FH, "$adir/$f")) {
	    print "Content-Type:application/x-download\n";  
	    print "Content-Length: " . (stat("$adir/$f"))[7] . "\n";
	    print "Content-Disposition:attachment;filename=$f\n\n";
	    while (<FH>) {
	      print;
	    }
	    close FH;
	  }
	  exit 0;
	}
      } else {
	unless (exists($stages->{$stageid})) {
	  $stages->{$stageid} = { name => $stagename, files => [] };
	}
	if ($ending eq "info") {
	  my $info_text = "";
	  open(FH, "$adir/$f");
	  while (<FH>) {
	    $info_text .= $_;
	  }
	  close FH;
	  $stages->{$stageid}->{info} = $info_text;
	} else {
	  push(@{$stages->{$stageid}->{files}}, $result_type.".".$ending);
	}
      }
    }
    return $stages;
  } else {
    print $cgi->header('text/plain');
    print "ERROR: could not open analysis directory";
    exit 0;
  }  
}

sub types {
  my ($self, $id, $user) = @_;

  $id =~ s/mgm//;

  my $job;
  my $jobs = $self->_master->Job->get_objects( { metagenome_id => $id } );
  if (scalar(@$jobs)) {
    $job = $jobs->[0];
  } else {
    return [];
  }

  unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
    return [];
  }
  
  use MGRAST::Analysis;
  my $mgdb = MGRAST::Analysis->new( $self->_master->db_handle );
  $mgdb->set_jobs([$id]);
  
  return $mgdb->get_sources;
}
