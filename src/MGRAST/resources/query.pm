package resources::query;

use CGI;
use JSON;

use WebServiceObject;
use MGRAST::MetagenomeAnalysis2;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "query metagenomes that have a certain annotation",
		  'parameters' => { "annotation" => "string",
				    "type" => [ 'organism', 'function'],
				    "source" => "string",
				    "partial" => "boolean" },
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

  my $type = 'organism';
  if ($cgi->param('type')) {
    $type = $cgi->param('type');
  }
  my $source;
  if ($cgi->param('source')) {
    @$source = $cgi->param('source');
  }
  my $ann;
  if (scalar(@$rest)) {
    $ann = shift @$rest;
  }
  if ($cgi->param('annotation')) {
    $ann = $cgi->param('annotation');
  }
  
  my $exact = 1;
  if ($cgi->param('partial')) {
    $exact = 0;
  }
  
  unless (defined($ann)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient parameters for query call";
    exit 0;
  }

  my $mgdb = MGRAST::MetagenomeAnalysis2->new( $master->db_handle );
  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }
  
  my $content = $mgdb->metagenome_search($type, $source, $ann, $exact);
  @$content = map { "mgm".$_ } @$content;

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;

}

sub TO_JSON { return { %{ shift() } }; }

1;
