package resources::project;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    $self->{name} = "project";
    $self->{rights} = \%rights;
    $self->{attributes} = { "id"             => [ 'string', 'unique object identifier' ],
    	                    "name"           => [ 'string', 'human readable identifier' ],
    	                    "libraries"      => [ 'list', [ 'reference library', 'a list of references to the related library objects' ] ],
			                "samples"        => [ 'list', [ 'reference sample', 'a list of references to the related sample objects' ] ],
			                "metagenomes"    => [ 'list', [ 'reference metagenome', 'a list of references to the related metagenome objects' ] ],
    	                    "description"    => [ 'string', 'a short, comprehensive description of the project' ],
    	                    "funding_source" => [ 'string', 'the official name of the source of funding of this project' ],
    	                    "pi"             => [ 'string', 'the first and last name of the principal investigator of the project' ],
    	                    "metadata"       => [ 'hash', 'key value pairs describing metadata' ],
    	                    "created"        => [ 'date', 'time the object was first created' ],
    	                    "version"        => [ 'integer', 'version of the object' ],
    	                    "url"            => [ 'uri', 'resource location of this object instance' ],
    	                    "status"         => [ 'cv', [ ['public', 'object is public'],
							  ['private', 'object is private'] ] ]
    	                  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "A project is a composition of samples, libraries and metagenomes being analyzed in a global context.",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $self->cgi->url."/".$self->name,				      
				      'description' => "Returns a set of data matching the query criteria.",
				      'example'     => [ $self->cgi->url."/".$self->name."?limit=20&order=name",
    				                     'retrieve the first 20 projects ordered by name' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "next"   => [ "uri", "link to the previous set or null if this is the first set" ],
							 "prev"   => [ "uri", "link to the next set or null if this is the last set" ],
							 "order"  => [ "string", "name of the attribute the returned data is ordered by" ],
							 "data"   => [ "list", [ "object", [$self->attributes, "list of the project objects"] ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ],
									    'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->cgi->url."/".$self->name."/mgp128?verbosity=full",
      				                     'retrieve all data for project mgp128' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				     ]
				 };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my ($id) = $rest->[0] =~ /^mgp(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();

    # check if this is an action request
    my $requests = { 'movemetagenomes' => 1 };
    if (scalar(@$rest) > 1 && $requests->{$rest->[1]}) {
      # move metagenomes to a different project
      if ($rest->[1] eq 'movemetagenomes') {
	unless ($self->user->has_star_right('edit', 'user')) {
	  $self->return_data( {"ERROR" => "insufficient permissions for this user call"}, 401 );
	}
	my ($id2) = $self->cgi->param('target') =~ /^mgp(\d+)$/;
	if (! $id2) {
	   $self->return_data( {"ERROR" => "invalid id format: " . $self->cgi->param('target')}, 400 );
	}
	my $project_a = $master->Project->init( {id => $id} );
	my $project_b = $master->Project->init( {id => $id2} );

	unless (ref($project_a) && ref($project_b)) {
	  $self->return_data( {"ERROR" => "id $id or $id2 does not exists"}, 404 );
	}

	my $proj_job = $master->ProjectJob->get_objects({ project => $project_a });
	my $job_a_hash = {};
	foreach my $j (@$proj_job) {
	  $job_a_hash->{$j->job->{metagenome_id}} = $j->job;
	}
	my @move_over = $self->cgi->param("move");
	foreach my $m (@move_over) {
	  $m =~ s/^mgm//;
	  unless ($job_a_hash->{$m}) {
	    $self->return_data( {"ERROR" => "metagenome not part of source project: " . $m}, 400 );
	  }
	}

	foreach my $m (@move_over) {
	  my $job = $master->Job->get_objects( { metagenome_id => $m });
	  if (scalar(@$job)) {
	    $job = $job->[0];
	    $project_a->remove_job($job);
	    $project_b->add_job($job);
	  }
	}

	$self->return_data( {"OK" => "metagenomes moved"}, 200 );
      }
    }
  
    # get data
    my $project = $master->Project->init( {id => $id} );
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }

    # check rights
    unless ($project->{public} || exists($self->rights->{$id}) || exists($self->rights->{'*'})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # return cached if exists
    $self->return_cached();
    
    # prepare data
    my $data = $self->prepare_data( [$project] );
    $data = $data->[0];
    $self->return_data($data, undef, 1); # cache this!
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master   = $self->connect_to_datasource();
    my $projects = [];
    my $total    = 0;

    # check pagination
    my $limit  = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";

    if ($limit == 0) {
        $limit = 18446744073709551615;
    }

    # check if we just want the private projects
    if ($self->cgi->param('private')) {
      unless ($self->user) {
	$self->return_data({"ERROR" => "private option requires authentication"}, 400);
      }
      my $ids = [];
      if ($self->cgi->param('edit')) {
	$ids = $self->user->has_right_to(undef, 'edit', 'project');
      } else {
	$ids = $self->user->has_right_to(undef, 'view', 'project');
      }
      if (scalar(@$ids) && $ids->[0] eq '*') {
	shift @$ids;
      }
      my $list = join(",", @$ids);
      $total = scalar(@$ids);
      $projects = $master->Project->get_objects( {$order => [undef, "id IN ($list) ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    }
    # get all items the user has access to
    elsif (exists $self->rights->{'*'}) {
        $total    = $master->Project->count_all();
        $projects = $master->Project->get_objects( {$order => [undef, "_id IS NOT NULL ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    } else {
        my $public = $master->Project->get_public_projects(1);
        my $list   = join(',', (@$public, keys %{$self->rights}));
        $total     = scalar(@$public) + scalar(keys %{$self->rights});
        $projects  = $master->Project->get_objects( {$order => [undef, "id IN ($list) ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    }
    $limit = ($limit > scalar(@$projects)) ? scalar(@$projects) : $limit;
    
    # prepare data to the correct output format
    my $data = $self->prepare_data($projects);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);

    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $objects = [];
    foreach my $project (@$data) {
        my $url = $self->cgi->url;
        my $obj = {};
        $obj->{id}      = "mgp".$project->id;
        $obj->{name}    = $project->name;
        $obj->{pi}      = $project->pi;
        $obj->{status}  = $project->public ? 'public' : 'private';
        $obj->{version} = 1;
        $obj->{url}     = $url.'/project/'.$obj->{id};
        $obj->{created} = "";
    
        if ($self->cgi->param('verbosity')) {
            if ($self->cgi->param('verbosity') eq 'full') {
	        my @jobs      = map { ["mgm".$_, $url.'/metagenome/mgm'.$_] } @{ $project->all_metagenome_ids };
	        my @colls     = @{ $project->collections };
	        my @samples   = map { ["mgs".$_->{ID}, $url."/sample/mgs".$_->{ID}] } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
	        my @libraries = map { ["mgl".$_->{ID}, $url."/library/mgl".$_->{ID}] } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
	        $obj->{metagenomes} = \@jobs;	
	        $obj->{samples}   = \@samples;
	        $obj->{libraries} = \@libraries;
            }
            if (($self->cgi->param('verbosity') eq 'verbose') || ($self->cgi->param('verbosity') eq 'full') || ($self->cgi->param('verbosity') eq 'summary')) {
	        my $metadata  = $project->data();
	        my $desc = $metadata->{project_description} || $metadata->{study_abstract} || " - ";
	        my $fund = $metadata->{project_funding} || " - ";
	        $obj->{metadata}       = $metadata;
	        $obj->{description}    = $desc;
	        $obj->{funding_source} = $fund;
		
		if ($self->cgi->param('verbosity') eq 'summary') {
		  my $jdata = $project->metagenomes_summary();
		  $obj->{metagenomes} = [];
		  foreach my $row (@$jdata) {
		    push(@{$obj->{metagenomes}}, { metagenome_id => $row->[0],
						   name => $row->[1],
						   basepairs => $row->[2],
						   sequences => $row->[3],
						   biome => $row->[4],
						   feature => $row->[5],
						   material => $row->[6],
						   location => $row->[7],
						   country => $row->[8],
						   coordinates => $row->[9],
						   sequence_type => $row->[10],
						   sequencing_method => $row->[11] });
		  }
		}
            } elsif ($self->cgi->param('verbosity') ne 'minimal') {
	        $self->return_data( {"ERROR" => "invalid value for option verbosity"}, 400 );
            }
        }
        push @$objects, $obj;      
    }
    return $objects;
}

1;
