#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;

sub usage {
  print "user_set_password.pl >>> set a user password in the web application database\n";
  print "user_set_password.pl -login <login> -password <password>\n";
}

# read in parameters
my $login       = '';
my $password    = '';

GetOptions ( 'login=s' => \$login,
	     'password=s' => \$password,
	   );


unless ($login and $password) {
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

# get user
my $user = $dbmaster->User->init( { 'login' => $login } );
unless (ref $user) {
  print "User $login not found in database, aborting.\n";
  exit 0;
}

# set password
if ($user->set_password($password)) {
  print "password set.\n";
  exit 1;
} else {
  print "could not set password.\n";
  exit 0;
}
