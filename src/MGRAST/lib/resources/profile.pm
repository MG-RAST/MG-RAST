package resources::profile;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use List::MoreUtils qw(natatime);

use Conf;
use MGRAST::Analysis;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map { $_, 1 } grep {$_ ne '*'} @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "profile";
    $self->{rights} = \%rights;
    $self->{cutoffs} = { evalue => '5', identity => '60', length => '15' };
    $self->{batch_size} = 250;
    $self->{sources} = [
        $self->source->{m5nr},
        @{$self->source->{protein}},
        $self->source->{m5rna},
        @{$self->source->{rna}},
        @{$self->source->{ontology}}
    ];
    $self->{attributes} = {
        "id"                  => [ 'string', 'unique object identifier' ],
        "format"              => [ 'string', 'format specification name' ],
        "format_url"          => [ 'string', 'url to the format specification' ],
        "type"                => [ 'string', 'type of the data in the return table (taxon, function or gene)' ],
        "generated_by"        => [ 'string', 'identifier of the data generator' ],
        "date"                => [ 'date', 'time the output data was generated' ],
        "matrix_type"         => [ 'string', 'type of the data encoding matrix (dense or sparse)' ],
        "matrix_element_type" => [ 'string', 'data type of the elements in the return matrix' ],
        "shape"               => [ 'list', [ 'integer', 'list of the dimension sizes of the return matrix' ] ],
        "rows"                => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
    						                               'metadata' => [ 'hash', 'key value pairs describing metadata' ] }, "rows object" ] ]
    						     ],
    	"columns"             => [ 'list', [ 'object', [ { 'id'       => [ 'string', 'unique identifier' ],
    							                           'metadata' => [ 'hash', 'list of metadata, contains the metagenome' ] }, "columns object" ] ]
    							 ],
    	"data"                => [ 'list', [ 'list', [ 'float', 'the matrix values' ] ] ]
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name'         => $self->name,
        'url'          => $self->cgi->url."/".$self->name,
        'description'  => "A profile in biom format that contains abundance and similarity values",
        'type'          => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests'      => [
            { 'name'        => "info",
			  'request'     => $self->cgi->url."/".$self->name,
			  'description' => "Returns description of parameters and attributes.",
              'method'      => "GET" ,
              'type'        => "synchronous" ,  
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {} }
			},
            { 'name'        => "instance",
              'description' => "Returns a single data object in BIOM format",
              'method'      => "GET" ,
              'type'        => "synchronous or asynchronous" ,  
              'attributes'  => $self->attributes,
              'parameters'  => {
                  'options' => {
                      'asynchronous' => ['boolean', "if true return process id to query status resource for results, default is false"],
                      'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                      'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                      'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                      'nocutoff' => ['boolean', 'if true, get data using no cutoffs'],
                      'source'   => ['cv', $self->{sources}],
                      'type'     => ['cv', [ ['organism', 'return organism data'],
											  ['function', 'return functional data'],
											  ['feature', 'return feature data'] ]
									],
					  'hit_type' => ['cv', [ ['all', 'returns results based on all organisms that map to top hit per read-feature'],
                                             ['single', 'returns results based on a single organism for top hit per read-feature'],
                                             ['lca', 'returns results based on the Least Common Ancestor for all organisms (M5NR+M5RNA only) that map to hits from a read-feature']]
                                    ]
				  },
                  'required' => { "id" => ["string", "unique object identifier"] },
                  'body'     => {} }
            }
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
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $id does not exist"}, 404 );
    }
    $job = $job->[0];
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id $id is still processing and unavailable"}, 404 );
    }
    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || ($self->user && $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    # asynchronous call, fork the process and return the process id.
    # caching is done with shock, not memcache
    if ($self->cgi->param('asynchronous')) {
        # check if temp async node is in shock
        my $temp_attr = {
            type => "temp",
            url_id => $self->url_id,
            owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
            data_type => "profile"
        };
        my $tnodes = $self->get_shock_query($temp_attr, $self->mgrast_token);
        if ($tnodes && (@$tnodes > 0)) {
            $self->return_data({"status" => "submitted", "id" => $tnodes->[0]->{id}, "url" => $self->cgi->url."/status/".$tnodes->[0]->{id}});
        }
        # check if static feature profile node is in shock (attributes get changed)
        if (($self->cgi->param('type') eq 'feature') && $self->cgi->param('source') && $self->cgi->param('nocutoff')) {
            my $static_attr = {
                id => 'mgm'.$id,
                type => 'metagenome',
                data_type => 'profile',
                stage_name => 'done'
            };
            my $snodes = $self->get_shock_query($static_attr, $self->mgrast_token);
            foreach my $n (@$snodes) {
                # its cached ! return the node file
                if ($n->{attributes}{data_source} && ($n->{attributes}{data_source} eq $self->cgi->param('source'))) {
                    $self->return_data({"status" => "done", "id" => $n->{id}, "url" => $self->cgi->url."/status/".$n->{id}});
                }
            }
        }
        # need to create new temp node and fork
        my $node = $self->set_shock_node('mgm'.$id.'.biom', undef, $temp_attr, $self->mgrast_token, undef, undef, "7D");
        my $pid = fork();
        # child - get data and dump it
        if ($pid == 0) {
            close STDERR;
            close STDOUT;
            my ($data, $error) = $self->prepare_data($id, $node->{id});
            if ($error) {
                $data->{STATUS} = $error;
            }
            $self->put_shock_file($data->{id}.".biom", $data, $node->{id}, $self->mgrast_token);
            exit 0;
        }
        # parent - end html session
        else {
            $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->cgi->url."/status/".$node->{id}});
        }
    }
    # synchronous call, prepare then return data, cached in memcache
    else {
        # return cached if exists
        $self->return_cached();
        # prepare data
        my ($data, $error) = $self->prepare_data($id, undef);
        # don't cache errors
        if ($error) {
            $self->return_data($data, $error);
        } else {
            $self->return_data($data, undef, 1); # cache this!
        }
    }
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $id, $async_id) = @_;

    my $params = {};
    my $cgi = $self->cgi;
    $params->{type}     = $cgi->param('type') ? $cgi->param('type') : 'organism';
    $params->{hit_type} = $cgi->param('hit_type') ? $cgi->param('hit_type') : 'all';
    $params->{source}   = $cgi->param('source') ? $cgi->param('source') : (($params->{type} eq 'organism') ? 'M5NR' : (($params->{type} eq 'function') ? 'Subsystems': 'RefSeq'));
    $params->{evalue}   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    $params->{identity} = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    $params->{length}   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
    $params->{nocutoff} = $cgi->param('nocutoff') ? 1 : 0;
    
    my $shock_cached = (($params->{type} eq 'feature') && $params->{nocutoff}) ? 1 : 0;
    
    # get data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $id does not exist"}, 404 );
    }
    my $data = $job->[0];
    
    # get database
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        return ({"ERROR" => "could not connect to analysis database"}, 500);
    }
    $mgdb->set_jobs([$id]);
    
    # validate cutoffs
    if (int($params->{evalue}) < 1) {
        return ({"ERROR" => "invalid evalue for matrix call, must be integer greater than 1"}, 500);
    }
    if ((int($params->{identity}) < 0) || (int($params->{identity}) > 100)) {
        return ({"ERROR" => "invalid identity for matrix call, must be integer between 0 and 100"}, 500);
    }
    if (int($params->{length}) < 1) {
        return ({"ERROR" => "invalid length for matrix call, must be integer greater than 1"}, 500);
    }
    
    if ($params->{nocutoff}) {
        $params->{evalue}   = undef;
        $params->{identity} = undef;
        $params->{length}   = undef;
    } else {
        $params->{evalue}   = int($params->{evalue});
        $params->{identity} = int($params->{identity});
        $params->{length}   = int($params->{length});
    }
    
    # validate type / source
    my $all_srcs = {};
    if ($params->{type} eq 'organism') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
    } elsif ($params->{type} eq 'function') {
        map { $all_srcs->{$_->[0]} = 1 } grep { $_->[0] !~ /^GO/ } @{$mgdb->sources_for_type('ontology')};
    } elsif ($params->{type} eq 'feature') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
        map { $all_srcs->{$_->[0]} = 1 } grep { $_->[0] !~ /^GO/ } @{$mgdb->sources_for_type('ontology')};
        $all_srcs->{ALL} = 1;
    } else {
        return ({"ERROR" => "Invalid type for profile call: ".$params->{type}." - valid types are ['function', 'organism', 'feature']"}, 400);
    }
    unless (exists $all_srcs->{ $params->{source} }) {
        return ({"ERROR" => "Invalid source for profile call of type ".$params->{type}.": ".$params->{source}." - valid types are [".join(", ", keys %$all_srcs)."]"}, 400);
    }

    my $values  = [];
    my $rows    = [];
    my $ttype   = '';
    my $columns = [ { id => 'abundance', metadata => {metagenome => "mgm".$id} },
		            { id => 'e-value', metadata => {metagenome => "mgm".$id} },
		            { id => 'percent identity', metadata => {metagenome => "mgm".$id} },
		            { id => 'alignment length', metadata => {metagenome => "mgm".$id} }
		          ];

    # get data
    if ($params->{type} eq 'organism') {
        $ttype = 'Taxon';
        my $result = [];
        if ($params->{hit_type} eq 'all') {
            # my ($self, $sources, $eval, $ident, $alen, $with_taxid) = @_;
            (undef, $result) = $mgdb->get_organisms_for_sources([$params->{source}], $params->{evalue}, $params->{identity}, $params->{length}, 1);
            # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s, taxid
        } elsif ($params->{hit_type} eq 'single') {
            # my ($self, $source, $eval, $ident, $alen, $with_taxid) = @_;
            $result = $mgdb->get_organisms_unique_for_source($params->{source}, $params->{evalue}, $params->{identity}, $params->{length}, 1);
            # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s, taxid
        } elsif ($params->{hit_type} eq 'lca') {
            # my ($self, $eval, $ident, $alen) = @_;
            $result = $mgdb->get_lca_data($params->{evalue}, $params->{identity}, $params->{length});
            # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
        }
        foreach my $row (@$result) {
            if ($params->{hit_type} eq 'all') {
                my $rmd = { taxonomy => [$row->[2], $row->[3], $row->[4], $row->[5], $row->[6], $row->[7], $row->[8]] };
                push(@$rows, { "id" => $row->[9], "metadata" => $rmd });
                push(@$values, [ $self->toFloat($row->[10]), $self->toFloat($row->[12]), $self->toFloat($row->[14]), $self->toFloat($row->[16]) ]);
            } else {
                my $rmd = { taxonomy => [$row->[1], $row->[2], $row->[3], $row->[4], $row->[5], $row->[6], $row->[7]] };
                push(@$rows, { "id" => $row->[8], "metadata" => $rmd });
                push(@$values, [ $self->toFloat($row->[9]), $self->toFloat($row->[10]), $self->toFloat($row->[12]), $self->toFloat($row->[14]) ]);
            }
        }
    }
    elsif ($params->{type} eq 'function') {
        $ttype = 'Function';
        my $function2ont = $mgdb->get_hierarchy('ontology', $params->{source});
        # my ($self, $source, $eval, $ident, $alen) = @_;
        my (undef, $result) = $mgdb->get_ontology_for_source($params->{source}, $params->{evalue}, $params->{identity}, $params->{length});
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
        my $id2ann = {}; # md5_id => { accession => [], function => [], organism => [], ontology => [] }
        my $id2md5 = {}; # md5_id => md5
        # mgid, md5_id, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
        my $result = $mgdb->get_md5_data(undef, $params->{evalue}, $params->{identity}, $params->{length}, 1);
        my @md5s   = map { $_->[1] } @$result;
        my %ontol  = map { $_->[0], 1 } @{$mgdb->sources_for_type('ontology')};
        # handle grouped sources
        my $qsource = $params->{source};
        if (($params->{source} eq 'ALL') || ($params->{source} eq 'M5NR') || ($params->{source} eq 'M5RNA')) {
            $qsource = undef;
        }
        # query cassandra m5nr
        my $chdl = $self->cassandra_m5nr_handle("m5nr_v".$mgdb->_version, $Conf::cassandra_m5nr);
        my $iter = natatime $self->{batch_size}, @md5s;
        while (my @curr = $iter->()) {
            my $cass_data = $chdl->get_records_by_id(\@curr, $qsource);
            foreach my $info (@$cass_data) {
                # filter m5nr / m5rna results
                if (($params->{source} eq 'M5NR') && (! $info->{is_protein})) {
                    next;
                }
                if (($params->{source} eq 'M5RNA') && $info->{is_protein}) {
                    next;
                }
                $id2md5->{$info->{id}} = $info->{md5};
                if (exists $ontol{$info->{source}}) {
                    $id2ann->{$info->{id}}{$info->{source}}{ontology} = $info->{accession};
                } else {
                    $id2ann->{$info->{id}}{$info->{source}}{accession} = $info->{accession};
                }
                if ($info->{function}) {
                    $id2ann->{$info->{id}}{$info->{source}}{function} = $info->{function};
                }
                if ($info->{organism}) {
                    $id2ann->{$info->{id}}{$info->{source}}{organism} = $info->{organism};
                }
            }
        }
        $chdl->close();
        # add metadata to rows
        foreach my $row (@$result) {
            my $mid = $row->[1];
            next unless (exists $id2md5->{$mid});
            push(@$rows, { "id" => $id2md5->{$mid}, "metadata" => $id2ann->{$mid} });
            push(@$values, [ $self->toFloat($row->[2]), $self->toFloat($row->[3]), $self->toFloat($row->[5]), $self->toFloat($row->[7]) ]);
        }
    }
  
    my $obj = {
        "id"                  => "mgm".$id.'_'.$params->{type}.'_'.$params->{source},
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
        "data"                => $values
	};
	
	# cach it in shock if right type
	if ($shock_cached) {
	    my $node = {};
	    my $attr = {
	        id            => 'mgm'.$id,
	        job_id        => $data->{job_id},
	        created       => $data->{created_on},
	        name          => $data->{name},
	        owner         => 'mgu'.$data->{owner},
	        sequence_type => $data->{sequence_type},
	        status        => $data->{public} ? 'public' : 'private',
	        project_id    => undef,
	        project_name  => undef,
            type          => 'metagenome',
            data_type     => 'profile',
            data_source   => $params->{source},
            file_format   => 'biom',
            stage_name    => 'done',
            stage_id      => '999'
	    };
	    eval {
	        my $proj = $data->primary_project;
	        if ($proj->{id}) {
	            $attr->{project_id} = 'mgp'.$proj->{id};
	            $attr->{project_name} = $proj->{name};
            }
	    };
	    # update existing node / remove expiration
	    # file added to node in asynch mode in parent function
	    if ($async_id) {
	        $node = $self->update_shock_node($async_id, $attr, $self->mgrast_token);
	        $node = $self->update_shock_node_expiration($async_id, $self->mgrast_token);
	    }
	    # create new node
	    else {
	        $node = $self->set_shock_node($obj->{id}.'.biom', $obj, $attr, $self->mgrast_token);
	    }
	    if ($data->{public}) {
	        $self->edit_shock_public_acl($node->{id}, $self->mgrast_token, 'put', 'read');
	    }
	}
    
    return ($obj, undef);
}

1;
