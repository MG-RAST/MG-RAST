#!/usr/bin/env perl

# MG-RAST pipeline job submitter for AWE
# Command name: submit_to_awe
# Use case: submit a job with a local input file and a pipeline template,
#           input file is local and will be uploaded to shock automatially.
# Operations:
#      1. upload input file to shock OR copy input shock node
#      2. create job script based on job template and available info
#      3. submit the job json script to awe

use lib "/MG-RAST/conf";
use lib "/MG-RAST/site/lib/MGRAST";

use strict;
use warnings;
no warnings('once');

use Pipeline;
use Conf;

use JSON;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use File::Slurp;

# options
my $job_id     = "";
my $input_file = "";
my $input_node = "";
my $submit_id  = "";
my $awe_url    = "";
my $shock_url  = "";
my $version    = "";
my $clientgroups = undef;
my $image_ver  = "";
my $no_start   = 0;
my $use_ssh    = 0;
my $use_docker = 0;
my $help       = 0;
my $priority   = 0;

my $options = GetOptions (
    "job_id=s"       => \$job_id,
    "input_file=s"   => \$input_file,
    "input_node=s"   => \$input_node,
    "submit_id=s"    => \$submit_id,
	"awe_url=s"      => \$awe_url,
	"shock_url=s"    => \$shock_url,
	"version=s"      => \$version,
	"no_start!"      => \$no_start,
	"use_ssh!"       => \$use_ssh,
	"use_docker!"    => \$use_docker, # enables docker specific workflow entries, dockerimage and environ
	"clientgroups=s" => \$clientgroups,
	"image_ver=s"    => \$image_ver,
	"priority=i"     => \$priority,
	"help!"          => \$help
);

if ($help) {
    print get_usage();
    exit 0;
} elsif (! $job_id) {
    print STDERR "ERROR: A job identifier is required.\n";
    exit 1;
} elsif (! ($input_file || $input_node)) {
    print STDERR "ERROR: An input file or node was not specified.\n";
    exit 1;
} elsif ($input_file && (! -e $input_file)) {
    print STDERR "ERROR: The input file [$input_file] does not exist.\n";
    exit 1;
}

# set obj handles
my $jobdb = Pipeline::get_jobcache_dbh(
    $Conf::mgrast_jobcache_host,
    $Conf::mgrast_jobcache_db,
	$Conf::mgrast_jobcache_user,
	$Conf::mgrast_jobcache_password
);

my $agent = LWP::UserAgent->new();
$agent->timeout(3600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# set default url
if (! $awe_url) {
    $awe_url = $Conf::awe_url;
}

# set values based on input options
my $vars = Pipeline::template_keywords();
if ($shock_url) {
    $vars->{shock_url} = $shock_url;
}
if ($submit_id) {
    $vars->{submission_id} = $submit_id;
}
if ($version) {
    $vars->{pipeline_version} = $version;
}
if ($image_ver) {
    $vars->{docker_image_version} = $image_ver;
}
if (defined $clientgroups) {
	$vars->{clientgroups} = $clientgroups;
}

# get job related info from DB
my $jobj = Pipeline::get_jobcache_info($jobdb, $job_id);
unless ($jobj && (scalar(keys %$jobj) > 0) && exists($jobj->{options})) {
    print STDERR "ERROR: Job $job_id does not exist.\n";
    exit 1;
}
my $jstat = Pipeline::get_job_statistics($jobdb, $job_id);
my $jattr = Pipeline::get_job_attributes($jobdb, $job_id);
my $jopts = Pipeline::get_job_options($jobj->{options});

# build upload attributes
my $up_attr = {
    id          => 'mgm'.$jobj->{metagenome_id},
    job_id      => $job_id,
    name        => $jobj->{name},
    created     => $jobj->{created_on},
    status      => 'private',
    assembled   => $jattr->{assembled} ? 'yes' : 'no',
    data_type   => 'sequence',
    seq_format  => 'bp',
    file_format => ($jattr->{file_type} && ($jattr->{file_type} eq 'fastq')) ? 'fastq' : 'fasta',
    stage_id    => '050',
    stage_name  => 'upload',
    type        => 'metagenome',
    statistics  => {},
    sequence_type    => $jobj->{sequence_type} || $jattr->{sequence_type_guess},
    pipeline_version => $vars->{pipeline_version}
};

# project info
if ($jobj->{project_id} && $jobj->{project_name}) {
    $up_attr->{project_id}   = 'mgp'.$jobj->{project_id};
    $up_attr->{project_name} = $jobj->{project_name};
}

# stats info
foreach my $s (keys %$jstat) {
    if ($s =~ /(.+)_raw$/) {
        $up_attr->{statistics}{$1} = $jstat->{$s};
    }
}
$vars->{bp_count} = $up_attr->{statistics}{bp_count};
if ($priority > 0) {
    $vars->{priority} = $priority;
} else {
    $vars->{priority} = Pipeline::set_priority($vars->{bp_count}, $jattr->{priority});
}

my $content = {};
$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

if ($input_file) {
    # upload input to shock
    $content = {
        priority   => 9,
        upload     => [$input_file],
        attributes => [undef, "$input_file.json", Content => $json->encode($up_attr)]
    };
} elsif ($input_node) {
    # copy input node
    $content = {
        priority     => 9,
        copy_data    => $input_node,
        copy_indexes => 1,
        attributes   => [undef, "attr.json", Content => $json->encode($up_attr)]
    };
}
# POST to shock
print "upload input to Shock... ";
my $spost = $agent->post(
    $vars->{shock_url}.'/node',
    'Authorization', $Conf::pipeline_token,
    'Content_Type', 'multipart/form-data',
    'Content', $content
);
my $sres = undef;
eval {
    $sres = $json->decode($spost->content);
};
if ($@) {
    print STDERR "ERROR: Return from shock is not JSON:\n".$spost->content."\n";
    exit 1;
}
if ($sres->{error}) {
    print STDERR "ERROR: (shock) ".$sres->{error}[0]."\n";
    exit 1;
}
print " ...done.\n";

my $node_id = $sres->{data}{id};
print "upload shock node\t$node_id\n";

# create workflow from template
my $workflow_obj = Pipeline::populate_template($jobj, $jattr, $jopts, $vars, $node_id, $vars->{pipeline_version}, $use_docker);
unless ($workflow_obj) {
    print STDERR "ERROR: unable to populate template and transform to JSON\n";
	exit 1;
}
my $workflow_str  = $json->encode($workflow_obj);
my $workflow_file = $Conf::temp."/".$job_id.".awe_workflow.json";
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
my $awe_id = $ares->{data}{id};
print "awe job:\t".$awe_id."\n";

# update job attributes
Pipeline::set_job_attributes($jobdb, $job_id, {"pipeline_id" => $awe_id});

sub get_usage {
    return "USAGE: submit_to_awe.pl -job_id=<job identifier> -input_file=<input file> -input_node=<input shock node> [-submit_id=<submission id> -awe_url=<awe url> -shock_url=<shock url> -version=<template version> -clientgroups=<group list> -no_start -use_docker]\n";
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }

