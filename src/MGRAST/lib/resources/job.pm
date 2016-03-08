package resources::job;

use strict;
use warnings;
no warnings('once');

use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use List::MoreUtils qw(any uniq);
use Scalar::Util qw(looks_like_number);
use StreamingUpload;

use MGRAST::Abundance;
use MGRAST::Metadata;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "job";
    $self->{job_actions} = {
        reserve  => 1,
        create   => 1,
        submit   => 1,
        resubmit => 1,
        share    => 1,
        public   => 1,
        viewable => 1,
        rename   => 1,
        delete   => 1,
        solr     => 1,
        addproject => 1,
        statistics => 1,
        attributes => 1
    };
    $self->{attributes} = {
        reserve => { "timestamp"     => [ 'date', 'time the metagenome was first reserved' ],
                     "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                     "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                     "kbase_id"      => [ "string", "unique KBase metagenome identifier" ] },
        create => { "timestamp" => [ 'date', 'time the metagenome was first reserved' ],
                    "options"   => [ "string", "job pipeline option string" ],
                    "job_id"    => [ "int", "unique MG-RAST job identifier" ] },
        submit => { "awe_id" => [ "string", "ID of AWE job" ],
                    "log"    => [ "string", "log of sumbission" ] },
        delete => { "deleted" => [ 'boolean', 'the metagenome is deleted' ],
                    "error"   => [ "string", "error message if unable to delete" ] },
        addproject => { "project_id"   => [ "string", "unique MG-RAST project identifier" ],
                        "project_name" => [ "string", "MG-RAST project name" ],
                        "status"       => [ 'string', 'status of action' ] },
        data  => { "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                   "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                   "data"          => [ 'hash', 'key value pairs of job data' ] },
        change => { "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                    "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                    "status"        => [ 'string', 'status of action' ] },
        kb2mg => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of KBase id to MG-RAST id' ] },
        mg2kb => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of MG-RAST id to KBase id' ] }
    };
    $self->{create_param} = {
        'metagenome_id' => ["string", "unique MG-RAST metagenome identifier"],
        'input_id'      => ["string", "shock node id of input sequence file (optional)"],
        'submission'    => ["string", "unique submission id (optional)"]
    };
    my @input_stats = map { substr($_, 0, -4) } grep { $_ =~ /_raw$/ } @{$self->seq_stats};
    map { $self->{create_param}{$_} = ['float', 'sequence statistic'] } grep { $_ !~ /drisee/ } @input_stats;
    map { $self->{create_param}{$_} = ['string', 'pipeline option'] } @{$self->pipeline_opts};
    $self->{create_param}{sequence_type} = [
        "cv", [["WGS", "whole genome shotgun sequenceing"],
               ["Amplicon", "amplicon rRNA sequenceing"],
               ["AmpliconGene", "amplicon gene sequenceing"],
               ["MT", "metatranscriptome sequenceing"]]
    ];
    @{$self->{taxa}} = grep { $_->[0] !~ /strain/ } @{$self->hierarchy->{organism}};
    $self->{ann_ver} = 1;
    
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		            'url' => $self->cgi->url."/".$self->name,
		            'description' => "Resource for creating and querying MG-RAST jobs.",
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
				        { 'name'        => "reserve",
				          'request'     => $self->cgi->url."/".$self->name."/reserve",
				          'description' => "Reserve IDs for MG-RAST job.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{reserve},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {
							                     "kbase_id"  => ['boolean', "if true create KBase ID, default is false."],
							                     "name"      => ["string", "name of metagenome (required)"],
							                     "input_id"  => ["string", "shock node id of input sequence file (optional)"],
							                     "file"      => ["string", "name of sequence file"],
							                     "file_size" => ["string", "byte size of sequence file"],
          							             "file_checksum" => ["string", "md5 checksum of sequence file"] } }
						},
						{ 'name'        => "create",
				          'request'     => $self->cgi->url."/".$self->name."/create",
				          'description' => "Create an MG-RAST job with input reserved ID, sequence stats, and pipeline options.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{create},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => $self->{create_param} }
						},
						{ 'name'        => "submit",
				          'request'     => $self->cgi->url."/".$self->name."/submit",
				          'description' => "Submit a MG-RAST job to AWE pipeline.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{submit},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "input_id" => ["string", "shock node id of input sequence file"] } }
						},
						{ 'name'        => "resubmit",
				          'request'     => $self->cgi->url."/".$self->name."/resubmit",
				          'description' => "Re-submit an existing MG-RAST job to AWE pipeline.",
				          'method'      => "PUT",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{submit},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "awe_id" => ["string", "awe job id of original job"] } }
						},
						{ 'name'        => "share",
				          'request'     => $self->cgi->url."/".$self->name."/share",
				          'description' => "Share metagenome with another user.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "shared"  => ['list', ['string', 'user metagenome shared with']] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "user_id"       => ["string", "unique user identifier to share with"],
							                                 "user_email"    => ["string", "user email to share with"],
							                                 "edit"          => ["boolean", "if true edit rights shared, else (default) view rights only"] } }
						},
						{ 'name'        => "public",
				          'request'     => $self->cgi->url."/".$self->name."/public",
				          'description' => "Change status of metagenome to public.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "public"  => ['boolean', 'the metagenome is public'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"] } }
						},
						{ 'name'        => "viewable",
				          'request'     => $self->cgi->url."/".$self->name."/viewable",
				          'description' => "Change the view state of metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "viewable"  => ['boolean', 'the metagenome is viewable'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "viewable" => ["boolean", "true: make viewable, false: make hidden, default: true"] } }
						},
						{ 'name'        => "rename",
				          'request'     => $self->cgi->url."/".$self->name."/rename",
				          'description' => "Change the name of metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "name" => ["string", "new name of metagenome"] } }
						},
						{ 'name'        => "delete",
				          'request'     => $self->cgi->url."/".$self->name."/delete",
				          'description' => "Delete metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{delete},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
     							                             "reason" => ["string", "reason for deleting metagenome"] } }
						},
						{ 'name'        => "addproject",
				          'request'     => $self->cgi->url."/".$self->name."/addproject",
				          'description' => "Add exisiting MG-RAST job to existing MG-RAST project.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{addproject},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "project_id" => ["string", "unique MG-RAST project identifier"] } }
						},
						{ 'name'        => "statistics",
				          'request'     => $self->cgi->url."/".$self->name."/statistics/{ID}",
				          'description' => "Return current job statistics",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => {},
							                 'required' => { "id" => ["string","unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "statistics",
				          'request'     => $self->cgi->url."/".$self->name."/statistics",
				          'description' => "Add to job statistics",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "statistics"    => ["hash", "key value pairs for new statistics"] } }
						},
						{ 'name'        => "attributes",
				          'request'     => $self->cgi->url."/".$self->name."/attributes/{ID}",
				          'description' => "Return current job attributes",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => {},
							                 'required' => { "id" => ["string","unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "attributes",
				          'request'     => $self->cgi->url."/".$self->name."/attributes",
				          'description' => "Add to job attributes",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
     							                             "attributes"    => ["hash", "key value pairs for new attributes"] } }
						},
						{ 'name'        => "abundance",
				          'request'     => $self->cgi->url."/".$self->name."/abundance/{ID}",
				          'description' => "Get abundances for different annotations",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => { "level"    => ["cv", $self->{taxa}],
				                                             "ann_ver"  => ["int", "version of m5nr annotations"],
                                                             "type"     => ["cv", [["all", "return abundances for all annotations"],
                                                                                   ["organism", "return abundances for organism annotations"],
                                                                                   ["ontology", "return abundances for ontology annotations"],
                                                                                   ["function", "return abundances for function annotations"]] ] },
							                 'required' => { "id" => ["string","unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "solr",
				          'request'     => $self->cgi->url."/".$self->name."/solr",
				          'description' => "Update job data in solr",
				          'method'      => "POST",
				          'type'        => "asynchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "rebuild"       => ["boolean", "re-compute all statistics, default is to not compute if exists"],
							                                 "debug"         => ["boolean", "return solr post data instead of actually posting it"],
     							                             "solr_data"     => ["hash", "key value pairs for solr data"] } }
						},
						{ 'name'        => "kb2mg",
				          'request'     => $self->cgi->url."/".$self->name."/kb2mg",
				          'description' => "Return a mapping of KBase ids to MG-RAST ids",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{kb2mg},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {"ids" => ['list', ['string', 'KBase ids']]} }
						},
						{ 'name'        => "mg2kb",
				          'request'     => $self->cgi->url."/".$self->name."/mg2kb",
				          'description' => "Return a mapping of MG-RAST ids to KBase ids",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{mg2kb},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {"ids" => ['list', ['string', 'MG-RAST ids']]} }
						},
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
        $self->job_data($self->rest->[0], $self->rest->[1]);
    } elsif (exists $self->{job_actions}{ $self->rest->[0] }) {
        $self->job_action($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'kb2mg') || ($self->rest->[0] eq 'mg2kb')) {
        $self->id_lookup($self->rest->[0]);
    } else {
        $self->info();
    }
}

sub job_data {
    my ($self, $type, $mgid) = @_;
    
    my $master = $self->connect_to_datasource();
    # check id format
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if (! $id) {
        $self->return_data( {"ERROR" => "invalid id format: $mgid"}, 400 );
    }
    # check rights
    unless ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for metagenome $mgid"}, 401 );
    }
    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $mgid does not exist"}, 404 );
    }
    $job = $job->[0];
    
    my $data = {};
    if ($type eq "statistics") {
        $data = $job->stats();
    } elsif ($type eq "attributes") {
        $data = $job->data();
    } elsif ($type eq "abundance") {
        MGRAST::Abundance::get_analysis_dbh();
        my $taxa = $self->cgi->param('level') || "";
        my $ann  = $self->cgi->param('type') || "all";
        my $ver  = $self->cgi->param('ann_ver') || $self->{ann_ver};
        
        if (($ann eq "all") || ($ann eq "organism")) {
            if (! $taxa) {
                foreach my $t (@{$self->{taxa}}) {
                    my $other = ($t->[0] eq 'domain') ? 1 : 0;
                    $data->{taxonomy}->{$t->[0]} = MGRAST::Abundance::get_taxa_abundances($job->{job_id}, $t->[0], $other, $ver);
                }
            } elsif ( any {$_->[0] eq $taxa} @{$self->{taxa}} ) {
                my $other = ($taxa eq 'domain') ? 1 : 0;
                $data->{taxonomy}->{$taxa} = MGRAST::Abundance::get_taxa_abundances($job->{job_id}, $taxa, $other, $ver);
            } else {
                return ({"ERROR" => "invalid group_level for organism - valid types are [".join(", ", map {$_->[0]} @{$self->{taxa}})."]"}, 404);
            }
        }
        if (($ann eq "all") || ($ann eq "ontology")) {
            $data->{ontology} = MGRAST::Abundance::get_ontology_abundances($job->{job_id}, $ver);
        }
        if (($ann eq "all") || ($ann eq "function")) {
            $data->{function} = MGRAST::Abundance::get_function_abundances($job->{job_id}, $ver);
        }
        if (scalar(keys %$data) == 0) {
            $self->return_data( {"ERROR" => "invalid job abundance type: $ann"}, 400 );
        }
    } else {
        $self->return_data( {"ERROR" => "invalid job data type: $type"}, 400 );
    }
    
    $self->return_data({
        metagenome_id => 'mgm'.$job->{metagenome_id},
        job_id        => $job->{job_id},
        data          => $data
    });
}

sub job_action {
    my ($self, $action) = @_;
    
    my $master = $self->connect_to_datasource();
    unless ($self->user) {
        $self->return_data( {"ERROR" => "Missing authentication"}, 401 );
    }
    
    my $data = {};
    my $post = $self->get_post_data();
    
    # job does not exist yet
    if ($action eq 'reserve') {
        # get from shock node if given
        if (exists $post->{input_id}) {
            my $nodeid = $post->{input_id};
            eval {
                my $node = $self->get_shock_node($nodeid, $self->token, $self->user_auth);
                $post->{file} = $node->{file}{name};
                $post->{file_size} = $node->{file}{size};
                $post->{file_checksum} = $node->{file}{checksum}{md5};
            };
            if ($@ || (! $post)) {
                $self->return_data( {"ERROR" => "unable to obtain sequence file statistics from shock node ".$nodeid}, 500 );
            }
        }
        my @params = ();
        foreach my $p ('name', 'file', 'file_size', 'file_checksum') {
            if (exists $post->{$p}) {
                push @params, $post->{$p};
            } else {
                $self->return_data( {"ERROR" => "Missing required parameter '$p'"}, 404 );
            }
        }
        my $job = $master->Job->reserve_job_id($self->user, $params[0], $params[1], $params[2], $params[3]);
        unless ($job) {
            $self->return_data( {"ERROR" => "Unable to reserve job id"}, 500 );
        }
        my $mgid = 'mgm'.$job->{metagenome_id};
        $data = { timestamp     => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
                  metagenome_id => $mgid,
                  job_id        => $job->{job_id},
                  kbase_id      => (exists($post->{kbase_id}) && $post->{kbase_id}) ? $self->reserve_kbase_id($mgid): undef
        };
    }
    # we have a job in DB, do something
    else {
        # check id format
        my (undef, $id) = $post->{metagenome_id} =~ /^(mgm)?(\d+\.\d+)$/;
        if (! $id) {
            $self->return_data( {"ERROR" => "invalid id format: ".$post->{metagenome_id}}, 400 );
        }
        # check rights
        unless ($self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome'))) {
            $self->return_data( {"ERROR" => "insufficient permissions for metagenome ".$post->{metagenome_id}}, 401 );
        }
        # get data
        my $job = $master->Job->get_objects( {metagenome_id => $id} );
        unless ($job && @$job) {
            $self->return_data( {"ERROR" => "id ".$post->{metagenome_id}." does not exist"}, 404 );
        }
        $job = $job->[0];
        
        if ($action eq 'create') {
            # get from shock node if given
            if (exists $post->{input_id}) {
                my $nodeid = $post->{input_id};
                eval {
                    my $node = $self->get_shock_node($nodeid, $self->token, $self->user_auth);
                    # pull from stats_info and pipeline_info in attributes
                    foreach my $x (('stats_info', 'pipeline_info')) {
                        if (exists($node->{attributes}{$x}) && ref($node->{attributes}{$x})) {
                            foreach my $k (keys %{$node->{attributes}{$x}}) {
                                # only add values that are not already given
                                if (! exists($post->{$k})) {
                                    $post->{$k} = $node->{attributes}{$x}{$k};
                                }
                            }
                        }
                    }
                };
                delete $post->{input_id};
                if ($@ || (! $post)) {
                    $self->return_data( {"ERROR" => "unable to obtain sequence file info from shock node ".$nodeid}, 500 );
                }
            }
            # fix assembly defaults
            if (exists($post->{sequencing_method_guess}) && ($post->{sequencing_method_guess} eq "assembled")) {
                $post->{assembled}    = 'yes';
                $post->{filter_ln}    = 'no';
                $post->{filter_ambig} = 'no';
                $post->{dynamic_trim} = 'no';
                $post->{dereplicate}  = 'no';
                $post->{bowtie}       = 'no';
            }
            # set pipeline defaults if missing
            foreach my $key (@{$self->pipeline_opts}) {
                if (exists($self->pipeline_defaults->{$key}) && (! exists($post->{$key}))) {
                    $post->{$key} = $self->pipeline_defaults->{$key};
                }
            }
            if ($post->{file_type} eq 'fasta') {
                $post->{file_type} = 'fna';
            }
            # fix booleans
            foreach my $key (keys %$post) {
                if ($post->{$key} eq 'yes') {
                    $post->{$key} = 1;
                } elsif ($post->{$key} eq 'no') {
                    $post->{$key} = 0;
                }
            }
            # check params
            delete $post->{metagenome_id};
            foreach my $key (keys %{$self->{create_param}}) {
                if (($key eq 'metagenome_id') || ($key eq 'input_id') || ($key eq 'submission')) {
                    next;
                }
                if (! exists($post->{$key})) {
                    $self->return_data( {"ERROR" => "Missing required parameter '$key'"}, 404 );
                }
            }
            # calculate length trim
        	$post->{max_ln} = int($post->{average_length} + ($post->{filter_ln_mult} * $post->{standard_deviation_length}));
        	$post->{min_ln} = int($post->{average_length} - ($post->{filter_ln_mult} * $post->{standard_deviation_length}));
        	if ($post->{min_ln} < 1) {
        	    $post->{min_ln} = 1;
        	}
            # create job
            $job  = $master->Job->initialize($self->user, $post, $job);
            $data = {
                timestamp => $job->{created_on},
                options   => $job->{options},
                job_id    => $job->{job_id}
            };
        } elsif (($action eq 'submit') || ($action eq 'resubmit')) {
            my $cmd;
            if ($action eq 'resubmit') {
                $cmd = $Conf::resubmit_to_awe." --job_id ".$job->{job_id}." --awe_id ".$post->{awe_id}." --shock_url ".$Conf::shock_url." --awe_url ".$Conf::awe_url;
            } else {
                my $jdata = $job->data();
                $cmd = $Conf::submit_to_awe." --job_id ".$job->{job_id}." --input_node ".$post->{input_id}." --shock_url ".$Conf::shock_url." --awe_url ".$Conf::awe_url;
                if (exists $jdata->{submission}) {
                    $cmd .= " --submit_id ".$jdata->{submission};
                }
            }
            my @log = `$cmd 2>&1`;
            chomp @log;
            my @err = grep { $_ =~ /^ERROR/ } @log;
            if (@err) {
                $self->return_data( {"ERROR" => join("\n", @log)}, 400 );
            }
            my @aweid = grep { $_ =~ /^awe job/ } @log;
            my $aid   = "";
            if (@aweid) {
                (undef, $aid) = split(/\t/, $aweid[0]);
            }
            if ($aid) {
                $data = {
                    awe_id => $aid,
                    log    => join("\n", @log)
                };
            } else {
                $self->return_data( {"ERROR" => "Unknown error, missing AWE job ID:\n".join("\n", @log)}, 500 );
            }
        } elsif ($action eq 'share') {
            # get user to share with
            my $share_user = undef;
            if ($post->{user_id}) {
                my (undef, $uid) = $post->{user_id} =~ /^(mgu)?(\d+)$/;
                $share_user = $master->User->init({ _id => $uid });
            } elsif ($post->{user_email}) {
                $share_user = $master->User->init({ email => $post->{user_email} });
            } else {
                $self->return_data( {"ERROR" => "Missing required parameter user_id or user_email"}, 404 );
            }
            unless ($share_user && ref($share_user)) {
                $self->return_data( {"ERROR" => "Unable to find user to share with"}, 404 );
            }
            # share rights if not owner
            unless ($share_user->_id eq $job->owner->_id) {
                my @rights = ('view');
                if ($post->{edit}) {
                    push @rights, 'edit';
                }
                foreach my $name (@rights) {
                    my $right_query = {
                        name => $name,
                	    data_type => 'metagenome',
                	    data_id => $job->metagenome_id,
                	    scope => $share_user->get_user_scope
                    };
                    unless(scalar( @{$master->Rights->get_objects($right_query)} )) {
                        $right_query->{granted} = 1;
                        $right_query->{delegated} = 1;
                        my $right = $master->Rights->create($right_query);
            	        unless (ref $right) {
            	            $self->return_data( {"ERROR" => "Failed to create ".$name." right in the user database, aborting."}, 500 );
            	        }
                    }
                }
            }
            # get all who can view / skip owner
            my $view_query = {
                name => 'view',
        	    data_type => 'metagenome',
        	    data_id => $job->metagenome_id
            };
            my $shared = [];
            my $owner_user = $master->User->init({ _id => $job->owner->_id });
            my $view_rights = $master->Rights->get_objects($view_query);
            foreach my $vr (@$view_rights) {
                next if (($owner_user->get_user_scope->_id eq $vr->scope->_id) || ($vr->scope->name =~ /^token\:/));
                push @$shared, $vr->scope->name_readable;
            }
            $data = { shared => $shared };
        } elsif ($action eq 'public') {
            # update shock nodes
            my $nodes = $self->get_shock_query({'type' => 'metagenome', 'id' => 'mgm'.$job->{metagenome_id}}, $self->mgrast_token);
            foreach my $n (@$nodes) {
                my $attr = $n->{attributes};
                $attr->{status} = 'public';
                $self->update_shock_node($n->{id}, $attr, $self->mgrast_token);
                $self->edit_shock_public_acl($n->{id}, $self->mgrast_token, 'put', 'read');
            }
            # update db
            $job->public(1);
            $data = { public => $job->public ? 1 : 0 };
        } elsif ($action eq 'viewable') {
            my $state = 1;
            if (exists($post->{viewable}) && defined($post->{viewable}) && (! $post->{viewable})) {
                $state = 0;
            }
            # update db
            $job->viewable($state);
            $data = { viewable => $job->viewable ? 1 : 0 };
        } elsif ($action eq 'rename') {
            $data = {
                metagenome_id => 'mgm'.$job->metagenome_id,
                job_id        => $job->job_id
            };
            if ($post->{name}) {
                $job->name($post->{name});
                $data->{status} = 1;
            } else {
                $data->{status} = 0;
            }
        } elsif ($action eq 'delete') {
            # Auf Wiedersehen!
            my $reason = $post->{reason} || "";
            my ($status, $message) = $job->user_delete($self->user, $reason);
            $data = {
                deleted => $status,
                error   => $message
            };
        } elsif ($action eq 'addproject') {
            # check id format
            my (undef, $pid) = $post->{project_id} =~ /^(mgp)?(\d+)$/;
            if (! $pid) {
                $self->return_data( {"ERROR" => "invalid id format: ".$post->{project_id}}, 400 );
            }
            # check rights
            unless ($self->user->has_right(undef, 'edit', 'project', $pid) || $self->user->has_star_right('edit', 'project')) {
                $self->return_data( {"ERROR" => "insufficient permissions for project ".$post->{project_id}}, 401 );
            }
            # get data
            my $project = $master->Project->get_objects( {id => $pid} );
            unless ($project && @$project) {
                $self->return_data( {"ERROR" => "id ".$post->{project_id}." does not exists"}, 404 );
            }
            $project = $project->[0];
            # add it
            my $status = $project->add_job($job);
            $data = {
                project_id   => "mgp".$project->{id},
                project_name => $project->{name},
                status       => $status
            };
        } elsif (($action eq "statistics") || ($action eq "attributes")) {
            my $status = $job->set_job_data($action, $post->{$action});
            $data = {
                metagenome_id => 'mgm'.$job->metagenome_id,
                job_id        => $job->job_id,
                status        => $status
            };
        } elsif ($action eq 'solr') {
            my $rebuild = $post->{rebuild} ? 1 : 0;
            my $sdata   = $post->{solr_data} || {};
            my $unique  = $self->url_id . md5_hex($self->json->encode($post));
            
            # asynchronous call, fork the process and return the process id.
            # caching is done with shock, not memcache
            my $attr = {
                type => "temp",
                url_id => $unique,
                owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous"
            };
            # already cashed in shock - say submitted in case its running
            my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
            if ($nodes && (@$nodes > 0)) {
                $self->return_data({"status" => "submitted", "id" => $nodes->[0]->{id}, "url" => $self->cgi->url."/status/".$nodes->[0]->{id}});
            }
            # need to create new node and fork
            my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "7D");
            my $pid = fork();
            # child - get data and POST it
            if ($pid == 0) {
                # create DB handels inside child as they break on fork
                my $mddb = MGRAST::Metadata->new();
                MGRAST::Abundance::get_analysis_dbh();
                my $jobj = $master->Job->get_objects( {metagenome_id => $id} );
                $job = $jobj->[0];
                my $jdata = $job->data();
                my $jobid = $job->{job_id};
                my $mgid  = 'mgm'.$job->{metagenome_id};
                
                close STDERR;
                close STDOUT;
                open(DEBUG, ">/MG-RAST/site/CGI/Tmp/solr.debug");
                # solr data
                my $solr_data = {
                    job                => int($jobid),
                    id                 => $mgid,
                    id_sort            => $mgid,
                    status             => $job->{public} ? 'public' : 'private',
                    status_sort        => $job->{public} ? 'public' : 'private',
                    created            => solr_time_format($job->{created_on}),
                    created_sort       => solr_time_format($job->{created_on}),
                    name               => $job->{name},
                    name_sort          => $job->{name},
                    sequence_type      => $job->{sequence_type},
                    sequence_type_sort => $job->{sequence_type},
                    seq_method         => $jdata->{sequencing_method_guess},
                    seq_method_sort    => $jdata->{sequencing_method_guess},
                    version            => $self->{ann_ver},
                    metadata           => "",
                    md5                => []
                };
                # md5s
                print DEBUG "md5 data\n" if $post->{debug};
                eval {
                    my $md5_stuff = [ map {$_->[0]} @{MGRAST::Abundance::get_md5sum_abundance($jobid, $self->{ann_ver})} ];
                    $solr_data->{md5} = $md5_stuff;
                };
                if ($@) { print DEBUG "eval: ".$@; }
                # project - from jobdb
                print DEBUG "project data\n" if $post->{debug};
                eval {
    	            my $proj = $job->primary_project;
    	            if ($proj->{id}) {
    	                $solr_data->{project_id}        = "mgp".$proj->{id};
    	                $solr_data->{project_id_sort}   = "mgp".$proj->{id};
    	                $solr_data->{project_name}      = $proj->{name};
    	                $solr_data->{project_name_sort} = $proj->{name};
                    }
    	        };
    	        if ($@) { print DEBUG "eval: ".$@; }
                # statistics - from postdata or jobdb
                print DEBUG "seqstats data\n" if $post->{debug};
                eval {
                    my $seq_stats = exists($sdata->{sequence_stats}) ? $sdata->{sequence_stats} : $job->stats();
                    while (my ($key, $val) = each(%$seq_stats)) {
                        if (looks_like_number($val)) {
                            if ($key =~ /count/ || $key =~ /min/ || $key =~ /max/) {
                                $solr_data->{$key.'_l'} = $val * 1;
                            } else {
                                $solr_data->{$key.'_d'} = $val * 1.0;
                            }
                        }
                    }
                };
                if ($@) { print DEBUG "eval: ".$@; }
                # annotations - from postdata or mg stats (if not rebuild) or from analysis db
                my $mg_stats = {};
                # function
                print DEBUG "function data\n" if $post->{debug};
                eval {
                    if (exists($sdata->{function}) && $sdata->{function}) {
                        $solr_data->{function} = $sdata->{function};
                    } elsif ($rebuild) {
                        $solr_data->{function} = [ map {$_->[0]} @{MGRAST::Abundance::get_function_abundances($jobid, $self->{ann_ver})} ];
                    } else {
                        unless (exists $mg_stats->{function}) {
                            $mg_stats = $self->metagenome_stats_from_shock($solr_data->{id});
                        }
                        if (exists $mg_stats->{function}) {
                            $solr_data->{function} = [ map {$_->[0]} @{$mg_stats->{function}} ];
                        } else {
                            $solr_data->{function} = [ map {$_->[0]} @{MGRAST::Abundance::get_function_abundances($jobid, $self->{ann_ver})} ];
                        }
                    }
                };
                if ($@) { print DEBUG "eval: ".$@; }
                # organism - species
                print DEBUG "organism data\n" if $post->{debug};
                eval {
                    if (exists($sdata->{organism}) && $sdata->{organism}) {
                        $solr_data->{organism} = $sdata->{organism};
                    } elsif ($rebuild) {
                        $solr_data->{organism} = [ map {$_->[0]} @{MGRAST::Abundance::get_taxa_abundances($jobid, 'species', 0, $self->{ann_ver})} ];
                    } else {
                        unless (exists $mg_stats->{taxonomy}) {
                            $mg_stats = $self->metagenome_stats_from_shock($solr_data->{id});
                        }
                        if (exists($mg_stats->{taxonomy}) && exists($mg_stats->{taxonomy}{species}) && $mg_stats->{taxonomy}{species}) {
                            $solr_data->{organism} = [ map {$_->[0]} @{$mg_stats->{taxonomy}{species}} ];
                        } else {
                            $solr_data->{organism} = [ map {$_->[0]} @{MGRAST::Abundance::get_taxa_abundances($jobid, 'species', 0, $self->{ann_ver})} ];
                        }
                    }
                };
                if ($@) { print DEBUG "eval: ".$@; }
                # mixs metadata - from jobdb
                print DEBUG "mixs data\n" if $post->{debug};
                eval {
                    my $mixs = $mddb->get_job_mixs($job);
                    while (my ($key, $val) = each(%$mixs)) {
                        if ($val) {
                            $solr_data->{$key} = $val;
                            $solr_data->{$key.'_sort'} = $val;
                        }
                    }
                };
                if ($@) { print DEBUG "eval: ".$@; }
                # full metadata - from jobdb
                print DEBUG "mixs data\n" if $post->{debug};
                eval {
                    my $mdata = $mddb->get_jobs_metadata_fast([$jobid])->{$jobid};
                    foreach my $cat (('project', 'sample', 'env_package', 'library')) {
                        eval {
                            if (exists($mdata->{$cat}) && $mdata->{$cat}{id} && $mdata->{$cat}{name} && $mdata->{$cat}{data}) {
                                $solr_data->{$cat.'_id'}      = $mdata->{$cat}{id};
                                $solr_data->{$cat.'_id_sort'} = $mdata->{$cat}{id};
                                $solr_data->{$cat.'_name'}    = $mdata->{$cat}{name};
                                my $concat = join(", ", grep { $_ && ($_ ne " - ") } values %{$mdata->{$cat}{data}});
                                $solr_data->{$cat}      = $concat;
                                $solr_data->{metadata} .= ", ".$concat;
                            }
                        };
                    }
                };
                if ($@) { print DEBUG "eval: ".$@; }
                
                # get content
                print DEBUG "solr command\n" if $post->{debug};
                my $filename = $jobid.".".time.'.solr.json';
                my $solr_str = $self->json->encode({
                    delete => { id => $mgid },
                    commit => { expungeDeletes => "true" },
                    add    => { doc => $solr_data }
                });
                
                # POST to solr
                my $err = "";
                if (! $post->{debug}) {
                    my $solr_file = $Conf::temp."/".$filename;
                    open(SOLR, ">$solr_file") or die "Couldn't open file: $!";
                    print SOLR $solr_str;
                    close(SOLR);
                    $err = $self->solr_post($solr_file);
                }
                
                # POST to shock, triggers end of asynch action
                print DEBUG "shock post\n" if $post->{debug};
                eval {
                    if ($err) {
                        $solr_str = qq({"ERROR": "$err", "STATUS": 500});
                    }
                    $self->put_shock_file($filename, $solr_str, $node->{id}, $self->mgrast_token, 1);
                };
                if ($@) { print DEBUG "eval: ".$@; }
                exit 0;
            }
            # parent - end html session
            else {
                $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->cgi->url."/status/".$node->{id}});
            }
        }
    }
    
    $self->return_data($data);
}

sub solr_post {
    my ($self, $solr_file) = @_;
    
    # post commands and data
    my $post_url = $Conf::job_solr."/".$Conf::job_collect."/update/json?commit=true";
    my $err = "";
    my $req = StreamingUpload->new(
        POST => $post_url,
        path => $solr_file,
        headers => HTTP::Headers->new(
            'Content-Type' => 'application/json',
            'Content-Length' => -s $solr_file,
        )
    );
    $self->agent->timeout(7200);
    my $response = $self->agent->request($req);
    if ($response->{"_msg"} ne 'OK') {
        my $content = $response->{"_content"};
        $err = "solr POST failed: ".$content;
    }
    return $err;
}

sub id_lookup {
    my ($self, $action) = @_;
    
    my $data = {};
    my $post = $self->get_post_data();
    unless (exists($post->{ids}) && (@{$post->{ids}} > 0)) {
        $self->return_data( {"ERROR" => "No IDs submitted"}, 404 );
    } 
    
    if ($action eq 'kb2mg') {
        my $result = $self->kbase_idserver('kbase_ids_to_external_ids', [$post->{ids}]);
        map { $data->{$_} = $result->[0]->{$_}->[1] } keys %{$result->[0]};
    } elsif ($action eq 'mg2kb') {
        my $result = $self->kbase_idserver('external_ids_to_kbase_ids', ['MG-RAST', $post->{ids}]);
        map { $data->{$_} = $result->[0]->{$_} } keys %{$result->[0]};
    }
    
    $self->return_data({'data' => $data, 'found' => scalar(keys %$data)});
}

sub reserve_kbase_id {
    my ($self, $mgid) = @_;
    
    my $result = $self->kbase_idserver('register_ids', ["kb|mg", "MG-RAST", [$mgid]]);
    unless (exists($result->[0]->{$mgid}) && $result->[0]->{$mgid}) {
        $self->return_data( {"ERROR" => "Unable to reserve KBase id for $mgid"}, 500 );
    }
    return $result->[0]->{$mgid};
}

sub solr_time_format {
    my ($dt) = @_;
    if ($dt =~ /^(\d{4}\-\d\d\-\d\d)[ T](\d\d\:\d\d\:\d\d)/) {
        $dt = $1.'T'.$2.'Z';
    } elsif ($dt =~ /^(\d{4}\-\d\d\-\d\d)/) {
        $dt = $1.'T00:00:00Z'
    }
    return $dt;
}

1;
