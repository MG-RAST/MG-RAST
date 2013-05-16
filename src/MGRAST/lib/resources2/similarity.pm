package resources2::similarity;

use strict;
use warnings;
no warnings('once');

use Data::Dumper;
use HTML::Strip;

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "similarity";
    $self->{types} = { "organism" => 1, "function" => 1, "ontology" => 1, "feature" => 1 };
    $self->{cutoffs} = { evalue => '5', identity => '60', length => '15' };
    $self->{attributes} = { "streaming text" => [ 'object', [{ "col1" => ['string', 'query sequence id'],
                                                               "col2" => ['string', 'hit m5nr id (md5sum)'],
                                                               "col3" => ['float', 'percentage identity'],
                                                               "col4" => ['int', 'alignment length,'],
                                                               "col5" => ['int', 'number of mismatches'],
                                                               "col6" => ['int', 'number of gap openings'],
                                                               "col7" => ['int', 'query start'],
                                                               "col8" => ['int', 'query end'],
                                                               "col9" => ['int', 'hit start'],
                                                               "col10" => ['int', 'hit end'],
                                                               "col11" => ['float', 'e-value'],
                                                               "col12" => ['float', 'bit score'],
                                                               "col13" => ['string', 'semicolon seperated list of annotations']
                                                              }, "tab deliminted blast m8 with annotation"] ] };
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
			          'method'      => "GET",
				      'type'        => "synchronous",  
				      'attributes'  => "self",
				      'parameters'  => { 'required' => {},
				                         'options'  => {},
						                 'body'     => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "tab deliminted blast m8 with annotation",
				      'method'      => "GET",
				      'type'        => "stream",  
				      'attributes'  => $self->{attributes},
				      'parameters'  => { 'required' => { "id" => [ "string", "unique metagenome identifier" ] },
				                         'options' => { 'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                                                        'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                                                        'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
				                                        "type" => [ "cv", [[ "organism", "return organism data" ],
												                           [ "function", "return function data" ],
												                           [ "ontology", "return ontology data" ],
												                           [ "feature", "return feature data" ]] ],
									                  "source" => [ "cv", [[ "RefSeq", "protein database, type organism, function, feature" ],
                           												   [ "GenBank", "protein database, type organism, function, feature" ],
                           												   [ "IMG", "protein database, type organism, function, feature" ],
                           												   [ "SEED", "protein database, type organism, function, feature" ],
                           												   [ "TrEMBL", "protein database, type organism, function, feature" ],
                           												   [ "SwissProt", "protein database, type organism, function, feature" ],
                           												   [ "PATRIC", "protein database, type organism, function, feature" ],
                           												   [ "KEGG", "protein database, type organism, function, feature" ],
                                       									   [ "RDP", "RNA database, type organism, function, feature" ],
                                       									   [ "Greengenes", "RNA database, type organism, function, feature" ],
                                       									   [ "LSU", "RNA database, type organism, function, feature" ],
                                       									   [ "SSU", "RNA database, type organism, function, feature" ],
                                       									   [ "Subsystems", "ontology database, type ontology only" ],
                           												   [ "NOG", "ontology database, type ontology only" ],
                           												   [ "COG", "ontology database, type ontology only" ],
                           												   [ "KO", "ontology database, type ontology only" ]] ] },
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
    
    my $data = $self->prepare_data($job);
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    my $cgi    = $self->cgi;
    my $type   = $cgi->param('type') ? $cgi->param('type') : 'organism';
    my $source = $cgi->param('source') ? $cgi->param('source') : (($type eq 'ontology') ? 'Subsystems' : 'RefSeq');
    my $eval   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    my $ident  = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    my $alen   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
  
    my $master = $self->connect_to_datasource();
    use MGRAST::Analysis;
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data({"ERROR" => "resource database offline"}, 503);
    }
    my $mgid = $data->{metagenome_id};
    $mgdb->set_jobs([$mgid]);

    unless (exists $mgdb->_src_id->{$source}) {
        $self->return_data({"ERROR" => "Invalid source was entered ($source). Please use one of: ".join(", ", keys %{$mgdb->_src_id})}, 404);
    }
    unless (exists $self->{types}{$type}) {
        $self->return_data({"ERROR" => "Invalid type was entered ($type). Please use one of: ".join(", ", keys %{$self->{types}})}, 404);
    }

    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
    
    my $srcid = $mgdb->_src_id->{$source};
    my $where = $mgdb->_get_where_str([$mgdb->_qver, "job = ".$data->{job_id}, $eval, $ident, $alen, "seek IS NOT NULL", "length IS NOT NULL"]);
    my $query = "SELECT md5, seek, length FROM ".$mgdb->_jtbl->{md5}.$where." ORDER BY seek";
    
    open(FILE, "<" . $mgdb->_sim_file($data->{job_id})) || $self->return_data({"ERROR" => "resource database offline"}, 503);
    print $cgi->header(-type => 'text/plain', -status => 200, -Access_Control_Allow_Origin => '*');

    my $hs = HTML::Strip->new();
    foreach my $row (@{ $mgdb->_dbh->selectall_arrayref($query) }) {
        my ($md5, $seek, $len) = @$row;
        my $ann = [];
        if ($type eq 'organism') {
            $ann = $mgdb->_dbh->selectcol_arrayref("SELECT DISTINCT o.name FROM md5_annotation a, organisms_ncbi o WHERE a.md5=$md5 AND a.source=$srcid AND a.organism=o._id");
        } elsif ($type eq 'function') {
            $ann = $mgdb->_dbh->selectcol_arrayref("SELECT DISTINCT f.name FROM md5_annotation a, functions f WHERE a.md5=$md5 AND a.source=$srcid AND a.function=f._id");
        } else {
            $ann = $mgdb->_dbh->selectcol_arrayref("SELECT DISTINCT id FROM md5_annotation WHERE md5=$md5 AND source=$srcid");
        }
        if (@$ann == 0) { next; }
        my $rec = '';
        seek(FILE, $seek, 0);
        read(FILE, $rec, $len);
        chomp $rec;
        foreach my $line ( split(/\n/, $rec) ) {
            my @tabs = split(/\t/, $line);
            my $rid  = $hs->parse($tabs[0]);
            $hs->eof;
            print join("\t", ('mgm'.$mgid."|".$rid, @tabs[1..11], join(";", @$ann)))."\n";
        }
    }
    close FILE;
    exit 0;
}

1;
