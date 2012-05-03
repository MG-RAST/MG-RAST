package resources::sample;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenomic sample",
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

  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'metagenome')} : ();
  my $dbh = $master->db_handle;
  my $sample;

  if ($rest && scalar(@$rest)) {
    my $id = shift @$rest;
    $id =~ s/mgs(.+)/$1/;
    $sample = $master->MetaDataCollection->init( {ID => $id} );
  } else {
    my $ids = {};
    my $sample_map   = {};
    my $job_samp_map = {};
    my $job_samples  = $dbh->selectall_arrayref("SELECT sample, metagenome_id, public FROM Job");
    map { $job_samp_map->{$_->[0]} = 1 }  @$job_samples;
    map { $sample_map->{$_->[0]} = $_->[1] } @{$dbh->selectall_arrayref("SELECT _id, ID FROM MetaDataCollection WHERE type='sample'")};

    # add samples with job: public or rights
    map { $ids->{"mgs".$sample_map->{$_->[0]}} = 1 } grep { ($_->[2] == 1) || exists($rights{$_->[1]}) || exists($rights{'*'}) } @$job_samples;
    # add samples with no job
    map { $ids->{"mgs".$sample_map->{$_}} = 1 } grep { ! exists $job_samp_map->{$_} } keys %$sample_map;
    
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode([sort keys %$ids]);
    exit 0;
  }

  if ($sample && ref($sample)) {
    my $obj   = {};
    my $mdata = $sample->data();
    my $name  = $sample->name ? $sample->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : (exists($mdata->{sample_id}) ? $mdata->{sample_id} : ''));
    my $proj  = $sample->project;
    my $epack = $sample->children('ep');
    my @jobs  = grep { $_->{public} || exists($rights{$_->{metagenome_id}}) || exists($rights{'*'}) } @{ $sample->jobs };

    $obj->{id}       = "mgs".$sample->ID;
    $obj->{about}    = "sample";
    $obj->{name}     = $name;
    $obj->{url}      = $cgi->url.'/sample/'.$obj->{id};
    $obj->{version}  = 1;
    $obj->{created}  = $sample->entry_date;
    $obj->{metadata} = $mdata;
    $obj->{project}  = $proj ? "mgp".$proj->{id} : undef;
    $obj->{env_package} = @$epack ? "mge".$epack->[0]->{ID} : undef;
    @{ $obj->{libraries} } = map { "mgl".$_->{ID} } @{ $sample->children('library') };
    @{ $obj->{metagenomes} } = map { "mgm".$_->{metagenome_id} } @jobs;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($obj);
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: sample not found";
    exit 0;
  }

}

sub TO_JSON { return { %{ shift() } }; }

1;
