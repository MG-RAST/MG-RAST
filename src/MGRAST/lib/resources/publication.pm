package resources::publication;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "Annotators attach publications to ProteinSequences.  The criteria we have used
to gather such connections is a bit nonstandard.  We have sought to attach publications
to ProteinSequences when the publication includes an expert asserting a belief or estimate
of function.  The paper may not be the original characterization.  Further, it may not
even discuss a sequence protein (much of the lietarture is very valuable, but reports
work on proteins in strains that have not yet been sequenced).  On the other hand,
reports of sequencing regions of a chromosome (with no specific assertion of a
clear function) should not be attached.  The attached publications give an ID (usually a
Pubmed ID),  a URL to the paper (when we have it), and a title (when we have it).

It has the following fields:

=over 4


=item citation

Hyperlink of the article. The text is the article title.



=back


",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/json" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  my $ua = LWP::UserAgent->new;
  my $cdmi_url = "http://bio-data-1.mcs.anl.gov/services/cdmi_api";
  if (! $rest || ! scalar(@$rest)) {    
    my $data = { 'params' => [ 0, 1000000, ["id"] ],
		 'method' => 'CDMI_EntityAPI.all_entities_Publication',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $publication_list = [];
    @$publication_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $publication_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "citation" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Publication',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $publication = $response->{result}->[0]->{$k[0]};
    $publication->{url} = $cgi->url."/publication/".$rest->[0];
    my $out = $json->encode( $publication );
    $out =~ s/%7C/|/g;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $out;
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;