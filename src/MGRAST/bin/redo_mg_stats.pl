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

my $waittime  = 120;
my $errortime = 1800;
my $mgids  = "";
my $mgfile = "";
my $shock  = "https://shock.mg-rast.org";
my $apiurl = "https://api.mg-rast.org";
my $admin_token = "";
my $shock_token = "";
my $abundance   = "";
my $rarefaction = 0;
my $nodelete    = 0;
my $usage = qq($0
  --mgids        Comma seperated IDs of metagenomes to process
  --mgfile       File of IDs of metagenomes to process
  --apiurl       MG-RAST API url
  --admin_token  MG-RAST admin token
  --shock_token  MG-RAST shock token
  --abundance    Recompute static abundances, use one of: all, organism, ontology, function
  --rarefaction  Recompute static rarefaction
  --nodelete     Do not delete original stats file
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'mgids:s'  => \$mgids,
    'mgfile:s' => \$mgfile,
	'apiurl:s' => \$apiurl,
	'admin_token:s' => \$admin_token,
	'shock_token:s' => \$shock_token,
	'abundance:s'   => \$abundance,
	'rarefaction!'  => \$rarefaction,
	'nodelete!'     => \$nodelete
   ) ) {
    print STDERR $usage; exit 1;
}

unless ($apiurl && $admin_token && $shock_token) {
    print STDERR $usage; exit 1;
}

unless ($rarefaction || $abundance) {
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
    print STDERR "Processing $mgid\n";
    my $snid = "";
    eval {
        my $get = $agent->get($apiurl.'/download/'.$mgid."?stage=done", ('Authorization', "mgrast $admin_token"));
        my $info = $json->decode( $get->content );
        foreach my $n (@{$info->{data}}) {
            if ($n->{data_type} eq 'statistics') {
                $snid = $n->{node_id};
            }
        }
    };
    unless ($snid) {
        print STDERR "ERROR: unable to get statistics node for $mgid from API\n";
        next;
    }
    print STDERR "Found stats node $snid\n";
    
    # get stats node and file
    my $snode = undef;
    my $sobj = undef;
    eval {
        my $get = $agent->get($shock.'/node/'.$snid, ('Authorization', "mgrast $shock_token"));
        my $info = $json->decode( $get->content );
        $snode = $info->{data};
    };
    eval {
        my $get = $agent->get($shock.'/node/'.$snid."?download", ('Authorization', "mgrast $shock_token"));
        $sobj = $json->decode( $get->content );
    };
    unless ($snode && $sobj) {
        print STDERR "ERROR: unable to get statistics node for $snid ($mgid) from Shock\n";
        next;
    }
    print STDERR "Downloaded stats node $snid: ".$snode->{file}{name}." ".$snode->{file}{size}."\n";
    
    # compute rarefaction
    if ($rarefaction) {
        my $url = $apiurl.'/compute/rarefaction/'.$mgid."?asynchronous=1&alpha=1&level=species&ann_ver=1";
        print STDERR "Started rarefaction compute: ".$url."\n";
        
        my $data = async_compute($url, $admin_token, 0);
        unless ($data && $data->{data} && $data->{data}{rarefaction} && $data->{data}{alphadiversity}) {
            print STDERR "ERROR: unable to compute rarefaction for $mgid from API\n";
            next;
        }
        print STDERR "Completed rarefaction compute\n";
        $sobj->{rarefaction} = $data->{data}{rarefaction};
        $sobj->{sequence_stats}{alpha_diversity_shannon} = $data->{data}{alphadiversity};
    }
    
    # compute abundances
    if ($abundance) {
        my $url = $apiurl."/job/abundance/".$mgid."?type=".$abundance."&ann_ver=1";
        print STDERR "Started abundance compute: ".$url."\n";
        
        my $data = async_compute($url, $admin_token, 0);
        unless ($data && $data->{data}) {
            print STDERR "ERROR: unable to compute abundances for $mgid from API\n";
            next;
        }
        print STDERR "Completed abundances compute\n";
        if ($abundance eq 'all') {
            $sobj->{taxonomy} = $data->{data}{taxonomy};
            $sobj->{function} = $data->{data}{function};
            $sobj->{ontology} = $data->{data}{ontology};
        } elsif ($abundance eq 'organism') {
            $sobj->{taxonomy} = $data->{data}{taxonomy};
        } else {
            $sobj->{$abundance} = $data->{data}{$abundance};
        }
    }
    
    # post new node with stats attributes and file
    my $status = undef;
    eval {
        my $content = {
            attributes => [undef, "attributes", Content => $json->encode($snode->{attributes})],
            upload => [undef, $snode->{file}{name}, Content => $json->encode($sobj)]
        };
        my @args = (
            'Authorization', "mgrast $shock_token",
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
    print STDERR "New stats node ".$status->{data}{id}." created\n";
    
    # delete old stats node
    if (! $nodelete) {
        $status = undef;
        eval {
            my $del = $agent->delete($shock.'/node/'.$snid, ('Authorization', "mgrast $shock_token"));
            $status = $json->decode( $del->content );
        };
        unless ($status) {
            print STDERR "ERROR: unable to DELETE old statistics node $snid for $mgid from Shock\n";
            next;
        }
        print STDERR "Old stats node $snid deleted\n";
    }
}

sub async_compute {
    my ($url, $token, $try) = @_;
    if ($try > 3) {
        print STDERR "ERROR: Async process failed $try times\n";
        exit 1;
    }
    my $data = undef;
    eval {
        my $get  = $agent->get($url."&retry=".$try, ('Authorization', "mgrast $token"));
        $data = $json->decode($get->content);
        if ($data->{ERROR}) {
            print STDERR "ERROR: ".$data->{ERROR}." - trying again\n";
            $try += 1;
            $data = async_compute($url, $token, $try);
        }
        print STDERR "status: ".$data->{url}."\n";
        while ($data->{status} ne 'done') {
            sleep $waittime;
            $get = $agent->get($data->{url});
            $data = $json->decode($get->content);
            if ($data->{ERROR}) {
                print STDERR "ERROR: ".$data->{ERROR}." - trying again\n";
                $try += 1;
                $data = async_compute($url, $token, $try);
            } else {
                my $last = DateTime::Format::ISO8601->parse_datetime($data->{updated});
                my $now  = shock_time();
                my $diff = $now->subtract_datetime_absolute($last);
                if ($diff->seconds > $errortime) {
                    print STDERR "ERROR: Async process died - trying again\n";
                    $try += 1;
                    $data = async_compute($url, $token, $try);
                }
            }
        }
    };
    return $data;
}

sub shock_time {
    my $dt = undef;
    eval {
        my $get = $agent->get($shock);
        my $info = $json->decode($get->content);
        $dt = DateTime::Format::ISO8601->parse_datetime($info->{server_time});
    };
    return $dt;
}

exit 0;
