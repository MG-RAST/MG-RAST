#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");


my $md5="068792e95e38032059ba7d9c26c1be78";

# url to retrieve all annotations from the m5nr for a given md5 sum
my $m5nr_url = "http://api.metagenomics.anl.gov/1/m5nr/md5/";
my $url = $m5nr_url.uri_escape("$md5?order=function&source=TrEMBL");

# retrieve response in json
# return value is an array of hashes sorted by function name
my $content = $ua->get($url)->content;

my $json = new JSON;
my $annotations = $json->decode( $content );

#to view results
#print Dumper($annotations)."\n";

my $uniprot_id = $annotations->{'data'}->[0]->{'accession'};

#base url for uniprot entries
my $uniprot_url = "http://www.uniprot.org/uniprot/";

# print UniProt url (e.g. http://www.uniprot.org/uniprot/B2ISL2) 
print "UniProt URL: $uniprot_url$uniprot_id\n";
