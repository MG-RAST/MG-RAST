#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON;
use DBI;

my $verbose = 0;
my $output  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $usage   = qq($0
  --output  dump file name
  --dbhost  db host, default '$dbhost'
  --dbname  db name, default '$dbname'
  --dbuser  db user, default '$dbuser'
  );

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
            'output:s' => \$output,
		    'dbname:s' => \$dbname,
		    'dbuser:s' => \$dbuser,
		    'dbhost:s' => \$dbhost
		 ) ) {
  print STDERR $usage; exit 1;
}
my $sth;

if (! $output) {
    print STDERR $usage; exit;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

print STDERR "Loading sources ...\n";
my %src_lookup = ();
$sth = $dbh->prepare("SELECT _id, name, type FROM sources");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    $src_lookup{$row[0]}{source_id} = int($row[0]);
    $src_lookup{$row[0]}{source} = $row[1];
    $src_lookup{$row[0]}{type} = $row[2];
}
$sth->finish;

print STDERR "Loading ontologies ...\n";
my %ont_lookup = ();
$sth = $dbh->prepare("SELECT id, level1, level2, level3, level4 FROM ontologies");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    $ont_lookup{$row[0]}{level1} = $row[1];
    $ont_lookup{$row[0]}{level2} = $row[2];
    $ont_lookup{$row[0]}{level3} = $row[3];
    $ont_lookup{$row[0]}{level4} = $row[4];
}
$sth->finish;

print STDERR "Loading organisms ...\n";
my %org_lookup = ();
$sth = $dbh->prepare("SELECT _id, name, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, ncbi_tax_id FROM organisms_ncbi");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    $org_lookup{$row[0]}{organism_id} = int($row[0]);
    $org_lookup{$row[0]}{organism} = $row[1];
    if ($row[2]) { $org_lookup{$row[0]}{domain} = $row[2]; }
    if ($row[3]) { $org_lookup{$row[0]}{phylum} = $row[3]; }
    if ($row[4]) { $org_lookup{$row[0]}{class} = $row[4]; }
    if ($row[5]) { $org_lookup{$row[0]}{order} = $row[5]; }
    if ($row[6]) { $org_lookup{$row[0]}{family} = $row[6]; }
    if ($row[7]) { $org_lookup{$row[0]}{genus} = $row[7]; }
    if ($row[8]) { $org_lookup{$row[0]}{species} = $row[8]; }
    if ($row[9]) { $org_lookup{$row[0]}{ncbi_tax_id} = int($row[9]); }
}
$sth->finish;

print STDERR "Loading functions ...\n";
my %func_lookup = ();
$sth = $dbh->prepare("SELECT _id, name FROM functions");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    $func_lookup{$row[0]}{function_id} = int($row[0]);
    $func_lookup{$row[0]}{function} = $row[1];
}
$sth->finish;

print STDERR "Loading md5s ...\n";
my %md5_lookup = ();
$sth = $dbh->prepare("SELECT _id, md5 FROM md5s");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    $md5_lookup{$row[1]}{md5_id} = int($row[0]);
    $md5_lookup{$row[1]}{md5} = $row[1];
}
$sth->finish;

open(DUMP, ">$output") or die "Couldn't open $output for writing.\n";
# rna
print STDERR "Dumping rna annotations ...\n";
my $count = 1;
$sth = $dbh->prepare("SELECT md5, id, function, organism, source FROM md5_rna WHERE tax_rank = 1");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $org, $src) = @row;
    my $data = { 'id' => $count, 'accession' => $id };
    if ($md5 && exists($md5_lookup{$md5})) {
        map { $data->{$_} = $md5_lookup{$md5}{$_} } keys %{$md5_lookup{$md5}};
    }
    if ($func && exists($func_lookup{$func})) {
        map { $data->{$_} = $func_lookup{$func}{$_} } keys %{$func_lookup{$func}};
    }
    if ($org && exists($org_lookup{$org})) {
        map { $data->{$_} = $org_lookup{$org}{$_} } keys %{$org_lookup{$org}};
    }
    if ($src && exists($src_lookup{$src})) {
        map { $data->{$_} = $src_lookup{$src}{$_} } keys %{$src_lookup{$src}};
    }
    $count += 1;
    print DUMP to_json($data, {ascii => 1})."\n";
}
$sth->finish;

# protein
print STDERR "Dumping protein annotations ...\n";
$sth = $dbh->prepare("SELECT md5, id, function, organism, source FROM md5_protein");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $org, $src) = @row;
    my $data = { 'id' => $count, 'accession' => $id };
    if ($md5 && exists($md5_lookup{$md5})) {
        map { $data->{$_} = $md5_lookup{$md5}{$_} } keys %{$md5_lookup{$md5}};
    }
    if ($func && exists($func_lookup{$func})) {
        map { $data->{$_} = $func_lookup{$func}{$_} } keys %{$func_lookup{$func}};
    }
    if ($org && exists($org_lookup{$org})) {
        map { $data->{$_} = $org_lookup{$org}{$_} } keys %{$org_lookup{$org}};
    }
    if ($src && exists($src_lookup{$src})) {
        map { $data->{$_} = $src_lookup{$src}{$_} } keys %{$src_lookup{$src}};
    }
    $count += 1;
    print DUMP to_json($data, {ascii => 1})."\n";
}
$sth->finish;

# ontology
print STDERR "Dumping ontology annotations ...\n";
$sth = $dbh->prepare("SELECT md5, id, function, source FROM md5_ontology WHERE source != 11");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $src) = @row;
    my $data = { 'id' => $count, 'accession' => $id };
    if ($md5 && exists($md5_lookup{$md5})) {
        map { $data->{$_} = $md5_lookup{$md5}{$_} } keys %{$md5_lookup{$md5}};
    }
    if ($func && exists($func_lookup{$func})) {
        map { $data->{$_} = $func_lookup{$func}{$_} } keys %{$func_lookup{$func}};
    }
    if (exists($ont_lookup{$id})) {
        map { $data->{$_} = $ont_lookup{$id}{$_} } keys %{$ont_lookup{$id}};
    }
    if ($src && exists($src_lookup{$src})) {
        map { $data->{$_} = $src_lookup{$src}{$_} } keys %{$src_lookup{$src}};
    }
    $count += 1;
    print DUMP to_json($data, {ascii => 1})."\n";
}
$sth->finish;

close(DUMP);
$dbh->disconnect;
