package JobDB::JobInfo;

use strict;
use warnings;
use MGRAST::Metadata;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

sub populate_job {
  my ($self, $job) = @_;

  my $master    = $self->_master();
  my $coords    = $job->lat_lon;
  my $job_stats = $job->stats;
  my $attribs   = { job => $job };

  $attribs->{project_name}  = $job->primary_project->name if $job->primary_project;
  $attribs->{project_pi}    = $job->primary_project->pi if $job->primary_project;
  $attribs->{sequence_type} = $job->seq_type if $job->seq_type;
  $attribs->{sequence_tech} = $job->seq_method if $job->seq_method;
  $attribs->{latitude}      = $coords->[0] if @$coords;
  $attribs->{longitude}     = $coords->[1] if @$coords;
  $attribs->{country}       = $job->country if $job->country;
  $attribs->{location}      = $job->location if $job->location;
  $attribs->{biome}         = $job->biome if $job->biome;
  $attribs->{feature}       = $job->feature if $job->feature;
  $attribs->{material}      = $job->material if $job->material;
  $attribs->{env_package}   = $job->env_package_type if $job->env_package_type;
  $attribs->{bp_count}      = $job_stats->{bp_count_raw} if $job_stats->{bp_count_raw};
  $attribs->{seq_count}     = $job_stats->{sequence_count_raw} if $job_stats->{sequence_count_raw};
  $attribs->{avg_len}       = $job_stats->{average_length_raw} if $job_stats->{average_length_raw};
  $attribs->{drisee}        = $job_stats->{drisee_score_raw} if $job_stats->{drisee_score_raw};
  $attribs->{alpha_diverse} = $job_stats->{alpha_diversity_shannon} if $job_stats->{alpha_diversity_shannon};

  $master->JobInfo->create($attribs);
}
