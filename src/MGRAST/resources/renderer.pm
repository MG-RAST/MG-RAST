package resources::renderer;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "renderer library provider",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/javascript" };

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

  my @renderers = ();
  my $adir = "/homes/paczian/public/renderers";
  if (opendir(my $dh, $adir)) {
    @renderers = grep { -f "$adir/$_" } readdir($dh);
    closedir $dh;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not open renderers directory";
    exit 0;
  }
  my $renderer_hash = {};
  %$renderer_hash = map { $_ => 1 } @renderers;

  if ($rest && scalar(@$rest)) {
    if ($renderer_hash->{$rest->[0]}) {
      if (open(FH, "<$adir/".$rest->[0])) {
	print $cgi->header(-type => 'application/javascript',
			   -status => 200,
			   -Access_Control_Allow_Origin => '*' );
	while (<FH>) {
	  print $_;
	}
	exit 0;
	close FH;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 500,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: reading renderer failed";
	exit 0;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid renderer requested";
      exit 0;
    }
  }
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  
  print $json->encode( \@renderers );
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
