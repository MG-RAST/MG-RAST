package resources::contigchunk;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "ContigChunks are strings of DNA thought of as being a string in a 4-character alphabet
with an associated ID.  We allow a broader alphabet that includes U (for RNA) and
the standard ambiguity characters.
The notion of ContigChunk was introduced to avoid transferring/manipulating
huge contigs to access small substrings.  A ContigSequence is formed by
concatenating a set of one or more ContigChunks.  Thus, ContigChunks are the
basic units moved from the database to memory.  Their existence should be
hidden from users in most circumstances (users are expected to request
substrings of ContigSequences, and the Kbase software locates the appropriate
ContigChunks).

It has the following fields:

=over 4


=item sequence

base pairs that make up this sequence



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
		 'method' => 'CDMI_EntityAPI.all_entities_ContigChunk',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $contigchunk_list = [];
    @$contigchunk_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $contigchunk_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "sequence" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_ContigChunk',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $contigchunk = $response->{result}->[0]->{$k[0]};
    $contigchunk->{url} = $cgi->url."/contigchunk/".$rest->[0];
    my $out = $json->encode( $contigchunk );
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