package resources2::metagenome;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}       = "metagenome";
    $self->{attributes} = { "id"       => [ 'string', 'unique object identifier' ],
                            "name"     => [ 'string', 'human readable identifier' ],
                            "library"  => [ 'reference library', 'reference to the related library object' ],
                            "sample"   => [ 'reference sample', 'reference to the related sample object' ],
                            "project"  => [ 'reference project', 'reference to the project object' ],
                            "metadata" => [ 'hash',    'key value pairs describing metadata' ],
                            "created"  => [ 'date',    'time the object was first created' ],
                            "version"  => [ 'integer', 'version of the object' ],
                            "url"      => [ 'uri',     'resource location of this object instance' ],
                            "sequence_type" => [ 'string', 'sequencing type' ]
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "A metagenome is an analyzed set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => $Conf::cgi_url.'/Html/api.html#'.$self->name,
                    'requests'      => [{ 'name'        => "info",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns description of parameters and attributes.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => "self",
                                          'parameters'  => { 'options'  => {},
                                                             'required' => {},
                                                             'body'     => {} }
                                        },
                                        { 'name'        => "query",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns a set of data matching the query criteria.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => { "next"   => ["uri","link to the previous set or null if this is the first set"],
                                                             "prev"   => ["uri","link to the next set or null if this is the last set"],
                                                             "order"  => ["string","name of the attribute the returned data is ordered by"],
                                                             "data"   => ["list", ["object", [$self->attributes, "list of the metagenome objects"] ]],
                                                             "limit"  => ["integer","maximum number of data items returned, default is 10"],
                                                             "offset" => ["integer","zero based index of the first returned data item"],
                                                             "total_count" => ["integer","total number of available data items"] },
                                          'parameters' => { 'options' => {
                                                                'verbosity' => ['cv',
                                                                                [['minimal','returns only minimal information'],
                                                                                 ['verbose','returns a standard subselection of metadata'],
                                                                                 ['full','returns all connected metadata']] ],
                                                                'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                'order'  => ['cv',
                                                                             [['id','return data objects ordered by id'],
                                                                              ['name','return data objects ordered by name']] ]
                                                                         },
                                                            'required' => {},
                                                            'body'     => {} }
                                        },
                                        { 'name'        => "instance",
                                          'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                          'description' => "Returns a single data object.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => $self->attributes,
                                          'parameters'  => { 'options' => {
                                                                 'verbosity' => ['cv',
                                                                                 [['minimal','returns only minimal information'],
                                                                                  ['verbose','returns a standard subselection of metadata'],
                                                                                  ['full','returns all connected metadata']] ]
                                                                          },
                                                             'required' => { "id" => ["string","unique object identifier"] },
                                                             'body'     => {} }
                                        }] };
    $self->return_data($content);
}

# method initially called from the api module
# method to parse parameters and decide which requests to process
sub request {
    my ($self) = @_;

    # check for parameters
    my @parameters = $self->cgi->param;
    if ( (scalar(@{$self->rest}) == 0) &&
         ((scalar(@parameters) == 0) || ((scalar(@parameters) == 1) && ($parameters[0] eq 'keywords'))) )
    {
        $self->info();
    }

    # check for id
    if ( scalar(@{$self->rest}) ) {
        $self->instance();
    } else {
        $self->query();
    }
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();

    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    if (scalar(@$job)) {
        $job = $job->[0];
    }
    else {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }

    # check rights
    unless ($job->public || $self->user->has_right(undef, 'view', 'metagenome', $job->metagenome_id)) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $self->prepare_data( [$job] );
    $data = $data->[0];

    $self->return_data($data);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master = $self->connect_to_datasource();
    my $jobs   = [];

    # get all user rights
    my %rights   = $self->user ? map { $_, 1 } @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    my $staruser = ($self->user && $self->user->has_right(undef, 'view', 'metagenome', '*')) ? 1 : 0;

    # get all items the user has access to
    if ($staruser) {
        $jobs = $master->Job->get_objects({viewable => 1});
    }
    else {
        $jobs = $master->Job->get_public_jobs();
        foreach my $key (keys %rights) {
            push @$jobs, $master->Job->get_objects({metagenome_id => $key})->[0];
        }
    }

    # check limit
    my $limit  = $self->cgi->param('limit')  || 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    if ($order eq 'id') {
        $order = 'metagenome_id';
    }
    @$jobs = sort { $a->{$order} cmp $b->{$order} } @$jobs;
    @$jobs = @$jobs[ $offset .. ($offset + $limit - 1) ];

    # prepare data to the correct output format
    my $data = $self->prepare_data($jobs);

    # check for pagination
    $data = $self->check_pagination($data);

    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $jobdata = {};
    if ($self->cgi->param('verbosity') && ($self->cgi->param('verbosity') ne 'minimal')) {
        use MGRAST::Metadata;
        my $jids = [];
        @$jids   = map { $_->{metagenome_id} } @$data;
        my $mddb = MGRAST::Metadata->new();
        $jobdata = $mddb->get_jobs_metadata_fast($jids, 1);
    }

    my $objects = [];
    foreach my $job (@$data) {
        my $url = $self->cgi->url;
        my $obj = {};
        $obj->{id}      = "mgm".$job->{metagenome_id};
        $obj->{name}    = $job->{name};
        $obj->{url}     = $url.'/metagenome/'.$obj->{id};
        $obj->{created} = $job->{created_on};

        if ($self->cgi->param('verbosity')) {
            if ($self->cgi->param('verbosity') eq 'full') {
                $obj->{metadata} = $jobdata->{$job->{metagenome_id}};
            }
            if (($self->cgi->param('verbosity') eq 'verbose') || ($self->cgi->param('verbosity') eq 'full')) {
                my $proj = $job->primary_project;
                my $samp = $job->sample;
                my $lib  = $job->library;
                $obj->{sequence_type} = $job->{sequence_type};
                $obj->{version} = 1;
                $obj->{project} = $proj ? ["mgp".$proj->{id}, $url."/project/mgp".$proj->{id}] : undef;
                eval { $obj->{sample} = $samp ? ["mgs".$samp->{ID}, $url."/sample/mgs".$samp->{ID}] : undef; };
            	if ($@) {
            	  $obj->{sample} = undef;
            	}
            	eval { $obj->{library} = $lib ? ["mgl".$lib->{ID}, $url."/library/mgl".$lib->{ID}] : undef; };
            	if ($@) {
            	  $obj->{library} = undef;
            	}
            } elsif ($self->cgi->param('verbosity') ne 'minimal') {
                return_data( {"ERROR" => "invalid value for option verbosity"}, 400 );
            }
        }
        push @$objects, $obj;
    }
    return $objects;
}

1;
