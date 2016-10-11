#!/usr/bin/env perl

use strict;
use warnings;

use JSON;
use Getopt::Long;
use Data::Dumper;
use Devel::Size qw(size total_size);
use Inline::Python qw(py_eval);

my $batch = 1000;
my $host = "";
my $name = "";
my $usage = qq($0
  --batch  query batch size, default: 1000
  --host   Cassandra host
  --name   Cassandra name
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'batch:i' => \$batch,
	'host:s'  => \$host,
	'name:s'  => \$name
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($host && $name) {
    print STDERR $usage; exit 1;
}

my $python = q(
import random
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy
from cassandra.query import dict_factory

class TestCass(object):
    def __init__(self, host, name):
        self.timeout = 300
        self.max_int = 24468843
        self.name = name
        self.hosts = host.split(",")
        self.handle = Cluster(
            contact_points = self.hosts,
            default_retry_policy = RetryPolicy()
        )
        self.session = self.handle.connect(self.name)
        self.session.default_timeout = self.timeout
        self.session.row_factory = dict_factory
        #self.prep = self.session.prepare("SELECT * FROM id_annotation WHERE id IN ? AND source=?")
    def random_array(self, size):
        array = []
        for i in range(size):
            array.append(random.randint(1, self.max_int))
        return array
    def get_records(self, ids, source='RefSeq'):
        found = []
        query = "SELECT * FROM id_annotation WHERE id IN (%s) AND source='%s'"%(",".join(map(str, ids)), source)
        rows = self.session.execute(query)
        for r in rows:
            found.append(r)
        return found
    def get_md5s(self, ids, source='RefSeq'):
        found = []
        query = "SELECT * FROM id_annotation WHERE id IN (%s) AND source='%s'"%(",".join(map(str, ids)), source)
        rows = self.session.execute(query)
        for r in rows:
            found.append(r["md5"])
        return found
    def get_iter(self, ids, source='RefSeq'):
        query = "SELECT * FROM id_annotation WHERE id IN (%s) AND source='%s'"%(",".join(map(str, ids)), source)
        return self.session.execute(query)
);

py_eval($python);

my $start = time;
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

my $tester = Inline::Python::Object->new('__main__', 'TestCass', $host, $name);
my $fields = join('%2C', ('md5_id', 'source', 'md5', 'accession', 'function', 'organism'));

my $random_ids = $tester->random_array($batch);
my $recs = $tester->get_records($random_ids);
my $md5s = $tester->get_md5s($random_ids);
my $iter = $tester->get_iter($random_ids);

print STDERR "\n";
my $end = time;

print "time: ".($end - $start)." seconds\n";
print "recs size: ".total_size($recs)." bytes\n";
print "md5s size: ".total_size($md5s)." bytes\n";
print "iter size: ".total_size($iter)." bytes\n";
print "recs found: ".scalar(@$recs)."\n";
print "md5s found: ".scalar(@$md5s)."\n";
print "first recs: ".Dumper($recs->[0])."\n";
print "first md5s: ".Dumper($md5s->[0])."\n";
print "iter: ".Dumper($iter)."\n";

