#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON;
use DBI;

my $output  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $usage   = qq($0
  --output  dump files prefix
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
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

if (! $output) {
    print STDERR $usage; exit 1;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

print STDERR "Loading ontologies ...\n";
my $ontol = $dbh->selectall_arrayref("SELECT s.name, o.id, o.level1, o.level2, o.level3, o.level4 FROM ontologies o, sources s WHERE o.source = s._id");
print STDERR "Dumping ontologies ...\n";
open(ODUMPA, ">$output.ontology.all") or die "Couldn't open $output.ontology.all for writing.\n";
open(ODUMP1, ">$output.ontology.level1") or die "Couldn't open $output.ontology.level1 for writing.\n";
open(ODUMP2, ">$output.ontology.level2") or die "Couldn't open $output.ontology.level2 for writing.\n";
open(ODUMP3, ">$output.ontology.level3") or die "Couldn't open $output.ontology.level3 for writing.\n";
open(ODUMP4, ">$output.ontology.level4") or die "Couldn't open $output.ontology.level4 for writing.\n";
foreach my $row (@$ontol) {
    my @ont = ();
    foreach my $o (@$row) {
        $o = $o || "";
        $o =~ s/\"/\\"/g;
        push @ont, $o;
    }
    print ODUMPA join(",", map { '"'.$_.'"' } @ont)."\n";
    if ($ont[2]) { print ODUMP1 join(",", map { '"'.$_.'"' } ($ont[0], $ont[2], $ont[1]))."\n"; }
    if ($ont[3]) { print ODUMP2 join(",", map { '"'.$_.'"' } ($ont[0], $ont[3], $ont[1]))."\n"; }
    if ($ont[4]) { print ODUMP3 join(",", map { '"'.$_.'"' } ($ont[0], $ont[4], $ont[1]))."\n"; }
    if ($ont[5]) { print ODUMP4 join(",", map { '"'.$_.'"' } ($ont[0], $ont[5], $ont[1]))."\n"; }
}
close(ODUMPA);
close(ODUMP1);
close(ODUMP2);
close(ODUMP3);
close(ODUMP4);

print STDERR "Loading taxonomy ...\n";
my $taxa = $dbh->selectall_arrayref("SELECT name, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, ncbi_tax_id FROM organisms_ncbi");
print STDERR "Dumping taxonomy ...\n";
open(TDUMPA, ">$output.taxonomy.all") or die "Couldn't open $output.ontology.all for writing.\n";
open(TDUMP1, ">$output.taxonomy.domain") or die "Couldn't open $output.taxonomy.domain for writing.\n";
open(TDUMP2, ">$output.taxonomy.phylum") or die "Couldn't open $output.taxonomy.phylum for writing.\n";
open(TDUMP3, ">$output.taxonomy.class") or die "Couldn't open $output.taxonomy.class for writing.\n";
open(TDUMP4, ">$output.taxonomy.order") or die "Couldn't open $output.taxonomy.order for writing.\n";
open(TDUMP5, ">$output.taxonomy.family") or die "Couldn't open $output.taxonomy.family for writing.\n";
open(TDUMP6, ">$output.taxonomy.genus") or die "Couldn't open $output.taxonomy.genus for writing.\n";
open(TDUMP7, ">$output.taxonomy.species") or die "Couldn't open $output.taxonomy.species for writing.\n";
foreach my $row (@$taxa) {
    my @tax = ();
    foreach my $t (@$row) {
        $t = $t || "";
        $t =~ s/\"/\\"/g;
        push @tax, $t;
    }
    print TDUMPA join(",", map { '"'.$_.'"' } @tax)."\n";
    if ($tax[1]) { print TDUMP1 join(",", map { '"'.$_.'"' } ($tax[1], $tax[0]))."\n"; }
    if ($tax[2]) { print TDUMP2 join(",", map { '"'.$_.'"' } ($tax[2], $tax[0]))."\n"; }
    if ($tax[3]) { print TDUMP3 join(",", map { '"'.$_.'"' } ($tax[3], $tax[0]))."\n"; }
    if ($tax[4]) { print TDUMP4 join(",", map { '"'.$_.'"' } ($tax[4], $tax[0]))."\n"; }
    if ($tax[5]) { print TDUMP5 join(",", map { '"'.$_.'"' } ($tax[5], $tax[0]))."\n"; }
    if ($tax[6]) { print TDUMP6 join(",", map { '"'.$_.'"' } ($tax[6], $tax[0]))."\n"; }
    if ($tax[7]) { print TDUMP7 join(",", map { '"'.$_.'"' } ($tax[7], $tax[0]))."\n"; }
}
close(TDUMPA);
close(TDUMP1);
close(TDUMP2);
close(TDUMP3);
close(TDUMP4);
close(TDUMP5);
close(TDUMP6);
close(TDUMP7);

print STDERR "Loading protein md5s ...\n";
my $pmd5s = $dbh->selectcol_arrayref("SELECT DISTINCT md5 FROM md5_protein");

print STDERR "Loading rna md5s ...\n";
my $rmd5s = $dbh->selectcol_arrayref("SELECT DISTINCT md5 FROM md5_rna");

print STDERR "Loading ontology md5s ...\n";
my $omd5s = $dbh->selectcol_arrayref("SELECT DISTINCT md5 FROM md5_ontology");

print STDERR "Loading md5s with single organism ...\n";
my $uquery  = "SELECT DISTINCT m.md5, o.name FROM md5_organism_unique u, md5s m, organisms_ncbi o WHERE u.md5 = m._id AND u.organism = o._id";
my %md5_org = map { $_->[0], $_->[1] } @{ $dbh->selectall_arrayref($uquery) };

print STDERR "Loading md5s with lca string ...\n";
my $lquery  = "SELECT md5, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, tax_strain FROM md5_lca";
my %md5_lca = map { $_->[0], [$_->[1], $_->[2], $_->[3], $_->[4], $_->[5], $_->[6], $_->[7], $_->[8]] } @{ $dbh->selectall_arrayref($lquery) };

open(IDUMP, ">$output.annotation.id") or die "Couldn't open $output.annotation.id for writing.\n";
open(MDUMP, ">$output.annotation.md5") or die "Couldn't open $output.annotation.md5 for writing.\n";

print STDERR "Dumping protein data ...\n";
foreach my $md5 (@$pmd5s) {
    my $data = $dbh->selectall_arrayref("SELECT DISTINCT m._id, s.source, a.id, f.name, o.name FROM md5_protein a INNER JOIN md5s m ON a.md5 = m.md5 LEFT OUTER JOIN functions f ON a.function = f._id LEFT OUTER JOIN organisms_ncbi o ON a.organism = o._id LEFT OUTER JOIN sources s ON a.source = s._id where a.md5='$md5'");
    next unless ($data && @$data);
    my $mid  = $data->[0][0];
    my $srcs = {};
    my $uniq = $md5_org{$md5} || "";
    $uniq =~ s/\"/\\"/g;
    my @lca = $md5_lca{$md5} || ();
    @lca = map { $_ =~ s/\'/''/g } @lca;
    my $lca = "[".join(",", map { "'".$_."'" } @lca)."]";
    $lca =~ s/\"/\\"/g;
    foreach my $d (@$data) {
        # source => [[ accession, function, organism ]]
        push @{$srcs->{$d->[1]}}, [ $d->[2], $d->[3], $d->[4] ];
    }
    foreach my $src (keys %$srcs) {
        my @acc = map { $_->[0] =~ s/\'/''/g } @{$srcs->{$src}};
        my @fun = map { $_->[1] =~ s/\'/''/g } @{$srcs->{$src}};
        my @org = map { $_->[2] =~ s/\'/''/g } @{$srcs->{$src}};
        my $acc = "[".join(",", map { "'".$_."'" } @acc)."]";
        my $fun = "[".join(",", map { "'".$_."'" } @fun)."]";
        my $org = "[".join(",", map { "'".$_."'" } @org)."]";
        $acc =~ s/\"/\\"/g;
        $fun =~ s/\"/\\"/g;
        $org =~ s/\"/\\"/g;
        print IDUMP join(",", map { '"'.$_.'"' } ($mid, $src, $md5, "true", $uniq, $lca, $acc, $fun, $org))."\n";
        print MDUMP join(",", map { '"'.$_.'"' } ($md5, $src, "true", $uniq, $lca, $acc, $fun, $org))."\n";
    }
}

print STDERR "Dumping rna data ...\n";
foreach my $md5 (@$rmd5s) {
    my $data = $dbh->selectall_arrayref("SELECT DISTINCT m._id, s.source, a.id, f.name, o.name FROM md5_rna a INNER JOIN md5s m ON a.md5 = m.md5 LEFT OUTER JOIN functions f ON a.function = f._id LEFT OUTER JOIN organisms_ncbi o ON a.organism = o._id LEFT OUTER JOIN sources s ON a.source = s._id where a.md5='$md5'");
    next unless ($data && @$data);
    my $mid  = $data->[0][0];
    my $srcs = {};
    my $uniq = $md5_org{$md5} || "";
    $uniq =~ s/\"/\\"/g;
    my @lca = $md5_lca{$md5} || ();
    @lca = map { $_ =~ s/\'/''/g } @lca;
    my $lca = "[".join(",", map { "'".$_."'" } @lca)."]";
    $lca =~ s/\"/\\"/g;
    foreach my $d (@$data) {
        # source => [[ accession, function, organism ]]
        push @{$srcs->{$d->[1]}}, [ $d->[2], $d->[3], $d->[4] ];
    }
    foreach my $src (keys %$srcs) {
        my @acc = map { $_->[0] =~ s/\'/''/g } @{$srcs->{$src}};
        my @fun = map { $_->[1] =~ s/\'/''/g } @{$srcs->{$src}};
        my @org = map { $_->[2] =~ s/\'/''/g } @{$srcs->{$src}};
        my $acc = "[".join(",", map { "'".$_."'" } @acc)."]";
        my $fun = "[".join(",", map { "'".$_."'" } @fun)."]";
        my $org = "[".join(",", map { "'".$_."'" } @org)."]";
        $acc =~ s/\"/\\"/g;
        $fun =~ s/\"/\\"/g;
        $org =~ s/\"/\\"/g;
        print IDUMP join("", map { '"'.$_.'"' } ($mid, $src, $md5, "false", $uniq, $lca, $acc, $fun, $org))."\n";
        print MDUMP join("", map { '"'.$_.'"' } ($md5, $src, "false", $uniq, $lca, $acc, $fun, $org))."\n";
    }
}

print STDERR "Dumping ontology data ...\n";
foreach my $md5 (@$omd5s) {
    my $data = $dbh->selectall_arrayref("SELECT DISTINCT m._id, s.source, a.id, f.name FROM md5_ontology a INNER JOIN md5s m ON a.md5 = m.md5 LEFT OUTER JOIN functions f ON a.function = f._id LEFT OUTER JOIN sources s ON a.source = s._id where a.md5='$md5'");
    next unless ($data && @$data);
    my $mid  = $data->[0][0];
    my $srcs = {};
    foreach my $d (@$data) {
        # source => [[ accession, function ]]
        push @{$srcs->{$d->[1]}}, [ $d->[2], $d->[3] ];
    }
    foreach my $src (keys %$srcs) {
        next if ($src eq 'GO');
        my @acc = map { $_->[0] =~ s/\'/''/g } @{$srcs->{$src}};
        my @fun = map { $_->[1] =~ s/\'/''/g } @{$srcs->{$src}};
        my $acc = "[".join(",", map { "'".$_."'" } @acc)."]";
        my $fun = "[".join(",", map { "'".$_."'" } @fun)."]";
        $acc =~ s/\"/\\"/g;
        $fun =~ s/\"/\\"/g;
        print IDUMP join(",", map { '"'.$_.'"' } ($mid, $src, $md5, "true", "", "[]", $acc, $fun, ""))."\n";
        print MDUMP join(",", map { '"'.$_.'"' } ($md5, $src, "true", "", "[]", $acc, $fun. ""))."\n";
    }
}

close(IDUMP);
close(MDUMP);
$dbh->disconnect;
