package Auth;

use JSON;
use CGI;

sub authenticate {
  my ($key) = @_;

  # check if we can connect to the user database
  use WebApplicationDBHandle;
  my ($master, $error) = WebApplicationDBHandle->new();
  if ($error) {
    return (undef, "authentication database offline");
  }

  # default values
  my $user = undef;
  my $auth_source = 'WebServicesKey';
  my $auth_value = $key;

  # this is KBase
  if ($key =~ /globusonline/ || $key =~ /^kbgo4711/) {
    my $json = new JSON;
    my $cgi = new CGI;

    $auth_source = 'kbase_user';
    my $ustruct = "";
    
    # this is a key, not a token, obtain a token
    if ($key =~ /^kbgo4711/) {
      $key =~ s/^kbgo4711//;
      $ustruct = globus_token($key);
      if ($ustruct) {
	if ($ustruct->{access_token}) {
	  print $cgi->header(-type => 'application/json',
			     -status => 200,
			     -Access_Control_Allow_Origin => '*' );
	  print '{ "token": "'.$ustruct->{access_token}.'" }';
	  exit;
	} else {
	  return (undef, "invalid globus online credentials");
	}
      } else {
          return (undef, "could not reach globus online auth server");
      }
    }

    # validate the token
    my $validation_url = 'https://nexus.api.globusonline.org/goauth/keys/';    

    # token syntax check
    my ($user, $sig) = $key =~ /^un=([^\|]+)\|.+SigningSubject=([^\|]+)/;
    unless ($user && $sig) {
      return (undef, "error parsing globus online credentials");
    }
    $sig =~ s/^.*\/([abcdef0123456789-]+)$/$1/;

    # perform validation
    my $result = `curl -s -X GET "$validation_url$sig"`;
    eval {
      $ustruct = $json->decode($result);
    };
    if ($@) {
      return (undef, "could not reach globus online auth server");
    } else {

      # check if we have a valid token
      if ($ustruct->{valid}) {

	# set the auth value to the detected user
	$auth_value = $user;
	
	# check if we have a webkey to connect the token to
	if ($cgi->param('webkey')) {

	  # check if the webkey is valid
	  my $pref = $master->Preferences->get_objects( { name => 'WebServicesKey', value => $cgi->param('webkey') } );
	  if (scalar(@$pref)) {
	    my $u = $pref->[0]->user;
	    $pref = $master->Preferences->get_objects( { name => 'WebServiceKeyTdate', user => $u } );
	    if (scalar(@$pref) && $pref->[0]->value > time) {

	      # check if the accounts are already connected
	      my $existing = $master->Preferences->get_objects( { name => 'kbase_user', user => $u } );
	      if (scalar(@$existing)) {

		# we already have a connection, just in case the kbase username has changed, update the setting
		$existing->[0]->value($user);
	      } else {
		
		# create a connection between kbase user and mg-rast user
		$master->Preferences->create( { name => 'kbase_user', user => $u, value => $user } );
	      }
	    } else {
	      return (undef, "webkey expired");
	    }
	  } else {
	    return (undef, "invalid webkey");
	  }
	} else {
	  # check if a connection exists
	  my $pref = $master->Preferences->get_objects( { name => 'kbase_user', value => $user } );
	  if (! scalar(@$pref)) {
	    return (undef, "valid kbase user");
	  }
	}
      } else {
	return (undef, "globus authentication did not validate");
      }
    }
  }
    
  # check for the preference setting for the defined authentication source and value
  my $preference = $master->Preferences->get_objects( { name => $auth_source, value => $auth_value } );
  if (scalar(@$preference)) {

    # check if this is a webkey, then we need to test if it is still valid
    if ($auth_source eq "WebServicesKey") {
      my $u = $preference->[0]->user;
      $preference = $master->Preferences->get_objects( { name => 'WebServiceKeyTdate', user => $u } );
      if (scalar(@$preference) && $preference->[0]->value > time) {
	$user = $preference->[0]->user;
	return ($user);
      } else {
	return (undef, "webkey expired");
      }
    } else {

      # return the user connected to the preference
      $user = $preference->[0]->user;
      return ($user);
    }
  } else {
    # there is no preference, maybe this is a session cookie?
    my $sessions = $master->UserSession->get_objects({ 'session_id' => $auth_value });
    if (scalar(@$sessions)) {
      $user = $sessions->[0]->user;
      return ($user);
    }

    # all checks failed, the authentication is invalid
    return (undef, "invalid webkey"); 
  }
}

sub globus_token {
    my ($key) = @_;
    my $token = undef;
    my $json = new JSON;
    my $pre = `curl -s -H "Authorization: Basic $key" -X POST "https://nexus.api.globusonline.org/goauth/token?grant_type=client_credentials"`;
    eval {
	    $token = $json->decode($pre);
    };
    if ($@) {
        print STDERR "could not reach auth server: $@\n";
        return undef;
    } else {
        return $token;
    }
}

sub globus_info {
    my ($token) = @_;
    if (! $token) {
        return undef;
    }
    my $info = undef;
    if ($token =~ /^un=(\w+)?\|/) {
        my $name = $1;
        my $json = new JSON;
        my $pre = `curl -s -H "Authorization: Globus-Goauthtoken $token" -X GET "https://nexus.api.globusonline.org/users/$name"`;
        eval {
            $info = $json->decode($pre);
        };
        if ($@) {
            print STDERR "could not reach auth server: $@\n";
            return undef;
        } else {
            return $info;
        }
    } else {
        print STDERR "invalid token format\n";
        return undef;
    }
}

1;
