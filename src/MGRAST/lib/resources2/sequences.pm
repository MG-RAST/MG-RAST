package resources2::sequences;

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
    $self->{name}       = "sequences";
    $self->{attributes} = { "id"      => [ 'string', 'unique object identifier' ],
    	                    "data"    => [ 'list',  [ 'hash', 'a hash of data_type to list of sequences' ] ],
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
		    'description' => "A set of genomic sequences of a metagenome annotated by a specified source",
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
				    { 'name'        => "md5",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { "sequence_type" => [ "cv", [ [ "dna", "return DNA sequences" ],
													 [ "protein", "return protein sequences" ] ] ],
									    "md5" => [ "list", [ "string", "md5 identifier" ] ] },
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => {  } } },
				    { 'name'        => "annotation",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { "data_type" => [ "cv", [ [ "organism", "return organism data" ],
												     [ "function", "return function data" ],
												     [ "ontology", "return ontology data" ] ] ],
									    "sequence_type" => [ "cv", [ [ "dna", "return DNA sequences" ],
													 [ "protein", "return protein sequences" ] ] ],
									    "organism" => [ "list", [ "string", "organism to filter by" ] ],
									    "function" => [ "list", [ "string", "function to filter by" ] ],
									    "ontology" => [ "list", [ "string", "ontology to filter by" ] ],
									    "source" => [ "cv", [  [  "RDP", "RNA database, type organism and feature only" ],
												[ "Greengenes", "RNA database, type organism and feature only" ],
												[ "LSU", "RNA database, type organism and feature only" ],
												[ "SSU", "RNA database, type organism and feature only" ],
												[ "SwissProt", "protein database, type organism and feature only" ],
												[ "GenBank", "protein database, type organism and feature only" ],
												[ "IMG", "protein database, type organism and feature only" ],
												[ "SEED", "protein database, type organism and feature only" ],
												[ "TrEMBL", "protein database, type organism and feature only" ],
												[ "RefSeq", "protein database, type organism and feature only" ],
												[ "PATRIC", "protein database, type organism and feature only" ],
												[ "eggNOG", "protein database, type organism and feature only" ],
												[ "KEGG", "protein database, type organism and feature only" ],												
												[ "NOG", "ontology database, type function only" ],
												[ "COG", "ontology database, type function only" ],
												[ "KO", "ontology database, type function only" ],
												[ "GO", "ontology database, type function only" ],
												[ "Subsystems", "ontology database, type function only" ] ] ] },
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => { } } }
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
    my $job = $master->Job->init( {metagenome_id => $id} );
    unless ($job && ref($job)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }
    
    # check rights
    unless ($job->{public} || $self->user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $self->prepare_data($job);
    
    $self->return_data($data);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
    $self->info();
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $cgi  = $self->cgi;
    my $type = $cgi->param('data_type') ? $cgi->param('data_type') : 'organism';
    my $seq  = $cgi->param('sequence_type') ? $cgi->param('sequence_type') : 'dna';
    my @srcs = $cgi->param('source') ? $cgi->param('source') : ();
    my @anns = $cgi->param($type) ? $cgi->param($type) : ();
    my @md5s = $cgi->param('md5') ? $cgi->param('md5') : ();
  
    my $master = $self->connect_to_datasource();
    use MGRAST::Analysis;
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data( {"ERROR" => "resource database offline"}, 503 );
    }
  
    my $content;
    if (scalar(@md5s) > 0) {
        $content = $mgdb->sequences_for_md5s($data->{metagenome_id}, $seq, \@md5s);
    } else {
        $content = $mgdb->sequences_for_annotation($data->{metagenome_id}, $seq, $type, \@srcs, \@anns);
    }

    my $object = { id      => "mgm".$data->{metagenome_id},
		           data    => $content,
		           url     => $cgi->url.'/sequences/'.$data->{metagenome_id},
		           version => 1
		         };
  
    return $object;
}

1;
