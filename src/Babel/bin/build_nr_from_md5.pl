
use strict;
use warnings;
use vars qw($opt_f $opt_d $opt_o);
use Getopt::Std;
use Digest::MD5;
#use Bio::SearchIO;
  


getopts('f:d:o:');

my @files;

if ($opt_d and -d $opt_d){

    my @list =`find $opt_d -name "*md5.fasta"`;
    foreach my $var (@list){
	chomp $var;
	push  @files, $var;
    }
    print STDERR join "\n" , @files , "\n";

}
elsif($opt_f and -f $opt_f){
    
    push @files , $opt_f;
}

$opt_o = "/tmp/" unless ($opt_o);


my $id_hash = {};

$id_hash = read_fasta( $id_hash , @files);

# my $md5 = Digest::MD5::md5_hex( uc $sequence );


sub read_fasta{
    my ($hash , $files) = @_;

    my $default = $/;
   
    
    open(NR , ">$opt_o/nr") or die "Can't open nr\n";


    foreach my $file (@files){

	my ($path,$source) = $file =~ /([\w\/]+)\/(\w+)\/[\w\.]+$/;
	print  "Reading $file\n";
	print  "$source\n$path\n";
	# next unless ($source=~/NCBI/);
	my $ids = {};

   
  
	open(FASTA , $file ) or die "Can't open file $file \n!";
	# set line end
	$/=">";

	my $count = 0;
	while(my $line = <FASTA>){
	    my @entries = split "\n" , $line;
	    my $end = pop @entries;
	    my $md5id  = shift @entries;
	    my $fasta = join "" , @entries;
	    next unless ($fasta);

       

	    # print "$md5id\n";
	    $hash->{ $md5id }++ ;


	    if ( $hash->{ $md5id }  < 2 ) {
		print NR ">$md5id\n$fasta\n";
	    } 
	    $count++;
	    # exit if ($count > 3);
	}
	
	
	close(FASTA);

	# set line end back to default
	$/=$default;
    }
    
    close(FILE);
    close(NR);

    $/=$default;
    return $hash;
}
