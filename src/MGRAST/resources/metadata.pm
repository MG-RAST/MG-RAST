package resources::metadata;

use CGI;
use JSON;

use MGRAST::Metadata;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metadata",
		  'path components' => [ "cv", "template", "export", "export/<project id>" ],
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
  if ($rest && ( (@$rest == 0) || ((@$rest == 1) && ($rest->[0] eq 'about')) )) {
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

  my $type = shift @$rest;
  my $data = {};

  if ($type eq 'cv') {
    my $objs = $master->MetaDataCV->get_objects();
    foreach my $o (@$objs) {
      if ($o->type eq 'select') {
	push @{ $data->{$o->type}{$o->tag} }, $o->value;
      }
      else {
	$data->{$o->type}{$o->tag} = $o->value;
      }
    }
  }
  elsif ($type eq 'template') {
    my $objs = $master->MetaDataTemplate->get_objects();
    foreach my $o (@$objs) {
      my $info = { qiime_tag  => $o->qiime_tag,
		   mgrast_tag => $o->mgrast_tag,
		   definition => $o->definition,
		   required   => $o->required,
		   mixs       => $o->mixs,
		   type       => $o->type };
      $data->{$o->category_type}{$o->category}{$o->tag} = $info;
    }
  }
  elsif ($type eq 'export') {
    if (@$rest == 0) {
      my $ids = {};
      my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();
      if (exists $rights{'*'}) {
	map { $ids->{"mgp".$_->{id}} = 1 } @{ $master->Project->get_objects() };
      }
      else {
	my $public = $master->Project->get_objects( {public => 1} );
	map { $ids->{"mgp".$_->{id}} = 1 } @$public;
	map { $ids->{"mgp".$_} = 1 } keys %rights;
      }
      $data = [sort keys %$ids];
    }
    else {
      my $id = shift @$rest;
      $id =~ s/mgp(.+)/$1/;
      my $project = $master->Project->init( {id => $id} );
      unless ($project && ref($project)) {
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: project not found";
	exit 0;
      }
      unless ($project->public || ($user && ($user->has_right(undef, 'view', 'project', '*') || $user->has_right(undef, 'view', 'project', $id)))) {
	print $cgi->header(-type => 'text/plain',
			   -status => 401,
			   -Access_Control_Allow_Origin => '*' );
	print "ERROR: Invalid authentication for project id: mgp".$id;
	exit 0;
      }
      my $mddb = MGRAST::Metadata->new();
      $data = $mddb->export_metadata_for_project($project);
    }
  }
  else {
    print $cgi->header(-type => 'text/plain',
		       -status => 400,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid type for metadata call: ".$type." - valid types are [ 'cv', 'template', 'export' ]";
    exit 0;
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
