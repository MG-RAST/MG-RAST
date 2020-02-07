package resources::library;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->{user} ? map {$_, 1} @{$self->{user}->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{post_actions} = {
        'addaccession' => 1
    };
    $self->{name} = "library";
    $self->{rights} = \%rights;
    $self->{attributes} = { "id"           => [ 'string', 'unique object identifier' ],
    	                    "name"         => [ 'string', 'human readable identifier' ],
    	                    "sequencesets" => [ 'list', [ 'reference sequenceset', 'a list of references to the related sequence sets' ] ],
    	                    "metagenome"   => [ 'reference metagenome', 'reference to the related metagenome object' ],
    	                    "sample"       => [ 'reference sample', 'reference to the related sample object' ],
    	                    "project"      => [ 'reference project', 'reference to the project object' ],
    	                    "metadata"     => [ 'hash', 'key value pairs describing metadata' ],
    	                    "created"      => [ 'date', 'time the object was first created' ],
    	                    "version"      => [ 'integer', 'version of the object' ],
    	                    "url"          => [ 'uri', 'resource location of this object instance' ]
    	                  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->url."/".$self->name,
		    'description' => "A library of metagenomic sequences from some environment linked to a specific sample",
		    'type' => 'object',
		    'documentation' => $self->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $self->url."/".$self->name,				      
				      'description' => "Returns a set of data matching the query criteria.",
				      'example'     => [ $self->url."/".$self->name."?limit=20&order=name",
				                         'retrieve the first 20 libraries ordered by name' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "next"   => [ "uri", "link to the previous set or null if this is the first set" ],
							 "prev"   => [ "uri", "link to the next set or null if this is the last set" ],
							 "order"  => [ "string", "name of the attribute the returned data is ordered by" ],
							 "data"   => [ "list", [ "object", [$self->attributes, "list of the library objects"] ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ] ] ],
									    'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->url."/".$self->name."/{id}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->url."/".$self->name."/mgl52924?verbosity=full",
  				                         'retrieve all data for library mgl52924' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns a standard subselection of metadata' ],
												     [ 'full', 'returns all connected metadata' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				  ]
		  };

    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;

    # check for parameters
    my @parameters = $self->cgi->param;
    if ( (scalar(@{$self->rest}) == 0) &&
         ((scalar(@parameters) == 0) || ((scalar(@parameters) == 1) && ($parameters[0] eq 'keywords'))) )
    {
        $self->info();
    }
    if ($self->method eq 'POST') {
        if ((scalar(@{$self->rest}) > 1) && exists($self->{post_actions}{$self->rest->[1]})) {
            $self->post_action();
        } else {
            $self->info();
        }
    } elsif ( ($self->method eq 'GET') && scalar(@{$self->rest}) ) {
         $self->instance();
    } else {
        $self->query();
    }
}

sub post_action {
    my ($self) = @_;

    # get rest parameters
    my $rest = $self->rest;
    # get database
    my $master = $self->connect_to_datasource();

    # check id format
    my ($id) = $rest->[0] =~ /^mgl(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get sample
    my $library = $master->MetaDataCollection->init( {ID => $id} );
    unless (ref($library)) {
        $self->return_data( {"ERROR" => "id ".$rest->[0]." does not exists"}, 404 );
    }

    # check rights
    foreach my $mg (@{$library->metagenome_ids}) {
        unless ($self->user && ($self->user->has_star_right('edit', 'metagenome') || $self->user->has_right(undef, 'edit', 'metagenome', $mg))) {
            $self->return_data( { "ERROR" => "insufficient permissions" }, 401 );
        }
    }

    # add external db accesion ID
    if ($rest->[1] eq 'addaccession') {
        # get paramaters
        my $dbname    = $self->cgi->param('dbname') || "";
        my $accession = $self->cgi->param('accession') || "";
        unless ($dbname && $accession) {
            $self->return_data( {"ERROR" => "Missing required options: dbname or accession"}, 404 );
        }
        # update DB
        my $key = lc($dbname).'_id';
        $library->data($key, $accession);
        # return success
        $self->return_data( {"OK" => "accession added", "library" => 'mgl'.$id, $key => $accession}, 200 );
    }
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $rest = $self->rest;
    my ($id) = $rest->[0] =~ /^mgl(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }

    # get database
    my $master = $self->connect_to_datasource();
  
    # get data
    my $library = $master->MetaDataCollection->init( {ID => $id} );
    unless (ref($library)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }

    # prepare data
    my $data = $self->prepare_data([ $library ]);
    $data = $data->[0];

    $self->return_data($data)
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master = $self->connect_to_datasource();
    my $dbh    = $master->db_handle();
  
    my $library_found = {};
    my $library_map   = {};
    my $job_lib_map   = {};
    my $job_library   = $dbh->selectall_arrayref("SELECT library, metagenome_id, public FROM Job WHERE viewable=1 AND library IS NOT NULL");
    map { $library_map->{$_->[0]} = {id => $_->[1], name => $_->[2], entry_date => $_->[3]} } @{$dbh->selectall_arrayref("SELECT _id, ID, name, entry_date FROM MetaDataCollection WHERE type='library'")};
  
    # add libraries with job: public or rights
    foreach my $jl (@$job_library) {
        next unless ($jl && $jl->[0] && $library_map->{$jl->[0]});
        $job_lib_map->{$jl->[0]} = 1;
        if (($jl->[2] && ($jl->[2] == 1)) || exists($self->rights->{$jl->[1]}) || exists($self->rights->{'*'})) {
            $library_found->{$jl->[0]} = $library_map->{$jl->[0]};
        }
    }
    # add libraries with no job
    map { $library_found->{$_} = $library_map->{$_} } grep { ! exists $job_lib_map->{$_} } keys %$library_map;
    my $libraries = [];
    @$libraries   = values %$library_found;
    my $total     = scalar @$libraries;

    # check limit
    my $limit   = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset  = $self->cgi->param('offset') || 0;
    my $order   = $self->cgi->param('order')  || "id";
    @$libraries = sort { $a->{$order} cmp $b->{$order} } @$libraries;
    $limit      = (($limit == 0) || ($limit > scalar(@$libraries))) ? scalar(@$libraries) : $limit;
    @$libraries = @$libraries[$offset..($offset+$limit-1)];

    # prepare data to the correct output format
    my $data = $self->prepare_data($libraries);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);

    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($self, $data) = @_;

  my $mddb;
  my $master = $self->connect_to_datasource();
  if ($self->cgi->param('verbosity') && $self->cgi->param('verbosity') ne 'minimal') {
    use MGRAST::Metadata;
    my $mddb = MGRAST::Metadata->new();
  }

  my $objects = [];
  foreach my $library (@$data) {
      if ($library->{ID}) {
          $library->{id} = $library->{ID};
      }
      my $url = $self->url;
      my $obj = {};
      $obj->{id}      = "mgl".$library->{id};
      $obj->{name}    = $library->{name};
      $obj->{url}     = $url.'/library/'.$obj->{id};
      $obj->{version} = 1;
      $obj->{created} = $library->{entry_date};
    
      if ($self->cgi->param('verbosity')) {
          if ($self->cgi->param('verbosity') ne 'minimal' && ref($library) ne 'JobDB::MetaDataCollection') {
	          $library = $master->MetaDataCollection->init( {ID => $library->{id}} );
          }
          if ($self->cgi->param('verbosity') eq 'full') {
	          my $proj = $library->project;
	          my @jobs = grep { $_->{public} || exists($self->rights->{$_->{metagenome_id}}) || exists($self->rights->{'*'}) } @{$library->jobs};
	          my $ljob = (@jobs > 0) ? $jobs[0] : undef;
	          my $samp = ref($library->parent) ? $library->parent : undef;
	          $obj->{project}       = $proj ? ["mgp".$proj->{id}, $url."/project/mgp".$proj->{id}] : undef;
              $obj->{sample}        = $samp ? ["mgs".$samp->{ID}, $url."/sample/mgs".$samp->{ID}] : undef;
	          $obj->{reads}         = $ljob ? ["mgm".$ljob->{metagenome_id}, $url.'/metagenome/mgm'.$ljob->{metagenome_id}] : undef;
	          $obj->{metagenome}    = $ljob ? ["mgm".$ljob->{metagenome_id}, $url.'/metagenome/mgm'.$ljob->{metagenome_id}] : undef;
	          $obj->{sequence_sets} = [];
	          if ($ljob) {
	              my ($seq_sets, $skip) = $self->get_download_set($ljob->{metagenome_id}, undef, $self->mgrast_token, 1);
	              $obj->{sequence_sets} = $seq_sets;
	          }
          }
          if ($self->cgi->param('verbosity') eq 'verbose' || $self->cgi->param('verbosity') eq 'full') {
	          my $mdata = $library->data();
	          if ($self->cgi->param('template')) {
	              $mdata = $mddb->add_template_to_data($library->lib_type, $mdata);
	          }
	          $obj->{metadata} = $mdata;
          } elsif ($self->cgi->param('verbosity') ne 'minimal') {
	          $self->return_data( {"ERROR" => "invalid value for option verbosity"}, 400 );
          }
      }
      push @$objects, $obj;      
  }
  return $objects;
}

1;
