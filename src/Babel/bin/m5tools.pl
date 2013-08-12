#!/usr/bin/env perl

use strict;
use warnings;
use diagnostics;

use List::MoreUtils qw(natatime uniq);
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
my $batch = 100;
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

my $smap = get_data('GET', 'sources');

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
    my ($total, $count) = process_sims($sim, $src, $batch);
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
        foreach my $d ( @{ get_data("GET", "md5/".$m, {'sequence' => '1'}) } ) {
            print STDOUT ">".$d->{md5}."\n".$d->{sequence}."\n";
        }
    }
}
elsif($acc && ($opt eq 'sequence')) {
    foreach my $a (@{ list_from_input($acc) }) {
        foreach my $d ( @{ get_data("GET", "accession/".$a, {'sequence' => '1'}) } ) {
            print STDOUT ">".$d->{id}."\n".$d->{sequence}."\n";
        }
    }
}
elsif ($md5) {
    my $md5s = list_from_input($md5);
    my $iter = natatime $batch, @$md5s;
    while (my @curr = $iter->()) {
        foreach my $d ( @{ get_data("POST", "md5", {'limit' => $batch*1000,'source' => $src,'data' => \@curr,'order' => 'md5'}) } ) {
            print STDOUT $d->{accession}."\t".$d->{md5}."\t".$d->{function}.(exists($d->{organism}) ? "\t".$d->{organism} : '')."\n";
        }
    }
}
elsif($acc) {
    my $accs = list_from_input($acc);
    my $iter = natatime $batch, @$accs;
    while (my @curr = $iter->()) {
        foreach my $d ( @{ get_data("POST", "accession", {'limit' => $batch*1000,'source' => $src,'data' => \@curr,'order' => 'accession'}) } ) {
            print STDOUT $d->{accession}."\t".$d->{md5}."\t".$d->{function}.(exists($d->{organism}) ? "\t".$d->{organism} : '')."\n";
        }
    }
}
else {
    &help($options, $smap);
    exit 1;
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
    my ($file, $source, $batch) = @_;

    my $total = 0;
    my $count = 0;
    my @lines = ();
    my %md5s  = ();

    open(INFILE, "<$file") or die "Can't open file $file!\n";
    while (my $line = <INFILE>) {
        $total += 1;
        chomp $line;
        # @rest = [ identity, length, mismatch, gaps, q_start, q_end, s_start, s_end, evalue, bit_score ]
        my ($frag, $md5, @rest) = split(/\t/, $line);
        
        # process chunk
        if (scalar(keys %md5s) >= $batch) {
            my $data = {};
            foreach my $rec (@{ get_data("POST", "md5", {'limit' => $batch*1000,'source' => $source,'data' => [keys %md5s]}) }) {
                push @{ $data->{$rec->{md5}} }, $rec;
            }
            if (scalar(keys %$data) > 0) {
                my @results = ();
                foreach my $l (@lines) {
                    next if (! exists($data->{$l->[1]}));
                    $count += 1;
                    foreach my $d (sort {$a->{function} cmp $b->{function}} @{$data->{$l->[1]}}) {
                        if ($d->{type} eq 'ontology') {
                            push @results, join("\t", ($l->[1],$l->[0],$d->{function},$d->{accession},$l->[2],$l->[3],$l->[10]));
                        } else {
                            push @results, join("\t", ($l->[1],$l->[0],$d->{function},$d->{organism},$l->[2],$l->[3],$l->[10]));
                        }
                    }
                }
                @results = uniq @results;
                print STDOUT join("\n", @results);
            }
            %md5s  = ();
            @lines = ();
        }
        $md5s{$md5} = 1;
        push @lines, [$frag, $md5, @rest];
    }
    close INFILE;
    
    # do last chunk
    if (scalar(keys %md5s) > 0) {
        my $data = {};
        foreach my $rec (@{ get_data("POST", "md5", {'limit' => $batch*1000,'source' => $source,'data' => [keys %md5s]}) }) {
            push @{ $data->{$rec->{md5}} }, $rec;
        }
        if (scalar(keys %$data) > 0) {
            my @results = ();
            foreach my $l (@lines) {
                next if (! exists($data->{$l->[1]}));
                $count += 1;
                foreach my $d (sort {$a->{function} cmp $b->{function}} @{$data->{$l->[1]}}) {
                    if ($d->{type} eq 'ontology') {
                        push @results, join("\t", ($l->[1],$l->[0],$d->{function},$d->{accession},$l->[2],$l->[3],$l->[10]));
                    } else {
                        push @results, join("\t", ($l->[1],$l->[0],$d->{function},$d->{organism},$l->[2],$l->[3],$l->[10]));
                    }
                }
            }
            @results = uniq @results;
            print STDOUT join("\n", @results);
        }
    }
    
    return ($total, $count);
}

sub get_data {
    my ($method, $resource, $params) = @_;
    
    my $data = undef;
    eval {
        my $res = undef;
        if ($method eq 'GET') {
            my $opts = ($params && (scalar(keys %$params) > 0)) ? '?'.join('&', map {$_.'='.$params->{$_}} keys %$params) : '';
            $res = $agent->get($api.'/m5nr/'.$resource.$opts);
        }
        if ($method eq 'POST') {
            my $pdata = $json->encode($params);
            $res = $agent->post($api.'/m5nr/'.$resource, Content => $pdata);
        }
        $data = $json->decode($res->content);
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
