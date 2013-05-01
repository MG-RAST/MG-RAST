package resources2::annotations;

use strict;
use warnings;
no warnings('once');
use Data::Dumper;

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}       = "sequences";
    $self->{attributes} = { "id"      => [ 'string', 'unique object identifier' ],
    	                    "data"    => [ 'hash', 'annotations names pointing to list of md5s' ],
    	                    "version" => [ 'integer', 'version of the object' ],
    	                    "url"     => [ 'uri', 'resource location of this object instance' ] };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		            'url' => $self->cgi->url."/".$self->name,
		            'description' => "All annotations of a metagenome for a specific annotation type and source",
		            'type' => 'object',
		            'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		            'requests' => [
		            { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
			          'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'required' => {},
				                         'options'  => {},
						                 'body'     => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'required' => { "id" => [ "string", "unique metagenome identifier" ] },
				                         'options' => { "type" => [ "cv", [[ "organism", "return organism data" ],
												                           [ "function", "return function data" ],
												                           [ "ontology", "return ontology data" ]] ],
									                  "source" => [ "cv", [[ "RefSeq", "protein database, type organism and function only" ],
                           												   [ "GenBank", "protein database, type organism and function only" ],
                           												   [ "IMG", "protein database, type organism and function only" ],
                           												   [ "SEED", "protein database, type organism and function only" ],
                           												   [ "TrEMBL", "protein database, type organism and function only" ],
                           												   [ "SwissProt", "protein database, type organism and function only" ],
                           												   [ "PATRIC", "protein database, type organism and function only" ],
                           												   [ "KEGG", "protein database, type organism and function only" ],
                                       									   [ "RDP", "RNA database, type organism and function only" ],
                                       									   [ "Greengenes", "RNA database, type organism and function only" ],
                                       									   [ "LSU", "RNA database, type organism and function only" ],
                                       									   [ "SSU", "RNA database, type organism and function only" ],
                                       									   [ "Subsystems", "ontology database, type ontology only" ],
                           												   [ "NOG", "ontology database, type ontology only" ],
                           												   [ "COG", "ontology database, type ontology only" ],
                           												   [ "KO", "ontology database, type ontology only" ]] ],
                           							  'asynchronous' => [ 'boolean', "if true, return process id to query status resource for results.  default is false." ] },
							              'body' => {} } }
				  ]
		  };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
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
    unless ($job && scalar(@$job)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    } else {
        $job = $job->[0];
    }  
    
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    # return cached if exists
    $self->return_cached();
    
    # if asynchronous call, fork the process and return the process id.  otherwise, prepare and return data.
    if($self->cgi->param('asynchronous')) {
        my $pid = fork();
        # child - get data and dump it
        if ($pid == 0) {
            my $fname = $Conf::temp.'/'.$$.'.json';
            close STDERR;
            close STDOUT;
            my $data = $self->prepare_data($job);
            open(FILE, ">$fname");
            print FILE $self->json->encode($data);
            close FILE;
            exit 0;
        }
        # parent - end html session
        else {
            my $fname = $Conf::temp.'/'.$pid.'.json';
            $self->return_data({"status" => "Submitted", "id" => $pid, "url" => $self->cgi->url."/status/".$pid});
        }
    } else {
        # prepare data
        my $data = $self->prepare_data($job);
        $self->return_data($data, undef, 1); # cache this!
    }
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $cgi = $self->cgi;
    my $type = $cgi->param('type') ? $cgi->param('type') : 'organism';
    my $source = $cgi->param('source') ? $cgi->param('source') : (($type eq 'ontology') ? 'Subsystems' : 'RefSeq');
  
    my $master = $self->connect_to_datasource();
    use MGRAST::Analysis;
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data( {"ERROR" => "resource database offline"}, 503 );
    }
    my $mgid = $data->{metagenome_id};
    $mgdb->set_jobs([$mgid]);

    my $content;
    if ($type eq 'organism') {
        $content = $mgdb->get_org_md5(undef, undef, undef, [$source]);
    } elsif ($type eq 'function') {
        $content = $mgdb->get_func_md5(undef, undef, undef, [$source]);
    } elsif ($type eq 'ontology') {
        $content = $mgdb->get_ontol_md5(undef, undef, undef, $source);
    } else {
        $self->return_data( {"ERROR" => "Invalid annotation type was entered ($type). Please use one of: organism, function, ontology"}, 404 );
    }

    my $annotations = {};
    if ($content && exists($content->{$mgid})) {
        my %md5s = ();
        foreach my $ann (keys %{$content->{$mgid}}) {
            map { $md5s{$_} = 1 } keys %{$content->{$mgid}{$ann}};
        }
        my $md5_map = $mgdb->decode_annotation('md5', [keys %md5s]);
        foreach my $ann (keys %{$content->{$mgid}}) {
            my @md5sums = map { $md5_map->{$_} } grep { exists $md5_map->{$_} } keys %{$content->{$mgid}{$ann}};
            if (@md5sums > 0) {
                $annotations->{$ann} = \@md5sums;
            }
        }
    }

    my $object = { id      => "mgm".$mgid,
		           data    => $annotations,
		           url     => $cgi->url."/mgm".$mgid."?type=".$type.'&source='.$source,
		           version => 1
		         };
  
    return $object;
}

1;
