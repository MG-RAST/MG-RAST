#!/soft/packages/perl/5.12.1/bin/perl

BEGIN {
    unshift @INC, qw(
              /mcs/bio/mg-rast/devel/sites/MG-RAST/site/lib
              /mcs/bio/mg-rast/devel/sites/MG-RAST/site/lib/WebApplication
              /mcs/bio/mg-rast/devel/sites/MG-RAST/site/lib/PPO
              /mcs/bio/mg-rast/devel/sites/MG-RAST/site/lib/MGRAST
              /mcs/bio/mg-rast/devel/sites/MG-RAST/site/lib/Babel
              /mcs/bio/mg-rast/devel/sites/MG-RAST/conf
	);
}
########################################################################
use strict;
use warnings;

use WebApplicationDBHandle;
use CGI;
use CGI::Cookie;
use Digest::MD5;
use Time::Local;
use DBI;
use HTML::Strip;

use Conf;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

my $allow_application = 0;
my $allow_user = 0;

my ($master, $error) = new WebApplicationDBHandle;
if ($error) {
  warning_message("The user database is currently offline");
}

my $dbh = dbh();
my $cgi = new CGI();

# strip out HTML
my $hs = HTML::Strip->new();
my @cgi_params = $cgi->param;
foreach my $p (@cgi_params) {
    my @plist = $cgi->param($p);
    foreach my $p1 (@plist) {
        if ($p1) {
            $p1 = $hs->parse($p1);
        }
    }
    $cgi->param($p, @plist);
}
$hs->eof;

my $cookie = $cgi->cookie('WebSession');
my $user = "";
my $uhash = "";
if ($cookie) {
  my $sessions = $master->UserSession->get_objects({ 'session_id' => $cookie });
  if (scalar(@$sessions)) {
    $user = $sessions->[0]->user;
  }
  $cookie = CGI::Cookie->new( -name    => 'WebSession',
			      -value   => $cookie,
			      -expires => "+2d" );
}
if ($cgi->param('logout')) {
    $cookie = CGI::Cookie->new( -name    => 'WebSession',
				-value   => '',
				-expires => "-1d" );
    
    if ($cgi->param('redirect')) {
      print $cgi->header( -redirect => $cgi->param('redirect'), -cookie => $cookie, -charset => 'UTF-8' );
    } else { 
      print $cgi->header( -cookie => $cookie, -charset => 'UTF-8' );
      print base_template();
      print success_message("You have been logged out.");
      print close_template();
      exit 0;
    }
}

if ($cgi->param('login') && $cgi->param('pass')) {
  $user = $master->User->init( { login => $cgi->param('login') } );
  if (ref $user && crypt($cgi->param('pass'), $user->password) eq $user->password) {
    # get 'random' data
    my $host= $cgi->remote_host();
    my $rand = int(int(time)*rand(100));
    
    # hide it behind a md5 sum (32 char hex)
    my $md5 = Digest::MD5->new;
    $md5->add($host, $rand);
    my $id = $md5->hexdigest;
    my $s = $master->UserSession->get_objects({ user => $user });
    if (scalar(@$s)) {
      $s->[0]->session_id($id);
      $s->[0]->timestamp(time);
    } else {
      $master->UserSession->create({ session_id => $id, user => $user, timestamp => time });
    }
    $cookie = CGI::Cookie->new( -name    => 'WebSession',
				-value   => $id,
				-expires => '+2d' );
  } else {
    login_screen({ "invalid" => 1 });
    exit 0;
  }
}

unless ($cgi->param('action')) {
  print $cgi->header(-cookie => $cookie, -charset => 'UTF-8' );
  print base_template();

  if (! $allow_application  && ! $allow_user) {
    print qq~<div class="alert alert-info">
  <h3>MG-RAST oAuth2 Server</h3>
  <p>This server will provide secure authentication using the oAuth2 scheme. User and application registration is currently closed.</p>
</div>~;
  }

  if ( $allow_application ) {
    print qq~
<div class="well">
  <h3>Register Application</h3>
  <form>
    <input type="hidden" name="action" value="register_application">
    <label>application name</label>
    <input type="text" class="span6" placeholder="enter application name" name="application">
    <span class="help-block">Create a unique identifier for your application. Use alphanumerical characters only.</span>
    <label>application url</label>
    <input type="text" class="span6" placeholder="enter URL" name="url">
    <span class="help-block">Enter the full path to your application script that will handle the authentication.</span>
    <button type="submit" class="btn">register</button>
  </form>
</div>~;
  }
  print close_template();
} else {
  if ($cgi->param("action") eq "register_application") {
    if ($cgi->param("application") && $cgi->param("url")) {
      my $res = $dbh->selectrow_arrayref("SELECT application FROM apps WHERE application =".$dbh->quote($cgi->param("application")).";");
      if ($dbh->err()) {
	warning_message($DBI::errstr);
	exit 0;
      }
      if ($res) {
	warning_message("This application is already registered.");
      } else {
	my $secret = secret();
	$dbh->do("INSERT INTO apps (application, url, secret) VALUES (".$dbh->quote($cgi->param("application")).", ".$dbh->quote($cgi->param("url")).", '".$secret."');");
	$dbh->commit();
	if ($dbh->err()) {
	  warning_message($DBI::errstr);
	  exit 0;
	}
	success_message("Successfully registered application:<br><table><tr><th>application name</th><td>".$cgi->param("application")."</td></tr><tr><th>application url</th><td>".$cgi->param("url")."</td></tr><tr><th>application secret</th><td>".$secret."</td></tr></table>");
	exit 0;
      }
    } else {
      warning_message("You must supply both an application name and a URL");
      exit 0;
    }
  } elsif ($cgi->param("action") eq "dialog") {
      if ($cgi->param("client_id") && $cgi->param("redirect_url")) {
	my $res = $dbh->selectrow_arrayref("SELECT application FROM apps WHERE application=".$dbh->quote($cgi->param("client_id"))." AND url=".$dbh->quote($cgi->param('redirect_url')).";");
	if ($dbh->err()) {
	  warning_message($DBI::errstr);
	  exit 0;
	}
	if ($res) {
	  if ($user) {
	    if (defined($cgi->param("accept"))) {
	      my $secret = secret();
	      if ($cgi->param('accept') eq '1') {
		$res = $dbh->do("INSERT INTO accepts (login, application, token) VALUES ('".$user->login."','".$cgi->param('client_id')."','".$secret."');");
		$dbh->commit();
		if ($dbh->err()) {
		  warning_message($DBI::errstr);
		  exit 0;
		}
	      } else {
		warning_message("You denied the application ".$cgi->param('client_id')." to access your data.");
		exit 0;
	      }	      
	      my $url = $cgi->param("redirect_url");
	      if ($url =~ /\?/) {
		$url .= "&";
	      } else {
		$url .= "?";
	      }
	      print $cgi->redirect( -uri => $url."code=".$secret, -cookie=>$cookie);
	      exit 0;				
	    } else {
		$res = $dbh->selectrow_arrayref("SELECT application, token FROM accepts WHERE application=".$dbh->quote($cgi->param("client_id"))." AND login='".$user->login."';");
		if ($dbh->err()) {
		    warning_message($DBI::errstr);
		    exit 0;
		}
		if ($res) {
		    my $url = $cgi->param("redirect_url");
		    if ($url =~ /\?/) {
			$url .= "&";
		    } else {
			$url .= "?";
		    }
		    print $cgi->redirect( -uri => $url."code=".$res->[1], -cookie=>$cookie );
		    exit 0;				
		} else {
		    auth_client_screen();
		    exit 0;
		}
	    }
	  } else {
	    login_screen();
	    exit 0;
	  }
	} else {
	  $dbh->disconnect();
	  print $cgi->header(-type => 'application/json',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print "{ 'error': 'redirect_url does not match client id' }";
	  exit 0;
	}
      }
    } elsif ($cgi->param("action") eq "token") {
      if ($cgi->param("client_id") && $cgi->param("client_secret") && $cgi->param("code")) {
	my $res = $dbh->selectrow_arrayref("SELECT accepts.login FROM apps, accepts WHERE apps.application=".$dbh->quote($cgi->param("client_id"))." AND apps.secret=".$dbh->quote($cgi->param('client_secret'))." AND apps.application=accepts.application and accepts.token=".$dbh->quote($cgi->param('code')).";");
	if ($dbh->err()) {
	  warning_message($DBI::errstr);
	  exit 0;
	}
	if ($res) {
	  my $login = $res->[0];
	  $user = $master->User->init( { login => $login } );
	  unless (ref($user)) {
	  $dbh->disconnect();
	  print $cgi->header(-type => 'application/json',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print '{ "error": "invalid user code" }';
	  exit 0;
	  }
	} else {
	  $dbh->disconnect();
	  print $cgi->header(-type => 'application/json',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print '{ "error": "invalid code" }';
	  exit 0;
	}

	my $token = $master->Preferences->get_objects( { user => $user, name => 'WebServicesKey' } );
	my $timeout = $master->Preferences->get_objects( { user => $user, name => 'WebServiceKeyTdate' } );
	if (scalar(@$token)) {
	  if ($timeout->[0]->value > time) {
	    $token->[0]->value(secret());
	    $timeout->[0]->value(time + (60 * 60 * 24 * 7));
	    $token = $token->[0]->value;
	  } else {
	    $token = $token->[0]->value;
	  }
	} else {
	  $token = secret();
	  $master->Preferences->create( { user => $user, name => 'WebServicesKey', value => $token } );
	  $master->Preferences->create( { user => $user, name => 'WebServiceKeyTdate', value => time + (60 * 60 * 24 * 7) } );
	}
	
	$dbh->disconnect();
	print $cgi->header(-type => 'application/json',
			   -status => 200,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "token": "'.$token.'", "user": "'.$user->login.'" }';
	exit 0;	
      } else {
	$dbh->disconnect();
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "missing parameter" }';
	exit 0;
      }
    } elsif ($cgi->param("action") eq "create_group") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $gid = &secret(10);
	    my $group = $master->Scope->get_objects( { name => $gid } );
	    while (scalar(@$group)) {
		$gid = &secret(10);
		$group = $master->Scope->get_objects( { name => $gid } );
	    }
	    $group = $master->Scope->create( { name => $gid, application => undef, description => "SHOCK" } );
	    if (ref($group)) {
		my $uhs = $master->UserHasScope->create( { user => $user, scope => $group, granted => 1 } );
		if (ref($uhs)) {
		    my $right = $master->Rights->create( { application => undef,
							   scope => $user->get_user_scope,
							   data_type => 'scope',
							   data_id => $group->_id,
							   name => 'edit',
							   delegated => 0,
							   granted => 1 } );
		    if (ref($right)) {
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "success": "group created successfully" }';
			exit 0;
		    } else {
			$group->delete();
			$uhs->delete();
			print $cgi->header(-type => 'application/json',
					   -status => 400,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "error": "group creation failed due to a database error while creating user group admin right" }';
			exit 0;
		    }
		} else {
		    $group->delete();
		    print $cgi->header(-type => 'application/json',
				       -status => 400,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "error": "group creation failed due to a database error while connecting user to group" }';
		    exit 0;
		}
	    } else {
		print $cgi->header(-type => 'application/json',
				   -status => 400,
				   -charset => 'UTF-8',
				   -Access_Control_Allow_Origin => '*' );
		print '{ "error": "group creation failed due to a database error at group creation" }';
		exit 0;
	    }
	}
    } elsif ($cgi->param("action") eq "delete_group") {
	if (&authenticate_user($cgi->param('token'))) {
	    if ($cgi->param('group')) {
		my $gid = $cgi->param('group');
		my $group = $master->Scope->get_objects( { name => $gid } );
		if (scalar(@$group)) {
		    $group = $group->[0];
		    if ($user->has_right(undef, 'edit', 'scope', $gid, 1)) {
			my $uhss = $master->UserHasScope->get_objects( { scope => $group } );
			my $rights = $master->Rights->get_objects( { data_type => 'scope', data_id => $group->_id } );
			foreach my $uhs (@$uhss) {
			    $uhs->delete();
			}
			foreach my $right (@$rights) {
			    $right->delete();
			}
			$rights = $master->Rights->get_objects( { scope => $group } );
			foreach my $right (@$rights) {
			    $right->delete();
			}
			$group->delete();
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "success": "group deleted successfully" }';
			exit 0;
		    } else {
			print $cgi->header(-type => 'application/json',
					   -status => 400,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "error": "insufficient rights to delete this group" }';
			exit 0;
		    }
		} else {
		    print $cgi->header(-type => 'application/json',
				       -status => 400,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "error": "invalid group" }';
		    exit 0;
		}
	    } else {
		print $cgi->header(-type => 'application/json',
				   -status => 400,
				   -charset => 'UTF-8',
				   -Access_Control_Allow_Origin => '*' );
		print '{ "error": "missing parameter group" }';
		exit 0;
	    }
	}
    } elsif ($cgi->param("action") eq "add_to_group") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $u2 = &get_user();
	    my $group = &get_group();
	    my $gid = $cgi->param('group');
	    if ($user->has_right(undef, 'edit', 'scope', $gid, 1)) {
		my $uhs = $master->UserHasScope->get_objects( { user => $u2, scope => $group } );
		if (scalar(@$uhs)) {
		    $uhs = $uhs->[0];
		    if ($uhs->{granted}) {
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user was already part of this group" }';
			exit 0;
		    } else {
			$uhs->granted(1);
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user added to group successfully" }';
			exit 0;
		    }
		} else {
		    $uhs = $master->UserHasScope->create( { user => $u2, scope => $group, granted => 1 } );
		}
		if (ref($uhs)) {
		    if ($cgi->param('type') && $cgi->param('type') eq 'owner') {
			my $right = $master->Rights->get_objects( { scope => $u2->get_user_scope,
								    data_type => 'scope',
								    data_id => $group->_id,
								    name => 'edit' } );
			if (scalar(@$right)) {
			    $right = $right->[0];
			    if ($right->{granted} && ! $right->{delegated}) {
				print $cgi->header(-type => 'application/json',
						   -status => 200,
						   -charset => 'UTF-8',
						   -Access_Control_Allow_Origin => '*' );
				print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user was already owner of this group" }';
				exit 0;
			    } else {
				$right->granted(1);
				$right->delegated(0);
				print $cgi->header(-type => 'application/json',
						   -status => 200,
						   -charset => 'UTF-8',
						   -Access_Control_Allow_Origin => '*' );
				print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user added as owner to group successfully" }';
				exit 0;
			    }
			} else {
			    $right = $master->Rights->create( { scope => $u2->get_user_scope,
								data_type => 'scope',
								data_id => $group->_id,
								name => 'edit',
								granted => 1,
								delegated => 0 } );
			}
			unless (ref($right)) {
			    $uhs->delete();
			    print $cgi->header(-type => 'application/json',
					       -status => 400,
					       -charset => 'UTF-8',
					       -Access_Control_Allow_Origin => '*' );
			    print '{ "error": "adding to group failed due to a database error while creating group right" }';
			    exit 0;
			}
		    }
		    print $cgi->header(-type => 'application/json',
				       -status => 200,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user added as member to group successfully" }';
		    exit 0;
		} else {
		    print $cgi->header(-type => 'application/json',
				       -status => 400,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "error": "adding to group failed due to a database error while connecting user to group" }';
		    exit 0;
		}
	    } else {
		print $cgi->header(-type => 'application/json',
				   -status => 400,
				   -charset => 'UTF-8',
				   -Access_Control_Allow_Origin => '*' );
		print '{ "error": "invalid permissions to edit group" }';
		exit 0;
	    }
	}
    } elsif ($cgi->param("action") eq "delete_from_group") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $u2 = &get_user();
	    my $group = &get_group();
	    my $gid = $cgi->param('group');
	    if ($user->has_right(undef, 'edit', 'scope', $gid, 1)) {
		my $uhs = $master->UserHasScope->get_objects( { user => $u2, scope => $group, granted => 1 } );
		if (scalar($uhs)) {
		    my $right = $master->Rights->get_objects( { scope => $u2->get_user_scope,
								data_type => 'scope',
								data_id => $group->_id,
								name => 'edit' } );
		    if (scalar($right)) {
			$right->[0]->delete();
		    }
		    $uhs->[0]->delete();
		    print $cgi->header(-type => 'application/json',
				       -status => 200,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user deleted from group successfully" }';
		    exit 0;
		} else {
		    print $cgi->header(-type => 'application/json',
				       -status => 400,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "error": "deleting from group failed due to a database error while connecting user to group" }';
		    exit 0;
		}
	    } else {
		print $cgi->header(-type => 'application/json',
				   -status => 400,
				   -charset => 'UTF-8',
				   -Access_Control_Allow_Origin => '*' );
		print '{ "error": "invalid permissions to edit group" }';
		exit 0;
	    }
	}
    } elsif ($cgi->param("action") eq "create_group_admin") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $u2 = &get_user();
	    my $group = &get_group();
	    my $gid = $cgi->param('group');
	    if ($user->has_right(undef, 'edit', 'scope', $gid, 1)) {
		if ($u2->has_right(undef, 'edit', 'scope', $gid, 1)) {
		    print $cgi->header(-type => 'application/json',
				       -status => 200,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user was already owner of the group" }';
		    exit 0;
		} else {
		    my $right = $master->Rights->get_objects( { application => undef,
								data_type => 'scope',
								data_id => $group->_id,
								name => 'edit' } );
		    if (scalar(@$right)) {
			$right->delegated(0);
			$right->granted(1);
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user is now owner of the group" }';
			exit 0;
		    } else {
			$right = $master->Rights->create( { application => undef,
							    data_type => 'scope',
							    data_id => $group->_id,
							    name => 'edit',
							    granted => 1,
							    delegated => 0 } );
			if (ref($right)) {
			    print $cgi->header(-type => 'application/json',
					       -status => 200,
					       -charset => 'UTF-8',
					       -Access_Control_Allow_Origin => '*' );
			    print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user is now owner of the group" }';
			    exit 0;
			} else {
			    print $cgi->header(-type => 'application/json',
					       -status => 400,
					       -charset => 'UTF-8',
					       -Access_Control_Allow_Origin => '*' );
			    print '{ "error": "deleting from group failed due to a database error while creating owner right" }';
			    exit 0;
			}
		    }
		}
	    }
	}
    } elsif ($cgi->param("action") eq "delete_group_admin") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $u2 = &get_user();
	    my $group = &get_group();
	    my $gid = $cgi->param('group');
	    if ($user->has_right(undef, 'edit', 'scope', $gid, 1)) {
		my $admins = $master->Rights->get_objects( { application => undef,
							     data_type => 'scope',
							     data_id => $group->_id,
							     name => 'edit',
							     granted => 1,
							     delegated => 0 } );
		if (scalar(@$admins) < 2) {
		    print $cgi->header(-type => 'application/json',
				       -status => 400,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "error": "you cannot delete the last admin of a group" }';
		    exit 0;
		}
		if ($u2->has_right(undef, 'edit', 'scope', $gid, 1)) {
		    my $right = $master->Rights->get_objects( { application => undef,
								data_type => 'scope',
								data_id => $group->_id,
								scope => $u2->get_user_scope(),
								name => 'edit' } );
		    if (scalar(@$right)) {
			$right->[0]->delete();
			print $cgi->header(-type => 'application/json',
					   -status => 200,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user no longer owner of the group" }';
		    exit 0;
		    } else {
			print $cgi->header(-type => 'application/json',
					   -status => 400,
					   -charset => 'UTF-8',
					   -Access_Control_Allow_Origin => '*' );
			print '{ "error": "database error when retrieving owner right" }';
			exit 0;
		    }		    
		} else {
		    print $cgi->header(-type => 'application/json',
				       -status => 200,
				       -charset => 'UTF-8',
				       -Access_Control_Allow_Origin => '*' );
		    print '{ "group": "'.$gid.'", "error": null, "user": "'.$u2->{login}.'", "success": "user was not owner of the group" }';
		    exit 0;
		}
	    }
	}
    } elsif ($cgi->param("action") eq "credentials") {
	if (&authenticate_user($cgi->param('token'))) {
	    my $return_data = '{ "user": "'.$user->{login}.'", "firstname": "'.$user->{firstname}.'", "lastname": "'.$user->{lastname}.'", "email": "'.$user->{email}.'"';
	    if ($cgi->param('groups')) {
		my $groups = [];
		my $ugroups = $master->UserHasScope->get_objects({ user => $user });
		if (scalar(@$ugroups)) {
		    foreach my $g (@$ugroups) {
			if ($g->scope->description && $g->scope->description eq "SHOCK") {
			    push(@$groups, $g->scope->name);
			}
		    }
		    if (scalar(@$groups)) {
			$return_data .= ', "groups": ["'.join('","', @$groups).'"]';
		    } else {
			$return_data .= ', "groups": []';
		    }
		} else {
		    $return_data .= ', "groups": []';
		}
		
	    }
	    if ($cgi->param('group_members')) {
		my @gs = $cgi->param('group_members');
		$return_data .= ', "group_members": { ';
		my $gms = [];
		foreach my $g (@gs) {
		    my $scope = $master->Scope->get_objects( { name => $g } );
		    if (scalar(@$scope)) {
			$scope = $scope->[0];
			if (scalar(@{$master->UserHasScope->get_objects({ user => $user, scope => $scope })})) {
			    my $mems = $master->UserHasScope->get_objects( { scope => $scope } );
			    my $logins = [];
			    foreach my $mem (@$mems) {
				push(@$logins, $mem->user->login);
			    }
			    if (scalar(@$logins)) {
				push(@$gms, '"'.$g.'": [ "'.join('","', @$logins).'" ]');
			    }
			}
		    }
		}
		$return_data .= join(",", @$gms)." }";
	    }

	    $return_data .= " }";
	    print $cgi->header(-type => 'application/json',
			       -status => 200,
			       -charset => 'UTF-8',
			       -Access_Control_Allow_Origin => '*' );
	    print $return_data;
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "invalid action parameter" }';
	exit 0;
    }
}

sub base_template {
    return qq~<!DOCTYPE html>
<html>

  <head>

    <title>MG-RAST Authentication</title>

    <script type="text/javascript" src="./Html/jquery.min.js"></script>
    <script type="text/javascript" src="./Html/bootstrap.min.js"></script>

    <link rel="stylesheet" type="text/css" href="./Html/bootstrap.min.css">

  </head>

  <body>

  <div class="container">
    <div class="navbar">
      <div class="navbar-inner">
        <div class="container">
          <img src="./Html/MGRAST_logo.png" style="height: 55px; margin-top: 2px; float: left;">
          <ul class="nav">
            <li>
              <a href="#" style="padding-top: 17px; margin-left: 20px;">User - Application - Authentication</a>
            </li>
          </ul>
        </div>
      </div>
    </div>~;
}

sub close_template {
    return qq~
    </div>

  </body>
</html>~;
}

sub warning_message {
    my ($message) = @_;

    $dbh->disconnect();
    print $cgi->header(-charset => 'UTF-8');
    print base_template();
    print qq~<div class="alert alert-error">
<button class="close" data-dismiss="alert" type="button">x</button>
<strong>Warning</strong><br>~;
    print $message;
    print qq~<br><a href="oauth2.cgi">return to home</a></div>~;
    print close_template();    
}

sub success_message {
    my ($message) = @_;

    $dbh->disconnect();
    print $cgi->header(-charset => 'UTF-8');
    print base_template();
    print qq~<div class="alert alert-success">
<button class="close" data-dismiss="alert" type="button">x</button>
<strong>Info</strong><br>~;
    print $message;
    print qq~<br><a href="oauth2.cgi">return to home</a></div>~;
    print close_template();
}

sub login_screen {
    my ($params) = @_;

    my $message = "";
    if ($params->{invalid}) {
	$message = qq~<div class="alert alert-error">
<button class="close" data-dismiss="alert" type="button">x</button>
<strong>Warning</strong><br>Your login failed.</div>~;
    }

    my @pa = $cgi->param;
    my $hidden = "";
    foreach my $p (@pa) {
	next if ($p eq "login");
	next if ($p eq "pass");
	$hidden .= "<input type='hidden' name='".$p."' value='".$cgi->param($p)."'>";
    }

    print $cgi->header(-charset => 'UTF-8');
    print base_template();
print qq~
<div class="well">
  <h3>Login to MG-RAST</h3>
  <form method=post>
    $hidden$message
    <label>login</label>
    <input type="text" class="span3" placeholder="enter login" name="login">
    <label>password</label>
    <input type="password" class="span3" placeholder="enter password" name="pass">
    <button type="submit" class="btn">login</button>
  </form>
</div>~;
    print close_template();

    $dbh->disconnect();
}

sub auth_client_screen {
    my @pa = $cgi->param;
    my $hidden = "<input type='hidden' name='accept' id='accept_app'>";
    foreach my $p (@pa) {
	next if ($p eq "login");
	next if ($p eq "pass");
	$hidden .= "<input type='hidden' name='".$p."' value='".$cgi->param($p)."'>";
    }

    my $application = $cgi->param("client_id");
    print $cgi->header(-cookie=>$cookie, -charset => 'UTF-8');
    print base_template();
    print qq~
  <div class="well">
    <h3>MG-RAST application authorization</h3>
    <p>The application <b>$application</b> is requesting to verify your login, name and email address as stored in MG-RAST. Is that OK?</p>
    <form>
      $hidden
      <input type="button" value="deny" class="btn" onclick="document.getElementById('accept_app').value='0';document.forms[0].submit();"><input type="button" class="btn" value="accept" onclick="document.getElementById('accept_app').value='1';document.forms[0].submit();">
    </form>
  </div>~;
    print close_template();

    $dbh->disconnect();
}

sub secret {
    my ($secret_length) = @_;

    unless ($secret_length) {
	$secret_length = 25;
    }
    
    my $generated = "";
    my $possible = 'abcdefghijkmnpqrstuvwxyz123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    while (length($generated) < $secret_length) {
	$generated .= substr($possible, (int(rand(length($possible)))), 1);
    }
    return $generated;
}

sub dbh {
  return DBI->connect("DBI:SQLite:dbname=".$Conf::mgrast_data."/oauth/user.db", "", "", {AutoCommit => 0, PrintError => 1});
}

sub authenticate_user {
    my ($token) = @_;

    unless ($token) {
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "required parameter token missing" }';
	exit 0;
    }

    my $pref = $master->Preferences->get_objects( { name => 'WebServicesKey', value => $token } );
    if (scalar(@$pref)) {
	$user = $pref->[0]->user;
	$pref = $master->Preferences->get_objects( { name => 'WebServiceKeyTdate', user => $user } );
	if (scalar(@$pref) && $pref->[0]->value > time) {
	    return 1;
	} else {
	    print $cgi->header(-type => 'application/json',
			       -status => 400,
			       -charset => 'UTF-8',
			       -Access_Control_Allow_Origin => '*' );
	    print '{ "error": "token timed out" }';
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "invalid token" }';
	exit 0;
    }
}

sub get_user {
    my $u2 = undef;
    if ($cgi->param('user_id')) {
	$u2 = $master->User->get_objects( { login => $cgi->param('user_id') } );
	if (scalar(@$u2)) {
	    $u2 = $u2->[0];
	} else {
	    print $cgi->header(-type => 'application/json',
			       -status => 400,
			       -charset => 'UTF-8',
			       -Access_Control_Allow_Origin => '*' );
	    print '{ "error": "invalid user id" }';
	    exit 0;
	}
    } elsif ($cgi->param('email')) {
	$u2 = $master->User->get_objects( { email => $cgi->param('email') } );
	if (scalar(@$u2)) {
	    $u2 = $u2->[0];
	} else {
	    print $cgi->header(-type => 'application/json',
			       -status => 400,
			       -charset => 'UTF-8',
			       -Access_Control_Allow_Origin => '*' );
	    print '{ "error": "invalid user email" }';
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "missing parameter, you must provide either user_id or email" }';
	exit 0;
    }
    return $u2;
}

sub get_group {
    my $group = undef;
    if ($cgi->param('group')) {
	my $gid = $cgi->param('group');
	$group = $master->Scope->get_objects( { name => $gid } );
	if (scalar(@$group)) {
	    $group = $group->[0];
	} else {
	    print $cgi->header(-type => 'application/json',
			       -status => 400,
			       -charset => 'UTF-8',
			       -Access_Control_Allow_Origin => '*' );
	    print '{ "error": "invalid group id" }';
	    exit 0;
	}
    } else {
	print $cgi->header(-type => 'application/json',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print '{ "error": "missing parameter group" }';
	exit 0;	
    }
    return $group;
}
