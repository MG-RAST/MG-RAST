#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;
use JSON;
use DBI;
use warnings;
no warnings "numeric";

sub usage {
  print "profile_manager.pl >>> applies or removes a list of profiles to/from the database\n";
  print "profile_manager.pl -profiles <a json list of profile objects to apply> [ -remove <if true remove instead of add> -test <if true return statistics only (no db change), default is true> -host <db host> -user <db username> -password <db password>]\n";
}

my ($username, $password, $profiles, $remove, $test, $host);
$test = 1;

GetOptions(
	   'user=s'     => \$username,
	   'pass=s'     => \$password,
	   'host=s'     => \$host,
	   'remove=s'   => \$remove,
	   'profiles=s' => \$profiles,
	   'test=s'     => \$test
	   
);

unless ($profiles) {
  &usage;
  exit 0;
}

my $json = JSON->new();
$json->max_size(0);
$json->allow_nonref;
$json->utf8();

print "connecting to database\n";
my $dbh = DBI->connect("DBI:mysql:database=JobDB".($host ? ";host=$host": ""), $username, $password, { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) || die "Database connect error: $@";

print "reading profiles\n";
open(FH, "<".$profiles) or die "could not open profiles file: $@\n";
my $pdata = "";
while (<FH>) {
  chomp;
  $pdata .= $_;
}
my $pprof = $json->decode($pdata);
close FH;

print scalar(@$pprof)." profiles read\n";

foreach my $p (@$pprof) {
  print "testing profile ".$p->{name}."\n";
    
  my $numlevels = scalar(@{$p->{hierarchy}});
  my $ids = {};
  my ($bronze, $silver, $gold, $numbronze, $numsilver, $numgold, $bcollections, $scollections, $gcollections);
  $bronze = "'".join("', '", @{$p->{hierarchy}->[0]})."'";
  $numbronze = scalar(@{$p->{hierarchy}->[0]});
  $bcollections = $dbh->selectall_arrayref("SELECT collection FROM MetaDataEntry WHERE tag IN (".$bronze.") GROUP BY collection HAVING COUNT(*)=".$numbronze);
  if ($numlevels > 1) {
    $silver = $bronze.", '".join("', '", @{$p->{hierarchy}->[1]})."'";
    $numsilver = scalar(@{$p->{hierarchy}->[1]}) + $numbronze;
    $scollections = $dbh->selectall_arrayref("SELECT collection FROM MetaDataEntry WHERE tag IN (".$silver.") GROUP BY collection HAVING COUNT(*)=".$numsilver);
  }
  if ($numlevels > 2) {
    $gold = $silver.", '".join("', '", @{$p->{hierarchy}->[2]})."'";
    $numgold = scalar(@{$p->{hierarchy}->[2]}) + $numsilver;
    $gcollections = $dbh->selectall_arrayref("SELECT collection FROM MetaDataEntry WHERE tag IN (".$gold.") GROUP BY collection HAVING COUNT(*)=".$numgold);
  }

  if ($numlevels > 2) {
    map { $ids->{$_->[0]} = 1 } @$gcollections;
    print "found ".(scalar keys %$ids)." gold datasets\n";
    my $sids = {};
    my $bids = {};
    foreach my $c (@$scollections) {
      if (! $ids->{$c->[0]}) {
	$sids->{$c->[0]} = 1;
      }
    }
    print "found ".(scalar keys %$sids)." silver datasets\n";
    foreach my $c (@$bcollections) {
      if (! $ids->{$c->[0]} && ! $sids->{$c->[0]}) {
	$bids->{$c->[0]} = 1;
      }
    }
    print "found ".(scalar keys %$bids)." bronze datasets\n";
    unless ($test) {
      my $k = [];
      @$k = keys %$ids;
      print "adding gold tags\n";
      addIds($k, $p->{name}, $dbh, 'gold', $remove);
      @$k = keys %$sids;
      print "adding silver tags\n";
      addIds($k, $p->{name}, $dbh, 'silver', $remove, 1);
      @$k = keys %$bids;
      print "adding bronze tags\n";
      addIds($k, $p->{name}, $dbh, 'bronze', $remove, 1);
    }
  } elsif ($numlevels > 1) {
    map { $ids->{$_->[0]} = 1 } @$scollections;
    print "found ".(scalar keys %$ids)." gold datasets\n";
    my $sids = {};
    foreach my $c (@$scollections) {
      if (! $ids->{$c->[0]}) {
	$sids->{$c->[0]} = 1;
      }
    }
    print "found ".(scalar keys %$sids)." silver datasets\n";
    unless ($test) {
      my $k = [];
      @$k = keys %$ids;
      print "adding gold tags\n";
      addIds($k, $p->{name}, $dbh, 'gold', $remove);
      @$k = keys %$sids;
      print "adding silver tags\n";
      addIds($k, $p->{name}, $dbh, 'silver', $remove, 1);
    }
  } else {
    map { $ids->{$_->[0]} = 1 } @$bcollections;
    print "found ".(scalar keys %$ids)." gold datasets\n";
    unless ($test) {
      my $k = [];
      @$k = keys %$ids;
      print "adding gold tags\n";
      addIds($k, $p->{name}, $dbh, 'gold', $remove);
    }
  }
    
}

$dbh->disconnect();

print "all done.\n";

sub addIds {
  my ($ids, $name, $dbh, $rating, $remove, $nopurge) = @_;

  unless ($ids && $name && $dbh) {
    return;
  }

  unless ($nopurge) {
    $dbh->do("DELETE FROM MetaDataEntry WHERE tag = 'profile_rating_".$name."'");
    $dbh->commit;
  }
  
  if ($remove) {
    return;
  }

  $rating = $rating || "gold";

  my $sth = $dbh->prepare("INSERT INTO MetaDataEntry(value, collection, _collection_db, tag, mixs, required) VALUES ('$rating', ?, 2, 'profile_rating_$name', 0, 0)");
  foreach my $id (@$ids) {
    $sth->execute($id);
  }
  $dbh->commit;
}
