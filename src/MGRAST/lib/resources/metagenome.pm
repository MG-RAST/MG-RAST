package resources::metagenome;

use strict;
use warnings;
no warnings('once');

use URI::Escape;
use List::Util qw(first max min sum);
use POSIX qw(strftime floor);

use MGRAST::Metadata;
use MGRAST::Analysis;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map {$_, 1} grep {$_ ne '*'} @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "metagenome";
    $self->{mgdb} = undef;
    $self->{rights} = \%rights;
    $self->{cv} = { verbosity => {'minimal' => 1, 'mixs' => 1, 'metadata' => 1, 'stats' => 1, 'full' => 1},
                    direction => {'asc' => 1, 'desc' => 1},
                    status => {'both' => 1, 'public' => 1, 'private' => 1},
                    match => {'any' => 1, 'all' => 1}
    };
    $self->{instance} = { "id"       => [ 'string', 'unique metagenome identifier' ],
                          "url"      => [ 'uri', 'resource location of this object instance' ],
                          "name"     => [ 'string', 'name of metagenome' ],
                          "library"  => [ 'reference library', 'reference to the related library object' ],
                          "sample"   => [ 'reference sample', 'reference to the related sample object' ],
                          "project"  => [ 'reference project', 'reference to the project object' ],
                          "metadata" => [ 'hash', 'key value pairs describing all metadata' ],
                          "mixs"     => [ 'hash', 'key value pairs describing MIxS metadata' ],
                          "created"  => [ 'date', 'time the metagenome was first created' ],
                          "version"  => [ 'integer', 'version of the metagenome' ],
                          "status"   => [ 'cv', [['public', 'metagenome is public'],
						                         ['private', 'metagenome is private'] ] ],
						  "statistics" => [ 'hash', 'key value pairs describing statistics' ],
                          "sequence_type" => [ 'string', 'sequencing type' ],
                          "pipeline_parameters" => [ 'hash', 'key value pairs describing pipeline parameters' ]
    };
    $self->{query} = { "id"        => [ 'string', 'unique metagenome identifier' ],
                       "url"       => [ 'uri', 'resource location of this object instance' ],
                       "name"      => [ 'string', 'name of metagenome' ],
                       "biome"     => [ 'string', 'environmental biome, EnvO term' ],
                       "feature"   => [ 'string', 'environmental feature, EnvO term' ],
                       "material"  => [ 'string', 'environmental material, EnvO term' ],
                       "country"   => [ 'string', 'country where sample taken' ],
                       "location"  => [ 'string', 'location where sample taken' ],
                       "longitude" => [ 'string', 'longitude where sample taken' ],
                       "latitude"  => [ 'string', 'latitude where sample taken' ],
                       "created"   => [ 'date', 'time the metagenome was first created' ],
                       "status"    => [ 'cv', [['public', 'metagenome is public'],
						                       ['private', 'metagenome is private']] ],
					   "env_package_type" => [ 'string', 'environmental package of sample, GSC term' ],
					   "project_id"       => [ 'string', 'id of project containing metagenome' ],
                       "project_name"     => [ 'string', 'name of project containing metagenome' ],
                       "PI_firstname"     => [ 'string', 'principal investigator\'s first name' ],
                       "PI_lastname"      => [ 'string', 'principal investigator\'s last name' ],
                       "sequence_type"    => [ 'string', 'sequencing type' ],
                       "seq_method"       => [ 'string', 'sequencing method' ],
                       "collection_date"  => [ 'string', 'date sample collected' ]
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "A metagenome is an analyzed set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
                    'requests'      => [{ 'name'        => "info",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns description of parameters and attributes.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => "self",
                                          'parameters'  => { 'options'  => {},
                                                             'required' => {},
                                                             'body'     => {} }
                                        },
                                        { 'name'        => "query",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns a set of data matching the query criteria.",
                                          'example'     => [ $self->cgi->url."/".$self->name."?limit=20&order=name",
                          				                     'retrieve the first 20 metagenomes ordered by name' ],
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => { "next"    => ["uri","link to the previous set or null if this is the first set"],
                                                             "prev"    => ["uri","link to the next set or null if this is the last set"],
                                                             "order"   => ["string","name of the attribute the returned data is ordered by"],
                                                             "data"    => ["list", ["object", [$self->{query}, "metagenome object"] ]],
                                                             "limit"   => ["integer","maximum number of data items returned, default is 10"],
                                                             "offset"  => ["integer","zero based index of the first returned data item"],
                                                             "version" => ['integer', 'version of the object'],
                                                             "url"     => ['uri', 'resource location of this object instance'],
                                                             "total_count" => ["integer","total number of available data items"] },
                                          'parameters' => { 'options' => {
                                                                'metadata'  => ["string", "search parameter: query string for any metadata field"],
                                                                'md5'       => ["string", "search parameter: md5 checksum of feature sequence"],
                                                                'function'  => ["string", "search parameter: query string for function"],
                                                                'organism'  => ["string", "search parameter: query string for organism"],
                                                                'limit'     => ["integer", "maximum number of items requested"],
                                                                'offset'    => ["integer", "zero based index of the first data object to be returned"],
                                                                'order'     => ["string", "metagenome object field to sort by (default is id)"],
                                                                'direction' => ['cv', [['asc','sort by ascending order'],
                                                                                       ['desc','sort by descending order']]],
                                                                'match' => ['cv', [['all','return metagenomes that match all search parameters'],
                                                                                   ['any','return metagenomes that match any search parameters']]],
                                                                'status' => ['cv', [['both','returns all data (public and private) user has access to view'],
                                                                                    ['public','returns all public data'],
                                                                                    ['private','returns private data user has access to view']]],
                                                                'verbosity' => ['cv', [['minimal','returns only minimal information'],
                                                                                       ['mixs','returns all GSC MIxS metadata'],
                                                                                       ['metadata','returns minimal with metadata'],
                                                                                       ['stats','returns minimal with statistics'],
                                                                                       ['full','returns all metadata and statistics']] ] },
                                                            'required' => {},
                                                            'body'     => {} }
                                        },
                                        { 'name'        => "instance",
                                          'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                          'description' => "Returns a single data object.",
                                          'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3?verbosity=metadata",
                          				                     'retrieve all metadata for metagenome mgm4447943.3' ],
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => $self->{instance},
                                          'parameters'  => { 'options' => {
                                                                 'verbosity' => ['cv', [['minimal','returns only minimal information'],
                                                                                        ['metadata','returns minimal with metadata'],
                                                                                        ['stats','returns minimal with statistics'],
                                                                                        ['full','returns all metadata and statistics']]]
                                                                          },
                                                             'required' => { "id" => ["string","unique object identifier"] },
                                                             'body'     => {} }
                                        }] };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check verbosity
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    unless (exists $self->{cv}{verbosity}{$verb}) {
        $self->return_data({"ERROR" => "Invalid verbosity entered ($verb)."}, 404);
    }
    
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
    
    # job is in pipeline, just view minimal info
    unless ($job->viewable) {
        $verb = 'pipeline';
    }

    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || ($self->user && $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # return cached if exists
    $self->return_cached();
    
    # prepare data
    my $data = $self->prepare_data([$job], $verb);
    $data = $data->[0];
    $self->return_data($data, undef, 1); # cache this!
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master = $self->connect_to_datasource();
    
    # get paramaters
    my $verb   = $self->cgi->param('verbosity') || 'minimal';
    my $limit  = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order') || "id";
    my $dir    = $self->cgi->param('direction') || 'asc';
    my $match  = $self->cgi->param('match') || 'all';
    my $status = $self->cgi->param('status') || 'both';
    
    # check CV
    unless (exists $self->{cv}{verbosity}{$verb}) {
        $self->return_data({"ERROR" => "Invalid verbosity entered ($verb)."}, 404);
    }
    unless (exists $self->{cv}{direction}{$dir}) {
        $self->return_data({"ERROR" => "Invalid direction entered ($dir) for query."}, 404);
    }
    unless (exists $self->{cv}{match}{$match}) {
        $self->return_data({"ERROR" => "Invalid match entered ($match) for query."}, 404);
    }
    unless (exists $self->{cv}{status}{$status}) {
        $self->return_data({"ERROR" => "Invalid status entered ($status) for query."}, 404);
    }
    unless (exists $self->{query}{$order}) {
        $self->return_data({"ERROR" => "Invalid order entered ($order) for query."}, 404);
    }
    if (($limit > 10000) || ($limit < 1)) {
        $self->return_data({"ERROR" => "Limit must be less than 10,000 and greater than 0 ($limit) for query."}, 404);
    }

    # explicitly setting the default CGI parameters for returned url strings
    $self->cgi->param('verbosity', $verb);
    $self->cgi->param('limit', $limit);
    $self->cgi->param('offset', $offset);
    $self->cgi->param('order', $order);
    $self->cgi->param('direction', $dir);
    $self->cgi->param('match', $match);
    $self->cgi->param('status', $status);
    
    # get query fields
    my @url_params = ();
    my @solr_fields = ();
    # non-returnable query fields
    foreach my $field ('metadata', 'md5', 'function', 'organism') {
        if ($self->cgi->param($field)) {
            push @url_params, $field."=".$self->cgi->param($field);
            push @solr_fields, $field.':'.$self->cgi->param($field);
        }
    }
    # returnable query fields
    foreach my $field (grep {($_ ne 'status') && ($_ ne 'url')} keys %{$self->{query}}) {
        if ($self->cgi->param($field)) {
            push @url_params, $field."=".$self->cgi->param($field);
            push @solr_fields, $field.':'.$self->cgi->param($field);
        }
    }
    # sequence stat fields
    foreach my $field (@{$self->seq_stats}) {
        if ($self->cgi->param($field)) {
            push @url_params, $field."=".$self->cgi->param($field);
            push @solr_fields, $field.':'.$self->cgi->param($field);
        }
    }
    
    # build urls
    my $query_str = join('&', @url_params);
    my $solr_query_str = ($match eq 'all') ? join(' AND ', @solr_fields) : join(' OR ', @solr_fields);
    
    # complete solr query and add rights
    if ($solr_query_str ne "") {
        $solr_query_str = '('.$solr_query_str.') AND ';
    }
    
    my $return_empty_set = 0;
    if ($status eq 'public') {
        $solr_query_str .= '(status:public)';
    } elsif ($status eq 'private') {
        unless ($self->user) {
            $self->return_data( {"ERROR" => "Missing authentication for searching private datasets"}, 401 );
        }
        if ($self->user->has_star_right('view', 'metagenome')) {
            $solr_query_str .= "(status:private)";
        } else {
            if (scalar(%{$self->rights}) > 0) {
                $solr_query_str .= "(status:private AND (".join(" OR ", map {'id:mgm'.$_} keys %{$self->rights})."))";
            } else {
                $return_empty_set = 1;
            }
        }
    } else {
        if ($self->user) {
            if ($self->user->has_star_right('view', 'metagenome')) {
                $solr_query_str .= "(status:*)";
            } else {
                if (scalar(%{$self->rights}) > 0) {
                    $solr_query_str .= "((status:public) OR (status:private AND (".join(" OR ", map {'id:mgm'.$_} keys %{$self->rights}).")))";
                } else {
                    $solr_query_str .= '(status:public)';
                }
            }
        } else {
            $solr_query_str .= '(status:public)';
        }
    }
    
    # get results
    my ($data, $total) = ([], 0);
    my $fields = ['id', 'name', 'status', 'created'];
    if ($verb eq 'mixs') {
        @$fields = keys %{$self->{query}};
    }
    unless ($return_empty_set) {
        ($data, $total) = $self->solr_data($solr_query_str, $order."_sort+".$dir, $offset, $limit, $fields);
    }
    my $obj = $self->check_pagination($data, $total, $limit);
    $obj->{version} = 1;
    
    # found nothing, return it
    if (scalar(@$data) == 0) {
        $self->return_data($obj);
    }

    if (($verb eq 'minimal') || ($verb eq 'mixs')) {
        # add missing fields to solr data
        foreach my $item (@{$obj->{data}}) {
            map { $item->{$_} = exists($item->{$_}) ? $item->{$_} : "" } @$fields;
        }
    } else {
        # create job objects from solr data
        my $jobs = [];
        foreach my $d (@{$obj->{data}}) {
            my $id = $d->{id};
            $id =~ s/^mgm//;
            my $job = $master->Job->get_objects( {metagenome_id => $id, viewable => 1} );
            if ($job && @$job) {
                push @$jobs, $job->[0];
            }
        }
        $obj->{data} = $self->prepare_data($jobs, $verb);
    }
    
    $self->return_data($obj);
}

sub solr_data {
    my ($self, $solr_query_str, $sort, $offset, $limit, $fields) = @_;
    $solr_query_str = uri_unescape($solr_query_str);
    $solr_query_str = uri_escape($solr_query_str);
    return $self->get_solr_query("POST", $Conf::job_solr, $Conf::job_collect, $solr_query_str, $sort, $offset, $limit, $fields);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data, $verb) = @_;
    
    my $mgids = [];
    @$mgids = map { $_->{metagenome_id} } @$data;
    my $jobdata = {};
    my $mddb = undef;
    
    if (($verb eq 'metadata') || ($verb eq 'full')) {
        $mddb = MGRAST::Metadata->new();
        $jobdata = $mddb->get_jobs_metadata_fast($mgids, 1);
    }
    if (($verb eq 'stats') || ($verb eq 'full')) {
        # initialize analysis obj with mgids
        my $master = $self->connect_to_datasource();
        my $mgdb = MGRAST::Analysis->new( $master->db_handle );
        unless (ref($mgdb)) {
            $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
        }
        $mgdb->set_jobs($mgids);
        $self->{mgdb} = $mgdb;
    }

    my $objects = [];
    foreach my $job (@$data) {
        my $url = $self->cgi->url;
        # set object
        my $obj = {};
        $obj->{id} = "mgm".$job->{metagenome_id};
        $obj->{url} = $url.'/metagenome/'.$obj->{id}.'?verbosity='.$verb;
        $obj->{name} = $job->{name};
        $obj->{job_id} = $job->{job_id};
        $obj->{status} = ($verb eq 'pipeline') ? 'pipeline' : ($job->{public} ? 'public' : 'private');
        $obj->{created} = $job->{created_on};
        $obj->{version} = 1;
        $obj->{project} = undef;
        $obj->{sample}  = undef;
        $obj->{library} = undef;
        $obj->{sequence_type} = $job->{sequence_type};
        # add metadata pointers
	    eval {
	        my $proj = $job->primary_project;
	        $obj->{project} = ["mgp".$proj->{id}, $url."/project/mgp".$proj->{id}];
	    };
	    eval {
	        my $samp = $job->sample;
	        $obj->{sample} = ["mgs".$samp->{ID}, $url."/sample/mgs".$samp->{ID}];
	    };
	    eval {
	        my $lib = $job->library;
	        $obj->{library} = ["mgl".$lib->{ID}, $url."/library/mgl".$lib->{ID}];
	    };
	    # get job info
	    my $jstats  = $job->stats();
	    my $jdata   = $job->data();
	    if (exists($jdata->{deleted}) && $jdata->{deleted}) {
	        # this is a deleted job !!
	        $self->return_data( {"ERROR" => "Metagenome mgm".$job->{metagenome_id}." does not exist: ".$jdata->{deleted}}, 400 );
	    }
	    # add pipeline info
	    my $pparams = $self->pipeline_defaults;
	    $pparams->{assembled} = (exists($jdata->{assembled}) && $jdata->{assembled}) ? 'yes' : 'no';
	    $pparams->{publish_priority} = (exists($jdata->{priority}) && $jdata->{priority}) ? $jdata->{priority} : 'never';
	    # replace value defaults
	    foreach my $tag (('max_ambig', 'min_qual', 'max_lqb', 'screen_indexes',
	                      'm5nr_sims_version', 'm5rna_sims_version',
	                      'm5nr_annotation_version', 'm5rna_annotation_version')) {
	        if (exists($jdata->{$tag}) && defined($jdata->{$tag})) {
	            $pparams->{$tag} = $jdata->{$tag};
	        }
        }
        # replace boolean defaults
        foreach my $tag (('filter_ln', 'filter_ambig', 'dynamic_trim', 'dereplicate', 'bowtie')) {
	        if (exists($jdata->{$tag}) && (! $jdata->{$tag})) {
	            $pparams->{$tag} = 'no';
	        }
        }
	    # preprocessing
	    if ($jdata->{file_type}) {
	        $pparams->{file_type} = ($jdata->{file_type} =~ /^(fq|fastq)$/) ? 'fastq' : 'fna';
	    } elsif ($jdata->{suffix}) {
	        $pparams->{file_type} = ($jdata->{suffix} =~ /^(fq|fastq)$/) ? 'fastq' : 'fna';
	    } else {
	        $pparams->{file_type} = 'fna';
	    }
        if ($pparams->{file_type} eq 'fna') {
            if ($jdata->{max_ln} && $jstats->{average_length_raw} && $jstats->{standard_deviation_length_raw} && ($jstats->{standard_deviation_length_raw} > 0)) {
		        my $multiplier = (1.0 * ($jdata->{max_ln} - $jstats->{average_length_raw})) / $jstats->{standard_deviation_length_raw};
		        $pparams->{filter_ln_mult} = sprintf("%.2f", $multiplier);
            }
            delete @{$pparams}{'dynamic_trim', 'min_qual', 'max_lqb'};
        } elsif ($pparams->{file_type} eq 'fastq') {
            delete @{$pparams}{'filter_ln', 'filter_ln_mult', 'filter_ambig', 'max_ambig'};
        }
        $obj->{pipeline_parameters} = $pparams;
        $obj->{pipeline_version} = '3.0';
        
        if (($verb eq 'mixs') || ($verb eq 'full')) {
            if (! $mddb) {
                $mddb = MGRAST::Metadata->new();
            }
            my $mixs = $mddb->get_job_mixs($job);
	        if ($verb eq 'full') {
	            $obj->{mixs} = $mixs;
            } else {
                map { $obj->{$_} = $mixs->{$_} } keys %$mixs;
            }
        }
        if (($verb eq 'metadata') || ($verb eq 'full')) {
            $obj->{metadata} = $jobdata->{$job->{metagenome_id}};
            $obj->{mixs_compliant} = $mddb->is_job_compliant($job);
        }
        if (($verb eq 'stats') || ($verb eq 'full')) {
            my $params = {type => 'metagenome', data_type => 'statistics', id => 'mgm'.$job->{metagenome_id}};
            my $stat_node = $self->get_shock_query($params, $self->mgrast_token);
            if (scalar(@{$stat_node}) == 0) {
                $obj->{statistics} = {};
            } else {
                $obj->{statistics} = $self->clean_stats($stat_node->[0]{id});
            }
        }
        push @$objects, $obj;
    }
    return $objects;
}

sub clean_stats {
    my ($self, $stat_node_id) = @_;
    
    my $stats = $self->json->decode($self->get_shock_file($stat_node_id, undef, $self->mgrast_token));
    # seq stats
    foreach my $key (keys %{$stats->{sequence_stats}}) {
        $stats->{sequence_stats}{$key} = $self->toFloat($stats->{sequence_stats}{$key});
    }
    # source
    foreach my $src (keys %{$stats->{source}}) {
        foreach my $type (keys %{$stats->{source}{$src}}) {
            if (! $stats->{source}{$src}{$type}) {
                $stats->{source}{$src}{$type} = [];
            } else {
                $stats->{source}{$src}{$type} = [ map { int($_) } @{$stats->{source}{$src}{$type}} ];
            }
        }
    }
    # qc
    foreach my $qc (keys %{$stats->{qc}}) {
        foreach my $type (keys %{$stats->{qc}{$qc}}) {
            if (! $stats->{qc}{$qc}{$type}{data}) {                
                $stats->{qc}{$qc}{$type}{data} = [];
            }
        }
    }
    # tax / ontol
    foreach my $ann (('taxonomy', 'ontology')) {
        foreach my $type (keys %{$stats->{$ann}}) {
            if (! $stats->{$ann}{$type}) {
                $stats->{$ann}{$type} = [];
            } else {
                $stats->{$ann}{$type} = [ map { [$_->[0], int($_->[1])] } @{$stats->{$ann}{$type}} ];
            }
        }
    }
    # histograms
    foreach my $hist (('gc_histogram', 'length_histogram')) {
        foreach my $type (keys %{$stats->{$hist}}) {
            if (! $stats->{$hist}{$type}) {
                $stats->{$hist}{$type} = [];
            } else {
                $stats->{$hist}{$type} = [ map { [$self->toFloat($_->[0]), int($_->[1])] } @{$stats->{$hist}{$type}} ];
            }
        }
    }
    # rarefaction
    $stats->{rarefaction} = [ map { [int($_->[0]), $self->toFloat($_->[1])] } @{$stats->{rarefaction}} ];
    
    return $stats;
}

1;
