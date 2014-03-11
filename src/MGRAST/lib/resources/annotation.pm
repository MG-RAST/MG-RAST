package resources::annotation;

use strict;
use warnings;
no warnings('once');

use List::MoreUtils qw(any uniq);
use Data::Dumper;
use HTML::Strip;
use URI::Escape;

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}  = "annotation";
    $self->{types} = [[ "organism", "return organism data" ],
                      [ "function", "return function data" ],
                      [ "ontology", "return ontology data" ],
                      [ "feature", "return feature data" ],
                      [ "md5", "return md5sum data" ]];
    $self->{cutoffs}  = { evalue => '5', identity => '60', length => '15' };
    $self->{m5nr_ver} = "1";
    $self->{m5nr_max} = 10000;
    $self->{attributes} = { sequence => {
                                "col_01" => ['string', 'sequence id'],
                                "col_02" => ['string', 'm5nr id (md5sum)'],
                                "col_03" => ['string', 'dna sequence'],
                                "col_04" => ['string', 'semicolon seperated list of annotations'] },
                            similarity => {
                                "col_01" => ['string', 'query sequence id'],
                                "col_02" => ['string', 'hit m5nr id (md5sum)'],
                                "col_03" => ['float', 'percentage identity'],
                                "col_04" => ['int', 'alignment length,'],
                                "col_05" => ['int', 'number of mismatches'],
                                "col_06" => ['int', 'number of gap openings'],
                                "col_07" => ['int', 'query start'],
                                "col_08" => ['int', 'query end'],
                                "col_09" => ['int', 'hit start'],
                                "col_10" => ['int', 'hit end'],
                                "col_11" => ['float', 'e-value'],
                                "col_12" => ['float', 'bit score'],
                                "col_13" => ['string', 'semicolon seperated list of annotations'] }
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $sources = [];
    map { push @$sources, $_ } @{$self->source->{protein}};
    map { push @$sources, $_ } @{$self->source->{rna}};
    map { push @$sources, $_ } @{$self->source->{ontology}};
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
						                     'body'     => {} }
						},
				        { 'name'        => "sequence",
				          'request'     => $self->cgi->url."/".$self->name."/sequence/{ID}",
				          'description' => "tab deliminted annotated sequence stream",
				          'example'     => [ $self->cgi->url."/".$self->name."/sequence/mgm4447943.3?evalue=10&type=organism&source=SwissProt",
				                             'all annotated read sequences from mgm4447943.3 with hits in SwissProt organisms at evaule < e-10' ],
				          'method'      => "GET",
				          'type'        => "stream",  
				          'attributes'  => { "streaming text" => ['object', [$self->{attributes}{sequence}, "tab deliminted annotated sequence stream"]] },
				          'parameters'  => { 'required' => { "id" => [ "string", "unique metagenome identifier" ] },
				                             'options' => { 'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                                                            'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                                                            'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                                                            "filter"   => ['string', 'text string to filter annotations by: only return those that contain text'],
				                                            "type"     => ["cv", $self->{types} ],
									                        "source"   => ["cv", $sources ],
									                        "filter_level" => ['string', 'hierarchal level to filter annotations by, for organism or ontology only'] },
							                 'body' => {} }
						},
						{ 'name'        => "similarity",
				          'request'     => $self->cgi->url."/".$self->name."/similarity/{ID}",
				          'description' => "tab deliminted blast m8 with annotation",
				          'example'     => [ $self->cgi->url."/".$self->name."/similarity/mgm4447943.3?identity=80&type=function&source=KO",
  				                             'all annotated read blat stats from mgm4447943.3 with hits in KO functions at % identity > 80' ],
				          'method'      => "GET",
				          'type'        => "stream",  
				          'attributes'  => { "streaming text" => ['object', [$self->{attributes}{similarity}, "tab deliminted blast m8 with annotation"]] },
				          'parameters'  => { 'required' => { "id" => [ "string", "unique metagenome identifier" ] },
				                             'options' => { 'evalue'   => ['int', 'negative exponent value for maximum e-value cutoff: default is '.$self->{cutoffs}{evalue}],
                                                            'identity' => ['int', 'percent value for minimum % identity cutoff: default is '.$self->{cutoffs}{identity}],
                                                            'length'   => ['int', 'value for minimum alignment length cutoff: default is '.$self->{cutoffs}{length}],
                                                            "filter"   => ['string', 'text string to filter annotations by: only return those that contain text'],
				                                            "type"     => ["cv", $self->{types} ],
									                        "source"   => ["cv", $sources ],
									                        "filter_level" => ['string', 'hierarchal level to filter annotations by, for organism or ontology only'] },
							                 'body' => {} }
						} ]
		  };

    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif ($self->rest->[1] && (($self->rest->[0] eq 'sequence') || ($self->rest->[0] eq 'similarity'))) {
        $self->instance($self->rest->[0], $self->rest->[1]);
    } else {
        $self->info();
    }
}

# the resource is called with an id parameter
sub instance {
    my ($self, $format, $mgid) = @_;
    
    # check id format
    my $rest = $self->rest;
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: ".$mgid}, 400 );
    }

    # get data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id, viewable => 1} );
    unless ($job && scalar(@$job)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    } else {
        $job = $job->[0];
    }  
    
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    $self->prepare_data($job, $format);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data, $format) = @_;

    my $cgi    = $self->cgi;
    my $type   = $cgi->param('type') ? $cgi->param('type') : 'organism';
    my $source = $cgi->param('source') ? $cgi->param('source') : (($type eq 'ontology') ? 'Subsystems' : 'RefSeq');
    my $eval   = defined($cgi->param('evalue')) ? $cgi->param('evalue') : $self->{cutoffs}{evalue};
    my $ident  = defined($cgi->param('identity')) ? $cgi->param('identity') : $self->{cutoffs}{identity};
    my $alen   = defined($cgi->param('length')) ? $cgi->param('length') : $self->{cutoffs}{length};
    my $filter = $cgi->param('filter') || undef;
    my $flevel = $cgi->param('filter_level') || undef;
    my $md5s = [];
    
    # post of md5s
    if ($self->method eq 'POST') {
        my $post_data = $self->cgi->param('POSTDATA') ? $self->cgi->param('POSTDATA') : join(" ", $self->cgi->param('keywords'));
        # all options sent as post data
        if ($post_data) {
            eval {
                my $json_data = $self->json->decode($post_data);
                if (exists $json_data->{type})     { $type   = $json_data->{type}; }
                if (exists $json_data->{source})   { $source = $json_data->{source}; }
                if (exists $json_data->{evalue})   { $eval   = $json_data->{evalue}; }
                if (exists $json_data->{identity}) { $ident  = $json_data->{identity}; }
                if (exists $json_data->{length})   { $alen   = $json_data->{length}; }
                $filter = undef;
                $flevel = undef;
                $md5s = $json_data->{md5s};
            };
        # data sent in post form
        } elsif ($self->cgi->param('md5s')) {
            eval {
                @$md5s = split(/;/, $self->cgi->param('md5s'));
            };
        } else {
            $self->return_data( {"ERROR" => "POST request missing md5s"}, 400 );
        }
        if ($@ || (@$md5s == 0)) {
            $self->return_data( {"ERROR" => "unable to obtain POSTed data: ".$@}, 500 );
        }
    } elsif ($filter && ($type eq 'md5')) {
        $md5s = [$filter];
        $filter = undef;
    }
    
    # set DB handle
    my $master = $self->connect_to_datasource();
    use MGRAST::Analysis;
    my $mgdb = MGRAST::Analysis->new( $master->db_handle );
    unless (ref($mgdb)) {
        $self->return_data({"ERROR" => "resource database offline"}, 503);
    }
    my $mgid = $data->{metagenome_id};
    $mgdb->set_jobs([$mgid]);

    # validate options
    unless (exists $mgdb->_src_id->{$source}) {
        $self->return_data({"ERROR" => "Invalid source was entered ($source). Please use one of: ".join(", ", keys %{$mgdb->_src_id})}, 404);
    }
    if (($type eq 'ontology') && (! any {$_->[0] eq $source} @{$self->source->{ontology}})) {
        $self->return_data({"ERROR" => "Invalid ontology source was entered ($source). Please use one of: ".join(", ", map {$_->[0]} @{$self->source->{ontology}})}, 404);
    }
    if (($type eq 'organism') && (any {$_->[0] eq $source} @{$self->source->{ontology}})) {
        $self->return_data({"ERROR" => "Invalid organism source was entered ($source). Please use one of: ".join(", ", map {$_->[0]} (@{$self->source->{protein}}, @{$self->source->{rna}}))}, 404);
    }
    unless (any {$_->[0] eq $type} @{$self->{types}}) {
        $self->return_data({"ERROR" => "Invalid type was entered ($type). Please use one of: ".join(", ", map {$_->[0]} @{$self->{types}})}, 404);
    }
    
    # only have filter_level for organism or ontology
    if ( $flevel && (($flevel =~ /^strain|species|function$/) || ($type !~ /^organism|ontology$/)) ) {
        $flevel = undef;
    }
    if ($filter && $flevel) {
        unless ( (($type eq 'organism') && (any {$_->[0] eq $flevel} @{$self->hierarchy->{organism}})) ||
                 (($type eq 'ontology') && (any {$_->[0] eq $flevel} @{$self->hierarchy->{ontology}})) ) {
            $self->return_data({"ERROR" => "Invalid filter_level was entered ($flevel). For organism use one of: ".join(", ", map {$_->[0]} @{$self->hierarchy->{organism}}).". For ontology use one of: ".join(", ", map {$_->[0]} @{$self->hierarchy->{ontology}})}, 404);
        }
    }
    
    # build queries
    $eval  = (defined($eval)  && ($eval  =~ /^\d+$/)) ? "exp_avg <= " . ($eval * -1) : "";
    $ident = (defined($ident) && ($ident =~ /^\d+$/)) ? "ident_avg >= $ident" : "";
    $alen  = (defined($alen)  && ($alen  =~ /^\d+$/)) ? "len_avg >= $alen"    : "";
    
    my $query = "";
    if (@$md5s) {
        $query  = "SELECT j.md5, j.seek, j.length FROM ".$mgdb->_jtbl->{md5}." j, ".$mgdb->_atbl->{md5}." m";
        $query .= $mgdb->_get_where_str([ 'j.'.$mgdb->_qver, "j.job = ".$data->{job_id},
                                          'j.'.$eval, 'j.'.$ident, 'j.'.$alen,
                                          'j.seek IS NOT NULL', 'j.length IS NOT NULL',
                                          'j.md5 = m._id', 'm.md5 IN ('.join(",", map {$mgdb->_dbh->quote($_)} @$md5s).')'
                                        ]);
        $query .= " ORDER BY j.seek";
    } else {
        $query  = "SELECT md5, seek, length FROM ".$mgdb->_jtbl->{md5};
        $query .= $mgdb->_get_where_str([ $mgdb->_qver, "job = ".$data->{job_id},
                                          $eval, $ident, $alen,
                                          "seek IS NOT NULL", "length IS NOT NULL"
                                        ]);
        $query .= " ORDER BY seek";
    }
    
    my $srcid = $mgdb->_src_id->{$source};
    my @head  = map { $self->{attributes}{$format}{$_}[1] } sort keys %{$self->{attributes}{$format}};
    my $count = 0;
    
    open(FILE, "<" . $mgdb->_sim_file($data->{job_id})) || $self->return_data({"ERROR" => "resource database offline"}, 503);
    print $cgi->header(-type => 'text/plain', -status => 200, -Access_Control_Allow_Origin => '*');
    print join("\t", @head)."\n";

    my $hs  = HTML::Strip->new();
    my $sth = $mgdb->_dbh->prepare($query);
    $sth->execute() or die "Couldn't execute statement: ".$sth->errstr;
    
    # loop through indices and print data
    while (my @row = $sth->fetchrow_array()) {
        my ($md5, $seek, $len, $mmd5) = @row;
        my $sql = "";
        my $ann = [];
        if ($type eq 'organism') {
            $sql = "SELECT DISTINCT o.name FROM md5_annotation a, organisms_ncbi o WHERE a.md5=$md5 AND a.source=$srcid AND a.organism=o._id";
            if ($filter && $flevel) {
                $sql .= " AND o.tax_".$flevel."=".$mgdb->_dbh->quote($filter);
            }
        } elsif ($type eq 'function') {
            $sql = "SELECT DISTINCT f.name FROM md5_annotation a, functions f WHERE a.md5=$md5 AND a.source=$srcid AND a.function=f._id";
        } elsif ($type eq 'ontology') {
            $sql = "SELECT DISTINCT o.name FROM md5_annotation a, ontologies o WHERE a.md5=$md5 AND a.source=$srcid AND a.id=o.name";
            if ($filter && $flevel) {
                $sql .= " AND o.".$flevel."=".$mgdb->_dbh->quote($filter);
            }
        } elsif ($type eq 'feature') {
            $sql = "SELECT DISTINCT id FROM md5_annotation WHERE md5=$md5 AND source=$srcid";
        }
        
        if ($type ne 'md5') {
            $ann = $mgdb->_dbh->selectcol_arrayref($sql);
            # remove non-matching annotations if using filter without hierarchal level
            if ($filter && (! $flevel)) {
                my @matches = grep {/$filter/} @$ann;
                @$ann = @matches;
            }
            if (@$ann == 0) { next; }
        }
        
        # pull data from indexed file
        my $rec = '';
        seek(FILE, $seek, 0);
        read(FILE, $rec, $len);
        chomp $rec;
        foreach my $line ( split(/\n/, $rec) ) {
            my @tabs = split(/\t/, $line);
            if ($tabs[0]) {
                my @out = ();
                my $rid = $hs->parse($tabs[0]);
                unless ($mgid && $rid) {
                    next;
                }
                $hs->eof;
                if (($format eq 'sequence') && (@tabs == 13)) {
                    @out = ('mgm'.$mgid."|".$rid, $tabs[1], $tabs[12], join(";", @$ann));
                } elsif ($format eq 'similarity') {
                    @out = ('mgm'.$mgid."|".$rid, @tabs[1..11], join(";", @$ann));
                    $count += 1;
                }
                if ($type eq 'md5') {
                    pop @out;
                }
                print join("\t", map {$_ || ''} @out)."\n";
                $count += 1;
            }
        }
    }
    
    # cleanup
    $sth->finish;
    $mgdb->_dbh->commit;
    print "Download complete. $count rows retrieved\n";
    close FILE;
    exit 0;
}

1;
