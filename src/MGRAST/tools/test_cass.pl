#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Inline::Python qw(py_eval);

my $batch = 100;
my $count = 10;
my $chost = "";
my $cname = "";
my $usage = qq($0
  --batch  query batch size, default: 100
  --count  number of query iterations, default: 10
  --chost  Cassandra host
  --cname  Cassandra name
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'batch:i' => \$batch,
	'count:i' => \$count,
	'chost:s' => \$chost,
	'cname:s' => \$cname
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($chost && $cname) {
    print STDERR $usage; exit 1;
}

py_eval(<<'END');

import random
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy

class TestCass(object):
    def __init__(self, chost, cname):
        self.max_int = 24468843
        self.cname = cname
        self.handle = Cluster(
            contact_points=[chost],
            default_retry_policy = RetryPolicy()
        )
    def random_array(self, size):
        array = []
        for i in range(size):
            array.append(random.randint(1, self.max_int))
        return array
    def get_records(self, ids):
        found = []
        query = "SELECT * FROM id_annotation WHERE id IN ("+",".join(map(str, ints))+");"
        session = self.handle.connect(self.cname)
        rows = session.execute(query)
        for r in rows:
            found.append(r.md5)
        return found

END

my $md5s = {};
my $start = time;
my $tester = Inline::Python::Object->new('__main__', 'TestCass', $chost, $cname);

foreach my $i (1..$count) {
    print ".";
    my $random_ids = $tester->random_array($batch);
    map { $md5s->{$_} = 1 } @{ $tester->get_records($random_ids) };
}
my $end = time;

print "$count loops of size $batch ran in ".($end - $start)." seconds\n";
print ($count * $batch)." ids requested, ".scalar(keys %$md5s)." md5s found\n"
    
