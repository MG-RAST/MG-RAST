package resources2::search;

use strict;
use warnings;
no warnings('once');

use URI::Escape;
use Digest::MD5;

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
    $self->{return_fields} = {'job'           => [ 'string', 'MG-RAST internal job number' ],
                              'id'            => [ 'string', 'metagenome id' ],
                              'name'          => [ 'string', 'name of metagenome' ],
                              'project_id'    => [ 'string', 'project containing metagenome' ],
                              'project_name'  => [ 'string', 'project containing metagenome' ],
                              'status'        => [ 'string', 'public/private status of metagenome' ],
                              'biome'         => [ 'string', 'environmental biome, EnvO term' ],
                              'feature'       => [ 'string', 'environmental feature, EnvO term' ],
                              'material'      => [ 'string', 'environmental material, EnvO term' ],
                              'country'       => [ 'string', 'country' ],
                              'location'      => [ 'string', 'location' ],
                              'sequence_type' => [ 'string', 'type of sequence library (Amplicon, mt, Unknown, WGS)' ],
                              'PI_lastname'   => [ 'string', 'principal investigator\'s last name' ]};

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
                                         'parameters'  => { 'options'  => { 'limit'     => ["integer", "maximum number of items requested"],
                                                                            'offset'    => ["integer", "zero based index of the first data object to be returned"],
                                                                            'md5'       => ["string", "md5 checksum of feature sequence"],
                                                                            'function'  => ["string", "query string for function"],
                                                                            'metadata'  => ["string", "query string for any metadata field"],
                                                                            'organism'  => ["string", "query string for organism"],
                                                                            'order'     => ["string", "metagenome object field to sort by (default is id)"],
                                                                            'direction' => ["cv", "sort direction: asc for ascending (default), desc for descending"],
                                                                            'match'     => ["cv", "boolean operator for search fields: all (default), any"],
                                                                            'status'    => ["cv", "public, private, both (default)"]
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

    # sorting
    my $order = $self->cgi->param('order') ? $self->cgi->param('order') : 'id';
    my $direction = $self->cgi->param('direction') ? $self->cgi->param('direction') : 'asc';
    my $match = $self->cgi->param('match') ? $self->cgi->param('match') : 'all';
    my $status = $self->cgi->param('status') ? $self->cgi->param('status') : 'both';

    # explicitly setting the default CGI parameters for returned url strings
    $self->cgi->param('limit', $limit);
    $self->cgi->param('offset', $offset);
    $self->cgi->param('order', $order);
    $self->cgi->param('direction', $direction);
    $self->cgi->param('match', $match);
    $self->cgi->param('status', $status);

    unless(exists($self->{return_fields}->{$order})) {
        $order = 'id';
    }

    unless($direction eq 'asc' || $direction eq 'desc') {
        $direction = 'asc';
    }

    unless($match eq 'all' || $match eq 'any') {
        $match = 'all';
    }

    unless($status eq 'public' || $status eq 'private' || $status eq 'both') {
        $status = 'both';
    }

    # build url
    my $query_str = "";
    my $solr_query_str = "";
    foreach my $field ('md5', 'function', 'metadata', 'organism') {
        if($self->cgi->param($field)) {
            if($query_str ne "") {
                $query_str .= '&';
                if($match eq 'all') {
                    $solr_query_str .= ' AND ';
                } else {
                    $solr_query_str .= ' OR ';
                }
            }
            $query_str .= "$field=".$self->cgi->param($field);
            $solr_query_str .= "($field:".$self->cgi->param($field);
        }
    }

    # all non-numeric fields must use separate solr string field for sorting
    unless($order eq 'job' || $order eq 'sequence_type') {
        $order .= "_sort";
    }

    # complete solr query and add rights
    if($solr_query_str ne "") {
        $solr_query_str .= ') AND ';
    }

    my $return_empty_set = 0;

    if($status eq 'public') {
        $solr_query_str .= '(status:public)';
    } elsif($status eq 'private') {
        if($self->user) {
            if($self->user->has_star_right('view', 'metagenome')) {
                $solr_query_str .= "(status:private)";
            } else {
                my $userjobs = $self->user->has_right_to(undef, 'view', 'metagenome');
                if ($userjobs->[0] eq '*') {
                    $solr_query_str .= "(status:private)";
                } elsif ( @$userjobs > 0 ) {
                    $solr_query_str .= "((status:private AND (id:mgm".join(" OR id:mgm", map {"$_"} @$userjobs).")))";
                } else {
                    $return_empty_set = 1;
                }
            }
        } else {
            $self->return_data( {"ERROR" => "a search with status=private requires authentication and this request was not authenticated"}, 401 );
        }
    } else {
        if($self->user) {
            if($self->user->has_star_right('view', 'metagenome')) {
                $solr_query_str .= "(status:*)";
            } else {
                my $userjobs = $self->user->has_right_to(undef, 'view', 'metagenome');
                if ($userjobs->[0] eq '*') {
                    $solr_query_str .= "(status:*)";
                } elsif ( @$userjobs > 0 ) {
                    $solr_query_str .= "((status:public) OR (status:private AND (id:mgm".join(" OR id:mgm", map {"$_"} @$userjobs).")))";
                } else {
                    $solr_query_str .= '(status:public)';
                }
            }
        } else {
            $solr_query_str .= '(status:public)';
        }
    }

    # get results
    my $data;
    my $total;
    if($return_empty_set == 1) {
        $data = [];
        $total = 0;
    } else {
        ($data, $total) = $self->solr_data($solr_query_str, "$order $direction", $offset, $limit);
    }
    my $obj = $self->check_pagination($data, $total, $limit, "/$type");
    $obj->{version} = 1;

    foreach my $data_item (@{$obj->{data}}) {
        foreach my $return_field (keys %{$self->{return_fields}}) {
            if(! exists($data_item->{$return_field})) {
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
    my ($self, $solr_query_str, $sort_field, $offset, $limit) = @_;
    $solr_query_str = uri_unescape($solr_query_str);
    $solr_query_str = uri_escape($solr_query_str);
    my $fields = ['job', 'id', 'name', 'project_id', 'project_name', 'status', 'biome', 'feature', 'material', 'country', 'location', 'sequence_type', 'PI_lastname'];
    return $self->get_solr_query("POST", $Conf::job_solr, $Conf::job_collect, $solr_query_str, $sort_field, $offset, $limit, $fields);
}

1;
