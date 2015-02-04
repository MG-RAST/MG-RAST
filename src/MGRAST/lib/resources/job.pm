package resources::job;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
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
        reserve => 1,
        create  => 1,
        submit  => 1,
        share   => 1,
        public  => 1,
        delete  => 1,
        addproject => 1
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
        kb2mg => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of KBase id to MG-RAST id' ] },
        mg2kb => { "found" => [ 'int', 'number of input ids that have an alias' ],
                   "data"  => [ 'hash', 'key value pairs of MG-RAST id to KBase id' ] }
    };
    $self->{create_param} = {
        'metagenome_id' => ["string", "unique MG-RAST metagenome identifier"],
        'input_id'      => ["string", "shock node id of input sequence file (optional)"],
        'sequence_type' => ["cv", [["WGS", "whole genome shotgun sequenceing"],
                                   ["Amplicon", "amplicon sequenceing"],
                                   ["MT", "metatranscriptome sequenceing"]] ]
    };
    my @input_stats = map { substr($_, 0, -4) } grep { $_ =~ /_raw$/ } @{$self->seq_stats};
    map { $self->{create_param}{$_} = ['float', 'sequence statistic'] } grep { $_ !~ /drisee/ } @input_stats;
    map { $self->{create_param}{$_} = ['string', 'pipeline option'] } @{$self->pipeline_opts};
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		            'url' => $self->cgi->url."/".$self->name,
		            'description' => "Resource for creating and querying MG-RAST jobs.",
		            'type' => 'object',
		            'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		            'requests' => [
		                { 'name'        => "info",
				          'request'     => $self->cgi->url."/".$self->name,
				          'description' => "Returns description of parameters and attributes.",
				          'method'      => "GET",
				          'type'        => "synchronous",  
				          'attributes'  => "self",
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {} }
						},
				        { 'name'        => "reserve",
				          'request'     => $self->cgi->url."/".$self->name."/reserve",
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
				          'request'     => $self->cgi->url."/".$self->name."/create",
				          'description' => "Create an MG-RAST job with input reserved ID, sequence stats, and pipeline options.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{create},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => $self->{create_param} }
						},
						{ 'name'        => "submit",
				          'request'     => $self->cgi->url."/".$self->name."/submit",
				          'description' => "Submit an existing MG-RAST job to AWE pipeline.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{submit},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "input_id" => ["string", "shock node id of input sequence file"] } }
						},
						{ 'name'        => "share",
				          'request'     => $self->cgi->url."/".$self->name."/share",
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
				          'request'     => $self->cgi->url."/".$self->name."/public",
				          'description' => "Change status of metagenome to public.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => { "public"  => ['boolean', 'the metagenome is public'] },
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"] } }
						},
						{ 'name'        => "delete",
				          'request'     => $self->cgi->url."/".$self->name."/delete",
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
				          'request'     => $self->cgi->url."/".$self->name."/addproject",
				          'description' => "Add exisiting MG-RAST job to existing MG-RAST project.",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{addproject},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => { "metagenome_id" => ["string", "unique MG-RAST metagenome identifier"],
							                                 "project_id" => ["string", "unique MG-RAST project identifier"] } }
						},
						{ 'name'        => "kb2mg",
				          'request'     => $self->cgi->url."/".$self->name."/kb2mg",
				          'description' => "Return a mapping of KBase ids to MG-RAST ids",
				          'method'      => "POST",
				          'type'        => "synchronous",
				          'attributes'  => $self->{attributes}{kb2mg},
				          'parameters'  => { 'options'  => {},
							                 'required' => {},
							                 'body'     => {"ids" => ['list', ['string', 'KBase ids']]} }
						},
						{ 'name'        => "mg2kb",
				          'request'     => $self->cgi->url."/".$self->name."/mg2kb",
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
    } elsif (exists $self->{job_actions}{ $self->rest->[0] }) {
        $self->job_action($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'kb2mg') || ($self->rest->[0] eq 'mg2kb')) {
        $self->id_lookup($self->rest->[0]);
    } else {
        $self->info();
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
                my $node = $self->get_shock_node($nodeid, $self->mgrast_token);
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
        my (undef, $id) = $post->{metagenome_id} =~ /^(mgm)?(\d+\.\d+)$/;
        if (! $id) {
            $self->return_data( {"ERROR" => "invalid id format: ".$post->{metagenome_id}}, 400 );
        }
        # check rights
        unless ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome')) {
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
                    my $node = $self->get_shock_node($nodeid, $self->mgrast_token);
                    $post = $node->{attributes}{stats_info};
                };
                if ($@ || (! $post)) {
                    $self->return_data( {"ERROR" => "unable to obtain sequence file statistics from shock node ".$nodeid}, 500 );
                }
            }
            # check params
            foreach my $key (keys %{$self->{create_param}}) {
                unless (exists $post->{$key}) {
                    $self->return_data( {"ERROR" => "Missing required parameter '$key'"}, 404 );
                }
            }
            # create job
            $job  = $master->Job->initialize($self->user, $post, $job);
            $data = {
                timestamp => $job->{created_on},
                options   => $job->{options},
                job_id    => $job->{job_id}
            };
        } elsif ($action eq 'submit') {
            my $cmd = $Conf::submit_to_awe." --job_id ".$job->{job_id}." --input_node ".$post->{input_id}." --shock_url ".$Conf::shock_url." --awe_url ".$Conf::awe_url;
            my @log = `$cmd 2>&1`;
            chomp @log;
            my @err = grep { $_ =~ /^ERROR/ } @log;
            if (@err) {
                $self->return_data( {"ERROR" => join("\n", @log)}, 400 );
            }
            my (undef, $awe_id) = split(/\t/, $log[1]);
            $data = {
                awe_id => $awe_id,
                log    => join("\n", @log)
            };
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
                if ($post->{edit}) {
                    push @rights, 'edit';
                }
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
            # update shock nodes
            my $nodes = $self->get_shock_query({'type' => 'metagenome', 'id' => 'mgm'.$job->{metagenome_id}}, $self->mgrast_token);
            foreach my $n (@$nodes) {
                my $attr = $n->{attributes};
                $attr->{status} = 'public';
                $self->update_shock_node($n->{id}, $attr, $self->mgrast_token);
                $self->edit_shock_public_acl($n->{id}, $self->mgrast_token, 'put', 'read');
            }
            # update db
            $job->public(1);
            $data = { public => $job->public ? 1 : 0 };
        } elsif ($action eq 'delete') {
            # Auf Wiedersehen!
            my $reason = $post->{reason} || "";
            my ($status, $message) = $job->user_delete($self->user, $reason);
            $data = {
                deleted => $status,
                error   => $message
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
                project_id   => $project->{id},
                project_name => $project->{name},
                status       => $status
            };
        }
    }
    
    $self->return_data($data);
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

sub get_post_data {
    my ($self) = @_;
    
    # posted data
    my $post_data = $self->cgi->param('POSTDATA') ? $self->cgi->param('POSTDATA') : join(" ", $self->cgi->param('keywords'));
    unless ($post_data) {
        $self->return_data( {"ERROR" => "POST request missing data"}, 400 );
    }
    
    my $pdata = {};
    eval {
        $pdata = $self->json->decode($post_data);
    };
    if ($@ || (scalar(keys %$pdata) == 0)) {
        $self->return_data( {"ERROR" => "unable to obtain POSTed data: ".$@}, 500 );
    }
    return $pdata;
}

1;
