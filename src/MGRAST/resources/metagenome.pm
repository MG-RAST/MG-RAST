package resources::metagenome;

use CGI;
use JSON;

use MGRAST::Metadata;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenome object",
		  'parameters' => { "id" => "string" },
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

      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $json->encode( $obj );
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
    print "ERROR: Could not retrive metagenome data from database for id ".$id;
    exit 0;
  }

  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
