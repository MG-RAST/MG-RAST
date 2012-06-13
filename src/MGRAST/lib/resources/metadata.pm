package resources::metadata;

use CGI;
use JSON;

use MGRAST::Metadata;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();
my $categories = {project => 1, sample => 1, library => 1, env_package => 1};
my $groups     = {migs => 1, mims => 1, mixs => 1};

sub about {
  my $content = { 'description' => "metadata",
		  'path components' => [ "cv", "template", "export", "export/<project id>", 'validate' ],
		  'parameters' => { validate => { group    => [keys %$groups],
						  category => [keys %$categories],
						  label    => 'string',
						  value    => 'string'
						} },
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
    error(500, "resource database offline");
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
      my $info = { aliases    => [ $o->mgrast_tag, $o->qiime_tag ],
		   definition => $o->definition,
		   required   => $o->required,
		   mixs       => $o->mixs,
		   type       => $o->type,
		   unit       => $o->unit };
      $data->{$o->category_type}{$o->category}{$o->tag} = $info;
    }
  }
  elsif ($type eq 'validate') {
    my $group = $cgi->param('group');
    my $cat   = $cgi->param('category');
    my $label = $cgi->param('label');
    my $value = $cgi->param('value');
    my $mddb  = MGRAST::Metadata->new();

    unless ($group && exists($groups->{$group})) {
      error(400, "Invalid / missing parameter 'group': ".$group." - valid types are [ '".join("', '", keys %$groups)."' ]");
    }
    unless ($cat && exists($categories->{$cat})) {
      error(400, "Invalid / missing parameter 'category': ".$cat." - valid types are [ '".join("', '", keys %$categories)."' ]");
    }
    unless ($label) {
      error(400, "Missing parameter 'label'");
    }
    unless ($value) {
      error(400, "Missing parameter 'value'");
    }

    # internal name
    if ($cat eq 'env_package') { $cat = 'ep'; }

    # special case: geo_loc_name
    if (($cat eq 'sample') && ($label eq 'geo_loc_name')) { $label = 'country'; }

    # special case: lat_lon
    if (($cat eq 'sample') && ($label eq 'lat_lon')) {
      my ($lat, $lon) = split(/\s+/, $value);
      my ($lat_valid, $lat_err) = @{ $mddb->validate_value($cat, 'latitude', $lat) };
      my ($lon_valid, $lon_err) = @{ $mddb->validate_value($cat, 'longitude', $lon) };
      if ($lat_valid && $lon_valid) {
	$data = {is_valid => 1, message => ""};
      } else {
	$data = {is_valid => 0, message => "unable to validate $value: $lat_err"};
      }
    }
    # invalid label
    elsif (! $mddb->validate_tag($cat, $label)) {
      $data = {is_valid => 0, message => "label '$label' does not exist in category '".(($cat eq 'ep') ? 'env_package' : $cat)."'"};
    }
    # not mixs label
    elsif (! $mddb->validate_mixs($label)) {
      $data = {is_valid => 0, message => "label '$label' is not a valid ".uc($group)." term"};
    }
    # test it
    else {
      my ($is_valid, $err_msg) = @{ $mddb->validate_value($cat, $label, $value) };
      if ($is_valid) {
	$data = {is_valid => 1, message => ""};
      } else {
	$data = {is_valid => 0, message => "unable to validate $value: $err_msg"};
      }
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
	error(400, "project not found");
      }
      unless ($project->public || ($user && ($user->has_right(undef, 'view', 'project', '*') || $user->has_right(undef, 'view', 'project', $id)))) {
	error(401, "Invalid authentication for project id: mgp".$id);
      }
      my $mddb = MGRAST::Metadata->new();
      $data = $mddb->export_metadata_for_project($project);
    }
  }
  else {
    error(400, "Invalid type for metadata call: ".$type." - valid types are [ 'cv', 'template', 'export', 'validate' ]");
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($data);
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;

sub error {
  my ($num, $msg) = @_;

  print $cgi->header(-type => 'text/plain',
		     -status => $num,
		     -Access_Control_Allow_Origin => '*' );
  print "ERROR: $msg";
  exit 0;
}
