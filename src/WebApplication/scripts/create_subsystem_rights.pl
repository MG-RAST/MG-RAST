#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use FIG;

use Getopt::Long;

sub usage {
  print "create_subsystem_rights.pl >>> grants the rights to access subsystems in the Subsystem Editor to the user specified by login to all subsystems of the SEED username slogin\n";
  print "user_set_password.pl -login <login> -slogin <seed login>\n";
}

# read in parameters
my $slogin       = '';
my $login    = '';

GetOptions ( 'slogin=s' => \$slogin,
	     'login=s' => \$login,
	   );


unless ($slogin and $login) {
  &usage;
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

my $fig = new FIG;

my @subsystems = $fig->all_subsystems();

foreach my $sname ( @subsystems ) {

   my ( $ssversion, $sscurator, $pedigree, $ssroles ) = $fig->subsystem_info( $sname );
   if ( $sscurator eq $slogin ) {

     my $rights = $dbmaster->Rights->get_objects( { name => 'edit',
						   scope => $user->get_user_scope,
						   data_type => 'subsystem',
						   data_id   => $sname } );

     unless ( scalar( @$rights ) ) {
       my $right = $dbmaster->Rights->create( { name => 'edit',
						scope => $user->get_user_scope,
						data_type => 'subsystem',
						data_id => $sname,
						granted => 1,
						delegated => 0 } );
       if ( ref( $right ) ) {
	 print "User ".$user->firstname()." ".$user->lastname() ." got right for editing $sname\n";
       }
     }
   }

}
