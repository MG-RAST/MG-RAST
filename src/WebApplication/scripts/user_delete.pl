#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "user_delete.pl >>> delete a user to the web application database\n";
  print "user_delete.pl -login <login> \n";
  print "*** THIS CANNOT BE UNDONE ***\n";
}

# read in parameters
my $login      = '';

GetOptions ( 'login=s' => \$login,
	   );


unless ($login) {
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


# get the user
my $user;
if ($user = $dbmaster->User->init({ login => $login })) {
    print "Deleting user ".($user->firstname||'[no firstname]')." ".($user->lastname||'[no lastname]')." ($login).\n";
    $user->delete();
    print "Done.\n";
}
else {
    print "Unable to find user with login $login.\n";
    print "Bye.\n";
}
