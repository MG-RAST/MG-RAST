#!/usr/bin/env perl

use strict;
use warnings;

use Text::CSV;
use JSON;
use File::Slurp;
use BerkeleyDB;
use Getopt::Long;
use Data::Dumper;

my $file  = "";
my $scgs  = "";
my $input = "";
my $build = 0;
my $usage = qq($0
  --file   path to db file
  --scgs   path to scg file
  --input  file with list of test md5s or input data
  --build  build db file

input file is CSV format ordered by md5, lists are comma seperated in brackets:
md5, source, is_protein, single organism, lca list, accession list, function list, organism list

scg file is JSON format:
{ md5 => scg_id }
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
	'file:s'  => \$file,
    'scgs:s'  => \$scgs,
	'input:s' => \$input,
	'build!'  => \$build
   ) ) {
    print STDERR $usage; exit 1;
}

unless ($file && $input && (-s $input)) {
    print STDERR $usage; exit 1;
}

my $csv  = Text::CSV->new({binary => 1, allow_loose_quotes => 1, allow_loose_escapes => 1});
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# get scg hash
my $scgs = {};
eval {
    $scgs = $json->decode(read_file($scgs));
};

# create db hash
my %dbh;
if ($build) {
    tie %dbh, "BerkeleyDB::Hash", -Filename => $file, -Flags => DB_CREATE;
} else {
    tie %dbh, "BerkeleyDB::Hash", -Filename => $file, -Flags => DB_RDONLY;
}

my $count = 0;
my $start = time;
open(my $fh, "<$input");
if ($build) {
    ### must be ordered by md5
    ### each md5-source combo is unique
    my $prev = "";
    my $md5  = "";
    my @data = ();
    while (my $row = $csv->getline($fh)) {
        $count += 1;
        if (($count % 100000) == 0) {
            print STDERR ".";
        }
        $md5 = $row->[0];
        unless ($prev) {
            $prev = $md5; # for first line only
        }
        if ($prev ne $md5) {
            $dbh{$prev} = $json->encode(\@data);
            $prev = $md5;
            @data = ();
        }
        my $ann = {
            source     => $row->[1],
            is_protein => ($row->[2] eq 'true') ? 1 : 0,
            is_scg     => exists($scgs->{$md5}) ? 1 : 0,
            single     => $row->[3],
            lca        => str_to_array($row->[4]),
            accession  => str_to_array($row->[5]),
            function   => str_to_array($row->[6]),
            organism   => str_to_array($row->[7])
        };
        push @data, $ann;
    }
    if (scalar(@data) > 0) {
        $dbh{$md5} = $json->encode(\@data);
    }
    print STDERR "\nlast md5 = ".$md5."\n";
} else {
    my $srcs = {};
    while (my $md5 = <$fh>) {
        $count += 1;
        if (($count % 100000) == 0) {
            print STDERR ".";
        }
        chomp $md5;
        my $data = $json->decode( $dbh{$md5} );
        foreach my $ann (@$data) {
            if (exists $srcs->{$ann->{source}}) {
                $srcs->{$ann->{source}} += 1;
            } else {
                $srcs->{$ann->{source}} = 1;
            }
        }
    }
    print STDERR "\n".Dumper($srcs);
}
close($fh);
my $end = time;

print "Processed $count lines in ".($end-$start)." seconds\n";

sub str_to_array {
    my ($str) = @_;
    $str =~ s/^\['?//;
    $str =~ s/'?\]$//;
    my @items = split(/','/, $str);
    for (@items) {
        s/^["'\\]*//;
        s/["'\\]*$//;
    }
    return \@items;
}
