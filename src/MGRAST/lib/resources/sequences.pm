package resources::sequences;

use CGI;
use JSON;

use WebServiceObject;
use Babel::lib::Babel;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "sequences for md5s or for annotations, given a metagenome",
		  'parameters' => { "id" => "string",
				    "type" => [ "organism", "function", "ontology" ],
				    "seq" => [ "dna", "protein" ],
				    "source" => { "protein"  => [ map {$_->[0]} @{$ach->get_protein_sources} ],
						  "ontology" => [ map {$_->[0]} @{$ach->get_ontology_sources} ],
						  "rna"      => [ map {$_->[0]} @{$ach->get_rna_sources} ]
						},
				    "organism" => "string",
				    "function" => "array of string",
				    "md5" => "array of string" },
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
  my $user = $params->{user};
  my ($master, $error) = WebServiceObject::db_connect();
  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }
  
  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: missing id in sequences call";
    exit 0;
  }

  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
  }
  my $seq = 'dna';
  if ($cgi->param('seq')) {
    $seq = $cgi->param('seq');
  }
  my $source;
  if ($cgi->param('source')) {
    @$source = $cgi->param('source');
  }
  my $anns;
  if ($cgi->param('organism')) {
    @$anns = $cgi->param('organism');
  }
  if ($cgi->param('function')) {
    @$anns = $cgi->param('function');
  }
  my $md5s;
  if ($cgi->param('md5')) {
    @$md5s = $cgi->param('md5');
  }

  my $job = $master->Job->init( {metagenome_id => $id} );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {

      use MGRAST::Analysis;
      my $mgdb = MGRAST::Analysis->new( $master->db_handle );
      unless (ref($mgdb)) {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: could not connect to resource database";
	exit 0;
      }
      $mgdb->set_jobs([$id]);
      
      my $content;
      if (ref $md5s) {
	$content = $mgdb->sequences_for_md5s($id, $seq, $md5s);
      } else {
	$content = $mgdb->sequences_for_annotation($id, $seq, $type, $source, $anns);
      }

      unless ($content) {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: could not retrieve sequences from resource database";
	exit 0;
      }

      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode($content);
      exit 0;

    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid authentication for id ".$id;
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not retrive job data from database for id ".$id;
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
