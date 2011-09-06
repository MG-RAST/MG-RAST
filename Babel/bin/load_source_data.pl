#!/usr/bin/env perl

use strict;
use warnings;

use Babel::lib::Babel;
use Data::Dumper;
use Getopt::Long;

my $usage = "load_source_data.pl [--verbose] --download DOWNLOAD_FILE --source SOURCE_FILE\n";
my $dfile = '';
my $sfile = '';
my $verb  = '';

if ( ! GetOptions("download=s" => \$dfile, "source=s" => \$sfile, "verbose!" => \$verb) ) {
  print STDERR $usage; exit;
}
unless ($sfile && (-s $sfile) && $dfile && (-s $dfile)) {
  print STDERR $usage; exit;
}

my $babel = new Babel::lib::Babel;
my $dbh   = $babel->dbh();
my $data  = $babel->source_info_from_file($sfile);
my $down  = $babel->download_info_from_file($dfile);
my $srcs  = $babel->sources();
my $repos = {};

foreach my $name ( keys %$srcs ) {
  if (exists $data->{$name}) {
    my $src  = exists($data->{$name}{source})      ? $data->{$name}{source}      : '';
    my $vers = exists($data->{$name}{version})     ? $data->{$name}{version}     : '';
    my $desc = exists($data->{$name}{description}) ? $data->{$name}{description} : '';
    my $titl = exists($data->{$name}{title})       ? $data->{$name}{title}       : '';
    my $url  = exists($data->{$name}{url})         ? $data->{$name}{url}         : '';
    my $type = exists($data->{$name}{type})        ? $data->{$name}{type}        : '';
    my $link = exists($data->{$name}{link})        ? $data->{$name}{link}        : '';
    my $sql  = qq(UPDATE sources SET source='$src', version='$vers', description='$desc', url='$url', type='$type', title='$titl', link='$link' WHERE name='$name');
    if ($src && $url && $type) {
      $repos->{$src} = 1;
      if ($verb) { print "$sql\n"; }
      my $res = $dbh->do($sql);
      if (! $res) { print STDERR "Error updating sources: " . $dbh->error . "\n"; }
    }
  }
  else {
    print "ERROR: $name\n";
  }
}
foreach my $name ( keys %$repos ) {
  if (exists($down->{$name}) && (scalar(@{$down->{$name}}) > 0)) {
    my (@paths, @files);
    my $date = $down->{$name}[0]{download_date};
    foreach my $d ( @{$down->{$name}} ) {
      push @paths, $d->{download_path};
      push @files, $d->{download_file};
    }
    my $path = "{" . join(",", map {qq("$_")} @paths) . "}";
    my $file = "{" . join(",", map {qq("$_")} @files) . "}";
    my $sql  = qq(UPDATE sources SET download_path='$path', download_file='$file', download_date='$date' WHERE source='$name');

    if ($verb) { print "$sql\n"; }
    my $res = $dbh->do($sql);
    if (! $res) { print STDERR "Error updating sources: " . $dbh->error . "\n"; }
  }
}

