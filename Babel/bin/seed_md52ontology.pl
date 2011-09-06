#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

my $usage = "seed_md52ontology.pl [--verbose] --ontology subsystems_file --md52id2func md52id2func_file\n";
my $ofile = '';
my $mfile = '';
my $verb  = '';

if ( ! GetOptions("ontology=s" => \$ofile, "md52id2func=s" => \$mfile, "verbose!" => \$verb) ) {
  print STDERR $usage; exit;
}
unless ($ofile && (-s $ofile) && $mfile && (-s $mfile)) {
  print STDERR $usage; exit;
}

my $id_role = [];
print STDERR "Parsing $ofile ... " if ($verb);
open(OFILE, "<$ofile") || die "Can not open $ofile $!";
while (my $line = <OFILE>) {
  chomp $line;
  my ($step1, $step2, $ss, $role, $id) = split(/\t/, $line);
  if ($role && $id) { push @$id_role, [$id, $role, quotemeta($role)]; }
}
close OFILE;
print STDERR "Done - " . scalar(@$id_role) . " subsystems loaded\n" if ($verb);

my $func_md5 = {};
print STDERR "Parsing $mfile ... " if ($verb);
open(MFILE, "<$mfile") || die "Can not open $mfile $!";
while (my $line = <MFILE>) {
  chomp $line;
  my ($md5, $id, $func, $org, $source) = split(/\t/, $line);

  if ($md5 && $func) { $func_md5->{$func}->{$md5} = 1; }
}
close MFILE;
print STDERR "Done - " . scalar(keys %$func_md5) . " functions loaded\n" if ($verb);

my $count = 0;
print STDERR "Matching roles to functions ... " if ($verb);
foreach my $func (keys %$func_md5) {
  foreach my $set (@$id_role) {
    my ($id, $role, $qrole) = @$set;
    if ($func =~ /$qrole/) {
      foreach my $md5 (keys %{$func_md5->{$func}}) {
	$count += 1;
	print STDOUT join("\t", ($md5, $id, $role, 'Subsystems')) . "\n";
      }
    }
  }
}
close MFILE;
print STDERR "Done - $count md5 - subsystems found\n" if ($verb);
