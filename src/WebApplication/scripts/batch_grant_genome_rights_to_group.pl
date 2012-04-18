#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use FIG;

use Getopt::Long;

sub usage {
  print "batch_grant_genome_rights_to_group.pl >>> grants the rights to access a list of genomes to a group\n";
  print "batch_grant_genome_rights_to_group.pl -genome_list <genome id file> -group <group name>\n";
}

# read in parameters
my $group_name = '';
my $genome_list = '';

GetOptions ( 'group=s' => \$group_name,
	     'genome_list=s' => \$genome_list,
	   );


unless ($group_name and $genome_list) {
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

# get group
my $group = $dbmaster->Scope->init( { 'name' => $group_name,
				      'application' => undef } );
unless (ref($group)) {
  print "Group $group_name not found in database, aborting.\n";
  exit 0;
}

# open the list of genome ids
open(FH, $genome_list) or die "Could not open $genome_list: $!\n";
my $genomes = [];
while (<FH>) {
  my $line = $_;
  chomp $line;
  if ($line =~ /^\d+\.\d+$/) {
    push(@$genomes, $line);
  } else {
    print "skipping $line - invalid format\n";
  }
}
close FH;

# get view genome rights of that group
my $view_rights = $dbmaster->Rights->get_objects( { name => 'view',
						    data_type => 'genome',
						    scope => $group } );

my $annotate_rights = $dbmaster->Rights->get_objects( { name => 'annotate',
						    data_type => 'genome',
						    scope => $group } );

my $edit_rights = $dbmaster->Rights->get_objects( { name => 'edit',
						    data_type => 'genome',
						    scope => $group } );
my $all_rights = {};
foreach my $right (@$view_rights) {
  unless (exists($all_rights->{$right->{data_id}})) {
    $all_rights->{$right->{data_id}} = {};
  }
  $all_rights->{$right->{data_id}}->{view} = $right;
}
foreach my $right (@$annotate_rights) {
  unless (exists($all_rights->{$right->{data_id}})) {
    $all_rights->{$right->{data_id}} = {};
  }
  $all_rights->{$right->{data_id}}->{annotate} = $right;
}
foreach my $right (@$edit_rights) {
  unless (exists($all_rights->{$right->{data_id}})) {
    $all_rights->{$right->{data_id}} = {};
  }
  $all_rights->{$right->{data_id}}->{edit} = $right;
}

my @names = ('view', 'annotate', 'edit');

foreach my $id (@$genomes) {
  foreach my $name (@names) {
    if (exists($all_rights->{$id}) && defined($all_rights->{$id}->{$name})) {
      my $right = $all_rights->{$id}->{$name};
      if ($right->granted) {
	print "right $name genome $id was already granted\n";
      } else {
	$right->granted(1);
	print "right $name genome $id was present, but not granted. It has been granted.\n";
      }
    } else {
      my $created = $dbmaster->Rights->create( { name => $name,
						 data_type => 'genome',
						 data_id => $id,
						 scope => $group,
						 granted => 1,
						 delegated => 1 } );
      if ($created) {
	print "right $name genome $id created.\n";
      } else {
	print "creation of right $name genome $id failed.\n";
      }
    }
  }
}
print "done.\n";
