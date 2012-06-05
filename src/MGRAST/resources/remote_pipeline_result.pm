package resources::remote_pipeline_result;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

my $inpath = "/homes/paczian/public/mobedac_remote";

sub about {
  my $content = { 'description' => "receive pipeline results from other pipelines" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $body = $cgi->param('POSTDATA');
  $body = $json->decode($body);
  my $user = $params->{user};

  if ($user && $user->login eq 'mobedac') {
    if ($body->{analysis_system} && $body->{libraries} && ref($body->{libraries} eq 'ARRAY') && scalar (@{$body->{libraries}})) {
      my $infile = $body->{analysis_system}."_".join("_", @{$body->{libraries}});
      if (open FH, ">$inpath/$infile") {
	print FH Dumper $body;
	close FH;
	print $cgi->header(-type => 'text/plain',
			   -status => 201,
			   -Access_Control_Allow_Origin => '*' );
	print "data received successfully";
	exit 0;
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 507,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: storing object failed";
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid parameters, requires analysis_system and libraries";
    }
  } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: authentication failed";    
  }

}

sub TO_JSON { return { %{ shift() } }; }

1;
