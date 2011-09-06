#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Carp;
use DBI;
use Getopt::Long;

use Global_Config;

my $verbose   = 0;
my @datafile  = ();
my @aliasfile = ();
my $dbtype    = $Global_Config::babel_dbtype;
my $dbname    = $Global_Config::babel_db;
my $dbhost    = $Global_Config::babel_dbhost;
my $dbuser    = $Global_Config::babel_dbuser;
my $usage     = qq(
DESCRIPTION: (load_MD5DATA2DB)
load the ACH database tables with the inputted file data.

USAGE:
  --datafile  source_data   Required. This may be multiple files by calling the option multiple times
  --aliasfile source_alias  Optional. This may be multiple files by calling the option multiple times.
  --dbhost    db user       Optional. Server of database. Default is '$dbhost'
  --dbname    db name       Optional. Name of database. Default is '$dbname'
  --dbtype    db type       Optional. Type (pg|mysel) of database. Default is '$dbtype'
  --dbuser    db user       Optional. Owner of database. Default is '$dbuser'
  --verbose                 Optional. Verbose output.

);
if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! &GetOptions ('verbose!'    => \$verbose, 
		    'datafile=s'  => \@datafile,
		    'aliasfile=s' => \@aliasfile,
		    'dbhost:s'    => \$dbhost,
		    'dbname:s'    => \$dbname,
		    'dbtype:s'    => \$dbtype,
		    'dbuser:s'    => \$dbuser
		   ) )
  { print STDERR $usage; exit; }

if (@datafile == 0) { print STDERR $usage; exit; }

my $dbh = DBI->connect("DBI:$dbtype:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " , DBI->error , "\n"; }

my $alias_id  = &get_next_id($dbh, 'ACH_ALIASES');
my $alias_hdl = $dbh->prepare("INSERT INTO ACH_ALIASES (_id,id,alias_id,alias_source) VALUES (?,?,?,?)");

foreach my $afile (@aliasfile) {
  open(AFILE, "<$afile") || die "Can't open file $afile\n";
  if ($verbose) { print STDERR "Parsing $afile ... \n"; }

  while (my $line = <AFILE>) {
    chomp $line;
    my ($id, @aliases) = split(/\t/, $line);
    foreach (@aliases) {
      if ($_ =~ /^(\S+?):(\S+)$/) {
	my $return = $alias_hdl->execute($alias_id, $id, $2, $1);
    
	unless ($return && ($return == 1)) {
	  print STDERR "ERROR:\t $alias_id , $id , $2 , $1 \n";
	  exit;
	}

	$alias_id += 1;
	unless ($alias_id % 2000000) {
	  if ($verbose) { print STDERR "$alias_id:\t$id , $2 , $1\n"; }
	}
      }
    }
  }
  close AFILE;
}

my $table      = "ACH_DATA";
my $data_id    = &get_next_id($dbh, $table);
my $idctg_id   = &get_next_id($dbh, 'ACH_ID2CONTIG');
my $org_ids    = {};
my $contig_ids = {};
my $source_ids = {};
my $func_ids   = {};

&disable_data_table_indexes($dbh, $table, $dbtype, $verbose);
my $data_hdl  = $dbh->prepare("INSERT INTO $table (_id,md5,id,function,organism,source) VALUES (?,?,?,?,?,?)");
my $idctg_hdl = $dbh->prepare("INSERT INTO ACH_ID2CONTIG (_id,data_id,contig,strand,low,high) VALUES (?,?,?,?,?,?)");

foreach my $file (@datafile) {
  open (FILE , "$file") or die "Can't open file $file\n";
  if ($verbose) { print STDERR "Parsing $file ... \n"; }
  
  while (my $line = <FILE>) {
    chomp $line;
    my ($md5, $id, $func, $org, $source, $beg, $end, $strand, $ctg_id, $ctg_desc, $len) = split(/\t/, $line);

    unless ($md5 && $id) { next; }

    $func = &clean_text($func);
    $org  = &clean_text($org);
    
    my $funcID = ($func   ? &get_function($dbh,$func,$func_ids)   : undef);
    my $orgID  = ($org    ? &get_org($dbh,$org,$org_ids)          : undef);
    my $srcID  = ($source ? &get_source($dbh,$source,$source_ids) : undef);

    if (defined($beg) && defined($end) && $strand && $ctg_id && $ctg_desc && $len) {
      $ctg_id   = &clean_text($ctg_id);
      $ctg_desc = &clean_text($ctg_desc);
      my $ctgID = &get_contig($dbh,$ctg_id,$contig_ids,$ctg_desc,$len,$orgID);
      my $exec  = $idctg_hdl->execute($idctg_id, $data_id, $ctgID, $strand, $beg, $end);
      $idctg_id++;
    }

    my $return = $data_hdl->execute($data_id, $md5, $id, $funcID, $orgID, $srcID);    
    unless ($return && ($return == 1)) {
      print STDERR "ERROR:\t $md5 , $id , $func , $org , $source \n";
      exit;
    }
    
    $data_id++;
    unless ($data_id % 100000) {
      if ($verbose) { print STDERR "$data_id\t $md5 , $id , $func , $org , $source \n"; }
    }
  }
  close FILE;
}

&enable_data_table_indexes($dbh, $table, $dbtype, $verbose);
my $rc = $dbh->rollback;
unless ($rc) { print STDERR "Error: " , $dbh->errstr , "\n"; }

$dbh->disconnect;
if ($verbose) { print STDERR "Done.\n"; }
exit;


sub disable_data_table_indexes {
  my ($dbh, $table, $dbtype, $v) = @_;

  my @rv;
  if ($v) { print STDERR "Disabling indexes for $table ...\n"; }
  if ($dbtype =~ /^mysql$/i) {
    push @rv, $dbh->do("ALTER TABLE $table DISABLE KEYS");
  }
  elsif ($dbtype =~ /^(pg$|postgres)/i) {
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_ID");
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_md5");
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_function");
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_organism");
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_org_group");
    push @rv, $dbh->do("DROP INDEX IF EXISTS DATA_md5_source");
  }
  if ($v) { print STDERR join("\n", @rv) . "\n"; }
}

sub enable_data_table_indexes {
  my ($dbh, $table, $dbtype, $v) = @_;

  my @rv;
  if ($v) { print STDERR "Enabling indexes for $table ...\n"; }
  if ($dbtype =~ /^mysql$/i) {
    push @rv, $dbh->do("ALTER TABLE $table ENABLE KEYS");
  }
  elsif ($dbtype =~ /^(pg$|postgres)/i) {
    push @rv, $dbh->do("CREATE INDEX DATA_ID ON $table (id)");
    push @rv, $dbh->do("CREATE INDEX DATA_md5 ON $table (md5)");
    push @rv, $dbh->do("CREATE INDEX DATA_function ON $table (function)");
    push @rv, $dbh->do("CREATE INDEX DATA_organism ON $table (organism)");
    push @rv, $dbh->do("CREATE INDEX DATA_org_group ON $table (organism_group)");
    push @rv, $dbh->do("CREATE INDEX DATA_md5_source ON $table (source,md5)");
  }
  if ($v) { print STDERR join("\n", @rv) . "\n"; }
}

sub get_org {
    my ($dbh, $org, $org_ids) = @_;

    unless ( $org_ids->{$org} ) {
      my $sql = "SELECT _id FROM ACH_ORGANISMS WHERE name='$org'";	
      my $row = $dbh->selectrow_arrayref($sql);

      if ( $row && (@$row > 0) ) {
	$org_ids->{$org} = $row->[0];
      } else {
	my $id = &get_next_id($dbh, "ACH_ORGANISMS");
	$dbh->do("INSERT INTO ACH_ORGANISMS (_id, name) VALUES ($id, '$org')");
	$org_ids->{$org} = $id;
      }
    }
    return $org_ids->{$org};
}

sub get_contig {
  my ($dbh, $contig, $contig_ids, $ctg_desc, $len, $orgID) = @_;

    unless ( $contig_ids->{$contig} ) {
      my $sql = "SELECT _id FROM ACH_CONTIGS WHERE name='$contig'";	
      my $row = $dbh->selectrow_arrayref($sql);

      if ( $row && (@$row > 0) ) {
	$contig_ids->{$contig} = $row->[0];
      } else {
	my $id = &get_next_id($dbh, "ACH_CONTIGS");
	$dbh->do("INSERT INTO ACH_CONTIGS (_id, name, description, length, organism) VALUES ($id, '$contig', '$ctg_desc', $len, $orgID)");
	$contig_ids->{$contig} = $id;
      }
    }
    return $contig_ids->{$contig};
}

sub get_source {
    my ($dbh, $source, $source_ids) = @_;

    unless ( $source_ids->{$source} ) {
      my $sql = "SELECT _id FROM ACH_SOURCES WHERE name='$source'";	
      my $row = $dbh->selectrow_arrayref($sql);
 
      if ( $row && (@$row > 0) ) {
	$source_ids->{$source} = $row->[0];
      } else {
	my $id = &get_next_id($dbh, "ACH_SOURCES");
	$dbh->do("INSERT INTO ACH_SOURCES (_id, name) VALUES ($id, '$source')");
	$source_ids->{$source} = $id;
      }
    }
    return $source_ids->{$source};
}

sub get_function {
    my ($dbh, $func, $func_ids) = @_;

    unless ( $func_ids->{$func} ) {
      my $sql = "SELECT _id FROM ACH_FUNCTIONS WHERE function='$func'";
      my $row = $dbh->selectrow_arrayref($sql);

      if ( $row && (@$row > 0) ) {
	$func_ids->{$func} = $row->[0];
      } else {
	my $id = &get_next_id($dbh, "ACH_FUNCTIONS");
	$dbh->do("INSERT INTO ACH_FUNCTIONS (_id, function) VALUES ($id, '$func')");
	$func_ids->{$func} = $id;
      }
    }
    return $func_ids->{$func};
}

sub get_next_id {
  my ($dbh, $table) = @_;

  my $row = $dbh->selectrow_arrayref("SELECT MAX(_id) FROM $table");
  return ($row && (@$row > 0)) ? $row->[0] + 1 : 1;
}

sub clean_text {
  my ($text) = @_;

  my $clean = $text;
  $clean =~ s/\\//g;
  $clean =~ s/'/\\'/g;
  $clean =~ s/^\s+//g;
  $clean =~ s/\s+$//g;
  return $clean;
}
