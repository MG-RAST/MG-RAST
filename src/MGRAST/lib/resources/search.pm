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
  my ($class, @args) = @_;
  
  # Call the constructor of the parent class
  my $self = $class->SUPER::new(@args);
  
  # Add name / attributes
  $self->{name} = "search";
  $self->{attributes} = {};
  $self->{fields} = $ElasticSearch::fields;
  
  return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
            'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "Elastic search for Metagenomes.",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [
                    { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET",
				      'type'        => "synchronous",
				      'attributes'  => "self",
				      'parameters'  => {'options' => {}, 'required' => {}, 'body' => {}}
					},
				    { 'name'        => "query",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Elastic search",
				      'example'     => [ $self->cgi->url."/".$self->name."?material=saline water",
                                         'return the first ten datasets that have saline water as the sample material' ],
				      'method'      => "GET",
				      'type'        => "synchronous",
				      'attributes'  => $self->attributes,
				      'parameters'  => {'options' => {}, 'required' => {}, 'body' => {}}
				    },
				    { 'name'        => "upsert",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Elastic Upsert",
				      'method'      => "GET",
				      'type'        => "synchronous",
				      'attributes'  => { "metagenome_id" => [ "string", "unique MG-RAST metagenome identifier" ],
                                         "status"        => [ 'string', 'status of action' ] },
				      'parameters'  => {'options' => {}, 'required' => {"id" => ["string","unique object identifier"]}, 'body' => {}}
				    },
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
    my $mgid = $self->idresolve($rest->[0]);
    my (undef, $id) = $mgid =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }
    
    # check rights
    unless ($self->user && ($self->user->has_right(undef, 'edit', 'metagenome', $id) || $self->user->has_star_right('edit', 'metagenome'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for metagenome ".$mgid}, 401 );
    }
    
    # create and upsert
    my $debug = $self->cgi->param('debug');
    my $success = $self->upsert_to_elasticsearch($id, $debug);
    if ($debug) {
        $self->return_data($success);
    }
    $self->return_data({ metagenome_id => $mgid, status => $success ? "updated" : "failed" });
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
  my ($self) = @_;

  $self->json->utf8();

  # get paramaters
  my $limit  = $self->cgi->param('limit') || 10;
  my $offset = $self->cgi->param('offset') || 0;
  my $order  = $self->cgi->param('order') || "metagenome_id";
  my $dir    = $self->cgi->param('direction') || 'asc';
    
  # check CV
  if (($limit > 1000) || ($limit < 1)) {
    $self->return_data({"ERROR" => "Limit must be less than 1,000 and greater than 0 ($limit) for query."}, 404);
  }
  
  # explicitly setting the default CGI parameters for returned url strings
  $self->cgi->param('limit', $limit);
  $self->cgi->param('offset', $offset);
  $self->cgi->param('order', $order);
  $self->cgi->param('direction', $dir);

  # get query fields
  my $query = {};
  foreach my $field (keys %{$self->{fields}}) {
    if ($self->cgi->param($field)) {
      my $type = $ElasticSearch::types->{$field};
      my @param = $self->cgi->param($field);
      my $entries = [];
      foreach my $p (@param) {
	if ($p =~ /\s/) {
	  push(@$entries, split(/\s/, $p));
	} else {
	  push(@$entries, $p);
	}
      }
      unless ($field eq "all") {
	my $key = $self->{fields}->{$field};
	$key =~ s/\.keyword$//;
	$field = $key;
      }
      $query->{$field} = { "entries" => $entries, "type" => $type };
    }
  }
  my $in = undef;
  if ($self->user) {
    if (! $self->user->has_star_right('view', 'metagenome')) {
      @$in = map { "mgm".$_ } @{$self->user->has_right_to(undef, 'view', 'metagenome')};
    }
  } else {
    $query->{"job_info_public"} = { "entries" => [ 1 ], "type" => "boolean" };
  }
  if (defined $self->cgi->param('public') && $self->cgi->param('public') == 1) {
    $in = undef;
  }
  my ($data, $error) = $self->get_elastic_query($Conf::es_host."/metagenome_index/metagenome", $query, $self->{fields}->{$order}, $dir, $offset, $limit, $in ? [ "id", $in ] : undef, defined $self->cgi->param('public') && $self->cgi->param('public') == 0 );
  
  if ($error) {
    $self->return_data({"ERROR" => "An error occurred: $error"}, 500);
  } else {
    $self->return_data($self->prepare_data($data, $limit), 200);
  }
  
  exit 0;
}

sub prepare_data {
  my ($self, $data, $limit) = @_;

  my $d = $data->{hits}->{hits} || [];
  my $total = $data->{hits}->{total} || 0;
  
  my $obj = $self->check_pagination($d, $total, $limit);
  $obj->{version} = 1;
  $obj->{data} = [];

  my %rev = ();
  foreach my $key (keys(%{$self->{fields}})) {
    my $val = $self->{fields}->{$key};
    $val =~ s/\.keyword$//;
    $rev{$val} = $key;
  }
  foreach my $set (@$d) {
    my $entry = {};
    foreach my $k (keys(%{$set->{_source}})) {
      if (defined $rev{$k}) {
	$entry->{$rev{$k}} = $set->{_source}->{$k};
      } else {
	$entry->{$k} = $set->{_source}->{$k};
      }
    }
    push(@{$obj->{data}}, $entry);
  }
  
  return $obj;
}

1;
