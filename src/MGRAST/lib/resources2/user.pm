package resources2::user;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use parent qw(resources2::resource);
use WebApplicationDBHandle;
use DBMaster;


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
                            "active"     => [ 'boolean', '' ],
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
                    'documentation' => $cgi->url.'/api.html#'.$self->name,
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
                                      'method'      => "GET" ,
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
    my $id = $rest->[0];

    if ($rest && scalar(@$rest) == 1) {
        unless ($self->user && $self->user->has_right(undef, 'edit', 'user', $self->user->{_id})) {
            $self->return_data( {"ERROR" => "insufficient permissions for user call"}, 400 );
        }
    }

    use WebApplicationDBHandle;
    use DBMaster;

    my ($dbmaster, $error) = WebApplicationDBHandle->new();
    if ($error) {
        $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 500 );
    }
  
    # get data
    my $user = $dbmaster->User->get_objects( { "login" => $id } );

    unless (scalar(@$user)) {
        $self->return_data( {"ERROR" => "login $id does not exists"}, 404 );
    }

    # prepare data
    my $data = $self->prepare_data($user->[0]);
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
    $obj->{url}        = $url.'/user/'.$obj->{id};

    return $obj;
}

1;
