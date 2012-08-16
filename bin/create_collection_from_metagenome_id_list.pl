#!/soft/packages/perl/5.12.1/bin/perl

use warnings;
use strict;

use Getopt::Long;

use WebApplicationDBHandle;
use DBMaster;
use Conf;

sub usage {
  print "create_collection_from_metagenome_id_list.pl >>> creates a collection for a user from a list of metagenome_ids\n";
  print "create_collection_from_metagenome_id_list.pl -file <metagenome id file> -login <user login> -collection <collection name> [ -append <append if group exists?> ]\n";
}

my ($file, $login, $collection, $append);

GetOptions( 'file=s' => \$file,
            'login=s' => \$login,
	    'collection=s' => \$collection,
	    'append=s' => \$append );

unless ($file and $login and $collection) {
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

my $user = $dbmaster->User->get_objects( { login => $login } );
if (scalar(@$user)) {
  $user = $user->[0];
} else {
  print "could not find user in user database, aborting.\n";
  exit 0;
}

my $mgids = [];
if (open(FH, $file)) {
  while (<FH>) {
    chomp;
    push(@$mgids, $_);
  }
  close FH;
} else {
  print "could not open input file $file: $! $@\n";
  exit 0;
}

my $metagenomes = [];
foreach my $mgid (@$mgids) {
  my $mg = $mgmaster->Job->get_objects( { metagenome_id => $mgid } );
  if (scalar(@$mg)) {
    push(@$metagenomes, $mg->[0]);
  } else {
    print "failed to get metagenome $mgid, aborting.\n";
    exit 0;
  }
}

my $backend = $dbmaster->Backend->get_objects( { name => 'MGRAST' } )->[0];

my $prefs = $dbmaster->Preferences->get_objects( { user => $user, name => 'mgrast_collection' } );
my $colls = {};
foreach my $pref (@$prefs) {
  my ($name, $mg) = split /\|/, $pref->{value};
  if (! exists($colls->{$name})) {
    $colls->{$name} = {};
  }
  $colls->{$name}->{$mg} = 1;
}

if (exists($colls->{$collection}) && ! $append) {
  print "collection $collection already exists and you did not choose to append, aborting.\n";
  return 0;
}

foreach my $mg (@$metagenomes) {
  if (exists($colls->{$collection}) && $colls->{$collection}->{$mg->{job_id}}) {
    print "metagenome ".$mg->{name}." ( ".$mg->{metagenome_id}." / ".$mg->{job_id}." ) is already part of collection '$collection', skipping.\n";
  } else {
    my $p = $dbmaster->Preferences->create( { user => $user, name => 'mgrast_collection', value => $collection."|".$mg->{job_id}, application => $backend } );
    if (ref($p)) {
      print "metagenome ".$mg->{name}." ( ".$mg->{metagenome_id}." / ".$mg->{job_id}." ) added to collection '$collection'.\n";
    } else {
      print "adding metagenome ".$mg->{name}." ( ".$mg->{metagenome_id}." / ".$mg->{job_id}." ) to collection '$collection' failed.\n";
    }
  }
}

print "done.\nHave a nice day :)\n\n";
