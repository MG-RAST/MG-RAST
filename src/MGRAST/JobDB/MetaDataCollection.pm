package JobDB::MetaDataCollection;

use strict;
use warnings;
use Data::Dumper ;

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
    
    my $jstat = $self->_master->MetaDataEntry->get_objects( { collection   => $self ,
							  tag       => $tag  ,
							  value     => $value ,
							});
    if ( ref $jstat and scalar @$jstat ){
      $jstat->[0]->value($value) ;
    }
    else{
      $jstat = $self->_master->MetaDataEntry->create( { collection   => $self ,
						    tag       => $tag  ,
						    value     => $value ,
						  });
    }

    return $value  ;
  }
  elsif( $tag ){
    $sth = $dbh->prepare("SELECT tag, value FROM MetaDataEntry where collection='". $self->_id ."' and tag='$tag'") ;
    $sth->execute;
     my $results = $sth->fetchall_arrayref();
  
    return map { $_->[1] } @$results ;
  }
  else{
    $sth = $dbh->prepare("SELECT tag, value FROM MetaDataEntry where collection='". $self->_id ."'");
  }
  
  $sth->execute;
  my $results = $sth->fetchall_arrayref();
  my $rhash = {};
  map { $rhash->{ $_->[0] } = $_->[1] } @$results ;
  
  return $rhash;
}


sub xml {
    my ($self) = @_ ;
    

    my $jobs = [] ;
    push @$jobs , $self->job if ($self->job) ;
    push @$jobs , @{ $self->_master->Job->get_objects( {sample => $self} ) };
    
   
    my $pjs = {} ;
  
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


sub tabular{
    my ($self) = @_ ;
    #  my $jids = {} ;
    # map { print Dumper $jobs unless(ref $_) ; $jids->{$_->metagenome_id} }  @$jobs ;
    # my $names = {} ;
    # map { $names->{$_->name} } @$jobs ;
    # my $jobs = [] ;
    # push @$jobs , $self->job->metagenome_id if ($self->job) ;
    # push @$jobs ,  $self->_master->Job->get_objects( {sample => $self} ) ;
    
    # # dump meta data
    # my $mds =  $self->_master->MetaDataEntry->get_objects( { job => $j } ) ;
    # 	if ($mds and scalar @$mds){
    # 	  open(META , ">$tmp_dir/metadata.txt") or die "Can't open $tmp_dir/metadata.txt for writing!\n";
    # 	  print META "metagenome_id\t".$j->metagenome_id."\n";
	  
    # 	  my $pjs = $self->_master->ProjectJob->get_objects( { job => $j } ) ;
    # 	  if ($pjs and scalar @$pjs){
    # 	    print "project_name\t" , join ";" , map { $pj->project->name } @$pjs ;
    # 	    print "project_id\t" , join ";" , map { $pj->project->id } @$pjs ;
    # 	  }
	  
    # 	  foreach my $md (@$mds){
    # 	    print META $md->tag , "\t" , $md->value, "\n" ;	 
    # 	  }
    # 	  close(META) ;
    # 	}
}

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

