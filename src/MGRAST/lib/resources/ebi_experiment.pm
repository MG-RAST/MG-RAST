package resources::ebi_experiment;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "ebi experiment",
		  'parameters' => { "id" => "string" },
		  'return_type' => "text/xml" };

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
    my $mdata  = $library->data();
    my $libID  = "mgl".$library->ID;
    my $name   = $library->name ? $library->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : '');
    my @descs  = sort { length($b) <=> length($a) } map { $mdata->{$_} } grep { $_ =~ /description/i } keys %$mdata;
    my $dtext  = (@descs > 0) ? "<DESIGN_DESCRIPTION>".$descs[0]."</DESIGN_DESCRIPTION>" : '';
    my $study  = ref($library->project) ? "<STUDY_REF refname=\"mgp".$library->project->{id}."\" />" : '';
    my $sample = ref($library->parent) ? "<SAMPLE_DESCRIPTOR refname=\"mgs".$library->parent->{ID}."\" />" : '';
    my $lprot  = exists($mdata->{lib_construction}) ? "<LIBRARY_CONSTRUCTION_PROTOCOL>".$mdata->{lib_construction}."</LIBRARY_CONSTRUCTION_PROTOCOL>" : '';
    my $method = exists($mdata->{seq_method}) ? uc($mdata->{seq_method}) : "UNKNOWN";
    my $model  = exists($mdata->{seq_model}) ? $mdata->{seq_model} : lc($method);
    my $pre    = "        ";
    my $attr   = "";

    foreach my $tag (keys %$mdata) {
      $attr .= $pre."<EXPERIMENT_ATTRIBUTE>\n";
      $attr .= $pre."    <TAG>".$tag."</TAG>\n";
      $attr .= $pre."    <VALUE>".$mdata->{$tag}."</VALUE>\n";
      $attr .= $pre."</EXPERIMENT_ATTRIBUTE>\n";
    }
    my $xml = qq~<?xml version="1.0" encoding="UTF-8"?>
<EXPERIMENT_SET>
<EXPERIMENT alias="$libID" center_name="EBI" broker_name="MGRAST">
    <TITLE>$name</TITLE>
    $study
    <DESIGN>
        $dtext
        $sample
        <LIBRARY_DESCRIPTOR>
            <LIBRARY_NAME>$name</LIBRARY_NAME>
            $lprot
        </LIBRARY_DESCRIPTOR>
    </DESIGN>
    <PLATFORM>
        <$method>
            <INSTRUMENT_MODEL>$model</INSTRUMENT_MODEL>
        </$method>
    </PLATFORM>
    <PROCESSING/>
    <EXPERIMENT_ATTRIBUTES>
$attr
    </EXPERIMENT_ATTRIBUTES>
</EXPERIMENT>
</EXPERIMENT_SET>
~;
    print $cgi->header(-type => 'text/xml',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $xml;
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: experiment not found";
    exit 0;
  }

}

sub TO_JSON { return { %{ shift() } }; }

1;
