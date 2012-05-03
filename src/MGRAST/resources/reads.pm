package resources::reads;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenome reads file",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/x-download" };

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

  unless (scalar(@$rest) == 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid number of parameters for reads call";
    exit 0;
  }

  my ($mgid) = $rest->[0] =~ /^mgm(\d+\.\d+)$/;

  unless ($mgid) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for reads call";
    exit 0;  
  }

  my $job = $master->Job->init( {metagenome_id => $mgid} );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $mgid))) {
      my $dir = $job->download_dir;
      if (opendir(my $dh, $dir)) {
	my @readfile = grep { /^.+(\.fna|\.fasta|\.sff|\.fastq)(\.gz)?$/ && -f "$dir/$_" } readdir($dh);
	closedir $dh;
	if (scalar(@readfile)) {
	  my $fn = $readfile[0];
	  if (open(FH, "$dir/$fn")) {
	    print "Content-Type:application/x-download\n";  
	    print "Access-Control-Allow-Origin: *\n";
	    print "Content-Length: " . (stat("$dir/$fn"))[7] . "\n";
	    print "Content-Disposition:attachment;filename=$fn\n\n";
	    while (<FH>) {
	      print;
	    }
	    close FH;
	  } else {
	    print $cgi->header(-type => 'text/plain',
			       -status => 404,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: could not open reads file";
	    exit 0;
	  }
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: reads file not found";
	  exit 0;
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 404,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: could not access job directory";
	exit 0;
      }
      $job->download(0);
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: Invalid authentication for id ".$rest->[0];
      exit 0;
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 404,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not retrive job data from database for id ".$rest->[0];
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
