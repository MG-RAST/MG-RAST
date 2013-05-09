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
    $self->{sources} = [ ['Subsystems', 'returns 4 level SEED-Subsystems ontology' ],
						 ['COG', 'returns 3 level COG ontology'],
					     ['NOG', 'returns 3 level NOG ontology'],
						 ['KO', 'returns 4 level KEGG-KO ontology' ] ];
    $self->{hierarchy} = { taxonomy => [ ['species', 'taxonomy level'],
					                     ['genus', 'taxonomy level'],
					                     ['family', 'taxonomy level'],
					                     ['order', ' taxonomy level'],
					                     ['class', ' taxonomy level'],
					                     ['phylum', 'taxonomy level'],
					                     ['domain', 'top taxonomy level'] ],
			               ontology => [ ['function', 'bottom ontology level'],
                                         ['level3', 'ontology level' ],
                                         ['level2', 'ontology level' ],
					                     ['level1', 'top ontology level'] ]
			              };
	$self->{attributes} = { taxonomy => { data    => [ 'list', ['list', 'requested taxonomy levels, from highest to lowest'] ],
             	                          version => [ 'integer', 'version of the object' ],
             	                          url     => [ 'uri', 'resource location of this object instance' ] },
             	            ontology => { data    => [ 'list', ['list', 'requested ontology levels, from highest to lowest'] ],
                                          version => [ 'integer', 'version of the object' ],
                                          url     => [ 'uri', 'resource location of this object instance' ] },
                           	sources  => { data    => [ 'hash', [{'key' => ['string', 'source name'],
                                                                 'value' => ['object', 'source object']}, 'source object hash'] ],
                                          version => [ 'integer', 'version of the object' ],
                                          url     => [ 'uri', 'resource location of this object instance' ] }
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
		  'documentation' => $self->cgi->url.'/api.html#'.$self->name,
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
				       { 'name'        => "ontology",
					 'request'     => $self->cgi->url."/".$self->name."/ontology",
					 'description' => "",
					 'method'      => "GET",
					 'type'        => "synchronous",  
					 'attributes'  => $self->{attributes}{ontology},
					 'parameters'  => { 'options'  => { 'source' => ['cv', $self->{sources} ],
										'id_map' => ['boolean', 'if true overrides other options and returns a map { ontology ID: [ontology levels] }'],
									    'min_level' => ['cv', $self->{hierarchy}{ontology}],
									    'parent_name' => ['string', 'name of ontology group to retrieve children of']
									  },
							    'required' => {},
							    'body'     => {} }
				       },
				       { 'name'        => "taxonomy",
					 'request'     => $self->cgi->url."/".$self->name."/taxonomy",
					 'description' => "",
					 'method'      => "GET",
					 'type'        => "synchronous",  
					 'attributes'  => $self->{attributes}{taxonomy},
					 'parameters'  => { 'options'  => {
					                    'id_map' => ['boolean', 'if true overrides other options and returns a map { NCBI tax ID: [taxonomy levels] }'],
									    'min_level' => ['cv', $self->{hierarchy}{taxonomy}],
									    'parent_name' => ['string', 'name of taxanomy group to retrieve children of']
									  },
							    'required' => {},
							    'body'     => {} }
				       },
				       { 'name'        => "sources",
					 'request'     => $self->cgi->url."/".$self->name."/sources",
					 'description' => "",
					 'method'      => "GET",
					 'type'        => "synchronous",  
					 'attributes'  => $self->{attributes}{sources},
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
    } elsif (($self->rest->[0] eq 'taxonomy') || ($self->rest->[0] eq 'ontology') || ($self->rest->[0] eq 'sources')) {
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
    my $url = $self->cgi->url.'/m5nr/'.$type;
    my $data = [];
    my $pname = $self->cgi->param('parent_name') || '';
        
    if ($type eq 'ontology') {
        my @ont_hier = map { $_->[0] } @{$self->{hierarchy}{ontology}};
        my @src_map  = map { $_->[0] } @{$self->{sources}};
        my $source   = $self->cgi->param('source') || 'Subsystems';
        my $min_lvl  = $self->cgi->param('min_level') || 'function';
        $url .= '?source='.$source.'&min_level='.$min_lvl;
        unless ( grep(/^$source$/, @src_map) ) {
            $self->return_data({"ERROR" => "Invalid source was entered ($source). Please use one of: ".join(", ", @src_map)}, 404);
        }
        if ( grep(/^$min_lvl$/, @ont_hier) ) {
            if ($min_lvl eq 'function') {
  	            $min_lvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
        } else {
            $self->return_data({"ERROR" => "invalid min_level for m5nr/ontology: ".$min_lvl." - valid types are [".join(", ", @ont_hier)."]"}, 404);
        }
        if ( $self->cgi->param('id_map') ) {
            $url .= '&id_map=1';
            $data = $mgdb->get_hierarchy('ontology', $source);
        } elsif ($pname && ($min_lvl ne 'level1')) {
            $data = $mgdb->get_hierarchy_slice('ontology', $source, $pname, $min_lvl);
        } else {
            @$data = values %{ $mgdb->get_hierarchy('ontology', $source, undef, undef, $min_lvl) };
        }
    } elsif ($type eq 'taxonomy') {
        my @tax_hier = map { $_->[0] } @{$self->{hierarchy}{taxonomy}};
        my $min_lvl  = $self->cgi->param('min_level') || 'species';
        $url .= '?min_level='.$min_lvl;
        if ( grep(/^$min_lvl$/, @tax_hier) ) {
            $min_lvl = 'tax_'.$min_lvl;
        } else {
            $self->return_data({"ERROR" => "invalid min_level for m5nr/taxonomy: ".$min_lvl." - valid types are [".join(", ", @tax_hier)."]"}, 404);
        }
        if ( $self->cgi->param('id_map') ) {
            $url .= '&id_map=1';
            $data = $mgdb->get_hierarchy('organism', undef, 1);
        } elsif ($pname && ($min_lvl ne 'tax_domain')) {
            $data = $mgdb->get_hierarchy_slice('organism', undef, $pname, $min_lvl);
        } else {
            @$data = values %{ $mgdb->get_hierarchy('organism', undef, undef, undef, $min_lvl) };
        }
    } elsif ($type eq 'sources') {
        $data = $mgdb->_sources();
        delete $data->{GO};
    } else {
        $self->return_data({"ERROR" => "Invalid resource type was entered ($type)."}, 404);
    }
    
    my $obj = { data    => $data,
                version => 1,
             	url     => $url };
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

1;

