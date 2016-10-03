#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON;
use LWP::UserAgent;

my $mgid     = "";
my $version = "";
my $output  = "";
my $token   = "";
my $apiurl  = "http://api.metagenomics.anl.gov";
my $shock   = "http://shock.metagenomics.anl.gov";
my $usage   = qq($0
  --mgid    ID of metagenome to dump
  --version m5nr version #
  --output  dump file prefix
  --token   mg-rast user token
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'mgid:s'    => \$mgid,
    'version:i' => \$version,
    'output:s'  => \$output,
    'token:s'   => \$token
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($mgid && $output) {
    print STDERR $usage; exit 1;
}

my $agent = LWP::UserAgent->new;
$agent->timeout(600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# get metagenome info from API
print STDERR "Retrieving metagenome info\n";
my $mg_obj = get_api_obj($apiurl.'/metagenome/'.$mgid);
my $files  = get_api_obj($apiurl.'/download/'.$mgid);
my $job    = $mg_obj->{job_id};

print STDERR "Downloading similarity file\n";
# download similarity file from shock
my $sims_node  = "";
foreach my $f (@{$files->{data}}) {
    if (exists($f->{stage_name}) && ($f->{stage_name} eq "filter.sims")) {
        $sims_node = $f->{node_id};
    }
}
if (! $sims_node) {
    print STDERR "ERROR: missing similarity file\n";
    exit 1;
}
download_file($sims_node, "$output.$job.sims");

print STDERR "Starting data export\n";
# parse similarity file to output schema
# tabbed: query, subject, identity, length, mismatch, gaps, q_start, q_end, s_start, s_end, evalue, bit_score, sequence
my $cur = "";
my $rec = 1;
my $num = 0;
open(SIMF, "<$output.$job.sims");
open(DUMP, ">$output.$job.job_features") or die "Couldn't open $output.$job.job_features for writing.\n";
while (my $line = <SIMF>) {
    chomp $line;
    my ($feature, $md5, $ident, $len, undef, undef, undef, undef, undef, undef, $eval, $score, $seq) = split(/\t/, $line);
    my $exp = get_exponent($eval);
    next if ($exp > -3); # throw out bad hits
    if (! $cur) {
        # first line only
        $cur = $md5;
    }
    if ($cur ne $md5) {
        # sorted by md5 / increment record
        $rec += 1;
        $cur = $md5;
    }
    my @out = (
        $version,
        $job,
        $md5,
        $feature,
        $exp,
        int($ident),
        int($len),
        $rec
    );
    print DUMP join(",", map { '"'.$_.'"' } @out)."\n";
    $num += 1;
}
close(DUMP);
close(SIMF);
print STDERR "exported $num rows for $rec md5s\n";

unlink("$output.$job.sims");

sub get_api_obj {
    my ($url) = @_;
    
    my $response = undef;
    my @args = $token ? ('Authorization', "mgrast $token") : ();
    
    eval {
        my $get = $agent->get($url, @args);
        $response = $json->decode( $get->content );
    };
    
    if ($@ || (! ref($response))) {
        print STDERR "ERROR: unable to complete $url\n";
        exit 1;
    } elsif (exists($response->{ERROR}) && $response->{ERROR}) {
        print STDERR "ERROR: ".$response->{ERROR}."\n";
        exit 1;
    }
    return $response;
}

sub download_file {
    my ($node, $file) = @_;

    my $response = undef;
    my $fhdl = undef;
    my @args = $token ? ('Authorization', "mgrast $token") : ();
    
    open($fhdl, ">$file") || return ("", "Unable to open file $file");
    push @args, (':read_size_hint', 8192, ':content_cb', sub{ my ($chunk) = @_; print $fhdl $chunk; });
    
    eval {
        my $url = $shock.'/node/'.$node.'?download';
        $response = $agent->get($url, @args);
    };
    
    if ($@ || (! $response)) {
        print STDERR "ERROR: unable to download $node\n";
        exit 1;
    }
    close($fhdl);
}

sub get_exponent {
  my ($eval) = @_;

  my ($m, $e) = split(/e/, $eval);
  unless ($e) {
    my ($tmp) = $eval =~ /0\.(\d+)$/;
    my @count = $tmp =~/(\d)/gc;
    $e = scalar @count;
    $e = $e * -1;
  }
  return $e * 1;
}
