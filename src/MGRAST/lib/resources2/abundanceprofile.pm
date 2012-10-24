package resources2::abundanceprofile;

use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use MGRAST::Analysis;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "abundanceprofile";
    $self->{attributes} = { "id"                  => [ 'string', 'unique object identifier' ],
    	                    "format"              => [ 'string', 'format specification name' ],
    	                    "format_url"          => [ 'string', 'url to the format specification' ],
    	                    "type"                => [ 'string', 'type of the data in the return table (taxon, function or gene)' ],
    	                    "generated_by"        => [ 'string', 'identifier of the data generator' ],
    	                    "date"                => [ 'date', 'time the output data was generated' ],
    	                    "matrix_type"         => [ 'string', 'type of the data encoding matrix (dense or sparse)' ],
    	                    "matrix_element_type" => [ 'string', 'data type of the elements in the return matrix' ],
    	                    "shape"               => [ 'list', [ 'integer', 'list of the dimension sizes of the return matrix' ] ],
    	                    "rows"                => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
    						                                                   'metadata' => [ 'hash', 'key value pairs describing metadata' ] }, "rows object" ] ] ],
    	                    "columns"             => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
    							                                               'metadata' => [ 'hash', 'list of metadata, contains the metagenome' ] }, "columns object" ] ] ],
    	                    "data"                => [ 'list', [ 'list', [ 'float', 'the matrix values' ] ] ]
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
				    'parameters'  => { 'options'     => {},
						               'required'    => {},
						               'body'        => {} } },
				  { 'name'        => "instance",
				    'request'     => $self->cgi->url."/".$self->name."/{ID}",
				    'description' => "Returns a single data object.",
				    'method'      => "GET" ,
				    'type'        => "synchronous" ,  
				    'attributes'  => $self->attributes,
				    'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												   [ 'verbose', 'returns all metadata' ],
												   [ 'full', 'returns all references' ] ] ],
									  'type' => [ 'cv', [ ['organism', 'return organism data'],
											      ['function', 'return functional data'],
											      ['feature', 'return feature data'] ] ],
									  'source' => [ 'cv', [ [ "M5RNA", "comprehensive RNA database, type organism and feature only" ],
												[  "RDP", "RNA database, type organism and feature only" ],
												[ "Greengenes", "RNA database, type organism and feature only" ],
												[ "LSU", "RNA database, type organism and feature only" ],
												[ "SSU", "RNA database, type organism and feature only" ],
												[ "M5NR", "comprehensive protein database, type organism and feature only" ],
												[ "SwissProt", "protein database, type organism and feature only" ],
												[ "GenBank", "protein database, type organism and feature only" ],
												[ "IMG", "protein database, type organism and feature only" ],
												[ "SEED", "protein database, type organism and feature only" ],
												[ "TrEMBL", "protein database, type organism and feature only" ],
												[ "RefSeq", "protein database, type organism and feature only" ],
												[ "PATRIC", "protein database, type organism and feature only" ],
												[ "eggNOG", "protein database, type organism and feature only" ],
												[ "KEGG", "protein database, type organism and feature only" ],
												[ "NOG", "ontology database, type function only" ],
												[ "COG", "ontology database, type function only" ],
												[ "KO", "ontology database, type function only" ],
												[ "GO", "ontology database, type function only" ],
												[ "Subsystems", "ontology database, type function only" ] ] ],
									},
						       'required'    => { "id" => [ "string", "unique object identifier" ] },
						       'body'        => {} } },
				]
		};
  
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();

    # get data
    my $job = $master->Job->init( {metagenome_id => $id} );
    unless ($job && ref($job)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }
    
    # check rights
    unless ($job->{public} || exists($self->rights->{$id})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $self->prepare_data($job);
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $params = {};
    my $cgi = $self->cgi;
    $params->{type}   = $cgi->param('type') ? $cgi->param('type') : 'organism';
    $params->{source} = $cgi->param('source') ? $cgi->param('source') : (($params->{type} eq 'organism') ? 'M5NR' : (($params->{type} eq 'function') ? 'Subsystems': 'RefSeq'));
  
    # get database
    my $master = $self->connect_to_datasource();
    my $mgdb   = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
    }
    my $id = $data->{metagenome_id};
    $mgdb->set_jobs([$id]);
  
    # validate type / source
    my $all_srcs = {};
    if ($params->{type} eq 'organism') {
        $all_srcs = { M5NR => 1, M5RNA => 1 };
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
    } elsif ($params->{type} eq 'function') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_ontology_sources};
    } elsif ($params->{type} eq 'feature') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_protein_sources};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->ach->get_rna_sources};
    } else {
        $self->return_data({"ERROR" => "Invalid type for profile call: ".$params->{type}." - valid types are ['function', 'organism', 'feature']"}, 400);
    }
    unless (exists $all_srcs->{ $params->{source} }) {
        $self->return_data({"ERROR" => "Invalid source for profile call of type ".$params->{type}.": ".$params->{source}." - valid types are [".join(", ", keys %$all_srcs)."]"}, 400);
    }

    my $values  = [];
    my $rows    = [];
    my $ttype   = '';
    my $columns = [ { id => 'abundance', metadata => { metagenome => 'mgm'.$id } },
		            { id => 'e-value', metadata => { metagenome => 'mgm'.$id } },
		            { id => 'percent identity', metadata => { metagenome => 'mgm'.$id } },
		            { id => 'alignment length', metadata => { metagenome => 'mgm'.$id } }
		          ];

    # get data
    if ($params->{type} eq 'organism') {
        $ttype = 'Taxon';
        my $strain2tax = $mgdb->ach->map_organism_tax_id();
        my ($md5_abund, $result) = $mgdb->get_organisms_for_sources([$params->{source}]);
        # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
        foreach my $row (@$result) {
            next unless (exists $strain2tax->{$row->[9]});
            my $tax_str = [ "k__".$row->[2], "p__".$row->[3], "c__".$row->[4], "o__".$row->[5], "f__".$row->[6], "g__".$row->[7], "s__".$row->[9] ];
            push(@$rows, { "id" => $strain2tax->{$row->[9]}, "metadata" => { "taxonomy" => $tax_str }  });
            push(@$values, [ $self->toFloat($row->[10]), $self->toFloat($row->[12]), $self->toFloat($row->[14]), $self->toFloat($row->[16]) ]);
        }
    }
    elsif ($params->{type} eq 'function') {
        $ttype = 'Function';
        my $function2ont = $mgdb->ach->get_all_ontology4source_hash($params->{source});
        my ($md5_abund, $result) = $mgdb->get_ontology_for_source($params->{source});
        # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
        foreach my $row (@$result) {
            next unless (exists $function2ont->{$row->[1]});
            my $ont_str = [ map { defined($_) ? $_ : '-' } @{$function2ont->{$row->[1]}} ];
            push(@$rows, { "id" => $row->[1], "metadata" => { "ontology" => $ont_str } });
            push(@$values, [ $self->toFloat($row->[3]), $self->toFloat($row->[5]), $self->toFloat($row->[7]), $self->toFloat($row->[9]) ]);
        }
    }
    elsif ($params->{type} eq 'feature') {
        $ttype = 'Gene';
        my $md52id = {};
        my $result = $mgdb->get_md5_data(undef, undef, undef, undef, 1);
        # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, seek, length
        my @md5s = map { $_->[1] } @$result;
        map { push @{$md52id->{$_->[1]}}, $_->[0] } @{ $mgdb->ach->md5s2ids4source(\@md5s, $params->{source}) };
        foreach my $row (@$result) {
            next unless (exists $md52id->{$row->[1]});
            push(@$rows, { "id" => $row->[1], "metadata" => { $params->{source}." ID" => $md52id->{$row->[1]} } });
            push(@$values, [ $self->toFloat($row->[2]), $self->toFloat($row->[3]), $self->toFloat($row->[5]), $self->toFloat($row->[7]) ]);
        }
    }
  
    my $obj  = { "id"                  => "mgm".$id,
	             "format"              => "Biological Observation Matrix 1.0",
	             "format_url"          => "http://biom-format.org",
	             "type"                => $ttype." table",
	             "generated_by"        => "MG-RAST revision ".$Conf::server_version,
	             "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
	             "matrix_type"         => "dense",
	             "matrix_element_type" => "float",
	             "shape"               => [ scalar(@$values), 4 ],
	             "rows"                => $rows,
	             "columns"             => $columns,
	             "data"                => $values };
    
  return $obj;
}

1;
