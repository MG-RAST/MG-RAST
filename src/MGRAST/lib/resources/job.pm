package resources::job;

use strict;
use warnings;
no warnings('once');

use URI::Encode qw(uri_encode uri_decode);
use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use List::MoreUtils qw(any uniq);
use Scalar::Util qw(looks_like_number);
use StreamingUpload;

use MGRAST::Metadata;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "job";
    $self->{job_actions} = {
			    reserve  => 1,
			    create   => 1,
			    submit   => 1,
			    resubmit => 1,
			    archive  => 1,
			    share    => 1,
			    public   => 1,
			    viewable => 1,
			    rename   => 1,
			    delete   => 1,
			    solr     => 1,
			    abundance  => 1,
			    addproject => 1,
			    statistics => 1,
			    attributes => 1,
			    changesequencetype => 1,
			    publicationadjust => 1
    };
    $self->{attributes} = {
        reserve => { "timestamp"     => [ 'date', 'time the metagenome was first reserved' ],
                     "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                     "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                     "kbase_id"      => [ "string", "unique KBase metagenome identifier" ] },
        create => { "timestamp" => [ 'date', 'time the metagenome was first reserved' ],
                    "options"   => [ "string", "job pipeline option string" ],
                    "job_id"    => [ "int", "unique MG-RAST job identifier" ] },
        submit => { "awe_id" => [ "string", "ID of AWE job" ],
                    "log"    => [ "string", "log of sumbission" ] },
        delete => { "deleted" => [ 'boolean', 'the metagenome is deleted' ],
                    "error"   => [ "string", "error message if unable to delete" ] },
        addproject => { "project_id"   => [ "string", "unique MG-RAST project identifier" ],
                        "project_name" => [ "string", "MG-RAST project name" ],
                        "status"       => [ 'string', 'status of action' ] },
        data  => { "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                   "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                   "data"          => [ 'hash', 'key value pairs of job data' ] },
        change => { "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                    "job_id"        => [ "int", "unique MG-RAST job identifier" ],
                    "status"        => [ 'string', 'status of action' ] },
        kb2mg => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of KBase id to MG-RAST id' ] },
        mg2kb => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of MG-RAST id to KBase id' ] }
    };
    $self->{create_param} = {
        'metagenome_id' => ["string", "unique MG-RAST metagenome identifier"],
        'input_id'      => ["string", "shock node id of input sequence file (optional)"],
        'submission'    => ["string", "unique submission id (optional)"]
    };
    my @input_stats = map { substr($_, 0, -4) } grep { $_ =~ /_raw$/ } @{$self->seq_stats};
    map { $self->{create_param}{$_} = ['float', 'sequence statistic'] } grep { $_ !~ /drisee/ } @input_stats;
    map { $self->{create_param}{$_} = ['string', 'pipeline option'] } @{$self->pipeline_opts};
    $self->{create_param}{sequence_type} = [
        "cv", [["WGS", "whole genome shotgun sequencing"],
               ["Amplicon", "amplicon rRNA sequencing"],
               ["Metabarcode", "metabarcode sequencing"],
               ["MT", "metatranscriptome sequencing"]]
    ];
    @{$self->{taxa}} = grep { $_->[0] !~ /strain/ } @{$self->hierarchy->{organism}};
    
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		            'url' => $self->url."/".$self->name,
		            'description' => "Resource for creating and querying MG-RAST jobs.",
		            'type' => 'object',
		            'documentation' => $self->url.'/api.html#'.$self->name,
		            'requests' => [
		                { 'name'        => "info",
				          'request'     => $self->url."/".$self->name,
				          'description' => "Returns description of parameters and attributes.",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => "self",
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {} }
						},
				        { 'name'        => "reserve",
				          'request'     => $self->url."/".$self->name."/reserve",
				          'description' => "Reserve IDs for MG-RAST job.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{reserve},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {
							                     "kbase_id"  => ['boolean', "if true create KBase ID, default is false."],
							                     "name"      => ["string", "name of metagenome (required)"],
							                     "input_id"  => ["string", "shock node id of input sequence file (optional)"],
							                     "file"      => ["string", "name of sequence file"],
							                     "file_size" => ["string", "byte size of sequence file"],
          							             "file_checksum" => ["string", "md5 checksum of sequence file"] } }
						},
						{ 'name'        => "create",
				          'request'     => $self->url."/".$self->name."/create",
				          'description' => "Create an MG-RAST job with input reserved ID, sequence stats, and pipeline options.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{create},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => $self->{create_param} }
						},
						{ 'name'        => "submit",
				          'request'     => $self->url."/".$self->name."/submit",
				          'description' => "Submit a MG-RAST job to AWE pipeline.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{submit},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "input_id" => ["string", "shock node id of input sequence file"] } }
						},
						{ 'name'        => "resubmit",
				          'request'     => $self->url."/".$self->name."/resubmit",
				          'description' => "Re-submit an existing MG-RAST job to AWE pipeline.",
				          'method'      => "PUT",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{submit},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "awe_id" => ["string", "awe job id of original job"] } }
						},
						{ 'name'        => "archive",
                          'request'     => $self->url."/".$self->name."/archive",
                          'description' => "Archive MG-RAST analysis-pipeline document and logs from AWE into Shock",
                          'method'      => "POST",
                          'type'        => "synchronous",
                          'attributes'  => $self->{attributes}{change},
                          'parameters'  => { 'options'  => {},
                                             'required' => {},
                                             'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
                                                             "awe_id" => ["string", "AWE ID of MG-RAST job"],
                                                             "force"  => ["boolean", "if true, recreate document in Shock from AWE."],
				                                             "delete" => ["boolean", "if true (and user is admin) delete original document from AWE on completion."] } }
                        },
						{ 'name'        => "share",
				          'request'     => $self->url."/".$self->name."/share",
				          'description' => "Share metagenome with another user.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "shared"  => ['list', ['string', 'user metagenome shared with']] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "user_id"       => ["string", "unique user identifier to share with"],
							                                 "user_email"    => ["string", "user email to share with"],
							                                 "edit"          => ["boolean", "if true edit rights shared, else (default) view rights only"] } }
						},
						{ 'name'        => "public",
				          'request'     => $self->url."/".$self->name."/public",
				          'description' => "Change status of metagenome to public.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "public"  => ['boolean', 'the metagenome is public'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"] } }
						},
					   { 'name'        => "check_mixs",
				          'request'     => $self->url."/".$self->name."/check_mixs",
				          'description' => "Check if a metagenome has MiXS data.",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => { "has_mixs"  => ['boolean', 'the metagenome has MiXS data'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"] } }
						},
						{ 'name'        => "viewable",
				          'request'     => $self->url."/".$self->name."/viewable",
				          'description' => "Change the view state of metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "viewable"  => ['boolean', 'the metagenome is viewable'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "viewable" => ["boolean", "true: make viewable, false: make hidden, default: true"] } }
						},
						{ 'name'        => "rename",
				          'request'     => $self->url."/".$self->name."/rename",
				          'description' => "Change the name of metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "name" => ["string", "new name of metagenome"] } }
						},
						{ 'name'        => "delete",
				          'request'     => $self->url."/".$self->name."/delete",
				          'description' => "Delete metagenome.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{delete},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
     							                             "reason" => ["string", "reason for deleting metagenome"] } }
						},
						{ 'name'        => "addproject",
				          'request'     => $self->url."/".$self->name."/addproject",
				          'description' => "Add exisiting MG-RAST job to existing MG-RAST project.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{addproject},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "project_id" => ["string", "unique MG-RAST project identifier"] } }
						},
						{ 'name'        => "statistics",
				          'request'     => $self->url."/".$self->name."/statistics/{id}",
				          'description' => "Return current job statistics",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => {},
							                 'required' => { "id" => ["string", "unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "statistics",
				          'request'     => $self->url."/".$self->name."/statistics",
				          'description' => "Add to job statistics",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "statistics"    => ["hash", "key value pairs for new statistics"] } }
						},
						{ 'name'        => "attributes",
				          'request'     => $self->url."/".$self->name."/attributes/{id}",
				          'description' => "Return current job attributes",
				          'method'      => "GET",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => {},
							                 'required' => { "id" => ["string","unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "attributes",
				          'request'     => $self->url."/".$self->name."/attributes",
				          'description' => "Add to job attributes",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
     							                             "attributes"    => ["hash", "key value pairs for new attributes"] } }
						},
						{ 'name'        => "abundance",
				          'request'     => $self->url."/".$self->name."/abundance/{id}",
				          'description' => "Get abundances for different annotations",
				          'method'      => "GET",
				          'type'        => "asynchronous",
				          'attributes'  => $self->{attributes}{data},
				          'parameters'  => { 'options'  => { "level"   => ["cv", $self->{taxa}],
				                                             "ann_ver" => ["int", 'M5NR annotation version, default '.$self->{m5nr_default}],
				                                             'retry'   => ['int', 'force rerun and set retry number, default is zero - no retry'],
                                                             "type"    => ["cv", [["all", "return abundances for all annotations"],
                                                                                  ["organism", "return abundances for organism annotations"],
                                                                                  ["ontology", "return abundances for ontology annotations"],
                                                                                  ["function", "return abundances for function annotations"]] ] },
							                 'required' => { "id" => ["string","unique MG-RAST metagenome identifier"] },
							                 'body'     => {} }
						},
						{ 'name'        => "abundance",
				          'request'     => $self->url."/".$self->name."/abundance",
				          'description' => "load abundances",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "ann_ver" => ["int", 'M5NR annotation version, default '.$self->{m5nr_default}],
							                                 "count"   => ["int", "total rows loaded, required for data integrity check with 'end' action"],
							                                 "type"    => ["cv", [["md5", "md5 abundace data"],
							                                                      ["lca", "lca abundace data"]] ],
							                                 "action"  => ["cv", [["start", "flag job as loading"],
							                                                      ["load", "load data to table"],
							                                                      ["end", "flag job as completed"],
							                                                      ["status", "get state of loading job"]] ],
							                                 "data"    => ["list", ["float", "md5 abundance summary data"]] } }
						},
						{ 'name'        => "solr",
				          'request'     => $self->url."/".$self->name."/solr",
				          'description' => "Update job data in solr",
				          'method'      => "POST",
				          'type'        => "asynchronous",
				          'attributes'  => $self->{attributes}{change},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "rebuild"       => ["boolean", "re-compute all statistics, default is to not compute if exists"],
							                                 'retry'         => ['int', 'force rerun and set retry number, default is zero - no retry'],
							                                 "debug"         => ["boolean", "return solr post data instead of actually posting it"],
							                                 "ann_ver"       => ["int", 'M5NR annotation version, default '.$self->{m5nr_default}],
     							                             "solr_data"     => ["hash", "key value pairs for solr data"] } }
						},
						{ 'name'        => "kb2mg",
				          'request'     => $self->url."/".$self->name."/kb2mg",
				          'description' => "Return a mapping of KBase ids to MG-RAST ids",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{kb2mg},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {"ids" => ['list', ['string', 'KBase ids']]} }
						},
						{ 'name'        => "mg2kb",
				          'request'     => $self->url."/".$self->name."/mg2kb",
				          'description' => "Return a mapping of MG-RAST ids to KBase ids",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{mg2kb},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {"ids" => ['list', ['string', 'MG-RAST ids']]} }
						},
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
    } elsif (($self->method eq 'GET') && (scalar(@{$self->rest}) > 1)) {
        $self->job_data($self->rest->[0], $self->rest->[1]);
    } elsif (exists $self->{job_actions}{ $self->rest->[0] }) {
        $self->job_action($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'kb2mg') || ($self->rest->[0] eq 'mg2kb')) {
        $self->id_lookup($self->rest->[0]);
    } else {
        $self->info();
    }
}

sub job_data {
    my ($self, $type, $tempid) = @_;
    
    my $master = $self->connect_to_datasource();
    # check id format
    my $mgid = $self->idresolve($tempid);
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if (! $id) {
        $self->return_data( {"ERROR" => "invalid id format: ".$tempid}, 400 );
    }
    # check rights
    unless ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $id) || $self->user->has_star_right('view', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for metagenome $mgid"}, 401 );
    }
    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $mgid does not exist"}, 404 );
    }
    $job = $job->[0];
    
    if ($type eq "statistics") {
        $self->return_data({
            metagenome_id => 'mgm'.$job->{metagenome_id},
            job_id        => $job->{job_id},
            data          => $job->stats()
        });
      } elsif ($type eq "check_mixs") {
	my $mddb = MGRAST::Metadata->new();
	my $errors = $mddb->verify_job_metadata($job);
	if (scalar(@$errors)) {
	  $self->return_data({ "has_mixs" => 0, "errors" => $errors }, 200);
	} else {
	  $self->return_data({ "has_mixs" => 1 }, 200);
	}
    } elsif ($type eq "attributes") {
        $self->return_data({
            metagenome_id => 'mgm'.$job->{metagenome_id},
            job_id        => $job->{job_id},
            data          => $job->data()
        });
    } elsif ($type eq "abundance") {
        my $taxa  = $self->cgi->param('level') || "";
        my $ann   = $self->cgi->param('type') || "all";
        my $ver   = $self->cgi->param('ann_ver') || $self->{m5nr_default};
        my $retry = int($self->cgi->param('retry')) || 0;
        # validate parameters
        unless (($retry =~ /^\d+$/) && ($retry > 0)) {
            $retry = 0;
        }
        my %valid_tax = map { $_ => 1 } @{$self->{taxa}};
        my %valid_ann = (all => 1, organism => 1, ontology => 1, function => 1);        
        if ($taxa && (! exists($valid_tax{$taxa}))) {
            return ({"ERROR" => "invalid group_level for organism - valid types are [".join(", ", map {$_->[0]} @{$self->{taxa}})."]"}, 404);
        }
        if (! exists($valid_ann{$ann})) {
            $self->return_data( {"ERROR" => "invalid job abundance type: $ann"}, 400 );
        }
        # asynchronous call, fork the process and return the process id.
        # caching is done with shock, not memcache
        my $attr = {
            type => "temp",
            url_id => $self->url_id,
            owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
            data_type => "abundance"
        };
        # already cashed in shock - say submitted in case its running
        my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
        if ($nodes && (@$nodes > 0)) {
            if ($retry) {
                foreach my $n (@$nodes) {
                    $self->delete_shock_node($n->{id}, $self->mgrast_token);
                }
            } else {
                $self->return_data({"status" => "submitted", "id" => $nodes->[0]->{id}, "url" => $self->url."/status/".$nodes->[0]->{id}});
            }
        }
        
        # test cassandra access
        my $ctest = $self->cassandra_test("job");
        unless ($ctest) {
            $self->return_data({"ERROR" => "unable to connect to metagenomics analysis database"}, 500);
        }
        
        # need to create new node and fork
        $attr->{progress} = {
            completed => 'none',
            queried   => 0,
            found     => 0
        };
        $attr->{parameters} = {
            id       => 'mgm'.$job->{metagenome_id},
            job_id   => $job->{job_id},
            resource => "job/abundance",
            level    => $taxa,
            ann_type => $ann,
            version  => $ver,
            retry    => $retry
        };
        my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "3D");
        my $pid = fork();
        # child - get data and POST it
        if ($pid == 0) {
            close STDERR;
            close STDOUT;
            # create DB handels inside child as they break on fork
            $master = $self->connect_to_datasource();
            my $jobj = $master->Job->get_objects( {metagenome_id => $id} );
            $job = $jobj->[0];
            
            my $mgcass = $self->cassandra_abundance($ver);
            my $token = $self->mgrast_token;
            $mgcass->set_shock($token);
            
            # set options
            my $taxa_set = $taxa ? [$taxa] : [map {$_->[0]} reverse @{$self->{taxa}}];
            my $get_org  = (($ann eq "all") || ($ann eq "organism")) ? 1 : 0;
            my $get_fun  = (($ann eq "all") || ($ann eq "function")) ? 1 : 0;
            my $get_ont  = (($ann eq "all") || ($ann eq "ontology")) ? 1 : 0;
            
            # get data
            my $data = {};
            my ($md5_num, $org_map, $fun_map, $ont_map) = @{ $mgcass->all_annotation_abundances($job->{job_id}, $taxa_set, $get_org, $get_fun, $get_ont, $node) };
            if ($md5_num > 0) {
                if ($get_org) {
                    $data->{taxonomy} = {};
                    foreach my $t (keys %{$org_map}) {
                        $data->{taxonomy}{$t} = [ map { [ $_, $org_map->{$t}{$_} ] } keys %{$org_map->{$t}} ];
                    }
                }
                if ($get_fun) {
                    $data->{function} = [ map { [ $_, $fun_map->{$_} ] } keys %{$fun_map} ];
                }
                if ($get_ont) {
                    $data->{ontology} = {};
                    foreach my $s (keys %{$ont_map}) {
                        $data->{ontology}{$s} = [ map { [ $_, $ont_map->{$s}{$_} ] } keys %{$ont_map->{$s}} ];
                    }
                }
            } else {
                $data = {
                    ERROR  => "no md5 hits available",
                    STATUS => 500
                };
            }
            $mgcass->close();
            
            # POST to shock, triggers end of asynch action
            $self->put_shock_file("mgm".$job->{metagenome_id}.".abundance", $data, $node->{id}, $self->mgrast_token);
            exit 0;
        }
        # parent - end html session
        else {
            $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->url."/status/".$node->{id}});
        }
    } else {
        $self->return_data( {"ERROR" => "invalid job data type: $type"}, 400 );
    }
}

sub job_action {
    my ($self, $action) = @_;
    
    my $master = $self->connect_to_datasource();
    unless ($self->user) {
        $self->return_data( {"ERROR" => "Missing authentication"}, 401 );
    }
    
    my $data = {};
    my $post = $self->get_post_data();
    
    # job does not exist yet
    if ($action eq 'reserve') {
        # get from shock node if given
        if (exists $post->{input_id}) {
            my $nodeid = $post->{input_id};
            eval {
                my $node = $self->get_shock_node($nodeid, $self->token, $self->user_auth);
                $post->{file} = $node->{file}{name};
                $post->{file_size} = $node->{file}{size};
                $post->{file_checksum} = $node->{file}{checksum}{md5};
            };
            if ($@ || (! $post)) {
                $self->return_data( {"ERROR" => "unable to obtain sequence file statistics from shock node ".$nodeid}, 500 );
            }
        }
        my @params = ();
        foreach my $p ('name', 'file', 'file_size', 'file_checksum') {
            if (exists $post->{$p}) {
                push @params, $post->{$p};
            } else {
                $self->return_data( {"ERROR" => "Missing required parameter '$p'"}, 404 );
            }
        }
        my $job = $master->Job->reserve_job_id($self->user, $params[0], $params[1], $params[2], $params[3]);
        unless ($job) {
            $self->return_data( {"ERROR" => "Unable to reserve job id"}, 500 );
        }
        my $mgid = 'mgm'.$job->{metagenome_id};
        $data = { timestamp     => strftime("%Y-%m-%dT%H:%M:%S", gmtime),
                  metagenome_id => $mgid,
                  job_id        => $job->{job_id},
                  kbase_id      => (exists($post->{kbase_id}) && $post->{kbase_id}) ? $self->reserve_kbase_id($mgid): undef
        };
    }
    # we have a job in DB, do something
    else {
        # check id format
        unless (defined $post->{metagenome_id}) {
            $post = $self->get_post_data(["metagenome_id", "reason"]);
        }
        unless ($post->{metagenome_id}) {
            $self->return_data( {"ERROR" => "missing metagenome id"}, 400 );
        }
        my $tempid = $self->idresolve($post->{metagenome_id});
        my (undef, $id) = $tempid =~ /^(mgm)?(\d+\.\d+)$/;
        if (! $id) {
            $self->return_data( {"ERROR" => "invalid id format: ".$post->{metagenome_id}}, 400 );
        }
        $post->{metagenome_id} = $tempid;
        
        # check rights
        unless ($self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome'))) {
            $self->return_data( {"ERROR" => "insufficient permissions for metagenome ".$post->{metagenome_id}}, 401 );
        }
        # get data
        my $job = $master->Job->get_objects( {metagenome_id => $id} );
        unless ($job && @$job) {
            $self->return_data( {"ERROR" => "id ".$post->{metagenome_id}." does not exist"}, 404 );
        }
        $job = $job->[0];
        
        if ($action eq 'create') {
            # get from shock node if given
            if (exists $post->{input_id}) {
                my $nodeid = $post->{input_id};
                eval {
                    my $node = $self->get_shock_node($nodeid, $self->token, $self->user_auth);
                    # pull from stats_info and pipeline_info in attributes
                    foreach my $x (('stats_info', 'pipeline_info')) {
                        if (exists($node->{attributes}{$x}) && ref($node->{attributes}{$x})) {
                            foreach my $k (keys %{$node->{attributes}{$x}}) {
                                # only add values that are not already given
                                if (! exists($post->{$k})) {
                                    $post->{$k} = $node->{attributes}{$x}{$k};
                                }
                            }
                        }
                    }
                };
                delete $post->{input_id};
                if ($@ || (! $post)) {
                    $self->return_data( {"ERROR" => "unable to obtain sequence file info from shock node ".$nodeid}, 500 );
                }
            }
            # fix assembly defaults
            if (exists($post->{sequencing_method_guess}) && ($post->{sequencing_method_guess} eq "assembled")) {
                $post->{assembled}    = 'yes';
                $post->{filter_ln}    = 'no';
                $post->{filter_ambig} = 'no';
                $post->{dynamic_trim} = 'no';
                $post->{dereplicate}  = 'no';
                $post->{bowtie}       = 'no';
            }
            # set pipeline defaults if missing
            foreach my $key (@{$self->pipeline_opts}) {
                if (exists($self->pipeline_defaults->{$key}) && (! exists($post->{$key}))) {
                    $post->{$key} = $self->pipeline_defaults->{$key};
                }
            }
            if ($post->{file_type} eq 'fasta') {
                $post->{file_type} = 'fna';
            }
            # fix booleans
            foreach my $key (keys %$post) {
                if ($post->{$key} eq 'yes') {
                    $post->{$key} = 1;
                } elsif ($post->{$key} eq 'no') {
                    $post->{$key} = 0;
                }
            }
            # check params
            delete $post->{metagenome_id};
            foreach my $key (keys %{$self->{create_param}}) {
                if (($key eq 'metagenome_id') || ($key eq 'input_id') || ($key eq 'submission')) {
                    next;
                }
                if (! exists($post->{$key})) {
                    $self->return_data( {"ERROR" => "Missing required parameter '$key'"}, 404 );
                }
            }
            # calculate length trim
        	$post->{max_ln} = int($post->{average_length} + ($post->{filter_ln_mult} * $post->{standard_deviation_length}));
        	$post->{min_ln} = int($post->{average_length} - ($post->{filter_ln_mult} * $post->{standard_deviation_length}));
        	if ($post->{min_ln} < 1) {
        	    $post->{min_ln} = 1;
        	}
            # create job
            $job  = $master->Job->initialize($self->user, $post, $job);
            $data = {
                timestamp => $job->{created_on},
                options   => $job->{options},
                job_id    => $job->{job_id}
            };
        } elsif ($action eq 'publicationadjust') {
            my $prio = $post->{priority};
            my $pmap = {
                "never"       => 1,
                "date"        => 5,
                "6months"     => 10,
                "3months"     => 15,
                "immediately" => 20
            };
            unless ($prio && $pmap->{$prio}) {
                $self->return_data( {"ERROR" => "no / invalid priority given"}, 400 );
            }
            my $awe_id = $post->{awe_id};
            unless ($awe_id) {
                $self->return_data( {"ERROR" => "no awe id given"}, 400 );
            }
            my $master = $self->connect_to_datasource();
            $master->JobAttributes->get_objects({ job => $job, tag => 'priority'})->[0]->value($prio);
            $data = $self->awe_job_action($awe_id, "priority=".$pmap->{$prio}, $self->mgrast_token);

            $self->return_data($data);
        } elsif (($action eq 'submit') || ($action eq 'resubmit')) {
            # first check if already exists
            my ($has_id, $has_state) = $self->awe_has_job($job->{job_id}, $self->mgrast_token);
            if ($has_id && ($has_state ne 'deleted')) {
                $self->return_data( {"ERROR" => "This metagenome already exists in AWE: name=".$job->{job_id}.", id=$has_id, state=$has_state"}, 422 );
            }
            my $cmd;
            if ($action eq 'resubmit') {
                $cmd = $Conf::resubmit_to_awe." --use_docker --job_id ".$job->{job_id}." --shock_url ".$Conf::shock_url." --awe_url ".$Conf::awe_url;
                if ($post->{awe_id}) {
                    $cmd .= " --awe_id ".$post->{awe_id};
                }
            } else {
                my $jdata = $job->data();
                $cmd = $Conf::submit_to_awe." --use_docker --job_id ".$job->{job_id}." --input_node ".$post->{input_id}." --shock_url ".$Conf::shock_url." --awe_url ".$Conf::awe_url;
                if (exists $jdata->{submission}) {
                    $cmd .= " --submit_id ".$jdata->{submission};
                }
            }
            my $aid = "";
            my @log = `$cmd 2>&1`;
            chomp @log;
            my @err = grep { $_ =~ /^ERROR/ } @log;
            if (@err) {
                # AWE sometimes returns an error but still submits the job
                ($has_id, $has_state) = $self->awe_has_job($job->{job_id}, $self->mgrast_token);
                if ($has_id) {
                    $aid = $has_id;
                } else {
                    $self->return_data( {"ERROR" => join("\n", @log)}, 400 );
                }
            }
            my @aweid = grep { $_ =~ /^awe job/ } @log;
            if (@aweid && (! $aid)) {
                (undef, $aid) = split(/\t/, $aweid[0]);
            }
            if ($aid) {
                $data = {
                    awe_id => $aid,
                    log    => join("\n", @log)
                };
            } else {
                $self->return_data( {"ERROR" => "Unknown error, missing AWE job ID:\n".join("\n", @log)}, 500 );
            }
        } elsif ($action eq 'archive') {
            my $awe_id = $post->{awe_id} || undef;
            my $force  = $post->{force} ? 1 : 0;
            my $delete = $post->{delete} ? 1 : 0;
            unless ($awe_id) {
                $self->return_data( {"ERROR" => "Missing required parameter awe_id (AWE job ID)"}, 404 );
            }
            $data = {
                metagenome_id => $post->{metagenome_id},
                job_id        => $job->{job_id},
                status        => 'incomplete'
            };
            # test if id already archived
            my $squery = {
                id         => $post->{metagenome_id},
                data_type  => 'awe_workflow'
            };
            my $nodes = $self->get_shock_query($squery, $self->mgrast_token);
            # not in shock or force to re-archive
            if ((scalar(@$nodes) == 0) || $force) {
                my $awe_doc = $self->get_awe_full_document($awe_id, $self->mgrast_token);
                if (! $awe_doc) {
                    $self->return_data( {"ERROR" => "Unable to retrieve pipeline document for ID $awe_id"}, 500 );
                }
                if ($awe_doc->{info}{userattr}{id} ne $post->{metagenome_id}) {
                    $self->return_data( {"ERROR" => "Inputed MG-RAST ID does not match pipeline document"}, 404 );
                }
                my $p_version  = $job->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
                my $shock_attr = {
                    id            => $post->{metagenome_id},
                    job_id        => $job->{job_id},
                    created       => $job->{created_on},
                    name          => $job->{name},
                    owner         => 'mgu'.$job->{owner},
                    sequence_type => $job->{sequence_type},
                    status        => $job->{public} ? 'public' : 'private',
                    project_id    => undef,
                    project_name  => undef,
                    type          => 'metagenome',
                    data_type     => 'awe_workflow',
                    workflow_type => 'full',
                    awe_id        => $awe_id,
                    file_format   => 'json',
                    pipeline_version => $p_version
                };
                eval {
                    my $proj = $job->primary_project;
                    if ($proj->{id}) {
                        $shock_attr->{project_id} = 'mgp'.$proj->{id};
                        $shock_attr->{project_name} = $proj->{name};
                    }
                };
                # POST to shock
                my $job_node = $self->set_shock_node($post->{metagenome_id}.'.awe.json', $awe_doc, $shock_attr, $self->mgrast_token);
                if ($job_node && $job_node->{id}) {
                    $data->{status} = 'archived';
                }
            }
            # archive was already in shock
            if (scalar(@$nodes) > 0) {
                 if ($force && ($data->{status} eq 'archived')) {
                     # new archive was force created - delete old nodes
                     foreach my $n (@$nodes) {
                         $self->delete_shock_node($n->{id}, $self->mgrast_token);
                     }
                 } else {
                     # archive already exists / nothing was done
                     $data->{status} = 'archived';
                 }
            }
            # delete if success and requested and user is admin
            if (($data->{status} eq 'archived') && $delete && $self->user->is_admin('MGRAST')) {
                $self->awe_job_action($awe_id, "delete", $self->mgrast_token);
            }
        } elsif ($action eq 'share') {
            # get user to share with
            my $share_user = undef;
            if ($post->{user_id}) {
                my (undef, $uid) = $post->{user_id} =~ /^(mgu)?(\d+)$/;
                $share_user = $master->User->init({ _id => $uid });
            } elsif ($post->{user_email}) {
                $share_user = $master->User->init({ email => $post->{user_email} });
            } else {
                $self->return_data( {"ERROR" => "Missing required parameter user_id or user_email"}, 404 );
            }
            unless ($share_user && ref($share_user)) {
                $self->return_data( {"ERROR" => "Unable to find user to share with"}, 404 );
            }
            # share rights if not owner
            unless ($share_user->_id eq $job->owner->_id) {
                my @rights = ('view');
                my @acls = ('read');
                if ($post->{edit}) {
                    push @rights, 'edit';
                    push @acls, 'write';
                }
                # update mysql db
                foreach my $name (@rights) {
                    my $right_query = {
                        name => $name,
                	    data_type => 'metagenome',
                	    data_id => $job->metagenome_id,
                	    scope => $share_user->get_user_scope
                    };
                    unless(scalar( @{$master->Rights->get_objects($right_query)} )) {
                        $right_query->{granted} = 1;
                        $right_query->{delegated} = 1;
                        my $right = $master->Rights->create($right_query);
            	        unless (ref $right) {
            	            $self->return_data( {"ERROR" => "Failed to create ".$name." right in the user database, aborting."}, 500 );
            	        }
                    }
                }
                # update shock nodes
                my $nodes = $self->get_shock_query({'id' => 'mgm'.$job->{metagenome_id}}, $self->mgrast_token);
                foreach my $n (@$nodes) {
                    if ($n->{attributes}{type} ne 'metagenome') {
                        next;
                    }
                    foreach my $acl (@acls) {
                        $self->edit_shock_acl($n->{id}, $self->mgrast_token, 'put', $acl);
                    }
                }
            }
            # get all who can view / skip owner
            my $view_query = {
                name => 'view',
        	    data_type => 'metagenome',
        	    data_id => $job->metagenome_id
            };
            my $shared = [];
            my $owner_user = $master->User->init({ _id => $job->owner->_id });
            my $view_rights = $master->Rights->get_objects($view_query);
            foreach my $vr (@$view_rights) {
                next if (($owner_user->get_user_scope->_id eq $vr->scope->_id) || ($vr->scope->name =~ /^token\:/));
                push @$shared, $vr->scope->name_readable;
            }
            $data = { shared => $shared };
        } elsif ($action eq 'public') {
            # check if the metadata is ok
            my $mddb = MGRAST::Metadata->new();
            my $errors = $mddb->verify_job_metadata($job);
            if (scalar(@$errors)) {
                $self->return_data({ "ERROR" => "insufficient metadata for publication", "errors" => $errors }, 400);
            }
	    
            # update shock nodes
            my $nodes = $self->get_shock_query({'id' => 'mgm'.$job->{metagenome_id}}, $self->mgrast_token);
            foreach my $n (@$nodes) {
                my $attr = $n->{attributes};
                if ($attr->{type} ne 'metagenome') {
                    next;
                }
                $attr->{status} = 'public';
                $self->update_shock_node($n->{id}, $attr, $self->mgrast_token);
                $self->edit_shock_public_acl($n->{id}, $self->mgrast_token, 'put', 'read');
            }
            # update mysql db
            $job->public(1);
            $job->set_publication_date();
            # update elasticsearch
            $self->upsert_to_elasticsearch_metadata($job->metagenome_id);
            $data = { public => $job->public ? 1 : 0 };
        } elsif ($action eq 'viewable') {
            my $state = 1;
            if (exists($post->{viewable}) && defined($post->{viewable}) && (! $post->{viewable})) {
                $state = 0;
            }
            # update db
            $job->viewable($state);
            $data = { viewable => $job->viewable ? 1 : 0 };
        } elsif ($action eq 'rename') {
            $data = {
                metagenome_id => 'mgm'.$job->metagenome_id,
                job_id        => $job->job_id
            };
            if ($post->{name}) {
                $job->name($post->{name});
                $self->upsert_to_elasticsearch_metadata($job->metagenome_id);
                $data->{status} = 1;
            } else {
                $data->{status} = 0;
            }
	  } elsif ($action eq 'changesequencetype') {
          $job->sequence_type($post->{sequence_type});
          $self->upsert_to_elasticsearch_metadata($job->metagenome_id);
          $data = {
              metagenome_id => 'mgm'.$job->metagenome_id,
		      job_id        => $job->job_id,
		      sequence_type => $post->{sequence_type}
          };
	  } elsif ($action eq 'delete') {
          # Auf Wiedersehen!
          my $reason = $post->{reason} || "";
          my $mgid = 'mgm'.$job->{metagenome_id};
          eval {
              my ($status, $message) = $job->user_delete($self->user, $reason);
              $job->delete();
              $self->delete_from_elasticsearch($mgid);
              $data = {
                  deleted => $status,
                  error   => $message
              };
          };
        } elsif ($action eq 'addproject') {
            # check id format
            my (undef, $pid) = $post->{project_id} =~ /^(mgp)?(\d+)$/;
            if (! $pid) {
                $self->return_data( {"ERROR" => "invalid id format: ".$post->{project_id}}, 400 );
            }
            # check rights
            unless ($self->user->has_right(undef, 'edit', 'project', $pid) || $self->user->has_star_right('edit', 'project')) {
                $self->return_data( {"ERROR" => "insufficient permissions for project ".$post->{project_id}}, 401 );
            }
            # get data
            my $project = $master->Project->get_objects( {id => $pid} );
            unless ($project && @$project) {
                $self->return_data( {"ERROR" => "id ".$post->{project_id}." does not exists"}, 404 );
            }
            $project = $project->[0];
            # add it
            my $status = $project->add_job($job);
            $data = {
                project_id   => "mgp".$project->{id},
                project_name => $project->{name},
                status       => $status
            };
        } elsif (($action eq "statistics") || ($action eq "attributes")) {
            my $status = $job->set_job_data($action, $post->{$action});
            $data = {
                metagenome_id => 'mgm'.$job->metagenome_id,
                job_id        => $job->job_id,
                status        => $status
            };
        } elsif ($action eq "abundance") {
            my $ver    = $post->{ann_ver} || $self->{m5nr_default};
            my $type   = $post->{type}    || "";
            my $action = $post->{action}  || "";
            my $count  = $post->{count}   || 0;
            my $rows   = $post->{data}    || [];
            my $jobid  = $job->{job_id};
            
            my $mgcass = $self->cassandra_handle("job", $ver);
            unless ($mgcass) {
                $self->return_data({"ERROR" => "unable to connect to metagenomics analysis database"}, 500);
            }
            unless (($type eq "md5") || ($type eq "lca") || ($action eq "status")) {
                $self->return_data( {"ERROR" => "invalid abundance type: ".$type.", use of of 'md5' or 'lca'"}, 400 );
            }
            $data = {
                metagenome_id => 'mgm'.$job->{metagenome_id},
                job_id        => $job->{job_id}
            };
            
            if ($action eq "start") {
                # add to info - set loaded to false
                if ($mgcass->has_job($jobid)) {
                    if ($type eq "md5") {
                        # reset job_info, md5s to 0
                        $mgcass->update_info_md5s($jobid, 0, 0);
                    } elsif ($type eq "lca") {
                        # reset job_info, lcas to 0
                        $mgcass->update_info_lcas($jobid, 0, 0);
                    }
                } else {
                    # insert job_info
                    $mgcass->insert_job_info($jobid);
                }
                $data->{status} = "empty $type";
            } elsif ($action eq "load") {
                unless ($rows && (scalar(@$rows) > 0)) {
                    $self->return_data( {"ERROR" => "missing required 'data' for loading"}, 400 );
                }
                # insert batch is atomic and sets loaded=false, update_on=time.now() in job_info
                # data->loaded is current total loaded
                if ($type eq "md5") {
                    $data->{loaded} = $mgcass->insert_job_md5s($jobid, $rows);
                } elsif ($type eq "lca") {
                    # url decode lca string
                    map { $_->[0] = uri_decode($_->[0]) } @$rows;
                    $data->{loaded} = $mgcass->insert_job_lcas($jobid, $rows);
                }
                $data->{status} = "loading $type";
            } elsif ($action eq "end") {
                # make sure job exists
                unless ($mgcass->has_job($jobid)) {
                    $self->return_data( {"ERROR" => "unable to end job, does not exist"}, 500 );
                }
                # sanity check on loaded count
                # lca may have zero loaded!
                unless ($count || ($type eq "lca")) {
                    $self->return_data( {"ERROR" => "missing required 'count' option to end"}, 400 );
                }
                my $curr = $mgcass->get_info_count($jobid, $type);
                if ($curr != $count) {
                    $self->return_data( {"ERROR" => "data sanity check failed, only ".$curr." out of ".$count." rows loaded"}, 500 );
                }
                $data->{loaded} = $curr;
                # set loaded to true / done
                $mgcass->set_loaded($jobid, 1);
                $data->{status} = "done $type";
            } elsif ($action eq "status") {
                my $info = $mgcass->get_job_info($jobid);
                if ($info) {
                    %$data = (%$data, %$info);
                    $data->{status} = "exists";
                    if ($post->{validate}) {
                        $data->{md5rows} = $mgcass->get_data_count($jobid, 'md5');
                        $data->{lcarows} = $mgcass->get_data_count($jobid, 'lca');
                    }
                } else {
                    $data->{status} = "missing";
                }
            } else {
                $self->return_data( {"ERROR" => "invalid abundance action: ".$post->{action}.", use of of 'start, 'load', 'end'"}, 400 );
            }
            $mgcass->close();
        } elsif ($action eq 'solr') {
            my $rebuild = $post->{rebuild} ? 1 : 0;
            my $sync    = $post->{sync} ? 1 : 0; # synchronous call
            my $sdata   = $post->{solr_data} || {};
            my $ver     = $post->{ann_ver} || $self->{m5nr_default};
            my $unique  = $self->url_id . md5_hex($self->json->encode($post));
            my $retry   = $post->{retry} || 0;
            
            if (($retry =~ /^\d+$/) && ($retry > 0)) {
                $retry = int($retry);
            } else {
                $retry = 0;
            }
            
            # asynchronous call, fork the process and return the process id.
            # caching is done with shock, not memcache
            my $attr = {
                type => "temp",
                url_id => $unique,
                owner  => $self->user ? 'mgu'.$self->user->_id : "anonymous",
                data_type => "solr"
            };
            # already cashed in shock - say submitted in case its running
            if ($sync == 0) {
                my $nodes = $self->get_shock_query($attr, $self->mgrast_token);
                if ($nodes && (@$nodes > 0)) {
                    if ($retry) {
                        foreach my $n (@$nodes) {
                            $self->delete_shock_node($n->{id}, $self->mgrast_token);
                        }
                    } else {
                        $self->return_data({"status" => "submitted", "id" => $nodes->[0]->{id}, "url" => $self->url."/status/".$nodes->[0]->{id}});
                    }
                }
            }
            # test cassandra access
            my $ctest = $self->cassandra_test("job");
            unless ($ctest) {
                $self->return_data({"ERROR" => "unable to connect to metagenomics analysis database"}, 500);
            }
            # need to create new node and fork
            $attr->{progress} = {
                completed => 'none',
                queried   => 0,
                found     => 0
            };
            $attr->{parameters} = {
                id       => 'mgm'.$job->metagenome_id,
                job_id   => $job->job_id,
                resource => "job/solr",
                version  => $ver,
                retry    => $retry
            };
            my $node = $self->set_shock_node("asynchronous", undef, $attr, $self->mgrast_token, undef, undef, "3D");
            my $pid = 0;
            if ($sync == 0) {
                $pid = fork();
            }
            # child - get data and POST it
            if ($pid == 0) {
                # create DB handels inside child as they break on fork
                if ($sync == 0) {
                    $master = $self->connect_to_datasource();
                }
                my $mgcass = $self->cassandra_abundance($ver);
                my $mddb = MGRAST::Metadata->new();
                
                my $jobj = $master->Job->get_objects( {metagenome_id => $id} );
                $job = $jobj->[0];
                my $jdata = $job->data();
                my $jobid = $job->{job_id};
                my $mgid  = 'mgm'.$job->{metagenome_id};
                my $filename = $jobid.".".time.'.solr.json';

                if ($sync == 0) {
                    close STDERR;
                    close STDOUT;
                }
                
                # solr data
                my $solr_data = {
                    job                => int($jobid),
                    id                 => $mgid,
                    id_sort            => $mgid,
                    status             => $job->{public} ? 'public' : 'private',
                    status_sort        => $job->{public} ? 'public' : 'private',
                    created            => solr_time_format($job->{created_on}),
                    created_sort       => solr_time_format($job->{created_on}),
                    name               => $job->{name},
                    name_sort          => $job->{name},
                    sequence_type      => $job->{sequence_type},
                    sequence_type_sort => $job->{sequence_type},
                    seq_method         => $jdata->{sequencing_method_guess},
                    seq_method_sort    => $jdata->{sequencing_method_guess},
                    version            => $ver,
                    metadata           => ""
                };
                # project - from jobdb
                eval {
                    my $proj = $job->primary_project;
    	            if ($proj->{id}) {
    	                $solr_data->{project_id}        = "mgp".$proj->{id};
    	                $solr_data->{project_id_sort}   = "mgp".$proj->{id};
    	                $solr_data->{project_name}      = $proj->{name};
    	                $solr_data->{project_name_sort} = $proj->{name};
	                }
                };
                if ($@) {
                    $self->return_data({"ERROR" => "error: ".$@});
                }
                # statistics - from postdata or jobdb
                my $seq_stats = exists($sdata->{sequence_stats}) ? $sdata->{sequence_stats} : $job->stats();
                while (my ($key, $val) = each(%$seq_stats)) {
                    if (looks_like_number($val)) {
                        if ($key =~ /count/ || $key =~ /min/ || $key =~ /max/) {
                            $solr_data->{$key.'_l'} = $val * 1;
                        } else {
                            $solr_data->{$key.'_d'} = $val * 1.0;
                        }
                    }
                }
                $self->update_progress($node, 'statistics');
                
                # annotations - from postdata or mg stats (if not rebuild) or from analysis db
                my $mg_stats = {};
                my $get_fun  = 0;
                my $get_org  = 0;
                
                # function
                if (exists($sdata->{function}) && $sdata->{function}) {
                    $solr_data->{function} = $sdata->{function};
                } elsif ($rebuild) {
                    $get_fun = 1;
                } else {
                    unless (exists $mg_stats->{function}) {
                        $mg_stats = $self->metagenome_stats_from_shock($solr_data->{id});
                    }
                    if (exists $mg_stats->{function}) {
                        $solr_data->{function} = [ map {$_->[0]} @{$mg_stats->{function}} ];
                    } else {
                        $get_fun = 1;
                    }
                }
                $self->update_progress($node, 'function');
                # organism - species
                if (exists($sdata->{organism}) && $sdata->{organism}) {
                    $solr_data->{organism} = $sdata->{organism};
                } elsif ($rebuild) {
                    $get_org = 1;
                } else {
                    unless (exists $mg_stats->{taxonomy}) {
                        $mg_stats = $self->metagenome_stats_from_shock($solr_data->{id});
                    }
                    if (exists($mg_stats->{taxonomy}) && exists($mg_stats->{taxonomy}{species}) && $mg_stats->{taxonomy}{species}) {
                        $solr_data->{organism} = [ map {$_->[0]} @{$mg_stats->{taxonomy}{species}} ];
                    } else {
                        $get_org = 1;
                    }
                }
                $self->update_progress($node, 'organism');
                # get annotations from DB
                if ($get_org || $get_fun) {
                    my ($md5_num, $org_map, $fun_map, undef) = @{ $mgcass->all_annotation_abundances($jobid, ['species'], $get_org, $get_fun, 0, $node) };
                    if ($md5_num == 0) {
                        $self->put_shock_file($filename, qq({"ERROR": "no md5 hits available", "STATUS": 500}), $node->{id}, $self->mgrast_token, 1);
                        exit 0;
                    }
                    if ($get_org) {
                        $solr_data->{organism} = [ keys %{$org_map->{species}} ];
                    }
                    if ($get_fun) {
                        $solr_data->{function} = [ keys %{$fun_map} ];
                    }
                }
                # get md5 list
                if (exists($sdata->{md5}) && $sdata->{md5}) {
                    $solr_data->{md5} = $sdata->{md5};
                } else {
                    $solr_data->{md5} = $mgcass->all_md5s($jobid);
                }
                # refresh node object
                $node = $self->get_shock_node($node->{id}, $self->mgrast_token);
                $self->update_progress($node, 'md5');
                
                # close cassandra db
                $mgcass->close();
                
                # mixs metadata - from jobdb
                my $mixs = $mddb->get_job_mixs($job);
                while (my ($key, $val) = each(%$mixs)) {
                    if ($val) {
                        $solr_data->{$key} = $val;
                        $solr_data->{$key.'_sort'} = $val;
                    }
                }
                # full metadata - from jobdb
                my $mdata = $mddb->get_jobs_metadata_fast([$jobid])->{$jobid};
                foreach my $cat (('project', 'sample', 'env_package', 'library')) {
                    eval {
                        if (exists($mdata->{$cat}) && $mdata->{$cat}{id} && $mdata->{$cat}{name} && $mdata->{$cat}{data}) {
                            $solr_data->{$cat.'_id'}      = $mdata->{$cat}{id};
                            $solr_data->{$cat.'_id_sort'} = $mdata->{$cat}{id};
                            $solr_data->{$cat.'_name'}    = $mdata->{$cat}{name};
                            my $concat = join(", ", grep { $_ && ($_ ne " - ") } values %{$mdata->{$cat}{data}});
                            $solr_data->{$cat}      = $concat;
                            $solr_data->{metadata} .= ", ".$concat;
                        }
                    };
                    if ($@) {
                        $self->return_data({"ERROR" => "error: ".$@});
                    }
                }
                $self->update_progress($node, 'metadata');
                
                if ($sync == 1) {
                    $self->return_data({"data" => $solr_data});
                }
                # get content
                my @solr_cmds = (
                    '"delete": { "id": "'.$mgid.'" }',
                    '"commit": { "expungeDeletes": "true" }',
                    '"add": { "doc": '.$self->json->encode($solr_data).' }'
                );
                my $solr_str = '{'.join(", ", @solr_cmds).'}';
                
                # POST to solr
                my $err = "";
                if (! $post->{debug}) {
                    my $solr_file = $Conf::temp."/".$filename;
                    open(SOLR, ">$solr_file") or die "Couldn't open file: $!";
                    print SOLR $solr_str;
                    close(SOLR);
                    $err = $self->solr_post($solr_file);
                }
                if ($err) {
                    $solr_str = qq({"ERROR": "$err", "STATUS": 500});
                }
                
                # POST to shock, triggers end of asynch action
                $self->update_progress($node, 'solr');
                $self->put_shock_file($filename, $solr_str, $node->{id}, $self->mgrast_token, 1);
                exit 0;
            }
            # parent - end html session
            else {
                $self->return_data({"status" => "submitted", "id" => $node->{id}, "url" => $self->url."/status/".$node->{id}});
            }
        }
    }
    
    $self->return_data($data);
}

sub solr_post {
    my ($self, $solr_file) = @_;
    
    # post commands and data
    my $post_url = $Conf::job_solr."/".$Conf::job_collect."/update/json?commit=true";
    my $err = "";
    my $req = StreamingUpload->new(
        POST => $post_url,
        path => $solr_file,
        headers => HTTP::Headers->new(
            'Content-Type' => 'application/json',
            'Content-Length' => -s $solr_file,
        )
    );
    $self->agent->timeout(7200);
    my $response = $self->agent->request($req);
    if ($response->{"_msg"} ne 'OK') {
        my $content = $response->{"_content"};
        $err = "solr POST failed: ".$content;
    }
    return $err;
}

sub update_progress {
    my ($self, $node, $status) = @_;
    $node->{attributes}{progress}{completed} = $status;
    $node = $self->update_shock_node($node->{id}, $node->{attributes}, $self->mgrast_token);
}

sub id_lookup {
    my ($self, $action) = @_;
    
    my $data = {};
    my $post = $self->get_post_data();
    unless (exists($post->{ids}) && (@{$post->{ids}} > 0)) {
        $self->return_data( {"ERROR" => "No IDs submitted"}, 404 );
    } 
    
    if ($action eq 'kb2mg') {
        my $result = $self->kbase_idserver('kbase_ids_to_external_ids', [$post->{ids}]);
        map { $data->{$_} = $result->[0]->{$_}->[1] } keys %{$result->[0]};
    } elsif ($action eq 'mg2kb') {
        my $result = $self->kbase_idserver('external_ids_to_kbase_ids', ['MG-RAST', $post->{ids}]);
        map { $data->{$_} = $result->[0]->{$_} } keys %{$result->[0]};
    }
    
    $self->return_data({'data' => $data, 'found' => scalar(keys %$data)});
}

sub reserve_kbase_id {
    my ($self, $mgid) = @_;
    
    my $result = $self->kbase_idserver('register_ids', ["kb|mg", "MG-RAST", [$mgid]]);
    unless (exists($result->[0]->{$mgid}) && $result->[0]->{$mgid}) {
        $self->return_data( {"ERROR" => "Unable to reserve KBase id for $mgid"}, 500 );
    }
    return $result->[0]->{$mgid};
}

sub solr_time_format {
    my ($dt) = @_;
    if ($dt =~ /^(\d{4}\-\d\d\-\d\d)[ T](\d\d\:\d\d\:\d\d)/) {
        $dt = $1.'T'.$2.'Z';
    } elsif ($dt =~ /^(\d{4}\-\d\d\-\d\d)/) {
        $dt = $1.'T00:00:00Z'
    }
    return $dt;
}

1;
