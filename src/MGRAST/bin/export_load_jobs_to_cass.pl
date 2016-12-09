#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use JSON;
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
my $force   = 0;
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
  --force   force load even if exists
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
	'batch:i'   => \$batch,
	'force!'    => \$force
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

my $post_attempt = 0;
my ($count, $total, $data, $query, $sth);

my $agent = LWP::UserAgent->new;
$agent->timeout(600);

my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

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

foreach my $mgid (@mg_list) {
    # first check if job already loaded in cassandra
    if (! $force) {
        my $info = undef;
        eval {
            my $req = HTTP::Request->new(POST => $apiurl.'/job/abundance');
            $req->header('content-type' => 'application/json');
            $req->header('authorization' => "mgrast $token");
            $req->content($json->encode({metagenome_id => $mgid, action => 'status'}));
            my $resp = $agent->request($req);
            $info = $json->decode( $resp->decoded_content );
        };
        unless ($info && exists($info->{status})) {
            print STDERR "Unable to query metagenome $mgid through API\n";
            next;
        }
        if (($info->{status} eq 'exists') && ($info->{loaded} eq 'true')) {
            print STDERR "Skipping $mgid - already loaded\n";
            next;
        }
    }

    # get job ID, verify job in system
    my $jobid = 0;
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

    # set to start loading
    print STDERR "md5 abundance data\n";
    print STDERR "\tset as unloaded\n";
    post_data($mgid, "start", "md5", undef, undef);

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
            post_data($mgid, "load", "md5", undef, $data);
            $count = 0;
            $data  = [];
        }
    }
    if ($count > 0) {
        post_data($mgid, "load", "md5", undef, $data);
    }
    print STDERR "\t$total md5 rows uploaded\n";
    print STDERR "\tset as loaded\n";
    post_data($mgid, "end", "md5", $total, undef);

    print STDERR "lca abundance data\n";
    print STDERR "\tset as unloaded\n";
    post_data($mgid, "start", "lca", undef, undef);

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
            post_data($mgid, "load", "lca", undef, $data);
            $count = 0;
            $data  = [];        
        }
    }
    if ($count > 0) {
        post_data($mgid, "load", "lca", undef, $data);
    }
    print STDERR "\t$total lca rows uploaded\n";
    print STDERR "\tset as loaded\n";
    post_data($mgid, "end", "lca", $total, undef);
}

$dbh->disconnect;
exit 0;

sub post_data {
    my ($mgid, $action, $type, $count, $data) = @_;
    
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
        # try 3 times
        if ($post_attempt == 3) {
            my $message = $resp->decoded_content;
            print STDERR "API error: (".$resp->code.") ".($message || $resp->message)."\n";
            $post_attempt = 0;
            return;
        } else {
            $post_attempt += 1;
            post_data($mgid, $action, $type, $count, $data);
        }
    }
}
