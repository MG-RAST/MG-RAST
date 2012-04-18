#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Cache::Memcached;
use DBI;

my $bindir  = "/homes/tharriso/MGRAST/Babel/bin";
my $verbose = 0;
my $memkey  = '_ach';
my $memhost = "kursk-1.mcs.anl.gov:11211";
my $dbhost  = "kursk-1.mcs.anl.gov";
my $dbname  = "mgrast_ach_prod";
my $dbuser  = "mgrastprod";
my $tmpdir  = "/tmp";
my $usage   = qq($0
  --verbose     optional
  --mem_host    memcache host, default '$memhost'
  --mem_key     memcache key extension, default '$memkey'
  --dbhost      db host, default '$dbhost'
  --dbname      db name, default '$dbname'
  --dbuser      db user, default '$dbuser'
  --tmpdir      temp dir, default '$tmpdir'
  );

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions('verbose!'   => \$verbose,
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

my $mch = new Cache::Memcached {'servers' => [$memhost], 'debug' => 0, 'compress_threshold' => 10_000};
unless ($mch && ref($mch)) { print STDERR "Unable to connect to memcache:\n$usage"; exit 1; }

my @types = ('source', 'organism', 'function');
my @md5s  = ('md5_protein', 'md5_rna', 'md5_ontology');

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

# create mapping tables
print STDERR "Creating tables ... " if ($verbose);
foreach my $t ((@types, @md5s)) {
  $dbh->do("DROP TABLE IF EXISTS ${t}_map");
}
$dbh->do("SELECT _id, name, type INTO source_map FROM sources");
$dbh->do("SELECT _id, name, ncbi_tax_id INTO organism_map FROM organisms_ncbi");
$dbh->do("SELECT _id, name INTO function_map FROM functions");
$dbh->do("SELECT DISTINCT md5, source, function, organism INTO md5_protein_map FROM md5_protein");
$dbh->do("SELECT DISTINCT md5, source, function, organism INTO md5_rna_map FROM md5_rna");
$dbh->do("SELECT DISTINCT md5, source, function, id INTO md5_ontology_map FROM md5_ontology");
print STDERR "Done\n" if ($verbose);

# dump tables
print STDERR "Dumping tables ... " if ($verbose);
foreach my $t ((@types, @md5s)) {
  $dbh->do("COPY ${t}_map TO '$tmpdir/${t}_map' WITH NULL AS ''");
}
system("cat ".join(" ", map {"$tmpdir/${_}_map"} @md5s)." | sort > $tmpdir/md5_data_map");
print STDERR "Done\n" if ($verbose);

# load memcache
print STDERR "Loading memcache ...\n" if ($verbose);
foreach my $t (@types) {
  system("$bindir/md52memcache.pl --verbose --mem_host $memhost --mem_key $memkey --map $tmpdir/${t}_map --option $t");
}
system("$bindir/md52memcache.pl --verbose --mem_host $memhost --mem_key $memkey --md5 $tmpdir/md5_data_map --lca $tmpdir/md5_lca_map --option md5");
print STDERR "Done\n" if ($verbose);

$dbh->disconnect;
