package resources::download;

use strict;
use warnings;
no warnings('once');

use Clone qw(clone);
use Data::Dumper;
use File::Slurp;
use List::MoreUtils qw(any uniq);
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "download";
    $self->{default_pipeline_version} = "3.0";
    $self->{default_pipeline_commit}  = "https://github.com/MG-RAST/pipeline";
    $self->{default_template_version} = "https://github.com/MG-RAST/MG-RAST/tree/api/src/MGRAST/workflows";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "An analysis file from the processing of a metagenome from a specific stage in its analysis",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				              'request'     => $self->cgi->url."/".$self->name,
				              'description' => "Returns description of parameters and attributes.",
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => "self",
				              'parameters'  => { 'options'  => {},
							                     'required' => {},
							                     'body'     => {} }
							},
				            { 'name'        => "instance",
				              'request'     => $self->cgi->url."/".$self->name."/{ID}",
				              'description' => "Returns a single sequence file.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3?file=350.1",
      				                             'download fasta file of gene-called protein sequences (from stage 350)' ],
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => { "data" => [ 'file', 'requested analysis file' ] },
				              'parameters'  => { 'options'  => { "file" => [ "string", "file name or identifier" ],
				                                                 "link" => [ "boolean", "if true return one time link for download and not file stream" ] },
							                     'required' => { "id" => [ "string", "unique metagenome identifier" ] },
							                     'body'     => {} }
							},
							{ 'name'        => "history",
				              'request'     => $self->cgi->url."/".$self->name."/{ID}/history",
				              'description' => "Summery of MG-RAST analysis-pipeline workflow and commands.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3/history",
      				                             'Workflow document for mgm4447943.3' ],
				              'method'      => "GET",
				              'type'        => "synchronous",
				              'attributes'  => { "data" => [ 'file', 'requested workflow file' ] },
				              'parameters'  => { 'options'  => { "awe_id" => ["string", "optional: AWE ID of MG-RAST metagenome"],
				                                                 "force"  => ["boolean", "if true, recreate document in Shock from AWE."],
				                                                 "delete" => ["boolean", "if true (and user is admin) delete original document from AWE on completion."] },
							                     'required' => { "id" => [ "string", "unique metagenome identifier" ] },
							                     'body'     => {} }
							},
				            { 'name'        => "setlist",
				              'request'     => $self->cgi->url."/".$self->name."/{ID}",
				              'description' => "Returns a list of sets of sequence files for the given id.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3?stage=650",
        				                         'view all available files from stage 650' ],
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => { "stage_name" => [ "string", "name of the stage in processing of this file" ],
							                     "stage_id"   => [ "string", "three digit numerical identifier of the stage" ],
							                     "stage_type" => [ "string", "type of the analysis file within a stage, i.e. passed or removed for quality control steps" ],
							                     "file_name"  => [ "string", "name of the analysis file" ],
							                     "file_id"    => [ "string", "unique identifier of file in stage" ],
							                     "id"         => [ "string", "unique metagenome identifier" ],
							                     "url"        => [ "string", "url for retrieving this analysis file" ] },
				             'parameters'  => { 'options'  => { "stage" => [ "string", "stage name or identifier" ] },
							                    'required' => { "id" => [ "string", "unique metagenome identifier" ] },
							                    'body'     => {} }
							} ]
		  };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
  
    # check id format
    my $rest = $self->rest;
    my $tempid = $self->idresolve($rest->[0]);
    my (undef, $id) = $tempid =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();

    # get data
    my $mgid = 'mgm'.$id;
    my $job  = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id ".$rest->[0]." does not exist"}, 404 );
    }
    $job = $job->[0];
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id ".$rest->[0]." is still processing and unavailable"}, 404 );
    }
    
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    if ((@$rest > 1) && ($rest->[0] eq 'history')) {
        $self->return_data( $self->awe_history($mgid, $job) );
    }

    # get data / parameters
    my $stage   = $self->cgi->param('stage') || undef;
    my $file    = $self->cgi->param('file') || undef;
    my $link    = $self->cgi->param('link') ? 1 : 0;
    my $version = $job->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
    my $setlist = $self->get_download_set($job->{metagenome_id}, $version, $self->mgrast_token);
    
    # return file from shock
    if ($file) {
        my $node = undef;
        foreach my $set (@$setlist) {
            if (! $job->{public}) {
                my $pid = $self->obfuscate($mgid);
                $set->{file_name} =~ s/$mgid/$pid/;
            }
            if (($set->{file_id} eq $file) || ($set->{file_name} eq $file)) {
                if ($link) {
                    my $data = $self->get_shock_preauth($set->{node_id}, $self->mgrast_token, $set->{file_name});
                    $self->return_data($data);
                } else {
                    $self->return_shock_file($set->{node_id}, $set->{file_size}, $set->{file_name}, $self->mgrast_token);
                }
            }
        }
        $self->return_data( {"ERROR" => "requested file ($file) is not available"}, 404 );
    }
    # return stage(s) list
    my $data = {
        id   => $mgid,
        url  => $self->cgi->url."/".$self->name."/".$mgid,
        data => []
    };
    if ($stage) {
        $data->{url} .= '?stage='.$stage;
        foreach my $set (@$setlist) {
            if (($set->{stage_id} eq $stage) || ($set->{stage_name} eq $stage)) {
                push @{$data->{data}}, $set;
            }
        }
    }
    # return all
    else {
        $data->{data} = $setlist;
    }
    $self->return_data($data);
}

sub awe_history {
    my ($self, $mgid, $job) = @_;
    
    my $awe_id = $self->cgi->param('awe_id') || undef;
    my $force  = $self->cgi->param('force') ? 1 : 0;
    my $delete = $self->cgi->param('delete') ? 1 : 0;
    my $debug  = $self->cgi->param('debug') ? 1 : 0;
    my $data   = {
        id   => $mgid,
        url  => $self->cgi->url."/".$self->name."/".$mgid."?force=".$force,
        data => []
    };
    if ($awe_id) {
        $data->{url} .= "&awe_id=".$awe_id;
    }
    if ($delete) {
         $data->{url} .= "&delete=".$delete;
    }
    if ($debug) {
         $data->{url} .= "&debug=".$debug;
    }

    my $job_doc = undef;
    my $is_template = 0;
    
    # get shock node and file
    my $squery = {
        id         => $mgid,
        data_type  => 'awe_workflow'
    };
    my $nodes = $self->get_shock_query($squery, $self->mgrast_token);
    if ((scalar(@$nodes) > 0) && (! $force)) {
        my ($content, $err) = $self->get_shock_file($nodes->[0]{id}, undef, $self->mgrast_token);
        if ($err) {
            $self->return_data( {"ERROR" => "Unable to retrieve processing history: $err"}, 500 );
        }
        eval {
            $job_doc = $self->json->decode($content);
            if ($nodes->[0]{attributes}{workflow_type} && ($nodes->[0]{attributes}{workflow_type} eq 'template')) {
                $is_template = 1;
            }
        };
    }
    # got from shock
    if ($job_doc && $debug) {
        $data->{node} = $nodes->[0]{id};
    }
    
    # not in shock / create document
    if (! $job_doc) {
        # try and find AWE id in DB
        if (! $awe_id) {
            my $jdata = $job->data();
            if ($jdata->{pipeline_id}) {
                $awe_id = $jdata->{pipeline_id};
            }
        }
        # build from AWE
        if ($awe_id) {
            $job_doc = $self->get_awe_full_document($awe_id, $self->mgrast_token);
        }
        # no ID or not in AWE - just use template
        if (! $job_doc) {
            $job_doc = $self->get_workflow_from_template($job);
            $is_template = 1;
        }
    }
    
    # too many errors
    if (! $job_doc) {
        $self->return_data( {"ERROR" => "Unable to retrieve processing history"}, 500 );
    }
    if ($job_doc->{info}{userattr}{id} ne $mgid) {
        $self->return_data( {"ERROR" => "MG-RAST ID ($mgid) does not match processing document"}, 404 );
    }
    
    # get static stage info
    my $stage_info = undef;
    eval {
        my $temp_str = read_file($Conf::workflow_dir."/stages-info.json");
        $stage_info  = $self->json->decode($temp_str);
    };
    if (! $stage_info) {
        $self->return_data( {"ERROR" => "Unable to retrieve pipeline stage information"}, 500 );
    }
    
    # get downloadable files
    my $version = $job->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
    my @setlist = @{ $self->get_download_set($job->{metagenome_id}, $version, $self->mgrast_token) };
    my $upload  = shift @setlist;
    my %setmap  = map { $_->{file_name}, $_ } @setlist;
    my %filemap = map { $_, 0 } keys %setmap;
    
    # build history
    my $awe_history = {
        id => $job_doc->{id} || undef,
        info => $job_doc->{info},
        tasks => [ $stage_info->{upload} ],
        template => $stage_info->{template}{$version} || $self->{default_template_version},
        enviroment => $stage_info->{enviroment}{$version} || $self->{default_pipeline_commit}
    };
    if (! $awe_history->{info}{submittime}) {
        $awe_history->{info}{submittime} = $job->{created_on};
    }
    $awe_history->{info}{userattr}{status} = $job->{public} ? 'public' : 'private';
    
    # upload stage
    push @{ $awe_history->{tasks}[0]{inputs} }, {
        file_name => $job->{file},
        file_size => $job->{file_size_raw},
        file_md5  => $job->{file_checksum_raw},
        node_id   => $upload->{node_id},
        url       => $upload->{url}
    };
    
    # remaining stages
    foreach my $st (@{$stage_info->{tasks}}) {
        # copy stage
        my $ht = clone($st);
        # get useage by version
        $ht->{uses} = [];
        foreach my $stu (@{$st->{uses}}) {
            if  (exists $stu->{versions}{$version}) {
                my $htu = clone($stu);
                delete $htu->{versions};
                push @{$ht->{uses}}, $htu;
            }
        }
        # get inputs / outputs by members
        foreach my $dt (@{$job_doc->{tasks}}) {
            if (exists $st->{members}{ $dt->{cmd}{description} }) {
                # hash structure
                if ($is_template) {
                    while (my ($fname, $input) = each %{$dt->{inputs}}) {
                        my $origin = undef;
                        if (exists($input->{origin}) && ($input->{origin} =~ /^\d+$/)) {
                            $origin = $job_doc->{tasks}[ int($input->{origin}) ]{cmd}{description};
                        }
                        push @{$ht->{inputs}}, {
                            parent => $origin,
                            file_name => $fname
                        };
                    }
                    while (my ($fname, $output) = each %{$dt->{outputs}}) {
                        my $hto = {
                            temperary => (exists($output->{delete}) && ($output->{delete} eq 'true')) ? 1 : 0,
                            file_name => $fname,
                        };
                        if (exists $setmap{$fname}) {
                            $filemap{$fname}   = 1;
                            $hto->{file_size}  = $setmap{$fname}{file_size};
                            $hto->{file_md5}   = $setmap{$fname}{file_md5};
                            $hto->{node_id}    = $setmap{$fname}{node_id};
                            $hto->{url}        = $setmap{$fname}{url};
                            $hto->{statistics} = $setmap{$fname}{statistics};
                        }
                        push @{$ht->{outputs}}, $hto;
                    }
                }
                # array structure
                else {
                    foreach my $input (@{$dt->{inputs}}) {
                        my $origin = undef;
                        if (exists($input->{origin}) && ($input->{origin} =~ /^\d+$/)) {
                            $origin = $job_doc->{tasks}[ int($input->{origin}) ]{cmd}{description};
                        }
                        push @{$ht->{inputs}}, {
                            parent => $origin,
                            file_name => $input->{filename},
                            file_size => $input->{size}
                        };
                    }
                    foreach my $output (@{$dt->{outputs}}) {
                        my $hto = {
                            temperary => (exists($output->{delete}) && ($output->{delete} eq 'true')) ? 1 : 0,
                            file_name => $output->{filename},
                            file_size => $output->{size}
                        };
                        if (exists $setmap{$output->{filename}}) {
                            $filemap{$output->{filename}} = 1;
                            $hto->{file_md5}   = $setmap{$output->{filename}}{file_md5};
                            $hto->{node_id}    = $setmap{$output->{filename}}{node_id};
                            $hto->{url}        = $setmap{$output->{filename}}{url};
                            $hto->{statistics} = $setmap{$output->{filename}}{statistics};
                        }
                        push @{$ht->{outputs}}, $hto;
                    }
                }
            }
        }
        push @{ $awe_history->{tasks} }, $ht;
    }
    
    # bookkeeping to check for missed downloadable files
    if ($debug) {
        $awe_history->{missing} = [];
        while (my ($fname, $status) = each %filemap) {
            if ($status == 0) {
                push @{$awe_history->{missing}}, $setmap{$fname};
            }
        }
    }
    $data->{data} = $awe_history;
    
    # POST to shock if created
    my $new_node = undef;
    if ((scalar(@$nodes) == 0) || $force) {
        my $shock_attr = {
            id            => $mgid,
            job_id        => $job->{job_id},
            created       => $job->{created_on},
            name          => $job->{name},
            owner         => 'mgu'.$job->{owner},
            sequence_type => $job->{sequence_type},
            status        => $job->{public} ? 'public' : 'private',
            project_id    => undef,
            project_name  => undef,
            type          => 'metagenome',
            data_type     => 'awe_workflow',
            workflow_type => $is_template ? 'template' : 'full',
            awe_id        => $awe_id,
            file_format   => 'json'
        };
        eval {
            my $proj = $job->primary_project;
            if ($proj->{id}) {
                $shock_attr->{project_id} = 'mgp'.$proj->{id};
                $shock_attr->{project_name} = $proj->{name};
            }
        };
        my $new_node = $self->set_shock_node($mgid.'.awe.json', $job_doc, $shock_attr, $self->mgrast_token);
    }
    if ($new_node && $debug) {
        $data->{node} = $new_node->{id};
    }
    
    # delete old from shock if force re-create and success
    if ((scalar(@$nodes) > 0) && $new_node && $force) {
        foreach my $n (@$nodes) {
             $self->delete_shock_node($n->{id}, $self->mgrast_token);
         }
    }
    
    # delete if success and requested and user is admin
    if (((scalar(@$nodes) > 0) || $new_node) && $delete && $self->user->is_admin('MGRAST')) {
        $self->awe_job_action($awe_id, "delete", $self->mgrast_token);
    }
    
    return $data;
}

# this produces a generic AWE workflow for a job at a given version
sub get_workflow_from_template {
    my ($self, $job) = @_;
    
    use Pipeline;
    my $input_id = "";
    my $upload   = $self->get_shock_query({'id' => 'mgm'.$job->{metagenome_id}, 'stage_name' => 'upload'}, $self->mgrast_token);
    if ((@$upload > 0) && $upload->[0]{id}) {
        $input_id = $upload->[0]{id};
    }
    my $jattr = $job->data();
    my $jstat = $job->stats();
    my $jopts = Pipeline::get_job_options($job->{options});
    my $vars  = Pipeline::template_keywords();
    my $version = $jattr->{pipeline_version} || $self->{default_pipeline_version};
    $vars->{pipeline_version} = $version;
    $vars->{bp_count} = $jstat->{bp_count_raw};
    $vars->{priority} = Pipeline::set_priority($jstat->{bp_count_raw}, $jattr->{priority});
    
    return Pipeline::populate_template($job, $jattr, $jopts, $vars, $input_id, $version, 1);
}

1;
