package resources2::metagenome_statistics;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}       = "metagenome_statistics";
    $self->{attributes} = { "id" => [ 'string', 'unique metagenome id' ],
			    "basic" => [ 'hash', 'basic sequence information about the uploaded data' ],
			    "consensus" => [ 'hash', 'consensus information' ],
			    "drisee_info" => [ 'hash', 'basic drisee information' ],
			    "drisee_stats" => [ 'hash', 'drisee statistics' ],
			    "kmer_15" => [ 'hash', 'kmer 15 counts' ],
			    "kmer_6" => [ 'hash', 'kmer 6 counts' ],
			    "preprocess_passed" => [ 'hash', 'basic sequence information about the data that passed preprocessing' ],
			    "preprocess_removed" => [ 'hash', 'basic sequence information about the data that was removed during preprocessing' ],
			    "dereplication_passed" => [ 'hash', 'basic sequence information about the data that passed dereplication' ],
			    "dereplication_removed" => [ 'hash', 'basic sequence information about the data that was removed during preprocessing' ],
			    "species" => [ 'hash', 'species counts' ],
			    "sims" => [ 'hash', 'sims counts' ],
			    "rarefaction" => [ 'hash', 'rarefaction data' ],
			    "COG" => [ 'hash', 'COG counts' ],
			    "KO" => [ 'hash', 'KO counts' ],
			    "NOG" => [ 'hash', 'NOG counts' ],
			    "Subsystem" => [ 'hash', 'Subsystem counts' ],
			    "class" => [ 'hash', 'class counts' ],
			    "domain" => [ 'hash', 'domain counts' ],
			    "family" => [ 'hash', 'family counts' ],
			    "order" => [ 'hash', 'order counts' ],
			    "genus" => [ 'hash', 'genus counts' ],
			    "phylum" => [ 'hash', 'phylum counts' ]
			  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "An set of statistical information obtained during the analysis of a metagenomic sequence",
		    'type' => 'object',
		    'documentation' => $Conf::cgi_url.'/Html/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a JSON structure of statistical information.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "metagenome id" ] },
							 'body'        => {} } }
				  ]
		  };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
  my ($self) = @_;
  
  # check id format
  my $rest = $self->rest;
  my ($pref, $mgid) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
  if (! $mgid) {
    $self->return_data({"ERROR" => "invalid id format: ".$rest->[0] }, 400);
  }
  
  # get database
  my $master = $self->connect_to_datasource();
  
  # get data
  my $job = $master->Job->init( { metagenome_id => $mgid } );
  unless ($job && ref($job)) {
    $self->return_data( {"ERROR" => "id $mgid does not exists"}, 404 );
  }
  
  # check rights
  unless ($job->{public} || $self->user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id})) {
    $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
  }
  
  my $structure = { consensus => "075.consensus.stats",
		    drisee_info => "075.drisee.info",
		    drisee_stats => "075.drisee.stats",
		    kmer_15 => "075.kmer.15.stats",
		    kmer_6 => "075.kmer.6.stats",
		    preprocessed_passed => "100.preprocess.passed.fna.stats",
		    preprocessed_removed => "100.preprocess.removed.fna.stats",
		    dereplication_passed => "150.dereplication.passed.fna.stats",
		    dereplication_removed => "150.dereplication.removed.fna.stats",
		    species => "999.done.species.stats",
		    sims => "999.done.sims.stats",
		    rarefaction => "999.done.rarefaction.stats",
		    COG => "999.done.COG.stats",
		    KO => "999.done.KO.stats",
		    NOG => "999.done.NOG.stats",
		    Subsystems => "999.done.Subsystems.stats",
		    class => "999.done.class.stats",
		    domain => "999.done.domain.stats",
		    family => "999.done.family.stats",
		    order => "999.done.order.stats",
		    genus => "999.done.genus.stats",
		    phylum => "999.done.phylum.stats" };

  my $data = { id => $rest->[0] };
  foreach my $key (keys(%$structure)) {
    $data->{$key} = [];
    if (-f $job->analysis_dir."/".$structure->{$key} && open(FH, "<".$job->analysis_dir."/".$structure->{$key})) {
      while (<FH>) {
	chomp;
	my ($k, $v) = split /\t/;
	if ($k && $v) {
	  push(@{$data->{$key}}, [$k, $v]);
	}
      }
      close FH;
    }
  }

  if (opendir(my $dh, $job->download_dir)) {
    my @statfiles = grep { -f $job->download_dir."/$_" && $_ =~ /\.stats$/ } readdir($dh);
    closedir $dh;
    if (scalar(@statfiles) && -f $job->download_dir."/".$statfiles[0] && open(FH, "<".$job->download_dir."/".$statfiles[0])) {
      $data->{basic} = [];
      while (<FH>) {
	chomp;
	my ($k, $v) = split /\t/;
	if ($k && $v) {
	  push(@{$data->{basic}}, [$k, $v]);
	}
      }
      close FH;
    }
  }

  $self->return_data($data);
}

1;
