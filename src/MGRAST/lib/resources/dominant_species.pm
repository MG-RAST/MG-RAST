package resources::dominant_species;

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
  my $content = { 'description' => "dominant species for metagenome or set of metagenomes. id may be one or more metagenome or project ids, or the keyword 'all'",
		  'parameters'  => { "id" => "string",
				     "limit" => "int",
				     "source" => { "protein" => [ 'M5NR', map {$_->[0]} @{$ach->get_protein_sources} ],
						   "rna"     => [ 'M5RNA', map {$_->[0]} @{$ach->get_rna_sources} ]
						 }
				   },
		  'defaults' => { "limit" => 10,
				  "source" => 'M5NR'
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
    exit 0;
  }

  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: resource database offline";
    exit 0;
  }

  my $p_public = $master->Project->get_public_projects(1);
  my $m_public = $master->Job->get_public_jobs(1);
  my %p_rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();
  my %m_rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();
  my @ids  = $cgi->param('id') || ();
  my @mgs  = ();
  my $all  = 0;

  map { $p_rights{$_} = 1 } @$p_public;
  map { $m_rights{$_} = 1 } @$m_public;

  if ((scalar(@ids) == 1) && ($ids[0] eq 'public')) {
    @mgs = @$m_public;
  }
  elsif ((scalar(@ids) == 1) && ($ids[0] eq 'all')) {
    $all = 1;
  }
  elsif (scalar(@ids) >= 1) {
    my %seen = {};
    foreach my $id (@ids) {
      next if (exists $seen{$id});
      if ($id =~ /^mgm(\d+\.\d+)$/) {
	if (exists($m_rights{'*'}) || exists($m_rights{$1})) {
	  push @mgs, $1;
	}
      } elsif ($id =~ /^mgp(\d+)$/) {
	if (exists($p_rights{'*'}) || exists($p_rights{$1})) {
	  my $proj = $master->Project->init( {id => $1} );
	  foreach my $mgid (@{ $proj->metagenomes(1) }) {
	    next unless (exists($m_rights{'*'}) || exists($m_rights{$mgid}));
	    push @mgs, $mgid;
	  }
	}
      }
      $seen{$id} = 1;
    }
  }

  my $params = {};
  while (scalar(@$rest) > 1) {
    my $key = shift @$rest;
    my $value = shift @$rest;
    $params->{$key} = $value;
  }
  if ($cgi->param('limit'))  { $params->{limit}  = $cgi->param('limit'); }
  if ($cgi->param('source')) { $params->{source} = $cgi->param('source'); }
  my $limit  = ($params->{limit})  ? $params->{limit}  : 10;
  my $source = ($params->{source}) ? $params->{source} : 'M5NR';

  my $data;
  my %mg_set = map { $_, 1 } @mgs;
  my $mgdb   = MGRAST::Analysis->new( $master->db_handle );

  unless (ref($mgdb)) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access analysis database";
    exit 0;
  }

  if ((scalar(@mgs) == 0) && $all) {
    $data = $mgdb->get_global_rank_abundance($limit, 'organism', $source);
  }
  elsif (scalar(keys %mg_set) > 1) {
    $mgdb->set_jobs([keys %mg_set]);
    $data = $mgdb->get_set_rank_abundance($limit, 'organism', [$source]);
  }
  elsif (scalar(keys %mg_set) == 1) {
    $mgdb->set_jobs([keys %mg_set]);
    my $abunds = $mgdb->get_rank_abundance($limit, 'organism', [$source]);
    # mgid => [ annotation, abundance ]
    if (exists $abunds->{$mgs[0]}) {
      $data = $abunds->{$mgs[0]};
    }
  }
  else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: dominant species call requires at least one valid id parameter";
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
