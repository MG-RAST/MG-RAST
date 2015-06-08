#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON;
use DBI;
use LWP::UserAgent;

my $output  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $m5nr    = "";
my $version = "";
my $usage   = qq($0
  --job     ID of job to dump
  --output  dump file prefix
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
  --m5nr    m5nr solr url
  --version m5nr version #
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'job:i'     => \$job,
    'output:s'  => \$output,
	'dbname:s'  => \$dbname,
	'dbuser:s'  => \$dbuser,
	'dbhost:s'  => \$dbhost,
	'm5nr:s'    => \$m5nr,
	'version:i' => \$version
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($job && $output) {
    print STDERR $usage; exit 1;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

my $agent = LWP::UserAgent->new;
$agent->timeout(600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

open(DUMP, ">$output.$job") or die "Couldn't open $output.$job for writing.\n";

my $query = "SELECT md5, abundance, exp_avg, exp_stdv, len_avg, len_stdv, ident_avg, ident_stdv, seek, length, is_protein FROM job_md5s WHERE version=$version AND job=$job";
my $sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

my @batch_set = ();
my $batch_count = 0;
while (my @row = $sth->fetchrow_array()) {
    push @batch_set, \@row;
    $batch_count += 1;
    if ($batch_count == 1000) {
        my @mids = map { $_->[0] } @batch_set;
        my @field = ('md5_id', 'md5', 'source', 'accession', 'function', 'organism');
        my $query = 'q=*%3A*&fq=md5_id:('.join(' OR ', @mids).')&start=0&rows=1000000000&wt=json&fl='.join('%2C', @field);
        my $result = $agent->post($m5nr."/m5nr_".$version, Content => $query);
        my $content = $json->decode( $result->content );
        
        foreach my $set (@batch_set) {
            my ($mid, $abund, $ea, $es, $la, $ls, $ia, $is, $seek, $len, $prot) = $set;
            
        }
        @batch_set = ();
        $batch_count = 0;
    }
}

close(DUMP);
$dbh->disconnect;

