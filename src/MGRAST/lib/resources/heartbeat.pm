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
			  'SHOCK' => 'http://shock.metagenomics.anl.gov/',
			  'AWE' => 'http://140.221.67.236:8000/',
			  # 'M5NR' => 'http://140.221.67.212:8983/solr/',
			  'solr' => 'http://140.221.67.239:8983/solr/',
			  'postgres' => 'db',
			  'mySQL' => 'db' };
    $self->{attributes} = { "service" => [ 'string', "cv", [ ['FTP', 'file server'],
							     ['website', 'MG-RAST website'],
							     ['SHOCK', 'object storage']
							     ['AWE', 'worker engine'],
							     #['M5NR', 'non-redundant sequence database'],
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
			       "DBI:Pg:database=mgrast_analysis;host=kharkov-1.igsb.anl.gov;sslcert=/homes/jbischof/tmp/.postgresql/postgresql.crt;sslkey=/homes/jbischof/tmp/.postgresql/postgresql.key",
			       "mgrastprod",
			       "rsTZ4etXYWqp2u"
			      );
	if ($dbh) {
	  $status = 1;
	}
      } else {
	my $jobcache_db = "JobDB";
	my $jobcache_host = "kursk-3.mcs.anl.gov";
	my $jobcache_user = "mgrast";
	my $jobcache_password = "";
	
	my $mysql_client_key = "/mcs/bio/app-users/mgrastprod/.mysql/client-key.pem";
	my $mysql_client_cert = "/mcs/bio/app-users/mgrastprod/.mysql/client-cert.pem";
	my $mysql_ca_file = "/mcs/bio/app-users/mgrastprod/.mysql/ca-cert.pem";
	
	$dbh = DBI->connect("DBI:mysql:database=".$jobcache_db.";host=".$jobcache_host.";",
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

    $obj->{service} = $id;
    $obj->{status} = $status;
    $obj->{url} = $self->cgi->url."/".$self->name."/".$id;
    
    # check the status service
    $self->return_data($data, undef, 1);
}

1;
