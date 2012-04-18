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
my $id_hash     = {};
my $source_hash = {};

$id_hash = read_fasta( $id_hash , @files , $source_hash);
open(SOURCES , ">$destination_dir/sources") or die "Can't open file sources\n";
foreach my $s (keys %$source_hash){
  print SOURCES "$s\t" . $source_hash->{$s} . "\n";
}
close(SOURCES);

# my $md5 = Digest::MD5::md5_hex( uc $sequence );


sub read_fasta{
    my ($hash , $files , $source_hash) = @_;

    my $default = $/;
   
    
    open(NR   , ">$destination_dir/md5.fasta")   or die "Can't open nr\n";
    open(FILE , ">$destination_dir/md52id2func") or die "Can't open md2id2func";

    
    open(FUNC , ">$destination_dir/assigned_functions") or die "Can't open file assigned_functions\n";
    open(ORG  , ">$destination_dir/org.table")          or die "Can't open file org.table\n";
    open(FAS  , ">$destination_dir/fasta")              or die "Can't open fasta\n";
    open(ALL  , ">$destination_dir/$source.faa")        or die "Can't open $source.faa\n";
    open(GI  , ">$destination_dir/gi2id")               or die "Can't open gi2id\n";
    
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
	    
	    my @lines = split "\n" , $line;
	    my $end = pop @lines;
	    my $id_line  = shift @lines;
	    my $fasta = join "" , @lines;
	   
	    next unless ($fasta);
	    my $md5 = Digest::MD5::md5_hex( uc $fasta );
	    my @entries;
	    if ($id_line =~/>/){
		@entries = split ">gi" , $id_line ;
	    }
	    else{
		push @entries , $id_line ;
	    }

	    unless ($hash->{ $md5 }) { $hash->{ $md5 } = 0} ;

	    # print STDERR $id_line , "\n\n";

	    foreach my $entry (@entries){
 
		next unless ($entry);

		my ($gi , $source , $id) = $entry =~/^g{0,1}i{0,1}\|(\d+)\|(\w+)\|([^\s]+)/;
		
		my ($func , $org) = $entry =~/[^\s]+\s([^\[]+)\[?([^\]\[]*)\]?/;

		print GI    "$gi\t$source|$id\n";

		my @ids = split  /\|/ , $id ;
		push @ids , $gi ;
		
		#print STDERR "$gi \t $source \t @ids \t $func \t $org\n";
		
		$source_hash->{$source}++;
	     
		
		unless($org){
		    # print STDERR "Error , no organism name\n";
		    # print STDERR $id_line , "\n";
		    $org = "organism not parsed/found in ncbi nr"
	  
		}
		unless ($gi){
		    print STDERR "No GI:\t$entry\n";
		    next;
		}
		unless ($id){
		    print STDERR "No ID:\t$entry\n";
		    next;
		}
		
		# next if ($id =~/^sp/);

	

		foreach my $id (@ids){
		  
		  print FILE "$md5\t$id\t" . $func ."\t". $org ."\t$source\n";
		
		  # for build nr
		  my $prefix = $source ;
		  $prefix = "gi" if ($id =~/^(\d+)$/);
		  print ALL    ">$prefix|$id\t$func\t$org\n$fasta\n";
		  print FAS    ">$prefix|$id\n$fasta\n";
		  print FUNC   "$prefix|$id\t$func\n";
		  print ORG    "$prefix|$id\t$org\n";
		}
		
		unless ( $hash->{ $md5 }   ) {
		  print NR ">lcl|$md5\n$fasta\n";
		  $hash->{ $md5 }++;
		  } 
		$count++;
		#exit if ($count > 3);
	    }
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
