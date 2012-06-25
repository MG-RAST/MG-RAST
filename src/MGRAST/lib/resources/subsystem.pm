package resources::subsystem;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "A subsystem is a set of functional roles that have been annotated simultaneously (e.g.,
the roles present in a specific pathway), with an associated subsystem spreadsheet
which encodes the fids in each genome that implement the functional roles in the
subsystem.

It has the following fields:

=over 4


=item version

version number for the subsystem. This value is
incremented each time the subsystem is backed up.


=item curator

name of the person currently in charge of the
subsystem


=item notes

descriptive notes about the subsystem


=item description

description of the subsystem's function in the
cell


=item usable

TRUE if this is a usable subsystem, else FALSE. An
unusable subsystem is one that is experimental or is of
such low quality that it can negatively affect analysis.


=item private

TRUE if this is a private subsystem, else FALSE. A
private subsystem has valid data, but is not considered ready
for general distribution.


=item cluster_based

TRUE if this is a clustering-based subsystem, else
FALSE. A clustering-based subsystem is one in which there is
functional-coupling evidence that genes belong together, but
we do not yet know what they do.


=item experimental

TRUE if this is an experimental subsystem, else FALSE.
An experimental subsystem is designed for investigation and
is not yet ready to be used in comparative analysis and
annotation.



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
		 'method' => 'CDMI_EntityAPI.all_entities_Subsystem',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $subsystem_list = [];
    @$subsystem_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $subsystem_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "version", "curator", "notes", "description", "usable", "private", "cluster_based", "experimental" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Subsystem',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $subsystem = $response->{result}->[0]->{$k[0]};
    $subsystem->{url} = $cgi->url."/subsystem/".$rest->[0];
    my $out = $json->encode( $subsystem );
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