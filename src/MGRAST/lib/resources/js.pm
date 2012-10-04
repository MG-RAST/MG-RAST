package resources::js;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "js library provider",
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

  my @scripts = ();
  my $adir = "/homes/paczian/public/js";
  if (opendir(my $dh, $adir)) {
    @scripts = grep { -f "$adir/$_" } readdir($dh);
    closedir $dh;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not open library directory";
    exit 0;
  }
  my $scripts_hash = {};
  %$scripts_hash = map { $_ => 1 } @scripts;

  if ($rest && scalar(@$rest)) {
    if ($scripts_hash->{$rest->[0]}) {
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
	print "ERROR: reading library failed";
	exit 0;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid library requested";
      exit 0;
    }
  }
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  
  print $json->encode( \@scripts );
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
