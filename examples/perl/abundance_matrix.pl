#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

# define the parameters
my $metagenomes = ["mgm4440442.5", "mgm4440026.3"];
my $group_level = "family";
my $result_type = "abundance";
my $source = "SEED";

# retrieve the data
my $base_url = "http://api.metagenomics.anl.gov/1/matrix/organism";
my $url = $base_url.uri_escape("?group_level=$group_level&result_type=$result_type&source=$source&evalue=15&".join("&", map{"id=".$_}@$metagenomes));
my $content = $ua->get($url)->content;

# create a perl data structure from the returned JSON
my $json = new JSON;

my $abundances = $json->decode( $content );

print Dumper($abundances)."\n";
