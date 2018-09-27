package resources::profile;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use Data::Dumper;
use List::MoreUtils qw(natatime);

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map { $_, 1 } grep {$_ ne '*'} @{$self->user->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "profile";
    $self->{rights} = \%rights;
    $self->{sources} = [
        @{$self->source->{protein}},
        @{$self->source->{rna}},
        @{$self->source->{ontology}}
    ];
    $self->{ontology} = { map { $_, 1 } @{$self->source_by_type('ontology')} };
    $self->{profile}  = {
        id        => [ 'string', 'unique metagenome identifier' ],
        created   => [ 'string', 'time the output data was generated' ],
        version   => [ 'integer', 'version number of M5NR used' ],
        source    => [ 'string', 'source used in annotations' ],
        columns   => [ 'list', [ 'string', 'list of the columns in data' ] ],
        condensed => [ 'boolean', 'true if annotations are numeric identifiers and not full text' ],
        row_total => [ 'integer', 'number of rows in data matrix' ],
        data      => [ 'list', [ 'list', [ 'various', 'the matrix values' ] ] ]
    };
    $self->{submit} = {
        id     => [ 'string', 'unique status identifier' ],
        status => [ 'string', 'cv', ['submitted', 'process is has been submitted'],
                                    ['processing', 'process is still computing'],
                                    ['done', 'process is done computing'] ],
        url     => [ 'url', 'resource location of this object instance']
    };
    $self->{status} = {
        id     => [ 'string', 'unique profile status identifier' ],
        status => [ 'string', 'cv', ['submitted', 'profile is has been submitted'],
                                    ['processing', 'profile is still computing'],
                                    ['done', 'profile is done computing'] ],
        url     => [ 'url', 'resource location of this object instance'],
        size    => [ 'integer', 'size of profile in bytes' ],
        created => [ 'string', 'time the profile was completed' ],
        md5     => [ 'string', 'md5sum of profile' ],
        rows    => [ 'string', 'number of rows in profile data' ],
        source  => [ 'string', 'source name used in profile' ],
        data    => $self->{profile}
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name'         => $self->name,
        'url'          => $self->url."/".$self->name,
        'description'  => "A feature profile in json format that contains abundance and similarity values along with annotations",
        'type'          => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests'      => [
            { 'name'        => "info",
			  'request'     => $self->url."/".$self->name,
			  'description' => "Returns description of parameters and attributes.",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {} }
			},
            { 'name'        => "instance",
              'request'     => $self->url."/".$self->name."/{id}",
              'description' => "Submits profile creation",
              'example'     => [ $self->url."/".$self->name."/mgm4447943.3?source=RefSeq&format=biom",
                               'retrieve BIOM profile of RefSeq annotations' ],
              'method'      => "GET",
              'type'        => "asynchronous",
              'attributes'  => $self->{submit},
              'parameters'  => {
                  'options' => {
                      'condensed' => ['boolean', 'if true, return condensed profile (integer ids for annotations, non-lca only)'],
                      'retry'     => ['int', 'force rerun and set retry number, default is zero - no retry'],
                      ## mgrast and lca formats saved as permanent shock node
                      'format'    => ['cv', [['mgrast','compressed json format (default)'],
                                             ['lca', 'compressed json format with LCA annotations'],
                                             ['biom','BIOM json format']]],
                      'source'    => ['cv', $self->{sources}],
                      'version'   => ['integer', 'M5NR version, default is '.$self->{m5nr_default}],
                      'verbosity' => ['cv', [['full','returns all data (default)'],
                                             ['minimal','returns only minimal information']]]
				  },
                  'required' => { "id" => ["string", "unique object identifier"] },
                  'body'     => {} }
            },
            { 'name'        => "status",
              'request'     => $self->url."/".$self->name."/status/{uuid}",
              'description' => "Return profile status and/or results",
	          'example'     => [ $self->url."/".$self->name."/status/4dac8fcf-aa46-4177-b30f-db3933462ed3",
				                 "Return profile status and/or results" ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->{status},
              'parameters'  => {
                  'options' => {
                      'verbosity' => ['cv', [['full','returns all data (default)'],
                                             ['minimal','returns only minimal information']]]
				  },
                  'required' => { "uuid" => ["string", "RFC 4122 UUID for process"] },
                  'body'     => {} }
            }
        ]
	};
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (scalar(@{$self->rest}) == 1) {
        $self->submit($self->rest->[0]);
    } elsif ((scalar(@{$self->rest}) > 1) && ($self->rest->[0] eq 'status')) {
        $self->status($self->rest->[1]);
    } else {
        $self->info();
    }
}

sub status {
    my ($self, $uuid, $node) = @_;
    
    my $verbosity = $self->cgi->param('verbosity') || "full";
    # get node
    if ($uuid) {
        $node = $self->get_shock_node($uuid, $self->mgrast_token);
    }
    if (! $node) {
        $self->return_data( {"ERROR" => "unable to retrieve profile: missing from shock"}, 500 );
    }
    if (! $uuid) {
        $uuid = $node->{id};
    }
    my $obj = $self->status_report_from_node($node, "processing");
    if ($node->{file}{name} && $node->{file}{size}) {
        $obj->{status} = "done";
        if ($verbosity eq "full") {
            my ($content, $err) = $self->get_shock_file($uuid, undef, $self->mgrast_token);
            if ($err) {
                $self->return_data( {"ERROR" => "unable to retrieve profile: ".$err}, 500 );
            }
            $obj->{data} = $self->json->decode($content);
        }
    }
    $self->return_data($obj);
}

sub submit {
    my ($self, $tempid) = @_;
    
    # check id format
    my $mid = $self->idresolve($tempid);
    my ($id) = $mid =~ /^mgm(\d+\.\d+)$/;
    unless ($id) {
        $self->return_data( {"ERROR" => "invalid id format: ".$tempid}, 400 );
    }
    # get database / data
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $tempid does not exist"}, 404 );
    }
    $job = $job->[0];
    unless ($job->viewable) {
        $self->return_data( {"ERROR" => "id $tempid is still processing and unavailable"}, 404 );
    }
    # check rights
    unless ($job->{public} || exists($self->rights->{$id}) || ($self->user && $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    my $mgid  = 'mgm'.$id;
    my $jobid = $job->{job_id};
    
    # get paramaters
    my $version   = $self->check_version($self->cgi->param('version'));
    my $source    = $self->cgi->param('source') || 'RefSeq';
    my $condensed = ($self->cgi->param('condensed') && ($self->cgi->param('condensed') ne 'false')) ? 'true' : 'false';
    my $format    = $self->cgi->param('format') || 'mgrast';
    my $retry     = $self->cgi->param('retry') ? int($self->cgi->param('retry')) : 0;
    my $debug     = $self->cgi->param('debug') ? 1 : 0;
    unless (($retry =~ /^\d+$/) && ($retry > 0)) {
        $retry = 0;
    }
    
    if ($format eq 'lca') {
        $source    = 'LCA';
        $condensed = 'false';
    } else {
        # validate type / source
        my $all_srcs = {};
        if ($job->{sequence_type} eq "Amplicon") {
            map { $all_srcs->{$_} = 1 } @{$self->source_by_type('rna')};
        } elsif ($job->{sequence_type} eq "Metabarcode") {
            map { $all_srcs->{$_} = 1 } @{$self->source_by_type('protein')};
        } else {
            map { $all_srcs->{$_} = 1 } @{$self->source_by_type('protein')};
            map { $all_srcs->{$_} = 1 } @{$self->source_by_type('rna')};
            map { $all_srcs->{$_} = 1 } @{$self->source_by_type('ontology')};
        }
        unless (exists $all_srcs->{$source}) {
            $self->return_data( {"ERROR" => "invalid source for profile: ".$source." - valid types are [".join(", ", keys %$all_srcs)."]"}, 400 );
        }
    }
    
    # check for static feature profile node from shock
    # delete if doing retry
    my $squery = {
        id => $mgid,
        data_type => 'profile'
    };
    my $snodes = $self->get_shock_query($squery, $self->mgrast_token);
    if ($snodes && (@$snodes > 0)) {
        $self->check_static_profile($snodes, $source, $condensed, $version, $retry);
    }
    
    # check if temp profile compute node is in shock
    # this only catches profiles that are currently being created
    my $tquery = {
        type => "temp",
        url_id => $self->url_id,
        owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
        data_type => "profile"
    };
    my $tnodes = $self->get_shock_query($tquery, $self->mgrast_token);
    if ($tnodes && (@$tnodes > 0)) {
        if ($retry) {
            foreach my $n (@$tnodes) {
                $self->delete_shock_node($n->{id}, $self->mgrast_token);
            }
        } else {
            my $obj = $self->status_report_from_node($tnodes->[0], "submitted");
            $self->return_data($obj);
        }
    }
    
    # test cassandra access
    my $ctest = $self->cassandra_test("job");
    unless ($ctest) {
        $self->return_data( {"ERROR" => "unable to connect to metagenomics analysis database"}, 500 );
    }
    
    # need to create new temp node
    $tquery->{row_total} = 0;
    $tquery->{progress} = {
        completed => 0,
        queried   => 0,
        found     => 0
    };
    $tquery->{parameters} = {
        id          => $mgid,
        job_id      => $jobid,
        resource    => "profile",
        source      => $source,
        source_type => $self->type_by_source($source) || undef,
        format      => $format,
        retry       => $retry,
        condensed   => $condensed,
        version     => $version
    };
    my $expire = ($format =~ /^(mgrast|lca)$/) ? "1D" : "7D";
    my $node = $self->set_shock_node($mgid.'.json', undef, $tquery, $self->mgrast_token, undef, undef, $expire);
    
    # debug - run synchronously
    if ($debug) {
        print STDERR Dumper($node);
        $self->create_profile($id, $node, $tquery->{parameters});
        $self->return_data($node);
    }
    
    # asynchronous call, fork the process
    my $pid = fork();
    # child - compute data and dump it
    if ($pid == 0) {
        close STDERR;
        close STDOUT;
        $self->create_profile($id, $node, $tquery->{parameters});
        exit 0;
    }
    # parent - end html session
    else {
        my $obj = $self->status_report_from_node($node, "submitted");
        $self->return_data($obj);
    }
}

# reformat the data into the requested output format
sub create_profile {
    my ($self, $id, $node, $param) = @_;
    
    # get data
    my $master = $self->connect_to_datasource();
    my $job  = $master->Job->get_objects( {metagenome_id => $id} );
    my $data = $job->[0];
    
    # cassandra handle
    my $mgcass = $self->cassandra_profile($param->{version});
    
    ### create profile
    # store it in shock permanently if mgrast / lca format
    $param->{swap} = $self->to_swap($data);
    my $attr = undef;
    if ($param->{format} =~ /^(mgrast|lca)$/) {
        $attr = {
            id            => 'mgm'.$id,
            job_id        => $data->{job_id},
            created       => $data->{created_on},
            name          => $data->{name},
            owner         => 'mgu'.$data->{owner},
            sequence_type => $data->{sequence_type},
            status        => $data->{public} ? 'public' : 'private',
            project_id    => undef,
            project_name  => undef,
            type          => 'metagenome',
            data_type     => 'profile',
            format        => $param->{format},
            source        => $param->{source},
            row_total     => 0,
            retry         => $param->{retry},
            condensed     => $param->{condensed},
            version       => $param->{version},
            file_format   => 'json'
        };
        eval {
            my $proj = $data->primary_project;
            if ($proj->{id}) {
                $attr->{project_id} = 'mgp'.$proj->{id};
                $attr->{project_name} = $proj->{name};
            }
        };
    }
    
    # set shock
    my $token = $self->mgrast_token;
    $mgcass->set_shock($token);
    
    ### saves output file or error message in shock
    $mgcass->compute_profile($node, $param, $attr);
    $mgcass->close();
    return undef;
}

sub status_report_from_node {
    my ($self, $node, $status) = @_;
    my $report = {
        id      => $node->{id},
        status  => $status,
        url     => $self->url."/".$self->name."/status/".$node->{id},
        size    => $node->{file}{size},
        created => $node->{file}{created_on},
        retry   => 0,
        md5     => $node->{file}{checksum}{md5} ? $node->{file}{checksum}{md5} : ""
    };
    $report->{progress} = {
        started => $node->{created_on},
        updated => ($node->{last_modified} eq "0001-01-01T00:00:00Z") ? $node->{created_on} : $node->{last_modified},
        queried => $node->{attributes}{progress}{queried} || $node->{attributes}{md5_queried} || $node->{attributes}{lca_queried} || 0,
        found   => $node->{attributes}{progress}{found} || $node->{attributes}{md5_found} || $node->{attributes}{lca_found} || 0
    };
    if (exists $node->{attributes}{retry}) {
        $report->{retry} = $node->{attributes}{retry};
    }
    if (exists $node->{attributes}{row_total}) {
        $report->{rows} = $node->{attributes}{row_total};
    }
    if (exists $node->{attributes}{parameters}) {
        $report->{parameters} = $node->{attributes}{parameters};
    } else {
        # is permanent shock node
        $report->{parameters} = {
            id         => $node->{attributes}{id},
            source     => $node->{attributes}{source},
            format     => $node->{attributes}{format},
            condensed  => $node->{attributes}{condensed},
            version    => $node->{attributes}{version}
        };
    }
    return $report;
}

sub check_static_profile {
    my ($self, $nodes, $source, $condensed, $version, $retry) = @_;
    
    # sort results by newest to oldest
    my @sorted = sort { $b->{file}{created_on} cmp $a->{file}{created_on} } @$nodes;
    
    foreach my $n (@sorted) {
        if ( $n->{attributes}{condensed} &&
             ($n->{attributes}{condensed} eq $condensed) &&
             $n->{attributes}{version} &&
             (int($n->{attributes}{version}) == int($version)) &&
             $n->{attributes}{source} &&
             ($n->{attributes}{source} eq $source) ) {
            if ($retry) {
                $self->delete_shock_node($n->{id}, $self->mgrast_token);
            } else {
                $self->status(undef, $n);
            }
        }
    }
}

sub check_version {
    my ($self, $version) = @_;
    
    unless ($version) {
        $version = $self->{m5nr_default};
    }
    unless ($version =~ /^\d+$/) {
        $self->return_data({"ERROR" => "invalid version was entered ($version). Must be an integer"}, 404);
    }
    $version = $version * 1;
    ## currently only support version 1
    unless ($version == 1) {
        $self->return_data({"ERROR" => "invalid version was entered ($version). Currently only version 1 is supported"}, 404);
    }
    #unless (exists $self->{m5nr_version}{$version}) {
    #    $self->return_data({"ERROR" => "invalid version was entered ($version). Please use one of: ".join(", ", keys %{$self->{m5nr_version}})}, 404);
    #}
    return $version;
}

1;
