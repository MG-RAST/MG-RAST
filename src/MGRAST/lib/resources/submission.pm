package resources::submission;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use Digest::MD5 qw(md5_hex md5_base64);
use Data::Dumper;
use DateTime::Format::ISO8601;
use Template;

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "submission";
    $self->{param_file} = "submission_parameters.json";
    $self->{submit_params} = {
        # inbox action options
        "debug"          => [ "boolean", "if true return workflow document instead of submitting"],
        "project_name"   => [ "string", "unique MG-RAST project name" ],
        "project_id"     => [ "string", "unique MG-RAST project identifier" ],
        "metadata_file"  => [ "string", "RFC 4122 UUID for metadata file" ],
        "seq_files"      => [ "list", ["string", "RFC 4122 UUID for sequence file"] ],
        "multiplex_file" => [ "string", "RFC 4122 UUID for file to demultiplex" ],
        "barcode_file"   => [ "string", "RFC 4122 UUID for barcode mapping file" ],
        "pair_file_1"    => [ "string", "RFC 4122 UUID for pair 1 file" ],
        "pair_file_2"    => [ "string", "RFC 4122 UUID for pair 2 file" ],
        "index_file"     => [ "string", "RFC 4122 UUID for index (barcode) file" ],
        "mg_name"        => [ "string", "name of metagenome for pair-join"],
        "rc_index"       => [ "boolean", "If true barcodes in index file are reverse compliment of mapping file, default is false" ],
        "retain"         => [ "boolean", "If true retain non-overlapping sequences, default is false" ],
        # pipeline flags
        "assembled"    => [ "boolean", "if true sequences are assembeled, default is false" ],
        "filter_ln"    => [ "boolean", "if true run sequence length filtering, default is true" ],
        "filter_ambig" => [ "boolean", "if true run sequence ambiguous bp filtering, default is true" ],
        "dynamic_trim" => [ "boolean", "if true run qual score dynamic trimmer, default is true" ],
        "dereplicate"  => [ "boolean", "if true run dereplication, default is true" ],
        "bowtie"       => [ "boolean", "if true run bowtie screening, default is true" ],
        # pipeline options
        "max_ambig" => [ "int", "maximum ambiguous bps to allow through per sequence, default is 5" ],
        "max_lqb"   => [ "int", "maximum number of low-quality bases per read, default is 5" ],
        "min_qual"  => [ "int", "quality threshold for low-quality bases, default is 15" ],
        "filter_ln_mult" => [ "float", "sequence length filtering multiplier, default is 2.0" ],
        "screen_indexes" => [ "cv", [["h_sapiens", "Homo sapiens (default)"],
                                     ["a_thaliana", "Arabidopsis thaliana"],
                                     ["b_taurus", "Bos taurus"],
                                     ["d_melanogaster", "Drosophila melanogaster"],
                                     ["e_coli", "Escherichia coli"],
                                     ["m_musculus", "Mus musculus"],
                                     ["r_norvegicus", "Rattus norvegicus"],
                                     ["s_scrofa", "Sus scrofa"]] ],
        "priority" => [ "cv", [["never", "Data will stay private (default)"],
                               ["immediately", "Data will be publicly accessible immediately after processing completion"],
                               ["3months", "Data will be publicly accessible after 3 months"],
                               ["6months", "Data will be publicly accessible after 6 months"],
                               ["date", "Data will be publicly accessible eventually"]] ]
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
        'description' => "submission runs input through a series of validation and pre-processing steps, then submits the results to the MG-RAST anaylsis pipeline",
        'type' => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests' => [
            { 'name'        => "info",
              'request'     => $self->cgi->url."/".$self->name,
              'description' => "Returns description of parameters and attributes.",
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {}
              }
            },
            { 'name'        => "list",
              'request'     => $self->cgi->url."/".$self->name."/list",
              'description' => "list all submissions by user",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'user'        => [ 'string', "user id" ],
                  'timestamp'   => [ 'string', "timestamp for return of this query" ],
                  'submissions' => [ 'list', ['object', [
                                        { 'id' => ['string', "RFC 4122 UUID for submission"],
                                          'type' => ['string', "type of submission"],
                                          'status' => ['string', "status of submission"],
                                          'timestamp' => ['string', "timestamp of submission creation"] },
                                        "submission object" ]]
                                   ]
              },
              'parameters'  => {
                  'options'  => { "all" => [ "boolean", "if true and user is admin, list all submissions, default is off" ] },
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "status",
              'request'     => $self->cgi->url."/".$self->name."/{UUID}",
              'description' => "get status of submission from ID",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => { "full" => [ "boolean", "if true show full document of running jobs, default is summary" ] },
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for submission" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "delete",
              'request'     => $self->cgi->url."/".$self->name."/{UUID}",
              'description' => "delete all files and running processes for given submission ID",
              'method'      => "DELETE",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => { "full" => [ "boolean", "if true delete all files and metagenomes in mgrast for submission, default just data in inbox" ] },
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for submission" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "submit",
              'request'     => $self->cgi->url."/".$self->name."/submit",
              'description' => "start new submission",
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => $self->{submit_params}
              }
            }
        ]
    };
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    # must have auth
    if ($self->user) {
        if (scalar(@{$self->rest}) == 0) {
            $self->info();
        } elsif ($self->rest->[0] eq 'list') {
            $self->list();
        } elsif ($self->method eq 'GET') {
            $self->status($self->rest->[0]);
        } elsif ($self->method eq 'DELETE') {
            $self->delete($self->rest->[0]);
        } elsif (($self->method eq 'POST') && ($self->rest->[0] eq 'submit')) {
            $self->submit();
        }
    }
    $self->info();
}

sub list {
    my ($self) = @_;
    
    # get all submission jobs
    my $all = $self->cgi->param('all') ? 1 : 0;
    my $is_admin = ($self->user->is_admin('MGRAST') && $all) ? 1 : 0;
    my $user_id = 'mgu'.$self->user->_id;
    my $submit_data = [];
    my $submit_query = { "info.pipeline" => 'submission'};
    if (! $is_admin) {
        $submit_query->{"info.user"} = $user_id;
    }
    my $submit_jobs = $self->get_awe_query($submit_query, $self->token, $self->user_auth);
    
    # get / return summary
    foreach my $job (@{$submit_jobs->{data}}) {
        if ($job->{info}{userattr}{submission}) {
            my $sdata = {
                id => $job->{info}{userattr}{submission},
                type => $job->{info}{description},
                status => $job->{state},
                timestamp => $job->{info}{submittime}
            };
            if ($is_admin) {
                $sdata->{user} = $job->{info}{user};
            }
            push @$submit_data, $sdata;
        }
    }
    $self->return_data({
        user        => $user_id,
        timestamp   => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
        submissions => $submit_data
    });
}

sub status {
    my ($self, $uuid) = @_;
    
    my $full = $self->cgi->param('full') ? 1 : 0;
    my $response = {
        id         => $uuid,
        user       => 'mgu'.$self->user->_id,
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    my $is_admin = $self->user->is_admin('MGRAST') ? 1 : 0;
    
    # get data
    my $nodes  = $self->submission_nodes($uuid, 1, $is_admin);
    my $jobs   = $self->submission_jobs($uuid, 1, $is_admin);
    my $submit = $jobs->{submit};
    my $pnode  = $self->get_param_node($submit);

    if ((! $submit) || (! $pnode)) {
        $response->{status} = "No submission exists for given ID";
        $self->return_data($response);
    } elsif ($submit->{state} eq 'deleted') {
        $response->{status} = "Deleted submission";
        $self->return_data($response);
    }
    
    # get submission info - parameters file
    my $info = {};
    eval {
        my ($info_text, $err) = $self->get_shock_file($pnode, undef, $is_admin ? $self->{mgrast_token} : $self->token, undef, $self->user_auth);
        if ($err) {
            $self->return_data( {"ERROR" => "Unable to fetch Shock file $pnode: $err"}, 500 );
        }
        $info = $self->json->decode($info_text);
    };
    if (! $info) {
        $response->{status} = "Broken submission, missing parameter data $pnode";
        $self->return_data($response);
    }
    
    # get submission results - either stdout from workunit if running or from shock if done
    my $report = $self->get_task_report($submit->{tasks}[-1], 'stdout', $self->token, $self->user_auth);
    my $result = $self->parse_submit_output($report);
    
    # set output
    my $output = {
        type => $info->{input}{type}, # submission type
        submission => $info,          # submission inputs / paramaters
        results => $result,           # info on success or failer of sequences
        preprocessing => [],          # info of preprocessing pipeline stages
        metagenomes => [],            # info of analysis pipeline stages per metagenome
        timestamp => $submit->{info}{submittime}  # submission time
    };
    
    # status of preprocessing workflow
    foreach my $task (@{$submit->{tasks}}) {
        my $summery = {
            stage => $task->{cmd}{description},
            inputs => [ map { $_->{filename} } @{$task->{inputs}} ],
            status => $task->{state}
        };
        if ($task->{state} eq 'suspend') {
            $summery->{error} = $self->get_task_report($task, 'stderr', $self->token, $self->user_auth) || 'unknown error';
        }
        push @{$output->{preprocessing}}, $summery;
    }
    
    # check children workflows - get current stage
    foreach my $pj (@{$jobs->{pipeline}}) {
        # get current runtime
        my $runtime = 0;
        foreach my $pjt (@{$pj->{tasks}}) {
            if ($pjt->{starteddate} eq "0001-01-01T00:00:00Z") {
                next; # task hasnt started yet, no runtime
            }
            my $start = DateTime::Format::ISO8601->parse_datetime($pjt->{starteddate})->epoch();
            # if still running just get current time
            my $end = ($pjt->{completeddate} eq "0001-01-01T00:00:00Z") ? time : DateTime::Format::ISO8601->parse_datetime($pjt->{completeddate})->epoch();
            # ignore screwy stuff
            my $total = (($end - $start) < 0) ? 0 : $end - $start;
            $runtime += $total;
        }
        if ($full) {
            $pj->{info}{runtime} = $runtime;
            push @{$output->{metagenomes}}, $pj;
        } else {
            my $tasknum = scalar(@{$pj->{tasks}});
            my $summery = {
                id => $pj->{info}{userattr}{id},
                job => $pj->{id},
                name => $pj->{info}{userattr}{name},
                status => $pj->{state},
                submittime => $pj->{info}{submittime},
                completedtime => $pj->{info}{completedtime},
                runtime => $runtime,
                totaltasks => $tasknum,
                completedtasks => $tasknum - $pj->{remaintasks}
            };
            push @{$output->{metagenomes}}, $summery;
        }
    }
    
    $response->{status} = $output;
    $self->return_data($response);
}

sub delete {
    my ($self, $uuid) = @_;
    
    my $full  = $self->cgi->param('full') ? 1 : 0;
    my $nodes = $self->submission_nodes($uuid);
    my $jobs  = $self->submission_jobs($uuid, $full);
    
    # delete inbox nodes
    foreach my $n (@{$nodes->{inbox}}) {
        if ($n->{id}) {
            $self->delete_shock_node($n->{id}, $self->token, $self->user_auth);
        }
    }
    
    # delete inbox workflows
    if ($jobs->{submit} && $jobs->{submit}{id}) {
        $self->delete_awe_job($jobs->{submit}{id}, $self->token, $self->user_auth);
    }
    
    # delete metagenomes if exist: nodes / workflows / job in mysql
    if ($full && (@{$jobs->{pipeline}} > 0)) {
        my $master = $self->connect_to_datasource();
        foreach my $j (@{$jobs->{pipeline}}) {
            next unless ($j->{info}{userattr} && $j->{info}{userattr}{id});
            my ($id) = $j->{info}{userattr}{id} =~ /^mgm(\d+\.\d+)$/;
            next unless ($id);
            if ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome')) {
                my $job = $master->Job->get_objects( {metagenome_id => $id} );
                if ($job && @$job) {
                    $job = $job->[0];
                    $job->user_delete($self->user, "deleted by user for submission ".$uuid);
                }
            }
        }
    }
    
    $self->return_data({
        id         => $uuid,
        user       => 'mgu'.$self->user->_id,
        status     => "successfully deleted",
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub submit {
    my ($self) = @_;
    
    my $uuid = $self->uuidv4();
    my $post = $self->get_post_data([ keys %{$self->{submit_params}} ]);
    # inbox action options
    my $debug          = $post->{'debug'} ? 1 : 0;
    my $project_name   = $post->{'project_name'} || "";
    my $project_id     = $post->{'project_id'} || "";
    my $metadata_file  = $post->{'metadata_file'} || "";
    my $multiplex_file = $post->{'multiplex_file'} || "";
    my $barcode_file   = $post->{'barcode_file'} || "";
    my $pair_file_1    = $post->{'pair_file_1'} || "";
    my $pair_file_2    = $post->{'pair_file_2'} || "";
    my $index_file     = $post->{'index_file'} || "";
    my $mg_name        = $post->{'mg_name'} || "";
    my $rc_index       = $post->{'rc_index'} ? 1 : 0;
    my $retain         = $post->{'retain'} ? 1 : 0;
    my $seq_files      = $post->{'seq_files'} || [];
    if ($seq_files && (! ref($seq_files))) {
        $seq_files = [$seq_files];
    }
    # pipeline parameters
    my $pipeline_params = {
        # flags
        'assembled'     => $post->{'assembled'} ? 1 : 0,
        'filter_ln'     => $post->{'filter_ln'} ? 1 : 0,
        'filter_ambig'  => $post->{'filter_ambig'} ? 1 : 0,
        'dynamic_trim'  => $post->{'dynamic_trim'} ? 1 : 0,
        'dereplicate'   => $post->{'dereplicate'} ? 1 : 0,
        'bowtie'        => $post->{'bowtie'} ? 1 : 0,
        # options
        'priority'       => $post->{'priority'} || "never",
        'max_ambig'      => $post->{'max_ambig'} || 5,
        'max_lqb'        => $post->{'max_lqb'} || 5,
        'min_qual'       => $post->{'min_qual'} || 15,
        'filter_ln_mult' => $post->{'filter_ln_mult'} || 2.0,
        'screen_indexes' => $post->{'screen_indexes'} || "h_sapiens"
    };
    
    my $input = {};
    my $project_obj  = undef;
    my $metadata_obj = undef;
    my $md_json_node = undef;
    my $user_id  = 'mgu'.$self->user->_id;
    my $response = {
        id         => $uuid,
        user       => $user_id,
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    
    # process metadata
    if ($metadata_file) {
        # validate / extract barcodes if exist
        # $uuid, $is_inbox, $extract_barcodes, $auth, $authPrefix, $submit_id
        my ($is_valid, $mdata, $log, $bar_id, $bar_count, $json_node) = $self->metadata_validation($metadata_file, 1, 1, $self->token, $self->user_auth, $uuid);
        unless ($is_valid) {
            $response->{status} = "invalid metadata";
            $response->{error} = ($mdata && (@$mdata > 0)) ? $mdata : $log;
            $self->return_data($response);
        }
        $project_name = $mdata->{data}{project_name}{value};
        $metadata_obj = $mdata;
        $md_json_node = $json_node;
        # use extracted barcodes if mutiplex file
        if ($bar_id && ($bar_count > 1) && $multiplex_file && (! $barcode_file)) {
            $barcode_file = $bar_id;
        }
    }
    
    # check combinations
    if (($pair_file_1 && (! $pair_file_2)) || ($pair_file_2 && (! $pair_file_1))) {
        $self->return_data( {"ERROR" => "Must include pair_file_1 and pair_file_2 together to merge pairs"}, 400 );
    } elsif (($multiplex_file && (! $barcode_file)) || ($barcode_file && (! $multiplex_file))) {
        $self->return_data( {"ERROR" => "Must include multiplex_file and barcode_file together to demultiplex"}, 400 );
    } elsif (! ($pair_file_1 || $multiplex_file || (@$seq_files > 0))) {
        $self->return_data( {"ERROR" => "No sequence files provided"}, 400 );
    }
    
    # get project if exists from name or id
    if ($project_id) {
        my (undef, $pid) = $project_id =~ /^(mgp)?(\d+)$/;
        if (! $pid) {
            $self->return_data( {"ERROR" => "invalid project id format: ".$project_id}, 400 );
        }
        $project_id = $pid;
    }

    my $master = $self->connect_to_datasource();
    my $pquery = $project_name ? {name => $project_name} : ($project_id ? {id => $project_id} : undef);

    if ($pquery) {
        my $projects = $master->Project->get_objects($pquery);
        if (scalar(@$projects) && $self->user->has_right(undef, 'edit', 'project', $projects->[0]->id)) {
            $project_obj = $projects->[0];
            unless ($project_name) {
                $project_name = $project_obj->{name};
            }
        }
    }
    # make project
    if ((! $project_obj) && $project_name) {
      my $p = $master->Project->get_objects({ name => $project_name });
      if (scalar(@$p)) {
	$self->return_data( {"ERROR" => "This project name is already taken. Please choose a different name."}, 400 );
      } else {
	$project_obj = $master->Project->create_project($self->user, $project_name);
      }
    }
    # verify it worked
    unless ($project_obj) {
        $self->return_data( {"ERROR" => "Missing project information, must have one of metadata_file, project_id, or project_name"}, 400 );
    }
    
    # figure out pre-pipeline workflow
    my @submit = ();
    my $tasks = [];
    if ($pair_file_1 && $pair_file_2 && $index_file && $barcode_file) {
        $self->add_submission($pair_file_1, $uuid, $self->token, $self->user_auth);
        $self->add_submission($pair_file_2, $uuid, $self->token, $self->user_auth);
        $self->add_submission($index_file, $uuid, $self->token, $self->user_auth);
        $self->add_submission($barcode_file, $uuid, $self->token, $self->user_auth);
        $input = {
            'type'  => "pairjoin_demultiplex",
            'files' => {
                'pair1' => $self->node_id_to_inbox($pair_file_1, $self->token, $self->user_auth),
                'pair2' => $self->node_id_to_inbox($pair_file_2, $self->token, $self->user_auth),
                'index' => $self->node_id_to_inbox($index_file, $self->token, $self->user_auth),
                'barcode' => $self->node_id_to_inbox($barcode_file, $self->token, $self->user_auth)
            }
        };
        my $outprefix = $mg_name || $self->uuidv4();
        # need stats on input files, each one can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p2_tid = scalar(@$tasks);
        my $p1_fname = (keys %{$tasks->[$p2_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $idx_tid = scalar(@$tasks);
        my $p2_fname = (keys %{$tasks->[$idx_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($idx_tid, -1, $index_file, undef, $self->token, $self->user_auth);
        my $pj_tid = scalar(@$tasks);
        my $idx_fname = (keys %{$tasks->[$pj_tid-1]->{outputs}})[0];
        # pair join - this is 2 tasks, dependent on previous tasks  
        # $taskid, $depend_p1, $depend_p2, $depend_idx, $pair1, $pair2, $index, $outprefix, $retain, $auth, $authPrefix
        push @$tasks, $self->build_pair_join_task($pj_tid, $p2_tid-1, $idx_tid-1, $pj_tid-1, $p1_fname, $p2_fname, $idx_fname, $outprefix, $retain, $self->token, $self->user_auth);
        # demultiplex it - # of tasks = barcode_count + 1 (start at task 3)
        my $dm_tid = scalar(@$tasks);
        # $taskid, $depend_seq, $depend_bc, $seq, $barcode, $rc_bar, $auth, $authPrefix
        @submit = $self->build_demultiplex_task($dm_tid, $dm_tid-1, -1, $outprefix.".fastq", $barcode_file, $rc_index, $self->token, $self->user_auth);
        push @$tasks, @submit;
    } elsif ($pair_file_1 && $pair_file_2) {
        $self->add_submission($pair_file_1, $uuid, $self->token, $self->user_auth);
        $self->add_submission($pair_file_2, $uuid, $self->token, $self->user_auth);
        $input = {
            'type'  => "pairjoin",
            'files' => {
                'pair1' => $self->node_id_to_inbox($pair_file_1, $self->token, $self->user_auth),
                'pair2' => $self->node_id_to_inbox($pair_file_2, $self->token, $self->user_auth)
            }
        };
        my $outprefix = $mg_name || $self->uuidv4();
        # need stats on input files, each one can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p2_tid = scalar(@$tasks);
        my $p1_fname = (keys %{$tasks->[$p2_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $pj_tid = scalar(@$tasks);
        my $p2_fname = (keys %{$tasks->[$pj_tid-1]->{outputs}})[0];
        # pair join - this is 2 tasks, dependent on previous tasks
        # $taskid, $depend_p1, $depend_p2, $depend_idx, $pair1, $pair2, $index, $outprefix, $retain, $auth, $authPrefix
        @submit = $self->build_pair_join_task($pj_tid, $p2_tid-1, $pj_tid-1, undef, $p1_fname, $p2_fname, undef, $outprefix, $retain, $self->token, $self->user_auth);
        push @$tasks, @submit;
    } elsif ($multiplex_file && $barcode_file) {
        $self->add_submission($multiplex_file, $uuid, $self->token, $self->user_auth);
        $self->add_submission($barcode_file, $uuid, $self->token, $self->user_auth);
        $input = {
            'type'  => "demultiplex",
            'files' => {
                'sequence' => $self->node_id_to_inbox($multiplex_file, $self->token, $self->user_auth),
                'barcode' => $self->node_id_to_inbox($barcode_file, $self->token, $self->user_auth)
            }
        };
        # need stats on input file, can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $multiplex_file, undef, $self->token, $self->user_auth);
        my $mult_fname = (keys %{$tasks->[0]->{outputs}})[0];
        my $index_fname = undef;
        # is this illumina format with index file?
        if ($index_file) {
            $self->add_submission($index_file, $uuid, $self->token, $self->user_auth);
            $input->{files}{index} = $self->node_id_to_inbox($index_file, $self->token, $self->user_auth);
            push @$tasks, $self->build_seq_stat_task(1, -1, $index_file, undef, $self->token, $self->user_auth);
            $index_fname = (keys %{$tasks->[1]->{outputs}})[0];
        }
        my $dm_tid = scalar(@$tasks);
        # just demultiplex - # of tasks = barcode_count + 1 (start at task 1/2)
        # $taskid, $depend_seq, $depend_bc, $seq, $barcode, $rc_bar, $auth, $authPrefix
        @submit = $self->build_demultiplex_task($dm_tid, 0, -1, $mult_fname, $barcode_file, $rc_index, $self->token, $self->user_auth);
        push @$tasks, @submit;
    } elsif (scalar(@$seq_files) > 0) {
        $input = {
            'type'  => "simple",
            'files' => []
        };
        # one or more sequence files, no transformations
        my $taskid = 0;
        foreach my $seq (@$seq_files) {
            $self->add_submission($seq, $uuid, $self->token, $self->user_auth);
            push @{$input->{files}}, $self->node_id_to_inbox($seq, $self->token, $self->user_auth);
            my ($task1, $task2) = $self->build_seq_stat_task($taskid, -1, $seq, undef, $self->token, $self->user_auth);
            push @$tasks, $task1;
            $taskid += 1;
            # this is a sff file
            if ($task2) {
                push @submit, $task2;
                push @$tasks, $task2;
                $taskid += 1;
            } else {
                push @submit, $task1;
            }
        }
    } else {
        $self->return_data( {"ERROR" => "Invalid pre-processing option combination, no suitable sequence files found"}, 400 );
    }
    
    # extract sequence files to submit
    my $sub_files = [];
    my $sub_tids = [];
    foreach my $s (@submit) {
        if (exists($s->{userattr}{data_type}) && ($s->{userattr}{data_type} eq "sequence")) {
            foreach my $o (keys %{$s->{outputs}}) {
                push @$sub_files, $o;
            }
            if (! $s->{skip}) {
                push @$sub_tids, $s->{taskid};
            }
        }
    }
    
    # post parameters to shock
    my $param_obj = {
        input => $input,
        files => $sub_files,
        parameters => $pipeline_params,
        submission => $uuid
    };
    if ($metadata_file) {
        $param_obj->{metadata} = $metadata_file;
    }
    my $param_str = $self->json->encode($param_obj);
    my $param_attr = {
        type  => 'inbox',
        id    => $user_id,
        user  => $self->user->login,
        email => $self->user->email,
        submission => $uuid,
        data_type  => 'submission',
        stats_info => {
            type      => 'ASCII text',
            suffix    => 'json',
            file_type => 'json',
            file_name => $self->{param_file},
            file_size => length($param_str),
            checksum  => md5_hex($param_str)
        }
    };
    
    # remove any empty tasks
    my $staskid = scalar(@$tasks);
    @$tasks = grep { ! $_->{skip} } @$tasks;

    # add submission task
    my $submit_task = $self->empty_awe_task(1);
    $submit_task->{cmd}{description} = 'mg submit '.scalar(@$sub_files);
    $submit_task->{cmd}{name} = "awe_submit_to_mgrast.pl";
    $submit_task->{cmd}{args} = '-input @'.$self->{param_file};
    $submit_task->{cmd}{environ}{private} = {"USER_AUTH" => $self->token, "MGRAST_API" => $self->cgi->url};
    $submit_task->{taskid} = "$staskid";
    $submit_task->{dependsOn} = $sub_tids;
    $submit_task->{outputs} = {
        "awe_stdout.txt" => {
            host => $Conf::shock_url,
            node => "-",
            attrfile => "userattr.json"
        },
        "awe_stderr.txt" => {
            host => $Conf::shock_url,
            node => "-",
            attrfile => "userattr.json"
        }
    };
    $submit_task->{userattr}{stage_name} = "submission";
    # metadata or project
    if ($metadata_obj || $project_obj) {
        if ($metadata_obj && $md_json_node) {
            $submit_task->{cmd}{args} .= ' -metadata @'.$md_json_node->{file}{name};
            $submit_task->{inputs}{$md_json_node->{file}{name}} = {host => $Conf::shock_url, node => $md_json_node->{id}};
        }
        if ($project_obj) {
            $submit_task->{cmd}{args} .= ' -project mgp'.$project_obj->{id};
        }
    } else {
        $self->return_data( {"ERROR" => "Missing project information, must have one of metadata_file, project_id, or project_name"}, 400 );
    }
    
    # paramater node (do right before submit to AWE)
    my $param_node = $self->set_shock_node($self->{param_file}, $param_str, $param_attr, $self->token, 1, $self->user_auth);
    $self->edit_shock_acl($param_node->{id}, $self->token, 'mgrast', 'put', 'all', $self->user_auth);
    $submit_task->{inputs}{$self->{param_file}} = {host => $Conf::shock_url, node => $param_node->{id}};
    push @$tasks, $submit_task;
    
    # build workflow
    my $info = {
        shock_url     => $Conf::shock_url,
        job_name      => $user_id.'_submission',
        user_id       => $user_id,
        user_name     => $self->user->login,
        user_email    => $self->user->email,
        pipeline      => "submission",
        description   => $input->{type},
        clientgroups  => $Conf::mgrast_inbox_clientgroups,
        submission_id => $uuid,
        task_list     => $self->json->encode($tasks)
    };
    my $job = $self->submit_awe_template($info, $Conf::mgrast_submission_workflow, $self->token, $self->user_auth, $debug);
    
    $response->{job} = $job;
    $response->{info} = $param_obj;
    $self->return_data($response);
}

sub submission_nodes {
    my ($self, $uuid, $full, $is_admin) = @_;
    
    my $user_id = 'mgu'.$self->user->_id;
    my $inbox_query = {
        submission => $uuid,
        type => 'inbox'
    };
    my $inbox_query2 = {
        submission => $uuid,
        type => 'inbox'
    };
    my $mgrast_query = {
        submission => $uuid,
        type => 'metagenome'
    };
    if (! $is_admin) {
        $inbox_query->{id} = $user_id;
        $inbox_query2->{id} = $self->user->{login};
        $mgrast_query->{owner} = $user_id;
    }
    my $inbox_nodes = $self->get_shock_query($inbox_query, $self->token, $self->user_auth);
    push(@$inbox_nodes, @{$self->get_shock_query($inbox_query2, $self->token, $self->user_auth)});
    my $data = { inbox => $inbox_nodes || [] };
    if ($full) {
        my $mgrast_nodes = $self->get_shock_query($mgrast_query, $self->mgrast_token);
        $data->{mgrast} = $mgrast_nodes || [];
    }
    return $data;
}

sub submission_jobs {
    my ($self, $uuid, $full, $is_admin) = @_;
    
    my $user_id = 'mgu'.$self->user->_id;
    my $inbox_query = {
        "info.pipeline" => 'submission',
        "info.userattr.submission" => $uuid
    };
    my $mgrast_query = {
        "info.pipeline" => 'mgrast-prod',
        "info.userattr.submission" => $uuid
    };
    if (! $is_admin) {
        $inbox_query->{"info.user"} = $user_id;
        $mgrast_query->{"info.user"} = $user_id;
    }
    my $inbox_jobs = $self->get_awe_query($inbox_query, $self->token, $self->user_auth);
    my $submit = (scalar(@{$inbox_jobs->{data}}) > 0) ? $inbox_jobs->{data}[0] : {};
    my $data = { submit => $submit };
    if ($full) {
        my $mgrast_jobs = $self->get_awe_query($mgrast_query, $self->mgrast_token);
        $data->{pipeline} = $mgrast_jobs->{data} || [];
    }
    return $data;
}

sub get_param_node {
    my ($self, $job) = @_;
    if ($job->{tasks} && (@{$job->{tasks}} > 0)) {
        foreach my $out (@{$job->{tasks}[-1]{inputs}}) {
            if ($out->{filename} eq $self->{param_file}) {
                return $out->{node};
            }
        }
    }
    return undef;
}

sub parse_submit_output {
    my ($self, $report) = @_;
    my $info = {};
    if (! $report) {
        return $info;
    }
    foreach my $line (split(/\n/, $report)) {
        my ($type, @rest) = split(/\t/, $line);
        if (scalar(@rest) == 1) {
            push @{$info->{$type}}, $rest[0];
        } elsif (scalar(@rest) > 1) {
            if ($type eq 'submitted') {
                push @{$info->{$type}}, {
                    file_name => $rest[0],
                    metagenome_name => $rest[1],
                    pipeline_id => $rest[2],
                    metagenome_id => $rest[3]
                };
            } else {
                push @{$info->{$type}}, \@rest;
            }
        } else {
            next;
        }
    }
    return $info;
}

1;
