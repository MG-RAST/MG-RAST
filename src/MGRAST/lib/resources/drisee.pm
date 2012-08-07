package resources::drisee;

use CGI;
use JSON;

use List::Util qw(first max min sum);
use MGRAST::Analysis;
use WebServiceObject;
use POSIX qw(strftime);

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();
my $types = {all => 1, error => 1, count => 1, percent => 1};

sub about {
  my $content = { 'description' => "drisee data for a metagenome",
		  'documentation' => '',
		  'required' => { "metagenome id" => "string" },
		  'options' => { "type" => [ ['all', 'outputs combined error, count, percent data'],
					     ['error', 'outputs drisee percent errors'],
					     ['count', 'outputs drisee count profile'],
					     ['percent', 'outputs drisee percent profile'] ]
			       },
		  'attributes' => { 'about'   => 'string',
				    'id'      => 'string',
				    'url'     => 'url',
				    'version' => 'integer',
				    'created' => 'datetime',
				    'errors'  => 'hash of float',
				    'bins'    => 'hash of integer',
				    'count_profile'   => 'object',
				    'percent_profile' => 'object'
				  },
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
  my $user = $params->{user};
  my ($master, $error) = WebServiceObject::db_connect();
  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
  }

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }

  my %rights   = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();
  my $staruser = ($user && $user->has_right(undef, 'view', 'metagenome', '*')) ? 1 : 0;

  unless ($rest && (@$rest > 0)) {
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

  my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format: ".$id;
    exit 0;
  }

  my $type = $cgi->param('type') ? $cgi->param('type') : 'all';
  unless (exists $types->{$type}) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for matrix call: ".$type." - valid types are [".join(", ", keys %$types)."]";
    exit 0;
  }

  my $job = $master->Job->get_objects( {metagenome_id => $id} );
  my $analysis = MGRAST::Analysis->new( $master->db_handle );

  if (@$job && $analysis) {
    $job = $job->[0];
    if ($job->public || $staruser || exists($rights{$job->metagenome_id})) {
      my $obj = { about   => "drisee",
		  id      => 'mgm'.$id,
		  url     => $cgi->url.'/drisee/mgm'.$id.'?type='.$type,
		  version => 1,
		  created => strftime("%Y-%m-%dT%H:%M:%S", localtime)
		};
      my $col_set = ['A', 'T', 'C', 'G', 'N', 'InDel'];
      my $drisee  = $analysis->get_qc_stats($job->job_id, 'drisee');

      if (($type eq 'all') || ($type eq 'error')) {
	my $stats = $job->stats();
	$obj->{errors} = { total => $stats->{drisee_score_raw} ? $stats->{drisee_score_raw} * 1.0 : undef };

	if ($drisee && (@$drisee > 2) && ($drisee->[1][0] eq '#')) {
	  $obj->{errors}{insertion_deletion} =  $drisee->[1][6] * 1.0;
	  $obj->{errors}{substitution} = { A => $drisee->[1][1] * 1.0,
					   T => $drisee->[1][2] * 1.0,
					   C => $drisee->[1][3] * 1.0,
					   G => $drisee->[1][4] * 1.0,
					   N => $drisee->[1][5] * 1.0 };
	}
      }
      if (($type eq 'all') || ($type eq 'count')) {
	my $rows = [];
	my $cols = [];
	my $data = [];
	map { push @$cols, $_.' match consensus sequence' } @$col_set;
	map { push @$cols, $_.' not match consensus sequence' } @$col_set;
	if ($drisee && (@$drisee > 2) && ($drisee->[0][0] eq '#')) {
	  foreach my $row (@$drisee) {
	     next if ($row->[0] eq '#');
	     my @nums = map { int($_) } @$row;
	     push @$rows, shift @nums;
	     push @$data, [ @nums ];
	  }
	}
	$obj->{count_profile} = { rows => $rows, columns => $cols, data => $data };				     
      }
      if (($type eq 'all') || ($type eq 'percent')) {
	my $rows = [];
	my $cols = [ @$col_set, 'Total' ];
	my $data = [];
	if ($drisee && (@$drisee > 2) && ($drisee->[0][0] eq '#')) {
	  foreach my $row (@$drisee) {
	     my $x = shift @$row;
	     next if ($x eq '#');
	     if (int($x) > 50) {
	       my $sum = sum @$row;
	       my @per = map { sprintf("%.2f", 100 * (($_ * 1.0) / $sum)) * 1.0 } @$row;
	       push @$rows, int($x);
	       push @$data, [ @per[6..11], sprintf("%.2f", sum(@per[6..11])) * 1.0 ];
	     }
	  }
	}
	$obj->{percent_profile} = { rows => $rows, columns => $cols, data => $data };
      }
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
