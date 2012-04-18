#!/usr/bin/env perl
use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;

sub usage {
  print "assign_subsystems_from_user_to_group.pl >>> grant all subsystem rights of a user to a group\n";
  print "assign_subsystems_from_user_to_group.pl -login <login> -group <group>\n";
}

# read in parameters
my $login       = '';
my $group = '';

GetOptions ( 'login=s' => \$login,
	     'group=s' => \$group );

unless ($login and $group) {
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

# get the user from the db
my $user = $dbmaster->User->get_objects( { 'login' => $login } );
if (scalar(@$user)) {
  $user = $user->[0];
} else {
  print "Could not get user $login from the database\n";
  exit 0;
}

# check if there is an Admin scope, otherwise create it
my $scope = $dbmaster->Scope->get_objects( { 'name' => $group } );
if (scalar(@$scope)) {
  $scope = $scope->[0];
} else {
  print "Could not find group $group.\n";
  exit 0;
}

# get all subsystem rights of this user
my $rights = $dbmaster->Rights->get_objects( { data_type => 'subsystem', scope => $user->get_user_scope } );
if (scalar(@$rights)) {
  my $num_ss = 0;

  foreach my $right (@$rights) {
    # check if the group does not yet have the right
    my $existing = $dbmaster->Rights->get_objects( { 'scope' => $scope,
						     'data_type' => 'subsystem',
						     'name' => $right->name(),
						     'data_id' => $right->data_id() } );
    if (scalar(@$existing)) {
      $existing->[0]->granted(1);
    } else {
      $dbmaster->Rights->create( { 'scope' => $scope,
				   'data_type' => 'subsystem',
				   'name' => $right->name(),
				   'data_id' => $right->data_id(),
				   'granted' => 1,
				   'delegated' => 1 } );
    }
    print "right for subsystem ".$right->data_id()." granted.\n";
    $num_ss++;
  }
  
  print "Access for $num_ss subsystems owned by $login granted to $group\n";

} else {
  print "No subsystem rights found for $login\n";
  exit 0;
}
