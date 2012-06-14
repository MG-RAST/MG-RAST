package OntologyOnDemand::Category;

use strict;
use warnings;

sub create_ID{
  my ( $self ) = @_;

  my $statement;

  # get database handle
  my $dbh = $self->_master->db_handle;
  

  $statement = "select Category.ID from Category group by ID";


  my $sth = $dbh->prepare($statement);
  my $rv = $sth->execute;
  my $prefix = "CMG";
  my $version = "0";

  while ( my @row = $sth->fetchrow_array ) {
      my ($tmp) = $row[0] =~ /$prefix(\d+)/;
      $version = $tmp if ($tmp > $version);
  }
  
  print STDERR "Version is $version\n";
  $version++;

  return $prefix.$version;
}

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

