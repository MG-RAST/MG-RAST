#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;

sub usage {
  print "org_count.pl >>> counts the number of organizations for a list of users\n";
  print "org_count.pl -input <input_file>\n";
}

# read in parameters
my $input       = '';

GetOptions ( 'input=s' => \$input );


unless ($input) {
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

# open the user file
my @users;
open(FH, $input) or die "Could not open user file $input";
while (<FH>) {
  chomp;
  push(@users, $_);
}
close FH;

my $organizations = {};

foreach my $login (@users) {
  # get user
  my $user = $dbmaster->User->init( { 'login' => $login } );
  unless (ref $user) {
    print "User $login not found in database.\n";
  }
  my $uos = $dbmaster->OrganizationUsers->get_objects( { user => $user } );
  foreach my $uo (@$uos) {
    if (exists($organizations->{$uo->organization->name})) {
      $organizations->{$uo->organization->name} ++;
    } else {
      $organizations->{$uo->organization->name} = 1;
    }
  }
}

print "Oranization\tNo. Members\n";
foreach my $key (keys(%$organizations)) {
  print $key."\t".$organizations->{$key}."\n";
}

exit 1;
