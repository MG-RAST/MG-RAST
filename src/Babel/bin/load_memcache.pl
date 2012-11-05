#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Cache::Memcached;
use DBI;

my $bindir  = "";
my $verbose = 0;
my $fdump   = 0;
my $memkey  = '_ach';
my $memhost = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $tmpdir  = "/tmp";
my $usage   = qq($0
  --verbose     optional
  --file_dump   only dump files, do not load memcache
  --mem_host    memcache host, default '$memhost'
  --mem_key     memcache key extension, default '$memkey'
  --dbhost      db host, default '$dbhost'
  --dbname      db name, default '$dbname'
  --dbuser      db user, default '$dbuser'
  --tmpdir      temp dir, default '$tmpdir'
  );

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
            'verbose!'   => \$verbose,
            'file_dump!' => \$fdump,
		    'mem_host:s' => \$memhost,
		    'mem_key:s'  => \$memkey,
		    'dbname:s'   => \$dbname,
		    'dbuser:s'   => \$dbuser,
		    'dbhost:s'   => \$dbhost,
		    'tmpdir:s'   => \$tmpdir
		 ) ) {
  print STDERR $usage; exit 1;
}

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '', {AutoCommit => 0});
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }

my @types = ('source', 'organism', 'function', 'ontology');
my @md5s  = ('md5_organism', 'md5_ontology', 'md5_lca');

# get lca table
my $has_lca = $dbh->selectcol_arrayref("SELECT COUNT(relname) FROM pg_class WHERE relname = 'md5_lca'");
unless ($has_lca && ($has_lca->[0] == 1)) {
  print STDERR "Creating md5_lca ...\n" if ($verbose);
  system("$bindir/md52lca.pl --verbose --load_db --out $tmpdir/md5_lca_map --dbhost $dbhost --dbname $dbname --dbuser $dbuser");
  print STDERR "Done\n" if ($verbose);
} else {
  print STDERR "Dumping md5_lca ... " if ($verbose);
  $dbh->do("COPY md5_lca TO '$tmpdir/md5_lca_map' WITH NULL AS ''");
  print STDERR "Done\n" if ($verbose);
}

# dump table data to files
print STDERR "Dumping table data ... " if ($verbose);
$dbh->do("COPY (SELECT _id, name, type FROM sources) TO '$tmpdir/source_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT _id, name, ncbi_tax_id FROM organisms_ncbi) TO '$tmpdir/organism_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT _id, name FROM functions) TO '$tmpdir/function_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT _id, id, type FROM ontologies) TO '$tmpdir/ontology_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT DISTINCT md5, source, function, organism FROM md5_protein) TO '$tmpdir/md5_protein_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT DISTINCT md5, source, function, organism FROM md5_rna) TO '$tmpdir/md5_rna_map' WITH NULL AS ''");
$dbh->do("COPY (SELECT DISTINCT m.md5, m.source, m.function, o._id FROM md5_ontology m, ontologies o WHERE m.id=o.id) TO '$tmpdir/md5_ontology_map' WITH NULL AS ''");
system("cat md5_protein_map md5_rna_map | sort -T $tmpdir > $tmpdir/md5_organism_map");
print STDERR "Done\n" if ($verbose);
$dbh->disconnect;

unless ($fdump) {
# load memcache
    print STDERR "Loading memcache ...\n" if ($verbose);
    foreach my $t (@types) {
        system("$bindir/md52memcache.pl --verbose --mem_host $memhost --mem_key $memkey --map $tmpdir/${t}_map --option $t");
    }
    foreach my $m (@md5s) {
        system("$bindir/md52memcache.pl --verbose --mem_host $memhost --mem_key $memkey --map $tmpdir/${m}_map --option $m");
    }
    print STDERR "Done\n" if ($verbose);
}
