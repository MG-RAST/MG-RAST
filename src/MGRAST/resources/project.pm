package resources::project;

use CGI;
use JSON;

use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "metagenomic project",
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

  my %rights = $user ? map {$_, 1} @{$user->has_right_to(undef, 'view', 'project')} : ();
  my $project;

  if ($rest && scalar(@$rest)) {
    my $id = shift @$rest;
    $id =~ s/mgp(.+)/$1/;
    $project = $master->Project->init( {id => $id} );
  } else {
    my $ids = {};
    if (exists $rights{'*'}) {
      map { $ids->{"mgp".$_->{id}} = 1 } @{ $master->Project->get_objects() };
    }
    else {
      my $public = $master->Project->get_objects( {public => 1} );
      map { $ids->{"mgp".$_->{id}} = 1 } @$public;
      map { $ids->{"mgp".$_} = 1 } keys %rights;
    }
    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode([sort keys %$ids]);
    exit 0;
  }
  
  if ($project && ref($project) && ($project->public || exists($rights{'*'}) || exists($rights{$project->id}))) {

    my %meta_hash = map { $_->{tag} => $_->{value} } @{ $master->ProjectMD->get_objects({project => $project}) };
    my $obj  = {};
    my $data = $project->data();
    my $dbh  = $master->db_handle();
    my $sth  = $dbh->prepare("select Job.metagenome_id from ProjectJob, Job where ProjectJob.project=? and ProjectJob.job=Job._id");
    $sth->execute($project->_id);

    my @jobs = map { "mgm".$_->[0] } @{ $sth->fetchall_arrayref() };
    my @colls = map { $_->collection } @{ $master->ProjectCollection->get_objects({project => $project}) };
    my @samples = map { "mgs".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
    my @libraries = map { "mgl".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
    
    $obj->{id}             = "mgp".$project->id;
    $obj->{name}           = $project->name;
    $obj->{analyzed}       = \@jobs;
    $obj->{pi}             = $project->pi;
    $obj->{metadata}       = \%meta_hash;
    $obj->{description}    = $meta_hash->{project_description} || $meta_hash->{study_abstract} || " - ";
    $obj->{funding_source} = $meta_hash->{project_funding} || " - ";
    $obj->{samples}        = \@samples;
    $obj->{libraries}      = \@libraries;
    $obj->{about}          = "metagenomics project";
    $obj->{version}        = 1;
    $obj->{url}            = $cgi->url.'/project/'.$object->{id};
    $obj->{created}        = "";

    print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    print $json->encode( $obj );
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
