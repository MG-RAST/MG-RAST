#!/usr/bin/env perl

###### cleanup tool ######
# given AWE ID
# 1. delete job from AWE
# 2. delete all output files in shock

use lib "/MG-RAST/conf";

use strict;
use warnings;
no warnings('once');

use Conf;
use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;

my $shock_url  = $Conf::shock_url;
my $awe_url    = $Conf::awe_url;
my $auth_token = $Conf::pipeline_token;

my $aweid = shift @ARGV;

unless ($aweid) {
    print STDERR "Usage: \tdelete_job_and_files.pl <awe_id> \n";
    exit 1;
}

# set handels
my $agent = LWP::UserAgent->new();
$agent->timeout(3600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# get job document
my $response = undef;
my $job_doc  = undef;
eval {
    my $get = $self->agent->get($awe_url.'/job/'.$aweid, 'Authorization', $auth_token);
    $response = $self->json->decode( $get->content );
};
if ($@ || (! ref($response))) {
    print STDERR "ERROR: unable to connect to AWE server\n";
} elsif (exists($response->{error}) && $response->{error}) {
    print STDERR "ERROR: ".$response->{error}[0]."\n";
} else {
    $job_doc = $response->{data};
}

# delete job
system("curl -X DELETE -H 'Authorization: $auth_token' '$awe_url/job/$aweid?full=1'");

# delete nodes
foreach my $task (@{$job_doc->{tasks}}) {
    foreach my $out (@{$task->{outputs}}) {
        if ($out->{node} && ($out->{node} ne '-')) {
            system("curl -X DELETE -H 'Authorization: $auth_token' '$shock_url/node/".$out->{node}."'");
        }
    }
}

exit 0;
