package resources2::matrix;

use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use MGRAST::Metadata;
use MGRAST::Analysis;
use Babel::lib::Babel;
use Data::Dumper;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "matrix";
    $self->{attributes} = { "id"                   => [ 'string', 'unique object identifier' ],
    	                    "format"               => [ 'string', 'format specification name' ],
    	                    "format_url"           => [ 'string', 'url to the format specification' ],
    	                    "type"                 => [ 'string', 'type of the data in the return table (taxon, function or gene)' ],
    	                    "generated_by"         => [ 'string', 'identifier of the data generator' ],
    	                    "date"                 => [ 'date', 'time the output data was generated' ],
    	                    "matrix_type"          => [ 'string', 'type of the data encoding matrix (dense or sparse)' ],
    	                    "matrix_element_type"  => [ 'string', 'data type of the elements in the return matrix' ],
    	                    "matrix_element_value" => [ 'string', 'result_type of the elements in the return matrix' ],
    	                    "shape"                => [ 'list', ['integer', 'list of the dimension sizes of the return matrix'] ],
    	                    "rows"                 => [ 'list', ['object', [{'id'       => ['string', 'unique annotation text'],
    						                                                 'metadata' => ['hash', 'key value pairs describing metadata']}, "rows object"]] ],
    	                    "columns"              => [ 'list', ['object', [{'id'       => ['string', 'unique metagenome identifier'],
    							                                             'metadata' => ['hash', 'key value pairs describing metadata']}, "columns object"]] ],
    	                    "data"                 => [ 'list', ['list', ['float', 'the matrix values']] ]
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
    		        'url' => $self->cgi->url."/".$self->name,
    		        'description' => "A profile in biom format that contains abundance counts",
    		        'type' => 'object',
    		        'documentation' => $Conf::cgi_url.'/Html/api.html#'.$self->name,
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
    						        { 'name'        => "organism",
    				                  'request'     => $self->cgi->url."/".$self->name."/organism",
    				                  'description' => "Returns a single data object.",
    				                  'method'      => "GET" ,
    				                  'type'        => "synchronous" ,  
    				                  'attributes'  => $self->attributes,
    				                  'parameters'  => { 'options'  => { 'format' => [ 'cv', [['biom', 'Biological Observation Matrix (BIOM) format: http://biom-format.org/'],
                      					                                                      ['plain', 'tab-seperated plain text format']] ],
    				                                                     'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                      						                                                       ['evalue', 'average e-value exponent of hits in annotation'],
                      						                                                       ['identity', 'average percent identity of hits in annotation'],
                      						                                                       ['length', 'average alignment length of hits in annotation']] ],
    									                                 'source' => [ 'cv', [["M5RNA", "comprehensive RNA database"],
    												                                          ["RDP", "RNA database"],
    												                                          ["Greengenes", "RNA database"],
    												                                          ["LSU", "RNA database"],
    												                                          ["SSU", "RNA database"],
    												                                          ["M5NR", "comprehensive protein database"],
    												                                          ["SwissProt", "protein database"],
    												                                          ["GenBank", "protein database"],
    												                                          ["IMG", "protein database"],
    												                                          ["SEED", "protein database"],
    												                                          ["TrEMBL", "protein database"],
    												                                          ["RefSeq", "protein database"],
    												                                          ["PATRIC", "protein database"],
    												                                          ["eggNOG", "protein database"],
    												                                          ["KEGG", "protein database"]] ],
    												                     'show_hierarchy' => [ 'boolean', 'Show full hierarchy text string in row when using format=plain' ],
    												                     'group_level' => [ 'cv', [['strain', 'bottom organism taxanomic level'],
                                                         						                   ['species', 'organism type level'],
                                                         						                   ['genus', 'organism taxanomic level'],
                                                         						                   ['family', 'organism taxanomic level'],
                                                         						                   ['order', 'organism taxanomic level'],
                                                         						                   ['class', 'organism taxanomic level'],
                                                         						                   ['phylum', 'organism taxanomic level'],
                                                         						                   ['domain', 'top organism taxanomic level']] ],
                                                         				 'id' => [ "string", "one or more metagenome or project unique identifier" ] },
    						                             'required' => {},
    						                             'body'     => {} }
    						        },
    						        { 'name'        => "function",
    				                  'request'     => $self->cgi->url."/".$self->name."/function",
    				                  'description' => "Returns a single data object.",
    				                  'method'      => "GET" ,
    				                  'type'        => "synchronous" ,  
    				                  'attributes'  => $self->attributes,
    				                  'parameters'  => { 'options'  => { 'format' => [ 'cv', [['biom', 'Biological Observation Matrix (BIOM) format: http://biom-format.org/'],
                        					                                                  ['plain', 'tab-seperated plain text format']] ],
    				                                                     'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                        						                                                   ['evalue', 'average e-value exponent of hits in annotation'],
                        						                                                   ['identity', 'average percent identity of hits in annotation'],
                        						                                                   ['length', 'average alignment length of hits in annotation']] ],
    									                                 'source' => [ 'cv', [["NOG", "ontology database, type function only"],
    												                                          ["COG", "ontology database, type function only"],
    												                                          ["KO", "ontology database, type function only"],
    												                                          ["GO", "ontology database, type function only"],
    												                                          ["Subsystems", "ontology database, type function only"]] ],
    												                     'show_hierarchy' => [ 'boolean', 'Show full hierarchy text string in row when using format=plain' ],
    												                     'group_level' => [ 'cv', [['function', 'bottom ontology level (function:default)'],
                                                         						                   ['level3', 'function type level (function)' ],
                                                         						                   ['level2', 'function type level (function)' ],
                                                         						                   ['level1', 'top function type level (function)']] ],
    												                     'id' => [ "string", "one or more metagenome or project unique identifier" ] },
    						                             'required' => {},
    						                             'body'     => {} } }
    				                { 'name'        => "feature",
    				                  'request'     => $self->cgi->url."/".$self->name."/feature",
    				                  'description' => "Returns a single data object.",
    				                  'method'      => "GET" ,
    				                  'type'        => "synchronous" ,  
    				                  'attributes'  => $self->attributes,
    				                  'parameters'  => { 'options'  => { 'format' => [ 'cv', [['biom', 'Biological Observation Matrix (BIOM) format: http://biom-format.org/'],
                        					                                                  ['plain', 'tab-seperated plain text format']] ],
    				                                                     'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                        						                                                   ['evalue', 'average e-value exponent of hits in annotation'],
                        						                                                   ['identity', 'average percent identity of hits in annotation'],
                        						                                                   ['length', 'average alignment length of hits in annotation']] ],
    									                                 'source' => [ 'cv', [["RDP", "RNA database"],
                               												                  ["Greengenes", "RNA database"],
                               												                  ["LSU", "RNA database"],
                               											                      ["SSU", "RNA database"],
                               									                              ["SwissProt", "protein database"],
                               											                      ["GenBank", "protein database"],
                               										                          ["IMG", "protein database"],
                               											                      ["SEED", "protein database"],
                               								                                  ["TrEMBL", "protein database"],
                               												                  ["RefSeq", "protein database"],
                               												                  ["PATRIC", "protein database"],
                               									                              ["eggNOG", "protein database"],
                               									                              ["KEGG", "protein database"]] ],
                               									         'id' => [ "string", "one or more metagenome or project unique identifier" ] },
    						                             'required' => {},
    						                             'body'     => {} } }
    				              ] };
    $self->return_data($content);
}

1;
