#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "test.pl >>> test\n";
  print "test.pl -key <k>\n";
}

# read in parameters
my $key  = '';

GetOptions ( 'key=s' => \$key );


unless ($key) {
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

my $user = WebApplicationDBHandle::authenticate_user($dbmaster, $key);
if ($user) {
  print "authenticated as ".$user->firstname . " " . $user->lastname . " (" . $user->login . ")\n";
} else {
  print "authentication with key $key failed.\n";
}
