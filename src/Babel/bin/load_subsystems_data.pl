#!/usr/bin/env perl

use strict;
use warnings;


use Data::Dumper;
use XML::Simple;
use Getopt::Long;

use Conf;
use Babel::lib::Babel;

my $usage       = "$0 [--verbose] [--dbtype TYPE] [--dbname NAME] [--dbuser USER] [--dbhost HOST] --subsystem SUBSYSTEM_FILE\n";
my $source_file = '';
my $verbose     = '';
my $source      = "SEED";
my $dbname      = $Conf::babel_db;
my $dbuser      = $Conf::babel_dbuser;
my $dbhost      = $Conf::babel_dbhost;
my $dbtype      = $Conf::babel_dbtype;

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! GetOptions("verbose!"    => \$verbose,
		  "subsystem=s" => \$source_file,
		  'dbname:s'    => \$dbname,
		  'dbuser:s'    => \$dbuser,
		  'dbhost:s'    => \$dbhost,
		  'dbtype:s'    => \$dbtype
		 ) ) {
  print STDERR $usage; exit;
}
if ( (! $source_file) || (! -s $source_file) ) {
  print STDERR $usage; exit;
}

# get data from subsystem file: func => [ step1, step2, subsys ]
print "Reading subsystem data from $source_file ... " if ($verbose);
my $ss_func2subsys = &load_data_from_file($source_file, $verbose);
print "Done\n" if ($verbose);

# get Babel db handle
print "Initializing Babel DB\n" if ($verbose); 
my ($dbh, $babel);
if ($dbname && $dbuser && $dbhost && $dbtype) {
  $dbh   = DBI->connect("DBI:$dbtype:dbname=$dbname;host=$dbhost", $dbuser, '');
  $babel = Babel::lib::Babel->new($dbh);
}
else {
  $babel = new Babel;
  $dbh   = $babel->dbh();
}

# load subsystem table: func => [ ids ]
print "Clearing current sybsystem table ... " if ($verbose);
$dbh->do("truncate table ach_subsystems");
print "Done\n" if ($verbose);

print "Loading subsystem table from data ... " if ($verbose);
my $ss_func2ids = &load_table_from_data($ss_func2subsys, $dbh);
print "Done\n" if ($verbose);

print "Clearing subsystem data from functions table ... " if ($verbose);
$dbh->do("alter table ach_functions drop column subsystem");
$dbh->do("alter table ach_functions add column subsystem integer[]");
$dbh->do("create index functions_subsystem on ach_functions (subsystem)");
print "Done\n" if ($verbose);

# get SEED functions from Babel: md5 => func => id
print "Getting function sets from DB for $source ... " if ($verbose);
my $md5_func_sets = {};
foreach ( @{ $babel->get_function_set_4_source($source) } ) {
  $md5_func_sets->{ $_->[0] }->{ $_->[1] } = $_->[2];
}
print "Done (" . scalar(keys %$md5_func_sets) . " sets found)\n" if ($verbose);

# map subsystem functions to babel SEED functions
my $found = {};
my $total = {};
my $ssid_funcids = {};
my $funcid_ssids = {};

print "Mapping subsystems to functions ... \n" if ($verbose);
foreach my $md5 ( keys %$md5_func_sets ) {
  my $ach_func2id = $md5_func_sets->{$md5};

  while ( my ($ach_f, $ach_id) = each %$ach_func2id ) {
    $ach_f =~ s/\[SS\]//;
    $ach_f =~ s/^\s+//;
    $ach_f =~ s/\s+$//;
    if ( exists $ss_func2ids->{$ach_f} ) {
      foreach my $ss_id ( @{ $ss_func2ids->{$ach_f} } ) {
	  $funcid_ssids->{$ach_id}->{$ss_id} = 1;
	  $ssid_funcids->{$ss_id}->{$ach_id} = 1;
	}
      $found->{$ach_f} = 1;
    }
    $total->{$ach_f} = 1;
  }
}
print "\tFound " . scalar(keys %$found) . " functions (out of " . scalar(keys %$total) . ")\n";

print "Updating " . scalar(keys %$ssid_funcids) . " subsystem entries ... " if ($verbose);
while ( my ($ssid, $funcids) = each %$ssid_funcids ) {
  my $a_str = "\'{" . join(",", keys %$funcids) . "}\'";
  $dbh->do("update ach_subsystems set function = $a_str where _id = $ssid");
}
print "Done\n" if ($verbose);

print "Updating " . scalar(keys %$funcid_ssids) . " function entries ... " if ($verbose);
while ( my ($funcid, $ssids) = each %$funcid_ssids ) {
  my $a_str = "\'{" . join(",", keys %$ssids) . "}\'";
  $dbh->do("update ach_functions set subsystem = $a_str where _id = $funcid");
}
print "Done\n\n" if ($verbose);


sub load_data_from_file {
  my ($source_file, $verbose) = @_;

  my $funcs = {};
  
  open (FILE, $source_file) or die "Can't open $source_file"; 
  while( my $line = <FILE>) {
    chomp $line;
    my @fields = split(/\t/, $line);
    
    unless (scalar @fields == 4) {
      print STDERR "Error: bad line '$line'\n";
    }

    my ($subsys, $step1, $step2, $func) = @fields;
    if (! $func) { next; }
    
    $subsys = $subsys || "Unknown";
    $step1  = $step1  || "Unknown";
    $step2  = $step2  || "Unknown";
    push @{ $funcs->{$func} }, [ $step1, $step2, $subsys ];
  }
  return $funcs;
}

sub load_table_from_data {
  my ($func2subsys, $dbh) = @_;

  my $insert = {};
  my $funcs  = {};
  my $i = 1;

  while ( my ($func, $val) = each %$func2subsys ) {
    foreach my $set ( @$val ) {
      my ($step1, $step2, $subsys) = @$set;
      my $key = "$step1$step2$subsys";
      if (exists $insert->{$key}) {
	push @{ $funcs->{$func} }, $insert->{$key};
      }
      else {
	my $qstep1  = $dbh->quote($step1);
	my $qstep2  = $dbh->quote($step2);
	my $qsubsys = $dbh->quote($subsys);
	$dbh->do("insert into ach_subsystems (_id, step1, step2, subsystem) values ($i, $qstep1, $qstep2, $qsubsys)");
	
	$insert->{$key} = $i;
	push @{ $funcs->{$func} }, $i;
	$i += 1;
      }
    }
  }
  return $funcs;
}
