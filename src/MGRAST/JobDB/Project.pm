package JobDB::Project;

use strict;
use warnings;
use Data::Dumper;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

sub _webserviceable {
  return 1;
}

sub last_id {
    my ($self) = @_;

    my $dbh = $self->_master()->db_handle();
    my $sth = $dbh->prepare("SELECT max(id) FROM Project");
    $sth->execute;
    my $result = $sth->fetchrow_arrayref();
    return $result->[0] || "0" ;
}



sub count_all {
 my ($self) = @_;

    my $dbh = $self->_master()->db_handle();
    my $sth = $dbh->prepare("SELECT count(*) FROM Project");
    $sth->execute;
    my $result = $sth->fetchrow_arrayref();
    return ( $result->[0] ) ;
}

sub count_public {
 my ($self) = @_;

    my $dbh = $self->_master()->db_handle();
    my $sth = $dbh->prepare("SELECT count(*) FROM Project where public=1");
    $sth->execute;
    my $result = $sth->fetchrow_arrayref();
    return ( $result->[0] ) ;
}


=pod

=item * B<data> ()

Returns a hash of all stats keys and values for a job. 
If a key is given , returns only hash of specified 
key , value pair. Sets a value if key and value is given

=cut

sub data {
  my ( $self , $tag , $value ) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth ;
  
  if (defined($value) and $tag){

    if (ref $value){
      print STDERR "ERROR: invalid value type for $tag  ($value) \n" ;
      print STDERR Dumper $value ;
      return 0 ;
    }
    
    my $jstat = $self->_master->ProjectMD->get_objects( { project   => $self ,
							  tag       => $tag  ,
							  value     => $value ,
							});
    if ( ref $jstat and scalar @$jstat ){
      $jstat->[0]->value($value) ;
    }
    else{
      $jstat = $self->_master->ProjectMD->create( { project   => $self ,
						    tag       => $tag  ,
						    value     => $value ,
						  });
    }

    return $value  ;
  }
  elsif( $tag ){
    $sth = $dbh->prepare("SELECT tag, value FROM ProjectMD where project='". $self->_id ."' and tag='$tag'") ;
    $sth->execute;
     my $results = $sth->fetchall_arrayref();
  
    return map { $_->[1] } @$results ;
  }
  else{
    $sth = $dbh->prepare("SELECT tag, value FROM ProjectMD where project='". $self->_id ."'");
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
  return $rhash;
}


# internal method , returns _id for all jobs of a project a user has access to 
sub _job_ids {
  my ($self) = @_ ;

  my $user      = $self->_master->{_user} ;
  my $dbh       = $self->_master->db_handle;
  my $sth ;
  my $jobs      = [] ;
  my $user_jobs = {} ;
  
  $sth = $dbh->prepare("select Job._id , Job.job_id , Job.metagenome_id , Job.name , Job.viewable , Job.public  from ProjectJob , Job  where ProjectJob.project=".$self->_id." and Job._id = ProjectJob.job") ;
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  
  if ($user and ref $user){
    my $ujr = defined($user) ? $user->has_right_to(undef, 'view', 'metagenome') : [];
    %$user_jobs = map { $_ => 1 } @$ujr;
  }
  
  my @pjobs   = map { $_->[0] } grep { $user_jobs->{$_->[2]} || $user_jobs->{'*'} || $_->[5] } @$results;
  
  return \@pjobs ;
}


# list of all metagenomes for this project
sub metagenomes {
  my ($self , $id_only) = @_ ;
  
  my $dbh = $self->_master->db_handle;
  my $sth ;
  my $metagenomes = [] ;
  
  if ($id_only){
    $sth = $dbh->prepare("select Job.metagenome_id , from ProjectJob , Job , where ProjectJob.project=".$self->_id." and Job._id = ProjectJob.job") ;
    $sth->execute;
    my $results = $sth->selectcol_arrayref();
  
    return $results ;

  }
  else{
    foreach my $pjs ( @{ $self->_master->ProjectJob->get_objects( {  project => $self }) }){
      push @$metagenomes , $pjs->job ;
    }
  }
  return $metagenomes ;
}

# return all metagenome ids and names of this project
sub metagenomes_id_name {
  my ($self) = @_ ;
  
  my $dbh = $self->_master->db_handle;
  my $sth;
  my $metagenomes = {};
  
  $sth = $dbh->prepare("select Job.metagenome_id, Job.name from ProjectJob, Job where ProjectJob.project=".$self->_id." and Job._id=ProjectJob.job");
  $sth->execute;
  my $result = $sth->fetchall_arrayref();

  %$metagenomes = map { $_->[0] => $_->[1] } @$result;

  return $metagenomes;
}

sub all_metagenome_ids{
  my ($self) = @_;
  
  my $dbh = $self->_master->db_handle;
  
  # queries
  my $q1 = "select Job.metagenome_id  from ProjectJob , Job  where ProjectJob.project=".$self->_id." and Job._id = ProjectJob.job";
  my $q2 = "select value  from ProjectJob , MetaDataEntry where project = ".$self->_id." and ProjectJob.job = MetaDataEntry.job and ( MetaDataEntry.tag = 'sample_id' ) group by value;"; 
  
  my @results ;
  push @results , ( map { "mgrast:".$_ } @{ $dbh->selectcol_arrayref($q1) } );
  push @results , @{ $dbh->selectcol_arrayref($q2) };
		     
  return \@results ;
}

sub samples {}

# add a job to project
sub add_job {
  my ($self, $job, $noscope) = @_;

  unless ($job and ref($job)) {
    return "error: invalid job object";
  }
  my $check = $self->_master->ProjectJob->get_objects({ job => $job });
  if (scalar @$check) {
    return "error: job already in a project";
  }

  unless ($noscope) {
    my $webappdb = $self->_master->{_user}->_master;
    my $pscope   = $webappdb->Scope->init( { application => undef,
					     name => 'MGRAST_project_'.$self->id } );
    unless ($pscope) {
      $pscope = $webappdb->Scope->create( { application => undef,
					    name => 'MGRAST_project_'.$self->id,
					    description => 'MGRAST Project scope' } );
    }
    my $rights = $webappdb->Rights->get_objects( { scope => $pscope } );
    my %rhash  = map { $_->{data_id} => $_ } @$rights;
    
    unless (exists $rhash{$job->{metagenome_id}}) {
      $webappdb->Rights->create( { granted => 1,
				   name => 'view',
				   data_type => 'metagenome',
				   data_id => $job->{metagenome_id},
				   delegated => 1,
				   scope => $pscope } );
    }
  }
  $self->_master->ProjectJob->create({ job => $job, project => $self });
  return "success: job added";
}

sub pubmed {
  my ($self) = @_;
  
  my $query="select value  from ProjectJob , MetaDataEntry where project = ".$self->_id." and ProjectJob.job = MetaDataEntry.job and ( MetaDataEntry.tag = 'external-ids_pubmed_id' ) group by value;";
  my $dbh = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref($query);

  my $values = {};
  foreach my $tmp (@$results){
    map { $values->{$_}++ } split " ; " , $tmp ;
  }

  return [ keys %$values ] ;
}

sub countries {
  my ($self) = @_;
  
  my $query="select value  from ProjectJob , MetaDataEntry where project = ".$self->_id." and ProjectJob.job = MetaDataEntry.job and ( MetaDataEntry.tag = 'country' or  MetaDataEntry.tag = 'sample-origin_country') group by value;";
  my $dbh = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref($query);

  my $values = {};
  foreach my $tmp (@$results){
    map { $values->{$_}++ } split " ; " , $tmp ;
  }

  return [ keys %$values ] ;
}

sub biomes {
  my ($self) = @_ ;

  my $query="select value  from ProjectJob , MetaDataEntry where project = ".$self->_id." and ProjectJob.job = MetaDataEntry.job and MetaDataEntry.tag in ('env_feature' , 'env_matter' , 'env_biome' , 'biome-information_envo_lite' ) group by value;";
  my $dbh = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref($query);

  my $biomes = {};
  foreach my $tmp (@$results){
    map { $biomes->{$_}++ } split " ; " , $tmp ;
  }

  return [ keys %$biomes ] ;
}


sub sequence_types {
  my ($self) = @_ ;

  my $query="select Job.sequence_type  from ProjectJob , Job where ProjectJob.project = " . $self->_id . " and ProjectJob.job = Job._id  group by Job.sequence_type;";
  my $dbh = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref($query);

  my $biomes = {};
  foreach my $tmp (@$results){
    map { $biomes->{$_}++ } split " ; " , $tmp ;
  }

  return [ keys %$biomes ] ;
}


sub bp_count_raw {
  my ($self) = @_ ;

  my $query   = "select sum(value) from ProjectJob , JobStatistics where project = ".$self->_id." and ProjectJob.job = JobStatistics.job and JobStatistics.tag regexp 'bp_count_raw'" ;
  my $dbh     = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref($query);
  
  return $results->[0] || 0 ;
}

sub metagenomes_summary {
  my ($self) = @_ ;
  my @data ;
  my @header = ('Metagenome ID' , 'Metagenome Name' , '# base pairs' , 'Biome' , 'Location' , 'Country' , 'Sequence Type') ;



  my $dbh = $self->_master->db_handle;
  my $sth ;
  my $metagenomes = [] ;
  
  # get all jobs for this project a user has access to
  my $job_ids = $self->_job_ids;

  # get job info
  my $statement = "select _id , job_id , metagenome_id , name , sequence_type from  Job where _id in ('". join ("','" , @$job_ids )."')" ;
  my $r = $dbh->selectall_hashref( $statement , ['_id']);

  
  # get metadata
  $statement = "select job , tag , value  from MetaDataEntry where job in ('". join ("','" , @$job_ids) ."') and tag in ('country' , 'env_feature' , 'env_matter' , 'env_biome' , 'biome-information_envo_lite',  'sample-origin_country' , 'specific_location' , 'sample-origin_location' )"; 
  my $res    = $dbh->selectall_arrayref( $statement );

  foreach my $row (@$res){
    $r->{ $row->[0] }->{ biome }->{$row->[2]}++  if ($row->[1] =~/env_|biome/);
    $r->{ $row->[0] }->{ country } .= $row->[2] if ($row->[1] =~/^country|sample.+country/);
    $r->{ $row->[0] }->{ location } .= $row->[2] if ($row->[1] =~/location|sample.+location/);
  }


  # get job stats
  my $select_stats =("SELECT job , tag , value FROM JobStatistics where job in ('" . join ("','" , @$job_ids)."') and tag='bp_count_raw' ") ;
  my $stats = $dbh->selectall_hashref( $select_stats , ['job' , 'tag'] );
  

  # join data
  map {  
    my @biomes = ref $r->{ $_ }->{ biome }  ?  keys %{$r->{ $_ }->{ biome }} :  ();
    push @data, [  $r->{ $_ }->{'metagenome_id'},
		   $r->{ $_ }->{name},
		   format_number($stats->{ $_ }->{bp_count_raw}->{value}) || '-' ,
		   (scalar @biomes ? join(" ; ",  @biomes) : "-") ,
		   $r->{ $_ }->{location} || '-',
		   $r->{ $_ }->{country},
		   $r->{ $_ }->{sequence_type} ,
		];
       } @$job_ids ;
  
   return \@data ;

}

##########################
# output methods
#########################

sub xml {
    my ($self) = @_ ;
    my $xml = "<?xml version=\"1.0\" ?>\n" ;
    
    $xml .= "<project id='". $self->id ."'>\n";
    $xml .= "<name>". $self->name ."</name>\n";
    $xml .= "<submitter>". ( $self->creator ? $self->creator->name : 'ERROR:no submitter') ."</submitter>\n";
    
    my $data = $self->_master->ProjectMD->get_objects( { project => $self } );
    foreach my $md (@$data){
      next if ($md->tag =~ /email/ );
      my $value = $md->value ;
	$xml .= "<".$md->tag.">".$value."</".$md->tag.">\n";
    }
    $xml .= "<metagenomes>\n" ;
    foreach my $pjs ( @{ $self->_master->ProjectJob->get_objects( {  project => $self }) }){
      my $j = $pjs->job ;
      next unless ($j and ref $j);
      $xml .=  "<metagenome>\n";
      $xml .=  "\t<metagenome_id namespace='MG-RAST'>". $j->metagenome_id."</metagenome_id>\n";
      $xml .=  "\t<sample_id namespace='MG-RAST'>".$j->sample->ID."</sample_id>\n" if ($j->sample and ref $j->sample);
      $xml .=  "</metagenome>\n";
    }
    $xml .= "</metagenomes>\n";
    $xml .= "</project>\n";
    
    return $xml ;
}

sub tabular {
  my ($self , $all ) = @_ ;
  my $xml = '' ;

  my @header = ( 'project name' , 'project id' ) ;
  my @pdata  = (  $self->name , $self->id ) ;
  
  my $data = $self->_master->ProjectMD->get_objects( { project => $self } );
  foreach my $md (@$data){
    # my $value = $md->value;
    next if ($md->tag eq "sample_collection_id");
    next if ($md->tag =~ /email/ );
    push @header , $md->tag ;
    my $value = $md->value ;
    $value =~ s/(\r\n|\n|\r)/ /g;
    push @pdata  , $value;
  }


  my $jheader = {} ;
  my $jdata   = {} ;
  
  foreach my $pjs ( @{ $self->_master->ProjectJob->get_objects( {  project => $self }) }){
    my $j = $pjs->job ;
    next unless ($j and ref $j);
    my $s = $j->sample ;
    unless ($s and ref $s){
      my $ss = $self->_master->MetaDataCollection->get_objects( { job => $j } );
      $s = shift @$ss if ($ss and scalar @$ss) ;
    } 
    next unless ($s and ref $s);
    my $data = $s->data ;
    #print STDERR Dumper $data ;
    map { ($_ =~ /email/) ? '' : $jheader->{$_}++ } keys %$data ;
    $jdata->{$j->metagenome_id} = $data ;
  }
  
  # print data

  my $output = '';
  $output .= join "\t" , 'metagenome' , @header , keys %$jheader ; 
  $output .= "\n" ;
  foreach my $id (keys %$jdata){
    $output .= join "\t" , $id , @pdata , map { my $tmp = $jdata->{$id}->{$_} || 'unknown' ; $tmp =~ s/(\r\n|\n|\r)/ /g ; $tmp  } keys %$jheader ;
    $output .="\n";
  }

  return $output ;
}



sub verbose {
  my ($self , $all ) = @_ ;
  my $xml = '' ;

  my @header = ( 'project name' , 'project id' ) ;
  my @pdata  = (  $self->name , $self->id ) ;
  
  my $data = $self->_master->ProjectMD->get_objects( { project => $self } );
  foreach my $md (@$data){
    push @header , $md->tag ;
    push @pdata  , $md->value;
  }


  my $jheader = {} ;
  my $jdata   = {} ;
  
  foreach my $pjs ( @{ $self->_master->ProjectJob->get_objects( {  project => $self }) }){
    my $j = $pjs->job ;
    next unless ($j and ref $j);
    my $s = $j->sample ;
    unless ($s and ref $s){
      my $ss = $self->_master->MetaDataCollection->get_objects( { job => $j } );
      $s = shift @$ss if ($ss and scalar @$ss) ;
    } 
    next unless ($s and ref $s);
    my $data = $s->data ;

    map { $jheader->{$_}++} keys %$data ;
    $jdata->{$j->metagenome_id} = $data ;
  }
  
  # print data

  my $output = '';
  
  foreach my $id (keys %$jdata){
    $output .= join "\t" , @pdata , map { $jdata->{$id}->{$_} || 'unknown' } keys %$jheader ;
    $output .="\n";
  }

  return $output ;
}

sub format_number {
  my ($val) = @_;

  unless ($val) { return $val; }
  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}
