#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

use FIG_Config;
use Babel::lib::Babel;

my $usage   = "load_stats.pl [--verbose] [--dbname NAME] [--dbuser USER] [--dbhost HOST]\n";
my $dbname  = $FIG_Config::babel_db;
my $dbuser  = $FIG_Config::babel_dbuser;
my $dbhost  = $FIG_Config::babel_dbhost;
my $verbose = 0;

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! GetOptions('dbname:s' => \$dbname,
		  'dbuser:s' => \$dbuser,
		  'dbhost:s' => \$dbhost,
		  "verbose!" => \$verbose,
		 ) ) {
  print STDERR $usage; exit;
}

print "Initializing Babel DB\n" if ($verbose); 
my ($dbh, $babel);
if ($dbname && $dbuser && $dbhost) {
  $dbh   = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '');
  $babel = Babel::lib::Babel->new($dbh);
}
else {
  $babel = new Babel::lib::Babel;
  $dbh   = $babel->dbh();
}

print "Adding source protein id counts to db ...\n" if ($verbose);
&add_stats( "protein_ids", $babel->source_stats4pid() );
print "Adding source ontology id counts to db ...\n" if ($verbose);
&add_stats( "ontology_ids", $babel->source_stats4oid() );
print "Adding source rna id counts to db ...\n" if ($verbose);
&add_stats( "rna_ids", $babel->source_stats4rid() );
print "Adding source md5 counts to db ...\n" if ($verbose);
&add_stats( "md5s", $babel->source_stats4md5() );
print "Adding source uniq md5 counts to db ...\n" if ($verbose);
&add_stats( "uniq_md5s", $babel->source_stats4md5uniq() );
print "Adding source function counts to db ...\n" if ($verbose);
&add_stats( "functions", $babel->source_stats4func() );
print "Adding source contig counts to db ...\n" if ($verbose);
&add_stats( "contigs", $babel->source_stats4contig() );
print "Adding source organism counts to db ...\n" if ($verbose);
&add_stats( "organisms", $babel->source_stats4org() );
print "Adding source NCBI organism counts to db ...\n" if ($verbose);
&add_stats( "ncbi_organisms", $babel->source_stats4org_tax() );

print "Adding total protein id counts to db ...\n" if ($verbose);
my $t_pid = $dbh->selectcol_arrayref("SELECT COUNT(DISTINCT id) FROM md5_protein");
&add_count( "protein_ids", $t_pid->[0] );

print "Adding total ontology id counts to db ...\n" if ($verbose);
my $t_oid = $dbh->selectcol_arrayref("SELECT COUNT(DISTINCT id) FROM md5_ontology");
&add_count( "ontology_ids", $t_oid->[0] );

print "Adding total rna id counts to db ...\n" if ($verbose);
my $t_rid = $dbh->selectcol_arrayref("SELECT COUNT(DISTINCT id) FROM md5_rna");
&add_count( "rna_ids", $t_rid->[0] );

print "Adding total function counts to db ...\n" if ($verbose);
my $t_func = $dbh->selectcol_arrayref("SELECT COUNT(_id) FROM functions");
&add_count( "functions", $t_func->[0] );

print "Adding total organism counts to db ...\n" if ($verbose);
my $t_org = $dbh->selectcol_arrayref("SELECT COUNT(_id) FROM organisms_ncbi");
&add_count( "organisms", $t_org->[0] );

print "Adding total contig counts to db ...\n" if ($verbose);
my $t_ctg = $dbh->selectcol_arrayref("SELECT COUNT(_id) FROM contigs");
&add_count( "contigs", $t_ctg->[0] );

print "Adding protein md5 counts to db ...\n" if ($verbose);
my $t_pmd5 = $dbh->selectcol_arrayref("SELECT COUNT(DISTINCT md5) FROM md5_protein");
&add_count( "protein_md5s", $t_pmd5->[0] );

print "Adding rna md5 counts to db ...\n" if ($verbose);
my $t_rmd5 = $dbh->selectcol_arrayref("SELECT COUNT(DISTINCT md5) FROM md5_rna");
&add_count( "rna_md5s", $t_rmd5->[0] );

print "Adding total md5 counts to db ...\n" if ($verbose);
my $t_md5 = $t_pmd5->[0] + $t_rmd5->[0];
&add_count( "md5s", $t_md5 );

print "Done\n" if ($verbose);

sub add_stats {
  my ($col, $data) = @_;

  foreach (@$data) {
    if ( $babel->is_source($_->[0]) ) {
      my $sql = qq(UPDATE sources SET $col=$_->[1] WHERE _id='$_->[0]');
      my $res = $dbh->do($sql);
      if (! $res) { print STDERR "Error: $sql\n" . $dbh->error . "\n"; }
    }
  }
}

sub add_count {
  my ($type, $count) =@_;

  my $sql = "SELECT COUNT(*) FROM counts WHERE type='$type'";
  my $val = $dbh->selectcol_arrayref($sql);

  if ($val && $val->[0]) {
    $sql = "UPDATE counts SET count=$count WHERE type='$type'";
  }
  else {
    $sql = "INSERT INTO counts (type, count) VALUES ('$type', $count)";
  }
  my $res = $dbh->do($sql);
  if (! $res) { print STDERR "Error running: $sql\n" . $dbh->error . "\n"; }
}
