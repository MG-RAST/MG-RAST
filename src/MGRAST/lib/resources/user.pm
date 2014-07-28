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
    $self->{attributes} = { "id"         => [ 'string', 'user id' ],
			    "login"      => [ 'string', 'user login'],
                            "email"      => [ 'string', 'user e-mail' ],
                            "firstname"  => [ 'string', 'first name of user' ],
                            "lastname"   => [ 'string', 'last name of user' ],
                            "entry_date" => [ 'date', 'date of user creation' ],
                            "active"     => [ 'boolean', 'user is active' ],
                            "comment"    => [ 'string', 'any comment about the user account' ],
                            "url"        => [ 'uri', 'resource location of this object instance' ]
                          };

    $self->{cv} = { verbosity => {'minimal' => 1, 'preferences' => 1, 'rights' => 1, 'scopes' => 1, 'full' => 1, 'session' => 1},
                    direction => {'asc' => 1, 'desc' => 1},
                    match => {'any' => 1, 'all' => 1}
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
                    			                         "info for user 'johndoe'" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'     => $self->attributes,
                                                         'required'    => { "id" => [ "string", "unique user login or ID" ] },
                                                         'body'        => {} } },
				    { 'name'        => "delete",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Delete a user object.",
                                      'example'     => [ 'curl -X DELETE -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'/johndoe"',
                    			                         "error or success message" ],
                                      'method'      => "DELETE",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => {},
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => { "id" => [ "string", "unique user login or ID" ] },
                                                         'body'        => {} } },
				    { 'name'        => "update",
                                      'request'     => $self->cgi->url."/".$self->name."/{ID}",
                                      'description' => "Returns a single user object.",
                                      'example'     => [ 'curl -X PUT -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'/johndoe?firstname=Jim"',
							 "set firstname of user 'johndoe' to 'Jim'" ],
                                      'method'      => "PUT",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => $self->attributes,
                                      'parameters'  => { 'options'     => {},
                                                         'required'    => { "id" => [ "string", "unique user login or ID" ] },
                                                         'body'        => {} } },
				    { 'name'        => "query",
                                      'request'     => $self->cgi->url."/".$self->name,
                                      'description' => "Returns a matching list of user objects.",
                                      'example'     => [ 'curl -X GET -H "auth: admin_auth_key" "'.$self->cgi->url."/".$self->name.'?lastname=Doe&firstname=John"',
							 "info for users with firstname 'John' and lastname 'Doe'" ],
                                      'method'      => "GET",
                                      'type'        => "synchronous" ,  
                                      'attributes'  => { "next"    => ["uri","link to the previous set or null if this is the first set"],
							 "prev"    => ["uri","link to the next set or null if this is the last set"],
							 "order"   => ["string","name of the attribute the returned data is ordered by"],
							 "data"    => ["list", ["object", [$self->{attributes}, "user object"] ]],
							 "limit"   => ["integer","maximum number of data items returned, default is 10"],
							 "offset"  => ["integer","zero based index of the first returned data item"],
							 "version" => ['integer', 'version of the object'],
							 "url"     => ['uri', 'resource location of this object instance'],
							 "total_count" => ["integer","total number of available data items"] },
                                      'parameters'  => { 'options' =>
							 { "id"         => [ 'string', 'search term for user id' ],
							   "login"      => [ 'string', 'search term for user login'],
							   "email"      => [ 'string', 'search term for user e-mail' ],
							   "firstname"  => [ 'string', 'search term for first name of user' ],
							   "lastname"   => [ 'string', 'search term for last name of user' ],
							   "entry_date" => [ 'date', 'search term for date of user creation' ],
							   "active"     => [ 'boolean', 'search term for user is active' ],
							   "comment"    => [ 'string', 'search term for any comment about the user account' ],
							   'limit'     => ["integer", "maximum number of items requested"],
							   'offset'    => ["integer", "zero based index of the first data object to be returned"],
							   'order'     => ["string", "metagenome object field to sort by (default is id)"],
							   'direction' => ['cv', [['asc','sort by ascending order'],
										  ['desc','sort by descending order']]],
							   'match' => ['cv', [['all','return metagenomes that match all search parameters'],
									      ['any','return metagenomes that match any search parameters']]],
							   'status' => ['cv', [['both','returns all data (public and private) user has access to view'],
									       ['public','returns all public data'],
									       ['private','returns private data user has access to view']]],
							   'verbosity' => ['cv', [['minimal','returns only minimal information'],
										  ['preferences','returns minimal with preferences'],
										  ['scopes','returns minimal with scopes'],
										  ['rights','returns minimal with rights'],
										  ['full','returns minimal with preferences, scopes and rights']] ] },
                                                         'required'    => {},
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
  unless ($rest && scalar(@$rest)) {
    $self->return_data( {"ERROR" => "invalid id format"}, 400 );
  }
  
  # check verbosity
  my $verb = $self->cgi->param('verbosity') || 'minimal';
  unless (exists $self->{cv}{verbosity}{$verb}) {
    $self->return_data({"ERROR" => "Invalid verbosity entered ($verb)."}, 404);
  }
  
  # get database
  my ($master, $error) = WebApplicationDBHandle->new();
  if ($error) {
    $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 503 );
  }

  # check if this is a reset password request
  if (scalar(@$rest) == 1 && $rest->[0] eq 'resetpassword') {
    # passwords may only be reset with a valid recaptcha
    my $ua = $self->{agent};
    $ua->env_proxy();
    my $resp = $ua->post( 'http://www.google.com/recaptcha/api/verify', { privatekey => '6Lf1FL4SAAAAAIJLRoCYjkEgie7RIvfV9hQGnAOh',
									  remoteip   => $ENV{'REMOTE_ADDR'},
									  challenge  => $self->{cgi}->param('challenge'),
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
    # now check if the login and email address correspond
    my $user = $master->User->get_objects( { login => $self->{cgi}->param('login'), email => $self->{cgi}->param('email') } );
    if ($user && scalar(@$user)) {
      $user = $user->[0];
      &set_password($user, &generate_password(), 1);
      $self->return_data( {"OK" => "password reset"}, 200 );

    } else {
      $self->return_data( {"ERROR" => "login and email do not match or are not registered"}, 400 );
    }
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
    $self->return_data( {"ERROR" => "user '".$rest->[0]."' does not exist"}, 404 );
  }
  $user = $user->[0];
  
  # check rights
  unless ($self->user && ($self->user->has_right(undef, 'edit', 'user', $user->{_id}) || $self->user->has_star_right('edit', 'user'))) {
    $self->return_data( {"ERROR" => "insufficient permissions for user call"}, 401 );
  }
  
  # check if this is a user update
  if ($self->{method} eq 'PUT') {
    if (defined $self->{cgi}->param('email')) {
      $user->email(uri_unescape($self->{cgi}->param('email')));
    }
    if (defined $self->{cgi}->param('firstname')) {
      $user->firstname(uri_unescape($self->{cgi}->param('firstname')));
    }
    if (defined $self->{cgi}->param('lastname')) {
      $user->lastname(uri_unescape($self->{cgi}->param('lastname')));
    }
    if (defined $self->{cgi}->param('active')) {
      $user->active(uri_unescape($self->{cgi}->param('active')));
    }
    if (defined $self->{cgi}->param('comment')) {
      $user->comment(uri_unescape($self->{cgi}->param('comment')));
    }
  }

  # check if this is a user deletion
  if ($self->{method} eq 'DELETE') {
    eval {
      $user->delete();
    };
    if ($@) {
      $self->return_data( { "ERROR" => $@ }, 500 );
    } else {
      $self->return_data( {"OK" => "user deleted"}, 200 );
    }
  }
  
  # check if this is an action request
  my $requests = { 'setpassword' => 1,
		   'webkey' => 1 };
  if (scalar(@$rest) > 1 && $requests->{$rest->[1]}) {
    # set password
    if ($rest->[1] eq 'setpassword') {
      if ($self->cgi->param('dwp')) {
	&set_password($user, $self->cgi->param('dwp'));
	$self->return_data( {"OK" => "password set"}, 200 );
      } else {
	$self->return_data( { "ERROR" => "no password passed to set" }, 400 );
      }
    }
    # webkey
    if ($rest->[1] eq 'webkey') {
      if (! $rest->[2]) {
	$self->return_data( {"ERROR" => "webkey request requires action parameter"}, 400 );
      }

      my $timeout = 60 * 60 * 24 * 7; # one week  
      my $webkey = { "key" => 0,
		     "date" => 0,
		     "valid" => 0 };
      
      my $existing_key = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
      my $existing_date = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );

      # refresh webkey
      if ($rest->[2] eq "refresh") {
	if (scalar(@$existing_date)) {
	  my $tdate = time + $timeout;
	  $existing_date->[0]->value($tdate);
	  $webkey->{key} = $existing_key->[0]->{value};
	  $webkey->{date} = $existing_date->[0]->value();
	  if ($webkey->{date} > time) {
	    $webkey->{valid} = 1;
	  }
	  $self->return_data( $webkey, 200 );
	} else {
	  $self->return_data( {"ERROR" => "there is no webkey to refresh"}, 400 );
	}	
      }
      # create new
      elsif ($rest->[2] eq "create") {
	my $generated = "";
	my $possible = 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
	while (length($generated) < 25) {
	  $generated .= substr($possible, (int(rand(length($possible)))), 1);
	}
	my $preference = $master->Preferences->get_objects( { value => $generated } );
	
	while (scalar(@$preference)) {
	  $generated = "";
	  while (length($generated) < 25) {
	    $generated .= substr($possible, (int(rand(length($possible)))), 1);
	  }
	  $preference = $master->Preferences->get_objects( { value => $generated } );
	}
	my $tdate = time + $timeout;
	
	my $pref = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
	if (scalar(@$pref)) {
	  $pref = $pref->[0];
	} else {
	  $pref = $master->Preferences->create( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
	}
	$pref->value($tdate);
	
	$pref = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
	if (scalar(@$pref)) {
	  $pref = $pref->[0];
	} else {
	  $pref = $master->Preferences->create( { 'user' => $user, 'name' => 'WebServicesKey' } );
	}
	$pref->value($generated);
	$webkey->{key} = $generated;
	$webkey->{date} = $tdate;
	$webkey->{valid} = 1;
	$self->return_data( $webkey, 200 );
      }
      # invalidate
      elsif ($rest->[2] eq "invalidate") {
	if (scalar(@$existing_key)) {
	  foreach my $key (@$existing_key) {
	    $key->delete();
	  }
	  foreach my $key (@$existing_date) {
	    $key->delete();
	  }
	  $self->return_data( {"OK" => "webkey invalidated"}, 200 );
	} else {
	  $self->return_data( {"ERROR" => "there is no webkey to invalidate"}, 400 );
	}
      }
    }
  }
  
  # get the user preferences
  if ($verb eq 'preferences') {
    my $prefs = $master->Preferences->get_objects({ user => $user });
    $user->{preferences} = [];
    @{$user->{preferences}} = map { { name => $_->{name}, value => $_->{value} } } @$prefs;
  }
  # get the users rights
  elsif ($verb eq 'rights') {
    my $rights = $user->rights();
    $user->{rights} = [];
    @{$user->{rights}} = map {
      { name => $_->{name},
	  data_type => $_->{data_type},
	    data_id => $_->{data_id},
	      granted => $_->{granted},
		delegated => $_->{delegated} }
    } @$rights;
  }
  # get the users scopes
  elsif ($verb eq 'scopes') {
    my $scopes = $user->scopes();
    $user->{scopes} = [];
    @{$user->{scopes}} = map { { name => $_->{name},
				     description => $_->{description} } } @$scopes;
  }
  # get all data 
  elsif ($verb eq 'full') {
    my $prefs = $master->Preferences->get_objects({ user => $user });
    $user->{preferences} = [];
    @{$user->{preferences}} = map { { name => $_->{name}, value => $_->{value} } } @$prefs;
    my $rights = $user->rights();
    $user->{rights} = [];
    @{$user->{rights}} = map { { name => $_->{name},
				   data_type => $_->{data_type},
				     data_id => $_->{data_id},
				       granted => $_->{granted},
					 delegated => $_->{delegated} } } @$rights;
    my $scopes = $user->scopes();
    $user->{scopes} = [];
    @{$user->{scopes}} = map { { name => $_->{name},
				   description => $_->{description} } } @$scopes;
    $user->{session} = {};
    my $usession = $master->UserSession->get_objects( { user => $user } );
    if (ref($usession) eq 'ARRAY' and scalar(@$usession)) {
      $usession = $usession->[0];
      $user->{session} = { error_page => $usession->{error_page},
			   session_id => $usession->{session_id},
			   error_parameters => $usession->{error_parameters},
			   current_page => $usession->{current_page},
			   timestamp => $usession->{timestamp},
			   previous_page => $usession->{previous_page},
			   current_parameters => $usession->{current_parameters},
			   previous_parameters => $usession->{previous_parameters} };
    }
    $user->{organization} = {};
    my $uho = $master->OrganizationUsers->get_objects( { user => $user } );
    if (ref($uho) eq 'ARRAY' and scalar(@$uho)) {
      my $org = $uho->[0]->organization;
      $user->{organization} = { country => $org->{country},
				city => $org->{city},
				date => $org->{date},
				url => $org->{url},
				name => $org->{name},
				abbreviation => $org->{abbreviation},
				location => $org->{location} };
    }
  }
  
  # prepare data
  my $data = $self->prepare_data($user);
  $self->return_data($data);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my ($master, $error) = WebApplicationDBHandle->new();
    if ($error) {
        $self->return_data( {"ERROR" => "could not connect to user database - $error"}, 503 );
    }
    
    # get paramaters
    my $verb   = $self->cgi->param('verbosity') || 'minimal';
    my $limit  = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order') || "lastname";
    my $dir    = $self->cgi->param('direction') || 'asc';
    my $match  = $self->cgi->param('match') || 'all';
    
    # check CV
    unless (exists $self->{cv}{verbosity}{$verb}) {
        $self->return_data({"ERROR" => "Invalid verbosity entered ($verb)."}, 404);
    }
    unless (exists $self->{cv}{direction}{$dir}) {
        $self->return_data({"ERROR" => "Invalid direction entered ($dir) for query."}, 404);
    }
    unless (exists $self->{cv}{match}{$match}) {
        $self->return_data({"ERROR" => "Invalid match entered ($match) for query."}, 404);
    }
    unless (exists $self->{attributes}{$order}) {
        $self->return_data({"ERROR" => "Invalid order entered ($order) for query."}, 404);
    }
    if (($limit > 10000) || ($limit < 1)) {
        $self->return_data({"ERROR" => "Limit must be less than 10,000 and greater than 0 ($limit) for query."}, 404);
    }

    # explicitly setting the default CGI parameters for returned url strings
    $self->cgi->param('verbosity', $verb);
    $self->cgi->param('limit', $limit);
    $self->cgi->param('offset', $offset);
    $self->cgi->param('order', $order);
    $self->cgi->param('direction', $dir);
    $self->cgi->param('match', $match);

    # check rights
    unless ($self->user && ($self->user->has_star_right('edit', 'user'))) {
        $self->return_data( {"ERROR" => "insufficient permissions for user query"}, 401 );
    }

    # create the WHERE clause
    my $where = [];
    
    # iterate over the attributes
    foreach my $key (keys(%{$self->{attributes}})) {

      # check if there is a value for the attribute
      if (defined $self->cgi->param($key)) {
	
	# check what operator
	my $val = uri_unescape($self->cgi->param($key));
	
	my $str = $key;
	
	# like
	if ($val =~ /\*/) {
	  $val =~ s/\*/\%/g;
	  # not like
	  if ($val =~ /^\!/) {
	    $val =~ s/^\!//;
	    $str .= " NOT ";
	  }
	  $str .= " LIKE ";
	}
	# inclusive range
	elsif ($val =~ /^\[(.+)\;(.+)\]$/) {
	  my $a = $1;
	  my $b = $2;
	  $str .= ">= ".$master->backend->quote($a)." AND $key<=".$master->backend->quote($b);
	  push(@$where, $str);
	  next;
	}
	# exclusive range
	elsif ($val =~ /^\](.+)\;(.+)\[$/) {
	  my $a = $1;
	  my $b = $2;
	  $str .= "> ".$master->backend->quote($a)." AND $key<".$master->backend->quote($b);
	  push(@$where, $str);
	  next;
	}
	# mixed range
	elsif ($val =~ /^\](.+)\;(.+)\]$/) {
	  my $a = $1;
	  my $b = $2;
	  $str .= "> ".$master->backend->quote($a)." AND $key<=".$master->backend->quote($b);
	  push(@$where, $str);
	  next;
	}
	# mixed range
	elsif ($val =~ /^\[(.+)\;(.+)\[$/) {
	  my $a = $1;
	  my $b = $2;
	  $str .= ">=".$master->backend->quote($a)." AND $key<".$master->backend->quote($b);
	  push(@$where, $str);
	  next;
	}
	# greater than or equal to
	elsif ($val =~ /^\[(.+)$/) {
	  $val = $1;
	  $str .= ">=";
	}
	# greater than
	elsif ($val =~ /^\](.+)$/) {
	  $val = $1;
	  $str .= ">";
	}
	# less than
	elsif ($val =~ /^(.+)\[$/) {
	  $val = $1;
	  $str .= "<";
	}
	# less than or equal to
	elsif ($val =~ /^(.+)\]$/) {
	  $val = $1;
	  $str .= "<=";
	}
	
	# not equal
	elsif ($val =~ /^\!/) {
	  $val =~ s/^\!//;
	  $str .= "!=";
	}
	# equal
	else {
	  $str .= "=";
	}
	$str .= $master->backend->quote($val);
	push(@$where, $str);
      }
    }
    my $where_string2 = join(" AND ", @$where);
    my $where_string = "";
    if (scalar(@$where)) {
      $where_string = "WHERE ".join(" AND ", @$where);
    }

    my $data = [];
    my $total = $master->backend->get_rows('User', ["COUNT(*)"], $where_string2, {})->[0]->[0];
    # get only basic data
    if ($verb eq 'minimal') {
      $data = $master->backend->get_rows('User', [], $where_string2, { "sort_by" => [ "$order $dir LIMIT $limit OFFSET $offset" ], "row_as_hash" => 1 });
    }
    # get the user preferences
    elsif ($verb eq 'preferences') {
      my $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN Preferences ON t1._id=Preferences.user ORDER BY t1.$order ".uc($dir), [], undef, {});
      my $uhash = {};
      my $order_array = [];
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 value 10 user 11 _user_db 12 application 13 _application_db 14 name 15 
	if (! defined $uhash->{$row->[8]}) {
	  push(@$order_array, $row->[8]);
	  $uhash->{$row->[8]} = { _id => $row->[0],
				  login => $row->[8],
				  email => $row->[2],
				  firstname => $row->[1],
				  lastname => $row->[7],
				  entry_date => $row->[5],
				  active => $row->[6],
				  comment => $row->[4],
				  preferences => [] };
	}
	push(@{$uhash->{$row->[8]}->{preferences}}, { name => $row->[15], value => $row->[10] });
      }
      foreach my $key (@$order_array) {
	push(@$data, $uhash->{$key});
      }
    }
    # get the users rights
    elsif ($verb eq 'rights') {
      my $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN UserHasScope ON t1._id=UserHasScope.user JOIN Scope on Scope._id=UserHasScope.scope JOIN Rights ON Scope._id=Rights.scope ORDER BY t1.$order ".uc($dir), [], undef, {});
      my $uhash = {};
      my $order_array = [];
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 user 10 _user_db 11 scope 12 _scope_db 13 granted 14 _id 15 application 16 _application_db 17 name 18 description 19 _id 20 granted 21 delegated 22 data_id 23 data_type 24 application 25 _application_db 26 name 27 scope 28 _scope_db 29
	if (! defined $uhash->{$row->[8]}) {
	  push(@$order_array, $row->[8]);
	  $uhash->{$row->[8]} = { _id => $row->[0],
				  login => $row->[8],
				  email => $row->[2],
				  firstname => $row->[1],
				  lastname => $row->[7],
				  entry_date => $row->[5],
				  active => $row->[6],
				  comment => $row->[4],
				  rights => [] };
	}
	push(@{$uhash->{$row->[8]}->{rights}}, { name => $row->[27],
						 data_type => $row->[24],
						 data_id => $row->[23],
						 granted => $row->[21],
						 delegated => $row->[22] });
      }
      foreach my $key (@$order_array) {
	push(@$data, $uhash->{$key});
      }
    }
    # get the users scopes
    elsif ($verb eq 'scopes') {
      my $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN UserHasScope ON t1._id=UserHasScope.user JOIN Scope on Scope._id=UserHasScope.scope ORDER BY $order ".uc($dir), [], undef, {});
      my $uhash = {};
      my $order_array = [];
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 user 10 _user_db 11 scope 12 _scope_db 13 granted 14 _id 15 application 16 _application_db 17 name 18 description 19
	if (! defined $uhash->{$row->[8]}) {
	  push(@$order_array, $row->[8]);
	  $uhash->{$row->[8]} = { _id => $row->[0],
				  login => $row->[8],
				  email => $row->[2],
				  firstname => $row->[1],
				  lastname => $row->[7],
				  entry_date => $row->[5],
				  active => $row->[6],
				  comment => $row->[4],
				  scopes => [] };
	}
	push(@{$uhash->{$row->[8]}->{scopes}}, { name => $row->[18], description => $row->[19] } );
      }
      foreach my $key (@$order_array) {
	push(@$data, $uhash->{$key});
      }
    }
    # get session statistics
    elsif ($verb eq 'session') {
      
    }
    # get everything
    else {
      #  _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 user 10 _user_db 11 scope 12 _scope_db 13 granted 14 _id 15 application 16 _application_db 17 name 18 description 19 _id 20 granted 21 delegated 22 data_id 23 data_type 24 application 25 _application_db 26 name 27 scope 28 _scope_db 29
      my $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN UserHasScope ON t1._id=UserHasScope.user JOIN Scope on Scope._id=UserHasScope.scope JOIN Rights ON Scope._id=Rights.scope ORDER BY $order ".uc($dir), [], undef, {});
      my $uhash = {};
      my $order_array = [];
      foreach my $row (@$rows) {
	if (! defined $uhash->{$row->[8]}) {
	  push(@$order_array, $row->[8]);
	  $uhash->{$row->[8]} = { _id => $row->[0],
				  login => $row->[8],
				  email => $row->[2],
				  firstname => $row->[1],
				  lastname => $row->[7],
				  entry_date => $row->[5],
				  active => $row->[6],
				  comment => $row->[4],
				  rights => [],
				  scopes => {},
				  preferences => [],
				  organization => {},
				  session => {} };
	}
	push(@{$uhash->{$row->[8]}->{rights}}, { name => $row->[27],
						 data_type => $row->[24],
						 data_id => $row->[23],
						 granted => $row->[21],
						 delegated => $row->[22] });
	$uhash->{$row->[8]}->{scopes}->{$row->[12]} = { name => $row->[18], description => $row->[19] };
      }
      $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN Preferences ON t1._id=Preferences.user ORDER BY t1.$order ".uc($dir), [], undef, {});
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 value 10 user 11 _user_db 12 application 13 _application_db 14 name 15 
	
	push(@{$uhash->{$row->[8]}->{preferences}}, { name => $row->[15], value => $row->[10] });
      }
      $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN UserSession ON t1._id=UserSession.user ORDER BY t1.$order ".uc($dir), [], undef, {});
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 error_page 10 session_id 11 error_parameters 12 current_page 13 timestamp 14 previous_page 15 user 16 _user_db 17 current_parameters 18 previous_parameters 19 
	
	$uhash->{$row->[8]}->{session} = { error_page => $row->[10],
					   session_id => $row->[11],
					   error_parameters => $row->[12],
					   current_page => $row->[13],
					   timestamp => $row->[14],
					   previous_page => $row->[15],
					   current_parameters => $row->[18],
					   previous_parameters => $row->[19] };
      }
      $rows = $master->backend->get_rows( "(SELECT * FROM User $where_string ORDER BY $order ".uc($dir)." LIMIT $limit OFFSET $offset) AS t1 JOIN OrganizationUsers ON t1._id=OrganizationUsers.user JOIN Organization ON OrganizationUsers.organization=Organization._id ORDER BY t1.$order ".uc($dir), [], undef, {});
      foreach my $row (@$rows) {
	# _id 0 firstname 1 email 2 password 3 comment 4 entry_date 5 active 6 lastname 7 login 8 _id 9 user 10 _user_db 11 organization 12 _organization_db 13 _id 14 country 15 city 16 date 17 url 18 name 19 abbreviation 20 scope 21 _scope_db 22 loaction 23
	
	$uhash->{$row->[8]}->{organization} = { country => $row->[15],
						city => $row->[16],
						date => $row->[17],
						url => $row->[18],
						name => $row->[19],
						abbreviation => $row->[20],
						location => $row->[23] };
      }
      foreach my $key (@$order_array) {
	my $s = [];
	foreach my $sc (keys(%{$uhash->{$key}->{scopes}})) {
	  push(@$s, $uhash->{$key}->{scopes}->{$sc});
	}
	$uhash->{$key}->{scopes} = $s;
	push(@$data, $uhash->{$key});
      }
    }

    # prepare the userdata
    my $obj = $self->check_pagination($data, $total, $limit);
    $obj->{version} = 1;

    $obj->{data} = $self->prepare_data($data);

    $self->return_data($obj);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $user) = @_;

    my $url = $self->cgi->url;

    my $result = [];
    my $islist = 1;
    if (ref($user) ne "ARRAY") {
      $user = [ $user ];
      $islist = 0;
    }

    foreach my $u (@$user) {
      my $obj = {};
      $obj->{id}         = 'mgu'.$u->{_id};
      $obj->{login}      = $u->{login};
      $obj->{email}      = $u->{email};
      $obj->{firstname}  = $u->{firstname};
      $obj->{lastname}   = $u->{lastname};
      $obj->{entry_date} = $u->{entry_date};
      $obj->{active}     = $u->{active};
      $obj->{comment}    = $u->{comment};
      $obj->{url}        = $self->cgi->url.'/'.$self->{name}.'/'.$obj->{id};

      if (defined $u->{preferences}) { $obj->{preferences} = $u->{preferences} };
      if (defined $u->{rights}) { $obj->{rights} = $u->{rights} };
      if (defined $u->{scopes}) { $obj->{scopes} = $u->{scopes} };
      if (defined $u->{session}) { $obj->{session} = $u->{session} };
      if (defined $u->{organization}) { $obj->{organization} = $u->{organization} };
      
      push(@$result, $obj);
    }

    return $islist ? $result : $result->[0];
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
  unless (uri_unescape($cgi->param('email')) =~ /[\d\w\.\'-]+\@[\d\w\.-]+\.[\w+]/) {
    $self->return_data( {"ERROR" => "email address invalid"}, 400 );
  }

  # check login
  unless ($cgi->param('login')) {
    $self->return_data( {"ERROR" => "no login passed"}, 400 );
  }

  # check if the login is valid
  unless (uri_unescape($cgi->param('login')) =~ /^[\d\w]+$/) {
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
  my $user_by_login = $master->User->init( { login => uri_unescape($cgi->param('login')) } );
  if (ref($user_by_login)) {
    $self->return_data( {"ERROR" => "login already taken"}, 400 );
  }
  else {
    
    # check email 
    my $user_by_email = $master->User->init( { email => uri_unescape($cgi->param('email')) } );
    if (ref($user_by_email)) {
      $self->return_data( {"ERROR" => "email already taken"}, 400 );  
    }
  }

  # check if scope exists
  if ($master->Scope->init( { application => undef,
			      name => uri_unescape($cgi->param('login')) } )) {
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
  $user = $master->User->create( { email      => uri_unescape($cgi->param('email')),
				   firstname  => uri_unescape($cgi->param('firstname')),
				   lastname   => uri_unescape($cgi->param('lastname')),
				   login      => uri_unescape($cgi->param('login')) } );
  
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
    $user_org = $hs->parse(uri_unescape($cgi->param('organization')));
  }

  if ($cgi->param('lru')) {
    my $hs = HTML::Strip->new();
    $url = $hs->parse(uri_unescape($cgi->param('lru')));
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
    my $country = $hs->parse( uri_unescape($cgi->param('country')) );
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
  $ubody->param('FIRSTNAME', $user->{firstname});
  $ubody->param('LASTNAME', $user->{lastname});
  $ubody->param('LOGIN', $user->{login});
  $ubody->param('EMAIL_USER', $user->{email});
  $ubody->param('APPLICATION_NAME', "MG-RAST");
  $ubody->param('APPLICATION_URL', "http://metagenomics.anl.gov");
  $ubody->param('EMAIL_ADMIN', "mg-rast\@mcs.anl.gov");
  
  $user->send_email( "mg-rast\@mcs.anl.gov",
		     'MG-RAST - new account requested',
		     $ubody->output
		   );
  
  return $user;
}

sub set_password {
  my ($user, $password, $reset) = @_;

  my $new_password = &encrypt($password);
  $user->password($new_password);

  if ($reset) {
    my $body = HTML::Template->new(filename => '../../src/WebApplication/templates/EmailNewPassword.tmpl',
				   die_on_bad_params => 0);
    $body->param('LOGIN', $user->{login});
    $body->param('NEWPASSWORD', $password);
    $body->param('APPLICATION_NAME', "MG-RAST");
    $body->param('APPLICATION_URL', "http://metagenomics.anl.gov");
    $body->param('EMAIL_ADMIN', "mg-rast\@mcs.anl.gov");
    
    $user->send_email( "mg-rast\@mcs.anl.gov",
		       'MG-RAST - new password requested',
		       $body->output,
		     );
  }
}

sub generate_password {
  return join '', (0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64, rand 64, rand 64, rand 64, rand 64, rand 64, rand 64];
}

sub encrypt {
  my ($password) = @_;

  my $seed = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
  return crypt($password, $seed);
}

1;
