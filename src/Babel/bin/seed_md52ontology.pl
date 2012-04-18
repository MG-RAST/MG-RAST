#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

my $usage = "seed_md52ontology.pl [--verbose] --ss_file subsystems_file [ss,step1,step2,role] --md5_file md52id2func_file [md5,id,func,org,source] --dir_out DIR\n";
my $sfile = '';
my $mfile = '';
my $odir  = '';
my $verb  = '';

if ( ! GetOptions("ss_file=s" => \$sfile, "md5_file=s" => \$mfile, "dir_out=s" => \$odir, "verbose!" => \$verb) ) {
  print STDERR $usage; exit;
}
unless ($sfile && (-s $sfile) && $mfile && (-s $mfile) && (-d $odir)) {
  print STDERR $usage; exit;
}

my $out_ss   = "$odir/SEED.id2subsystems";
my $out_ont  = "$odir/SEED.md52id2ont";
my $id_role  = [];
my $func_md5 = {};
my $count    = 1;

print STDERR "Parsing $sfile ... " if ($verb);
open(SFILE, "<$sfile") || die "Can not open $sfile $!";
open(OUTSS, ">$out_ss") || die "Can not open $out_ss $!";
while (my $line = <SFILE>) {
  chomp $line;
  my ($ss, $step1, $step2, $role) = split(/\t/, $line);
  my $num = $count =~ /\d/g;
  my $id  = "SS" . "0" x (5 - $num) . $count;
  print OUTSS "$step1\t$step2\t$ss\t$role\t$id\n";
  if ($role && $id) { push @$id_role, [$id, $role, quotemeta($role)]; }
  $count += 1;
}
close SFILE;
close OUTSS;
print STDERR "Done - " . scalar(@$id_role) . " subsystems loaded\n" if ($verb);

print STDERR "Parsing $mfile ... " if ($verb);
open(MFILE, "<$mfile") || die "Can not open $mfile $!";
while (my $line = <MFILE>) {
  chomp $line;
  my ($md5, $id, $func, $org, $source) = split(/\t/, $line);
  if ($md5 && $func) { $func_md5->{$func}->{$md5} = 1; }
}
close MFILE;
print STDERR "Done - " . scalar(keys %$func_md5) . " functions loaded\n" if ($verb);

$count = 0;
print STDERR "Matching roles to functions ... " if ($verb);
open(OUTONT, ">$out_ont") || die "Can not open $out_ont $!";
foreach my $func (keys %$func_md5) {
  foreach my $set (@$id_role) {
    my ($id, $role, $qrole) = @$set;
    if ($func =~ /$qrole/) {
      foreach my $md5 (keys %{$func_md5->{$func}}) {
	$count += 1;
	print OUTONT join("\t", ($md5, $id, $role, 'Subsystems')) . "\n";
      }
    }
  }
}
close OUTONT;
print STDERR "Done - $count md5 - subsystems found\n" if ($verb);
