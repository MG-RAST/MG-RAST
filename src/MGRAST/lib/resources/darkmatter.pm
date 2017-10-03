package resources::darkmatter;

use strict;
use warnings;
no warnings('once');

use Data::Dumper;
use POSIX qw(strftime);
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "darkmatter";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->url."/".$self->name,
        'description' => "An analysis file from the processing of a metagenome from a specific stage in its analysis",
        'type' => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests' => [
            {
                'name'        => "info",
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
            {
                'name'        => "instance",
                'request'     => $self->url."/".$self->name."/{ID}",
                'description' => "Returns a darkmatter sequence file.",
                'example'     => [ $self->url."/".$self->name."/mgm4447943.3?",
      				               'download fasta file of gene-called protein sequences with no similarities' ],
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => {
                    'id'     => [ 'string', 'unique metagenome identifier' ],
                    'status' => [ 'string', 'cv', ['submitted', 'darkmatter is has been submitted'],
                                                  ['processing', 'darkmatter is still computing'],
                                                  ['done', 'darkmatter is done'] ],
                    'url'     => [ 'url', 'resource location of this object instance'],
                    'name'    => [ 'string', 'name of the file' ],
                    'size'    => [ 'integer', 'size of file in bytes' ],
                    'md5'     => [ 'string', 'md5sum of file' ],
                },
                'parameters'  => {
                    'options'  => {},
                    'required' => { "id" => [ "string", "unique metagenome identifier" ] },
                    'body'     => {}
                }
			},
        ]
    };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;

    # check id format
    my $rest   = $self->rest;
    my $debug  = $self->cgi->param('debug') ? 1 : 0;
    my $restid = $rest->[0];
    my $tempid = $self->idresolve($restid);
    my (undef, $id) = $tempid =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: ".$restid}, 400 );
    }

    # get database / data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $restid does not exist"}, 404 );
    }
    $job = $job->[0];
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id $restid is still processing and unavailable"}, 404 );
    }
    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || ($self->user && $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    # get download set for metagenome
    my $version = $job->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
    my ($setlist, $skip) = $self->get_download_set($job->{metagenome_id}, $version, $self->mgrast_token);
    $setlist = $self->fix_download_filenames($setlist, $restid);
    
    # see if darkmatter file already exists
    foreach my $set (@$setlist) {
        if (($set->{stage_name} eq 'darkmatter') && ($set->{data_type} eq 'sequence') && ($set->{file_size} > 0)) {
            my $preauth = $self->get_shock_preauth($set->{node_id}, $self->mgrast_token, $set->{file_name});
            $self->return_data({
                id     => $restid,
                status => 'done',
                url    => $preauth->{url},
                name   => $set->{file_name},
                size   => $set->{file_size},
                md5    => $set->{file_md5},
                timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
            });
        }
    }
    
    # see if running in AWE
    my $dm_query = {
        "info.pipeline" => 'darkmatter',
        "info.name"     => 'DM:'.$job->job_id
    };
    my $dm_jobs = $self->get_awe_query($dm_query, $self->mgrast_token);
    if ($dm_jobs->{data} && (scalar(@{$dm_jobs->{data}}) > 0)) {
        $self->return_data({
            id     => $restid,
            job    => $dm_jobs->{data}[0]{id},
            status => 'processing',
            timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
        });
    }
    
    #### need to create darkmatter file
    my @map_files = ();
    my @sim_files = ();
    my $awe_info  = {
        job_name     => 'DM:'.$job->job_id,
        project_name => $job->primary_project->{name} || undef,
        user         => 'mgu'.$self->user->{_id},
        mg_id        => 'mgm'.$job->metagenome_id,
        job_id       => $job->job_id,
        mg_name      => $job->name,
        job_date     => $job->created_on,
        status       => $job->public ? 'public' : 'private',
        seq_type     => $job->sequence_type,
        project_id   => $job->primary_project->{id} || undef,
        shock_url    => $Conf::shock_url
    };
    # find input files - take filtering if exists otherwise use genecalling
    my ($geneset, $filterset, $awe_files);
    foreach my $set (@$setlist) {
        next unless ($set->{file_size} && ($set->{file_size} > 0));
        if (($set->{data_type} eq 'sequence') && ($set->{stage_name} eq 'genecalling')) {
            $geneset = $set;
        } elsif (($set->{data_type} eq 'sequence') && ($set->{stage_name} eq 'filtering')) {
            $filterset = $set;
        }
        if (($set->{data_type} eq 'similarity') && ($set->{stage_name} eq 'rna.sims')) {
            push @sim_files, $set;
        }
        if (($set->{data_type} eq 'similarity') && ($set->{stage_name} eq 'protein.sims')) {
            push @sim_files, $set;
        }
        if (($set->{data_type} eq 'cluster') && ($set->{stage_name} eq 'rna.cluster.map')) {
            push @map_files, $set;
        }
        if (($set->{data_type} eq 'cluster') && ($set->{stage_name} eq 'protein.cluster.map')) {
            push @map_files, $set;
        }
    }
    # process sequence input
    if ($filterset && ref($filterset)) {
        $awe_files = [{
            filename => $filterset->{file_name},
            host     => $Conf::shock_url,
            node     => $filterset->{node_id}
        }];
        $awe_info->{input_opts} = '-i @'.$filterset->{file_name};
    } elsif ($geneset && ref($geneset)) {
        $awe_files = [{
            filename => $geneset->{file_name},
            host     => $Conf::shock_url,
            node     => $geneset->{node_id}
        }];
        $awe_info->{input_opts} = '-i @'.$geneset->{file_name};
    } else {
        $self->return_data( {"ERROR" => "dataset $restid missing required genecalling file"}, 404 );
    }
    # process sim / map inputs
    if (scalar(@sim_files) == 0) {
        $self->return_data( {"ERROR" => "dataset $restid missing required similarity file"}, 404 );
    }
    foreach my $s (@sim_files) {
        push @$awe_files, {
            filename => $s->{file_name},
            host     => $Conf::shock_url,
            node     => $s->{node_id}
        };
        $awe_info->{input_opts} .= ' -s @'.$s->{file_name};
    }
    foreach my $m (@map_files) {
        push @$awe_files, {
            filename => $m->{file_name},
            host     => $Conf::shock_url,
            node     => $m->{node_id}
        };
        $awe_info->{input_opts} .= ' -m @'.$m->{file_name};
    }
    $awe_info->{input_files} = $self->json->encode($awe_files);
    
    # submit to AWE
    my $awejob = $self->submit_awe_template($awe_info, $Conf::mgrast_darkmatter_workflow, $self->mgrast_token, 'mgrast', $debug);
    if ($debug) {
        $self->return_data($awejob);
    }
    my $response = {
        id     => $restid,
        job    => $awejob->{id},
        status => 'submitted',
        timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    $self->return_data($response);
}

1;
