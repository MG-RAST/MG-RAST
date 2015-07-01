#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON;
use DBI;
use LWP::UserAgent;

my $job     = "";
my $output  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $dbpass  = "";
my $m5nr    = "";
my $version = "";
my $usage   = qq($0
  --job     ID of job to dump
  --output  dump file prefix
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
  --dbpass  db password
  --m5nr    m5nr solr url
  --version m5nr version #
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'job:i'     => \$job,
    'output:s'  => \$output,
    'dbhost:s'  => \$dbhost,
	'dbname:s'  => \$dbname,
	'dbuser:s'  => \$dbuser,
	'dbpass:s'  => \$dbpass,
	'm5nr:s'    => \$m5nr,
	'version:i' => \$version
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($job && $output) {
    print STDERR $usage; exit 1;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, $dbpass, {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

my $agent = LWP::UserAgent->new;
$agent->timeout(600);
my $json = JSON->new;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

open(DUMP, ">$output.$job") or die "Couldn't open $output.$job for writing.\n";

my $query = "SELECT md5, abundance, exp_avg, ident_avg, len_avg, exp_stdv, ident_stdv, len_stdv, seek, length, is_protein FROM job_md5s WHERE version=$version AND job=$job";
my $sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

my @batch_set = ();
my $batch_count = 0;
my $md5_count = 0;
my $batch_num = 0;
while (my @row = $sth->fetchrow_array()) {
    push @batch_set, \@row;
    $batch_count += 1;
    $md5_count += 1;
    if ($batch_count == 1000) {
        $batch_num += 1;
        my @output = process_batch(\@batch_set, $m5nr."/m5nr_".$version."/select");
        foreach my $line (@output) {
            print DUMP join(",", map { '"'.$_.'"' } @$line)."\n";
        }
        @batch_set = ();
        $batch_count = 0;
    }
}
if (@batch_set > 0) {
    $batch_num += 1;
    my @output = process_batch(\@batch_set, $m5nr."/m5nr_".$version."/select");
    foreach my $line (@output) {
        print DUMP join(",", map { '"'.$_.'"' } @$line)."\n";
    }
}

close(DUMP);
$dbh->disconnect;

sub process_batch {
    my ($batch_set, $url) = @_;
    
    my $try = 0;
    my $data = {};
    my @mids = map { $_->[0] } @batch_set;
    my @field = ('md5_id', 'md5', 'source', 'accession', 'function', 'organism');
    my $query = 'q=*%3A*&fq=md5_id:('.join(' OR ', @mids).')&start=0&rows=1000000000&wt=json&fl='.join('%2C', @field);
    my $result = $agent->post($url, Content => $query);
    
    while (1) {
        my $result = $agent->post($url, Content => $query);
        eval {
            my $content = $json->decode($result->content);
            foreach my $m (@{$content->{response}{docs}}) {
                push @{ $data->{$m->{md5_id}} }, $m;
            }
        };
        if ($@) {
            # try again !!!
            if ($try >= 3) {
                print STDERR "Failed 3 times at md5 $md5_count (batch $batch_num)\n".$@."\n".$result->content."\n";
                $dbh->disconnect;
                exit 1;
            } else {
                $try += 1;
            }
        } else {
            last;
        }
    }
    
    my @output = ();
    foreach my $set (@batch_set) {
        my ($mid, $abund, $ea, $ia, $la, $es, $is, $ls, $seek, $len, $prot) = @$set;
        next unless ($data->{$mid});
        next if (int($ea) > 0);
        $ea = $ea * -1;
        my $md5  = $data->{$mid}[0]{md5};
        my $srcs = {};
        my $md5_info = {
            "abundance"  => $abund,
            "exp_avg"    => $ea,
            "ident_avg"  => $ia,
            "len_avg"    => $la,
            "exp_stdv"   => $es,
            "ident_stdv" => $is,
            "len_stdv"   => $ls,
            "seek"       => defined($seek) ? $seek : "",
            "length"     => defined($len) ? $len : "",
            "is_protein" => $prot ? 'true' : 'false'
        };
        
        foreach my $ann (@{$data->{$mid}}) {
            next unless ($ann->{source});
            # source => [[ accession, function, organism ]]
            $ann->{accession} =~ s/\'/''/g;
            $ann->{function}  =~ s/\'/''/g;
            $ann->{organism}  =~ s/\'/''/g;
            push @{$srcs->{$ann->{source}}}, [ $ann->{accession}, $ann->{function}, $ann->{organism} ];
        }
        foreach my $src (keys %$srcs) {
            my @acc = map { $_->[0] } @{$srcs->{$src}};
            my @fun = map { $_->[1] } @{$srcs->{$src}};
            my @org = map { $_->[2] } @{$srcs->{$src}};
            my $acc = "[".join(",", map { "'".$_."'" } @acc)."]";
            my $fun = "[".join(",", map { "'".$_."'" } @fun)."]";
            my $org = "[".join(",", map { "'".$_."'" } @org)."]";
            $acc =~ s/\"/\\"/g;
            $fun =~ s/\"/\\"/g;
            $org =~ s/\"/\\"/g;
            my $out = [ $version, $job, $src, $md5, $json->encode($md5_info), $acc, $fun, $org ];
            push @output, $out;
        }
    }
    return @output;
}
