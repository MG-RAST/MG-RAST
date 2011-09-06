#!/usr/bin/env perl

use strict;
use warnings; 

use PPOBackend;

# usage message 
sub usage {
  my $error = shift;
  print "Usage: ppo_sqlite_copy.pl source_database target_database\n";
  print "Error: $error\n" if($error);
  exit;
}

my $source = $ARGV[0] | '';
-f $source || &usage("Unable to find database source '$source'.");
my $target = $ARGV[1] || &usage('No new database name given');
!-f $target || &usage("Target file already exists.");
my $connect = "DBI:SQLite:dbname=$target";

system("cp", $source, $target) == 0
  || &usage("Unable to copy database from $source to $target.");


my $backend = PPOBackend->new(-backend => 'SQLite', -database => $source);

if (ref $backend) {
  $backend->update_row('_references', 
		       { '_database' => $target,
			 '_backend_data' => $connect }, 
		       '_database='.$backend->dbh->quote($source))
    || die "Failed to update database.";
}
else {
  &usage("Unable to open database '$source'.");
}

$backend->dbh->disconnect;

exit 1;
