
use strict;
use warnings;
use vars qw($opt_f $opt_d $opt_t);
use Getopt::Std;
use Digest::MD5;
use Bio::SearchIO;
use File::stat;
use Time::localtime;  


getopts('f:d:t:');

my @files;
my $target_dir = $opt_t || "/tmp/";

if ($opt_d and -d $opt_d){

    my @list =`find $opt_d -name "*.fa"`;
    foreach my $var (@list){
	chomp $var;
	push  @files, $var;
    }
    print STDERR join "\n" , @files , "\n";

}
elsif($opt_f and -f $opt_f){
    
    push @files , $opt_f;
}


# exit;

my $id_hash = {};

$id_hash = read_fasta( $id_hash , @files);

print STDERR "Writing md5 to id\n";
open (TMP , ">$target_dir/md52id") or die "Can't open file $target_dir/md52id!\n";

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
   
    my $time = time;
    
    open(NR   , ">$target_dir/md5.fasta") or die "Can't open $target_dir/md5.fasta\n";
    open(FILE , ">$target_dir/md52id2func") or die "Can't open md2id2func";
    open(LOG  , ">$target_dir/files4md5_build." . get_timestamp($time) ) or die "can't open log file";


    # start log file
    print LOG "Files\tTimestamp\n"; 
    print LOG "-----\t---------\n";

    foreach my $file (@files){


	my $id_file = $file ;
	$id_file =~ s/\.fa$/.txt/;
	
	my $fs = stat("$file");
	my ($fname) = $file =~ /IMG\/\d+\/(.+\.fa)/;
	print LOG "$fname\t" . ctime($fs->mtime) , "\n";


	my ($path,$source) = $file =~ /([\w\/]+)\/(\w+)\/[\w\.]+$/;
	my $org = `cut -f1 $path/$source/META`;
	chomp $org;

	print  "Reading $file\n";
	print  "$source\n$path\n";
	print "Id file $id_file\n";
	print "Organism $org\n";

	my $imgIDs = {};
	open (IDS , $id_file) or die "Can't open file $id_file";
	while (my $line = <IDS>){
	    chomp $line;
	    my @fields = split "\t" , $line;
	    # print $fields[0] , "\t" , $fields[5] , "\t" , $fields[7] , "\t" , $fields[9] || " " , "\n";
	    $imgIDs->{ $fields[0] } = { locus       => $fields[5] ,
					description => $fields[7],
					img_annot   => $fields[9] || "",
				    };
	}

     
	$source = "IMG";
	# next unless ($source=~/NCBI/);
       


   
  
	open(FASTA , $file ) or die "Can't open file $file \n!";
	# set line end
	$/=">";

	my $count = 0;
	while(my $line = <FASTA>){

	    my %ids;
	    my @entries = split "\n" , $line;
	    my $end = pop @entries;
	    my $id_line  = shift @entries;
	    next unless ($id_line);
	    my ($img_id , $id) = $id_line =~/^>?([^\s]+)\s+([^\s]+)/;
	    my $fasta = join "" , @entries;
	    next unless ($fasta);

	    
	    my $func  = $imgIDs->{$img_id}->{description} || "";
	    my $locus = $imgIDs->{$img_id}->{locus} || "";

	    $ids{$locus}  = 1;
	    $ids{$img_id} = 1;
	    $ids{$id}     = 1;

	    my $md5 = Digest::MD5::md5_hex( uc $fasta );
	    # print $id_line , "\n";
	    # print "new\t'$img_id'\t$id\t$locus\t$func\t$org\n";
	    push @{ $hash->{ $md5 } } , $id ;

	    foreach my $i (keys %ids){
		print FILE "$md5\t$i\t$func\t$org\t$source\n";
	    }
	    
	    unless ($img_id and $func and $org){
		print STDERR "$id_line\n";
		# next;
	    }
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

    $/=$default;
    return $hash;
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
