package resources::atomicregulon;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "An atomic regulon is an indivisible group of coregulated features
on a single genome. Atomic regulons are constructed so that a given feature
can only belong to one. Because of this, the expression levels for
atomic regulons represent in some sense the state of a cell.
An atomicRegulon is a set of protein-encoding genes that
are believed to have identical expression profiles (i.e.,
they will all be expressed or none will be expressed in the
vast majority of conditions).  These are sometimes referred
to as "atomic regulons".  Note that there are more common
notions of "coregulated set of genes" based on the notion
that a single regulatory mechanism impacts an entire set of
genes. Since multiple other mechanisms may impact
overlapping sets, the genes impacted by a regulatory
mechanism need not all share the same expression profile.
We use a distinct notion (CoregulatedSet) to reference sets
of genes impacted by a single regulatory mechanism (i.e.,
by a single transcription regulator).

It has the following fields:

=over 4



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
		 'method' => 'CDMI_EntityAPI.all_entities_AtomicRegulon',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $atomicregulon_list = [];
    @$atomicregulon_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $atomicregulon_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_AtomicRegulon',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $atomicregulon = $response->{result}->[0]->{$k[0]};
    $atomicregulon->{url} = $cgi->url."/atomicregulon/".$rest->[0];
    my $out = $json->encode( $atomicregulon );
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