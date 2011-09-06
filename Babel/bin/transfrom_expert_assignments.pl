#!/usr/bin/env /home/wilke/FIGdisk/bin/run_perl

use Data::Dumper;
use Carp;
use Global_Config;

use strict;
use warnings;


use FIG;
my $fig = new FIG;


my $dir = shift @ARGV;
my $out  = shift @ARGV;

unless(-d $dir){
  print STDERR "No file $dir\n";
  print STDERR "script DIR\n";
  exit;
}

my @dirs = `find $dir -type d`;


foreach my $expert_dir (@dirs){
  chomp $expert_dir;
  next if ($expert_dir eq $dir);
 
  print STDERR "MSG: Searching in $expert_dir.\n";
  my @files = `find $expert_dir -name anno.clean*`; 
  print STDERR "MSG: Found ".scalar @files." files.\n";

  my ($exp) = $expert_dir =~/([^\/]+)$/;

  next if ($exp =~ /contrib/);

  my $assertions = {};

  foreach my $file (sort @files){
    print STDERR "MSG: Reading $file\n";
    chomp $file;

 
    foreach my $line (`cat $file`) {
      chomp $line;
      my @fields = split "\t" , $line;
      if (scalar @fields > 4){
	print STDERR "ERROR(3)($file): ".$line,"\n";
      }
      if (scalar @fields > 0){
	#print STDERR "MSG: current ID " . $fields[0] ."\n";
	#print STDERR "MSG : $line \n";
	my $url = '';
	$url =  $fields[3] if ($fields[3] and $fields[3] =~/http/);
	$assertions->{ $fields[0] } = {
				       func => $fields[1] ? $fields[1] : '',
				       url  => $url ,
				       expert => $exp,
				       md5  => $fig->md5_of_peg($fields[0]) || '',
				      };
	
      }
      else{
	print STDERR "ERROR(0)($file): $line \n";
      }
	     
    }
  }
  foreach my $id (keys %$assertions){
    my $peg = $assertions->{$id};
    print "$id\t".$peg->{func}."\t".$peg->{md5}."\t".$peg->{expert}."\t".$peg->{url}."\n";
  }

}


exit;

# $/ = "\n//\n";
# open(NEW,">$out") || die "bad";
# foreach $_ (`cat $file`)
# {
#     if ($_ =~ /^(\S+)\t[^\t]+\t([^\n]+)\n(.*)/s)
#     {
# 	$xxx = $1;
# 	$peg = $2;
# 	$exp = $3;
# 	$func= $4;
# 	$url = $5;
# 	$md5 = $fig->md5_of_peg($peg);
# 	print "$peg\t$who\t$ts\t$md5\n$txt";
#     }
# }
