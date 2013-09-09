package resources::resource;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use CGI;
use JSON;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex md5_base64);

1;

sub new {
    my ($class, $params) = @_;

    # set variables
    my $memd = undef;
    eval {
        require Cache::Memcached;
        Cache::Memcached->import();
        $memd = new Cache::Memcached {'servers' => [$Conf::web_memcache], 'debug' => 0, 'compress_threshold' => 10_000};
    };
    my $agent = LWP::UserAgent->new;
    my $json  = JSON->new;
    my $url_id = get_url_id($params->{cgi}, $params->{resource}, $params->{rest_parameters}, $params->{json_rpc}, $params->{user});
    $json = $json->utf8();
    $json->max_size(0);
    $json->allow_nonref;
    my $html_messages = { 200 => "OK",
                          201 => "Created",
                          204 => "No Content",
                          400 => "Bad Request",
                          401 => "Unauthorized",
    		              404 => "Not Found",
    		              416 => "Request Range Not Satisfiable",
    		              500 => "Internal Server Error",
    		              501 => "Not Implemented",
    		              503 => "Service Unavailable",
    		              507 => "Storing object failed",
    		              -32602 => "Invalid params",
    		              -32603 => "Internal error"
    		              };
    # create object
    my $self = {
        format        => "application/json",
        agent         => $agent,
        memd          => $memd,
        json          => $json,
        cgi           => $params->{cgi},
        rest          => $params->{rest_parameters} || [],
        method        => $params->{method},
        submethod     => $params->{submethod},
        resource      => $params->{resource},
        user          => $params->{user},
        token         => $params->{cgi}->http('HTTP_AUTH') || undef,
        json_rpc      => $params->{json_rpc} ? $params->{json_rpc} : 0,
        json_rpc_id   => ($params->{json_rpc} && exists($params->{json_rpc_id})) ? $params->{json_rpc_id} : undef,
        html_messages => $html_messages,
        expire        => $Conf::web_memcache_expire || 172800, # use config or 48 hours
        name          => '',
        url_id        => $url_id,
        rights        => {},
        attributes    => {}
    };
    bless $self, $class;
    return $self;
}

### make a unique id for each resource / option combination (no auth)
sub get_url_id {
    my ($cgi, $resource, $rest, $rpc, $user) = @_;
    my $rurl = $cgi->url(-relative=>1).$resource;
    my %params = map { $_ => [$cgi->param($_)] } $cgi->param;
    foreach my $r (@$rest) {
        $rurl .= $r;
    }
    foreach my $p (sort keys %params) {
        next if ($p eq 'auth');
        $rurl .= $p.join("", sort @{$params{$p}});
    }
    if ($rpc) {
        $rurl .= 'jsonrpc';
    }
    if ($user) {
        $rurl .= $user->login;
    }
    return md5_hex($rurl);
}

# get functions for class variables
sub agent {
    my ($self) = @_;
    return $self->{agent};
}
sub memd {
    my ($self) = @_;
    return $self->{memd};
}
sub json {
    my ($self) = @_;
    return $self->{json};
}
sub cgi {
    my ($self) = @_;
    return $self->{cgi};
}
sub rest {
    my ($self) = @_;
    return $self->{rest};
}
sub method {
    my ($self) = @_;
    return $self->{method};
}
sub submethod {
    my ($self) = @_;
    return $self->{submethod};
}
sub user {
    my ($self) = @_;
    return $self->{user};
}
sub token {
    my ($self) = @_;
    return $self->{token};
}
sub json_rpc {
    my ($self) = @_;
    return $self->{json_rpc};
}
sub json_rpc_id {
    my ($self) = @_;
    return $self->{json_rpc_id};
}
sub html_messages {
    my ($self) = @_;
    return $self->{html_messages};
}
sub name {
    my ($self) = @_;
    return $self->{name};
}
sub url_id {
    my ($self) = @_;
    return $self->{url_id};
}
sub rights {
    my ($self) = @_;
    return $self->{rights};
}
sub attributes {
    my ($self) = @_;
    return $self->{attributes};
}

# hardcoded source info
sub source {
    return { m5nr     => ["M5NR", "comprehensive protein database"],
             m5rna    => ["M5RNA", "comprehensive RNA database"],
             protein  => [ ["RefSeq", "protein database, type organism, function, feature"],
					       ["GenBank", "protein database, type organism, function, feature"],
			               ["IMG", "protein database, type organism, function, feature"],
				           ["SEED", "protein database, type organism, function, feature"],
				           ["TrEMBL", "protein database, type organism, function, feature"],
			               ["SwissProt", "protein database, type organism, function, feature"],
					       ["PATRIC", "protein database, type organism, function, feature"],
					       ["KEGG", "protein database, type organism, function, feature"] ],
             rna      => [ ["RDP", "RNA database, type organism, function, feature"],
			               ["Greengenes", "RNA database, type organism, function, feature"],
		                   ["LSU", "RNA database, type organism, function, feature"],
		                   ["SSU", "RNA database, type organism, function, feature"] ],
             ontology => [ ["Subsystems", "ontology database, type ontology only"],
                           ["NOG", "ontology database, type ontology only"],
                           ["COG", "ontology database, type ontology only"],
                           ["KO", "ontology database, type ontology only"] ]
    };
}

# hardcoded hierarchy info
sub hierarchy {
    return { organism => [ ['strain', 'bottom organism taxanomic level'],
                           ['species', 'organism type level'],
                           ['genus', 'organism taxanomic level'],
                           ['family', 'organism taxanomic level'],
                           ['order', 'organism taxanomic level'],
                           ['class', 'organism taxanomic level'],
                           ['phylum', 'organism taxanomic level'],
                           ['domain', 'top organism taxanomic level'] ],
             ontology => [ ['function', 'bottom function ontology level'],
                           ['level3', 'function ontology level' ],
                           ['level2', 'function ontology level' ],
                           ['level1', 'top function ontology level'] ]
    };
}

# hardcoded list of metagenome sequence statistics names
sub seq_stats {
    return [ 'alpha_diversity_shannon',
             'ambig_char_count_preprocessed',
             'ambig_char_count_preprocessed_rna',
             'ambig_char_count_raw',
             'ambig_sequence_count_preprocessed',
             'ambig_sequence_count_preprocessed_rna',
             'ambig_sequence_count_raw',
             'average_ambig_chars_preprocessed',
             'average_ambig_chars_preprocessed_rna',
             'average_ambig_chars_raw',
             'average_gc_content_preprocessed',
             'average_gc_content_preprocessed_rna',
             'average_gc_content_raw',
             'average_gc_ratio_preprocessed',
             'average_gc_ratio_preprocessed_rna',
             'average_gc_ratio_raw',
             'average_length_preprocessed',
             'average_length_preprocessed_rna',
             'average_length_raw',
             'bp_count_preprocessed',
             'bp_count_preprocessed_rna',
             'bp_count_raw',
             'clustered_sequence_count_processed',
             'clustered_sequence_count_processed_aa',
             'clustered_sequence_count_processed_rna',
             'cluster_count_processed',
             'cluster_count_processed_aa',
             'cluster_count_processed_rna',
             'drisee_score_raw',
             'length_max_preprocessed',
             'length_max_preprocessed_rna',
             'length_max_raw',
             'length_min_preprocessed',
             'length_min_preprocessed_rna',
             'length_min_raw',
             'ratio_reads_aa',
             'ratio_reads_rna',
             'read_count_annotated',
             'read_count_processed_aa',
             'read_count_processed_rna',
             'sequence_count_dereplication_removed',
             'sequence_count_ontology',
             'sequence_count_preprocessed',
             'sequence_count_preprocessed_rna',
             'sequence_count_processed',
             'sequence_count_processed_aa',
             'sequence_count_processed_rna',
             'sequence_count_raw',
             'sequence_count_sims_aa',
             'sequence_count_sims_rna',
             'standard_deviation_gc_content_preprocessed',
             'standard_deviation_gc_content_preprocessed_rna',
             'standard_deviation_gc_content_raw',
             'standard_deviation_gc_ratio_preprocessed',
             'standard_deviation_gc_ratio_preprocessed_rna',
             'standard_deviation_gc_ratio_raw',
             'standard_deviation_length_preprocessed',
             'standard_deviation_length_preprocessed_rna',
             'standard_deviation_length_raw'
    ];
}

# get / set functions for class variables
sub format {
    my ($self, $format) = @_;
    if ($format) {
        $self->{format} = $format;
    }
    return $self->{format};
}

# get cgi header
sub header {
    my ($self, $status) =  @_;
    return $self->cgi->header( -type => $self->format,
	                           -status => $status,
	                           -Access_Control_Allow_Origin => '*' );
}

# method initially called from the api module
# method to parse parameters and decide which requests to process
# overide this if not doing standard info / instance / query options
sub request {
    my ($self) = @_;

    # check for parameters
    my @parameters = $self->cgi->param;
    if ( (scalar(@{$self->rest}) == 0) &&
         ((scalar(@parameters) == 0) || ((scalar(@parameters) == 1) && ($parameters[0] eq 'keywords'))) )
    {
        $self->info();
    }

    # check for id
    if ( scalar(@{$self->rest}) ) {
        $self->instance();
    } else {
        $self->query();
    }
}

# get a connection to the datasource
sub connect_to_datasource {
    my ($self) = @_;

    my ($master, $error);
    eval {
        require WebServiceObject;
        WebServiceObject->import();
        ($master, $error) = WebServiceObject::db_connect();
    };

    if ($@ || $error || (! $master)) {
        $self->return_data({ "ERROR" => "resource database offline" }, 503);
    } else {
        return $master;
    }
}

# check if pagination parameters are used
sub check_pagination {
    my ($self, $data, $total, $limit, $path) = @_;

    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order') || undef;
    my @params = $self->cgi->param;
    $total = int($total);
    $limit = int($limit);
    $path  = $path || "";
    
    my $total_count = $total || scalar(@$data);
    my $prev_offset = (($offset - $limit) < 0) ? 0 : $offset - $limit;
    my $next_offset = $offset + $limit;
    
    my $object = { "limit" => int($limit),
	               "offset" => int($offset),
	               "total_count" => int($total_count),
	               "data" => $data };

    # don't build urls for POST
    if ($self->method eq 'GET') {
        my $add_params  = join('&', map {$_."=".$self->cgi->param($_)} grep {$_ ne 'offset'} @params);
        $object->{url}  = $self->cgi->url."/".$self->name.$path."?$add_params&offset=$offset";
        $object->{prev} = ($offset > 0) ? $self->cgi->url."/".$self->name.$path."?$add_params&offset=$prev_offset" : undef;
        $object->{next} = (($offset < $total_count) && ($total_count > $limit)) ? $self->cgi->url."/".$self->name.$path."?$add_params&offset=$next_offset" : undef;
    }
	if ($order) {
	    $object->{order} = $order;
    }
    
	return $object;
}

# return cached data if exists
sub return_cached {
    my ($self) = @_;
    
    if ($self->memd) {
        my $cached = $self->memd->get($self->url_id);
        if ($cached) {
            # do a runaround on ->return_data
            print $self->header;
            print $cached;
            exit 0;
        }
    }
}

# print the actual data output
sub return_data {
    my ($self, $data, $error, $cache_me) = @_;

    # default status is OK
    my $status = 200;  
  
    # if the result is an empty array, status is 204
    if (ref($data) eq "ARRAY" && scalar(@$data) == 0) {
        $status = 204;
    }

    # if an error is passed, change the return format to text 
    # and change the status code to the error code passed
    if ($error) {
        $self->format("application/json");
        $status = $error;
    }

    # check for remote procedure call
    if ($self->json_rpc) {
        # check to comply to Bob Standards
        unless (ref($data) eq 'ARRAY') {
            $data = [ $data ];
        }

        # only reply if this is not a notification
        if ($error) {
	        my $error_code = $status;
	        if ($status == 400) {
	            $status = -32602;
	        } elsif ($status == 500) {
	            $status = -32603;
	        }
	        # there was an error
	        $data = { jsonrpc => "2.0",
                      error => { code    => $error_code,
                                 message => $self->html_messages->{$status},
                                 data    => $data->[0] },
                      id => $self->json_rpc_id };
        } else {
	        # normal result
	        $data = { jsonrpc => "2.0",
		              result  => $data,
		              id      => $self->json_rpc_id };
		    # cache this!
            if ($cache_me && $self->memd) {
                $self->memd->set($self->url_id, $self->json->encode($data), $self->{expire});
            }
        }
        print $self->header($status);
        print $self->json->encode($data);
        exit 0;
    }
    else {
        # check for JSONP
        if ($self->cgi->param('callback')) {
            if ($self->format ne "application/json") {
	            $data = { 'data' => $data };
            }
            $self->format("application/json");
            print $self->header($status);
            print $self->cgi->param('callback')."(".$self->json->encode($data).");";
            exit 0;
        }
        # normal return
        else {
            if ($self->format eq 'application/json') {
                $data = $self->json->encode($data);
            }
            # cache this!
            if ($cache_me && $self->memd) {
                $self->memd->set($self->url_id, $data, $self->{expire});
            }
            # send it
            print $self->header($status);
            print $data;
            exit 0;
        }
    }
}

# print a file to download
sub return_file {
    my ($self, $filedir, $filename) = @_;
    
    unless ("$filedir/$filename" && (-s "$filedir/$filename")) {
	    $self->return_data( {"ERROR" => "could not access filesystem"}, 404 );
    }
    if (open(FH, "<$filedir/$filename")) {
	    print "Content-Type:application/x-download\n";  
	    print "Access-Control-Allow-Origin: *\n";
	    print "Content-Length: " . (stat("$filedir/$filename"))[7] . "\n";
	    print "Content-Disposition:attachment;filename=$filename\n\n";
	    while (<FH>) {
	        print $_;
	    }
	    close FH;
	    exit 0;
    } else {
	    $self->return_data( {"ERROR" => "could not access requested file: $filename"}, 404 );
    }
}

sub get_sequence_sets {
    my ($self, $job) = @_;
  
    my $mgid = $job->metagenome_id;
    my $rdir = $job->download_dir;
    my $adir = $job->analysis_dir;
    my $stages = [];
    if (opendir(my $dh, $rdir)) {
        my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
        closedir $dh;
        my $fnum = 1;
        foreach my $rf (@rawfiles) {
            my ($jid, $ftype) = $rf =~ /^(\d+)\.(fna|fastq)(\.gz)?$/;
            push(@$stages, { id  => "mgm".$mgid,
                             url => $self->cgi->url.'/download/mgm'.$mgid.'?file=050.'.$fnum,
		                     stage_id   => "050",
		                     stage_name => "upload",
		                     stage_type => $ftype,
		                     file_id    => "050.".$fnum,
		                     file_name  => $rf });
            $fnum += 1;
        }
    }
    if (opendir(my $dh, $adir)) {
        my @stagefiles = sort grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
        closedir $dh;
        my $stagehash = {};
        foreach my $sf (@stagefiles) {
            my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
            next unless ($stageid && $stagename && $stageresult);
            if (exists($stagehash->{$stageid})) {
	            $stagehash->{$stageid}++;
            } else {
	            $stagehash->{$stageid} = 1;
            }
            push(@$stages, { id  => "mgm".$mgid,
                             url => $self->cgi->url.'/download/mgm'.$mgid.'?file='.$stageid.'.'.$stagehash->{$stageid},
		                     stage_id   => $stageid,
		                     stage_name => $stagename,
		                     stage_type => $stageresult,
		                     file_id    => $stageid.".".$stagehash->{$stageid},
		                     file_name  => $sf });
        }
    }
    return $stages;
}

sub edit_shock_acl {
    my ($self, $id, $auth, $email, $action, $acl) = @_;
    
    my $response = undef;
    my $url = $Conf::shock_url.'/node/'.$id.'/acl?'.$acl.'='.$email;
    eval {
        my $tmp = undef;
        if ($action eq 'delete') {
            $tmp = $self->agent->delete($url, 'Authorization' => "OAuth $auth");
        } elsif ($action eq 'put') {
            $tmp = $self->agent->put($url, 'Authorization' => "OAuth $auth");
        } else {
            $self->return_data( {"ERROR" => "Invalid Shock ACL action: $action"}, 500 );
        }
        $response = $self->json->decode( $tmp->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to $action ACL '$acl' to node $id in Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

sub set_shock_node {
    my ($self, $name, $file, $attr, $auth) = @_;
    
    my $attr_str = $self->json->encode($attr);
    my $file_str = $self->json->encode($file);
    my $content  = [attributes => [undef, "$name.json", Content => $attr_str], upload => [undef, $name, Content => $file_str]];
    my $response = undef;
    eval {
        my $post = undef;
        if ($auth) {
            $post = $self->agent->post($Conf::shock_url.'/node', $content, Content_Type => 'form-data', Authorization => "OAuth $auth");
        } else {
            $post = $self->agent->post($Conf::shock_url.'/node', $content, Content_Type => 'form-data');
        }
        $response = $self->json->decode( $post->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to POST to Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

sub get_shock_node {
    my ($self, $id, $auth) = @_;
    
    my $content = undef;
    eval {
        my $get = undef;
        if ($auth) {
            $get = $self->agent->get($Conf::shock_url.'/node/'.$id, 'Authorization' => "OAuth $auth");
        } else {
            $get = $self->agent->get($Conf::shock_url.'/node/'.$id);
        }
        $content = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($content))) {
        return undef;
    } elsif (exists($content->{error}) && $content->{error}) {
        $self->return_data( {"ERROR" => "Unable to GET node $id from Shock: ".$content->{error}[0]}, $content->{status} );
    } else {
        return $content->{data};
    }
}

sub get_shock_file {
    my ($self, $id, $file, $auth) = @_;
    
    my $content = undef;
    eval {
        my $get = undef;
        if ($auth) {
            $get = $self->agent->get($Conf::shock_url.'/node/'.$id.'?download', 'Authorization' => "OAuth $auth");
        } else {
            $get = $self->agent->get($Conf::shock_url.'/node/'.$id.'?download');
        }
        $content = $get->content;
    };
    if ($@ || (! $content)) {
        return undef;
    } elsif (ref($content) && exists($content->{error}) && $content->{error}) {
        $self->return_data( {"ERROR" => "Unable to GET file $id from Shock: ".$content->{error}[0]}, $content->{status} );
    } elsif ($file) {
        if (open(FILE, ">$file")) {
            print FILE $content;
            close(FILE);
            return 1;
        } else {
            return undef;
        }
    } else {
        return $content;
    }
}

sub get_shock_query {
    my ($self, $params, $auth) = @_;
    
    my $shock = undef;
    my $query = '?query&limit=0';
    if ($params && (scalar(keys %$params) > 0)) {
        map { $query .= '&'.$_.'='.$params->{$_} } keys %$params;
    }
    eval {
        my $get = undef;
        if ($auth) {
            $get = $self->agent->get($Conf::shock_url.'/node'.$query, 'Authorization' => "OAuth $auth");
        } else {
            $get = $self->agent->get($Conf::shock_url.'/node'.$query);
        }
        $shock = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($shock))) {
        return [];
    } elsif (exists($shock->{error}) && $shock->{error}) {
        $self->return_data( {"ERROR" => "Unable to query Shock: ".$shock->{error}[0]}, $shock->{status} );
    } else {
        return $shock->{data};
    }
}

sub get_solr_query {
    my ($self, $method, $server, $collect, $query, $sort, $offset, $limit, $fields) = @_;
    
    my $content = undef;
    my $url  = $server.'/'.$collect.'/select';
    my $data = 'q=*%3A*&fq='.$query.'&start='.$offset.'&rows='.$limit.'&wt=json';
    if ($sort) {
        $data .= '&sort='.$sort;
    }
    if ($fields && (@$fields > 0)) {
        $data .= '&fl='.join('%2C', @$fields);
    }
    eval {
        my $res = undef;
        if ($method eq 'GET') {
            $res = $self->agent->get($url.'?'.$data);
        }
        if ($method eq 'POST') {
            $res = $self->agent->post($url, Content => $data);
        }
        $content = $self->json->decode( $res->content );
    };
    if ($@ || (! ref($content))) {
        return ([], 0);
    } elsif (exists $content->{error}) {
        $self->return_data( {"ERROR" => "Unable to query DB: ".$content->{error}{msg}}, $content->{error}{status} );
    } elsif (exists $content->{response}) {
        return ($content->{response}{docs}, $content->{response}{numFound});
    } elsif (exists $content->{grouped}) {
        return $content->{grouped};
    } else {
        $self->return_data( {"ERROR" => "Invalid SOLR return response"}, 500 );
    }
}

# I can't find a perl library that gives me random UUID !
sub uuidv4 {
    my ($self) = @_;
    my $uuid = `python -c "import uuid; print uuid.uuid4()"`;
    chomp $uuid;
    return $uuid;
}

sub toFloat {
    my ($self, $x) = @_;
    return $x * 1.0;
}

sub toNum {
    my ($self, $x, $type) = @_;
    if ($type eq 'abundance') {
        return int($x);
    } else {
        return $x * 1.0;
    }
}

###################################################
#  stub functions - replace these in child class  #
###################################################

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    return undef;
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    return $self->info();
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
    return $self->info();
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;
    return undef;
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }
