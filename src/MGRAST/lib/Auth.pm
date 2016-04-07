package Auth;

use JSON;
use CGI;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

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

  if ($key =~ /^mggo4711/) {
      $key =~ s/^mggo4711//;
      
      unless ($ENV{'SCRIPT_URI'} =~ /^https/) {
          return (undef, "insecure protocol");
      }

      use MIME::Base64;
      use LWP::UserAgent;
      use Conf;
      my ($u,$p) = split(/\:/, decode_base64($key));
      my $us = $master->User->init( { login => $u } );
      if (ref $us and crypt($p, $us->password) eq $us->password) {
        my $pref = $master->Preferences->get_objects( { name => 'WebServiceKeyTdate', user => $us } );
	unless (scalar(@$pref)) {
	  my $t = time + (60 * 60 * 24 * 7);
	  my $wkey = "";
	  my $possible = 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
	  while (length($wkey) < 25) {
	    $wkey .= substr($possible, (int(rand(length($possible)))), 1);
	  }
	
	  $master->Preferences->create({ user => $us, name => "WebServicesKey", value => $wkey });
	  $pref = [ $master->Preferences->create({ user => $us, name => "WebServiceKeyTdate", value => $t }) ];
	}
	if ($pref->[0]->value < time) {
	  $pref->[0]->value(time + 1209600);
	}
	my $skeytimeout = $pref->[0]->value();
	$pref = $master->Preferences->get_objects( { name => 'WebServicesKey', user => $us } );
	my $cgi = new CGI;
	my $verbose = "";
	if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'verbose') {
	  $verbose = ', "login":"'.$us->{login}.'", "firstname":"'.$us->{firstname}.'", "lastname":"'.$us->{lastname}.'", "email":"'.$us->{email}.'", "id":"mgu'.$us->{_id}.'"';
	  # terms of service
	  my $tos = $master->Preferences->get_objects( { name => 'AgreeTermsOfService', user => $us } );
	  my $agree = 0;
	  foreach my $t (@$tos) {
	    if ($t->{value} > $agree) {
	      $agree = $t->{value};
	    }
	  }
	  $verbose .= ', "tos": "'.$agree.'"';
	  
	  # SHOCK preferences
	  my $prefs = $master->Preferences->get_objects({ user => $us, name => "shock_pref_node" });
	  if (scalar(@$prefs)) {
	    my $nodeid = $prefs->[0]->{value};
	    my $response = undef;
	    my $json = new JSON;
	    $json = $json->utf8();
	    $json->max_size(0);
	    $json->allow_nonref;
	    my $agent = LWP::UserAgent->new;
	    eval {
	      my @args = ('Authorization', "mgrast ".$pref->[0]->{value});
	      my $url = $Conf::shock_url.'/node/'.$nodeid;
	      my $get = $agent->get($url, @args);
	      $response = $json->decode( $get->content );
	    };
	    if ($@ || (! ref($response))) {
	      $verbose.=', "preferences": "ERROR - SHOCK server unavailable"';
	    } elsif (exists($response->{error}) && $response->{error}) {
	      $verbose.=', "preferences": "ERROR - '.$response->{error}.'"';
	    } else {
	      $verbose.=', "preferences": '.$json->encode($response->{data}->{attributes}->{pref});
	    }
	  }
	}
	print $cgi->header(-type => 'application/json',
			   -status => 200,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "token": "'.$pref->[0]->value.'", "expiration": "'.$skeytimeout.'"'.$verbose.' }';
	exit;
      } else {
        return (undef, "invalid MG-RAST credentials");
      }
  }

  # this is KBase
  if ($key =~ /globusonline/ || $key =~ /^kbgo4711/) {

    my $json = new JSON;
    my $cgi = new CGI;

    $auth_source = 'kbase_user';
    my $ustruct = "";
    
    # this is a key, not a token, obtain a token
    if ($key =~ /^kbgo4711/) {

      unless ($ENV{'SCRIPT_URI'} =~ /^https/) {
        return (undef, "insecure protocol");
      }

      $key =~ s/^kbgo4711//;
      $ustruct = globus_token($key);
      if ($ustruct) {
	if ($ustruct->{access_token}) {
	  my $info = { token => $ustruct->{access_token} };
	  if ($cgi->param('verbosity') && $cgi->param('verbosity') eq 'verbose') {
	    my $verb = globus_info($ustruct->{access_token});
	    foreach my $key (keys(%$verb)) {
	      $info->{$key} = $verb->{$key};
	    }
	  }
	  print $cgi->header(-type => 'application/json',
			     -status => 200,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print $json->encode($info);
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
    my $userdata_url = 'https://nexus.api.globusonline.org/users/';

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

	    # there is no connection, create a fake user and hook them up
	    $result = `curl -s -H "Authorization: Globus-Goauthtoken $key" -X GET "$userdata_url$user"`;
	    my $globus_udata;
	    eval {
	      $globus_udata = $json->decode($result);
	    };
	    if ($@) {
	      return (undef, "could not reach globus online auth server");
	    }
	    my $existing = $master->User->get_objects({email => $globus_udata->{email}});
	    if (scalar(@$existing)) {
	      my $found_user = $existing->[0];
	      $master->Preferences->create( { name => 'kbase_user', user => $found_user, value => $user } );
	      return ($found_user);
	    } else {
	      my $firstname = "unknown";
	      my $lastname = "";
	      if ($globus_udata->{fullname} =~ /\s/) {
		($firstname, $lastname) = $globus_udata->{fullname} =~ /^(.+)\s(.+)$/;
	      } else {
		$lastname = $globus_udata->{username};
	      }
	      my $kbauto_user = $master->User->create({ firstname => $firstname, lastname => $lastname, email => $globus_udata->{email}, login => "KBaseAutoGeneratedUser:".$globus_udata->{username}, comment => "auto-generated KBase user" });
	      $master->Preferences->create( { name => 'kbase_user', user => $kbauto_user, value => $user } );
	      return ($kbauto_user);
	    }
	  }
	}
      } else {
	return (undef, "globus authentication did not validate");
      }
    }
  }

  # check for MG-RAST default auth header
  if ($auth_value =~ /^mgrast /) {
    $auth_value =~ s/^mgrast //;
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
