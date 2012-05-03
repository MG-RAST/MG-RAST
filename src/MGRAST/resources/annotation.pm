package resources::annotation;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "annotations for an md5 given a namespace - parameterless call will return a list of available namespaces",
		  'parameters' => { "id" => "string",
				    "namespace" => "string" },
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

  use Babel::lib::Babel;
  my $ach = new Babel::lib::Babel;
  unless (ref($ach)) {
     print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not connect to resource database";
    exit 0;
  }

  my $sources;
  if ($cgi->param('namespace')) {
    $sources = [ $cgi->param('namespace') ];
  }

  unless ($sources) {
    $sources = $ach->sources;
    my $source_list = [];
    @$source_list = map { $_ } keys(%$sources);
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($source_list);
    exit 0;
  }

  unless (scalar(@$rest)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for annotation call";
    exit 0;
  }
  
  my $md5s = [ shift @$rest ];
  
  my $stuff = $ach->md5s2idfunc4sources($md5s, $sources);
  my $org = $ach->md5s2organisms($md5s);
  if (scalar(@$org)) {
    $org = $org->[0]->[0];
  } else {
    $org = "unknown";
  }

  unless (scalar(keys(%$stuff))) {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: md5 not found";
    exit 0;
  }
  my $data = { md5 => $md5s->[0],
	       source => $stuff->{$md5s->[0]}->[0]->[0],
	       FID => $stuff->{$md5s->[0]}->[0]->[1],
	       function => $stuff->{$md5s->[0]}->[0]->[2],
	       organism => $org };	  

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
