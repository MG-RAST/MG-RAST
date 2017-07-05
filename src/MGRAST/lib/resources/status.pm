package resources::status;

use strict;
use warnings;
no warnings('once');

use JSON;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "status";
    $self->{attributes} = {
        "id"     => [ 'string', 'process id' ],
        "status" => [ 'string', 'cv', [ ['processing', 'process is still computing'],
                                        ['done', 'process is done computing'] ] ],
        "url"    => [ 'url', 'resource location of this object instance'],
        "data"   => [ 'hash', 'if status is done, data holds the result, otherwise data is not present']
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->url."/".$self->name,
        'description' => "Status of asynchronous API calls",
        'type' => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests' => [
            {
                'name'        => "info",
                'request'     => $self->url."/".$self->name,
                'description' => "Returns description of parameters and attributes.",
                'method'      => "GET" ,
                'type'        => "synchronous" ,  
                'attributes'  => "self",
                'parameters'  => { 'options'  => {},
                                   'required' => {},
                                   'body'     => {} }
            },
            {
                'name'        => "instance",
                'request'     => $self->url."/".$self->name."/{UUID}",
                'description' => "Returns a single data object.",
                'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->url."/".$self->name.'/cfb3d9e1-c9ba-4260-95bf-e410c57b1e49"',
                              		"data for asynchronous call with ID cfb3d9e1-c9ba-4260-95bf-e410c57b1e49" ],
                'method'      => "GET" ,
                'type'        => "synchronous" ,  
                'attributes'  => $self->attributes,
                'parameters'  => { 'options' => {
                                        'verbosity' => ['cv', [['full','returns all connected metadata'],
                                                               ['minimal','returns only minimal information']]]
                                    },
                                    'required' => { "id" => ["string","RFC 4122 UUID for process"] },
                                    'body'     => {} }
            }
        ]
    };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    my $verbosity = $self->cgi->param('verbosity') || "full";
    
    # get node
    my $uuid = $self->rest->[0];
    my $node = $self->get_shock_node($uuid, $self->mgrast_token);
    if (! $node) {
        $self->return_data( {"ERROR" => "process id $uuid does not exist"}, 404 );
    }
    
    my $obj = {
        id => $uuid,
        status => "processing",
        url => $self->url."/".$self->name."/".$uuid,
        started => $node->{created_on},
        updated => $node->{last_modified}
    };
    if (exists $node->{attributes}{progress}) {
        $obj->{progress} = $node->{attributes}{progress};
    }
    if (exists $node->{attributes}{parameters}) {
        $obj->{parameters} = $node->{attributes}{parameters};
    }
    
    if ($node->{file}{name} && $node->{file}{size}) {
        $obj->{status} = "done";
        $obj->{size}   = $node->{file}{size};
        $obj->{md5}    = $node->{file}{checksum}{md5};
        $obj->{completed} = $node->{file}{created_on};
        if ($verbosity eq "full") {
            my ($content, $err) = $self->get_shock_file($uuid, undef, $self->mgrast_token);
            if ($err) {
                $self->return_data( {"ERROR" => "unable to retrieve data: ".$err}, 404 );
            }
            # handle error in content
            my $data = undef;
            eval {
                $data = $self->json->decode($content);
            };
            if ($@ || (! $data)) {
                $data = $content;
            }
            if (ref($data) eq "HASH") {
                my $error = exists($data->{ERROR}) ? $data->{ERROR} : (exists($data->{error}) ? $data->{error} : undef);
                if ($error) {
                    my $status = exists($data->{STATUS}) ? $data->{STATUS} : (exists($data->{status}) ? $data->{status} : 500);
                    $self->return_data( {"ERROR" => $error},  $status);
                }
            }
            $obj->{data} = $data;
        }
    }
    
    $self->return_data($obj);
}

1;
