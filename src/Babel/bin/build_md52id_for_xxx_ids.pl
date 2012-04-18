
use strict;
use warnings;
use vars qw($opt_f $opt_d);

use DBI;
use Digest::MD5;
use Getopt::Long;
use Data::Dumper;
use Babel;

# read in parameters
my $xxx2fasta         = '';
my $xxx2ids           = '';
my $id2function       = '';
my $source            = "SEED 018c";

GetOptions ( 'fasta=s'         => \$xxx2fasta ,
	     'xxx2ids=s'       => \$xxx2ids,
	     'id2function=s'   => \$id2function ,
	     );


my $db = "Babel";
my $dbuser =  "ach" || "root" || "ACH";
my $dbhost = "bio-data-1.mcs.anl.gov";
my $dbpass = '';
my $dbport = '';
my $dbh;

if ($dbhost)
{
    $dbh = DBI->connect("DBI:mysql:dbname=$db;host=$dbhost", $dbuser, $dbpass);
}

unless ($dbh) {
    print STDERR "Error , " , DBI->error , "\n";
}

my $babel = Babel->new( $dbh );


my $id2md5 = {};
$id2md5 = read_fasta( $id2md5 , $xxx2fasta);

my $xxx2md52fig = read_peg_synonyms($id2md5 , $xxx2ids , $babel);

exit;
print STDERR "Writing md5 to id\n";
open (TMP , ">/tmp/md52id") or die "Can't open file!\n";

foreach my $id (keys %{$id2md5}){
    print TMP $id."\t";
    print TMP join ";" , $id2md5->{ $id }  ;
    print TMP "\n";
}

close (TMP);

# my $md5 = Digest::MD5::md5_hex( uc $sequence );


sub read_fasta{
  my ($hash , $file) = @_;
    
  my $default = $/;
  
  open(FASTA , $file ) or die "Can't open file $file \n!";
  # set line end
  $/=">";
  
  my $count = 0;
  while(my $line = <FASTA>){
    my @entries = split "\n" , $line;
    my $end = pop @entries;
    my $id  = shift @entries;
    my $fasta = join "" , @entries;
    next unless ($fasta);
    
    
    
    my $md5 = Digest::MD5::md5_hex( uc $fasta );
    # print "new\t$id\t$md5\n";
    $hash->{ $id } = $md5 ;
    
    # print FILE "$md5\t$id\t\t\t$source\n";
    # print "$md5\t$id\t\t\t$source\n";
    
    if ( $hash->{ $id }  ) {
      # print NR ">lcl|$md5\n$fasta\n";
    } 
    $count++;
    # exit if ($count > 3);
  }
  
  
  close(FASTA);
    
  # set line end back to default
  $/=$default;

  return $hash;
}


sub read_peg_synonyms{
  my ($id2md5 , $file , $babel) = @_;
  

  open(FILE , $file ) or die "Can't open file $file \n!";
  
  while (my $line = <FILE>){
    chomp $line ;

    my ($xxxLength , $ids) = split "\t" , $line ;
    my (@figs) = $ids =~/(fig\|\d+\.\d+\.peg\.\d+)/gc ;
    my ($xxx , $length) = split "," , $xxxLength ;
      
    foreach my $fig (@figs){
      foreach my $response (  @{ $babel->id2function_organism($fig) } ) {
	print join "\t" , $xxx , $id2md5->{$xxx}  , @$response , "\n";
      }
    }
  }
  
  close FILE;
}
