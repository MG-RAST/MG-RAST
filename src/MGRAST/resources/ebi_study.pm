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

  my $project;
  if ($rest && scalar(@$rest)) {
    my $id = shift @$rest;
    $id =~ s/mgp(.+)/$1/;
    $project = $master->Project->get_objects( { id => $id } );
  } else {
    my $unvalidated_objects = $master->Project->get_objects();
    my $objects = [];
    foreach my $object (@$unvalidated_objects) {
      if ($object->{public} || ($user && $user->has_right(undef, 'view', 'project', $object->{id}))) {
	push(@$objects, $object);
      }
    }
    my $pids = [];
    @$pids = map { "mgp".$_->{id} } @$objects;
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode($pids);
    exit 0;
  }
  
  if ($project) {
    $project = $project->[0];

    my $dbh = $master->db_handle();
    my $sth = $dbh->prepare("select Job.metagenome_id from ProjectJob, Job where ProjectJob.project=? and ProjectJob.job=Job._id");
    $sth->execute($project->{_id});
    my $jobs = [];
    @$jobs = map { "mgm".$_->[0] } @{$sth->fetchall_arrayref()};
    my $all_meta = $master->ProjectMD->get_objects( { project => $project } );
    my $meta_hash = {};
    %$meta_hash = map { $_->{tag} => $_->{value} } @$all_meta;
    my $samples = $master->MetaDataCollection->get_objects( { type => 'sample', project => $project } );

    my $xml = qq~<?xml version="1.0" encoding="UTF-8"?>
<STUDY_SET>
<STUDY alias="~.("mgp".$project->id).qq~" center_name="~.($meta_hash->{organization} || "-").qq~">
     <DESCRIPTOR>
          <STUDY_TITLE>~.($project->{name} || " - ").qq~</STUDY_TITLE>
          <STUDY_TYPE existing_study_type="Metagenome Analysis"/>
          <CENTER_PROJECT_NAME>~.($project->{name} || " - ").qq~</CENTER_PROJECT_NAME>
          <STUDY_ABSTRACT>~.($meta_hash->{study_abstract} || " - ").qq~</STUDY_ABSTRACT>
          <STUDY_DESCRIPTION>~.($meta_hash->{project_description} || " - ").qq~</STUDY_DESCRIPTION>
     </DESCRIPTOR>
     <STUDY_LINKS>
     </STUDY_LINKS>
     <STUDY_ATTRIBUTES>
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
    print "ERROR: project not found";
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;
