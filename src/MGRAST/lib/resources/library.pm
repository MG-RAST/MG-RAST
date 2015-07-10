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
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "A library of metagenomic samples from some environment",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $self->cgi->url."/".$self->name,				      
				      'description' => "Returns a set of data matching the query criteria.",
				      'example'     => [ $self->cgi->url."/".$self->name."?limit=20&order=name",
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
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->cgi->url."/".$self->name."/mgl52924?verbosity=full",
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
  
    my $libraries_hash = {};
    my $library_map    = {};
    my $job_lib_map    = {};
    my $job_library    = $dbh->selectall_arrayref("SELECT library, metagenome_id, public FROM Job WHERE viewable=1");
    map { $library_map->{$_->[0]} = {id => $_->[1], name => $_->[2], entry_date => $_->[3]} } @{$dbh->selectall_arrayref("SELECT _id, ID, name, entry_date FROM MetaDataCollection WHERE type='library'")};
  
    # add libraries with job: public or rights
    foreach my $jl (@$job_library) {
        next unless ($library_map->{$jl->[0]});
        $job_lib_map->{$jl->[0]} = 1;
        if (($jl->[2] == 1) || exists($self->rights->{$jl->[1]}) || exists($self->rights->{'*'})) {
            $libraries_hash->{"mgl".$library_map->{$jl->[0]}} = $library_map->{$jl->[0]};
        }
    }
    # add libraries with no job
    map { $libraries_hash->{"mgl".$library_map->{$_}} = $library_map->{$_} } grep { ! exists $job_lib_map->{$_} } keys %$library_map;
    my $libraries = [];
    @$libraries   = map { $libraries_hash->{$_} } keys(%$libraries_hash);
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
      my $url = $self->cgi->url;
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
	          $obj->{sequence_sets} = $ljob ? $self->get_download_set($ljob->{metagenome_id}, $self->mgrast_token, 1) : [];
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
