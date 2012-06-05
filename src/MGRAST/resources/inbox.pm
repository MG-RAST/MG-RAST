package resources::inbox;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "receive user inbox data, requires authentication",
		  'parameters' => [ 'filename', 'data' ] };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $user = $params->{user};
  my $rest = $params->{rest_parameters};
  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  if ($user) {
    use Digest::MD5 qw(md5_hex);
    use FIG_Config;
    my $base_dir = "$FIG_Config::incoming";
    my $udir = $base_dir."/".md5_hex($user->login);
    my $fn = $params->{cgi_parameters}->{upload};
   
    if ($fn) {

      if ($fn =~ /\.\./) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: invalid parameters, trying to change directory with filename, aborting";
	exit 0;
      }

      if ($fn !~ /^[\w\d_\.]+$/) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: invalid parameters, filename allows only word, underscore, . and number characters";
	exit 0;
      }
      
      if (-f "$udir/$fn") {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: the file already exists";    
	exit 0;
      }

#      use Data::Dumper;
#      print STDERR Dumper($cgi)."\n";
      
      my $fh = $cgi->upload('upload');
      if (defined $fh) {
	my $io_handle = $fh->handle;
	if (open FH, ">$udir/$fn") {
	  my ($bytesread, $buffer);
	  while ($bytesread = $io_handle->read($buffer,4096)) {
	    print FH $buffer;
	  }
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
	  print "ERROR: storing object failed - could not open target file";
	    exit 0;
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 507,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: storing object failed - could not obtain filehandle";
	exit 0;
      }
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid parameters, requires filename and data";
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 401,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: authentication failed";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
