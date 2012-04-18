#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use FIG;

use Getopt::Long;

sub usage {
  print "grant_user_genome_rights_to_group.pl >>> grants the rights to access genomes a user has to a group\n";
  print "grant_user_genome_rights_to_group.pl -login <login> -group <group name> [ -edit <edit> ]\n";
}

# read in parameters
my $group_name = '';
my $login = '';
my $edit = '';
my $ingroup = '';

GetOptions ( 'group=s' => \$group_name,
	     'login=s' => \$login,
	     'edit=s' => \$edit,
	     'ingroup=s' => \$ingroup,
	   );


unless ($group_name and ($login or $ingroup)) {
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

my $userscope;
if ($ingroup) {
  $userscope = $dbmaster->Scope->init( { 'name' => $ingroup,
					 'application' => undef } );
  unless (ref($userscope)) {
    print "Group $ingroup not found in database, aborting.\n";
    exit 0;
  }
} else {

  # get user
  my $user = $dbmaster->User->init( { 'login' => $login } );
  unless (ref $user) {
    print "User $login not found in database, aborting.\n";
    exit 0;
  }
  $userscope = $user->get_user_scope();
}

# get group
my $group = $dbmaster->Scope->init( { 'name' => $group_name,
				      'application' => undef } );
unless (ref($group)) {
  print "Group $group_name not found in database, aborting.\n";
  exit 0;
}

# get view genome rights of that user
my $rights = $dbmaster->Rights->get_objects( { name => 'view',
					       data_type => 'genome',
					       scope => $userscope } );

unless (scalar(@$rights)) {
  print "No genome rights found for user, aborting.\n";
  exit 0;
}

foreach my $right (@$rights) {
  # check if the group already has the right
  my $existing = $dbmaster->Rights->get_objects( { name => 'view',
						   data_type => 'genome',
						   data_id => $right->data_id(),
						   scope => $group,
						   granted => 1 } );

  if (scalar(@$existing)) {
    print "Right for ".$right->data_id()." already exists, skipping.\n";
  } else {
    
    my $created = $dbmaster->Rights->create( { name => 'view',
					       data_type => 'genome',
					       data_id => $right->data_id(),
					       scope => $group,
					       granted => 1,
					       delegated => 1 } );
    if ($created) {
      print "right for ".$group->name()." to genome ".$right->data_id()." created.\n";
    } else {
      print "creation of right for ".$group->name()." to genome ".$right->data_id()." failed.\n";
    }
  }
}

if ($edit) {
  $rights = $dbmaster->Rights->get_objects( { name => 'edit',
					      data_type => 'genome',
					      scope => $userscope } );
  foreach my $right (@$rights) {
    # check if the group already has the right
    my $existing = $dbmaster->Rights->get_objects( { name => 'edit',
						     data_type => 'genome',
						     data_id => $right->data_id(),
						     scope => $group,
						     granted => 1 } );
    
    if (scalar(@$existing)) {
      print "Right for ".$right->data_id()." already exists, skipping.\n";
    } else {
      
      my $created = $dbmaster->Rights->create( { name => 'edit',
						 data_type => 'genome',
						 data_id => $right->data_id(),
						 scope => $group,
						 granted => 1,
						 delegated => 1 } );
      if ($created) {
	print "edit right for ".$group->name()." to genome ".$right->data_id()." created.\n";
      } else {
	print "creation of right for ".$group->name()." to genome ".$right->data_id()." failed.\n";
      }
    }
  }
}

print "done.\n";
