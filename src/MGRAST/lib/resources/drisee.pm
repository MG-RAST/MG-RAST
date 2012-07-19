package resources::drisee;

use CGI;
use JSON;

use List::Util qw(first max min sum);
use MGRAST::Analysis;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "drisee data for a metagenome",
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
  my $analysis = MGRAST::Analysis->new( $master->db_handle );

  if (@$job && $analysis) {
    $job = $job->[0];
    if ($job->public || $staruser || exists($rights{$job->metagenome_id})) {
      my $stats  = $job->stats();
      my $dscore = $stats->{drisee_score_raw} || undef;
      my $drisee = $analysis->get_qc_stats($job->job_id, 'drisee');

      my $col_raw = ['A', 'T', 'C', 'G', 'N', 'InDel', 'A', 'T', 'C', 'G', 'N', 'InDel'];
      my $col_per = ['A', 'T', 'C', 'G', 'N', 'InDel', 'Total'];
      my $row_raw = [];
      my $row_per = [];
      my $dri_raw = [];
      my $dri_per = [];
      if ($drisee && (@$drisee > 2) && ($drisee->[0][0] eq '#')) {
	foreach my $row (@$drisee) {
	  my $x = shift @$row;
	  next if ($x eq '#');
	  push @$row_raw, $x;
	  push @$dri_raw, $row;
	  if (int($x) > 50) {
	    my $sum = sum @$row;
	    my @per = map { sprintf("%.2f", 100 * (($_ * 1.0) / $sum)) } @$row;
	    push @$row_per, $x;
	    push @$dri_per, [ @per[6..11], sprintf("%.2f", sum(@per[6..11])) ];
	  }
	}
      }

      my $obj = { error   => $dscore,
		  profile => @$dri_raw ? { columns => $col_raw, rows => $row_raw, data => $dri_raw } : undef,
		  percent => @$dri_per ? { columns => $col_per, rows => $row_per, data => $dri_per } : undef
		};

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
    print "ERROR: Could not retrive drisee data from database for id ".$id;
    exit 0;
  }

  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
