package resources::kmer;

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
		  'required'   => { "metagenome id" => "string" },
		  'options'    => { "size" => ['integer', 'compute for kmer inputed length, default 15'] },
		  'attributes' => { 'about'    => 'string',
				    'id'       => 'string',
				    'url'      => 'url',
				    'version'  => 'integer',
				    'created'  => 'datetime',
				    'columns'  => 'array of string',
				    'profile'  => 'list of list of integer'
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

  my $size = $cgi->param('size') ? $cgi->param('size') : '15';
  my $job  = $master->Job->get_objects( {metagenome_id => $id} );
  my $analysis = MGRAST::Analysis->new( $master->db_handle );

  if (@$job && $analysis) {
    $job = $job->[0];
    if ($job->public || $staruser || exists($rights{$job->metagenome_id})) {
      my $obj = { about    => "k-mer profile",
		  id       => 'mgm'.$id,
		  url      => $cgi->url.'/kmer/mgm'.$id.'?size='.$size,
		  version  => 1,
		  created  => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		  profile  => undef,
		  columns  => [ 'count of identical kmers of size N',
				'number of times count occures',
				'product of column 1 and 2',
				'reverse sum of column 2',
				'reverse sum of column 3',
				'ratio of column 5 to total sum column 3 (not reverse)' ]
		};
      my $kmer = $analysis->get_qc_stats($job->job_id, 'kmer.'.$size);
      if ($kmer && (@$kmer > 1)) {
	$obj->{profile} = $kmer;
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
