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
my $count;

if (! $output) {
    print STDERR $usage; exit 1;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

## skipping GO
print STDERR "Loading sources ...\n";
my $src_sql = "SELECT _id AS source_id, name AS source, source AS organization, description, type, url, email, link, title, version, download_date FROM sources WHERE _id != 11";
my $src_lookup = $dbh->selectall_hashref($src_sql , "source_id");

print STDERR "Dumping sources ...\n";
open(SRC, ">$output.source") or die "Couldn't open $output.source for writing.\n";
foreach my $set (values %$src_lookup) {
    $set->{id} = 's_'.$set->{source_id};
    $set->{object} = 'source';
    print SRC to_json($set, {ascii => 1})."\n";
    delete $set->{id};
    delete $set->{object};
}
close(SRC);

print STDERR "Loading ontologies ...\n";
my $ont_sql = "SELECT _id AS ontology_id, o.id AS accession, o.level1, o.level2, o.level3, o.level4, s.name AS source FROM ontologies o, sources s WHERE o.source = s._id AND s._id != 11";
my $ont_lookup = $dbh->selectall_hashref($ont_sql , "accession");

print STDERR "Dumping ontologies ...\n";
open(ONT, ">$output.ontology") or die "Couldn't open $output.ontology for writing.\n";
$count = 1;
foreach my $set (values %$ont_lookup) {
    $set->{id} = 'o_'.$count;
    $set->{object} = 'ontology';
    if ($set->{source} =~ /^[NC]OG$/) {
        delete $set->{level4};
    }
    print ONT to_json($set, {ascii => 1})."\n";
    delete $set->{id};
    delete $set->{object};
    $count += 1;
}
close(ONT);

print STDERR "Loading organisms ...\n";
my $org_sql = "SELECT _id AS organism_id, name AS organism, tax_domain AS domain, tax_phylum AS phylum, tax_class AS class, tax_order AS order, tax_family AS family, tax_genus AS genus, tax_species AS species, ncbi_tax_id FROM organisms_ncbi";
my $org_lookup = $dbh->selectall_hashref($org_sql , "organism_id");

print STDERR "Dumping taxonomy ...\n";
open(TAX, ">$output.taxonomy") or die "Couldn't open $output.taxonomy for writing.\n";
foreach my $set (values %$org_lookup) {
    $set->{id} = 't_'.$set->{organism_id};
    $set->{object} = 'taxonomy';
    print TAX to_json($set, {ascii => 1})."\n";
    delete $set->{id};
    delete $set->{object};
}
close(TAX);

print STDERR "Loading functions ...\n";
my $func_sql = "SELECT _id AS function_id, name AS function FROM functions";
my $func_lookup = $dbh->selectall_hashref($func_sql , "function_id");

print STDERR "Loading md5s ...\n";
my $md5_sql = "SELECT _id AS md5_id, md5 FROM md5s";
my $md5_lookup = $dbh->selectall_hashref($md5_sql , "md5");

open(DUMP, ">$output.annotation") or die "Couldn't open $output.annotation for writing.\n";
# rna
print STDERR "Dumping rna annotations ...\n";
$count = 1;
$sth = $dbh->prepare("SELECT md5, id, function, organism, source FROM md5_rna WHERE tax_rank = 1");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $org, $src) = @row;
    my $data = { 'id' => 'a_'.$count, 'accession' => $id, 'object' => 'annotation' };
    if ($md5 && exists($md5_lookup->{$md5})) {
        map { $data->{$_} = $md5_lookup->{$md5}{$_} } keys %{$md5_lookup->{$md5}};
    }
    if ($func && exists($func_lookup->{$func})) {
        map { $data->{$_} = $func_lookup->{$func}{$_} } keys %{$func_lookup->{$func}};
    }
    if ($org && exists($org_lookup->{$org})) {
        map { $data->{$_} = $org_lookup->{$org}{$_} } keys %{$org_lookup->{$org}};
    }
    if ($src && exists($src_lookup->{$src})) {
        map { $data->{$_} = $src_lookup->{$src}{$_} } grep { exists $src_lookup->{$src}{$_} } ('source_id', 'source', 'type');
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
    my $aliases = $dbh->selectall_arrayref("SELECT alias_source, alias_id FROM aliases_protein WHERE id=".$dbh->quote($id));
    my $data = { 'id' => 'a_'.$count, 'accession' => $id, 'object' => 'annotation' };
    if ($aliases && (@$aliases > 0)) {
        $data->{alias} = [];
        foreach $aset (@$aliases) {
            my ($asrc, $aid) = @$aset;
            if ($asrc && $aid && ($aid !~ /^$asrc:/)) {
                $aid = $asrc.":".$aid;
            }
            push @{$data->{alias}}, $aid;
        }
    }
    if ($md5 && exists($md5_lookup->{$md5})) {
        map { $data->{$_} = $md5_lookup->{$md5}{$_} } keys %{$md5_lookup->{$md5}};
    }
    if ($func && exists($func_lookup->{$func})) {
        map { $data->{$_} = $func_lookup->{$func}{$_} } keys %{$func_lookup->{$func}};
    }
    if ($org && exists($org_lookup->{$org})) {
        map { $data->{$_} = $org_lookup->{$org}{$_} } keys %{$org_lookup->{$org}};
    }
    if ($src && exists($src_lookup->{$src})) {
        map { $data->{$_} = $src_lookup->{$src}{$_} } grep { exists $src_lookup->{$src}{$_} } ('source_id', 'source', 'type');
    }
    $count += 1;
    print DUMP to_json($data, {ascii => 1})."\n";
}
$sth->finish;

# ontology - skip GO
print STDERR "Dumping ontology annotations ...\n";
$sth = $dbh->prepare("SELECT md5, id, function, source FROM md5_ontology WHERE source != 11");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $src) = @row;
    my $data = { 'id' => 'a_'.$count, 'accession' => $id, 'object' => 'annotation' };
    if ($md5 && exists($md5_lookup->{$md5})) {
        map { $data->{$_} = $md5_lookup->{$md5}{$_} } keys %{$md5_lookup->{$md5}};
    }
    if ($func && exists($func_lookup->{$func})) {
        map { $data->{$_} = $func_lookup->{$func}{$_} } keys %{$func_lookup->{$func}};
    }
    if ($id && exists($ont_lookup->{$id})) {
        map { $data->{$_} = $ont_lookup->{$id}{$_} } keys %{$ont_lookup->{$id}};
    }
    if ($src && exists($src_lookup->{$src})) {
        map { $data->{$_} = $src_lookup->{$src}{$_} } grep { exists $src_lookup->{$src}{$_} } ('source_id', 'source', 'type');
    }
    $count += 1;
    print DUMP to_json($data, {ascii => 1})."\n";
}
$sth->finish;
close(DUMP);
$dbh->disconnect;
