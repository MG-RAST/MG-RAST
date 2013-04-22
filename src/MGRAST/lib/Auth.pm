package Auth;

sub authenticate {
  my ($key) = @_;

  use WebApplicationDBHandle;
  my ($master, $error) = WebApplicationDBHandle->new();
  if ($error) {
    return undef;
  }

  my $user = undef;

  my $auth_source = 'WebServicesKey';
  my $auth_value = $key;

  # this is kbase
  if ($key =~ /globusonline/ || $key =~ /^kbgo4711/) {
    use JSON;
    my $json = new JSON;
    use CGI;
    my $cgi = new CGI;

    $auth_source = 'kbase_user';
    my $ustruct = "";
    
    if ($key =~ /^kbgo4711/) {
      $key =~ s/^kbgo4711//;
      $ustruct = globus_token($key);
      if ($ustruct) {
	      print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
	      print '{ "token": "'.$ustruct->{access_token}.'" }';
	      exit;
      } else {
          return undef;
      }
    }

    my $validation_url = 'https://nexus.api.globusonline.org/goauth/keys/';    

    my ($user, $sig) = $key =~ /^un=([^\|]+)\|.+SigningSubject=([^\|]+)/;
    unless ($user && $sig) {
      return undef;
    }
    $sig =~ s/^.*\/([abcdef0123456789-]+)$/$1/;
    my $result = `curl -s -X GET "$validation_url$sig"`;
    eval {
      $ustruct = $json->decode($result);
    };
    if ($@) {
      die "could not reach auth server";
    } else {
      if ($ustruct->{valid}) {
	      $auth_value = $user;	
	      if ($cgi->param('webkey')) {
	          my $pref = $master->Preferences->get_objects( { name => 'WebServicesKey', value => $cgi->param('webkey') } );
	          if (scalar(@$pref)) {
	              my $u = $pref->[0]->user;
	              $pref = $master->Preferences->get_objects( { name => 'WebServiceKeyTdate', user => $u } );
	              if (scalar(@$pref) && $pref->[0]->value > time) {
	                  my $existing = $master->Preferences->get_objects( { name => 'kbase_user', user => $u } );
	                  if (scalar(@$existing)) {
		                  $existing->[0]->value($user);
	                  } else {
		                  $master->Preferences->create( { name => 'kbase_user', user => $u, value => $user } );
	                  }
	              }
	          }
	      }
      } else {
	      return undef;
      }
    }
  }
    
  my $preference = $master->Preferences->get_objects( { name => $auth_source, value => $auth_value } );
  if (scalar(@$preference)) {
    $user = $preference->[0]->user;
    return $user;
  }

  return undef;
}

sub globus_token {
    my ($key) = @_;
    my $token = undef;
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
