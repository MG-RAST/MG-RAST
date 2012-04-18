#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Cache::Memcached;

my $verbose = 0;
my $lcaf    = '';
my $md5f    = '';
my $mapf    = '';
my $select  = '';
my $memkey  = '_ach';
my $memhost = "kursk-1.mcs.anl.gov:11211";
my $options = { md5      => 1,
		function => 1,
		organism => 1,
		source   => 1
	      };

my $usage = "$0 [--verbose] --mem_host <server address: default '$memhost'> --mem_key <key extension: default '$memkey'> --lca <lca file> --md5 <md5 data file> --map <annotation mapping file> --option <input type: " . join("|", keys %$options) . ">\n";
$usage   .= "lca file (unique md5s):\tmd5, domain, phylum, class, order, family, genus, species, name, level\n";
$usage   .= "md5 file (sorted md5s):\tmd5, source, organism, function\n";
$usage   .= "map file:\tinteger id, text name, optional\n";

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions('verbose!'   => \$verbose,
		  'lca:s'      => \$lcaf,
		  'md5:s'      => \$md5f,
		  'map:s'      => \$mapf,
		  'option=s'   => \$select,
		  'mem_host:s' => \$memhost,
		  'mem_key:s'  => \$memkey
		 ) ) {
  print STDERR $usage; exit 1;
}
unless (exists $options->{$select}) {
  print STDERR "Unknown option $select.\n$usage"; exit 1;
}

my $num = 0;
my $mem_cache = new Cache::Memcached {'servers' => [$memhost], 'debug' => 0, 'compress_threshold' => 10_000};

unless ($mem_cache && ref($mem_cache)) { print STDERR "Unable to connect to memcache:\n$usage"; exit 1; }

if (($select eq 'md5') && $lcaf && $md5f && (-s $lcaf) && (-s $md5f)) {
  my $md5_data = {};
  my $curr = '';
  my $data = {};

  print STDERR "Parsing lca file ... " if ($verbose);
  open(LCAF, "<$lcaf") || die "Can't open file $lcaf: $!\n";
  while (my $line = <LCAF>) {
    chomp $line;
    $num += 1;
    my ($md5, @taxa) = split(/\t/, $line);
    my $rank = pop @taxa;
    $md5_data->{$md5}->{lca} = \@taxa;
  }
  close LCAF;
  print STDERR "Done parsing $num md5s\n" if ($verbose);
  
  $num = 0;
  print STDERR "Parsing md5 file / adding to memcache ... " if ($verbose);
  open(MD5F, "<$md5f") || die "Can't open file $md5f: $!\n";
  while (my $line = <MD5F>) {
    chomp $line;
    my ($md5, $src, $func, $org) = split(/\t/, $line);
    
    # initial
    if ($curr eq '') {
      $curr = $md5;
      $data = (exists $md5_data->{$md5}) ? $md5_data->{$md5} : {};
    }
    # next chunk
    if ($curr ne $md5) {
      my $key = $curr . $memkey;
      $mem_cache->set($key, $data, undef); # no experiation
      
      # reset
      delete $md5_data->{$curr};
      $curr = $md5;
      $data = (exists $md5_data->{$md5}) ? $md5_data->{$md5} : {};
      $num += 1;
    }
    # add data
    push @{ $data->{$src}->{$func} }, $org;
  }
  close MD5F;
  print STDERR "Done parsing / adding $num md5s\n" if ($verbose);
  
  $num = 0;
  print STDERR "Adding missing to memcache ... " if ($verbose);
  foreach my $md5 (keys %$md5_data) {
    $num += 1;
    my $key = $md5 . $memkey;
    $mem_cache->set($key, $md5_data->{$md5}, undef); # no experiation
  }
  print STDERR "Done adding $num md5s\n" if ($verbose);
}
elsif (($select ne 'md5') && $mapf && (-s $mapf)) {
  my $map_data = {};

  print STDERR "Parsing $select map file ... " if ($verbose);
  open(MAPF, "<$mapf") || die "Can't open file $mapf: $!\n";
  while (my $line = <MAPF>) {
    chomp $line;
    $num += 1;
    my ($id, $name, $other) = split(/\t/, $line);
    if (($select eq 'organism') || ($select eq 'source')) {
      $other =~ s/\\N//;
      $map_data->{$id} = [ $name, $other ];
    } else {
      $map_data->{$id} = $name;
    }
  }
  close MAPF;
  print STDERR "Done parsing $num $select\n" if ($verbose);

  print STDERR "Adding to memcache ... " if ($verbose);
  my $key = $select . $memkey;
  $mem_cache->set($key, $map_data, undef); # no experiation
  print STDERR "Done\n" if ($verbose);
}
else {
  print STDERR "Missing input file(s):\n$usage"; exit 1;
}
