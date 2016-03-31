package JobDB::Project;

use strict;
use warnings;
use Data::Dumper;
use MGRAST::Metadata;

use Conf;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

sub create_project {
  my ($self, $user, $name, $metadata, $curator, $public) = @_;

  unless ($metadata && ref($metadata)) {
    $metadata = [];
  }
  my $master = $self->_master();
  $public = $public ? 1 : 0;

  # create project
  my $nid = $master->Project->last_id + 1;
  my $attribs = { id => $nid, name => $name, type => 'study', public => $public };
  if ($curator && ref($curator)) {
    $attribs->{creator} = $curator;
  } 
  my $project = $master->Project->create($attribs);

  # create rights
  # Connect to User/Rights DB
  my $webappdb = DBMaster->new(-database => $Conf::webapplication_db,
			       -backend  => $Conf::webapplication_backend,
			       -host     => $Conf::webapplication_host,
			       -user     => $Conf::webapplication_user,
			      );
  foreach my $right (('view', 'edit', 'delete')) {
    $webappdb->Rights->create( { application => undef,
				 scope => $user->get_user_scope,
				 name => $right,
				 data_type => 'project',
				 data_id => $project->id,
				 granted => 1 } );
  }
  $webappdb->Scope->create( { application => undef,
			      name => 'MGRAST_project_'.$project->id,
			      description => 'MGRAST Project scope' } );
  # add metadata
  foreach my $data (@$metadata) {
    $master->ProjectMD->create( { project => $project,
				  tag     => $data->[0],
				  value   => $data->[1] } );
  }
  return $project;
}

sub delete_project {
  my ($self, $user) = @_;

  my $jobdbm = $self->_master();
  if ($user && $user->has_right(undef, 'edit', 'project', $self->id)) {
    my $udbm = $user->_master();
    my $project_jobs = $jobdbm->ProjectJob->get_objects( { project => $self } );
    foreach my $p (@$project_jobs) {
      $p->delete;
    }
    my $jobs_with_project = $jobdbm->Job->get_objects( { primary_project => $self } );
    foreach my $p (@$jobs_with_project) {
      $p->delete;
    }
    my $project_rights = $udbm->Rights->get_objects( { data_type => 'project', data_id => $self->id  } );
    foreach my $r (@$project_rights) {
      $r->delete;
    }
    my $pscope = $udbm->Scope->init( { application => undef,
				       name => 'MGRAST_project_'.$self->id } );
    if ($pscope) {
      my $uhss = $udbm->UserHasScope->get_objects( { scope => $pscope } );
      foreach my $uhs (@$uhss) {
	$uhs->delete;
      }
      $pscope->delete;
    }
    my $metadbm = MGRAST::Metadata->new->_handle();
    my $project_meta = $metadbm->ProjectMD->get_objects( { project => $self } );
    foreach my $m (@$project_meta) {
      $m->delete;
    }
    $self->delete;
    return 1;
  } else {
    return 0;
  }

  return 1;
}

sub is_empty {
  my ($self) = @_;

  my $db = $self->_master();
  my $query  = "SELECT * FROM ProjectJob p, Job j WHERE p.project=".$self->_id." AND j._id=p.job LIMIT 1";
  my $result = $db->db_handle->selectcol_arrayref($query);
  return ($result && @$result) ? 0 : 1;
  
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
  my $sth = $dbh->prepare("SELECT count(*) FROM Project WHERE public=1");
  $sth->execute;
  my $result = $sth->fetchrow_arrayref();
  return ( $result->[0] ) ;
}

sub get_private_projects {
  my ($self, $user, $edit) = @_;

  unless ($user && ref($user)) { return []; }
  my $ids = $edit ? $user->has_right_to(undef,'edit','project') : $user->has_right_to(undef,'view','project');
  unless ($ids && (@$ids > 0)) { return []; }

  my $private = [];
  my $master  = $self->_master();
  foreach my $id (@$ids) {
    my $p = $master->Project->init( {id => $id} );
    if ($p && ref($p)) {
      push @$private, $p;
    }
  }

  return $private;
}

sub get_public_projects {
  my ($self, $id_only) = @_;

  my $db = $self->_master();
  if ($id_only) {
    my $query  = "select id from Project where public=1";
    my $result = $db->db_handle->selectcol_arrayref($query);
    return ($result && @$result) ? $result : [];
  }
  else {
    return $db->Project->get_objects( {public => 1} );
  }
}

=pod

=item * B<data> ()

Returns a hash of all MDE keys and values for a project. 
If a key is given, returns only hash of specified key, value pair.
Sets a value if key and value is given (return true or false if works)

=cut

sub data {
  my ($self, $tag, $value) = @_;

  my $dbh = $self->_master->db_handle;
  my $sth;
  
  if (defined($value) and $tag) {
    if (ref $value) {
      print STDERR "ERROR: invalid value type for $tag  ($value) \n";
      print STDERR Dumper $value;
      return 0;
    }
    my $jstat = $self->_master->ProjectMD->get_objects( { project => $self,
							  tag     => $tag,
							  value   => $value
							});
    if (ref $jstat and scalar @$jstat) {
      $jstat->[0]->value($value);
    } else {
      $jstat = $self->_master->ProjectMD->create( { project => $self,
						    tag     => $tag,
						    value   => $value
						  });
    }
    return 1;
  }
  elsif ($tag) {
    $sth = $dbh->prepare("SELECT tag, value FROM ProjectMD where project=".$self->_id." and tag='$tag'");
  } else {
    $sth = $dbh->prepare("SELECT tag, value FROM ProjectMD where project=".$self->_id);
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash   = {};
  map { $rhash->{$_->[0]} = $_->[1] } @$results;
  
  return $rhash;
}

# list of all collections for this project
sub collections {
  my ($self, $type, $id_only) = @_;

  my $db = $self->_master();
  if ($id_only) {
    my $query = "select distinct c.ID from ProjectCollection p, MetaDataCollection c where p.collection=c._id and p.project=".$self->_id;
    if ($type) {
      $query .= " and c.type = ".$db->db_handle->quote($type);
    }
    my $result = $db->db_handle->selectcol_arrayref($query);
    return ($result && @$result) ? $result : [];
  }
  else {
    my $colls = [];
    foreach my $pc ( @{ $db->ProjectCollection->get_objects({project => $self}) } ) {
      if ($type) {
	if ($pc->collection->type && ($pc->collection->type eq $type)) {
	  push @$colls, $pc->collection;
	}
      } else {
	push @$colls, $pc->collection;
      }
    }
    return $colls;
  }
}

# list of all metagenomes for this project
sub metagenomes {
  my ($self, $id_only, $all) = @_;
  
  my $db = $self->_master();
  if ($id_only) {
    my $query  = "select distinct j.metagenome_id from ProjectJob p, Job j where p.project=".$self->_id." and j._id=p.job".($all ? "" : " and j.viewable=1");
    my $result = $db->db_handle->selectcol_arrayref($query);
    return ($result && @$result) ? $result : [];
  }
  else {
    my $mgs = [];
    foreach my $pjs ( @{ $db->ProjectJob->get_objects({project => $self }) } ) {
      push @$mgs, $pjs->job;
    }
    return $mgs;
  }
}

# return all metagenome ids and names of this project
sub metagenomes_id_name {
  my ($self) = @_ ;
  my $query  = "select j.metagenome_id, j.name from ProjectJob p, Job j where p.project=".$self->_id." and j._id=p.job and j.viewable=1";
  my $result = $self->_master->db_handle->selectall_arrayref($query);
  my %mgmap  = map { $_->[0] => $_->[1] } @$result;
  return \%mgmap;
}

sub all_metagenome_ids {
  my ($self, $all) = @_;
  return $self->metagenomes(1, $all);
}

# add a metadata collection to project
sub add_collection {
  my ($self, $collection) = @_;

  my $check = $self->_master->ProjectCollection->get_objects({ collection => $collection, project => $self });
  unless (@$check > 0) {
    $self->_master->ProjectCollection->create({ collection => $collection, project => $self });
  }
}

# add a job to project
sub add_job {
  my ($self, $job, $noscope) = @_;

  unless ($job and ref($job)) {
    return "error: invalid job object";
  }
  my $check = $self->_master->ProjectJob->get_objects({ job => $job });
  if (scalar @$check) {
    my $in_this = 0;
    foreach my $pj (@$check) {
      if ($pj->project->id == $self->id) { $in_this = 1; }
    }
    return $in_this ? "success: job already in this project" : "error: job already in a different project";
  }

  unless ($noscope) {
    # Connect to User/Rights DB
    my $webappdb = DBMaster->new(-database => $Conf::webapplication_db,
				 -backend  => $Conf::webapplication_backend,
				 -host     => $Conf::webapplication_host,
				 -user     => $Conf::webapplication_user,
				);
    my $pscope = $webappdb->Scope->init( { application => undef,
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
  # connect job and project
  $self->_master->ProjectJob->create({ job => $job, project => $self });
  unless ($job->primary_project && ref($job->primary_project)) {
    $job->primary_project($self);
  }
  # connect job metadata and project
  if ($job->sample && ref($job->sample))   { $self->add_collection( $job->sample ); }
  if ($job->library && ref($job->library)) { $self->add_collection( $job->library ); }

  return "success: job added";
}

# remove a metadata collection from project
sub remove_collection {
  my ($self, $collection) = @_;

  my $proj_coll = $self->_master->ProjectCollection->get_objects({ collection => $collection, project => $self });
  map { $_->delete() } @$proj_coll;
}

# remove a job from project
sub remove_job {
  my ($self, $job, $noscope) = @_;

  unless ($job and ref($job)) {
    return "error: invalid job object";
  }
  my $proj_job = $self->_master->ProjectJob->get_objects({ job => $job, project => $self });
  unless (scalar @$proj_job) {
    return "success: job not in this project";
  }
  map { $_->delete() } @$proj_job;

  unless ($noscope) {
    # Connect to User/Rights DB
    my $webappdb = DBMaster->new(-database => $Conf::webapplication_db,
				 -backend  => $Conf::webapplication_backend,
				 -host     => $Conf::webapplication_host,
				 -user     => $Conf::webapplication_user,
				);
    my $pscope = $webappdb->Scope->init( { application => undef,
					   name => 'MGRAST_project_'.$self->id } );
    if ($pscope) {
      my $rights = $webappdb->Rights->get_objects( {scope => $pscope} );
      my %rhash  = map { $_->{data_id} => $_ } @$rights;
      
      if (exists $rhash{$job->{metagenome_id}}) {
	$rhash{$job->{metagenome_id}}->delete();
      }
    }
  }
  if ($job->sample && ref($job->sample))   { $self->remove_collection( $job->sample ); }
  if ($job->library && ref($job->library)) { $self->remove_collection( $job->library ); }

  my $dbh = $self->_master()->db_handle();
  my $str = "UPDATE Job SET primary_project = NULL, _primary_project_db = NULL WHERE job_id = ".$job->job_id;
  $dbh->do($str);

  return "success: job removed";
}

sub pi {
  my ($self) = @_;

  my $name = [];
  my $data = $self->data;
  foreach my $n (('PI_firstname', 'PI_lastname')) {
    if (exists $data->{$n}) {
      push @$name, $data->{$n};
    }
  }
  return @$name ? join(" ", @$name) : '';
}

sub pubmed {
  my ($self) = @_;
  my $query   = "select distinct m.value from ProjectCollection p, MetaDataEntry m where p.project=".$self->_id." and p.collection=m.collection and m.tag='pubmed_id'";
  my $results = $self->_master->db_handle->selectcol_arrayref($query);
  my $values  = {};
  foreach my $tmp (@$results) {
    my @set = split(/,/, $tmp);
    foreach my $v (@set) {
      $v =~ s/^\s+//;
      $v =~ s/\s+$//;
      $values->{$v} = 1;
    }
  }
  return [ keys %$values ];
}

sub countries {
  my ($self) = @_;
  my $query   = "select distinct m.value from ProjectCollection p, MetaDataEntry m where p.project=".$self->_id." and p.collection=m.collection and m.tag='country'";
  my $results = $self->_master->db_handle->selectcol_arrayref($query);
  @$results = grep { $_ } @$results;
  return ($results && @$results) ? $results : [];
}

sub enviroments {
  my ($self) = @_ ;
  my $query   = "select distinct m.value from ProjectCollection p, MetaDataEntry m where p.project=".$self->_id." and p.collection=m.collection and m.tag in ('biome','feature','material')";
  my $results = $self->_master->db_handle->selectcol_arrayref($query);
  @$results = grep { $_ } @$results;
  return ($results && @$results) ? $results : [];
}

sub sequence_types {
  my ($self) = @_;
  ## calculated takes precidence over inputed
  my $mddb    = MGRAST::Metadata->new();
  my $query   = "select distinct j.sequence_type from Job j, ProjectJob p where p.project=".$self->_id." and p.job=j._id and j.viewable=1";
  my $results = $self->_master->db_handle->selectcol_arrayref($query);
  unless ($results && @$results) {
    $results = [];
    $query   = "select distinct m.value from ProjectCollection p, MetaDataEntry m where p.project=".$self->_id." and p.collection=m.collection and m.tag='investigation_type'";
    my $tmp  = $self->_master->db_handle->selectcol_arrayref($query);
    unless ($tmp && @$tmp) { return []; }
    foreach my $s (@$tmp) {
      push @$results, $mddb->investigation_type_alias($s);
    }
  }
  @$results = grep { $_ } @$results;
  return $results;
}

sub bp_count_raw {
  my ($self) = @_;
  my $query   = "select sum(s.value) from ProjectJob p, JobStatistics s where p.project=".$self->_id." and p.job=s.job and s.tag='bp_count_raw'";
  my $results = $self->_master->db_handle->selectcol_arrayref($query);
  return $results->[0] || 0;
}

sub metagenomes_summary {
  my ($self) = @_;
  my @data;
  my @header = ('Metagenome ID', 'Metagenome Name', '# base pairs', 'Enviroment', 'Location', 'Country', 'Sequence Type');
  
  my $project_jobs = $self->_master->ProjectJob->get_objects( {project => $self} );
  my $user = $self->_master->{_user};

  if (@$project_jobs > 0) {    
    my @pdata = ();
    my $user_jobs = {};
    my $ujr = defined($user) ? $user->has_right_to(undef, 'view', 'metagenome') : [];
    %$user_jobs = map { $_ => 1 } @$ujr;
    my @pjobs   = map { $_->job } grep { $user_jobs->{$_->job->metagenome_id} || $user_jobs->{'*'} || $_->job->public } @$project_jobs;
    my $jindices = {};
    my $i = 0;
    foreach my $pj (@pjobs) {
      my $coord = $pj->lat_lon;
      my $stats = $pj->stats;
      $jindices->{$pj->{_id}} = $i;
      push @data, [  $pj->metagenome_id,
		     $pj->name,
		     format_number($stats->{bp_count_raw}),
		     format_number($stats->{sequence_count_raw}),
		     $pj->biome,
		     $pj->feature,
		     $pj->material,
		     $pj->location,
		     $pj->country,
		     @$coord ? join(", ", @$coord) : '',
		     $pj->seq_type,
		     $pj->seq_method,
		     $pj->viewable,
		     $pj->created_on,
		     {}
		  ];
      $i++;
    }
    my $jdbh  = $self->_master->db_handle();
    my $res = $jdbh->selectall_arrayref('SELECT tag, value, job FROM JobAttributes WHERE job IN ('.join(", ", map { $_->{_id} } @pjobs).')', { Slice => {} });
    foreach my $row (@$res) {
      $data[$jindices->{$row->{job}}]->[14]->{$row->{tag}} = $row->{value};
    }
  }
  return \@data;
}

##########################
# output methods
#########################

sub xml {
    my ($self) = @_;
    my $xml = "<?xml version=\"1.0\" ?>\n";
    $xml .= "<project id='". $self->id ."'>\n";
    $xml .= "<name>". $self->name ."</name>\n";
    $xml .= "<submitter>". ($self->creator ? $self->creator->name : 'ERROR:no submitter') ."</submitter>\n";
    
    my $data = $self->_master->ProjectMD->get_objects( {project => $self} );
    foreach my $md (@$data) {
      next if ($md->tag =~ /email/);
      my $value = $md->value;
	$xml .= "<".$md->tag.">".$value."</".$md->tag.">\n";
    }
    $xml .= "<metagenomes>\n";
    foreach my $pjs (@{ $self->_master->ProjectJob->get_objects( {project => $self}) }) {
      my $j = $pjs->job;
      next unless ($j and ref $j);
      $xml .=  "<metagenome>\n";
      $xml .=  "\t<metagenome_id namespace='MG-RAST'>". $j->metagenome_id."</metagenome_id>\n";
      $xml .=  "\t<sample_id namespace='MG-RAST'>".$j->sample->ID."</sample_id>\n" if ($j->sample and ref $j->sample);
      $xml .=  "\t<library_id namespace='MG-RAST'>".$j->library->ID."</library_id>\n" if ($j->library and ref $j->library);
      $xml .=  "</metagenome>\n";
    }
    $xml .= "</metagenomes>\n";
    $xml .= "</project>\n";
    return $xml;
}

sub tabular {
  my ($self, $all) = @_;
  my $xml = '';

  my @header = ('project name', 'project id');
  my @pdata  = ($self->name, $self->id);
  my $data   = $self->_master->ProjectMD->get_objects( {project => $self} );

  foreach my $md (@$data) {
    next if ($md->tag eq "sample_collection_id");
    next if ($md->tag =~ /email/);
    push @header, $md->tag;
    my $value = $md->value;
    $value =~ s/(\r\n|\n|\r)/ /g;
    push @pdata, $value;
  }

  my $jheader = {};
  my $jdata   = {};
  
  foreach my $pjs (@{ $self->_master->ProjectJob->get_objects( {project => $self}) }) {
    my $j = $pjs->job;
    next unless ($j and ref $j);
    my $s = $j->sample;
    my $l = $j->library;
    next unless ($s and $l and ref $s and ref $l);
    my $sdata = $s->data;
    my $ldata = $l->data;
    map { ($_ =~ /email/) ? '' : $jheader->{$_}++ } keys %$sdata;
    map { ($_ =~ /email/) ? '' : $jheader->{$_}++ } keys %$ldata;
    map { $jdata->{$j->metagenome_id}->{$_} = $sdata->{$_} } keys %$sdata;
    map { $jdata->{$j->metagenome_id}->{$_} = $ldata->{$_} } keys %$ldata;
  }
  
  # print data
  my $output = join("\t", ('metagenome', @header, keys %$jheader))."\n";
  foreach my $id (keys %$jdata) {
    $output .= join("\t", ($id, @pdata, map { my $tmp = $jdata->{$id}->{$_} || 'unknown'; $tmp =~ s/(\r\n|\n|\r)/ /g; $tmp } keys %$jheader))."\n";
  }
  return $output;
}

sub verbose {
  my ($self, $all) = @_;
  my $xml = '';

  my @header = ('project name', 'project id');
  my @pdata  = ($self->name, $self->id);
  my $data   = $self->_master->ProjectMD->get_objects( {project => $self} );

  foreach my $md (@$data) {
    push @header, $md->tag;
    push @pdata, $md->value;
  }

  my $jheader = {};
  my $jdata   = {};
  
  foreach my $pjs (@{ $self->_master->ProjectJob->get_objects( {project => $self}) }) {
    my $j = $pjs->job;
    next unless ($j and ref $j);
    my $s = $j->sample;
    my $l = $j->library;
    next unless ($s and $l and ref $s and ref $l);
    my $sdata = $s->data;
    my $ldata = $l->data;
    map { $jheader->{$_}++ } keys %$sdata;
    map { $jheader->{$_}++ } keys %$ldata;
    map { $jdata->{$j->metagenome_id}->{$_} = $sdata->{$_} } keys %$sdata;
    map { $jdata->{$j->metagenome_id}->{$_} = $ldata->{$_} } keys %$ldata;
  }
  
  # print data
  my $output = '';
  foreach my $id (keys %$jdata) {
    $output .= join("\t", (@pdata, map { $jdata->{$id}->{$_} || 'unknown' } keys %$jheader))."\n";
  }
  return $output;
}

sub format_number {
  my ($val) = @_;
  
  if (! $val) {
    return $val;
  }
  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}
