#
# Annotation clearinghouse client code.
#
# The contrib dir is where the expert annotations are stored; it is separate
# from the main clearinghouse data directory since the clearinghouse data
# will be replaced on a regular basis.
#

package AnnotationClearingHouse::ACH;

use FIG_Config;
use Data::Dumper;
use strict;
use DB_File;
use File::Copy;
use DirHandle;
use IO::File; 
use Digest::MD5;
 
use POSIX;

# my $arch = `arch`;
my $arch = "i686";
chomp $arch;


#
# Construct from directory containing an anno clearinghouse.
#
sub new
{
    my($class,  $dbh , $user , $readonly , $current_dir, $contrib_dir ) = @_;  

    # check 
    print STDERR "No Databses Handle\n" unless ($dbh);
    $contrib_dir = 0 unless ($contrib_dir and -d $contrib_dir);
    $current_dir = 0 unless ($current_dir and -d $current_dir);

    my $self = {
		current_dir => $current_dir || "/vol/clearinghouse/current",
		contrib_dir => $contrib_dir ||  "/vol/clearinghouse/contrib/" ,
		dbh         => $dbh || undef ,
		readonly    => 0 || $readonly ,
		user        => $user ,
	
    };
    

    return bless $self, $class;
}

# database handle
sub dbh{
  my ($self) = @_;
  return $self->{dbh}
}

# directory for all nr files 
sub nr_dir{
   my ($self) = @_;
   return $self->{current_dir}
}

sub user{
  my ($self , $user) = @_;
  $self->{user} = $user if ($user and ref $user);
  return $self->{user}
}



#
# md52... section
#

sub md52id{
 my ($self , $md5 , $regexp) = @_;
 
 $md5 =~ s/'/\\'/gc;
 my $statement = "select ID , md5 from ACH_DATA where md5='$md5'" ;

 

#  my $sth = $self->dbh->prepare( "select ID , md5 from ACH_DATA where md5= ?" );

#  # loop
#  print "STH:\t" ,  $sth->execute($md5) , "\n";
#  $rows = $sth->fetchall_array;
#  # loop

 my $rows  = $self->dbh->selectall_arrayref($statement);
 

  return $rows
}

sub md52id_bulk{
 my ($self , $md5s , $regexp) = @_;
 
 my @sets;
 my $sth = $self->dbh->prepare( "select ID , md5 from ACH_DATA where md5= ?" );
 
 foreach my $md5 (@$md5s){
   $sth->execute($md5);
   push @sets , $sth->fetchall_array;
 }

 return \@sets;
}


sub md52org{
  my ($self, $md5) = @_;
  my $statement = "select ACH_ORGANISMS.name , ACH_DATA.md5 from ACH_DATA , ACH_ORGANISMS where ACH_DATA.md5 = '$md5' and ACH_ORGANISMS._id = ACH_DATA.organism";
  my $rows  = $self->dbh->selectall_arrayref($statement);
  return $rows;
}

sub md52function{
my ($self, $md5) = @_;
my $statement = "select ACH_FUNCTIONS.function , ACH_DATA.md5 from ACH_DATA , ACH_FUNCTIONS where ACH_DATA.md5 = '$md5' and ACH_FUNCTIONS._id = ACH_DATA.function group by ACH_FUNCTIONS.function";
my $rows  = $self->dbh->selectall_arrayref($statement);
return $rows;

}

sub md52set{
 my ($self , $md5 , $regexp) = @_;
 
 $md5 =~ s/'/\\'/gc;
 my $statement = "select ACH_DATA.ID , ACH_DATA.md5 , ACH_FUNCTIONS.function , ACH_ORGANISMS.name , ACH_SOURCES.name  from ACH_DATA , ACH_FUNCTIONS , ACH_ORGANISMS , ACH_SOURCES where ACH_DATA.md5='$md5' and ACH_DATA.function = ACH_FUNCTIONS._id and ACH_DATA.organism = ACH_ORGANISMS._id and ACH_DATA.source = ACH_SOURCES._id" ;

 

#  my $sth = $self->dbh->prepare( "select ID , md5 from ACH_DATA where md5= ?" );

#  # loop
#  print "STH:\t" ,  $sth->execute($md5) , "\n";
#  $rows = $sth->fetchall_array;
#  # loop

 my $rows  = $self->dbh->selectall_arrayref($statement);
 

  return $rows
}


sub md5s2sets{
  my ($self , $md5s) = @_;
  
  my $list = "(";
  while  (my $id = pop @$md5s){
    $id =~ s/'/\\'/gc;
    $list .= "'$id'";
    $list .= " , " if (scalar @$md5s);
  }
  $list .= ")";
  my $statement = "select ACH_DATA.ID , ACH_DATA.md5 , ACH_FUNCTIONS.function , ACH_ORGANISMS.name , ACH_SOURCES.name  from ACH_DATA , ACH_FUNCTIONS , ACH_ORGANISMS , ACH_SOURCES where ACH_DATA.md5 in $list and ACH_DATA.function = ACH_FUNCTIONS._id and ACH_DATA.organism = ACH_ORGANISMS._id and ACH_DATA.source = ACH_SOURCES._id order by ACH_DATA.md5" ;
  # print STDERR $statement , "\n";
  my $rows  = $self->dbh->selectall_arrayref($statement);
  
  return $rows   
}


sub md52id4source{
 my ($self , $md5 , $source) = @_;
 
 $md5 =~ s/'/\\'/gc;
 # get source id
 unless ($source =~/^\d+$/){
   my $statement = "select _id from ACH_SOURCES where name='$source'" ;
   my $resp = $self->dbh->selectcol_arrayref($statement);
   $source = $resp->[0];
 }

 my $statement = "select ACH_DATA.ID , ACH_DATA.md5 , ACH_FUNCTIONS.function , ACH_ORGANISMS.name , ACH_SOURCES.name  from ACH_DATA , ACH_FUNCTIONS , ACH_ORGANISMS , ACH_SOURCES where ACH_DATA.md5='$md5' and ACH_DATA.function = ACH_FUNCTIONS._id and ACH_DATA.organism = ACH_ORGANISMS._id and ACH_DATA.source = ACH_SOURCES._id and ACH_SOURCES._id = $source" ;

 my $rows  = $self->dbh->selectall_arrayref($statement);
 return $rows
}


#
# org2... section
#

sub org2md5{
  my ($self, $org , $regexp) = @_;
  $org =~s/'/\\'/gc;
  my $statement = "select ACH_DATA.md5 , ACH_ORGANISMS.name  from ACH_DATA , ACH_ORGANISMS where ACH_ORGANISMS.name = '$org' and ACH_ORGANISMS._id = ACH_DATA.organism group by ACH_DATA.md5";

  if ($regexp){
    $org =~s/\|/\\\\\|/gc;
     $statement = "select ACH_DATA.md5 , ACH_ORGANISMS.name  from ACH_DATA , ACH_ORGANISMS where ACH_ORGANISMS.name regexp '$org' and ACH_ORGANISMS._id = ACH_DATA.organism group by ACH_DATA.md5 , ACH_ORGANISMS.name";
  }

 my $rows  = $self->dbh->selectall_arrayref($statement);
 return $rows;
}
sub org2id{
 my ($self, $org , $regexp) = @_;

  $org =~s/'/\\'/gc;
  my $statement = "select ACH_DATA.id , ACH_ORGANISMS.name  from ACH_DATA , ACH_ORGANISMS where ACH_ORGANISMS.name = '$org' and ACH_ORGANISMS._id = ACH_DATA.organism";
 
 if ($regexp){
   $org =~s/\|/\\\\\|/gc;
   $statement = "select ACH_DATA.id , ACH_ORGANISMS.name  from ACH_DATA , ACH_ORGANISMS where ACH_ORGANISMS.name regexp '$org' and ACH_ORGANISMS._id = ACH_DATA.organism";
 }
# print STDERR $statement , "\n";
 my $rows  = $self->dbh->selectall_arrayref($statement);
 return $rows;
}

sub org2function{
 my ($self, $org , $regexp) = @_;

  $org =~s/'/\\'/gc;
  my $statement = "select ACH_FUNCTIONS.function , ACH_ORGANISMS.name  from ACH_DATA , ACH_FUNCTIONS , ACH_ORGANISMS where ACH_ORGANISMS.name = '$org' 
and ACH_ORGANISMS._id = ACH_DATA.organism and ACH_DATA.function = ACH_FUNCTIONS._id group by ACH_FUNCTIONS.function";

  if ($regexp){
    my $orgs = $self->organism($org , $regexp);
    my @functions ;
    
    foreach my $org (@$orgs){
  
      my $funcs = $self->org2function($org);
      push @functions , @$funcs;
    }
    
    return \@functions;
  }
 else{
   my $rows  = $self->dbh->selectall_arrayref($statement);
   return $rows;
 }
}

sub organism{
  my ($self , $org , $regexp) = @_;
 
  $org =~ s/'/\\'/gc;
  my $statement = "select ACH_ORGANISMS.name from ACH_ORGANISMS  where ACH_ORGANISMS.name = '$org' " ;
 
  if ($regexp){
    $org =~s/\|/\\\\\|/gc;
    $statement = "select ACH_ORGANISMS.name  from ACH_ORGANISMS  where ACH_ORGANISMS.name regexp '$org'  ";
  }

   my $rows  = $self->dbh->selectcol_arrayref($statement);
 
   return $rows
}


#
# function2... section
#

sub function2md5{
  my ($self , $func , $regexp) = @_;
 
  $func =~ s/'/\\'/gc;
  my $statement = "select ACH_FUNCTIONS.function , ACH_DATA.md5 from ACH_FUNCTIONS , ACH_DATA where ACH_FUNCTIONS.function = '$func' and ACH_DATA.function = ACH_FUNCTIONS._id" ;
 
  if ($regexp){
    $func =~s/\|/\\\\\|/gc;
    $statement = "select ACH_FUNCTIONS.function , ACH_DATA.md5 from ACH_FUNCTIONS , ACH_DATA where ACH_FUNCTIONS.function regexp '$func' and ACH_DATA.function = ACH_FUNCTIONS._id";
  }

 my $rows  = $self->dbh->selectall_arrayref($statement);
 
 return $rows
}

sub function2id{
   my ($self, $func , $regexp) = @_;
   my $statement = "select  ACH_DATA.id , ACH_FUNCTIONS.function from ACH_DATA , ACH_FUNCTIONS where ACH_FUNCTIONS.function = '$func' and ACH_FUNCTIONS._id = ACH_DATA.function";
   if ($regexp){
     $func =~s/'/\\'/gc;
     $func =~s/\|/\\\\\|/gc;
     $statement = "select  ACH_DATA.id , ACH_FUNCTIONS.function from ACH_DATA , ACH_FUNCTIONS where ACH_FUNCTIONS.function regexp '$func' and ACH_FUNCTIONS._id = ACH_DATA.function";
   }
   my $rows  = $self->dbh->selectall_arrayref($statement);
   return $rows;
}

sub function2org{
  my ($self, $func , $regexp) = @_;
  
  $func =~s/'/\\'/gc;
  my $statement = "select ACH_ORGANISMS.name ,  ACH_FUNCTIONS.function   from ACH_DATA , ACH_FUNCTIONS , ACH_ORGANISMS where ACH_FUNCTIONS.name = '$func' 
and ACH_ORGANISMS._id = ACH_DATA.organism and ACH_DATA.function = ACH_FUNCTIONS._id group by ACH_ORGANISMS.name";
  
   if ($regexp){
     my $functions = $self->function($func , $regexp);
     my @rows ;
    
    foreach my $f (@$functions){
  
      my $funcs = $self->function2org($f);
      push @rows , @$funcs;
    }
    
    return \@rows;
   }
  
  my $rows  = $self->dbh->selectall_arrayref($statement);
  return $rows;
}

sub function{
   my ($self , $func , $regexp) = @_;
 
  $func =~ s/'/\\'/gc;
  my $statement = "select ACH_FUNCTIONS.function  ACH_FUNCTIONS  where ACH_FUNCTIONS.function = '$func' " ;
 
  if ($regexp){
    $func =~s/\|/\\\\\|/gc;
    $statement = "select ACH_FUNCTIONS.function  ACH_FUNCTIONS  where ACH_FUNCTIONS.function regexp '$func' ";
  }

   my $rows  = $self->dbh->selectcol_arrayref($statement);
 
   return $rows
}

# id2... Section

sub id2org{
  my ($self, $id , $regexp) = @_;
  my $statement = "select ACH_ORGANISMS.name , ACH_DATA.id from ACH_DATA , ACH_ORGANISMS where ACH_DATA.id = '$id' and ACH_ORGANISMS._id = ACH_DATA.organism";
  if ($regexp){
    $id =~s/'/\\'/gc;
    $id =~s/\|/\\\\\|/gc;
    $statement = "select ACH_ORGANISMS.name , ACH_DATA.id from ACH_DATA , ACH_ORGANISMS where ACH_DATA.id regexp '$id' and ACH_ORGANISMS._id = ACH_DATA.organism";
  }
  my $rows  = $self->dbh->selectall_arrayref($statement);
  return $rows;
}



sub id2md5{
 my ($self , $id , $regexp) = @_;
 
 $id =~ s/'/\\'/gc;
 my $statement = "select md5 , ID from ACH_DATA where ID='$id'" ;
 
 if ($regexp){
   $id =~s/\|/\\\\\|/gc;
   $statement = "select md5 , ID from ACH_DATA where ID regexp '$id'";
 }

 my $rows  = $self->dbh->selectall_arrayref($statement);
 
 return $rows
}

sub ids2md5s{
 my ($self , $ids) = @_;
 
 my $list = "(";
 while  (my $id = pop @$ids){
   $id =~ s/'/\\'/gc;
   $list .= "'$id'";
   $list .= " , " if (scalar @$ids);
 }
 $list .= ")";
 my $statement = "select md5 , ID from ACH_DATA where ID in $list" ;
 # print STDERR$statement ,"\n";
 my $rows  = $self->dbh->selectall_arrayref($statement);
 
 return $rows
}

sub id2org{
  my ($self, $id , $regexp) = @_;
  my $statement = "select ACH_ORGANISMS.name , ACH_DATA.id from ACH_DATA , ACH_ORGANISMS where ACH_DATA.id = '$id' and ACH_ORGANISMS._id = ACH_DATA.organism";
  if ($regexp){
    $id =~s/'/\\'/gc;
    $id =~s/\|/\\\\\|/gc;
    $statement = "select ACH_ORGANISMS.name , ACH_DATA.id from ACH_DATA , ACH_ORGANISMS where ACH_DATA.id regexp '$id' and ACH_ORGANISMS._id = ACH_DATA.organism";
  }
  my $rows  = $self->dbh->selectall_arrayref($statement);
  return $rows;
}

sub id2function{
  my ($self, $id , $regexp) = @_;
  my $statement = "select ACH_FUNCTIONS.function , ACH_DATA.id from ACH_DATA , ACH_FUNCTIONS where ACH_DATA.id = '$id' and ACH_FUNCTIONS._id = ACH_DATA.function";
  if ($regexp){
    $id =~s/'/\\'/gc;
    $id =~s/\|/\\\\\|/gc;
    $statement = "select ACH_FUNCTIONS.function , ACH_DATA.id from ACH_DATA , ACH_FUNCTIONS where ACH_DATA.id regexp '$id' and ACH_FUNCTIONS._id = ACH_DATA.function";
  }
  my $rows  = $self->dbh->selectall_arrayref($statement);
  return $rows;

}

sub id {
  my ($self, $id , $regexp) = @_;
  my $statement = "select ID from ACH_DATA where ID='$id'" ;
  
  if ($regexp){
    $id =~s/\|/\\\\\|/gc;
    $statement = "select  ID from ACH_DATA where ID regexp '$id'";
  }
  
  return  $self->dbh->selectcol_arrayref($statement);
}

sub id2set{
  my ($self, $id , $regexp) = @_;
  my $ids = $self->id($id , $regexp);
  my @sets;

  foreach my $i (@$ids){
    my $md5 = $self->id2md5($id);
    foreach my $m (@$md5){
      push @sets , @{ $self->md52set($m->[0]) };
    }
  }
  return \@sets ;
}

sub ids2sets{
  my ($self, $ids) = @_;
  
  my $md5s = $self->ids2md5s($ids);
  my %md5list;
  map { $md5list{ $_->[0] }++ } @$md5s;
  #my $hash = map { $_->[0] => $_->[1] } @$md5s ;
  my @list = keys %md5list;
  return $self->md5s2sets(\@list) ;
}


sub id2id4source{
  my ($self, $id , $source , $regexp) = @_;
  
  unless ($source =~/^\d+$/){
    my $statement = "select _id from ACH_SOURCES where name='$source'" ;
    my $resp = $self->dbh->selectcol_arrayref($statement);
    $source = $resp->[0];
  }
  my $ids = $self->id($id , $regexp);
  my @sets;

  foreach my $i (@$ids){
    my $md5 = $self->id2md5($id);
    foreach my $m (@$md5){
      push @sets , @{ $self->md52id4source($m->[0] , $source) };
    }
  }
  return \@sets ;
}

#
# SOURCE part
#


sub sources{
 my ($self , $source , $regexp) = @_;
 
 my $statement = "select name from ACH_SOURCES group by name" ;
 # print STDERR$statement ,"\n";
 my $rows  = $self->dbh->selectcol_arrayref($statement);
 
 return $rows
}


1;
