package JobDB::Analysis;
use Data::Dumper;

1;

sub _webserviceable {
  return 1;
}

sub create {
 
   return 0 ;
}

sub delete {
  die "analysis objects cannot be deleted";
}

sub set_attributes {
  die "method set_attributes not available for this virtual object";
}

sub init {
  my ($self, $attributes, $user) = @_;

  my @keys = keys(%$attributes);
  if ($self->is_index(\@keys)) {
    my $objects = $self->get_objects($attributes, $user);
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

  $opts->{base_url} = ' error ' unless   $opts->{base_url} ;

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
  my $data = $self->get_data($values , $opts);
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
  my ($self, $values, $opts ) = @_;

  my $data = [];

  use CGI;
  $CGI::LIST_CONTEXT_WARN = 0;
  $CGI::Application::LIST_CONTEXT_WARN = 0;
  my $cgi = new CGI;
  my $base_url = $cgi->url ;

  my $date = `date`;
  chomp $date;

  my $mgid = $values->{id} || '' ;
  $mgid =~ s/^mgm// ;

  my $obj = {
	     _id => '' ,
	     about => 'metagenome analysis resource' ,
	     name => undef ,
	     id =>  $values->{id} ,
	     url => $base_url . "/analysis/" .  $values->{id} ,
	     version => '0.1 alpha',
	     created => $date,
	     data => { },
	     provenance => {},
	    };

  my $job = $self->_master->Job->init( { metagenome_id => $mgid } );
  if ($job and ref $job){
    my ($list , $stages) = $self->create_file_list($job , $base_url);
    $obj->{data} = $list ;
    $obj->{stages} = $stages ;
  }

  push @$data, $obj ;
  return $data ;
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

sub create_file_list{
  my ($self, $job, $base_url) = @_ ;
  
  my $screened = 0 ;
  my $files = {} ;
  my $stages = {} ;
  # analysis    
  my $dir =  $job->download_dir(1);
  opendir(DATA, $dir ) or die "Can't open download dir $dir\n"  ;
  my @files = readdir DATA ;

  foreach my $file (sort @files){
    next unless -f "$dir/$file" ;

    my ($sid , $sname) = $file =~/^(\d+)\.([^\.]+)/ ; 
    
    if ($file =~ /\.info$/){
      $stages->{ $sid }->{ info } = `fgrep -v "#" $dir/$file` ;
      $stages->{ $sid }->{ name } = $sname  unless ($sname =~/load/); 
    }
    elsif( $file =~ /\.stats$/ ){}
    else{
      push @{$stages->{$sid}->{files}} , $file ;
    }

    my $compression = undef ;
    $compression = "gzip" if ($file =~/.gz$/);
    my $type = 'txt' ;
    if ($compression){ ( $file =~ /faa\.gz|fna\.gz/ ) ? $type = 'fasta' : '' ; }
    else{  ( $file =~ /faa|fna|fasta/) ? $type = 'fasta' : '' ;  }

    $files->{ $file } = { type => $type ,
			  size => -s  $job->download_dir(1) . "/$file"  ,
			  compression => $compression ,
			  description => undef ,
			  url => "$base_url/analysis/data/id/mgm".$job->metagenome_id."/file/$file",
			} ;
    
  }

  return ($files, $stages);
}

sub data {
  my ($self, $params, $user) = @_;

  unless ($params->{id} && $params->{file}) {
    print $cgi->header('text/plain');
    print "ERROR: missing id or file in analysis call";
    exit 0;
  }

  my $mgid = $params->{id};
  $mgid =~ s/^mgm(.*)$/$1/;
  my $job = $self->_master->Job->init( { metagenome_id => $mgid } );
  unless (ref($job)) {
    print $cgi->header('text/plain');
    print "ERROR: could not retrieve job from database";
    exit 0;
  }
  unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $mgid))) {
    print $cgi->header('text/plain');
    print "ERROR: insufficient permissions to access this data";
    exit 0;
  }

  my $dir =  $job->download_dir(1);
  my $file = $params->{file};

  if (open(FH, "<$dir/$file")) {
    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . (stat("$dir/$file"))[7] . "\n";
    print "Content-Disposition:attachment;filename=$file\n\n";
    while (<FH>) {
      print $_;
    }
    close FH;
    exit 0;
  } else {
    print $cgi->header('text/plain');
    print "ERROR: could not open file @$";
    exit 0;
  }
}
