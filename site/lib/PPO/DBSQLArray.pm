package DBSQLArray;

# DBSQLArray - ties persistent perl object arrays to the database backend

# $Id: DBSQLArray.pm,v 1.7 2008-04-10 14:42:56 paarmann Exp $

use strict;
use warnings;

use base qw( Tie::Array );

use DBObject qw( DB_ARRAY_OF_SCALARS DB_ARRAY_OF_OBJECTS );

1;

=pod

=head1 NAME

DBSQLArray - ties persistent perl object arrays to the database backend

=head1 DESCRIPTION

This module provides methods for tying array attributes of DBObjects to the 
database backend. It supplies all required methods to tie an array to a package
based on the Tie::Array package.

Even though named DB/SQL/Array it will make use of the database methods provided
by the backend of the DBMaster and thus be portable to other database implementations.

It provides DELETE and EXISTS methods, and implementations of PUSH, POP, SHIFT, 
UNSHIFT, SPLICE and CLEAR in terms of basic FETCH, STORE, FETCHSIZE, STORESIZE.

=head1 METHODS

=over 4

=item * B<TIEARRAY> I<parent_object>, I<attribute_key>

This method is invoked by the command tie @array, DBSQLArray, I<parent_object>, 
I<attribute_key> and associates an array attribute with it's database backend.

=cut

sub TIEARRAY {
  my ($class, $parent, $key) = @_;
  
  my $self = { '_parent' => $parent,
	       '_attribute' => $key,
	       '_array' => [],
	     };
  bless $self, $class;

  my $id = $parent->_id;

  # load array from database if applicable
  if ($parent->attributes->{$key}->[0] == DB_ARRAY_OF_SCALARS) {
    
    # get array content
    my $data = $self->backend->get_rows( $self->table, [ '_value' ], "_source_id=$id", 
					 { 'sort_by' => [ '_array_index' ] } );
    foreach (@$data) {
      push(@{$self->{'_array'}}, $_->[0]);
    }
	
  }
  elsif ($parent->attributes->{$key}->[0] == DB_ARRAY_OF_OBJECTS) {

    # get object array class
    my ($refclass) = ($parent->attributes->{$key}->[1] =~ /\w+::(\w+)/);
    
    # get array content
    my $data = $self->backend->get_rows( $self->table, [ '_target_db', '_target_id' ], "_source_id=$id", 
					 { 'sort_by' => [ '_array_index' ] } );
    foreach (@$data) {
      push(@{$self->{'_array'}}, [ $_->[0], $refclass, $_->[1] ]);
    }

  }
  else {
    die "Unknown attribute type '".$parent->attributes->{$key}->[0]."'.";
  }

  return $self;
}

=pod

=item * B<FETCH> I<this>, I<index>

Retrieve the datum in I<index> for the tied array associated with object I<this>.

=cut

sub FETCH {
  my ($self, $index) = @_;

  # in the case of object arrays check if object has to be retrieved first
  if ($self->type == DB_ARRAY_OF_OBJECTS and 
      ref($self->{'_array'}->[$index]) ne $self->ref_type) {

    # fetch object and store it in the array
    my $object = $self->{'_parent'}->_master->fetch_by_ref( @{$self->{'_array'}->[$index]} );
    unless (ref $object) {
      $self->SPLICE($index,1);
      warn "Invalid object reference in array: ".join(', ',@{$self->{'_array'}->[$index]}).
	", deleted entry _source_id=".$self->{'_parent'}->_id." and _array_index=$index.";
    }
    
    $self->{'_array'}->[$index] = $object;
    
  }	

  return $self->{'_array'}->[$index];

}

=pod

=item * B<STORE> I<this>, I<index>, I<value>

Store datum I<value> into I<index> for the tied array associated with object I<this>.
If this makes the array larger then class's mapping of undef should be returned for 
new positions. Storing a value in the array automatically updates the corresponding 
entries in the database.

=cut

sub STORE {
  my( $self, $index, $value ) = @_;

  my $parent = $self->{'_parent'};
  my $key = $self->{'_attribute'};
  my $id = $parent->_id;

  # delete entry ($value = undef)
  unless (defined $value) {
    $self->backend->delete_rows( $self->table, "_source_id=$id and _array_index=$index" );
    return undef;
  }

  # set entry - check value first 
  if ($self->type == DB_ARRAY_OF_OBJECTS and ref($value) ne $self->ref_type) {
    die "Mismatched object class at position $index for array attribute '$key': '".$value."'.";
  }
  elsif ($self->type == DB_ARRAY_OF_SCALARS and ref($value)) {
    die "Mismatched value at position $index for array attribute '$key': '$value'.";
  }

  # update existing entry?
  if (exists ($self->{'_array'}->[$index])) {

    # array of objects
    if ($self->type == DB_ARRAY_OF_OBJECTS) {
      
      my ($db_id, $obj_id) = $parent->_master->translate_ref_to_ids($value);

      $self->backend->update_row( $self->table, { '_target_db' => $db_id, '_target_id' => $obj_id }, 
				  "_source_id=$id and _array_index=$index" );

    }
 
    # array of scalars
    elsif ($self->type == DB_ARRAY_OF_SCALARS) {

      $self->backend->update_row( $self->table, { '_value' => $value }, 
				  "_source_id=$id and _array_index=$index" );      

    }

  }

  # new entry
  else {

    # array of objects
    if ($parent->attributes->{$key}->[0] == DB_ARRAY_OF_OBJECTS) {
      
      my ($db_id, $obj_id) = $parent->_master->translate_ref_to_ids($value);

      $self->backend->insert_row( $self->table, { '_array_index' => $index, '_source_id' => $id,     
						  '_target_id' => $obj_id,  '_target_db' => $db_id, } );

    }
    # array of scalars
    elsif ($parent->attributes->{$key}->[0] == DB_ARRAY_OF_SCALARS) {

      $self->backend->insert_row( $self->table, { '_array_index' => $index, 
						  '_source_id' => $id, 
						  '_value' => $value,  
						});
    }
  }  

  $self->{'_array'}->[$index] = $value;
  
}

=pod

=item * B<FETCHSIZE> I<this>

Returns the total number of items in the tied array associated with object I<this>.
(Equivalent to scalar(@array)).

=cut

sub FETCHSIZE {
  return scalar @{$_[0]->{'_array'}};
}

=pod

=item * B<STORESIZE> I<this>, I<count>

Sets the total number of items in the tied array associated with object I<this> to be
I<count>. If this makes the array larger then class's mapping of undef should be returned
for new positions. If the array becomes smaller then entries beyond I<count> are removed
and their rows delete from the database table.

=cut

sub STORESIZE {
  my ($self, $size) = @_;

  # is the array becoming smaller?
  if ($size < $self->FETCHSIZE) {

    # delete from array
    foreach ( 1 .. $self->FETCHSIZE() - $size  ) {
      pop @{$self->{'_array'}};
    }

    # delete from database 
    my $id = $self->{'_parent'}->_id;
    $self->backend->delete_rows( $self->table, "_source_id=$id and _array_index>=$size" );

  }
}	    

=pod

=item * B<EXISTS> I<this>, I<key>

Return true if the element at index I<key> exists in the tied array I<this>.

=cut

sub EXISTS {
  my ($self, $index) = @_;
  return exists $self->{'_array'}->[$index];
}

=pod

=item * B<DELETE> I<this>, I<key>

Delete the element at index I<key> exists in the tied array I<this>.
This method will delete the corresponding row from the database table.

=cut

sub DELETE {
  my ($self, $index) = @_;
  return $self->STORE( $index, undef );
}

=pod

=item * B<CLEAR> I<this>

Clear (remove, delete, ...) all values from the tied array I<this>.
This method will delete all entries from the array database table.

=cut

sub CLEAR {

  $_[0]->backend->delete_rows( $_[0]->table, '_source_id='.$_[0]->{'_parent'}->_id );
  @{$_[0]->{_array}} = ();

}

=pod 

=item * B<backend> 

Helper method to get the backend from the DBMaster stored in the parent object

=cut

sub backend {
  return $_[0]->{'_parent'}->_master->backend;
}

=pod 

=item * B<database> 

Helper method to get the name of the database from the DBMaster stored in the parent object

=cut

sub database {
  return $_[0]->{'_parent'}->_master->database;
}

=pod 

=item * B<table> 

Helper method to get the name of the array table from the parent object

=cut

sub table {
  return $_[0]->{'_parent'}->_table().'_'.$_[0]->{'_attribute'};
}


=pod 

=item * B<type> 

Helper method to get the type of the array attribute from the parent object

=cut

sub type {
  return $_[0]->{'_parent'}->attributes->{ $_[0]->{'_attribute'} }->[0];
}


=pod 

=item * B<ref_type> 

Helper method to get the perl package name of the array attribute from the parent object

=cut

sub ref_type {
  return $_[0]->{'_parent'}->attributes->{ $_[0]->{'_attribute'} }->[1];
}
