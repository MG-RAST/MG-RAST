#!/usr/bin/env perl
use strict;
use warnings;

use FIG;
use Conf;

use Getopt::Long;
use Data::Dumper;

sub usage {
  print "extract_sequences.pl >>> turn an existing user into an administrator\n";
  print "extract_sequences.pl -target <target file> [-archae <include archae?>]\n";
}

# read in parameters
my $target = '';
my $archae = '';

GetOptions ( 'target=s' => \$target,
	     'archae=s' => \$archae );

unless ($target) {
  &usage();
  exit 0;
}

# get fig and dbhandle
print "getting database connection...\n";
my $fig = new FIG;
if (ref($fig)) {
  print "ok.\n";
} else {
  print "failed.\n";
  exit 0;
}
my $rdbH = $fig->db_handle;

# check if archae are to be exported as well
my $export_archae = '';
if ($archae) {
  $export_archae = " OR maindomain='Archae'";
}

# count organisms and hash org ids
my $genomes = $rdbH->SQL("SELECT genome FROM genome WHERE maindomain='Bacteria'$export_archae");
my $genomes_hash = {};
%$genomes_hash = map { $_->[0] => 0 } @$genomes;
my $num_genomes = scalar(@$genomes);
print $num_genomes . " organisms found.\n";

# open target file
open(FH, ">$target") or die "Could not open target file for writing: $@ $!\n";

# iterate through the genomes
my $i = 1;
foreach my $id (keys(%$genomes_hash)) {

  # get all features
  print "getting features for $id ($i/$num_genomes)...\n";
  my $features = $rdbH->SQL("SELECT id, contig, minloc, maxloc FROM features WHERE genome='$id'");
  print scalar(@$features) . " features found.\n";

  # get sequence
  if (open(SEQ, $Conf::organisms."/".$id."/contigs")) {
    my $contigs = {};
    my $contig = "";
    my $cid = "";
    while (<SEQ>) {
      chomp;
      my $line = $_;
      if ($line =~ /^>/) {
	if ($cid) {
	  $contigs->{$cid} = $contig;
	  $contig = "";
	}
	$cid = substr($line, 1);
      } else {
	$contig .= $line;
      }
    }
    $contigs->{$cid} = $contig;
    close SEQ;

    # write out the features
    foreach my $feature (@$features) {
      print FH ">".$feature->[0]."\n";
      my $seq = substr($contigs->{$feature->[1]}, $feature->[2] - 1, $feature->[3] - $feature->[2] + 1);
      my $numlines = int(length($seq) / 60) + 1;
      for (my $h=0; $h<$numlines; $h++) {
	if (($h + 1) * 60 > length($seq)) {
	  if (length($seq) % 60 > 0) {
	    print FH substr($seq, $h * 60)."\n";
	  }
	} else {
	  print FH substr($seq, $h * 60, 60)."\n";
	}
      }
    }
    print "done.\n";

  } else {
    print "Could not open sequence file for $id: $@ $!\n";
  }

  $i++;
}

# close target file
close FH;

# end program
print "done.";
