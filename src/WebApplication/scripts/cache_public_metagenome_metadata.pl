#!/usr/bin/env perl
use strict;
use warnings;

use MGRAST::Metadata;
use Conf;
use DBMaster;

# get the data connections
my $mgrast = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobCacheMGRast',
			    -host     => $Conf::mgrast_jobcache_host,
			    -user     => $Conf::mgrast_jobcache_user,
			    -password => $Conf::mgrast_jobcache_password );

my $metadata = MGRAST::Metadata->new()->{_handle};

# extract the initial data
my $public_projects = $mgrast->Project->get_objects( { public => 1 } );
my $jobs = [];
foreach my $project (@$public_projects) {
  my $pjobs = $mgrast->ProjectJob->get_objects( { project => $project } );
  foreach my $pj (@$pjobs) {
    push(@$jobs, $pj->job);
    $jobs->[scalar(@$jobs) - 1]->{pname} = $project->{name};
    $jobs->[scalar(@$jobs) - 1]->{project} = $project;
  }
}
my $md_list = { 'biome-information_envo_lite' => 4,
		'sample-origin_altitude' => 5,
		'sample-origin_depth' => 6,
		'sample-origin_location' => 7,
		'sample-origin_ph' => 8,
		'sample-origin_country' => 9,
		'sample-origin_temperature' => 10,
		'sequencing_sequencing_method' => 11,
		'PI_lastname' => 12 };
my $data = [];
foreach my $job (@$jobs) {
  $job->{genome_name} =~ s/'//g;
  $job->{pname} =~ s/'//g;
  my $row = [ [ $job->{_id} ], [ $job->{genome_name} ], [ $job->{genome_id} ], [ $job->{pname} ], [ ], [ ], [ ], [ ], [ ], [ ], [ ], [ ], [ ] ];
  my $md = $metadata->MetaDataEntry->get_objects( { job => $job } );
  push(@$md, @{$metadata->ProjectMD->get_objects( { project => $job->{project} } )});
  foreach my $m (@$md) {
    if ($m->{value} ne "") {
      if ($md_list->{$m->{tag}}) {
	if (! defined($row->[$md_list->{$m->{tag}}])) {
	  $row->[$md_list->{$m->{tag}}] = [];
	}
	push(@{$row->[$md_list->{$m->{tag}}]}, $m->{value});
      }
    }
  }
  push(@$data, $row);
}

my $string_data = "";
my $rows = [];
foreach my $row (@$data) {
  push(@$rows, join('||', map { join("\*\*", @$_) } @$row));
}
$string_data = join('##', @$rows);

$self->{data} = $string_data;

if (open(FH, ">".$Conf::temp."/mgs_temp_data")) {
  print FH $string_data;
  close FH;
}
