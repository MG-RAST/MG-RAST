package resources::genome;

use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "The Kbase houses a large and growing set of genomes.  We often have multiple
genomes that have identical DNA.  These usually have distinct gene calls and
annotations, but not always.  We consider the Kbase to be a framework for
managing hundreds of thousands of genomes and offering the tools needed to
support compartive analysis on large sets of genomes, some of which are
virtually identical.
Each genome has an MD5 value computed from the DNA that is associated with the genome.
Hence, it is easy to recognize when you have identical genomes, perhaps annotated
by distinct groups.

It has the following fields:

=over 4


=item pegs

Number of protein encoding genes for this genome.


=item rnas

Number of RNA features found for this organism.


=item scientific_name

Full genus/species/strain name of the genome sequence.


=item complete

TRUE if the genome sequence is complete, else FALSE


=item prokaryotic

TRUE if this is a prokaryotic genome sequence, else FALSE


=item dna_size

Number of base pairs in the genome sequence.


=item contigs

Number of contigs for this genome sequence.


=item domain

Domain for this organism (Archaea, Bacteria, Eukaryota,
Virus, Plasmid, or Environmental Sample).


=item genetic_code

Genetic code number used for protein translation on most
of this genome sequence's contigs.


=item gc_content

Percent GC content present in the genome sequence's
DNA.


=item phenotype

zero or more strings describing phenotypic information
about this genome sequence


=item md5

MD5 identifier describing the genome's DNA sequence


=item source_id

identifier assigned to this genome by the original
source



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
		 'method' => 'CDMI_EntityAPI.all_entities_Genome',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $genome_list = [];
    @$genome_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $genome_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "pegs", "rnas", "scientific_name", "complete", "prokaryotic", "dna_size", "contigs", "domain", "genetic_code", "gc_content", "phenotype", "md5", "source_id" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Genome',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $genome = $response->{result}->[0]->{$k[0]};
    $genome->{url} = $cgi->url."/genome/".$rest->[0];
    my $out = $json->encode( $genome );
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