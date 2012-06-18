package resources::jobgroupSummary;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "returns summary information about a jobgroup",
		  'parameters' => { "name" => "string" },
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

  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  unless ($rest && scalar(@$rest) == 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 501,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid parameters for jobgroupSummary call (requires jobgroup name)";
    exit 0;
  }

  use WebServiceObject;
  my ($jobdb, $error) = WebServiceObject::db_connect();

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not connect to job database - $error";
    exit 0;
  }

  my $dbh = $jobdb->db_handle;
  my $statement = "select Project._id, Project.name, Project.id, count(*) as jobs from Project, Jobgroup, JobgroupJob, Job where Job.primary_project = Project.id and Jobgroup.name='".$rest->[0]."' and JobgroupJob.jobgroup = Jobgroup._id and Job._id = JobgroupJob.job and Project.public = 1 group by Project._id";
  my $pdata = $dbh->selectall_arrayref($statement);

  my $data = [];
  foreach my $pd (@$pdata) {
    my $pmd = $dbh->selectall_arrayref("select tag, value from ProjectMD where project=127 and tag in ('PI_firstname', 'PI_lastname', 'PI_email')");
    my ($firstname, $lastname, $email) = ("", "", "");
    foreach my $d (@$pmd) {
      if ($d->[0] eq "PI_firstname") {
	$firstname = $d->[1];
      } elsif ($d->[0] eq "PI_lastname") {
	$lastname = $d->[1];
      } elsif ($d->[0] eq "PI_email") {
	$email =  $d->[1];
      }
    }
    my $obj = { name => $pd->[1],
		id => $pd->[2],
		numjobs => $pd->[3],
		pi_firstname => $firstname,
		pi_lastname => $lastname,
		pi_email => $email };
    push(@$data, $obj);
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode( $data );
}

sub TO_JSON { return { %{ shift() } }; }

1;
