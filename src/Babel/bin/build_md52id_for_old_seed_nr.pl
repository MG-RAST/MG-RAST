use strict;
use warnings;
use vars qw($opt_f $opt_d $opt_t $opt_s);

use Digest::MD5;
#use Bio::SearchIO;
  

use Getopt::Long;

my $key               = "";
my $seed_nr           = "";
my $seed_peg_synonyms = "";
my $destination_dir   = "/tmp/";

# opt_t target directory
# opt_d destination directory

GetOptions ( 'key=s'         => \$key ,
	     'nr=s'          => \$seed_nr ,
	     'synonyms=s'    => \$seed_peg_synonyms,
	     'destination=s' => \$destination_dir,
	   );

my @files;

my $source = "SEED2Subsystems_018c";

# parameter check 

unless (-d $destination_dir){
    print STDERR "No destination directory $destination_dir\n";
    exit;
}

# read mapping
my $xxx2seed = {} ;
open(FILE , $seed_peg_synonyms) or die "Can't open file $seed_peg_synonyms!\n";
while (my $line = <FILE>){
  # print $line;
  chomp $line;
  my ($xxx_string , $id_string) = split "\t" , $line;
  my ($xxx , $xxx_length)       = split ","  , $xxx_string;

  my @ids  = split ";" , $id_string ;
  my @figs = $id_string =~ /(fig\|\d+\.\d+\.peg\.\d+)/gc; 
  # print $xxx , "\t" , (join "\t" , @figs)  , "\n";
  $xxx2seed->{ $xxx } = \@figs ;
  if ($xxx eq "xxx00257445" ){
    print join "\t" , ("FIGS:: " , @figs , "\n") ;
  }
}

    
push @files , $seed_nr;




# read files
my $id_hash = {};
$id_hash = read_fasta( $id_hash , @files , $xxx2seed );

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
    my ($hash , $files , $xxx2seed ) = @_;

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
	    print "IDs " , join "\t" , ($id , $func , $gi || ''  , $org) , "\n";
	    print "Fig: " , (join "\t" , $id , @ { $xxx2seed->{ $id } }  ) , "\n" ;
	    unless($org){
	      $org  = 'NA' ;
	      $func = 'NA' ; 
	    }

	    push @{ $hash->{ $md5 } } , @{ $xxx2seed->{ $id } }  ;

	    foreach my $fid ( @{ $xxx2seed->{ $id } }) {
	      print FILE "$md5\t$fid\t" . $func ."\t". $org ."\t$source\n";
	      
	      # for build nr
	      print FAS  ">$fid\n$fasta\n";
	      print FUNC "$fid\t$func\n";
	      print ORG  "$fid\t$org\n";
	      
	      if ( scalar @{ $hash->{ $md5 } } < 2 ) {
		print NR ">lcl|$md5\n$fasta\n";
	      } 
	      $count++;
	      # exit if ($count > 3);
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
