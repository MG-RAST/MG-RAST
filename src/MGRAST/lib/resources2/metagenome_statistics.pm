package resources2::metagenome_statistics;

use strict;
use warnings;
no warnings('once');

use MGRAST::Analysis;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}       = "metagenome_statistics";
    $self->{attributes} = { 
                "id" => [ 'string', 'unique metagenome id' ],
                "length_histogram" => {
                    "upload"  => [ 'list', 'length distribution of uploaded sequences' ],
                    "post_qc" => [ 'list', 'length distribution of post-qc sequences' ]
                },
                "gc_histogram" => {
                    "upload"   => [ 'list', 'gc % distribution of uploaded sequences' ],
                    "post_qc"  => [ 'list', 'gc % distribution of post-qc sequences' ]
                },
                "qc" => {
                    "drisee"     => [ 'list', 'drisee profile' ],
                    "kmer_6"     => [ 'list', 'kmer 6 counts' ],
                    "kmer_15"    => [ 'list', 'kmer 15 counts' ],
                    "nucleotide" => [ 'list', 'nucleotide profile information' ]
                },
                "sequence_stats" => [ 'hash', 'statistics on sequence files of all pipeline stages' ],
                "taxonomy" => {
                    "species" => [ 'list', 'species counts' ],
                    "genus"   => [ 'list', 'genus counts' ],
                    "family"  => [ 'list', 'family counts' ],
                    "order"   => [ 'list', 'order counts' ],
                    "class"   => [ 'list', 'class counts' ],
                    "phylum"  => [ 'list', 'phylum counts' ],
                    "domain"  => [ 'list', 'domain counts' ]
                },
                "ontology" => {
                    "COG"       => [ 'list', 'COG counts' ],
    			    "KO"        => [ 'list', 'KO counts' ],
    			    "NOG"       => [ 'list', 'NOG counts' ],
    			    "Subsystem" => [ 'list', 'Subsystem counts' ]
                },
                "source" => [ 'hash', 'evalue and % identity counts per source' ],
			    "rarefaction" => [ 'list', 'rarefaction coordinate data' ]
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
  my $job = $master->Job->get_objects( {metagenome_id => $mgid} );
  unless ($job && @$job) {
    $self->return_data( {"ERROR" => "id $mgid does not exist"}, 404 );
  }
  $job = $job->[0];
  
  # check rights
  unless ($job->public || $self->user->has_right(undef, 'view', 'metagenome', $job->metagenome_id) || $self->user->has_star_right('view', 'metagenome')) {
    $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
  }
  
  # initialize analysis obj with mgid
  my $jid  = $job->job_id;
  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
      $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
  }
  $mgdb->set_jobs([$mgid]);  

  my $object = {
      id => $rest->[0],
      length_histogram => {
          "upload"  => $mgdb->get_histogram_nums($jid, 'len', 'raw'),
          "post_qc" => $mgdb->get_histogram_nums($jid, 'len', 'qc')
      },
      gc_histogram => {
          "upload"  => $mgdb->get_histogram_nums($jid, 'gc', 'raw'),
          "post_qc" => $mgdb->get_histogram_nums($jid, 'gc', 'qc')
      },
      qc => {
          "drisee"     => $mgdb->get_qc_stats($jid, 'drisee'),
          "kmer_6"     => $mgdb->get_qc_stats($jid, 'kmer.6'),
          "kmer_15"    => $mgdb->get_qc_stats($jid, 'kmer.15'),
          "nucleotide" => $mgdb->get_qc_stats($jid, 'consensus')
      },
      sequence_stats => $job->stats(),
      taxonomy => {
          "species" => $mgdb->get_taxa_stats($jid, 'species'),
          "genus"   => $mgdb->get_taxa_stats($jid, 'genus'),
          "family"  => $mgdb->get_taxa_stats($jid, 'family'),
          "order"   => $mgdb->get_taxa_stats($jid, 'order'),
          "class"   => $mgdb->get_taxa_stats($jid, 'class'),
          "phylum"  => $mgdb->get_taxa_stats($jid, 'phylum'),
          "domain"  => $mgdb->get_taxa_stats($jid, 'domain')
      },
      ontology => {
          "COG"       => $mgdb->get_ontology_stats($jid, 'COG'),
		  "KO"        => $mgdb->get_ontology_stats($jid, 'KO'),
		  "NOG"       => $mgdb->get_ontology_stats($jid, 'NOG'),
		  "Subsystem" => $mgdb->get_ontology_stats($jid, 'Subsystem')
      },
      source => $mgdb->get_source_stats($jid),
	  rarefaction => $mgdb->get_rarefaction_coords($jid)
  };

  $self->return_data($object);
}

1;
