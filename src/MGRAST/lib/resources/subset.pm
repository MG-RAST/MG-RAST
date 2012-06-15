package resources::subset;

use WebServiceObject;
use MGRAST::Analysis;
use Babel::lib::Babel;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "md5s with counts for organism or function, given a metagenome and an optional source",
		  'parameters' => { "id" => "string",
				    "type" => [ "organism", "function" ],
				    "source" => { "protein"  => [ map {$_->[0]} @{$ach->get_protein_sources} ],
						  "ontology" => [ map {$_->[0]} @{$ach->get_ontology_sources} ],
						  "rna"      => [ map {$_->[0]} @{$ach->get_rna_sources} ]
						},
				    "organism" => "string",
				    "function" => "string" },
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

  my $cgi = new CGI;
  my $json = new JSON;
  $json = $json->utf8();
  
  my $id = shift @$rest;
  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: missing id in subset call";
    exit 0;
  }
  (undef, $id) = $id =~ /^(mgm)?(\d+\.\d+)$/;
  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
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
    my @funcs = $cgi->param('function');
    if (ref($anns)) {
      push(@$anns, @funcs);
    } else {
      $anns = \@funcs;
    }
  }
  
  my $job = $master->Job->init( {metagenome_id => $id} );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {

      my $mgdb = MGRAST::Analysis->new( $master->db_handle );
      unless (ref($mgdb)) {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Could not access analysis database";
      }

      $mgdb->set_jobs([$id]);
      
      my $content = $mgdb->md5_abundance_for_annotations($id, $type, $source, $anns);
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
