#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Digest::MD5;
use LWP::UserAgent;
use Data::Dumper;
use JSON;

my $api = '';
my $sim = '';
my $acc = '';
my $md5 = '';
my $seq = '';
my $src = '';
my $opt = '';
my $help = 0;
my $verb = 0;
my $options = {sequence => 1, annotation => 1};
my $sources = {};

GetOptions( "verbose!"   => \$verb,
            "api=s"      => \$api,
	        "sim=s"      => \$sim,
	        "acc=s"      => \$acc,
	        "md5=s"      => \$md5,
            "sequence=s" => \$seq,
	        "source=s"   => \$src,
	        "option=s"   => \$opt,
	        "help!"      => \$help
 	  );

unless ($api) {
    print STDERR "Missing required API url\n";
    help($options, {});
    exit 1;
}

my $agent = LWP::UserAgent->new;
my $json  = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

my @data = ();
my $smap = get_data('sources');
my $hdr  = ["Accession", "MD5", "Function", "Organism"];

if ($help) {
    help($options, $smap);
    exit 0;
}
unless (exists($options->{$opt}) || $seq || $sim) {
    print STDERR "One of the following paramters are required: option, sequence, or sim\n";
    help($options, $smap);
    exit 1;
}
unless ($src) {
    print STDERR "Source is required\n";
    help($options, $smap);
    exit 1;
}
unless (exists $smap->{$src}) {
    print STDERR "Invalid source: $src\n";
    help($options, $smap);
    exit 1;
}

if ($sim) {
    unless (-s $sim) {
        print STDERR "File missing: $sim\n";
        help($options, $smap);
        exit 1;
    }
    my ($total, $count) = process_sims($sim, $src);
    print STDERR "$count out of $total similarities annotated for source $src\n";
    exit 0;
}
elsif ($seq) {
    $seq =~ s/\s+//sg;
    print STDOUT Digest::MD5::md5_hex(uc $seq)."\n";
    exit 0;
}
elsif ($md5 && ($opt eq 'sequence')) {
    foreach my $m (@{ list_from_input($md5) }) {
        push @data, get_data("md5/".$m, {'sequence' => '1'});
    }
}
elsif($acc && ($opt eq 'sequence')) {
    foreach my $a (@{ list_from_input($acc) }) {
        push @data, get_data("accession/".$a, {'sequence' => '1'});
    }
}
elsif ($md5) {
    foreach my $m (@{ list_from_input($md5) }) {
        push @data, @{ get_data("md5/".$m, {'source' => $src}) };
    }
}
elsif($acc) {
    foreach my $a (@{ list_from_input($acc) }) {
        push @data, @{ get_data("accession/".$a, {'source' => $src}) };
    }
}
else {
    &help($options, $smap);
    exit 1;
}

unless (@data > 0) {
    print STDERR "No data available for the given input\n";
}
if ($opt eq 'sequence') {
    foreach my $d (@data) {
        print STDOUT ">".($d->{id} ? $d->{id} : $d->{md5})."\n".$d->{sequence}."\n";
    }
} else {
    if ($data[0]{type} eq 'ontology') {
        pop @$hdr;
    }
    print STDOUT join("\t", @$hdr)."\n";
    @data = sort { ($$a{md5} cmp $$b{md5}) or ($$a{function} cmp $$b{function}) } @data;
    foreach my $d (@data) {
        print STDOUT $d->{accession}."\t".$d->{md5}."\t".$d->{function}.(exists($d->{organism}) ? "\t".$d->{organism} : '')."\n";
    }
}

sub list_from_input {
    my ($input) = @_;

    my @list = ();
    if (-s $input) {
        @list = `cat $input`;
        chomp @list;
    }
    else {
        @list = split(/,/, $input);
    }
    my %set = map {$_, 1} @list;
    return [keys %set];
}

sub process_sims {
    # output: md5, query, identity, length, evalue, function, organism
    my ($file, $source) = @_;

    my $total = 0;
    my $count = 0;

    open(INFILE, "<$file") or die "Can't open file $file!\n";
    while (my $line = <INFILE>) {
        $total += 1;
        chomp $line;
        # @rest = [ identity, length, mismatch, gaps, q_start, q_end, s_start, s_end, evalue, bit_score ]
        my ($frag, $md5, @rest) = split(/\t/, $line);
        my $data = get_data("md5/".$md5, {'source' => $source});
        next if (@$data == 0);
        
        @$data = sort { $$a{function} cmp $$b{function} } @$data;
        foreach my $d (@$data) {
            if ($d->{type} eq 'ontology') {
                print STDOUT join("\t", ($md5,$frag,$rest[0],$rest[1],$rest[8],$d->{function},$d->{accession}))."\n";
            } else {
                print STDOUT join("\t", ($md5,$frag,$rest[0],$rest[1],$rest[8],$d->{function},$d->{organism}))."\n";
            }
        }
        $count += 1;
    }
    close INFILE;
    
    return ($total, $count);
}

sub get_data {
    my ($resource, $params) = @_;
    
    my $data = undef;
    my $url  = $api.'/m5nr/'.$resource.'?limit=1000';
    if ($params && (scalar(keys %$params) > 0)) {
        $url = $url.'&'.join('&', map { $_.'='.$params->{$_} } keys %$params);
    }
    eval {
        my $get = $agent->get($url);
        $data = $json->decode($get->content);
    };
    if ($@ || (! ref($data))) {
        print STDERR "Error accessing M5NR API: ".$@."\n";
        exit 1;
    } elsif (exists($data->{ERROR}) && $data->{ERROR}) {
        print STDERR "Error: ".$data->{ERROR}."\n";
        exit 1;
    } else {
        return $data->{data};
    }
}

sub help {
    my ($options, $smap) = @_ ;

    my $opts = join(", ", keys %$options);
    my $srcs = join(", ", sort keys %$smap);

    print STDERR qq(Usage: $0
  --api       <api url>          required: url of m5nr API, required
  --sim       <similarity file>  file in blast m8 format to be annotated
  --acc       <accession ids>    file or comma seperated list of protein ids
  --md5       <md5sums>          file or comma seperated list of md5sums
  --sequence  <aa sequence>      protein sequence, returns md5sum of sequence
  --source    <source name>      required: source for annotation
  --option    <output option>    output type, one of: $opts
  --verbose                      verbose output
  --help                         show this

  Sources: $srcs
);
}
