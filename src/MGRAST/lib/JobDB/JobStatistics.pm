package JobDB::JobStatistics;

use strict;
use warnings;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

sub stats_for_tag {
  my ($self, $tag, $jobs, $is_mgid) = @_;
  
  my $dbh = $self->_master->db_handle;
  my $sql = "SELECT MIN(value + 0), MAX(value + 0), AVG(value + 0), STDDEV(value + 0) FROM JobStatistics WHERE tag = ".$dbh->quote($tag);
  if ($jobs && (@$jobs > 0)) {
    my $id = $is_mgid ? 'metagenome_id' : 'job_id';
    $sql .= " AND job IN (SELECT _id from Job WHERE $id IN (".join(",", map {$dbh->quote($_)} @$jobs)."))";
  }
  my $stats = $dbh->selectrow_arrayref($sql);
  if ($stats && (@$stats == 4)) {
    return $stats;
  } else {
    return [];
  }
  # [ min, max, avg, stdv ]
}
