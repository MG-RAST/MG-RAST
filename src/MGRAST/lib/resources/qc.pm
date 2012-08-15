package resources::qc;

use resources::compute;

use CGI;
use JSON;

use Conf;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

my $result_data_dir = "/homes/paczian/public/asynch/qc";
my $pipeline_dir = "/mcs/bio/mg-rast/prod/pipeline/bin";

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  if (! $rest || ($rest && scalar(@$rest) == 0)) {
    my $content = { 'options' => { 'direct_return' => [ [ 0, 'always return a status token' ],
							[ 1, 'if the compute is done, return the result data' ] ] },
		    'required' => { 'id'=> [ 'string', 'id of the metagenome to be analyzed' ] },
		    'documentation' => $Conf::html_url.'/api.html#qc',
		    'type' => 'compute',
		    'attributes' => { 'id' => [ 'string', 'id of the metagenome to be analyzed' ],
				      'status' => [ 'string', 'status of the compute, one of [ waiting, running, error, complete ]' ],
				      'message' => [ 'string', 'informational message about the computation' ],
				      'error' => [ 'string', 'the error message if one ocurred, otherwise an empty string' ],
				      'time' => [ 'string', 'computation time of the job at the time of the query' ],
				      'result' => [ 'url', 'url to the result data or an empty string if the result is not yet available' ] },
		    'description' => "computes quality assessment data of a metagenomic sequence" };
    
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode( $content );
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    my $id = shift @$rest;

    unless (-f "$result_data_dir/$id") {
      print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    
      print "invalid id";
      exit 0;
    }
    
    my $status = { 'id' => $id,
		   'status' => "unknown",
		   'message' => "",
		   'error' => "",
		   'result' => "" };

    # check if the data for this id is already computed
    if (-f "$result_data_dir/$id.histogram") {
      if ($cgi->param('direct_return') && $cgi->param('direct_return') eq '1') {
	result($id);
      } else {
	$status->{status} = "complete";
	$status->{message} = "the result file has been successfully computed and is available via the result link";
	$status->{result} = $cgi->url."/qc/$id?direct_return=1"
      }
    } else {
      my $compute = status({ resource => 'qc',
			      id => $id });
      if ($compute->{error} eq "job does not exist") {
	$compute = submit({ resource => 'qc',
			     id => $id,
			     script => "$pipeline_dir/consensus.py -i $result_data_dir/$id -o $result_data_dir/$id.histogram" });
      }
      $status->{status} = $compute->{status};
      $status->{error} = $compute->{error};
      $status->{time} = $compute->{time};
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print $json->encode($status);
    exit 0;
  }
}

sub result {
  my ($id) = @_;

  if (open(FH, "<$result_data_dir/$id.histogram")) {
    print $cgi->header(-type => 'text/plain',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    while (<FH>) {
      print;
    }
    close FH;
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "Could not open result file $result_data_dir/$id.histogram: $@";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
