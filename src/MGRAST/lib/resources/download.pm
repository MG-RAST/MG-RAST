package resources::download;

use strict;
use warnings;
no warnings('once');

use Data::Dumper;
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
				              'description' => "Document of MG-RAST analysis-pipeline workflow and logs.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3/history",
      				                             'Workflow document for mgm4447943.3' ],
				              'method'      => "GET",
				              'type'        => "synchronous",
				              'attributes'  => { "data" => [ 'file', 'requested workflow file' ] },
				              'parameters'  => { 'options'  => { "awe_id" => ["string", "AWE ID of MG-RAST metagenome"],
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
    my $setlist = $self->get_download_set($job->{metagenome_id}, $self->mgrast_token);
    
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
    
    # get shock node and file
    if (! $force) {
        my $squery = {
            id         => $mgid,
            data_type  => 'awe_history',
            stage_name => 'done'
        };
        my $nodes = $self->get_shock_query($squery, $self->mgrast_token);
        if (scalar(@nodes) > 0) {
            my $content = $self->get_shock_file($nodes->[0]{id}, undef, $self->mgrast_token);
            my $data = undef;
            eval {
                $data = $self->json->decode($content);
            };
            if ($data) {
                return $data;
            }
        }
    }
    # not in shock / create from AWE
    if (! $awe_id) {
        my $jdata = $job->data();
        if ($jdata->{pipeline_id}) {
            $awe_id = $jdata->{pipeline_id};
        }
    }
    my $awe_job = undef;
    if ($awe_id) {
        
    }
    
    # get AWE document and report
    my $awe_job = $self->get_awe_job($awe_id, $self->mgrast_token);
    my $awe_log = $self->get_awe_log($awe_id, $self->mgrast_token);
    if ($awe_job->{info}{id} ne $mgid) {
        $self->return_data( {"ERROR" => "Inputed MG-RAST ID does not match pipeline document"}, 404)
    }
    # condense report, merge into workflow
    my $task_len = scalar(@{$awe_job->{tasks}})
    my $awe_history = awe_job;
    for (my $i=0; $i <= $task_len; $i++) {
        
    }
        
    ### TODO ###
    # POST to shock
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
        data_type     => 'awe_history',
        awe_id        => $awe_id,
        file_format   => 'json',
        stage_name    => 'done',
        stage_id      => '999'
    };
    eval {
        my $proj = $job->primary_project;
        if ($proj->{id}) {
            $shock_attr->{project_id} = 'mgp'.$proj->{id};
            $shock_attr->{project_name} = $proj->{name};
        }
    };
    my $job_node = $self->set_shock_node($mgid.'.awe.json', $awe_history, $shock_attr, $self->mgrast_token);
    # delete if requested and user is admin
    if ($job_node && $job_node->{id} && $delete && $self->user->is_admin('MGRAST')) {
        $self->awe_job_action($awe_id, "delete", $self->mgrast_token);
    }
    return $awe_history;
}

# this produces a generic AWE workflow for a job at a given version
sub get_workflow_from_template {
    my ($self, $job) = @_;
    
    use Pipeline;
    my $input_id = "";
    my $upload   = $self->get_shock_query({'id' => 'mgm'.$mgid, 'stage_name' => 'upload'}, $self->mgrast_token);
    if ((@$upload > 0) && $upload->[0]{id}) {
        $input_id = $upload->[0]{id};
    }
    my $jattr = $job->data();
    my $jstat = $job->stats();
    my $jopts = Pipeline::get_job_options($job->{options});
    my $vars  = Pipeline::template_keywords();
    my $version = $jattr->{pipeline_version} || "3.0";
    $vars->{pipeline_version} = $version;
    $vars->{bp_count} = $jstat->{bp_count_raw};
    $vars->{priority} = Pipeline::set_priority($jstat->{bp_count_raw}, $jattr->{priority});
    
    return Pipeline::populate_template($job, $jattr, $jopts, $vars, $input_id, $version, 1);
}

1;
