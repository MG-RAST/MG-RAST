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
my $dbname  = "mgrast_ach_prod";
my $dbhost  = "kursk-3.mcs.anl.gov";
my $dbuser  = "mgrastprod";

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

print STDERR "Loading DB data ... " if ($verbose);
my ($ncbi_org, $other_org) = &get_organism_maps($dbh);
my ($prot_src, $rna_src) = &get_source_maps($dbh);
print STDERR " Done\n" if ($verbose);

open(OUTF, ">$outfile") || die "Can not open $outfile: $!\n";
foreach my $src_set ((['protein', $prot_src], ['rna', $rna_src])) {
  my ($type, $src_map) = @$src_set;
  print STDERR "Processing $type md5s.\n" if ($verbose);
  while ( my ($sid, $sname) = each %$src_map) {
    print STDERR "\t$sname ... " if ($verbose);
    my $only_one = 0;
    my $has_max  = 0;
    my $random   = 0;
    my $no_taxid = 0;
    my $org_num = {};
    my $md5_org = {};
    my $query   = "select distinct md5, organism from md5_$type".(($sname =~ /^M5(NR|RNA)$/) ? "" : " where source = $sid");
    my $db_rows = $dbh->prepare($query);
    $db_rows->execute();
    
    while (my @row = $db_rows->fetchrow_array) {
      push @{ $md5_org->{$row[0]} }, $row[1];
      $org_num->{$row[1]} += 1;
    }
    
    while ( my ($md5, $orgs) = each %$md5_org) {
      # if only one, use it
      if (scalar($orgs) == 1) {
	my $oname = exists($ncbi_org->{$orgs->[0]}) ? $ncbi_org->{$orgs->[0]} : $other_org->{$orgs->[0]};
	print OUTF join("\t", ($md5, $oname, $sname))."\n";
	$only_one += 1;
      }
      # get ncbi set or other set sorted by abundance
      else {
	my @org_set = map { [$ncbi_org->{$_}, $org_num->{$_}] } grep {exists $ncbi_org->{$_}} @$orgs;
	if (@org_set == 0) {
	  @org_set = map { [$other_org->{$_}, $org_num->{$_}] } grep {exists $other_org->{$_}} @$orgs;
	  $no_taxid += 1;
	}
	next if (@org_set == 0);
	@org_set = sort { $b->[1] <=> $a->[1] } @org_set;
	my $max  = $org_set[0][1];
	my @top  = map { $_->[0] } grep { $_->[1] == $max } @org_set;
	# if we have a top one, use
	if (@top == 1) {
	  print OUTF join("\t", ($md5, $top[0], $sname))."\n";
	  $has_max += 1;
	}
	# randomly choose
	else {
	  my $rand_index = int( rand(scalar(@top)) );
	  print OUTF join("\t", ($md5, $top[$rand_index], $sname))."\n";
	  $random += 1;
	}
      }
    }
    print STDERR "total: ".($only_one+$has_max+$random)." ($no_taxid no taxid), only one: $only_one, has max: $has_max, random: $random\n" if ($verbose);
  }
}
close OUTF;
print STDERR "Done processing sources.\n" if ($verbose);

if ($load_db) {
  print STDERR "Creating table md5_organism_unique ... " if ($verbose);
  $dbh->do("DROP TABLE IF EXISTS md5_organism_unique");
  $dbh->do("CREATE TABLE md5_organism_unique (md5 char(32) NOT NULL, organism text, source text);");
  $dbh->commit;
  print STDERR "Done.\n" if ($verbose);

  print STDERR "Loading data to md5_organism_unique ... " if ($verbose);
  $dbh->do("COPY md5_organism_unique FROM '$outfile'");
  $dbh->commit;
  print STDERR "Done.\n" if ($verbose);

  print STDERR "Creating indexes for md5_organism_unique ... " if ($verbose);
  $dbh->do("CREATE INDEX md5_organism_unique_key ON md5_organism_unique (md5, source);");
  $dbh->commit;
  print STDERR "Done.\n" if ($verbose);
}

sub get_organism_maps {
  my ($dbh) = @_;

  my $ncbi  = {};
  my $other = {};
  my $rows  = $dbh->selectall_arrayref("select _id, name, ncbi_tax_id from organisms_ncbi");
  if ($rows && (@$rows > 0)) {
    foreach my $r (@$rows) {
      if ($r->[2]) { $ncbi->{$r->[0]} = $r->[1]; }
      else         { $other->{$r->[0]} = $r->[1]; }
    }
  }
  return ($ncbi, $other);
}

sub get_source_maps {
  my ($dbh) = @_;

  my $prots = {};
  my $rnas  = {};
  my $rows  = $dbh->selectall_arrayref("select _id, name, type from sources");
  if ($rows && (@$rows > 0)) {
    foreach my $r (@$rows) {
      if ($r->[2] eq 'protein') { $prots->{$r->[0]} = $r->[1]; }
      elsif ($r->[2] eq 'rna')  { $rnas->{$r->[0]} = $r->[1]; }
    }
  }
  $prots->{M5NR} = 'M5NR';
  $rnas->{M5RNA} = 'M5RNA';
  return ($prots, $rnas);
}
