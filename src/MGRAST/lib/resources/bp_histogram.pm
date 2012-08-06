package resources::bp_histogram;

use CGI;
use JSON;

use List::Util qw(first max min sum);
use MGRAST::Analysis;
use WebServiceObject;
use POSIX qw(strftime floor);

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "nucleotide histogram for a metagenome",
		  'documentation' => '',
		  'required' => { "metagenome id" => "string" },
		  'attributes' => { 'about'    => 'string',
				    'id'       => 'string',
				    'url'      => 'url',
				    'version'  => 'integer',
				    'created'  => 'datetime',
				    'counts'   => 'object',
				    'percents' => 'object'
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

  my $job = $master->Job->get_objects( {metagenome_id => $id} );
  my $analysis = MGRAST::Analysis->new( $master->db_handle );

  if (@$job && $analysis) {
    $job = $job->[0];
    if ($job->public || $staruser || exists($rights{$job->metagenome_id})) {
      my $obj = { about    => "nucleotide histogram",
		  id       => 'mgm'.$id,
		  url      => $cgi->url.'/bp_histogram/mgm'.$id,
		  version  => 1,
		  created  => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		  counts   => undef,
		  percents => undef
		};
      my $col_set = ['A', 'T', 'C', 'G', 'N'];
      my $nucleo  = $analysis->get_qc_stats($job->job_id, 'consensus');

      if ($nucleo && (@$nucleo > 2)) {
	# rows = [ pos, A, C, G, T, N, total ]
 	my $rrow = [];
	my $prow = [];
	my $raw  = [];
	my $per  = [];

	foreach my $row (@$nucleo) {
	  next if (($row->[0] eq '#') || (! $row->[6]));
	  @$row = map { int($_) } @$row;
	  push @$rrow, $row->[0] + 1;
	  push @$raw, [ $row->[1], $row->[4], $row->[2], $row->[3], $row->[5], $row->[6] ];
	  unless (($row->[0] > 100) && ($row->[6] < 1000)) {
	    push @$prow, $row->[0] + 1;
	    my $sum = $row->[6];
	    my @per = map { floor(100 * 100 * (($_ * 1.0) / $sum)) / 100 } @$row;
	    push @$per, [ $per[1], $per[4], $per[2], $per[3], $per[5] ];
	  }
	}
	$obj->{counts}   = { rows => $rrow, columns => [@$col_set, 'Total'], data => $raw };
	$obj->{percents} = { rows => $prow, columns => $col_set, data => $per };
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
