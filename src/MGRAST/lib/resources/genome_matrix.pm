package resources::genome_matrix;

use Conf;
use CGI;
use JSON;

use POSIX qw(strftime);
use LWP::UserAgent;
use Babel::lib::Babel;

my $version = "1.1";
my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "genome matrix",
		  'options' => { "id" => ["string", "metagenome or project id"],
				 "group_level" => [ ['subsystem', 'function subsystem level'],
						    ['role', 'function role level'],
						    ['level2', 'subsystem group level'],
						    ['level1', 'top hierarchy level']
						  ],
				 "format" => [ ['biom', 'Biological Observation Matrix (BIOM) format: http://biom-format.org/'],
					       ['plain', 'tab-seperated plain text format']
					     ]
			       },
		  'attributes' => { "id"                   => "string",
				    "format"               => "string",
				    "format_url"           => "uri",
				    "type"                 => "string",
				    "generated_by"         => "string",
				    "date"                 => "datetime",
				    "matrix_type"          => "string",
				    "matrix_element_type"  => "string",
				    "shape"                => "list<integer>",
				    "rows"                 => "list<object>",
				    "columns"              => "list<object>",
				    "data"                 => "list<list<integer>>"
				  },
		  'version' => $version,
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

  my $ua = LWP::UserAgent->new;
  my $cdmi_url = "http://bio-data-1.mcs.anl.gov/services/cdmi_api";

  # get params
  unless ($cgi->param('id')) {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: No ids submitted, aleast one 'id' is required";
    exit 0;
  }

  my @ids    = $cgi->param('id');
  my $type   = $cgi->param('group_level') || "subsystem";
  my $format = $cgi->param('format') || "biom";

  unless ($type =~ /^(level1|level2|subsystem|role)$/) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid group_level parameter, use one of: 'subsystem', 'role'";
    exit 0;
  }
  unless ($format =~ /^(biom|plain)$/) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid format parameter, use one of: 'biom', 'plain'";
    exit 0;
  }

  ## get genome data
  my $content;
  my $genome_data = { 'params' => [ \@ids, [ "id", "pegs", "rnas", "scientific_name", "complete", "prokaryotic", "dna_size", "contigs", "domain", "genetic_code", "gc_content", "phenotype", "md5", "source_id" ] ],
		      'method' => 'CDMI_EntityAPI.get_entity_Genome',
		      'version' => $version };
  $content = $json->encode($genome_data);
  $content =~ s/%7C/|/g;
  my $genome_info = $json->decode($ua->post($cdmi_url, Content => $content)->content)->{result}->[0];

  ## get fids for genomes
  my @gids = keys %$genome_info;
  my $fid_data = { 'params' => [ [ @gids ], [ "CDS" ] ],
		   'method' => 'CDMI_API.genomes_to_fids',
		   'version' => $version };
  $content = $json->encode($fid_data);
  $content =~ s/%7C/|/g;
  # gid => [ fids ]
  my $fid_info = $json->decode($ua->post($cdmi_url, Content => $content)->content)->{result}->[0];

  ## get functions for fids
  my $toget = ($type eq 'role') ? 'role' : 'subsystem';
  my @fids  = ();
  foreach my $g (keys %$fid_info) {
    map { push @fids, $_ } @{ $fid_info->{$g} };
  }
  my $func_data = { 'params' => [ [ @fids ] ],
		    'method' => 'CDMI_API.fids_to_'.$toget.'s',
		    'version' => $version };
  $content = $json->encode($func_data);
  $content =~ s/%7C/|/g;
  # fid => [ names ]
  my $func_info = $json->decode($ua->post($cdmi_url, Content => $content)->content)->{result}->[0];

  ## map: fid => gid
  my $gmap = {};
  foreach my $gid (keys %$fid_info) {
    map { $gmap->{$_} = $gid } @{ $fid_info->{$gid} };
  }

  ## map: subsystem => level1/2
  my $lmap = {};
  if ($type =~ /^level(1|2)$/) {
    my $num = $1 - 1;
    my $ach = new Babel::lib::Babel;
    foreach my $ss (values %{$ach->subsystem_hash()}) {
      $ss->[2] =~ s/_/ /g;
      $lmap->{$ss->[2]} = $ss->[$num];
    }
  }

  ## map: func => gid => num
  my $fmap = {};
  foreach my $fid (keys %$func_info) {
    my $g = $gmap->{$fid};
    foreach my $func ( @{$func_info->{$fid}} ) {
      if ($type =~ /^level/) {
	if (exists $lmap->{$func}) {
	  $fmap->{ $lmap->{$func} }{$g} += 1;
	}
      } else {
	$fmap->{$func}{$g} += 1;
      }
    }
  }

  ## static id list
  my @orgs  = sort keys %$fid_info;
  my @funcs = sort keys %$fmap;

  ## convert to table
  if ($format eq 'plain') {
    print $cgi->header(-type => 'text/plain',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
    print "\t".join("\t", @orgs)."\n";
    foreach my $f (@funcs) {
      print $f;
      foreach my $g (@orgs) {
	print "\t".(exists($fmap->{$f}{$g}) ? $fmap->{$f}{$g} : 0);
      }
      print "\n";
    }
    exit 0;
  }
  ## convert to biom
  else {
    my $matrix = [];
    foreach my $f (@funcs) {
      my $row = [];
      foreach my $g (@orgs) {
	push @$row, exists($fmap->{$f}{$g}) ? int($fmap->{$f}{$g}) : 0;
      }
      push @$matrix, $row;
    }
    my $data = { "id"                  => join(";", @orgs),
		 "format"              => "Biological Observation Matrix 0.9.1",
		 "format_url"          => "http://biom-format.org",
		 "type"                => "Function table",
		 "generated_by"        => "KBASE version ".$version,
		 "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
		 "matrix_type"         => "dense",
		 "matrix_element_type" => "int",
		 "shape"               => [ scalar(@funcs), scalar(@orgs) ],
		 "rows"                => [ map { { "id" => $_, "metadata" => undef } } @funcs ],
		 "columns"             => [ map { { "id" => $_, "metadata" => $genome_info->{$_} } } @orgs ],
		 "data"                => $matrix };

    my $out = $json->encode( $data );
    $out =~ s/%7C/|/g;
    print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
    print $out;
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
