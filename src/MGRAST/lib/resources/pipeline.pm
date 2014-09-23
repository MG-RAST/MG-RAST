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
    $self->{name} = "pipeline";
    $self->{version} = '3.0';
    $self->{attributes} = { data   => [ 'list', ['object', 'workflow document'] ],
                            error  => [ 'list', ['string', 'error that occured'] ],
                            status => [ 'int', 'http status code' ] };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
                    'url' => $self->cgi->url."/".$self->name,
                    'description' => "The resource returns information about a users data in the pipeline.",
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
                                      'description' => "Returns a single job document.",
                                      'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'/{job ID}"',
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
                                      'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'?state=queued"',
                    			                         "queued jobs in pipeline for user" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'  => {},
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
    unless ($self->user) {
        $self->return_data( {"ERROR" => "Missing authentication"}, 401 );
    }
    my $master = $self->connect_to_datasource();
    my $job  = undef;
    my $rest = $self->rest;
    
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
    unless ($self->user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}) || $self->user->has_star_right('view', 'metagenome')) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    my $data = $self->get_awe_query({'info.name' => $job->{job_id}}, $self->mgrast_token);
    $self->return_data($data);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
    
    # set params
    unless ($self->user) {
        $self->return_data( {"ERROR" => "Missing authentication"}, 401 );
    }
    my $master = $self->connect_to_datasource();
    
    # get paramaters
    my %params = $self->cgi->Vars;
    if (scalar(keys %params) == 0) {
        $self->return_data( {"ERROR" => "Missing query paramaters"}, 401 );
    }
    # other users data if admin
    if ($self->user->is_admin('MGRAST') && exists($params{'info.user'})) {
        $params{'info.user'} = $self->user_id( $params{'info.user'} );
    }
    # this users data
    else {
        $params{'info.user'} = $self->user_id();
    }
    
    my $data = $self->get_awe_query(\%params, $self->mgrast_token);
    $self->return_data($data);
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
