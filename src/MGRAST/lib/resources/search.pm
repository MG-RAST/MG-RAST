package resources::search;

use strict;
use warnings;
no warnings('once');

use Conf;
use ElasticSearch;
use parent qw(resources::resource);
use Encode qw(decode_utf8 encode_utf8);

use JSON;
use URI::Escape qw(uri_escape uri_unescape);
use List::MoreUtils qw(any uniq);

# Override parent constructor
sub new {
    my ( $class, @args ) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);

    # Add name / attributes
    $self->{name}       = "search";
    $self->{attributes} = {};
    $self->{fields}     = $ElasticSearch::fields;
    $self->{field_opts} = { map {$_, ['string', 'metadata to filter results by']} keys %{$self->{fields}} };
    $self->{query_opts} = {
        'debug'     => [ 'boolean', "if true return ES search query" ],
        'index'     => [ 'string', "index name, default: metagenome_index" ],
        'public'    => [ 'boolean', "if true include public data in query" ],
        'limit'     => [ 'integer', 'maximum number of datasets returned' ],
        'after'     => [ 'string', 'sort field value to return results after' ],
        'order'     => [ 'string', 'fieldname to sort by' ],
        'no_score'  => [ 'boolean', "if true do not use _score for first level ordering" ],
        'direction' => [
            'cv',
            [
                [ 'asc',  'sort data ascending' ],
                [ 'desc', 'sort data descending' ]
            ]],
        'match' => [
            'cv',
            [
                ['all', 'return that match all (AND) search parameters'],
                ['any', 'return that match any (OR) search parameters']
            ]],
        'function'   => [ 'string', "function name to filter results by" ],
        'func_per'   => [ 'integer', "percent abundance cutoff for function name" ],
        'taxonomy'   => [ 'string', "taxonomy name to filter results by" ],
        'taxa_per'   => [ 'integer', "percent abundance cutoff for taxonomy name" ],
        'taxa_level' => [ 'string', "taxonomic level the name belongs to, required with percent cutoff" ]
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
                'request'     => $self->url."/".$self->name."/{id}",
                'description' => "Elastic Upsert",
                'method'      => "POST",
                'type'        => "synchronous",
                'attributes'  => {
                    "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                    "status"        => [ 'string', 'status of action' ]
                },
                'parameters' => {
                    'options'  => {},
                    'required' => { "id" => [ "string", "unique object identifier" ] },
                    'body'     => {
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
                        ],
                        "function" => [ 'list', ['object', 'tuple of function name (string) and abundance (int)'] ],
                        "taxonomy" => [ 'object', 'mapping of taxa level name (string) to list of tuples: taxa name (string) and abundace (int)' ]
                    }
                }
            },
            {
                'name'        => "query",
                'request'     => $self->url."/".$self->name,
                'description' => "Elastic search",
                'example'     => [ $self->url."/".$self->name."?material=saline water", 'return the first ten datasets that have saline water as the sample material' ],
                'method'     => "GET",
                'type'       => "synchronous",
                'attributes' => $self->{attributes},
                'parameters' => {
                    'options'  => { %{$self->{field_opts}}, %{$self->{query_opts}} },
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
    my $post  = $self->get_post_data(['debug', 'index'. 'type', 'function', 'taxonomy']);
    my $debug = $post->{'debug'} ? 1 : 0;
    my $index = $post->{'index'} || "metagenome_index";
    my $type  = $post->{'type'}  || "metadata";
    my $func  = $post->{'function'} || undef;
    my $taxa  = $post->{'taxonomy'} || undef;
    
    my $result = {};

    if ( ( $type eq 'metadata' ) || ( $type eq 'all' ) ) {
        $result->{'metadata'} = $self->upsert_to_elasticsearch_metadata( $mgid, $index, $debug );
    }
    if ( ( $type eq 'taxonomy' ) || ( $type eq 'function' ) ) {
        my $temp = $self->upsert_to_elasticsearch_annotation( $mgid, $type, $index, $func, $taxa, $debug );
        $result->{$type} = $temp->{$type} || "failed";
    }
    if ( ( $type eq 'annotation' ) || ( $type eq 'all' ) ) {
        my $temp = $self->upsert_to_elasticsearch_annotation( $mgid, 'both', $index, $func, $taxa, $debug );
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
    
    # whitelist parameters
    my @all_params = $self->cgi->param;
    foreach my $p (@all_params) {
        if ( $p =~ /^\_/ ) {
            next;
        }
        unless (exists($self->{query_opts}{$p}) || exists($self->{fields}{$p})) {
            $self->return_data( { "ERROR" => "Invalid parameter: $p" }, 404 );
        }
    }

    # get paramaters
    my $index  = $self->cgi->param('index')     || "metagenome_index";
    my $public = $self->cgi->param('public')    || undef;
    my $limit  = $self->cgi->param('limit')     || 10;
    my $after  = $self->cgi->param('after')     || undef;
    my $order  = $self->cgi->param('order')     || "metagenome_id";
    my $dir    = $self->cgi->param('direction') || 'asc';
    my $match  = $self->cgi->param('match')     || 'all';
    my $no_scr = $self->cgi->param('no_score')  || undef;
    my $debug  = $self->cgi->param('debug')     || undef;

    # validate paramaters
    unless ( ($match eq 'all') || ($match eq 'any') ) {
        $self->return_data( { "ERROR" => "Match must be 'all' or 'any' only." }, 404 );
    }
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
    $self->cgi->param( 'order',     $order );
    $self->cgi->param( 'direction', $dir );
    $self->cgi->param( 'match',     $match );

    # get query fields
    my $queries = [];
    foreach my $field ( keys %{ $self->{fields} } ) {
        next if $field eq 'public';
        if ( $self->cgi->param($field) ) {
            my $type  = $ElasticSearch::types->{$field};
            my @param = decode_utf8($self->cgi->param($field));
            my $key   = $self->{fields}{$field};
            $key =~ s/\.keyword$//;
            # clean query whitespace
            my $query = join(' ', @param);
            $query =~ s/^\s+|\s+$//g;
            $query =~ s/\s+/ /g;
            # remove specified fields (non-escaped ':'), only using set default
            # if (($query =~ /:/) && ($query !~ /\\:/)) {
            #     my @parts = split(/:/, $query);
            #     $query = join(" ", @parts[1..$#parts]);
            # }
            # remove specified fields (non-escaped ':'), only using set default
            if (( $field !~ /_tag/ ) && ($query =~ /:/) && ($query !~ /\\:/)) {
                my @parts = split(/:/, $query);
                $query = join(" ", @parts[1..$#parts]);
            }
            else {
		        $query=~s/\:/\\\:/g
            }
            push @$queries, {"field" => $key, "query" => $query, "type" => $type};
        }
    }
    
    # get taxa / func queries
    my $function   = $self->cgi->param('function')   || undef;
    my $func_per   = $self->cgi->param('func_per')   || undef;
    my $taxonomy   = $self->cgi->param('taxonomy')   || undef;
    my $taxa_per   = $self->cgi->param('taxa_per')   || undef;
    my $taxa_level = $self->cgi->param('taxa_level') || undef;
 
    if ( $function ) {
        if ($function =~ /:/) {
            my @parts = split(/:/, $function);
            $function = join(" ", @parts[1..$#parts])
        }
        if ( $func_per ) {
            if ( any {$_ == $func_per} @{$ElasticSearch::func_num} ) {
                push @$queries, {"field" => "f_".$func_per, "query" => $function, "type" => "child", "name" => "function"};
            } else {
                $self->return_data( { "ERROR" => "func_per must be one of: ".join(", ", @{$ElasticSearch::func_num}) }, 404 );
            }
        } else {
            push @$queries, {"field" => "all", "query" => $function, "type" => "child", "name" => "function"};
        }
    }
    if ( $taxonomy ) {
        if ($taxonomy =~ /:/) {
            my @parts = split(/:/, $taxonomy);
            $taxonomy = join(" ", @parts[1..$#parts])
        }
        if ( $taxa_per && $taxa_level ) {
            my $taxa_query = lc(substr($taxa_level, 0, 1))."_".$taxonomy;
            if ( any {$_ == $taxa_per} @{$ElasticSearch::taxa_num} ) {
                push @$queries, {"field" => "t_".$taxa_per, "query" => $taxa_query, "type" => "child", "name" => "taxonomy"};
            } else {
                $self->return_data( { "ERROR" => "taxa_per must be one of: ".join(", ", @{$ElasticSearch::taxa_num}) }, 404 );
            }
        } elsif ( (! $taxa_per) && (! $taxa_level) ) {
            push @$queries, {"field" => "all", "query" => $taxonomy, "type" => "child", "name" => "taxonomy"};
        } else {
            $self->return_data( { "ERROR" => "both taxa_per and taxa_level must be used together" }, 404 );
        }
    }
        
    # get filters - this are "or" - only for public/private selection
    my $filters = [];
    my $no_pub = ($public && (($public eq "1") || ($public eq "true") || ($public eq "yes"))) ? 0 : 1;
    if ( $self->user ) {
        # not admin user, filter by id
        unless ( $self->user->has_star_right('view', 'metagenome') ) {
            my @pids = map { "mgp".$_ } @{ $self->user->has_right_to(undef, 'view', 'project') };
            if ( scalar(@pids) ) {
                push( @$filters, [ "project_project_id", [ @pids ] ] );
            }
            unless ( $no_pub ) {
                push( @$filters, [ "job_info_public", [ JSON::true ] ] );
            }
        }
    }
    # no user, filter by only public
    else {
        push( @$filters, [ "job_info_public", [ JSON::true ] ] );
        $no_pub = 0;
    }
    
    my $es_url = $Conf::es_host."/".$index."/metagenome";
    my ($data, $error) = $self->get_elastic_query($es_url, $queries, $self->{fields}{$order}, $no_scr, $dir, $match, $after, $limit, $filters, $no_pub, $debug);

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
        $next_after = join(",", @{$d->[-1]{sort}});
    }

    my @params     = $self->cgi->param;
    my $add_params = join( '&',
        map { $_ . "=" . decode_utf8($self->cgi->param($_)) }
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
    if ( defined($next_after) && ( $limit == scalar(@$d) ) ) {
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
            # skip merged fields
            if ($k =~ /^all/) {
                next;
            }
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
