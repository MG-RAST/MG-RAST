package resources::family;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "The Kbase will support the maintenance of protein families (as sets of Features
with associated translations).  We are initially only supporting the notion of a family
as composed of a set of isofunctional homologs.  That is, the families we
initially support should be thought of as containing protein-encoding genes whose
associated sequences all implement the same function
(we do understand that the notion of "function" is somewhat ambiguous, so let
us sweep this under the rug by calling a functional role a "primitive concept").
We currently support families in which the members are
translations of features, and we think of Features as
having an associated function. Identical protein sequences
as products of translating distinct genes may or may not
have identical functions, and we allow multiple members of
the same Family to share identical protein sequences.  This
may be justified, since in a very, very, very few cases
identical proteins do, in fact, have distinct functions.
We would prefer to reach the point where our Families are
sets of protein sequence, rather than sets of
protein-encoding Features.

It has the following fields:

=over 4


=item type

type of protein family (e.g. FIGfam, equivalog)


=item family_function

optional free-form description of the family. For function-based
families, this would be the functional role for the family
members.



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
		 'method' => 'CDMI_EntityAPI.all_entities_Family',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $family_list = [];
    @$family_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $family_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "type", "family_function" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Family',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $family = $response->{result}->[0]->{$k[0]};
    $family->{url} = $cgi->url."/family/".$rest->[0];
    my $out = $json->encode( $family );
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