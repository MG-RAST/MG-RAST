package resources::m5nr;

use strict;
use warnings;
no warnings('once');

use URI::Escape;
use Digest::MD5;

use MGRAST::Analysis;
use Babel::lib::Babel;
use Conf;
use parent qw(resources::resource);

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
					     'example'     => [ $self->cgi->url."/".$self->name."/ontology?source=Subsystems&min_level=level3",
       				                        'retrieve subsystems hierarchy for the top 3 levels' ],
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
					     'example'     => [ $self->cgi->url."/".$self->name."/taxonomy?parent_name=Bacteroidetes&min_level=class",
        				                    'retrieve all class level taxa that belong to Bacteroidetes' ],
					     'method'      => "GET",
					     'type'        => "synchronous",  
					     'attributes'  => $self->{attributes}{taxonomy},
					     'parameters'  => { 'options'  => { 'id_map' => ['boolean', 'if true overrides other options and returns a map { NCBI tax ID: [taxonomy levels] }'],
									                        'min_level' => ['cv', $self->{hierarchy}{taxonomy}],
									                        'parent_name' => ['string', 'name of taxanomy group to retrieve children of']
									                      },
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "sources",
					     'request'     => $self->cgi->url."/".$self->name."/sources",
					     'example'     => [ $self->cgi->url."/".$self->name."/sources",
         				                    'retrieve all data sources for M5NR' ],
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
   					     'example'     => [ $self->cgi->url."/".$self->name."/accession/YP_003268079.1",
          				                    "retrieve M5NR data for accession ID 'YP_003268079.1'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'limit'  => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"],
    					                                    'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ]
    					                                  },
   							                'required' => { "id" => ["string", "unique identifier from source DB"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "md5",
   					     'request'     => $self->cgi->url."/".$self->name."/md5/{id}",
   					     'description' => "Return annotation(s) or sequence of given md5sum (M5NR ID)",
   					     'example'     => [ $self->cgi->url."/".$self->name."/md5/000821a2e2f63df1a3873e4b280002a8?source=InterPro",
           				                    "retrieve InterPro M5NR data for md5sum '000821a2e2f63df1a3873e4b280002a8'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'source' => ['string','source name to restrict search by'],
   					                                        'limit'  => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"],
   					                                        'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ]
   					                                      },
   							                'required' => { "id" => ["string", "unique identifier in form of md5 checksum"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "function",
   					     'request'     => $self->cgi->url."/".$self->name."/function/{text}",
   					     'description' => "Return annotations for function names containing the given text",
   					     'example'     => [ $self->cgi->url."/".$self->name."/function/sulfatase?source=GenBank",
             				                "retrieve GenBank M5NR data for function names containing string 'sulfatase'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'source' => ['string','source name to restrict search by'],
   					                                        'limit'  => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"]
    					                                  },
   							                'required' => { "text" => ["string", "text string of partial function name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "organism",
   					     'request'     => $self->cgi->url."/".$self->name."/organism/{text}",
   					     'description' => "Return annotations for organism names containing the given text",
   					     'example'     => [ $self->cgi->url."/".$self->name."/organism/Akkermansia?source=KEGG",
              				                "retrieve KEGG M5NR data for organism names containing string 'Akkermansia'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'source' => ['string','source name to restrict search by'],
   					                                        'limit'  => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"]
     					                                  },
   							                'required' => { "text" => ["string", "text string of partial organism name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "sequence",
   					     'request'     => $self->cgi->url."/".$self->name."/sequence/{text}",
   					     'description' => "Return annotation(s) for md5sum (M5NR ID) of given sequence",
   					     'example'     => [ $self->cgi->url."/".$self->name."/sequence/MAGENHQWQGSIL?source=TrEMBL",
            				                "retrieve TrEMBL M5NR data for md5sum of sequence 'MAGENHQWQGSIL'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'source' => ['string','source name to restrict search by'],
   					                                        'limit'  => ['integer','maximum number of items requested'],
                                                            'offset' => ['integer','zero based index of the first data object to be returned'],
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"]
      					                                  },
   							                'required' => { "text" => ["string", "text string of protein sequence"] },
   							                'body'     => {} }
   				       },
                           { 'name'        => "accession",
      					     'request'     => $self->cgi->url."/".$self->name."/accession",
      					     'description' => "Return annotation or sequence of given source protein ID",
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'options'  => { 'DATA'   => ['string','semicolon seperated list of unique identifier from source DB'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
       					                                  },
      							                'required' => {},
      							                'body'     => {} }
      				       },
   				           { 'name'        => "md5",
      					     'request'     => $self->cgi->url."/".$self->name."/md5",
      					     'description' => "Return annotation(s) or sequence of given md5sum (M5NR ID)",
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'options'  => { 'DATA'   => ['string','semicolon seperated list of unique identifier in form of md5 checksum'],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
      					                                      },
      							                'required' => {},
      							                'body'     => {} }
      				       },
   				           { 'name'        => "function",
      					     'request'     => $self->cgi->url."/".$self->name."/function",
      					     'description' => "",
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'options'  => { 'DATA'   => ['string','semicolon seperated list of text string of partial function name'],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
       					                                  },
      							                'required' => {},
      							                'body'     => {} }
      				       },
      				       { 'name'        => "organism",
      					     'request'     => $self->cgi->url."/".$self->name."/organism",
      					     'description' => "",
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'options'  => { 'DATA'   => ['string','semicolon seperated list of text string of partial organism name'],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
        					                                  },
      							                'required' => {},
      							                'body'     => {} }
      				       },
      				       { 'name'        => "sequence",
      					     'request'     => $self->cgi->url."/".$self->name."/sequence",
      					     'description' => "",
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'options'  => { 'DATA'   => ['string','semicolon seperated list of text string of protein sequence'],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
         					                                  },
      							                'required' => {},
      							                'body'     => {} }
      				       }
   				       ]
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
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1] && $seq && ($self->method eq 'GET')) {
        $self->instance($self->rest->[0], $self->rest->[1]);
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1] && ($self->method eq 'GET')) {
        $self->query($self->rest->[0], $self->rest->[1]);
    } elsif ((scalar(@{$self->rest}) == 1) && ($self->method eq 'POST')) {
        $self->query($self->rest->[0]);
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
            $self->return_data({"ERROR" => "invalid source was entered ($source). Please use one of: ".join(", ", @src_map)}, 404);
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
            $url .= '&parent_name=$pname';
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
            $url .= '&parent_name=$pname';
            $data = $mgdb->get_hierarchy_slice('organism', undef, $pname, $min_lvl);
        } else {
            @$data = values %{ $mgdb->get_hierarchy('organism', undef, undef, undef, $min_lvl) };
        }
    } elsif ($type eq 'sources') {
        $data = $mgdb->_sources();
        delete $data->{GO};
    } else {
        $self->return_data({"ERROR" => "invalid resource type was entered ($type)"}, 404);
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
        $self->return_data({"ERROR" => "invalid resource type was entered ($type) for sequence output"}, 404);
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
    
    # paramaters
    my $source = $self->cgi->param('source') ? $self->cgi->param('source') : undef;
    my $limit  = $self->cgi->param('limit') ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') ? $self->cgi->param('offset') : 0;
    my $order  = $self->cgi->param('order') ? $self->cgi->param('order') : undef;
    
    # build data / url
    my $post = ($self->method eq 'POST') ? 1 : 0;
    my $data = [];
    my $path = '';
    
    if ($post) {
        eval {
            @$data = split(/;/, $self->cgi->param('DATA'));
        };
        if ($@ || (@$data == 0)) {
            $self->return_data( {"ERROR" => "unable to obtain POSTed data: ".$@}, 500 );
        }
        $path = '/'.$type;
    } else {
        $data = [$item];
        $path = '/'.$type.'/'.$item;
    }
    
    my $url = $self->cgi->url.'/m5nr'.$path.'?limit='.$limit.'&offset='.$offset;
    if ($source && ($type ne 'accession')) {
        $url .= '&source='.$source;
    }
    
    # strip wildcards
    map { $_ =~ s/\*//g } @$data;

    # get md5 for sequence
    if ($type eq 'sequence') {
        foreach my $d (@$data) {
            $d =~ s/\s+//sg;
            $d = Digest::MD5::md5_hex(uc $d);
        }
        $type = 'md5';
    }
    
    # get results
    my ($result, $total);
    if ($type eq 'md5') {
        my $md5s = $self->clean_md5($data);
        ($result, $total) = $self->solr_data($type, $md5s, $source, $offset, $limit, $order);
    } elsif ($type eq 'accession') {
        ($result, $total) = $self->solr_data($type, $data, undef, $offset, $limit, $order);
    } else {
        ($result, $total) = $self->solr_data($type, $data, $source, $offset, $limit, $order, 1);
    }
    my $obj = $self->check_pagination($result, $total, $limit, $path);
    $obj->{version} = 1;
    
    $self->return_data($obj);
}

sub clean_md5 {
    my ($self, $md5s) = @_;
    my $clean = [];
    foreach my $m (@$md5s) {
        my $c = $m;
        $c =~ s/[^a-zA-Z0-9]//g;
        unless ($c && (length($c) == 32)) {
            $self->return_data({"ERROR" => "invalid md5 was entered ($m)"}, 404);
        }
        push @$clean, $c;
    }
    return $clean;
}

sub solr_data {
    my ($self, $field, $data, $source, $offset, $limit, $order, $partial) = @_;
    
    @$data = map { uri_escape( uri_unescape($_) ) } @$data;
    if ($partial) {
        @$data = map { '*'.$_.'*' } @$data;
    }
    my $sort   = $order ? $order.'_sort+asc' : '';
    my $fields = ['source', 'function', 'accession', 'organism', 'ncbi_tax_id', 'type', 'md5'];
    my $method = (@$data > 1) ? 'POST' : 'GET';
    my $query  = join('+OR+', map { $field.'%3A'.$_ } @$data);
    if ($source) {
        $query = '('.$query.')+AND+source%3A'.$source;
    }
    return $self->get_solr_query($method, $Conf::m5nr_solr, $Conf::m5nr_collect, $query, $sort, $offset, $limit, $fields);
}

1;

