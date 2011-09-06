package Babel::WebPage::Sequence;

# $Id: Sequence.pm,v 1.8 2011-05-02 21:39:34 tharriso Exp $

use strict;
use warnings;

use base qw( WebPage );

use Babel::lib::Babel;
use Global_Config;
use Data::Dumper;

1;


sub init {
  my $self = shift;
  $self->title("M5NR - Sequence Retrieval");

  # get data handler, connect to database and initialise babel
  my $babel = new Babel::lib::Babel;
  $self->data('babel', $babel);
}


sub output {
  my ($self) = @_;
 
  my $anno =  $self->data('babel');
  my $query = $self->application->cgi->param('query') || '';
  my $content = "<h2>Sequence Retrieval from the M5NR</h2>\n";

  if ($query) {
    $query =~ s/ //g;
    my @query = split(',',$query);
  
    $content .= "<p><strong>Retrieving sequence data for the following query: $query</strong></p>";
    $content .= "<p> &raquo; <a href='".$self->application->url."?page=Sequence'>do another sequence lookup</a></p>";
    $content .= "<pre>\n";
    $content .= "QUERY: $query\nRESULT(S):\n\n";

    my $md5seq = {};
    my $md5id  = $anno->ids2md5s(\@query);
    my %md5s   = map {$_->[0], 1} @$md5id;

    foreach my $q (@query) {
      push @$md5id, [ $q, $q ];
      $md5s{$q} = 1;
    }

    my @fasta  = split("\n", $anno->md5s2sequences([keys %md5s]));
    chomp @fasta;
    
    for (my $i=0; $i<@fasta; $i += 2) {
      if ($fasta[$i] =~ /^>(\S+)/) {
	my $id  = $1;
	my $seq = $fasta[$i+1];
	$id  =~ s/^lcl\|//;
	$seq =~ s/(.{80})/$1\n/g;
	$md5seq->{$id} = $seq;
      }
    }
    $content .= join("\n", map {">".$_->[1]."\n".$md5seq->{$_->[0]}} grep {exists($md5seq->{$_->[0]})} @$md5id);
    $content .= "</pre>\n";
  }
  else {
    $content .= "<p>To retrieve the sequence data for identifiers or md5 checksums within the M5NR, please enter the identifier or md5sum below and press Retrieve. It is possible to retrieve sequences for multiple identifiers by entering a comma separated list of querys.</p>";
    
    $content .= $self->start_form('retrieve_form', { page => 'Sequence' });
    $content .= "<table><tr><th>Look up sequence for </th>";
    $content .= "<td><input name='query' type='text' size='40' maxlength='400'></td>";
    $content .= "<td><input type='submit' value=' Retrieve '>";
    $content .= "</td></tr></table>";
    $content .= $self->end_form();
  }
  return $content;
}

