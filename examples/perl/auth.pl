#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

# set the authentication header
$ua->default_header('AUTH' => '12345');

# retrieve data requiring authentication
print $ua->get("http://api.metagenomics.anl.gov/1/metagenome/mgm12345.3")->content;

