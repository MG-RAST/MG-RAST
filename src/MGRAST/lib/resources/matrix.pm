package resources::matrix;

use strict;
use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use MGRAST::Metadata;
use Data::Dumper;
use URI::Escape;
use List::Util qw(max min sum first);
use List::MoreUtils qw(any uniq);
use Digest::MD5 qw(md5_hex md5_base64);
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "matrix";
    $self->{org2tax} = {};
    $self->{org2tid} = {};
    $self->{max_mgs} = 100;
    $self->{cutoffs} = { evalue => '5', identity => '60', length => '15' };
    $self->{attributes} = {
        "id"                   => [ 'string', 'unique object identifier' ],
        "url"                  => [ 'uri', 'resource location of this object instance' ],
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
                                                         'metadata' => ['hash', 'key value pairs describing metadata']}, "rows object"]]
                                  ],
        "columns"              => [ 'list', ['object', [{'id'       => ['string', 'unique metagenome identifier'],
                                                         'metadata' => ['hash', 'key value pairs describing metadata']}, "columns object"]]
                                  ],
        "data"                 => [ 'list', ['list', ['float', 'the matrix values']] ]
    };
    $self->{sources} = {
        organism => [ @{$self->source->{protein}}, @{$self->source->{rna}} ],
        ontology => $self->source->{ontology}
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->url."/".$self->name,
        'description' => "A profile in biom format that contains abundance counts",
        'type' => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests' => [
            { 'name'        => "info",
              'request'     => $self->url."/".$self->name,
              'description' => "Returns description of parameters and attributes.",
              'method'      => "GET" ,
              'type'        => "synchronous" ,  
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {} }
            },
            { 'name'        => "organism",
              'request'     => $self->url."/".$self->name."/organism",
              'description' => "Returns a BIOM v1.0 object as described here: http://biom-format.org/documentation/format_versions/biom-1.0.html",
              'example'     => [ $self->url."/".$self->name."/organism?id=mgm4447943.3&id=mgm4447192.3&id=mgm4447102.3&group_level=family&source=RefSeq&evalue=15",
                                 'retrieve abundance matrix of RefSeq organism annotations at family taxa for listed metagenomes at evalue < e-15' ],
              'method'      => "GET" ,
              'type'        => "asynchronous",
              'attributes'  => $self->{attributes},
              'parameters'  => {
                  'options'  => {
                      'id'       => [ 'string', 'one or more metagenome or project unique identifier' ],
                      'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                      'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                      'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                      'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                                                ['evalue', 'average e-value exponent of hits in annotation'],
                                                ['identity', 'average percent identity of hits in annotation'],
                                                ['length', 'average alignment length of hits in annotation']] ],
                      'hit_type' => [ 'cv', [['all', 'returns results based on all organisms that map to top hit per read-feature'],
                                             ['single', 'returns results based on a single organism for top hit per read-feature'],
                                             ['lca', 'returns results based on the Least Common Ancestor for all organisms for hits from a read-feature']] ],
                      'source' => [ 'cv', $self->{sources}{organism} ],
                      'group_level' => [ 'cv', $self->hierarchy->{organism} ],
                      'grep' => [ 'string', 'filter the return results to only include annotations that contain this text' ],
                      'filter' => [ 'string', 'filter the return results to only include abundances based on genes with this function' ],
                      'filter_level' => [ 'cv', $self->hierarchy->{ontology} ],
                      'filter_source' => [ 'cv', $self->{sources}{ontology} ],
                      'hide_metadata' => [ 'boolean', "if true do not return metagenome metadata in 'columns' object, default is false" ],
                      'version' => [ 'int', 'M5NR version, default '.$self->{m5nr_default} ] },
				  'required' => {},
                  'body'     => {} }
            },
            { 'name'        => "function",
              'request'     => $self->url."/".$self->name."/function",
              'description' => "Returns a BIOM v1.0 object as described here: http://biom-format.org/documentation/format_versions/biom-1.0.html.",
              'example'     => [ $self->url."/".$self->name."/function?id=mgm4447943.3&id=mgm4447192.3&id=mgm4447102.3&group_level=level3&source=Subsystems&identity=80",
                                 'retrieve abundance matrix of Subsystem annotations at level3 for listed metagenomes at % identity > 80' ],
              'method'      => "GET" ,
              'type'        => "asynchronous",
              'attributes'  => $self->{attributes},
              'parameters'  => {
				'options'  => {
                           'id'       => [ 'string', 'one or more metagenome or project unique identifier' ],
					       'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
					       'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
					       'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
					       'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
									 ['evalue', 'average e-value exponent of hits in annotation'],
									 ['identity', 'average percent identity of hits in annotation'],
									 ['length', 'average alignment length of hits in annotation']] ],
					       'source' => [ 'cv', $self->{sources}{ontology} ],
					       'group_level' => [ 'cv', $self->hierarchy->{ontology} ],
					       'grep' => [ 'string', 'filter the return results to only include annotations that contain this text' ],
					       'filter' => [ 'string', 'filter the return results to only include abundances based on genes with this organism' ],
					       'filter_level' => [ 'cv', $self->hierarchy->{organism} ],
					       'filter_source' => [ 'cv', $self->{sources}{organism} ],
					       'hide_metadata' => [ 'boolean', "if true do not return metagenome metadata in 'columns' object, default is false" ],
					       'version' => [ 'int', 'M5NR version, default '.$self->{m5nr_default} ] },
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
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (($self->rest->[0] eq 'organism') || ($self->rest->[0] eq 'function')) {
        $self->instance($self->rest->[0]);
    } else {
        $self->info();
    }
}

# the resource is called with a parameter
sub instance {
    my ($self, $type) = @_;
    
    # get id set
    unless ($self->cgi->param('id')) {
        $self->return_data( {"ERROR" => "no ids submitted, aleast one 'id' is required"}, 400 );
    }
    my @ids   = $self->cgi->param('id');
    my %mgids = ();
    my $seen  = {};
        
    # get database
    my $master = $self->connect_to_datasource();

    # get user viewable
    my $m_star = ($self->user && $self->user->has_star_right('view', 'metagenome')) ? 1 : 0;
    my $p_star = ($self->user && $self->user->has_star_right('view', 'project')) ? 1 : 0;
    my $m_private = $master->Job->get_private_jobs($self->user, 1);
    my $m_public  = $master->Job->get_public_jobs(1);
    my $p_private = $self->user ? $self->user->has_right_to(undef, 'view', 'project') : [];
    my $p_public  = $master->Project->get_public_projects(1);
    my %m_rights = map {$_, 1} (@$m_private, @$m_public);
    my %p_rights = map {$_, 1} (@$p_private, @$p_public);

    # get unique list of mgids based on user rights and inputed ids
    foreach my $tempid (@ids) {
        my $id = $self->idresolve($tempid);
        next if (exists $seen->{$id});
        if ($id =~ /^mgm(\d+\.\d+)$/) {
            if ($m_star || exists($m_rights{$1})) {
                $mgids{$1} = 1;
            } else {
                $self->return_data( {"ERROR" => "insufficient permissions in matrix call for id: ".$id}, 401 );
            }
        } elsif ($id =~ /^mgp(\d+)$/) {
            if ($p_star || exists($p_rights{$1})) {
                my $proj = $master->Project->init( {id => $1} );
                foreach my $mgid (@{ $proj->metagenomes(1) }) {
                    next unless ($m_star || exists($m_rights{$mgid}));
                    $mgids{$mgid} = 1;
                }
            } else {
                $self->return_data( {"ERROR" => "insufficient permissions in matrix call for id: ".$id}, 401 );
            }
        } else {
            $self->return_data( {"ERROR" => "unknown id in matrix call: ".$tempid}, 404 );
        }
        $seen->{$id} = 1;
    }
    if (scalar(keys %mgids) == 0) {
        $self->return_data( {"ERROR" => "no valid ids submitted and/or found: ".join(", ", @ids)}, 404 );
    }
    if (scalar(keys %mgids) > $self->{max_mgs}) {
        $self->return_data( {"ERROR" => "to many metagenomes requested (".scalar(keys %mgids)."), query is limited to ".$self->{max_mgs}." metagenomes"}, 404 );
    }
    
    # unique list and sort it - sort required for proper caching
    my @mgids = sort keys %mgids;
    # validate / parse request options
    my ($params, $metadata, $hierarchy) = $self->process_parameters($master, \@mgids, $type);
    if (exists $params->{'ERROR'}) {
        $self->return_data( {"ERROR" => $params->{'ERROR'}}, 400 );
    }
    
    # check if temp profile compute node is in shock
    my $attr = {
        type   => "temp",
        url_id => $self->url_id,
        owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
        data_type => "matrix"
    };
    # already cashed in shock - say submitted in case its running
    my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
    if ($nodes && (@$nodes > 0)) {
        # sort results by newest to oldest
        my @sorted = sort { $b->{file}{created_on} cmp $a->{file}{created_on} } @$nodes;
        $self->return_data({"status" => "submitted", "id" => $sorted[0]->{id}, "url" => $self->url."/status/".$sorted[0]->{id}});
    }
    
    # test cassandra access
    my $ctest = $self->cassandra_test("job");
    unless ($ctest) {
        $self->return_data( {"ERROR" => "unable to connect to metagenomics analysis database"}, 500 );
    }
    
    # need to create new temp node
    $attr->{parameters} = $params;
    $attr->{progress}   = {};
    foreach my $j (@{$params->{job_ids}}) {
        $attr->{progress}{$j} = {queried => 0, found => 0, completed => 0};
    }
    my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "7D");
    
    # asynchronous call, fork the process and return the process id.
    my $pid = fork();
    # child - get data and dump it
    if ($pid == 0) {
        close STDERR;
        close STDOUT;
        $self->create_matrix($node, $params, $metadata, $hierarchy);
        exit 0;
    }
    # parent - end html session
    else {
        $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->url."/status/".$node->{id}});
    }
}

# validate / reformat the data into the request paramaters
sub process_parameters {
    my ($self, $master, $data, $type) = @_;
    my $default_prot_source = 'RefSeq';
    my $default_rna_source = 'RDP';
    my $default_ont_source = 'Subsystems';
    
    # get optional params
    my $cgi = $self->cgi;
    my $grep   = $cgi->param('grep') || undef;
    my $source = $cgi->param('source');
    my $rtype  = $cgi->param('result_type') ? $cgi->param('result_type') : 'abundance';
    my $htype  = $cgi->param('hit_type') ? $cgi->param('hit_type') : 'all';
    my $glvl   = $cgi->param('group_level') ? $cgi->param('group_level') : (($type eq 'organism') ? 'strain' : 'function');
    my $eval   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    my $ident  = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    my $alen   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
    my $flvl   = $cgi->param('filter_level') ? $cgi->param('filter_level') : (($type eq 'organism') ? 'function' : 'strain');
    my $fsrc   = $cgi->param('filter_source') ? $cgi->param('filter_source') : (($type eq 'organism') ? $default_ont_source : $default_prot_source);
    my $filter = $cgi->param('filter') ? $cgi->param('filter') : "";
    my $hide_md = $cgi->param('hide_metadata') ? 1 : 0;
    my $hide_hy = $cgi->param('hide_hierarchy') ? 1 : 0;
    my $version = $cgi->param('version') || $self->{m5nr_default};
    my $leaf_node = 0;
    my $prot_func = 0;
    my $leaf_filter = 0;
    my $group_level = $glvl;
    my $filter_level = $flvl;
    
    # controlled vocabulary set
    my $result_map = {abundance => 'abundance', evalue => 'exp_avg', length => 'len_avg', identity => 'ident_avg'};
    my %prot_srcs  = map { $_->[0], 1 } @{$self->source->{protein}};
    my %rna_srcs   = map { $_->[0], 1 } @{$self->source->{rna}};
    my %func_srcs  = map { $_->[0], 1 } @{$self->{sources}{ontology}};
    my %org_srcs   = map { $_->[0], 1 } @{$self->{sources}{organism}};
    my @tax_hier   = map { $_->[0] } reverse @{$self->hierarchy->{organism}};
    my @ont_hier   = map { $_->[0] } reverse @{$self->hierarchy->{ontology}};
    
    # id mapping / validation
    my @job_ids = ();
    my @mg_ids  = ();
    my $id_map  = $master->Job->get_job_ids($data);
    foreach my $mid (@$data) {
        if (exists $id_map->{$mid}) {
            push @job_ids, $id_map->{$mid};
            push @mg_ids, 'mgm'.$mid;
        } else {
            return ({"ERROR" => "invalid id: mgm".$mid}, undef, undef);
        }
    }
    
    # validate metagenome type combinations
    # invalid - amplicon with: non-amplicon function, protein datasource, filtering 
    my $num_rna  = 0;
    my $num_gene = 0;
    my $type_map = $master->Job->get_sequence_types($data);
    map { $num_rna += 1 } grep { $_ eq 'Amplicon' } values %$type_map;
    map { $num_gene += 1 } grep { $_ eq 'Metabarcode' } values %$type_map;
    if ($num_rna) {
        unless ($source) {
            $source = $default_rna_source;
        }
        if ($num_rna != scalar(@$data)) {
            return ({"ERROR" => "invalid combination: mixing Amplicon with Metagenome and/or Metatranscriptome. $num_rna of ".scalar(@$data)." are Amplicon"}, undef, undef);
        }
        if ($type eq 'function') {
            return ({"ERROR" => "invalid combination: requesting functional annotations with Amplicon data sets"}, undef, undef);
        }
        if (exists $prot_srcs{$source}) {
            return ({"ERROR" => "invalid combination: requesting protein source annotations with Amplicon data sets"}, undef, undef);
        }
        if ($filter) {
            return ({"ERROR" => "invalid combination: filtering by functional annotations with Amplicon data sets"}, undef, undef);
        }
    }
    if ($num_gene) {
        unless ($source) {
            $source = $default_prot_source;
        }
        if ($type eq 'function') {
            return ({"ERROR" => "invalid combination: requesting functional annotations with Metabarcode data sets"}, undef, undef);
        }
        if (exists $rna_srcs{$source}) {
            return ({"ERROR" => "invalid combination: requesting RNA source annotations with Metabarcode data sets"}, undef, undef);
        }
        if ($filter) {
            return ({"ERROR" => "invalid combination: filtering by functional annotations with Metabarcode data sets"}, undef, undef);
        }
    }
    unless ($source) {
        $source = ($type eq 'organism') ? $default_prot_source : $default_ont_source;
    }
    
    my $matrix_id  = join("_", map {'mgm'.$_} @$data).'_'.join("_", ($type, $glvl, $source, $htype, $rtype, $eval, $ident, $alen));
    my $matrix_url = $self->url.'/matrix/'.$type.'?id='.join('&id=', map {'mgm'.$_} @$data).'&group_level='.$glvl.'&source='.$source.
                     '&hit_type='.$htype.'&result_type='.$rtype.'&evalue='.$eval.'&identity='.$ident.'&length='.$alen;
    if ($hide_md) {
        $matrix_id .= '_'.$hide_md;
        $matrix_url .= '&hide_metadata='.$hide_md;
    }
    if ($hide_hy) {
        $matrix_id .= '_'.$hide_hy;
        $matrix_url .= '&hide_hierarchy='.$hide_hy;
    }
    if ($filter) {
        $matrix_id .= md5_hex($filter)."_".$fsrc."_".$flvl;
        $matrix_url .= '&filter='.uri_escape($filter).'&filter_source='.$fsrc.'&filter_level='.$flvl;
    }
    if ($grep) {
        $matrix_id .= '_'.$grep;
        $matrix_url .= '&grep='.$grep;
    }
    
    # validate cutoffs
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? int($eval)  : undef;
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? int($ident) : undef;
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? int($alen)  : undef;
    if (defined($eval) && ($eval < 1)) {
        return ({"ERROR" => "invalid evalue for matrix call, must be integer greater than 1"}, undef, undef);
    }
    if (defined($ident) && (($ident < 0) || ($ident > 100))) {
        return ({"ERROR" => "invalid identity for matrix call, must be integer between 0 and 100"}, undef, undef);
    }
    if (defined($alen) && ($alen < 1)) {
        return ({"ERROR" => "invalid length for matrix call, must be integer greater than 1"}, undef, undef);
    }
    
    # validate controlled vocabulary params
    unless (exists $result_map->{$rtype}) {
        return ({"ERROR" => "invalid result_type for matrix call: ".$rtype." - valid types are [".join(", ", keys %$result_map)."]"}, undef, undef);
    }
    if ($type eq 'organism') {
        if ( any {$_ eq $glvl} @tax_hier ) {
            if ($glvl eq 'strain') {
                $leaf_node = 1;
            }
        } else {
            return ({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @tax_hier)."]"}, undef, undef);
        }
        if ( any {$_ eq $flvl} @ont_hier ) {
            if ($flvl eq 'function') {
                $flvl = ($fsrc =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
            if (($flvl eq 'level4') || (($fsrc =~ /^[NC]OG$/) && ($flvl eq 'level3'))) {
                $leaf_filter = 1;
            }
        } else {
            return ({"ERROR" => "invalid filter_level for matrix call of type ".$type.": ".$filter_level." - valid types are [".join(", ", @ont_hier)."]"}, undef, undef);
        }
        unless (exists $org_srcs{$source}) {
            return ({"ERROR" => "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %org_srcs)."]"}, undef, undef);
        }
        unless (exists $func_srcs{$fsrc}) {
            return ({"ERROR" => "invalid filter_source for matrix call of type ".$type.": ".$fsrc." - valid types are [".join(", ", keys %func_srcs)."]"}, undef, undef);
        }
    } elsif ($type eq 'function') {
        $htype = 'all';
        if ( exists $prot_srcs{$source} ) {
            $group_level = 'function';
            $glvl = 'function';
            $leaf_node = 1;
            $prot_func = 1;
        } elsif ( any {$_ eq $glvl} @ont_hier ) {
            if ($glvl eq 'function') {
                $glvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
            if (($glvl eq 'level4') || (($source =~ /^[NC]OG$/) && ($glvl eq 'level3'))) {
                $leaf_node = 1;
            }
        } else {
            return ({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @ont_hier)."]"}, undef, undef);
        }
        if ( any {$_ eq $flvl} @tax_hier ) {
            if ($flvl eq 'strain') {
                $leaf_filter = 1;
            }
        } else {
            return ({"ERROR" => "invalid filter_level for matrix call of type ".$type.": ".$filter_level." - valid types are [".join(", ", @tax_hier)."]"}, undef, undef);
        }
        unless (exists($func_srcs{$source}) || exists($prot_srcs{$source})) {
            return ({"ERROR" => "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %func_srcs)."]"}, undef, undef);
        }
        unless (exists $org_srcs{$fsrc}) {
            return ({"ERROR" => "invalid filter_source for matrix call of type ".$type.": ".$fsrc." - valid types are [".join(", ", keys %org_srcs)."]"}, undef, undef);
        }
    } else {
        return ({"ERROR" => "invalid resource type was entered ($type)."}, undef, undef);
    }
    
    # reset type
    if (exists($func_srcs{$source}) && ($type eq "function")) {
        $type = "ontology";
    }
    
    # row hierarchies
    my $hierarchy = [];
    my ($hmatch, $fields, $squery);
    if ($type eq "organism") {
        if ($leaf_node) {
            $hmatch = "organism";
            pop @tax_hier;
            $fields = [ @tax_hier, 'ncbi_tax_id', 'organism' ];
        } else {
            $hmatch = $glvl;
            foreach my $h (@tax_hier) {
                push @$fields, $h;
                if ($h eq $glvl) {
                    last;
                }
            }
        }
        $squery = 'object%3Ataxonomy';
    } elsif ($type eq 'ontology') {
        if ($leaf_node) {
            $hmatch = "accession";
            pop @ont_hier;
            $fields = [ @ont_hier, 'level4', 'accession' ];
        } else {
            $hmatch = $glvl;
            foreach my $h (@ont_hier) {
                push @$fields, $h;
                if ($h eq $glvl) {
                    last;
                }
            }
        }
        $squery = 'object%3Aontology+AND+source%3A'.$source;
    }
    if ($squery && (! $hide_hy)) {
        # get hierarchy from m5nr solr
        if ($leaf_node) {
            ($hierarchy, undef) = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $squery, undef, 0, 1000000, $fields);
        } else {
            $squery .= '&group=true&group.field='.$glvl;
            my $result = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $squery, undef, 0, 1000000, $fields);
            foreach my $group (@{$result->{$glvl}{groups}}) {
                push @$hierarchy, $group->{doclist}{docs}[0];
            }
        }
    }
    
    # column metadata
    my $metadata = {};
    if (! $hide_md) {
        my $mddb = MGRAST::Metadata->new();
        $metadata = $mddb->get_jobs_metadata_fast($data, 1);
    }
    
    # done
    my $params = {
        id          => $matrix_id,
        url         => $matrix_url,
        mg_ids      => \@mg_ids,
        job_ids     => \@job_ids,
        swaps       => $self->to_swap_set($data), # data is mg_ids w/o prefix
        resource    => "matrix",
        type        => $type,
        group_level => $glvl,
        source      => $source,
        source_type => $self->type_by_source($source),
        result_type => $rtype,
        hit_type    => $htype,
        evalue      => $eval,
        identity    => $ident,
        length      => $alen,
        version     => $version,
        hier_match  => $hmatch,
        filter      => $filter,
        filter_level  => $flvl,
        filter_source => $fsrc,
        leaf_node     => $leaf_node,
        leaf_filter   => $leaf_filter
    };
    return ($params, $metadata, $hierarchy);
}

sub create_matrix {
    my ($self, $node, $params, $metadata, $hierarchy) = @_;
    
    # cassandra handle
    my $mgcass = $self->cassandra_matrix($params->{version});
    
    # set shock
    my $token = $self->mgrast_token;
    $mgcass->set_shock($token);
    
    ### create matrix / saves output file or error message in shock
    $mgcass->compute_matrix($node, $params, $metadata, $hierarchy);
    $mgcass->close();
    return undef;
}

1;
