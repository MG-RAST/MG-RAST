package resources::resource;

use strict;
use warnings;
no warnings('once');
use Encode qw(decode_utf8 encode_utf8);

use Auth;
use Conf;
use ElasticSearch;
use MGRAST::Metadata;

use CGI;
use JSON;
use XML::Simple;
use URI::Escape;
use MIME::Base64;
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Basename;
use File::Temp qw(tempfile tempdir);
use Storable qw(dclone);
use UUID::Tiny ":std";
use List::Util qw(max min sum);
use Digest::MD5 qw(md5_hex md5_base64);
use Template;
use Inline::Python qw(py_eval);

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

1;

###################################################
#  create new instance of parent class            #
###################################################

sub new {
    my ($class, $params) = @_;

    # set variables
    my $memd = undef;
    eval {
        require Cache::Memcached;
        Cache::Memcached->import();
        $memd = new Cache::Memcached {'servers' => $Conf::web_memcache, 'debug' => 0, 'compress_threshold' => 10_000};
    };
    my $url_id = get_url_id($params->{cgi}, $params->{resource}, $params->{rest_parameters}, $params->{json_rpc}, $params->{user});
    my $self_url = get_self_url($params->{cgi}, $params->{is_ssl});
    my $agent = LWP::UserAgent->new;
    $agent->timeout(600);
    my $json = JSON->new();
    $json->max_size(0);
    $json->allow_nonref;
    
    my $html_messages = {
        200 => "OK",
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
	
    #### changed because globus has hard time handeling multiple tokens
    my $user_auth = "mgrast";
    my $mgrast_token = $Conf::mgrast_oauth_token || undef;
	
    # create object
    my $self = {
        format        => "application/json",
        agent         => $agent,
        memd          => $memd,
        json          => $json,
        cgi           => $params->{cgi},
        url           => $self_url,
        rest          => $params->{rest_parameters} || [],
        method        => $params->{method},
        submethod     => $params->{submethod},
        resource      => $params->{resource},
        user          => $params->{user},
        token         => $params->{token},
        mgrast_token  => $mgrast_token,
        user_auth     => $user_auth,
        json_rpc      => $params->{json_rpc} ? $params->{json_rpc} : 0,
        json_rpc_id   => ($params->{json_rpc} && exists($params->{json_rpc_id})) ? $params->{json_rpc_id} : undef,
        html_messages => $html_messages,
        expire        => $Conf::web_memcache_expire || 172800, # use config or 48 hours
        name          => '',
        url_id        => $url_id,
        rights        => {},
        attributes    => {},
        m5nr_version  => {'1' => '20100309', '7' => '20120401', '9' => '20130801', '10' => '20131215'},
        m5nr_default  => 1,
        default_pipeline_version => "3.0"
    };
    bless $self, $class;
    return $self;
}

### make a unique id for each resource / option combination (no auth)
sub get_url_id {
    my ($cgi, $resource, $rest, $rpc, $user) = @_;
    my $rurl = $cgi->url(-relative=>1).$resource;
    if ($cgi->url =~ /dev/) {
        $rurl = 'dev'.$rurl;
    }
    my %params = map { $_ => [($cgi->param($_))] } $cgi->param;
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

sub get_self_url {
    my ($cgi, $is_ssl) = @_;
    my $cgi_url = $cgi->url;
    if ($is_ssl) {
        $cgi_url =~ s/^http/https/;
    }
    return $cgi_url;
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
sub url {
    my ($self) = @_;
    return $self->{url};
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
sub mgrast_token {
    my ($self) = @_;
    return $self->{mgrast_token};
}
sub user_auth {
    my ($self) = @_;
    return $self->{user_auth};
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
sub m5nr_version {
    my ($self) = @_;
    return $self->{m5nr_version};
}

#####################
#  hardcoded lists  #
#####################

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
					       ["KEGG", "protein database, type organism, function, feature"],
                           ["eggNOG", "protein database, type organism, function, feature"] ],
             rna      => [ ["RDP", "RNA database, type organism, function, feature"],
			               ["Greengenes", "RNA database, type organism, function, feature"],
		                   ["LSU", "RNA database, type organism, function, feature"],
		                   ["SSU", "RNA database, type organism, function, feature"],
		                   ["ITS", "RNA database, type organism, function, feature"] ],
             ontology => [ ["Subsystems", "ontology database, type ontology only"],
                           ["NOG", "ontology database, type ontology only"],
                           ["COG", "ontology database, type ontology only"],
                           ["KO", "ontology database, type ontology only"] ]
    };
}

sub valid_source {
    my ($self, $src, $type) = @_;
    if (! $src) {
        return 0;
    }
    my @test = $type ? ($type) : ("protein", "rna", "ontology");
    foreach my $t (@test) {
        if (exists $self->source->{$t}) {
            foreach my $s (@{$self->source->{$t}}) {
                if ($s->[0] eq $src) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

sub source_by_type {
    my ($self, $type) = @_;
    my @srcs = ();
    my @test = $type ? ($type) : ("protein", "rna", "ontology");
    foreach my $t (@test) {
        if (exists $self->source->{$t}) {
            foreach my $s (@{$self->source->{$t}}) {
                push @srcs, $s->[0];
            }
        }
    }
    return \@srcs;
}

sub type_by_source {
    my ($self, $source) = @_;
    foreach my $t (("protein", "rna", "ontology")) {
        if (exists $self->source->{$t}) {
            foreach my $s (@{$self->source->{$t}}) {
                if ($s->[0] eq $source) {
                    return $t;
                }
            }
        }
    }
    return undef;
}

# hardcoded hierarchy info
sub hierarchy {
    return { organism => [ ['strain', 'bottom organism taxonomic level'],
                           ['species', 'organism type level'],
                           ['genus', 'organism taxonomic level'],
                           ['family', 'organism taxonomic level'],
                           ['order', 'organism taxonomic level'],
                           ['class', 'organism taxonomic level'],
                           ['phylum', 'organism taxonomic level'],
                           ['domain', 'top organism taxonomic level'] ],
             ontology => [ ['function', 'bottom function ontology level'],
                           ['level3', 'function ontology level' ],
                           ['level2', 'function ontology level' ],
                           ['level1', 'top function ontology level'] ]
    };
}

# hardcoded list of metagenome pipeline option keywords for submission
sub pipeline_opts {
    return [
        'aa_pid',
        'assembled',
        'bowtie',
        'dereplicate',
        'dynamic_trim',
        'fgs_type',
        'file_type',
        'filter_ambig',
        'filter_ln',
        'filter_ln_mult',
        'max_ambig',
        'max_lqb',
        'min_qual',
        'prefix_length',
        'priority',
        'rna_pid',
        'screen_indexes',
        'sequence_type',           # not in defaults
        'sequencing_method_guess'  # not in defaults
    ];
}

# hardcoded list of metagenome pipeline paramters with defaults
sub pipeline_defaults {
    return {
        'aa_pid' => '90',
        'assembled' => 'no',
        'bowtie' => 'yes',
        'dereplicate' => 'yes',
        'dynamic_trim' => 'yes',
        'fgs_type' => '454',
        'file_type' => 'fna',
        'filter_ambig' => 'yes',
        'filter_ln' => 'yes',
        'filter_ln_mult' => '2.0',
        'm5nr_annotation_version' => '1',   # not in options
        'm5rna_annotation_version' => '1',  # not in options
        'm5nr_sims_version' => '1',         # not in options
        'm5rna_sims_version' => '1',        # not in options
        'max_ambig' => '5',
        'max_lqb' => '5',
        'min_qual' => '15',
        'prefix_length' => '50',
        'priority' => 'never',
        'rna_pid' => '97',
        'screen_indexes' => 'h_sapiens'
    };
}

# hardcoded list of metagenome sequence statistics names
sub seq_stats {
    return [ 'alpha_diversity_shannon_d',
             'ambig_char_count_preprocessed_l',
             'ambig_char_count_preprocessed_rna_l',
             'ambig_char_count_raw_l',
             'ambig_sequence_count_preprocessed_l',
             'ambig_sequence_count_preprocessed_rna_l',
             'ambig_sequence_count_raw_l',
             'average_ambig_chars_preprocessed_d',
             'average_ambig_chars_preprocessed_rna_d',
             'average_ambig_chars_raw_d',
             'average_gc_content_preprocessed_d',
             'average_gc_content_preprocessed_rna_d',
             'average_gc_content_raw_d',
             'average_gc_ratio_preprocessed_d',
             'average_gc_ratio_preprocessed_rna_d',
             'average_gc_ratio_raw_d',
             'average_length_preprocessed_d',
             'average_length_preprocessed_rna_d',
             'average_length_raw_d',
             'bp_count_preprocessed_l',
             'bp_count_preprocessed_rna_l',
             'bp_count_raw_l',
             'clustered_sequence_count_processed_l',
             'clustered_sequence_count_processed_aa_l',
             'clustered_sequence_count_processed_rna_l',
             'cluster_count_processed_l',
             'cluster_count_processed_aa_l',
             'cluster_count_processed_rna_l',
             'drisee_score_raw_d',
             'length_max_preprocessed_l',
             'length_max_preprocessed_rna_l',
             'length_max_raw_l',
             'length_min_preprocessed_l',
             'length_min_preprocessed_rna_l',
             'length_min_raw_l',
             'ratio_reads_aa_d',
             'ratio_reads_rna_d',
             'read_count_annotated_l',
             'read_count_processed_aa_l',
             'read_count_processed_rna_l',
             'sequence_count_dereplication_removed_l',
             'sequence_count_ontology_l',
             'sequence_count_preprocessed_l',
             'sequence_count_preprocessed_rna_l',
             'sequence_count_processed_l',
             'sequence_count_processed_aa_l',
             'sequence_count_processed_rna_l',
             'sequence_count_raw_l',
             'sequence_count_sims_aa_l',
             'sequence_count_sims_rna_l',
             'standard_deviation_gc_content_preprocessed_d',
             'standard_deviation_gc_content_preprocessed_rna_d',
             'standard_deviation_gc_content_raw_d',
             'standard_deviation_gc_ratio_preprocessed_d',
             'standard_deviation_gc_ratio_preprocessed_rna_d',
             'standard_deviation_gc_ratio_raw_d',
             'standard_deviation_length_preprocessed_d',
             'standard_deviation_length_preprocessed_rna_d',
             'standard_deviation_length_raw_d'
    ];
}

######################################
#  response / data return functions  #
######################################

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
    my ($self, $status, $text) =  @_;
    unless ($status) {
        $status = 200;
    }
    my $size = 0;
    {
        #use bytes;
        if ($text) {
            $size = length($text);
        }
    }
    my $header = $self->cgi->header(
        -type => $self->format,
	    -status => $status,
	    -Access_Control_Allow_Origin => '*',
	    -Content_Length => $size
	);
    return $header
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
        $self->return_data({ "ERROR" => "resource database offline . " }, 503);  # WebServiceObject:db_connect doesn't populate $error
    } else {
      if (ref $self->user) {
	$master->{_user} = $self->user;
      }
      return $master;
    }
}

# check if pagination parameters are used
sub check_pagination {
    my ($self, $data, $total, $limit, $path, $offset) = @_;

    $offset = $self->cgi->param('offset') ? $self->cgi->param('offset') : ($offset ? $offset : 0);
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
        my $add_params  = join('&', map {$_."=".decode_utf8($self->cgi->param($_))} grep {$_ ne 'offset'} @params);
        $object->{url}  = $self->url."/".$self->name.$path."?$add_params&offset=$offset";
        $object->{prev} = ($offset > 0) ? $self->url."/".$self->name.$path."?$add_params&offset=$prev_offset" : undef;
        $object->{next} = (($offset < $total_count) && ($total_count > $limit)) ? $self->url."/".$self->name.$path."?$add_params&offset=$next_offset" : undef;
    }
    if ($order) {
      $object->{order} = $order;
    }
    
    return $object;
}

# get paramaters from POSTDATA or form fields
sub get_post_data {
    my ($self, $fields) = @_;
    
    my %data = ();
    # get by paramaters first
    # value may be array
    if ($fields && (@$fields > 0)) {
        foreach my $f (@$fields) {
            my @val = $self->cgi->param($f);
            if (@val) {
                if (scalar(@val) == 1) {
                    $data{$f} = decode_utf8($val[0]);
                } elsif (scalar(@val) > 1) {
                    @{$data{$f}} = map {decode_utf8($_)} @val;
                }
            }
        }
    }
    # get by posted data
    my $post_data = $self->cgi->param('POSTDATA') ? decode_utf8($self->cgi->param('POSTDATA')) : join(" ", $self->cgi->param('keywords'));
    if ($post_data) {
        my $pdata = {};
        eval {
            $pdata = $self->json->decode($post_data);
        };
        @data{ keys %$pdata } = values %$pdata;
    }
    # get broken post data
    if (scalar(keys %data) == 0) {
        my $all_data = join(" ", $self->cgi->Vars);
        my $pdata = {};
        eval {
            $pdata = $self->json->decode($all_data);
        };
        @data{ keys %$pdata } = values %$pdata;
    }
    return \%data;
}

# return cached data if exists
sub return_cached {
    my ($self) = @_;
    
    if ($self->memd) {
        my $cached = $self->memd->get($self->url_id);
        if ($cached) {
            # do a runaround on ->return_data
            print $self->header(200, $cached);
            print $cached;
            exit 0;
        }
    }
}

# print the actual data output
sub return_data {
    my ($self, $data, $error, $cache_me, $raw) = @_;

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
        my $data_text = $self->json->encode($data);
        print $self->header($status, $data_text);
        print $data_text;
        exit 0;
    }
    else {
        # check for JSONP
        if ($self->cgi->param('callback')) {
            if ($self->format ne "application/json") {
	            $data = { 'data' => $data };
            }
            $self->format("application/json");
            my $data_text = $self->cgi->param('callback')."(".$self->json->encode($data).");";
            print $self->header($status, $data_text);
            print $data_text;
            exit 0;
        }
        # normal return
        else {
	  if ($self->format eq 'application/json') {
	    $self->format('application/json; charset=UTF-8');
	    $data = $self->json->encode($data);
	  }
	  
	  # cache this!
	  if ($cache_me && $self->memd) {
	    $self->memd->set($self->url_id, $data, $self->{expire});
	  }
	  # send it
	  print $self->header($status, $data);
	  print $data;
	  exit 0;
        }
    }
}

# print a string to download
sub download_text {
    my ($self, $text, $name) = @_;
    print "Content-Type: application/x-download\n";
    print "Access-Control-Allow-Origin: *\n";
    print "Content-Length: ".length($text)."\n";
    print "Content-Disposition: attachment;filename=$name\n\n";
    print $text;
    exit 0;
}

# print a local file to download
sub download_local {
    my ($self, $filepath, $name) = @_;
    if (open(FH, "<$filepath")) {
      my $content = do { local $/; <FH> };
      close FH;
      print "Content-Type: application/octet-stream\n";
      print "Access-Control-Allow-Origin: *\n";
      print "Content-Length: ".length($content)."\n";
      print "Content-Disposition: attachment;filename=$name\n\n";
      print $content;
    } else {
      print "Content-Type: text/plain\n";
      print "Access-Control-Allow-Origin: *\n";
      print "ERROR (500): Unable to retrieve file $name\n";
    }
    exit 0;
}

# stream a file from shock to browser
sub return_shock_file {
    my ($self, $id, $size, $name, $auth, $authPrefix) = @_;
        
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    # print headers
    print "Content-Type: application/x-download\n";
    print "Access-Control-Allow-Origin: *\n";
    if ($size) {
        print "Content-Length: ".$size."\n";
    }
    print "Content-Disposition: attachment;filename=".$name."\n\n";
    eval {
        my $url = $Conf::shock_url.'/node/'.$id.'?download_raw';
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            ':read_size_hint', 8192,
            ':content_cb', sub{ my ($chunk) = @_; print $chunk; }
        );
        # print content
        $response = $self->agent->get($url, @args);
    };
    if ($@ || (! $response)) {
        print "ERROR (500): Unable to retrieve file from Shock server\n";
    }
    exit 0;
}

# validate / sanitize md5sum
sub clean_md5 {
    my ($self, $md5) = @_;
    my $clean = $md5;
    $clean =~ s/[^a-zA-Z0-9]//g;
    unless ($clean && (length($clean) == 32)) {
        return 0;
    }
    return 1;
}

# return sequence data for md5s as fasta or json / and error
sub md5s2sequences {
    my ($self, $md5s, $version, $format) = @_;
    
    # check md5s
    my @clean = grep { $self->clean_md5($_) } @$md5s;
    
    # make id file
    my ($tfh, $tfile) = tempfile("md5XXXXXXX", DIR => $Conf::temp, SUFFIX => '.ids');
    map { print $tfh "lcl|$_\n" } @clean;
    close($tfh);
    
    # get m5nr
    my $seqs = "";
    my $m5nr = "";
    if ($Conf::m5nr_fasta && (-f $Conf::m5nr_fasta)) {
        $m5nr = $Conf::m5nr_fasta;
    } elsif ($Conf::m5nr_dir && (-d $Conf::m5nr_dir)) {
        $m5nr = $Conf::m5nr_dir."/".$self->{m5nr_version}{$version}."/md5nr";
    } else {
        return (undef, "missing M5NR sequence data");
    }
    
    # get seqs
    my $ferror = "";
    eval {
        my $fastacmd = $Conf::fastacmd;
        foreach my $line (`$fastacmd -d $m5nr -i $tfile -l 0 -t T -p T`) {
            if ((! $line) || ($line =~ /^\s+$/) || ($line =~ /^\[fastacmd\]/)) {
                if ($line =~ /ERROR/) {
                    $ferror .= $line;
                }
                next;
            }
            if ($line =~ /^>/) {
                $line = (split(/\s/, $line))[0]."\n";
            }
            $seqs .= $line;
        }
    };
    if ($@) {
        return (undef, "unable to access M5NR sequence data");
    }
    if ($ferror) {
        return (undef, $ferror);
    }
    
    # output
    if ($format eq 'fasta') {
        return ($seqs, undef);
    } else {
        my $data  = [];
        my @lines = split(/\n/, $seqs);
        chomp @lines;
        for (my $i = 0; $i < scalar(@lines); $i += 2) {
            push @$data, {'md5' => (split(/\|/, $lines[$i]))[1], 'sequence' => $lines[$i+1]};
        }
        return ($data, undef);
    }
}

#############################
#  shock related functions  #
#############################

## download array of info for metagenome files in shock
sub get_download_set {
    my ($self, $mgid, $version, $auth, $seq_only, $authPrefix) = @_;

    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $vernum = $self->normailze_pipeline_version($version);
    my %seen   = ();
    my $skip   = {};
    my %subset = ('adapter.trim' => 1, 'preprocess' => 1, 'dereplication' => 1, 'screen' => 1);
    my $stages = [];
    my $mgall  = $self->get_shock_query({'id' => 'mgm'.$mgid}, $auth, $authPrefix);
    my $mgmap  = {};
    my $mgdata = [];
    # filter out non-downloadable nodes
    foreach my $node (@$mgall) {
        # skip no file
        unless (exists($node->{file}{checksum}{md5}) || ($node->{file}{size} > 0) || ($node->{file}{name} ne "")) {
            $skip->{$node->{id}} = "missing file";
            next;
        }
        # skip profiles
        if (exists($node->{attributes}{data_type}) && ($node->{attributes}{data_type} eq 'profile')) {
            $skip->{$node->{id}} = "profile node";
            next;
        }
        # fix malformed stats nodes
        if (exists($node->{attributes}{data_type}) && ($node->{attributes}{data_type} eq 'statistics') &&
                exists($node->{attributes}{file_format}) && ($node->{attributes}{file_format} eq 'json')) {
            $node->{attributes}{stage_name} = 'done';
            $node->{attributes}{stage_id}   = '999';
        }
        unless (exists($node->{attributes}{stage_id}) && exists($node->{attributes}{stage_name}) && exists($node->{attributes}{file_format})
                    && exists($node->{attributes}{data_type}) && ($node->{attributes}{type} eq 'metagenome')) {
            $skip->{$node->{id}} = "missing attributes";
            next;
        }
        my $unique = $node->{attributes}{stage_id}.$node->{attributes}{stage_name}.$node->{attributes}{file_format}.$node->{attributes}{data_type};
        push @{$mgmap->{$unique}}, $node;
    }
    # find duplicates and only keep latest
    foreach my $nodes (values %$mgmap) {
        if (scalar(@$nodes) == 1) {
            push @$mgdata, $nodes->[0];
        } elsif (scalar(@$nodes) > 1) {
            my @sorted = sort { $b->{created_on} cmp $a->{created_on} } @$nodes;
            push @$mgdata, $sorted[0];
        }
    }
    # sort by stages
    @$mgdata = sort { ($a->{attributes}{stage_id} cmp $b->{attributes}{stage_id}) ||
                        ($a->{attributes}{data_type} cmp $b->{attributes}{data_type}) } @$mgdata;
    
    # process nodes / create download stages struct
    foreach my $node (@$mgdata) {
        my $attr = $node->{attributes};
        my $file = $node->{file};
        # only return sequence files
        if ($seq_only && ($attr->{data_type} !~ /^sequence|passed|removed$/)) {
            $skip->{$node->{id}} = "not sequence file";
            next;
        }
        if (exists $seen{$attr->{stage_id}}) {
            $seen{$attr->{stage_id}} += 1;
        } else {
            $seen{$attr->{stage_id}} = 1;
        }
        my $file_id = $attr->{stage_id}.'.'.$seen{$attr->{stage_id}};
        my $data = { id  => "mgm".$mgid,
		             url => $self->url.'/download/mgm'.$mgid.'?file='.$file_id,
		             node_id    => $node->{id},
		             stage_id   => $attr->{stage_id},
		             stage_name => $attr->{stage_name},
		             data_type  => $attr->{data_type},
		             file_id    => $file_id,
		             file_size  => $file->{size} || 0,
		             file_md5   => $file->{checksum}{md5} || undef
		};
	    foreach my $label (('statistics', 'seq_format', 'file_format', 'cluster_percent')) {
		    if (exists $attr->{$label}) {
                $data->{$label} = $attr->{$label};
            }
		}
	    if (exists $data->{statistics}) {
	        foreach my $k (keys %{$data->{statistics}}) {
	            $data->{statistics}{$k} = $self->strToNum($data->{statistics}{$k});
	        }
	    }
        # rename for subset
        if (exists $subset{$data->{stage_name}}) {
            $data->{stage_name} .= ($attr->{data_type} eq 'removed') ? '.removed' : '.passed';
        }
        # rename for cluster
        if ($data->{stage_name} =~ /\.cluster$/) {
            $data->{stage_name} .= ($attr->{data_type} eq 'cluster') ? '.map' : '.seq';
        }
        # build proper file name
        my $suffix = "";
        if (exists $data->{cluster_percent}) {
            my $seqtype = (exists($data->{seq_format}) && ($data->{seq_format} eq 'bp')) ? 'rna' : 'aa';
            if ($data->{stage_name} =~ /rna/) {
                # some mislabeled rna nodes
                $seqtype = 'rna';
            }
            $suffix = ".cluster.".$seqtype.$data->{cluster_percent};
            if ($data->{data_type} eq "cluster") {
                $suffix .= '.mapping';
            } elsif ($seqtype eq 'rna') {
                $suffix .= '.fna';
            } elsif ($seqtype eq 'aa') {
                $suffix .= '.faa';
            }
            $data->{cluster_percent} = int($data->{cluster_percent});
        }
        elsif (($data->{data_type} =~ /^sequence|passed|removed$/) && exists($data->{file_format})) {
            if ($data->{stage_name} eq 'rna.filter') {
                $suffix = '.search.rna';
            } elsif ($data->{stage_name} eq 'genecalling') {
                $suffix = '.genecalling.coding';
            } else {
                $suffix = ".".$data->{stage_name};
            }
            if ($data->{file_format} eq 'fastq') {
                $suffix .= '.fastq';
            } elsif (exists($data->{seq_format}) && ($data->{seq_format} eq 'bp')) {
                $suffix .= '.fna';
            } elsif (exists($data->{seq_format}) && ($data->{seq_format} eq 'aa')) {
                $suffix .= '.faa';
            }
        } elsif ($data->{stage_name} eq 'protein.sims') {
            $suffix = '.superblat.sims';
        } elsif ($data->{stage_name} eq 'filter.sims') {
            $suffix = '.annotation.sims.filter.seq';
        } elsif ($data->{data_type} eq 'md5') {
            if ($vernum < 400) {
                $suffix = '.annotation.md5.summary';
            } else {
                $suffix = '.annotation.md5.abundance';
            }
        } elsif ($data->{data_type} eq 'lca') {
            if ($vernum < 400) {
                $suffix = '.annotation.lca.summary';
            } else {
                $suffix = '.annotation.lca.abundance';
            }
        } elsif ($data->{data_type} eq 'coverage') {
            $suffix = '.assembly.coverage';
        } else {
            $suffix = ".".$data->{stage_name};
        }
        $data->{file_name} = $attr->{job_id}.".".$data->{stage_id}.$suffix;
        if ($data->{data_type} eq 'statistics') {
            # no stage_id in stats file name
            $data->{file_name} = $attr->{job_id}.'.statistics.json';
        } elsif (($data->{stage_name} eq 'filter.sims') && ($vernum == 300)) {
            # old pipeline naming scheme
            $data->{file_name} = $attr->{job_id}.'.900.loadDB.sims.filter.seq';
        }
        push @$stages, $data;
    }
    
    # final check for any missing
    foreach my $n (@$mgall) {
        my $in_stage = 0;
        foreach my $s (@$stages) {
            if ($s->{node_id} eq $n->{id}) {
                $in_stage = 1;
            }
        }
        unless ($in_stage || exists($skip->{$n->{id}})) {
            $skip->{$n->{id}} = "missing download";
        }
    }
    
    return ($stages, $skip);
}

sub fix_download_filenames {
    my ($self, $data, $id) = @_;
    foreach my $d (@$data) {
        if (exists $d->{file_name}) {
            $d->{file_name} = $self->fix_download_filename($d->{file_name}, $id);
        }
        if (exists $d->{inputs}) {
            foreach my $i (@{$d->{inputs}}) {
                if (exists $i->{file_name}) {
                    $i->{file_name} = $self->fix_download_filename($i->{file_name}, $id);
                }
            }
        }
        if (exists $d->{outputs}) {
            foreach my $o (@{$d->{outputs}}) {
                if (exists $o->{file_name}) {
                    $o->{file_name} = $self->fix_download_filename($o->{file_name}, $id);
                }
            }
        }
    }
    return $data;
}

sub fix_download_filename {
    my ($self, $fname, $id) = @_;
    # has jobid prefix
    if ($fname =~ /^(\d+)\.(.*)/) {
        $fname = $id.".".$2;
    }
    return $fname
}

sub clean_setlist {
    my ($self, $setlist, $job) = @_;
    
    my $has_human = $self->has_human($setlist, $job);
    if (! $has_human) {
        return $setlist;
    }
    
    foreach my $set (@$setlist) {
        my $stage_id = int($set->{stage_id});
        if ($stage_id < 200) {
            if (exists $set->{node_id}) {
                delete $set->{node_id};
            }
            if (exists $set->{url}) {
                delete $set->{url};
            }
        }
    }
    
    return $setlist;
}

sub has_human {
    my ($self, $setlist, $job) = @_;
    
    if (($job->sequence_type ne 'WGS') && ($job->sequence_type ne 'MT')) {
        return 0;
    }
    
    my $jdata = $job->data;
    if (exists($jdata->{screen_indexes}) && ($jdata->{screen_indexes} =~ /h_sapiens/)) {
        my $dpass = 0;
        my $spass = 0;
        foreach my $set (@$setlist) {
            if (($set->{stage_name} eq "dereplication.passed") && exists($set->{statistics})) {
                $dpass = $set->{statistics}{sequence_count} || 0;
            }
            if (($set->{stage_name} eq "screen.passed") && exists($set->{statistics})) {
                $spass = $set->{statistics}{sequence_count} || 0;
            }
        }
        if ($dpass && $spass && ($spass < $dpass)) {
            return 1;
        }
    }
    return 0;
}

# add or delete an ACL based on username
sub edit_shock_acl {
    my ($self, $id, $auth, $user, $action, $acl, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $url = $Conf::shock_url.'/node/'.$id.'/acl/'.$acl.'?users='.$user;
    eval {
        my $tmp = undef;
        if ($action eq 'delete') {
            $tmp = $self->agent->delete($url, 'Authorization' => "$authPrefix $auth");
        } elsif ($action eq 'put') {
            $tmp = $self->agent->put($url, 'Authorization' => "$authPrefix $auth");
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

# add or delete public from a node ACL
sub edit_shock_public_acl {
    my ($self, $id, $auth, $action, $acl, $authPrefix) = @_;

    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $url = $Conf::shock_url.'/node/'.$id.'/acl/public_'.$acl;
    eval {
        my $tmp = undef;
        if ($action eq 'delete') {
            $tmp = $self->agent->delete($url, 'Authorization' => "$authPrefix $auth");
        } elsif ($action eq 'put') {
            $tmp = $self->agent->put($url, 'Authorization' => "$authPrefix $auth");
        } else {
            $self->return_data( {"ERROR" => "Invalid Shock ACL action: $action"}, 500 );
        }
        $response = $self->json->decode( $tmp->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to $action public ACL for '$acl' to node $id in Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# create node with optional file and/or attributes
# file is json struct by default
sub set_shock_node {
    my ($self, $name, $file, $attr, $auth, $not_json, $authPrefix, $expiration) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }
    my $response = undef;
    my $content = {};
    $self->json->utf8();
    
    if ($file) {
        my $file_str = $not_json ? $file : $self->json->encode($file);
        $content->{upload} = [undef, $name, Content => $file_str];
    }
    if ($attr) {
        $content->{attributes} = [undef, "$name.json", Content => $self->json->encode($attr)];
    }
    if ($expiration && ($expiration =~ /^(\d+)(M|H|D)$/)) {
        $content->{expiration} = $expiration;
    }
    eval {
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            'Content_Type', 'multipart/form-data',
            $content ? ('Content', $content) : ()
        );
        my $post = $self->agent->post($Conf::shock_url.'/node', @args);
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

# add a file to existing shock node
# file is json struct by default
sub put_shock_file {
    my ($self, $name, $file, $node, $auth, $not_json, $authPrefix, $expiration) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }
    my $response = undef;
    my $file_str = $not_json ? $file : $self->json->encode($file);
    my $content->{upload} = [undef, $name, Content => $file_str];
    if ($expiration && ($expiration =~ /^(\d+)(M|H|D)$/)) {
        $content->{expiration} = $expiration;
    }
    eval {
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            'Content_Type', 'multipart/form-data',
            $content ? ('Content', $content) : ()
        );
        my $req = POST($Conf::shock_url.'/node/'.$node, @args);
        $req->method('PUT');
        my $put = $self->agent->request($req);
        $response = $self->json->decode( $put->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to PUT to Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# set node file_name
sub update_shock_node_file_name {
    my ($self, $id, $fname, $auth, $authPrefix) = @_;

    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $content = {file_name => $fname};
    eval {
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            'Content_Type', 'multipart/form-data',
            $content ? ('Content', $content) : ()
        );
        my $req = POST($Conf::shock_url.'/node/'.$id, @args);
        $req->method('PUT');
        my $put = $self->agent->request($req);
        $response = $self->json->decode( $put->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to PUT to Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# just adjust expiration
sub update_shock_node_expiration {
    my ($self, $id, $auth, $authPrefix, $expiration) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $content  = undef;
    if ($expiration) {
        $content = {expiration => $expiration};
    } else {
        $content = {remove_expiration => "true"};
    }
    
    eval {
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            'Content_Type', 'multipart/form-data',
            $content ? ('Content', $content) : ()
        );
        my $req = POST($Conf::shock_url.'/node/'.$id, @args);
        $req->method('PUT');
        my $put = $self->agent->request($req);
        $response = $self->json->decode( $put->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to PUT to Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# edit node attributes
sub update_shock_node {
    my ($self, $id, $attr, $auth, $authPrefix, $expiration) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }
    my $response = undef;
    my $content = {attributes => [undef, "n/a", Content => $self->json->encode($attr)]};
    if ($expiration && ($expiration =~ /^(\d+)(M|H|D)$/)) {
        $content->{expiration} = $expiration;
    }
    eval {
        my @args = (
            $auth ? ('Authorization', "$authPrefix $auth") : (),
            'Content_Type', 'multipart/form-data',
            $content ? ('Content', $content) : ()
        );
        my $req = POST($Conf::shock_url.'/node/'.$id, @args);
        $req->method('PUT');
        my $put = $self->agent->request($req);
        $response = $self->json->decode( $put->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to PUT to Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# get node contents
sub get_shock_node {
    my ($self, $id, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::shock_url.'/node/'.$id, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to GET node $id from Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# delete node
sub delete_shock_node {
    my ($self, $id, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->delete($Conf::shock_url.'/node/'.$id, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to DELETE node $id from Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# get the shock preauth url for a file
sub get_shock_preauth {
    my ($self, $id, $auth, $fn, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::shock_url.'/node/'.$id.'?download_url'.($fn ? "&file_name=".$fn : ""), @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to GET node $id from Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# write file content to given filepath, else return file content as string
# returns tuple: (content, error_msg)
sub get_shock_file {
    my ($self, $id, $file, $auth, $index, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $fhdl = undef;
    my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
    
    if ($file) {
        open($fhdl, ">$file") || return ("", "Unable to open file $file");
        push @args, (':read_size_hint', 8192, ':content_cb', sub{ my ($chunk) = @_; print $fhdl $chunk; });
    }
    eval {
        my $url = $Conf::shock_url.'/node/'.$id.'?download'.($index ? '&'.$index : '');
        $response = $self->agent->get($url, @args);
    };
    if ($@ || (! $response)) {
        return ("", "Unable to connect to Shock server");
    } elsif ($response->is_error) {
        return ("", $response->code.": ".$response->message);
    } elsif ($file) {
        close($fhdl);
        return (1, undef);
    } else {
        return ($response->content, undef);
    }
}

# get list of nodes for query
sub get_shock_query {
    my ($self, $params, $auth, $authPrefix, $querynode) = @_;

    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }    

    my $response = undef;
    my $query = '?query'.($querynode ? 'node' : '').'&limit=0';
    if ($params && (scalar(keys %$params) > 0)) {
        while (my ($key, $value) = each %$params) {
            if (ref($value)) {
                map { $query .= '&'.$key.'='.uri_escape($_) } @$value;
            } else {
                $query .= '&'.$key.'='.uri_escape($value);
            }
        }
    }
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::shock_url.'/node'.$query, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return [];
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to query Shock: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

sub metagenome_stats_from_shock {
    my ($self, $mgid, $type) = @_;
    
    my $params = {data_type => 'statistics', id => $mgid};
    my $stat_node = $self->get_shock_query($params, $self->mgrast_token);
    if (scalar(@{$stat_node}) == 0) {
        return {};
    }
    
    my ($stats, $err) = $self->json->decode($self->get_shock_file($stat_node->[0]{id}, undef, $self->mgrast_token));
    if ($err) {
        $self->return_data( {"ERROR" => $err}, 500 );
    }
    
    my $result = {
        'length_histogram' => {
            'upload' => undef,
            'post_qc' => undef
        },
        'gc_histogram' => {
            'upload' => undef,
            'post_qc' => undef
        },
        'qc' => {
            'bp_profile' => undef,
            'drisee'     => undef,
            'kmer'       => {
                '15_mer' => undef,
                '6_mer'  => undef
            }
        },
        'rarefaction'        => undef,
        'sequence_breakdown' => {},
        'sequence_stats'     => {},
        'ontology'           => {},
        'taxonomy'           => {},
        'source'             => {},
        'function'           => []
    };
    
    # seq stats
    if ($stats->{sequence_stats} && (ref($stats->{sequence_stats}) eq 'HASH')) {
        foreach my $key (keys %{$stats->{sequence_stats}}) {
            eval {
                $result->{sequence_stats}{$key} = $self->toFloat($stats->{sequence_stats}{$key});
            };
        }
    }
    # seq breakdown - don't ask how its done
    eval {
        if ($type && $stats->{sequence_stats}) {
            $result->{sequence_breakdown} = $self->compute_breakdown($stats->{sequence_stats}, $type);
        }
    };
    # source
    if ($stats->{source} && (ref($stats->{source}) eq 'HASH')) {
        foreach my $src (keys %{$stats->{source}}) {
            $result->{source}{$src} = {};
            foreach my $type (keys %{$stats->{source}{$src}}) {
                eval {
                    if (! $stats->{source}{$src}{$type}) {
                        $result->{source}{$src}{$type} = [];
                    } else {
                        $result->{source}{$src}{$type} = [ map { int($_) } @{$stats->{source}{$src}{$type}} ];
                    }
                };
            }
        }
    }
    # qc
    if ($stats->{qc} && (ref($stats->{qc}) eq 'HASH')) {
        foreach my $qc (keys %{$stats->{qc}}) {
            if ($stats->{qc}{$qc} && (ref($stats->{qc}{$qc}) eq 'HASH')) {
                foreach my $type (keys %{$stats->{qc}{$qc}}) {
                    eval {
                        $result->{qc}{$qc}{$type} = $stats->{qc}{$qc}{$type};
                        if (! $stats->{qc}{$qc}{$type}{data}) {
                            $result->{qc}{$qc}{$type}{data} = [];
                        }
                    };
                }
            }
        }
    }
    # tax / ontol
    foreach my $ann (('taxonomy', 'ontology')) {
        if ($stats->{$ann} && (ref($stats->{$ann}) eq 'HASH')) {
            foreach my $type (keys %{$stats->{$ann}}) {
                eval {
                    if (! $stats->{$ann}{$type}) {
                        $result->{$ann}{$type} = [];
                    } else {
                        $result->{$ann}{$type} = [ map { [$_->[0], int($_->[1])] } grep { $_->[0] && $_->[1] } @{$stats->{$ann}{$type}} ];
                    }
                };
            }
        }
    }
    # histograms
    foreach my $hist (('gc_histogram', 'length_histogram')) {
        if ($stats->{$hist} && (ref($stats->{$hist}) eq 'HASH')) {
            foreach my $type (keys %{$stats->{$hist}}) {
                eval {
                    if (! $stats->{$hist}{$type}) {
                        $result->{$hist}{$type} = [];
                    } else {
                        $result->{$hist}{$type} = [ map { [$self->toFloat($_->[0]), int($_->[1])] } @{$stats->{$hist}{$type}} ];
                    }
                };
            }
        }
    }
    # rarefaction
    if ($stats->{rarefaction} && (ref($stats->{rarefaction}) eq 'ARRAY')) {
        eval {
            $result->{rarefaction} = [ map { [int($_->[0]), $self->toFloat($_->[1])] } @{$stats->{rarefaction}} ];
        };
    }
    # functions
    eval {
        $result->{function} = $stats->{function} || [];
    };
    
    return $result;
}

###########################
#  AWE related functions  #
###########################

# submit job to awe using a template
# provided auth is for shock items
sub submit_awe_template {
    my ($self, $info, $template, $auth, $authPrefix, $debug) = @_;
    
    # do template replacement
    my $tt = Template->new( ABSOLUTE => 1 );
    my $awf = '';
    $tt->process($template, $info, \$awf) || die $tt->error();
    
    # Submit job to AWE and check for successful submission
    # mgrast owns awe job, user owns shock data
    if ($debug) {
        return $self->json->decode($awf);
    }
    my $job = $self->post_awe_job($awf, $auth, $auth, 1, $authPrefix, $authPrefix);
    unless ($job && $job->{state} && $job->{state} eq "init") {
        $self->return_data( {"ERROR" => "job could not be submitted"}, 500 );
    }
    return $job;
}

# submit job to awe
sub post_awe_job {
    my ($self, $workflow, $shock_auth, $awe_auth, $is_string, $shockAuthPrefix, $aweAuthPrefix) = @_;

    if (! $aweAuthPrefix) {
        $aweAuthPrefix = "mgrast";
    }
    if (! $shockAuthPrefix) {
        $shockAuthPrefix = "mgrast";
    }

    my $content = undef;
    if ($is_string) {
        $content = { upload => [undef, "workflow.awf", Content => $workflow] }
    } else {
        $content = [ upload => [$workflow] ];
    }

    my $response = undef;
    eval {
        my $post = $self->agent->post($Conf::awe_url.'/job',
                                      'Datatoken', "$shockAuthPrefix ".$shock_auth,
                                      'Authorization', "$aweAuthPrefix ".$awe_auth,
                                      'Content-Type', 'multipart/form-data',
                                      'Content', $content);
        $response = $self->json->decode( $post->content );
    };

    if ($@ || (! ref($response))) {
        $self->return_data( {"ERROR" => "Unable to connect to AWE server"}, 500 );
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to submit to AWE: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# PUT command to perfrom action on a job
sub awe_job_action {
    my ($self, $id, $action, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my ($method, $url);
        if ($action eq 'delete') {
            $method = 'DELETE';
            $url = $Conf::awe_url.'/job/'.$id.'?full';
        } else {
            $method = 'PUT';
            $url = $Conf::awe_url.'/job/'.$id.'?'.$action;
        }
        my $req = POST($url, @args);
        $req->method($method);
        my $act = $self->agent->request($req);
        $response = $self->json->decode( $act->content );
    };
    if ($@ || (! ref($response))) {
        $self->return_data( {"ERROR" => "Unable to PUT to AWE: ".$@}, 500 );
    } else {
        return $response;
    }
}

# get status and awe_id if metagenome job in awe
sub awe_has_job {
    my ($self, $name, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
        $authPrefix = "mgrast";
    }
    
    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::awe_url.'/job?query&info.name='.$name, @args);
        $response = $self->json->decode( $get->content );
    };
    
    if ($response && exists($response->{data}) && (scalar(@{$response->{data}}) > 0)) {
        return ($response->{data}[0]{id}, $response->{data}[0]{state});
    } else {
        return (undef, undef);
    }
}

# get job document
sub get_awe_job {
    my ($self, $id, $auth, $authPrefix, $pass_back_errors) = @_;
    
    if (! $authPrefix) {
        $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::awe_url.'/job/'.$id, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
	    my $err = {"ERROR" => "Unable to GET job $id from AWE: ".$response->{error}[0]};
        if ($pass_back_errors) {
	        return $err;
	    } else {
	        $self->return_data( $err, $response->{status} );
	    }
    } else {
        return $response->{data};
    }
}

# get job report
sub get_awe_log {
    my ($self, $id, $auth, $authPrefix, $pass_back_errors) = @_;
    
    if (! $authPrefix) {
        $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::awe_url.'/job/'.$id.'?report', @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        my $err = {"ERROR" => "Unable to GET report $id from AWE: ".$response->{error}[0]};
        if ($pass_back_errors) {
	        return $err;
	    } else {
	        $self->return_data( $err, $response->{status} );
	    }
    } else {
        return $response->{data};
    }
}

# get merge of awe job and awe report
sub get_awe_full_document {
    my ($self, $id, $auth, $authPrefix) = @_;
    # get objects
    my $awe_job = $self->get_awe_job($id, $auth, $authPrefix, 1);
    my $awe_log = $self->get_awe_log($id, $auth, $authPrefix, 1);
    # check for errors
    if ((! $awe_job) || (! $awe_log) || exists($awe_job->{ERROR}) || exists($awe_log->{ERROR})) {
        return undef;
    }
    my $task_len = scalar(@{$awe_job->{tasks}});
    # merge in workunit logs
    for (my $i=0; $i <= $task_len; $i++) {
        $awe_job->{tasks}[$i]{workunits} = undef;
        eval {
            $awe_job->{tasks}[$i]{workunits} = $awe_log->{tasks}[$i]{workunits};
        };
    }
    return $awe_job;
}

# get list of jobs for query
sub get_awe_query {
    my ($self, $params, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    my $query = '?query';
    unless (exists $params->{'limit'}) {
        $query .= '&limit=0';
    }
    if ($params && (scalar(keys %$params) > 0)) {
        while (my ($key, $value) = each %$params) {
            if (ref($value)) {
                map { $query .= '&'.$key.'='.uri_escape($_) } @$value;
            } else {
                $query .= '&'.$key.'='.uri_escape($value);
            }
        }
    }
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->get($Conf::awe_url.'/job'.$query, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        $self->return_data( {"ERROR" => "Unable to query AWE: ".$@}, 500 );
    } else {
        return $response;
    }
}

# get workunit report
sub get_awe_report {
    my ($self, $id, $type, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $url = $Conf::awe_url.'/work/'.$id.'?report='.$type;
        my $get = $self->agent->get($url, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return "";
    } elsif (exists($response->{error}) && $response->{error}) {
        my $err = $response->{error}[0];
        # special exception for lost workunit
        if (($err =~ /no workunit found/) || ($err =~ /log type.*not found/)) {
            return "";
        }
        $self->return_data( {"ERROR" => "AWE error: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

# get report from completed or suspended task
sub get_task_report {
    my ($self, $task, $type, $auth, $authPrefix, $rank) = @_;
    
    if (! $rank) {
        $rank = 0;
    }
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }
    
    my $wuid = undef;
    if (! $task->{jobid}) {
        # no jobid
        $wuid = $task->{taskid}."_".$rank;
    } elsif (index($task->{taskid}, $task->{jobid}) == 0) {
        # jobid is in taskid
        $wuid = $task->{taskid}."_".$rank;
    } else {
        # add them together
        $wuid = $task->{jobid}."_".$task->{taskid}."_".$rank;
    }
    my $rtext = $self->get_awe_report($wuid, $type, $auth, $authPrefix);
    my $rfile = "awe_".$type.".txt";
    
    # check shock if missing
    if ((! $rtext) && exists($task->{outputs})) {
        foreach my $out (@{$task->{outputs}}) {
            if (($out->{filename} eq $rfile) && $out->{node} && ($out->{node} ne "-")) {
                ($rtext, undef) = $self->get_shock_file($out->{node}, undef, $auth, undef, $authPrefix);
                last;
            }
        }
    }
    return $rtext || "";
}

# delete job document
sub delete_awe_job {
    my ($self, $id, $auth, $authPrefix) = @_;
    
    if (! $authPrefix) {
      $authPrefix = "mgrast";
    }

    my $response = undef;
    eval {
        my @args = $auth ? ('Authorization', "$authPrefix $auth") : ();
        my $get = $self->agent->delete($Conf::awe_url.'/job/'.$id, @args);
        $response = $self->json->decode( $get->content );
    };
    if ($@ || (! ref($response))) {
        return undef;
    } elsif (exists($response->{error}) && $response->{error}) {
        $self->return_data( {"ERROR" => "Unable to DELETE job $id from AWE: ".$response->{error}[0]}, $response->{status} );
    } else {
        return $response->{data};
    }
}

sub empty_awe_task {
    my ($self, $docker) = @_;
    my $task = {
        cmd => {
            args => "",
            description => "",
            name => "",
            environ => {}
        },
        dependsOn => [],
        inputs    => {},
        outputs   => {},
        userattr  => {},
        taskid    => "0",
        totalwork => 1
    };
    if ($docker) {
        $task->{cmd}{Dockerimage} = $Conf::pipeline_docker_image;
    }
    return $task;
}

############################
#  other server functions  #
############################

sub parse_ebi_receipt {
    my ($self, $text) = @_;
    
    my $xml = undef;
    eval {
        $xml = XMLin($text, ForceArray => ['SAMPLE', 'EXPERIMENT', 'ACTIONS', 'RUN', 'INFO', 'ERROR']);
    };
    if ($@ || (! ref($xml))) {
        return {success => 'false', error => $text, info => 'Receipt is not valid XML'};
    }
    my $receipt = {
        success => $xml->{'success'},
        info    => $xml->{'MESSAGES'}{'INFO'},
        error   => $xml->{'MESSAGES'}{'ERROR'} || undef,
        submission => {
            mgrast_accession => $xml->{'SUBMISSION'}{'alias'},
            ena_accession    => $xml->{'SUBMISSION'}{'accession'} || undef,
        },
        study => {
            mgrast_accession  => $xml->{'STUDY'}{'alias'},
            ena_accession     => $xml->{'STUDY'}{'accession'} || undef,
        },
        samples     => [],
        experiments => [],
        runs        => []
    };
    @{$receipt->{samples}}     = map { {mgrast_accession => $_->{alias}, ena_accession => $_->{accession} || undef } } @{$xml->{'SAMPLE'}};
    @{$receipt->{experiments}} = map { {mgrast_accession => $_->{alias}, ena_accession => $_->{accession} || undef } } @{$xml->{'EXPERIMENT'}};
    @{$receipt->{runs}}        = map { {mgrast_accession => $_->{alias}, ena_accession => $_->{accession} || undef } } @{$xml->{'RUN'}};
    
    return $receipt;
}

sub cassandra_test {
    my ($self, $db) = @_;
    my $hosts = $Conf::cassandra_m5nr;
    unless ($hosts && (@$hosts > 0)) {
        return 0;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from cass_connection import CassTest|;
    py_eval($import);
    my $test = Inline::Python::Object->new('__main__', 'CassTest', $hosts, $db);
    return $test->test();
}

sub cassandra_handle {
    my ($self, $db, $version) = @_;
    
    my $hosts = $Conf::cassandra_m5nr;
    unless ($version && $hosts && (@$hosts > 0)) {
        return undef;
    }
    my $test = $self->cassandra_test($db);
    unless ($test) {
        return undef;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from mgrast_cassandra import *|;
    py_eval($import);
    if ($db eq 'm5nr') {
        return Inline::Python::Object->new('__main__', 'M5nrHandle', $hosts, $version);
    } elsif ($db eq 'job') {
        return Inline::Python::Object->new('__main__', 'JobHandle', $hosts, $version);
    } else {
        return undef;
    }
}

sub cassandra_abundance {
    my ($self, $version) = @_;
    
    my $hosts = $Conf::cassandra_m5nr;
    unless ($version && $hosts && (@$hosts > 0)) {
        return undef;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from abundance import Abundance|;
    py_eval($import);
    return Inline::Python::Object->new('__main__', 'Abundance', $hosts, $version);
}

sub cassandra_profile {
    my ($self, $version) = @_;
    
    my $hosts = $Conf::cassandra_m5nr;
    unless ($version && $hosts && (@$hosts > 0)) {
        return undef;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from profile import Profile|;
    py_eval($import);
    return Inline::Python::Object->new('__main__', 'Profile', $hosts, $version);
}

sub cassandra_matrix {
    my ($self, $version) = @_;
    
    my $hosts = $Conf::cassandra_m5nr;
    unless ($version && $hosts && (@$hosts > 0)) {
        return undef;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from matrix import Matrix|;
    py_eval($import);
    return Inline::Python::Object->new('__main__', 'Matrix', $hosts, $version);
}

sub cassandra_m5nr {
    my ($self, $version) = @_;
    
    my $hosts = $Conf::cassandra_m5nr;
    unless ($version && $hosts && (@$hosts > 0)) {
        return undef;
    }
    my $import = q|import sys; sys.path.insert(1, "|.$Conf::pylib_dir.q|"); from m5nr import M5nrUpload|;
    py_eval($import);
    return Inline::Python::Object->new('__main__', 'M5nrUpload', $hosts, $version);
}

sub delete_from_elasticsearch {
    # returns boolean, success or failure
    my ($self, $mgid) = @_;
    
    unless ($mgid) {
        return 0;
    }
    if ($mgid !~ /^mgm/) {
        $mgid = 'mgm'.$mgid;
    }
    my $esurl = $Conf::es_host."/metagenome_index/metagenome/".$mgid;
    my $response = undef;
    eval {
        my $del = $self->agent->delete($esurl);
        $response = $self->json->decode($del->content);
    };
    if ($@ || (! ref($response)) || $response->{error} || (! $response->{result}) || ($response->{result} eq 'not_found')) {
        return 0;
    }
    return 1;
}

sub upsert_to_elasticsearch_metadata {
    # input is metagenome ID - for JobDB queries
    # assume rights checking has already been done
    # returns 'failed' or 'updated'
    my ($self, $mgid, $index, $debug) = @_;
    
    if (! $index) {
        $index = "metagenome_index";
    }
    
    # get job
    my $master = $self->connect_to_datasource();
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    my $job = $master->Job->get_objects( {metagenome_id => $id} );
    unless ( ( $job && @$job) || $self->cgi->param("force") ) {
        return "failed";
    }
    $job = $job->[0];
    
    # get data
    my $esdata = {};
    my $mddb   = MGRAST::Metadata->new();
    my $mixs   = $mddb->is_job_compliant($job);
    my $m_data = $mddb->get_job_metadata($job);
    my $a_data = $job->data();
    my $s_data = $job->stats();
    
    # map
    my $oMap = $ElasticSearch::ontology;
    my $tMap = $ElasticSearch::types;
    my $fMap = $ElasticSearch::fields;
    map { $fMap->{$_} = (split(/\./, $fMap->{$_}))[0] } keys %$fMap;
    
    # job info
    foreach my $k (keys %$job) {
        if ($k && exists($fMap->{$k}) && defined($job->{$k})) {
            $esdata->{ $fMap->{$k} } = $self->jsonTypecast($tMap->{$k}, $job->{$k});
        }
    }
    # job attributes
    foreach my $k (keys %$a_data) {
        if ($k && (exists $fMap->{$k}) && defined($a_data->{$k})) {
            $esdata->{ $fMap->{$k} } = $self->jsonTypecast($tMap->{$k}, $a_data->{$k});
        }
    }
    # job stats
    foreach my $k (keys %$s_data) {
        if ($k && (exists $fMap->{$k}) && defined($s_data->{$k})) {
            $esdata->{ $fMap->{$k} } = $self->jsonTypecast($tMap->{$k}, $s_data->{$k});
        }
    }
    # job metadata
    $esdata->{ $fMap->{'all'} } = "";
    foreach my $md (('project', 'sample', 'library', 'env_package')) {
        my $allmd = 'all_'.$md;
        $esdata->{ $fMap->{$allmd} } = "";
        if (exists($m_data->{$md}) && $m_data->{$md}{id} && $m_data->{$md}{name} && $m_data->{$md}{data}) {
            # _id / _name
            $esdata->{ $fMap->{$md.'_id'} }   = $self->jsonTypecast($tMap->{$md.'_id'}, $m_data->{$md}{id});
            $esdata->{ $fMap->{$md.'_name'} } = $self->jsonTypecast($tMap->{$md.'_name'}, $m_data->{$md}{name});
            $esdata->{$fMap->{'all'}}  = unique_concat($esdata->{$fMap->{'all'}}, $m_data->{$md}{id}." ".$m_data->{$md}{name});
            $esdata->{$fMap->{$allmd}} = unique_concat($esdata->{$fMap->{$allmd}}, $m_data->{$md}{id}." ".$m_data->{$md}{name});
            # _type
            if (exists($fMap->{$md.'_type'}) && $m_data->{$md}{type}) {
                $esdata->{ $fMap->{$md.'_type'} } = $self->jsonTypecast($tMap->{$md.'_type'}, $m_data->{$md}{type});
                $esdata->{$fMap->{'all'}}  = unique_concat($esdata->{$fMap->{'all'}}, $m_data->{$md}{type});
                $esdata->{$fMap->{$allmd}} = unique_concat($esdata->{$fMap->{$allmd}}, $m_data->{$md}{type});
            }
            foreach my $k (keys %{$m_data->{$md}{data}}) {
                if ($k && defined($m_data->{$md}{data}{$k}) && !defined($esdata->{ $fMap->{$k} } ) ) {  # do not write user metadata over job data
                    # all go into catchall
                    $esdata->{$fMap->{'all'}}  = unique_concat($esdata->{$fMap->{'all'}}, $m_data->{$md}{data}{$k});
                    $esdata->{$fMap->{$allmd}} = unique_concat($esdata->{$fMap->{$allmd}}, $m_data->{$md}{data}{$k});
                    # special case for ebi_id
                    if ($k eq 'ebi_id') {
                        my $kx = $md.'_'.$k;
                        $esdata->{ $fMap->{$kx} } = $self->jsonTypecast($tMap->{$kx}, $m_data->{$md}{data}{$k});
                    } elsif (exists $fMap->{$k}) {
                        $esdata->{ $fMap->{$k} } = $self->jsonTypecast($tMap->{$k}, $m_data->{$md}{data}{$k});
                    }
                }
            }
        }
        $esdata->{$fMap->{$allmd}} = $self->jsonTypecast('text', $esdata->{$fMap->{$allmd}});
    }
    $esdata->{$fMap->{'all'}} = $self->jsonTypecast('text', $esdata->{$fMap->{'all'}});
    $esdata->{id} = "mgm".$id;
    $esdata->{job_info_mixs_compliant} = $mixs ? JSON::true : JSON::false;
    
    # ontology IDs
    foreach my $ofield (keys %$oMap) {
        if (exists $esdata->{$ofield}) {
            my $oid = $mddb->get_cv_ontology_id($oMap->{$ofield}, $esdata->{$ofield});
            if ($oid) {
                $esdata->{ $ofield.'_id' } = $oid;
            }
        }
    }
    
    # clean
    foreach my $k (keys %$esdata) {
        if (! defined($esdata->{$k})) {
            delete $esdata->{$k};
        }
    }
    
    if ($debug) {
        return $esdata;
    }
    
    # PUT docuemnt
    $self->json->utf8();
    my $entry = $self->json->encode($esdata);
    my $esurl = $Conf::es_host."/$index/metagenome/".$esdata->{id};
    my $response = undef;
    eval {
        my @args = (
            'Content_Type', 'application/json',
            'Content', $entry
        );
        my $req = POST($esurl, @args);
        $req->method('PUT');
        my $put = $self->agent->request($req);
        $response = $self->json->decode($put->content);
    };
    if ($@ || (! ref($response)) || $response->{error} || (! $response->{result})) {
        return "failed";
    }
    return "updated";
}

sub upsert_to_elasticsearch_annotation {
    # input is metagenome ID - for shock metagenome statistics lookup
    # assume rights checking has already been done
    # returns 'failed' or 'updated'
    my ($self, $mgid, $type, $index, $func, $taxa, $debug) = @_;
    
    # ranges
    my $t_nums = $ElasticSearch::taxa_num;
    my $f_nums = $ElasticSearch::func_num;
    
    my $results  = {};
    my $mg_stats = undef;
    
    if (($type eq 'taxonomy') || ($type eq 'both')) {
        if ((! $taxa) && (! $mg_stats)) {
            $mg_stats = $self->metagenome_stats_from_shock($mgid);
        }
        if (! $taxa) {
            $taxa = $mg_stats->{'taxonomy'};
        }
        $results->{'taxonomy'} = undef;
    }
    if (($type eq 'function') || ($type eq 'both')) {
        if ((! $func) && (! $mg_stats)) {
            $mg_stats = $self->metagenome_stats_from_shock($mgid);
        }
        if (! $func) {
            $func = $mg_stats->{'function'};
        }
        $results->{'function'} = undef;
    }
    
    if (exists($results->{'taxonomy'}) && $taxa) {
        $results->{'taxonomy'} = {
            'id'  => $mgid,
            'all' => ''
        };
        foreach my $level (keys %$taxa) {
            if ($level eq 'species') {
                next;
            }
            my $prefix = lc(substr($level, 0, 1));
            my $total = sum map {$_->[1]} @{$taxa->{$level}};
            foreach my $t (@{$taxa->{$level}}) {
                if (split(/\s+/, $t->[0]) > 1) {
                    next;
                }
                $results->{'taxonomy'}{'all'} = unique_concat($results->{'taxonomy'}{'all'}, $t->[0]);
                my $rel = int((($t->[1] / $total) * 100) + 0.5);
                foreach my $n (@$t_nums) {
                    if ($rel >= $n) {
                        unless (exists $results->{'taxonomy'}{'t_'.$n}) {
                            $results->{'taxonomy'}{'t_'.$n} = "";
                        }
                        $results->{'taxonomy'}{'t_'.$n} .= " ".$prefix.'_'.$t->[0];
                    }
                }
            }
        }
        # clean
        foreach my $k (keys %{$results->{'taxonomy'}}) {
            $results->{'taxonomy'}{$k} = $self->jsonTypecast('text', $results->{'taxonomy'}{$k});
        }
    }
    if (exists($results->{'function'}) && $func) {
        $results->{'function'} = {
            'id'  => $mgid,
            'all' => ''
        };
        my $total = sum map {$_->[1]} @$func;
        foreach my $f (@$func) {
            $results->{'function'}{'all'} = unique_concat($results->{'function'}{'all'}, $f->[0]);
            my $rel = int((($f->[1] / $total) * 100) + 0.5);
            foreach my $n (@$f_nums) {
                if ($rel >= $n) {
                    unless (exists $results->{'function'}{'f_'.$n}) {
                        $results->{'function'}{'f_'.$n} = "";
                    }
                    $results->{'function'}{'f_'.$n} = unique_concat($results->{'function'}{'f_'.$n}, $f->[0]);
                }
            }
        }
        # clean
        foreach my $k (keys %{$results->{'function'}}) {
            $results->{'function'}{$k} = $self->jsonTypecast('text', $results->{'function'}{$k});
        }
    }
    if ($debug) {
        return $results;
    }
    
    $self->json->utf8();
    my $success = {};
    
    # PUT document(s)
    foreach my $key (keys %$results) {
        if ($results->{$key}) {
            my $entry = $self->json->encode($results->{$key});
            my $esurl = $Conf::es_host."/$index/$key/$mgid?parent=$mgid";
            my $response = undef;
                my @args = (
                    'Content_Type', 'application/json',
                    'Content', $entry
                );
                my $req = POST($esurl, @args);
                $req->method('PUT');
                my $put = $self->agent->request($req);
                $response = $put->content;  # If it's an error message, preserve it.
            eval {
                $response = $self->json->decode($put->content);
            };
            if ($@ || (! ref($response)) || $response->{error} || (! $response->{result})) {
                $success->{$key} = "failed: $response";
            }
            $success->{$key} = "updated";
        } else {
            $success->{$key} = "failed";
        }
    }
    
    return $success;
}

sub unique_concat {
    my ($str1, $str2) = @_;
    unless ($str1 || $str2) {
        return "";
    }
    unless ($str1) {
        return $str2;
    }
    unless ($str2) {
        return $str1
    }
    my @parts = split(/\s+/, $str2);
    foreach my $p (@parts) {
        unless ($str1 =~ /\Q$p\E/) {
            $str1 .= " ".$p;
        }
    }
    return $str1;
}

sub get_elastic_query {
    my ($self, $server, $queries, $order, $no_scr, $dir, $match, $after, $limit, $filters, $no_pub, $debug) = @_;

    my $opr = ($match eq 'any') ? 'or' : 'and';
    my $postJSON = {
        "size" => $limit,
        "sort" => [],
        "query" => {
            "bool" => {
                "must" => [],
                "filter" => []
            }
        }
    };
    
    unless ($no_scr) {
        push @{$postJSON->{"sort"}}, { "_score" => {"order" => "desc"} };
    }
    push @{$postJSON->{"sort"}}, { $order => {"order" => $dir} };
      
    # for scrolling
    if ($after) {
        $postJSON->{"search_after"} = [ split(/,/, $after) ];
    }
    
    # filter for project ids and public status (not scored)

    if ($filters) {

        if (@$filters > 1) {
            # this is an or
            foreach my $f (@$filters) {
                push(@{$postJSON->{"query"}{"bool"}{"filter"}[0]{"bool"}{"should"}}, { "terms" => {$f->[0] => $f->[1]} });
            }
        }
        else {
            foreach my $f (@$filters) {
                push(@{$postJSON->{"query"}{"bool"}{"filter"}}, { "terms" => {$f->[0] => $f->[1]} }); 
            }
        }
    }
    
    # do not return public data
    if ($no_pub) {
        $postJSON->{"query"}{"bool"}{"must_not"} = [{
            "term" => { "job_info_public" => JSON::true }
        }];
    }

    # must for query terms (scored)
    foreach my $q (@$queries) {
        my $qstr = $q->{"query"};
        if ($q->{"type"} eq 'boolean') {
            $qstr = ($qstr && ($qstr ne 'false')) ? JSON::true : JSON::false;
        }
        my $query_doc = {
            "query_string" => {
                "default_operator" => $opr,
                "query" => $qstr
            }
        };
        if ($q->{"field"}) {
            $query_doc->{"query_string"}{"default_field"} = $q->{"field"};
        }
        if (($q->{"type"} eq 'child') && $q->{"name"}) {
            $query_doc = {
                "has_child" => {
                    "type" => $q->{"name"},
                    "query" => $query_doc
                }
            };
        }
        push(@{$postJSON->{"query"}{"bool"}{"must"}}, $query_doc);
    }

    if (! scalar(@{$postJSON->{"query"}{"bool"}{"filter"}})) {
        delete $postJSON->{"query"}{"bool"}{"filter"};
    }
    if (! scalar(@{$postJSON->{"query"}{"bool"}{"must"}})) {
        delete $postJSON->{"query"}{"bool"}{"must"};
    }
    
    if ($debug) {
        return {
            "query" => $postJSON,
            "url"   => $server.'/_search'
        };
    }
    
    my $content;
    my $res;  # need it here for error trapping
    eval {
        $res  = $self->agent->post($server.'/_search', Content => $self->json->encode($postJSON), 
                                      "Content-Type", "application/json");
        $content = $self->json->decode($res->content);
    };
    if ($@ || (! ref($content))) {
        # one of the likely things to get us here is that json->decode fails because error message, not json
        $self->return_data( { "ERROR" => $res->content} , 500) ; 
        return undef, $@;
    } elsif (exists $content->{error}) {
        if (ref $content->{error}) {
         eval {
              if (exists($content->{error}{type}) && exists($content->{error}{reason}) && exists($content->{status})) {
                  $self->return_data( {"ERROR" => $content->{error}{type}.": ".$content->{error}{reason}.$res->$content}, $content->{status} );
              } else {
                 $self->return_data( {"ERROR" => "Invalid Elastic Search return response: $res"}, 500 );
              }
        # fallback -- if error, but eval aborts 
        $self->return_data( { "ERROR" => $res->content }, 500) ; } 
        } else {  # content->error is not ref
        $self->return_data( { "ERROR" => "ES response: $content->{error}" }, 500) ; }
    } else {   #no error
        return $content;
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

sub kbase_idserver {
    my ($self, $method, $params) = @_;
    
    my $content = undef;
    my $post_data = {"method" => "IDServerAPI.".$method, "version" => "1.1", "params" => $params};
    eval {
        my $response = $self->agent->post($Conf::idserver_url, Content => $self->json->encode($post_data));
        $content = $self->json->decode( $response->content );
    };
    if ($@ || (! ref($content))) {
        $self->return_data( {"ERROR" => "Unable to access KBase idserver"}, 500 );
    } elsif (exists $content->{error}) {
        $self->return_data( {"ERROR" => $content->{error}{message}}, 500 );
    } elsif (exists $content->{result}) {
        return $content->{result};
    } else {
        $self->return_data( {"ERROR" => "Invalid KBase idserver return response"}, 500 );
    }
}

###################################
#  inbox and submission functions #
###################################

# add submission id to inbox node
sub add_submission {
    my ($self, $node_id, $submit_id, $auth, $authPrefix) = @_;
    my $node = $self->node_from_inbox_id($node_id, $auth, $authPrefix);
    my $attr = $node->{attributes};
    $attr->{submission} = $submit_id;
    $node = $self->update_shock_node($node_id, $attr, $auth, $authPrefix);
    $self->edit_shock_acl($node_id, $auth, 'mgrast', 'put', 'all', $authPrefix);
}

# get inbox object from shock node id
sub node_id_to_inbox {
    my ($self, $id, $auth, $authPrefix) = @_;
    my $node = $self->get_shock_node($id, $auth, $authPrefix);
    return $self->node_to_inbox($node, $auth, $authPrefix);
}

# get inbox object from shock node
sub node_to_inbox {
    my ($self, $node, $auth, $authPrefix) = @_;
    my $info = {
        'id'        => $node->{id},
        'filename'  => $node->{file}{name},
        'filesize'  => $node->{file}{size},
        'checksum'  => $node->{file}{checksum}{md5},
        'timestamp' => $node->{created_on}
    };
    # get file_info / compute if missing or bad state
    unless (exists($node->{attributes}{stats_info}) && ($node->{attributes}{stats_info}{file_type} ne 'none')) {
        ($node, undef) = $self->get_file_info(undef, $node, $auth, $authPrefix);
    }
    $info->{stats_info} = $node->{attributes}{stats_info};
    # add data_type for validated files
    if (exists $node->{attributes}{data_type}) {
        $info->{data_type} = $node->{attributes}{data_type};
    }
    # add submission id if exists
    if (exists $node->{attributes}{submission}) {
        $info->{submission} = $node->{attributes}{submission};
    }
    # add expiration if missing -- NOT for submission nodes !
    if (exists($node->{attributes}{data_type}) && ($node->{attributes}{data_type} ne "submission") && ($node->{expiration} eq "0001-01-01T00:00:00Z")) {
        $self->update_shock_node_expiration($node->{id}, $auth, $authPrefix, "10D");
    }
    return $info;
}

# this takes uuid or node
sub get_file_info {
    my ($self, $uuid, $node, $auth, $authPrefix) = @_;
    
    # get and validate file
    if ($uuid) {
        $node = $self->node_from_inbox_id($uuid, $auth, $authPrefix);
    } elsif ($node && ref($node)) {
        $uuid = $node->{id};
    } else {
        return undef;
    }
    
    # wait on file lock, 10 min timeout
    my $start = time;
    while (exists($node->{file}{locked}) && $node->{file}{locked}) {
        if ($node->{file}{locked}{error}) {
            return (undef, $node->{file}{locked}{error});
        }
        my $curr = time;
        if (($curr - $start) > 600) {
            last;
        }
        sleep 10;
        $node = $self->node_from_inbox_id($uuid, $auth, $authPrefix);
    }
    
    my ($file_type, $err_msg, $file_format, $file_suffix);
    my @file_parts = split(/\./, $node->{file}{name});
    if (scalar(@file_parts) == 1) {
        $file_suffix = ""
    } else {
        $file_suffix = $file_parts[-1];
        # tar excetions
        if ( (($file_suffix eq "gz") || ($file_suffix eq "bz2")) && (scalar(@file_parts) > 2) && ($file_parts[-2] eq "tar") ) {
            $file_suffix = "tar.".$file_suffix;
        }
    }
    
    if (int($node->{file}{size}) == 0) {
        # zero sized file
        ($file_type, $err_msg) = ("empty file", "[error] file '".$node->{file}{name}."' is empty.");
        $file_format = "none";
    } else {
        # download first 2000 bytes of file for quick stats
        my $time = time;
        my $tempfile = $Conf::temp."/temp.".basename($node->{file}{name}).".".$time;
        $self->get_shock_file($uuid, $tempfile, $auth, "length=2000", $authPrefix);
        ($file_type, $err_msg) = $self->verify_file_type($tempfile, $node->{file}{name}, $file_suffix);
        $file_format = $self->get_file_format($tempfile, $file_type, $file_suffix);
        unlink($tempfile);
    }
    
    # get info / update node
    my $stats_info = {
        type      => $file_type,
        suffix    => $file_suffix,
        file_type => $file_format,
        file_name => $node->{file}{name},
        file_size => $node->{file}{size},
        checksum  => $node->{file}{checksum}{md5}
    };
    my $new_attr = $node->{attributes};
    if (exists $new_attr->{stats_info}) {
        map { $new_attr->{stats_info}{$_} = $stats_info->{$_} } keys %$stats_info;
    } else {
        $new_attr->{stats_info} = $stats_info;
    }
    $node = $self->update_shock_node($uuid, $new_attr, $auth, $authPrefix);
    # add mgrast to ACLs
    $self->edit_shock_acl($uuid, $auth, 'mgrast', 'put', 'all', $authPrefix);
    
    # return data
    return ($node, $err_msg);
}

sub normalize_barcode_file {
    my ($self, $uuid, $rc_barcode, $auth, $authPrefix) = @_;
    
    my $to_update = 0;
    my ($btext, $err) = $self->get_shock_file($uuid, undef, $auth, undef, $authPrefix);
    if ($err) {
        $self->return_data( {"ERROR" => $err}, 500 );
    }
    chomp $btext;
    
    my @cdata = ();
    my @bdata = map { [ split(/\t/, $_) ] } split(/\n/, $btext);
    if ($bdata[0][0] =~ /^#?SampleID$/) {
        # skip header: Illumina or Qiime style
        $to_update = 1;
        shift @bdata;
    }
    foreach my $set (@bdata) {
        unless ($set->[0] && $set->[1]) {
            $to_update = 1;
            next;
        }
        if ($set->[1] =~ /^[ATGCatgc-]+$/ ) {
            # correct in second column
            push @cdata, $set;
        } elsif ($set->[0] =~ /^[ATGCatgc-]+$/ ) {
            # incorrect in first column
            push @cdata, [ $set->[1], $set->[0] ];
            $to_update = 1;
        } else {
            # row is missing barcode, skip it
            $to_update = 1;
        }
    }
    if ($rc_barcode) {
        $to_update = 1;
        for (my $i=0; $i<scalar(@cdata); $i++) {
            my $rcseq = $cdata[$i][1];
            $rcseq =~ tr/ATGCatgc/TACGtacg/;
            if ($rcseq =~ /-/) {
                # reverse double barcodes properly
                my @parts = split(/-/, $rcseq);
                $rcseq = reverse($parts[0]).'-'.reverse($parts[1])
            } else {
                $rcseq = reverse($rcseq);
            }
            $cdata[$i][1] = $rcseq;
        }
    }
    # sanity check
    if (scalar(@cdata) < 2) {
        $self->return_data( {"ERROR" => "number of barcodes in barcode_file must be greater than 1"}, 400 );
    }
    my @names = map { $_->[0] } @cdata;
    if ($to_update) {
        # create new barcode file with same metadata as old
        my $ctext = join("\n", map { $_->[0]."\t".$_->[1] } @cdata)."\n";
        my $bar_node = $self->get_shock_node($uuid, $auth, $authPrefix);
        my $new_node = $self->set_shock_node($bar_node->{file}{name}, $ctext, $bar_node->{attributes}, $auth, 1, $authPrefix, "10D");
        $self->delete_shock_node($uuid, $auth, $authPrefix);
        $uuid = $new_node->{id};
    }
    return ($uuid, \@names);
}

sub metadata_validation {
    my ($self, $uuid, $is_inbox, $extract_barcodes, $auth, $authPrefix, $submit_id) = @_;
    
    use MGRAST::Metadata;
    my $mddb = MGRAST::Metadata->new();
    
    # get and check node
    my $node = $self->get_shock_node($uuid, $auth, $authPrefix);
    my $file_suffix = (split(/\./, $node->{file}{name}))[-1];
    unless (($file_suffix eq 'xls') || ($file_suffix eq 'xlsx')) {
        $self->return_data( {"ERROR" => $uuid." (".$node->{file}{name}.") is not an excel format file (.xls or .xlsx)"}, 400 );
    }
    if ($is_inbox && $self->user) {
        my $attr = $node->{attributes};
        $attr->{type}  = "inbox";
        $attr->{id}    = 'mgu'.$self->user->_id;
        $attr->{user}  = $self->user->login;
        $attr->{email} = $self->user->email;
        $attr->{stats_info} = {
            type      => "binary or non-ASCII file",
            suffix    => $file_suffix,
            file_type => "excel",
            file_name => $node->{file}{name},
            file_size => $node->{file}{size},
            checksum  => $node->{file}{checksum}{md5}
        };
        if ($submit_id) {
            $attr->{submission} = $submit_id;
        }
        $node = $self->update_shock_node($uuid, $attr, $auth, $authPrefix);
        $self->edit_shock_acl($uuid, $auth, 'mgrast', 'put', 'all', $authPrefix);
    }
    
    # validate metadata
    my $master = $self->connect_to_datasource();
    my $md_file = $Conf::temp."/".$node->{id}."_".$node->{file}{name};
    $self->get_shock_file($node->{id}, $md_file, $auth, undef, $authPrefix);
    my ($is_valid, $data, $log) = $mddb->validate_metadata($md_file);
    
    my $bar_id = undef;
    my $bar_count = 0;
    my $json_node = undef;
    
    if ($is_valid) {
        # check project permissions
        my $project_name = $data->{data}{project_name}{value};
        my $projects = $master->Project->get_objects( { name => $project_name } );
        if (scalar(@$projects) && (! $self->user->has_right(undef, 'edit', 'project', $projects->[0]->{id}))) {
            $self->return_data( {"ERROR" => "The project name you have chosen already exists and you do not have edit rights to this project"}, 401 );
        }
        # add metadata json format to inbox
        if ($is_inbox && $self->user) {
            my $md_basename = fileparse($node->{file}{name}, qr/\.[^.]*/);
            $self->json->utf8();
            my $md_string = $self->json->encode($data);
            my $json_attr = {
                type  => 'inbox',
                id    => 'mgu'.$self->user->_id,
                user  => $self->user->login,
                email => $self->user->email,
                data_type => 'metadata',
                stats_info => {
                    type      => 'ASCII text',
                    suffix    => 'json',
                    file_type => 'json',
                    file_name => $md_basename.".json",
                    file_size => length($md_string)
                }
            };
            if ($submit_id) {
                $json_attr->{submission} = $submit_id;
            }
            $json_node = $self->set_shock_node($md_basename.".json", $md_string, $json_attr, $auth, 1, $authPrefix, "10D");
            $self->edit_shock_acl($json_node->{id}, $auth, 'mgrast', 'put', 'all', $authPrefix);
        }
        # update origional metadata node
        my $attr = $node->{attributes};
        $attr->{data_type} = 'metadata';
        if ($json_node) {
            $attr->{extracted} = $json_node->{id};
        }
        $self->update_shock_node($node->{id}, $attr, $auth, $authPrefix);
        
        # extract barcodes if exist
        my $barcodes = {};
        foreach my $sample ( @{$data->{samples}} ) {
            next unless ($sample->{libraries} && scalar(@{$sample->{libraries}}));
            foreach my $library (@{$sample->{libraries}}) {
                next unless (exists($library->{data}) && exists($library->{data}{forward_barcodes}));
                my $mg_name = "";
                if (exists $library->{data}{metagenome_name}) {
                    $mg_name = $library->{data}{metagenome_name}{value};
                } elsif (exists $library->{data}{file_name}) {
                    $mg_name = fileparse($library->{data}{file_name}{value}, qr/\.[^.]*/);
                } else {
                    next;
                }
                $barcodes->{$mg_name} = $library->{data}{forward_barcodes}{value};
            }
        }
        $bar_count = scalar(keys(%$barcodes));
        # barcode file: SampleID \t Barcode
        if (($bar_count > 0) && $extract_barcodes && $self->user) {
            my $bar_name = fileparse($node->{file}{name}, qr/\.[^.]*/).".barcodes";
            my $bar_data = join("\n", map { $_."\t".$barcodes->{$_} } keys %$barcodes)."\n";
            my $bar_attr = {
                type  => 'inbox',
                id    => 'mgu'.$self->user->_id,
                user  => $self->user->login,
                email => $self->user->email,
                data_type => 'barcode',
                stats_info => {
                    type      => 'ASCII text',
                    suffix    => 'barcodes',
                    file_type => 'barcodes',
                    file_name => $bar_name,
                    file_size => length($bar_data),
                    checksum  => md5_hex($bar_data),
                    barcode_count => $bar_count
                }
            };
            if ($submit_id) {
                $bar_attr->{submission} = $submit_id;
            }
            my $bar_node = $self->set_shock_node($bar_name, $bar_data, $bar_attr, $auth, 1, $authPrefix, "10D");
            $bar_id = $bar_node->{id};
            $self->edit_shock_acl($bar_node->{id}, $auth, 'mgrast', 'put', 'all', $authPrefix);
        }
    } else {
        $data = $data->{data};
    }
    return ($is_valid, $data, $log, $bar_id, $bar_count, $json_node);
}

# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# returns array of 1 or 2 tasks - may be sff file
sub build_seq_stat_task {
    my ($self, $taskid, $depend, $seq, $seq_type, $auth, $authPrefix) = @_;
    
    # may be sff file, then return 2 tasks
    if ($seq_type && ($seq_type eq "sff")) {
        return $self->build_sff_fastq_task($taskid, $depend, $seq, $auth, $authPrefix);
    } elsif ($seq_type && ($seq_type eq "fna")) {
        $seq_type = "fasta";
    }
    
    my $seq_task = $self->empty_awe_task(1);
    $seq_task->{cmd}{description} = "sequence stats";
    $seq_task->{cmd}{name} = "mgrast_seq_length_stats.pl";
    $seq_task->{taskid} = "$taskid";
    
    # seq node exist - no dependencies
    if ($depend < 0) {
        # get / verify nodes
        my $seq_node = $self->node_from_inbox_id($seq, $auth, $authPrefix);
        unless (exists($seq_node->{attributes}{stats_info}) && ($seq_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($seq_node, undef) = $self->get_file_info(undef, $seq_node, $auth, $authPrefix);
        }
        $seq_type = $self->seq_type_from_node($seq_node, $auth, $authPrefix);
        # seq stats already ran, skip it
        if (exists($seq_node->{attributes}{data_type}) &&
            exists($seq_node->{attributes}{stats_info}{sequence_count}) &&
            ($seq_node->{attributes}{data_type} eq 'sequence') &&
            (($seq_node->{attributes}{stats_info}{sequence_count})*1 > 0) &&
            (($seq_type eq 'fasta') || ($seq_type eq 'fastq'))) {
            $seq_task->{skip} = 1;
        }
        $seq = $seq_node->{file}{name};
        $seq_task->{inputs}{$seq} = {host => $Conf::shock_url, node => $seq_node->{id}, attrfile => "input_attr.json"};
        $seq_task->{outputs}{$seq} = {host => $Conf::shock_url, node => $seq_node->{id}, attrfile => "output_attr.json", type => "update"};
    } else {
        unless ($seq_type) {
            $seq_type = (split(/\./, $seq))[-1];
        }
        $seq_task->{inputs}{$seq} = {host => $Conf::shock_url, node => "-", origin => "$depend", attrfile => "input_attr.json"};
        $seq_task->{outputs}{$seq} = {host => $Conf::shock_url, node => "-", origin => "$depend", attrfile => "output_attr.json", type => "update"};
        push @{$seq_task->{dependsOn}}, "$depend";
    }
    $seq_task->{userattr}{data_type} = "sequence";
    $seq_task->{userattr}{stage_name} = "sequence_stats";
    
    # may be sff file, then return 2 tasks - final check
    if ($seq_type eq "sff") {
        return $self->build_sff_fastq_task($taskid, $depend, $seq, $auth, $authPrefix);
    }
    
    $seq_task->{cmd}{args} = '-input=@'.$seq.' -input_json=input_attr.json -output_json=output_attr.json -type='.$seq_type;
    return ($seq_task);
}


# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# returns array of 2 tasks
sub build_sff_fastq_task {
    my ($self, $taskid, $depend, $sff, $auth, $authPrefix) = @_;
    
    my $sff_task = $self->empty_awe_task(1);
    $sff_task->{cmd}{description} = "sff to fastq";
    $sff_task->{cmd}{name} = "sff_extract_0_2_8";
    $sff_task->{taskid} = "$taskid";
    
    # sff node exist - no dependencies
    if ($depend < 0) {
        # get / verify nodes
        my $sff_node = $self->node_from_inbox_id($sff, $auth, $authPrefix);
        unless (exists($sff_node->{attributes}{stats_info}) && ($sff_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($sff_node, undef) = $self->get_file_info(undef, $sff_node, $auth, $authPrefix);
        }
        unless ($sff_node->{attributes}{stats_info}{file_type} eq 'sff') {
            $self->return_data( {"ERROR" => $sff_node->{file}{name}." (".$sff_node->{id}.") not a sff format file"}, 404 );
        }
        $sff = $sff_node->{file}{name};
        $sff_task->{inputs}{$sff} = {host => $Conf::shock_url, node => $sff_node->{id}};
        $sff_task->{userattr}{parent_sff_file} = $sff_node->{id};
    } else {
        $sff_task->{inputs}{$sff} = {host => $Conf::shock_url, node => "-", origin => "$depend"};
        push @{$sff_task->{dependsOn}}, "$depend";
    }
    my $basename = fileparse($sff, qr/\.[^.]*/);
    $sff_task->{outputs}{"$basename.fastq"} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json"};
    $sff_task->{cmd}{args} = '-Q @'.$sff." -s $basename.fastq";
    $sff_task->{userattr}{stage_name} = "sff_to_fastq";
    
    # add seq stats step - not sff file
    my ($seq_task) = $self->build_seq_stat_task($taskid+1, $taskid, "$basename.fastq", "fastq", $auth, $authPrefix);
    return ($sff_task, $seq_task);
}

# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# returns array of 2 tasks
sub build_pair_join_task {
    my ($self, $taskid, $depend_p1, $depend_p2, $pair1, $pair2, $outprefix, $retain, $userattr, $auth, $authPrefix) = @_;
    
    my $pj_task = $self->empty_awe_task(1);
    $pj_task->{cmd}{description} = "merge mate-pairs";
    $pj_task->{cmd}{name} = "fastq-join";
    $pj_task->{taskid} = "$taskid";
    
    # p1 node exist - no dependencies
    if ($depend_p1 < 0) {
        my $p1_node = $self->node_from_inbox_id($pair1, $auth, $authPrefix);
        unless (exists($p1_node->{attributes}{stats_info}) && ($p1_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($p1_node, undef) = $self->get_file_info(undef, $p1_node, $auth, $authPrefix);
        }
        unless ($self->seq_type_from_node($p1_node, $auth, $authPrefix) eq 'fastq') {
            $self->return_data( {"ERROR" => "pair 1 file must be fastq format"}, 400 );
        }
        $pair1 = $p1_node->{file}{name};
        $pj_task->{inputs}{$pair1} = {host => $Conf::shock_url, node => $p1_node->{id}};
        $pj_task->{userattr}{parent_R1_file} = $p1_node->{id};
    } else {
        $pj_task->{inputs}{$pair1} = {host => $Conf::shock_url, node => "-", origin => "$depend_p1"};
        push @{$pj_task->{dependsOn}}, "$depend_p1";
    }
    # p2 node exist - no dependencies
    if ($depend_p2 < 0) {
        my $p2_node = $self->node_from_inbox_id($pair2, $auth, $authPrefix);
        unless (exists($p2_node->{attributes}{stats_info}) && ($p2_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($p2_node, undef) = $self->get_file_info(undef, $p2_node, $auth, $authPrefix);
        }
        unless ($self->seq_type_from_node($p2_node, $auth, $authPrefix) eq 'fastq') {
            $self->return_data( {"ERROR" => "pair 2 file must be fastq format"}, 400 );
        }
        $pair2 = $p2_node->{file}{name};
        $pj_task->{inputs}{$pair2} = {host => $Conf::shock_url, node => $p2_node->{id}};
        $pj_task->{userattr}{parent_R2_file} = $p2_node->{id};
    } else {
        $pj_task->{inputs}{$pair2} = {host => $Conf::shock_url, node => "-", origin => "$depend_p2"};
        push @{$pj_task->{dependsOn}}, "$depend_p2";
    }

    # build pair join task
    my @outfiles = map { $outprefix.'.'.$_.'.fastq' } ('join', 'un1', 'un2');
    $pj_task->{cmd}{args} = '-m 8 -p 10 @'.$pair1.' @'.$pair2.' -o '.$outprefix.'.%.fastq';
    $pj_task->{userattr}{stage_name} = "pair_join";
    if ($userattr && ref($userattr)) {
        @{$pj_task->{userattr}}{keys %$userattr} = values %$userattr;
    }
    $pj_task->{outputs}{$outfiles[0]} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json", delete => JSON::true};
    if ($retain) {
        $pj_task->{outputs}{$outfiles[1]} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json", delete => JSON::true};
        $pj_task->{outputs}{$outfiles[2]} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json", delete => JSON::true};
    }
    my @tasks = ($pj_task);
    my $depend = $taskid;
    
    # move or merge
    my $seqfile = $outprefix.'.fastq';
    $taskid += 1;
    my $last_task = $self->empty_awe_task(1);
    
    # merge if retain
    if ($retain) {
        $last_task->{cmd}{description} = "merge unjoined";
        $last_task->{cmd}{name} = "sed";
        $last_task->{cmd}{args} = "-n w'$seqfile' ".join(' ', map { '@'.$_ } @outfiles);
        foreach my $outf (@outfiles) {
            $last_task->{inputs}{$outf} = {host => $Conf::shock_url, node => "-", origin => "$depend", attrfile => "input_attr.json"};
        }
    }
    # else rename file
    else {
        $last_task->{cmd}{description} = "rename joined";
        $last_task->{cmd}{name} = "mv";
        $last_task->{cmd}{args} = '@'.$outfiles[0].' '.$seqfile;
        $last_task->{inputs}{$outfiles[0]} = {host => $Conf::shock_url, node => "-", origin => "$depend", attrfile => "input_attr.json"};
    }
    $last_task->{outputs}{$seqfile} = {host => $Conf::shock_url, node => "-", attrfile => "input_attr.json"};
    $last_task->{dependsOn} = ["$depend"];
    $last_task->{taskid} = "$taskid";
    push @tasks, $last_task;
    
    # build seq stats task - not sff file
    $taskid += 1;
    my ($seq_task) = $self->build_seq_stat_task($taskid, $taskid-1, $seqfile, "fastq", $auth, $authPrefix);
    push @tasks, $seq_task;
    
    return @tasks;
}

# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# returns array of 2 or more tasks
sub build_demultiplex_454_task {
    my ($self, $taskid, $depend_seq, $depend_bc, $seq, $barcode, $bc_names, $auth, $authPrefix) = @_;
    
    my $seq_type = "";
    my $dm_task  = $self->empty_awe_task(1);
    $dm_task->{cmd}{description} = "demultiplex 454";
    $dm_task->{cmd}{name} = "demultiplex.py";
    $dm_task->{taskid} = "$taskid";
    
    # seq node exist - no dependencies
    if ($depend_seq < 0) {
        my $seq_node = $self->node_from_inbox_id($seq, $auth, $authPrefix);
        unless (exists($seq_node->{attributes}{stats_info}) && ($seq_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($seq_node, undef) = $self->get_file_info(undef, $seq_node, $auth, $authPrefix);
        }
        $seq = $seq_node->{file}{name};
        $seq_type = $self->seq_type_from_node($seq_node, $auth, $authPrefix);
        $dm_task->{inputs}{$seq} = {host => $Conf::shock_url, node => $seq_node->{id}};
        $dm_task->{userattr}{parent_multx_file} = $seq_node->{id};
    } else {
        $seq_type = (split(/\./, $seq))[-1];
        $dm_task->{inputs}{$seq} = {host => $Conf::shock_url, node => "-", origin => "$depend_seq"};
        push @{$dm_task->{dependsOn}}, "$depend_seq";
    }
    # bc node exist - no dependencies
    my $basename = fileparse($seq, qr/\.[^.]*/);
    if ($depend_bc < 0) {
        my $bc_node = $self->node_from_inbox_id($barcode, $auth, $authPrefix);
        unless (exists($bc_node->{attributes}{stats_info}) && ($bc_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($bc_node, undef) = $self->get_file_info(undef, $bc_node, $auth, $authPrefix);
        }
        $barcode = $bc_node->{file}{name};
        $dm_task->{inputs}{$barcode} = {host => $Conf::shock_url, node => $bc_node->{id}};
    } else {
        $self->return_data( {"ERROR" => "missing barcode file $barcode"}, 400 );
    }
    
    $dm_task->{cmd}{args} = '-f '.$seq_type.' -b @'.$barcode.' -i @'.$seq;
    
    # build outputs
    push @$bc_names, "unmatched";
    foreach my $fname (@$bc_names) {
        $dm_task->{outputs}{"$fname.$seq_type"} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json"};
    }
    $dm_task->{userattr}{stage_name} = "demultiplex";
    
    # add seq stats - not sff file
    my @tasks = ($dm_task);
    my $depend = $taskid;
    foreach my $fname (@$bc_names) {
        $taskid += 1;
        my ($seq_task) = $self->build_seq_stat_task($taskid, $depend, "$fname.$seq_type", $seq_type, $auth, $authPrefix);
        push @tasks, $seq_task;
    }
    
    return @tasks;
}

# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# returns array of 2 or more tasks
sub build_demultiplex_illumina_task {
    my ($self, $taskid, $depend_seq, $depend_bc, $depend_idx1, $depend_idx2, $seq, $barcode, $index1, $index2, $bc_names, $auth, $authPrefix) = @_;
    
    my $double_bc = $index2 ? 1 : 0;
    my $dm_task   = $self->empty_awe_task(1);
    $dm_task->{cmd}{description} = "demultiplex illumina";
    $dm_task->{cmd}{name} = "fastq-multx";
    $dm_task->{taskid} = "$taskid";
    
    # seq 1 node exist - no dependencies
    if ($depend_seq < 0) {
        my $seq_node = $self->node_from_inbox_id($seq, $auth, $authPrefix);
        unless (exists($seq_node->{attributes}{stats_info}) && ($seq_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($seq_node, undef) = $self->get_file_info(undef, $seq_node, $auth, $authPrefix);
        }
        $seq = $seq_node->{file}{name};
        $dm_task->{inputs}{$seq} = {host => $Conf::shock_url, node => $seq_node->{id}};
        $dm_task->{userattr}{parent_multx_file} = $seq_node->{id};
    } else {
        $dm_task->{inputs}{$seq} = {host => $Conf::shock_url, node => "-", origin => "$depend_seq"};
        push @{$dm_task->{dependsOn}}, "$depend_seq";
    }
    # bc node exist - no dependencies
    if ($depend_bc < 0) {
        my $bc_node = $self->node_from_inbox_id($barcode, $auth, $authPrefix);
        unless (exists($bc_node->{attributes}{stats_info}) && ($bc_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($bc_node, undef) = $self->get_file_info(undef, $bc_node, $auth, $authPrefix);
        }
        $barcode = $bc_node->{file}{name};
        $dm_task->{inputs}{$barcode} = {host => $Conf::shock_url, node => $bc_node->{id}};
    } else {
        $self->return_data( {"ERROR" => "missing barcode file $barcode"}, 400 );
    }
    # index 1 node exist - no dependencies
    if ($depend_idx1 < 0) {
        my $idx_node = $self->node_from_inbox_id($index1, $auth, $authPrefix);
        unless (exists($idx_node->{attributes}{stats_info}) && ($idx_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($idx_node, undef) = $self->get_file_info(undef, $idx_node, $auth, $authPrefix);
        }
        $index1 = $idx_node->{file}{name};
        $dm_task->{inputs}{$index1} = {host => $Conf::shock_url, node => $idx_node->{id}};
    } else {
        $dm_task->{inputs}{$index1} = {host => $Conf::shock_url, node => "-", origin => "$depend_idx1"};
        push @{$dm_task->{dependsOn}}, "$depend_idx1";
    }
    # index 2 node exist - no dependencies
    if ($double_bc) {
        if ($depend_idx2 < 0) {
            my $idx_node = $self->node_from_inbox_id($index2, $auth, $authPrefix);
            unless (exists($idx_node->{attributes}{stats_info}) && ($idx_node->{attributes}{stats_info}{file_type} ne 'none')) {
                ($idx_node, undef) = $self->get_file_info(undef, $idx_node, $auth, $authPrefix);
            }
            $index2 = $idx_node->{file}{name};
            $dm_task->{inputs}{$index2} = {host => $Conf::shock_url, node => $idx_node->{id}};
        } else {
            $dm_task->{inputs}{$index2} = {host => $Conf::shock_url, node => "-", origin => "$depend_idx2"};
            push @{$dm_task->{dependsOn}}, "$depend_idx2";
        }
        # double bc command
        $dm_task->{cmd}{args} = '-B @'.$barcode.' @'.$index1.' @'.$index2.' @'.$seq.' -o n/a -o n/a -o %.fastq';
    } else {
        # single bc command
        $dm_task->{cmd}{args} = '-B @'.$barcode.' @'.$index1.' @'.$seq.' -o n/a -o %.fastq';
    }
    
    # build outputs
    push @$bc_names, "unmatched";
    foreach my $fname (@$bc_names) {
        $dm_task->{outputs}{$fname.'.fastq'} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json"};
    }
    $dm_task->{userattr}{stage_name} = "demultiplex";
    
    # add seq stats - not sff file
    my @tasks = ($dm_task);
    my $depend = $taskid;
    foreach my $fname (@$bc_names) {
        $taskid += 1;
        my ($seq_task) = $self->build_seq_stat_task($taskid, $depend, $fname.'.fastq', 'fastq', $auth, $authPrefix);
        push @tasks, $seq_task;
    }
    
    return @tasks;
}

# if input node has no dependency, then value is -1 and it is a shock node id,
# otherwise shock node does not exist and its a filename
# creates pair-join task for each paired demultiplex output
# returns array of 2 or more tasks
sub build_demultiplex_pairjoin_task {
    my ($self, $taskid, $depend_seq1, $depend_seq2, $depend_bc, $depend_idx1, $depend_idx2, $seq1, $seq2, $barcode, $index1, $index2, $bc_names, $retain, $auth, $authPrefix) = @_;
    
    my $double_bc = $index2 ? 1 : 0;
    my $dm_task   = $self->empty_awe_task(1);
    $dm_task->{cmd}{description} = "demultiplex illumina";
    $dm_task->{cmd}{name} = "fastq-multx";
    $dm_task->{taskid} = "$taskid";
    
    # seq 1 node exist - no dependencies
    if ($depend_seq1 < 0) {
        my $seq_node = $self->node_from_inbox_id($seq1, $auth, $authPrefix);
        unless (exists($seq_node->{attributes}{stats_info}) && ($seq_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($seq_node, undef) = $self->get_file_info(undef, $seq_node, $auth, $authPrefix);
        }
        $seq1 = $seq_node->{file}{name};
        $dm_task->{inputs}{$seq1} = {host => $Conf::shock_url, node => $seq_node->{id}};
        $dm_task->{userattr}{parent_R1_file} = $seq_node->{id};
    } else {
        $dm_task->{inputs}{$seq1} = {host => $Conf::shock_url, node => "-", origin => "$depend_seq1"};
        push @{$dm_task->{dependsOn}}, "$depend_seq1";
    }
    if ($depend_seq2 < 0) {
        my $seq_node = $self->node_from_inbox_id($seq2, $auth, $authPrefix);
        unless (exists($seq_node->{attributes}{stats_info}) && ($seq_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($seq_node, undef) = $self->get_file_info(undef, $seq_node, $auth, $authPrefix);
        }
        $seq2 = $seq_node->{file}{name};
        $dm_task->{inputs}{$seq2} = {host => $Conf::shock_url, node => $seq_node->{id}};
        $dm_task->{userattr}{parent_R2_file} = $seq_node->{id};
    } else {
        $dm_task->{inputs}{$seq2} = {host => $Conf::shock_url, node => "-", origin => "$depend_seq2"};
        push @{$dm_task->{dependsOn}}, "$depend_seq2";
    }
    # bc node exist - no dependencies
    if ($depend_bc < 0) {
        my $bc_node = $self->node_from_inbox_id($barcode, $auth, $authPrefix);
        unless (exists($bc_node->{attributes}{stats_info}) && ($bc_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($bc_node, undef) = $self->get_file_info(undef, $bc_node, $auth, $authPrefix);
        }
        $barcode = $bc_node->{file}{name};
        $dm_task->{inputs}{$barcode} = {host => $Conf::shock_url, node => $bc_node->{id}};
    } else {
        $self->return_data( {"ERROR" => "missing barcode file $barcode"}, 400 );
    }
    # index 1 node exist - no dependencies
    if ($depend_idx1 < 0) {
        my $idx_node = $self->node_from_inbox_id($index1, $auth, $authPrefix);
        unless (exists($idx_node->{attributes}{stats_info}) && ($idx_node->{attributes}{stats_info}{file_type} ne 'none')) {
            ($idx_node, undef) = $self->get_file_info(undef, $idx_node, $auth, $authPrefix);
        }
        $index1 = $idx_node->{file}{name};
        $dm_task->{inputs}{$index1} = {host => $Conf::shock_url, node => $idx_node->{id}};
    } else {
        $dm_task->{inputs}{$index1} = {host => $Conf::shock_url, node => "-", origin => "$depend_idx1"};
        push @{$dm_task->{dependsOn}}, "$depend_idx1";
    }
    # index 2 node exist - no dependencies
    if ($double_bc) {
        if ($depend_idx2 < 0) {
            my $idx_node = $self->node_from_inbox_id($index2, $auth, $authPrefix);
            unless (exists($idx_node->{attributes}{stats_info}) && ($idx_node->{attributes}{stats_info}{file_type} ne 'none')) {
                ($idx_node, undef) = $self->get_file_info(undef, $idx_node, $auth, $authPrefix);
            }
            $index2 = $idx_node->{file}{name};
            $dm_task->{inputs}{$index2} = {host => $Conf::shock_url, node => $idx_node->{id}};
        } else {
            $dm_task->{inputs}{$index2} = {host => $Conf::shock_url, node => "-", origin => "$depend_idx2"};
            push @{$dm_task->{dependsOn}}, "$depend_idx2";
        }
        # double bc command
        $dm_task->{cmd}{args} = '-B @'.$barcode.' @'.$index1.' @'.$index2.' @'.$seq1.' @'.$seq2.' -o n/a -o n/a -o %.R1.fastq -o %.R2.fastq';
    } else {
        # single bc command
        $dm_task->{cmd}{args} = '-B @'.$barcode.' @'.$index1.' @'.$seq1.' @'.$seq2.' -o n/a -o %.R1.fastq -o %.R2.fastq';
    }
    
    # build outputs, set intermediate files to delete
    my @outpairs = ();
    push @$bc_names, "unmatched";
    foreach my $fname (@$bc_names) {
        $dm_task->{outputs}{$fname.'.R1.fastq'} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json", delete => JSON::true};
        $dm_task->{outputs}{$fname.'.R2.fastq'} = {host => $Conf::shock_url, node => "-", attrfile => "userattr.json", delete => JSON::true};
        push @outpairs, [$fname.'.R1.fastq', $fname.'.R2.fastq', $fname];
    }
    $dm_task->{userattr}{stage_name} = "demultiplex";
    
    # add pair-join for each output pair
    my @tasks = ($dm_task);
    my $depend = $taskid;
    my $userattr = {parent_R1_file => $dm_task->{userattr}{parent_R1_file}, parent_R2_file => $dm_task->{userattr}{parent_R2_file}};
    foreach my $set (@outpairs) {
        # my ($self, $taskid, $depend_p1, $depend_p2, $pair1, $pair2, $outprefix, $retain, $userattr, $auth, $authPrefix) = @_;
        my @pj_tasks = $self->build_pair_join_task($taskid+1, $depend, $depend, $set->[0], $set->[1], $set->[2], $retain, $userattr, $auth, $authPrefix);
        $taskid += scalar(@pj_tasks);
        push @tasks, @pj_tasks;
    }
    
    return @tasks;
}

sub node_from_inbox_id {
    my ($self, $uuid, $auth, $authPrefix) = @_;
    my $node = $self->get_shock_node($uuid, $auth, $authPrefix);
    unless ( exists($node->{attributes}{type}) && ($node->{attributes}{type} eq 'inbox') &&
             exists($node->{attributes}{id}) && (($node->{attributes}{id} eq 'mgu'.$self->user->_id) || ($node->{attributes}{id} eq $self->user->{login})) ) {
        $self->return_data( {"ERROR" => "file id '$uuid' does not exist in your inbox"}, 404 );
    }
    return $node;
}

sub seq_type_from_node {
    my ($self, $node, $auth, $authPrefix) = @_;
    unless (exists($node->{attributes}{stats_info}) && ($node->{attributes}{stats_info}{file_type} ne 'none')) {
        my $err_msg;
        ($node, $err_msg) = $self->get_file_info(undef, $node, $auth, $authPrefix);
        if ($err_msg) {
            $self->return_data( {"ERROR" => $err_msg}, 404 );
        }
    }
    my $file_type = $node->{attributes}{stats_info}{file_type};
    unless (($file_type eq 'fasta') || ($file_type eq 'fastq')) {
        $self->return_data( {"ERROR" => "Invalid file_type: $file_type"}, 404 );
    }
    return $file_type;
}

sub is_sff_file {
    my ($self, $uuid, $node, $auth, $authPrefix) = @_;
    # get node
    if ($uuid) {
        $node = $self->node_from_inbox_id($uuid, $auth, $authPrefix);
    } elsif ($node && ref($node)) {
        $uuid = $node->{id};
    } else {
        return 0;
    }
    # get type
    unless (exists($node->{attributes}{stats_info}) && ($node->{attributes}{stats_info}{file_type} ne 'none')) {
        my $err_msg;
        ($node, $err_msg) = $self->get_file_info(undef, $node, $auth, $authPrefix);
        if ($err_msg) {
            $self->return_data( {"ERROR" => $err_msg}, 404 );
        }
    }
    if ($node->{attributes}{stats_info}{file_type} eq 'sff') {
        return 1;
    }
    return 0;
}

sub verify_file_type {
    my ($self, $tempfile, $fname, $file_suffix) = @_;
    # Need to do the 'safe-open' trick here, file might be hard to escape in the shell
    open(P, "-|", "file", "-b", "$tempfile") || $self->return_data( {"ERROR" => "unable to verify file type/format"}, 400 );
    my $file_type = <P>;
    close(P);
    chomp $file_type;
    if ( $file_type =~ m/\S/ ) {
	    $file_type =~ s/^\s+//;   #...trim leading whitespace
	    $file_type =~ s/\s+$//;   #...trim trailing whitespace
    } else {
	    # file does not work for fastq -- craps out for lines beginning with '@'
	    # check first 4 lines for fastq like format
	    my @lines = `cat -A '$tempfile' 2>/dev/null | head -n4`;
	    chomp @lines;
	    if ( ($lines[0] =~ /^\@/) && ($lines[0] =~ /\$$/) && ($lines[1] =~ /\$$/) &&
	         ($lines[2] =~ /^\+/) && ($lines[2] =~ /\$$/) && ($lines[3] =~ /\$$/) ) {
	        $file_type = 'ASCII text';
	    } else {
	        $file_type = 'unknown file type';
	    }
    }
    if ($file_type =~ /^ASCII/) {
	    # ignore some useless information and stuff that gets in when the file command guesses wrong
	    $file_type =~ s/, with very long lines//;
	    $file_type =~ s/C\+\+ program //;
	    $file_type =~ s/Java program //;
	    $file_type =~ s/English //;
    } else {
	    $file_type = "binary or non-ASCII file";
    }
    # now return type and error
    if ( ($file_type eq 'ASCII text') ||
         ($file_type eq 'ASCII text, with CR line terminators') ||
         ($file_type eq 'ASCII text, with CRLF line terminators') ) {
        return ($file_type, "");
    } elsif ($file_suffix eq 'sff') {
        return ("binary sff sequence file", "");
    } elsif (($file_suffix eq 'xls') || ($file_suffix eq 'xlsx')) {
        return ("binary excel spreadsheet file", "");
    } elsif (($file_suffix eq 'tar') || ($file_suffix eq 'zip')) {
        return ("binary $file_suffix archive file", "")
    } elsif (($file_suffix eq 'gz') || ($file_suffix eq 'bz2')) {
        return ("binary $file_suffix compressed file", "")
    } elsif (($file_suffix eq 'tar.gz') || ($file_suffix eq 'tar.bz2')) {
        return ("binary ".(split(/\./, $file_suffix))[1]." compressed tar archive file", "")
    }
    
    return ($file_type, "[error] file '$fname' is of unsupported file type '$file_type'.");
}

sub get_file_format {
    my ($self, $tempfile, $file_type, $file_suffix) = @_;
    if ($file_suffix eq 'qual') {
	    return 'qual';
    }
    if (($file_type =~ /^binary/) && ($file_suffix eq 'sff')) {
	    return 'sff';
    }
    if (($file_suffix eq 'xls') || ($file_suffix eq 'xlsx')) {
        return 'excel';
    }
    if (($file_type =~ /^binary/) && ($file_suffix =~ /tar|zip|gz|bz2$/)) {
        return $file_suffix;
    }
    # identify fasta or fastq
    if ($file_type =~ /^ASCII/) {
	    my @chars;
	    my $old_eol = $/;
	    my $line;
	    my $i;
	    open(TMP, "<$tempfile") || $self->return_data( {"ERROR" => "unable to verify file type/format"}, 400 );
	    # ignore blank lines at beginning of file
	    while (defined($line = <TMP>) and chomp $line and $line =~ /^\s*$/) {}
	    close(TMP);
	    $/ = $old_eol;

	    if ($line =~ /^LOCUS/) {
	        return 'genbank';
	    } elsif ($line =~ /^>/) {
	        return 'fasta';
        } elsif ($line =~ /^@/) {
	        return 'fastq';
        } else {
	        return 'text';
	    }
    } else {
	    return 'unknown';
    }
}

###################
#  math functions #
###################

sub uuidv4 {
    my ($self) = @_;
    my $uuid = create_uuid(UUID_V4);
    return uuid_to_string($uuid);
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

sub strToNum {
    my ($self, $x) = @_;
    if (int($x) == $x) {
        return int($x);
    } else {
        return $x * 1.0;
    }
}

sub jsonTypecast {
    my ($self, $type, $val) = @_;
    unless (defined($val)) {
        return undef;
    }
    if (($type eq 'text') || ($type eq 'keyword')) {
        $val =~ s/^\s+//;
        $val =~ s/\s+$//;
        $val =~ s/\s+/ /g;
    } elsif ( $type eq 'arrayText' ) {
        my @array  = split(';', $val);
        $val = \@array; 
         
    } elsif (($type eq 'integer') || ($type eq 'long')) {
        if ($val =~ /^[+-]?\d+$/) {
            $val = int($val);
        } else {
            $val = undef;
        }
    } elsif ($type eq 'float') {
        if ($val =~ /^[+-]?\d*\.?\d+$/) {
            $val = $val * 1.0
        } else {
            $val = undef;
        }
    } elsif ($type eq 'date') {
        $val =~ s/^\s+//;
        $val =~ s/\s+$//;
        $val =~ s/\s+/T/;
        $val =~ s/\-00/-01/g;
    } elsif ($type eq 'boolean') {
        $val = $val ? JSON::true : JSON::false;
    }
    return $val;
}

sub get_alpha_diversity {
    my ($self, $org_map) = @_;
    # org_map = taxa => abundance
    my $alpha = 0;
    my $h1    = 0;
    my $sum   = sum values %$org_map;
    
    unless ($sum) {
        return $alpha;
    }
    foreach my $num (values %$org_map) {
        my $p = $num / $sum;
        if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
    }
    $alpha = 2 ** $h1;
    
    return $alpha;
}

sub get_rarefaction_xy {
    my ($self, $org_map, $nseq) = @_;
    # org_map = taxa => abundance
    my $rare = [];
    my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
    my @nums = sort {$a <=> $b} values %$org_map;
    my $k    = scalar @nums;

    for (my $n = 0; $n < $nseq; $n += $size) {
        my $coeff = nCr2ln($nseq, $n);
        my $curr  = 0;
        map { $curr += exp( nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
        push @$rare, [ $n, $k - $curr ];
    }
    
    return $rare;
}

# log of N choose R 
sub nCr2ln {
    my ($n, $r) = @_;

    my $c = 1;
    if ($r > $n) {
        return $c;
    }
    if (($r < 50) && ($n < 50)) {
        map { $c = ($c * ($n - $_)) / ($_ + 1) } (0..($r-1));
        return log($c);
    }
    if ($r <= $n) {
        $c = gammaln($n + 1) - gammaln($r + 1) - gammaln($n - $r); 
    } else {
        $c = -1000;
    }
    return $c;
}

# This is Stirling's formula for gammaln, used for calculating nCr
sub gammaln {
    my ($x) = @_;
    unless ($x > 0) { return 0; }
    my $s = log($x);
    return log(2 * 3.14159265458) / 2 + $x * $s + $s / 2 - $x;
}

# fuzzy math here
sub compute_breakdown {
    my ($self, $stats, $seq_type) = @_;
    
    my $raw_seqs    = exists($stats->{sequence_count_raw}) ? $stats->{sequence_count_raw} : 0;
    my $qc_rna_seqs = exists($stats->{sequence_count_preprocessed_rna}) ? $stats->{sequence_count_preprocessed_rna} : 0;
    my $qc_seqs     = exists($stats->{sequence_count_preprocessed}) ? $stats->{sequence_count_preprocessed} : 0;
    my $rna_sims    = exists($stats->{sequence_count_sims_rna}) ? $stats->{sequence_count_sims_rna} : 0;
    my $aa_sims     = exists($stats->{sequence_count_sims_aa}) ? $stats->{sequence_count_sims_aa} : 0;
    my $aa_reads    = exists($stats->{read_count_processed_aa}) ? $stats->{read_count_processed_aa} : 0;
    my $r_clusts    = exists($stats->{cluster_count_processed_rna}) ? $stats->{cluster_count_processed_rna} : 0;
    my $r_clust_seq = exists($stats->{clustered_sequence_count_processed_rna}) ? $stats->{clustered_sequence_count_processed_rna} : 0;
    my $clusts      = exists($stats->{cluster_count_processed_aa}) ? $stats->{cluster_count_processed_aa} : (exists($stats->{cluster_count_processed}) ? $stats->{cluster_count_processed} : 0);
    my $clust_seq   = exists($stats->{clustered_sequence_count_processed_aa}) ? $stats->{clustered_sequence_count_processed_aa} : (exists($stats->{clustered_sequence_count_processed}) ? $stats->{clustered_sequence_count_processed} : 0);
    
    my $is_rna  = ($seq_type eq 'Amplicon') ? 1 : 0;
    my $is_gene = ($seq_type eq 'Metabarcode') ? 1 : 0;
    my $qc_fail_seqs  = $raw_seqs - $qc_seqs;
    my $ann_aa_reads  = $aa_sims ? ($aa_sims - $clusts) + $clust_seq : 0;
    my $unkn_aa_reads = $aa_reads - $ann_aa_reads;
    my $ann_rna_reads = $rna_sims ? ($rna_sims - $r_clusts) + $r_clust_seq : 0;
    my $unknown_all   = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads);

    # amplicon rna numbers
    if ($is_rna) {
        $qc_fail_seqs  = $raw_seqs - $qc_rna_seqs;
        $unkn_aa_reads = 0;
        $ann_aa_reads  = 0;
        $unknown_all   = $raw_seqs - ($qc_fail_seqs + $ann_rna_reads);
        if ($raw_seqs < ($qc_fail_seqs + $ann_rna_reads)) {
            my $diff = ($qc_fail_seqs + $ann_rna_reads) - $raw_seqs;
            $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
        }
    }
    # amplicon gene numbers
    elsif ($is_gene) {
        $ann_rna_reads = 0;
        $unknown_all = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads);
        if ($raw_seqs < ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads)) {
            my $diff = ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads) - $raw_seqs;
            $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
        }
    }
    # wgs / mt numbers
    else {
        # get correct qc rna
        if ($qc_rna_seqs > $qc_seqs) {
            $ann_rna_reads = int((($qc_seqs * 1.0) / $qc_rna_seqs) * $ann_rna_reads);
        }
        if ($unknown_all < 0) { $unknown_all = 0; }
        if ($raw_seqs < ($qc_fail_seqs + $unknown_all + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads)) {
            my $diff = ($qc_fail_seqs + $unknown_all + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
            $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
        }
        if (($unknown_all == 0) && ($raw_seqs < ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads))) {
            my $diff = ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
            $unkn_aa_reads = ($diff > $unkn_aa_reads) ? 0 : $unkn_aa_reads - $diff;
        }
        ## hack to make MT numbers add up
        if (($unknown_all == 0) && ($unkn_aa_reads == 0) && ($raw_seqs < ($qc_fail_seqs + $ann_aa_reads + $ann_rna_reads))) {
            my $diff = ($qc_fail_seqs + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
            $ann_rna_reads = ($diff > $ann_rna_reads) ? 0 : $ann_rna_reads - $diff;
        }
        my $diff = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads);
        if ($unknown_all < $diff) {
            $unknown_all = $diff;
        }
    }
    
    return {
        total        => int($raw_seqs),
        failed_qc    => abs($qc_fail_seqs),
        unknown      => abs($unknown_all),
        unknown_prot => abs($unkn_aa_reads),
        known_prot   => abs($ann_aa_reads),
        known_rna    => abs($ann_rna_reads)
    };
  }

# obfuscate an mg-rast id
sub obfuscate {
  my ($self, $id) = @_;
  
  my @set = ('0' ..'9', 'a' .. 'f');
  my $str = join '' => map $set[rand @set], 1 .. 10;
  $id = unpack ("H*",$id);
  $id = $str.$id;
  
  return $id;
}

# resolve an obfuscated mg-rast id
# if it is an mg-rast id already, return it as is
sub idresolve {
  my ($self, $id) = @_;

  unless ($id =~ /^mgm/ or $id =~ /^mgp/ or $id =~ /^\d+\.\d+$/) { 
    if(length($id) >=10){
    $id = substr $id, 10;
    $id = pack (qq{H*},qq{$id});
   }
  }
  
  return $id;
}

sub normailze_pipeline_version {
    my ($self, $pv) = @_;
    my @nums = split(/\./, $pv);
    my $nv = $nums[0] * 100;
    if (scalar(@nums) > 1) {
        $nv += ($nums[1] * 10);
    }
    if (scalar(@nums) > 2) {
        $nv += ($nums[2] * 1);
    }
    return $nv;
}

sub to_swap {
    my ($self, $job) = @_;
    my $pv = $job->data('pipeline_version')->{pipeline_version} || $self->{default_pipeline_version};
    my $nv = $self->normailze_pipeline_version($pv);
    if (($nv < 400) || ($nv > 403)) {
        return undef;
    } else {
        return 1;
    }
}

# mgids with NO mgm prefix
sub to_swap_set {
    my ($self, $mgids) = @_;
    my $master = $self->connect_to_datasource();
    my $pv_set = $master->Job->get_job_pipelines($mgids, $self->{default_pipeline_version});
    my $sw_set = [];
    foreach my $m (@$mgids) {
        my $nv = $self->normailze_pipeline_version($pv_set->{$m});
        if (($nv < 400) || ($nv > 403)) {
            push @$sw_set, undef;
        } else {
            push @$sw_set, 1;
        }
    }
    return $sw_set;
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
