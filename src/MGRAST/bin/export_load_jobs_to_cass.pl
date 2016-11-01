#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use JSON;
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;

my $mgid    = "";
my $version = 1;
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $dbpass  = "";
my $dbcert  = "";
my $apiurl  = "";
my $token   = "";
my $batch   = 5000;
my $usage   = qq($0
  --mgid    ID of metagenome to export / load
  --version m5nr version #, default 1
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
  --dbpass  db password
  --dbcert  db cert path
  --apiurl  MG-RAST API url
  --token   MG-RAST API user token
  --batch   size of batch insert
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'mgid:s'    => \$mgid,
    'version:i' => \$version,
    'dbhost:s'  => \$dbhost,
	'dbname:s'  => \$dbname,
	'dbuser:s'  => \$dbuser,
	'dbpass:s'  => \$dbpass,
	'dbcert:s'  => \$dbcert,
	'apiurl:s'  => \$apiurl,
	'token:s'   => \$token,
	'batch:i'   => \$batch
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($mgid && $apiurl && $token) {
    print STDERR $usage; exit 1;
}

my ($count, $total, $data, $query, $sth);

my $agent = LWP::UserAgent->new;
$agent->timeout(600);

my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

my $dbh = DBI->connect(
    "DBI:Pg:dbname=$dbname;host=$dbhost;sslcert=$dbcert/postgresql.crt;sslkey=$dbcert/postgresql.key",
    $dbuser,
    $dbpass,
    {AutoCommit => 0}
);
unless ($dbh) {
    print STDERR "Error: " . $DBI::errstr . "\n"; exit 1;
}

my $jobid = 0;
eval {
    my $get = $agent->get($apiurl.'/metagenome/'.$mgid."?verbosity=minimal", ('Authorization', "mgrast $token"));
    my $info = $json->decode( $get->content );
    $jobid = $info->{job_id};
};
unless ($jobid) {
    print STDERR "Unable to get metagenome info from API\n"; exit 1;
}
print STDERR "Processing $mgid ($jobid)\n";

print STDERR "md5 abundance data\n";
print STDERR "\tset as unloaded\n";
post_data("start", "md5", undef, undef);

print STDERR "\tstart load from postgres\n";
$count = 0;
$total = 0;
$data  = [];
$query = "SELECT m.md5, j.abundance, j.exp_avg, j.ident_avg, j.len_avg, j.seek, j.length FROM job_md5s j, md5s m ".
         "WHERE j.version=$version AND j.job=$jobid AND j.md5=m._id AND j.exp_avg <= -3";
$sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

while (my @row = $sth->fetchrow_array()) {
    my ($md5, $abund, $expa, $identa, $lena, $seek, $length) = @row;
    next unless ($md5 && $abund);
    push @$data, [
        $md5,
        int($abund),
        $expa * 1.0,
        $identa * 1.0,
        $lena * 1.0,
        $seek ? int($seek) : 0,
        $length ? int($length) : 0
    ];
    $count += 1;
    $total += 1;
    if ($count == $batch) {
        post_data("load", "md5", undef, $data);
        $count = 0;
        $data  = [];        
    }
}
if ($count > 0) {
    post_data("load", "md5", undef, $data);
}
print STDERR "\t$total md5 rows uploaded\n";
print STDERR "\tset as loaded\n";
post_data("end", "md5", $total, undef);

print STDERR "lca abundance data\n";
print STDERR "\tset as unloaded\n";
post_data("start", "lca", undef, undef);

print STDERR "\tstart load from postgres\n";
$count = 0;
$total = 0;
$data  = [];
$query = "SELECT lca, abundance, exp_avg, ident_avg, len_avg, md5s, level FROM job_lcas WHERE version=$version AND job=$jobid AND exp_avg <= -3";
$sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

while (my @row = $sth->fetchrow_array()) {
    my ($lca, $abund, $expa, $identa, $lena, $md5s, $level) = @row;
    next unless ($lca && $abund);
    push @$data, [
        $lca,
        int($abund),
        $expa * 1.0,
        $identa * 1.0,
        $lena * 1.0,
        $md5s ? int($md5s) : 0,
        $level ? int($level) : 0
    ];
    $count += 1;
    $total += 1;
    if ($count == $batch) {
        post_data("load", "lca", undef, $data);
        $count = 0;
        $data  = [];        
    }
}
if ($count > 0) {
    post_data("load", "lca", undef, $data);
}
print STDERR "\t$total lca rows uploaded\n";
print STDERR "\tset as loaded\n";
post_data("end", "lca", $total, undef);

$dbh->disconnect;

sub post_data {
    my ($action, $type, $count, $data) = @_;
    
    my $post_data = {
        metagenome_id => $mgid,
        action => $action,
        type => $type
    };
    if ($count) {
        $post_data->{count} = $count;
    }
    if ($data) {
        $post_data->{data} = $data;
    }
    
    my $req = HTTP::Request->new(POST => $apiurl."/job/abundance");
    $req->header('content-type' => 'application/json');
    $req->header('authorization' => "mgrast $token");
    $req->content($json->encode($post_data));
    
    my $resp = $agent->request($req);
    unless ($resp->is_success) {
        print STDERR "API error: (".$resp->code.") ".$resp->message."\n";
    }
}
