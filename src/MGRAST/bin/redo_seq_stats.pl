#!/usr/bin/env perl

use strict;
use warnings;

use JSON;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;

my $dir   = ".";
my $node  = "";
my $shock = "https://shock.mg-rast.org";
my $token = "";
my $usage = qq($0
  --node  Node ID of file to run stats on
  --shock Shock API url
  --token MG-RAST shock token
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'dir:s'   => \$dir,
    'node:s'  => \$node,
    'shock:s' => \$shock,
	'token:s' => \$token
   ) ) {
    print STDERR $usage; exit 1;
}

unless ($node && $shock && $token) {
    print STDERR $usage; exit 1;
}

# get stats node and file
my $snode = undef;
my $sfile = undef;
my $attr  = undef;
eval {
    my $get = $agent->get($shock.'/node/'.$node, ('Authorization', "mgrast $token"));
    my $info = $json->decode( $get->content );
    $snode = $info->{data};
    $sfile = $dir."/".$snode->{file}{name};
    $attr  = $snode->{attributes};
};
unless ($snode && $sfile && $attr) {
    print STDERR "ERROR: unable to GET node ($node) from Shock\n";
    exit 1;
}
open(SFILE, ">$sfile");
eval {
    my @args = (
        'Authorization', "mgrast $token",
        ':read_size_hint', 8192,
        ':content_cb', sub{ my ($chunk) = @_; print SFILE $chunk; }
    );
    # print content
    $agent->get($shock.'/node/'.$node."?download", @args);
};
close(SFILE);
print STDERR "Downloaded node $node: ".$snode->{file}{name}." ".$snode->{file}{size}."\n";

# run seq stats script
my $type = ($attr->{file_format} eq 'fastq') ? 'fastq' : 'fasta';
my $cmd  = "seq_length_stats.py -i $sfile -t $type";
if ($attr->{seq_format} eq 'aa') {
    $cmd .= " -f"
}
my @out = `$cmd`;
chomp @out;
my $stats = {};
foreach my $line (@out) {
    if ($line =~ /^\[error\]/) {
        last;
    }
    my ($k, $v) = split(/\t/, $line);
    $stats->{$k} = $v;
}

# PUT new stat attributes
$attr->{statistics} = $stats;
my $response = undef;
eval {
    my @args = (
        'Authorization', "mgrast $token",
        'Content_Type', 'multipart/form-data',
        'Content', {attributes => [undef, "n/a", Content => $json->encode($attr)]}
    );
    my $req = POST($shock.'/node/'.$node, @args);
    $req->method('PUT');
    my $put = $self->agent->request($req);
    $response = $self->json->decode( $put->content );
};
if ($@ || (! ref($response))) {
    print STDERR "ERROR: unable to PUT node ($node) to Shock\n";
} elsif (exists($response->{error}) && $response->{error}) {
    print STDERR "ERROR: unable to PUT: ".$response->{error}[0]." (".$response->{status}.")\n";
}

