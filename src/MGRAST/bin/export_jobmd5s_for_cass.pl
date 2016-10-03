#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use DBI;

my $job     = "";
my $version = "";
my $output  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $dbpass  = "";
my $dbcert  = "";
my $usage   = qq($0
  --job     ID of job to dump
  --version m5nr version #
  --output  dump file prefix
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
  --dbpass  db password
  --dbcert  db cert path
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'job:i'     => \$job,
    'version:i' => \$version,
    'output:s'  => \$output,
    'dbhost:s'  => \$dbhost,
	'dbname:s'  => \$dbname,
	'dbuser:s'  => \$dbuser,
	'dbpass:s'  => \$dbpass,
	'dbcert:s'  => \$dbcert
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($job && $output) {
    print STDERR $usage; exit 1;
}

my $dbh = DBI->connect(
    "DBI:Pg:dbname=$dbname;host=$dbhost;sslcert=$dbcert/postgresql.crt;sslkey=$dbcert/postgresql.key",
    $dbuser,
    $dbpass,
    {AutoCommit => 0}
);
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

open(DUMP, ">$output.$job.job_md5s") or die "Couldn't open $output.$job.job_md5s for writing.\n";

my $query = "SELECT m.md5, j.abundance, j.exp_avg, j.ident_avg, j.len_avg, j.seek, j.length FROM job_md5s j, md5s m ".
            "WHERE j.version=$version AND j.job=$job AND j.md5=m._id AND j.exp_avg <= -3";
my $sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

my $num = 0;
print STDERR "Starting data export\n";
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $abund, $expa, $identa, $lena, $seek, $length) = @row;
    my @out = (
        $version,
        $job,
        $md5,
        $abund,
        sprintf("%.3f", $expa),
        sprintf("%.3f", $identa),
        sprintf("%.3f", $lena),
        $seek || "",
        $length || ""
    );
    print DUMP join(",", map { '"'.$_.'"' } @out)."\n";
    $num += 1;
}

print STDERR "exported $num rows\n";
close(DUMP);
$dbh->disconnect;
