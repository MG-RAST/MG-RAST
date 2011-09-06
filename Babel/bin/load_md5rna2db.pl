#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Carp;
use DBI;
use Getopt::Long;

use Global_Config;

my $verbose   = 0;
my $datafile  = '';
my $taxfile   = '';
my $index     = 0;
my $test      = 0;
my $tmpdir    = "/tmp";
my $dbname    = $Global_Config::babel_db;
my $dbhost    = $Global_Config::babel_dbhost;
my $dbuser    = $Global_Config::babel_dbuser;
my $usage     = qq(
DESCRIPTION: ($0)
load the ACH database tables with the inputted file data. Must be postgresql db.

USAGE:
  --datafile  source_data   Required.
  --taxfile   source_tax    Required.
  --tmp_dir   dir           Optional. Dir to create temperary files. Default is '$tmpdir'
  --dbhost    db user       Optional. Server of database. Default is '$dbhost'
  --dbname    db name       Optional. Name of database. Default is '$dbname'
  --dbuser    db user       Optional. Owner of database. Default is '$dbuser'
  --index                   Optional. Create and load indexes when done. Default is off.
  --test                    Optional. Run without psql COPY and index drop/load. Default is off.
  --verbose                 Optional. Verbose output. Default is off.

);
if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! &GetOptions ('verbose!'    => \$verbose,
		    'index!'      => \$index,
		    'test!'       => \$test,
		    'datafile=s'  => \$datafile,
		    'taxfile=s'   => \$taxfile,
		    'tmp_dir:s'   => \$tmpdir,
		    'dbhost:s'    => \$dbhost,
		    'dbname:s'    => \$dbname,
		    'dbuser:s'    => \$dbuser
		   ) )
  { print STDERR $usage; exit; }

unless ($datafile && $taxfile && (-s $datafile) && (-s $taxfile)) { print STDERR $usage; exit; }

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " , DBI->error , "\n"; }

my $psql = "psql -U $dbuser -h $dbhost -d $dbname";
my $taxa = {};
my $tbls = { tbl => { md5   => "md5_rna",
		      func  => "functions",
		      org   => "organisms_ncbi",
		      src   => "sources"
		    },
	     idx => { md5   => ["id","md5","function","organism","tax_rank","source"],
		      func  => ["name"],
		      src   => ["name"]
		    } };

open(TFILE, "$taxfile") || die "Can't open file $taxfile\n";
if ($verbose) { print STDERR "Parsing $taxfile ... \n"; }
while (my $line = <TFILE>) {
  chomp $line;
  my ($id, $tax) = split(/\t/, $line);
  unless ($id && $tax) { next; }
  my @tax_set  = map { &clean_wsp($_) } split(/;/, $tax);
  my $tax_rank = &rank_taxonomy($tax, join(" ", @tax_set[0,1]));
  $taxa->{$id} = [ $tax_rank, [ reverse @tax_set ] ];
}
close TFILE;

&drop_table_indexes($dbh, $tbls->{tbl}{func}, $verbose);
&drop_table_indexes($dbh, $tbls->{tbl}{src}, $verbose);

my $func_ids = &get_id_set($dbh, $psql, $tbls->{tbl}{func}, '3', 'name', $datafile, $verbose);
my $src_ids  = &get_id_set($dbh, $psql, $tbls->{tbl}{src}, '5', 'name', $datafile, $verbose);
my $org_ids  = &get_name_id_from_db($dbh, $tbls->{tbl}{org}, $verbose);
my ($funcID, $orgID, $srcID, $rankID);

my $data_tmp = "$tmpdir/data." . unpack("H*", pack("Nn", time, $$));
open(DTMP, ">$data_tmp") || die "Can not open $data_tmp: $!";
open(DFILE, "$datafile") || die "Can't open file $datafile\n";

if ($verbose) { print STDERR "Parsing $datafile ... \n"; }
my $count = 0;
while (my $line = <DFILE>) {
  chomp $line;
  my ($md5, $id, $func, $org, $source) = split(/\t/, $line);
  unless ($md5 && $id && exists($taxa->{$id})) { next; }

  $funcID = ($func   && exists($func_ids->{$func}))  ? $func_ids->{$func}  : '\\N';
  $srcID  = ($source && exists($src_ids->{$source})) ? $src_ids->{$source} : '';
  $orgID  = '';
  $rankID = $taxa->{$id}[0];

  if ($org && exists($org_ids->{$org})) {
    $orgID = $org_ids->{$org};
  }
  else {
    foreach my $t ( @{$taxa->{$id}[1]} ) {
      if (exists $org_ids->{$t}) {
	$orgID = $org_ids->{$t};
	last;
      }
    }
  }

  if ($md5 && $id && $funcID && $orgID && $srcID && $rankID) {
    print DTMP join("\t", ($md5, $id, $funcID, $orgID, $rankID, $srcID)) . "\n";
  }
    
  $count += 1;
  unless ($count % 100000) {
    if ($verbose) { print STDERR "$count\t $md5 , $id , $func ($funcID) , $org ($orgID) , $rankID, $source ($srcID)\n"; }
  }
}
close DFILE;
close DTMP;

&drop_table_indexes($dbh, $tbls->{tbl}{md5}, $verbose);
&psql_copy($psql, $tbls->{tbl}{md5}, 'md5,id,function,organism,tax_rank,source', $data_tmp, $verbose);
$dbh->commit;

if ($index) {
  foreach (('func','src','md5')) {
    &create_table_indexes($dbh, $tbls->{tbl}{$_}, $tbls->{idx}{$_}, $verbose);
  }
}

$dbh->commit;
$dbh->disconnect;
if ($verbose) { print STDERR "Done.\n"; }
exit 0;


sub drop_table_indexes {
  my ($dbh, $table, $v) = @_;
  
  if ($test) { return; }
  my @rv;
  if ($v) { print STDERR "Disabling indexes for $table ...\n"; }
  my $sql = qq(SELECT ci.relname FROM pg_index i, pg_class ci, pg_class ct
               WHERE i.indexrelid=ci.oid AND i.indrelid=ct.oid AND i.indisprimary is false AND ct.relname='$table');
  my $idx = $dbh->selectcol_arrayref($sql);
  if ($idx && (@$idx > 0)) {
    foreach my $i (@$idx) { push @rv, $dbh->do("DROP INDEX IF EXISTS $i"); }
  }
  $dbh->commit;
  if ($v) { print STDERR join("\n", @rv) . "\n"; }
}

sub create_table_indexes {
  my ($dbh, $table, $indexes, $v) = @_;

  if ($test) { return; }
  my @rv;
  foreach my $i (@$indexes) {
    my $x = $i;
    $x =~ s/,/_/g;
    my $sql = "CREATE INDEX ${table}_$x ON $table ($i)";
    if ($v) { print STDERR "$sql\n"; }
    push @rv, $dbh->do($sql);
  }
  $dbh->commit;
  if ($v) { print STDERR join("\n", @rv) . "\n"; }
}

sub psql_copy {
  my ($cmd, $table, $cols, $file, $v) = @_;

  my $psql = qq($cmd -c "COPY $table ($cols) FROM '$file';");
  unless (-s $file) {
    print STDERR "No data in '$file' to COPY to '$table', skipping\n"; return;
  }
  if ($test) { print STDERR "\n$psql\n"; return; }
  
  my $run = &run_cmd($psql, $v);
  #if ($run) { unlink($file); }
}

sub get_id_set {
  my ($dbh, $psql, $table, $cnum, $cname, $file, $v, $org_map) = @_;

  my $set = &get_name_id_from_db($dbh, $table, $v);
  my $tmp = "$tmpdir/$table." . unpack("H*", pack("Nn", time, $$));
  my $cmd = "cat $file | cut -f$cnum | sort -u | sed '/^\\s*\$/d' | tr -c '[:print:][:cntrl:]' '[?*]'";

  # if already has values in table, just get unique new ones
  if ( scalar(keys %$set) > 0 ) {
    print STDERR "Running $cmd ...\nOutputing unique $table to $tmp ... " if ($v);
    open(TMP, ">$tmp") || die "Can not open $tmp: $!";
    foreach my $n (`$cmd`) {
      chomp $n;
      if (! exists $set->{$n}) { print TMP &clean_text($n) . "\n"; }
    }
    close TMP;
    print STDERR "Done\n" if ($v);
  }
  # else get unique all
  else {
    &run_cmd("$cmd > $tmp", $v);
  }
  &psql_copy($psql, $table, $cname, $tmp, $v);
  return &get_name_id_from_db($dbh, $table, $v);
}

sub get_name_id_from_db {
  my ($dbh, $table, $v) = @_;

  print STDERR "Getting data for $table ... " if ($v);
  my %set = ();
  my $all = $dbh->selectall_arrayref("SELECT name, _id FROM $table");
  if ($all && (@$all > 0)) {
    %set = map { $_->[0], $_->[1] } @$all;
  }
  print STDERR "Done - " . scalar(keys %set) . " $table\n" if ($v);

  return \%set;
}

sub clean_wsp {
  my ($text) = @_;

  if (! $text) { return $text; }
  my $clean = $text;
  $clean =~ s/^\s+//;
  $clean =~ s/\s+$//;
  return $clean;
}

sub clean_text {
  my ($text) = @_;

  if (! $text) { return $text; }
  my $clean = $text;
  $clean =~ s/^\s+//;
  $clean =~ s/\s+$//;
  $clean =~ s/\\/\\\\/g; # escape the escapes
  $clean =~ s/'/\\'/g;   # escape the single quotes
  return $clean;
}

sub rank_taxonomy {
  my ($tax, $top) = @_;
  my $rank;

  ## enviromental
  if ($tax =~ /(environmental samples|uncultured)/i) {
    $rank = 3;
  }
  ## unknown
  elsif ($top =~ /(artificial sequences|other sequences|unclassified|unidentified|unknown)/i) {
    $rank = 2;
  }
  ## known
  else {
    $rank = 1;
  }
  return $rank;
}

sub run_cmd {
  my ($cmd, $v) = @_;

  if ($v) { print STDERR "Running: $cmd ...\n"; }
  my $r = system($cmd);
  if ($r == 0) {
    return 1;
  } else {
    die "ERROR: $cmd: $!\n"
  }
}
