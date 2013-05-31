package resources2::m5nr;

use strict;
use warnings;
no warnings('once');

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
                            annotation => { version => [ 'integer', 'version of the object' ],
                                            url  => [ 'uri', 'resource location of this object instance' ],
                                            data => [ 'list', ['object', [{'id'       => [ 'string', 'unique identifier' ],
                                                                           'md5'      => [ 'string', 'md5 checksum - M5NR ID' ],
                                                                           'function' => [ 'string', 'function annotation' ],
                                                                           'organism' => [ 'string', 'organism annotation' ],
                                                                           'source'   => [ 'string', 'source name' ]}, "annotation object"]] ] },
                            sequence => { version => [ 'integer', 'version of the object' ],
                                          url  => [ 'uri', 'resource location of this object instance' ],
                                          data => [ 'object', [{'id'       => [ 'string', 'unique identifier' ],
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
				       { 'name'        => "ID",
   					     'request'     => $self->cgi->url."/".$self->name."/id/{id}",
   					     'description' => "Return annotation or sequence of given source protein ID",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => {sequence => $self->{attributes}{sequence}, annotation => $self->{attributes}{annotation}},
   					     'parameters'  => { 'options'  => { 'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ] },
   							                'required' => { "id" => ["string", "unique identifier from protein DB"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "md5",
   					     'request'     => $self->cgi->url."/".$self->name."/md5/{id}",
   					     'description' => "Return annotation(s) or sequence of given md5sum (M5NR ID)",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => {sequence => $self->{attributes}{sequence}, annotation => $self->{attributes}{annotation}},
   					     'parameters'  => { 'options'  => { 'sequence' => [ 'boolean', "if true return sequence output, else return annotation output. default is false." ] },
   							                'required' => { "id" => ["string", "unique identifier in form of md5 checksum"] },
   							                'body'     => {} }
   				       },
				       { 'name'        => "function",
   					     'request'     => $self->cgi->url."/".$self->name."/function/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'partial' => [ 'boolean', "if true return all sets where function contains input string, else requires exact match. default is false." ] },
   							                'required' => { "text" => ["string", "text string of function name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "organism",
   					     'request'     => $self->cgi->url."/".$self->name."/organism/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => { 'partial' => [ 'boolean', "if true return all sets where organism contains input string, else requires exact match. default is false." ] },
   							                'required' => { "text" => ["string", "text string of organism name"] },
   							                'body'     => {} }
   				       },
   				       { 'name'        => "sequence",
   					     'request'     => $self->cgi->url."/".$self->name."/sequence/{text}",
   					     'description' => "",
   					     'method'      => "GET",
   					     'type'        => "synchronous",  
   					     'attributes'  => $self->{attributes}{annotation},
   					     'parameters'  => { 'options'  => {},
   							                'required' => { "text" => ["string", "text string of protein sequence"] },
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
    } elsif ((scalar(@{$self->rest}) > 1) && $self->rest->[1]) {
        $self->instance($self->rest->[0], $self->rest->[1]);
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

# return object data: id, md5, sequence
sub instance {
    my ($self, $type, $item) = @_;
    
    # get database
    my $ach = new Babel::lib::Babel;
    unless (ref($ach)) {
        $self->return_data({"ERROR" => "could not connect to M5NR database"}, 500);
    }
    
    my $seq  = $self->cgi->param('sequence') ? 1 : 0;
    my $part = $self->cgi->param('partial') ? 1 : 0;
    my $data = [];
    my $url  = $self->cgi->url.'/m5nr/'.$type.'/'.$item;
    
    if ($type eq 'id') {
        if ($seq) {
            my $md5 = $ach->id2md5($item);
            unless ($md5 && @$md5 && $md5->[0][0]) {
                $self->return_data( {"ERROR" => "id $item does not exist in M5NR"}, 404 );
            }
            $data = {id => $item, md5 => $md5->[0][0], sequence => $ach->md52sequence($md5->[0][0])};
        } else {
            $data = $self->reformat_set($ach->id2set($item));
        }
    } elsif ($type eq 'md5') {
        if ($seq) {
            $data = {id => undef, md5 => $item, sequence => $ach->md52sequence($item)};
        } else {
            $data = $self->reformat_set($ach->md52set($item));
        }
    } elsif ($type eq 'function') {
        $data = $self->reformat_set($ach->functions2sets([$item], $part));
    } elsif ($type eq 'organism') {
        $data = $self->reformat_set($ach->organisms2sets([$item], $part));
    } elsif ($type eq 'sequence') {
        $data = $self->reformat_set($ach->sequence2set(uc($item)));
    } else {
        $self->return_data({"ERROR" => "Invalid resource type was entered ($type)."}, 404);
    }
    
    if ($seq) {
        $url .= '?sequence=1';
    } elsif ($part) {
        $url .= '?partial=1';
    }
    my $obj = { data => $data, version => 1, url => $url };
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

sub reformat_set {
    my ($self, $set) = @_;
    my $data = [];
    foreach my $s (@$set) {
	    push @$data, { id       => $s->[0],
		               md5      => $s->[1],
		               function => $s->[2],
		               organism => $s->[3],
		               source   => $s->[4] };
    }
    return $data;
}

1;

