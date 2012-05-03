package resources::library;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenomic library",
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
  my $library;

  if ($rest && scalar(@$rest)) {
    my $id = shift @$rest;
    $id =~ s/mgl(.+)/$1/;
    $library = $master->MetaDataCollection->init( {ID => $id} );
  } else {
    my $ids = {};
    my $library_map = {};
    my $job_lib_map = {};
    my $job_library = $dbh->selectall_arrayref("SELECT library, metagenome_id, public FROM Job");
    map { $job_lib_map->{$_->[0]} = 1 }  @$job_library;
    map { $library_map->{$_->[0]} = $_->[1] } @{$dbh->selectall_arrayref("SELECT _id, ID FROM MetaDataCollection WHERE type='library'")};

    # add libraries with job: public or rights
    map { $ids->{"mgl".$library_map->{$_->[0]}} = 1 } grep { ($_->[2] == 1) || exists($rights{$_->[1]}) || exists($rights{'*'}) } @$job_library;
    # add libraries with no job
    map { $ids->{"mgl".$library_map->{$_}} = 1 } grep { ! exists $job_lib_map->{$_} } keys %$library_map;
    
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode([sort keys %$ids]);
    exit 0;
  }

  if ($library && ref($library)) {
    my $obj    = {};
    my $mdata  = $library->data();
    my $name   = $library->name ? $library->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : '');
    my $proj   = $library->project;
    my @jobs   = grep { $_->public || exists($rights{$_->metagenome_id}) || exists($rights{'*'}) } @{ $library->jobs };
    my $sample = $master->MetaDataCollection->get_objects( {parent => $library, type => 'sample'} );

    $obj->{id}       = "mgl".$library->ID;
    $obj->{about}    = "metagenomics library";
    $obj->{name}     = $name;
    $obj->{url}      = $cgi->url.'/library/'.$obj->{id};
    $obj->{version}  = 1;
    $obj->{created}  = $library->entry_date;
    $obj->{metadata} = $mdata;
    $obj->{project}  = $proj ? "mgp".$proj->{id} : undef;
    $obj->{sample}   = @$sample ? $sample->[0]->{ID} : undef;
    @{ $obj->{metagenomes} } = map { "mgm".$_->metagenome_id } @jobs;
    @{ $obj->{sequence_sets} } = map { get_sequence_sets($_) } @jobs;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($obj);
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: library not found";
    exit 0;
  }

}

sub get_sequence_sets {
  my ($job) = @_;
  
  my $adir   = $job->analysis_dir;
  my $stages = [];
  if (opendir(my $dh, $adir)) {
    my @stagefiles = grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
    closedir $dh;
    my $stagehash = {};
    foreach my $sf (@stagefiles) {
      my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
      next unless ($stageid && $stagename && $stageresult);
      if (exists($stagehash->{$stageid})) {
	$stagehash->{$stageid}++;
      } else {
	$stagehash->{$stageid} = 1;
      }
      push(@$stages, { id => "mgm".$mgid."-".$stageid."-".$stagehash->{$stageid},
		       stage_id => $stageid,
		       stage_name => $stagename,
		       stage_type => $stageresult,
		       file_name => $sf });
    }
    return $stages;
  } else {
    return [];
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
