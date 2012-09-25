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

  my $user = $params->{user};

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }

  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();
  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;

  my $staruser = ($user && $user->has_right(undef, 'view', 'metagenome', '*')) ? 1 : 0;

  unless ($id) {
    my $ids = {};
    if ($staruser) {
      map { $ids->{"mgm".$_->{metagenome_id}} = 1 } @{ $master->Job->get_objects({viewable => 1}) };
    }
    else {
      my $public = $master->Job->get_public_jobs(1);
      map { $ids->{"mgm".$_} = 1 } @$public;
      map { $ids->{"mgm".$_} = 1 } keys %rights;
    }

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode([sort keys %$ids]);
    exit 0;
  }

  my $job = $master->Job->get_objects( {metagenome_id => $id} );
  if (@$job) {
    $job = $job->[0];
    if ($job->public || $staruser || exists($rights{$job->metagenome_id})) {
      my $obj  = {};
      my $mddb = MGRAST::Metadata->new();
      my $temp = ($cgi->param('template')) ? 1 : 0;

      $obj->{_id}      = $job->_id;
      $obj->{id}       = "mgm".$job->metagenome_id;
      $obj->{about}    = "metagenome";
      $obj->{name}     = $job->name;
      $obj->{url}      = $cgi->url.'/metagenome/'.$obj->{id};
      $obj->{version}  = 1;
      $obj->{created}  = $job->created_on;
      $obj->{sample}   = $job->sample ? "mgs".$job->sample->ID : undef;
      $obj->{library}  = $job->library ? "mgl".$job->library->ID : undef;
      $obj->{metadata} = $mddb->get_job_metadata($job, $temp);
	  $obj->{stats}    = $job->stats;
	  $obj->{attributes} = $job->data;

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
