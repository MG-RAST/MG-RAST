package resources2::matrix;

use strict;
use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use MGRAST::Metadata;
use MGRAST::Analysis;
use Data::Dumper;
use URI::Escape;
use List::Util qw(max min sum first);
use Digest::MD5 qw(md5_hex md5_base64);
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "matrix";
    $self->{org2tax} = {};
    $self->{cutoffs} = { evalue => '5', identity => '60', length => '15' };
    $self->{hierarchy} = { organism => [ ['strain', 'bottom organism taxanomic level'],
                                         ['species', 'organism type level'],
                                         ['genus', 'organism taxanomic level'],
                                         ['family', 'organism taxanomic level'],
                                         ['order', 'organism taxanomic level'],
                                         ['class', 'organism taxanomic level'],
                                         ['phylum', 'organism taxanomic level'],
                                         ['domain', 'top organism taxanomic level'] ],
                           ontology => [ ['function', 'bottom function ontology level'],
                                         ['level3', 'function ontology level' ],
                                         ['level2', 'function ontology level' ],
                                         ['level1', 'top function ontology level'] ]
                         };
    $self->{sources} = { organism => [ ["M5NR", "comprehensive protein database"],
                                       ["RefSeq", "protein database"],
                                       ["SwissProt", "protein database"],
                                       ["GenBank", "protein database"],
                                       ["IMG", "protein database"],
                                       ["SEED", "protein database"],
                                       ["TrEMBL", "protein database"],
                                       ["PATRIC", "protein database"],
                                       ["KEGG", "protein database"],
                                       ["M5RNA", "comprehensive RNA database"],
                                       ["RDP", "RNA database"],
                                       ["Greengenes", "RNA database"],
                                       ["LSU", "RNA database"],
                                       ["SSU", "RNA database"] ],
                         ontology => [ ["Subsystems", "ontology database, type function only"],
                                       ["NOG", "ontology database, type function only"],
                                       ["COG", "ontology database, type function only"],
                                       ["KO", "ontology database, type function only"] ]
                                     };
    $self->{attributes} = { "id"                   => [ 'string', 'unique object identifier' ],
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
                                                      'type'        => "synchronous or asynchronous" ,  
                                                      'attributes'  => $self->attributes,
                                                      'parameters'  => { 'options'  => { 'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                                                                                         'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                                                                                         'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                                                                                         'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                                                                                                                   ['evalue', 'average e-value exponent of hits in annotation'],
                                                                                                                   ['identity', 'average percent identity of hits in annotation'],
                                                                                                                   ['length', 'average alignment length of hits in annotation']] ],
                                                                                         'hit_type' => [ 'cv', [['all', 'returns results based on all organisms that map to top hit per read-feature'],
                                                                                                                ['single', 'returns results based on a single organism for top hit per read-feature'],
                                                                                                                ['lca', 'returns results based on the Least Common Ancestor for all organisms (M5NR+M5RNA only) that map to hits from a read-feature']] ],
                                                                                         'source' => [ 'cv', $self->{sources}{organism} ],
                                                                                         'group_level' => [ 'cv', $self->{hierarchy}{organism} ],
                                                                                         'filter' => [ 'string', 'filter the return results to only include abundances based on genes with this function' ],
                                                                                         'filter_source' => [ 'cv', $self->{sources}{ontology} ],
                                                                                         'id' => [ 'string', 'one or more metagenome or project unique identifier' ],
                                                                                         'hide_metadata' => [ 'boolean', "if false, return metagenome metadata set in 'columns' object.  default is false." ],
                                                                                         'asynchronous' => [ 'boolean', "if true, return process id to query status resource for results.  default is false." ] },
                                                                         'required' => {},
                                                                         'body'     => {} }
                                                            },
                                                            { 'name'        => "function",
                                                      'request'     => $self->cgi->url."/".$self->name."/function",
                                                      'description' => "Returns a single data object.",
                                                      'method'      => "GET" ,
                                                      'type'        => "synchronous or asynchronous" ,  
                                                      'attributes'  => $self->attributes,
                                                      'parameters'  => { 'options'  => { 'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                                                                                         'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                                                                                         'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                                                                                         'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                                                                                                                   ['evalue', 'average e-value exponent of hits in annotation'],
                                                                                                                   ['identity', 'average percent identity of hits in annotation'],
                                                                                                                   ['length', 'average alignment length of hits in annotation']] ],
                                                                                         'source' => [ 'cv', $self->{sources}{ontology} ],
                                                                                         'group_level' => [ 'cv', $self->{hierarchy}{ontology} ],
                                                                                         'filter' => [ 'string', 'filter the return results to only include abundances based on genes with this organism' ],
                                                                                         'filter_source' => [ 'cv', $self->{sources}{organism} ],
                                                                                         'id' => [ 'string', 'one or more metagenome or project unique identifier' ],
                                                                                         'hide_metadata' => [ 'boolean', "if false return metagenome metadata set in 'columns' object" ],
                                                                                         'asynchronous' => [ 'boolean', "if true, return process id to query status resource for results.  default is false." ] },
                                                                         'required' => {},
                                                                         'body'     => {} }
                                                            },
                                                    { 'name'        => "feature",
                                                      'request'     => $self->cgi->url."/".$self->name."/feature",
                                                      'description' => "Returns a single data object.",
                                                      'method'      => "GET" ,
                                                      'type'        => "synchronous or asynchronous" ,  
                                                      'attributes'  => $self->attributes,
                                                      'parameters'  => { 'options'  => { 'result_type' => [ 'cv', [['abundance', 'number of reads with hits in annotation'],
                                                                                                                   ['evalue', 'average e-value exponent of hits in annotation'],
                                                                                                                   ['identity', 'average percent identity of hits in annotation'],
                                                                                                                   ['length', 'average alignment length of hits in annotation']] ],
                                                                                         'source' => [ 'cv', [["RefSeq", "protein database"],
                                                                                                              ["SwissProt", "protein database"],
                                                                                                              ["GenBank", "protein database"],
                                                                                                              ["IMG", "protein database"],
                                                                                                              ["SEED", "protein database"],
                                                                                                              ["TrEMBL", "protein database"],
                                                                                                              ["PATRIC", "protein database"],
                                                                                                              ["KEGG", "protein database"],
                                                                                                              ["RDP", "RNA database"],
                                                                                                              ["Greengenes", "RNA database"],
                                                                                                              ["LSU", "RNA database"],
                                                                                                              ["SSU", "RNA database"]] ],
                                                                                         'id' => [ "string", "one or more metagenome or project unique identifier" ],
                                                                                         'hide_metadata' => [ 'boolean', "if false return metagenome metadata set in 'columns' object" ],
                                                                                         'asynchronous' => [ 'boolean', "if true, return process id to query status resource for results.  default is false." ] },
                                                                         'required' => {},
                                                                         'body'     => {} } }
                                                  ] };
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (($self->rest->[0] eq 'organism') || ($self->rest->[0] eq 'function') || ($self->rest->[0] eq 'feature')) {
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
    my $mgids = {};
    my $seen  = {};
        
    # get database
    my $master = $self->connect_to_datasource();

    # get user viewable
    my $m_star = ($self->user && $self->user->has_right(undef, 'view', 'metagenome', '*')) ? 1 : 0;
    my $p_star = ($self->user && $self->user->has_right(undef, 'view', 'project', '*')) ? 1 : 0;
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
                    $mgids->{$1} = 1;
            } else {
                $self->return_data( {"ERROR" => "insufficient permissions in matrix call for id: ".$id}, 401 );
            }
        } elsif ($id =~ /^mgp(\d+)$/) {
            if ($p_star || exists($p_rights{$1})) {
                    my $proj = $master->Project->init( {id => $1} );
                    foreach my $mgid (@{ $proj->metagenomes(1) }) {
                        next unless ($m_star || exists($m_rights{$mgid}));
                        $mgids->{$mgid} = 1;
                    }
            } else {
                $self->return_data( {"ERROR" => "insufficient permissions in matrix call for id: ".$id}, 401 );
            }
        } else {
            $self->return_data( {"ERROR" => "unknown id in matrix call: ".$id}, 401 );
        }
        $seen->{$id} = 1;
    }
    if (scalar(keys %$mgids) == 0) {
        $self->return_data( {"ERROR" => "no valid ids submitted and/or found: ".join(", ", @ids)}, 401 );
    }

    # return cached if exists
    $self->return_cached();
    
    # if asynchronous call, fork the process and return the process id.  otherwise, prepare and return data.
    if($self->cgi->param('asynchronous')) {
        my $pid = fork();
        # child - get data and dump it
        if ($pid == 0) {
            my $fname = $Conf::temp.'/'.$$.'.json';
            close STDERR;
            close STDOUT;
            my $data = $self->prepare_data([keys %$mgids], $type);
            open(FILE, ">$fname");
            print FILE $self->json->encode($data);
            close FILE;
            exit 0;
        }
        # parent - end html session
        else {
            my $fname = $Conf::temp.'/'.$pid.'.json';
            $self->return_data({"status" => "Submitted", "id" => $pid, "url" => $self->cgi->url."/status/".$pid});
        }
    } else {
        # prepare data
        my $data = $self->prepare_data([keys %$mgids], $type);
        $self->return_data($data, undef, 1); # cache this!
    }
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data, $type) = @_;
    
    # get optional params
    my $cgi = $self->cgi;
    my $source = $cgi->param('source') ? $cgi->param('source') : (($type eq 'organism') ? 'M5NR' : (($type eq 'function') ? 'Subsystems': 'RefSeq'));
    my $rtype  = $cgi->param('result_type') ? $cgi->param('result_type') : 'abundance';
    my $htype  = $cgi->param('hit_type') ? $cgi->param('hit_type') : 'all';
    my $glvl   = $cgi->param('group_level') ? $cgi->param('group_level') : (($type eq 'organism') ? 'strain' : 'function');
    my $eval   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    my $ident  = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    my $alen   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
    my $fsrc   = $cgi->param('filter_source') ? $cgi->param('filter_source') : (($type eq 'organism') ? 'Subsystems' : 'M5NR');
    my @filter = $cgi->param('filter') ? $cgi->param('filter') : ();
    my $hide_md   = $cgi->param('hide_metadata') ? 1 : 0;
    my $all_srcs  = {};
    my $leaf_node = 0;
    my $group_level = $glvl;
    my $matrix_id  = join("_", map {'mgm'.$_} sort @$data).'_'.join("_", ($type, $glvl, $source, $htype, $rtype, $eval, $ident, $alen));
    my $matrix_url = $self->cgi->url.'/matrix/'.$type.'?id='.join('&id=', map {'mgm'.$_} sort @$data).'&group_level='.$glvl.
                     '&source='.$source.'&hit_type='.$htype.'&result_type='.$rtype.'&evalue='.$eval.'&identity='.$ident.'&length='.$alen;
    if ($hide_md) {
        $matrix_id .= '_'.$hide_md;
        $matrix_url .= '&hide_metadata='.$hide_md;
    }
    if (@filter > 0) {
        $matrix_id .= md5_hex( join("_", sort map { s/\s+/_/g } @filter) )."_".$fsrc;
        $matrix_url .= '&filter='.join('&filter=', sort map { uri_escape($_) } @filter).'&filter_source='.$fsrc;
    }

    # initialize analysis obj with mgids
    my $master = $self->connect_to_datasource();
    my $mgdb   = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
    }
    $mgdb->set_jobs($data);

    # validate cutoffs
    if (int($eval) < 1) {
        $self->return_data({"ERROR" => "invalid evalue for matrix call, must be integer greater than 1"}, 500);
    }
    if ((int($ident) < 0) || (int($ident) > 100)) {
        $self->return_data({"ERROR" => "invalid identity for matrix call, must be integer between 0 and 100"}, 500);
    }
    if (int($alen) < 1) {
        $self->return_data({"ERROR" => "invalid length for matrix call, must be integer greater than 1"}, 500);
    }

    # controlled vocabulary set
    my $result_idx = { abundance => {function => 3, organism => {all => 10, single => 9, lca => 9}, feature => 2},
                       evalue    => {function => 5, organism => {all => 12, single => 10, lca => 10}, feature => 3},
                       length    => {function => 7, organism => {all => 14, single => 12, lca => 12}, feature => 5},
                       identity  => {function => 9, organism => {all => 16, single => 14, lca => 14}, feature => 7}
                     };
    my $result_map = {abundance => 'abundance', evalue => 'exp_avg', length => 'len_avg', identity => 'ident_avg'};
    my @func_hier  = map { $_->[0] } @{$self->{hierarchy}{ontology}};
    my @org_hier   = map { $_->[0] } @{$self->{hierarchy}{organism}};
    my $type_set   = ["function", "organism", "feature"];
                             
    # validate controlled vocabulary params
    unless (exists $result_map->{$rtype}) {
        $self->return_data({"ERROR" => "invalid result_type for matrix call: ".$rtype." - valid types are [".join(", ", keys %$result_map)."]"}, 500);
    }
    if ($type eq 'organism') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
        if ( grep(/^$glvl$/, @org_hier) ) {
            $glvl = 'tax_'.$glvl;
            if ($glvl eq 'tax_strain') {
                      $glvl = 'name';
                      $leaf_node = 1;
            }
        } else {
            $self->return_data({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @org_hier)."]"}, 500);
        }
    } elsif ($type eq 'function') {
        map { $all_srcs->{$_->[0]} = 1 } grep { $_->[0] !~ /^GO/ } @{$mgdb->sources_for_type('ontology')};
        if ( grep(/^$glvl$/, @func_hier) ) {
            if ($glvl eq 'function') {
                      $glvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
                      $leaf_node = 1;
            }
            if ( ($source =~ /^[NC]OG$/) && ($glvl eq 'level3') ) {
                      $leaf_node = 1;
            }
        } else {
            $self->return_data({"ERROR" => "invalid group_level for matrix call of type ".$type.": ".$group_level." - valid types are [".join(", ", @func_hier)."]"}, 500);
        }
    } elsif ($type eq 'feature') {
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
        map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
        delete $all_srcs->{M5NR};
        delete $all_srcs->{M5RNA};
    }
    unless (exists $all_srcs->{$source}) {
        $self->return_data({"ERROR" => "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %$all_srcs)."]"}, 500);
    }

    # get data
    my $md52id  = {};
    my $ttype   = '';
    my $mtype   = '';
    my $matrix  = []; # [ row <annotation>, col <mgid>, value ]
    my $col_idx = $result_idx->{$rtype}{$type};
    my $umd5s   = [];

    if ($type eq 'organism') {
        $ttype = 'Taxon';
        $mtype = 'taxonomy';
        $col_idx = $result_idx->{$rtype}{$type}{$htype};
        if (@filter > 0) {
            $umd5s = $mgdb->get_md5s_for_ontology(\@filter, $fsrc);
        }
        unless ((@filter > 0) && (@$umd5s == 0)) {
            if ($htype eq 'all') {
                if ($leaf_node) {
                    # my ($self, $md5s, $sources, $eval, $ident, $alen, $with_taxid) = @_;
                    my (undef, $info) = $mgdb->get_organisms_for_md5s($umd5s, [$source], int($eval), int($ident), int($alen));
                    # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
                    @$matrix = map {[ $_->[9], $_->[0], $self->toNum($_->[$col_idx], $rtype) ]} grep {$_->[9] !~ /^(\-|unclassified)/} @$info;
                    map { $self->{org2tax}->{$_->[9]} = [ @$_[2..9] ] } @$info;
                } else {
                    # my ($self, $level, $names, $srcs, $value, $md5s, $eval, $ident, $alen) = @_;
                    @$matrix = map {[ $_->[1], $_->[0], $self->toNum($_->[2], $rtype) ]} grep {$_->[1] !~ /^(\-|unclassified)/} @{$mgdb->get_abundance_for_tax_level($glvl, undef, [$source], $result_map->{$rtype}, $umd5s, int($eval), int($ident), int($alen))};
                    # mgid, hier_annotation, value
                }
            } elsif ($htype eq 'single') {
                # my ($self, $source, $eval, $ident, $alen) = @_;
                my $info = $mgdb->get_organisms_unique_for_source($source, int($eval), int($ident), int($alen));
                # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
                my @levels  = reverse @org_hier;
                my $lvl_idx = first { $levels[$_] eq $group_level } 0..$#levels;
                $lvl_idx += 1;
                my $merged = {};
                foreach my $set (@$info) {
                    next if ($set->[$lvl_idx] =~ /^(\-|unclassified)/);
                    if (! exists($merged->{$set->[0]}{$set->[$lvl_idx]})) {
                        $merged->{$set->[0]}{$set->[$lvl_idx]} = [ $self->toNum($set->[$col_idx], $rtype), 1 ];
                    } else {
                        $merged->{$set->[0]}{$set->[$lvl_idx]}[0] += $self->toNum($set->[$col_idx], $rtype);
                        $merged->{$set->[0]}{$set->[$lvl_idx]}[1] += 1;
                    }
                }
                foreach my $m (keys %$merged) {
                    foreach my $a (keys %{$merged->{$m}}) {
                        my $val = ($rtype eq 'abundance') ? $merged->{$m}{$a}[0] : $merged->{$m}{$a}[0] / $merged->{$m}{$a}[1];
                        push @$matrix, [ $a, $m, $val ];
                    }
                }
            } elsif ($htype eq 'lca') {
                # my ($self, $eval, $ident, $alen) = @_;
                my $info = $mgdb->get_lca_data(int($eval), int($ident), int($alen));
                # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
                my @levels  = reverse @org_hier;
                my $lvl_idx = first { $levels[$_] eq $group_level } 0..$#levels;
                $lvl_idx += 1;
                my $merged = {};
                foreach my $set (@$info) {
                    next if ($set->[$lvl_idx] =~ /^(\-|unclassified)/);
                    if (! exists($merged->{$set->[0]}{$set->[$lvl_idx]})) {
                        $merged->{$set->[0]}{$set->[$lvl_idx]} = [ $self->toNum($set->[$col_idx], $rtype), 1 ];
                    } else {
                        $merged->{$set->[0]}{$set->[$lvl_idx]}[0] += $self->toNum($set->[$col_idx], $rtype);
                        $merged->{$set->[0]}{$set->[$lvl_idx]}[1] += 1;
                    }
                }
                foreach my $m (keys %$merged) {
                    foreach my $a (keys %{$merged->{$m}}) {
                        my $val = ($rtype eq 'abundance') ? $merged->{$m}{$a}[0] : $merged->{$m}{$a}[0] / $merged->{$m}{$a}[1];
                        push @$matrix, [ $a, $m, $val ];
                    }
                }
            } else {
                $self->return_data({"ERROR" => "invalid hit_type for matrix call: ".$htype." - valid types are ['all', 'single', 'lca']"}, 500);
            }
        }
    } elsif ($type eq 'function') {
        $ttype = 'Function';
        $mtype = 'ontology';
        if (@filter > 0) {
            $umd5s = $mgdb->get_md5s_for_organism(\@filter, $fsrc);
        }
        unless ((@filter > 0) && (@$umd5s == 0)) {
            if ($leaf_node) {
                # my ($self, $md5s, $source, $eval, $ident, $alen) = @_;
                my (undef, $info) = $mgdb->get_ontology_for_md5s($umd5s, $source, int($eval), int($ident), int($alen));
                # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
                @$matrix = map {[ $_->[1], $_->[0], $self->toNum($_->[$col_idx], $rtype) ]} @$info;
            } else {
                # my ($self, $level, $names, $src, $value, $md5s, $eval, $ident, $alen) = @_;
                @$matrix = map {[ $_->[1], $_->[0], $self->toNum($_->[2], $rtype) ]} @{$mgdb->get_abundance_for_ontol_level($glvl, undef, $source, $result_map->{$rtype}, $umd5s, int($eval), int($ident), int($alen))};
                # mgid, hier_annotation, value
            }
        }
    } elsif ($type eq 'feature') {
        $ttype = 'Gene';
        $mtype = $source.' ID';
        # my ($self, $md5s, $eval, $ident, $alen, $ignore_sk, $rep_org_src) = @_;
        my $info = $mgdb->get_md5_data(undef, int($eval), int($ident), int($alen), 1);
        # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
        my %md5s = map { $_->[1], 1 } @$info;
        my $mmap = $mgdb->decode_annotation('md5', [keys %md5s]);
        map { push @{$md52id->{ $mmap->{$_->[1]} }}, $_->[0] } @{ $mgdb->annotation_for_md5s([keys %md5s], [$source]) };
        @$matrix = map {[ $_->[1], $_->[0], $self->toNum($_->[$col_idx], $rtype) ]} grep {exists $md52id->{$_->[1]}} @$info;
    }

    @$matrix = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @$matrix;
    my $row_ids = $self->sorted_hash($matrix, 0);
    my $col_ids = $self->sorted_hash($matrix, 1);

    # produce output
    my $brows = [];
    my $bcols = [];
    my $r_map = ($type eq 'feature') ? $md52id : $self->get_hierarchy($mgdb, $type, $glvl, $source, $leaf_node);
    foreach my $rid (sort {$row_ids->{$a} <=> $row_ids->{$b}} keys %$row_ids) {
        my $rmd = exists($r_map->{$rid}) ? { $mtype => $r_map->{$rid} } : undef;
        push @$brows, { id => $rid, metadata => $rmd };
    }
    my $mddb = MGRAST::Metadata->new();
    my $meta = $hide_md ? {} : $mddb->get_jobs_metadata_fast($data, 1);
    my $name = $mgdb->_name_map();
    foreach my $cid (sort {$col_ids->{$a} <=> $col_ids->{$b}} keys %$col_ids) {
        my $cmd = exists($meta->{$cid}) ? $meta->{$cid} : undef;
        my $cnm = exists($name->{$cid}) ? $name->{$cid} : undef;
        push @$bcols, { id => 'mgm'.$cid, name => $cnm, metadata => $cmd };
    }
    
    my $obj = { "id"                   => $matrix_id,
                "url"                  => $matrix_url,
                "format"               => "Biological Observation Matrix 1.0",
                "format_url"           => "http://biom-format.org",
                "type"                 => $ttype." table",
                "generated_by"         => "MG-RAST revision ".$Conf::server_version,
                "date"                 => strftime("%Y-%m-%dT%H:%M:%S", localtime),
                "matrix_type"          => "sparse",
                "matrix_element_type"  => ($rtype eq 'abundance') ? "int" : "float",
                "matrix_element_value" => $rtype,
                "shape"                => [ scalar(keys %$row_ids), scalar(keys %$col_ids) ],
                "rows"                 => $brows,
                "columns"              => $bcols,
                "data"                 => $self->index_sparse_matrix($matrix, $row_ids, $col_ids)
              };
                        
    return $obj;
}

sub get_hierarchy {
    my ($self, $mgdb, $type, $level, $src, $leaf_node) = @_;
    if ($type eq 'organism') {
        return $leaf_node ? $self->{org2tax} : $mgdb->get_hierarchy('organism', undef, undef, undef, $level);
    } elsif ($type eq 'function') {
        return $leaf_node ? $mgdb->get_hierarchy('ontology', $src) : $mgdb->get_hierarchy('ontology', $src, undef, undef, $level);
    } else {
        return {};
    }
}

sub index_sparse_matrix {
    my ($self, $matrix, $rows, $cols) = @_;
    my $sparse = [];
    foreach my $pos (@$matrix) {
        my ($r, $c, $v) = @$pos;
        push @$sparse, [ $rows->{$r}, $cols->{$c}, $v ];
    }
    return $sparse;
}

sub sorted_hash {
    my ($self, $array, $idx) = @_;
    my $pos = 0;
    my $out = {};
    my @sub = sort map { $_->[$idx] } @$array;
    foreach my $x (@sub) {
        next if (exists $out->{$x});
        $out->{$x} = $pos;
        $pos += 1;
    }
    return $out;
}

1;
