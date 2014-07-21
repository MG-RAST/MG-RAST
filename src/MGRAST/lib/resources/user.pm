package resources::user;

use strict;
use warnings;
no warnings('once');

use Conf;
use Data::Dumper;
use parent qw(resources::resource);
use WebApplicationDBHandle;
use URI::Escape;

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "user";
    $self->{attributes} = { "id"         => [ 'string', 'user login' ],
                            "email"      => [ 'string', 'user e-mail' ],
                            "firstname"  => [ 'string', 'first name of user' ],
                            "lastname"   => [ 'string', 'last name of user' ],
                            "entry_date" => [ 'date', 'date of user creation' ],
                            "active"     => [ 'boolean', 'user is active' ],
                            "comment"    => [ 'string', 'any comment about the user account' ],
                            "url"        => [ 'uri', 'resource location of this object instance' ]
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
                    'url' => $self->cgi->url."/".$self->name,
                    'description' => "The user resource returns information about a user.",
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
                                    { 'name'        => "instance",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Returns a single user object.",
                                      'example'     => [ 'curl -X GET -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'/johndoe"',
                    			                         "info for user 'joeblow'" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => { "id" => [ "string", "unique user login or ID" ] },
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
    unless ($rest && scalar(@$rest) == 1) {
        $self->return_data( {"ERROR" => "invalid id format"}, 400 );
    }

    # get database
    my ($master, $error) = WebApplicationDBHandle->new();
    if ($error) {
        $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 503 );
    }

    # check if this is a user creation
    if ($self->{method} eq 'POST') {
      # users may only be created with a valid recaptcha
      my $ua = $self->{agent};
      $ua->env_proxy();
      my $resp = $ua->post( 'http://www.google.com/recaptcha/api/verify', { privatekey => '6Lf1FL4SAAAAAIJLRoCYjkEgie7RIvfV9hQGnAOh',
									    remoteip   => $ENV{'REMOTE_ADDR'},
									    challenge  => $rest->[0],
									    response   => $self->{cgi}->param('response') }
			  );
      if ( $resp->is_success ) {
	my ( $answer, $message ) = split( /\n/, $resp->content, 2 );
	if ( $answer !~ /true/ ) {
	  $self->return_data( {"ERROR" => "recaptcha failed"}, 400 );
	}
      } else {
	$self->return_data( {"ERROR" => "recaptcha server could not be reached"}, 400 );
      }

      # if we get here, recaptcha is successful
      my $new_user = &create_user($self);
      $self->return_data($self->prepare_data($new_user));
    }
        
    # get data
    my $user = [];
    if ($rest->[0] =~ /^mgu(\d+)$/) { # user id
      $user = $master->User->get_objects( {"_id" => $1} );
    } elsif (uri_unescape($rest->[0]) =~ /\@/) {
      $user = $master->User->get_objects( { "email" => uri_unescape($rest->[0]) } );
    } else { # user login
      $user = $master->User->get_objects( { "login" => $rest->[0] } );
    }
    unless (scalar(@$user)) {
        $self->return_data( {"ERROR" => "user '".$rest->[0]."' does not exists"}, 404 );
    }
    $user = $user->[0];

    # check rights
    unless ($self->user && ($self->user->has_right(undef, 'edit', 'user', $user->{_id}) || $self->user->has_star_right('edit', 'user'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for user call"}, 401 );
    }

    # check if this is a user update
    if ($self->{method} eq 'PUT') {
      if (defined $self->{cgi}->param('email')) {
	$user->email(uri_decode($self->{cgi}->param('email')));
      }
      if (defined $self->{cgi}->param('firstname')) {
	$user->firstname(uri_decode($self->{cgi}->param('firstname')));
      }
      if (defined $self->{cgi}->param('lastname')) {
	$user->lastname(uri_decode($self->{cgi}->param('lastname')));
      }
      if (defined $self->{cgi}->param('active')) {
	$user->active(uri_decode($self->{cgi}->param('active')));
      }
      if (defined $self->{cgi}->param('comment')) {
	$user->comment(uri_decode($self->{cgi}->param('comment')));
      }
    }

    # prepare data
    my $data = $self->prepare_data($user);
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $user) = @_;

    my $url = $self->cgi->url;
    my $obj = {};
    $obj->{id}         = 'mgu'.$user->_id;
    $obj->{login}      = $user->login;
    $obj->{email}      = $user->email;
    $obj->{firstname}  = $user->firstname;
    $obj->{lastname}   = $user->lastname;
    $obj->{entry_date} = $user->entry_date;
    $obj->{active}     = $user->active;
    $obj->{comment}    = $user->comment;
    $obj->{url}        = $self->cgi->url.'/'.$self->{name}.'/'.$obj->{id};

    return $obj;
}

# create a new user
sub create_user {
  my ($self) = @_;

  use HTML::Strip;
  use HTML::Template;

  my $cgi = $self->{cgi};

  # check for an email address
  unless ($cgi->param('email')) {
    $self->return_data( {"ERROR" => "no email address passed"}, 400 );
  }

  # check if email address is valid
  unless ($cgi->param('email') =~ /[\d\w\.\'-]+\@[\d\w\.-]+\.[\w+]/) {
    $self->return_data( {"ERROR" => "email address invalid"}, 400 );
  }

  # check login
  unless ($cgi->param('login')) {
    $self->return_data( {"ERROR" => "no login passed"}, 400 );
  }

  # check if the login is valid
  unless ($cgi->param('login') =~ /^[\d\w]+$/) {
    $self->return_data( {"ERROR" => "login is invalid"}, 400 );
  }

  # check if firstname and lastname are distinct
  if ($cgi->param('firstname') && $cgi->param('lastname')) {
    if ($cgi->param('firstname') eq $cgi->param('lastname')) {
      $self->return_data( {"ERROR" => "first and last name must be distinct"}, 400 );
    }
  }

  my $user;

  # get database
  my ($master, $error) = WebApplicationDBHandle->new();
  
  # check login
  my $user_by_login = $master->User->init( { login => $cgi->param('login') } );
  if (ref($user_by_login)) {
    $self->return_data( {"ERROR" => "login already taken"}, 400 );
  }
  else {
    
    # check email 
    my $user_by_email = $master->User->init( { email => $cgi->param('email') } );
    if (ref($user_by_email)) {
      $self->return_data( {"ERROR" => "email already taken"}, 400 );  
    }
  }

  # check if scope exists
  if ($master->Scope->init( { application => undef,
			      name => $cgi->param('login') } )) {
    $self->return_data( {"ERROR" => "login already taken"}, 400 );
  }
  
  # check first name
  unless ($cgi->param('firstname')) {
    $self->return_data( {"ERROR" => "no firstname passed"}, 400 );
  }
      
  # check last name
  unless ($cgi->param('lastname')) {
    $self->return_data( {"ERROR" => "no lastname passed"}, 400 );
  }

  # create the user in the db
  $user = $master->User->create( { email      => $cgi->param('email'),
				   firstname  => $cgi->param('firstname'),
				   lastname   => $cgi->param('lastname'),
				   login      => $cgi->param('login') } );
  
  # check for success
  unless (ref($user)) {
    $self->return_data( {"ERROR" => "could not create user"}, 500 );
  }
  
  # check for organization information
  my $user_org = "";
  my $org_found = 0;
  my $url = "";

  if ($cgi->param('organization')) {
    my $hs = HTML::Strip->new();
    $user_org = $hs->parse($cgi->param('organization'));
  }

  if ($cgi->param('lru')) {
    my $hs = HTML::Strip->new();
    $url = $hs->parse($cgi->param('lru'));
  }

  if ($user_org) {
      
    # check if we find this organization by name
    my $existing_org = $master->Organization->init( { name => $user_org } );
      
    # check if we have a url to compare
    if ($url) {
      $url =~ s/(.*)\/$/$1/;
      $url = "http://".$url;
      $existing_org = $master->Organization->get_objects( { url => $url } );
      if (scalar($existing_org)) {
	$existing_org = $existing_org->[0];
      }
    }
      
    # check if we found an existing org
    if ($existing_org) {
      $user_org = $existing_org->name();
      unless (scalar(@{$master->OrganizationUsers->get_objects( { organization => $existing_org,
								  user => $user } )})) {
	$master->OrganizationUsers->create( { organization => $existing_org,
					      user => $user } );
      }
      $org_found = 1;
    }
  }

  # prepare admin email
  my $abody = HTML::Template->new(filename => '../../src/WebApplication/templates/EmailReviewNewAccount.tmpl',
				  die_on_bad_params => 0);
  $abody->param('FIRSTNAME', $user->firstname);
  $abody->param('LASTNAME', $user->lastname);
  $abody->param('LOGIN', $user->login);
  $abody->param('EMAIL_USER', $user->email);
  $abody->param('APPLICATION_NAME', "MG-RAST");
  $abody->param('APPLICATION_URL', "http://metagenomics.anl.gov");
  $abody->param('EMAIL_ADMIN', "mg-rast\@mcs.anl.gov");
  $abody->param('URL', $url);
  if ($cgi->param('country')) {
    my $hs = HTML::Strip->new();
    my $country = $hs->parse( $cgi->param('country') );
    $abody->param('COUNTRY', $country);
  }
  if ($user_org) {
    $abody->param('ORGANIZATION', $user_org);
    if ($org_found) {
      $abody->param('ORG_FOUND', "This organization was already present in the database.");
    } else {
      $abody->param('ORG_FOUND', "This organization does not yet exist. Please create it on the Organization page.");
    }
  }
  
  # add registration request (non granted login right)
  $user->add_login_right( $master->Backend->init({ 'name' => "MGRAST" }) );

  # check if user wants to be on the mailinglist
  if ($cgi->param('mailinglist')) {
    $master->Preferences->create( { user => $user,
				    name => 'mailinglist',
				    value => 'mgrast' } );
  }
  
  # send user email
  my $ubody = HTML::Template->new(filename => '../../src/WebApplication/templates/EmailNewAccount.tmpl',
				  die_on_bad_params => 0);
  $ubody->param('FIRSTNAME', $user->firstname);
  $ubody->param('LASTNAME', $user->lastname);
  $ubody->param('LOGIN', $user->login);
  $ubody->param('EMAIL_USER', $user->email);
  $ubody->param('APPLICATION_NAME', "MG-RAST");
  $ubody->param('APPLICATION_URL', "http://metagenomics.anl.gov");
  $ubody->param('EMAIL_ADMIN', "mg-rast\@mcs.anl.gov");
  
  $user->send_email( "mg-rast\@mcs.anl.gov",
		     'MG-RAST - new account requested',
		     $ubody->output
		   );
  
  return $user;
}

1;
