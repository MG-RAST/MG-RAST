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

## skipping GO
print STDERR "Loading sources ...\n";
my $src_data = ['source_id','source','organization','description','type','url','email','link','title','version','download_date'];
my $src_sql = "SELECT _id AS source_id, name AS source, source AS organization, description, type, url, email, link, title, version, download_date FROM sources WHERE _id != 11";
my $src_lookup = $dbh->selectall_hashref($src_sql , "source_id");

print STDERR "Dumping sources ...\n";
open(SRC, ">$output.source") or die "Couldn't open $output.source for writing.\n";
print SRC to_json(lookup2data($src_lookup, $src_data, 'static_source'), {ascii => 1})."\n";
close(SRC);

print STDERR "Loading ontologies ...\n";
my $ont_sql = "SELECT id, level1, level2, level3, level4, source FROM ontologies";
my $ont_lookup = $dbh->selectall_hashref($ont_sql , "id");
foreach my $onts (grep {$_->{type} eq 'ontology'} values %$src_lookup) {
    my $ont_data = ['id','level1','level2','level3','level4'];
    if ($onts->{source} =~ /^[CN]OG$/) {
        pop @$ont_data;
    }
    my %sub_ont_lookup = map {$_, $ont_lookup->{$_}} grep {$ont_lookup->{$_}{source} eq $onts->{source_id}} keys %$ont_lookup;
    print STDERR "Dumping ontology ".$onts->{source}." ...\n";
    open(TAX, ">$output.".$onts->{source}) or die "Couldn't open $output.".$onts->{source}." for writing.\n";
    print TAX to_json(lookup2data(\%sub_ont_lookup, $ont_data, 'static_'.$onts->{source}), {ascii => 1})."\n";
    close(TAX);
}

print STDERR "Loading organisms ...\n";
my $org_data = ['organism_id','organism','domain','phylum','class','order','family','genus','species','ncbi_tax_id'];
my $org_sql = "SELECT _id AS organism_id, name AS organism, tax_domain AS domain, tax_phylum AS phylum, tax_class AS class, tax_order AS order, tax_family AS family, tax_genus AS genus, tax_species AS species, ncbi_tax_id FROM organisms_ncbi";
my $org_lookup = $dbh->selectall_hashref($org_sql , "organism_id");

print STDERR "Dumping taxonomy ...\n";
open(TAX, ">$output.taxonomy") or die "Couldn't open $output.taxonomy for writing.\n";
print TAX to_json(lookup2data($org_lookup, $org_data, 'static_taxonomy'), {ascii => 1})."\n";
close(TAX);

$dbh->disconnect;
exit;

print STDERR "Loading functions ...\n";
my $func_sql = "SELECT _id AS function_id, name AS function FROM functions";
my $func_lookup = $dbh->selectall_hashref($func_sql , "function_id");

print STDERR "Loading md5s ...\n";
my $md5_sql = "SELECT _id AS md5_id, md5 FROM md5s";
my $md5_lookup = $dbh->selectall_hashref($md5_sql , "md5_id");

open(DUMP, ">$output") or die "Couldn't open $output for writing.\n";
# rna
print STDERR "Dumping rna annotations ...\n";
my $count = 1;
$sth = $dbh->prepare("SELECT md5, id, function, organism, source FROM md5_rna WHERE tax_rank = 1");
$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $id, $func, $org, $src) = @row;
    my $data = { 'id' => $count, 'accession' => $id };
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
    my $data = { 'id' => $count, 'accession' => $id };
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
    my $data = { 'id' => $count, 'accession' => $id };
    if ($md5 && exists($md5_lookup->{$md5})) {
        map { $data->{$_} = $md5_lookup->{$md5}{$_} } keys %{$md5_lookup->{$md5}};
    }
    if ($func && exists($func_lookup->{$func})) {
        map { $data->{$_} = $func_lookup->{$func}{$_} } keys %{$func_lookup->{$func}};
    }
    if ($id && exists($ont_lookup->{$id})) {
        map { $data->{$_} = $ont_lookup->{$id}{$_} } grep { exists $ont_lookup->{$id}{$_} } ('level1', 'level2', 'level3', 'level4');
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

sub lookup2data {
    my ($lookup, $list, $id) = @_;
    my %data = map {$_, []} @$list;
    foreach my $set (values %$lookup) {
        foreach my $field (@$list) {
            my $value = exists($set->{$field}) ? $set->{$field} : undef;
            push @{$data{$field}}, $value;
        }
    }
    $data{id} = $id;
    return \%data;
}