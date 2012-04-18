#!/usr/bin/env perl

use strict;
use warnings; 

use DBMaster;
use Getopt::Long;
use DirHandle;

use FIG_Config;

use constant BACKEND  => 'MySQL';
use constant DATABASE => 'jobcache.db';

# usage message 
sub usage {
  my $error = shift;
  print "Usage: mgrast_sync.pl [-job id] [-verbose]\n";
  print "Error: $error\n" if($error);
  exit;
}

print "[SYNC] Syncing $FIG_Config::mgrast_jobs\n";

# get command line parameters
my %options = ();
GetOptions (\%options, 
	    "job=s", "verbose",
	    "backend=s", "database=s", "host=s", "user=s",
	   ); 

print "[SYNC] Verbose mode ON\n" if ($options{verbose});

# check for job directory
unless(defined($FIG_Config::mgrast_jobs)) {
  &usage("No job directory found in FIG_Config.pm.");
}

# check for web application db settings in FIG_Config
unless(defined($FIG_Config::webapplication_db) and
       defined($FIG_Config::webapplication_backend)) {
  &usage("No webapplication db settings found in FIG_Config.pm.");
}


# init PPO 
my $backend  = $options{backend} || BACKEND;
my $database = $options{database} || $FIG_Config::mgrast_jobcache_db || DATABASE;
my $dbmaster = DBMaster->new(-database => $database,
			     -backend  => $backend,
			     -host     => $FIG_Config::mgrast_jobcache_host,
			     -user     => $FIG_Config::mgrast_jobcache_user,
			     -password => $FIG_Config::mgrast_jobcache_password
			    );

# update just the specified job
if ($options{job}) {
  my $job;
  eval { $job = $dbmaster->Job->init({ id => $options{job}}) };
  if ($job) {
    print "Updated job id ".$job->id.".\n" 
      if ($options{verbose});
  }
  else {
    print STDERR "Update failed on job ".$options{job}.".\n";
  }
}

# update all jobs in the job directory
else {
  my $jobs = [];
  my $dh = new DirHandle($FIG_Config::mgrast_jobs);
  while (defined($_ = $dh->read())) {
    next unless /^\d+$/;
    my $id = $_;
    my $job;
    eval { $job = $dbmaster->Job->init({ id => $id}) };
    if ($job) {
      print "Update successful on job $id.\n"
	if ($options{verbose});
      push @$jobs, $job;
    }
    else {
      print STDERR "[SYNC] Update failed on job $id.\n";
    }
  }
  print "[SYNC] Updated ".scalar(@$jobs)." in the job directory.\n";
}

exit 1;
