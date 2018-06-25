package resources::search;

use strict;
use warnings;
no warnings('once');

use Conf;
use ElasticSearch;
use parent qw(resources::resource);

use URI::Escape qw(uri_escape uri_unescape);

# Override parent constructor
sub new {
    my ( $class, @args ) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);

    # Add name / attributes
    $self->{name}       = "search";
    $self->{attributes} = {};
    $self->{fields}     = $ElasticSearch::fields;

    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name'          => $self->name,
        'url'           => $self->url."/".$self->name,
        'description'   => "Elastic search for Metagenomes",
        'type'          => 'object',
        'documentation' => $self->url.'/api.html#'.$self->name,
        'requests'      => [
            {
                'name'    => "info",
                'request' => $self->url."/".$self->name,
                'description' =>
                  "Returns description of parameters and attributes.",
                'method'     => "GET",
                'type'       => "synchronous",
                'attributes' => "self",
                'parameters' => { 'options' => {}, 'required' => {}, 'body' => {} }
            },
            {
                'name'        => "upsert",
                'request'     => $self->url."/".$self->name."/{ID}",
                'description' => "Elastic Upsert",
                'method'      => "GET",
                'type'        => "synchronous",
                'attributes'  => {
                    "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                    "status"        => [ 'string', 'status of action' ]
                },
                'parameters' => {
                    'options' => {
                        "debug" => [ 'boolean', "if true return ES docuemnt to upsert without POSTing it" ],
                        "index" => [ 'string', "index name, default: metagenome_index" ],
                        "type"  => [
                            'cv',
                            [
                                [ "metadata", "update/insert metadata only, default" ],
                                [ "taxonomy", "update/insert taxonomy annotations (requires metadata upserted)" ],
                                [ "function", "update/insert function annotations (requires metadata upserted)" ],
                                [ "annotation", "update/insert all annotations (requires metadata upserted)" ],
                                [ "all", "update/insert metadata and all annotations" ],
                            ]
                        ]
                    },
                    'required' => { "id" => [ "string", "unique object identifier" ] },
                    'body'     => {}
                }
            },
            {
                'name'        => "query",
                'request'     => $self->url."/".$self->name,
                'description' => "Elastic search",
                'example'     => [ $self->url."/".$self->name."?material=saline water", 'return the first ten datasets that have saline water as the sample material' ],
                'method'     => "GET",
                'type'       => "synchronous",
                'attributes' => $self->attributes,
                'parameters' => {
                    'options' => {
                        "debug"     => [ 'boolean', "if true return ES search query" ],
                        'index'     => [ 'string', "index name, default: metagenome_index" ],
                        'public'    => [ 'boolean', "if true include public data in query" ],
                        'limit'     => [ 'integer', 'maximum number of datasets returned' ],
                        'after'     => [ 'string', 'sort field value to return results after' ],
                        'order'     => [ 'string', 'fieldname to sort by' ],
                        'relevance' => [ 'boolean', "if true order by _score first than order value" ],
                        'direction' => [
                            'cv',
                            [
                                [ 'asc',  'sort data ascending' ],
                                [ 'desc', 'sort data descending' ]
                            ]
                        ]
                    },
                    'required' => {},
                    'body'     => {}
                }
            }
        ]
    };
    $self->return_data($content);
}

# the resource is called with an id parameter
# create ES document and upsert to ES server
sub instance {
    my ($self) = @_;

    # check id format
    my $rest = $self->rest;
    my $mgid = $self->idresolve( $rest->[0] );
    my ( undef, $id ) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if ( ( !$id ) && scalar(@$rest) ) {
        $self->return_data( { "ERROR" => "invalid id format: " . $rest->[0] }, 400 );
    }

    # check rights
    unless ( $self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome')) ) {
        $self->return_data( { "ERROR" => "insufficient permissions for metagenome " . $mgid }, 401 );
    }

    # create and upsert
    my $debug  = $self->cgi->param('debug') ? 1 : 0;
    my $index  = $self->cgi->param('index') || "metagenome_index";
    my $type   = $self->cgi->param('type') || "metadata";
    my $result = {};

    if ( ( $type eq 'metadata' ) || ( $type eq 'all' ) ) {
        $result->{'metadata'} = $self->upsert_to_elasticsearch_metadata( $mgid, $index, $debug );
    }
    if ( ( $type eq 'taxonomy' ) || ( $type eq 'function' ) ) {
        my $temp = $self->upsert_to_elasticsearch_annotation( $mgid, $type, $index, $debug );
        $result->{$type} = $temp->{$type} || "failed";
    }
    if ( ( $type eq 'annotation' ) || ( $type eq 'all' ) ) {
        my $temp = $self->upsert_to_elasticsearch_annotation( $mgid, 'both', $index, $debug );
        $result->{'taxonomy'} = $temp->{'taxonomy'} || "failed";
        $result->{'function'} = $temp->{'function'} || "failed";
    }

    if ($debug) {
        $self->return_data($result);
    }

    my $status = "updated";
    foreach my $k ( keys %$result ) {
        if ( $result->{$k} eq 'failed' ) {
            $status = "failed";
        }
    }

    $self->return_data( { metagenome_id => $mgid, status => $status, result => $result } );
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    $self->json->utf8();

    # get paramaters
    my $index  = $self->cgi->param('index')     || "metagenome_index";
    my $public = $self->cgi->param('public')    || undef;
    my $limit  = $self->cgi->param('limit')     || 10;
    my $after  = $self->cgi->param('after')     || undef;
    my $order  = $self->cgi->param('order')     || "metagenome_id";
    my $dir    = $self->cgi->param('direction') || 'asc';
    my $rel    = $self->cgi->param('relevance') ? 1 : 0;
    my $debug  = $self->cgi->param('debug') ? 1 : 0;

    # validate paramaters
    unless ( ($dir eq 'desc') || ($dir eq 'asc') ) {
        $self->return_data( { "ERROR" => "Direction must be 'asc' or 'desc' only." }, 404 );
    }
    unless ( exists($self->{fields}{$order}) ) {
        $self->return_data( { "ERROR" => "Invalid order field, must be one of the returned fields." }, 404 );
    }
    if ( ( $limit > 1000 ) || ( $limit < 1 ) ) {
        $self->return_data( { "ERROR" => "Limit must be less than 1,000 and greater than 0 ($limit) for query." }, 404 );
    }

    # explicitly setting the default CGI parameters for returned url strings
    $self->cgi->param( 'index',     $index );
    $self->cgi->param( 'limit',     $limit );
    $self->cgi->param( 'after',     $after );
    $self->cgi->param( 'order',     $order );
    $self->cgi->param( 'direction', $dir );
    $self->cgi->param( 'relevance', $rel );

    # get query fields
    my $query = {};
    foreach my $field ( keys %{ $self->{fields} } ) {
        next if $field eq 'public';
        if ( $self->cgi->param($field) ) {
            my $type    = $ElasticSearch::types->{$field};
            my @param   = $self->cgi->param($field);
            my $entries = [];
            foreach my $p (@param) {
                if ( $p =~ /\s/ ) {
                    push( @$entries, split( /\s+/, $p ) );
                }
                else {
                    push( @$entries, $p );
                }
            }
            # use 'term' for keywords, 'match' for others
            my $query_type;
            if ( $field eq "all" ) {
                $field = "all_metadata";
                $query_type = "match";
            } else {
                my $key = $self->{fields}->{$field};
                if ($key =~ /\.keyword$/) {
                    $query_type = "term";
                    $key =~ s/\.keyword$//;
                } elsif ($type eq 'keyword') {
                    $query_type = "term";
                }
                $field = $key;
            }
            $query->{$field} = { "entries" => $entries, "type" => $type, "query" => $query_type };
        }
    }
    my $ins = [];
    my $get_public = ($public && (($public eq "1") || ($public eq "true") || ($public eq "yes"))) ? 1 : 0;
    
    if ( $self->user ) {
        # admin user, get all or filter non-public
        if ( $self->user->has_star_right('view', 'metagenome') ) {
            if ( ! $get_public ) {
                push( @$ins, [ "job_info_public", ["false"], "boolean" ] );
            }
        }
        # reuglar user, filter by id and public
        else {
            my @pids = map { "mgp".$_ } @{ $self->user->has_right_to(undef, 'view', 'project') };
            if ( scalar(@pids) ) {
                push( @$ins, [ "project_project_id", \@pids, "keyword" ] );
            }
            if ( $get_public ) {
                push( @$ins, [ "job_info_public", ["true"], "boolean" ] );
            }
        }
    }
    # no user, filter by only public
    else {
        push( @$ins, [ "job_info_public", ["true"], "boolean" ] );
    }
    
    my ($data, $error) = $self->get_elastic_query($Conf::es_host."/$index/metagenome", $query, $self->{fields}{$order}, $rel, $dir, $after, $limit, $ins, $debug);
    
    if ($debug) {
        $self->return_data( $data, 200 );
    }
    if ($error) {
        $self->return_data( { "ERROR" => "An error occurred: $error" }, 500 );
    }
    
    $self->return_data( $self->prepare_data( $data, $limit, $after ), 200 );
}

sub prepare_data {
    my ( $self, $data, $limit, $after ) = @_;

    my $d = $data->{hits}->{hits} || [];
    my $next_after = undef;
    if (   ( scalar(@$d) > 0 )
        && exists( $d->[-1]{sort} )
        && ( scalar( @{ $d->[-1]{sort} } ) > 0 ) )
    {
        $next_after = $d->[-1]{sort}[0];
    }

    my @params     = $self->cgi->param;
    my $add_params = join( '&',
        map { $_ . "=" . $self->cgi->param($_) }
        grep { $_ ne 'after' } @params );

    my $obj = {
        "total_count" => $data->{hits}->{total} || 0,
        "limit"       => $limit,
        "url"         => $self->url . "/"
          . $self->name
          . "?$add_params"
          . ( $after ? "&after=$after" : "" ),
        "version" => 1,
        "data"    => []
    };
    if ( $next_after && ( $limit == scalar(@$d) ) ) {
        $obj->{next} =
          $self->url . "/" . $self->name . "?$add_params&after=$next_after";
    }

    if ($after) {
        $obj->{after} = $after;
    }

    my %rev = ();
    foreach my $key ( keys( %{ $self->{fields} } ) ) {
        my $val = $self->{fields}->{$key};
        $val =~ s/\.keyword$//;
        $rev{$val} = $key;
    }

    foreach my $set (@$d) {
        my $entry = {};
        foreach my $k ( keys( %{ $set->{_source} } ) ) {
            if ( defined $rev{$k} ) {
                $entry->{ $rev{$k} } = $set->{_source}->{$k};
            }
            else {
                $entry->{$k} = $set->{_source}->{$k};
            }
        }
        push( @{ $obj->{data} }, $entry );
    }

    return $obj;
}

1;
