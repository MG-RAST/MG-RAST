package MGRAST::Metadata;

use strict;
use warnings;

use LWP::Simple;
use URI::Escape;
use Storable qw(dclone);
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use JSON;

use DBMaster;
use Conf;

sub new {
  my ($class, $app, $debug) = @_;

  $app   = $app   || '';
  $debug = $debug || '';
  my $self = { app => $app, debug => $debug };
  eval {
      $self->{_handle} = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'MGRASTMetadata',
					-host     => $Conf::mgrast_jobcache_host,
					-user     => $Conf::mgrast_jobcache_user,
					-password => $Conf::mgrast_jobcache_password || "");
    };
  if ($@) {
    warn "Unable to connect to MGRAST metadata db: $@\n";
    $self->{_handle} = undef;
  }

  bless ($self, $class);
  return $self;
}

=pod

=item * B<template> ()

Returns the metadata temple in the format:
category => 'category_type' => <category_type>
category => tag => { aliases, definition, type, required, mixs, unit }

=cut

sub template {
  my ($self) = @_;

  unless ($self->{data} && ref($self->{data})) {
    my $data = {};
    my $dbh  = $self->{_handle}->db_handle;
    my $tmp  = $dbh->selectall_arrayref("SELECT category_type,category,tag,mgrast_tag,qiime_tag,definition,required,type,mixs,unit FROM MetaDataTemplate");
    unless ($tmp && (@$tmp)) { return $data; }
    map { $data->{$_->[1]}{category_type} = $_->[0] } @$tmp;
    map { $data->{$_->[1]}{$_->[2]} =
            { aliases    => [ $_->[3], $_->[4] ],
              definition => $_->[5],
              required   => $_->[6],
              type       => $_->[7],
              mixs       => $_->[8],
              unit       => $_->[9]
            } } @$tmp;
    $self->{data} = $data;
  }
  return $self->{data};
}

sub get_cv_all {
    my ($self, $tag) = @_;
    my $data = {};
    my $dbh = $self->{_handle}->db_handle;
    my $tmp = $dbh->selectall_arrayref("SELECT tag, value FROM MetaDataCV WHERE type='select'");
    if ($tmp && @$tmp) {
        foreach my $x (@$tmp) {
            push @{ $data->{$x->[0]} }, $x->[1];
        }
    }
    return $data;
}

sub get_cv_select {
  my ($self, $tag) = @_;
  my $dbh = $self->{_handle}->db_handle;
  my $tmp = $dbh->selectcol_arrayref("SELECT DISTINCT value FROM MetaDataCV WHERE tag='$tag' AND type='select'");
  return ($tmp && @$tmp) ? $tmp : [];
}

sub get_cv_ontology {
  my ($self, $tag, $version) = @_;
  if (! $version) {
      $version = $self->cv_latest_version($tag);
  }
  my $dbh = $self->{_handle}->db_handle;
  my $tmp = $dbh->selectall_arrayref("SELECT value, value_id FROM MetaDataCV WHERE tag='$tag' AND type='ontology' AND value_version='$version'");
  return ($tmp && @$tmp) ? $tmp : [];
}

sub cv_ontology_info {
  my ($self, $tag) = @_;
  my $dbh = $self->{_handle}->db_handle;
  my $tmp = $dbh->selectrow_arrayref("SELECT DISTINCT value, value_id FROM MetaDataCV WHERE tag='$tag' AND type='ont_info'");
  return ($tmp && @$tmp) ? $tmp : ['', ''];
}

sub cv_ontology_versions {
    my ($self, $tag) = @_;
    my $dbh = $self->{_handle}->db_handle;
    if ($tag) {
        my $tmp = $dbh->selectcol_arrayref("SELECT DISTINCT value_version FROM MetaDataCV WHERE tag='$tag' AND type='ontology'");
        return ($tmp && @$tmp) ? $tmp : [];
    } else {
        my $data = {};
        my $tmp = $dbh->selectall_arrayref("SELECT DISTINCT tag, value_version FROM MetaDataCV WHERE type='ontology'");
        if ($tmp && @$tmp) {
            foreach my $x (@$tmp) {
                push @{ $data->{$x->[0]} }, $x->[1];
            }
        }
        return $data;
    }
}

sub cv_latest_version {
  my ($self, $tag) = @_;
  my $dbh = $self->{_handle}->db_handle;
  if ($tag) {
      my $one = $dbh->selectcol_arrayref("SELECT value FROM MetaDataCV WHERE tag='$tag' AND type='latest_version'");
      return ($one && @$one) ? $one->[0] : '';
  } else {
      my $all = $dbh->selectall_arrayref("SELECT tag, value FROM MetaDataCV WHERE type='latest_version'");
      if ($all && @$all) {
          my %data = map {$_->[0], $_->[1]} @$all;
          return \%data;
      } else {
          return {};
      }
  }
}

=pod

=item * B<mixs> ()

Returns set of all required mixs tags in the format:
category_type => tag => 1

=cut

sub mixs {
  my ($self) = @_;

  my $mixs = {};
  my $template = $self->template();
  foreach my $cat (keys %$template) {
    my $ct = $template->{$cat}{category_type};
    foreach my $tag (keys %{$template->{$cat}}) {
      next if ($tag eq 'category_type');
      if ($template->{$cat}{$tag}{required} && $template->{$cat}{$tag}{mixs}) {
	if ($ct eq 'library') {
	  $mixs->{$ct}{$cat}{$tag} = 1;
	} else {
	  $mixs->{$ct}{$tag} = 1;
	}
      }
    }
  }
  return $mixs;
}

=pod

=item * B<validate_mixs> (Scalar<tag>)

Check that tag is mixs tag
return boolean

=cut

sub validate_mixs {
  my ($self, $tag) = @_;
  my $dbh = $self->{_handle}->db_handle;
  my $tmp = $dbh->selectcol_arrayref("SELECT count(*) FROM MetaDataTemplate WHERE tag='$tag' AND mixs=1");
  return ($tmp && @$tmp && ($tmp->[0] > 0)) ? 1 : 0;
}

=pod

=item * B<validate_tag> (Scalar<category>, Scalar<tag>)

Check that tag exists for category
return boolean

=cut

sub validate_tag {
  my ($self, $cat, $tag) = @_;
  my $dbh = $self->{_handle}->db_handle;
  my $tmp = $dbh->selectcol_arrayref("SELECT count(*) FROM MetaDataTemplate WHERE category_type='$cat' AND tag='$tag'");
  return ($tmp && @$tmp && ($tmp->[0] > 0)) ? 1 : 0;
}

=pod

=item * B<validate_value> (Scalar<category>, Scalar<tag>, Scalar<value>)

Based on category and tag, check that value is of correct type
return tuple ref: [ boolean, error_message ]

=cut

sub validate_value {
  my ($self, $cat, $tag, $val, $version) = @_;

  my $dbh  = $self->{_handle}->db_handle;
  my $tmp  = $dbh->selectcol_arrayref("SELECT distinct type FROM MetaDataTemplate WHERE category_type='$cat' AND tag='$tag'");
  my $type = $tmp->[0];

  if ($type eq 'int') {
    return ($val =~ /^[+-]?\d+$/) ? [1, ''] : [0, 'not an integer'];
  } elsif ($type eq 'float') {
    return ($val =~ /^[+-]?\d+\.?\d*$/) ? [1, ''] : [0, 'not a float'];
  } elsif ($type eq 'boolean') {
    return (($val eq '1') || (lc($val) eq 'yes') || (lc($val) eq 'true')) ? [1, ''] : [0, 'not a boolean'];
  } elsif ($type eq 'email') {
    return ($val =~ /^\S+\@\S+\.\S+$/) ? [1, ''] : [0, 'invalid email'];
  } elsif ($type eq 'url') {
    return ($val =~ /^(ht|f)tp(s)?:\/\//) ? [1, ''] : [0, 'invalid url'];
  } elsif ($type eq 'date') {
    return ($val =~ /^\d{4}(-\d\d){0,2}/) ? [1, ''] : [0, 'not ISO8601 compliant date'];
  } elsif ($type eq 'time') {
    return ($val =~ /^\d\d:\d\d(:\d\d)?/) ? [1, ''] : [0, 'not ISO8601 compliant time'];
  } elsif ($type eq 'timezone') {
    return ($val =~ /^UTC/) ? [1, ''] : [0, 'not ISO8601 compliant timezone'];
  } elsif ($type eq 'select') {
    # hack for different country tags
    if ($tag =~ /country$/) {
        $tag = 'country';
    }
    my %cvs = map {$_, 1} @{ $self->get_cv_select($tag) };
    return exists($cvs{lc($val)}) ? [1, ''] : [0, 'not one of: '.join(', ', sort keys %cvs)];
  } elsif ($type eq 'ontology') {
    unless ($version) {
        $version = $self->cv_latest_version($tag);
    }
    my %cvv = map {$_, 1} @{ $self->cv_ontology_versions($tag) };
    unless (exists $cvv{$version}) {
        return [0, "invalid version '$version' for label '$tag'"];
    }
    my $cvi = $self->cv_ontology_info($tag);
    my $cvo = $self->get_cv_ontology($tag, $version);
    my %oid = map {$_->[1], 1} @$cvo;
    my %oname = map {$_->[0], 1} @$cvo;
    if (exists($oname{$val}) || exists($oid{$val})) {
        return [1, '']
    } else {
        return [0, "not part of $tag: ".$cvi->[0]];
    }
  } else {
    return [0, "unknown category '$cat'"];
  }
}

=pod

=item * B<get_jobs_metadata_fast> (Array<ids>, Boolean<is_mgid>)

if input array has metagenome ids then use is_mgis = 1
if input array has job ids then use is_mgis = 0 (default)
Returns Metadata for jobs in the format:
key => category_type => { id => #, name => '', type => '', data => {tag => value} }
where key is same type as input array

=cut 

sub get_jobs_metadata_fast {
  my ($self, $job_ids, $is_mgid) = @_;

  my $data  = {};
  my $projs = {};
  my $samps = {};
  my $libs  = {};
  my $epks  = {};
  my $dbh   = $self->{_handle}->db_handle;
  my $key   = $is_mgid ? 'metagenome_id' : 'job_id';
  my $where = $is_mgid ? 'metagenome_id IN ('.join(',', map {"'$_'"} @$job_ids).')' : 'job_id IN ('.join(',', @$job_ids).')';
  my $where2= $is_mgid ? 'j.metagenome_id IN ('.join(',', map {"'$_'"} @$job_ids).')' : 'j.job_id IN ('.join(',', @$job_ids).')';
  my $jobs = $dbh->selectall_arrayref("SELECT ".$key.",primary_project,sample,library,sequence_type,name,metagenome_id,file,file_checksum_raw FROM Job WHERE ".$where);
  my $meth = $dbh->selectall_arrayref("SELECT j.".$key.", a.value FROM Job j, JobAttributes a WHERE j._id=a.job AND a.tag='sequencing_method_guess' AND ".$where2);
  my %pids = map { $_->[1], 1 } grep {$_->[1] && ($_->[1] =~ /\d+/)} @$jobs;
  my %sids = map { $_->[2], 1 } grep {$_->[2] && ($_->[2] =~ /\d+/)} @$jobs;
  my %lids = map { $_->[3], 1 } grep {$_->[3] && ($_->[3] =~ /\d+/)} @$jobs;
  my %mmap = map { $_->[0], $_->[1] } @$meth;

  if (scalar(keys %pids) > 0) {
    my $ptmp = $dbh->selectall_arrayref("SELECT p._id, p.id, p.name, p.public, md.tag, md.value FROM Project p LEFT OUTER JOIN ProjectMD md ON p._id = md.project WHERE p._id IN (".join(',', keys %pids).")");
    foreach my $p (@$ptmp) {
      $projs->{$p->[0]}{id} = 'mgp'.$p->[1];
      $projs->{$p->[0]}{name} = $p->[2];
      $projs->{$p->[0]}{public} = $p->[2];
      if ($p->[4]) {
	$projs->{$p->[0]}{data}{$p->[4]} = $p->[5];
      }
    }
  }
  if (scalar(keys %sids) > 0) {
    my $stmp = $dbh->selectall_arrayref("SELECT s._id, s.ID, s.name, md.tag, md.value FROM MetaDataCollection s, MetaDataEntry md WHERE s.type = 'sample' AND s._id = md.collection AND s._id IN (".join(',', keys %sids).")");
    my $etmp = $dbh->selectall_arrayref("SELECT e.parent, e.ID, e.name, md.tag, md.value FROM MetaDataCollection e, MetaDataEntry md WHERE e.type = 'ep' AND e._id = md.collection AND e.parent IN (".join(',', keys %sids).")");
    foreach my $s (@$stmp) {
      $samps->{$s->[0]}{id} = 'mgs'.$s->[1];
      $samps->{$s->[0]}{name} = $s->[2];
      $samps->{$s->[0]}{data}{$s->[3]} = $s->[4];
    }
    foreach my $e (@$etmp) {
      $epks->{$e->[0]}{id} = 'mge'.$e->[1];
      $epks->{$e->[0]}{name} = $e->[2];
      $epks->{$e->[0]}{data}{$e->[3]} = $e->[4];
    }
  }
  if (scalar(keys %lids) > 0) {
    my $ltmp  = $dbh->selectall_arrayref("SELECT l._id, l.ID, l.name, md.tag, md.value FROM MetaDataCollection l, MetaDataEntry md WHERE l.type = 'library' AND l._id = md.collection AND l._id IN (".join(',', keys %lids).")");
    foreach my $l (@$ltmp) {
      $libs->{$l->[0]}{id} = 'mgl'.$l->[1];
      $libs->{$l->[0]}{name} = $l->[2];
      $libs->{$l->[0]}{data}{$l->[3]} = $l->[4];
    }
  }

  foreach my $row (@$jobs) {
    # $key,primary_project,sample,library,sequence_type,name,metagenome_id,file,file_checksum_raw
    my ($j, $p, $s, $l, $t, $n, $m, $f, $c) = @$row;
    $n = $n || '';    
    if ($p && exists($projs->{$p})) {
      map { $projs->{$p}{data}{$_} =~ s/^(gaz|country):\s?//i } grep {$projs->{$p}{data}{$_}} keys %{$projs->{$p}{data}};
      $data->{$j}{project} = $projs->{$p};
    }
    if ($s && exists($samps->{$s})) {
      map { $samps->{$s}{data}{$_} =~ s/^(gaz|country|envo):\s?//i } grep {$samps->{$s}{data}{$_}} keys %{$samps->{$s}{data}};
      $data->{$j}{sample} = $samps->{$s};
      unless ($data->{$j}{sample}{name}) {
	$data->{$j}{sample}{name} = $n;
      }
    }
    if ($l && exists($libs->{$l})) {
      $data->{$j}{library} = $libs->{$l};
      unless ($data->{$j}{library}{name}) {
	$data->{$j}{library}{name} = $n;
      }
      ## type: calculated takes precidence over inputed      
      $data->{$j}{library}{type} = $t ? $t : $self->investigation_type_alias($libs->{$l}{data}{investigation_type});
      unless ($data->{$j}{library}{data}{seq_meth}) {
	    $data->{$j}{library}{data}{seq_meth} = exists($mmap{$j}) ? $mmap{$j} : '';
      }
      # make sure these are same as job table
      $data->{$j}{library}{data}{metagenome_id}   = $m;
      $data->{$j}{library}{data}{metagenome_name} = $n;
      if ($f) { $data->{$j}{library}{data}{file_name} = $f; }
      if ($c) { $data->{$j}{library}{data}{file_checksum} = $c; }
    }
    if ($s && exists($epks->{$s})) {
      $data->{$j}{env_package} = $epks->{$s};
      $data->{$j}{env_package}{type} = exists($epks->{$s}{data}{env_package}) ? $epks->{$s}{data}{env_package} : (exists($samps->{$s}{data}{env_package}) ? $samps->{$s}{data}{env_package} : '');
      unless ($data->{$j}{env_package}{name}) {
	$data->{$j}{env_package}{name} = $data->{$j}{env_package}{type} ? $n.": ".$data->{$j}{env_package}{type} : $n;
      }
    }
  }
  return $data;
}

=pod

=item * B<get_jobs_metadata> (Array(JobObject<job>), Boolean<is_mgid>)

Returns Metadata for jobs in the format:
key => category_type => { id => #, name => '', type => '', data => {tag => value} }
where key is metageome_id if is_mgid=1, else job_id (default)

=cut 

sub get_jobs_metadata {
  my ($self, $jobs, $is_mgid, $full_data) = @_;

  my $data = {};
  foreach my $job (@$jobs) {
    my $key = $is_mgid ? $job->metagenome_id : $job->job_id;
    if ($job->primary_project) {
      $data->{$key}{project} = {id => 'mgp'.$job->primary_project->id, name => $job->primary_project->name, public => $job->primary_project->public, data => $job->primary_project->data};
      map { $data->{$key}{project}{data}{$_} =~ s/^(gaz|country):\s?//i } grep {$data->{$key}{project}{data}{$_}} keys %{$data->{$key}{project}{data}};
      if ($full_data) {
	$data->{$key}{project}{data} = $self->add_template_to_data('project', $data->{$key}{project}{data});
      }
    }
    if ($job->sample) {
      $data->{$key}{sample} = {id => 'mgs'.$job->sample->ID, name => $job->sample->name || $job->name, data => $job->sample->data};
      map { $data->{$key}{sample}{data}{$_} =~ s/^(gaz|country|envo):\s?//i } grep {$data->{$key}{sample}{data}{$_}} keys %{$data->{$key}{sample}{data}};
      if ($full_data) {
	$data->{$key}{sample}{data} = $self->add_template_to_data('sample', $data->{$key}{sample}{data});
      }
    }
    if ($job->library) {
      $data->{$key}{library} = {id => 'mgl'.$job->library->ID, name => $job->library->name || $job->name, data => $job->library->data};
      ## type: calculated takes precidence over inputed
      $data->{$key}{library}{type} = $job->sequence_type ? $job->sequence_type : $self->investigation_type_alias($job->library->lib_type);
      unless ($data->{$key}{library}{data}{seq_meth}) {
	$data->{$key}{library}{data}{seq_meth} = $job->data('sequencing_method_guess')->{sequencing_method_guess} || '';
      }
      # make sure these are same as job table
      $data->{$key}{library}{data}{metagenome_id}   = $job->{metagenome_id};
      $data->{$key}{library}{data}{metagenome_name} = $job->{name} ? $job->{name} : '';
      if ($job->{file}) { $data->{$key}{library}{data}{file_name} = $job->{file}; }
      if ($job->{file_checksum_raw}) { $data->{$key}{library}{data}{file_checksum} = $job->{file_checksum_raw}; }
      # add template if requested
      if ($full_data) {
	$data->{$key}{library}{data} = $self->add_template_to_data($job->library->lib_type, $data->{$key}{library}{data});
      }
    }
    my $ep = $job->env_package;
    if ($ep) {
      $data->{$key}{env_package} = {id => 'mge'.$ep->ID, name => $ep->name || $job->name.": ".$ep->ep_type, type => $ep->ep_type, data => $ep->data};
      if ($full_data) {
	$data->{$key}{env_package}{data} = $self->add_template_to_data($ep->ep_type, $data->{$key}{env_package}{data});
      }
    }
  }
  return $data;
}

=pod

=item * B<get_job_metadata> (JobObject<job>)

Returns Metadata for a job in the format:
category_type => { id => #, name => '', type => '', data => {tag => value} }

=cut 

sub get_job_metadata {
  my ($self, $job, $full_data) = @_;

  my $data = $self->get_jobs_metadata([$job], 0, $full_data);
  return exists($data->{$job->job_id}) ? $data->{$job->job_id} : {};
}

sub get_job_mixs {
    my ($self, $job) = @_;
    
    my $mixs = {};
    $mixs->{project_id}   = "";
    $mixs->{project_name} = "";
    $mixs->{PI_firstname} = "";
    $mixs->{PI_lastname}  = "";
    eval {
        $mixs->{project_id}   = 'mgp'.$job->primary_project->{id};
        $mixs->{project_name} = $job->primary_project->{name};
    };
    eval {
        my $pdata = $job->primary_project->data;
        $mixs->{PI_firstname} = $pdata->{PI_firstname};
	    $mixs->{PI_lastname}  = $pdata->{PI_lastname};
    };
    my $lat_lon = $job->lat_lon;
    $mixs->{latitude}   = (@$lat_lon > 1) ? $lat_lon->[0] : "";
    $mixs->{longitude}  = (@$lat_lon > 1) ? $lat_lon->[1] : "";
    $mixs->{country}    = $job->country || "";
    $mixs->{location}   = $job->location || "";
    $mixs->{biome}      = $job->biome || "";
    $mixs->{feature}    = $job->feature || "";
    $mixs->{material}   = $job->material || "";
    $mixs->{seq_method} = $job->seq_method || "";
    $mixs->{sequence_type}    = $job->seq_type || "";
    $mixs->{collection_date}  = $job->collection_date || "";
    $mixs->{env_package_type} = $job->env_package_type || "";
    
    return $mixs;
}

=pod

=item * B<is_job_compliant> (JobObject<job>)

Returns true if job exists and has all mandatory mixs fields filled out.

=cut

sub is_job_compliant {
  my ($self, $job) = @_;

  my $mixs = $self->mixs();
  my $data = $self->get_job_metadata($job);
  unless (exists $data->{library}{data}{investigation_type}) {
    return 0;
  }
  my $lib = $data->{library}{data}{investigation_type};
  unless (exists $mixs->{library}{$lib}) {
    return 0;
  }
  foreach my $cat (keys %$mixs) {
    if ($cat eq 'library') {
      foreach my $tag (keys %{$mixs->{library}{$lib}}) {
	if (! exists($data->{$cat}{data}{$tag})) {
	  return 0;
	}
      }
    }
    else {
      foreach my $tag (keys %{$mixs->{$cat}}) {
	if (! exists($data->{$cat}{data}{$tag})) {
	  return 0;
	}
      }
    }
  }
  return 1;
}

=pod

=item * B<verify_job_metadata> (JobObject<job>)

Returns a list of errors is mixs compliance.

=cut

sub verify_job_metadata {
  my ($self, $job) = @_;

  my $mixs = $self->mixs();
  my $data = $self->get_job_metadata($job);
  my $errors = [];
  unless (exists $data->{library}{data}{investigation_type}) {
    push(@$errors, "mandatory term 'investigation type' missing");
  }
  my $lib = $data->{library}{data}{investigation_type};
  unless (exists $mixs->{library}{$lib}) {
    push(@$errors, "library missing");
  }
  foreach my $cat (keys %$mixs) {
    if ($cat eq 'library') {
      foreach my $tag (keys %{$mixs->{library}{$lib}}) {
	if (! exists($data->{$cat}{data}{$tag})) {
	  push(@$errors, "mandatory term '$tag' from category '$cat' missing");
	}
      }
    }
    else {
      foreach my $tag (keys %{$mixs->{$cat}}) {
	if (! exists($data->{$cat}{data}{$tag})) {
	  push(@$errors, "mandatory term '$tag' from category '$cat' missing");
	}
      }
    }
  }
  return $errors;
}

=pod

=item * B<get_metadata_for_tables> (Array[JobObject<job> || Scalar<id>], Boolean<is_mgid>,  Boolean<use_fast>)

Given an array of Job PPO objects (or job/metagenome id if use_fast true),
return a hash refrence of { key => [ category, tag, value ] }
where key is metageome_id if is_mgid=1, else job_id (default)

=cut

sub get_metadata_for_tables {
  my ($self, $jobs, $is_mgid, $use_fast) = @_;
  
  my $data  = $use_fast ? $self->get_jobs_metadata_fast($jobs, $is_mgid) : $self->get_jobs_metadata($jobs, $is_mgid);
  my $table = {};
  foreach my $job (keys %$data) {
    if ($data->{$job}{project}) {
      push @{$table->{$job}}, [ 'Project', 'project_name', $data->{$job}{project}{name} ];
      push @{$table->{$job}}, [ 'Project', 'mgrast_id', $data->{$job}{project}{id} ];
      while ( my ($k, $v) = each %{ $data->{$job}{project}{data} } ) {
	next if ($k eq 'project_name');
	$v = clean_value($v);
	next unless (defined($v) && ($v =~ /\S/));
	push @{$table->{$job}}, [ 'Project', $k, $v ];
      }
    }
    if ($data->{$job}{sample}) {
      push @{$table->{$job}}, [ 'Sample', 'sample_name', $data->{$job}{sample}{name} ];
      push @{$table->{$job}}, [ 'Sample', 'mgrast_id', $data->{$job}{sample}{id} ];
      while ( my ($k, $v) = each %{ $data->{$job}{sample}{data} } ) {
	$v = clean_value($v);
	next unless (defined($v) && ($v =~ /\S/));
	push @{$table->{$job}}, [ 'Sample', $k, $v ];
      }
    }
    if ($data->{$job}{library}) {
      my $ltype = $data->{$job}{library}{data}{investigation_type} || $data->{$job}{library}{type};
      push @{$table->{$job}}, [ "Library: $ltype", 'library_name', $data->{$job}{library}{name} ];
      push @{$table->{$job}}, [ "Library: $ltype", 'mgrast_id', $data->{$job}{library}{id} ];
      while ( my ($k, $v) = each %{ $data->{$job}{library}{data} } ) {
	$v = clean_value($v);
	next unless (defined($v) && ($v =~ /\S/));
	push @{$table->{$job}}, [ "Library: $ltype", $k, $v ];
      }
    }
    if ($data->{$job}{env_package}) {
      my $etype = $data->{$job}{env_package}{type};
      push @{$table->{$job}}, [ "Enviromental Package: $etype", 'mgrast_id', $data->{$job}{env_package}{id} ];
      while ( my ($k, $v) = each %{ $data->{$job}{env_package}{data} } ) {
	$v = clean_value($v);
	next unless (defined($v) && ($v =~ /\S/));
	push @{$table->{$job}}, [ "Enviromental Package: $etype", $k, $v ];
      }

    }
  }
  return $table;
}

sub get_metadata_for_table {
  my ($self, $job, $is_mgid, $use_fast) = @_;

  my $result = $self->get_metadata_for_tables([$job], $is_mgid, $use_fast);
  my $table  = [];

  if ($use_fast && exists($result->{$job})) {
    $table = $result->{$job};
  }
  elsif ((! $use_fast) && $is_mgid && exists($result->{$job->metagenome_id})) {
    $table = $result->{$job->metagenome_id};
  }
  elsif ((! $use_fast) && (! $is_mgid) && exists($result->{$job->job_id})) {
    $table = $result->{$job->job_id};
  }
  return $table;
}

=pod

=item * B<export_metadata_for_jobs> (Arrayref<JobObject job>, Scalar<file>, Scalar<orient>)

For a given list of Job Objs and a file name.
return a filepath with a matrix of metagenome ids X metadata names, cell is value
orient = 'job' sets mgid as column header
orient = 'key' sets metadata category:tag as column header

=cut

sub export_metadata_for_jobs {
  my ($self, $jobs, $file, $orient) = @_;

  unless ($orient) { $orient = "tag"; }

  my $fpath = "$Conf::temp/$file";
  my $keys  = {};
  my $jset  = [];

  foreach my $jobj (@$jobs) {
    my $jid  = $jobj->metagenome_id;
    my $data = $self->get_job_metadata($jobj);
    push @$jset, $jid;
    foreach my $cat (keys %$data) {
      foreach my $tag (keys %{$data->{$cat}{data}}) {
	my $key = exists($data->{$cat}{type}) ? $cat.':'.$data->{$cat}{type}.':'.$tag : $cat.':'.$tag;
	if ( defined($data->{$cat}{data}{$tag}) && ($data->{$cat}{data}{$tag} =~ /\S/) ) {
	  $keys->{$key}{$jid} = $data->{$cat}{data}{$tag};
	}
      }
    }
  }

  if (open(FILE, ">$fpath")) {
    if ($orient eq "job") {
      print FILE "#SampleID\t" . join("\t", @$jset) . "\n";
      foreach my $k (sort keys %$keys) {
	my @row = ();
	foreach my $j (@$jset) {
	  push @row, exists($keys->{$k}{$j}) ? $keys->{$k}{$j} : '';
	}
	print FILE "$k\t" . join("\t", @row) . "\n";
      }
    } else {
      print FILE "#SampleID\t" . join("\t", sort keys %$keys) . "\n";
      foreach my $j (@$jset) {
	my @row = ();
	foreach my $k (sort keys %$keys) {
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

=item * B<export_metadata_for_project> (ProjectObject<project>)

return hash of metadata for project and its collections
return hash: { name:<proj_name: str>, data:<proj_data: dict>, sampleNum:<number_samples: int>, samples:<list of sample objs> }
objects:
data:        { tag: {qiime_tag:<str>, mgrast_tag:<str>, definition:<str>, required:<bool>, mixs:<bool>, type:<str>, value:<str>} }
sample:      { name:<samp_name: str>, data:<samp_data: dict>, envPackage:<env_package obj>, libNum:<number_libraries: int>, libraries:<list of library objs> }
library:     { name:<metagenome_name: str>, type:<library_type: str>, data<library_data: dict> }
env_package: { name:<samp_name-env_package_type: str>, type:<env_package_type: str>, data<env_package_data: dict> }

=cut

sub export_metadata_for_project {
  my ($self, $project, $all_fields) = @_;

  my $pdata = $project->data;
  $pdata->{project_name} = $project->name;
  $pdata->{mgrast_id}    = 'mgp'.$project->id;
  my $mdata = { name => $project->name,
		id   => 'mgp'.$project->id,
		data => $self->add_template_to_data('project', $pdata, $all_fields),
		sampleNum => 0,
		samples   => [] };

  foreach my $samp ( @{ $project->collections('sample') } ) {
    my $e_obj = {};
    my $epack = $samp->children('ep');
    my $sdata = $samp->data;
    my $sname = $samp->name || 'mgs'.$samp->ID;

    if (@$epack && $epack->[0]->ep_type) {
      my $edata = $epack->[0]->data;
      $edata->{sample_name} = $sname;
      $edata->{mgrast_id}   = 'mge'.$epack->[0]->ID;
      $e_obj = { name => $epack->[0]->name || 'mge'.$epack->[0]->ID,
		 id   => 'mge'.$epack->[0]->ID,
		 type => $epack->[0]->ep_type,
		 data => $self->add_template_to_data($epack->[0]->ep_type, $edata, $all_fields) };
    }
    $sdata->{sample_name} = $sname;
    $sdata->{mgrast_id}   = 'mgs'.$samp->ID;
    my $s_obj = { name   => $sname,
		  id     => 'mgs'.$samp->ID,
		  data   => $self->add_template_to_data('sample', $sdata, $all_fields),
		  libNum => 0,
		  libraries => []
		};
    if (exists $e_obj->{id}) {
      $s_obj->{envPackage} = $e_obj;
    }

    foreach my $lib ( @{ $samp->children('library') } ) {
      next unless ($lib->lib_type);
      my $ldata = $lib->data;
      $ldata->{sample_name} = $sname;
      $ldata->{mgrast_id}   = 'mgl'.$lib->ID;
      my $lib_jobs = $lib->jobs;
      if (@$lib_jobs > 0) {
	$ldata->{metagenome_id} = $lib_jobs->[0]->{metagenome_id};
	$ldata->{metagenome_name} = $lib_jobs->[0]->{name} || '';
	if ($lib_jobs->[0]->{file}) { $ldata->{file_name} = $lib_jobs->[0]->{file}; }
	if ($lib_jobs->[0]->{file_checksum_raw}) { $ldata->{file_checksum} = $lib_jobs->[0]->{file_checksum_raw}; }
      }
      push @{ $s_obj->{libraries} }, { name => $lib->name || 'mgl'.$lib->ID,
				       id   => 'mgl'.$lib->ID,
				       type => $lib->lib_type,
				       data => $self->add_template_to_data($lib->lib_type, $ldata, $all_fields)};
      $s_obj->{libNum} += 1;
    }

    push @{ $mdata->{samples} }, $s_obj;
    $mdata->{sampleNum} += 1;
  }
  return $mdata;
}

## input:  { tag => value }
## output: { tag => {aliases=>[<str>], definition=><str>, required=><bool>, mixs=><bool>, type=><str>, unit=><str>, value=><str>} }
## all required tags will be added
sub add_template_to_data {
  my ($self, $cat, $data, $all) = @_;
  my $t_data   = {};
  my $template = $self->template;
  my @required = grep { ($_ ne 'category_type') && $template->{$cat}{$_}{required} } keys %{$template->{$cat}};
  map { $data->{$_} = '' } grep { ! exists($data->{$_}) } @required;
  if ($all) {
    my @all_fields = grep { $_ ne 'category_type' } keys %{$template->{$cat}};
    map { $data->{$_} = '' } grep { ! exists($data->{$_}) } @all_fields;
  }

  my $misc = 0;
  while ( my ($tag, $val) = each %$data ) {
    my $ttag = '';
    $val = clean_value($val);
    if (! exists $template->{$cat}{$tag}) {
      next unless (defined($val) && ($val =~ /\S/));
      if ($tag =~ /^misc_param_/) {
	$ttag = 'misc_param';
      } else {
	$misc += 1;
	$val  = $tag.': '.$val;
	$tag  = 'misc_param_'.$misc;
	$ttag = 'misc_param';
      }
    } else {
      $ttag = $tag;
    }
    next unless ($all || $template->{$cat}{$ttag}{required} || (defined($val) && ($val =~ /\S/)));
    $t_data->{$tag}{value} = $val;
    $t_data->{$tag}{unit}  = $template->{$cat}{$ttag}{unit};
    $t_data->{$tag}{type}  = $template->{$cat}{$ttag}{type};
    $t_data->{$tag}{mixs}  = $template->{$cat}{$ttag}{mixs};
    $t_data->{$tag}{aliases} = $template->{$cat}{$ttag}{aliases};
    $t_data->{$tag}{required} = $template->{$cat}{$ttag}{required};
    $t_data->{$tag}{definition} = $template->{$cat}{$ttag}{definition};
  }
  return $t_data;
}

sub clean_value {
  my ($val) = @_;
  if ($val) {
    $val =~ s/^\s+//;
    $val =~ s/\s+$//;
    $val =~ s/^-$//;
  }
  return $val;
}

=pod

=item * B<get_unique_for_tag> (Scalar<tag>)

Returns list of unique values for a specific tag from MetaDataEntry.

=cut 

sub get_unique_for_tag {
  my ($self, $tag) = @_;
  
  $tag = lc( clean_value($tag) );
  my $mddb = $self->{_handle};
  my $tmp = $mddb->db_handle->selectcol_arrayref("SELECT DISTINCT value FROM MetaDataEntry WHERE tag=".$mddb->db_handle->quote($tag));
  return ($tmp && @$tmp) ? $tmp : [];
}


=pod

=item * B<get_all_for_tag> (Scalar<tag>, Boolean<no_ppo>)

Returns all data for a specific tag from MetaDataEntry.
If no_ppo true return [ _id, collection, value ], else return PPO object array.

=cut 

sub get_all_for_tag {
  my ($self, $tag, $no_ppo) = @_;
  
  my $mddb = $self->{_handle};

  if (! $no_ppo) {
    return $mddb->MetaDataEntry->get_objects({tag => $tag});
  }
  else {
    my $tmp = $mddb->db_handle->selectall_arrayref("SELECT _id,collection,value FROM MetaDataEntry WHERE tag=\'$tag\'");
    return ($tmp && @$tmp) ? $tmp : [];
  }
}

=pod

=item * B<add_entry> (CollectionObject<collection>, Arrayref<data>, Boolean<append>)

Adds/modifies tag / value for inputed collection and job in MetaDataEntry.
If append option is true, will append value to tag list.

=cut

sub add_entries {
  my ($self, $collection, $data, $append) = @_;

  unless ($collection && ref($collection)) { return undef; }
  my $template = $self->template();
  my $mddb  = $self->{_handle};
  my $ctype = $collection->category_type( $collection->type ) || '';

  foreach my $set (@$data) {
    my ($tag, $val) = @$set;
    next unless (defined($val) && ($val =~ /\S/));
    if (! $append) {
      my $objs = $mddb->MetaDataEntry->get_objects({collection => $collection, tag => $tag});
      foreach my $o (@$objs) { $o->delete(); }
    }
    my $attr = { collection => $collection,
		 tag        => $tag,
		 value      => $val,
		 required   => exists($template->{$ctype}{$tag}{required}) ? $template->{$ctype}{$tag}{required} : 0,
		 mixs       => exists($template->{$ctype}{$tag}{mixs}) ? $template->{$ctype}{$tag}{mixs} : 0
	       };
    $mddb->MetaDataEntry->create($attr);
  }
}

=pod

=item * B<add_collection> (ProjectObject<project>,Scalar<type>,CuratorObject<creator>,Scalar<name>,MetaDataCollectionObject<parent>,Scalar<source>,Scalar<url>,JobObject<job>)

Creates and returns a MetaDataCollection PPO obj.
Creates links in Job obj and ProjectCollection obj.
project and type are required, rest are optional

=cut

sub add_collection {
  my ($self, $project, $type, $creator, $name, $parent, $source, $url, $job) = @_;

  unless ($project && ref($project) && $type) { return undef; }
  my $mddb = $self->{_handle};
  my $id   = $mddb->MetaDataCollection->last_id + 1;
  my $attr = { ID     => $id,
	       type   => $type,
	       source => ($source ? $source : "MG-RAST"),
	       url    => ($url ? $url : ''),
	       name   => ($name ? $name : '')
	     };
  if ($creator && ref($creator)) {
    $attr->{creator} = $creator;
  }
  if ($parent && ref($parent)) {
    $attr->{parent} = $parent;
  }
  my $coll = $mddb->MetaDataCollection->create($attr);
  $mddb->ProjectCollection->create({project => $project, collection => $coll});
  if ($job && ref($job)) {
    if ($type eq 'sample') {
      $job->sample($coll);
    } elsif ($type eq 'library') {
      $job->library($coll);
    }
  }
  return $coll;
}

=pod

=item * B<add_curator> (UserObject<user>, Scalar<status>, Scalar<url>)

Creates and returns a Curator PPO obj based upon given WebAppBackend::User PPO obj.
status and url are optional.

=cut

sub add_curator {
  my ($self, $user, $status, $url) = @_;

  unless ($user && ref($user)) { return undef; }
  my $mddb = $self->{_handle};
  my $this_user = $mddb->Curator->get_objects({user => $user});
  if (@$this_user > 0) {
    return $this_user->[0];
  }
  my $max = $mddb->db_handle->selectrow_arrayref("SELECT MAX(ID) FROM Curator");
  if ($max && (@$max > 0)) {
    my $attr = { ID     => $max->[0] + 1,
		 status => ($status ? $status : "manual"),
		 name   => $user->firstname . " " . $user->lastname,
		 email  => $user->email,
		 url    => ($url ? $url : ''),
		 user   => $user,
		 type   => ($user->is_admin('MGRAST') ? "Admin" : "User")
	       };
    return $mddb->Curator->create($attr);
  }
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
    my $attr = { comment    => ($comment ? $comment : ''),
		 collection => $collection,
		 curator    => $curator,
		 type       => ($type ? $type : '')
	       };
    return $mddb->UpdateLog->create($attr);
  }
  return undef;
}

=pod

=item * B<update_collection> (Scalar<collection>, Hashref<attributes>)

Updates MetaDataCollection, based on collection ID, with inputed attributes.

=cut

sub update_collection {
  my ($self, $collection, $attributes) = @_;
  $self->{_handle}->MetaDataCollection->init({ID => $collection})->set_attributes($attributes);
}

=pod

=item * B<update_curator> (Scalar<curator>, Hashref<attributes>)

Updates Curator, based on curator ID, with inputed attributes.

=cut

sub update_curator {
  my ($self, $curator, $attributes) = @_;
  $self->{_handle}->Curator->init({ID => $curator})->set_attributes($attributes);
}

sub validate_metadata {
  my ($self, $filename, $skip_required, $map_by_id) = @_;

  my $extn = '';
  if ($filename =~ /\.(xls(x)?)$/) {
    $extn = $1;
  } else {
    return (0, {is_valid => 0, data => []}, "Invalid filetype. Needs to be one of .xls or .xlsx");
  }
  my ($out_hdl, $out_name) = tempfile("metadata_XXXXXXX", DIR => $Conf::temp, SUFFIX => '.json');
  close $out_hdl;

  my $data = {};
  my $json = new JSON;
  my $text = "";
  my $cmd  = $Conf::validate_metadata.($skip_required ? " -s" : "").($map_by_id ? " -d" : "")." -f $extn -j $out_name $filename 2>&1";
  my $log  = `$cmd`;
  chomp $log;
  
  eval {
      open(JSONF, "<$out_name");
      $text = do { local $/; <JSONF> };
      close JSONF;
  };
  if ($@) {
      return (0, {is_valid => 0, data => []}, $@);
  }

  if (! $text) {
    $data = { is_valid => 0, data => [] };
  } else {
    $json = $json->utf8();
    $data = $json->decode($text);
  }

  my $is_valid = $data->{is_valid} ? 1 : 0;
  return ($is_valid, $data, $log);
}

### this handels both new projects / collections and updating existing
sub add_valid_metadata {
  my ($self, $user, $data, $jobs, $project, $map_by_id, $delete_old) = @_;

  unless ($user && ref($user)) {
    return (undef, [], ["invalid user object"]);
  }

  my $err_msg = [];
  my $added   = [];
  my $mddb    = $self->{_handle};
  my $curator = $self->add_curator($user);
  my $job_map = {};
  my $job_name_change = []; # [old, new]
  if ($map_by_id) {
    %$job_map = map {$_->metagenome_id, $_} grep {$user->has_right(undef, 'edit', 'metagenome', $_->metagenome_id) || $user->has_star_right('edit', 'metagenome')} @$jobs;
  } else {
    %$job_map = map {$_->name, $_} grep {$user->has_right(undef, 'edit', 'metagenome', $_->metagenome_id) || $user->has_star_right('edit', 'metagenome')} @$jobs;
  }
  if (scalar(keys %$job_map) < scalar(@$jobs)) {
    push @$err_msg, "user lacks permission to edit ".(scalar(@$jobs) - scalar(keys %$job_map))." metagenome(s)";
  }
  
  ### create project / add jobs and metadata
  my $new_proj = 0;
  my @proj_md  = map { [$_, $data->{data}{$_}{value}] } keys %{$data->{data}};
  unless ($project && ref($project)) {
    $project  = $mddb->Project->create_project($user, $data->{name}, \@proj_md, $curator, 0);
    $new_proj = 1;
  }
  unless ( $user->has_right(undef, 'edit', 'project', $project->id) || $user->has_star_right('edit', 'project') ) {
    push @$err_msg, "user lacks permission to edit project ".$project->id;
    return ($project->id, [], $err_msg);
  }
  unless ($new_proj) {
    foreach my $md (@proj_md) {
      $project->data($md->[0], $md->[1]);
    }
  }

  ## process samples
  SAMP: foreach my $samp (@{$data->{samples}}) {
    my $samp_coll = undef;
    # use existing sample if ID given
    if ($samp->{id}) {
      my $samp_ID = $samp->{id};
      $samp_ID    =~ s/mgs(.+)/$1/;
      $samp_coll  = $mddb->MetaDataCollection->init({ID => $samp_ID});
      my $samp_proj = [];
      if (ref($samp_coll)) {
	$samp_proj = $mddb->ProjectCollection->get_objects({project => $project, collection => $samp_coll});
      }
      if (@$samp_proj == 0) {
	push @$err_msg, "sample ".$samp->{id}." does not exist";
	next SAMP;
      } else {
	# valid sample for this project
	$samp_coll->name($samp->{name});
      }
    }
    # else create new sample
    else {
      $samp_coll = $self->add_collection($project, 'sample', $curator, $samp->{name});
    }
    # delete / replace sample metadata
    my $samp_mde = $mddb->MetaDataEntry->get_objects({collection => $samp_coll});
    map { $_->delete() } @$samp_mde;
    if (exists $samp->{data}{mgrast_id}) {
      $samp->{data}{mgrast_id} = { value => 'mgs'.$samp_coll->ID };
    }
    my @samp_md = map { [ $_, $samp->{data}{$_}{value} ] } keys %{$samp->{data}};
    $self->add_entries($samp_coll, \@samp_md);
    
    ## process sample env_package
    my $ep_coll = undef;
    # use existing env_package if ID given
    if ($samp->{envPackage}{id}) {
      my $ep_ID = $samp->{envPackage}{id};
      $ep_ID    =~ s/mge(.+)/$1/;
      $ep_coll  = $mddb->MetaDataCollection->init({ID => $ep_ID});
      if (ref($ep_coll) && ($ep_coll->parent->{ID} == $samp_coll->ID)) {
	# valid ep for this sample
	$ep_coll->name($samp->{envPackage}{name});
      }
    }
    # create new ep for this sample if not created above
    unless (ref($ep_coll) && ($ep_coll->parent->{ID} == $samp_coll->ID)) {
      $ep_coll = $self->add_collection($project, 'ep', $curator, $samp->{envPackage}{name}, $samp_coll);
    }
    # delete / replace ep metadata
    my $ep_mde = $mddb->MetaDataEntry->get_objects({collection => $ep_coll});
    map { $_->delete() } @$ep_mde;
    if (exists $samp->{envPackage}{data}{mgrast_id}) {
      $samp->{envPackage}{data}{mgrast_id} = { value => 'mge'.$ep_coll->ID };
    }
    my @ep_md = map { [ $_, $samp->{envPackage}{data}{$_}{value} ] } keys %{$samp->{envPackage}{data}};
    push @ep_md, [ 'env_package', $samp->{envPackage}{type} ];
    $self->add_entries($ep_coll, \@ep_md);

    ## process libraries for sample
    my $has_lib = 0;
    LIB: foreach my $lib (@{$samp->{libraries}}) {
      # find job associated with library (use id or name for mapping)
      my $lib_mg  = $map_by_id ? ($lib->{data}{metagenome_id} ? $lib->{data}{metagenome_id}{value} : undef) : $lib->{data}{metagenome_name}{value};
      my $lib_job = ($lib_mg && exists($job_map->{$lib_mg})) ? $job_map->{$lib_mg} : undef;
      unless ($lib_job && ref($lib_job)) {
	push @$err_msg, "unable to map a metagenome to library ".$lib->{name};
	next LIB;
      }

      my $lib_coll = undef;
      # use existing library if ID given
      if ($lib->{id}) {
	my $lib_ID = $lib->{id};
	$lib_ID    =~ s/mgl(.+)/$1/;
	$lib_coll  = $mddb->MetaDataCollection->init({ID => $lib_ID});
	my $lib_proj = [];
	if (ref($lib_coll)) {
	  $lib_proj = $mddb->ProjectCollection->get_objects({project => $project, collection => $lib_coll});
	}
	if (@$lib_proj == 0) {
	  push @$err_msg, "library ".$lib->{id}." does not exist";
	  next LIB;
	} else {
	  # valid library for this project
	  $lib_coll->name($lib->{name});
	}
      }
      # else create new library
      else {
	$lib_coll = $self->add_collection($project, 'library', $curator, $lib->{name}, $samp_coll);
      }
      # delete / replace library metadata
      my $lib_mde = $mddb->MetaDataEntry->get_objects({collection => $lib_coll});
      map { $_->delete() } @$lib_mde;
      if (exists $lib->{data}{mgrast_id}) {
	$lib->{data}{mgrast_id} = { value => 'mgl'.$lib_coll->ID };
      }
      my @lib_md = map { [$_, $lib->{data}{$_}{value}] } keys %{$lib->{data}};
      $self->add_entries($lib_coll, \@lib_md);

      ### add job to project
      my $msg = $project->add_job($lib_job);
      if ($msg =~ /error/i) {
	push @$err_msg, $msg;
	next LIB;
      } else {
	## delete old if exists and not same as new
	if ($delete_old && $lib_job->sample && ref($lib_job->sample) && ($lib_job->sample->ID != $samp_coll->ID)
	                && $lib_job->library && ref($lib_job->library) && ($lib_job->library->ID != $lib_coll->ID)) {
	  my $old_samp = $lib_job->sample;
	  my $os_jobs  = $old_samp->jobs;
	  if ((@$os_jobs == 1) && ($os_jobs->[0]->job_id == $lib_job->job_id)) {
	    $old_samp->delete_all;
	    $old_samp->delete;
	  }
	  else {
	    my $old_lib = $lib_job->library;
	    my $ol_jobs = $old_lib->jobs;
	    if ((@$ol_jobs == 1) && ($ol_jobs->[0]->job_id == $lib_job->job_id)) {
	      $old_lib->delete_all;
	      $old_lib->delete;
	    }
	  }
	}
	## add new sample and library to job and project
	$lib_job->sample($samp_coll);
	$lib_job->library($lib_coll);
	$project->add_collection( $lib_job->sample );
	$project->add_collection( $lib_job->library );
	push @$added, $lib_job;
	$has_lib = 1;

	# change job name if differs and using id mapping
	if ($map_by_id && exists($lib->{data}{metagenome_name}) && ($lib->{data}{metagenome_name}{value} ne $lib_job->name)) {
	  $lib_job->name( $lib->{data}{metagenome_name}{value} );
	}
      }
    }
    unless ($has_lib) {
      push @$err_msg, "sample '".$samp_coll->name."' has no library, not creating sample";
      $samp_coll->delete_all;
      $samp_coll->delete;
    }
  }
  return ($project->id, $added, $err_msg);
}

sub investigation_type_alias {
  my ($self, $type) = @_;
  unless ($type) { return ""; }
  if    ($type eq 'metagenome')        { return "WGS"; }
  elsif ($type eq 'mimarks-survey')    { return "Amplicon"; }
  elsif ($type eq 'metatranscriptome') { return "MT"; }
  elsif ($type eq 'WGS')               { return "metagenome"; }
  elsif ($type eq 'Amplicon')          { return "mimarks-survey"; }
  elsif ($type eq 'MT')                { return "metatranscriptome"; }
  else { return ""; }
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
