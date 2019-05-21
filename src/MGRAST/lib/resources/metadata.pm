package resources::metadata;

use strict;
use warnings;
no warnings('once');

use File::Slurp;
use POSIX qw(strftime);

use MGRAST::Metadata;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "metadata";
    $self->{attributes} = {
        "template" => {
            "project" => [ 'hash', [{'key' => ['string', 'project type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'projects and their metadata'] ],
            "sample"  => [ 'hash', [{'key' => ['string', 'sample type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'samples and their metadata'] ],
            "library" => [ 'hash', [{'key' => ['string', 'library type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'libraries and their metadata'] ],
            "ep"      => [ 'hash', [{'key' => ['string', 'environmental package type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'eps and their metadata'] ]
        },
        "version" => {
            "material" => [ 'list', ['string', 'version number'] ],
            "feature"  => [ 'list', ['string', 'version number'] ],
            "biome"    => [ 'list', ['string', 'version number'] ]
        },
        "cv" => {
            "ontology" => [ 'hash', [{'key' => ['string', 'metadata label'],
                            'value' => ['list', [ 'list', ['string', 'ontology term and ID'] ]]}, 'list of CV terms for metadata'] ],
            "select"   => [ 'hash', [{'key' => ['string', 'metadata label'],
                            'value' => ['list', ['string', 'CV term']]}, 'list of CV terms for metadata'] ]
        },
        "ontology" => {
            "name" => ['string', 'ontology name'],
            "nodes" => ['hash', [{'key' => ['string', 'ontology ID'],
                                'value' => ['hash', 'hash of information and relationships for given ontology ID']}, 'info for ontology ID']],
            "rootNode" => ['string', 'ontology ID of root'],
            "showRoot" => ['boolean', 'option to show root when displaying'],
            "type" => ['string', 'this type'],
            "version" => ['string', 'version of this ontology']
        },
        "view" => {
            "label" => [ 'string', 'metadata label' ],
            "total" => [ 'int', 'count of unique values' ],
            "values" => [ 'list', ['string', 'metadata value'] ]
        },
        "export" => {
            "id"        => [ 'string', 'unique object identifier' ],
            "name"      => [ 'string', 'human readable identifier' ],
            "samples"   => [ 'list', [ 'object', 'sample object containing sample metadata, sample libraries, sample envPackage' ] ],
            "sampleNum" => [ 'int', 'number of samples in project' ],
            "data"      => [ 'hash', [{'key' => ['string', 'metadata label'],
                             'value' => ['object', 'project metadata objects']}, 'hash of metadata by label'] ]
        },
        "add" => {
            'project' => [ 'string', 'unique object identifier' ],
            'added'   => [ 'list', ['string', 'ID of metagenome with metadata added'] ],
            'errors'  => [ 'list', ['string', 'error message that may have occurred'] ]
        },
        "validate_post" => {
            'is_valid' => [ 'boolean', 'the metadata sheet is valid' ],
            'message'  => [ 'string', 'if not valid, reason why' ],
            'metadata' => [ 'object', 'valid metadata object for project and its samples and libraries' ]
        },
        "validate_get" => {
            'is_valid' => [ 'boolean', 'the inputted value is valid for the given category and label' ],
            'message'  => [ 'string', 'if not valid, reason why' ]
        },
        "patch" => {
            'metagenome' => [ 'string', 'metagenome_id' ],
            'key'  => [ 'string', 'key' ],
            'value'  => [ 'string', 'value' ]
        }
    };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name'          => $self->name,
        'url'           => $self->url."/".$self->name,
        'description'   => "Metagenomic metadata is data providing information about one or more aspects of a set sequences from a sample of some environment",
        'type'          => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests'      => [
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
            { 'name'        => "patch",
              'request'     => $self->url."/".$self->name,
              'description' => "",
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  =>  $self->attributes->{validate_post} ,
              'parameters'  => { 'options'  => {},
				 'required' => {},
				 'body'     => {} }
            },
            { 'name'        => "template",
              'request'     => $self->url."/".$self->name."/template",
              'description' => "Returns static template for metadata object relationships and types",
              'example'     => [ $self->url."/".$self->name."/template", 'metadata template' ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{template},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {} }
            },
            { 'name'        => "cv",
              'request'     => $self->url."/".$self->name."/cv",
              'description' => "Returns static controlled vocabularies used in metadata. By default returns all CVs at latest version. If label and version options used, returns those specific values.",
              'example'     => [ $self->url."/".$self->name."/cv?label=country",
                                 'metadata controlled vocabularies' ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{cv},
              'parameters'  => { 'required' => {},
                                 'body'     => {},
                                 'options'  => {
                                     'label'   => ['string', 'metadata label'],
                                     'version' => ['string', 'version of CV ontology to use']
                                }}
            },
            { 'name'        => "ontology",
              'request'     => $self->url."/".$self->name."/ontology",
              'description' => "Returns static ontology used in metadata for the given name and version.",
              'example'     => [ $self->url."/".$self->name."/ontology?name=biome&version=2017-04-15",
                                 'metadata ontology lookup' ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{ontology},
              'parameters'  => { 'required' => {
                                    'name'    => ['string', 'ontology name'],
                                    'version' => ['string', 'version of ontology to use'] },
                                 'body'     => {},
                                 'options'  => {} }
            },
            { 'name'        => "ontology",
              'request'     => $self->url."/".$self->name."/ontology",
              'description' => "Update metadata CV ontology with new version, requires admin auth token",
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => { "status"    => ['string', 'status of update'],
                                 "timestamp" => ['date', 'time of completion'] },
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {
                                     'upload'  => ['file', 'file with data'],
                                     'name'    => ['string', 'ontology name'],
                                     'root'    => ['string', 'root ID for lookup'],
                                     'version' => ['string', 'version of ontology to add']
                                }}
            },
            { 'name'        => "version",
              'request'     => $self->url."/".$self->name."/version",
              'description' => "Returns all versions available for given ontology.",
              'example'     => [ $self->url."/".$self->name."/version?label=biome",
                                 'metadata version lookup' ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{version},
              'parameters'  => { 'options'  => { 'label' => ['string', 'ontology metadata label'] },
                                 'required' => {},
                                 'body'     => {} }
            },
            { 'name'        => "view",
              'request'     => $self->url."/".$self->name."/view/{label}",
              'description' => "Returns list of unique metadata values submitted by users for given label",
              'example'     => [ $self->url."/".$self->name."/view/biome",
                                 'all biome values' ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{view},
              'parameters'  => { 'options'  => {},
                                 'required' => { "label" => ["string", "valid metadata label"] },
                                 'body'     => {} }
            },
            { 'name'        => "export",
              'request'     => $self->url."/".$self->name."/export/{id}",
              'description' => "Returns full nested metadata for a project in same format as template, or metadata for a single metagenome.",
              'example'     => [ $self->url."/".$self->name."/export/mgp128",
                                 'all metadata for project mgp128' ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{export},
              'parameters'  => { 'options'  => { 'format' => ['cv', [['json', 'json format'], ['xlsx', 'excel file']] ] },
                                 'required' => { "id" => ["string", "unique object identifier"] },
                                 'body'     => {} }
            },
            { 'name'        => "import",
              'request'     => $self->url."/".$self->name."/import",
              'description' => "Create project with given metadata spreadsheet and metagenome IDs, either upload or shock node",
              'example'     => [ 'curl -X POST -F "metagenome=mgm12345" -F "metagenome=mgm67890" -F "upload=@metadata.xlsx" "'.$self->url."/".$self->name.'/import"',
                              	 "create project with metadata from file 'metadata.xlsx'" ],
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{add},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {
                                     "metagenome" => ['string', 'unique metagenome ID'],
                                     "upload"     => ["file", "xlsx or xls format spreadsheet with metadata"],
                                     "node_id"    => ["string", "shock node ID of metadata spreadsheet"]
                                }}
            },
            { 'name'        => "update",
              'request'     => $self->url."/".$self->name."/update",
              'description' => "Update project with given metadata spreadsheet and metagenome IDs, either upload or shock node",
              'example'     => [ 'curl -X POST -F "project=mgp123" -F "upload=@metadata.xlsx" "'.$self->url."/".$self->name.'/update"',
                              	 "update project mgp123 with metadata from file 'metadata.xlsx'" ],
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{add},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {
                                     "project"    => ["string", "unique project identifier"],
                                     "metagenome" => ['string', 'unique metagenome ID'],
                                     "upload"     => ["file", "xlsx or xls format spreadsheet with metadata"],
                                     "node_id"    => ["string", "shock node ID of metadata spreadsheet"],
                                     "map_by_id"  => ["boolean", "option to map metadata from spreadsheet to metagenomes using ID, default is name"]
                                }}
            },
            { 'name'        => "validate",
              'request'     => $self->url."/".$self->name."/validate",
              'description' => "Validate given metadata spreadsheet, either upload or shock node",
              'example'     => [ 'curl -X POST -F "upload=@metadata.xlsx" "'.$self->url."/".$self->name.'/validate"',
                            	 "validate file 'metadata.xlsx' against MG-RAST metadata template" ],
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{validate_post},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {
                                     "upload" => ["file", "xlsx or xls format spreadsheet with metadata"],
                                     "node_id" => ["string", "shock node ID of metadata spreadsheet"]
                                }}
            },
            { 'name'        => "validate",
              'request'     => $self->url."/".$self->name."/validate",
              'description' => "Validate given metadata value",
              'example'     => [ $self->url."/".$self->name."/validate?category=sample&label=material&value=soil",
                               	 "check if 'soil' is a valid term for sample material" ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{validate_get},
              'parameters'  => { 'required' => {},
                                 'body'     => {},
                                 'options'  => {
						'group'  => ['cv', [['mixs', 'label is part of MIxS (minimal) metadata'],
								    ['mims', 'label is part of MIMS (metagenome) metadata'],
								    ['migs', 'label is part of MIGS (genome) metadata']]],
						'category' => ['cv', [['project', 'label belongs to project metadata'],
								      ['sample', 'label belongs to sample metadata'],
								      ['library', 'label belongs to library metadata'],
								      ['env_package', 'label belongs to env_package metadata']]],
						'label'    => ['string', 'metadata label'],
						'value'    => ['string', 'metadata value'],
						'version'  => ['string', 'version of CV ontology to use']
					       }
			       }
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
    } elsif (($self->rest->[0] =~ /^(template|cv|ontology|version)$/) && ($self->method eq 'GET')) {
        $self->static($self->rest->[0]);
    } elsif (($self->rest->[0] =~ /^(cv|ontology|version)$/) && ($self->method eq 'POST')) {
        $self->update($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'ontology') && ($self->method eq 'DELETE')) {
        $self->delete_ont();
    } elsif (($self->rest->[0] eq 'view') && (scalar(@{$self->rest}) == 2)) {
        $self->list_values($self->rest->[1]);
    } elsif (($self->rest->[0] eq 'export') && (scalar(@{$self->rest}) == 2)) {
        $self->instance($self->rest->[1]);
    } elsif (($self->rest->[0] eq 'validate') && ($self->method eq 'GET')) {
        $self->validate_value();
    } elsif (($self->rest->[0] =~ /^(validate|import|update)$/) && ($self->method eq 'POST')) {
        $self->process_file($self->rest->[0]);
    } elsif (($self->rest->[0] =~ /^(patch)$/) && ($self->method eq 'POST')) {
        $self->patch($self->rest->[0]);
    } elsif ($self->rest->[0] eq 'google') {
      $self->google($self->rest->[1]);
    } else {
        $self->info();
    }
}

# return static data: template / cv / ontology
sub static {
    my ($self, $type) = @_;
    
    my $mddb = MGRAST::Metadata->new();
    my $onts = $mddb->cv_ontology_types();
    my $data = {};
    
    # get versions for ontologies
    if ($type eq 'version') {
        my $label = $self->cgi->param('label') || '';
        if ($label && exists($onts->{$label})) {
            $data = $mddb->cv_ontology_versions($label);
        } else {
            $data = $mddb->cv_ontology_versions();
        }
    # get CV data
    } elsif ($type eq 'cv') {
        my $ver   = $self->cgi->param('version') || '';
        my $label = $self->cgi->param('label') || '';
        # get a specific label / version
        if ($label) {
            if (exists $onts->{$label}) {
                $data = $mddb->get_cv_ontology($label, $ver);
            } else {
                # select options are versionless
                $data = $mddb->get_cv_select($label);
            }
            if (! $data) {
                $self->return_data( {"ERROR" => "No CV exists for the given combination of options"}, 404 );
            }
        # get all, latest version ontology only
        } else {
            my $latest = $mddb->cv_latest_version();
            $data = {
                latest_version => $latest,
                versions       => $mddb->cv_ontology_versions(),
                ontology_info  => $mddb->cv_ontology_info(),
                ontology       => {},
                select         => $mddb->get_cv_all()
            };
            while ( ($label, $ver) = each(%$latest) ) {
                if (exists $onts->{$label}) {
                    $data->{ontology}{$label} = $mddb->get_cv_ontology($label, $ver);
                }
            }
        }
    # get ontology data
    } elsif ($type eq 'ontology') {
        my $ver  = $self->cgi->param('version') || '';
        my $name = $self->cgi->param('name') || '';
        unless ($name) {
            $self->return_data( {"ERROR" => "'name' is a required parameter"}, 404 );
        }
        unless (exists $onts->{$name}) {
            $self->return_data( {"ERROR" => "No ontology exists for $name"}, 404 );
        }
        unless ($ver) {
            $ver = $mddb->cv_latest_version($name);
        }
        my $nodes = $self->get_shock_query({'type' => 'ontology', 'name' => $name, 'version' => $ver});
        unless ($nodes && (@$nodes > 0)) {
            $self->return_data( {"ERROR" => "ontology data for $name (version $ver) is missing or corrupt"}, 500 );
        }
        $data = $nodes->[0]->{attributes};
        $data->{nodes} = {};
        eval {
            my ($content, $err) = $self->get_shock_file($nodes->[0]->{id});
            $data->{nodes} = $self->json->decode($content);
        };
    # get template data
    } elsif ($type eq 'template') {
        my $temp = $mddb->template();
        foreach my $cat (keys %$temp) {
            my $cat_type = $temp->{$cat}{category_type};
            my $cat_data = $temp->{$cat};
            delete $cat_data->{category_type};
            $data->{$cat_type}{$cat} = $cat_data;
        }
    }
    $self->json->utf8();
    $self->return_data($data);
}

# delete ontology based on given name and version
sub delete_ont {
    my ($self) = @_;
    
    unless ($self->user && $self->user->is_admin('MGRAST')) {
        $self->info();
    }
    my $post = $self->get_post_data(["name", "version"]);
    unless ($post->{name} && $post->{version}) {
        $self->return_data({"ERROR" => "Missing parameters, requires: name, version"}, 404);
    }
    my $mddb = MGRAST::Metadata->new();
    # check if this version already exists
    my $current = $mddb->get_cv_ontology($post->{name}, $post->{version});
    # delete from mysql
    $mddb->del_cv_ontology($post->{name}, $post->{version});
    # delete from shock
    my $nodes = $self->get_shock_query({'type' => 'ontology', 'name' => $post->{name}, 'version' => $post->{version}});
    foreach my $n (@$nodes) {
        $self->delete_shock_node($n->{id}, $self->mgrast_token);
    }
    $self->return_data({status => "completed", deleted => scalar(@$current), timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime)});
}

# update metadata CV select list or ontology
sub update {
    my ($self, $type) = @_;
    
    unless ($self->user && $self->user->is_admin('MGRAST')) {
        $self->info();
    }
    my $data = { status => "", timestamp => strftime("%Y-%m-%dT%H:%M:%S", gmtime) };
    my $mddb = MGRAST::Metadata->new();
    
    if ($type eq 'version') {
        my $post = $self->get_post_data(["label", "version"]);
        unless ($post->{label} && $post->{version}) {
            $self->return_data({"ERROR" => "Missing parameters, requires: label, version"}, 404);
        }
        my %current = map { $_, 1 } @{$mddb->cv_ontology_versions($post->{label})};
        if (exists $current{$post->{version}}) {
            $mddb->set_cv_latest_version($post->{label}, $post->{version});
        } else {
            $self->return_data({"ERROR" => "Invalid version, does not exist: ".$post->{version}}, 404);
        }
        $data->{status}  = "completed";
    }
    elsif ($type eq 'cv') {
        my $post = $self->get_post_data(["data", "label", "action"]);
        unless ($post->{data} && @{$post->{data}} && $post->{label}) {
            $self->return_data({"ERROR" => "Missing parameters, requires: data, label"}, 404);
        }
        my $dataset = {};
        unless ($post->{action} && ($post->{action} eq 'replace')) {
            # default is to add current to new
            map { $dataset->{$_} = 1 } @{$mddb->get_cv_select($post->{label})};
        }
        map { $dataset->{$_} = 1 } @{$post->{data}};
        # delete and replace
        $mddb->del_cv_select($post->{label});
        $mddb->put_cv_select($post->{label}, [keys %$dataset]);
        $data->{updated} = scalar(@{$post->{data}});
        $data->{status}  = "completed";
    }
    elsif ($type eq 'ontology') {
        my $post = $self->get_post_data(["upload", "name", "root", "version", "debug"]);
        unless ($post->{upload} && $post->{name} && $post->{root} && $post->{version}) {
            $self->return_data({"ERROR" => "Missing parameters, requires: upload, name, root, version"}, 404);
        }
        # check if this version already exists
        my $current = $mddb->get_cv_ontology($post->{name}, $post->{version});
        if ($current && (@$current > 0)) {
            $self->return_data({"ERROR" => "Ontology ".$post->{name}." at version ".$post->{version}." already exists with ".scalar(@$current)." entries"}, 404);
        }
        
        # get file
        my $tmp_dir = $Conf::temp;
        my $fname = $post->{upload};
        if ($fname =~ /\.\./) {
            $self->return_data({"ERROR" => "Invalid parameters, trying to change directory with filename, aborting"}, 400);
        }
        if ($fname !~ /^[\w\d_\.\-]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, . and number characters"}, 400);
        }
        my $fhdl = $self->cgi->upload('upload');
        unless ($fhdl) {
            $self->return_data({"ERROR" => "Storing object failed - could not obtain filehandle"}, 507);
        }
        my $io_handle = $fhdl->handle;
        if (open FH, ">$tmp_dir/$fname") {
            my ($bytesread, $buffer);
            while ($bytesread = $io_handle->read($buffer, 4096)) {
        	    print FH $buffer;
        	}
            close FH;
        } else {
            $self->return_data({"ERROR" => "Storing object failed - could not open target file"}, 507);
        }
        
        # get hierarchy from file
        my $hier = undef;
        eval {
            my $hier_str = read_file("$tmp_dir/$fname");
            $hier = $self->json->decode($hier_str);
        };
        if ($@ || (! $hier)) {
            $self->return_data({"ERROR" => "Unable to JSON decode file $fname"}, 500);
        }
        
        # get flat list from hierarchy
        my $list = [];
        eval {
            foreach my $id (keys %$hier) {
                push @$list, [ $hier->{$id}{label}, $id ];
            }
        };
        if ($@ || (! $list)) {
            $self->return_data({"ERROR" => "Unable to parse file $fname, invalid JSON struct"}, 500);
        }
        
        # get hierarchy info struct
        my $hier_info = {
            'type' => 'ontology',
            'name' => $post->{name},
            'showRoot'  => JSON::false,
            'rootNode'  => $post->{root},
            'version'   => $post->{version},
            'nodeCount' => scalar(@$list)
        };
        
        if ($post->{debug}) {
            $data->{name}      = $post->{name};
            $data->{version}   = $post->{version};
            $data->{root}      = $post->{root};
            $data->{list}      = $list;
            $data->{hierarchy} = $hier;
        } else {
            # update mysql DB
            $mddb->put_cv_ontology($post->{name}, $post->{version}, $list);
            # set latest version
            $mddb->set_cv_latest_version($post->{name}, $post->{version});
            # POST to shock / make public
            my $node = $self->set_shock_node($post->{name}."_".$post->{version}, $hier, $hier_info, $self->mgrast_token);
            $self->edit_shock_public_acl($node->{id}, $self->mgrast_token, 'put', 'read');        
        }
        $data->{updated} = scalar(@$list);
        $data->{status}   = "completed";
    }
    $self->return_data($data);
}

# the resource is called with a label parameter
sub list_values {
    my ($self, $label) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    my $mddb = MGRAST::Metadata->new();
    
    my $values = $mddb->get_unique_for_tag($label);
    if (@$values == 0) {
        $self->return_data( {"ERROR" => "Invalid metadata label: ".$label}, 400 );
    }
    
    my $data = {
        label => $label,
        total => scalar(@$values),
        values => $values
    };
    $self->return_data($data);
}

# the resource is called with an id parameter
sub instance {
    my ($self, $tempid) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    my $mddb   = MGRAST::Metadata->new();
    my $id     = $self->idresolve($tempid);
    my $format = $self->cgi->param('format') || 'json';
    
    # project export
    if ($id =~ /^mgp(\d+)$/) {
        my $pid = $1;
        # get data
        my $project = $master->Project->init( {id => $pid} );
        unless (ref($project)) {
            $self->return_data( {"ERROR" => "project id $tempid does not exists"}, 404 );
        }
        # check rights
        unless ( $project->{public} ||
                 ($self->user && $self->user->has_right(undef, 'view', 'project', $pid)) ||
                 ($self->user && $self->user->has_star_right('view', 'project'))
               ) {
            $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
        }
        # prepare data
        my $data = $mddb->export_metadata_for_project($project);
        if ($format eq 'xlsx') {
            my ($efile, $error) = $mddb->metadata_to_excel($data);
            if ($error) {
                $self->return_data( {"ERROR" => "unable to export metadata: $error"}, 500 );
            }
            $self->download_local($efile, $tempid.'_metadata.xlsx');
        }
        $self->json->utf8();
        $self->return_data($data);
    }
    # metagenome export
    elsif ($id =~ /^mgm(\d+\.\d+)$/) {
        my $mgid = $1;
        # get data
        my $job = $master->Job->get_objects( {metagenome_id => $mgid} );
        unless ($job && @$job) {
            $self->return_data( {"ERROR" => "metagenome id $tempid does not exist"}, 404 );
        }
        $job = $job->[0];
        # check rights
        unless ( $job->{public} ||
                 ($self->user && $self->user->has_right(undef, 'view', 'metagenome', $mgid)) ||
                 ($self->user && $self->user->has_star_right('view', 'metagenome'))
               ) {
            $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
        }
        # prepare data / get mixs
        my $data = $mddb->get_job_metadata($job, 1, 0);
        my $mixs = $mddb->get_job_mixs($job);
        $data->{mixs} = $mixs;
        $self->json->utf8();
        $self->return_data($data);
    }
    # bad id
    else {
        $self->return_data( {"ERROR" => "invalid id format: ".$tempid}, 400 );
    }
}

# validate a single value
sub validate_value {
    my ($self) = @_;
    
    my $data = {};
    my $mddb = MGRAST::Metadata->new();
    
    # paramater cv
    my $categories = {project => 1, sample => 1, library => 1, env_package => 1};
    my $groups     = {migs => 1, mims => 1, mixs => 1};
    
    # get paramaters
    my $group = $self->cgi->param('group') || 'mixs';
    my $cat   = $self->cgi->param('category');
    my $label = $self->cgi->param('label');
    my $value = $self->cgi->param('value');
    my $ver   = $self->cgi->param('version');

    unless ($group && exists($groups->{$group})) {
        $self->return_data({"ERROR" => "Invalid / missing parameter 'group': ".$group." - valid types are [ '".join("', '", keys %$groups)."' ]"}, 404);
    }
    unless ($cat && exists($categories->{$cat})) {
        $self->return_data({"ERROR" => "Invalid / missing parameter 'category': ".$cat." - valid types are [ '".join("', '", keys %$categories)."' ]"}, 404);
    }
    unless ($label) {
        $self->return_data({"ERROR" => "Missing parameter 'label'"}, 404);
    }
    unless ($value) {
        $self->return_data({"ERROR" => "Missing parameter 'value'"}, 404);
    }

    # internal name
    if ($cat eq 'env_package') { $cat = 'ep'; }

    # special case: geo_loc_name
    if (($cat eq 'sample') && ($label eq 'geo_loc_name')) { $label = 'country'; }

    # special case: lat_lon
    if (($cat eq 'sample') && ($label eq 'lat_lon')) {
        my ($lat, $lon) = split(/\s+/, $value);
        my ($lat_valid, $lat_err) = @{ $mddb->validate_value($cat, 'latitude', $lat) };
        my ($lon_valid, $lon_err) = @{ $mddb->validate_value($cat, 'longitude', $lon) };
        if ($lat_valid && $lon_valid) {
	        $data = {is_valid => 1, message => undef};
        } else {
	        $data = {is_valid => 0, message => "unable to validate $value: $lat_err"};
        }
    }
    # invalid label
    elsif (! $mddb->validate_tag($cat, $label)) {
        $data = {is_valid => 0, message => "label '$label' does not exist in category '".(($cat eq 'ep') ? 'env_package' : $cat)."'"};
    }
    # not mixs label
    elsif (! $mddb->validate_mixs($label)) {
        $data = {is_valid => 0, message => "label '$label' is not a valid ".uc($group)." term"};
    }
    # test it
    else {
        my ($is_valid, $err_msg) = @{ $mddb->validate_value($cat, $label, $value, $ver) };
        if ($is_valid) {
	        $data = {is_valid => 1, message => undef};
        } else {
	        $data = {is_valid => 0, message => "unable to validate $value: $err_msg"};
        }
    }
    $self->return_data($data);
}

# POST function for uploaded file or shock node
# validate metadata spreadsheet
# import metadata for new project
# update metadata for existing project 
sub process_file {
    my ($self, $type) = @_;
    
    my $data   = {};
    my $master = $self->connect_to_datasource();
    my $mddb   = MGRAST::Metadata->new();
    my $post   = $self->get_post_data(["upload", "node_id", "project", "metagenome", "map_by_id", "force"]);
    
    # get metadata file
    my $tmp_dir = $Conf::temp;
    my $fname   = "";
    my $node    = undef;
    
    # uploaded / not POST data
    if ($post->{upload}) {
        $fname = $post->{upload};
        if ($fname =~ /\.\./) {
            $self->return_data({"ERROR" => "Invalid parameters, trying to change directory with filename, aborting"}, 400);
        }
        if ($fname !~ /^[\w\d_\.\-]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, -, . and number characters"}, 400);
        }
        
        my $fhdl = $self->cgi->upload('upload');
        unless ($fhdl) {
            $self->return_data({"ERROR" => "Storing object failed - could not obtain filehandle"}, 507);
        }
        my $io_handle = $fhdl->handle;
        if (open FH, ">$tmp_dir/$fname") {
            my ($bytesread, $buffer);
            while ($bytesread = $io_handle->read($buffer, 4096)) {
        	    print FH $buffer;
        	}
            close FH;
        } else {
            $self->return_data({"ERROR" => "Storing object failed - could not open target file"}, 507);
        }
    }
    # from shock node
    elsif ($post->{node_id}) {
        $node = $self->get_shock_node($post->{node_id}, $self->token, $self->user_auth);
        unless (exists $node->{attributes}{stats_info}) {
            ($node, undef) = $self->get_file_info(undef, $node, $self->token, $self->user_auth);
        }
        $fname = $node->{file}{name};
        my ($res, $err) = $self->get_shock_file($post->{node_id}, "$tmp_dir/$fname", $self->token, $self->user_auth);
        if ($err) {
            $self->return_data({"ERROR" => $err}, 500);
        }
    }
    # bad POST
    else {
        $self->return_data({"ERROR" => "Invalid parameters, requires uploaded file or shock node id"}, 404);
    }
        
    # validate file
    my ($is_valid, $md_obj, $log) = $mddb->validate_metadata("$tmp_dir/$fname");

    # is a shock node / update it
    if ($is_valid && $node && ref($node)) {
        my $attr = $node->{attributes};
        $attr->{data_type} = 'metadata';
        $self->update_shock_node($node->{id}, $attr, $self->token, $self->user_auth);
    }

    # run different actions
    if ($type eq 'validate') {
        $self->json->utf8();
        if ($is_valid) {
            delete $md_obj->{is_valid};
            $data = {is_valid => 1, message => undef, metadata => $md_obj};
        } else {
            if (@{$md_obj->{data}} > 0) {
                $data = {is_valid => 0, message => "", errors => $md_obj->{data}};
            } else {
                $data = {is_valid => 0, message => $log, errors => []};
            }
        }
    } elsif (($type eq 'import') || ($type eq 'update')) {
        unless ($is_valid || $post->{force} ) {
            $self->return_data({"ERROR" => "Unprocessable metadata:\n".join("\n", $log, @{$md_obj->{data}})}, 422);
        }
        unless ($post->{metagenome}) {
            $self->return_data({"ERROR" => "Invalid parameters, import or update requires metagenome ID(s)"}, 404);
	    }
        if (ref $post->{metagenome} ne "ARRAY") {
            $post->{metagenome} = [ split(/,/, $post->{metagenome}) ];
        }
        if (($type eq 'update') && (! $post->{project})) {
            $self->return_data({"ERROR" => "Invalid parameters, update requires project ID"}, 404);
        }

	    # get project object (if exists)
        my $project_name = $md_obj->{data}{project_name}{value};
        my $project_id   = ($type eq 'update') ? $post->{project} : (exists($md_obj->{id}) ? $md_obj->{id} : '');
        my $project_obj  = undef;

        # get metagenome objects
        my @jobs = ();
        foreach my $id (@{$post->{metagenome}}) {
	    $id = $self->idresolve($id);
            if ($id =~ /^mgm(\d+\.\d+)$/) {
                my $mgid = $1;
                # get data
                my $job = $master->Job->get_objects( {metagenome_id => $mgid} );
                unless ($job && @$job) {
                    $self->return_data( {"ERROR" => "Metagenome id $id does not exist"}, 404 );
                }
                $job = $job->[0];
                # check rights
                unless ($self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $mgid) || $self->user && $self->user->has_star_right('edit', 'metagenome') || ($project_obj && ($self->user->has_right(undef, 'edit', 'project', $project_obj->id) || $self->user->has_star_right('edit', 'project'))))) {
                    $self->return_data( {"ERROR" => "Insufficient permissions to edit this data"}, 401 );
                }
                push @jobs, $job;
            } else {
                $self->return_data( {"ERROR" => "Invalid metagenome id format: ".$id}, 400 );
            }
        }
        
        # get project from id or name, or create it
        my $projects = [];
        if ($project_id) {
            if ($project_id =~ /^mgp(\d+)$/) {
                my $pnum  = $1;
                $projects = $master->Project->get_objects( {id => $pnum} );
            } else {
                $self->return_data( {"ERROR" => "invalid project id format: ".$project_id}, 400 );
            }
        } elsif ($project_name) {
            $projects = $master->Project->get_objects( {name => $project_name} );
        }
        if (scalar(@$projects) > 0) {
            $project_obj = $projects->[0];
            # check rights
            unless ($self->user && ($self->user->has_right(undef, 'edit', 'project', $project_obj->id) || $self->user->has_star_right('edit', 'project'))) {
                $self->return_data( {"ERROR" => "insufficient permissions to edit this project"}, 401 );
            }
        }
        
        # import or update
        my $mapbyid = $post->{map_by_id} ? 1 : 0;
        my ($pnum, $added, $err_msg) = $mddb->add_valid_metadata($self->user, $md_obj, \@jobs, $project_obj, $mapbyid);
        if ($added && scalar(@$added)) {
            @$added = map { 'mgm'.$_->{metagenome_id} } @$added;
        }
        # update elasticsearch
        foreach my $mgid (@$added) {
            $self->upsert_to_elasticsearch_metadata($mgid);
        }
        $data = {project => 'mgp'.$pnum, added => $added, errors => $err_msg};
    }
    
    $self->return_data($data);
}
sub patch{  # Resource to update a single field at a time in the metadata database
    my ($self, $type) = @_;
    my $master = $self->connect_to_datasource();
    my $mddb   = MGRAST::Metadata->new();
    my $post   = $self->get_post_data(["tag", "value", "metagenome", "ctype"]);
    my $mgid   = $post->{metagenome};
    my $tag    = $post->{tag};
    my $value  = $post->{value};
    my $ctype  = exists ($post->{ctype}) ? $post->{ctype} : "sample";
    if (not $mgid =~  /mgm\d*.\d/)
        {die ("metagenome not in mgm.... format");}  # This is the protection against attacks
    $mgid =~ s/mgm//; 
    unless ($self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $mgid) || $self->user && $self->user->has_star_right('edit', 'metagenome')  ) )  { 
                    $self->return_data( {"ERROR" => "Insufficient permissions to edit mgm".$mgid}, 401 );
	}
#    my $jobs = $master->Job->get_objects( {metagenome_id => $mgid} ); 

  my $query  = "";
  my $collection = undef;
  if ($ctype =~ "sample") 
	{ 
	$query = "SELECT c._id, c.ID, c.type, c.name, c.parent FROM Job j, MetaDataCollection c WHERE j.metagenome_id=".$mgid." AND j.sample=c._id";
	}
#        my $jobs = $master->Job->get_objects( {metagenome_id => $mgid} ); 
#  	die ( "Too many jobs found!". scalar(@$jobs)) unless scalar(@$jobs) == 1; 
#	my $collection_id = @$jobs[0]->{sample};   # This did not work because "sample" and "library" fields in Jobs table
#       refer to _id field in MetaDataCollection but for some reason MetaDataCollection->init({_id => $collection}) fails with 
#      "There must be a unique index on the combination of attributes passed."  Going around this using ID field ...
# The $query =   ... selectall_arrayref  syntax is copied from add_valid_metadata
  elsif ($ctype =~ "library" ) 
	{ 
	$query = "SELECT c._id, c.ID, c.type, c.name, c.parent FROM Job j, MetaDataCollection c WHERE j.metagenome_id=".$mgid." AND j.library=c._id"; 
	} 
  elsif ($ctype =~ "ep" ) 
	{ 
	$query = "SELECT c._id, c.ID, c.type, c.name, c.parent FROM Job j, MetaDataCollection c WHERE j.metagenome_id=".$mgid." AND j.sample=c.parent AND c.type='ep'"; 
	} 
  else {die ("Can't handle collection type ". $ctype); } 
        my $result = $mddb->{_handle}->db_handle->selectall_arrayref($query);
	die ( "Wrong number of collections found:". scalar(@$result).".  This resource does not create collections.") unless scalar(@$result) == 1;
        $collection = @$result[0]->[1];
	{ 
	        { 
# I can get a samp_coll object if I have collection ID:
		my $samp_coll  = $mddb->{_handle}->MetaDataCollection->init({ID => $collection});   # collection of samples...

		# retrieving sample collection via MetaDataCollection->init and assigning into it with MetDataEntry-> create inadvertently 
		# 1)  wipes all existing data and 
		# 2)  adds duplicate fields
		#  retrieving sample collection via MetaDataCollection->init and assigning into it with mddb->add_entries  
		# does not have the above problems, even though $append = 0
		my $append = 0;
		my $data = [ [ $tag, $value ] ] ; 
		$mddb->add_entries ($samp_coll, $data, $append); 
      		}  
	}
    # update elasticsearch
    $self->upsert_to_elasticsearch_metadata($mgid);
    $self->return_data({ "OK" => "update attempted on mgm".$mgid }, 200);
}   ## WLT

sub google {
  my ($self, $id) = @_;

  # if there is an id, create the preference
  if ($id) {
    my $pref = $self->user->_master->Preferences->create({ user => $self->user,
							   name => 'UploadMetadataNode',
							   value => $id });
    if (ref($pref)) {
      $self->return_data({"OK" => "preference created"}, 200);
    } else {
      $self->return_data({"ERROR" => "unable to create preference node"}, 500);
    }
  }
  # otherwise, return the file
  else {
  
    my $nodeid = $self->user->_master->Preferences->get_objects({ user => $self->user,
								  name => 'UploadMetadataNode' });
    unless (scalar(@$nodeid)) {
      $self->return_data({"ERROR" => "no upload metadata node for user found"}, 404);
    }
    
    $nodeid = $nodeid->[0]->value;
    
    $self->return_shock_file($nodeid, undef, "metadata", $self->token, $self->user_auth);
  }
}

1;
