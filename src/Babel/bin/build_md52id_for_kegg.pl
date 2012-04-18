# -*- perl -*-
#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
# 
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License. 
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#


use FIG;

use Cwd;
use Carp;
use Data::Dumper;
use File::Path;
use Digest::MD5;
use Getopt::Std;
use File::stat;
use Time::localtime;
use warnings;
use strict;

use vars qw($opt_i $opt_o $opt_e $opt_a);
getopts('i:o:ea');

my $indir  = $opt_i ;
my $outdir = $opt_o ; 

my $time = time;

open(LOG,  ">$outdir/files4md5_build." . get_timestamp($time) ) || die "can't open log file";
# start log file
print LOG "Files\tTimestamp\n"; 
print LOG "-----\t---------\n";


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ... Extract genome information ...
#-----------------------------------------------------------------------
print STDERR "Extracting genome-name information ...\n";

if (-s "$indir/genome.gz")
{
    open(GENOME, "gunzip -c $indir/genome |") || die "could not read-open $indir/genome";

    my $fs = stat("$indir/genome.gz");
    print LOG "genome.gz\t" . ctime($fs->mtime) , "\n";

}
elsif (-s "$indir/genome")
{
    open(GENOME, "<$indir/genome") || die "could not read-open $indir/genome";
    
    my $fs = stat("$indir/genome");
    print LOG "genome\t" . ctime($fs->mtime) , "\n";

}
else
{
    die "Could not find either $indir/genome.gz or $indir/genome";
}

$/ = "\n///\n";

my %abbrev_of;
my %full_name_of;

while (defined( my $record = <GENOME>))
{
    chomp $record;
    my %parse = map { m/^(\S+)\s+(.*)$/so; $1 => $2 } split( /\n\b/, $record );
    
    if (defined($parse{ENTRY}) && defined($parse{NAME}) && defined($parse{DEFINITION}))
    {
	my $abbrev      =  $parse{ENTRY};
	$parse{NAME} =~ m/^([^,\s]+)/;
	my $short_name  =  $1;
	my $full_name   =  $parse{DEFINITION};
	$full_name   =~ s/[\s\n]+/ /gso;
	
	$abbrev_of{$short_name}    = $abbrev;
	$full_name_of{$short_name} = $full_name;
    }
    else
    {
	die "Could not parse record $.:\n$record";
    }
}
close(GENOME);
$/ = "\n";


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ... Extract sequence information ...
#-----------------------------------------------------------------------
print STDERR "Extracting sequence information ...\n";

if (-s "$indir/genes.tar.gz")
{

    my $fs = stat("$indir/genes.tar.gz");
    print LOG "genes.tar.gz\t" . ctime($fs->mtime) , "\n";

    if ($ENV{VERBOSE}) {
	open(GENES, "tar -xzvf $indir/genes.tar.gz -O |")  || die "could not pipe-open $indir/genes.tar.gz";
    } else {
	open(GENES, "tar -xzf  $indir/genes.tar.gz -O |")  || die "could not pipe-open $indir/genes.tar.gz";
    }
}
elsif (-s "$indir/genes.tar") {

    my $fs = stat("$indir/genes.tar");
    print LOG "genes.tar\t" . ctime($fs->mtime) , "\n";


    if ($ENV{VERBOSE}) {
	open(GENES,  "tar -xvf $indir/genes.tar -O |")  || die "could not pipe-open $indir/genes.tar";
    } else {
	open(GENES,  "tar -xf  $indir/genes.tar -O |")  || die "could not pipe-open $indir/genes.tar";
    }
}
else
{
    die "Could not find either '$indir/genes.tar.gz' or '$indir/genes.tar.gz'";
}

open(FASTA, ">$outdir/fasta")
    || die "could not write-open $outdir/fasta";
open(FUNC,  ">$outdir/assigned_functions")
    || die "could not write-open $outdir/assigned_functions";
open(ORGS,  ">$outdir/org.table")
    || die "could not write-open $outdir/org.table";
open(MD5, ">$outdir/md52id2func") || die "could not open $outdir/md52id2func";
open(FAS, ">$outdir/md5.fasta")   || die "could not open $outdir/md5.fasta";



close LOG;
my $md5_hash = {};

$/ = "\n///\n";
while (defined(my $record = <GENES>))
{
    chomp $record;
    my %parse = map { m/^(\S+)\s+(.*)$/so; $1 => $2 } split( /\n\b/, $record );
    
    my $gene_id    = "";
    my $short_name = "";

    if ($parse{ENTRY} =~ m/^(\S+)\s+CDS\s+(.*)$/o) {
	($gene_id, $short_name) = ($1, $2);
	print STDERR "die", "For record $., org $short_name was not in 'genomes' file; record:$record\n\t" 
	    unless defined($abbrev_of{$short_name});
    } else {
	print STDERR "Skipping non-CDS ENTRY field: $parse{ENTRY}\n" if (defined($ENV{VERBOSE}) && ($ENV{VERBOSE} > 1));
	next;
    }
    
    
    my $gene_name = "";
    if (defined($parse{NAME}))
    {
	if ($parse{NAME} =~ m/^(.*)$/so) {
	    $gene_name =  $1;
	    $gene_name =~ s/[\s\n]+/ /gso;
	} else {
	    die "For record $., org $short_name, could not parse NAME field $parse{NAME} in record:$record\n\t";
	}
    }

    my $func = "";
    if (defined($parse{DEFINITION}))
    {
	if ($parse{DEFINITION} =~ m/^(.*)$/mso) {
	    $func = $1;
	    $func =~ s/\s+$//so;
	    $func =~ s/\s+/ /gso;
	} else {
	    die "For record $., org $short_name, could not parse DEFINITION field $parse{DEFINITION} in record:$record\n\t";
	}
    }
    
    my $cluster   = "";
    my $clustfunc = "";

    if (defined($parse{ORTHOLOG}))
    {
	if ($parse{ORTHOLOG} =~ m/^KO:\s+(\S+)\s+(.*)$/so) {
	    ($cluster, $clustfunc) = ($1, $2);
	} else {
	    die "For record $., org $short_name, could not parse ORTHOLOG field $parse{ORTHOLOG} in record:$record\n\t";
	}
    }

    my $seq = "";
    if ($parse{AASEQ} =~ m/^\d+\s+(.*)$/so)
    {
	$seq =  $1;
	$seq =~ s/[\s\n]//gso;
	$seq =~ s/[^ARNDCQEGHILKMFPSTWYUVBZX]/x/igo;   #...Change invalid chars to 'x's.
    }
    else
    {
	print STDERR "For record $., org $short_name, skipping apparent pseudogene, name='$parse{NAME}', func='$parse{DEFINITION}' (no AASEQ); record:\n$record\n";
	next;
    }
    
    my $kegg_id = "kegg|$abbrev_of{$short_name}:$gene_id";
    my $id      = "$abbrev_of{$short_name}:$gene_id";
    &FIG::display_id_and_seq($kegg_id, \$seq, \*FASTA);

    my $md5 = Digest::MD5::md5_hex( uc $seq );
           
    unless ( $md5_hash->{ $md5 } ){
	print FAS ">lcl|$md5\n$seq\n";
    }
    $md5_hash->{ $md5 } = 1;

    print MD5 "$md5\t$id\t$func\t$full_name_of{$short_name}\tKEGG\n";
    print FUNC "$kegg_id\t$func\n";
    print ORGS "$kegg_id\t$full_name_of{$short_name}\n";
}
close(GENES) || die "Could not close pipe from genes.tar or genes.tar.gz";

exit(0);







sub get_timestamp {
  my ($string) = @_;
  
  my $lt = localtime($string);
  my $year  = $lt->year + 1900;
  my $month = $lt->mon  + 1;
  my $day   = $lt->mday;
  
  my $time_stamp = $year ;
  if ($month < 10) { $time_stamp .= "0$month"}
  else { $time_stamp .= $month }
  if ($day < 10) { $time_stamp .= "0$day"}
  else { $time_stamp .= $day }
  
  return  $time_stamp || "unknown" ;
}
