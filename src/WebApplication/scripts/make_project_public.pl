#!/usr/bin/env perl

use strict;
use warnings;

use DBMaster;
use Conf;

use Getopt::Long;


sub usage {
  print "make_project_public.pl >>> make a project and all its jobs public\n";
  print "make_project_public.pl -project_id <project id NOT _id!>\n";
}

# read in parameters
my $project_id  = '';

GetOptions ( 'project_id=s' => \$project_id );

unless ($project_id) {
  &usage();
  exit 0;
}


# initialize db-connection
my $jobdb = db_connect();

# check if we got a dbmaster
unless (ref $jobdb) {
  print "Could not connect to job db\n";
  exit 0;
}

my $project = $jobdb->Project->init( { id => $project_id } );
unless (ref $project) {
  print "Could not find project $project_id in the database\n";
  exit 0;
}

my $project_jobs = $jobdb->ProjectJob->get_objects( { project => $project } );
foreach my $pj (@$project_jobs) {
  $pj->job->public(1);
}
$project->public(1);

print "The project ".$project->name." ($project_id) and all its jobs are now public\nHave a nice day :)\n";

sub db_connect {
    my $jobdb = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobDB',
			       -host     => $Conf::mgrast_jobcache_host,
			       -user     => $Conf::mgrast_jobcache_user,
			       -password => $Conf::mgrast_jobcache_password );
    
    return $jobdb;
}
