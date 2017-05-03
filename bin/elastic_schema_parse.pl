#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use JSON;
use File::Slurp;
use POSIX qw(strftime);

sub TO_JSON { return { %{ shift() } }; }

sub usage {
    print "es_schema_parse.pl >>> parse elasticsearch schema to create perl hash of fields\n";
    print "es_schema_parse.pl -input <path to input schema file> -output <path to output file>\n";
}

# read in parameters
my $input  = '';
my $output = '';

GetOptions(
    'input=s'  => \$input,
    'output=s' => \$output
);

unless ($input and $output) {
    &usage();
    exit 0;
}

my $json = JSON->new();
$json->max_size(0);
$json->allow_nonref;

my $schema_str = read_file($input);
my $schema_obj = $json->decode($schema_str);
my $properties = $schema_obj->{mappings}{metagenome_metadata}{properties};

my @prefix = ("job_info_", "job_stat_", "project_", "sample_", "env_package_", "library_", "pipeline_parameters_");

open(OUTF, ">$output") or die "could not open outfile: $output";

# header
print OUTF "###################################\n";
print OUTF "# this is an auto-generated package\n";
print OUTF "# created by: /MG-RAST/bin/elastic_schema_parse.pl\n";
print OUTF "# created on: ".strftime("%Y-%m-%dT%H:%M:%S", gmtime)."\n";
print OUTF "###################################\n";
print OUTF "package ElasticSearch;\n\n";
print OUTF "use strict;\n";
print OUTF "use warnings;\n";
print OUTF "no warnings('once');\n\n";

# mixs list
print OUTF "our \$mixs = [\n";
print OUTF "\t'project_project_name',\n";
print OUTF "\t'sample_biome',\n";
print OUTF "\t'sample_feature',\n";
print OUTF "\t'sample_material',\n";
print OUTF "\t'sample_latitude',\n";
print OUTF "\t'sample_longitude',\n";
print OUTF "\t'sample_country',\n";
print OUTF "\t'sample_location',\n";
print OUTF "\t'sample_env_package',\n";
print OUTF "\t'sample_collection_date',\n";
print OUTF "\t'library_investigation_type',\n";
print OUTF "\t'library_seq_meth'\n";
print OUTF "]\n\n";

# id prefixes
print OUTF "our \$ids = {\n";
print OUTF "\t'id' => 'mgm'\n,";
print OUTF "\t'project_project_id' => 'mgp'\n,";
print OUTF "\t'sample_sample_id' => 'mgs'\n,";
print OUTF "\t'library_library_id' => 'mgl'\n,";
print OUTF "\t'env_package_env_package_id' => 'mge'\n";
print OUTF "}\n\n";

# field map
print OUTF "our \$fields = {\n";
print OUTF "\tall => 'all',\n";
print OUTF "\tmetagenome_id => 'id',\n";
foreach my $pf (@prefix) {
    foreach my $prop (keys %$properties) {
        if ($prop =~ /^$pf(.*)/) {
            my $name = $1;
            if (exists($properties->{$prop}{fields}) && exists($properties->{$prop}{fields}{keyword})) {
                print OUTF "\t$name => '$prop.keyword',\n";
            } else {
                print OUTF "\t$name => '$prop',\n";
            }
        }
    }
}
print OUTF "};\n\n";

# prefix map
print OUTF "our \$prefixes = {\n";
foreach my $pf (@prefix) {
    print OUTF "\t'$pf' => [\n";
    foreach my $prop (keys %$properties) {
        if ($prop =~ /^$pf(.*)/) {
            my $name = $1;
            print OUTF "\t\t'$name',\n";
        }
    }
    print OUTF "\t],\n";
}
print OUTF "};\n\n";

# type map
print OUTF "our \$types = {\n";
print OUTF "\tmetagenome_id => 'keyword',\n";
foreach my $pf (@prefix) {
    foreach my $prop (keys %$properties) {
        if ($prop =~ /^$pf(.*)/ && exists($properties->{$prop}{type})) {
            my $name = $1;
            print OUTF "\t$name => '".$properties->{$prop}{type}."',\n";
        }
    }
}
print OUTF "};\n\n1;\n";

