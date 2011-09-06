use strict;
use warnings;
use vars qw($opt_f $opt_d $opt_t $opt_s);
use Getopt::Std;
use Digest::MD5;
#use Bio::SearchIO;
  


getopts('f:d:t:s:');

# opt_t target directory
# opt_d destination directory

my @files;
my $destination_dir = $opt_d || "/tmp/";
my $source = $opt_s || '';

# parameter check 

unless (-d $destination_dir){
    print STDERR "No destination directory $destination_dir\n";
    exit;
}

if ($opt_t and -d $opt_t){

    my @list =`find $opt_d -name fasta`;
    foreach my $var (@list){
	chomp $var;
	push  @files, $var;
    }
    print STDERR join "\n" , @files , "\n";

}
elsif($opt_f and -f $opt_f){
    
    push @files , $opt_f;
}



# read files
my $id_hash = {};
$id_hash = read_fasta( $id_hash , @files);

exit;

print STDERR "Writing md5 to id\n";
open (TMP , ">/tmp/md52id") or die "Can't open file!\n";

foreach my $md5 (keys %{$id_hash}){
    print TMP $md5."\t";
    print TMP join ";" , @{ $id_hash->{ $md5 } } ;
    print TMP "\n";
}

close (TMP);

# my $md5 = Digest::MD5::md5_hex( uc $sequence );


sub read_fasta{
    my ($hash , $files) = @_;

    my $default = $/;
   
    
    open(NR   , ">$destination_dir/md5.fasta")   or die "Can't open nr\n";
    open(FILE , ">$destination_dir/md52id2func") or die "Can't open md2id2func";

    
    open(FUNC , ">$destination_dir/assigned_functions") or die "Can't open file assigned_functions\n";
    open(ORG  , ">$destination_dir/org.table")          or die "Can't open file org.table\n";
    open(FAS  , ">$destination_dir/fasta")              or die "Can't open fasta\n";
    
    foreach my $file (@files){
		
	my ($path,$t_source) = $file =~ /([\w\/]+)\/(\w+)\/[\w\.]+$/;
	$source = $t_source unless ($source);

	print  "Reading $file\n";
	print  "$source\n$path\n";

	my $ids = {};
   
  
	open(FASTA , $file ) or die "Can't open file $file \n!";
	# set line end
	$/="\n>";

	my $count = 0;
	while(my $line = <FASTA>){
	    
	    my @entries = split "\n" , $line;
	    my $end = pop @entries;
	    my $id_line  = shift @entries;
	    my $fasta = join "" , @entries;
	   
	    next unless ($fasta);
	    my $md5 = Digest::MD5::md5_hex( uc $fasta );
	   
	  
	    my @fields = split "\t" , $id_line ;

	    my ($id , $func) = $fields[0] =~/>{0,1}([^\s]+)\s*(.*)/;
	    my ($gi)         = $fields[1] =~/\((.*)\)/;
	    my ($org)        = $fields[2] =~/\((.*)\)/;
	    #my ($org)        = $fields[2] =~/(.*)/;
	    # print join "\t" , ($id , $func , $gi || ''  , $org) , "\n";
	    unless($org){
		print STDERR "Error , no organism name\n";
		print STDERR $id_line , "\n";
		exit;
	    }
	    push @{ $hash->{ $md5 } } , $id ;

	    print FILE "$md5\t$id\t" . $func ."\t". $org ."\t$source\n";
	    
	    # for build nr
	    print FAS  ">$id\n$fasta\n";
	    print FUNC "$id\t$func\n";
	    print ORG  "$id\t$org\n";
 
	    if ( scalar @{ $hash->{ $md5 } } < 2 ) {
		print NR ">lcl|$md5\n$fasta\n";
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
    
    close(ORG);
    close(FUNC);
    close(FAS);

    $/=$default;
    return $hash;
}
