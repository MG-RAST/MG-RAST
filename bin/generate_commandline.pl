#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

sub usage {
  print "generate_commandline.pl >>> create API commandline scripts\n";
  print "generate_commandline.pl -template <template file name> -config <configuration file name> [ -outdir <output directory> ]\n"; 
}

my $template = '';
my $outdir = '';
my $config = '';

GetOptions ( 'template=s' => \$template,
	     'config=s' => \$config,
             'outdir=s' => \$outdir );

unless ($template && $config) {
  &usage();
  exit 0;
}

my $t = [];
if (open(FH, "<$template")) {
  while (<FH>) {
    chomp;
    push(@$t, $_);
  }
  close FH;
  $t = join("###", @$t);
} else {
  print "could not open template file '$template': $@\n";
  exit;
}

my $data = {};
if (open(FH, "<$config")) {
  my $curr = undef;
  while (<FH>) {
    chomp;
    my ($key, $val) = split /\t/;
    next unless ($key && $val);
    next if ($key =~ /^#/);
    if ($key eq 'resource') {
      $curr = $val;
      $data->{$curr} = { resource => $val };
    } else {
      $data->{$curr}->{$key} = $val;
    }
  }
  close FH;

  foreach my $key (keys(%$data)) {
    next if ($key eq "default");
    my $currt = $t;
    foreach my $k (keys(%{$data->{$key}})) {
      my $v = $data->{$key}->{$k};
      $currt =~ s/##$k##/$v/g;
    }
    if (exists($data->{default})) {
      foreach my $k (keys(%{$data->{default}})) {
	my $v = $data->{default}->{$k};
	$currt =~ s/##$k##/$v/g;
      }
    }
    my @rows = split(/###/, $currt);
    if (open(FH, ">$outdir/$key")) {
      foreach my $row (@rows) {
	print FH $row."\n";
      }
      close FH;
    } else {
      print "could not open script file for output '$outdir/$key': $@\n";
      exit;
    }
  }
} else {
  print "could not open config file '$config': $@\n";
  exit;
}

print "all done.\nHave a nice day :)\n\n";
