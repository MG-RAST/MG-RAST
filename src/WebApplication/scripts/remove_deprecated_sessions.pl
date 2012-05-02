#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "remove_deprecated_sessions.pl >>> removes all deprecated sessions from the web application database\n";
  print "remove_deprecated_sessions.pl -execute 1 \n";
}

my $execute;

GetOptions ( 'execute=s' => \$execute );


unless ($execute) {
  &usage();
  exit 0;
}


# initialize db-master
my ($dbmaster, $error) = WebApplicationDBHandle->new();

# check if we got a dbmaster
if ($error) {
  print $error."\n";
  exit 0;
}

print "Deleting sessions...\n";

my $age = 172800; # two days in seconds

my $dbh = $dbmaster->db_handle;
my $time = time - ($age);
my $statement = "DELETE FROM UserSession WHERE timestamp < FROM_UNIXTIME($time) AND user IS NULL";
eval {
  
  $dbh->do($statement);
  $dbh->commit;
  
};

if ($@) {
  eval { $dbh->rollback };
  if ($@) {
    Confess("Rollback failed: $@");
  }
} else {

  print "Done.\n";

}
