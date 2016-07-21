package resources::matrix;

use strict;
use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use MGRAST::Metadata;
use MGRAST::Abundance;
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
        'url' => $self->cgi->url."/".$self->name,
        'description' => "A profile in biom format that contains abundance counts",
        'type' => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests' => [
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
            { 'name'        => "organism",
              'request'     => $self->cgi->url."/".$self->name."/organism",
              'description' => "Returns a BIOM object.",
              'example'     => [ $self->cgi->url."/".$self->name."/organism?id=mgm4447943.3&id=mgm4447192.3&id=mgm4447102.3&group_level=family&source=RefSeq&evalue=15",
                                 'retrieve abundance matrix of RefSeq organism annotations at family taxa for listed metagenomes at evalue < e-15' ],
              'method'      => "GET" ,
              'type'        => "synchronous or asynchronous" ,  
              'attributes'  => $self->{attributes},
              'parameters'  => {
                  'options'  => {
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
                      'id' => [ 'string', 'one or more metagenome or project unique identifier' ],
                      'hide_metadata' => [ 'boolean', "if true do not return metagenome metadata in 'columns' object, default is false" ],
                      'version' => [ 'int', 'M5NR version, default '.$self->{m5nr_default} ],
                      'asynchronous' => [ 'boolean', "if true return process id to query status resource for results, default is false" ] },
                  'required' => {},
                  'body'     => {} }
            },
            { 'name'        => "function",
              'request'     => $self->cgi->url."/".$self->name."/function",
              'description' => "Returns a BIOM object.",
              'example'     => [ $self->cgi->url."/".$self->name."/function?id=mgm4447943.3&id=mgm4447192.3&id=mgm4447102.3&group_level=level3&source=Subsystems&identity=80",
                                 'retrieve abundance matrix of Subsystem annotations at level3 for listed metagenomes at % identity > 80' ],
              'method'      => "GET" ,
              'type'        => "synchronous or asynchronous" ,  
              'attributes'  => $self->{attributes},
              'parameters'  => {
                  'options'  => {
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
                      'id' => [ 'string', 'one or more metagenome or project unique identifier' ],
                      'hide_metadata' => [ 'boolean', "if true do not return metagenome metadata in 'columns' object, default is false" ],
                      'version' => [ 'int', 'M5NR version, default '.$self->{m5nr_default} ],
                      'asynchronous' => [ 'boolean', "if true return process id to query status resource for results, default is false" ] },
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
    foreach my $id (@ids) {
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
            $self->return_data( {"ERROR" => "unknown id in matrix call: ".$id}, 404 );
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
    
    # asynchronous call, fork the process and return the process id.
    # caching is done with shock, not memcache
    if ($self->cgi->param('asynchronous')) {
        my $attr = {
            type => "temp",
            url_id => $self->url_id,
            owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
            data_type => "matrix"
        };
        # already cashed in shock - say submitted in case its running
        my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
        if ($nodes && (@$nodes > 0)) {
            # sort results by newest to oldest
            my @sorted = sort { $b->{file}{created_on} cmp $a->{file}{created_on} } @$nodes;
            $self->return_data({"status" => "submitted", "id" => $sorted[0]->{id}, "url" => $self->cgi->url."/status/".$sorted[0]->{id}});
        }
        # need to create new node and fork
        my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "7D");
        my $pid = fork();
        # child - get data and dump it
        if ($pid == 0) {
            close STDERR;
            close STDOUT;
            my ($data, $error) = $self->prepare_data(\@mgids, $type);
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
        my ($data, $error) = $self->prepare_data(\@mgids, $type);
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
    my ($self, $data, $type) = @_;
    
    # get optional params
    my $cgi = $self->cgi;
    my $grep   = $cgi->param('grep') || undef;
    my $source = $cgi->param('source') ? $cgi->param('source') : (($type eq 'organism') ? 'RefSeq' : 'Subsystems');
    my $rtype  = $cgi->param('result_type') ? $cgi->param('result_type') : 'abundance';
    my $htype  = $cgi->param('hit_type') ? $cgi->param('hit_type') : 'all';
    my $glvl   = $cgi->param('group_level') ? $cgi->param('group_level') : (($type eq 'organism') ? 'strain' : 'function');
    my $eval   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    my $ident  = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    my $alen   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
    my $flvl   = $cgi->param('filter_level') ? $cgi->param('filter_level') : (($type eq 'organism') ? 'function' : 'strain');
    my $fsrc   = $cgi->param('filter_source') ? $cgi->param('filter_source') : (($type eq 'organism') ? 'Subsystems' : 'RefSeq');
    my $filter = $cgi->param('filter') ? $cgi->param('filter') : "";
    my $hide_md = $cgi->param('hide_metadata') ? 1 : 0;
    my $hide_an = $cgi->param('hide_annotation') ? 1 : 0;
    my $version = $cgi->param('version') || $self->{m5nr_default};
    my $leaf_node = 0;
    my $prot_func = 0;
    my $leaf_filter = 0;
    my $group_level = $glvl;
    my $filter_level = $flvl;
   
    my $matrix_id  = join("_", map {'mgm'.$_} sort @$data).'_'.join("_", ($type, $glvl, $source, $htype, $rtype, $eval, $ident, $alen));
    my $matrix_url = $self->cgi->url.'/matrix/'.$type.'?id='.join('&id=', map {'mgm'.$_} sort @$data).'&group_level='.$glvl.'&source='.$source.
                     '&hit_type='.$htype.'&result_type='.$rtype.'&evalue='.$eval.'&identity='.$ident.'&length='.$alen;
    if ($hide_md) {
        $matrix_id .= '_'.$hide_md;
        $matrix_url .= '&hide_metadata='.$hide_md;
    }
    if ($hide_an) {
        $matrix_id .= '_'.$hide_an;
        $matrix_url .= '&hide_annotation='.$hide_an;
    }
    if ($filter) {
        $matrix_id .= md5_hex($filter)."_".$fsrc."_".$flvl;
        $matrix_url .= '&filter='.uri_escape($filter).'&filter_source='.$fsrc.'&filter_level='.$flvl;
    }
    if ($grep) {
        $matrix_id .= '_'.$grep;
        $matrix_url .= '&grep='.$grep;
    }

    # initialize analysis obj with mgids
    unless (exists $self->{m5nr_version}{$version}) {
        $self->return_data({"ERROR" => "invalid version was entered ($version). Please use one of: ".join(", ", keys %{$self->{m5nr_version}})}, 404);
    }
    my $master = $self->connect_to_datasource();
    my $chdl   = $self->cassandra_m5nr_handle("m5nr_v".$version, $Conf::cassandra_m5nr);
    my $mgdb   = MGRAST::Abundance->new($chdl, $version);
    unless (ref($mgdb)) {
        return ({"ERROR" => "could not connect to analysis database"}, 500);
    }

    # validate cutoffs
    if (int($eval) < 1) {
        return ({"ERROR" => "invalid evalue for matrix call, must be integer greater than 1"}, 404);
    }
    if ((int($ident) < 0) || (int($ident) > 100)) {
        return ({"ERROR" => "invalid identity for matrix call, must be integer between 0 and 100"}, 404);
    }
    if (int($alen) < 1) {
        return ({"ERROR" => "invalid length for matrix call, must be integer greater than 1"}, 404);
    }

    # controlled vocabulary set
    my $result_map = {abundance => 'abundance', evalue => 'exp_avg', length => 'len_avg', identity => 'ident_avg'};
    my %prot_srcs  = map { $_->[0], 1 } @{$self->source->{protein}};
    my %func_srcs  = map { $_->[0], 1 } @{$self->{sources}{ontology}};
    my %org_srcs   = map { $_->[0], 1 } @{$self->{sources}{organism}};
    my @tax_hier   = map { $_->[0] } @{$self->hierarchy->{organism}};
    my @ont_hier   = map { $_->[0] } @{$self->hierarchy->{ontology}};
                             
    # validate controlled vocabulary params
    unless (exists $result_map->{$rtype}) {
        return ({"ERROR" => "invalid result_type for matrix call: ".$rtype." - valid types are [".join(", ", keys %$result_map)."]"}, 404);
    }
    if ($type eq 'organism') {
        if ( any {$_ eq $glvl} @tax_hier ) {
            if ($glvl eq 'strain') {
                $leaf_node = 1;
            }
        } else {
            return ({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @tax_hier)."]"}, 404);
        }
        if ( any {$_ eq $flvl} @ont_hier ) {
            if ($flvl eq 'function') {
                $flvl = ($fsrc =~ /^[NC]OG$/) ? 'level3' : 'level4';
            }
            if (($flvl eq 'level4') || (($fsrc =~ /^[NC]OG$/) && ($flvl eq 'level3'))) {
                $leaf_filter = 1;
            }
        } else {
            return ({"ERROR" => "invalid filter_level for matrix call of type ".$type.": ".$filter_level." - valid types are [".join(", ", @ont_hier)."]"}, 404);
        }
        unless (exists $org_srcs{$source}) {
            return ({"ERROR" => "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %org_srcs)."]"}, 404);
        }
        unless (exists $func_srcs{$fsrc}) {
            return ({"ERROR" => "invalid filter_source for matrix call of type ".$type.": ".$fsrc." - valid types are [".join(", ", keys %func_srcs)."]"}, 404);
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
            return ({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @ont_hier)."]"}, 404);
        }
        if ( any {$_ eq $flvl} @tax_hier ) {
            if ($flvl eq 'strain') {
                $leaf_filter = 1;
            }
        } else {
            return ({"ERROR" => "invalid filter_level for matrix call of type ".$type.": ".$filter_level." - valid types are [".join(", ", @tax_hier)."]"}, 404);
        }
        unless (exists($func_srcs{$source}) || exists($prot_srcs{$source})) {
            return ({"ERROR" => "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %func_srcs)."]"}, 404);
        }
        unless (exists $org_srcs{$fsrc}) {
            return ({"ERROR" => "invalid filter_source for matrix call of type ".$type.": ".$fsrc." - valid types are [".join(", ", keys %org_srcs)."]"}, 404);
        }
    } else {
        return ({"ERROR" => "invalid resource type was entered ($type)."}, 404);
    }

    # validate metagenome type combinations
    # invalid - amplicon with: non-amplicon function, protein datasource, filtering 
    my $num_amp = 0;
    my $type_map = $master->Job->get_sequence_types($data);
    map { $num_amp += 1 } grep { $_ eq 'Amplicon' } values %$type_map;
    if ($num_amp) {
        if ($num_amp != scalar(@$data)) {
            return ({"ERROR" => "invalid combination: mixing Amplicon with Metagenome and/or Metatranscriptome. $num_amp of ".scalar(@$data)." are Amplicon"}, 400);
        }
        if ($type eq 'function') {
            return ({"ERROR" => "invalid combination: requesting functional annotations with Amplicon data sets"}, 400);
        }
        if (exists $prot_srcs{$source}) {
            return ({"ERROR" => "invalid combination: requesting protein source annotations with Amplicon data sets"}, 400);
        }
        if ($filter) {
            return ({"ERROR" => "invalid combination: filtering by functional annotations with Amplicon data sets"}, 400);
        }
    }
    
    # set matrix
    @$data = sort @$data;
    my $mddb = MGRAST::Metadata->new();
    my $meta = $hide_md ? {} : $mddb->get_jobs_metadata_fast($data, 1);
    my $columns = [ map { {id => $_, metadata => exists($meta->{$_}) ? $meta->{$_} : undef} } @$data ];
    my $matrix  = {
        id                   => $matrix_id,
        url                  => $matrix_url,
        format               => "Biological Observation Matrix 1.0",
        format_url           => "http://biom-format.org",
        type                 => ($type eq 'organism') ? "Taxon table" : "Function table",
        generated_by         => "MG-RAST".($Conf::server_version ? " revision ".$Conf::server_version : ""),
        date                 => strftime("%Y-%m-%dT%H:%M:%S", localtime),
        matrix_type          => "dense",
        matrix_element_type  => ($rtype eq 'abundance') ? "int" : "float",
        matrix_element_value => $rtype,
        shape                => [ 0, scalar(@$columns) ],
        rows                 => [],
        columns              => $columns,
        data                 => []
    };
    
    # reset type
    if ($prot_func && ($type eq "function")) {
        $type = "ontology";
    }
    
    # get grouping map: leaf_name => group_name
    my $group_map = undef;
    if (! $leaf_node) {
        if ($type eq "organism") {
            if ($htype ne 'lca') {
                $group_map = $chdl->get_org_taxa_map($glvl);
            } else {
                my @levels = reverse @tax_hier;
                $group_map = first { $levels[$_] eq $glvl } 0..$#levels;
            }
        } elsif ($type eq "ontology") {
            $group_map = $chdl->get_ontology_map($source, $glvl);
        }
    }
    
    # get filter list: all leaf names that match filter for given filter_level (organism, ontology only)
    my $filter_list = undef;
    if ($filter && (! $leaf_filter)) {
        if ($type eq "organism") {
            $filter_list = { map { $_, 1 } @{$chdl->get_organism_by_taxa($flvl, $filter)} };
        } elsif ($type eq "ontology") {
            $filter_list = { map { $_, 1 } @{$chdl->get_ontology_by_level($fsrc, $flvl, $filter)} };
        }
    }
    
    # build / start query
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= ".($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
    
    my $id_map = $master->Job->get_job_ids($data);
    my $query = "SELECT job, md5, ".$result_map->{$rtype}." FROM job_md5s";
    $query .= $mgdb->get_where_str([
        'version = '.$mgdb->version,
        'job IN ('.join(',', values %$id_map).')',
        $eval,
        $ident,
        $alen
    ]);
    $query .= " ORDER BY md5";
    my $sth = $mgdb->execute_query($query);
    
    # loop through results and build matrix
    my $mdata   = []; # 2D array
    my $md5_set = {}; # md5 => [[job, value]]
    my $col_idx = { map { $id_map->{$data->[$_]}, $_ } 0..$#$data }; # job_ids with column indexes
    my $row_idx = {}; # row ids with row index
    my $count   = 0;
    while (my @row = $sth->fetchrow_array()) {
        my ($job, $md5, $val) = @row;
        if (exists $md5_set->{$md5}) {
            push @{$md5_set->{$md5}}, [$job, $self->toNum($val, $rtype)];
        } else {
            $md5_set->{$md5} = [[$job, $self->toNum($val, $rtype)]];
        }
        $count++;
        if ($count == $mgdb->chunk) {
            $self->append_matrix($chdl, $type, $rtype, $htype, $source, $md5_set, $mdata, $col_idx, $row_idx, $group_map, $filter_list);
            $md5_set = {};
            $count = 0;
        }
    }
    if ($count > 0) {
        $self->append_matrix($chdl, $type, $rtype, $htype, $source, $md5_set, $mdata, $col_idx, $row_idx, $group_map, $filter_list);
    }
    
    # cleanup
    $mgdb->end_query($sth);
    $mgdb->DESTROY();
    
    # transform [ count, sum ] to single average
    if ($rtype ne 'abundance') {
        foreach my $row (@$mdata) {
            for (my $i=0; $i<@$row; $i++) {
                my ($num, $sum) = @{$row->[$i]};
                if ($num == 0) {
                    $row->[$i] = 0;
                } else {
                    $row->[$i] = round($sum / $num);
                }
            }
        }
    }
    
    # finalize matrix
    $matrix->{rows} = [ map {{id => $_, metadata => undef}} sort {$row_idx->{$a} <=> $row_idx->{$b}} keys %$row_idx ];
    $matrix->{data} = $mdata;
    $matrix->{shape}[0] = scalar(@{$matrix->{rows}});

    # column metadata / hierarchies
    my ($mtype, $fields, $squery);
    if ($type eq "organism") {
        $mtype  = 'taxonomy';
        $fields = [ @tax_hier, 'ncbi_tax_id', 'organism' ];
        $squery = 'object%3Ataxonomy';
        
    } elsif ($type eq 'ontology') {
        $mtype  = 'ontology';
        $fields = [ @ont_hier, 'level4', 'accession' ];
        $squery = 'object%3Aontology+AND+source%3A'.$source;
    }
    if ($squery && (! $hide_md)) {
        # get hierarchy from m5nr solr
        my $hierarchy = [];
        my $match = "";
        if (! $leaf_node) {
            $match = $glvl;
            $squery .= '&group=true&group.field='.$glvl;
            my $result = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $squery, undef, 0, 1000000, $fields);
            foreach my $group (@{$result->{$glvl}{groups}}) {
                push @$hierarchy, $group->{doclist}{docs}[0];
            }
        } else {
            $match = ($type eq "organism") ? 'organism' : 'accession';
            ($hierarchy, undef) = $self->get_solr_query('GET', $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$version, $squery, undef, 0, 1000000, $fields);
        }
        foreach my $r (@{$matrix->{rows}}) {
            foreach my $h (@$hierarchy) {
                if ($r->{id} eq $h->{$match}) {
                    if (exists $h->{organism}) {
                        $h->{strain} = $h->{organism};
                        delete $h->{organism};
                    }
                    if (exists $h->{accession}) {
                        delete $h->{accession};
                    }
                    if (exists $h->{ncbi_tax_id}) {
                        my $tid = $h->{ncbi_tax_id};
                        delete $h->{ncbi_tax_id};
                        $r->{metadata} = { $mtype => $h, ncbi_tax_id => $tid };
                    } else {
                        $r->{metadata} = { $mtype => $h };
                    }
                    last;
                }
            }
        }
    }
                        
    return ($matrix, undef);
}

sub append_matrix {
    my ($self, $chdl, $type, $rtype, $htype, $source, $md5_set, $mdata, $col_idx, $row_idx, $group_map, $filter_list, $filter_src) = @_;
    
    my @md5s = keys %$md5_set;
    my $next = scalar(keys %$row_idx); # incraments
    my $jnum = scalar(keys %$col_idx); # static
    
    # get filter md5s
    if ($filter_list && $filter_src) {
        my $field = ($type eq 'organism') ? 'accession' : 'organism';
        my @filter_md5s = ();
        my $filter_data = $chdl->get_records_by_id(\@md5s, $filter_src);
        foreach my $set (@$filter_data) {
            foreach my $a (@{$set->{$field}}) {
                if (exists $filter_list->{$a}) {
                    push @filter_md5s, $set->{id};
                }
            }
        }
        @md5s = @filter_md5s;
    }
    
    my $cass_data = $chdl->get_records_by_id(\@md5s, $source);
    foreach my $set (@$cass_data) {
        # get annotations based on type & hit_type
        my $annotations = [];
        if ($type eq 'function') {
            $annotations = $set->{function};
        } elsif ($type eq 'ontology') {
            $annotations = $set->{accession};
        } elsif ($type eq 'organism') {
            if ($htype eq 'all') {
                $annotations = $set->{organism};
            } elsif ($htype eq 'single') {
                $annotations = [ $set->{single} ];
            } elsif ($htype eq 'lca') {
                my $taxa = $set->{lca}[$group_map];
                next if ($taxa =~ /^\-/);
                $annotations = [ $taxa ];
            }
        }
        # grouping
        if (defined($group_map) && ($htype ne 'lca')) {
            my %unique = map { $group_map->{$_}, 1 } grep { exists($group_map->{$_}) } @$annotations;
            $annotations = [ keys %unique ];
        }
        
        # loop through annotations for row index
        foreach my $a (@$annotations) {
            my $rindex;
            if (exists $row_idx->{$a}) {
                # alrady saw this annotation
                $rindex = $row_idx->{$a};
            } else {
                # new annotation, add to rows
                $rindex = $next;
                $row_idx->{$a} = $rindex;
                $mdata->[$rindex] = [];
                if ($rtype eq 'abundance') {
                    # populate with zero's
                    map { push @{$mdata->[$rindex]}, 0 } (1..$jnum);
                } else {
                    # populate with tuple of zero's
                    map { push @{$mdata->[$rindex]}, [0, 0] } (1..$jnum);
                }
                $next++;
            }
            # loop through jobs that have md5 - add value
            # curr is int if abundance, tuple otherwise
            foreach my $info (@{$md5_set->{$set->{id}}}) {
                my ($job, $val) = @$info;
                my $curr = $mdata->[$rindex][$col_idx->{$job}];
                $mdata->[$rindex][$col_idx->{$job}] = $self->add_value($curr, $val, $rtype);
            }
        }
    }
}

# sum if abundance, [ count, sum ] if other
sub add_value {
    my ($self, $curr, $val, $type) = @_;
    if ($type eq 'abundance') {
        # return sum
        return $curr + $val;
    } else {
        # return tuple of count, sum
        return [ $curr->[0] + 1, $curr->[1] + $val ];
    }
}

# Round to nearest thousandth
sub round {
    my $val = shift;
    if ($val > 0) {
        return ( int( $val * 1000 + 0.5 ) / 1000 );
    } else {
        return ( int( $val * 1000 - 0.5 ) / 1000 );
    }
}

1;
