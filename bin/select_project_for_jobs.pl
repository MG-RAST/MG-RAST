#!/soft/packages/perl/5.12.1/bin/perl

use warnings;
use strict;

use Getopt::Long;

use WebApplicationDBHandle;
use DBMaster;
use Conf;

sub usage {
  print "select_project_for_jobs.pl >>> creates a collection for a user from a list of metagenome_ids\n";
  print "select_project_for_jobs.pl -jobs <file with job ids> -project <project id>\n";
}

my ($jobs, $project);

GetOptions( 'jobs=s' => \$jobs,
            'project=s' => \$project );

unless ($jobs and $project) {
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

# get jobdb connection
my $mgmaster = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobDB',
			      -host     => $Conf::mgrast_jobcache_host,
			      -user     => $Conf::mgrast_jobcache_user,
			      -password => $Conf::mgrast_jobcache_password );

unless (ref($mgmaster)) {
  print "could not connect to job database\n";
  exit 0;
}

# read the job ids
my $jids = [];
if (open(FH, $jobs)) {
  while (<FH>) {
    chomp;
    push(@$jids, $_);
  }
  close FH;
} else {
  print "could not open jobs file $jobs: $! $@\n";
  exit 0;
}

# get the project
my $p = $mgmaster->Project->init( { id => $project } );
unless (ref($p)) {
  print "could not initialize project $project\n";
}

# get the jobs
my $js = [];
foreach my $jid (@$jids) {
  my $job = $mgmaster->Job->get_objects( { job_id => $jid } );
  if (scalar(@$job)) {
    push(@$js, $job->[0]);
  } else {
    print "failed to get job $jid, aborting.\n";
    exit 0;
  }
}

# delete other project job connections for said jobs
foreach my $job (@$js) {
  my $pjs = $mgmaster->ProjectJob->get_objects({ job => $job });
  foreach my $pj (@$pjs) {
    $pj->delete;
  }
  $job->primary_project($project);
  $mgmaster->ProjectJob->create({job => $job, project => $project});
}


print "all done.\nHave a nice day :)\n\n";
