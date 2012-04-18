#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "batch_create_user_group.pl >>> create a list of users, grant them login right to an application and add them to a group\n";
  print "batch_create_user_group.pl -users <path to user list> -application <appl_name> -group <group name>\n";
}

my $users = "";
my $application = "";
my $group = "";

# get command line parameters
GetOptions ( "users=s" => \$users,
	     "application=s" => \$application,
	     "group=s" => \$group,
	   ); 


unless ($application and $users and $group) {
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

# get the group
my $group_object = $dbmaster->Scope->get_objects( { name => $group } );
if (scalar(@$group_object)) {
  $group_object = $group_object->[0];
} else {
  print "could not initialize group $group.\n";
  exit 0;
}

# get the application
my $application_object = $dbmaster->Backend->init({ name => $application });
unless ($application_object) {
  print "could not initialize application $application.\n";
  exit 0;
}

# get the list of users
if (open(FH, "<$users")) {
  my $i = 1;
  while (<FH>) {
    chomp;
    my ($firstname, $lastname, $login, $email) = split /\t/;
    if ($firstname && $lastname && $login && $email) {
      # sanity checks
      my $user;
      if ($user = $dbmaster->User->init({ email => $email })) {
	print "This email has already been registered for ".$user->login.", skipping.\n";
      } elsif ($user = $dbmaster->User->init({ login => $login })) {
	print "This login has already been registered for ".$user->firstname." ".$user->lastname.", skipping.\n";
      } else {
	# create the user in the db
	$user = $dbmaster->User->create( { email        => $email,
					   firstname    => $firstname,
					   lastname     => $lastname,
					   login        => $login,
					   active       => 1,
					   
					 } );
	# add and grant login right to the user
	$user->add_login_right($application_object);
	$user->grant_login_right($application_object);

	# add the user to the group
	$dbmaster->UserHasScope->create( { user => $user,
					   scope => $group_object,
					   granted => 1 } );
    } else {
      print "invalid format in user file line $i : $_\n";
    }
    $i++;
  }
  close FH;
} else {
  print "could not open user file: $! $@\n";
  exit 0;
}

print "done.\n";
