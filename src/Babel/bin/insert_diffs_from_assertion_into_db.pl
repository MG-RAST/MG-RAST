#!/usr/bin/env /home/wilke/FIGdisk/bin/run_perl

use Data::Dumper;
use Carp;
use Conf;
use FIG;
use strict;
use warnings;


my $fig = new FIG;

my $in = shift @ARGV;
my $out  = shift @ARGV;

unless(-f $in){
  print STDERR "No file $in\n";
  print STDERR "script diff_file\n";
  exit;
}


open (FILE , "$in") or die "Can not open file $in!";

my $corr = {};
print STDERR "Reading file $in.\n";
my $status = '';
while( <FILE> ){
  chomp $_;  
  my ($md5 , $fa, $fb) = split "\t"  , $_;

  next unless($fa);
  next unless($fb);

  my ($a , $b) = sort ( $fa , $fb);
  if ($corr->{$a}->{$b} and $corr->{$a}->{$b} ne $status){
    print STDERR "DIFF\t$a\t$b\t$status\t".$corr->{$a}->{$b}."\n";
  }
  elsif($corr->{$a}->{$b} and $corr->{$a}->{$b} eq $status){
    print STDERR "SAME\t$a\t$b\t$status\t".$corr->{$a}->{$b}."\n";
  }

  else{
    $corr->{$a}->{$b} = $status;
  }
 
}
print STDERR "Writing correspondences.\n";


my $rdbH = $fig->db_handle;



foreach my $a (keys %$corr){
    foreach my $b (keys %{ $corr->{$a} }){

	my $ea = &encode($a);
	my $eb = &encode($b);

	my $statement = "select function1 , function2 from ACH_Correspondence where function1='$ea' and function2='$eb';";
	# print STDERR $statement , "\n";
	my $relational_db_response = $rdbH->SQL($statement);
	if (@$relational_db_response) {
	    print "$a\t$b\tin db\n";
	}
	else{
	    #    print  join("\t",@$tuple),"\n";
	    $rdbH->SQL("INSERT INTO ACH_Correspondence (function1 , function2 , status) VALUES ('$ea','$eb','')");
	    print "$a\t$b\t".$corr->{$a}->{$b}."\n";
	}
    }
}




exit;



sub encode {
    my($x) = @_;

    $x =~ s/\\/\\\\/g;
    $x =~ s/\'/\\'/g;
    return $x;
}
