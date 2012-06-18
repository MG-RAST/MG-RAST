package AnnotationClearingHouse::WebPage::achtest;

# $Id: achtest.pm,v 1.1 2009-12-01 15:22:43 wilke Exp $

use strict;
use warnings;

use base qw( WebPage );

use AnnotationClearingHouse::ACH;
use Conf;
use FIG;

1;


sub init {
  my $self = shift;
  $self->title("Annotation Clearing House - Search");


  
  my $fig_path = "/vol/seed-anno-mirror";
  my $db = "ACH_TEST";
  my $dbuser = "ach";
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
  
  my $ach = AnnotationClearingHouse::ACH->new( $dbh );
  $self->data('ACH', $ach);
  
}


sub output {
  my ($self) = @_;

  my $fig = new FIG; 

  my $anno = $self->data('ACH');

   my $content = "<h1>Search the Annotation Clearing House</h1>";
  $content .= "<p>Welcome to the web search of the annotation clearing house. You can either search for identifiers known to any of the annotation groups, or try a keyword search which will retrieve annotations based on the query. It is possible to search for multiple identifiers by entering a comma separated list of query identifiers (you may or may not add a space after each comma).</p>";

  $content .= "<p>Choose a category to search the annotation clearing house for and enter a search query.</p>";
  $content .= $self->start_form('search_form', { 'page' => 'achtest' });
  $content .= "<table><tr><th>Search for an identifier:</th><td>";
  #$content .= "<table><tr><th>Search for </th>";
  #$content .= "<td> <select name='category'>";
  #$content .= "<option>identifier</option>";
  #$content .= "<option>keywords</option>";
  #$content .= "</td><td>";
  $content .= "<input name='query' type='text' size='40' maxlength='400'>";
  $content .= "<input type='submit' value=' Search '>";
  $content .= "</td></tr></table>";
  $content .= $self->end_form();

  my $category = $self->application->cgi->param('category') || 'identifier';
  my $query = $self->application->cgi->param('query') || '';
  my $max_results = 10;

  # ignore leading/trailing spaces
  $query =~ s/^\s+//;
  $query =~ s/\s+$//;

  # get principal ids (blocks)
  my %ids;
  my @results;
  if ($category eq 'identifier') {
    $query =~ s/,/, /g;
    my @query = split(', ',$query);
    $max_results = scalar(@query);
    foreach my $q (@query) {
      push @results , @{ $anno->id2set($q) };
    }
  }
  elsif ($category eq 'keywords') {
    my @result = $anno->search($query);
    for my $r (@result) {
      my ($id, $what, $fn) = @$r;
      my $pid = $anno->lookup_principal_id($id);
      $ids{$pid}++ if ($pid);
    }
  }
  else {
    die "Unknown search category in __PACKAGE__";
  }

  # start a hash with user login to user full name mappings
  my $users = { };

  my $html;
  # generate html table output and raw dump tsv
  $html .= "<p><strong>You are searching for $category with the following query: $query</strong></p>";
  $html .= "<p><em>(returning the first $max_results results)</em></p>" if ($category eq 'keywords');
  $html .= "<p> &raquo; <a href='".$self->application->url."'>do another search</a></p>";

  my $raw_dump = "QUERY: $query\n";
  $raw_dump .= "RESULT(S):\n\n";
  
  if (scalar(@results)) {
    
    
    
      # start the table
    my $odd=1;
    $html .= "<table style='margin-bottom: 10px;'>";
    $html .= "<tr><th class='result'>Identifier</th><th class='result'>md5</th>".
      "<th class='result'>Assignment</th><th class='result'>Organism</th><th class='result'>Source</th></tr>";
    
    my $current_org = '';
    my $current_len = '';
    
    foreach my $e (@results) {
      $html .= "<tr>";
      foreach my $f (@$e){
	$html .= "<td>".$self->get_url_for_id($f)."</td>";
      }
      $html .= "</tr>\n";
    }

    $content .= $html;
  }

  return $content;
  
}


# former link to uniprot/swissprot
# "<a href='http://ca.expasy.org/uniprot/$copy'>$id</a>";

sub get_url_for_id {
  my ($self, $id) = @_;

  my $copy = $id;
  if ($copy =~ s/^kegg\|//) {
    return "<a href='http://www.genome.jp/dbget-bin/www_bget?$copy'>$id</a>";
  }
  elsif ($copy =~ s/^sp\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^tr\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^uni\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gi\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^ref\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gb\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^cmr\|// or $copy =~ s/^tigrcmr\|//) {
    return "<a href='http://cmr.tigr.org/tigr-scripts/CMR/shared/GenePage.cgi?locus=$copy'>$id</a>";
  }
  elsif ($copy =~ /^fig\|/) {
    return "<a href='http://seed-viewer.theseed.org/linkin.cgi?id=$id'>$id</a>";
  }
  elsif ($copy =~ s/^img\|//) {
    return "<a href='http://img.jgi.doe.gov/cgi-bin/pub/main.cgi?section=GeneDetail&page=geneDetail&gene_oid=$copy'>$id</a>";
  }
  else {
    return $id;
  }

}
