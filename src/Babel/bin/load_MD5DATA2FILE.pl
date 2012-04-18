#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use XML::Simple;
use Getopt::Long;

my $verbose   = 0;
my @datafile  = ();
my @aliasfile = ();
my $src_file  = '';
my $out_dir   = '';

my $data_tbl   = "ach_data";
my $org_tbl    = "ach_organisms";
my $contig_tbl = "ach_contigs";
my $func_tbl   = "ach_functions";
my $alias_tbl  = "ach_aliases";
my $source_tbl = "ach_sources";
my $id_ctg_tbl = "ach_id2contig";
my $count_tbl  = "ach_counts";

my $usage = qq(
DESCRIPTION: (load_MD5DATA2FILE)
Create tab-sperated files for loading as tables in ACH db.
Files created:
   $data_tbl
   $org_tbl
   $contig_tbl
   $func_tbl
   $alias_tbl
   $source_tbl
   $id_ctg_tbl
   $count_tbl

USAGE:
  --datafile   source_data   Required. This may be multiple files by calling the option multiple times.
                             Main data file: md5, id, function, organism, source, beg_pos*, end_pos*, strand*, contig_id*, contig_desc*, contig_length*
  --aliasfile  source_alias  Optional. This may be multiple files by calling the option multiple times.
                             Alias data file: id, alias1, [alias2, alias3, ...]
  --source     source_info   Optional. xml file with additional source information.
  --outdir     ouput_dir     Optional. Dir path to place data files. Defualt is current dir.
  --verbose                  Optional. Verbose output.

);
if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! &GetOptions ('verbose!'    => \$verbose, 
		    'datafile=s'  => \@datafile,
		    'aliasfile=s' => \@aliasfile,
		    'source:s'    => \$src_file,
		    'outdir:s'    => \$out_dir
		   ) )
  { print STDERR $usage; exit; }

if (@datafile == 0) { print STDERR $usage; exit; }
if ($out_dir)       { $out_dir .= '/'; }

my $sources = ($src_file && (-s $src_file)) ? XMLin($src_file, ContentKey => '-content') : {};

my $alias_num = 1;
if ($verbose) { print STDERR "\nPrinting table $alias_tbl ... \n"; }
open(ALIAS, ">${out_dir}$alias_tbl") || die "Can't open file ${out_dir}$alias_tbl\n";
foreach my $afile (@aliasfile) {
  open(AFILE, "<$afile") || die "Can't open file $afile\n";
  if ($verbose) { print STDERR "Parsing $afile ... \n"; }

  while (my $line = <AFILE>) {
    chomp $line;
    my ($id, @aliases) = split(/\t/, $line);
    foreach (@aliases) {
      if ($_ =~ /^(\S+?):(\S+)$/) {
	print ALIAS "$alias_num\t$id\t$2\t$1\n";
	$alias_num += 1;
	unless ($alias_num % 2000000) {
	  if ($verbose) { print STDERR "$alias_num:\t$id , $2 , $1\n"; }
	}
      }
    }
  }
  close AFILE;
}
close ALIAS;

my $id_ids     = {};
my $md5_ids    = {};
my $org_ids    = {};
my $ctg_ids    = {};
my $func_ids   = {};
my $src_ids    = {};

my $data_num   = 1;
my $org_num    = 1;
my $ctg_num    = 1;
my $func_num   = 1;
my $src_num    = 1;
my $id_ctg_num = 1;

my ($orgID, $ctgID, $funcID, $srcID);

if ($verbose) { print STDERR "\nPrinting tables $data_tbl, $id_ctg_tbl ... \n"; }
open(DATA, ">${out_dir}$data_tbl") || die "Can't open file ${out_dir}$data_tbl\n";
open(ID2CTG, ">${out_dir}$id_ctg_tbl") || die "Can't open file ${out_dir}$id_ctg_tbl\n";

foreach my $dfile (@datafile) {
  open(DFILE, "<$dfile") || die "Can't open file $dfile\n";
  if ($verbose) { print STDERR "Parsing $dfile ... \n"; }
  
  while (my $line = <DFILE>) {
    chomp $line;
    my ($md5, $id, $func, $org, $source, $beg, $end, $strand, $ctg_id, $ctg_desc, $len) = split(/\t/, $line);

    unless ($md5 && $id) { next; }
    $id_ids->{$id}   = 1;
    $md5_ids->{$md5} = 1;
    
    if ($source) {
      if (exists $src_ids->{$source}) {
	$srcID = $src_ids->{$source}[0];
	$src_ids->{$source}[1]{$id}  = 1;
	$src_ids->{$source}[2]{$md5} = 1;
      } else {
	$srcID = $src_num;
	# source counts: id, md5, org, contig, func
	$src_ids->{$source} = [$src_num, {}, {}, {}, {}, {}];
	$src_num += 1;
      }
    } else {
      $srcID = "\\N";
    }

    if ($org) {
      $org =~ s/\\//g;
      $org =~ s/'/\\'/g;
      if (exists $org_ids->{$org}) {
	$orgID = $org_ids->{$org};
      } else {
	$orgID = $org_num;
	$org_ids->{$org} = $org_num;
	$org_num += 1;
      }
      $src_ids->{$source}[3]{$org} = 1;
    } else {
      $orgID = "\\N";
    }
    
    if (defined($beg) && defined($end) && $strand && $ctg_id && $ctg_desc && $len) {
      $ctg_id   =~ s/\\//g;
      $ctg_id   =~ s/'/\\'/g;
      $ctg_desc =~ s/\\//g;
      $ctg_desc =~ s/'/\\'/g;
      if (exists $ctg_ids->{$ctg_id}) {
	$ctgID = $ctg_ids->{$ctg_id}[0];
      } else {
	$ctgID = $ctg_num;
	$ctg_ids->{$ctg_id} = [$ctg_num, $ctg_desc, $len, $orgID];
	$ctg_num += 1;
      }
      print ID2CTG "$id_ctg_num\t$data_num\t$ctgID\t$strand\t$beg\t$end\n";
      $id_ctg_num += 1;
      $src_ids->{$source}[4]{$ctg_id} = 1;
    }

    if ($func) {
      $func =~ s/\\//g;
      $func =~ s/'/\\'/g;
      if (exists $func_ids->{$func}) {
	$funcID = $func_ids->{$func};
      } else {
	$funcID = $func_num;
	$func_ids->{$func} = $func_num;
	$func_num += 1;
      }
      $src_ids->{$source}[5]{$func} = 1;
    } else {
      $func = "\\N";
    }

    print DATA "$data_num\t$md5\t$id\t$funcID\t$srcID\t$orgID\t\\N\n";
    $data_num += 1;
    unless ($data_num % 1000000) {
      if ($verbose) { print STDERR "$data_num:\t$md5 , $id , $func , $org , $source\n"; }
    }
  }
  close DFILE;
}
close ID2CTG;
close DATA;

if ($verbose) { print STDERR "\nPrinting table $count_tbl ... \n"; }
my @counts = ( "ids\t" . scalar(keys %$id_ids), "md5s\t" . scalar(keys %$md5_ids),
	       "organisms\t" . ($org_num-1), "contigs" . ($ctg_num-1), "functions" . ($func_num-1), "sources" . ($src_num-1) );
open(COUNT, ">${out_dir}$count_tbl") || die "Can't open file ${out_dir}$count_tbl\n";
print COUNT join("\n", @counts) . "\n";
close COUNT;

if ($verbose) { print STDERR "\nPrinting table $org_tbl ... \n"; }
open(ORG, ">${out_dir}$org_tbl") || die "Can't open file ${out_dir}$org_tbl\n";
foreach (sort {$org_ids->{$a} <=> $org_ids->{$b}} keys %$org_ids) {
  print ORG $org_ids->{$_} . "\t$_" . ("\t\\N" x 11) . "\n";
}
close ORG;

if ($verbose) { print STDERR "\nPrinting table $contig_tbl ... \n"; }
open(CONTIG, ">${out_dir}$contig_tbl") || die "Can't open file ${out_dir}$contig_tbl\n";
foreach (sort {$ctg_ids->{$a}[0] <=> $ctg_ids->{$b}[0]} keys %$ctg_ids) {
  print CONTIG join( "\t", ($ctg_ids->{$_}[0], $_, @{$ctg_ids->{$_}}[1,2,3] )) . "\n";
}
close CONTIG;

if ($verbose) { print STDERR "\nPrinting table $func_tbl ... \n"; }
open(FUNC, ">${out_dir}$func_tbl") || die "Can't open file ${out_dir}$func_tbl\n";
foreach (sort {$func_ids->{$a} <=> $func_ids->{$b}} keys %$func_ids) {
  print FUNC $func_ids->{$_} . "\t$_\n";
}
close FUNC;

if ($verbose) { print STDERR "\nPrinting table $source_tbl ... \n"; }
open(SOURCE, ">${out_dir}$source_tbl") || die "Can't open file ${out_dir}$source_tbl\n";
foreach (sort {$src_ids->{$a}[0] <=> $src_ids->{$b}[0]} keys %$src_ids) {
  my @src_row = ( $src_ids->{$_}[0], $_ );
  if (exists $sources->{'names'}->{$_}) {
    my $src = $sources->{'names'}->{$_};
    push @src_row, $src, $sources->{'sources'}->{$src}->{'type'}, $sources->{'sources'}->{$src}->{'url'}, "\\N", "\\N";
  } else {
    push @src_row, "\\N", "\\N", "\\N", "\\N", "\\N";
  }  
  print SOURCE join("\t", @src_row) . "\t" . join("\t", map {scalar(keys %$_)} @{$src_ids->{$_}}[1,2,3,4,5]) . "\n";
}
close SOURCE;

if ($verbose) { print STDERR "Done.\n"; }
