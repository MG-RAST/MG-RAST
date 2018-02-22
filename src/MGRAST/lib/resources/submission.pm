package resources::submission;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use Digest::MD5 qw(md5_hex md5_base64);
use Data::Dumper;
use DateTime::Format::ISO8601;
use Template;

use MGRAST::Metadata;

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
        "rc_index"       => [ "boolean", "If true barcodes in mapping file are reverse compliment, default is false" ],
        "pair_file_1"    => [ "string", "RFC 4122 UUID for pair 1 file" ],
        "pair_file_2"    => [ "string", "RFC 4122 UUID for pair 2 file" ],
        "index_file"     => [ "string", "RFC 4122 UUID for index (barcode) file" ],
        "index_file_2"   => [ "string", "RFC 4122 UUID for second index file, for double barcodes (optional)" ],
        "mg_name"        => [ "string", "name of metagenome for pair-join"],
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
        'url' => $self->url."/".$self->name,
        'description' => "submission runs input through a series of validation and pre-processing steps, then submits the results to the MG-RAST anaylsis pipeline",
        'type' => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests' => [
            { 'name'        => "info",
              'request'     => $self->url."/".$self->name,
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
              'request'     => $self->url."/".$self->name."/list",
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
              'request'     => $self->url."/".$self->name."/{UUID}",
              'description' => "get status of submission from ID",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'          => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'        => [ 'string', "user id" ],
                  'error'       => [ 'string', "error message if any" ],
                  'timestamp'   => [ 'string', "timestamp for return of this query" ],
                  'pipeline_id' => [ 'string', "AWE ID of submission" ],
                  'info'        => [ 'hash', "submission AWE job info" ],
                  'state'       => [ 'string', "state of submission workflow" ],
                  'type'        => [ 'string', "type of submission" ],
                  'parameters'  => [ 'hash', "key value pairs of metagenome pipeline parameters" ],
                  'inputs'      => [ 'list', ['hash', 'input file info'] ],
                  'outputs'     => [ 'list', ['hash', 'output metagenome info'] ]
              },
              'parameters'  => {
                  'options'  => { "full" => [ "boolean", "if true show full document of running jobs, default is summary" ] },
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for submission" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "delete",
              'request'     => $self->url."/".$self->name."/{UUID}",
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
              'request'     => $self->url."/".$self->name."/submit",
              'description' => "start new submission",
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'error'      => [ 'string', "error message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => $self->{submit_params}
              }
            },
            { 'name'        => "ebi-submit",
              'request'     => $self->url."/".$self->name."/ebi",
              'description' => "start new EBI submission",
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'project'    => [ "string", "unique MG-RAST project identifier" ],
                  'user'       => [ 'string', "user id" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => {
                      "project_id" => [ "string", "unique MG-RAST project identifier" ],
                      "force"      => [ "boolean", "if true overwrite existing metagenome_taxonomy with inputted" ],
                      "upload"     => [ "boolean", "if true only upload files, do not submit XML forms" ],
                      "debug"      => [ "boolean", "if true run debug workflow instead of normal"],
                      "workflow"   => [ "boolean", "if true return workflow document instead of submitting"],
                      "project_taxonomy" => [ 'string', "optional: taxa_name to apply to all metagenomes of project" ],
                      "metagenome_taxonomy" => [ 'hash', "optional: key value pairs of metagenome_id => taxa_name" ]
                  }
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
        } elsif (($self->method eq 'POST') && ($self->rest->[0] eq 'ebi')) {
            $self->ebi_submit();
        }
    }
    $self->info();
}

sub ebi_submit {
    my ($self) = @_;
    
    my $uuid = $self->uuidv4();
    my $post = $self->get_post_data(['project_id', 'force', 'upload', 'debug', 'workflow', 'project_taxonomy', 'metagenome_taxonomy']);
    
    my $project_id = $post->{'project_id'} || undef;
    my $force      = $post->{'force'} ? 1 : 0;
    my $upload     = $post->{'upload'} ? 1 : 0;
    my $debug      = $post->{'debug'} ? 1 : 0;
    my $workflow   = $post->{'workflow'} ? 1 : 0;
    my $proj_taxa  = $post->{'project_taxonomy'} || "";
    my $mg_taxa    = $post->{'metagenome_taxonomy'} || {};
    
    my $master  = $self->connect_to_datasource();
    my $metadbm = MGRAST::Metadata->new->_handle();
    
    # check id format
    unless ($project_id) {
        $self->return_data( {"ERROR" => "missing project id"}, 400 );
    }
    my ($pid) = $project_id =~ /^mgp(\d+)$/;
    if (! $pid) {
        $self->return_data( {"ERROR" => "invalid project id format: " . $project_id}, 400 );
    }
    # edit rights
    unless ($self->user && ($self->user->has_star_right('edit', 'project') || $self->user->has_right(undef, 'edit', 'project', $pid))) {
        $self->return_data( { "ERROR" => "insufficient permissions" }, 401 );
    }
    # get project
    my $project = $master->Project->init({id => $pid});
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "project not found: " . $project_id}, 404 );
    }
    
    # set the metagenome_taxonomy if missing or overwrite
    # get the shock node of input sequence files
    my $awe_files = [];
    my $cwl_files = [];
    my $mgs = $project->metagenomes();
    foreach my $mg (@$mgs) {
        my $mgid = 'mgm'.$mg->metagenome_id;
        # add to input list
        my $version = $mg->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
        my ($mgfiles, undef) = $self->get_download_set($mg->metagenome_id, $version, $self->mgrast_token, 1);
        my $has_seq = 0;
        foreach my $mf (@$mgfiles) {
            if (($mf->{stage_name} eq 'upload') && ($mf->{file_size} > 0) && $mf->{node_id} && $mf->{file_format}) {
                push @$awe_files, {
                    filename => $mf->{file_name},
                    host     => $Conf::shock_url,
                    node     => $mf->{node_id}
                };
                push @$cwl_files, {
                    mgid => $mgid,
                    file => {
                        class  => "File",
                        path   => $mf->{file_name},
                        format => ($mf->{file_format} eq 'fastq') ? 'fastq' : 'fasta'
                    }
                };
                $has_seq = 1;
                last;
            }
        }
        unless ($has_seq) {
            $self->return_data( {"ERROR" => "metagenome $mgid is missing required input sequence file"}, 500 );
        }
        # see if it has name
        unless ($upload) {
            my $taxattr = {
                collection => $mg->sample,
                tag => 'metagenome_taxonomy'
            };
            my $existing = $metadbm->MetaDataEntry->get_objects($taxattr);
            if ((scalar(@$existing) == 0) || $force) {
                if ($mg_taxa->{$mgid}) {
                    $taxattr->{value} = $mg_taxa->{$mgid};
                } elsif ($proj_taxa) {
                    $taxattr->{value} = $proj_taxa;
                } else {
                    $self->return_data( {"ERROR" => "metagenome $mgid is missing required metagenome_taxonomy metadata"}, 500 );
                }
                if (scalar(@$existing)) {
                    foreach my $pmd (@$existing) {
                        $pmd->delete();
                    }
                }
                $metadbm->MetaDataEntry->create($taxattr);
            }
        }
    }
    
    # add cwl input file to shock
    my $user_id = 'mgu'.$self->user->_id;
    my $proj_id = 'mgp'.$project->{id};
    my $cwl_input = {
        seqFiles     => $cwl_files,
        project      => $proj_id,
        mgrastUrl    => $debug ? $Conf::dev_url : $Conf::cgi_url,
        mgrastToken  => $Conf::api_key,
        submitUrl    => $debug ? $Conf::ebi_test_url : $Conf::ebi_submission_url,
        user         => $Conf::mgrast_ebi_user,
        password     => $Conf::mgrast_ebi_pswd,
        submitOption => "ADD",
        submissionID => $uuid
    };
    my $cwl_attr = {
        type        => "submission",
        id          => $proj_id,
        owner       => $user_id,
        file_format => "json",
        data_type   => "cwl_input",
        submission  => $uuid,
        metagenomes => scalar(@$cwl_files)
    };
    my $cwl_node = $self->set_shock_node($Conf::cwl_input_file, $cwl_input, $cwl_attr, $self->mgrast_token);
    push @$awe_files, {
        filename => $Conf::cwl_input_file,
        host     => $Conf::shock_url,
        node     => $cwl_node->{id}
    };
    
    # fill out workflow template / submit to AWE
    my $awe_info = {
        shock_url     => $Conf::shock_url,
        project_id    => $proj_id,
        project_name  => $project->{name},
        user          => $user_id,
        submission_id => $uuid,
        mg_count      => scalar(@$cwl_files),
        cwl_input     => $Conf::cwl_input_file,
        input_files   => $self->json->encode($awe_files),
        docker_image_version => 'latest'
    };
    
    my $ebi_workflow = $Conf::mgrast_ebi_submit_workflow;
    if ($debug) {
        $ebi_workflow = $Conf::mgrast_ebi_debug_workflow;
    }
    if ($upload) {
        $ebi_workflow = $Conf::mgrast_ebi_upload_workflow;
    }
    
    my $job = $self->submit_awe_template($awe_info, $ebi_workflow, $self->mgrast_token, 'mgrast', $workflow);
    if ($workflow) {
        $self->return_data($job);
    }
    
    my $response = {
        id        => $uuid,
        job       => $job->{id},
        project   => $proj_id,
        user      => $user_id,
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    $self->return_data($response);
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
        error      => undef,
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    my $is_admin = $self->user->is_admin('MGRAST') ? 1 : 0;
    
    # is it a project ID ?
    if ($uuid =~ /^mgp\d+$/) {
        my $ebi_submit = $self->is_ebi_submission(undef, $uuid);
        if (! $ebi_submit) {
            $response->{error} = "No submission exists for given ID ".$uuid;
            $self->return_data($response);
        }
        my $ebi_response = $self->ebi_submission_status($ebi_submit, $response);
        $self->return_data($ebi_response);
    }
    
    # get data
    my $jobs   = $self->submission_jobs($uuid, $full, $is_admin);
    my $submit = $jobs->{submit};
    my $pnode  = $self->get_param_node($submit);

    if ((! $submit) || (! $pnode)) {
        my $ebi_submit = $self->is_ebi_submission($uuid);
        if (! $ebi_submit) {
            $response->{error} = "No submission exists for given ID ".$uuid;
            $self->return_data($response);
        }
        my $ebi_response = $self->ebi_submission_status($ebi_submit, $response);
        $self->return_data($ebi_response);
    }
    
    # add submission workflow info
    $response->{pipeline_id} = $submit->{id};
    $response->{project}     = $self->obfuscate($submit->{info}{project});
    $response->{info}        = $submit->{info};
    $response->{state}       = $submit->{state};
    $response->{type}        = $submit->{info}{description};
    
    if ($submit->{state} eq 'deleted') {
        $response->{error} = "Deleted submission";
        $self->return_data($response);
    }
    
    # get submission input - parameters file
    my $info = {};
    my $info_err = "";
    eval {
        my $info_text = "";
        ($info_text, $info_err) = $self->get_shock_file($pnode, undef, $is_admin ? $self->{mgrast_token} : $self->token, undef, $self->user_auth);
        $info = $self->json->decode($info_text);
    };
    if (! $info) {
        $response->{error} = "Broken submission: ".($info_err || "missing parameter data $pnode");
        $self->return_data($response);
    }
    $response->{parameters} = $info->{parameters};
    my $inputs = undef;
    eval {
        $inputs = [ sort { $a->{filename} cmp $b->{filename} } @{$info->{input}{files}} ];
    };
    if (! $inputs) {
        $inputs = $info->{input}{files};
    }
    $response->{inputs} = $inputs;
    
    # get submission results - either stdout from workunit if running or from shock if done
    my $report = $self->get_task_report($submit->{tasks}[-1], 'stdout', $self->token, $self->user_auth);
    my $result = $self->parse_submit_output($report);
    $response->{outputs} = [];
    if (exists($result->{submitted}) && (@{$result->{submitted}} > 0)) {
        # get inputs / outputs in same order
        $response->{outputs} = [ sort { $a->{filename} cmp $b->{filename} } @{$result->{submitted}} ];
    }
    
    # info of analysis pipeline stages per metagenome - 'full' option only
    if ($jobs->{pipeline} && (@{$jobs->{pipeline}} > 0)) {
        $response->{metagenomes} = [];
        # get them in same order
        foreach my $o (@{$response->{outputs}}) {
            foreach my $m (@{$jobs->{pipeline}}) {
                if ($o->{metagenome_id} eq $m->{userattr}{id}) {
                    push @{$response->{metagenomes}}, $m;
                    last;
                }
            }
        }
    }
    
    # status of preprocessing workflow
    # only for multi-step submissions
    my $preprocessing = [];
    foreach my $task (@{$submit->{tasks}}) {
        # skip submission stage
        if (exists($task->{userattr}{stage_name}) && ($task->{userattr}{stage_name} eq 'submission')) {
            next;
        }
        my $summery = {
            stage => $task->{cmd}{description},
            inputs => [ map { $_->{filename} } @{$task->{inputs}} ],
            status => $task->{state}
        };
        if ($task->{state} eq 'suspend') {
            $summery->{error} = $self->get_task_report($task, 'stderr', $self->token, $self->user_auth) || 'unknown error';
        }
        push @$preprocessing, $summery;
    }
    if (@$preprocessing > 0) {
        $response->{preprocessing} = $preprocessing;
    }
    
    $self->return_data($response);
}

sub delete {
    my ($self, $uuid) = @_;
    
    my $full  = $self->cgi->param('full') ? 1 : 0;
    my $nodes = $self->submission_nodes($uuid);
    my $jobs  = $self->submission_jobs($uuid, $full);
    
    # delete inbox nodes
    foreach my $n (@$nodes) {
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
    my $rc_barcode     = $post->{'rc_index'} ? 1 : 0;
    my $pair_file_1    = $post->{'pair_file_1'} || "";
    my $pair_file_2    = $post->{'pair_file_2'} || "";
    my $index_file     = $post->{'index_file'} || "";
    my $index_file_2   = $post->{'index_file_2'} || "";
    my $mg_name        = $post->{'mg_name'} || "";
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
        # use extracted barcodes if not supplied
        if ($bar_id && ($bar_count > 1) && (! $barcode_file)) {
            $barcode_file = $bar_id;
        }
    }
    
    # check combinations
    if (($pair_file_1 && (! $pair_file_2)) || ($pair_file_2 && (! $pair_file_1))) {
        $self->return_data( {"ERROR" => "Must include pair_file_1 and pair_file_2 together to merge pairs"}, 400 );
    } elsif ( ($multiplex_file && (! $barcode_file)) || ( $barcode_file && ((! $multiplex_file) || ((! $pair_file_1) || (! $pair_file_2))) ) ) {
        $self->return_data( {"ERROR" => "Must include multiplex_file or pair_file and barcode_file together to demultiplex"}, 400 );
    } elsif (! ($pair_file_1 || $multiplex_file || (@$seq_files > 0))) {
        $self->return_data( {"ERROR" => "No sequence files provided"}, 400 );
    }
    
    # normalize barcode file if exists
    my $bar_names = undef;
    if ($barcode_file) {
        my ($b_norm, $b_names) = $self->normalize_barcode_file($barcode_file, $rc_barcode, $self->token, $self->user_auth);
        $barcode_file = $b_norm;
        $bar_names = $b_names;
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
    $response->{project_id} = 'mgp'.$project_obj->{id};
    $response->{project}    = $self->obfuscate('mgp'.$project_obj->{id});
    
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
        if ($index_file_2) {
            $self->add_submission($index_file_2, $uuid, $self->token, $self->user_auth);
            $input->{'files'}{'index2'} = $self->node_id_to_inbox($index_file_2, $self->token, $self->user_auth);
        }
        my $outprefix = $mg_name || $self->uuidv4();
        # need stats on input files, each one can be 1 or 2 tasks
        my $p1_tid = 0;
        push @$tasks, $self->build_seq_stat_task($p1_tid, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p1_fname = (keys %{$tasks->[$p1_tid]->{outputs}})[0];
        my $p2_tid = scalar(@$tasks);
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $p2_fname = (keys %{$tasks->[$p2_tid]->{outputs}})[0];
        my $idx_tid = scalar(@$tasks);
        push @$tasks, $self->build_seq_stat_task($idx_tid, -1, $index_file, undef, $self->token, $self->user_auth);
        my $idx_fname = (keys %{$tasks->[$idx_tid]->{outputs}})[0];
        my $idx2_fname = undef;
        my $pjd_tid = scalar(@$tasks);
        if ($index_file_2) {
            push @$tasks, $self->build_seq_stat_task($pjd_tid, -1, $index_file_2, undef, $self->token, $self->user_auth);
            $idx2_fname = (keys %{$tasks->[$pjd_tid]->{outputs}})[0];
            $pjd_tid = scalar(@$tasks);
        }
        # this is 2 or more tasks, dependent on previous tasks
        # $taskid, $depend_seq1, $depend_seq2, $depend_bc, $depend_idx1, $depend_idx2, $seq1, $seq2, $barcode, $index1, $index2, $retain, $auth, $authPrefix
        @submit = $self->build_demultiplex_pairjoin_task($pjd_tid, $p1_tid, $p2_tid, -1, $idx_tid, $pjd_tid-1, $p1_fname, $p2_fname, $barcode_file, $idx_fname, $idx2_fname, $bar_names, $retain, $self->token, $self->user_auth);
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
        my $p1_tid = 0;
        push @$tasks, $self->build_seq_stat_task($p1_tid, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p1_fname = (keys %{$tasks->[$p1_tid]->{outputs}})[0];
        my $p2_tid = scalar(@$tasks);
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $p2_fname = (keys %{$tasks->[$p2_tid]->{outputs}})[0];
        my $pj_tid = scalar(@$tasks);
        # pair join - this is 2 tasks, dependent on previous tasks
        # $taskid, $depend_p1, $depend_p2, $pair1, $pair2, $outprefix, $retain, $auth, $authPrefix
        @submit = $self->build_pair_join_task($pj_tid, $p1_tid, $p2_tid, $p1_fname, $p2_fname, $outprefix, $retain, undef, $self->token, $self->user_auth);
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
        # need stats on input file
        push @$tasks, $self->build_seq_stat_task(0, -1, $multiplex_file, undef, $self->token, $self->user_auth);
        my $dm_tid = scalar(@$tasks);
        my $mult_fname = (keys %{$tasks->[0]->{outputs}})[0];
        # do illumina style demultiplex
        if ($index_file) {
            $self->add_submission($index_file, $uuid, $self->token, $self->user_auth);
            $input->{'files'}{'index'} = $self->node_id_to_inbox($index_file, $self->token, $self->user_auth);
            push @$tasks, $self->build_seq_stat_task(1, -1, $index_file, undef, $self->token, $self->user_auth);
            $dm_tid = scalar(@$tasks);
            my $idx_fname = (keys %{$tasks->[1]->{outputs}})[0];
            my $idx2_fname = undef;
            if ($index_file_2) {
                $self->add_submission($index_file_2, $uuid, $self->token, $self->user_auth);
                $input->{'files'}{'index2'} = $self->node_id_to_inbox($index_file_2, $self->token, $self->user_auth);
                push @$tasks, $self->build_seq_stat_task(2, -1, $index_file_2, undef, $self->token, $self->user_auth);
                $dm_tid = scalar(@$tasks);
                $idx2_fname = (keys %{$tasks->[2]->{outputs}})[0];
            }
            # $taskid, $depend_seq, $depend_bc, $depend_idx1, $depend_idx2, $seq, $barcode, $index1, $index2, $auth, $authPrefix
            @submit = $self->build_demultiplex_illumina_task($dm_tid, 0, -1, 1, 2, $mult_fname, $barcode_file, $idx_fname, $idx2_fname, $bar_names, $self->token, $self->user_auth);
        }
        # do 454 style demultiplex
        else {
            # $taskid, $depend_seq, $depend_bc, $seq, $barcode, $auth, $authPrefix
            @submit = $self->build_demultiplex_454_task($dm_tid, 0, -1, $mult_fname, $barcode_file, $bar_names, $self->token, $self->user_auth);
        }
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
    @$tasks = grep { ! $_->{skip} } @$tasks;
    my $staskid = scalar(@$tasks);

    # add submission task
    my $submit_task = $self->empty_awe_task(1);
    $submit_task->{cmd}{description} = 'mg submit '.scalar(@$sub_files);
    $submit_task->{cmd}{name} = "mgrast_submit.pl";
    $submit_task->{cmd}{args} = '-input @'.$self->{param_file};
    $submit_task->{cmd}{environ}{private} = {"USER_AUTH" => $self->token, "MGRAST_API" => $self->url};
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
        project_id    => $response->{project_id},
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

sub is_ebi_submission {
    my ($self, $uuid, $pid) = @_;
    
    my $ebi_query = {"info.pipeline" => 'mgrast-submit-ebi'};
    if ($uuid) {
        $ebi_query->{"info.userattr.submission"} = $uuid;
    } elsif ($pid) {
        $ebi_query->{"info.name"} = $pid;
    } else {
        return undef;
    }
    
    my $ebi_jobs = $self->get_awe_query($ebi_query, $self->mgrast_token);
    if ($ebi_jobs->{data} && (scalar(@{$ebi_jobs->{data}}) > 0)) {
        return $ebi_jobs->{data}[0];
    } else {
        return undef;
    }
}

sub submission_nodes {
    my ($self, $uuid) = @_;
    
    my $user_id = 'mgu'.$self->user->_id;
    my $query = {
        submission => $uuid,
        type => 'inbox',
        id => $user_id
    };
    return $self->get_shock_query($query, $self->token, $self->user_auth);
}

sub submission_jobs {
    my ($self, $uuid, $full, $is_admin) = @_;
    
    my $user_id = 'mgu'.$self->user->_id;
    my $inbox_query = {
        "info.pipeline" => 'submission',
        "info.userattr.submission" => $uuid
    };
    my $mgrast_query = {
        "info.pipeline" => '',
        "info.userattr.submission" => $uuid,
        "verbosity" => 'minimal',
        "userattr" => ['id', 'name', 'project_id']
    };
    if (! $is_admin) {
        $inbox_query->{"info.user"} = $user_id;
        $mgrast_query->{"info.user"} = $user_id;
    }
    my $inbox_jobs = $self->get_awe_query($inbox_query, $self->token, $self->user_auth);
    my $submit = ($inbox_jobs->{data} && (scalar(@{$inbox_jobs->{data}}) > 0)) ? $inbox_jobs->{data}[0] : {};
    my $data = { submit => $submit, pipeline => [] };
    if ($full) {
        foreach my $p (@{$Conf::pipeline_names}) {
            $mgrast_query->{"info.pipeline"} = $p;
            my $mgrast_jobs = $self->get_awe_query($mgrast_query, $self->mgrast_token);
            if ($mgrast_jobs->{data}) {
                push( @{$data->{pipeline}}, @{$mgrast_jobs->{data}} );
            }
        }
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
                    filename => $rest[0],
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

sub ebi_submission_status {
    my ($self, $job, $response) = @_;
    
    if ($job->{error} && ref($job->{error})) {
        $response->{status} = $job->{error}{status};
        if ($job->{error}{apperror}) {
            $response->{error} = $job->{error}{apperror};
        } elsif ($job->{error}{worknotes}) {
            $response->{error} = $job->{error}{worknotes};
        } else {
            $response->{error} = $job->{error}{servernotes};
        }
    } elsif ($job->{state} eq 'completed') {
        $response->{status} = 'completed';
        # get / parse receipt
        my ($text, $err) = $self->get_shock_file($job->{tasks}[0]{outputs}[0]{node}, undef, $self->mgrast_token);
        if ($err) {
            $response->{error} = $err
        } else {
            my $receipt = $self->parse_ebi_receipt($text);
            if ($receipt->{success} eq 'true') {
                $response->{receipt} = $receipt;
            } else {
                $response->{status}  = 'error';
                $response->{error}   = $receipt->{error};
                $response->{message} = $receipt->{info};
                $response->{receipt} = $job->{tasks}[0]{outputs}[0]{node};
            }
        }
    } else {
        $response->{status} = 'in-progress';
    }
    
    $response->{metagenomes} = $job->{info}{userattr}{metagenomes} ? $job->{info}{userattr}{metagenomes} * 1 : undef;
    $response->{project} = $job->{info}{name} || undef;
    $response->{id} = $job->{info}{userattr}{submission} || undef;
    return $response;
}

1;
