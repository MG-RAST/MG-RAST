#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "application_add_login_right_to_all.pl >>> add login right to an application to all users that have at least one granted login right\n";
  print "application_add_login_right_to_all.pl -application <appl_name>\n";
}

# get command line parameters
my %options = ();
GetOptions (\%options, 
	    "application=s",
	   ); 


unless ($options{application}) {
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

my $app = $dbmaster->Backend->init({ name => $options{application} });
unless ($app) {
  print "Unable to find a backend for application ".$options{application}.", aborting.\n";
  exit 0;
}

# get all users
my $users = $dbmaster->User->get_objects();

# get the users that have at least one granted login right
foreach my $user (@$users) {
  my $login_rights = $dbmaster->Rights->get_objects( { name => 'login',
						       granted => 1,
						       scope => $user->get_user_scope } );
  if (scalar(@$login_rights)) {

    # add and grant login right
    $user->add_login_right($app);
    $user->grant_login_right($app);
    
    print "Login right to ".$options{application}." granted to ".$user->firstname." ".$user->lastname."\n";
  }
}


print "Done.\n";
