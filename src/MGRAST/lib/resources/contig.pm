package resources::contig;

use CGI;
use JSON;

use LWP::UserAgent;

use constant UNMAP => {
                      'A' => 'aaa', 'B' => 'aac', 'C' => 'aag', 'D' => 'aat',
                      'E' => 'aca', 'F' => 'acc', 'G' => 'acg', 'H' => 'act',
                      'I' => 'aga', 'J' => 'agc', 'K' => 'agg', 'L' => 'agt',
                      'M' => 'ata', 'N' => 'atc', 'O' => 'atg', 'P' => 'att',
                      'Q' => 'caa', 'R' => 'cac', 'S' => 'cag', 'T' => 'cat',
                      'U' => 'cca', 'V' => 'ccc', 'W' => 'ccg', 'X' => 'cct',
                      'Y' => 'cga', 'Z' => 'cgc', 'a' => 'cgg', 'b' => 'cgt',
                      'c' => 'cta', 'd' => 'ctc', 'e' => 'ctg', 'f' => 'ctt',
                      'g' => 'gaa', 'h' => 'gac', 'i' => 'gag', 'j' => 'gat',
                      'k' => 'gca', 'l' => 'gcc', 'm' => 'gcg', 'n' => 'gct',
                      'o' => 'gga', 'p' => 'ggc', 'q' => 'ggg', 'r' => 'ggt',
                      's' => 'gta', 't' => 'gtc', 'u' => 'gtg', 'v' => 'gtt',
                      'w' => 'taa', 'x' => 'tac', 'y' => 'tag', 'z' => 'tat',
                      '0' => 'tca', '1' => 'tcc', '2' => 'tcg', '3' => 'tct',
                      '4' => 'tga', '5' => 'tgc', '6' => 'tgg', '7' => 'tgt',
                      '8' => 'tta', '9' => 'ttc', '/' => 'ttg', '+' => 'ttt',
                    };
use constant DIGITS64 => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/+';

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub sequencify {
    # Get the parameters.
    my ($string) = @_;
    # Declare the return variable.
    my $retVal = "";
    # Loop through the string.
    my $pos = 0;
    my $len = length($string);
    while ($pos < $len) {
        # Try to unmap the current character.
        my $triple = UNMAP->{substr($string, $pos, 1)};
        if (defined $triple) {
            $retVal .= $triple;
            $pos++;
        } else {
            # Here we have something unusual. Get the current character.
            my $char = substr($string, $pos, 1);
            # It can be a hyphen, an equal sign, or an exclamation point.
            if ($char eq '-') {
                # It's a hyphen. The next character is a run length.
                my $runLength = 1 + index(DIGITS64, substr($string, $pos+1, 1));
                $retVal .= '-' x $runLength;
                $pos += 2;
            } elsif ($char eq '=') {
                # It's an equal sign. Chop the last character off the end of the
                # return string.
                chop $retVal;
                $pos++;
            } elsif ($char eq '!') {
                # It's an exclamation point, so we have an unusual character.
                $retVal .= substr($string, $pos+1, 1);
                $pos += 2;
            }
        }
    }
    # Return the result.
    return $retVal;
}

sub about {
  my $content = { 'description' => "A contig is thought of as composing a part of the DNA associated with a specific
genome.  It is represented as an ID (including the genome ID) and a ContigSequence.
We do not think of strings of DNA from, say, a metgenomic sample as 'contigs',
since there is no associated genome (these would be considered ContigSequences).
This use of the term 'ContigSequence', rather than just 'DNA sequence', may turn out
to be a bad idea.  For now, you should just realize that a Contig has an associated
genome, but a ContigSequence does not.",
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
		 'method' => 'CDMI_EntityAPI.all_entities_Contig',
		 'version' => "1.1" };
    
    my $response = $json->decode($ua->post($cdmi_url, Content => $json->encode($data))->content);
    $response = $response->{result};

    my $contig_list = [];
    @$contig_list = map { keys(%$_) } @$response;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $contig_list );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $data = { 'params' => [ [ $rest->[0] ], [ "id" ], [], [ "id" ] ],
		 'method' => 'CDMI_EntityAPI.get_relationship_HasAsSequence',
		 'version' => "1.1" };
    
    my $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    my $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);
    my $seqids = [];
    foreach my $res (@{$response->{result}->[0]}) {
      push(@$seqids, $res->[2]->{id});
    }
    $data = { 'params' => [ $seqids, [ "id" ], [], [ "sequence" ] ],
	      'method' => 'CDMI_EntityAPI.get_relationship_HasSection',
	      'version' => "1.1" };
    $content = $json->encode($data);
    $content =~ s/%7C/|/g;
    $response = $json->decode($ua->post($cdmi_url, Content => $content)->content);

    my $sequence = "";
    foreach my $res (@{$response->{result}->[0]}) {
      $sequence .= $res->[2]->{sequence};
    }
    
    my $contig = { id => $rest->[0] };
    $contig->{url} = $cgi->url."/contig/".$rest->[0];
    $contig->{sequence} = sequencify($sequence);
    
    my $out = $json->encode( $contig );
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
