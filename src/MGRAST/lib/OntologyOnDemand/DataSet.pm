package OntologyOnDemand::DataSet;

use strict;
use warnings;

sub create_ID{
  my ( $self ) = @_;

  my $statement;

  # get database handle
  my $dbh = $self->_master->db_handle;
  

  $statement = "select DataSet.ID from DataSet group by ID desc limit 1";


  my $sth = $dbh->prepare($statement);
  my $rv = $sth->execute;
  my $prefix = "DSMG";
  my $version = "0";

  while ( my @row = $sth->fetchrow_array ) {
    ($version) = $row[0] =~ /$prefix(\d+)/;
  }
  
  $version++;

  return $prefix.$version;
}

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

