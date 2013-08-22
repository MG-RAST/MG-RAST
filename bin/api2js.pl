#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use JSON;
use LWP::UserAgent;

sub TO_JSON { return { %{ shift() } }; }

sub usage {
  print "api2js.pl >>> create a JSON structure file from a REST API\n";
  print "api2js.pl -url <url to api> -outfile <file for js output>\n";
}

# read in parameters
my $url     = '';
my $outfile = '';

GetOptions ( 'url=s' => \$url,
	     'outfile=s' => \$outfile );

unless ($url and $outfile) {
  &usage();
  exit 0;
}

my $json = new JSON;
my $ua = LWP::UserAgent->new;

print "\nconnecting to API...\n\n";

my $data = $json->decode($ua->get($url)->content);

my $numres = scalar(@{$data->{resources}});
print "got basic data, retrieving detail information for $numres resources...\n\n";

my $structure = { service => { url => $data->{url},
			       name => $data->{service},
			       version => $data->{version},
			       description => $data->{description} } };

my $resources = [];
my $i = 1;
foreach my $resource (@{$data->{resources}}) {
  my $retval = $json->decode($ua->get($resource->{url})->content);
  push(@$resources, $retval);
  print "received resource ".$resource->{name}." [$i/$numres]\n";
  $i++
}

$structure->{resources} = $resources;

if (open(FH, ">$outfile")) {
  print FH $json->pretty->encode($structure);
  close FH;
} else {
  die "could not open outfile for writing ($outfile): $@";
}

print "\nall done.\n\nHave a nice day :)\n\n";

exit;
