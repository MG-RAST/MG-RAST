package resources::user;

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
    $self->{name} = "user";
    $self->{attributes} = { "id"         => [ 'string', 'user login' ],
                            "email"      => [ 'string', 'user e-mail' ],
                            "firstname"  => [ 'string', 'first name of user' ],
                            "lastname"   => [ 'string', 'last name of user' ],
                            "entry_date" => [ 'date', 'date of user creation' ],
                            "active"     => [ 'boolean', 'user is active' ],
                            "comment"    => [ 'string', 'any comment about the user account' ],
                            "url"        => [ 'uri', 'resource location of this object instance' ]
                          };
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
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => {},
                                                         'body'        => {} } },
                                    { 'name'        => "instance",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Returns a single user object.",
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => { "id" => [ "string", "unique user login" ] },
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
    unless ($rest && scalar(@$rest) == 1) {
        $self->return_data( {"ERROR" => "invalid id format"}, 400 );
    }

    # get database
    my ($master, $error) = WebApplicationDBHandle->new();
    if ($error) {
        $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 503 );
    }
    
    # get data
    my $user = $master->User->get_objects( {"login" => $rest->[0]} );
    unless (scalar(@$user)) {
        $self->return_data( {"ERROR" => "login ".$rest->[0]." does not exists"}, 404 );
    }
    $user = $user->[0];

    # check rights
    unless ($self->user && ($self->user->has_right(undef, 'edit', 'user', $user->{_id}) || $self->user->has_star_right('edit', 'user'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for user call"}, 401 );
    }

    # prepare data
    my $data = $self->prepare_data($user);
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $user) = @_;

    my $url = $self->cgi->url;
    my $obj = {};
    $obj->{id}         = $user->login;
    $obj->{email}      = $user->email;
    $obj->{firstname}  = $user->firstname;
    $obj->{lastname}   = $user->lastname;
    $obj->{entry_date} = $user->entry_date;
    $obj->{active}     = $user->active;
    $obj->{comment}    = $user->comment;
    $obj->{url}        = $self->cgi->url.'/'.$self->{name}.'/'.$obj->{id};

    return $obj;
}

1;
