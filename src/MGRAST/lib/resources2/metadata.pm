package resources2::metadata;

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
    my %rights = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    $self->{name} = "metadata";
    $self->{rights} = \%rights;
    $self->{attributes} = { "template" => { "project" => [],
                                            "sample"  => [],
                                            "library" => [],
                                            "ep"      => [] },
                            "cv"       => { "ontology" => [],
                                            "ont_id"   => [],
                                            "select"   => [] },
                            "export"   => { "id"        => [],
                                            "name"      => [],
                                            "samples"   => [],
                                            "sampleNum" => [],
                                            "data"      => [] },
                            "validate" => { }
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "Metagenomic metadata is data providing information about one or more aspects of a set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => '',
                    'requests'      => [ { 'name'        => "info",
            				               'request'     => $self->cgi->url."/".$self->name,
            				               'description' => "Returns description of parameters and attributes.",
            				               'method'      => "GET",
            				               'type'        => "synchronous",  
            				               'attributes'  => "self",
            				               'parameters'  => { 'options'  => {},
            							                      'required' => {},
            							                      'body'     => {} } },
                                         { 'name'        => "template",
                                           'request'     => $self->cgi->url."/".$self->name."/template",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{template},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} } },
                                         { 'name'        => "cv",
                                           'request'     => $self->cgi->url."/".$self->name."/cv",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{cv},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} } },
                                         { 'name'        => "export",
                                           'request'     => $self->cgi->url."/".$self->name."/export/{ID}",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{export},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => { "id" => ["string", "unique object identifier"] },
                                                              'body'     => {} } },
                                         { 'name'        => "validate",
                                           'request'     => $self->cgi->url."/".$self->name."/validate",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{validate},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} } },
                                       ]
                  };
    $self->return_data($content);
}
    
    