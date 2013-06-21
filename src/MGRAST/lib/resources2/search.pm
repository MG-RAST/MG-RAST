package resources2::search;

use strict;
use warnings;
no warnings('once');

use URI::Escape;
use Digest::MD5;
use Data::Dumper;

use MGRAST::Analysis;
use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "search";
    $self->{return_fields} = {'job'          => [ 'string', 'MG-RAST internal job number' ],
                              'name'         => [ 'string', 'name of metagenome' ],
                              'id'           => [ 'string', 'metagenome id' ],
                              'project_id'   => [ 'string', 'project containing metagenome' ],
                              'project_name' => [ 'string', 'project containing metagenome' ],
                              'public'       => [ 'boolean', 'public status of metagenome' ],
                              'biome'        => [ 'string', 'environmental biome, EnvO term' ],
                              'feature'      => [ 'string', 'environmental feature, EnvO term' ],
                              'material'     => [ 'string', 'environmental material, EnvO term' ],
                              'country'      => [ 'string', 'country' ],
                              'location'     => [ 'string', 'location' ]};

    $self->{attributes} = { metagenome => { next   => ["uri","link to the previous set or null if this is the first set"],
                                            prev   => ["uri","link to the next set or null if this is the last set"],
                                            limit  => ["integer","maximum number of data items returned, default is 10"],
                                            offset => ["integer","zero based index of the first returned data item"],
                                            total_count => ["integer","total number of available data items"],
                                            version => [ 'integer', 'version of the object' ],
                                            url  => [ 'uri', 'resource location of this object instance' ],
                                            data => [ 'list', ['object', [$self->{return_fields}, "metagenome object"]] ] }
                          };
    return $self;
}


# resource is called without any parameters
# this method must return a description of the resource
sub info {
  my ($self) = @_;
  my $content = { 'name'          => $self->name,
                  'url'           => $self->cgi->url."/".$self->name,
                  'description'   => "search returns data objects in MG-RAST",
                  'type'          => 'object',
                  'documentation' => $self->cgi->url.'/api.html#'.$self->name,
                  'requests'      => [ { 'name'        => "info",
                                         'request'     => $self->cgi->url."/".$self->name,
                                         'description' => "Returns description of parameters and attributes.",
                                         'method'      => "GET",
                                         'type'        => "synchronous",  
                                         'attributes'  => "self",
                                         'parameters'  => { 'options'  => {},
                                                            'required' => {},
                                                            'body'     => {} }
                                       },
                                       { 'name'        => "metagenome",
                                         'request'     => $self->cgi->url."/".$self->name."/metagenome",
                                         'description' => "Returns a list of metagenome objects matching the criteria of the options specified.",
                                         'method'      => "GET",
                                         'type'        => "synchronous",  
                                         'attributes'  => $self->{attributes}{metagenome},
                                         'parameters'  => { 'options'  => { 'limit' => ["integer", "maximum number of items requested"],
                                                                            'offset' => ["integer", "zero based index of the first data object to be returned"],
                                                                            'function' => ["string", "query string for function"],
                                                                            'organism' => ["string", "query string for organism"],
                                                                            'metadata' => ["string", "query string for any metadata field"]
                                                                          },
                                                            'required' => {},
                                                            'body'     => {} }
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
    } elsif ($self->rest->[0] eq 'metagenome') {
        $self->query($self->rest->[0]);
    } else {
        $self->info();
    }
}

# return query data: search results
sub query {
    # currently the only type is metagenome
    my ($self, $type) = @_;
    
    # pagination
    my $limit  = $self->cgi->param('limit') ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') ? $self->cgi->param('offset') : 0;
    
    # build url
    my $query_str = "";
    my $solr_query_str = "";
    my %api_to_solr_fields = ( 'function' => 'functions',
                               'organism' => 'organisms',
                               'metadata' => 'metadata' );
    foreach my $field ('function', 'metadata', 'organism') {
        my $solr_field = $api_to_solr_fields{$field};
        if($self->cgi->param($field)) {
            if($query_str ne "") { $query_str .= '&'; }
            if($solr_query_str ne "") { $solr_query_str .= ' '; }
            $query_str .= "$field=".$self->cgi->param($field);
            $solr_query_str .= "$solr_field:".$self->cgi->param($field);
        }
    }

    my $path = '/'.$type;
    my $url = "";
    if($query_str eq "") {
        $url  = $self->cgi->url.'/search'.$path.'?limit='.$limit.'&offset='.$offset;
    } else {
        $url  = $self->cgi->url.'/search'.$path.'?'.$query_str.'&limit='.$limit.'&offset='.$offset;
    }
    
    # get results
    my ($data, $total) = $self->solr_data($solr_query_str, $offset, $limit);
    my $obj = $self->check_pagination($data, $total, $limit, $path);
    $obj->{url} = $url;
    $obj->{version} = 1;

    my $master = $self->connect_to_datasource();
    foreach my $data_item (@{$obj->{data}}) {
        foreach my $return_field (keys %{$self->{return_fields}}) {
            if($return_field eq 'id') {
                my $id = $data_item->{$return_field};
                $id =~ s/^mgm(\d+\.\d+)$/$1/;
                my $job = $master->Job->get_objects( {metagenome_id => $id, viewable => 1} );
                if($job && scalar(@$job)) {
                    $data_item->{job} = $job->[0]->{job_id};
                }
            } elsif($return_field eq 'public') {
                $data_item->{$return_field} = "true";
            } elsif(! exists($data_item->{$return_field})) {
                $data_item->{$return_field} = "";
            }
        }
    }
    
    # return cached if exists
    $self->return_cached();
    # cache this!
    $self->return_data($obj, undef, 1);
}

sub solr_data {
    my ($self, $solr_query_str, $offset, $limit) = @_;
    $solr_query_str = uri_unescape($solr_query_str);
    $solr_query_str = uri_escape($solr_query_str);
    my $fields = ['id', 'name', 'project_id', 'project_name', 'biome', 'feature', 'material', 'country', 'location'];
    return $self->get_solr_query($Conf::job_solr, $Conf::job_collect, $solr_query_str, $offset, $limit, $fields);
}

1;
