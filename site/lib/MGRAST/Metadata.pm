package MGRAST::Metadata;

use strict;
use warnings;
use Data::Dumper;

use WebComponent::FormWizard::DataStructures;
use DBMaster;
use FIG_Config;

#
# Add following lines to FIGConfig.pm
# $mgrast_metadata_db  = "MGRASTMetadata";
# $mgrast_metadata_host = "mg-rast.mcs.anl.gov";
# $mgrast_metadata_user  = "mgrast";
#

sub new {
  my ($class, $app, $debug) = @_;

  $app   = $app   || '';
  $debug = $debug || '';
  my $self = { app      => $app,
	       debug    => $debug,
	       template => $FIG_Config::mgrast_formWizard_templates . "/FormWizard_MetaData.xml"
	     };
  eval {
      $self->{_handle} = DBMaster->new( -database => $FIG_Config::mgrast_metadata_db || 'MGRASTMetadata',
					-host     => $FIG_Config::mgrast_metadata_host,
					-user     => $FIG_Config::mgrast_metadata_user,
					-password => $FIG_Config::mgrast_metadata_password || "");
    };
  if ($@) {
    warn "Unable to connect to MGRAST metadata db: $@\n";
    $self->{_handle} = undef;
  }

  bless ($self, $class);
  return $self;
}

=pod

=item * B<is_job_compliant> (JobObject<job>)

Returns true if job exists and has all mandatory migs fields filled out.

=cut 

sub is_job_compliant {
  my ($self, $job) = @_;

  my $data = $self->get_all_for_job($job);
  if (@$data == 0) { return 0; }
  
  my %job_tags  = map { $_->tag, 1 } grep { defined($_->value) && ($_->value =~ /\S/) } @$data;
  my $migs_tags = $self->get_migs_tags();
  my $env_tags  = $self->get_enviroment_tags();
  my %env_nums  = map { $_, scalar(keys %{$env_tags->{$_}}) } keys %$env_tags;
  
  my $miss_migs = 0;
  while ( my ($tag, $quest) = each %$migs_tags ) {
    if ( ($quest->{mandatory}) && (! exists $job_tags{$tag}) ) {
      $miss_migs += 1;
    }
  }

  my $job_env   = '';
  my $env_count = 0;
  my $has_env   = 0;
  foreach my $env ( keys %$env_tags ) {
    if ($job_env && ($job_env ne $env)) {
      next;
    }
    foreach my $tag ( keys %{ $env_tags->{$env} } ) {
      if ( exists $job_tags{$tag} ) {
	$job_env    = $env if (! $job_env);
	$env_count += 1;
      }
    }
  }
  if ($job_env && ($env_count > ($env_nums{$job_env} * 0.8)) ) {
    $has_env = 1;
  }

  return ( (! $miss_migs) && $has_env ) ? 1 : 0;
}

=pod

=item * B<export_metadata_for_jobs> (Arrayref<JobObject job>, Scalar<file>)

For a given list of Job Objs and a file name, return a filepath with:
column header is metagenome_id, row header is format (question | tag), cell is value

=cut

sub export_metadata_for_jobs {
  my ($self, $jobs, $file, $format, $orient) = @_;

  unless ($format) { $format = "tag"; }
  unless ($orient) { $orient = "key"; }

  my $fpath = "$FIG_Config::temp/$file";
  my $keys  = {};
  my $data  = $self->get_metadata_for_jobs($jobs); # job => [ [tag, category, question, value] ]
  my @jobs  = sort keys %$data;

  foreach my $job (@jobs) {
    foreach my $set ( @{$data->{$job}} ) {
      my $key = ($format eq "question") ? $set->[1] . " : " . $set->[2] : $set->[0];
      if ( defined($set->[3]) && ($set->[3] =~ /\S/) ) {
	$keys->{$key}->{$job} = $set->[3];
      }
    }
  }

  if (open(FILE, ">$fpath")) {
    if ($orient eq "job") {
      print FILE "#SampleID\t" . join("\t", @jobs) . "\n";
      foreach my $k ( sort keys %$keys ) {
	my @row = ();
	foreach my $j (@jobs) {
	  push @row, exists($keys->{$k}{$j}) ? $keys->{$k}{$j} : '';
	}
	print FILE "$k\t" . join("\t", @row) . "\n";
      }
    } else {
      print FILE "#SampleID\t" . join("\t", sort keys %$keys) . "\n";
      foreach my $j (@jobs) {
	my @row = ();
	foreach my $k ( sort keys %$keys ) {
	  push @row, exists($keys->{$k}{$j}) ? $keys->{$k}{$j} : '';
	}
	print FILE "$j\t" . join("\t", @row) . "\n";
      }
    }
    close FILE;
  }
  else {
    print STDERR "Could not open export file: $! $@\n";
    return '';
  }

  return $fpath;
}

=pod

=item * B<get_metadata_for_jobs> (Arrayref<JobObject job>)

For a given list of Job Objs, return a hash of data: job->metagenome_id => [ [tag, category, question, value] ]

=cut

sub get_metadata_for_jobs {
  my ($self, $jobs) = @_;

  my $set = {};

  foreach my $j ( @$jobs ) {
    my $data = $self->get_metadata_for_table($j);
    unless (ref($data) && (scalar(@$data) > 0)) { $data = []; }

    if    ($j && ref($j))         { $set->{$j->metagenome_id} = $data; }
    elsif ($j && ($j =~ /^\d+$/)) { $set->{$j} = $data; }
  }
  return $set;
}

=pod

=item * B<get_collection_for_job> (JobObject<job>)

Returns a PPO MetaDataCollection obj for a specific job.
If job not PPO obj and not in MetaDataCollection, return undef.

=cut 

sub get_collection_for_job {
  my ($self, $job) = @_;
  
  my $mddb = $self->{_handle};

  if ($job && ref($job)) {
    my $colls = $mddb->MetaDataCollection->get_objects({job => $job});
    if ($colls && (@$colls > 0)) { return $colls->[0]; }
  }
  return undef;
}

=pod

=item * B<get_all_for_collection> (Scalar<collection>)

For a specific collection ID, returns a PPO MetaDataCollection obj

=cut 

sub get_all_for_collection {
  my ($self, $collection) = @_;
  
  my $mddb = $self->{_handle};
  $collection = $collection || '';
  return $mddb->MetaDataCollection->init({ID => $collection});
}


=pod

=item * B<get_all_for_project> (ProjectObject<project>)

Returns all data for a specific project from ProjectMD.
If Project is PPO (jobcache obj) return PPO object array,
else if Project is index return [ _id, tag, value ]

=cut

sub get_all_for_project {
  my ($self, $proj) = @_;
  
  my $mddb = $self->{_handle};

  if ($proj && ref($proj)) {
    return $mddb->ProjectMD->get_objects({project => $proj});
  }
  elsif ($proj && ($proj =~ /^\d+$/)) {
    my $tmp = $mddb->db_handle->selectall_arrayref("SELECT _id,tag,value FROM ProjectMD WHERE project=$proj;");
    return ($tmp && @$tmp) ? $tmp : [];
  }
  return [];
}


=pod

=item * B<get_entries> ( tag , CollectionObject<collection>)

Returns values for a specific tag and collection from MetaDataEntry.
If collection is PPO (Metadata obj) return PPO object array,
else if Job is index return [ _id, tag, value ]

=cut

sub get_entries {
  my ($self, $tag , $collection) = @_;
  
  my $mddb = $self->{_handle};

  my $data = [];
  if ($collection && ref($collection)) {
    $data = $mddb->MetaDataEntry->get_objects({collection => $collection ,
					       tag => $tag });
  }
  elsif ($collection && ($collection =~ /^\d+$/)) {
    my $tmp  = $mddb->db_handle->selectall_arrayref("SELECT _id,tag,value,type,migs FROM MetaDataEntry WHERE collection=$collection and tag=$tag ;");
    if ($tmp && @$tmp) {
      foreach (@$tmp) {
	push @$data, {_id => $_->[0], tag => $_->[1], value => $_->[2], type => $_->[3], migs => $_->[4]};
      }
    }
  }
  return $data;
}

=pod

=item * B<get_all_for_job> (JobObject<job>)

Returns all data for a specific job from MetaDataEntry.
If Job is PPO (jobcache obj) return PPO object array,
else if Job is index return [ _id, tag, value ]

=cut

sub get_all_for_job {
  my ($self, $job) = @_;
  
  my $mddb = $self->{_handle};

  my $data = [];
  if ($job && ref($job)) {
    $data = $mddb->MetaDataEntry->get_objects({job => $job});
  }
  elsif ($job && ($job =~ /^\d+$/)) {
    my $tmp  = $mddb->db_handle->selectall_arrayref("SELECT _id,tag,value,type,migs FROM MetaDataEntry WHERE job=$job;");
    if ($tmp && @$tmp) {
      foreach (@$tmp) {
	push @$data, {_id => $_->[0], tag => $_->[1], value => $_->[2], type => $_->[3], migs => $_->[4]};
      }
    }
  }
  return $data;
}

=pod

=item * B<get_all_for_tag> (Scalar<tag>, Boolean<no_ppo>)

Returns all data for a specific tag from MetaDataEntry.
If no_ppo true return [ _id, job, value ], else return PPO object array.

=cut 

sub get_all_for_tag {
  my ($self, $tag, $no_ppo) = @_;
  
  my $mddb = $self->{_handle};

  if (! $no_ppo) {
    return $mddb->MetaDataEntry->get_objects({tag => $tag});
  }
  else {
    my $tmp = $mddb->db_handle->selectall_arrayref("SELECT _id,job,value FROM MetaDataEntry WHERE tag=\'$tag\'");
    return ($tmp && @$tmp) ? $tmp : [];
  }
}

=pod

=item * B<get_metadata_for_table> (JobObject<job>, Scalar<template>)

Given a Job PPO object and xml FormWizard template filename,
return an array refrence of [ tag, category, question, value ]

=cut

sub get_metadata_for_table {
  my ($self, $job, $template) = @_;

  my (@data, %tags, $cat, $quest, $is_xml);
  my $temp_data = $self->get_template_data($template);

  foreach ( @{ $self->get_all_for_job($job) } ) {
    $tags{$_->{tag}}->{$_->{value}}++;
  }

  foreach my $tag ( keys %tags ) {
    if (exists $temp_data->{$tag}) {
      ($cat, $quest, undef) = @{ $temp_data->{$tag} };
      $is_xml = 1;
    } else {
      ($cat, $quest) = ("Unassigned", $tag);
      $is_xml = 0;
    }
    foreach my $val ( keys %{ $tags{$tag} } ) {
      unless ( defined($val) && ($val =~ /\S/) ) { next; }
      if (($val eq "Please select") || ($val eq "not determined") || ($val eq "not selected")) { next; }
      if ($is_xml)      { $val = $self->unencode_value($tag, $val); }
      if (defined $val) { push @data, [ $tag, $cat, $quest, $val ]; }
    }
  }
  return \@data;
}

=pod

=item * B<get_metadata_for_display> (JobObject<job>, Scalar<template>)

Given a Job PPO object and xml FormWizard template filename,
return an hash refrence: category => question => [ value ]

=cut

sub get_metadata_for_display {
  my ($self, $job, $template) = @_;

  my (%data, %tags, $cat, $quest, $is_xml);
  my $temp_data = $self->get_template_data($template);

  foreach ( @{ $self->get_all_for_job($job) } ) {
    push @{ $tags{$_->{tag}} }, $_->{value};
  }
  
  foreach my $tag ( keys %tags ) {
    if (exists $temp_data->{$tag}) {
      ($cat, $quest, undef) = @{ $temp_data->{$tag} };
      $is_xml = 1;
    } else {
      ($cat, $quest) = ("Unassigned", $tag);
      $is_xml = 0;
    }
    foreach my $val ( @{ $tags{$tag} } ) {
      unless ( defined($val) && ($val =~ /\S/) ) { next; }
      if (($val eq "Please select") || ($val eq "not determined") || ($val eq "not selected")) { next; }
      if ($is_xml)      { $val = $self->unencode_value($tag, $val); }
      if (defined $val) {  push @{ $data{$cat}{$quest} }, $val; }
    }
  }
  return \%data;
}

=pod

=item * B<unencode_value> (Scalar<tag>, Scalar<value>, Scalar<template>)

Given a tag and value, return the unencoded (display) value.

=cut

sub unencode_value {
  my ($self, $tag, $value, $template) = @_;

  unless ($self->{types} && ref($self->{types})) {
    $self->{types} = $self->get_type_tags($template);
  }
  unless (exists $self->{types}->{$tag}) { return $value; }
    
  my $error   = '';
  my $package = "WebComponent::FormWizard::" . $self->{types}->{$tag};

  { # check if type package exists
    no strict;
    eval "require $package;";
    $error = $@;
  }
  
  # check it type package has check_data function
  # check_data returns undef if bad; may change data depending on type
  unless ($error) {
    my $type_obj = $package->new($self);
    if ($type_obj && $type_obj->can('unencode_value')) {
      $value = $type_obj->unencode_value($value);
    }
  }
  return $value;
}

=pod

=item * B<get_type_tags> (Scalar<template>)

Given an xml FormWizard template filename,
return hash refrence. Key is tag that has a type, value is type.

=cut

sub get_type_tags {
  my ($self, $template) = @_;

  my $struct    = $self->get_template_struct($template);
  my $prefix    = ($struct->noprefix == 0) ? $struct->prefix : '';
  my $type_tags = {};

  while ( my ($tag, $set) = each %{$struct->{name2original}} ) {
    if ( $set->{question}->{type} ) {
      my ($trim) = $tag =~ /^$prefix(.*)/;
      $type_tags->{$trim} = $set->{question}->{type};
    }
  }
  return $type_tags;
}

=pod

=item * B<get_migs_tags> (Scalar<template>)

Given an xml FormWizard template filename,
return hash refrence. Key is tag that is a migs term, value is question.

=cut

sub get_migs_tags {
  my ($self, $template) = @_;

  my $struct    = $self->get_template_struct($template);
  my $prefix    = ($struct->noprefix == 0) ? $struct->prefix : '';
  my $migs_tags = {};

  while ( my ($tag, $set) = each %{$struct->{name2original}} ) {
    if ( $set->{question}->{migs} ) {
      my ($trim) = $tag =~ /^$prefix(.*)/;
      $migs_tags->{$trim} = $set->{question};
    }
  }
  return $migs_tags;
}

=pod

=item * B<get_enviroment_tags> (Scalar<template>)

Given an xml FormWizard template filename,
return hash refrence. Key is enviroment type, value is hash of tags.

=cut

sub get_enviroment_tags {
  my ($self, $template) = @_;

  my $struct   = $self->get_template_struct($template);
  my $prefix   = ($struct->noprefix == 0) ? $struct->prefix : '';
  my $env_tags = {};

  while ( my ($tag, $set) = each %{$struct->{name2display}} ) {
    if ( $set->{display_category} eq "Environmental Package" ) {
      my ($trim) = $tag =~ /^$prefix(.*)/;
      $env_tags->{ $set->{display_title} }->{$trim} = 1;
    }
  }
  return $env_tags;
}

=pod

=item * B<get_template_struct> (Scalar<template>)

Given an xml FormWizard template filename,
return DataStructure obj

=cut

sub get_template_struct {
  my ($self, $template) = @_;

  unless ($self->{struct} && ref($self->{struct})) {
    $self->set_template_data($template);
  }
  return $self->{struct};
}

=pod

=item * B<get_template_data> (Scalar<template>)

Given an xml FormWizard template filename,
return hash refrence: tag => [ category, question, default ]

=cut

sub get_template_data {
  my ($self, $template) = @_;

  unless ($self->{data} && ref($self->{data})) {
    $self->set_template_data($template);
  }
  return $self->{data};
}

=pod

=item * B<set_template_data> (Scalar<template>)

Given an xml FormWizard template filename,
set $self->{data} to tag => [ category, question, default ]

=cut

sub set_template_data {
  my ($self, $template) = @_;

  $template  = $template || $self->{template};
  my $data   = {};
  my $struct = WebComponent::FormWizard::DataStructures->new((template => $template));
  if ( $struct && ref($struct) && $struct->{data} ) {
    foreach my $set ( @{$struct->{data}} ) {
      my ($tag, $step, $title, $name, $default) = @$set;
      my $category = ($step eq $title) ? $step : "$step : $title";
      $data->{$tag} = [ $category, $name, $default ];
    }
  }
  $self->{data}   = $data;
  $self->{struct} = $struct;
}

=pod

=item * B<get_collections>

Returns an array refrence of all MetaDataCollection IDs.

=cut 

sub get_collections {
  my ($self) = @_;

  my $dbh = $self->{_handle}->db_handle();
  return $dbh->selectcol_arrayref("SELECT DISTINCT ID FROM MetaDataCollection");
}

=pod

=item * B<get_projects>

Returns an array refrence of all ProjectMD IDs.

=cut 

sub get_projects {
  my ($self , $opt ) = @_;

  my $results ;
  $opt->{ public } = 1 unless ($opt) ;
  my $dbh = $self->{_handle}->db_handle();
  
  if ( $opt->{ privat } ) {
    $results = $dbh->selectcol_arrayref("SELECT DISTINCT id FROM Project where public!=1");
  }
  elsif ( $opt->{ all } ){
    $results = $dbh->selectcol_arrayref("SELECT DISTINCT id FROM Project");
  }
  else{
    $results = $dbh->selectcol_arrayref("SELECT DISTINCT id FROM Project where public=1 and ( type='study' or type='project' ) ");
  }

  return $results;
}


=pod

=item * B<get_jobs>

Returns an array refrence of all MetaDataEntry job refrence ids.

=cut 

sub get_jobs {
  my ($self) = @_;

  my $dbh = $self->{_handle}->db_handle();
  return $dbh->selectcol_arrayref("SELECT DISTINCT job FROM MetaDataEntry");
}

=pod

=item * B<get_tags>

Returns an array refrence of all MetaDataEntry tags.

=cut 

sub get_tags {
  my ($self) = @_;
  
  my $dbh = $self->{_handle}->db_handle();
  return $dbh->selectcol_arrayref("SELECT DISTINCT tag FROM MetaDataEntry");
}

=pod

=item * B<get_date_time> (JobObject<job>)

return string: date-time-timezone of job for display

=cut

sub get_date_time {
  my ($self, $job) = @_;
  
  my $mddb = $self->{_handle};
  my @dt   = ();

  if ($job && ref($job)) {
    my @date = ( @{ $mddb->MetaDataEntry->get_objects({ job => $job, tag => "sample-origin_sampling_date" }) },
		 @{ $mddb->MetaDataEntry->get_objects({ job => $job, tag => "collection_date" }) }
	       );
    my $time = $mddb->MetaDataEntry->get_objects({job => $job, tag => 'sample-origin_sampling_time'});
    my $zone = $mddb->MetaDataEntry->get_objects({job => $job, tag => 'sample-origin_sampling_timezone'});

    if (@date) {
      push @dt, $date[0]->value;
    }
    if (@$time && @$zone) {
      push @dt, $self->unencode_value($time->[0]->tag, $time->[0]->value);
      push @dt, $zone->[0]->value;
    }
  }
  return join(" ", @dt);
}

=pod

=item * B<get_env_packages> (JobObject<job>)

return string: enviroment package of job

=cut

sub get_env_package {
  my ($self, $job) = @_;

  my $dbh = $self->{_handle}->db_handle();
  my $env = $self->get_enviroment_tags;

  if ($job && ref($job)) {
    my $tags = $dbh->selectcol_arrayref("SELECT DISTINCT tag FROM MetaDataEntry WHERE job=" . $job->_id);
    if ($tags && (@$tags > 0)) {
      foreach my $t (@$tags) {
	foreach my $e (keys %$env) {
	  if (exists $env->{$e}->{$t}) { return $e; }
	}
      }
    }
  }
  return "";
}

=pod

=item * B<get_coordinates> (JobObject<job>)

Returns array refrence of all: [JobObj, Latitude, Longitude]
If Job entered, return [Latitude, Longitude]

=cut

sub get_coordinates {
  my ($self, $job) = @_;
  
  my $mddb = $self->{_handle};
  my $lat_tag = "sample-origin_latitude";
  my $lon_tag = "sample-origin_longitude";

  if ($job && ref($job)) {
    my $lat = $mddb->MetaDataEntry->get_objects({job => $job, tag => $lat_tag});
    my $lon = $mddb->MetaDataEntry->get_objects({job => $job, tag => $lon_tag});
    unless (@$lat && @$lon) {
      $lat = $mddb->MetaDataEntry->get_objects({job => $job, tag => "latitude"});
      $lon = $mddb->MetaDataEntry->get_objects({job => $job, tag => "longitude"});
    }
    return (@$lat && @$lon) ? [ $lat->[0]->value, $lon->[0]->value ] : [];
  }
  else {
    my @cord = ();
    my %lats = map { $_->job->job_id, $_ } @{ $mddb->MetaDataEntry->get_objects({tag => $lat_tag}) };
    my %lons = map { $_->job->job_id, $_ } @{ $mddb->MetaDataEntry->get_objects({tag => $lon_tag}) };
    foreach my $id (keys %lats) {
      if (exists $lons{$id}) {
	push @cord, [ $lats{$id}->job, $lats{$id}->value, $lons{$id}->value ];
      }
    }
    return \@cord;
  }
}

=pod

=item * B<get_biomes> (JobObject<job>)

Returns array refrence of all: [Biome]
If Job entered, return [Biome] for job

=cut

sub get_biomes {
  my ($self, $job) = @_;

  my $mddb = $self->{_handle};
  my $dbh  = $mddb->db_handle();
  my $btag = "biome-information_envo_lite";

  if ($job && ref($job)) {
    my @biomes = map { $_->value } @{ $mddb->MetaDataEntry->get_objects({job => $job, tag => $btag}) };
    return @biomes ? \@biomes : [];
  }
  else {
    my $biomes = $dbh->selectcol_arrayref("SELECT DISTINCT value FROM MetaDataEntry WHERE tag = '$btag' order by value");
    return ($biomes && (@$biomes > 0)) ? $biomes : [];
  }
}

=pod

=item * B<get_sequencers>

Returns all sequencers

=cut

sub get_sequencers {
  my ($self) = @_;

  my $dbh  = $self->{_handle}->db_handle();
  my $stag = "sequencing_sequencing_method";
  my $seqs = $dbh->selectcol_arrayref("SELECT DISTINCT value FROM MetaDataEntry WHERE tag = '$stag' order by value");
  return ($seqs && (@$seqs > 0)) ? $seqs : [];
}

=pod

=item * B<get_countries>

Returns all countries

=cut

sub get_countries {
  my ($self) = @_;

  my $package = "WebComponent::FormWizard::Country";
  my @data  = ();
  my $error = '';

  { # check if package exists
    no strict;
    eval "require $package;";
    $error = $@;
  }

  unless ($error) {
    my $obj = $package->new($self);
    if ($obj && $obj->can('countries')) {
      @data = sort values %{ $obj->countries() };
    }
  }
  return \@data;
}

=pod

=item * B<add_entry> (CollectionObject<collection>, JobObject<job>, Hashref<attributes>, Scalar<append>)

Adds/modifies tag information (type, migs, value) for inputed collection and job in MetaDataEntry.
If append option is true, will append value to tag list.

=cut

sub add_entries {
  my ($self, $collection, $job, $attributes, $append) = @_;

  my $mddb = $self->{_handle};

  if ($job && ref($job) && $collection && ref($collection)) {
    while (my ($tag, $data) = each %$attributes) {
      my ($type, $migs, $vals) = @$data;
      if (! $append) {
	my $objs = $mddb->MetaDataEntry->get_objects({job => $job, tag => $tag});
	foreach my $o (@$objs) { $o->delete(); }
      }
      my %attr = ( collection => $collection,
		   job        => $job,
		   tag        => $tag,
		   type       => $type,
		   migs       => $migs
		 );
      foreach my $v (@$vals) {
	unless (defined($v) && ($v =~ /\S/)) { next; }  # skip empty or only whitespace
	$attr{value} = $v;
	$mddb->MetaDataEntry->create(\%attr);
      }
    }
  }
}

=pod

=item * B<add_collection> (JobObject<job>, CuratorObject<creator>, Scalar<source>, Scalar<url>)

Creates and returns a MetaDataCollection PPO obj,
based upon given Job and Curator PPO objs.
source and url are optional.

=cut

sub add_collection {
  my ($self, $job, $creator, $source, $url , $type) = @_;

  my $mddb = $self->{_handle};

  if ($job && ref($job) && $creator && ref($creator)) {
    my $tmp = $mddb->db_handle->selectrow_arrayref("SELECT MAX(ID + 0) FROM MetaDataCollection");
    my ($max) = $tmp->[0] =~/^(\d+)/ ; 
    if ($max && ($max > 0)) {
      my %attr = ( ID      => $max + 1,
		   source  => ($source ? $source : "MG-RAST"),
		   creator => $creator,
		   url     => ($url ? $url : ''),
		   job     => $job ,
		   type    => ($type ? $type : 'sample') ,
		 );
      $self->html_dump(\%attr);
      return $mddb->MetaDataCollection->create(\%attr);
    }
  }
  return undef;
}

=pod

=item * B<add_curator> (UserObject<user>, Scalar<status>, Scalar<url>)

Creates and returns a Curator PPO obj based upon given WebAppBackend::User PPO obj.
status and url are optional.

=cut

sub add_curator {
  my ($self, $user, $status, $url) = @_;

  my $mddb = $self->{_handle};

  if ($user && ref($user)) {
    my $max = $mddb->db_handle->selectrow_arrayref("SELECT MAX(ID) FROM Curator");
    if ($max && (@$max > 0)) {
      my %attr = ( ID     => $max->[0] + 1,
		   status => ($status ? $status : "manual"),
		   name   => $user->firstname . " " . $user->lastname,
		   email  => $user->email,
		   url    => ($url ? $url : ''),
		   user   => $user,
		   type   => ($user->is_admin('MGRAST') ? "Admin" : "User")
		 );
      $self->html_dump(\%attr);
      return $mddb->Curator->create(\%attr);
    }
  }
  return undef;
}

=pod

=item * B<add_update> (CollectionObject<collection>, CuratorObject<curator>, Scalar<comment>, Scalar<type>)

Creates and returns a UpdateLog PPO obj,
based upon given Collection and Curator PPO objs.
comment and type are optional.

=cut

sub add_update {
  my ($self, $collection, $curator, $comment, $type) = @_;

  my $mddb = $self->{_handle};
  if ($collection && ref($collection) && $curator && ref($curator)) {
    my %attr = ( comment    => ($comment ? $comment : ''),
		 collection => $collection,
		 curator    => $curator,
		 type       => ($type ? $type : '')
	       );
    $self->html_dump(\%attr);
    return $mddb->UpdateLog->create(\%attr);
  }
  return undef;
}

=pod

=item * B<update_project_value> (Arrayref<values>)

Updates values for ProjectMD.
If input is [ ProjectMD PPO obj, value ], use PPO methods.
Else if input is [ ProjectMD _id, value ], use SQL methods.

=cut

sub update_project_value {
  my ($self, $values) = @_;

  my $mddb = $self->{_handle};
  
  foreach my $set ( @$values ) {
    my ($proj, $val) = @$set;
    if ($proj && ref($proj)) {
      if ($proj->value ne $val) {
	$proj->value($val);
	$self->html_dump([$proj, $val]);
      }
    }
    elsif ($proj && ($proj =~ /^\d+$/)) {
      my $qval = quotemeta($val);
      my $sql  = qq(UPDATE ProjectMD SET value='$qval' WHERE _id=$proj);
      $mddb->db_handle->do($sql);
      $self->html_dump($sql);
    }
  }
}

=pod

=item * B<update_entry_value> (Arrayref<values>)

Updates values for MetaDataEntry.
If input is [ MetaDataEntry PPO obj, value ], use PPO methods.
Else if input is [ MetaDataEntry _id, value ], use SQL methods.

=cut

sub update_entry_value {
  my ($self, $values) = @_;

  my $mddb = $self->{_handle};
  
  foreach my $set ( @$values ) {
    my ($mde, $val) = @$set;
    if ($mde && ref($mde)) {
      if ($mde->value ne $val) {
	$mde->value($val);
	$self->html_dump([$mde, $val]);
      }
    }
    elsif ($mde && ($mde =~ /^\d+$/)) {
      my $qval = quotemeta($val);
      my $sql  = qq(UPDATE MetaDataEntry SET value='$qval' WHERE _id=$mde);
      $mddb->db_handle->do($sql);
      $self->html_dump($sql);
    }
  }
}

=pod

=item * B<update_collection> (Scalar<collection>, Hashref<attributes>)

Updates MetaDataCollection, based on collection ID, with inputed attributes.

=cut

sub update_collection {
  my ($self, $collection, $attributes) = @_;

  my $mddb = $self->{_handle};
  $mddb->MetaDataCollection->init({ID => $collection})->set_attributes($attributes);
  $self->html_dump([$collection, $attributes]);
}

=pod

=item * B<update_curator> (Scalar<curator>, Hashref<attributes>)

Updates Curator, based on curator ID, with inputed attributes.

=cut

sub update_curator {
  my ($self, $curator, $attributes) = @_;

  my $mddb = $self->{_handle};
  $mddb->Curator->init({ID => $curator})->set_attributes($attributes);
  $self->html_dump([$curator, $attributes]);
}


# export functions

sub export_metadata {
 my ($self, $job, $dir, $type) = @_;

 if ($dir && (! -d $dir))   { mkdir $dir; }
 unless ($dir && (-d $dir)) { $dir = "/tmp/"; }

 my ($file, $error) = ("", "");
 

 unless($type){
   ($file,$error) = $self->export2tab($job , $dir) ;
   print STDERR $error if ($error);
 }
 return ($file, $error);
}

sub export2tab {
  my ($self, $job, $dir) = @_;
  
  unless ($dir && (-d $dir)) {
    return ("", "Export dir does not exist: $dir");
  }

  my $tmp = $self->get_all_for_job($job);
  my $attr = {} ;
  map { push @{ $attr->{ $_->tag } } , $_->value } @$tmp ;
  my $file = "$dir/" . $job->metagenome_id . ".csv";
  if (-f $file) { rename($file, $file.".".time); }

  return $self->write2file($attr, $file);
}

# write meta data hash to file 
sub write2file {
  my ($self, $data, $file) = @_;
  my $error = '';
  
  if (open(META, ">$file")) {
    while ( my($tag, $val) = each %$data ) {
      print META "$tag\t" . (ref($val) ? join("\t", @$val) : $val) . "\n";
    }
    close (META);
  }
  else {
    $error = "Can't open $file!";
  }

  return ($file, $error);
}

# import file for a given job
sub import_file {
  my ($self, $file, $job) = @_;

  # load data from file
  open (META, "$file") or die "Can't open $file\n";
  my $data = {};
  while (my $line = <META>) {
    chomp $line;
    my ($key, @val) = split(/\t/, $line);
    if (@val > 0) { $data->{$key} = [ @val ]; }
  }
  close (META);

  # store into db
  $self->add($job, $data);
}

sub html_dump {
  my ($self, $data) = @_;

  if ($self->{debug} && $self->{app} && ref($self->{app})) {
    $self->{app}->add_message('info', '<pre>' . Dumper($data) . '</pre>');
  }
}

sub _handle {
  my ($self) = @_;
  return $self->{_handle};
}

sub db {
  my ($self) = @_;
  return $self->{_handle};
}

sub debug {
  my ($self, $debug) = @_;
  $self->{debug} = $debug if (defined $debug and length $debug);
  return $self->{debug};
}

1;
