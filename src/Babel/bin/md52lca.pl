#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use DBI;
use Getopt::Long;

my $usage   = "$0 [--verbose] [--load_db] --out <outfile: must be absolute path>\n";
my $verbose = 0;
my $load_db = 0;
my $outfile = '';
my $dbname  = "";
my $dbhost  = "";
my $dbuser  = "";

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions('verbose!' => \$verbose,
		  'load_db!' => \$load_db,
		  'out=s'    => \$outfile,
		  'dbname:s' => \$dbname,
		  'dbuser:s' => \$dbuser,
		  'dbhost:s' => \$dbhost
		 ) ) {
  print STDERR $usage; exit 1;
}
unless ($outfile) { print STDERR $usage; exit 1; }

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

print STDERR "Loading organism data ... " if ($verbose);
my $org_map = &get_organism_map($dbh);
print STDERR " Done\n" if ($verbose);

my $src_map = &get_source_map($dbh);
my $md5_org = $dbh->prepare("select md5,organism,source from (select distinct md5,organism,source from md5_protein union select distinct md5,organism,source from md5_rna) as x order by md5");

my $cur_md5 = '';
my $has_lca = 0;
my $all_md5 = 0;
my $no_lca  = 0;
my $primary = $src_map->{'RefSeq'};
my $prime_o = {};
my $other_o = {};

print STDERR "Calculating lca for md5s:\n" if ($verbose);
$md5_org->execute();

open(OUTF, ">$outfile") || die "Can not open $outfile: $!\n";
while (my @row = $md5_org->fetchrow_array) {
  my ($md5, $org, $src) = @row;
  
  if ($cur_md5 eq '') { $cur_md5 = $md5; }
  if ($cur_md5 ne $md5) {
    if (scalar(keys %$prime_o) > 0) {
      my @lca = &get_lca($cur_md5, $org_map, [keys %$prime_o]);
      if (@lca == 9) {
	print OUTF join ("\t", ($cur_md5, @lca)) . "\n";
	$has_lca += 1;
      } else {
	$no_lca += 1;
      }
    }
    elsif (scalar(keys %$other_o) > 0) {
      my @lca = &get_lca($cur_md5, $org_map, [keys %$other_o]);
      if (@lca == 9) {
	print OUTF join ("\t", ($cur_md5, @lca)) . "\n";
	$has_lca += 1;
      } else {
	$no_lca += 1;
      }
    }
    else {
      print STDERR join ("\t", ("No taxonomy:", $cur_md5, $all_md5)) . "\n";
    }
    $all_md5 += 1;
    $prime_o = {};
    $other_o = {};
    $cur_md5 = $md5;
  }

  if ($src == $primary) {
    $prime_o->{$org} = 1;
  } else {
    $other_o->{$org} = 1;
  }
}

if (scalar(keys %$prime_o) > 0) {
  my @lca = &get_lca($cur_md5, $org_map, [keys %$prime_o]);
  if (@lca == 9) {
    print OUTF join ("\t", ($cur_md5, @lca)) . "\n";
  }
}
elsif (scalar(keys %$other_o) > 0) {
  my @lca = &get_lca($cur_md5, $org_map, [keys %$other_o]);
  if (@lca == 9) {
    print OUTF join ("\t", ($cur_md5, @lca)) . "\n";
  }
}
close OUTF;
print STDERR "Done: processed $all_md5 md5s: $has_lca have lca, $no_lca no lca\n" if ($verbose);

if ($load_db) {
  print STDERR "Creating table md5_lca ... " if ($verbose);
  $dbh->do("DROP TABLE IF EXISTS md5_lca");
  $dbh->do("CREATE TABLE md5_lca (md5 text PRIMARY KEY, tax_domain text, tax_phylum text, tax_class text, tax_order text, tax_family text, tax_genus text, tax_species text, tax_strain text, level integer)");
  $dbh->commit;
  print STDERR "Done.\n" if ($verbose);

  print STDERR "Loading data to md5_lca ... " if ($verbose);
  $dbh->do("COPY md5_lca FROM '$outfile'");
  $dbh->commit;
  print STDERR "Done.\n" if ($verbose);
}

exit 0;

sub get_lca {
  my ($md5, $org_map, $oids) = @_;

  my $coverage = {};
  foreach my $o (@$oids) {
    if ((exists $org_map->{$o}) && ($org_map->{$o}[0]) && (@{$org_map->{$o}} == 8)) {
      my $taxa = $org_map->{$o};
      for (my $i = 0; $i < scalar(@$taxa); $i++) {
	$coverage->{$i+1}->{ $taxa->[$i] }++ if ($taxa->[$i]);
      }
    }
  }

  if ( scalar(keys %$coverage) < 8 ) {
    print STDERR "Incomplete Taxonomy:\t$md5\t" . join(",", @$oids) . "\n";
    return ();
  }
  if ( scalar(keys %{$coverage->{1}}) > 1 ) {
    print STDERR "No LCA possible:\t$md5\t" . join(",", keys %{$coverage->{1}}) . "\n";
    return ();
  }

  my @lca = ();
  my $pos = 0;
  my $max = 0;
  
  foreach my $key (sort { $a <=> $b } keys %$coverage) {
    my $num = scalar keys %{$coverage->{$key}};
    if (($num <= $max) || ($max == 0)) {
      $max = $num;
      $pos = $key;
    }
  }

  if ( scalar(keys %{$coverage->{$pos}}) == 1 ) {
    @lca = map { keys %{$coverage->{$_}} } (1 .. $pos);
    push @lca, ( map {'-'} ($pos + 1 .. 8) ) if ($pos < 8);
    push @lca, $pos;
  }
  else {
    print STDERR "LCA error ($pos):\t$md5\n";
  }
  
  return @lca;
}

sub get_organism_map {
  my ($dbh) = @_;

  my $data = {};
  my $rows = $dbh->selectall_arrayref("select _id, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name from organisms_ncbi");
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], [ @$_[1..8] ] } @$rows;
  }

  return $data;
}

sub get_source_map {
  my ($dbh) = @_;

  my $data = {};
  my $rows = $dbh->selectall_arrayref("select name, _id from sources");
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], $_->[1] } @$rows;
  }
  return $data;
}
