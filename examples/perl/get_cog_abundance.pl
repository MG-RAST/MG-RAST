#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");


# get a user agent
my $ua = LWP::UserAgent->new;

# retrieve all data from oral hygiene project
my @ids= ('4447943.3', '4447192.3', '4447103.3', '4447102.3', '4447101.3', '4447971.3', '4447970.3', '4447903.3');
my $id_str = "id=mgm".join("&id=mgm", @ids);

# obtain COG abundance info for e^-10 and better BLAST results
my $base_url = "http://api.metagenomics.anl.gov/1/matrix/function";
my $url = $base_url.uri_escape("?$id_str&result_type=abundance&source=COG&evalue=10");

my $content = $ua->get($url)->content;

# create perl data structure from json
my $json = new JSON;
my $biom = $json->decode( $content );

#view results (output very big!)
print Dumper($biom)."\n";