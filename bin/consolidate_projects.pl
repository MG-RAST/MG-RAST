#!/usr/bin/perl

BEGIN {
    unshift @INC, qw(
              /MG-RAST/site/lib
              /MG-RAST/site/lib/WebApplication
              /MG-RAST/site/lib/PPO
              /MG-RAST/site/lib/MGRAST
              /MG-RAST/site/lib/Babel
              /MG-RAST/conf
        );
}

use warnings;
use strict;

use Getopt::Long;

use WebApplicationDBHandle;
use DBMaster;
use Conf;

sub usage {
  print "consolidate_projects.pl >>> moves all jobs from a list of projects into a target project\n";
  print "consolidate_projects.pl -projects <file with source project ids> -project <target project name>\n";
}

my ($project, $projects);

GetOptions( 'projects=s' => \$projects,
            'project=s' => \$project );

unless ($projects and $project) {
  &usage;
  exit 0;
}

print "getting user db...\n";

# initialize db-master
my ($dbmaster, $error) = WebApplicationDBHandle->new();

# check if we got a dbmaster
if ($error) {
  print $error."\n";
  exit 0;
}

print "getting job db...\n";

# get jobdb connection
my $mgmaster = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobDB',
			      -host     => $Conf::mgrast_jobcache_host,
			      -user     => $Conf::mgrast_jobcache_user,
			      -password => $Conf::mgrast_jobcache_password );

unless (ref($mgmaster)) {
  print "could not connect to job database\n";
  exit 0;
}

print "getting target project...\n";

# get the project
my $p = $mgmaster->Project->get_objects( { name => $project } );
if (scalar(@$p)) {
  $p = $p->[0];
} else {
  print "target project must exist, aborting\n";
  exit 0;
}

print "getting source projects...\n";

# read in the source project names
my $pids = [];
if (open FH, "<$projects") {
  while (<FH>) {
    chomp;
    print "$_ \n";
    push(@$pids, $_);
  }
  close FH;
} else {
  print "could not open source project file $projects: $@\n";
  exit 0;
}

print scalar(@$pids)." ids found.\ngetting jobs...\n";

# get the jobs
my $js = [];
my $x = 0;
my $y = 0;
foreach my $pid (@$pids) {
  $x++;
  my $jobs = $mgmaster->Project->init( { id => $pid } )->metagenomes();
  if (scalar(@$jobs)) {
    foreach my $j (@$jobs) {
      push(@$js, $j);
    }
  }
  my $z = scalar(@$jobs);
  $y += $z;
  print "project $x has $z jobs ($y jobs total fetched)\n";
}

print "updating connections...\n";

# delete other project job connections for said jobs
$x = 0;
foreach my $job (@$js) {
  my $pjs = $mgmaster->ProjectJob->get_objects({ job => $job });
  foreach my $pj (@$pjs) {
    $pj->delete;
  }
  $job->primary_project($p);
  $mgmaster->ProjectJob->create({job => $job, project => $p});
  $x++;
  print "$x out of $y done.\n";
}

print "deleting old projects...\n";
$x = scalar(@$pids);
$y = 0;
# delete the old projects
foreach my $id (@$pids) {
  $mgmaster->Project->init( { id => $id } )->delete();
  my $rs = $dbmaster->Rights->get_objects( { "data_type" => "project", "data_id" => $id } );
  foreach my $r (@$rs) {
    $r->delete();
  }
  $y++;
  print "$y out of $x done.\n";
}

print "all done.\nHave a nice day :)\n\n";
