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

}


