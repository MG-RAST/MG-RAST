#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use FIG;

use Getopt::Long;

sub usage {
  print "set_user_preference.pl >>> set a user preference\n";
  print "user_set_password.pl -login <login> -application <application> -preference <preference> -value <value>\n";
}

# read in parameters
my $login    = '';
my $app = '';
my $preference = '';
my $value = '';

GetOptions ( 'application=s' => \$app,
	     'login=s' => \$login,
	     'preference=s' => \$preference,
	     'value=s' => \$value,
	   );


unless ($app and $login and $preference and $value) {
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

my $application = $dbmaster->Backend->init( { name => $app } );
unless ( ref( $application ) ) {
  print STDERR "Application $app not found ! \n";
  exit(0);
}

# get user
my $user = $dbmaster->User->init( { 'login' => $login } );
unless (ref $user) {
  print "User $login not found in database, aborting.\n";
  exit 0;
}

my $preferences = $dbmaster->Preferences->get_objects( { user => $user,
							 name => $preference,
						         application => $application } );

unless ( scalar( @$preferences ) ) {
  my $preferenceobj = $dbmaster->Preferences->create( { user => $user,
							name => $preference,
							value => $value,
							application => $application } );
  print STDERR "Preference set.\n";
}
else {
  if ( $preferences->[0]->value eq $value ) {
    print STDERR "The user already has this preference.\n";
  }
  else {
    $preferences->[0]->value( $value );
    print STDERR "Preference set from ".$preferences->[0]->value." to $value\n";
  }
}
