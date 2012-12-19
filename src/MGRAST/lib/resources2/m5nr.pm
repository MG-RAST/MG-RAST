package resources2::m5nr;

use strict;
use warnings;
no warnings('once');

use MGRAST::Analysis;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "m5nr";
    $self->{attributes} = { 'hierarchy' => { 'NCBI'       => [ 'hash', '7 level NCBI taxonomy' ],
                                             'COG'        => [ 'hash', '3 level COG ontology' ],
                                             'NOG'        => [ 'hash', '3 level NOG ontology' ],
                                             'KO'         => [ 'hash', '4 level KEGG-KO ontology' ],
                                             'Subsystems' => [ 'hash', '4 level SEED-Subsystems ontology' ] },
                            'sources'   => [ 'hash', [['key',   ['string', 'source name']],
                                                      ['value', ['object', [ { 'name'        => ['string', 'source name'],
                                                                               'description' => ['string', 'description of source'],
                                                                               'type'        => ['string', 'type of source'],
                                                                               'link'        => ['string', 'link for source id'] },
                                                                             'information about source' ]]]
                                           ]]
                          };
    return $self;
}


# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "M5NR provides data through a comprehensive non-redundant protein / rRNA database",
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
            							                      'body'     => {} }
            							 },
                                         { 'name'        => "hierarchy",
                                           'request'     => $self->cgi->url."/".$self->name."/hierarchy",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{hierarchy},
                                           'parameters'  => { 'options'  => { 'source' => ['cv', ['NCBI',       'returns 7 level NCBI taxonomy'],
                                                                                                 ['COG',        'returns 3 level COG ontology'],
                                                                                                 ['NOG',        'returns 3 level NOG ontology'],
                                                                                                 ['KO',         'returns 4 level KEGG-KO ontology' ],
                                                                                                 ['Subsystems', 'returns 4 level SEED-Subsystems ontology' ]]
                                                                             },
                                                              'required' => {},
                                                              'body'     => {} }
                                         },
                                         { 'name'        => "sources",
                                           'request'     => $self->cgi->url."/".$self->name."/sources",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{sources},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} }
                                         } ]
                };
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (($self->rest->[0] eq 'hierarchy') || ($self->rest->[0] eq 'sources')) {
        $self->static($self->rest->[0]);
    } else {
        $self->info();
    }
}

# return static data: hierarchy or source
sub static {
    my ($self, $type) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    my $mgdb   = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
    }

    my $data = {};
    if ($type eq 'hierarchy') {
        my $source = $self->cgi->param('source') || 'NCBI';
        $data = ($source eq 'NCBI') ? $mgdb->get_hierarchy('organism') : $mgdb->get_hierarchy('ontology', $source);
    } elsif ($type eq 'sources') {
        $data = $mgdb->_sources();
        delete $data->{GO};
    }
    $self->return_data($data);
}

1;

