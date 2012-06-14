package resources::ebi_sample;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "ebi sample",
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
    my $mdata  = $sample->data();
    my $sampID = "mgs".$sample->ID;
    my @descs  = sort { length($b) <=> length($a) } map { $mdata->{$_} } grep { $_ =~ /description/i } keys %$mdata;
    my $dtext  = (@descs > 0) ? "<DESCRIPTION>".$descs[0]."</DESCRIPTION>" : "";
    my $name   = $sample->name ? $sample->name : (exists($mdata->{sample_name}) ? $mdata->{sample_name} : (exists($mdata->{sample_id}) ? $mdata->{sample_id} : ''));
    my $pre    = "        ";
    my $attr   = "";

    foreach my $tag (keys %$mdata) {
      $attr .= $pre."<SAMPLE_ATTRIBUTE>\n";
      $attr .= $pre."    <TAG>".$tag."</TAG>\n";
      $attr .= $pre."    <VALUE>".$mdata->{$tag}."</VALUE>\n";
      $attr .= $pre."</SAMPLE_ATTRIBUTE>\n";
    }
    my $xml = qq~<?xml version="1.0" encoding="UTF-8"?>
<SAMPLE_SET>
<SAMPLE alias="$sampID" center_name="EBI" broker_name="MGRAST">
    <TITLE>$name</TITLE>
    <SAMPLE_NAME>
        <COMMON_NAME>$name</COMMON_NAME>
    </SAMPLE_NAME>
    $dtext
    <SAMPLE_ATTRIBUTES>
$attr
    </SAMPLE_ATTRIBUTES>
</SAMPLE>
</SAMPLE_SET>
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
    print "ERROR: sample not found";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
