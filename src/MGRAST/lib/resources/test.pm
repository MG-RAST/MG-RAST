package resources::test;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

use URI::Escape qw(uri_escape uri_unescape);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "test";
    $self->{attributes} = { "code" => [ 'integer', 'HTTP Error Code' ],
    	                    "obj"  => [ 'string', 'stringified JSON' ]  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->url."/".$self->name,
		    'description' => "test resource.",
		    'type' => 'object',
		    'documentation' => $self->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->url."/".$self->name,				      
				      'description' => "Returns what you gave it.",
				      'example'     => [ $self->url."/".$self->name."?code=200&obj=".uri_escape('{"test":"ok"}'),
    				                     'return success, test - ok' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes ,
				      'parameters'  => { 'options'     => {},
							 'required'    => $self->attributes,
							 'body'        => {} } }
				     ]
				 };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;

    unless ($self->cgi->param('code') =~ /^\d+/) {
      $self->return_data( {"ERROR" => "code parameter must be a valid HTTP error code"}, 400 );
    }
    
    my $data = uri_unescape($self->cgi->param('obj'));
    
    print  $self->cgi->header( -type => "application/json",
			       -status => $self->cgi->param('code'),
			       -Access_Control_Allow_Origin => '*',
			       -Content_Length => length($data) );
    print $data;
    exit 0;
}
1;
