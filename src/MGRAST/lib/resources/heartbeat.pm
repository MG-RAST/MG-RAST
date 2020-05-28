package resources::heartbeat;

use strict;
use warnings;
no warnings('once');

use MongoDB;
use parent qw(resources::resource);

# Override parent constructor
sub new {
  my ($class, @args) = @_;
  
  # Call the constructor of the parent class
  my $self = $class->SUPER::new(@args);
  
  # Add name / attributes
  $self->{name} = "heartbeat";
  $self->{m5nr_version} = 1;
  $self->{services} = {
#      'FTP' => 'ftp://'.$Conf::ftp_download,
      'website' => $Conf::web_site,
      'SHOCK' => $Conf::shock_url,
      'SHOCKDB' => 'mongo',
      'AWE' => $Conf::awe_url,
      'AWEDB' => 'mongo',
      'M5NR' => $Conf::m5nr_solr,
      'solr' => $Conf::job_solr,
      'mySQL' => 'mysql',
      'cassandra' => $Conf::cassandra_m5nr
  };
  $self->{attributes} = { "service" => [ 'string', "cv", [
#                               ['FTP', 'file server'],
							   ['website', 'MG-RAST website'],
							   ['SHOCK', 'object storage'],
							   ['SHOCKDB', 'object storage mongodb'],
							   ['AWE', 'worker engine'],
							   ['AWEDB', 'worker engine mongodb'],
							   ['M5NR', 'non-redundant sequence database'],
							   ['solr', 'search engine'],
							   ['mySQL', 'job database'],
							   ['cassandra', 'analysis database'],
							 ] ],
			  "status"  => [ 'boolean', 'service is up or not' ],
			  "url"     => [ 'url', 'resource location of this resource']
			};
  return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
  my ($self) = @_;
  my $content = { 'name' => $self->name,
		  'url' => $self->url."/".$self->name,
		  'description' => "Status of services",
		  'type' => 'object',
		  'documentation' => $self->url.'/api.html#'.$self->name,
		  'requests' => [ { 'name'        => "info",
				    'request'     => $self->url."/".$self->name,
				    'description' => "Returns description of parameters and attributes.",
				    'method'      => "GET" ,
				    'type'        => "synchronous" ,  
				    'attributes'  => "self",
				    'parameters'  => { 'options'  => {},
						       'required' => {},
						       'body'     => {} }
				  },
				  { 'name'        => "instance",
				    'request'     => $self->url."/".$self->name."/{SERVICE}",
				    'description' => "Returns the status of a service.",
				    'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->url."/".$self->name.'/M5NR"',
						       "status of the M5NR service" ],
				    'method'      => "GET" ,
				    'type'        => "synchronous" ,  
				    'attributes'  => $self->attributes,
				    'parameters'  => { 'options' => {},
						       'required' => { "service" => [ "cv", $self->{attributes}->{service}->[2] ] },
						       'body'     => {} }
				  } ]
		};
  $self->return_data($content);
}

# the resource is called with a service parameter
sub instance {
  my ($self) = @_;
  
  # check id format
  my $rest = $self->rest;
  my $id = $rest->[0];
  if (! $self->{services}->{$id}) {
    $self->return_data( {"ERROR" => "invalid service name: " . $rest->[0]}, 400 );
  }
  
  my $status = 0;
  
  if ($self->{services}->{$id} eq 'mysql') {
    my $jobcache_db = $Conf::mgrast_jobcache_db;
    my $jobcache_host = $Conf::mgrast_jobcache_host;
    my $jobcache_user = $Conf::mgrast_jobcache_user;
    my $jobcache_password = $Conf::mgrast_jobcache_password;      
    my $dbh = DBI->connect("DBI:mysql:database=".$jobcache_db.";host=".$jobcache_host.";", $jobcache_user, $jobcache_password);
    if ($dbh) {
      $status = 1;
    }
  } elsif ($self->{services}->{$id} eq 'mongo') {
      my ($host, $port);
      if ($id eq 'SHOCKDB') {
          ($host, $port) = split(/:/, $Conf::shock_mongo_url);
      } elsif ($id eq 'AWEDB') {
          ($host, $port) = split(/:/, $Conf::awe_mongo_url);
      }
      my $client = MongoDB::MongoClient->new(host => $host, port => $port);
      if ($client) {
          $status = 1;
      }
  } elsif ($id eq 'cassandra') {
      # need to test a query as handle can still be made but cluster in bad state
      # test md5 is 74428bf03d3c75c944ea0b2eb632701f / E. coli alcohol dehydrogenase / m5nr version 1
      my $test_md5    = '74428bf03d3c75c944ea0b2eb632701f';
      my $test_source = "RefSeq";
      my $test_data = [];
      eval {
          my $chdl = $self->cassandra_handle("m5nr", $self->{m5nr_version});
          $test_data = $chdl->get_records_by_md5([$test_md5], $test_source);
          $chdl->close();
      };
      if ((! $@) && (@$test_data > 0)) {
          $status = 1;
      }
  } else {
    my $ua = $self->agent;
    $ua->timeout(10);
    my $url = $self->{services}->{$id};
    my $response = $ua->get($url);
    if ($response->is_success) {
      $status = 1;
    }
  }
  
  my $obj = {};
  $obj->{service} = $id;
  $obj->{status} = $status;
  $obj->{url} = $self->url."/".$self->name."/".$id;
  
  # check the status service
  $self->return_data($obj, undef, 1);
}

1;
