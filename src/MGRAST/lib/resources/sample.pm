package resources::sample;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->{user} ? map {$_, 1} @{$self->{user}->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "sample";
    $self->{rights} = \%rights;
    $self->{attributes} = { "id"          => [ 'string', 'unique object identifier' ],
    	                    "name"        => [ 'string', 'human readable identifier' ],
    	                    "libraries"   => [ 'list', [ 'reference library', 'a list of references to the related library objects' ] ],
                        	"metagenomes" => [ 'list', [ 'reference metagenome', 'a list of references to the related metagenome objects' ] ],
    	                    "project"     => [ 'reference project', 'reference to the project of this sample' ],
    	                    "env_package" => [ 'object', [ { "created" => [ "date", "creation date" ],
                        						             "name" => [ "string", "name of the package" ],
                        						             "metadata" => [ "hash", "key value pairs describing metadata" ],
                        						             "type" => [ "string", "package type" ],
                        						             "id" => [ "string", "unique package identifier" ] },"environmental package object" ] ],
    	                    "metadata"    => [ 'hash', 'key value pairs describing metadata' ],
    	                    "created"     => [ 'date', 'time the object was first created' ],
    	                    "version"     => [ 'integer', 'version of the object' ],
    	                    "url"         => [ 'uri', 'resource location of this object instance' ]
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "A metagenomic sample from some environment.",
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
				      'description' => "Returns a set of data matching the query criteria.",
				      'example'     => [ $self->cgi->url."/".$self->name."?limit=20&order=name",
  				                         'retrieve the first 20 samples ordered by name' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "next"   => [ "uri", "link to the previous set or null if this is the first set" ],
							 "prev"   => [ "uri", "link to the next set or null if this is the last set" ],
							 "order"  => [ "string", "name of the attribute the returned data is ordered by" ],
							 "data"   => [ "list", [ "object", [$self->attributes, "list of sample objects"] ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->cgi->url."/".$self->name."/mgs25823?verbosity=full",
    				                     'retrieve all data for sample mgs25823' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				     ]
				 };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my ($id) = $rest->[0] =~ /^mgs(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();
  
    # get data
    my $sample = $master->MetaDataCollection->init( {ID => $id} );
    unless (ref($sample)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }

    # prepare data
    my $data = $self->prepare_data([ $sample ]);
    $data = $data->[0];

    $self->return_data($data)
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    my $dbh    = $master->db_handle();
    
    my $samples_hash = {};
    my $sample_map   = {};
    my $job_sam_map  = {};
    my $job_sample   = $dbh->selectall_arrayref("SELECT sample, metagenome_id, public FROM Job WHERE viewable=1");
    map { $sample_map->{$_->[0]} = {id => $_->[1], name => $_->[2], entry_date => $_->[3]} } @{$dbh->selectall_arrayref("SELECT _id, ID, name, entry_date FROM MetaDataCollection WHERE type='sample'")};
  
    # add samples with job: public or rights
    foreach my $js (@$job_sample) {
        next unless ($js && $sample_map->{$js->[0]});
        $job_sam_map->{$js->[0]} = 1;
        if (($js->[2] == 1) || exists($self->rights->{$js->[1]}) || exists($self->rights->{'*'})) {
            $samples_hash->{"mgs".$sample_map->{$js->[0]}} = $sample_map->{$js->[0]};
        }
    }
    # add samples with no job
    map { $samples_hash->{"mgs".$sample_map->{$_}} = $sample_map->{$_} } grep { ! exists $job_sam_map->{$_} } keys %$sample_map;
    my $samples = [];
    @$samples   = map { $samples_hash->{$_} } keys(%$samples_hash);
    my $total   = scalar @$samples;

    # check limit
    my $limit  = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    @$samples  = sort { $a->{$order} cmp $b->{$order} } @$samples;
    $limit     = (($limit == 0) || ($limit > scalar(@$samples))) ? scalar(@$samples) : $limit;
    @$samples  = @$samples[$offset..($offset+$limit-1)];
    
    # prepare data to the correct output format
    my $data = $self->prepare_data($samples);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);

    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $mddb;
    my $master = $self->connect_to_datasource();
    if ($self->cgi->param('verbosity') && $self->cgi->param('verbosity') ne 'minimal') {
        use MGRAST::Metadata;
        my $mddb = MGRAST::Metadata->new();
    }

    my $objects = [];
    foreach my $sample (@$data) {
        if ($sample->{ID}) {
            $sample->{id} = $sample->{ID};
        }
        my $url = $self->cgi->url;
        my $obj = {};
        $obj->{id}      = "mgs".$sample->{id};
        $obj->{name}    = $sample->{name};
        $obj->{url}     = $url.'/sample/'.$obj->{id};
        $obj->{version} = 1;
        $obj->{created} = $sample->{entry_date};
        
        if ($self->cgi->param('verbosity')) {
            if ($self->cgi->param('verbosity') ne 'minimal' && ref($sample) ne 'JobDB::MetaDataCollection') {
    	        $sample = $master->MetaDataCollection->init( {ID => $sample->{id}} );
            }
            if ($self->cgi->param('verbosity') eq 'full') {
            	my $proj  = $sample->project;
            	my $epack = $sample->children('ep');
            	my @jobs  = grep { $_->{public} || exists($self->rights->{$_->{metagenome_id}}) || exists($self->rights->{'*'}) } @{$sample->jobs};
                my $env_package = undef;
                if (@$epack) {
            	    my $edata = $epack->[0]->data;
            	    $edata->{sample_name} = $obj->{name};
            	    $edata = $self->cgi->param('template') ? $mddb->add_template_to_data($epack->[0]->{ep_type}, $edata) : $edata;
            	    $env_package = { id       => "mge".$epack->[0]->{ID},
            			             name     => $epack->[0]->{name} || "mge".$epack->[0]->{ID},
            			             type     => $epack->[0]->{ep_type},
            			             created  => $epack->[0]->{entry_date},
            			             metadata => $edata };
            	}
            	$obj->{project} = $proj ? ["mgp".$proj->{id}, $url."/project/mgp".$proj->{id}] : undef;
            	$obj->{env_package} = $env_package;
            	@{ $obj->{libraries} } = map { ["mgl".$_->{ID}, $url."/library/mgl".$_->{ID}] } @{$sample->children('library')};
            	@{ $obj->{metagenomes} } = map { ["mgm".$_->{metagenome_id}, $url.'/metagenome/mgm'.$_->{metagenome_id}] } @jobs;
            }
            if ($self->cgi->param('verbosity') eq 'verbose' || $self->cgi->param('verbosity') eq 'full') {
    	        my $mdata = $sample->data();
    	        if ($self->cgi->param('template')) {
    	            $mdata = $mddb->add_template_to_data('sample', $mdata);
    	        }
    	        $obj->{metadata} = $mdata;
            } elsif ($self->cgi->param('verbosity') ne 'minimal') {
    	        $self->return_data( {"ERROR" => "invalid value for option verbosity"}, 400 );
            }
        }
        push @$objects, $obj;
    }
    return $objects;
}

1;
