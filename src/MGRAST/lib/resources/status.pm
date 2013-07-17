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
    $self->{attributes} = { "id"     => [ 'integer', 'process id' ],
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
    my $content = { 'name' => $self->name,
                            'url' => $self->cgi->url."/".$self->name,
                            'description' => "Status of asynchronous API calls",
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
                                                                 'body'     => {} }
                                            },
                                            { 'name'        => "instance",
                                              'request'     => $self->cgi->url."/".$self->name."/{TOKEN}",
                                              'description' => "Returns a single data object.",
                                              'example'     => [ 'curl -X GET -H "auth: <auth_key>" "'.$self->cgi->url."/".$self->name.'/12345"',
                              			                         "data for asynchronous call with ID 12345" ],
                                              'method'      => "GET" ,
                                              'type'        => "synchronous" ,  
                                              'attributes'  => $self->attributes,
                                              'parameters'  => { 'options' => {
                                                                 'verbosity' => ['cv',
                                                                                 [['full','returns all connected metadata'],
                                                                                  ['minimal','returns only minimal information']]]
                                                                               },
                                                                 'required' => { "id" => ["string","unique process id"] },
                                                                 'body'     => {} }
                                            } ] };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my ($id) = $rest->[0] =~ /^(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid process id format: " . $rest->[0]}, 400 );
    }

    my $process_status = `/bin/ps --no-heading -p $id`;
    chomp $process_status;

    my $fname = $Conf::temp.'/'.$id.'.json';

    if($process_status eq "" && !(-e $fname)) {
        $self->return_data( {"ERROR" => "process id $id does not exist"}, 404 );
    }

    # return cached if exists
    $self->return_cached();

    # prepare data
    my $data = $self->prepare_data($id, $process_status, $fname);
    if($data->{status} eq "Done") {
        $self->return_data($data, undef, 1); # cache this!
    } else {
        $self->return_data($data, undef, 0); # don't cache this!
    }
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $id, $process_status, $fname) = @_;

    my $obj = {};
    if ($process_status ne "") {
        $obj->{id} = $id;
        $obj->{status} = "processing";
        $obj->{url} = $self->cgi->url."/".$self->name."/".$id;
    } elsif ($process_status eq "" && $self->cgi->param('verbosity') && ($self->cgi->param('verbosity') eq 'minimal')) {
        $obj->{id} = $id;
        $obj->{status} = "done";
        $obj->{url} = $self->cgi->url."/".$self->name."/".$id;
    } else {
        $obj->{id} = $id;
        $obj->{status} = "done";
        $obj->{url} = $self->cgi->url."/".$self->name."/".$id;
        local $/;
        open my $fh, "<", $fname;
        my $json = <$fh>;
        close $fh;
        my $data = decode_json($json);
        $obj->{data} = $data;
    }

    return $obj;
}

1;
