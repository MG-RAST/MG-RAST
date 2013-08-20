#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

my $key = $ENV{"MGRKEY"};
# define the parameters
my $metagenome = $ARGV[0] ; # "mgm4440442.5" ;
my $group_level = "family" ;
my $result_type = "abundance";
my $source = "SEED";

die "Metagenome ID argument is required!   
Usage:    downloadMGR.pl <mgr accession number>   
Example:  downloadMGR.pl mgm4440442.5\n "  unless $#ARGV + 1 == 1;
die "Don't recognize format of $metagenome" unless $metagenome =~ m/\d\d\d\d\d\d\d.\d/;

# retrieve the data
my $base_url = "http://api.metagenomics.anl.gov/1/download/$metagenome?file=050.2";
my $url = $base_url."&auth=$key";

my $response = $ua->get($url, ":content_file" => "$metagenome.gz" );
# check http header 
my $content = $response->content;
die "Error with http request" unless $response->is_success ;
print STDERR "Writing result of $url to $metagenome.gz\n";
# check for file type 
my $type = `file $metagenome.gz` ; 
if ($type =~ m/ASCII/ )
	{rename("$metagenome.gz", "$metagenome.err");
	print STDERR "Error retrieving $metagenome, message in $metagenome.err\n";} 
