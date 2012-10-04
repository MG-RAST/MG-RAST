package resources::variant;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "Each subsystem may include the designation of distinct variants.  Thus,
there may be three closely-related, but distinguishable forms of histidine
degradation.  Each form would be called a "variant", with an associated code,
and all genomes implementing a specific variant can easily be accessed.

It has the following fields:

=over 4


=item role_rule

a space-delimited list of role IDs, in alphabetical order,
that represents a possible list of non-auxiliary roles applicable to
this variant. The roles are identified by their abbreviations. A
variant may have multiple role rules.


=item code

the variant code all by itself


=item type

variant type indicating the quality of the subsystem
support. A type of "vacant" means that the subsystem
does not appear to be implemented by the variant. A
type of "incomplete" means that the subsystem appears to be
missing many reactions. In all other cases, the type is
"normal".


=item comment

commentary text about the variant



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
		 'method' => 'CDMI_EntityAPI.all_entities_Variant',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $variant_list = [];
    @$variant_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $variant_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "role_rule", "code", "type", "comment" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Variant',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $variant = $response->{result}->[0]->{$k[0]};
    $variant->{url} = $cgi->url."/variant/".$rest->[0];
    my $out = $json->encode( $variant );
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