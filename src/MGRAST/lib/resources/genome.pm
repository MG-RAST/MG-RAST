package resources::genome;

use Conf;
use CGI;
use JSON;

use LWP::UserAgent;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();
$json->max_size(0);

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  my $ua = LWP::UserAgent->new;
  my $cdmi_url = "http://bio-data-1.mcs.anl.gov/services/cdmi_api";

  if (! $rest || ($rest && scalar(@$rest) == 0)) {
    my $content = { 'options' => { 'verbosity' => [ [ 'minimal', 'reference and list attributes are omitted' ],
						    [ 'verbose', 'all scalar and list attributes are returned' ],
						    [ 'full', 'all scalar and list attributes are returned, references are resolved using verbosity=minimal' ] ] },
		    'required' => {},
		    'documentation' => $Conf::html_url.'/api.html#genome',
		    'attributes' => { "id" => 'string',
				      "pegs" => 'integer',
				      "rnas" => 'integer',
				      "scientific_name" => 'string',
				      "complete" => 'boolean',
				      "prokaryotic" => 'boolean',
				      "dna_size" => 'integer',
				      "contigs" => 'list of contig',
				      'features' => 'list of feature',
				      "domain" => 'string',
				      "genetic_code" => 'integer',
				      "gc_content" => 'float',
				      "phenotype" => 'string',
				      "md5" => 'string',
				      "source_id" => 'string' },
		    'description' => "A genome is a sequenced strain of an organism. It contains some overview information and references to its contig sequences and annotated features",
		    'type' => 'object',
		    'url' => $cgi->url,
		    'name' => 'genome' };
    
    if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'verbose') {
      my $data = { 'params' => [ 0, 1000000, ["id"] ],
		   'method' => 'CDMI_EntityAPI.all_entities_Genome',
		   'version' => "1.1" };
      
      my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
      $response = $response->{result};
      
      my $genome_list = [];
      @$genome_list = map { keys(%$_) } @$response;
      $content->{items} = $genome_list;
    }

    if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'full') {
      my $data = { 'params' => [ 0, 1000000, [ "id", "pegs", "rnas", "scientific_name", "complete", "prokaryotic", "dna_size", "domain", "genetic_code", "gc_content", "phenotype", "md5", "source_id" ] ],
		   'method' => 'CDMI_EntityAPI.all_entities_Genome',
		   'version' => "1.1" };
      
      my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
      my $genome_list = [];
      my @k = keys(%{$response->{result}->[0]});
      foreach my $item (@k) {
	my $genome = $response->{result}->[0]->{$item};
	$genome->{url} = $cgi->url."/genome/".$genome->{id};
	push(@$genome_list, $genome);
      }
      $content->{items} = $genome_list;
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $content );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id", "pegs", "rnas", "scientific_name", "complete", "prokaryotic", "dna_size", "domain", "genetic_code", "gc_content", "phenotype", "md5", "source_id" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_Genome',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my @k = keys(%{$response->{result}->[0]});
    my $genome = $response->{result}->[0]->{$k[0]};
    $genome->{url} = $cgi->url."/genome/".$rest->[0];

    if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'verbose') {
      # get contigs
      $genome->{contigs} = [];    
      $data = { 'params' => [ [ $rest->[0] ], [ "id" ], [], [ "id" ] ],
		'method' => 'CDMI_EntityAPI.get_relationship_IsComposedOf',
		'version' => "1.1" };
      
      $content = $json->encode($data);
      $content =~ s/%7C/|/g;
      $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
      my $contig_ids = [];
      foreach my $res (@{$response->{result}->[0]}) {
	push(@$contig_ids, $res->[2]->{id});
	push(@{$genome->{contigs}}, { id => $res->[2]->{id}, url => $cgi->url."/contig/".$res->[2]->{id} });
      }

      # get features
      $genome->{features} = [];
      $data =  { "method" => "CDMI_EntityAPI.get_relationship_IsLocusFor",
		 "version" => "1.1" ,
		 "params" => [ $contig_ids, [ "id" ], [], [ "id" ] ] };
      $content = $json->encode($data);
      $content =~ s/%7C/|/g;
      $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
      foreach my $res (@{$response->{result}->[0]}) {
	push(@{$genome->{features}}, { id => $res->[2]->{id}, url => $cgi->url."/feature/".$res->[2]->{id} });
      }
    }

    if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'full') {
      # get contigs
      $genome->{contigs} = [];    
      $data = { 'params' => [ [ $rest->[0] ], [ "id" ], [], [ "id" ] ],
		'method' => 'CDMI_EntityAPI.get_relationship_IsComposedOf',
		'version' => "1.1" };
      
      $content = $json->encode($data);
      $content =~ s/%7C/|/g;
      $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
      my $contig_ids = [];
      foreach my $res (@{$response->{result}->[0]}) {
	push(@$contig_ids, $res->[2]->{id});
	push(@{$genome->{contigs}}, $json->decode($ua->get($cgi->url."/contig/".$res->[2]->{id})->content));
      }
      
      # get features
      $genome->{features} = [];
      $data =  {  "method" => "CDMI_EntityAPI.get_relationship_IsLocusFor",
		  "version" => "1.1" ,
		  "params" => [ $contig_ids, [ "id" ], [ "begin", "dir", "len" ], [ "id", "function" ] ] };
      $content = $json->encode($data);
      $content =~ s/%7C/|/g;
      $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
      foreach my $res (@{$response->{result}->[0]}) {
	push(@{$genome->{features}}, { "contig" => $res->[0]->{"id"},
				       "start" => $res->[1]->{"begin"},
				       "direction" => $res->[1]->{"dir"},
				       "length" => $res->[1]->{"len"},
				       "id" => $res->[2]->{"id"},
				       "function" => $res->[2]->{"function"} });
      }
    }
    
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
