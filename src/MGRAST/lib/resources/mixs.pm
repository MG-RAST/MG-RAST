package resources::mixs;

use strict;
use warnings;
no warnings('once');

use JSON::Validator;
use Data::Dumper;
use File::Slurp;
use POSIX qw(strftime);

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "mixs";
    $self->{instance} = {
        "id"          => [ 'string', 'unique MiXS Profile identifier' ],
        "name"        => [ 'string', 'profile name' ],
        "description" => [ 'string', 'profile description' ],
        "contact"     => [ 'object', [
            {
                "organization"        => [ 'string', 'organization full name' ],
                "organization_abbrev" => [ 'string', 'organization abbreviation' ],
                "url"                 => [ 'uri', 'organization url' ],
                "email"               => [ 'string', 'submitters email' ],
                "firstname"           => [ 'string', 'submitters first name' ],
                "lastname"            => [ 'string', 'submitters last name' ]
            },
            'contact information' ]
        ],
        "packages"  => [ 'list', ['string', 'package name with required field'] ],
        "hierarchy" => [ 'list', ['list', ['string', 'required field name']] ]
    };
    $self->{query} = {
        "data"  => [ 'list', [ 'object', [
            {
                "id"           => [ 'string', 'unique MiXS Profile identifier' ],
                "name"         => [ 'string', 'profile name' ],
                "organization" => [ 'string', 'organization full name' ],
                "updated"      => [ 'string', 'date-time the profile was last modified' ],
            },
            'profile information' ]
        ]],
        "url"   => [ 'uri', 'resource location of this object instance' ],
        "total" => [ 'integer', 'total number of available data items' ]
    };
    
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->url."/".$self->name,
        'description' => "",
        'type' => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests' => [
            {
                'name'        => "info",
                'request'     => $self->url."/".$self->name,
                'description' => "Returns description of parameters and attributes.",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => "self",
                'parameters'  => {
                    'options'  => {},
                    'required' => {},
                    'body'     => {}
                }
			},
            {
                'name'        => "instance",
                'request'     => $self->url."/".$self->name."/profile/{ID}",
	        'description' => "Retrieve MiXS Profile object for given ID",
	        'example'     => $self->url."/".$self->name."/profile/ab44ac2f-6781-4fb6-9149-8e62705e5319",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => $self->{instance},
                'parameters'  => {
                    'options'  => {},
                    'required' => { "id" => [ "string", "unique MiXS Profile identifier" ] },
                    'body'     => {}
                }
			},
            {
                'name'        => "query",
                'request'     => $self->url."/".$self->name."/profile",
                'description' => "Listing of avaiable MiXS Profiles in MG-RAST",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => $self->{query},
                'parameters'  => {
                    'options'  => {},
                    'required' => {},
                    'body'     => {}
                }
			},
            {
                'name'        => "validate",
                'request'     => $self->url."/".$self->name."/profile/validate",
                'description' => "Validate a MiXS Profile against current schema",
                'method'      => "POST",
                'type'        => "synchronous",
                'attributes'  => {
                    'is_valid' => [ 'boolean', 'the inputted profile is valid with the current schema' ],
                    'version'  => [ 'string', 'version of schema profile was validated against' ],
                    'message'  => [ 'string', 'if not valid, reason why' ]
                },
                'parameters'  => {
                    'options'  => {},
                    'required' => {},
                    'body'     => { "upload"  => ["file", "profile in json format file"],
                                    "version" => [ "string", "version of schema to validate against"] }
                }
			},
            {
                'name'        => "upload",
                'request'     => $self->url."/".$self->name."/profile/upload",
                'description' => "Upload a new MiXS Profile to MG-RAST",
                'method'      => "POST",
                'type'        => "synchronous",
                'attributes'  => {
                    'id'       => [ 'string', 'if valid, unique identifier for uploaded profile' ],
                    'is_valid' => [ 'boolean', 'the inputted profile is valid with the current schema' ],
                    'version'  => [ 'string', 'version of schema profile was validated against' ],
                    'message'  => [ 'string', 'if not valid, reason why' ]
                },
                'parameters'  => {
                    'options'  => {},
                    'required' => {},
                    'body'     => { "upload"  => ["file", "profile in json format file"],
                                    "version" => [ "string", "version of schema to validate against"] }
                }
			},
            {
                'name'        => "update",
                'request'     => $self->url."/".$self->name."/profile/{ID}",
                'description' => "Update an existing MiXS Profile in MG-RAST",
                'method'      => "POST",
                'type'        => "synchronous",
                'attributes'  => {
                    'id'       => [ 'string', 'unique identifier for updated profile' ],
                    'is_valid' => [ 'boolean', 'the inputted profile is valid with the current schema' ],
                    'version'  => [ 'string', 'version of schema profile was validated against' ],
                    'message'  => [ 'string', 'if not valid, reason why' ]
                },
                'parameters'  => {
                    'options'  => {},
                    'required' => { "id" => [ "string", "unique MiXS Profile identifier" ] },
                    'body'     => { "upload" => ["file", "profile in json format file"] }
                }
			},
            {
                'name'        => "schema",
                'request'     => $self->url."/".$self->name."/schema",
                'description' => "Retrieve current MiXS Schema",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => $self->{instance},
                'parameters'  => {
                    'options'  => { "version" => [ "string", "version of schema to retrieve, default is most current" ] },
                    'required' => {},
                    'body'     => {}
                }
			},
            {
                'name'        => "schema",
                'request'     => $self->url."/".$self->name."/schema",
                'description' => "Update current MiXS Schema",
                'method'      => "POST",
                'type'        => "synchronous",
                'attributes'  => $self->{instance},
                'parameters'  => {
                    'options'  => {},
                    'required' => {},
                    'body'     => { "upload"  => ["file", "schema in json format file"],
                                    "version" => [ "string", "version of schema to upload"] }
                }
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
    } elsif (($self->method eq 'GET') && ($self->rest->[0] eq 'profile') && (scalar(@{$self->rest}) > 1)) {
        $self->instance($self->rest->[1]);
    } elsif (($self->method eq 'GET') && ($self->rest->[0] eq 'profile') && (scalar(@{$self->rest}) == 1)) {
        $self->query();
    } elsif ($self->method eq 'POST') {
        if (($self->rest->[0] eq 'profile') && (scalar(@{$self->rest}) > 1)) {
            $self->process_file($self->rest->[1]);
        } elsif ($self->rest->[0] eq 'schema') {
            $self->process_file($self->rest->[0]);
        } else {
            $self->info();
        }
    } elsif (($self->method eq 'GET') && ($self->rest->[0] eq 'schema')) {
        $self->schema();
    } else {
        $self->info();
    }
}

# the resource is called with an id parameter
sub instance {
    my ($self, $uuid) = @_;
    
    # get profile from shock
    my ($text, $err) = $self->get_shock_file($uuid, undef, $self->mgrast_token);
    if ($err) {
        $self->return_data({"ERROR" => "MiXS Profile $uuid does not exist"}, 500);
    }
    
    $self->json->utf8();
    my $profile = $self->json->decode($text);
    $profile->{id} = $uuid;
    $self->return_data($profile);
}

# the resource is called without an id parameter
sub query {
    my ($self) = @_;
    
    my $response = {
        data  => [],
        total => 0,
        url   => $self->url."/".$self->name."/profile"
    };
    
    # query shock for mixs profiles
    my $nodes = $self->get_shock_query({type => "mixs", data_type => "profile"}, $self->mgrast_token);
    if ($nodes && (@$nodes > 0)) {
        foreach my $n (@$nodes) {
            push @{$response->{data}}, {
                "id"           => $n->{id},
                "name"         => $n->{attributes}{name},
                "organization" => $n->{attributes}{organization},
                "updated"      => $n->{created_on}
            };
        }
    }
    
    $response->{total} = scalar(@{$response->{data}});
    $self->return_data($response);
}

# POST function for uploaded file
# validate mixs profile
# upload new profile
# upload new schema
sub process_file {
    my ($self, $type) = @_;
    
    my $filename = "";
    my $filejson = undef;
    my $version  = $self->cgi->param('version') || undef;
    
    # get uploaded file
    if ($self->cgi->param('upload')) {
        $filename = $self->cgi->param('upload');
        if ($filename =~ /\.\./) {
            $self->return_data({"ERROR" => "Invalid parameters, trying to change directory with filename, aborting"}, 400);
        }
        if ($filename !~ /^[\w\d_\.\-]+$/) {
            $self->return_data({"ERROR" => "Invalid parameters, filename allows only word, underscore, -, . and number characters"}, 400);
        }
        my $fhdl = $self->cgi->upload('upload');
        unless ($fhdl) {
            $self->return_data({"ERROR" => "Storing object failed - could not obtain filehandle"}, 507);
        }
        $self->json->utf8();
        eval {
            my $text = read_file($fhdl);
            $filejson = $self->json->decode($text);
        };
        if ($@ || (! $filejson)) {
            $self->return_data({"ERROR" => "Unable to read uploaded file $filename, possible bad format"}, 422);
        }
    }
    # bad POST
    else {
        $self->return_data({"ERROR" => "Invalid parameters, missing required upload file"}, 404);
    }
    
    my $response = {};
    unless ($type eq 'schema') {
        # validate profile against latest schema
        my ($is_valid, $found_version, $error) = $self->validate_mixs_profile($filejson, $version);
        $response = {
            'is_valid' => $is_valid,
            'version'  => $found_version,
            'message'  => $error
        };
    }
    
    # run different actions
    if ($type eq 'validate') {
        $self->return_data($response);
    } elsif ($type eq 'upload') {
        # admin only
        unless ($self->user->is_admin('MGRAST')) {
            $self->return_data({"ERROR" => "Insufficient permissions to upload profile"}, 401);
        }
        # check if already exists
        my $nodes = $self->get_shock_query({type => "mixs", data_type => "profile"}, $self->mgrast_token);
        if ($nodes && (@$nodes > 0)) {
            foreach my $n (@$nodes) {
                if (($filejson->{name} eq $n->{attributes}{name}) && ($filejson->{contact}{organization} eq $n->{attributes}{organization})) {
                    $response->{id} = undef;
                    $response->{is_valid} = 0;
                    $response->{message}  = 'a profile with the given name and organization already exists';
                }
            }
        }
        # return if not valid
        unless ($response->{is_valid}) {
            $self->return_data($response);
        }
        # create shock node
        my $attr = {
            'type'           => 'mixs',
            'data_type'      => 'profile',
            'name'           => $filejson->{name},
            'organization'   => $filejson->{contact}{organization},
            'schema_version' => $response->{version}
        };
        my $node = $self->set_shock_node($filename, $filejson, $attr, $self->mgrast_token);
        $response->{id} = $node->{id};
        $self->return_data($response);
    } elsif ($type eq 'schema') {
        # admin only
        unless ($self->user->is_admin('MGRAST')) {
            $self->return_data({"ERROR" => "Insufficient permissions to upload profile"}, 401);
        }
        # check parameters
        unless ($version) {
            $self->return_data({"ERROR" => "Invalid parameters, missing required schema version"}, 404);
        }
        # check if already exists
        my $nodes = $self->get_shock_query({type => "mixs", data_type => "schema"}, $self->mgrast_token);
        if ($nodes && (@$nodes > 0)) {
            foreach my $n (@$nodes) {
                if ($version eq $n->{attributes}{version}) {
                    $self->return_data({"ERROR" => "MiXS Schema version '$version' already exists"}, 400);
                }
            }
        }
        my $attr = {
            'type'      => 'mixs',
            'data_type' => 'schema',
            'version'   => $version
        };
        my $node = $self->set_shock_node($filename, $filejson, $attr, $self->mgrast_token);
        $self->return_data({'id' => $node->{id}, 'version' => $version});
    } else {
        $self->info();
    }
}

sub schema {
    my ($self) = @_;
    
    my $version = $self->cgi->param('version') || undef;
    my ($schema, undef) = $self->get_schema($version);
    unless ($schema) {
         $self->return_data({"ERROR" => "MiXS Schema version '$version' does not exist"}, 500);
    }
    $self->return_data($schema);
}

sub validate_mixs_profile {
    my ($self, $filejson, $version) = @_;
    
    my $schema = undef;
    ($schema, $version) = $self->get_schema($version);
    unless ($schema) {
         $self->return_data({"ERROR" => "MiXS Schema is missing"}, 500);
    }
    
    my $validator = JSON::Validator->new;
    $validator->schema($schema);
    my @errors = $validator->validate($filejson);
    
    if (@errors) {
        return (0, $version, join("\n", @errors));
    } else {
        return (1, $version, undef);
    }
}

sub get_schema {
    my ($self, $version) = @_;
    
    my $nodeid = undef;
    my $nodes  = $self->get_shock_query({type => "mixs", data_type => "schema"}, $self->mgrast_token);
    if ($nodes && (@$nodes > 0)) {
        if ($version) {
            foreach my $n (@$nodes) {
                if ($n->{attributes}{version} eq $version) {
                    $nodeid = $n->{id};
                    last;
                }
            }
        } else {
            # lastest by creation date
            $nodeid = $nodes->[0]{id};
            $version = $nodes->[0]{attributes}{version};
        }
    }
    if ($nodeid) {
        # get schema from shock
        my ($text, $err) = $self->get_shock_file($nodeid, undef, $self->mgrast_token);
        if ($err) {
            return (undef, undef);
        }
        $self->json->utf8();
        my $schema = $self->json->decode($text);
        return ($schema, $version);
    } else {
        return (undef, undef);
    }
}

1;
