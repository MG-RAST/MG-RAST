package Babel::WebPage::Download;

use strict;
use warnings;

use base qw( WebPage );

use Babel::lib::Babel;
use Data::Dumper;

1;


sub init {
  my $self = shift;
  $self->title("M5nr - Download Links");
}


sub output {
  my ($self) = @_;
 
  my $content = qq~
<h2>Download source data and code for the M5nr</h2>
<p><ul>
  <li><a target=_blank href='ftp://ftp.mg-rast.org/data/M5nr'>M5nr FTP site</a></li>
  <li><a target=_blank href='ftp://ftp.mg-rast.org/data/M5nr/current/M5nr.gz'>Current M5nr FASTA</a></li>
  <li><a target=_blank href='ftp://ftp.mg-rast.org/data/M5nr/current/M5nr_blast.tar'>Current M5nr NCBI-BLAST db</a></li>
  <li><a target=_blank href='ftp://ftp.mg-rast.org/data/M5nr/sources'>M5nr Source Data</a></li>
  <li><a target=_blank href='https://github.com/MG-RAST/M5nr'>M5nr GitHub Repository</a></li>
</ul></p>
~;
     
  return $content;
}

