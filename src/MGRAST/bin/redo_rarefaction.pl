#!/usr/bin/env perl

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;

my $mgids  = "";
my $mgfile = "";
my $shock  = "http://shock.metagenomics.anl.gov";
my $apiurl = "";
my $token  = "";
my $usage  = qq($0
  --mgids  comma seperated IDs of metagenomes to process
  --mgfile file of IDs of metagenomes to process
  --apiurl MG-RAST API url
  --token  MG-RAST API user token
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'mgids:s'  => \$mgids,
    'mgfile:s' => \$mgfile,
	'apiurl:s' => \$apiurl,
	'token:s'  => \$token
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($apiurl && $token) {
    print STDERR $usage; exit 1;
}

my @mg_list = ();
if ($mgids) {
    @mg_list = split(/,/, $mgids);
} elsif ($mgfile && (-s $mgfile)) {
    open INFILE, "<$mgfile";
    @mg_list = <INFILE>;
    close INFILE;
    chomp @mg_list;
} else {
    print STDERR $usage; exit 1;
}

my $agent = LWP::UserAgent->new;
$agent->timeout(600);

my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

foreach my $mgid (@mg_list) {
    # get stats node id, verify in system
    my $snid = "";
    eval {
        my $get = $agent->get($apiurl.'/download/'.$mgid."?stage=done", ('Authorization', "mgrast $token"));
        my $info = $json->decode( $get->content );
        $snid = $info->{data}[0]{node_id};
    };
    unless ($snid) {
        print STDERR "ERROR: unable to get statistics node for $mgid from API\n";
        next;
    }
    # get stats node and file
    my $snode = undef;
    my $sobj = undef;
    eval {
        my $get = $agent->get($shock.'/node/'.$snid, ('Authorization', "mgrast $token"));
        my $info = $json->decode( $get->content );
        $snode = $info->{data};
    };
    eval {
        my $get = $agent->get($shock.'/node/'.$snid."?download", ('Authorization', "mgrast $token"));
        $sobj = $json->decode( $get->content );
    };
    unless ($snode && $sobj) {
        print STDERR "ERROR: unable to get statistics node for $snid ($mgid) from Shock\n";
        next;
    }
    # compute rarefaction
    my $rare = undef;
    my $alpha = undef;
    eval {
        my $get = $agent->get($apiurl.'/compute/rarefaction/'.$mgid."?asynchronous=1&alpha=1&level=species&ann_ver=1", ('Authorization', "mgrast $token"));
        my $info = $json->decode( $get->content );
        while ($info->{status} ne 'done') {
            sleep 30;
            $get = $agent->get($info->{url});
            $info = $json->decode( $get->content );
        }
        $rare = $info->{data}{rarefaction};
        $alpha = $info->{data}{alphadiversity};
    };
    unless ($rare && $alpha) {
        print STDERR "ERROR: unable to compute rarefaction for $mgid from API\n";
        next;
    }
    $sobj->{rarefaction} = $rare;
    # post new node with stats attributes and file
    my $status = undef;
    eval {
        my $content = {
            attributes => [undef, $snode->{file}{name}, Content => $json->encode($snode->{attributes})],
            upload => [undef, "attributes", Content => $json->encode($sobj)]
        };
        my @args = (
            'Authorization', "mgrast $token",
            'Content_Type', 'multipart/form-data',
            'Content', $content
        );
        my $post = $agent->post($shock.'/node', @args);
        $status = $json->decode( $post->content );
    };
    unless ($status) {
        print STDERR "ERROR: unable to POST new statistics node for $mgid to Shock\n";
        next;
    }
    print STDOUT "New stats node ".$status->{id}." created\n";
    # delete old stats node
    $status = undef;
    eval {
        my $del = $agent->delete($shock.'/node/'.$snid, ('Authorization', "mgrast $token"));
        $status = $json->decode( $del->content );
    };
    unless ($status) {
        print STDERR "ERROR: unable to DELETE old statistics node $snid for $mgid from Shock\n";
        next;
    }
    print STDOUT "Old stats node $snid deleted\n";
}

exit 0;

