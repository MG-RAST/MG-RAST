package Babel::WebPage::SearchResults;

# $Id: SearchResults.pm,v 1.11 2011-10-17 19:41:18 tharriso Exp $

use strict;
use warnings;

use base qw( WebPage );

use Babel::lib::Babel;
use Conf;
use Data::Dumper;

1;


sub init {
  my $self = shift;
  $self->title("M5nr - Search");

  # get data handler, connect to database and initialise babel
  my $babel = new Babel::lib::Babel;
  $self->data('babel', $babel);

  # register components
  $self->application->register_component('Table', 'SearchResults');
}


sub output {
  my ($self) = @_;

  # initialize
  my $babel = $self->data('babel');
  my $category = lc ($self->application->cgi->param('search_type') || 'identifier');
  my $match = $self->application->cgi->param('match_type') || 'exact';
  my $regex = ($match eq 'regex') ? 1 : 0;
  my $query = $self->application->cgi->param('query') || '';
  my $max_results = 10;
  my $results;
  my $content = '';
  my $fasta   = '';

  # ignore leading/trailing spaces
  $query =~ s/^\s+//;
  $query =~ s/\s+$//;
  $query =~ s/,\s*/,/g;

  my @query = split(',',$query);
  $max_results = scalar(@query);
  
  # get principal ids (blocks)
  # sets: [ id, md5, func, org, source ]
  my %ids;
  if ($category eq 'identifier') {
    $results = $babel->ids2sets(\@query);
    $fasta   = $babel->ids2sequences(\@query);
  }
  elsif ($category eq 'function') {
    $results = $babel->functions2sets(\@query, $regex);
  }
  elsif ($category eq "organism"){
    $results = $babel->organisms2sets(\@query, $regex);
  }
  elsif ($category eq "sequence"){
    $results = $babel->sequence2set($query[0]);
  }
  elsif ($category eq "md5"){
    $results = $babel->md5s2sets(\@query);
    $fasta   = $babel->md5s2sequences(\@query);
  }
  else {
    $self->app->add_message("warning" , "Unknown search category $category in __PACKAGE__");
  }

  # get sources
  my $sources = $babel->sources;
  
  # switch columns
  my @display_columns = map { [ $_->[4],
				($sources->{$_->[4]}{link} ? "<a target=_blank href='".$sources->{$_->[4]}{link}.$_->[0]."'>".$_->[0]."</a>" : $_->[0]),
				"<a target=_blank href='".$self->application->url."?page=SearchResults&search_type=md5&query=".$_->[1]."'>".$_->[1]."</a>",
				($_->[2] || ''),
				$_->[3] ] } @$results;

  # add search results to table
  my $table_component = $self->application->component('SearchResults');
  $table_component->data(\@display_columns);
  $table_component->columns( [ { 'name' => 'Source', 'filter' => 1, 'operator' => 'combobox' },
			       { 'name' => 'Source ID', 'filter' => 1 },
			       { 'name' => 'M5nr ID', 'filter' => 1, visible => (($category eq "md5") ? 0 : 1) },
			       { 'name' => 'Functional Assignment', 'filter' => 1 , 'operators' => ['like', 'unlike'], 'sortable' => 1},
			       { 'name' => 'Organism', 'filter' => 1, sortable => 1 }
			     ] );
  $table_component->show_top_browse(1);
  $table_component->show_bottom_browse(1);
  $table_component->show_export_button({ strip_html => 1 });
  $table_component->items_per_page(50);
  $table_component->show_select_items_per_page(1);

  # display fasta
  if ($fasta) {
    my @output = ();
    my @fasta  = split(/\n/, $fasta);
    for (my $i=0; $i<@fasta; $i += 2) {
      if ($fasta[$i] =~ /^>(\S+)/) {
	my $id  = $1;
	my $seq = $fasta[$i+1];
	$id  =~ s/^lcl\|//;
	$seq =~ s/(.{80})/$1\n/g;
	push @output, ">$id\n$seq";
      }
    }
    $fasta = join("\n", @output)
  }

  # generate html table output and raw dump tsv
  my $html = "<p><strong>You are searching for $category with the following query: $query</strong></p>";
  $html .= "<p><em>(returning the first $max_results results)</em></p>" if ($category eq 'keywords');
  $html .= "<p> &raquo; <a href='".$self->application->url."'>do another search</a></p>";
  
  my $raw_dump = "QUERY: $query\n";
  $raw_dump .= "RESULT(S):\n\n";
  
  $content .= $html ; 
  $content .= $table_component->output();
  $content .= $fasta ? "<br><p>Sequences:<p><pre>$fasta</pre>" : "";
  return $content;

}
