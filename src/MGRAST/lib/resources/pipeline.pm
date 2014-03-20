package resources::pipeline;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use parent qw(resources::resource);
use WebApplicationDBHandle;

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    $self->{name} = "pipeline";
    $self->{rights} = \%rights;
    $self->{version} = '3.0';
    $self->{attributes} = { data    => [ 'list', ['object', 'workflow document'] ],
                            version => [ 'integer', 'version of the pipeline' ],
                            url     => [ 'uri', 'resource location of this object instance' ] };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
                    'url' => $self->cgi->url."/".$self->name,
                    'description' => "The user resource returns information about a user.",
                    'type' => 'object',
                    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
                    'requests' => [ { 'name'        => "info",
                                      'request'     => $self->cgi->url."/".$self->name,
                                      'description' => "Returns description of parameters and attributes.",
                                      'method'      => "GET" ,
                                      'type'        => "synchronous" ,  
                                      'attributes'  => "self",
                                      'parameters'  => { 'options'  => {},
                                                         'required' => {},
                                                         'body'     => {} } },
                                    { 'name'        => "instance",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Returns a single user object.",
                                      'example'     => [ 'curl -X GET -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'/{job ID}"',
                    			                         "job in pipeline" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'  => {},
                                                         'required' => { "id" => ["string","unique object identifier"] },
                                                         'body'     => {} } },
                                    { 'name'        => "query",
                                      'request'     => $self->cgi->url."/".$self->name,
                                      'description' => "Returns a set of data matching the query criteria.",
                                      'example'     => [ 'curl -X GET -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'?user=johndoe"',
                    			                         "jobs in pipeline for user johndoe" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'  => { "user" => ["string", "user ID or login"],
                                                                         "project" => ["string", "project ID"],
                                                                         'verbosity' => ['cv', [['minimal','returns only minimal information'],
                                                                                                ['full','returns full workflow documents']]] },
                                                         'required' => {},
                                                         'body'     => {} } }
                                ]
                        };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;

    # set params
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    my $job  = undef;
    my $rest = $self->rest;
    my $master = $self->connect_to_datasource();
    my $url = $self->cgi->url.'/'.$rest->[0].'?verbosity='.$verb;
    
    # metagenome ID
    if ($rest->[0] =~ /^mgm(\d+\.\d+)$/) {
        $job = $master->Job->get_objects( {metagenome_id => $1} );
    }
    # job ID
    elsif ($rest->[0] =~ /^\d+$/) {
        $job = $master->Job->get_objects( {job_id => $rest->[0]} );
    }
    # bad ID
    else {
        $self->return_data( {"ERROR" => "invalid id format: ".$rest->[0]}, 400 );
    }
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id ".$rest->[0]." does not exist"}, 404 );
    }
    $job = $job->[0];
    
    # check rights
    unless ($job->{public} || exists($self->rights->{$job->{metagenome_id}}) || ($self->user && $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    my $data = $self->prepare_data({'info.name' => $job->{job_id}});
    my $obj = { data => $data->[0], version => $self->{version}, url => $url };
    $self->return_data($obj);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    
    # get paramaters
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    my $user = $self->cgi->param('user') || '';
    my $project = $self->cgi->param('project') || '';
    my $query = {};
    
    # build url
    my $url = $self->cgi->url.'/'.$self->name.'?verbosity='.$verb;
    if ($user) {
        $url .= '&user='.$user
    }
    if ($project) {
        $url .= '&project='.$project
    }
    
    # get user ID
    if ($user) {
        $query->{'info.user'} = $self->user_id($user);
    }
    # get project ID
    if ($project) {
        if ($project =~ /^mgp(\d+)$/) {
            my $pobj = $master->Project->init( {id => $1} );
            unless (ref($pobj)) {
                $self->return_data( {"ERROR" => "project $project does not exists"}, 404 );
            }
            # check rights
            unless ($pobj->{public} || exists($self->rights->{$pobj->{id}}) || exists($self->rights->{'*'})) {
                $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
            }
            $query->{'info.project'} = 'mgp'.$pobj->{id};
        } else {
            $self->return_data( {"ERROR" => "invalid id format: $project"}, 400 );
        }
    }
    # get user if no options
    if (! %$query) {
        $query->{'info.user'} = $self->user_id();
    }
    
    my $data = $self->prepare_data($query);
    my $obj = { data => $data, version => $self->{version}, url => $url };
    $self->return_data($obj);
}

sub prepare_data {
    my ($self, $query) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    
    $query->{'info.pipeline'} = 'mgrast-prod';
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    my $data = $self->get_awe_query($query);
    if ($verb eq 'minimal') {
        my $objs = [];
        foreach my $d (@$data) {
            my $job = $master->Job->get_objects( {job_id => $d->{info}{name}} );
            unless ($job && @$job) {
                next;
            }
            $job = $job->[0];
            my $min = { stages  => [],
                        id      => 'mgm'.$job->metagenome_id,
                        job_id  => $job->job_id,
                        name    => $job->name,
                        status  => $d->{state},
                        awe_id  => $d->{id},
                        project_id   => 'mgp'.$job->primary_project->{id},
                        project_name => $job->primary_project->{name},
                        user_id      => 'mgu'.$job->owner->{_id},
                        user_name    => $job->owner->{login},
                        submitted    => $d->{info}{submittime}
            };
            foreach my $t (@{$d->{tasks}}) {
                push @{$min->{stages}}, { name => $t->{cmd}{description},
                                          status => $t->{state},
                                          started => $t->{starteddate},
                                          completed => $t->{completeddate} };
            }
            push @$objs, $min;
        }
        return $objs;
    } else {
        return $data;
    }
}

sub user_id {
    my ($self, $user) = @_;
    
    my $uid = undef;
    # validate and get user_id
    if ($user) {
        # get database
        my ($master, $error) = WebApplicationDBHandle->new();
        if ($error) {
            $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 503 );
        }
        
        # get data
        my $uobj = [];
        if ($user =~ /^mgu(\d+)$/) { # user id
            $uobj = $master->User->get_objects( {"_id" => $1} );
        } else { # user login
            $uobj = $master->User->get_objects( {"login" => $user} );
        }
        unless (scalar(@$uobj)) {
            $self->return_data( {"ERROR" => "user '".$user."' does not exists"}, 404 );
        }
        $uobj = $uobj->[0];

        # check rights
        unless ($self->user && ($self->user->has_right(undef, 'edit', 'user', $uobj->{_id}) || $self->user->has_star_right('edit', 'user'))) {
            $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
        }
        $uid = $uobj->{_id};
    } elsif ($self->user) {
        $uid = $self->user->{_id};
    } else {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    return 'mgu'.$uid;
}

1;
