#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

my $usage = "create_eggnog_hierarchies.pl [--verbose] --func fun.txt --cat <DB>.funcat.txt --desc <DB>.description.txt > ontology\n";
my $func  = '';
my @cats  = ();
my @descs = ();
my $verb  = '';

if ( ! GetOptions("func=s" => \$func, "cat=s" => \@cats, "desc=s" => \@descs, "verbose!" => \$verb) ) {
  print STDERR $usage; exit;
}
unless ($func && (-s $func) && (@cats > 0) && (@descs > 0)) {
  print STDERR $usage; exit;
}

my $id_desc = {};
my $id_cat = {};
my $funcs = {};
my $top = '';

print STDERR "Parsing $func ... " if ($verb);
open(FUNC, "<$func") || die "Can not open $func $!";
while (my $line = <FUNC>) {
  next unless ($line && ($line =~ /\S/));
  chomp $line;
  if ($line =~ /^\S/) {
    $top = $line;
    next;
  }
  elsif ($line =~ /^\s+\[([A-Z])\]\s+(\S.*)/) {
    next unless ($top);
    my ($code, $lev2) = ($1, $2);
    $lev2 =~ s/\s+$//;
    $funcs->{$code} = [$top, $lev2];
  }
}
close FUNC;
print STDERR "Done\n" if ($verb);

foreach my $cfile (@cats) {
  print STDERR "Parsing $cfile ... " if ($verb);
  open(CFILE, "<$cfile") || die "Can not open $cfile $!";
  while (my $line = <CFILE>) {
    chomp $line;
    my ($id, $cat) = split(/\t/, $line);
    $id_cat->{$id} = $cat;
  }
  close CFILE;
  print STDERR "Done\n" if ($verb);
}

foreach my $dfile (@descs) {
  print STDERR "Parsing $dfile ... " if ($verb);
  open(DFILE, "<$dfile") || die "Can not open $dfile $!";
  while (my $line = <DFILE>) {
    chomp $line;
    my ($id, $desc) = split(/\t/, $line);
    $desc = $desc ? $desc : 'Function unknown';
    $id_desc->{$id} = $desc;
  }
  close DFILE;
  print STDERR "Done\n" if ($verb);
}

foreach my $id (sort keys %$id_cat) {
  if (exists($funcs->{$id_cat->{$id}}) && exists($id_desc->{$id})) {
    my ($lev1, $lev2) = @{ $funcs->{$id_cat->{$id}} };
    my $lev3 = $id_desc->{$id};
    my ($db) = ($id =~ /^([A-Za-z]+)\d+$/);
    print STDOUT join("\t", ($lev1,$lev2,$lev3,$id,$db)) . "\n";
  }
}
print STDERR "All Done\n" if ($verb);
