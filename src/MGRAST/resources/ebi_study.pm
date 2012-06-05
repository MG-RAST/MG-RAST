package resources::ebi_study;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "ebi study",
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

  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();
  my $project;

  if ($rest && scalar(@$rest)) {
    my $id = shift @$rest;
    $id =~ s/mgp(.+)/$1/;
    $project = $master->Project->init( {id => $id} );
  } else {
    my $ids = {};
    my $public = $master->Project->get_objects( {public => 1} );
    map { $ids->{"mgp".$_->{id}} = 1 } @$public;
    map { $ids->{"mgp".$_} = 1 } keys %rights;

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode([sort keys %$ids]);
    exit 0;
  }
  
  if ($project && ref($project) && ($project->public || exists($rights{'*'}) || exists($rights{$project->id}))) {
    my $mdata = $project->data();
    my $sid   = "mgp".$project->id;
    my $cname = exists($mdata->{organization}) ? $mdata->{organization} : "EBI";
    my $pre   = "        ";
    my $attr  = "";

    foreach my $tag (keys %$mdata) {
      $attr .= $pre."<STUDY_ATTRIBUTE>\n";
      $attr .= $pre."    <TAG>".$tag."</TAG>\n";
      $attr .= $pre."    <VALUE>".$mdata->{$tag}."</VALUE>\n";
      $attr .= $pre."</STUDY_ATTRIBUTE>\n";
    }
    my $xml = qq~<?xml version="1.0" encoding="UTF-8"?>
<STUDY_SET>
<STUDY alias="$sid" center_name="$cname" broker_name="MGRAST">
     <DESCRIPTOR>
          <STUDY_TITLE>~.$project->name.qq~</STUDY_TITLE>
          <STUDY_TYPE existing_study_type="Metagenome Analysis"/>
          <CENTER_PROJECT_NAME>~.$project->name.qq~</CENTER_PROJECT_NAME>
          <STUDY_ABSTRACT>~.($mdata->{study_abstract} || " - ").qq~</STUDY_ABSTRACT>
          <STUDY_DESCRIPTION>~.($mdata->{project_description} || " - ").qq~</STUDY_DESCRIPTION>
     </DESCRIPTOR>
     <STUDY_LINKS>
     </STUDY_LINKS>
     <STUDY_ATTRIBUTES>
$attr
     </STUDY_ATTRIBUTES>
</STUDY>
</STUDY_SET>~;

    print $cgi->header(-type => 'text/xml',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $xml;
    exit 0;
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: study not found";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
