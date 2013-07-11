package resources::metagenome;

use strict;
use warnings;
no warnings('once');

use List::Util qw(first max min sum);
use POSIX qw(strftime floor);
use MGRAST::Analysis;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map { $_, 1 } @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "metagenome";
    $self->{mgdb} = undef;
    $self->{rights} = \%rights;
    $self->{verbosity} = { 'instance' => {'minimal' => 1, 'metadata' => 1, 'stats' => 1, 'full' => 1},
                           'query'    => {'minimal' => 1, 'mixs' => 1}
    };
    $self->{instance} = { "id"       => [ 'string', 'unique object identifier' ],
                          "name"     => [ 'string', 'human readable identifier' ],
                          "library"  => [ 'reference library', 'reference to the related library object' ],
                          "sample"   => [ 'reference sample', 'reference to the related sample object' ],
                          "project"  => [ 'reference project', 'reference to the project object' ],
                          "metadata" => [ 'hash', 'key value pairs describing all metadata' ],
                          "mixs"     => [ 'hash', 'key value pairs describing MIxS metadata' ],
                          "created"  => [ 'date', 'time the object was first created' ],
                          "version"  => [ 'integer', 'version of the object' ],
                          "url"      => [ 'uri', 'resource location of this object instance' ],
                          "status"   => [ 'cv', [ ['public', 'object is public'],
						                          ['private', 'object is private'] ] ],
						  "statistics" => [ 'hash', 'key value pairs describing statistics' ],
                          "sequence_type" => [ 'string', 'sequencing type' ]
    };
    $self->{query} = { "id"        => [ 'string', 'unique object identifier' ],
                       "name"      => [ 'string', 'human readable identifier' ],
                       "project"   => [ 'string', 'name of project' ],
                       "package"   => [ 'string', 'enviromental package of sample' ],
                       "biome"     => [ 'string', 'biome of sample' ],
                       "feature"   => [ 'string', 'feature of sample' ],
                       "material"  => [ 'string', 'material of sample' ],
                       "country"   => [ 'string', 'country where sample taken' ],
                       "location"  => [ 'string', 'location where sample taken' ],
                       "longitude" => [ 'string', 'longitude where sample taken' ],
                       "latitude"  => [ 'string', 'latitude where sample taken' ],
                       "created"   => [ 'date', 'time the object was first created' ],
                       "url"       => [ 'uri', 'resource location of this object instance' ],
                       "status"    => [ 'cv', [ ['public', 'object is public'],
						                       ['private', 'object is private'] ] ],
                       "sequence_type" => [ 'string', 'sequencing type' ],
                       "seq_method"    => [ 'string', 'sequencing method' ],
                       "collection_date" => [ 'string', 'date sample collected' ]
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "A metagenome is an analyzed set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
                    'requests'      => [{ 'name'        => "info",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns description of parameters and attributes.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => "self",
                                          'parameters'  => { 'options'  => {},
                                                             'required' => {},
                                                             'body'     => {} }
                                        },
                                        { 'name'        => "query",
                                          'request'     => $self->cgi->url."/".$self->name,
                                          'description' => "Returns a set of data matching the query criteria.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => { "next"   => ["uri","link to the previous set or null if this is the first set"],
                                                             "prev"   => ["uri","link to the next set or null if this is the last set"],
                                                             "order"  => ["string","name of the attribute the returned data is ordered by"],
                                                             "data"   => ["list", ["object", [$self->{query}, "list of the metagenome objects"] ]],
                                                             "limit"  => ["integer","maximum number of data items returned, default is 10"],
                                                             "offset" => ["integer","zero based index of the first returned data item"],
                                                             "total_count" => ["integer","total number of available data items"] },
                                          'parameters' => { 'options' => {
                                                                'verbosity' => ['cv',
                                                                                [['minimal','returns only minimal information'],
                                                                                 ['mixs','returns all GSC MIxS metadata']] ],
                                                                'status' => ['cv',
                                                                             [['both','returns all data (public and private) user has access to view'],
                                                                              ['public','returns all public data'],
                                                                              ['private','returns private data user has access to view']] ],
                                                                'limit'  => ['integer','maximum number of items requested'],
                                                                'offset' => ['integer','zero based index of the first data object to be returned'],
                                                                'order'  => ['string', 'attribute name to order results by']
                                                                         },
                                                            'required' => {},
                                                            'body'     => {} }
                                        },
                                        { 'name'        => "instance",
                                          'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                          'description' => "Returns a single data object.",
                                          'method'      => "GET",
                                          'type'        => "synchronous",
                                          'attributes'  => $self->{instance},
                                          'parameters'  => { 'options' => {
                                                                 'verbosity' => ['cv',
                                                                                 [['minimal','returns only minimal information'],
                                                                                  ['metadata','returns minimal with metadata'],
                                                                                  ['stats','returns minimal with statistics'],
                                                                                  ['full','returns all metadata and statistics']] ]
                                                                          },
                                                             'required' => { "id" => ["string","unique object identifier"] },
                                                             'body'     => {} }
                                        }] };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check verbosity
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    unless (exists $self->{verbosity}{instance}{$verb}) {
        $self->return_data({"ERROR" => "Invalid verbosity entered ($verb) for instance."}, 404);
    }
    
    # check id format
    my $rest = $self->rest;
    my (undef, $id) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();

    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id, viewable => 1} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $id does not exist"}, 404 );
    }
    $job = $job->[0];

    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || exists($self->rights->{'*'})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # return cached if exists
    $self->return_cached();
    
    # prepare data
    my $data = $self->prepare_data([$job], 1);
    $data = $data->[0];
    $self->return_data($data, undef, 1); # cache this!
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # check verbosity
    my $verb = $self->cgi->param('verbosity') || 'minimal';
    unless (exists $self->{verbosity}{query}{$verb}) {
        $self->return_data({"ERROR" => "Invalid verbosity entered ($verb) for query."}, 404);
    }

    # get database
    my $master = $self->connect_to_datasource();
    
    # check pagination
    my $limit  = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    if ($order eq 'id') {
        $order = 'metagenome_id';
    }

    if ($limit == 0) {
        $limit = 18446744073709551615;
    }
    
    # get all items the user has access to
    my $status = $self->cgi->param('status') || "both";
    my $total = 0;
    my $query = "";
    my $job_pub = $master->Job->count_public();
    if (($status eq 'public') || (! $self->user)) {
        $total = $job_pub;
        $query = "viewable=1 AND public=1 ORDER BY $order LIMIT $limit OFFSET $offset";
    } elsif (exists $self->rights->{'*'}) {
        my $job_all = $master->Job->count_all();
        if ($status eq 'private') {
            $total = $job_all - $job_pub;
            $query = "viewable=1 AND (public IS NULL OR public=0) ORDER BY $order LIMIT $limit OFFSET $offset";
        } else {
            $total = $job_all;
            $query = "viewable=1 ORDER BY $order LIMIT $limit OFFSET $offset";
        }
    } else {
        my $private = $master->Job->get_private_jobs($self->user, 1);
        if ($status eq 'private') {
            $total = scalar(@$private);
	    if (@$private > 0) {
		$query = "viewable=1 AND metagenome_id IN (".join(',', @$private).") ORDER BY $order LIMIT $limit OFFSET $offset";
	    } else {
		$self->return_data($self->check_pagination([], $total, $limit));
	    }
        } else {
            $total = scalar(@$private) + $job_pub;
	    if (@$private > 0) {
		$query = "viewable=1 AND (public=1 OR metagenome_id IN (".join(',', @$private).")) ORDER BY $order LIMIT $limit OFFSET $offset";
	    } else {
		$query = "viewable=1 AND public=1 ORDER BY $order LIMIT $limit OFFSET $offset";
	    }
        }
    }
    my $jobs  = $master->Job->get_objects( {$order => [undef, $query]} );
    $limit = ($limit > scalar(@$jobs)) ? scalar(@$jobs) : $limit;
    
    # prepare data to the correct output format
    my $data = $self->prepare_data($jobs, 0);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);

    # return cached if exists
    $self->return_cached();

    $self->return_data($data, undef, 1);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data, $instance) = @_;

    my $verb = $self->cgi->param('verbosity') || 'minimal';
    my $mgids = [];
    @$mgids = map { $_->{metagenome_id} } @$data;
    my $jobdata = {};
    
    if (($verb eq 'metadata') || ($verb eq 'full')) {
        use MGRAST::Metadata;
        my $mddb = MGRAST::Metadata->new();
        $jobdata = $mddb->get_jobs_metadata_fast($mgids, 1);
    }
    if (($verb eq 'stats') || ($verb eq 'full')) {
        # initialize analysis obj with mgids
        my $master = $self->connect_to_datasource();
        my $mgdb = MGRAST::Analysis->new( $master->db_handle );
        unless (ref($mgdb)) {
            $self->return_data({"ERROR" => "could not connect to analysis database"}, 500);
        }
        $mgdb->set_jobs($mgids);
        $self->{mgdb} = $mgdb;
    }

    my $objects = [];
    foreach my $job (@$data) {
        my $url = $self->cgi->url;
        my $obj = {};
        $obj->{id}      = "mgm".$job->{metagenome_id};
        $obj->{name}    = $job->{name};
        $obj->{status}  = $job->{public} ? 'public' : 'private';
        $obj->{created} = $job->{created_on};
        
        if ($instance && ($verb ne 'mixs')) {
            $obj->{project} = undef;
            $obj->{sample}  = undef;
            $obj->{library} = undef;
	        eval {
	            my $proj = $job->primary_project;
	            $obj->{project} = ["mgp".$proj->{id}, $url."/project/mgp".$proj->{id}];
	        };
	        eval {
	            my $samp = $job->sample;
	            $obj->{sample} = ["mgs".$samp->{ID}, $url."/sample/mgs".$samp->{ID}];
	        };
	        eval {
	            my $lib = $job->library;
	            $obj->{library} = ["mgl".$lib->{ID}, $url."/library/mgl".$lib->{ID}];
	        };
            $obj->{sequence_type} = $job->{sequence_type};
            $obj->{version} = 1;
            $obj->{url} = $url.'/metagenome/'.$obj->{id}.'?verbosity='.$verb;
        }
        if (($verb eq 'mixs') || ($verb eq 'full')) {
            my $mixs = {};
		    $mixs->{project} = '-';
		    eval {
		        $mixs->{project} = $job->primary_project->{name};
		    };
	        my $lat_lon  = $job->lat_lon;
	        my $country  = $job->country;
	        my $location = $job->location;
	        my $col_date = $job->collection_date;
	        my $biome    = $job->biome;
	        my $feature  = $job->feature;
	        my $material = $job->material;
	        my $package  = $job->env_package_type;
	        my $seq_type = $job->seq_type;
	        my $seq_method = $job->seq_method;
	        $mixs->{latitude} = (@$lat_lon > 1) ? $lat_lon->[0] : "-";
	        $mixs->{longitude} = (@$lat_lon > 1) ? $lat_lon->[1] : "-";
	        $mixs->{country} = $country ? $country : "-";
	        $mixs->{location} = $location ? $location : "-";
	        $mixs->{collection_date} = $col_date ? $col_date : "-";
	        $mixs->{biome} = $biome ? $biome : "-";
	        $mixs->{feature} =  $feature ? $feature : "-";
	        $mixs->{material} = $material ? $material : "-";
	        $mixs->{package} = $package ? $package : "-";
	        $mixs->{seq_method} = $seq_method ? $seq_method : "-";
	        $mixs->{sequence_type} = $seq_type ? $seq_type : "-";
	        if ($verb eq 'full') {
	            $obj->{mixs} = $mixs;
	        } else {
	            @$obj{ keys %$mixs } = values %$mixs;
	        }
        }
        if (($verb eq 'metadata') || ($verb eq 'full')) {
            $obj->{metadata} = $jobdata->{$job->{metagenome_id}};
        }
        if (($verb eq 'stats') || ($verb eq 'full')) {
            $obj->{statistics} = $self->job_stats($job);
        }
        push @$objects, $obj;
    }
    return $objects;
}

sub job_stats {
    my ($self, $job) = @_;
    
    my $jid = $job->job_id;
    my $jstat = $job->stats();
    my $stats = {
        length_histogram => {
            "upload"  => $self->{mgdb}->get_histogram_nums($jid, 'len', 'raw'),
            "post_qc" => $self->{mgdb}->get_histogram_nums($jid, 'len', 'qc')
        },
        gc_histogram => {
            "upload"  => $self->{mgdb}->get_histogram_nums($jid, 'gc', 'raw'),
            "post_qc" => $self->{mgdb}->get_histogram_nums($jid, 'gc', 'qc')
        },
        taxonomy => {
            "species" => $self->{mgdb}->get_taxa_stats($jid, 'species'),
            "genus"   => $self->{mgdb}->get_taxa_stats($jid, 'genus'),
            "family"  => $self->{mgdb}->get_taxa_stats($jid, 'family'),
            "order"   => $self->{mgdb}->get_taxa_stats($jid, 'order'),
            "class"   => $self->{mgdb}->get_taxa_stats($jid, 'class'),
            "phylum"  => $self->{mgdb}->get_taxa_stats($jid, 'phylum'),
            "domain"  => $self->{mgdb}->get_taxa_stats($jid, 'domain')
        },
        ontology => {
            "COG" => $self->{mgdb}->get_ontology_stats($jid, 'COG'),
            "KO"  => $self->{mgdb}->get_ontology_stats($jid, 'KO'),
            "NOG" => $self->{mgdb}->get_ontology_stats($jid, 'NOG'),
            "Subsystems" => $self->{mgdb}->get_ontology_stats($jid, 'Subsystems')
        },
        source => $self->{mgdb}->get_source_stats($jid),
        rarefaction => $self->{mgdb}->get_rarefaction_coords($jid),
        sequence_stats => $jstat,
        qc => { "kmer" => {"6_mer" => $self->get_kmer($jid,'6'), "15_mer" => $self->get_kmer($jid,'15')},
                "drisee" => $self->get_drisee($jid, $jstat),
                "bp_profile" => $self->get_nucleo($jid)
        }
    };
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
	        if ($sum == 0) {
	            push @$per, [ $x, 0, 0, 0, 0, 0, 0, 0 ];
	        } else {
	            my @tmp = map { sprintf("%.2f", 100 * (($_ * 1.0) / $sum)) * 1.0 } @$row;
	            push @$per, [ $x, @tmp[6..11], sprintf("%.2f", sum(@tmp[6..11])) * 1.0 ];
            }
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
    	    if ($sum == 0) {
	            push @$per, [ $row->[0] + 1, 0, 0, 0, 0, 0 ];
	        } else {
    	        my @tmp = map { floor(100 * 100 * (($_ * 1.0) / $sum)) / 100 } @$row;
    	        push @$per, [ $row->[0] + 1, $tmp[1], $tmp[4], $tmp[2], $tmp[3], $tmp[5] ];
	        }
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
