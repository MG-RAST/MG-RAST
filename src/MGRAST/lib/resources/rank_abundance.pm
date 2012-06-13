package resources::rank_abundance;

use MGRAST::Analysis;
use WebServiceObject;

use CGI;
use JSON;
use POSIX qw(strftime);

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $ach = new Babel::lib::Babel;
  my $content = { 'description' => "metagenomic rank abundance",
		  'parameters'  => { "id" => "string",
				     "limit" => "int",
				     "term" => "string",
				     "type" => [ "organism", "function" ],
				     "source" => { "protein" => [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ],
						   "rna"     => [ 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources} ]
						 }
				   },
		  'defaults' => { "limit" => 10,
				  "term" => [],
				  "type" => 'organism',
				  "source" => 'M5NR'
				}
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
    exit 0;
  }

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }

  unless (scalar(@$rest) >= 1) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: rank abundance call requires at least an id parameter";
    exit 0;
  }
  
  my $id = shift @$rest;  
  (undef, $id) = $id =~ /^(mgm)?(\d+\.\d+)$/;
  unless ($id) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid id format for profile call";
    exit 0;
  }
  
  my $job = $master->Job->init( {metagenome_id => $id} );
  unless ($job && ref($job)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Unknown id in profile call: ".$rest->[0];
    exit 0;
  }
  
  unless ($job->public || ($user && $user->has_right(undef, 'view', 'metagenome', $id))) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Insufficient permissions for profile call for id: ".$rest->[0];
    exit 0;
  }

  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }
  if ($cgi->param('limit'))  { $params->{limit}  = $cgi->param('limit'); }
  if ($cgi->param('type'))   { $params->{type}   = $cgi->param('type'); }
  if ($cgi->param('source')) { $params->{source} = $cgi->param('source'); }

  my $limit  = ($params->{limit})  ? $params->{limit}  : 10;
  my $type   = ($params->{type})   ? $params->{type}   : 'organism';
  my $source = ($params->{source}) ? $params->{source} : 'M5NR';
  my @terms  = $cgi->param('term') || ();  

  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }
  $mgdb->set_jobs([$id]);

  unless (($type eq 'organism') || ($type eq 'function')) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for abundance call: ".$type." - valid types are [ 'organism', 'function' ]";
    exit 0;
  }

  my $data;
  if (@terms > 0) {
    my $abunds = $mgdb->get_abundance_for_set(\@terms, $type, [$source]);
    # mgid => annotation => abundance
    if (exists $abunds->{$id}) {
      @$data = map {[$_, $abunds->{$id}{$_}]} keys %{$abunds->{$id}};
    }
  }
  elsif ($limit > 0) {
    my $abunds = $mgdb->get_rank_abundance($limit, $type, [$source]);
    # mgid => [annotation, abundance]
    if (exists $abunds->{$id}) {
      $data = $abunds->{$id};
    }
  }
  else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: missing paramaters, must have limit or term.";
    exit 0;
  }
  @$data = sort { ($b->[1] <=> $a->[1]) || ($a->[0] cmp $b->[0]) } @$data;
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;

}

sub TO_JSON { return { %{ shift() } }; }

1;
