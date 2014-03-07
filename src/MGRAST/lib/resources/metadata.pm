package resources::metadata;

use strict;
use warnings;
no warnings('once');

use MGRAST::Metadata;
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    $self->{name} = "metadata";
    $self->{rights} = \%rights;
    $self->{ontologies} = { 'biome' => 1, 'feature' => 1, 'material' => 1 };
    $self->{attributes} = {
        "template" => {
            "project" => [ 'hash', [{'key' => ['string', 'project type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'projects and their metadata'] ],
            "sample"  => [ 'hash', [{'key' => ['string', 'sample type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'samples and their metadata'] ],
            "library" => [ 'hash', [{'key' => ['string', 'library type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'libraries and their metadata'] ],
            "ep"      => [ 'hash', [{'key' => ['string', 'enviromental package type'],
                           'value' => ['hash', 'hash of metadata objects by label']}, 'eps and their metadata'] ]
        },
        "cv" => {
            "ontology" => [ 'hash', [{'key' => ['string', 'metadata label'],
                            'value' => ['list', [ 'list', ['string', 'ontology term and ID'] ]]}, 'list of CV terms for metadata'] ],
            "ont_info" => [ 'hash', [{'key' => ['string', 'metadata label'],
                            'value' => ['list', ['string', 'ontology url and ID']]}, 'term IDs for metadata'] ],
            "select"   => [ 'hash', [{'key' => ['string', 'metadata label'],
                            'value' => ['list', ['string', 'CV term']]}, 'list of CV terms for metadata'] ]
        },
        "export" => {
            "id"        => [ 'string', 'unique object identifier' ],
            "name"      => [ 'string', 'human readable identifier' ],
            "samples"   => [ 'list', [ 'object', 'sample object containing sample metadata, sample libraries, sample envPackage' ] ],
            "sampleNum" => [ 'int', 'number of samples in project' ],
            "data"      => [ 'hash', [{'key' => ['string', 'metadata label'],
                             'value' => ['object', 'project metadata objects']}, 'hash of metadata by label'] ]
        },
        "validate_post" => {
            'is_valid' => [ 'boolean', 'the metadata sheet is valid' ],
            'message'  => [ 'string', 'if not valid, reason why' ],
            'metadata' => [ 'object', 'valid metadata object for project and its samples and libraries' ]
        },
        "validate_get" => {
            'is_valid' => [ 'boolean', 'the inputed value is valid for the given category and label' ],
            'message'  => [ 'string', 'if not valid, reason why' ]
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
        'url'           => $self->cgi->url."/".$self->name,
        'description'   => "Metagenomic metadata is data providing information about one or more aspects of a set sequences from a sample of some environment",
        'type'          => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests'      => [
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
            { 'name'        => "template",
              'request'     => $self->cgi->url."/".$self->name."/template",
              'description' => "Returns static template for metadata object relationships and types",
              'example'     => [ $self->cgi->url."/".$self->name."/template", 'metadata template' ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{template},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {} }
            },
            { 'name'        => "cv",
              'request'     => $self->cgi->url."/".$self->name."/cv",
              'description' => "Returns static controlled vocabularies used in metadata. By default returns all CVs at latest version. If label and version options used, returns those specific values.",
              'example'     => [ $self->cgi->url."/".$self->name."/cv",
                                 'metadata controlled vocabularies' ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{cv},
              'parameters'  => { 'required' => {},
                                 'body'     => {},
                                 'options'  => {
                                     'label'   => ['string', 'metadata label'],
                                     'version' => ['string', 'version of CV select list or ontology to use'] } }
            },
            { 'name'        => "export",
              'request'     => $self->cgi->url."/".$self->name."/export/{ID}",
              'description' => "Returns full nested metadata for a project in same format as template",
              'example'     => [ $self->cgi->url."/".$self->name."/export/mgp128",
                                 'all metadata for project mgp128' ],
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{export},
              'parameters'  => { 'options'  => {},
                                 'required' => { "id" => ["string", "unique object identifier"] },
                                 'body'     => {} }
            },
            { 'name'        => "validate",
              'request'     => $self->cgi->url."/".$self->name."/validate",
              'description' => "Validate given metadata spreadsheet",
              'example'     => [ 'curl -X POST -F "upload=@metadata.xlsx" "'.$self->cgi->url."/".$self->name.'/validate"',
                            	 "validate file 'metadata.xlsx' against MG-RAST metadata template" ],
              'method'      => "POST",
              'type'        => "synchronous",
              'attributes'  => $self->attributes->{validate_post},
              'parameters'  => { 'options'  => {},
                                 'required' => {},
                                 'body'     => {"upload" => ["file", "xlsx or xls format spreadsheet with metadata"]} }
            },
            { 'name'        => "validate",
              'request'     => $self->cgi->url."/".$self->name."/validate",
              'description' => "Validate given metadata value",
              'example'     => [ $self->cgi->url."/".$self->name."/validate?category=sample&label=material&value=soil",
                               	 "check if 'soil' is a vaild term for sample material" ],
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => $self->attributes->{validate_get},
              'parameters'  => { 'required' => {},
                                 'body'     => {},
                                 'options'  => {
                                     'group'    => ['cv', [['mixs', 'label is part of MIxS (minimal) metadata'],
                          								   ['mims', 'label is part of MIMS (metagenome) metadata'],
                          								   ['migs', 'label is part of MIGS (genome) metadata']]],
                                   	 'category' => ['cv', [['project', 'label belongs to project metadata'],
                                                           ['sample', 'label belongs to sample metadata'],
                                                           ['library', 'label belongs to library metadata'],
                                                           ['env_package', 'label belongs to env_package metadata']]],
                                   	 'label'    => ['string', 'metadata label'],
                                   	 'value'    => ['string', 'metadata value'],
                                   	 'version'  => ['string', 'version of CV select list or ontology to use'] } }
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
    } elsif (($self->rest->[0] eq 'template') || ($self->rest->[0] eq 'cv')) {
        $self->static($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'export') && (scalar(@{$self->rest}) == 2)) {
        $self->instance($self->rest->[1]);
    } elsif ($self->rest->[0] eq 'validate') {
        $self->validate();
    } else {
        $self->info();
    }
}

# return static data: template or cv
sub static {
    my ($self, $type, $version) = @_;
    
    my $data = {};
    # get CV data
    if ($type eq 'cv') {
        my $ver   = $self->cgi->param('version') || '';
        my $label = $self->cgi->param('label') || '';
        my $mddb  = MGRAST::Metadata->new();
        # get a specific label / version
        if ($label) {
            if (exists $self->{ontologies}{$label}) {
                $data = $mddb->get_cv_ontology($label, $ver);
            } else {
                $data = $mddb->get_cv_select($label, $ver);
            }
            if (! $data) {
                $self->return_data( {"ERROR" => "No CV exists for the given combination of options"}, 404 );
            }
        # get all latest version
        } else {
            my $latest = $mddb->cv_latest_version();
            $data = { latest_version => $latest,
                      ontology => {},
                      ont_info => {},
                      select => {} };
            while ( ($label, $ver) = each(%$latest) ) {
                if (exists $self->{ontologies}{$label}) {
                    $data->{ontology}{$label} = $mddb->get_cv_ontology($label, $ver);
                    $data->{ont_info}{$label} = $mddb->cv_ontology_info($label, $ver);
                } else {
                    $data->{select}{$label} = $mddb->get_cv_select($label, $ver);
                }
            }
        }
    # get template data
    } elsif ($type eq 'template') {
        my $master = $self->connect_to_datasource();
        my $objs = $master->MetaDataTemplate->get_objects();
        foreach my $o (@$objs) {
            my $info = { aliases    => [ $o->mgrast_tag, $o->qiime_tag ],
    		             definition => $o->definition,
    		             required   => $o->required,
    		             mixs       => $o->mixs,
    		             type       => $o->type,
    		             unit       => $o->unit };
            $data->{$o->category_type}{$o->category}{$o->tag} = $info;
        }
    }
    $self->return_data($data);
}

# the resource is called with an id parameter
sub instance {
    my ($self, $pid) = @_;
    
    # check id format
    my (undef, $id) = $pid =~ /^(mgp)?(\d+)$/;
    if ((! $id) && $pid) {
        $self->return_data( {"ERROR" => "invalid id format: " . $pid}, 400 );
    }
    
    # get database
    my $master = $self->connect_to_datasource();
    my $mddb = MGRAST::Metadata->new();
    
    # get data
    my $project = $master->Project->init( {id => $id} );
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "id $pid does not exists"}, 404 );
    }

    # check rights
    unless ($project->{public} || exists($self->rights->{$id}) || exists($self->rights->{'*'})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $mddb->export_metadata_for_project($project);
    $self->return_data($data)
}

# validate metadata, this can be GET for single value or POST for whole spreadsheet
sub validate {
    my ($self) = @_;
    
    my $data = {};
    my $mddb  = MGRAST::Metadata->new();
    
    if ($self->method eq 'GET') {
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
            my ($is_valid, $err_msg) = @{ $mddb->validate_value($cat, $label, $value) };
            if ($is_valid) {
	            $data = {is_valid => 1, message => undef};
            } else {
	            $data = {is_valid => 0, message => "unable to validate $value: $err_msg"};
            }
        }
    }
    elsif ($self->method eq 'POST') {
        # get metadata file
        my $tmp_dir = "$Conf::temp";
        my $fname   = $self->cgi->param('upload');
        
        unless ($fname) {
            $self->return_data({"ERROR" => "Invalid parameters, requires filename and data"}, 404);
        }
        if ($fname =~ /\.\./) {
            $self->return_data({"ERROR" => "Invalid parameters, trying to change directory with filename, aborting"}, 400);
        }
        if ($fname !~ /^[\w\d_\.]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, . and number characters"}, 400);
        }
        
        my $fhdl = $self->cgi->upload('upload');
        unless ($fhdl) {
            $self->return_data({"ERROR" => "Storing object failed - could not obtain filehandle"}, 507);
        }
        my $io_handle = $fhdl->handle;
        if (open FH, ">$tmp_dir/$fname") {
            my ($bytesread, $buffer);
            while ($bytesread = $io_handle->read($buffer,4096)) {
        	    print FH $buffer;
        	}
            close FH;
        } else {
            $self->return_data({"ERROR" => "Storing object failed - could not open target file"}, 507);
        }
        
        # validate file
        my ($is_valid, $obj, $log) = $mddb->validate_metadata("$tmp_dir/$fname");
        if ($is_valid) {
            delete $obj->{is_valid};
            $data = {is_valid => 1, message => undef, metadata => $obj};
        } else {
            $data = {is_valid => 0, message => $log, errors => $obj->{data}};
        }
    }
    else {
        $self->return_data({"ERROR" => "Invalid request method: ".$self->method}, 400);
    }
    $self->return_data($data);
}

1;
