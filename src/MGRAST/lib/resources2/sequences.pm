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
    	                    "data"    => [ 'hash', 'data type pointing at lists of sequences' ],
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
									    "annotation" => [ "list", [ "string", "data_type to filter by" ] ],
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
               												 [ "KO", "ontology database, type ontology only" ]] ] },
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

    # prepare data
    my $data = $self->prepare_data($job);
    
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $cgi  = $self->cgi;
    my $type = $cgi->param('data_type') ? $cgi->param('data_type') : 'organism';
    my $seq  = $cgi->param('sequence_type') ? $cgi->param('sequence_type') : 'dna';
    my @srcs = $cgi->param('source') ? $cgi->param('source') : ();
    my @anns = $cgi->param('annotation') ? $cgi->param('annotation') : ();
    my @md5s = $cgi->param('md5') ? $cgi->param('md5') : ();
  
    my $master = $self->connect_to_datasource();
    use MGRAST::Analysis;
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data( {"ERROR" => "resource database offline"}, 503 );
    }

    my $url = $cgi->url."/sequences/mgm".$data->{metagenome_id}."?sequence_type=".$seq;
    my $content;
    if (scalar(@md5s) > 0) {
        my $md5_ints_to_strings = $mgdb->_get_annotation_map('md5', \@md5s);
        if (scalar(keys %$md5_ints_to_strings) > 0) {
          $content = $mgdb->sequences_for_md5s($data->{metagenome_id}, $seq, [keys %$md5_ints_to_strings], 1);
          my %valid_md5s = map { $_ => 1} values %$md5_ints_to_strings; # uniquifying valid md5s
          $url .= "&md5=".join("&md5=", keys %valid_md5s);
        } else {
          $self->return_data( {"ERROR" => "No valid md5 was entered.  For more information on how to use this resource, view the resource description here: ".$cgi->url."/sequences"}, 404 );
        }
    } elsif (scalar(@anns) > 0) {
        $content = $mgdb->sequences_for_annotation($data->{metagenome_id}, $seq, $type, \@srcs, \@anns);
        $url .= "&data_type=".$type."&annotation=".join("&annotation=", @anns);
        if (scalar(@srcs) > 0) {
            $url .= "&source=".join("&source=", @srcs);
        }
    } else {
        $self->return_data( {"ERROR" => "To retrieve sequences, you must either enter an 'md5' or a 'data_type' and an 'annotation'.  The default 'data_type' is organism.  For more information on how to use this resource, view the resource description here: ".$cgi->url."/sequences"}, 404 );
    }

    my $object = { id      => "mgm".$data->{metagenome_id},
		           data    => $content,
		           url     => $url,
		           version => 1
		         };
  
    return $object;
}

1;
