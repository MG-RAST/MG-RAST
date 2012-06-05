package resources::library;

use CGI;
use JSON;

use MGRAST::Metadata;
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
    my $mddb   = MGRAST::Metadata->new();
    my $mdata  = $library->data();
    my $name   = $library->name ? $library->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : '');
    my $proj   = $library->project;
    my @jobs   = grep { $_->public || exists($rights{$_->metagenome_id}) || exists($rights{'*'}) } @{ $library->jobs };
    my $libjob = (@jobs > 0) ? $jobs[0] : undef;
    my $sample = ref($library->parent) ? $library->parent : undef;
    if ($cgi->param('template')) {
      $mdata = $mddb->add_template_to_data($library->lib_type, $mdata);
    }

    $obj->{id}       = "mgl".$library->ID;
    $obj->{about}    = "metagenomics library";
    $obj->{name}     = $name;
    $obj->{url}      = $cgi->url.'/library/'.$obj->{id};
    $obj->{version}  = 1;
    $obj->{created}  = $library->entry_date;
    $obj->{metadata} = $mdata;
    $obj->{project}  = $proj ? "mgp".$proj->{id} : undef;
    $obj->{sample}   = $sample ? "mgs".$sample->{ID} : undef;
    $obj->{reads}    = $libjob ? "mgm".$libjob->metagenome_id : undef;
    $obj->{metagenome} = $libjob ? "mgm".$libjob->metagenome_id : undef;
    $obj->{sequence_sets} = $libjob ? get_sequence_sets($libjob) : [];

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
  
  my $mgid = $job->metagenome_id;
  my $rdir = $job->download_dir;
  my $adir = $job->analysis_dir;
  my $stages = [];
  if (opendir(my $dh, $rdir)) {
    my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
    closedir $dh;
    my $fnum = 1;
    foreach my $rf (@rawfiles) {
      my ($jid, $ftype) = $rf =~ /^(\d+)\.(fna|fastq)(\.gz)?$/;
      push(@$stages, { id => "mgm".$mgid."-050-".$fnum,
		       stage_id => "050",
		       stage_name => "upload",
		       stage_type => $ftype,
		       file_name => $rf });
      $fnum += 1;
    }
  }
  if (opendir(my $dh, $adir)) {
    my @stagefiles = sort grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
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
  }
  return $stages;
}

sub TO_JSON { return { %{ shift() } }; }

1;
