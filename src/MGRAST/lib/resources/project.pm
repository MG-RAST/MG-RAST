package resources::project;

use CGI;
use JSON;

use HTML::Entities;
use MGRAST::Metadata;
use WebServiceObject;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8(); 

=pod

=head1 NAME

project resource

=head1 DESCRIPTION

returns requested project information

=head1 EXAMPLES

=over 4

=item * api.cgi/project/mgp10

=item * api.cgi/project?display=name&display=pi

=cut

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
    my $projects= ();
    if (exists $rights{'*'}) {
      push @$projects, @{ $master->Project->get_objects() };
    } else {
      my $public = $master->Project->get_public_projects();
      push @$projects, @$public;
      push @$projects, keys %rights;
    }
    
    my @results;

    # Returning the 'display' attributes for all requested projects.
    foreach my $project (@$projects) {
      my @attributes = $cgi->param('display');
      my $metadata;
      my @colls = ();
      
      my $obj  = {};

      foreach my $attr (@attributes) {
        if($attr eq 'id')                  { $obj->{id}             = "mgp".$project->id;
	} elsif($attr eq 'name')           { $obj->{name}           = $project->name;
	} elsif($attr eq 'analyzed')       {
          @jobs       = map { "mgm".$_ } @{ $project->all_metagenome_ids };
          $obj->{analyzed}       = \@jobs
	} elsif($attr eq 'pi')             { $obj->{pi}             = $project->pi;
	} elsif($attr eq 'metadata')       {
          $metadata   = $project->data();
          $obj->{metadata}       = $metadata;
	} elsif($attr eq 'description')    {
          $metadata   = $project->data();
          $metadata->{project_description} || $metadata->{study_abstract} || " - ";
          $obj->{description}    = $desc;
	} elsif($attr eq 'funding_source') {
          $metadata   = $project->data();
          $metadata->{project_funding} || " - ";
          $obj->{funding_source} = $fund;
	} elsif($attr eq 'samples') {
          @colls      = @{ $project->collections };
          @samples    = map { "mgs".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
          $obj->{samples}        = \@samples;
	} elsif($attr eq 'libraries')      {
          @colls      = @{ $project->collections };
          @libraries  = map { "mgl".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
          $obj->{libraries}      = \@libraries;
	} elsif($attr eq 'about')          { $obj->{about}          = "metagenomics project";
	} elsif($attr eq 'version')        { $obj->{version}        = 1;
	} elsif($attr eq 'url')            { $obj->{url}            = $cgi->url.'/project/'.$obj->{id};
	} elsif($attr eq 'created')        { $obj->{created}        = "";
        }
      }
      push @results, $obj;
    }
  
    print $cgi->header(-type => 'application/json',
           -status => 200,
           -Access_Control_Allow_Origin => '*' );
    print $json->encode(\@results);
    exit 0;
  }
  
  if ($project && ref($project) && ($project->public || exists($rights{'*'}) || exists($rights{$project->id}))) {
    my $metadata  = $project->data();
    my @jobs      = map { "mgm".$_ } @{ $project->all_metagenome_ids };
    my @colls     = @{ $project->collections };
    my @samples   = map { "mgs".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
    my @libraries = map { "mgl".$_->{ID} } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
    
    my $obj  = {};
    my $mddb = MGRAST::Metadata->new();
    my $desc = $metadata->{project_description} || $metadata->{study_abstract} || " - ";
    my $fund = $metadata->{project_funding} || " - ";
    if ($cgi->param('template')) {
      $metadata = $mddb->add_template_to_data('project', $metadata);
    }

    $obj->{id}             = "mgp".$project->id;
    $obj->{name}           = $project->name;
    $obj->{analyzed}       = \@jobs;
    $obj->{pi}             = $project->pi;
    $obj->{metadata}       = $metadata;
    $obj->{description}    = $desc;
    $obj->{funding_source} = $fund;
    $obj->{samples}        = \@samples;
    $obj->{libraries}      = \@libraries;
    $obj->{about}          = "metagenomics project";
    $obj->{version}        = 1;
    $obj->{url}            = $cgi->url.'/project/'.$obj->{id};
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
