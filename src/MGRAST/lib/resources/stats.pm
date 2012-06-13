package resources::stats;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "statistic files of metagenome jobs",
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

  my $id = shift @$rest;

  my ($pref, $mgid, $job, $stat_type);
  
  if ($id) {
    ($pref, $mgid, $stat_type) = $id =~ /^(mgm)?([\d\.]+)-(.+)$/;

    if ($mgid) {
      $job = $master->Job->init( {metagenome_id => $mgid} );
      if ($job && ref($job)) {
	unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $mgid))) {
	  print $cgi->header(-type => 'text/plain',
			     -status => 401,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: Insufficient permissions for stats call for id: ".$id;
	  exit 0;
	}
	
	# get the defined stats file
	my $adir = $job->analysis_dir;
	my $stagefilename;
	if (opendir(my $dh, $adir)) {
	  my @stagefiles = grep { /$stat_type\.stats$/ && -f "$adir/$_" } readdir($dh);
	  closedir $dh;
	  $stagefilename = $stagefiles[0];
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: could not find stats file";
	  exit 0;
	}
	if (open(FH, "$adir/$stagefilename")) {
	  print "Content-Type:application/x-download\n";
	  print "Access-Control-Allow-Origin: *\n";
	  print "Content-Length: " . (stat("$adir/$stagefilename"))[7] . "\n";
	  print "Content-Disposition:attachment;filename=$stagefilename\n\n";
	  while (<FH>) {
	    print;
	  }
	  close FH;
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: could not open stats file";
	  exit 0;
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 404,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: could not find metagenome for id: ".$id;
	exit 0;
      }
    } else {
      my ($pref, $mgid) = $id =~ /^(mgm)?(\d+\.\d+)$/;
      if ($mgid) {
	$job = $master->Job->init( {metagenome_id => $mgid} );
	if ($job && ref($job)) {
	  unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $mgid))) {
	    print $cgi->header(-type => 'text/plain',
			       -status => 401,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: Insufficient permissions for stats call for id: ".$id;
	    exit 0;
	  }
	  
	  # get the available stats files
	  my $adir = $job->analysis_dir;
	  if (opendir(my $dh, $adir)) {
	    my $stages = [];
	    my @stagefiles = grep { /^.*\.stats$/ && -f "$adir/$_" } readdir($dh);
	    closedir $dh;
	    foreach my $sf (@stagefiles) {
	      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.(.+)\.stats$/;
	      next unless ($stageid && $stagename && $stageresult);
	      push(@$stages, { id => "mgm".$mgid."-".$stageresult,
			       stat_type => $stageresult,
			       file_name => $sf });
	    }
	    print $cgi->header(-type => 'application/json',
			       -status => 200,
			       -Access_Control_Allow_Origin => '*' );
	    print $json->encode($stages);
	    exit 0;
	  } else {
	    print $cgi->header(-type => 'text/plain',
			       -status => 500,
			       -Access_Control_Allow_Origin => '*' );
	    print STDERR $adir." ".@$."\n";
	    exit 0;
	  }
	} else {
	  print $cgi->header(-type => 'text/plain',
			     -status => 404,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: Could not access metagenome: ".$id;
	  exit 0;	
	}
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid id format for stats call: ".$id;
	exit 0;
      }
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient parameters for stats call";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
