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
      $key =~ s/^kbgo4711(.*)$/Basic $1/;
      my $pre = `curl -s -H "Authorization: $key" -X POST "https://nexus.api.globusonline.org/goauth/token?grant_type=client_credentials"`;
      eval {
	$ustruct = $json->decode($pre);
      };
      if ($@) {
	print STDERR "could not reach auth server: $@\n";
	exit;
      } else {
	print $cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
	print "{ token: '".$ustruct->{access_token}."' }";
	exit;
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

  # use JSON;
  # use LWP::UserAgent;
  # my $json = new JSON;
  # my $cgi = new CGI();
  # my $ua = LWP::UserAgent->new;

  # my $call_url = "oAuth.cgi?action=data&access_token=" . $access_token;
  # my $response = $ua->get($call_url)->content;
  # my $data = $json->decode($response);
  # my $login = $data->{login};
  # my ($dbmaster, $error) = WebApplicationDBHandle->new();
  # my $user = $dbmaster->User->init({ "login" => $login });
  
  # return $user;
}

1;
