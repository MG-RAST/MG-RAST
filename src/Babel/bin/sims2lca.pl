#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Cache::Memcached;

my $verbose  = 0;
my $simf     = '';
my $outf     = '';
my $eval_rng = 0.2;
my $fcache   = '';
my $mcache   = ''; # _ach
my $memhost  = "140.221.76.21:11211";
my $usage    = "$0 [--verbose] [--file_cache <md52lca file> || --mem_cache <key extension>] [--eval <evalue range: default '$eval_rng'>] --sims <sim file> --out <out file>\n";

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions('verbose!' => \$verbose,
		  'sims=s'   => \$simf,
		  'out=s'    => \$outf,
		  'eval:f'   => \$eval_rng,
		  'file_cache:s' => \$fcache,
		  'mem_cache:s'  => \$mcache
		 ) ) {
  print STDERR $usage; exit 1;
}
unless ($simf && $outf && (-s $simf)) { print STDERR "Missing input and/or output files:\n$usage"; exit 1; }

my ($md5_mem, $md5_file);
print STDERR time . "\n";

# load md5 lcas
if ($fcache && (-s $fcache)) {
  $md5_file = {};
  print STDERR "Loading mapping file ... " if ($verbose);
  open(FILE, "<$fcache") || die "Can't open md5 to lca mapping file $fcache: $!\n";
  while (my $line = <FILE>) {
    chomp $line;
    my ($md5, @taxa) = split(/\t/, $line);
    my $rank = pop @taxa;
    $md5_file->{$md5} = \@taxa;
  }
  close FILE;
  print STDERR "Done\n" if ($verbose);
}
elsif ($mcache) {
  $md5_mem = new Cache::Memcached {'servers' => [$memhost], 'debug' => 0, 'compress_threshold' => 10_000};
}
else {
  print STDERR "Provide one of file_cache or mem_cache:\n$usage"; exit 1;
}

my $curr = '';
my ($top_exp, @md5s, @idents, @lens, @evals);

print STDERR time . "\n";
print STDERR "Reading sims file:\n" if ($verbose);
open(SIMF, "<$simf") || die "Can't open file $simf: $!\n";
open(OUTF, ">$outf") || die "Can't open file $outf: $!\n";
while (my $line = <SIMF>) {
  chomp $line;
  my ($fid,$md5,$ident,$len,undef,undef,undef,undef,undef,undef,$eval,$score) = split(/\t/, $line);

  if ($eval =~ /^(\d\.\d)e([-+])(\d+)$/) {
    my ($int, $pos, $exp) = ($1, $2, $3);
    my $is_zero = (($int eq '0.0') && ($exp eq '00')) ? 1 : 0;
    $exp = $is_zero ? 0 : ($pos eq '-') ? -1 * $exp : $exp;
    next if (($pos eq '+') && (! $is_zero));
    next if ((! $fid) || (! $line));

    if (! defined $top_exp) { $top_exp = $exp; }
    if ($curr eq '')   { $curr = $fid; }
    if ($curr ne $fid) {
      # get lca for md5s
      if (@md5s > 0) {
	my @taxa = &taxa_for_md5s(\@md5s);
	my @lca  = &get_lca($curr, \@taxa);
	if (@lca == 9) {
	  print OUTF join("\t", ($curr, join(";",@md5s), join(";",@idents), join(";",@lens), join(";",@evals), join(";",@lca))) . "\n";
	}
      }
      # reset variables
      $curr    = $fid;
      $top_exp = $exp;
      @md5s    = ();
      @idents  = ();
      @lens    = ();
      @evals   = ();
    }
    # add data
    if (($top_exp == 0) || ($exp < $top_exp)) {
      $top_exp = $exp;
    }
    elsif ($exp <= ($top_exp - ($top_exp * $eval_rng))) {
      next;
    }
    push @md5s  , $md5;
    push @idents, $ident;
    push @lens  , $len;
    push @evals , $exp;
  }
}

if (@md5s > 0) {
  my @taxa = &taxa_for_md5s(\@md5s);
  my @lca  = &get_lca($curr, \@taxa);
  if (@lca == 9) {
    print OUTF join("\t", ($curr, join(",",@md5s), join(",",@idents), join(",",@lens), join(",",@evals), @lca)) . "\n";
  }
}
close OUTF;
print STDERR "Done\n" if ($verbose);
print STDERR time . "\n";

exit 0;

sub taxa_for_md5s {
  my ($md5s) = @_;

  my @taxa = ();
  if ($md5_file && ref($md5_file)) {
    @taxa = map { $md5_file->{$_} } grep { exists $md5_file->{$_} } @$md5s;
  }
  elsif ($md5_mem && ref($md5_mem)) {
    my @keys = map { $_ . $mcache } @$md5s;
    my $data = $md5_mem->get_multi(@keys);
    if ($data && ref($data)) {
      @taxa = map { $data->{$_}{lca} } grep { exists $data->{$_}{lca} } @keys;
    }
  }
  return @taxa;
}

sub get_lca {
  my ($frag, $taxa) = @_;
  
  my $coverage = {};
  foreach my $t (@$taxa) {
    for (my $i = 0; $i < scalar(@$t); $i++) {
      $coverage->{$i+1}->{ $t->[$i] }++ if ($t->[$i]);
    }
  }

  if ( scalar(keys %$coverage) < 8 ) {
    print STDERR "Incomplete Taxonomy:\t$frag\t" . join("\t", map { join(";", @$_) } @$taxa) . "\n";
    return ();
  }
  if ( scalar(keys %{$coverage->{1}}) > 1 ) {
    print STDERR "No LCA possible:\t$frag\t" . join("\t", keys %{$coverage->{1}}) . "\n";
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
    print STDERR "LCA error ($pos)\t$frag\n";
  }
  
  return @lca;
}
