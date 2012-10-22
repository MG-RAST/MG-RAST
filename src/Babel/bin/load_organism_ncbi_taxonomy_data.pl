#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use List::Util qw(max min sum first);

use Conf;
use Babel::lib::Babel;

my $usage       = "$0 [--verbose] [--dbname NAME] [--dbuser USER] [--dbhost HOST] --taxonomy TAXPONOMY_FILE\n";
my $source_file = '';
my $verbose     = '';
my $dbname      = $Conf::babel_db;
my $dbuser      = $Conf::babel_dbuser;
my $dbhost      = $Conf::babel_dbhost;

my $order = [ "superkingdom", "kingdom", "phylum", "class", "order", "family", "genus", "species" ];

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit; }
if ( ! GetOptions("verbose!"   => \$verbose,
		  "taxonomy=s" => \$source_file,
		  'dbname:s'   => \$dbname,
		  'dbuser:s'   => \$dbuser,
		  'dbhost:s'   => \$dbhost
		 ) ) {
  print STDERR $usage; exit;
}
if ( (! $source_file) || (! -s $source_file) ) {
  print STDERR $usage; exit;
}

# get data from taxonomy file
print "Reading taxonomy data from $source_file\n" if ($verbose);
my ($orgs, $species, $aliases) = &load_data_from_file($order, $source_file, $verbose);
print "Got " . scalar(keys %$orgs) . " organisms, " . scalar(keys %$species) . " species, and " . scalar(keys %$aliases) . " aliases from tax data\n" if ($verbose);

# map to organism in Babel
print "Initializing Babel DB\n" if ($verbose); 
my ($dbh, $babel);
if ($dbname && $dbuser && $dbhost) {
  $dbh   = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, '');
  $babel = Babel::lib::Babel->new($dbh);
}
else {
  $babel = new Babel::lib::Babel;
  $dbh   = $babel->dbh();
}
my $data = $babel->get_organism_list;
print "Got " . scalar(@$data) . " organisms from DB\n" if ($verbose); 

my $found   = 0;
my $aliased = 0;
my $missed  = 0;
my $found_no_id = 0;

foreach my $org ( @$data ) {
  if ( exists $orgs->{$org} ) {
    my $info = $orgs->{$org};
    &update_organism( $dbh, $org, $info->{id}, $info->{taxonomy}, $order );
    $found++;
  }
  elsif ( exists $aliases->{$org} ) {
    my $info = $orgs->{$aliases->{$org}};
    &update_organism( $dbh, $org, $info->{id}, $info->{taxonomy}, $order );
    $aliased++;
  }
  elsif ( $org =~ /^(\S+\s+\S+)/ ) {
    my $prefix = lc($1);
    if (exists $species->{$prefix}) {
      &update_organism( $dbh, $org, 0, $species->{$prefix}, $order );
      $found_no_id++;
    } else {
      $missed++;
    }
  }
  else {
    $missed++;
  }
}

print "Found: $found\tAliased: $aliased\tMissed: $missed\tFound No TaxID: $found_no_id\n";

sub load_data_from_file {
  my ($order, $source_file, $verbose) = @_;

  my $tax_groups  = {};
  my $species_tax = {};
  my $org_aliases = {};
  my %order_map   = map { $_, 1 } @$order;
  
  open (FILE , $source_file) or die "Can't open $source_file";
  
  while( my $line = <FILE>) {
    chomp $line;
    my @fields = split(/\t/, $line);
    
    unless (scalar @fields >= 3) {
      print STDERR "Error: bad line '$line'\n";
    }

    my ($tax_id, $org, $tax_str, @aliases) = @fields;

    $tax_groups->{$org}->{id} = $tax_id;
    my @tax_groups = split(/\|\|/, $tax_str);

    unless( $tax_groups[0] =~/^superkingdom/ ) {
      $tax_groups[0] =~ s/^[^=]+/superkingdom/g;
    }

    my $species  = "";
    my $tax_hash = {};

    foreach my $g (@tax_groups) {
      my ($taxa, $name) = split(/=/, $g);
      if ( $taxa && $name ) {
	if ( exists $order_map{$taxa} ) {
	  $tax_groups->{$org}->{taxonomy}->{$taxa} = $name;
	  $tax_hash->{$taxa} = $name;
	  if ($taxa eq "species") { $species = $name; }
	}
	elsif ( $name =~/^Viruses$/ ) {
	  $tax_groups->{$org}->{taxonomy}->{superkingdom} = $name;
	  $tax_hash->{superkingdom} = $name;
	}
      }
      else {
	print STDERR "$g => $org => $tax_str\n$line\n";
      }
    }
    $species_tax->{ lc($species) } = $tax_hash;
    
    foreach my $a (@aliases) {
      my (undef, $alias) = split(/=/, $a);
      if ($alias) { $org_aliases->{$alias} = $org; }
    }
  }
  
  return ($tax_groups, $species_tax, $org_aliases);
}

sub update_organism { 
  my ($dbh, $org, $tax_id, $tax_set, $order) = @_;

  my @values = ();

  for ( my $i=0; $i < scalar(@$order); $i++ ) {
    my $value = 'unclassified';
    if ( exists $tax_set->{$order->[$i]} ) {
      $value = $tax_set->{$order->[$i]};
    }
    else {
      my $pos = $i;
      while ( ! ($tax_set->{$order->[$pos]}) and $pos ge "0" ) {
	$pos--;
      }
      $value = "unclassified (derived from " . $tax_set->{$order->[$pos]} . ")";
    }
    push @values, ($value || "unknown");
  }
  my $tax_str = join(";", @values);
  unshift @values, $tax_str;
  unshift @values, $tax_id;

  my $vals = join(", ", map { $dbh->quote($_) } @values);
  my $qorg = $dbh->quote($org);
  my $sql  = qq(update organisms_ncbi set (ncbi_tax_id, taxonomy, tax_domain, tax_kingdom, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species) = ($vals) where name=$qorg;);

  $dbh->do($sql);
}
