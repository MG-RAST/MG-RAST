#!/usr/bin/env perl

use lib "/MG-RAST/conf";
use lib "/MG-RAST/site/lib/MGRAST";

use strict;
use warnings;
no warnings('once');

use Pipeline;
use Conf;

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
my $template  = "mgrast-prod-annotation.awf";
my $pipeline  = "mgrast-annotation";
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
my $jobdb = Pipeline::get_jobcache_dbh(
    $Conf::mgrast_jobcache_host,
    $Conf::mgrast_jobcache_db,
	$Conf::mgrast_jobcache_user,
	$Conf::mgrast_jobcache_password
);
my $tpage = Template->new(ABSOLUTE => 1);
my $agent = LWP::UserAgent->new();
$agent->timeout(3600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# get default urls
my $vars = Pipeline::template_keywords;
if ($shock_url) {
    $vars->{shock_url} = $shock_url;
}
if (! $awe_url) {
    $awe_url = $Conf::awe_url;
}

# get job related info from DB
my $jobj = Pipeline::get_jobcache_info($jobdb, $job_id);
unless ($jobj && (scalar(keys %$jobj) > 0) && exists($jobj->{options})) {
    print STDERR "ERROR: Job $job_id does not exist.\n";
    exit 1;
}
my $jattr = Pipeline::get_job_attributes($jobdb, $job_id);

# populate workflow variables
$vars->{job_id}         = $job_id;
$vars->{mg_id}          = 'mgm'.$jobj->{metagenome_id};
$vars->{mg_name}        = $jobj->{name};
$vars->{job_date}       = $jobj->{created_on};
$vars->{status}         = $jobj->{public} ? "public" : "private";
$vars->{file_format}    = ($jattr->{file_type} && ($jattr->{file_type} eq 'fastq')) ? 'fastq' : 'fasta';
$vars->{seq_type}       = $jobj->{sequence_type} || $jattr->{sequence_type_guess};
$vars->{project_id}     = $jobj->{project_id} || '';
$vars->{project_name}   = $jobj->{project_name} || '';
$vars->{user}           = 'mgu'.$jobj->{owner} || '';
$vars->{type}           = $type;
$vars->{pipeline}       = $pipeline;
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
my $sres = undef;
my $sget = $agent->get(
    $vars->{shock_url}.'/node?query&type=metagenome&limit=0&job_id='.$job_id,
    'Authorization', $Conf::pipeline_token
);
eval {
    $sres = $json->decode($sget->content);
};
if ($@) {
    print STDERR "ERROR: Return from shock is not JSON:\n".$sget->content."\n";
    exit 1;
}
if ($sres->{error}) {
    print STDERR "ERROR: (shock) ".$sres->{error}[0]."\n";
    exit 1;
}

my %delete_file = (
    $job_id.".450.rna.sims.filter" => 1,
    $job_id.".450.rna.expand.rna" => 1,
    $job_id.".450.rna.expand.lca" => 1,
    $job_id.".650.aa.sims.filter" => 1,
    $job_id.".650.aa.expand.protein" => 1,
    $job_id.".650.aa.expand.lca" => 1,
    $job_id.".650.aa.expand.ontology" => 1,
    $job_id.".700.annotation.sims.filter.seq.index" => 1,
    $job_id.".700.annotation.source.stats" => 1
);
my @delete_node = ();

foreach my $n (@{$sres->{data}}) {
    unless (exists($n->{attributes}{stage_name}) && exists($n->{attributes}{data_type}) && exists($n->{file}{name})) {
        next;
    }
    if (($n->{attributes}{stage_name} eq 'qc') && ($n->{file}{name} =~ /assembly\.coverage$/)) {
        $vars->{assembly_file} = $n->{file}{name};
        $vars->{assembly_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'qc') && ($n->{file}{name} =~ /qc\.stats$/)) {
        $vars->{qc_stats_file} = $n->{file}{name};
        $vars->{qc_stats_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'qc') && ($n->{file}{name} =~ /upload\.stats$/)) {
        $vars->{upload_stats_file} = $n->{file}{name};
        $vars->{upload_stats_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'preprocess') && ($n->{attributes}{data_type} eq 'passed')) {
        $vars->{preprocess_passed_file} = $n->{file}{name};
        $vars->{preprocess_passed_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'dereplication') && ($n->{attributes}{data_type} eq 'removed')) {
        $vars->{dereplication_removed_file} = $n->{file}{name};
        $vars->{dereplication_removed_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'screen') {
        $vars->{screen_passed_file} = $n->{file}{name};
        $vars->{screen_passed_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'rna.filter') {
        $vars->{rna_filter_file} = $n->{file}{name};
        $vars->{rna_filter_node} = $n->{id};
    } elsif ($n->{attributes}{stage_name} eq 'genecalling') {
        $vars->{genecalling_file} = $n->{file}{name};
        $vars->{genecalling_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'rna.cluster') && ($n->{file}{name} =~ /cluster\.rna97\.mapping$/)) {
        $vars->{rna_mapping_file} = $n->{file}{name};
        $vars->{rna_mapping_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'rna.cluster') && ($n->{file}{name} =~ /cluster\.rna97\.fna$/)) {
        $vars->{rna_cluster_file} = $n->{file}{name};
        $vars->{rna_cluster_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'protein.cluster') && ($n->{file}{name} =~ /cluster\.aa90\.mapping$/)) {
        $vars->{prot_mapping_file} = $n->{file}{name};
        $vars->{prot_mapping_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'protein.cluster') && ($n->{file}{name} =~ /cluster\.aa90\.faa$/)) {
        $vars->{prot_cluster_file} = $n->{file}{name};
        $vars->{prot_cluster_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'protein.sims') && ($n->{file}{name} =~ /superblat\.sims$/)) {
        $vars->{prot_sims_file} = $n->{file}{name};
        $vars->{prot_sims_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'rna.sims') && ($n->{file}{name} =~ /rna\.sims$/)) {
        $vars->{rna_sims_file} = $n->{file}{name};
        $vars->{rna_sims_node} = $n->{id};
    } elsif (($n->{attributes}{stage_name} eq 'filter.sims') && ($n->{file}{name} =~ /annotation\.sims\.filter\.seq$/)) {
        $vars->{sim_seq_file} = $n->{file}{name};
        $vars->{sim_seq_node} = $n->{id};
    } elsif (exists $delete_file{$n->{file}{name}}) {
        push @delete_node, $n->{id};
    }
}

foreach my $x (("assembly_node", "qc_stats_node", "upload_stats_node", "preprocess_passed_node", "dereplication_removed_node", "screen_passed_node", "rna_filter_node", "genecalling_node", "rna_mapping_node", "rna_cluster_node", "prot_mapping_node", "prot_cluster_node", "prot_sims_node", "rna_sims_node", "sim_seq_node")) {
    if (! $vars->{$x}) {
        print STDERR "ERROR: Incomplete metagenome, missing stage: $x\n";
        exit 1;
    }
}

# deleting duplicate nodes
foreach my $n (@delete_node) {
    $self->agent->delete($Conf::shock_url.'/node/'.$n, ('Authorization', $Conf::pipeline_token));
}

# create workflow
my $workflow_str = "";
my $template_str = read_file($Conf::workflow_dir."/".$template);
$tpage->process(\$template_str, $vars, \$workflow_str) || die $tpage->error()."\n";

# write to file for debugging puposes (first time)
my $workflow_file = $Conf::temp."/".$job_id.".".$pipeline.".json";
write_file($workflow_file, $workflow_str);

# test mode
if ($no_start) {
    print "workflow\t".$workflow_file."\n";
    exit 0;
}

# submit to AWE
my $apost = $agent->post(
    $awe_url.'/job',
    'Datatoken', $Conf::pipeline_token,
    'Authorization', $Conf::pipeline_token,
    'Content_Type', 'multipart/form-data',
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
Pipeline::set_jobcache_info($jobdb, $job_id, 'viewable', 0);
Pipeline::set_job_attributes($jobdb, $job_id, {"pipeline_id" => $awe_id});

sub get_usage {
    return "USAGE: resubmit_annotation_to_awe.pl -job_id=<job identifier> -awe_url=<awe url> -shock_url=<shock url> -template=<template file> -clientgroups=<group list> -priority=<pipeline priority> -no_start -use_docker\n";
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }
