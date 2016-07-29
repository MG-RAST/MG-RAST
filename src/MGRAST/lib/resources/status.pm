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
        'url' => $self->cgi->url."/".$self->name,
        'description' => "Status of asynchronous API calls",
        'type' => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests' => [
            {
                'name'        => "info",
                'request'     => $self->cgi->url."/".$self->name,
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
                'request'     => $self->cgi->url."/".$self->name."/{UUID}",
                'description' => "Returns a single data object.",
                'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'/cfb3d9e1-c9ba-4260-95bf-e410c57b1e49"',
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
        url => $self->cgi->url."/".$self->name."/".$uuid,
        started => $node->{created_on}
    };
    
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
            $obj->{data} = $self->json->decode($content);
        }
    }
    
    $self->return_data($obj);
}

1;
