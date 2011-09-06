package Babel::WebPage::Search;

# $Id: Search.pm,v 1.6 2011-05-12 20:45:35 tharriso Exp $

use strict;
use warnings;

use base qw( WebPage );

1;


sub init {
  my $self = shift;
  $self->title("M5NR - Search");
}

# commented out frontend to search by keywords

sub output {
  my ($self) = @_;

  my $content = "<h2>Searching within the M5NR</h2>";
  $content .= "<p>Welcome to the web search of the M5NR. You can search for data associated with proteins from the following categories: identifiers, functions, organisms, sequences, or md5 checksums. For function or organism annotaion, you can search for data with an exact match to your query, or for data that matches part of your query. It is possible to search for multiple types of data by entering a comma separated list of queries.</p>";

  $content .= "<p>Choose a category and enter a search query. Optionally select exact or partial match.</p>";
  $content .= $self->start_form('search_form', { 'page' => 'SearchResults' });
  $content .= qq(<table><tr>
<th>Search for</th>
<td style='padding-left:10px'>
  <select id='selType' name='search_type' onchange='
    if ((this.value == "Function") || (this.value == "Organism")) {
      document.getElementById("tdMatch").style.display = "";
      document.getElementById("tdText").style.display = "none";
    } else {
      document.getElementById("tdText").style.display = "";
      document.getElementById("tdMatch").style.display = "none";
      document.getElementById("selMatch").value = "exact";
    }'>
    <option value='Identifier' selected='selected'>Identifier</option>
    <option value='Function'>Function</option>
    <option value='Organism'>Organism</option>
    <option value='Sequence'>Sequence</option>
    <option value='MD5'>MD5</option>
  </select></td>
<td style='padding-left:10px;display:none;' id='tdMatch'>
  <select id='selMatch' name='match_type'>
    <option value='exact' selected='selected'>is equal to</option>
    <option value='regex'>contains</option>
  </select></td>
<td style='padding-left:10px' id='tdText'>is equal to</td>
<td style='padding-left:10px'>
  <input name='query' type='text' size='40' />
  <input type='submit' value=' Search ' /></td>
</tr></table>
);

  $content .= $self->end_form();
  $content .= "<p><strong>Example searches:</strong></p>";
  $content .= "<ul>";
  $content .= "<p> &raquo; search for a SEED id: <a href='".$self->application->url."?page=SearchResults&query=fig|171101.1.peg.262'>fig|171101.1.peg.262</a></p>";
  $content .= "<p> &raquo; search for a KEGG id: <a href='".$self->application->url."?page=SearchResults&query=spv:SPH_0401'>spv:SPH_0401</a></p>";
  $content .= "<p> &raquo; search for multiple ids: <a href='".$self->application->url."?page=SearchResults&query=fig|171101.1.peg.262,spv:SPH_0401'>fig|171101.1.peg.262, spv:SPH_0401</a></p>";
  $content .= "<p> &raquo; retrieve the sequence for an id: <a href='".$self->application->url."?page=Sequence&query=NP_357856.1'>NP_357856.1</a></p>";
  $content .= "</ul>";

  return $content;
}


