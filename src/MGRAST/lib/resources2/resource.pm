package resources2::resource;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use CGI;
use JSON;
use LWP::UserAgent;
use Cache::Memcached;
use Digest::MD5 qw(md5_hex md5_base64);

1;

sub new {
    my ($class, $params) = @_;

    # set variables
    my $agent = LWP::UserAgent->new;
    my $memd  = new Cache::Memcached {'servers' => [$Conf::web_memcache || "kursk-2.mcs.anl.gov:11211"], 'debug' => 0, 'compress_threshold' => 10_000};
    my $json  = new JSON;
    my $url_id = get_url_id($params->{cgi}, $params->{resource}, $params->{rest_parameters}, $params->{json_rpc});
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
    my ($cgi, $resource, $rest, $rpc) = @_;
    my $rurl = $cgi->url(-relative=>1).$resource;
    my @params = $cgi->param;    
    foreach my $r (@$rest) {
        $rurl .= $r;
    }
    foreach my $p (sort @params) {
        next if ($p eq 'auth');
        my @values = $cgi->param($p) || ();
        $rurl .= $p.join("", sort @values);
    }
    if ($rpc) {
        $rurl .= 'jsonrpc';
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
    use WebServiceObject;

    my ($master, $error) = WebServiceObject::db_connect();
    if ($error) {
        $self->return_data({ "ERROR" => "resource database offline" }, 503);
    } else {
        return $master;
    }
}

# check if pagination parameters are used
sub check_pagination {
    my ($self, $data, $total, $limit) = @_;

    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    my @params = $self->cgi->param;
    
    my $total_count = $total || scalar(@$data);
    my $additional_params = "";

    foreach my $param (@params) {
        next if ($param eq 'offset');
        $additional_params .= $param."=".$self->cgi->param($param)."&";
    }
    if (length($additional_params)) {
        chop $additional_params;
    }
    my $prev_offset = (($offset - $limit) < 0) ? 0 : $offset - $limit;
    my $next_offset = $offset + $limit;
    
    my $prev = ($offset > 0) ? $self->cgi->url."/".$self->name."?$additional_params&offset=$prev_offset" : undef;
    my $next = (($offset < $total_count) && ($total_count > $limit)) ? $self->cgi->url."/".$self->name."?$additional_params&offset=$next_offset" : undef;

    my $attributes = $self->attributes;
    if (exists($attributes->{$order})) {
        return { "limit" => $limit,
		          "offset" => $offset,
		          "total_count" => $total_count,
		          "order" => $order,
		          "next" => $next,
		          "prev" => $prev,
		          "data" => $data };
    } else {
        $self->return_data({ "ERROR" => "invalid sort order, there is no attribute $order" }, 400);
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
            if ($cache_me) {
                $self->memd->set($self->url_id, $self->json->encode($data), $self->{expire});
            }
        }
        print $self->header;
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
            print $self->header;
            print $self->cgi->param('callback')."(".$self->json->encode($data).");";
            exit 0;
        }
        # normal return
        else {
            if ($self->format eq 'application/json') {
                $data = $self->json->encode($data);
            }
            # cache this!
            if ($cache_me) {
                $self->memd->set($self->url_id, $data, $self->{expire});
            }
            # send it
            print $self->header;
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
            push(@$stages, { id => "mgm".$mgid."-050-".$fnum,
		                     stage_id => "050",
		                     stage_name => "upload",
		                     stage_type => $ftype,
		                     file_name => $rf });
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
            push(@$stages, { id => "mgm".$mgid."-".$stageid."-".$stagehash->{$stageid},
		                     stage_id => $stageid,
		                     stage_name => $stagename,
		                     stage_type => $stageresult,
		                     file_name => $sf });
        }
    }
    return $stages;
}

sub create_virtual_shock_node {
    my ($self, $parent, $attr) = @_;

    my $attr_str = $self->json->encode($attr);
    my $content  = [ type => 'virtual', source => $parent, attributes => [undef, "$parent.json", Content => $attr_str] ];
    my $response = undef;
    eval {
        $response = $self->json->decode( $self->agent->post($Conf::shock_url.'/node', $content, Content_Type => 'form-data')->content );
    };
    if ($@ || (! ref($response)) || $response->{E}) {
        return undef;
    } else {
        return $response->{D};
    }
}

sub set_shock_node {
    my ($self, $name, $file, $attr) = @_;
    
    my $attr_str = $self->json->encode($attr);
    my $file_str = $self->json->encode($file);
    my $content  = [ attributes => [undef, "$name.json", Content => $attr_str], upload => [undef, $name, Content => $file_str] ];
    my $response = undef;
    eval {
        $response = $self->json->decode( $self->agent->post($Conf::shock_url.'/node', $content, Content_Type => 'form-data')->content );
    };
    if ($@ || (! ref($response)) || $response->{E}) {
        return undef;
    } else {
        return $response->{D};
    }
}

sub get_shock_node {
    my ($self, $id) = @_;
    
    my $content = undef;
    eval {
        $content = $self->json->decode( $self->agent->get($Conf::shock_url.'/node/'.$id)->content );
    };
    if ($@ || (! ref($content)) || $content->{E}) {
        return undef;
    } else {
        return $content->{D};
    }
}

sub get_shock_file {
    my ($self, $id, $file) = @_;
    
    my $content = undef;
    eval {
        $content = $self->agent->get($Conf::shock_url.'/node/'.$id.'?download')->content;
    };
    if ($@ || (! $content)) {
        return undef;
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
    my ($self, $params) = @_;
    
    my $shock = undef;
    my $query = '?query';
    map { $query .= '&'.$_.'='.$params->{$_} } keys %$params;
    
    eval {
        $shock = $self->json->decode( $self->agent->get($Conf::shock_url.'/node'.$query)->content );
    };
    if ($@ || (! ref($shock)) || $shock->{E} || (! $shock->{D})) {
        return [];
    } else {
        return $shock->{D};
    }
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
