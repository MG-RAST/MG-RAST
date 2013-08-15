#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

# create url specifying search criteria 
my $base_url = "http://api.metagenomics.anl.gov/1/metagenome";
my $url = $base_url.uri_escape("?biome=marine&function=protease&country=Mexico");

# retrieve response in json
my $content = $ua->get($url)->content;

# transform json into perl hash data structure
my $json = new JSON;
my $metagenomes = $json->decode( $content );

#view results
print Dumper($metagenomes)."\n";