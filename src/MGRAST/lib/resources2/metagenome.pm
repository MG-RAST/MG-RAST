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
    my %rights = $self->user ? map { $_, 1 } @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "metagenome";
    $self->{rights} = \%rights;
    $self->{attributes} = { "id"       => [ 'string', 'unique object identifier' ],
                            "name"     => [ 'string', 'human readable identifier' ],
                            "library"  => [ 'reference library', 'reference to the related library object' ],
                            "sample"   => [ 'reference sample', 'reference to the related sample object' ],
                            "project"  => [ 'reference project', 'reference to the project object' ],
                            "metadata" => [ 'hash', 'key value pairs describing metadata' ],
                            "created"  => [ 'date', 'time the object was first created' ],
                            "version"  => [ 'integer', 'version of the object' ],
                            "url"      => [ 'uri', 'resource location of this object instance' ],
                            "status"   => [ 'cv', [ ['public', 'object is public'],
						    ['private', 'object is private'] ] ],
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
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $id does not exist"}, 404 );
    }
    $job = $job->[0];

    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || ($self->user && $self->user->has_right(undef, 'view', 'metagenome', '*'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # get cached if exists
    my $cached = $self->memd->get($self->url_id);
    if ($cached) {
        # do a runaround on ->return_data
        print $self->header;
        print $cached;
        exit 0;
    }
    # prepare data
    my $data = $self->prepare_data( [$job] );
    $data = $data->[0];
    $self->return_data($data, undef, 1); # cache this!
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master = $self->connect_to_datasource();
    my $jobs   = [];
    my $total  = 0;

    # check pagination
    my $limit  = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    if ($order eq 'id') {
        $order = 'metagenome_id';
    }

    if ($limit == 0) {
        $limit = 18446744073709551615;
    }
    # get all items the user has access to
    if (exists $self->rights->{'*'}) {
        $total = $master->Job->count_all();
        $jobs  = $master->Job->get_objects( {$order => [undef, "viewable=1 ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    } else {
        my $public = $master->Job->get_public_jobs(1);
        my $list   = join(',', (@$public, keys %{$self->rights}));
        $total = scalar(@$public) + scalar(keys %{$self->rights});
        $jobs  = $master->Job->get_objects( {$order => [undef, "viewable=1 AND metagenome_id IN ($list) ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    }
    $limit = ($limit > scalar(@$jobs)) ? scalar(@$jobs) : $limit;
    
    # prepare data to the correct output format
    my $data = $self->prepare_data($jobs);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);

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
        $obj->{status}  = $job->{public} ? 'public' : 'private';
        $obj->{url}     = $url.'/metagenome/'.$obj->{id};
        $obj->{created} = $job->{created_on};

        if ($self->cgi->param('verbosity')) {
            if ($self->cgi->param('verbosity') eq 'full') {
                $obj->{metadata} = $jobdata->{$job->{metagenome_id}};
            }
            if (($self->cgi->param('verbosity') eq 'verbose') || ($self->cgi->param('verbosity') eq 'full')) {
                my $proj;
		eval {
		  $proj = $job->primary_project;
		};
                my $samp;
		eval {
		  $samp = $job->sample;
		};
                my $lib;
		eval {
		  $lib = $job->library;
		};
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
