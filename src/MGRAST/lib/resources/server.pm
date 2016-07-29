package resources::server;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use Cache::Memcached;
use parent qw(resources::resource);
use WebApplicationDBHandle;

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "server";
    $self->{attributes} = { "id"                 => [ 'string', 'unique identifier of this server' ],
                            "version"            => [ 'string', 'version number of the server' ],
                            "status"             => [ 'string', 'status of the server' ],
			    "info"               => [ 'string', 'informational text, i.e. downtime warnings' ],
                            "metagenomes"        => [ 'integer', 'total number of metagenomes' ],
                            "public_metagenomes" => [ 'integer', 'total number of public metagenomes' ],
                            "sequences"          => [ 'integer', 'total number of sequences' ],
                            "basepairs"          => [ 'integer', 'total number of basepairs' ],
                            "url"                => [ 'uri', 'resource location of this object instance' ]
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
                    'url' => $self->cgi->url."/".$self->name,
                    'description' => "The server resource returns information about a server.",
                    'type' => 'object',
                    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
                    'requests' => [ { 'name'        => "info",
                                      'request'     => $self->cgi->url."/".$self->name,
                                      'description' => "Returns the server information.",
                                      'method'      => "GET" ,
                                      'type'        => "synchronous" ,  
                                      'attributes'  => "self",
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => {},
                                                         'body'        => {} } },
                                    { 'name'        => "instance",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Returns a single user object.",
                                      'example'     => [ 'curl -X GET "'.$self->cgi->url."/".$self->name.'/MG-RAST"',
							 "info for the MG-RAST server" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => { "id" => [ "string", "unique server ID" ] },
                                                         'body'        => {} } },
                                     ]
                                 };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
  my ($self) = @_;
  
  # check for twitter status
  if ($self->rest->[0] eq 'twitter') {
    my $count = $self->rest->[1] || 5;
    my $data = `curl -s -X GET -H "Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAF%2BttwAAAAAADIFy3lxo9On1Qjx3SWZPCGIEOGU%3DeeNP5cxZXM7W70fE2A30dk2Hw4IwAuK3TSNEaK7pCJU1TY4VJ0" "https://api.twitter.com/1.1/statuses/user_timeline.json?screen_name=mg_rast&count=$count&trim_user=1"`;
    $self->return_data($self->json->decode($data));
  }

  # get the current messasge (if any) from SHOCK
  my $dis_msg;
  my $inf_msg;
  my $node = $self->get_shock_node($Conf::status_message_shock_node_id);
  if (ref $node && $node->{attributes}->{status} eq 'active') {
    if ($node->{attributes}->{severity} eq 'info') {
      $inf_msg = $node->{attributes}->{message};
    } elsif ($node->{attributes}->{severity} eq 'down') {
      $dis_msg = $node->{attributes}->{message};
    }
  }

  # get a dbmaster
  my $master = $self->connect_to_datasource();
  
  # cache DB counts
  my $counts = {};
  my $memd = new Cache::Memcached {'servers' => $Conf::web_memcache, 'debug' => 0, 'compress_threshold' => 10_000 };
  my $cache_key = "mgcounts";
  my $cdata = $memd->get("mgcounts");
  
  if ($cdata) {
    $counts = $cdata;
  } else {
    my ($min, $max, $avg, $stdv) = @{ $master->JobStatistics->stats_for_tag('drisee_score_raw', undef, undef, 1) };
    $counts = {
	       "metagenomes" => $master->Job->count_all(),
	       "public_metagenomes" => $master->Job->count_public(),
	       "sequences" => $master->Job->count_total_sequences(),
	       "basepairs" => $master->Job->count_total_bp(),
	       "driseemin" => $min,
	       "driseemax" => $max,
	       "driseeavg" => $avg,
	       "driseestdv" => $stdv
	      };
    $memd->set("mgcounts", $counts, 7200);
  }
  $memd->disconnect_all;
  
  # prepare data
  my $data = {
	      "id" => "MG-RAST",
	      "version" => $Conf::server_version,
	      "status" => $dis_msg ? "server down" : "ok",
	      "info" => $dis_msg ? $dis_msg : $inf_msg,
	      "metagenomes" => $counts->{metagenomes},
	      "public_metagenomes" => $counts->{public_metagenomes},
	      "sequences" => $counts->{sequences},
	      "basepairs" => $counts->{basepairs},
	      "drisee" => $counts->{drisee},
	      "url" => $self->cgi->url."/".$self->name."/MG-RAST"
	     };
  
  $self->return_data($data);
}

1;
