package resources::m5nr;

use strict;
use warnings;
no warnings('once');

use List::Util qw(first);
use URI::Escape;
use Digest::MD5;

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
	$self->{attributes} = { taxonomy => { data => [ 'list', ['object', [{'organism' => [ 'string', 'organism name' ],
	                                                                     'species'  => [ 'string', 'organism species' ],
                                                                         'genus'    => [ 'string', 'organism genus' ],
                                                                         'family'   => [ 'string', 'organism family' ],
                                                                         'order'    => [ 'string', 'organism order' ],
                                                                         'class'    => [ 'string', 'organism class' ],
                                                                         'phylum'   => [ 'string', 'organism phylum' ],
                                                                         'domain'   => [ 'string', 'organism domain' ],
                                                                         'ncbi_tax_id' => [ 'int', 'organism ncbi id' ]}, "taxonomy object"]] ],
             	                          version => [ 'integer', 'version of the object' ],
             	                          url     => [ 'uri', 'resource location of this object instance' ] },
             	            ontology => { data => [ 'list', ['object', [{'id'     => [ 'string', 'ontology ID' ],
                                      	                                 'level1' => [ 'string', 'ontology top level' ],
                                                                         'level2' => [ 'string', 'ontology level 2' ],
                                                                         'level3' => [ 'string', 'ontology level 3' ],
                                                                         'level4' => [ 'string', 'ontology bottom level' ],
                                                                         'source' => [ 'string', 'source name' ]}, "ontology object"]] ],
                                          version => [ 'integer', 'version of the object' ],
                                          url     => [ 'uri', 'resource location of this object instance' ] },
                           	sources  => { data    => [ 'list', ['object', 'source object'] ],
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
					     'parameters'  => { 'options'  => { 'source' => ['cv', $self->source->{ontology} ],
									                        'filter_level' => ['cv', $self->{hierarchy}{ontology}],
									                        'filter' => ['string', 'text of ontology group (filter_level) to filter by'],
									                        'min_level' => ['cv', $self->{hierarchy}{ontology}]
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
					     'parameters'  => { 'options'  => { 'filter_level' => ['cv', $self->{hierarchy}{taxonomy}],
	                                                        'filter' => ['string', 'text of taxanomy group (filter_level) to filter by'],
									                        'min_level' => ['cv', $self->{hierarchy}{taxonomy}]
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
                                                            "order"  => ["string","name of the attribute the returned data is ordered by"]
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
   					                                        'sequence' => ['boolean', "if true return sequence output, else return annotation output, default is false"]
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
   					                                        'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
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
   					     'example'     => [ $self->cgi->url."/".$self->name."/organism/akkermansia?source=KEGG",
              				                "retrieve KEGG M5NR data for organism names containing string 'akkermansia'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'source' => ['string','source name to restrict search by'],
   					                                        'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
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
      					     'description' => "Return annotations of given source protein IDs",
      					     'example'     => [ 'curl -X POST -d \'{"order":"function","data":["YP_003268079.1","COG1764"]}\' "'.$self->cgi->url."/".$self->name.'/accession"',
               				                    "retrieve M5NR data for accession IDs 'YP_003268079.1' and 'COG1764' ordered by function" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => { 'data'   => ['list',["string","unique identifier from source DB"]],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
       					                                      },
      							                'required' => {},
      							                'options'  => {} }
      				       },
   				           { 'name'        => "md5",
      					     'request'     => $self->cgi->url."/".$self->name."/md5",
      					     'description' => "Return annotations of given md5sums (M5NR ID)",
      					     'example'     => [ 'curl -X POST -d \'{"source":"InterPro","data":["000821a2e2f63df1a3873e4b280002a8","15bf1950bd9867099e72ea6516e3d602"]}\' "'.$self->cgi->url."/".$self->name.'/md5"',
                				                "retrieve InterPro M5NR data for md5s '000821a2e2f63df1a3873e4b280002a8' and '15bf1950bd9867099e72ea6516e3d602'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => { 'data'   => ['list',["string","unique identifier in form of md5 checksum"]],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
      					                                      },
      							                'required' => {},
      							                'options'  => {} }
      				       },
   				           { 'name'        => "function",
      					     'request'     => $self->cgi->url."/".$self->name."/function",
      					     'description' => "Return annotations for function names containing the given texts",
      					     'example'     => [ 'curl -X POST -d \'{"source":"GenBank","limit":50,"data":["sulfatase","phosphatase"]}\' "'.$self->cgi->url."/".$self->name.'/function"',
                  				                "retrieve top 50 GenBank M5NR data for function names containing string 'sulfatase' or 'phosphatase'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => { 'data'   => ['list',["string","text string of partial function name"]],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
       					                                      },
      							                'required' => {},
      							                'options'  => {} }
      				       },
      				       { 'name'        => "organism",
      					     'request'     => $self->cgi->url."/".$self->name."/organism",
      					     'description' => "Return annotations for organism names containing the given texts",
      					     'example'     => [ 'curl -X POST -d \'{"source":"KEGG","order":"accession","data":["akkermansia","yersinia"]}\' "'.$self->cgi->url."/".$self->name.'/organism"',
                   				                "retrieve KEGG M5NR data (ordered by accession ID) for organism names containing string 'akkermansia' or 'yersinia'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => { 'data'   => ['list',["string","text string of partial organism name"]],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
        					                                  },
      							                'required' => {},
      							                'options'  => {} }
      				       },
      				       { 'name'        => "sequence",
      					     'request'     => $self->cgi->url."/".$self->name."/sequence",
      					     'description' => "Return annotations for md5s (M5NR ID) of given sequences",
      					     'example'     => [ 'curl -X POST -d \'{"source":"KEGG","order":"source","data":["MAGENHQWQGSIL","MAGENHQWQGSIL"]}\' "'.$self->cgi->url."/".$self->name.'/sequence"',
                 				                "retrieve M5NR data ordered by source for sequences 'MAGENHQWQGSIL' and 'MAGENHQWQGSIL'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",  
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => { 'data'   => ['list',["string","text string of protein sequence"]],
      					                                        'source' => ['string','source name to restrict search by'],
      					                                        'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                "order"  => ["string","name of the attribute the returned data is ordered by"]
         					                                  },
      							                'required' => {},
      							                'options'  => {} }
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
    } elsif (($self->rest->[0] eq 'md5') && $self->rest->[1] && $seq && ($self->method eq 'GET')) {
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
    
    my $url = $self->cgi->url.'/m5nr/'.$type;
    my $solr = 'object%3A';
    my $limit = 1000000;
    my $filter = $self->cgi->param('filter') || '';
    my $min_lvl = $self->cgi->param('min_level') || '';
    my $fields = [];
    my $grouped = 0;
        
    if ($type eq 'ontology') {
        my @ont_hier = map { $_->[0] } @{$self->{hierarchy}{ontology}};
        my @src_map  = map { $_->[0] } @{$self->source->{ontology}};
        my $source   = $self->cgi->param('source') || 'Subsystems';
        $min_lvl = $min_lvl || 'function';
        $fields  = [ @ont_hier, 'level4', 'accession' ];
        
        unless ( grep(/^$source$/, @src_map) ) {
            $self->return_data({"ERROR" => "invalid source was entered ($source). Please use one of: ".join(", ", @src_map)}, 404);
        }
        $url .= '?source='.$source.'&min_level='.$min_lvl;
        $solr .= 'ontology+AND+source%3A'.$source;
        
        # filtered query
        if ($filter) {
            my $filter_lvl = $self->cgi->param('filter_level') || 'function';
            unless ( grep(/^$filter_lvl$/, @ont_hier) ) {
                $self->return_data({"ERROR" => "invalid filter_level for m5nr/ontology: ".$filter_lvl." - valid types are [".join(", ", @ont_hier)."]"}, 404);
            }
            $url .= '&filter_level='.$filter_lvl.'&filter='.$filter;
            if ($filter_lvl eq 'function') {
  	            $filter_lvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
            $solr .= '+AND+'.$filter_lvl.'%3A*'.uri_escape(uri_unescape($filter)).'*';
        }
        # min level query
        unless ( grep(/^$min_lvl$/, @ont_hier) ) {
            $self->return_data({"ERROR" => "invalid min_level for m5nr/ontology: ".$min_lvl." - valid types are [".join(", ", @ont_hier)."]"}, 404);
        }        
        if ($min_lvl ne 'function') {
            my $min_index = first { $ont_hier[$_] eq $min_lvl } 0..$#ont_hier;
            @$fields = splice @ont_hier, $min_index;
            $solr .= '&group=true&group.field='.$min_lvl;
            $grouped = 1;
        }
    } elsif ($type eq 'taxonomy') {
        my @tax_hier = map { $_->[0] } @{$self->{hierarchy}{taxonomy}};
        $min_lvl = $min_lvl || 'species';
        $fields  = [ @tax_hier, 'ncbi_tax_id', 'organism' ];
        
        $url .= '?min_level='.$min_lvl;
        $solr .= 'taxonomy';
        
        # filtered query
        if ($filter) {
            my $filter_lvl = $self->cgi->param('filter_level') || 'species';
            unless ( grep(/^$filter_lvl$/, @tax_hier) ) {
                $self->return_data({"ERROR" => "invalid filter_level for m5nr/taxonomy: ".$filter_lvl." - valid types are [".join(", ", @tax_hier)."]"}, 404);
            }
            $url .= '&filter_level='.$filter_lvl.'&filter='.$filter;
            $solr .= '+AND+'.$filter_lvl.'%3A*'.uri_escape(uri_unescape($filter)).'*';
        }
        # min level query
        unless ( grep(/^$min_lvl$/, @tax_hier) ) {
            $self->return_data({"ERROR" => "invalid min_level for m5nr/taxonomy: ".$min_lvl." - valid types are [".join(", ", @tax_hier)."]"}, 404);
        }
        if ($min_lvl ne 'species') {
            my $min_index = first { $tax_hier[$_] eq $min_lvl } 0..$#tax_hier;
            @$fields = splice @tax_hier, $min_index;
            $solr .= '&group=true&group.field='.$min_lvl;
            $grouped = 1;
        }
    } elsif ($type eq 'sources') {
        $fields = [ 'source', 'organization', 'description', 'type', 'url', 'email', 'link', 'title', 'version', 'download_date' ];
        $solr .= 'source';
    } else {
        $self->return_data({"ERROR" => "invalid resource type was entered ($type)"}, 404);
    }
    
    my $data = [];
    if ($grouped) {
        my $result = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect, $solr, undef, 0, $limit, $fields);
        foreach my $group (@{$result->{$min_lvl}{groups}}) {
            push @$data, $group->{doclist}{docs}[0];
        }
    } else {
        ($data, undef) = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect, $solr, undef, 0, $limit, $fields);
    }
    my $obj = { data => $data, version => 1, url => $url };
    
    $self->return_data($obj);
}

# return data: sequence object for accession or md5
sub instance {
    my ($self, $item) = @_;
    
    my $clean = $self->clean_md5($item);
    my $data = { md5 => $clean, sequence => $self->md52sequence($item) };
    my $url = $self->cgi->url.'/m5nr/md5/'.$item.'?sequence=1';
    my $obj = { data => $data, version => 1, url => $url };
    $self->return_data($obj);
}

# return query data: annotation object
sub query {
    my ($self, $type, $item) = @_;
    
    # paramaters
    my $source = $self->cgi->param('source') ? $self->cgi->param('source') : undef;
    my $limit  = $self->cgi->param('limit')  ? $self->cgi->param('limit')  : 10;
    my $offset = $self->cgi->param('offset') ? $self->cgi->param('offset') : 0;
    my $order  = $self->cgi->param('order')  ? $self->cgi->param('order')  : undef;
    my $exact  = $self->cgi->param('exact')  ? 1 : 0;
    
    # build data / url
    my $post = ($self->method eq 'POST') ? 1 : 0;
    my $data = [];
    my $path = '';
    
    if ($post) {
        my $post_data = $self->cgi->param('POSTDATA') ? $self->cgi->param('POSTDATA') : join(" ", $self->cgi->param('keywords'));
        # all options sent as post data
        if ($post_data) {
            eval {
                my $json_data = $self->json->decode($post_data);
                if (exists $json_data->{source}) { $source = $json_data->{source}; }
                if (exists $json_data->{limit})  { $limit  = $json_data->{limit}; }
                if (exists $json_data->{offset}) { $offset = $json_data->{offset}; }
                if (exists $json_data->{order})  { $order  = $json_data->{order}; }
                if (exists $json_data->{exact})  { $exact  = $json_data->{exact} ? 1 : 0; }
                $data = $json_data->{data};
            };
        # data sent in post form
        } elsif ($self->cgi->param('data')) {
            eval {
                @$data = split(/;/, $self->cgi->param('data'));
            };
        } else {
            $self->return_data( {"ERROR" => "POST request missing data"}, 400 );
        }
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
        my @md5s = map { $self->clean_md5($_) } @$data;
        ($result, $total) = $self->query_annotation($type, \@md5s, $source, $offset, $limit, $order, 1);
    } elsif ($type eq 'accession') {
        ($result, $total) = $self->query_annotation($type, $data, undef, $offset, $limit, $order, 1);
    } else {
        ($result, $total) = $self->query_annotation($type, $data, $source, $offset, $limit, $order, $exact);
    }
    my $obj = $self->check_pagination($result, $total, $limit, $path);
    $obj->{version} = 1;
    
    $self->return_data($obj);
}

sub clean_md5 {
    my ($self, $md5) = @_;
    my $clean = $md5;
    $clean =~ s/[^a-zA-Z0-9]//g;
    unless ($clean && (length($clean) == 32)) {
        $self->return_data({"ERROR" => "invalid md5 was entered ($md5)"}, 404);
    }
    return $clean;
}

sub md52sequence {
  my ($self, $md5) = @_;

  my $seq;
  eval {
      my @recs = `fastacmd -d $Conf::m5nr_fasta -s \"lcl|$md5\" -l 0 2>&1`;
      if ((@recs < 2) || (! $recs[0]) || ($recs[0] =~ /^\s+$/) || ($recs[0] =~ /^\[fastacmd\]/)) {
          $seq = "";
      } else {
          $seq = $recs[1];
          $seq =~ s/\s+//;
      }
  };
  if ($@) {
       $self->return_data({"ERROR" => "unable to access M5NR sequence data"}, 500);
  }
  
  return $seq;
}

sub query_annotation {
    my ($self, $field, $data, $source, $offset, $limit, $order, $exact) = @_;
    
    @$data = map { uri_escape( uri_unescape($_) ) } @$data;
    if ($exact) {
        @$data = map { '"'.$_.'"' } @$data;
    } else {
        @$data = map { '*'.$_.'*' } @$data;
    }
    my $sort   = $order ? $order.'_sort+asc' : '';
    my $fields = ['source', 'function', 'accession', 'organism', 'ncbi_tax_id', 'type', 'md5'];
    my $method = (@$data > 1) ? 'POST' : 'GET';
    my $query  = 'object%3Aannotation+AND+('.join('+OR+', map { $field.'%3A'.$_ } @$data).')';
    if ($source) {
        $query .= '+AND+source%3A'.$source;
    }
    return $self->get_solr_query($method, $Conf::m5nr_solr, $Conf::m5nr_collect, $query, $sort, $offset, $limit, $fields);
}

1;

