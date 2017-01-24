#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use JSON;
use DateTime;
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;

my $mgids   = "";
my $mgfile  = "";
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
  --mgids   comma seperated IDs of metagenomes to export / load
  --mgfile  file of IDs of metagenomes to export / load
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
    'mgids:s'   => \$mgids,
    'mgfile:s'  => \$mgfile,
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

unless ($apiurl && $token) {
    print STDERR $usage; exit 1;
}

my @mg_list = ();
if ($mgids) {
    @mg_list = split(/,/, $mgids);
} elsif ($mgfile && (-s $mgfile)) {
    open INFILE, "<$mgfile";
    @mg_list = <INFILE>;
    close INFILE;
    chomp @mg_list;
} else {
    print STDERR $usage; exit 1;
}

my ($count, $total, $query, $sth);

my $agent = LWP::UserAgent->new;
$agent->timeout(600);

my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

foreach my $mgid (@mg_list) {
    # get job ID, verify job in system
    my $jobid = 0;
    my $time = DateTime->now->iso8601;
    eval {
        my $get = $agent->get($apiurl.'/metagenome/'.$mgid."?verbosity=minimal", ('Authorization', "mgrast $token"));
        my $info = $json->decode( $get->content );
        $jobid = $info->{job_id};
    };
    unless ($jobid) {
        print STDERR "Unable to get metagenome $mgid info from API\n";
        next;
    }
    print STDERR "Processing $mgid ($jobid)\n";

    ## initalize
    print STDOUT "INSERT INTO job_info (version, job, md5s, lcas, updated_on, loaded) VALUES (1, $jobid, 0, 0, '".DateTime->now->iso8601."', false);\n";

    # get postgres handle
    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$dbname;host=$dbhost;sslcert=$dbcert/postgresql.crt;sslkey=$dbcert/postgresql.key",
        $dbuser,
        $dbpass,
        {AutoCommit => 0}
    );
    unless ($dbh) {
        print STDERR "Error: " . $DBI::errstr . "\n"; exit 1;
    }

    ## do md5s
    $count = 0;
    $total = 0;
    $query = "SELECT m.md5, j.abundance, j.exp_avg, j.ident_avg, j.len_avg, j.seek, j.length FROM job_md5s j, md5s m ".
             "WHERE j.version=$version AND j.job=$jobid AND j.md5=m._id AND j.exp_avg <= -3";
    $sth = $dbh->prepare($query);
    unless ($sth->execute()) {
        print STDERR "Postgres error: ".$sth->errstr."\n";
        $dbh->disconnect;
        next;
    }
    
    print STDOUT "BEGIN BATCH\n";
    while (my @row = $sth->fetchrow_array()) {
        my ($md5, $abund, $expa, $identa, $lena, $seek, $length) = @row;
        next unless ($md5 && $abund);
        my @values = (
            1,
            $jobid,
            "'".$md5."'",
            int($abund),
            $expa * 1.0,
            $identa * 1.0,
            $lena * 1.0,
            $seek ? int($seek) : 0,
            $length ? int($length) : 0
        );
        print STDOUT "INSERT INTO job_md5s (version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length) VALUES (".join(",", @values).");\n";
        $count += 1;
        $total += 1;
        if ($count == $batch) {
            print STDOUT "UPDATE job_info SET md5s = $total, loaded = false, updated_on = '".DateTime->now->iso8601."' WHERE version = 1 AND job = $jobid;\n";
            print STDOUT "APPLY BATCH;\nBEGIN BATCH\n";
            $count = 0;
        }
    }
    print STDOUT "UPDATE job_info SET md5s = $total, loaded = true, updated_on = '".DateTime->now->iso8601."' WHERE version = 1 AND job = $jobid;\n";
    print STDOUT "APPLY BATCH;\n";
    
    ## do lcas
    $count = 0;
    $total = 0;
    $query = "SELECT lca, abundance, exp_avg, ident_avg, len_avg, md5s, level FROM job_lcas WHERE version=$version AND job=$jobid AND exp_avg <= -3";
    $sth = $dbh->prepare($query);
    unless ($sth->execute()) {
        print STDERR "Postgres error: ".$sth->errstr."\n";
        $dbh->disconnect;
        next;
    }
    
    print STDOUT "BEGIN BATCH\n";
    while (my @row = $sth->fetchrow_array()) {
        my ($lca, $abund, $expa, $identa, $lena, $md5s, $level) = @row;
        next unless ($lca && $abund);
        my @values = (
            1,
            $jobid,
            "'".$lca."'",
            int($abund),
            $expa * 1.0,
            $identa * 1.0,
            $lena * 1.0,
            $md5s ? int($md5s) : 0,
            $level ? int($level) : 0
        );
        print STDOUT "INSERT INTO job_lcas (version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) VALUES (".join(",", @values).");\n";
        $count += 1;
        $total += 1;
        if ($count == $batch) {
            print STDOUT "UPDATE job_info SET lcas = $total, loaded = false, updated_on = '".DateTime->now->iso8601."' WHERE version = 1 AND job = $jobid;\n";
            print STDOUT "APPLY BATCH;\nBEGIN BATCH\n";
            $count = 0;      
        }
    }
    print STDOUT "UPDATE job_info SET lcas = $total, loaded = true, updated_on = '".DateTime->now->iso8601."' WHERE version = 1 AND job = $jobid;\n";
    print STDOUT "APPLY BATCH;\n";
    
    $dbh->disconnect;
}

exit 0;
