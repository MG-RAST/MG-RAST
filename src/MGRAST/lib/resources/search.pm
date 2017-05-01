package resources::search;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

use URI::Escape qw(uri_escape uri_unescape);

# Override parent constructor
sub new {
  my ($class, @args) = @_;
  
  # Call the constructor of the parent class
  my $self = $class->SUPER::new(@args);
  
  # Add name / attributes
  $self->{name} = "search";
  $self->{attributes} = {};
  
  $self->{fields} = { "all" => "all",
		      "metagenome_id" => "id",
		      "public" => "job_info_public",
		      "job_id" => "job_info_job_id",
		      "pipeline_version" => "job_info_pipeline_version",
		      "sequence_type" => "job_info_sequence_type",
		      "version" => "job_info_version",
		      "name" => "job_info_name.keyword",
		      "seq_method" => "job_info_seq_method",
		      "created" => "job_info_created",
		      "mixs_compliant" => "job_info_mixs_compliant",
		      "pi_firstname" => "project_PI_firstname.keyword",
		      "pi_lastname" => "project_PI_lastname.keyword",
		      "pi_organization" => "project_PI_organization.keyword",
		      "pi_organization_country" => "project_PI_organization_country",
		      "firstname" => "project_firstname.keyword",
		      "lastname" => "project_lastname.keyword",
		      "organization_country" => "project_organization_country",
		      "project_name" => "project_project_name.keyword",
		      "project_funding" => "project_project_funding.keyword",
		      "project_id" => "project_project_id",
		      "gold_id" => "library_gold_id",
		      "ncbi_id" => "project_ncbi_id",
		      "pubmed_id" => "library_pubmed_id",
		      "project" => "project_all",
		      "library_id" => "library_library_id",
		      "library_name" => "library_library_name.keyword",
		      "library" => "library_all",
		      "sample_id" => "sample_sample_id",
		      "collection_date" => "sample_collection_date",
		      "feature" => "sample_feature.keyword",
		      "latitude" => "sample_latitude",
		      "longitude" => "sample_longitude",
		      "altitude" => "sample_altitude",
		      "depth" => "sample_depth",
		      "elevation" => "sample_elevation",
		      "continent" => "sample_continent",
		      "biome" => "sample_biome",
		      "temperature" => "sample_temperature",
		      "sample_name" => "sample_sample_name.keyword",
		      "country" => "sample_country",
		      "env_package_type" => "sample_env_package_type",
		      "env_package_name" => "sample_env_package_name",
		      "env_package_id" => "sample_env_package_id",
		      "env_package" => "sample_env_package_all",
		      "location" => "sample_location.keyword",
		      "material" => "sample_material.keyword",
		      "sample" => "sample_sample_all",
		      "aa_pid" => "pipeline_parameters_aa_pid",
		      "assembled" => "pipeline_parameters_assembled",
		      "bowtie" => "pipeline_parameters_bowtie",
		      "dereplicate" => "pipeline_parameters_dereplicate",
		      "fgs_type" => "pipeline_parameters_fgs_type.keyword",
		      "file_type" => "pipeline_parameters_file_type",
		      "filter_ambig" => "pipeline_parameters_filter_ambig",
		      "filter_ln" => "pipeline_parameters_filter_ln",
		      "filter_ln_mult" => "pipeline_parameters_filter_ln_mult",
		      "m5nr_annotation_version" => "pipeline_parameters_m5nr_annotation_version",
		      "m5nr_sims_version" => "pipeline_parameters_m5nr_sims_version",
		      "m5rna_annotation_version" => "pipeline_parameters_m5rna_annotation_version",
		      "m5rna_sims_version" => "pipeline_parameters_m5rna_sims_version",
		      "max_ambig" => "pipeline_parameters_max_ambig",
		      "prefix_length" => "pipeline_parameters_prefix_length",
		      "priority" => "pipeline_parameters_priority",
		      "rna_pid" => "pipeline_parameters_rna_pid",
		      "screen_indexes" => "pipeline_parameters_screen_indexes" };
  
  return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "Elastic search for Metagenomes.",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $self->cgi->url."/".$self->name,				      
				      'description' => "Elastic search",
				      'example'     => [ $self->cgi->url."/".$self->name."?material=saline water",
							 'return the first ten datasets that have saline water as the sample material' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes ,
				      'parameters'  => { 'options'     => {},
							 'required'    => {},
							 'body'        => {} } }
				     ]
				 };

    $self->return_data($content);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  my ($self) = @_;

  $self->json->utf8();

  # get paramaters
  my $limit  = $self->cgi->param('limit') || 10;
  my $offset = $self->cgi->param('offset') || 0;
  my $order  = $self->cgi->param('order') || "metagenome_id";
  my $dir    = $self->cgi->param('direction') || 'asc';
    
  # check CV
  if (($limit > 1000) || ($limit < 1)) {
    $self->return_data({"ERROR" => "Limit must be less than 1,000 and greater than 0 ($limit) for query."}, 404);
  }
  
  # explicitly setting the default CGI parameters for returned url strings
  $self->cgi->param('limit', $limit);
  $self->cgi->param('offset', $offset);
  $self->cgi->param('order', $order);
  $self->cgi->param('direction', $dir);

  # get query fields
  my $query = [];
  foreach my $field (keys %{$self->{fields}}) {
    if ($self->cgi->param($field)) {
      my @param = $self->cgi->param($field);
      my $entries = [];
      foreach my $p (@param) {
	if ($field eq "all") {
	  push(@$entries, $p);
	} else {
	  push(@$entries, $self->{fields}->{$field}.':'.$p);
	}
      }
      push(@$query, $entries);
    }
  }
  # $Conf::metagenome_elastic
  my $in = undef;
  if ($self->user) {
    if (! $self->user->has_star_right('view', 'metagenome')) {
      @$in = map { "mgm".$_ } @{$self->user->has_right_to(undef, 'view', 'metagenome')};
    }
  } else {
    push(@$query, [ "job_info_public:1" ]);
  }
  my ($data, $error) = $self->get_elastic_query("http://bio-worker10.mcs.anl.gov:9200/metagenome_index/metagenome", $query, $self->{fields}->{$order}, $dir, $offset, $limit, $in ? [ "id", $in ] : undef);
  
  if ($error) {
    $self->return_data({"ERROR" => "An error occurred: $error"}, 500);
  } else {
    $self->return_data($self->prepare_data($data, $limit), 200);
  }
  
  exit 0;
}

sub prepare_data {
  my ($self, $data, $limit) = @_;

  my $d = $data->{hits}->{hits} || [];
  my $total = $data->{hits}->{total} || 0;
  
  my $obj = $self->check_pagination($d, $total, $limit);
  $obj->{version} = 1;
  $obj->{data} = [];

  my %rev = ();
  foreach my $key (keys(%{$self->{fields}})) {
    my $val = $self->{fields}->{$key};
    $val =~ s/\.keyword$//;
    $rev{$val} = $key;
  }
  foreach my $set (@$d) {
    my $entry = {};
    foreach my $k (keys(%{$set->{_source}})) {
      $entry->{$rev{$k}} = $set->{_source}->{$k};
    }
    push(@{$obj->{data}}, $entry);
  }
  
  return $obj;
}

1;
