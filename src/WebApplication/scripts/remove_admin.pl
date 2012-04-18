#!/usr/bin/env perl
use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;

sub usage {
  print "remove_admin.pl >>> turn an existing user into an administrator\n";
  print "remove_admin.pl -login <login> -application <application> [-db <database>]\n";
}

# read in parameters
my $login       = '';
my $application = '';
my $db = 'WebAppBackend';

GetOptions ( 'login=s' => \$login,
	     'application=s' => \$application,
	     'db=s' => \$db );

unless ($login and $application) {
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

my $backend = $dbmaster->Backend->init( { 'name' => $application } );

# get the user from the db
my $user = $dbmaster->User->init( { 'login' => $login } );
unless (ref($user)) {
  print "Could not get user $login from the database\n";
  exit 0;
}

# check if there is an Admin scope, otherwise create it
my $scope = $dbmaster->Scope->init( { 'application' => $backend,
				      'name' => 'Admin' } );
unless (ref($scope)) {
  print "Admin scope does not exist for application $application, run 'update_admin_scope.pl' first.\n";
  exit 0;
}

my $admin_right = $dbmaster->UserHasScope->get_objects( { 'scope' => $scope, 'user' => $user } );
unless (scalar(@$admin_right)) {
  print $user->firstname." ".$user->lastname." (".$user->login.") is not an admin of the application $application";
  exit 0;
}

$admin_right->[0]->delete;

print $user->firstname." ".$user->lastname." (".$user->login.") is no longer admin for application $application\n";
