#!/usr/bin/env perl

use strict;
use warnings;

use JSON;
use LWP::UserAgent;
use Getopt::Long;
use Data::Dumper;
use Inline::Python qw(py_eval);

my $batch = 100;
my $count = 10;
my $host = "";
my $name = "";
my $solr = "";
my $usage = qq($0
  --batch  query batch size, default: 100
  --count  number of query iterations, default: 10
  --host   Cassandra host
  --name   Cassandra name
  --solr   solr url "http://bio-worker3.mcs.anl.gov:8983/solr/m5nr_1/select"
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'batch:i' => \$batch,
	'count:i' => \$count,
	'host:s'  => \$host,
	'name:s'  => \$name,
	'solr:s'  => \$solr
   ) ) {
  print STDERR $usage; exit 1;
}

unless (($host && $name) || $solr) {
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
    def get_records(self, ids, source):
        found = []
        query = "SELECT * FROM id_annotation WHERE id IN (%s) AND source='%s'"%(",".join(map(str, ids)), source)
        rows = self.session.execute(query)
        for r in rows:
            found.append(r["md5"])
        return found
);

py_eval($python);

my $md5s = {};
my $start = time;

my $agent = LWP::UserAgent->new;
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

my $tester = Inline::Python::Object->new('__main__', 'TestCass', $host, $name);
my $fields = join('%2C', ('md5_id', 'source', 'md5', 'accession', 'function', 'organism'));

foreach my $i (1..$count) {
    print STDERR ".";
    my $random_ids = $tester->random_array($batch);
    if ($solr) {
        my $query = "md5_id:(".join(" OR ", @$random_ids).")";
        my $sdata = "q=*%3A*&fq=".$query."&start=0&rows=1000000000&wt=json&fl=".$fields;
        my $res = $json->decode( $agent->post($solr, Content => $sdata)->content );
        map { $md5s->{$_->{md5}} = 1 } @{$res->{response}{docs}};
    } else {
        map { $md5s->{$_} = 1 } @{ $tester->get_records($random_ids, 'RefSeq') };
    }
}
print STDERR "\n";
my $end = time;
my $total = $count * $batch;

print "$count loops of size $batch ran in ".($end - $start)." seconds\n";
print $total." ids requested, ".scalar(keys %$md5s)." md5s found\n";
