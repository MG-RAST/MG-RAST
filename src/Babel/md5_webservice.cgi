use strict;
use warnings;
no warnings 'once';

use CGI;
use JSON;
use Data::Dumper;

use Babel::lib::Babel;
use Config;

# create objects
my $cgi  = new CGI;
my $json = new JSON;
my $ach  = new Babel::lib::Babel;

unless ($ach && $ach->dbh) {
  print $cgi->header('text/plain');
  print "ERROR: Connection to M5nr database failed";
  exit 0;
}

# get parameters
my $abs = $cgi->url(-absolute=>1);
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\///;

my @rest = split m#/#, $rest;

map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);

if ( $ENV{'REQUEST_METHOD'} =~ /post/i ) {
  print $cgi->header('text/plain');
  print "ERROR: POST is not supported by this version";
  exit 0;
}

my $object_type = shift @rest;
unless ($object_type) {
  print $cgi->header('text/plain');
  print "ERROR: Invalid parameters - missing object type";
  exit 0;
}
if (scalar(@rest) == 0) {
  print $cgi->header('text/plain');
  print "ERROR: Invalid parameters - missing object request";
  exit 0;
}

my $request = shift @rest;
my $regex   = $cgi->param('regex') ? 1 : 0;
my $get_seq = $cgi->param('sequence') ? 1 : 0;
my $results = '';

if ($cgi->param('pretty')) {
  $json = $json->pretty;
}

# set object:  [ [id, md5, func, org, source] ]
if ($object_type eq 'ID') {
  if ($get_seq) {
    $results = &seq2json($json, $ach->id2sequence($request));
  } else {
    $results = &set2json($json, $ach->id2set($request));
  }
}
elsif ($object_type eq 'Function') {
  $results = &set2json($json, $ach->functions2sets([$request], $regex));
}
elsif ($object_type eq "Organism") {
  $results = &set2json($json, $ach->organisms2sets([$request], $regex));
}
elsif ($object_type eq "Sequence") {
  $results = &set2json($json, $ach->sequence2set($request));
}
elsif ($object_type eq "MD5") {
  if ($get_seq) {
    $results = &seq2json($json, $ach->md52sequence($request));
  } else {
    $results = &set2json($json, $ach->md52set($request));
  }
}
else {
  print $cgi->header('text/plain');
  print "ERROR: Invalid parameters - invalid object type: $object_type";
  exit 0;
}

if ($results) {
  print $cgi->header('text/plain');
  print $results;
  exit 0;
}
else {
  print $cgi->header('text/plain');
  print "ERROR: unable to retrieve object for $object_type/$request";
  exit 0;
}

sub set2json {
  my ($json, $set) = @_;
  my $printable = [];
  foreach my $data (@$set) {
    push @$printable, { id       => $data->[0],
			md5      => $data->[1],
			function => $data->[2],
			organism => $data->[3],
			source   => $data->[4] };
  }
  return $json->encode($printable);
}

sub seq2json {
  my ($json, $seq) = @_;
  chomp $seq;
  return $json->encode({ sequence => $seq });
}
