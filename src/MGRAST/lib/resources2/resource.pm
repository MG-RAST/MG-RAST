package resources2::resource;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use CGI;
use JSON;
use LWP::UserAgent;

1;

sub new {
    my ($class, $params) = @_;

    # set variables
    my $agent = LWP::UserAgent->new;
    my $json  = new JSON;
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
    		              -32602 => "Invalid params",
    		              -32603 => "Internal error"
    		              };
    # create object
    my $self = {
        format        => "application/json",
        agent         => $agent,
        json          => $json,
        cgi           => $params->{cgi},
        rest          => $params->{rest_parameters} || [],
        user          => $params->{user},
        json_rpc      => $params->{json_rpc} ? $params->{json_rpc} : 0,
        json_rpc_id   => ($params->{json_rpc} && exists($params->{json_rpc_id})) ? $params->{json_rpc_id} : undef,
        html_messages => $html_messages,
        name          => '',
        rights        => {},
        attributes    => {}
    };
    bless $self, $class;
    return $self;
}

# get functions for class variables
sub agent {
    my ($self) = @_;
    return $self->{agent};
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
    my ($self, $data) = @_;

    if ($self->cgi->param('limit') || $self->cgi->param('order')) {
        my $limit  = $self->cgi->param('limit') || 10;
        my $offset = $self->cgi->param('offset') || 0;
        my $order  = $self->cgi->param('order') || "id";
        my $total_count = scalar(@$data);
        my $additional_params = "";
        my @params = $self->cgi->param;
        foreach my $param (@params) {
            next if ($param eq 'offset');
            $additional_params .= $param."=".$self->cgi->param($param)."&";
        }
        if (length($additional_params)) {
            chop $additional_params;
        }
        my $prev_offset = $offset - $limit;
        if ($prev_offset < 0) {
            $prev_offset = 0;
        }
        my $prev = $offset ? $self->cgi->url."/".$self->name."?$additional_params&offset=$prev_offset" : undef;
        my $next_offset = $offset + $limit;
        my $next = ($offset < $total_count) ? $self->cgi->url."/".$self->name."?$additional_params&offset=$next_offset" : undef;
        my $attributes = attributes();
        if (exists($attributes->{$order})) {
            $data = { "limit" => $limit,
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
    return $data;
}

# print the actual data output
sub return_data {
    my ($self, $data, $error) = @_;

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
            print $self->header;
            if ($self->format eq 'application/json') {
	            print $self->json->encode($data);
            } else {
	            print $data;
            }
            exit 0;
        }
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

sub get_shock_node {
    my ($self, $id) = @_;
    
    my $shock = undef;
    eval {
        $shock = $self->json->decode( $self->agent->get($Conf::shock_url.'/node/'.$id)->content );
    };
    if ($@ || (! ref($shock)) || $shock->{E}) {
        return undef;
    } else {
        return $shock->{D};
    }
}

sub get_shock_file {
    my ($self, $id) = @_;
    
    my $file = undef;
    eval {
        $file = $self->agent->get($Conf::shock_url.'/node/'.$id.'?download')->content;
    };
    if ($@ || (! $file)) {
        return undef;
    } else {
        return $file;
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

###################################################
#  stub functions - replace these in child class  #
###################################################

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    return undef;
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;
    return undef;
}

# method to parse parameters and decide which requests to process
sub request {
    my ($self) = @_;
    return undef;
}

# enable hash-resolving in the JSON->encode function
sub TO_JSON { return { %{ shift() } }; }
