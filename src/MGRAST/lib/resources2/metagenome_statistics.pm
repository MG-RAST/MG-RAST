package resources2::metagenome_statistics;

use strict;
use warnings;
no warnings('once');

use List::Util qw(first max min sum);
use POSIX qw(strftime floor);
use MGRAST::Analysis;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "metagenome_statistics";
    $self->{mgdb} = undef;
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
                    "kmer" => { "6_mer"  => {"columns" => ['list', 'names of columns'], "data" => ['list', 'kmer 6 counts']},
                                "15_mer" => {"columns" => ['list', 'names of columns'], "data" => ['list', 'kmer 15 counts']} },
                    "drisee" => { "counts"   => {"columns" => ['list', 'names of columns'], "data" => ['list', 'drisee count profile']},
                                  "percents" => {"columns" => ['list', 'names of columns'], "data" => ['list', 'drisee percent profile']},
                                  "summary"  => {"columns" => ['list', 'names of columns'], "data" => ['list', 'drisee summary stats']} },
                    "bp_profile" => { "counts"   => {"columns" => ['list', 'names of columns'], "data" => ['list', 'nucleotide count profile']},
                                      "percents" => {"columns" => ['list', 'names of columns'], "data" => ['list', 'nucleotide percent profile']} }
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
    			    "Subsystems" => [ 'list', 'Subsystem counts' ]
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
				      'parameters'  => { 'options'  => {},
							             'required' => {},
						                 'body'     => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a JSON structure of statistical information.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options' => { 'verbosity' => ['cv',
                                                               [['minimal','returns only sequence_stats attribute'],
                                                                ['verbose','returns all but qc attribute'],
                                                                ['full','returns all attributes']] ] },
							             'required' => { "id" => [ "string", "metagenome id" ] },
							             'body'     => {} } }
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

  my $jstats = $job->stats();
  if ((! $self->cgi->param('verbosity')) || ($self->cgi->param('verbosity') eq 'minimal')) {
      $jstats->{id} = $rest->[0];
      return $self->return_data($jstats);
  }

  # initialize analysis obj with mgid
  my $jid  = $job->job_id;
  my $mgdb = MGRAST::Analysis->new( $master->db_handle );
  unless (ref($mgdb)) {
      $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
  }
  $mgdb->set_jobs([$mgid]);
  $self->{mgdb} = $mgdb;

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
      sequence_stats => $jstats,
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
		  "Subsystems" => $mgdb->get_ontology_stats($jid, 'Subsystems')
      },
      source => $mgdb->get_source_stats($jid),
	  rarefaction => $mgdb->get_rarefaction_coords($jid)
  };
  
  if ($self->cgi->param('verbosity') eq 'full') {
      $object->{qc} = { "kmer" => { "6_mer" => $self->get_kmer($jid, '6'),
                                    "15_mer" => $self->get_kmer($jid, '15'), },
                        "drisee" => $self->get_drisee($jid, $jstats),
                        "bp_profile" => $self->get_nucleo($jid)
                      };
  }
  $self->return_data($object);
}

sub get_drisee {
    my ($self, $jid, $stats) = @_;
    
    my $bp_set = ['A', 'T', 'C', 'G', 'N', 'InDel'];
    my $drisee = $self->{mgdb}->get_qc_stats($jid, 'drisee');
    my $ccols  = ['Position'];
    map { push @$ccols, $_.' match consensus sequence' } @$bp_set;
    map { push @$ccols, $_.' not match consensus sequence' } @$bp_set;
    my $data = { summary  => { columns => [@$bp_set, 'Total'], data => undef },
                 counts   => { columns => $ccols, data => undef },
                 percents => { columns => ['Position', @$bp_set, 'Total'], data => undef }
               };
    unless ($drisee && (@$drisee > 2) && ($drisee->[1][0] eq '#')) {
        return $data;
    }
    for (my $i=0; $i<6; $i++) {
        $data->{summary}{data}[$i] = $drisee->[1][$i+1] * 1.0;
    }
    $data->{summary}{data}[6] = $stats->{drisee_score_raw} ? $stats->{drisee_score_raw} * 1.0 : undef;
    my $raw = [];
    my $per = [];
    foreach my $row (@$drisee) {
        next if ($row->[0] =~ /\#/);
	    @$row = map { int($_) } @$row;
	    push @$raw, $row;
	    if ($row->[0] > 50) {
	        my $x = shift @$row;
	        my $sum = sum @$row;
	        my @tmp = map { sprintf("%.2f", 100 * (($_ * 1.0) / $sum)) * 1.0 } @$row;
	        push @$per, [ $x, @tmp[6..11], sprintf("%.2f", sum(@tmp[6..11])) * 1.0 ];
	    }        
    }
    $data->{counts}{data} = $raw;
    $data->{percents}{data} = $per;
    return $data;
}

sub get_nucleo {
    my ($self, $jid) = @_;
    
    my $cols = ['Position', 'A', 'T', 'C', 'G', 'N', 'Total'];
    my $nuc  = $self->{mgdb}->get_qc_stats($jid, 'consensus');
    my $data = { counts   => { columns => $cols, data => undef },
                 percents => { columns => [@$cols[0..5]], data => undef }
               };
    unless ($nuc && (@$nuc > 2)) {
        return $data;
    }
    my $raw = [];
    my $per = [];
    foreach my $row (@$nuc) {
        next if (($row->[0] eq '#') || (! $row->[6]));
        @$row = map { int($_) } @$row;
        push @$raw, [ $row->[0] + 1, $row->[1], $row->[4], $row->[2], $row->[3], $row->[5], $row->[6] ];
        unless (($row->[0] > 100) && ($row->[6] < 1000)) {
    	    my $sum = $row->[6];
    	    my @tmp = map { floor(100 * 100 * (($_ * 1.0) / $sum)) / 100 } @$row;
    	    push @$per, [ $row->[0] + 1, $tmp[1], $tmp[4], $tmp[2], $tmp[3], $tmp[5] ];
        }
    }
    $data->{counts}{data} = $raw;
    $data->{percents}{data} = $per;
    return $data;
}

sub get_kmer {
    my ($self, $jid, $num) = @_;
    
    my $cols = [ 'count of identical kmers of size N',
    			 'number of times count occures',
    	         'product of column 1 and 2',
    	         'reverse sum of column 2',
    	         'reverse sum of column 3',
    		     'ratio of column 5 to total sum column 3 (not reverse)'
               ];
    my $kmer = $self->{mgdb}->get_qc_stats($jid, 'kmer.'.$num);
    my $data = { columns => $cols, data => undef };
    unless ($kmer && (@$kmer > 1)) {
        return $data;
    }
    foreach my $row (@$kmer) {
        @$row = map { $_ * 1.0 } @$row;
    }
    $data->{data} = $kmer;
    return $data;
}

1;
