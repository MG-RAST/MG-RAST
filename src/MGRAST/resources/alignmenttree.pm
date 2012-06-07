package resources::alignmenttree;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "An alignment arranges a group of protein sequences so that they
match. Each alignment is associated with a phylogenetic tree that
describes how the sequences developed and their evolutionary distance.
The actual tree and alignment FASTA are stored in separate flat files.
The Kbase will maintain a set of alignments and associated
trees.  The majority
of these will be based on protein sequences.  We will not have a comprehensive set
but we will have tens of thousands of such alignments, and we view them as an
imporant resource to support annotation.
The alignments/trees will include the tools and parameters used to construct
them.
Access to the underlying sequences and trees in a form convenient to existing
tools will be supported.

It has the following fields:

=over 4


=item alignment_method

The name of the program used to produce the alignment.


=item alignment_parameters

The parameters given to the program when producing the alignment.


=item alignment_properties

A colon-delimited string of key-value pairs containing additional
properties of the alignment.


=item tree_method

The name of the program used to produce the tree.


=item tree_parameters

The parameters given to the program when producing the tree.


=item tree_properties

A colon-delimited string of key-value pairs containing additional
properties of the tree.



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
		 'method' => 'CDMI_EntityAPI.all_entities_AlignmentTree',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $alignmenttree_list = [];
    @$alignmenttree_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $alignmenttree_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "alignment_method", "alignment_parameters", "alignment_properties", "tree_method", "tree_parameters", "tree_properties" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_AlignmentTree',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $alignmenttree = $response->{result}->[0]->{$k[0]};
    $alignmenttree->{url} = $cgi->url."/alignmenttree/".$rest->[0];
    my $out = $json->encode( $alignmenttree );
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