#!/usr/bin/env perl

#use lib "/home/wilke/Swissknife_1.66/lib/";
use lib "/vol/biotools/share/db_update/Swissknife/lib/";

use SWISS::Entry;
use SWISS::KW;
use SWISS::OS;
use Digest::MD5;
use Getopt::Std;
use warnings;
use strict;
use File::stat;
use Time::localtime;

use vars qw($opt_i $opt_o $opt_e $opt_a);
getopts('i:o:ea');


my ($indir , $outdir , $unzip) = check_opts($opt_i, $opt_o, $opt_e);

# use opt_a to append to outputfiles
my $write = ">";
$write  = ">>" if ($opt_a);

my @files = (  "uniprot_sprot.dat.gz" , "uniprot_trembl.dat.gz" );
my $time = time;

$outdir = "/tmp/" unless ($outdir);

open(FUNC, "$write$outdir/assigned_functions") 
    || die "could not open $outdir/assigned_functions";
open(ORG,  "$write$outdir/org.table") || die "could not open $outdir/org.ta
ble";
open(SEQ, "$write$outdir/fasta")|| die "could not open $outdir/fasta"; 
open(MD5, "$write$outdir/md52id2func")|| die "could not open $outdir/md52id2func";
open(FAS, "$write$outdir/md5.fasta") || die "can not open $outdir/md5.fasta";
open(LOG,  ">$outdir/files4md5_build." . get_timestamp($time) ) || die "can't open log file";


# start log file
print LOG "Files\tTimestamp\n"; 
print LOG "-----\t---------\n";

foreach my $input (@files){
    print $input , "\n";

    my $fs = stat("$indir/$input");
    print LOG "$input\t" . ctime($fs->mtime) , "\n";


    unless (-f "$indir/$input"){
	print STDERR "No input file $input\n";
	next;
    }

    if ($unzip){
	`gunzip -c $indir/$input > /tmp/unzip.tmp`;
	$input = "/tmp/unzip.tmp";
    }
    else{
	$input = "$indir/$input";
    }
    
# input file
    open(UNIPROT , "$input") || die "Can't open $input!\n";
    
# Read an entire record at a time
    local $/ = "\n//\n";
    
    my $md5_hash = {};

    while (my $text = <UNIPROT>){
	# Read the entry
	my $entry = SWISS::Entry->fromText($text);
	
	
	#print $entry->toFasta , "\n";
	#next;
	
	# Print the primary accession number of each entry.
	print STDERR $entry->AC, "\t" , $entry->DEs->head->text . "\n"; 
#   print $entry->OSs->head->text, "\n";
#   print $entry->DEs->text, "\n";
#   print $entry->SQ, "\n";
#   print $entry->database_code,"\n";
	my $sequence = $entry->SQ;
	my $md5 = Digest::MD5::md5_hex( uc $sequence );
	
	
	unless ( $md5_hash->{ $md5 } ){
	    print FAS ">lcl|$md5\n$sequence\n";
	}
	$md5_hash->{ $md5 } = 1;
	
	my $source = '';
	if ($entry->database_code eq "S"){
	  $source = "SwissProt";
	  print SEQ ">sp|".$entry->AC."\n"; 
	  print SEQ $entry->SQ, "\n";
	  print FUNC "sp|".$entry->AC."\t". $entry->DEs->head->text, "\n";
	  print ORG  "sp|".$entry->AC."\t". $entry->OSs->head->text, "\n";
	  print MD5 "$md5\t".$entry->AC."\t".$entry->DEs->head->text."\t".$entry->OSs->head->text."\t$source\n";
	}
	elsif  ($entry->database_code eq "?") {
	    print STDERR "Can't determine database for ", $entry->AC ,"\n";
	    print STDERR $text , "\n";
	}
	else{
	  $source = "TrEMBL";
	  print SEQ ">tr|".$entry->AC."\n";
	  print SEQ $entry->SQ, "\n";
	  print FUNC "tr|".$entry->AC."\t". $entry->DEs->head->text, "\n";
	  print ORG  "tr|".$entry->AC."\t". $entry->OSs->head->text, "\n"; 
	  print MD5 "$md5\t".$entry->AC."\t".$entry->DEs->head->text."\t".$entry->OSs->head->text."\t$source\n";
	}
	
    
 #  foreach my $key  (keys(%{$entry->OSs}) ) {
#     print $key,"\t",$entry->OSs->{$key},"\n";

#   }
#   print join " ", @{$entry->OSs->{list}} , "\n";
#   print join " ", keys(%{$entry->OSs->{list}->[0]}) , "\n";
#   foreach my $key  ( keys(%{$entry->OSs->{list}->[0]} )) {
#     print $key,"\t",$entry->OSs->{$key},"\n";
    
#   }
 #  # If the entry has a SWISS-2DPAGE crossreference
#   if ($entry->DRs->get('SWISS-2DPAGE')) {
    
#     # Add the pseudo-keyword 'Gelelectrophoresis'
#     my $kw = new SWISS::KW;
#     $kw->text('Gelelectrophoresis');
#     $entry->KWs->add($kw);
#   };
  
#   # Print all keywords
#   foreach my $kw ($entry->KWs->elements) {
#     print $kw->text, ", ";
#   }
#   print "\n";

#   # Print number and Comments for all references
#   # (courtesy of Dan Bolser)
#   foreach my $ref ($entry->Refs->elements){
#     my $rn = $ref->RN;      # Reference Number
#     print "RN:\t$rn\n"; 

#     my $rc = $ref->RC;      # Reference Comment(s)
#     foreach my $type (keys %$rc){ # Comment type
#       foreach (@{$rc->{$type}}){  # Comment text
#         print join( "\t", "RC:", $type, $_->text), "\n";
#       }
#     }
#   }

    }
    close(UNIPROT);
}





sub check_opts{
    my ($indir , $outdir , $unzip) = @_;
    
    if ( !($indir) or !(-d $indir) ){
	print STDERR "No input directory!\n";
	# exit -1;
    }
    
    if ( !($outdir) ){
	print STDERR "No output directory\n";
	exit -1;
    }
    elsif ( !(-d $outdir) ){
	print STDERR "Directory $outdir does not exists, creating dir!\n";
	mkpath("$outdir", 1, 0777) || die "Could not create $outdir\n";
    }
    
    return ($indir , $outdir , $unzip);
}

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
