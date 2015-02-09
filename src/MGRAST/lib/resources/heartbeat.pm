package resources::heartbeat;

use strict;
use warnings;
no warnings('once');

use parent qw(resources::resource);

# Override parent constructor
sub new {
  my ($class, @args) = @_;
  
  # Call the constructor of the parent class
  my $self = $class->SUPER::new(@args);
  
  # Add name / attributes
  $self->{name} = "heartbeat";
  $self->{services} = { 'FTP' => 'ftp://ftp.metagenomics.anl.gov',
			'website' => 'http://metagenomics.anl.gov/',
			'SHOCK' => $Conf::shock_url,
			'AWE' => $Conf::awe_url,
			'M5NR' => $Conf::m5nr_solr,
			'solr' => $Conf::job_solr,
			'postgres' => 'db',
			'mySQL' => 'db' };
  $self->{attributes} = { "service" => [ 'string', "cv", [ ['FTP', 'file server'],
							   ['website', 'MG-RAST website'],
							   ['SHOCK', 'object storage'],
							   ['AWE', 'worker engine'],
							   ['M5NR', 'non-redundant sequence database'],
							   ['solr', 'search engine'],
							   ['postgres', 'analysis database'],
							   ['mySQL', 'job database']
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
		  'url' => $self->cgi->url."/".$self->name,
		  'description' => "Status of services",
		  'type' => 'object',
		  'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		  'requests' => [ { 'name'        => "info",
				    'request'     => $self->cgi->url."/".$self->name,
				    'description' => "Returns description of parameters and attributes.",
				    'method'      => "GET" ,
				    'type'        => "synchronous" ,  
				    'attributes'  => "self",
				    'parameters'  => { 'options'  => {},
						       'required' => {},
						       'body'     => {} }
				  },
				  { 'name'        => "instance",
				    'request'     => $self->cgi->url."/".$self->name."/{SERVICE}",
				    'description' => "Returns the status of a service.",
				    'example'     => [ 'curl -X GET -H "auth: auth_key" "'.$self->cgi->url."/".$self->name.'/M5NR"',
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
  
  if ($self->{services}->{$id} eq 'db') {
    if ($id eq 'postgres') {
      my $dbh = DBI->connect(
			     "DBI:Pg:database=".$Conf::mgrast_db.";host=".$Conf::mgrast_dbhost.";".$Conf::pgsslcert,
			     $Conf::mgrast_dbuser,
			     $Conf::mgrast_dbpass
			    );
      if ($dbh) {
	$status = 1;
      }
    } else {
      my $jobcache_db = $Conf::mgrast_jobcache_db;
      my $jobcache_host = $Conf::mgrast_jobcache_host;
      my $jobcache_user = $Conf::mgrast_jobcache_user;
      my $jobcache_password = $Conf::mgrast_jobcache_password;      
      my $dbh = DBI->connect("DBI:mysql:database=".$jobcache_db.";host=".$jobcache_host.";",
			     $jobcache_user,
			     $jobcache_password);
      if ($dbh) {
	$status = 1;
      }
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
  $obj->{url} = $self->cgi->url."/".$self->name."/".$id;
  
  # check the status service
  $self->return_data($obj, undef, 1);
}

1;
