#!/usr/bin/env perl
use strict;
use warnings;

use lib('../../WebApplication');
use lib('../../PPO');

use WebApplicationDBHandle;

use Getopt::Long;

sub usage {
  print "update_admin_scope.pl >>> update the rights of the administrator scope\n";
  print "update_admin_scope.pl -application <application> [-db <database>]\n";
}

# read in parameters
my $application = '';
my $db = "WebAppBackend";

GetOptions ( 'application=s' => \$application, 'db=s' => \$db );

unless ($application) {
  &usage();
  exit 0;
}

unshift(@INC, "../../$application");

# initialize db-master
my ($dbmaster, $error) = WebApplicationDBHandle->new();

# check if we got a dbmaster
if ($error) {
  print $error."\n";
  exit 0;
}
my $backend = $dbmaster->Backend->init( { 'name' => $application } );

unless (ref($backend)) {
  print "Could not retrieve backend $application from database\n";
  exit 0;
}

# check if there is an Admin scope, otherwise create it
my $scope = $dbmaster->Scope->init( { 'application' => $backend,
				      'name' => 'Admin' } );
unless (ref($scope)) {
  $scope = $dbmaster->Scope->create( { 'application' => $backend,
				       'name' => 'Admin',
				       'description' => 'automatically created admin scope' } );
}

require MyAppRights;
my $rights = eval("$application\::MyAppRights::rights()");
foreach my $right (@$rights) {

  # check if the right already exists
  unless (scalar(@{$dbmaster->Rights->get_objects( { 'application' => $backend,
						     'data_type' => $right->[1],
						     'data_id' => $right->[2],
						     'scope' => $scope,
						     'name' => $right->[0] } )})) {
    print "adding right " . join(',', @$right) . "\n";

    # create rights for the admin scope
    $dbmaster->Rights->create( { 'granted' => 1,
				 'application' => $backend,
				 'data_type' => $right->[1],
				 'data_id' => $right->[2],
				 'scope' => $scope,
				 'name' => $right->[0] } );
    
  }
}

print "Admin scope updated for application $application\n";
