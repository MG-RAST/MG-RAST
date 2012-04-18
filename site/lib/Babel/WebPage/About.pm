package Babel::WebPage::About;



use strict;
use warnings;

use base qw( WebPage );

1;


sub init {
  my $self = shift;
  $self->title("Annotation Clearing House - About");
}

# commented out frontend to search by keywords

sub output {
  my ($self) = @_;

  my $cgi = $self->app->cgi;

  my $UNIPROT_FILES = $self->load_file_list("/vol/biodb/processed_data/for_build_ach/current/UniProt");
  my $KEGG_FILES    = $self->load_file_list("/vol/biodb/processed_data/for_build_ach/current/KEGG");
  my $IMG_FILES     = $self->load_file_list("/vol/biodb/processed_data/for_build_ach/current/IMG");
  my $SEED_FILES     = $self->load_file_list("/vol/biodb/processed_data/for_build_ach/current/SEED");
  my $NCBI_FILES     = $self->load_file_list("/vol/biodb/processed_data/for_build_ach/current/NCBI");

  my $content = "<h1>Annotation Clearing House</h1>";
  $content .= "<ol>";
  # table of content for the page
  $content .= "<li><a href='#intro'>Introduction</a></li>";
  $content .= "<li><a href='#intro'>Non redundant database</a></li>";

  $content = "<h2>ACH</h2>";
 

  $content = "<h2>NR content</h2>";
  $content .= "



<h3>Uniprot Package</h3>
<p>
Data from uniprot has been downloaded March 6.
The download url is ftp.uniprot.org//pub/databases/uniprot/current_release/knowledgebase/complete 
</p>
<p>Following files from uniprot has been used to build the NR
</p>

$UNIPROT_FILES


<h3>KEGG Package</h3>

<p>Data from KEGG has been downloaded March 8.</br>
Download URLs are ftp://ftp.genome.ad.jp/pub/kegg/release/current/ and  ftp://ftp.genome.ad.jp/pub/kegg</p>

<p>
Following files from KEGG has been used to build the NR
</p>
<p>
$KEGG_FILES
</p>

<h3>IMG Package</h3>
<p>
Data from IMG has been downloaded June 01. </br>
The fasta files have been downloaded via http://img.jgi.doe.gov/cgi-bin/pub/main.cgi?section=TaxonDetail&downloadTaxonFaaFile=1&taxon_oid=\$TAXON_OID&_noHeader=1
<p>
Following files from IMG has been used to build the NR
</p><p>
$IMG_FILES
</p>

<h3>SEED Package</h3>
<p>
SEED Data has been used from March 01.
</p><p>
$SEED_FILES
</p>
";


  return $content;
}





sub load_file_list{
  my ($self , $path) = @_;
  my $content = "";
  if (-d $path){
    $content = $path;
    my $file = $path . "/files4md5_build";
    if (-f $file){

      $content = "<table><tr><th>Files</th><th>Timestamp</th><tr>\n";
      open(FILE , $file) or die "Can't open $file\n";
      my $header = <FILE>;
      $header .= <FILE>;
      while (my $line = <FILE>){
	chomp $line;
	my ($f , $d) = split "\t" , $line;
	$content .= "<tr><td>$f</td><td>$d</td></tr>\n";
      }
      $content .= "</table>\n";
      close(FILE);

    }
    else{
      $content .= "<p>No file $file</p>";
    }
  }
  else{
    $content = "No path to summary file";
  }

  return $content;
}
