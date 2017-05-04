#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use ElasticSearch;
use Data::Dumper;
use JSON;
use DBI;
use warnings;
no warnings "numeric";

sub usage {
  print "elastic_dump.pl >>> dumps all or one metagenome from the database into the JSON format for elastic search input\n";
  print "elastic_dump.pl -user <user for database> -pass <password for database> -outfile <file name to write the output to or 'stream' to print to STDOUT> [ -id <metagenome_id to dump (no mgm prefix), omitting this will dump entire database>, -host <db host> ]\n";
}

my ($username, $password, $mgid, $outfile, $host);
my ($jid, $pid, $sid, $lid, $eid);

GetOptions(
    'user=s'    => \$username,
    'pass=s'    => \$password,
    'id=s'      => \$mgid,
    'host=s'    => \$host,
    'outfile=s' => \$outfile
);

unless ($username) {
  &usage;
  exit 0;
}

$outfile = $outfile || "dump.json";

my $json = JSON->new();
$json->max_size(0);
$json->allow_nonref;
$json->utf8();

my $pMap = $ElasticSearch::prefixes;

my $dbh = DBI->connect("DBI:mysql:database=JobDB".($host ? ";host=$host": ""), $username, $password, { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) || die "Database connect error: $@";

my $jobs = $dbh->selectall_hashref("SELECT _id, primary_project, sample, library, metagenome_id, job_id, public, name, sequence_type, created_on FROM Job".($mgid ? " WHERE metagenome_id='$mgid'" : ""), "_id");
if ($mgid) {
    $jid = (keys %$jobs)[0];
    $pid = $jobs->{$jid}{'primary_project'};
    $sid = $jobs->{$jid}{'sample'};
    $lid = $jobs->{$jid}{'library'};
}

my $ep = $dbh->selectall_arrayref("SELECT parent, _id FROM MetaDataCollection WHERE type='ep' AND parent IS NOT NULL".(($mgid && $sid) ? " AND parent=$sid" : ""));
my $sample_ep = {};
%$sample_ep = map { $_->[0] => $_->[1] } @$ep;
if ($mgid && $sid && exists($sample_ep->{$sid})) {
    $eid = $sample_ep->{$sid};
}

my $aSet = "(".join(",", map { "'".$_."'" } (@{$pMap->{'pipeline_parameters_'}}, 'sequencing_method_guess')).")";
my $ja = $dbh->selectall_arrayref("SELECT job, tag, value FROM JobAttributes WHERE value IS NOT NULL AND job IS NOT NULL AND tag IN $aSet".($mgid ? " AND job=$jid" : ""));
my $jobattributes = {};
foreach my $j (@$ja) {
  if (! exists $jobattributes->{$j->[0]}) {
    $jobattributes->{$j->[0]} = {};
  }
  $jobattributes->{$j->[0]}->{$j->[1]} = $j->[2];
}

my $sSet = "(".join(",", map { "'".$_."'" } @{$pMap->{'job_stat_'}}).")";
my $js = $dbh->selectall_arrayref("SELECT job, tag, value FROM JobStatistics WHERE value IS NOT NULL AND job IS NOT NULL AND tag IN $sSet".($mgid ? " AND job=$jid" : ""));
my $jobstatistics = {};
foreach my $j (@$js) {
  if (! exists $jobstatistics->{$j->[0]}) {
    $jobstatistics->{$j->[0]} = {};
  }
  $jobstatistics->{$j->[0]}->{$j->[1]} = $j->[2];
}

my $p = $dbh->selectall_arrayref("SELECT _id, name, id FROM Project".(($mgid && $pid) ? " WHERE _id=$pid" : ""));
my $projects = {};
%$projects = map { $_->[0] => {'project_name' => $_->[1], 'project_id' => $_->[2]} } @$p;

my $pSet = "(".join(",", map { "'".$_."'" } @{$pMap->{'project_'}}).")";
my $pmd = $dbh->selectall_arrayref("SELECT project, tag, value FROM ProjectMD WHERE value IS NOT NULL AND project IS NOT NULL AND tag IN $pSet".(($mgid && $pid) ? " AND project=$pid" : ""));
my $projectMD = {};
foreach my $p (@$pmd) {
  if (! exists $projectMD->{$p->[0]}) {
    $projectMD->{$p->[0]} = {};
  }
  $projectMD->{$p->[0]}->{$p->[1]} = $p->[2];
}

my $col = $dbh->selectall_arrayref("SELECT _id, name, ID FROM MetaDataCollection".(($mgid && $sid && $lid && $eid) ? " WHERE _id IN ($sid, $lid, $eid)" : ""));
my $collections = {};
%$collections = map { $_->[0] => {'name' => $_->[1], 'id' => $_->[2]} } @$col;

my $mSet = "(".join(",", map { "'".$_."'" } (@{$pMap->{'sample_'}}, @{$pMap->{'library_'}})).")";
my $mde = $dbh->selectall_arrayref("SELECT collection, tag, value FROM MetaDataEntry WHERE value IS NOT NULL AND collection IS NOT NULL AND tag IN $mSet".(($mgid && $sid && $lid && $eid) ? " AND collection IN ($sid, $lid, $eid)" : ""));
my $metadata = {};
foreach my $m (@$mde) {
  if (! exists $metadata->{$m->[0]} ) {
    $metadata->{$m->[0]} = {};
  }
  $metadata->{$m->[0]}->{$m->[1]} = $m->[2];
}

$dbh->disconnect();

my $fMap = $ElasticSearch::fields;
my $tMap = $ElasticSearch::types;
my $mMap = $ElasticSearch::mixs;
my $iMap = $ElasticSearch::ids;
map { $fMap->{$_} = (split(/\./, $fMap->{$_}))[0] } keys %$fMap;

if ($outfile ne "stream") {
  open(FH, ">$outfile") or die "could not open outfile: $outfile";
  print FH "[\n";
} else {
  print "[\n";
}

my $count = 1;
my $total = scalar(keys %$jobs);

foreach my $jid (keys %$jobs) {
    
    my $jdata = {};
    my $mixs  = 1;
    my $job   = $jobs->{$jid};
    my $eid   = undef;

    $pid = $job->{'primary_project'};
    $sid = $job->{'sample'};
    $lid = $job->{'library'};
    $eid = ($sid && $sample_ep->{$sid}) ? $sample_ep->{$sid} : undef;
    
    # job_info
    foreach my $k (%$job) {
        if ($k && exists($fMap->{$k}) && defined($job->{$k})) {
            $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $job->{$k});
        }
    }
  
    # job attributes
    if (exists $jobattributes->{$jid}) {
        foreach my $k (keys %{$jobattributes->{$jid}}) {
            if ($k && (exists $fMap->{$k}) && defined($jobattributes->{$jid}{$k})) {
                $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $jobattributes->{$jid}{$k});
            }
        }
    }
    
    # job statistics
    if (exists $jobstatistics->{$jid}) {
        foreach my $k (keys %{$jobstatistics->{$jid}}) {
            if ($k && exists($fMap->{$k}) && defined($jobstatistics->{$jid}{$k})) {
                $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $jobstatistics->{$jid}{$k});
            }
        }
    }
    
    # project
    if ($pid && exists($projects->{$pid})) {
        foreach my $k (keys %{$projects->{$pid}}) {
            if ($k && exists($fMap->{$k}) && defined($projects->{$pid}{$k})) {
                $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $projects->{$pid}{$k});
            }
        }
        if (exists $projectMD->{$pid}) {
            foreach my $k (keys %{$projectMD->{$pid}}) {
                # special case for ebi_id
                if ($k eq 'ebi_id') {
                    $k = 'project_'.$k;
                }
                if ($k && exists($fMap->{$k}) && defined($projectMD->{$pid}{$k})) {
                    $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $projectMD->{$pid}{$k});
                }
            }
        }
    }
    
    # collections - need to double prefix for id and name
    foreach my $col ((['sample_', $sid], ['library_', $lid], ['env_package_', $eid])) {
        my $cid = $col->[1];
        if ($cid && exists($collections->{$cid})) {
            foreach my $k (keys %{$collections->{$cid}}) {
                $k = $col->[0].$k;
                if (exists($fMap->{$k}) && defined($collections->{$cid}{$k})) {
                    $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $collections->{$cid}{$k});
                }
            }
        }
        if ($cid && exists($metadata->{$cid})) {
            foreach my $k (keys %{$metadata->{$cid}}) {
                # special case for ebi_id
                if ($k eq 'ebi_id') {
                    $k = $col->[0].$k;
                }
                if (exists($fMap->{$k}) && defined($metadata->{$cid}{$k})) {
                    $jdata->{ $fMap->{$k} } = typecast($tMap->{$k}, $metadata->{$cid}{$k});
                }
            }
        }
    }
    
    # special case fix
    unless (exists $jdata->{library_seq_meth}) {
        if (exists $jobattributes->{$jid}{sequencing_method_guess}) {
            $jdata->{library_seq_meth} = $jobattributes->{$jid}{sequencing_method_guess};
        }
    }
    
    # clean
    foreach my $k (keys %$jdata) {
        if (! defined($jdata->{$k})) {
            delete $jdata->{$k};
        }
    }
    
    # mixs
    foreach my $m (@$mMap) {
        if (! exists($jdata->{$m})) {
            $mixs = 0;
        }
    }
    if (exists $jdata->{library_investigation_type}) {
        if (($jdata->{library_investigation_type} eq 'metatranscriptome') && (! exists($jdata->{library_mrna_percent}))) {
            $mixs = 0;
        } elsif (($jdata->{library_investigation_type} eq 'mimarks-survey') && (! exists($jdata->{library_target_gene}))) {
            $mixs = 0;
        }
    }
    $jdata->{job_info_mixs_compliant} = $mixs ? JSON::true : JSON::false;
    
    # id prefixes
    foreach my $k (keys %$iMap) {
        my $pre = $iMap->{$k};
        if (exists($jdata->{$k}) && ($jdata->{$k} !~ /^$pre/)) {
            $jdata->{$k} = $pre.$jdata->{$k};
        }
    }
    
    my $entry = $json->encode($jdata);
    if ($outfile ne "stream") {
        print FH $entry.($count == $total ? "" : ",")."\n";
    } else {
        print $entry.($count == $total ? "" : ",")."\n";
    }
    $count++;
}

if ($outfile ne "stream") {
  print FH "]\n";
  close FH;
} else {
  print "]\n";
}

sub typecast {
    my ($type, $val) = @_;
    unless (defined($val)) {
        return undef;
    }
    if (($type eq 'text') || ($type eq 'keyword')) {
        $val =~ s/^\s+//;
        $val =~ s/\s+$//;
        $val =~ s/\s+/ /g;
        $val = lc($val);
    } elsif (($type eq 'integer') || ($type eq 'long')) {
        if ($val =~ /^[+-]?\d+$/) {
            $val = int($val);
        } else {
            $val = undef;
        }
    } elsif ($type eq 'float') {
        if ($val =~ /^[+-]?\d*\.?\d+$/) {
            $val = $val * 1.0
        } else {
            $val = undef;
        }
    } elsif ($type eq 'date') {
        $val =~ s/^\s+//;
        $val =~ s/\s+$//;
        $val =~ s/\s+/T/;
        $val =~ s/\-00/-01/g;
    } elsif ($type eq 'boolean') {
        $val = $val ? JSON::true : JSON::false;
    }
    return $val;
}

sub TO_JSON { return { %{ shift() } }; }

