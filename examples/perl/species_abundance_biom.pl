#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

# set the parameters
my $metagenome = "mgm4440026.3";
my $source = "GenBank";

# retrieve the data
my $base_url = "http://api.metagenomics.anl.gov/1/matrix/organism";
my $url=$base_url.uri_escape("?id=$metagenome&source=$source");
my $content = $ua->get($url)->content;

# create perl data structure from json
my $json = new JSON;
my $biom = $json->decode( $content );

print Dumper($biom)."\n";
