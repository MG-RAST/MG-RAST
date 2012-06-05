package resources::sequenceSet;

use CGI;
use JSON;
use Data::Dumper;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenomic sequenceSet",
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

  my ($pref, $mgid, $job, $stageid, $stagenum);
  my $id;
  if ($rest && scalar(@$rest)) {
    $id = shift @$rest;
    ($pref, $mgid, $stageid, $stagenum) = $id =~ /^(mgm)?([\d\.]+)-(\d+)-(\d+)$/;

    if ($mgid) {
      $job = $master->Job->init( {metagenome_id => $mgid} );
      if ($job && ref($job)) {
	unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
	  print $cgi->header(-type => 'text/plain',
			     -status => 401,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: Insufficient permissions for sequenceSet call for id: ".$id;
	  exit 0;
	}
      } else {
	$job = undef;
      }
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: sequenceSet call requires an id parameter";
    exit 0;
  }

  unless (defined($job) && ref($job)) {
    my ($pref, $jid) = $id =~ /^(mgm)?(\d+\.\d+)$/;
    if ($jid) {
      $job = $master->Job->init( {metagenome_id => $jid} );
      if ($job && ref($job)) {
	unless ($job->{public} || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
	  print $cgi->header(-type => 'text/plain',
			     -status => 401,
			     -Access_Control_Allow_Origin => '*' );
	  print "ERROR: insufficient permissions for sequenceSet call for id: ".$id;
	  exit 0;
	}
	return get_all_sets($job);
      } else {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: unable to access metagenome: ".$id;
	exit 0;
      }      
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid id format for sequenceSet call";
      exit 0;
    }
  }

  my $filedir  = '';
  my $filename = '';
  if ($stageid eq "050") {
    $filedir = $job->download_dir;
    if (opendir(my $dh, $filedir)) {
      my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$filedir/$_" } readdir($dh);
      closedir $dh;
      $filename = $rawfiles[$stagenum - 1];
    }
  }
  else {
    $filedir = $job->analysis_dir;
    if (opendir(my $dh, $filedir)) {
      my @stagefiles = sort grep { /^$stageid.*(fna|faa)(\.gz)?$/ && -f "$filedir/$_" } readdir($dh);
      closedir $dh;
      $filename = $stagefiles[$stagenum - 1];
    }
  }
  
  unless ("$filedir/$filename" && (-s "$filedir/$filename")) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not access analysis directory";
    exit 0;
  }
  if (open(FH, "<$filedir/$filename")) {
    print "Content-Type:application/x-download\n";  
    print "Access-Control-Allow-Origin: *\n";
    print "Content-Length: " . (stat("$filedir/$filename"))[7] . "\n";
    print "Content-Disposition:attachment;filename=$filename\n\n";
    while (<FH>) {
      print $_;
    }
    close FH;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not access requested file";
    exit 0;
  }

  exit 0;
}

sub get_all_sets {
  my ($job) = @_;

  my $mgid = $job->metagenome_id;
  my $rdir = $job->download_dir;
  my $adir = $job->analysis_dir;
  my $stages = [];
  if (opendir(my $dh, $rdir)) {
    my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
    closedir $dh;
    my $fnum = 1;
    foreach my $rf (@rawfiles) {
      my ($jid, $ftype) = $rf =~ /^(\d+)\.(fna|fastq)(\.gz)?$/;
      push(@$stages, { id => "mgm".$mgid."-050-".$fnum,
		       stage_id => "050",
		       stage_name => "upload",
		       stage_type => $ftype,
		       file_name => $rf });
      $fnum += 1;
    }
  }
  if (opendir(my $dh, $adir)) {
    my @stagefiles = sort grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
    closedir $dh;
    my $stagehash = {};
    foreach my $sf (@stagefiles) {
      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
      next unless ($stageid && $stagename && $stageresult);
      if (exists($stagehash->{$stageid})) {
	$stagehash->{$stageid}++;
      } else {
	$stagehash->{$stageid} = 1;
      }
      push(@$stages, { id => "mgm".$mgid."-".$stageid."-".$stagehash->{$stageid},
		       stage_id => $stageid,
		       stage_name => $stagename,
		       stage_type => $stageresult,
		       file_name => $sf });
    }
  }
  if (@$stages > 0) {
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($stages);
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not access requested file";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
