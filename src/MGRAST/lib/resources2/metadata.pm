package resources2::metadata;

use strict;
use warnings;
no warnings('once');

use MGRAST::Metadata;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights   = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    my $metadata = { 'hash', ['key', ['string', 'metadata label']],
                             ['value', ['object', [ { 'type'       => ['string', 'value type: text, int, float, select, ontology'],
                                                      'definition' => ['string', 'definition of label'],
                                                      'required'   => ['boolean', 'is a required label'],
                                                      'mixs'       => ['boolean', 'is a MIxS label'],
                                                      'aliases'    => ['list', ['string', 'alternative name for label']]
                                                    }, 'information about metadata keyword' ]]]
                   };
    $self->{name}       = "metadata";
    $self->{rights}     = \%rights;
    $self->{attributes} = { "template" => { "project" => [ 'hash', ['key', ['string', 'project type']],
                                                                   ['value', ['object', [$metadata, 'available metadata for this project type']]] ],
                                            "sample"  => [ 'hash', ['key', ['string', 'sample type']],
                                                                   ['value', ['object', [$metadata, 'available metadata for this sample type']]] ],
                                            "library" => [ 'hash', ['key', ['string', 'library type']],
                                                                   ['value', ['object', [$metadata, 'available metadata for this library type']]] ],
                                            "ep"      => [ 'hash', ['key', ['string', 'enviromental package type']],
                                                                   ['value', ['object', [$metadata, 'available metadata for this ep type']]] ] },
                            "cv"       => { "ontology" => [ 'hash', ['key', ['string', 'metadata label']],
                                                                    ['value', ['int', 'bioportal ontology ID']] ],
                                            "ont_id"   => [ 'hash', ['key', ['string', 'metadata label']],
                                                                    ['value', ['int', 'bioportal term ID']] ],
                                            "select"   => [ 'hash', ['key', ['string', 'metadata label']],
                                                                    ['value', ['int', 'list of available CV terms']] ] },
                            "export"   => { "id"        => [],
                                            "name"      => [],
                                            "samples"   => [],
                                            "sampleNum" => [],
                                            "data"      => [] },
                            "validate" => { 'is_valid' => [ 'boolean', 'the inputed value is valid for the given category and label' ],
                                            'message'  => [ 'string', 'if not valid, reason why' ] }
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "Metagenomic metadata is data providing information about one or more aspects of a set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => '',
                    'requests'      => [ { 'name'        => "info",
            				               'request'     => $self->cgi->url."/".$self->name,
            				               'description' => "Returns description of parameters and attributes.",
            				               'method'      => "GET",
            				               'type'        => "synchronous",  
            				               'attributes'  => "self",
            				               'parameters'  => { 'options'  => {},
            							                      'required' => {},
            							                      'body'     => {} } },
                                         { 'name'        => "template",
                                           'request'     => $self->cgi->url."/".$self->name."/template",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{template},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} } },
                                         { 'name'        => "cv",
                                           'request'     => $self->cgi->url."/".$self->name."/cv",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{cv},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => {},
                                                              'body'     => {} } },
                                         { 'name'        => "export",
                                           'request'     => $self->cgi->url."/".$self->name."/export/{ID}",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{export},
                                           'parameters'  => { 'options'  => {},
                                                              'required' => { "id" => ["string", "unique object identifier"] },
                                                              'body'     => {} } },
                                         { 'name'        => "validate",
                                           'request'     => $self->cgi->url."/".$self->name."/validate",
                                           'description' => "",
                                           'method'      => "GET",
                                           'type'        => "synchronous",  
                                           'attributes'  => $self->attributes->{validate},
                                           'parameters'  => { 'options'  => { 'group'    => ['cv', [['migs', 'label is part of MIGS (genome) metadata'],
                          												                            ['mims', 'label is part of MIMS (metagenome) metadata'],
                          												                            ['mixs', 'label is part of MIxS (minimal) metadata']]],
                                   						                      'category' => ['cv', [['project', 'label belongs to project metadata'],
                                                                                                    ['sample', 'label belongs to sample metadata'],
                                                                                                    ['library', 'label belongs to library metadata'],
                                                                                                    ['env_package', 'label belongs to env_package metadata']]],
                                   						                      'label'    => ['string', 'metadata label'],
                                   						                      'value'    => ['string', 'metadata value'] },
                                                              'required' => {},
                                                              'body'     => {} } },
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
    } elsif (($self->rest->[0] eq 'template') || ($self->rest->[0] eq 'cv')) {
        $self->metadata($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'export') && (scalar(@{$self->rest}) == 2)) {
        $self->instance($self->rest->[1]);
    } elsif ($self->rest->[0] eq 'validate') {
        $self->validate();
    } else {
        $self->info();
    }
}

sub metadata {
    my ($self, $type) = @_;
    
    # get database
    my $master = $self->connect_to_datasource();
    
    # get data
    my $data = {};
    if ($type eq 'cv') {
        my $objs = $master->MetaDataCV->get_objects();
        foreach my $o (@$objs) {
            if ($o->type eq 'select') {
    	        push @{ $data->{$o->type}{$o->tag} }, $o->value;
            } else {
    	        $data->{$o->type}{$o->tag} = $o->value;
            }
        }
    } elsif ($type eq 'template') {
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
    unless ($project->{public} || exists($self->rights->{$id})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $mddb->export_metadata_for_project($project);
    $self->return_data($data)
}

sub validate {
    my ($self) = @_;
    
    # paramater cv
    my $categories = {project => 1, sample => 1, library => 1, env_package => 1};
    my $groups     = {migs => 1, mims => 1, mixs => 1};
    
    # get paramaters
    my $group = $self->cgi->param('group');
    my $cat   = $self->cgi->param('category');
    my $label = $self->cgi->param('label');
    my $value = $self->cgi->param('value');
    my $mddb  = MGRAST::Metadata->new();
    my $data  = {};

    unless ($group && exists($groups->{$group})) {
        $self->return_data({"ERROR" => "Invalid / missing parameter 'group': ".$group." - valid types are [ '".join("', '", keys %$groups)."' ]"}, 400);
    }
    unless ($cat && exists($categories->{$cat})) {
        $self->return_data({"ERROR" => "Invalid / missing parameter 'category': ".$cat." - valid types are [ '".join("', '", keys %$categories)."' ]"}, 400);
    }
    unless ($label) {
        $self->return_data({"ERROR" => "Missing parameter 'label'"}, 400);
    }
    unless ($value) {
        $self->return_data({"ERROR" => "Missing parameter 'value'"}, 400);
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
	        $data = {is_valid => 1, message => ""};
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
	        $data = {is_valid => 1, message => ""};
        } else {
	        $data = {is_valid => 0, message => "unable to validate $value: $err_msg"};
        }
    }
    $self->return_data($data);
}

1;
