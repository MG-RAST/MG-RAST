use strict;
use warnings;
no warnings 'once';

use DBI;
use CGI;
use JSON;
use URI::Escape;
use Data::Dumper;

use Babel::lib::Babel;
use Conf;

# create objects
my $cgi  = new CGI;
my $json = new JSON;
my $dbh  = DBI->connect("DBI:$Conf::babel_dbtype:dbname=$Conf::babel_db;host=$Conf::babel_dbhost", $Conf::babel_dbuser, '');
my $ach  = Babel::lib::Babel->new($dbh);

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

if ( $ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} =~ /post/i) ) {
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
my $partial = $cgi->param('partial') ? 1 : 0;
my $get_seq = $cgi->param('sequence') ? 1 : 0;
my $format  = $cgi->param('format') || '';
my $results = '';
$request = uri_unescape($request);

if ($cgi->param('pretty')) {
  $json = $json->pretty;
}

# set object:  [ [id, md5, func, org, source] ]
if ($object_type eq 'id') {
  my @id_array = split(/;/, $request);
  if ($get_seq) {
    if ($format eq 'fasta') {
      $results = $ach->ids2sequences(\@id_array);
    } else {
      $results = &seq2json($json, $ach->ids2sequences(\@id_array, 1), 1);
    }	
  } else {
    $results = &set2json($json, $ach->ids2sets(\@id_array));
  }
}
elsif ($object_type eq 'function') {
  $results = &set2json($json, $ach->functions2sets([$request], $partial));
}
elsif ($object_type eq "organism") {
  $results = &set2json($json, $ach->organisms2sets([$request], $partial));
}
elsif ($object_type eq "sequence") {
  $results = &set2json($json, $ach->sequence2set(uc($request)));
}
elsif ($object_type eq "md5") {
  my @md5_array = split(/;/, $request);
  if ($get_seq) {
    if ($format eq 'fasta') {
      $results = $ach->md5s2sequences(\@md5_array);
    } else {
      $results = &seq2json($json, $ach->md5s2sequences(\@md5_array, 1));
    }
  } else {
    $results = &set2json($json, $ach->md5s2sets(\@md5_array));
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
  my ($json, $seq, $is_id) = @_;
  my $printable = [];
  my $key = $is_id ? 'id' : 'md5';
  foreach my $data (@$seq) {
    push @$printable, {	$key => $data->[0], sequence => $data->[1] };
  } 
  return $json->encode($printable);
}
