#!/usr/bin/env perl

use lib "/MG-RAST/conf";
use lib "/MG-RAST/site/lib/MGRAST";

use strict;
use warnings;
no warnings('once');

use PipelineJob;
use PipelineAWE_Conf;

use JSON;
use Template;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use File::Slurp;

# options
my $job_id    = "";
my $awe_url   = "";
my $shock_url = "";
my $template  = "mgrast-prod-annotation.awe.template";
my $pipeline  = "mgrast-prod";
my $type      = "metagenome";
my $priority  = 1000;
my $help      = 0;
my $no_start  = 0;
my $use_docker   = 0;
my $clientgroups = undef;

my $options = GetOptions (
        "job_id=s"    => \$job_id,
        "awe_url=s"   => \$awe_url,
        "shock_url=s" => \$shock_url,
        "template=s"  => \$template,
        "priority=s"  => \$priority,
        "no_start!"   => \$no_start,
        "use_docker!" => \$use_docker, # enables docker specific workflow entries, dockerimage and environ
    	"clientgroups=s" => \$clientgroups,
        "help!"       => \$help
);

if ($help) {
    print get_usage();
    exit 0;
} elsif (! $job_id) {
    print STDERR "ERROR: A job identifier is required.\n";
    exit 1;
}

# set obj handles
my $jobdb = PipelineJob::get_jobcache_dbh(
    $PipelineAWE_Conf::job_dbhost,
    $PipelineAWE_Conf::job_dbname,
    $PipelineAWE_Conf::job_dbuser,
    $PipelineAWE_Conf::job_dbpass
);
my $tpage = Template->new(ABSOLUTE => 1);
my $agent = LWP::UserAgent->new();
$agent->timeout(3600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# get default urls
my $vars = $PipelineAWE_Conf::template_keywords;
if ($shock_url) {
    $vars->{shock_url} = $shock_url;
}
if (! $awe_url) {
    $awe_url = $PipelineAWE_Conf::awe_url;
}

# get job related info from DB
my $jobj = PipelineJob::get_jobcache_info($jobdb, $job_id);
unless ($jobj && (scalar(keys %$jobj) > 0) && exists($jobj->{options})) {
    print STDERR "ERROR: Job $job_id does not exist.\n";
    exit 1;
}
my $jattr = PipelineJob::get_job_attributes($jobdb, $job_id);

# populate workflow variables
$vars->{job_id}         = $job_id;
$vars->{mg_id}          = 'mgm'.$jobj->{metagenome_id};
$vars->{mg_name}        = $jobj->{name};
$vars->{job_date}       = $jobj->{created_on};
$vars->{status}         = $jobj->{public} ? "public" : "ptivate";
$vars->{file_format}    = ($jattr->{file_type} && ($jattr->{file_type} eq 'fastq')) ? 'fastq' : 'fasta';
$vars->{seq_type}       = $jobj->{sequence_type} || $jattr->{sequence_type_guess};
$vars->{project_id}     = $jobj->{project_id} || '';
$vars->{project_name}   = $jobj->{project_name} || '';
$vars->{user}           = 'mgu'.$jobj->{owner} || '';
$vars->{pipeline}       = $pipeline;
$vars->{type}           = $type;
$vars->{priority}       = $priority;

if (defined $clientgroups) {
	$vars->{clientgroups} = $clientgroups;
}

$vars->{docker_image_version} = 'latest';
if ($use_docker) {
	$vars->{docker_switch} = '';
} else {
	$vars->{docker_switch} = '_'; # disables these entries
}

# get job files
my @nids = ();
my $gres = undef;
my $nget = $agent->get(
    $vars->{shock_url}.'/node?query&type=metagenome&limit=0&job_id='.$job_id,
    'Authorization', $PipelineAWE_Conf::shock_pipeline_token
);
eval {
    $gres = $json->decode($nget->content);
};
if ($@) {
    print STDERR "ERROR: Return from shock is not JSON:\n".$nget->content."\n";
    exit 1;
}
if ($gres->{error}) {
    print STDERR "ERROR: (shock) ".$gres->{error}[0]."\n";
    exit 1;
}

foreach my $n (@{$gres->{data}}) {
    unless (exists($n->{attributes}{stage_name}) && exists($n->{attributes}{data_type})) {
        next;
    }
    if ($n->{attributes}{stage_name} eq 'protein.sims') {
        $vars->{prot_sims_file} = $n->{file}{name};
        $vars->{prot_sims_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'rna.sims') {
        $vars->{rna_sims_file} = $n->{file}{name};
        $vars->{rna_sims_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'filter.sims') {
        $vars->{sim_seq_file} = $n->{file}{name};
        $vars->{sim_seq_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'qc') {
        $vars->{assembly_file} = $n->{file}{name};
        $vars->{assembly_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'rna.cluster') && ($n->{attributes}{data_type} eq 'cluster')) {
        $vars->{rna_mapping_file} = $n->{file}{name};
        $vars->{rna_mapping_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'protein.cluster') && ($n->{attributes}{data_type} eq 'cluster')) {
        $vars->{prot_mapping_file} = $n->{file}{name};
        $vars->{prot_mapping_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'done') {
        $vars->{mg_stats_node} = $n->{id};
    }
}

foreach my $x (("prot_sims_node", "rna_sims_node", "sim_seq_node", "assembly_node", "rna_mapping_node", "prot_mapping_node", "mg_stats_node")) {
    if (! $vars->{$x}) {
        print STDERR "ERROR: Incomplete metagenome, missing stage: $x\n";
        exit 1;
    }
}

# create workflow
my $workflow_str = "";
my $template_str = read_file($PipelineAWE_Conf::BASE."/conf/".$template);
$tpage->process(\$template_str, $vars, \$workflow_str) || die $tpage->error()."\n";

# write to file for debugging puposes (first time)
my $workflow_file = $PipelineAWE_Conf::temp_dir."/".$job_id.".annotation_workflow.json";
write_file($workflow_file, $workflow_str);

# test mode
if ($no_start) {
    print "workflow\t".$workflow_file."\n";
    exit 0;
}

# submit to AWE
my $apost = $agent->post(
    $awe_url.'/job',
    'Datatoken', $PipelineAWE_Conf::shock_pipeline_token,
    'Authorization', $PipelineAWE_Conf::awe_pipeline_token,
    'Content_Type', 'multipart/form-data',
    #'Content', [ upload => [$workflow_file] ]
	'Content', [ upload => [undef, "n/a", Content => $workflow_str] ]
);

my $ares = undef;
eval {
    $ares = $json->decode($apost->content);
};
if ($@) {
    print STDERR "ERROR: Return from AWE is not JSON:\n".$apost->content."\n";
    exit 1;
}
if ($ares->{error}) {
    print STDERR "ERROR: (AWE) ".$ares->{error}[0]."\n";
    exit 1;
}

# get info
my $awe_id  = $ares->{data}{id};
my $awe_job = $ares->{data}{jid};
my $state   = $ares->{data}{state};
print "awe job (".$ares->{data}{jid}.")\t".$ares->{data}{id}."\n";

# update job
PipelineJob::set_jobcache_info($jobdb, $job_id, 'viewable', 0);
PipelineJob::set_job_attributes($jobdb, $job_id, {"pipeline_id" => $awe_id});

sub get_usage {
    return "USAGE: resubmit_annotation_to_awe.pl -job_id=<job identifier> -awe_url=<awe url> -shock_url=<shock url> -template=<template file> -clientgroups=<group list> -priority=<pipeline priority> -no_start -use_docker\n";
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }
