package resources::ebi_run;

use CGI;
use JSON;

use MGRAST::Metadata;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "ebi run",
		  'parameters' => { "id" => "string" },
		  'return_type' => "text/xml" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};
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

  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  unless ($id) {
    my $result = $master->Job->get_objects( {public => 1, viewable => 1} );
    if (ref($result) && ref($result) eq 'ARRAY' && scalar(@$result)) {
      my $ids = {};
      %$ids = map { "mgm".$_->{metagenome_id}, 1 } @$result;
      if ($user) {
	map { $ids->{"mgm".$_} = 1 } @{ $user->has_right_to(undef, 'view', 'metagenome') };
      }
      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode([sort keys %$ids]);
      exit 0;
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 500,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: could not retrieve any datasets";
      exit 0;
    }
  }

  my $job = $master->Job->init( {metagenome_id => $id} );
  if ($job && ref($job)) {
    if ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}))) {
      my $mgid = "mgm".$job->metagenome_id;
      my $expr = ref($job->library) ? "<EXPERIMENT_REF refname=\"mgl".$job->library->{ID}."\" />" : '';
      my $data = $job->data;
      my $type = exists($data->{file_type}) ? $data->{file_type} : "-";
      my $md5  = $job->file_checksum_raw ? "checksum_method='MD5' checksum='".$job->file_checksum_raw."'" : '';
      my $rdir = $job->download_dir;
      my $file = $job->job_id.".".$type.".gz";

      if (opendir(my $dh, $rdir)) {
	my @readfile = sort grep { /^.+(\.fna|\.sff|\.fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
	closedir $dh;
	$file = $readfile[0];
      }
      my $pre  = "        ";
      my $attr = "";
      foreach my $tag (keys %$data) {
	$attr .= $pre."<RUN_ATTRIBUTE>\n";
	$attr .= $pre."    <TAG>".$tag."</TAG>\n";
	$attr .= $pre."    <VALUE>".$data->{$tag}."</VALUE>\n";
	$attr .= $pre."</RUN_ATTRIBUTE>\n";
      }
      my $xml = qq~<?xml version="1.0" encoding="UTF-8"?>
<RUN_SET>
<RUN alias="$mgid" center_name="EBI" broker_name="MGRAST" run_center="MGRAST">
    $expr
    <DATA_BLOCK>
        <FILES>
            <FILE filename="$file" filetype="$type" $md5 />
        </FILES>
    </DATA_BLOCK>
    <RUN_ATTRIBUTES>
$attr
    </RUN_ATTRIBUTES>
</RUN>
</RUN_SET>
~;

      my $obj  = {};
      my $mddb = MGRAST::Metadata->new();

      $obj->{_id}      = $job->_id;
      $obj->{id}       = "mgm".$job->metagenome_id;
      $obj->{about}    = "metagenome";
      $obj->{name}     = $job->name;
      $obj->{url}      = $cgi->url.'/metagenome/'.$obj->{id};
      $obj->{version}  = 1;
      $obj->{created}  = $job->created_on;
      $obj->{sample}   = $job->sample ? "mgs".$job->sample->ID : undef;
      $obj->{library}  = $job->library ? "mgl".$job->library->ID : undef;
      $obj->{metadata} = $mddb->get_job_metadata($job);

      print $cgi->header(-type => 'text/xml',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $xml;
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
    print "ERROR: Could not retrive run data from database for id ".$id;
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
