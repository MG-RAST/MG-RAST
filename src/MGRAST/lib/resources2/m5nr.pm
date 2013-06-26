package resources2::m5nr;

use strict;
use warnings;
no warnings('once');

use URI::Escape;
use Digest::MD5;

use MGRAST::Analysis;
use Babel::lib::Babel;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "m5nr";
    $self->{request} = { ontology => 1, taxonomy => 1, sources => 1, accession => 1, 
                         md5 => 1, function => 1, organism => 1, sequence => 1 };
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
                                          url     => [ 'uri', 'resource location of this object instance' ] },
                            annotation => { next   => ["uri","link to the previous set or null if this is the first set"],
                                            prev   => ["uri","link to the next set or null if this is the last set"],
                                            limit  => ["integer","maximum number of data items returned, default is 10"],
                                            offset => ["integer","zero based index of the first returned data item"],
                                            total_count => ["integer","total number of available data items"],
                                            version => [ 'integer', 'version of the object' ],
                                            url  => [ 'uri', 'resource location of this object instance' ],
                                            data => [ 'list', ['object', [{'accession'   => [ 'string', 'unique identifier given by source' ],
                                                                           'md5'         => [ 'string', 'md5 checksum - M5NR ID' ],
                                                                           'function'    => [ 'string', 'function annotation' ],
                                                                           'organism'    => [ 'string', 'organism annotation' ],
                                                                           'ncbi_tax_id' => [ 'int', 'organism ncbi tax_id' ],
                                                                           'type'        => [ 'string', 'source type' ],
                                                                           'source'      => [ 'string', 'source name' ]}, "annotation object"]] ] },
                            sequence => { version => [ 'integer', 'version of the object' ],
                                          url  => [ 'uri', 'resource location of this object instance' ],
                                          data => [ 'object', [{'accession' => [ 'string', 'unique identifier given by source' ],
                                                                 'md5'      => [ 'string', 'md5 checksum - M5NR ID' ],
                                                                 'sequence' => [ 'string', 'protein sequence' ]}, "sequence object"] ] }
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
					 'description' => "Return functional hierarchy",
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
					 'description' => "Return organism hierarchy",
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
					     'description' => "Return all sources in M5NR",
					     'method'      => "GET",
					     'type'        => "synchronous",  
					     'attributes'  => $self->{attributes}{sources},
					     'parameters'  => { 'options'  => {},
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "accession",
   					     'request'     => $self->cgi->url."/".$self->name."/accession/{id}",
   					     'description' => "Return annotation or sequence of given source protein ID",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit' => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
    					                                    'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ]
    					                                  },
   							                'required' => { "id" => ["string", "unique identifier from source DB"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "md5",
   					     'request'     => $self->cgi->url."/".$self->name."/md5/{id}",
   					     'description' => "Return annotation(s) or sequence of given md5sum (M5NR ID)",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit' => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
   					                                        'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ]
   					                                      },
   							                'required' => { "id" => ["string", "unique identifier in form of md5 checksum"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "function",
   					     'request'     => $self->cgi->url."/".$self->name."/function/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit' => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned']
    					                                  },
   							                'required' => { "text" => ["string", "text string of function name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "organism",
   					     'request'     => $self->cgi->url."/".$self->name."/organism/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit' => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned']
     					                                  },
   							                'required' => { "text" => ["string", "text string of organism name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "sequence",
   					     'request'     => $self->cgi->url."/".$self->name."/sequence/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit' => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned']
      					                                  },
   							                'required' => { "text" => ["string", "text string of protein sequence"] },
   							                'body'     => {} }
   				       } ]
		};
  $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;

    my $seq = $self->cgi->param('sequence') ? 1 : 0;
    
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (($self->rest->[0] eq 'taxonomy') || ($self->rest->[0] eq 'ontology') || ($self->rest->[0] eq 'sources')) {
        $self->static($self->rest->[0]);
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1] && $seq) {
        $self->instance($self->rest->[0], $self->rest->[1]);
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1]) {
        $self->query($self->rest->[0], $self->rest->[1]);
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
    
    my $obj = { data => $data, version => 1, url => $url };
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

# return data: sequence object for accession or md5
sub instance {
    my ($self, $type, $item) = @_;
    
    # get database
    my $ach = new Babel::lib::Babel;
    unless (ref($ach)) {
        $self->return_data({"ERROR" => "could not connect to M5NR database"}, 500);
    }
    
    my $data = [];
    my $url  = $self->cgi->url.'/m5nr/'.$type.'/'.$item.'?sequence=1';
    
    if ($type eq 'md5') {
        my $clean = $self->clean_md5($item);
        $data = {id => undef, md5 => $clean, sequence => $ach->md52sequence($item)};
    } elsif ($type eq 'accession') {
        my $md5 = $ach->id2md5($item);
        unless ($md5 && @$md5 && $md5->[0][0]) {
            $self->return_data( {"ERROR" => "accession $item does not exist in M5NR"}, 404 );
        }
        my $clean = $self->clean_md5($md5->[0][0]);
        $data = {id => $item, md5 => $clean, sequence => $ach->md52sequence($md5->[0][0])};
    } else {
        $self->return_data({"ERROR" => "Invalid resource type was entered ($type) for sequence output."}, 404);
    }
    
    my $obj = { data => $data, version => 1, url => $url };
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

# return query data: annotation object
sub query {
    my ($self, $type, $item) = @_;
    
    # pagination
    my $limit  = $self->cgi->param('limit') ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') ? $self->cgi->param('offset') : 0;
    
    # build url
    my $path = '/'.$type.'/'.$item;
    my $url  = $self->cgi->url.'/m5nr'.$path.'?limit='.$limit.'&offset='.$offset;
    
    # strip wildcards    
    $item =~ s/\*//g;

    # get md5 for sequence
    if ($type eq 'sequence') {
        $item =~ s/\s+//sg;
        $item = Digest::MD5::md5_hex( uc $item );
        $type = 'md5';
    }
    
    # get results
    my ($data, $total);
    if ($type eq 'md5') {
        my $md5 = $self->clean_md5($item);
        ($data, $total) = $self->solr_data('md5', $md5, $offset, $limit);
    } else {
        ($data, $total) = $self->solr_data($type, $item, $offset, $limit, 1);
    }
    my $obj = $self->check_pagination($data, $total, $limit, $path);
    $obj->{url} = $url;
    $obj->{version} = 1;
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

sub clean_md5 {
    my ($self, $md5) = @_;
    my $clean = $md5;
    $clean =~ s/[^a-zA-Z0-9]//g;
    unless ($clean && (length($clean) == 32)) {
        $self->return_data({"ERROR" => "Invalid md5 was entered ($md5)."}, 404);
    }
    return $clean;
}

sub solr_data {
    my ($self, $field, $text, $offset, $limit, $partial) = @_;
    $text = uri_unescape($text);
    $text = uri_escape($text);
    if ($partial) {
        $text = '*'.$text.'*';
    }
    my $fields = ['source', 'function', 'accession', 'organism', 'ncbi_tax_id', 'type', 'md5'];
    return $self->get_solr_query($Conf::m5nr_solr, $Conf::m5nr_collect, $field.'%3A'.$text, "", $offset, $limit, $fields);
}

1;

