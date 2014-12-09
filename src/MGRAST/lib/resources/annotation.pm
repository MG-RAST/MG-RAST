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
                                "col_04" => ['string', 'semicolon separated list of annotations'] },
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
                                "col_13" => ['string', 'semicolon separated list of annotations'] }
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
				          'description' => "tab delimited annotated sequence stream",
				          'example'     => [ $self->cgi->url."/".$self->name."/sequence/mgm4447943.3?evalue=10&type=organism&source=SwissProt",
				                             'all annotated read sequences from mgm4447943.3 with hits in SwissProt organisms at evalue < e-10' ],
				          'method'      => "GET",
				          'type'        => "stream",  
				          'attributes'  => { "streaming text" => ['object', [$self->{attributes}{sequence}, "tab delimited annotated sequence stream"]] },
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
				          'description' => "tab delimited blast m8 with annotation",
				          'example'     => [ $self->cgi->url."/".$self->name."/similarity/mgm4447943.3?identity=80&type=function&source=KO",
  				                             'all annotated read blat stats from mgm4447943.3 with hits in KO functions at % identity > 80' ],
				          'method'      => "GET",
				          'type'        => "stream",  
				          'attributes'  => { "streaming text" => ['object', [$self->{attributes}{similarity}, "tab delimited blast m8 with annotation"]] },
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
                if ($type eq 'md5') {
                    $filter = undef;
                    $flevel = undef;
                    $md5s = $json_data->{md5s};
                }
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
        $filter = undef;
        $flevel = undef;
        $md5s = [$filter];
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
    
    # get shock node for file
    my $params = {type => 'metagenome', data_type => 'similarity', stage_name => 'filter.sims', id => 'mgm'.$mgid};
    my $sim_node = $self->get_shock_query($params, $self->mgrast_token);
    unless ((@$sim_node > 0) && exists($sim_node->[0]{id})) {
        $self->return_data({"ERROR" => "Unable to retrieve $format file"}, 500);
    }
    my $node_id = $sim_node->[0]{id};
    
    # print html and line headers
    my @head = map { $self->{attributes}{$format}{$_}[1] } sort keys %{$self->{attributes}{$format}};
    print $cgi->header(-type => 'text/plain', -status => 200, -Access_Control_Allow_Origin => '*');
    print join("\t", @head)."\n";
    
    # start query
    my $sth = $mgdb->_dbh->prepare($query);
    $sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

    # loop through indexes and print data
    my $srcid = $mgdb->_src_id->{$source};
    my $count = 0;
    my @md5s = ();
    my @seeks = ();
    my @lens = ();
    my $batch_count = 0;
    while (my @row = $sth->fetchrow_array()) {
        my ($md5, $seek, $len) = @row;
        push @md5s, $md5;
        push @seeks, $seek;
        push @lens, $len;
        $batch_count++;
        if($batch_count == 1000) {
            my $solr_query_str = "(source_id:$srcid) AND (md5_id:(".join(" OR ", @md5s)."))";
            $count = $self->print_batch($count, $node_id, $format, $mgid, $solr_query_str, $mgdb->_version, \@md5s, \@seeks, \@lens);
            @md5s = ();
            @seeks = ();
            @lens = ();
            $batch_count = 0;
        }
    }
    if($batch_count > 0) {
        my $solr_query_str = "(source_id:$srcid) AND (md5_id:(".join(" OR ", @md5s)."))";
        $count = $self->print_batch($count, $node_id, $format, $mgid, $solr_query_str, \@md5s, \@seeks, \@lens);
    }

    # cleanup
    $sth->finish;
    $mgdb->_dbh->commit;
    print "Download complete. $count rows retrieved\n";
    exit 0;
}

sub print_batch {
    my ($self, $count, $node_id, $format, $mgid, $solr_query_str, $ann_ver, $md5s, $seeks, $lens) = @_;

    my $cgi    = $self->cgi;
    my $type   = $cgi->param('type') ? $cgi->param('type') : 'organism';
    my $filter = $cgi->param('filter') || undef;
    my $flevel = $cgi->param('filter_level') || undef;
    my $fields = ();
    if ($type eq 'organism') {
	if ($filter && $flevel) {
	    $fields = ['organism', 'md5_id', $flevel];
	    $solr_query_str .= " AND ($flevel:$filter)";
	} else {
	    $fields = ['organism', 'md5_id'];
	}
    } elsif ($type eq 'function') {
	$fields = ['function', 'md5_id'];
    } elsif ($type eq 'ontology') {
	if ($filter && $flevel) {
	    $fields = ['organism', 'md5_id', $flevel];
	    $solr_query_str .= " AND ($flevel:$filter)";
	} else {
	    $fields = ['organism', 'md5_id'];
	}
    } elsif ($type eq 'feature') {
	$fields = ['md5_id'];
    }

    my ($data, $row_count) = $self->get_solr_query("POST", $Conf::m5nr_solr, $Conf::m5nr_collect.'_'.$ann_ver, $solr_query_str, "", 0, 1000000000, $fields);
    my %md5s_to_annot = ();
    if ($type ne 'md5') {
        foreach my $result (@$data) {
            $md5s_to_annot{$result->{md5_id}}{$result->{$type}} = 1;
        }
    }

    my $hs  = HTML::Strip->new();
    for(my $i=0; $i<@{$md5s}; $i++) {
	if ($type ne 'md5' && !exists $md5s_to_annot{$md5s->[$i]}) {
	    next;
	}
	# pull data from indexed shock file
	my $rec = $self->get_shock_file($node_id, undef, $self->mgrast_token, 'seek='.$seeks->[$i].'&length='.$lens->[$i]);
	chomp $rec;
	foreach my $line (split(/\n/, $rec)) {
	    my @tabs = split(/\t/, $line);
	    if ($tabs[0]) {
		my @out = ();
		my $rid = $hs->parse($tabs[0]);
		unless ($mgid && $rid) {
		    next;
		}
		$hs->eof;
		my $ann = [];
		foreach my $key (keys %{$md5s_to_annot{$md5s->[$i]}}) {
		    push @$ann, $key;
		}
		if ($type ne 'md5') {
                    if ($filter && (! $flevel)) {
                        my @matches = grep {/$filter/} @$ann;
                        @$ann = @matches;
                    }
                    if (@$ann == 0) { next; }
                }
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
    return $count;
}

1;
