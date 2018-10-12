package resources::researchobject;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

use POSIX qw(strftime);

# Override parent constructor
sub new {
    my ( $class, @args ) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);

    # Add name / attributes
    $self->{name} = "researchobject";
    $self->{attributes} = {
        "id" => [ 'string', 'unique metagenome identifier' ],
        "manifest" => [ 'string', 'name of this file' ],
        "createdOn" => [ 'date', 'time this manifest was created' ],
        "createdBy" => [ 'object', [ {
            'uri' => [ 'uri', 'location of this object creator' ],
            'name' => [ 'string', 'name of this object creator' ]
        }]],
        "aggregates" => [ 'list', [ 'object', [{
            'uri' => [ 'uri', 'location of file in manifest' ],
            'bundledAs' => [ 'object', [ {
                'folder' => [ 'string', 'directory path for file' ],
                'file' => [ 'string', 'name for file' ]
            }]]
        }]]]
    };
    $self->{cwl_url} = "https://raw.githubusercontent.com/MG-RAST/pipeline/master/CWL";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name'          => $self->name,
        'url'           => $self->url."/".$self->name,
        'description'   => "Research Object Manifest for MG-RAST Metagenome",
        'type'          => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests'      => [
            {
                'name'    => "info",
                'request' => $self->url."/".$self->name,
                'description' =>
                  "Returns description of parameters and attributes.",
                'method'     => "GET",
                'type'       => "synchronous",
                'attributes' => "self",
                'parameters' => { 'options' => {}, 'required' => {}, 'body' => {} }
            },
            {
                'name'        => "manifest",
                'request'     => $self->url."/".$self->name."/manifest/{id}",
                'description' => "Returns a single manifest object.",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => $self->{attributes},
                'parameters' => {
                    'options'  => {},
                    'required' => { "id" => [ "string", "unique object identifier" ] },
                    'body'     => {}
                }
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
    } elsif ($self->rest->[0] eq 'manifest') {
        $self->manifest($self->rest->[1]);
    } else {
        $self->info();
    }
}


# the resource is called with an id parameter
sub manifest {
    my ($self, $in_id) = @_;
    
    $self->json->utf8();
    
    # get database
    my $master = $self->connect_to_datasource();
    
    # check id format
    my $tempid = $self->idresolve($in_id);
    my (undef, $id) = $tempid =~ /^(mgm)?(\d+\.\d+)$/;
    if (! $id) {
        $self->return_data( {"ERROR" => "invalid id format: ".$in_id}, 400 );
    }

    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $in_id does not exist"}, 404 );
    }
    $job = $job->[0];
    
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id $in_id is still processing and unavailable"}, 404 );
    }
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    # create manifest
    my $manifest = {
        '@context' => [
            { '@base' => "/metadata/" },
            "https://w3id.org/bundle/context"
        ],
        "id" => '/',
        "manifest" => "manifest.json",
        "createdOn" => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
        "createdBy" => {
            "uri" => $self->url,
            "name" => "MG-RAST"
        },
        "retrievedFrom" => $self->url."/".$self->name."/manifest/".$in_id,
        "aggregates" => []
    };
    if ($self->user) {
        $manifest->{"retrievedBy"} = 'mgu'.$self->user->_id;
    }
    
    # set files
    my $jdata   = $job->data;
    my $version = $jdata->{pipeline_version} || $self->{default_pipeline_version};
    my ($setlist, $skip) = $self->get_download_set($job->{metagenome_id}, $version, $self->mgrast_token);
    $setlist = $self->fix_download_filenames($setlist, $in_id);
    $setlist = $self->clean_setlist($setlist, $job);
    
    foreach my $set (@$setlist) {
        if (exists $set->{url}) {
            push @{$manifest->{aggregates}}, {
                "uri" => $set->{url},
                "mediatype" => "text/plain; charset=\"UTF-8\"",
                "bundledAs" => {
                    "folder" => "/data/",
                    "filename" => $set->{file_name}
                }
            };
        }
    }
    
    # set workflow
    my $informat   = ($setlist->[0]{file_format} eq 'fastq') ? 'fastq' : 'fasta';
    my $seq_type   = $job->sequence_type;
    my $bowtie     = $jdata->{bowtie} ? 1 : 0;
    my $assembeled = $jdata->{assembeled} ? 1 : 0;
    if ($seq_type eq 'MT') {
        $seq_type = 'WGS';
    }
    my $workflow = $assembeled ? 'assembeled' : lc($seq_type);
    if ((! $bowtie) && ($seq_type eq 'WGS')) {
        $workflow .= "-noscreen";
    }
    if (! $assembeled) {
        $workflow .= "-".$informat
    }
    my $inputjob = $workflow.".job.yaml";
    my $inputjoburl = $self->{cwl_url}."/Workflows/".$inputjob;
    push @{$manifest->{aggregates}}, {
        "uri" => $inputjoburl,
        "mediatype" => "text/yaml; charset=\"UTF-8\"",
        "bundledAs" => {
            "folder" => "/snapshot/",
            "filename" => $inputjob
        }
    };
    $workflow .= ".workflow.cwl";
    my $workflowurl = $self->{cwl_url}."/PackedWorkflow/".$workflow;
    push @{$manifest->{aggregates}}, {
        "uri" => $workflowurl,
        "mediatype" => "application/json",
        "bundledAs" => {
            "folder" => "/workflow/",
            "filename" => $workflow
        }
    };
    
    # predata download script
    push @{$manifest->{aggregates}}, {
        "uri" => $self->{cwl_url}."/Inputs/DBs/getpredata.sh",
        "mediatype" => "application/x-sh",
        "bundledAs" => {
            "folder" => "/snapshot/DBs",
            "filename" => "getpredata.sh"
        }
    }
    
    # set tools / sub-workflows
    my $packed = $self->get_url_content($workflowurl);
    foreach my $obj (@{$packed->{'$graph'}}) {
        my $dir = "";
        my $name = $obj->{'id'};
        $name =~ tr/#//d;
        if ($name eq 'main') {
            next;
        }
        if ($obj->{'class'} eq 'CommandLineTool') {
            $dir = "Tools";
        } elsif ($obj->{'class'} eq 'Workflow') {
            $dir = "Workflows";
        }
        if ($dir) {
            push @{$manifest->{aggregates}}, {
                "uri" => $self->{cwl_url}."/".$dir."/".$name,
                "mediatype" => "text/x+yaml; charset=\"UTF-8\"",
                "conformsTo" => "https://w3id.org/cwl/",
                "bundledAs" => {
                    "folder" => "/snapshot/",
                    "filename" => $name
                }
            };
        }
    }
    
    $self->return_data($manifest);
};

sub get_url_content {
    my ($self, $url) = @_;
    
    my $content = "";
    eval {
        my $get = $self->agent->get($url);
        $content = $self->json->decode( $get->content );
    };
    return $content;
}

1;
