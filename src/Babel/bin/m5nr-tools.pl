#!/usr/bin/env perl

use strict;
use warnings;
use diagnostics;

use List::MoreUtils qw(natatime uniq);
use Getopt::Long;
use Digest::MD5;
use LWP::UserAgent;
use Data::Dumper;
use Pod::Usage;
use JSON;

=head1 NAME

m5nr-tools

=head1 VERSION

1

=head1 SYNOPSIS

m5nr-tools [--help, --verbose, --api <api url>, --source <source name>, --sim <similarity file>, --acc <accession ids>, --md5 <md5 checksums>, --sequence <aa sequence>, --option <cv: sequence or annotation>]

=head1 DESCRIPTION

Tool for retreiving M5NR annotations for inputed accession ids, md5 checksums, or protein sequence.  Option to annotate a blast m8 formatted similarity file.

Parameters:

=over 8

=item --api B<api_url>

url of m5nr API

=item --source B<source_name>

source for annotation

=back

Options:

=over 8

=item --help

display this help message

=item --verbose

run in a verbose mode

=item --sim B<similarity_file>

file in blast m8 format to be annotated

=item --acc B<accession_ids>

file or comma seperated list of protein ids

=item --md5 B<md5_checksums>

file or comma seperated list of md5sums

=item --sequence B<aa_sequence>

protein sequence, returns md5sum of sequence

=item --option B<output_type>

output type, one of: sequence or annotation
note: sequence output only available for --md5 input

=back

Output:

M5NR annotations based on input options.

=head1 EXAMPLES

m5nr-tools --api http://kbase.us/services/communities/1 --option annotation --source RefSeq --md5 0b95101ffea9396db4126e4656460ce5,068792e95e38032059ba7d9c26c1be78,0b96c92ce600d8b2427eedbc221642f1

=head1 SEE ALSO

-

=head1 AUTHORS

Jared Bischof, Travis Harrison, Folker Meyer, Tobias Paczian, Andreas Wilke

=cut


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

if ($help) {
    help();
    exit 0;
}

unless ($api) {
    print STDERR "Missing required API url\n";
    help();
    exit 1;
}

my $agent = LWP::UserAgent->new;
my $json  = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

my $smap = {};
eval {
    %$smap = map { $_->{source}, 1 } @{ get_data('GET', 'sources') };
};

unless (exists($options->{$opt}) || $seq || $sim) {
    print STDERR "One of the following paramters are required: option, sequence, or sim\n";
    help();
    exit 1;
}
unless ($src) {
    print STDERR "Source is required\n";
    help();
    exit 1;
}
unless (exists $smap->{$src}) {
    print STDERR "Invalid source: $src\n";
    print STDERR "Use one of: ".join(", ", keys %$smap)."\n";
    help();
    exit 1;
}

if ($sim) {
    unless (-s $sim) {
        print STDERR "Similarity file missing: $sim\n";
        help();
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
    help();
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
    pod2usage( { -exitval => 0,
                 -output  => \*STDOUT,
                 -verbose => 2,
		         -noperldoc => 1
               } );
}
