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
  print "elastic_dump.pl >>> dumps all or one metagenome from the database into the JSON format for elastic search input\n";
  print "elastic_dump.pl -user <user for database> -pass <password for database> -outfile <file name to write the output to or 'stream' to print to STDOUT> [ -id <metagenome_id to dump (no mgm prefix), omitting this will dump entire database>, -host <db host> ]\n";
}

my ($username, $password, $mgid, $outfile, $host);

GetOptions( 'user=s' => \$username,
	    'pass=s' => \$password,
            'id=s' => \$mgid,
	    'host=s' => \$host,
	    'outfile=s' => \$outfile );

unless ($username) {
  &usage;
  exit 0;
}

$outfile = $outfile || "dump.json";

my $dbh = DBI->connect("DBI:mysql:database=JobDB".($host ? ";host=$host": ""), $username, $password, { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) || die "Database connect error: $@";

my $jobs = $dbh->selectall_arrayref("SELECT _id, metagenome_id, job_id, public, name, sequence_type, created_on, primary_project, library, sample FROM Job".($mgid ? " WHERE metagenome_id=$mgid" : ""));
my $j_id = $jobs->[0]->[0];
my $pid = $jobs->[0]->[7];
my $sid = $jobs->[0]->[8];
my $lid = $jobs->[0]->[9];

my $ja = $dbh->selectall_arrayref("SELECT job, tag, value FROM JobAttributes WHERE value IS NOT NULL AND tag IN ('pipeline_version', 'aa_pid', 'assembled', 'bowtie', 'dereplicate', 'fgs_type', 'file_type', 'filter_ambig', 'filter_ln', 'filter_ln_mult', 'm5nr_annotation_version', 'm5nr_sims_version', 'm5rna_annotation_version', 'm5rna_sims_version', 'max_ambig', 'prefix_length', 'priority', 'rna_pid', 'screen_indexes') AND job IS NOT NULL".($mgid ? " AND job=$j_id" : ""));
my $jobattributes = {};
foreach my $j (@$ja) {
  if (! exists $jobattributes->{$j->[0]}) {
    $jobattributes->{$j->[0]} = {};
  }
  $jobattributes->{$j->[0]}->{$j->[1]} = $j->[2];
}

my $p = $dbh->selectall_arrayref("SELECT _id, name, id FROM Project".($mgid ? " WHERE _id=$pid" : ""));
my $projects;
%$projects = map { $_->[0] => $_ } @$p;

my $pmd = $dbh->selectall_arrayref("SELECT project, tag, value FROM ProjectMD WHERE value IS NOT NULL AND tag IN ('organization', 'organization_country', 'firstname', 'lastname', 'funding', 'pi_organization', 'pi_organization_country', 'pi_firstname', 'pi_lastname', 'ncbi_id')".($mgid ? " AND project=$pid" : ""));
my $projectMD = {};
foreach my $p (@$pmd) {
  if (! exists $projectMD->{$p->[0]}) {
    $projectMD->{$p->[0]} = {};
  }
  $projectMD->{$p->[0]}->{$p->[1]} = $p->[2];
}

my $col = $dbh->selectall_arrayref("SELECT _id, name, ID FROM MetaDataCollection".($mgid && $sid && $lid ? " WHERE _id IN ($sid, $lid)" : ""));
my $collections;
%$collections = map { $_->[0] => $_ } @$col;

my $mde = $dbh->selectall_arrayref("SELECT collection, tag, value FROM MetaDataEntry WHERE value IS NOT NULL AND tag IN ('gold_id', 'pubmed_id', 'collection_date', 'feature', 'latitude', 'longitude', 'altitude', 'depth', 'elevation', 'continent', 'biome', 'temperature', 'country', 'env_package_type', 'env_package_name', 'env_package_id', 'location', 'seq_meth', 'mrna_percent', 'target_gene', 'investigation_type', 'material')".($mgid && $sid && $lid ? " AND collection IN ($sid, $lid)" : ""));
my $metadata = {};
foreach my $m (@$mde) {
  if (! exists $metadata->{$m->[0]} ) {
    $metadata->{$m->[0]} = {};
  }
  $metadata->{$m->[0]}->{$m->[1]} = $m->[2];
}

my $ep = $dbh->selectall_arrayref("SELECT parent, value, name FROM MetaDataCollection, MetaDataEntry WHERE tag='env_package' AND MetaDataCollection._id=MetaDataEntry.collection AND parent IS NOT NULL".($mgid && $sid ? " AND parent=$sid" : ""));
foreach my $e (@$ep) {
  $metadata->{$e->[0]}->{env_package_type} = $e->[1];
  $metadata->{$e->[0]}->{env_package_name} = $e->[2];
}

my $jaMap = {
	     "pipeline_version" => [ "job_info_pipeline_version", 0 ],
	     "aa_pid" => [ "pipeline_parameters_aa_pid", 1 ],
	     "assembled" => [ "pipeline_parameters_assembled", 2 ],
	     "bowtie" => [ "pipeline_parameters_bowtie", 2 ],
	     "dereplicate" => [ "pipeline_parameters_dereplicate", 2 ],
	     "fgs_type" => [ "pipeline_parameters_fgs_type", 0 ],
	     "file_type" => [ "pipeline_parameters_file_type", 0 ],
	     "filter_ambig" => [ "pipeline_parameters_filter_ambig", 2 ],
	     "filter_ln" => [ "pipeline_parameters_filter_ln", 2 ],
	     "filter_ln_mult" => [ "pipeline_parameters_filter_ln_mult", 1 ],
	     "m5nr_annotation_version" => [ "pipeline_parameters_m5nr_annotation_version", 1 ],
	     "m5nr_sims_version" => [ "pipeline_parameters_m5nr_sims_version", 1 ],
	     "m5rna_annotation_version" => [ "pipeline_parameters_m5rna_annotation_version", 1 ],
	     "m5rna_sims_version" => [ "pipeline_parameters_m5rna_sims_version", 1 ],
	     "max_ambig" => [ "pipeline_parameters_max_ambig", 1 ],
	     "prefix_length" => [ "pipeline_parameters_prefix_length", 1 ],
	     "priority" => [ "pipeline_parameters_priority", 0 ],
	     "rna_pid" => [ "pipeline_parameters_rna_pid", 1 ],
	     "screen_indexes" => [ "pipeline_parameters_screen_indexes", 0 ]
	    };

my $pMap = {
	    "organization" => "project_organization",
	    "organization_country" => "project_organization_country",
	    "firstname" => "project_firstname",
	    "lastname" => "project_lastname",
	    "funding" => "project_funding",
	    "PI_organization" => "project_PI_organization",
	    "PI_organization_country" => "project_PI_organization_country",
	    "PI_firstname" => "project_PI_firstname",
	    "PI_lastname" => "project_PI_lastname",
	    "ncbi_id" => "project_ncbi_id"
	   };

my $libMap = {
	      "gold_id" => "library_gold_id",
	      "pubmed_id" => "library_pubmed_id",
	      "seq_meth" => "job_info_seq_method"
	     };

my $sampMap = {
	       "env_package_type" => [ "sample_env_package_type", 0 ],
	       "altitude" => [ "sample_altitude", 1 ],
	       "depth" => [ "sample_depth", 1 ],
	       "elevation" => [ "sample_elevation", 1 ],
	       "continent" => [ "sample_continent", 0 ],
	       "env_package_id" => [ "sample_env_package_id", 0 ],
	       "temperature" => [ "sample_temperature", 1 ],
	       "biome" => [ "sample_biome", 0 ],
	       "collection_date" => [ "sample_collection_date", 0 ],
	       "feature" => [ "sample_feature", 0 ],
	       "latitude" => [ "sample_latitude", 1 ],
	       "longitude" => [ "sample_longitude", 1 ],
	       "country" => [ "sample_country", 0 ],
	       "env_package_name" => [ "sample_env_package_name", 0 ],
	       "location" => [ "sample_location", 0 ],
	       "material" => [ "sample_material", 0 ]
	      };

my $mixsList = [
		"biome",
		"collection_date",
		"feature",
		"latitude",
		"longitude",
		"country",
		"env_package_name",
		"location",
		"material"
	       ];

if ($outfile ne "stream") {
  open(FH, ">$outfile") or die "could not open outfile: $outfile";

  print FH "[\n";
} else {
  print "[\n";
}

my $count = 1;
my $num = scalar(@$jobs);
foreach my $job (@$jobs) {

  my $mixs = 1;
  my $hasSM = 0;
  
  # Job
  $job->[6] =~ s/\s/T/;
  my $entry = '{ "id": "mgm'.$job->[1].'", "job_info_job_id": '.$job->[2].', "job_info_public": '.($job->[3] ? "true" : "false").', "job_info_name": "'.$job->[4].'", "job_info_sequence_type": "'.($job->[5]||"unknown").'", "job_info_created": "'.$job->[6].'"';

  # job attributes
  if (exists $jobattributes->{$job->[0]}) {
    foreach my $k (keys %{$jobattributes->{$job->[0]}}) {
      $entry .= ', "'.$jaMap->{$k}->[0].'": ';
      if ($jaMap->{$k}->[1] == 0) {
	$entry .= '"'.$jobattributes->{$job->[0]}->{$k}.'"';
      } elsif ($jaMap->{$k}->[1] == 1) {
	$entry .= sprintf("%g", $jobattributes->{$job->[0]}->{$k});
      } else {
	$entry .= $jobattributes->{$job->[0]}->{$k} ? "true" : "false";
      }
    }
  }

  # project
  if ($job->[7] && exists $projects->{$job->[7]}) {
    $projects->{$job->[7]}->[1] = &cleanse($projects->{$job->[7]}->[1]);
    
    $entry .= ', "project_project_name": "'.$projects->{$job->[7]}->[1].'", "project_project_id": "mgp'.$projects->{$job->[7]}->[2].'"';

    # project md
    if (exists $projectMD->{$projects->{$job->[7]}[0]}) {

      foreach my $k (keys %{$projectMD->{$projects->{$job->[7]}[0]}}) {
	$projectMD->{$projects->{$job->[7]}[0]}->{$k} = &cleanse($projectMD->{$projects->{$job->[7]}[0]}->{$k});
	$entry .= ', "'.$pMap->{$k}.'": "'.$projectMD->{$projects->{$job->[7]}[0]}->{$k}.'"';
      }
      
    } else {
      $mixs = 0;
    }
    
  }

  # library
  if ($job->[8] && exists $collections->{$job->[8]}) {
    $entry .= ', "library_library_name": "'.$collections->{$job->[8]}->[1].'", "library_library_id": "'.$collections->{$job->[8]}->[2].'"';

    if (exists $metadata->{$collections->{$job->[8]}->[0]}) {

      foreach my $k (keys %{$metadata->{$collections->{$job->[8]}->[0]}}) {
	next unless exists $libMap->{$k};
	$metadata->{$collections->{$job->[8]}->[0]}->{$k} = &cleanse($metadata->{$collections->{$job->[8]}->[0]}->{$k});
	$entry .= ', "'.$libMap->{$k}.'": "'.$metadata->{$collections->{$job->[8]}->[0]}->{$k}.'"';
      }

      if (! exists $metadata->{$collections->{$job->[8]}->[0]}->{seq_meth}) {
	$mixs = 0;
      } else {
	$hasSM = 1;
      }
      
      if (exists $metadata->{$collections->{$job->[8]}->[0]}->{investigation_type}) {
	if ($metadata->{$collections->{$job->[8]}->[0]}->{investigation_type} eq 'metatranscriptome' && ! exists $metadata->{$collections->{$job->[8]}->[0]}->{mrna_percent}) {
	  $mixs = 0;
	} elsif ($metadata->{$collections->{$job->[8]}->[0]}->{investigation_type} eq 'mimarks-survey' && ! exists $metadata->{$collections->{$job->[8]}->[0]}->{target_gene}) {
	  $mixs = 0;
	}
      } else {
	$mixs = 0;
      }
      
    } else {
      $mixs = 0;
    }
    
  } else {
    $mixs = 0;
  }

  unless ($hasSM) {
    if (exists $jobattributes->{$job->[0]} && exists $jobattributes->{$job->[0]}->{sequencing_method_guess}) {
      $entry .= ', "job_info_seq_method": "'.$jobattributes->{$job->[0]}->{sequencing_method_guess}.'"';
    }
  }

  # sample
  if ($job->[9] && exists $collections->{$job->[9]}) {
    $collections->{$job->[9]}->[1] = &cleanse($collections->{$job->[9]}->[1]);
    $entry .= ', "sample_sample_name": "'.$collections->{$job->[9]}->[1].'", "sample_sample_id": "'.$collections->{$job->[9]}->[2].'"';

    if (exists $metadata->{$collections->{$job->[9]}->[0]}) {

      foreach my $k (keys %{$metadata->{$collections->{$job->[9]}->[0]}}) {
	next unless $sampMap->{$k};
	$entry .= ', "'.$sampMap->{$k}->[0].'": ';
	$metadata->{$collections->{$job->[9]}->[0]}->{$k} = &cleanse($metadata->{$collections->{$job->[9]}->[0]}->{$k});
	if ($sampMap->{$k}->[1]) {
	  $entry .= sprintf("%g", $metadata->{$collections->{$job->[9]}->[0]}->{$k});
	} else {
	  $entry .= '"'.$metadata->{$collections->{$job->[9]}->[0]}->{$k}.'"';
	}
      }
      
      foreach my $m (@$mixsList) {
	unless (exists $metadata->{$collections->{$job->[9]}->[0]}->{$m}) {
	  $mixs = 0;
	  last;
	}
      }
    } else {
      $mixs = 0;
    }
  } else {
    $mixs = 0;
  }

  $entry .= ', "job_info_mixs_compliant": '.($mixs ? "true" : "false");
  
  # close
  $entry .= ' }'.($count == $num ? "" : ",")."\n";

  if ($outfile ne "stream") {
    print FH $entry;
  } else {
    print $entry;
  }
  

  $count++;
}

if ($outfile ne "stream") {
  print FH "]\n";
  
  close FH;
} else {
  print "]\n";
}

sub cleanse {
  my ($val) = @_;

  $val =~ s/\\//g;
  $val =~ s/"/\\"/g;
  $val =~ s/\t/ /g;
  $val =~ s/\s\s+/ /g;

  return $val;
}
