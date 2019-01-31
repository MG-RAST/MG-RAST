package resources::m5nr;

use strict;
use warnings;
no warnings('once');

use List::Util qw(first);
use List::MoreUtils qw(any uniq);
use URI::Escape;
use Digest::MD5;
use POSIX qw(strftime);

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "m5nr";
    $self->{m5nr_default} = '1';
    $self->{request} = { ontology => 1, taxonomy => 1, sources => 1, accession => 1, 
                         md5 => 1, function => 1, organism => 1, sequence => 1 };
	$self->{attributes} = { taxonomy => { data => [ 'list', ['object', [{'organism' => [ 'string', 'organism name' ],
	                                                                     'species'  => [ 'string', 'organism species' ],
                                                                         'genus'    => [ 'string', 'organism genus' ],
                                                                         'family'   => [ 'string', 'organism family' ],
                                                                         'order'    => [ 'string', 'organism order' ],
                                                                         'class'    => [ 'string', 'organism class' ],
                                                                         'phylum'   => [ 'string', 'organism phylum' ],
                                                                         'domain'   => [ 'string', 'organism domain' ],
                                                                         'ncbi_tax_id' => [ 'int', 'organism ncbi id' ]}, "taxonomy object"]] ],
             	                          version => [ 'integer', 'version of M5NR' ],
             	                          url     => [ 'uri', 'resource location of this object instance' ] },
             	            ontology => { data => [ 'list', ['object', [{'id'     => [ 'string', 'ontology ID' ],
                                      	                                 'level1' => [ 'string', 'ontology top level' ],
                                                                         'level2' => [ 'string', 'ontology level 2' ],
                                                                         'level3' => [ 'string', 'ontology level 3' ],
                                                                         'level4' => [ 'string', 'ontology bottom level' ],
                                                                         'source' => [ 'string', 'source name' ]}, "ontology object"]] ],
                                          version => [ 'integer', 'version of M5NR' ],
                                          url     => [ 'uri', 'resource location of this object instance' ] },
                           	sources  => { data    => [ 'list', ['object', 'source object'] ],
                                          version => [ 'integer', 'version of M5NR' ],
                                          url     => [ 'uri', 'resource location of this object instance' ] },
                            annotation => { next   => ["uri","link to the previous set or null if this is the first set"],
                                            prev   => ["uri","link to the next set or null if this is the last set"],
                                            limit  => ["integer","maximum number of data items returned, default is 10"],
                                            offset => ["integer","zero based index of the first returned data item"],
                                            total_count => ["integer","total number of available data items"],
                                            version => [ 'integer', 'version of M5NR' ],
                                            url  => [ 'uri', 'resource location of this object instance' ],
                                            data => [ 'list', ['object', [{'accession'   => [ 'string', 'unique identifier given by source' ],
                                                                           'md5'         => [ 'string', 'md5 checksum - M5NR ID' ],
                                                                           'function'    => [ 'string', 'function annotation' ],
                                                                           'organism'    => [ 'string', 'organism annotation' ],
                                                                           'ncbi_tax_id' => [ 'int', 'organism ncbi tax_id' ],
                                                                           'type'        => [ 'string', 'source type' ],
                                                                           'source'      => [ 'string', 'source name' ]}, "annotation object"]] ] },
                            sequence => { version => [ 'integer', 'version of M5NR' ],
                                          url  => [ 'uri', 'resource location of this object instance' ],
                                          data => [ 'object', [{ 'md5'      => [ 'string', 'md5 checksum - M5NR ID' ],
                                                                 'sequence' => [ 'string', 'protein sequence' ]}, "sequence object"] ] }
             	          };
    return $self;
}


# resource is called without any parameters
# this method must return a description of the resource
sub info {
  my ($self) = @_;
  my $content = {
          'name'          => $self->name,
		  'url'           => $self->url."/".$self->name,
		  'description'   => "M5NR provides data through a comprehensive non-redundant protein / rRNA database",
		  'type'          => 'object',
		  'documentation' => $self->url.'/api.html#'.$self->name,
		  'requests'      => [
		               { 'name'        => "info",
					     'request'     => $self->url."/".$self->name,
				         'description' => "Returns description of parameters and attributes.",
			             'method'      => "GET",
					     'type'        => "synchronous",
					     'attributes'  => "self",
				         'parameters'  => { 'options'  => {},
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "ontology",
					     'request'     => $self->url."/".$self->name."/ontology",
					     'description' => "Return functional hierarchy",
					     'example'     => [ $self->url."/".$self->name."/ontology?source=Subsystems&min_level=level3",
       				                        'retrieve subsystems hierarchy for the top 3 levels' ],
					     'method'      => "GET",
					     'type'        => "synchronous",
					     'attributes'  => $self->{attributes}{ontology},
					     'parameters'  => { 'options'  => {
					                            'source' => ['cv', $self->source->{ontology}],
									            'filter_level' => ['cv', $self->hierarchy->{ontology}],
									            'filter' => ['string', 'text of ontology group (filter_level) to filter by'],
									            'min_level' => ['cv', $self->hierarchy->{ontology}],
									            'exact'  => ['boolean', "if true return only those ontologies that exactly match filter, default is false"],
									            'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}],
									            'compressed' => ['boolean', 'if true, return full compressed ontology, other options ignored'],
									        },
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "taxonomy",
					     'request'     => $self->url."/".$self->name."/taxonomy",
					     'description' => "Return organism hierarchy",
					     'example'     => [ $self->url."/".$self->name."/taxonomy?filter=Bacteroidetes&filter_level=phylum&min_level=genus",
        				                    'retrieve all class level taxa that belong to Bacteroidetes' ],
					     'method'      => "GET",
					     'type'        => "synchronous",
					     'attributes'  => $self->{attributes}{taxonomy},
					     'parameters'  => { 'options'  => {
					                            'filter_level' => ['cv', [ @{$self->hierarchy->{organism}}[1..7] ]],
	                                            'filter' => ['string', 'text of taxonomy group (filter_level) to filter by'],
									            'min_level' => ['cv', [ @{$self->hierarchy->{organism}}[1..7] ]],
									            'exact'  => ['boolean', "if true return only those taxonomies that exactly match filter, default is false"],
									            'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}],
									            'compressed' => ['boolean', 'if true, return full compressed taxonomy, other options ignored'],
									        },
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "sources",
					     'request'     => $self->url."/".$self->name."/sources",
					     'example'     => [ $self->url."/".$self->name."/sources",
         				                    'retrieve all data sources for M5NR' ],
					     'description' => "Return all sources in M5NR",
					     'method'      => "GET",
					     'type'        => "synchronous",
					     'attributes'  => $self->{attributes}{sources},
					     'parameters'  => { 'options'  => {
					                            'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
					                        },
							                'required' => {},
							                'body'     => {} }
				       },
				       { 'name'        => "accession",
   					     'request'     => $self->url."/".$self->name."/accession/{id}",
   					     'description' => "Return annotation of given source protein ID",
   					     'example'     => [ $self->url."/".$self->name."/accession/YP_003268079.1",
          				                    "retrieve M5NR data for accession ID 'YP_003268079.1'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {
   					                            'limit'  => ['integer','maximum number of items requested'],
                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
    					                    },
   							                'required' => { "id" => ["string", "unique identifier from source DB"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "md5",
   					     'request'     => $self->url."/".$self->name."/md5/{id}",
   					     'description' => "Return annotation(s) or sequence of given md5sum (M5NR ID)",
   					     'example'     => [ $self->url."/".$self->name."/md5/000821a2e2f63df1a3873e4b280002a8?source=KEGG",
           				                    "retrieve KEGG M5NR data for md5sum '000821a2e2f63df1a3873e4b280002a8'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {
   					                            'source' => ['string','source name to restrict search by'],
   					                            'limit'  => ['integer','maximum number of items requested'],
                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                'order'  => ['string','name of the attribute the returned data is ordered by'],
   					                            'sequence' => ['boolean', "if true return sequence output, else return annotation output, default is false"],
   					                            'format' => ['cv', [['fasta', 'return sequences in fasta format'],
                                                                    ['json', 'return sequences in json struct']] ],
   					                            'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
   					                        },
   							                'required' => { "id" => ["string", "unique identifier in form of md5 checksum"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "function",
   					     'request'     => $self->url."/".$self->name."/function/{text}",
   					     'description' => "Return annotations for function names containing the given text",
   					     'example'     => [ $self->url."/".$self->name."/function/sulfatase?source=GenBank",
             				                "retrieve GenBank M5NR data for function names containing string 'sulfatase'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {
   					                            'source'  => ['string','source name to restrict search by'],
                                                'id_only' => ['boolean', "if true return map of { 'function_id' : 'function_text' } only"],
   					                            'exact'   => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
   					                            'inverse' => ['boolean', "if true return only those annotations that do not match input text, default is false"],
   					                            'limit'   => ['integer','maximum number of items requested'],
                                                'offset'  => ['integer','zero based index of the first data object to be returned'],
                                                'order'   => ['string','name of the attribute the returned data is ordered by'],
                                                'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
    					                    },
   							                'required' => { "text" => ["string", "text string of partial function name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "organism",
   					     'request'     => $self->url."/".$self->name."/organism/{text}",
   					     'description' => "Return annotations for organism names containing the given text",
   					     'example'     => [ $self->url."/".$self->name."/organism/akkermansia?source=KEGG",
              				                "retrieve KEGG M5NR data for organism names containing string 'akkermansia'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {
   					                            'source' => ['string','source name to restrict search by'],
   					                            'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
   					                            'inverse' => ['boolean', "if true return only those annotations that do not match input text, default is false"],
   					                            'tax_level' => ['cv', $self->hierarchy->{organism}],
   					                            'limit'  => ['integer','maximum number of items requested'],
                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
     					                    },
   							                'required' => { "text" => ["string", "text string of partial organism name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "sequence",
   					     'request'     => $self->url."/".$self->name."/sequence/{text}",
   					     'description' => "Return annotation(s) for md5sum (M5NR ID) of given sequence",
   					     'example'     => [ $self->url."/".$self->name."/sequence/MSTAITRQIVLDTETTGMNQIGAHYEGHKIIEIGAVEVVNRRLTGNNFHVYLKPDRLVDPEAFGVHGIADEFLLDKPTFAEVADEFMDYIRGAELVIHNAAFDIGFMDYEFSLLKRDIPKTNTFCKVTDSLAVARKMFPGKRNSLDALCARYEIDNSKRTLHGALLDAQILAEVYLAMTGGQTSMAFAMEGETQQQQGEATIQRIVRQASKLRVVFATDEEIAAHEARLDLVQKKGGSCLWRA?source=TrEMBL",
            				                "retrieve TrEMBL M5NR data for md5sum of sequence 'MSTAITRQIVLDTETTGMNQIGAHYEGHKIIEIGAVEVVNRRLTGNNFHVYLKPDRLVDPEAFGVHGIADEFLLDKPTFAEVADEFMDYIRGAELVIHNAAFDIGFMDYEFSLLKRDIPKTNTFCKVTDSLAVARKMFPGKRNSLDALCARYEIDNSKRTLHGALLDAQILAEVYLAMTGGQTSMAFAMEGETQQQQGEATIQRIVRQASKLRVVFATDEEIAAHEARLDLVQKKGGSCLWRA'" ],
   					     'method'      => "GET",
   					     'type'        => "synchronous",
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {
   					                            'source' => ['string','source name to restrict search by'],
   					                            'limit'  => ['integer','maximum number of items requested'],
                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
      					                    },
   							                'required' => { "text" => ["string", "text string of protein sequence"] },
   							                'body'     => {} }
   				       },
                       { 'name'        => "accession",
      				     'request'     => $self->url."/".$self->name."/accession",
      				     'description' => "Return annotations of given source protein IDs",
      				     'example'     => [ 'curl -X POST -d \'{"order":"function","data":["YP_003268079.1","COG1764"]}\' "'.$self->url."/".$self->name.'/accession"',
               				                "retrieve M5NR data for accession IDs 'YP_003268079.1' and 'COG1764' ordered by function" ],
      				      'method'      => "POST",
      				      'type'        => "synchronous",
      				      'attributes'  => $self->{attributes}{annotation},
      				      'parameters'  => { 'body'     => {
      					                         'data'   => ['list',["string","unique identifier from source DB"]],
      					                         'limit'  => ['integer','maximum number of items requested'],
                                                 'offset' => ['integer','zero based index of the first data object to be returned'],
                                                 'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                 'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
       					                     },
      							             'required' => {},
      							             'options'  => {} }
      				       },
   				           { 'name'        => "md5",
      					     'request'     => $self->url."/".$self->name."/md5",
      					     'description' => "Return annotations or sequences of given md5sums (M5NR ID)",
      					     'example'     => [ 'curl -X POST -d \'{"source":"RefSeq","data":["000821a2e2f63df1a3873e4b280002a8","15bf1950bd9867099e72ea6516e3d602"]}\' "'.$self->url."/".$self->name.'/md5"',
                				                "retrieve RefSeq M5NR data for md5s '000821a2e2f63df1a3873e4b280002a8' and '15bf1950bd9867099e72ea6516e3d602'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => {
      					                            'data'   => ['list',["string","unique identifier in form of md5 checksum"]],
      					                            'source' => ['string','source name to restrict search by'],
      					                            'limit'  => ['integer','maximum number of items requested'],
                                                    'offset' => ['integer','zero based index of the first data object to be returned'],
                                                    'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                    'sequence' => ['boolean', "if true return sequence output, else return annotation output, default is false"],
                                                    'format' => ['cv', [['fasta', 'return sequences in fasta format'],
                                                                        ['json', 'return sequences in json struct']] ],
                                                    'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
      					                        },
      							                'required' => {},
      							                'options'  => {} }
      				       },
   				           { 'name'        => "function",
      					     'request'     => $self->url."/".$self->name."/function",
      					     'description' => "Return annotations for function names containing the given texts",
      					     'example'     => [ 'curl -X POST -d \'{"source":"GenBank","limit":50,"data":["sulfatase","phosphatase"]}\' "'.$self->url."/".$self->name.'/function_id"',
                  				                "retrieve top 50 GenBank M5NR data for function names containing string 'sulfatase' or 'phosphatase'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => {
      					                            'data'    => ['list',["string","text string of partial function name"]],
      					                            'md5s'    => ['list',["string","md5 to constrain search by"]],
      					                            'source'  => ['string','source name to restrict search by'],
                                                    'id_only' => ['boolean', "if true return only [{ 'function_id' : <ID>, 'function' : <TEXT> }]"],
      					                            'exact'   => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
      					                            'inverse' => ['boolean', "if true return only those annotations that do not match input text, default is false"],
      					                            'limit'   => ['integer','maximum number of items requested'],
                                                    'offset'  => ['integer','zero based index of the first data object to be returned'],
                                                    'order'   => ['string','name of the attribute the returned data is ordered by'],
                                                    'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
       					                        },
      							                'required' => {},
      							                'options'  => {} }
      				       },
   				           { 'name'        => "function_id",
      					     'request'     => $self->url."/".$self->name."/function_id",
      					     'description' => "Return annotations for given function IDs",
					     'example'     => [ 'curl -X POST -d \'{"source":"GenBank","data":[2442,5432]}\' "'.$self->url."/".$self->name.'/function"',
                  				                "retrieve the GenBank functions for the defined ids" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => {
      					                            'data'     => ['list',["integer","function index ID"]],
                                                    'compress' => ['boolean', 'if true return map of { <ID> : <TEXT> } only'],
                                                    'version'  => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
       					                        },
      							                'required' => {},
      							                'options'  => {} }
      				       },
      				       { 'name'        => "organism",
      					     'request'     => $self->url."/".$self->name."/organism",
      					     'description' => "Return annotations for organism names containing the given texts",
      					     'example'     => [ 'curl -X POST -d \'{"source":"KEGG","order":"accession","data":["akkermansia","yersinia"]}\' "'.$self->url."/".$self->name.'/organism"',
                   				                "retrieve KEGG M5NR data (ordered by accession ID) for organism names containing string 'akkermansia' or 'yersinia'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => {
      					                            'data'   => ['list',["string","text string of partial organism name"]],
      					                            'md5s'   => ['list',["string","md5 to constrain search by"]],
      					                            'source' => ['string','source name to restrict search by'],
      					                            'exact'  => ['boolean', "if true return only those annotations that exactly match input text, default is false"],
      					                            'inverse' => ['boolean', "if true return only those annotations that do not match input text, default is false"],
      					                            'tax_level' => ['cv', $self->hierarchy->{organism}],
      					                            'limit'  => ['integer','maximum number of items requested'],
                                                    'offset' => ['integer','zero based index of the first data object to be returned'],
                                                    'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                    'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
        					                    },
      							                'required' => {},
      							                'options'  => {} }
      				       },
      				       { 'name'        => "sequence",
      					     'request'     => $self->url."/".$self->name."/sequence",
      					     'description' => "Return annotations for md5s (M5NR ID) of given sequences",
      					     'example'     => [ 'curl -X POST -d \'{"source":"GenBank","order":"source","data":["MAGENHQWQGSIL","MAGENHQWQGSIL"]}\' "'.$self->url."/".$self->name.'/sequence"',
                 				                "retrieve M5NR data ordered by source for sequences 'MAGENHQWQGSIL' and 'MAGENHQWQGSIL'" ],
      					     'method'      => "POST",
      					     'type'        => "synchronous",
      					     'attributes'  => $self->{attributes}{annotation},
      					     'parameters'  => { 'body'     => {
      					                            'data'   => ['list',["string","text string of protein sequence"]],
      					                            'source' => ['string','source name to restrict search by'],
      					                            'limit'  => ['integer','maximum number of items requested'],
                                                    'offset' => ['integer','zero based index of the first data object to be returned'],
                                                    'order'  => ['string','name of the attribute the returned data is ordered by'],
                                                    'version' => ['integer', 'M5NR version, default '.$self->{m5nr_default}]
         					                    },
      							                'required' => {},
      							                'options'  => {} }
      				       },
                           {
                               'name'        => 'create',
                               'request'     => $self->url."/".$self->name."/cassandra/create",
                               'description' => "Create cassandra keyspace for new M5NR version, requires admin auth token",
                               'method'      => "POST",
                               'type'        => "synchronous",
                               'attributes'  => {
                                   'status' => ['string', 'status of action'],
                                   'error'  => ['string', 'error message if any'],
                                   'time'   => ['date', 'time action was completed']
                               },
                               'parameters' => {
                                   'body' => {
                                       'version' => ['integer', 'M5NR version']
                                   },
                                   'required' => {},
                                   'options'  => {}
                               }
                           },
                           {
                               'name'        => 'insert',
                               'request'     => $self->url."/".$self->name."/cassandra/insert",
                               'description' => "Insert data into given cassandra table for new M5NR version, requires admin auth token",
                               'method'      => "POST",
                               'type'        => "synchronous",
                               'attributes'  => {
                                   'status' => ['string', 'status of action'],
                                   'error'  => ['string', 'error message if any'],
                                   'time'   => ['date', 'time action was completed']
                               },
                               'parameters' => {
                                   'body' => {
                                       'version' => ['integer', 'M5NR version'],
                                       'table'   => ['string', 'table to insert into'],
                                       'data'    => ['list', ['list', ['object', 'variable types for column insert']]]
                                   },
                                   'required' => {},
                                   'options'  => {}
                               }
                           }
   				       ]
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
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1] && ($self->method eq 'GET')) {
        $self->query($self->rest->[0], $self->rest->[1]);
    } elsif ((scalar(@{$self->rest}) > 1) && ($self->rest->[0] eq 'cassandra') && ($self->method eq 'POST')) {
        $self->cassandra($self->rest->[1]);
    } elsif ((scalar(@{$self->rest}) == 1) && ($self->method eq 'POST')) {
        $self->query($self->rest->[0]);
    } else {
        $self->info();
    }
}

# return static data: hierarchy or source
sub static {
    my ($self, $type) = @_;
    
    my $url = $self->url.'/m5nr/'.$type;
    my $solr = 'object%3A';
    my $limit = 1000000;
    my $exact = $self->cgi->param('exact') ? 1 : 0;
    my $filter = $self->cgi->param('filter') || '';
    my $min_lvl = $self->cgi->param('min_level') || '';
    my $version = $self->cgi->param('version') || $self->{m5nr_default};
    my $compressed = $self->cgi->param('compressed') ? 1 : 0;
    my $fields = [];
    my $grouped = 0;
    
    # validate version
    $self->check_version($version);
    
    # stream full compressed version from shock
    if ($compressed && (($type eq 'ontology') || ($type eq 'taxonomy'))) {
        my $query = {
            type => 'reference',
            data_type => 'm5nr hierarchy',
            name => $type,
            version => $version
        };
        my $nodes = $self->get_shock_query($query, $self->mgrast_token);
        if (scalar(@$nodes) != 1) {
            $self->return_data({"ERROR" => "missing compressed $type hierarchy for version $version"}, 404)
        }
        $self->return_shock_file($nodes->[0]{id}, $nodes->[0]{file}{size}, $nodes->[0]{file}{name}, $self->mgrast_token);
    }
    
    # return cached if exists
    $self->return_cached();
    
    if ($type eq 'ontology') {
        my @ont_hier = map { $_->[0] } @{$self->hierarchy->{ontology}};
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
            $filter = uri_escape(uri_unescape($filter));
            my $filter_lvl = $self->cgi->param('filter_level') || 'function';
            unless ( grep(/^$filter_lvl$/, @ont_hier) ) {
                $self->return_data({"ERROR" => "invalid filter_level for m5nr/ontology: ".$filter_lvl." - valid types are [".join(", ", @ont_hier)."]"}, 404);
            }
            $url .= '&filter_level='.$filter_lvl.'&filter='.$filter;
            if ($filter_lvl eq 'function') {
  	            $filter_lvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
            $solr .= '+AND+'.$filter_lvl.'%3A'.($exact ? '"'.$filter.'"' : '"*'.$filter.'*"');
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
        my @tax_hier = map { $_->[0] } @{$self->hierarchy->{organism}}[1..7];
        $min_lvl = $min_lvl || 'species';
        $fields  = [ @tax_hier, 'ncbi_tax_id', 'organism' ];
        
        $url .= '?min_level='.$min_lvl;
        $solr .= 'taxonomy';
        
        # filtered query
        if ($filter) {
            $filter = uri_escape(uri_unescape($filter));
            my $filter_lvl = $self->cgi->param('filter_level') || 'species';
            unless ( grep(/^$filter_lvl$/, @tax_hier) ) {
                $self->return_data({"ERROR" => "invalid filter_level for m5nr/taxonomy: ".$filter_lvl." - valid types are [".join(", ", @tax_hier)."]"}, 404);
            }
            $url .= '&filter_level='.$filter_lvl.'&filter='.$filter;
            $solr .= '+AND+'.$filter_lvl.'%3A'.($exact ? '"'.$filter.'"' : '"*'.$filter.'*"');
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
        $fields = [ 'source', 'source_id', 'organization', 'description', 'type', 'url', 'email', 'link', 'title', 'version', 'download_date' ];
        $solr .= 'source';
    } else {
        $self->return_data({"ERROR" => "invalid resource type was entered ($type)"}, 404);
    }
    
    my $data = [];
    if ($grouped) {
        my $result = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $solr, undef, 0, $limit, $fields);
        foreach my $group (@{$result->{$min_lvl}{groups}}) {
            push @$data, $group->{doclist}{docs}[0];
        }
    } else {
        ($data, undef) = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $solr, undef, 0, $limit, $fields);
    }
    my $obj = { data => $data, version => $version, url => $url };
    
    $self->return_data($obj, undef, 1); # cache this!
}

# return query data: annotation object
sub query {
    my ($self, $type, $item) = @_;
    
    # paramaters
    my $tlevel   = $self->cgi->param('tax_level') ? $self->cgi->param('tax_level') : 'strain';
    my $source   = $self->cgi->param('source')    ? $self->cgi->param('source') : undef;
    my $limit    = $self->cgi->param('limit')     ? $self->cgi->param('limit')  : 10;
    my $offset   = $self->cgi->param('offset')    ? $self->cgi->param('offset') : 0;
    my $order    = $self->cgi->param('order')     ? $self->cgi->param('order')  : undef;
    my $id_only  = $self->cgi->param('id_only')   ? 1 : 0;
    my $compress = $self->cgi->param('compress')  ? 1 : 0;
    my $exact    = $self->cgi->param('exact')     ? 1 : 0;
    my $inverse  = $self->cgi->param('inverse')   ? 1 : 0;
    my $sequence = $self->cgi->param('sequence')  ? 1 : 0;
    my $format   = $self->cgi->param('format')    ? $self->cgi->param('format') : 'fasta';
    my $version  = $self->cgi->param('version')  || $self->{m5nr_default};
    
    # build data / url
    my $post = ($self->method eq 'POST') ? 1 : 0;
    my $data = [];
    my $md5s = [];
    my $path = '';
    
    if ($post) {
        my $post_data = $self->cgi->param('POSTDATA') ? $self->cgi->param('POSTDATA') : join(" ", $self->cgi->param('keywords'));
        # all options sent as post data
        if ($post_data) {
            eval {
                my $json_data = $self->json->decode($post_data);
                if (exists $json_data->{tax_level}) { $tlevel   = $json_data->{tax_level}; }
                if (exists $json_data->{source})    { $source   = $json_data->{source}; }
                if (exists $json_data->{limit})     { $limit    = $json_data->{limit}; }
                if (exists $json_data->{offset})    { $offset   = $json_data->{offset}; }
                if (exists $json_data->{order})     { $order    = $json_data->{order}; }
                if (exists $json_data->{id_only})   { $id_only  = $json_data->{id_only} ? 1 : 0; }
                if (exists $json_data->{compress})  { $compress = $json_data->{compress} ? 1 : 0; }
                if (exists $json_data->{exact})     { $exact    = $json_data->{exact} ? 1 : 0; }
                if (exists $json_data->{inverse})   { $inverse  = $json_data->{inverse} ? 1 : 0; }
                if (exists $json_data->{sequence})  { $sequence = $json_data->{sequence} ? 1 : 0; }
                if (exists $json_data->{format})    { $format   = $json_data->{format}; }
                if (exists $json_data->{version})   { $version  = $json_data->{version}; }
                $data = $json_data->{data};
                $md5s = $json_data->{md5s};
            };
        # data sent in post form
        } elsif ($self->cgi->param('data')) {
            if ($self->cgi->param('md5s')) {
                @$md5s = split(/;/, $self->cgi->param('md5s'));
            }
            eval {
                @$data = split(/;/, $self->cgi->param('data'));
            };
        } else {
            $self->return_data( {"ERROR" => "POST request missing data"}, 400 );
        }
        if ($@) {
            $self->return_data( {"ERROR" => "unable to obtain POSTed data: ".$@}, 500 );
        }
        if ((ref($data) ne 'ARRAY') || (scalar(@$data) == 0)) {
            $self->return_data( {"ERROR" => "'data' field is empty or not an array"}, 400 );
        }
        $path = '/'.$type;
    } else {
        $data = [$item];
        $path = '/'.$type.'/'.$item;
    }
    
    # validate version
    $self->check_version($version);
    
    # get sequences if requested
    if (($type eq 'md5') && $sequence) {
        my ($result, $error) = $self->md5s2sequences($data, $version, $format);
        if ($error) {
            $self->return_data( {"ERROR" => $error}, 500 );
        }
        if ($format eq 'fasta') {
            $self->download_text($result, "md5s_".(scalar(@$data)).".fasta");
        } else {
            $self->return_data( {version => $version, data => $result} );
        }
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
        my @clean = grep { $self->clean_md5($_) } @$data;
        ($result, $total) = $self->query_annotation($version, 'md5', \@clean, $source, $offset, $limit, $order, 1);
    } elsif ($type eq 'accession') {
        ($result, $total) = $self->query_annotation($version, 'accession', $data, undef, $offset, $limit, $order, 1);
    } elsif ($type eq 'organism') {
        unless ( any {$_->[0] eq $tlevel} @{$self->hierarchy->{organism}} ) {
            $self->return_data({"ERROR" => "invalid tax_level for m5nr/organism: ".$tlevel." - valid types are [".join(", ", map {$_->[0]} @{$self->hierarchy->{organism}})."]"}, 404);
        }
        if ($tlevel eq 'strain') {
            $tlevel = 'organism';
        }
        ($result, $total) = $self->query_annotation($version, $tlevel, $data, $source, $offset, $limit, $order, $exact, $inverse, $md5s);
    } elsif ($type eq 'function') {
        if ($id_only) {
            ($result, $total) = $self->query_function($version, $data, $offset, $limit, $order, $exact, $inverse);
        } else {
            ($result, $total) = $self->query_annotation($version, 'function', $data, $source, $offset, $limit, $order, $exact, $inverse, $md5s);
        }
    } elsif ($type eq 'function_id') {
        my $chdl = $self->cassandra_handle("m5nr", $version);
        unless ($chdl) {
            return ({"ERROR" => "unable to connect to M5NR database"}, 500);
        }
        $result = $chdl->get_functions_by_id($data, $compress);
        $chdl->close();
        $self->return_data({'data' => $result, 'version' => $version});
    } else {
        $self->return_data({"ERROR" => "invalid resource type was entered ($type)"}, 404);
    }
    my $obj = $self->check_pagination($result, $total, $limit, $path, $offset);
    $obj->{version} = $version;
    
    $self->return_data($obj);
}

sub check_version {
    my ($self, $version) = @_;
    unless (exists $self->{m5nr_version}{$version}) {
        $self->return_data({"ERROR" => "invalid version was entered ($version). Please use one of: ".join(", ", keys %{$self->{m5nr_version}})}, 404);
    }
}

sub query_function {
    my ($self, $version, $data, $offset, $limit, $order, $exact, $inverse) = @_;
    
    @$data = map { uri_escape( uri_unescape($_) ) } @$data;
    if ($exact) {
        @$data = map { '"'.$_.'"' } @$data;
    } else {
        @$data = map { '"*'.$_.'*"' } @$data;
    }
    my $sort   = $order ? $order.'_sort+asc' : '';
    my $method = (@$data > 1) ? 'POST' : 'GET';
    my $query  = 'object%3Afunction+AND+';
    if ($inverse) {
        $query .= join('+AND+', map { '-function%3A'.$_ } @$data);
    } else {
        $query .= '('.join('+OR+', map { 'function%3A'.$_ } @$data).')';
    }
    return $self->get_solr_query($method, $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $query, $sort, $offset, $limit, ['function_id','function']);
}

sub query_annotation {
    my ($self, $version, $field, $data, $source, $offset, $limit, $order, $exact, $inverse, $md5s) = @_;
    
    @$data = map { uri_escape( uri_unescape($_) ) } @$data;
    if ($exact) {
        @$data = map { '"'.$_.'"' } @$data;
    } else {
        @$data = map { '"*'.$_.'*"' } @$data;
    }
    my $sort   = $order ? $order.'_sort+asc' : '';
    my $fields = ['source', 'function', 'organism', 'ncbi_tax_id', 'type', 'md5', 'accession'];
    my $method = ((@$data > 1) || ($md5s && (@$md5s > 0))) ? 'POST' : 'GET';
    my $query  = 'object%3Aannotation+AND+';
    if ($inverse) {
        $query .= join('+AND+', map { '-'.$field.'%3A'.$_ } @$data);
    } else {
        $query .= '('.join('+OR+', map { $field.'%3A'.$_ } @$data).')';
    }
    if ($source) {
        $query .= '+AND+source%3A'.$source;
    }
    if ($md5s && (@$md5s > 0)) {
        $query .= '+AND+('.join('+OR+', map { 'md5%3A'.$_ } @$md5s).')';
    }
    return $self->get_solr_query($method, $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $query, $sort, $offset, $limit, $fields);
}

sub cassandra {
    my ($self, $action) = @_;
    
    unless ($self->user && $self->user->is_admin('MGRAST')) {
        $self->info();
    }
    my $post = $self->get_post_data();
    my $version = $post->{'version'} || undef;
    unless ($version && ($version =~ /^\d+$/)) {
        return $self->return_data({"ERROR", "missing or invalid version number"}, 404);
    }
    
    my $m5nrcass = $self->cassandra_m5nr($version);
    unless ($m5nrcass) {
        $self->return_data({"ERROR" => "unable to connect to M5NR database"}, 500);
    }
    my $error = "";
       
    if ($action eq 'create') {
        $error = $m5nrcass->createNewM5nr();
    } elsif ($action eq 'insert') {
        my $table = $post->{'table'} || undef;
        my $data  = $post->{'data'} || [];
        # fix boolean
        if (($table eq "annotation.midx") || ($table eq "annotation.md5")) {
            for (my $i = 0; $i < scalar(@$data); $i++) {
                $data->[$i][2] = $data->[$i][2] ? 1 : 0;
            }
        }
        if ($table && (scalar(@$data) > 0)) {
            $error = $m5nrcass->batchInsert($table, $data);
        } else {
            $m5nrcass->close();
            return $self->return_data({"ERROR", "missing required table and/or data"}, 404);
        }
    } else {
        $m5nrcass->close();
        return $self->return_data({"ERROR", "invalid request"}, 404);
    }
    $m5nrcass->close();
    
    if ($error) {
        return $self->return_data({
            'status' => 'failed',
            'error'  => $error,
            'time'   => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
        });
    } else {
        return $self->return_data({
            'status' => 'success',
            'error'  => '',
            'time'   => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
        });
    }
}

1;

