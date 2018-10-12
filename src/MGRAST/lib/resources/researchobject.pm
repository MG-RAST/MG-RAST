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
        ]]},
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
                'name'        => "instance",
                'request'     => $self->url."/".$self->name."/{id}",
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
        }
    };
    
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    $self->json->utf8();
    
    # get database
    my $master = $self->connect_to_datasource();
    my $rest = $self->rest;
    
    # check id format
    my $tempid = $self->idresolve($rest->[0]);
    my (undef, $id) = $tempid =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $id does not exist"}, 404 );
    }
    $job = $job->[0];
    
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id $restid is still processing and unavailable"}, 404 );
    }
    
    # create manifest
    my $manifest = {
        "id" => $rest->[0],
        "manifest" => "manifest.json",
        "createdOn" => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
        "createdBy" => {
            "uri" => $self->url,
            "name" => "MG-RAST"
        },
        "aggregates" => []
    };
    
    # set files
    my $jdata   = $job->data;
    my $version = $jdata->{pipeline_version} || $self->{default_pipeline_version};
    my ($setlist, $skip) = $self->get_download_set($job->{metagenome_id}, $version, $self->mgrast_token);
    $setlist = $self->fix_download_filenames($setlist, $restid);
    $setlist = $self->clean_setlist($setlist, $job);
    
    foreach my $set (@$stelist) {
        if (exists $set->{url}) {
            push @{$manifest->{aggregates}}, {
                "uri" => $set->{url},
                "bundledAs" => {
                    "folder" => "data",
                    "file" => $set->{file_name}
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
    $workflow .= ".workflow.cwl";
    my $workflowurl = $self->{cwl_url}."/PackedWorkflow/".$workflow;
    push @{$manifest->{aggregates}}, {
        "uri" => $workflowurl,
        "bundledAs" => {
            "folder" => "workflow",
            "file" => $workflow
        }
    };
    
    # set tools
    my $packed = $self->get_url_content($workflowurl);
    foreach my $obj (@{$packed->{'$graph'}}) {
        my $dir = "";
        my $name = $obj->{'id'};
        $name =~ tr/#//d;
        if ($obj->{'class'} eq 'CommandLineTool') {
            $dir = "Tools";
        } elsif ($obj->{'class'} eq 'Workflow') {
            $dir = "Workflows";
        }
        if ($dir) {
            push @{$manifest->{aggregates}}, {
                "uri" => $self->{cwl_url}."/".$dir."/".$name;
                "bundledAs" => {
                    "folder" => "snapshot",
                    "file" => $name
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
        my $get = $self->agent->get();
        $content = $self->json->decode( $get->content );
    };
    return $content;
}

1;
