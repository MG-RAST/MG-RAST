package JobDB::MetaDataCollection;

use strict;
use warnings;
use Data::Dumper;

sub last_id {
    my ($self) = @_;

    my $dbh = $self->_master()->db_handle();
    my $sth = $dbh->prepare("SELECT max(ID + 0) FROM MetaDataCollection");
    $sth->execute;
    my $result = $sth->fetchrow_arrayref();
    my ($id) = $result->[0] =~/^(\d+)/;
    return $id || "0" ;
}

=item * B<data> ()

Returns a hash of all MDE keys and values for a collection. 
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
    my $jstat = $self->_master->MetaDataEntry->get_objects( { collection => $self,
							      tag        => $tag,
							      value      => $value
							    });
    if (ref $jstat and scalar @$jstat) {
      $jstat->[0]->value($value) ;
    }
    else {
      $jstat = $self->_master->MetaDataEntry->create( { collection => $self,
							tag        => $tag,
							value      => $value
						      });
    }
    return 1;
  }
  elsif ($tag) {
    $sth = $dbh->prepare("SELECT tag, value FROM MetaDataEntry where collection=".$self->_id." and tag='$tag'");
  } else {
    $sth = $dbh->prepare("SELECT tag, value FROM MetaDataEntry where collection=".$self->_id);
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash   = {};
  foreach my $set (@$results) {
    if (defined($set->[1]) && ($set->[1] =~ /\S/)) {
      $set->[1] =~ s/(envo|gaz)://i;
      $rhash->{$set->[0]} = $set->[1];
    }
  }  
  return $rhash;
}

=item * B<value_set> ()

Returns a list of values for given tag

=cut

sub value_set {
  my ($self, $tag) = @_;

  my $set  = [];
  my $dbh  = $self->_master->db_handle;
  my $results = $dbh->selectcol_arrayref("SELECT value FROM MetaDataEntry where collection=".$self->_id." and tag='$tag'");
  if ($results && (@$results > 0)) {
    foreach my $v (@$results) {
      if (defined($v) && ($v =~ /\S/)) { push @$set, $v; }
    }
  }
  return $set;
}

=item * B<project> ()

Returns project that have this collection

=cut

sub project {
  my ($self) = @_;
  my $proj_coll = $self->_master->ProjectCollection->get_objects({collection => $self});
  return (@$proj_coll > 0) ? $proj_coll->[0]->project : undef;
}

=item * B<jobs> ()

Returns array of jobs that have this collection

=cut

sub jobs {
  my ($self) = @_;

  my $jobs = [];
  if ($self->type eq 'sample') {
    $jobs = $self->_master->Job->get_objects({sample => $self, viewable => 1});
  }
  elsif ($self->type eq 'library') {
    $jobs = $self->_master->Job->get_objects({library => $self, viewable => 1});
  }
  elsif (($self->type eq 'ep') && $self->parent && ref($self->parent)) {
    $jobs = $self->_master->Job->get_objects({sample => $self->parent, viewable => 1});
  }
  return $jobs;
}

=item * B<children> ()

Returns array of children collections,
if type given only returns children of that type

=cut

sub children {
  my ($self, $type) = @_;

  my $children = [];
  if ($type) {
    $children = $self->_master->MetaDataCollection->get_objects({parent => $self, type => $type});
  } else {
    $children = $self->_master->MetaDataCollection->get_objects({parent => $self});
  }
  return $children;
}

sub category_type {
  my ($self, $type) = @_;

  my $ct = '';
  if ($type eq 'library') {
    $ct = $self->data('investigation_type')->{'investigation_type'};
  }
  elsif ($type eq 'ep') {
    $ct = $self->data('env_package')->{'env_package'} || $self->parent->data('env_package')->{'env_package'};
  }
  else {
    $ct = $self->type;
  }
  return $ct;
}

sub lib_type {
  my ($self) = @_;
  return $self->category_type('library');
}

sub ep_type {
  my ($self) = @_;
  return $self->category_type('ep');
}

sub delete_all {
  my ($self) = @_;
  $self->delete_children;
  $self->delete_entries;
  $self->delete_project;
}

sub delete_project {
  my ($self) = @_;
  foreach my $pc ( @{ $self->_master->ProjectCollection->get_objects({collection => $self}) } ) {
    $pc->delete;
  }
}

sub delete_entries {
  my ($self) = @_;
  foreach my $mde ( @{ $self->_master->MetaDataEntry->get_objects({collection => $self}) } ) {
    $mde->delete;
  }
}

sub delete_children {
  my ($self) = @_;
  foreach my $child ( @{ $self->children } ) {
    $child->delete_all;
    $child->delete;
  }
}

sub xml {
    my ($self) = @_;

    my $jobs = [];
    push @$jobs , $self->job if ($self->job) ;
    push @$jobs , @{ $self->_master->Job->get_objects( {sample => $self, viewable => 1} ) };
    
    my $pjs = {};
  
    map { map {$pjs->{ $_->project->id } = $_->project }  @{ $self->_master->ProjectJob->get_objects( { job => $_ } ) } } @$jobs;
    
    my $xml = "<?xml version=\"1.0\" ?>\n" ;
    $xml .= "<sample>\n";
    $xml .= "<name>". ($self->name || $self->data('sample_name') || "unknown" ) ."</name>\n";
    $xml .= "<sample_id namespace='MG-RAST'>". $self->ID ."</sample_id>\n";
    foreach my $pid (keys %$pjs){
      my $p = $pjs->{$pid};
      $xml .="<project>\n";
      $xml .="\t<name>".$p->name."</name>\n";
      $xml .="\t<project_id namespace='MG-RAST'>".$p->id."</project_id>\n";
      $xml .="</project>\n";
    }
    foreach my $j (@$jobs){
      print Dumper $jobs unless (ref $j);
      $xml .="<metagenome>\n";
      $xml .= "\t<metagenome_id namespace='MG-RAST'>". $j->metagenome_id."</metagenome_id>\n";
      $xml .= "\t<name>". $j->name."</name>\n";
      $xml .="</metagenome>\n";
      
    } 
    $xml .= "<submitter>". ( $self->creator ? $self->creator->name : 'ERROR:no submitter') ."</submitter>\n";
    $xml .= "<submitted>". $self->entry_date ."</submitted>\n";
    $xml .= "<source>". $self->source ."</source>\n" if ($self->source); 
    $xml .= "<url>". $self->source ."</url>\n" if ($self->url); 
    my $data = $self->_master->MetaDataEntry->get_objects( { collection => $self } );
    foreach my $md (@$data){
	$xml .= "<".$md->tag.">".$md->value."</".$md->tag.">\n";
    }

    $xml .= "</sample>\n";
    
    return $xml ;
}

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

