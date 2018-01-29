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
		    'url' => $self->url."/".$self->name,
		    'description' => "Elastic search for Metagenomes.",
		    'type' => 'object',
		    'documentation' => $self->url.'/api.html#'.$self->name,
		    'requests' => [
                    { 'name'        => "info",
				      'request'     => $self->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET",
				      'type'        => "synchronous",
				      'attributes'  => "self",
				      'parameters'  => {'options' => {}, 'required' => {}, 'body' => {}}
					},
				    { 'name'        => "query",
				      'request'     => $self->url."/".$self->name,
				      'description' => "Elastic search",
				      'example'     => [ $self->url."/".$self->name."?material=saline water",
                                         'return the first ten datasets that have saline water as the sample material' ],
				      'method'      => "GET",
				      'type'        => "synchronous",
				      'attributes'  => $self->attributes,
				      'parameters'  => {'options' => {}, 'required' => {}, 'body' => {}}
				    },
				    { 'name'        => "upsert",
				      'request'     => $self->url."/".$self->name."/{ID}",
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
  my $public = $self->cgi->param('public') || undef;
  my $limit  = $self->cgi->param('limit') || 10;
  my $after  = $self->cgi->param('after') || undef;
  my $order  = $self->cgi->param('order') || "metagenome_id";
  my $dir    = $self->cgi->param('direction') || 'asc';
  
  # validate paramaters
  unless (($dir eq 'asc') || ($dir eq 'desc')) {
      $self->return_data({"ERROR" => "Direction must be 'asc' or 'desc' only."}, 404);
  }
  unless (exists $self->{fields}{$order}) {
      $self->return_data({"ERROR" => "Invalid order field, must be one of the returned fields."}, 404);
  }
  if (($limit > 1000) || ($limit < 1)) {
    $self->return_data({"ERROR" => "Limit must be less than 1,000 and greater than 0 ($limit) for query."}, 404);
  }
  
  # explicitly setting the default CGI parameters for returned url strings
  $self->cgi->param('limit', $limit);
  $self->cgi->param('after', $after);
  $self->cgi->param('order', $order);
  $self->cgi->param('direction', $dir);

  # get query fields
  my $query = {};
  foreach my $field (keys %{$self->{fields}}) {
    next if $field eq 'public';
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
  my $ins = [];

  if ($public && (($public eq "1") || ($public eq "true") || ($public eq "yes")) ) {
    $query->{"job_info_public"} = { "entries" => [ 1 ], "type" => "boolean" };
  } elsif ($self->user) {
    if (! $self->user->has_star_right('view', 'metagenome')) {
	  my $in = [];
	  @$in = map { "mgm".$_ } @{$self->user->has_right_to(undef, 'view', 'metagenome')};
	  if (scalar(@$in)) {
	    push(@$ins, [ "id", $in ]);
	  }
	  if (! defined $self->cgi->param('public') || ($self->cgi->param('public') eq "1")  || ($self->cgi->param('public') eq "true")  || ($self->cgi->param('public') eq "yes") ) {
	    push(@$ins, [ "job_info_public", [ "true" ] ]);
	  }
    } else {
	  if (defined $self->cgi->param('public') && (($self->cgi->param('public') eq "0")  || ($self->cgi->param('public') eq "false")  || ($self->cgi->param('public') eq "no")) ) {
	    push(@$ins, [ "job_info_public", [ "false" ] ]);
	  }
    }
  } else {
    push(@$ins, [ "job_info_public", [ "true" ] ]);
  }
  my ($data, $error) = $self->get_elastic_query($Conf::es_host."/metagenome_index/metagenome", $query, $self->{fields}{$order}, $dir, $after, $limit, $ins ? $ins : undef);
  
  if ($error) {
    $self->return_data({"ERROR" => "An error occurred: $error"}, 500);
  } else {
    $self->return_data($self->prepare_data($data, $limit, $after), 200);
  }
  
  exit 0;
}

sub prepare_data {
  my ($self, $data, $limit, $after) = @_;
  
  my $d = $data->{hits}->{hits} || [];
  my $next_after = $d->[-1]{sort}[0];
  
  my @params = $self->cgi->param;
  my $add_params = join('&', map {$_."=".$self->cgi->param($_)} grep {$_ ne 'after'} @params);
  
  my $obj = {
      "total_count" => $data->{hits}->{total} || 0,
      "limit"       => $limit,
      "url"         => $self->url."/".$self->name."?$add_params".($after ? "&after=$after" : ""),
      "next"        => $self->url."/".$self->name."?$add_params&after=$next_after",
      "version"     => 1,
      "data"        => []
  };
  if ($after) {
      $obj->{after} = $after;
  }
  
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
