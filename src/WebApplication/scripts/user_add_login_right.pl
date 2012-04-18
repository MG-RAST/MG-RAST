#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "user_add_login_right.pl >>> add login right to an application to a user\n";
  print "user_add.pl -application <appl_name> -login <login> [-grant]\n";
}

# get command line parameters
my %options = ();
GetOptions (\%options, 
	    "application=s",
	    "login=s",
	    "grant",
	   ); 


unless ($options{application} and $options{login}) {
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


print "Adding login right to application ".$options{application}.
  " to user ".$options{login}.".\n";

# sanity checks
my $user = $dbmaster->User->init({ login => $options{login} });
unless ($user) {
  print "Unable to find a user with login ".$options{login}.", aborting.\n";
  exit 0;
}

my $app = $dbmaster->Backend->init({ name => $options{application} });
unless ($app) {
  print "Unable to find a backend for application ".$options{application}.", aborting.\n";
  exit 0;
}


# add (and grant) login right
$user->add_login_right($app);

if ($options{grant}) {
  print "Granting login right.\n";
  $user->grant_login_right($app);
}

print "Done.\n";
