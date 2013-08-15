#!/usr/bin/env perl
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;

# get a user agent
my $ua = LWP::UserAgent->new;
$ua->agent("MyClient/0.1 ");

# set the parameters
my @ids= ('4447943.3', '4447192.3', '4447103.3', '4447102.3', '4447101.3', '4447971.3', '4447970.3', '4447903.3');
my $id_str = "id=mgm".join("&id=mgm", @ids);
my $source = "GenBank";

# retrieve the data
my $base_url = "http://api.metagenomics.anl.gov/1/matrix/function";
#my $url=$base_url.uri_escape("?$id_str&source=$source");
my $url=$base_url."?$id_str&source=$source";


print "url: $url\n";

my $content = $ua->get($url)->content;

# create perl data structure from json
my $json = new JSON;
my $biom = $json->decode( $content );

# sub select matrix rows that match ‘dnaA’
open(OUTFILE, ">dnaA.tab");
print OUTFILE join("\t", @{$biom->{columns}})."\n";
for (my $r=0; $r<scalar(@{$biom->{rows}}); $r++) {
	if ($biom->{rows}[0]{id} =~ /dnaA/) {
		print OUTFILE join("\t", map { $biom->{data}[$r][$_] }
		@{$biom->{columns}})."\n";
	}
}
close(OUTPUT);
print "dnaA.tab written\n";
