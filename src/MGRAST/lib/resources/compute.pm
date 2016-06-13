package resources::compute;

use strict;
use warnings;
no warnings('once');

use MGRAST::Abundance;
use List::MoreUtils qw(any uniq);
use File::Temp qw(tempfile tempdir);

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "compute";
    $self->{example} = '"columns": ["mgm4441619.3","mgm4441656.4","mgm4441680.3","mgm4441681.3"], "rows": ["Eukaryota","Bacteria","Archaea"], "data": [[135,410,848,1243],[4397,6529,71423,204413],[1422,2156,874,1138]]';
    $self->{attributes} = { alphadiversity => { "id"   => [ "string", "unique metagenome identifier" ],
                                                "url"  => [ "string", "resource location of this object instance" ],
                                                "data" => [ 'float', 'alpha diversity value' ] },
                            rarefaction => { "id"   => [ "string", "unique metagenome identifier" ],
                                             "url"  => [ "string", "resource location of this object instance" ],
                                             "data" => ['list', ['list', ['float', 'rarefaction value']]], },
                            normalize => { 'data' => ['list', ['list', ['float', 'normalized value']]],
                                           'rows' => ['list', ['string', 'row id']],
                                           'columns' => ['list', ['string', 'column id']] },
                            significance => { 'data' => ['list', ['list', ['float', 'significance value']]],
                                              'rows' => ['list', ['string', 'row name']],
                                              'columns' => ['list', ['string', 'column name']] },
                            distance => { 'data' => ['list', ['list', ['float', 'distance value']]],
                                          'rows' => ['list', ['string', 'row id']],
                                          'columns' => ['list', ['string', 'column id']] },
                            heatmap => { 'data' => ['list', ['list', ['float', 'normalized value']]],
                                         'rows' => ['list', ['string', 'row id']],
                                         'columns' => ['list', ['string', 'column id']],
                                         'colindex' => ['list', ['float', 'column id index']],
                                         'rowindex' => ['list', ['float', 'row id index']],
                                         'coldend' => ['object', 'dendrogram object for columns'],
                                         'rowdend' => ['object', 'dendrogram object for rows'] },
                            pcoa => { 'data' => [ 'list', ['object', [
                                                            {'id' => ['string', 'column id'], 'pco' => ['list', ['float', 'principal component value']]},
                                                            "pcoa object" ]
                                                          ] ],
      				                  'pco' => ['list', ['float', 'average principal component value']] }
      				      };
    $self->{norm} = ["DESeq_blind","standardize","quantile","DESeq_per_condition","DESeq_pooled","DESeq_pooled_CR"];
    $self->{distance} = ["bray-curtis", "euclidean", "maximum", "manhattan", "canberra", "minkowski", "difference"];
    $self->{cluster} = ["ward", "single", "complete", "mcquitty", "median", "centroid"];
    $self->{significance} = ["Kruskal-Wallis", "t-test-paired", "Wilcoxon-paired", "t-test-unpaired", "Mann-Whitney-unpaired-Wilcoxon", "ANOVA-one-way"];
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		            'url' => $self->cgi->url."/".$self->name,
		            'description' => "Calculate various statistics for given input data.",
		            'type' => 'object',
		            'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		            'requests' => [
		                { 'name'        => "info",
				          'request'     => $self->cgi->url."/".$self->name,
				          'description' => "Returns description of parameters and attributes.",
				          'method'      => "GET",
				          'type'        => "synchronous",  
				          'attributes'  => "self",
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {} }
						},
						{ 'name'        => "alphadiversity",
				          'request'     => $self->cgi->url."/".$self->name."/alphadiversity/{ID}",
				          'description' => "Calculate alpha diversity value for given ID and taxon level.",
				          'example'     => [ $self->cgi->url."/".$self->name."/alphadiversity/mgm4447943.3?level=order",
             				                 "retrieve alpha diversity for order taxon" ],
				          'method'      => "GET",
				          'type'        => "synchronous or asynchronous",
				          'attributes'  => $self->{attributes}{alphadiversity},
				          'parameters'  => { 'options'  => { 'level' => ['cv', $self->hierarchy->{organism}],
				                                             "ann_ver" => ["int", 'M5NR annotation version, default '.$self->{m5nr_default}],
				                                             'asynchronous' => [ 'boolean', "if true return process id to query status resource for results, default is false" ] },
							                 'required' => { 'id' => ["string", "unique object identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "rarefaction",
				          'request'     => $self->cgi->url."/".$self->name."/rarefaction/{ID}",
				          'description' => "Calculate rarefaction x-y coordinates for given ID and taxon level.",
				          'example'     => [ $self->cgi->url."/".$self->name."/rarefaction/mgm4447943.3?level=order",
             				                 "retrieve rarefaction for order taxon" ],
				          'method'      => "GET",
				          'type'        => "synchronous or asynchronous",
				          'attributes'  => $self->{attributes}{rarefaction},
				          'parameters'  => { 'options'  => { 'level' => ['cv', $self->hierarchy->{organism}],
				                                             "alpha" => ["boolean", "if true also return alphadiversity, default is false"],
				                                             "seq_num" => ["int", "number of sequences in metagenome"],
				                                             "ann_ver" => ["int", 'M5NR annotation version, default '.$self->{m5nr_default}],
				                                             'asynchronous' => [ 'boolean', "if true return process id to query status resource for results, default is false" ] },
							                 'required' => { 'id' => ["string", "unique object identifier"] },
							                 'body'     => {} }
						},
				        { 'name'        => "normalize",
				          'request'     => $self->cgi->url."/".$self->name."/normalize",
				          'description' => "Calculate normalized values for given input data.",
				          'example'     => [ 'curl -X POST -d \'{'.$self->{example}.'}\' "'.$self->cgi->url."/".$self->name.'/normalize"',
             				                 "retrieve normalized values for input abundances" ],
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{normalize},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "data" => ['list', ['list', ['int', 'raw value']]],
          							                         "rows" => ['list', ['string', 'row id']],
          							                         "columns" => ['list', ['string', 'column id']],
          							                         "norm" => ['cv', [map {[$_, $_." normalization method"]} @{$self->{norm}}]] } }
						},
                        # { 'name'        => "significance",
                        #                         'request'     => $self->cgi->url."/".$self->name."/significance",
                        #                         'description' => "Calculate significance values for given input data.",
                        #                         'example'     => [ 'curl -X POST -d \'{"test":"Kruskal-Wallis","groups":["whale","whale","cow","cow"],'.$self->{example}.'}\' "'.$self->cgi->url."/".$self->name.'/significance"',
                        #                                            "retrieve significance values for input abundances and groups using the 'Kruskal-Wallis' significance test" ],
                        #                         'method'      => "POST",
                        #                         'type'        => "synchronous",
                        #                         'attributes'  => $self->{attributes}{significance},
                        #                         'parameters'  => { 'options'  => {},
                        #                    'required' => {},
                        #                    'body'     => { "data" => ['list', ['list', ['int', 'raw value']]],
                        #                                                                "rows" => ['list', ['string', 'row id']],
                        #                                                                "columns" => ['list', ['string', 'column id']],
                        #                                                                "groups" =>  ['list', ['string', 'group name']],
                        #                                                                "test" => ['cv', [map {[$_, $_." significance testing method"]} @{$self->{significance}}]],
                        #                                                                "norm" => ['cv', [map {[$_, $_." normalization method"]} @{$self->{norm}}]],
                        #                                                                "raw" => ["boolean", "option to use raw data (not normalize)"] } }
                        # },
						{ 'name'        => "distance",
				          'request'     => $self->cgi->url."/".$self->name."/distance",
				          'description' => "Calculate a distance matrix for given input data.",
				          'example'     => [ 'curl -X POST -d \'{"distance":"euclidean",'.$self->{example}.'}\' "'.$self->cgi->url."/".$self->name.'/distance"',
                 				             "retrieve distance matrix of normalized input abundances using 'euclidean' distance method" ],
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{distance},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "data" => ['list', ['list', ['float', 'raw or normalized value']]],
            							                     "rows" => ['list', ['string', 'row id']],
            							                     "columns" => ['list', ['string', 'column id']],
							                                 "distance" => ['cv', [map {[$_, $_." distance method"]} @{$self->{distance}}]],
							                                 "norm" => ['cv', [map {[$_, $_." normalization method"]} @{$self->{norm}}]],
							                                 "raw" => ["boolean", "option to use raw data (not normalize)"] } }
						},
						{ 'name'        => "heatmap",
				          'request'     => $self->cgi->url."/".$self->name."/heatmap",
				          'description' => "Calculate a dendrogram for given input data.",
				          'example'     => [ 'curl -X POST -d \'{"raw":0,"cluster":"mcquitty",'.$self->{example}.'}\' "'.$self->cgi->url."/".$self->name.'/heatmap"',
               				                 "retrieve dendrogram of normalized input abundances using 'mcquitty' cluster method" ],
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{heatmap},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "data" => ['list', ['list', ['float', 'raw or normalized value']]],
           							                         "rows" => ['list', ['string', 'row id']],
           							                         "columns" => ['list', ['string', 'column id']],
     							                             "cluster" => ['cv', [map {[$_, $_." cluster method"]} @{$self->{cluster}}]],
     							                             "distance" => ['cv', [map {[$_, $_." distance method"]} @{$self->{distance}}]],
     							                             "norm" => ['cv', [map {[$_, $_." normalization method"]} @{$self->{norm}}]],
     							                             "raw" => ["boolean", "option to use raw data (not normalize)"] } }
						},
						{ 'name'        => "pcoa",
				          'request'     => $self->cgi->url."/".$self->name."/pcoa",
				          'description' => "Calculate a PCoA for given input data.",
				          'example'     => [ 'curl -X POST -d \'{"raw":1,"distance":"euclidean",'.$self->{example}.'}\' "'.$self->cgi->url."/".$self->name.'/pcoa"',
                 				             "retrieve PCO of raw input abundances using 'euclidean' distance method" ],
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{pcoa},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "data" => ['list', ['list', ['float', 'raw or normalized value']]],
            							                     "rows" => ['list', ['string', 'row id']],
            							                     "columns" => ['list', ['string', 'column id']],
							                                 "distance" => ['cv', [map {[$_, $_." distance method"]} @{$self->{distance}}]],
							                                 "norm" => ['cv', [map {[$_, $_." normalization method"]} @{$self->{norm}}]],
							                                 "raw" => ["boolean", "option to use raw data (not normalize)"] } }
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
    } elsif (($self->method eq 'GET') && (scalar(@{$self->rest}) > 1)) {
        $self->instance($self->rest->[0], $self->rest->[1]);
    } elsif (any {$self->rest->[0] eq $_} ('normalize', 'significance', 'distance', 'heatmap', 'pcoa')) {
        $self->abundance_compute($self->rest->[0]);
    } elsif (any {$self->rest->[0] eq $_} ('stats', 'drisee', 'kmer')) {
        $self->sequence_compute($self->rest->[0]);
    } else {
        $self->info();
    }
}

sub sequence_compute {
    my ($self, $type) = @_;
    $self->return_data( {"ERROR" => "compute request $type is not currently available"}, 404 );
}

# the resource is called with an id parameter
sub instance {
    my ($self, $type, $mgid) = @_;
    
    # check id format
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if (! $id) {
        $self->return_data( {"ERROR" => "invalid id format: $mgid"}, 400 );
    }
    # get data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        return ({"ERROR" => "id mgm$id does not exist"}, 404);
    }
    $job = $job->[0];
    # check rights
    unless ($job->public || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome')))) {
        return ({"ERROR" => "insufficient permissions for metagenome mgm$id"}, 401);
    }
    
    # asynchronous call, fork the process and return the process id.
    if ($self->cgi->param('asynchronous')) {
        my $attr = {
            type => "temp",
            id   => $mgid,
            url_id => $self->url_id,
            owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
            data_type => "diversity"
        };
        # already cashed in shock - say submitted in case its running
        my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
        if ($nodes && (@$nodes > 0)) {
            $self->return_data({"status" => "submitted", "id" => $nodes->[0]->{id}, "url" => $self->cgi->url."/status/".$nodes->[0]->{id}});
        }
        # need to create new node and fork
        my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "7D");
        my $pid = fork();
        # child - get data and dump it
        if ($pid == 0) {
            close STDERR;
            close STDOUT;
            my ($data, $error) = $self->species_diversity_compute($type, $id);
            if ($error) {
                $data->{STATUS} = $error;
            }
            $self->put_shock_file($data->{id}."_".$type.".json", $data->{data}, $node->{id}, $self->mgrast_token);
            exit 0;
        }
        # parent - end html session
        else {
            $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->cgi->url."/status/".$node->{id}});
        }
    }
    # synchronous call, prepare then return data
    else {
        my ($data, $error) = $self->species_diversity_compute($type, $id);
        $self->return_data($data, $error);
    }
}

# compute alpha diversity and/or rarefaction
sub species_diversity_compute {
    my ($self, $type, $id) = @_;
    
    # get data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        return ({"ERROR" => "id mgm$id does not exist"}, 404);
    }
    $job = $job->[0];

    # initialize
    my $level = $self->cgi->param('level') || 'species';
    my $ver   = $self->cgi->param('ann_ver') || $self->{m5nr_default};
    my $data  = {
        id => 'mgm'.$job->{metagenome_id},
        url => $self->cgi->url.'/'.$type.'/mgm'.$job->{metagenome_id}.'?level='.$level
    };
    
    my $chdl = $self->cassandra_m5nr_handle("m5nr_v".$ver, $Conf::cassandra_m5nr);
    my $mgdb = MGRAST::Abundance->new($chdl, $ver);
    my ($org_map, undef, undef) = $mgdb->all_job_abundances($job->{job_id}, [$level], 1, undef, undef);
    
    if ($type eq "alphadiversity") {
        $data->{data} = $mgdb->get_alpha_diversity($org_map->{$level});
    } elsif ($type eq "rarefaction") {
        my $snum = $self->cgi->param('seq_num') || 0;
        my $alpha = $self->cgi->param('alpha') ? 1 : 0;
        unless ($snum) {
            my $jstats = $job->stats();
            $snum = $jstats->{sequence_count_raw} || 1;
        }
        my $rare = $mgdb->get_rarefaction_xy($org_map->{$level}, $snum);
        if ($alpha) {
            $data->{data}{rarefaction} = $rare;
            $data->{data}{alphadiversity} = $mgdb->get_alpha_diversity($org_map->{$level});
        } else {
            $data->{data} = $rare;
        }
    } else {
        return ({"ERROR" => "invalid compute type: $type"}, 400);
    }
    $mgdb->DESTROY();
    
    return ($data, undef);
}

sub abundance_compute {
    my ($self, $type) = @_;

    # paramaters
    my $raw = $self->cgi->param('raw') || 0;
    my $test = $self->cgi->param('test') || 'Kruskal-Wallis';
    my $norm = $self->cgi->param('norm') || 'DESeq_blind';
    my $cluster = $self->cgi->param('cluster') || 'ward';
    my $distance = $self->cgi->param('distance') || 'bray-curtis';
    my $groups = $self->cgi->param('groups') ? [split(/,/, $self->cgi->param('groups'))] : [];
    my $infile = '';
    
    # posted data
    my $post_data = $self->cgi->param('POSTDATA') ? $self->cgi->param('POSTDATA') : join("", $self->cgi->param('keywords'));
    if ($post_data) {
        my ($data, $col, $row) = ([], [], []);
        eval {
            my $json_data = $self->json->decode($post_data);
            if (exists $json_data->{raw}) { $raw = $json_data->{raw}; }
            if (exists $json_data->{test}) { $test = $json_data->{test}; }
            if (exists $json_data->{norm}) { $norm = $json_data->{norm}; }
            if (exists $json_data->{cluster}) { $cluster = $json_data->{cluster}; }
            if (exists $json_data->{distance}) { $distance = $json_data->{distance}; }
            $data = $json_data->{data};
            $col  = $json_data->{columns};
            $row  = $json_data->{rows};
            $groups = exists($json_data->{groups}) ? $json_data->{groups} : [];
        };
        if ($@ || (@$data == 0)) {
            $self->return_data( {"ERROR" => "unable to obtain POSTed data: ".$@}, 500 );
        }
        if (scalar(@$col) < 2) {
            $self->return_data( {"ERROR" => "a minimum of 2 columns are required"}, 400 );
        }
        if (scalar(@$row) < 2) {
            $self->return_data( {"ERROR" => "a minimum of 2 rows are required"}, 400 );
        }
        if ($type eq 'significance') {
            if (scalar(@$groups) < 3) {
                $self->return_data( {"ERROR" => "a minimum of 3 groups are required"}, 400 );
            }
            if (scalar(@$groups) != scalar(@$col)) {
                $self->return_data( {"ERROR" => "number of groups must match number of columns"}, 400 );
            }
        }
        # transform POSTed json to input file format
        my ($tfh, $tfile) = tempfile($type."XXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
        eval {
            print $tfh "\t".join("\t", @$col)."\n";
            for (my $i=0; $i<scalar(@$data); $i++) {
                print $tfh $row->[$i]."\t".join("\t", @{$data->[$i]})."\n";
            }
        };
        if ($@) {
            $self->return_data( {"ERROR" => "POSTed data format is invalid: ".$@}, 500 );
        }
        close $tfh;
        chmod 0666, $tfile;
        $infile = $tfile;
    # data sent in file upload
    } elsif ($self->cgi->param('data')) {
        $infile = $self->form_file('data', $type, 'txt');
    } else {
        $self->return_data( {"ERROR" => "POST request missing data"}, 400 );
    }
    
    # check cv
    unless (any {$_ eq $test} @{$self->{significance}}) {
        $self->return_data({"ERROR" => "test '$test' is invalid, use one of: ".join(",", @{$self->{significance}})}, 400);
    }
    unless (any {$_ eq $norm} @{$self->{norm}}) {
        $self->return_data({"ERROR" => "norm '$norm' is invalid, use one of: ".join(",", @{$self->{norm}})}, 400);
    }
    unless (any {$_ eq $cluster} @{$self->{cluster}}) {
        $self->return_data({"ERROR" => "cluster '$cluster' is invalid, use one of: ".join(",", @{$self->{cluster}})}, 400);
    }
    unless (any {$_ eq $distance} @{$self->{distance}}) {
        $self->return_data({"ERROR" => "distance '$distance' is invalid, use one of: ".join(",", @{$self->{distance}})}, 400);
    }
    
    my $data;
    # nomalize
    if ($type eq 'normalize') {
        $data = $self->normalize($infile, $norm, 1);
    }
    # significance
    elsif ($type eq 'significance') {
        #if (! $raw) {
        #    $infile = $self->normalize($infile, $norm);
        #}
        #$data = $self->significance($infile, $groups, $test, 1);
        $self->return_data( {"ERROR" => "compute request $type is not currently available"}, 404 );
    }
    # distance
    elsif ($type eq 'distance') {
        if (! $raw) {
            $infile = $self->normalize($infile, $norm);
        }
        $data = $self->distance($infile, $distance, 1);
    }
    # heatmap
    elsif ($type eq 'heatmap') {
        if (! $raw) {
            $infile = $self->normalize($infile, $norm);
        }
        $data = $self->heatmap($infile, $distance, $cluster, 1);
    }
    # pcoa
    elsif ($type eq 'pcoa') {
        if (! $raw) {
            $infile = $self->normalize($infile, $norm);
        }
        $data = $self->pcoa($infile, $distance, 1);
    }
    
    $self->return_data($data);
}

sub form_file {
    my ($self, $param, $prefix, $suffix) = @_;
    
    my $infile = '';
    my $fname  = $self->cgi->param($param);
    if ($fname) {
        if ($fname =~ /\.\./) {
            $self->return_data({"ERROR" => "Invalid parameters, trying to change directory with filename, aborting"}, 400);
        }
        if ($fname !~ /^[\w\d_\.]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, dot (.), and number characters"}, 400);
        }
        my $fhdl = $self->cgi->upload($param);
        if (defined $fhdl) {
            my ($bytesread, $buffer);
            my $io_handle = $fhdl->handle;
            my ($tfh, $tfile) = tempfile($prefix."XXXXXXX", DIR => $Conf::temp, SUFFIX => '.'.$suffix);
            while ($bytesread = $io_handle->read($buffer, 4096)) {
                print $tfh $buffer;
            }
            close $tfh;
            chmod 0666, $tfile;
            $infile = $tfile;
        } else {
            $self->return_data({"ERROR" => "storing object failed - could not open target file"}, 507);
        }
    } else {
        $self->return_data({"ERROR" => "Invalid parameters, requires filename and data"}, 400);
    }
    return $infile;
}

sub normalize {
    my ($self, $fname, $method, $json) = @_;
    
    my $time = time;
    my $src  = $Conf::bin."/norm_deseq.r";
    my $fout = $Conf::temp."/rdata.normalize.".$time;
    my $rcmd = qq(source("$src")
MGRAST_preprocessing(
    norm_method="$method",
    file_in="$fname",
    file_out="$fout",
    produce_fig=FALSE )
);
    $self->run_r($rcmd);
    if ($json) {
        return $self->parse_matrix($fout);
    } else {
        return $fout;
    }
}

sub significance {
    my ($self, $fname, $groups, $test, $json) = @_;
    
    my $time = time;
    my $src  = $Conf::bin."/group_stats_plot.r";
    my $fout = $Conf::temp."/rdata.significance.".$time;
    my $grps = 'c('.join(',', map {'"'.$_.'"'} @$groups).')';
    my $rcmd = qq(source("$src")
group_stats_plot(
    file_in="$fname",
    file_out="$fout",
    stat_test="$test",
    order_by=NULL,
    order_decreasing=TRUE,
    my_grouping=$grps )
);
    $self->run_r($rcmd);
    if ($json) {
        return $self->parse_matrix($fout);
    } else {
        return $fout;
    }
}

sub distance {
    my ($self, $fname, $dist, $json) = @_;
    
    my $time = time;
    my $src  = $Conf::bin."/calc_distance.r";
    my $fout = $Conf::temp."/rdata.distance.".$time;
    my $rcmd = qq(source("$src")
MGRAST_distance(
    file_in="$fname",
    file_out="$fout",
    dist_method="$dist" )
);
    $self->run_r($rcmd);
    if ($json) {
        return $self->parse_matrix($fout);
    } else {
        return $fout;
    }
}

sub heatmap {
    my ($self, $fname, $dist, $clust, $json) = @_;
    
    my $time = time;
    my $src  = $Conf::bin."/dendrogram.r";
    my ($fcol, $frow) = ($Conf::temp."/rdata.col.$time", $Conf::temp."/rdata.row.$time");
    my $rcmd = qq(source("$src")
MGRAST_dendrograms(
    file_in="$fname",
    file_out_column="$fcol",
    file_out_row="$frow",
    dist_method="$dist",
    clust_method="$clust",
    produce_figures=FALSE )
);
    $self->run_r($rcmd);
    if ($json) {
        my $data = $self->parse_matrix($fname);
        ($data->{colindex}, $data->{coldend}) = $self->ordered_distance($fcol);
        ($data->{rowindex}, $data->{rowdend}) = $self->ordered_distance($frow);
        return $data;
    } else {
        return ($fcol, $frow);
    }
}

sub pcoa {
    my ($self, $fname, $dist, $json) = @_;

    my $time = time;
    my $src  = $Conf::bin."/plot_pco.r";
    my $fout = $Conf::temp."/rdata.pcoa.".$time;
    my $rcmd = qq(source("$src")
MGRAST_plot_pco(
    file_in="$fname",
    file_out="$fout",
    dist_method="$dist",
    headers=0 )
);
    $self->run_r($rcmd);
    if ($json) {
        my $data = { data => [], pco => [] };
        my @matrix = map { [split(/\t/, $_)] } split(/\n/, $self->read_file($fout));
        foreach my $row (@matrix) {
            my $r = shift @$row;
            @$row = map {$_ * 1.0} @$row;
            $r =~ s/\"//g;
            if ($r =~ /^PCO/) {
                push @{$data->{pco}}, $row->[0];
            } else {
                push @{$data->{data}}, {'id' => $r, 'pco' => $row};
            }
        }
        return $data;
    } else {
        return $fout;
    }
}

sub run_r {
    my ($self, $rcmd) = @_;
    eval {
        my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
        system(qq(echo '$rcmd' | $R --vanilla --slave));
    };
    if ($@) {
        $self->return_data({"ERROR" => "Error running R: ".$@}, 500);
    }
}

sub read_file {
    my ($self, $fname) = @_;
    my $data = "";
    eval {
        open(DFH, "<$fname");
        $data = do { local $/; <DFH> };
        close DFH;
        unlink $fname;
    };
    if ($@ || (! $data)) {
        $self->return_data({"ERROR" => "Unable to retrieve results: ".$@}, 400);
    }
    return $data;
}

sub ordered_distance {
    my ($self, $fname) = @_;
    
    my @lines = split(/\n/, $self->read_file($fname));
    my $line1 = shift @lines;
    my @order_dist = map { int($_) } split(/,/, $line1);
    my @dist_matrix = ();

    shift @lines;
    foreach my $l (@lines) {
        my @row = map { int($_) } split(/\t/, $l);
        push @dist_matrix, \@row;
    }
    return (\@order_dist, \@dist_matrix);
}

sub parse_matrix {
    my ($self, $fname) = @_;
    
    my $data = { data => [], rows => [], columns => [] };
    my @matrix = map { [split(/\t/, $_)] } split(/\n/, $self->read_file($fname));
    $data->{columns} = shift @matrix;
    shift @{$data->{columns}};
    
    foreach my $row (@matrix) {
        my $r = shift @$row;
        @$row = map {$_ * 1.0} @$row;
        push @{$data->{rows}}, $r;
        push @{$data->{data}}, $row;
    }
    return $data;
}

1;
