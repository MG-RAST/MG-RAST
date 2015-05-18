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
  <h3>MG-RAST oAuth Server</h3>
  <p>This server will provide secure authentication using the oAuth scheme. User and application registration is currently closed.</p>
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
      if ($cgi->param("client_id") && ($cgi->param("redirect_url") || $cgi->param("redirect_uri"))) {
	  if ($cgi->param('redirect_uri')) {
	      $cgi->param('redirect_url', $cgi->param('redirect_uri'));
	  }
	  my ($redirect_url) = $cgi->param('redirect_url') =~ /^(http[s]*\:\/\/[^\/]+)/;
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
	      print $cgi->redirect( -uri => $url."code=".$secret.($cgi->param('state') ? "&state=".$cgi->param('state') : ""), -cookie=>$cookie);
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
	  print $cgi->header(-type => 'text/plain',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print "redirect_url does not match client id";
	  exit 0;
	}
      } else {
	  $dbh->disconnect();
	  print $cgi->header(-type => 'text/plain',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print "missing redirect_url";
	  exit 0;
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
	  print $cgi->header(-type => 'text/plain',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print "invalid user code";
	  exit 0;
	  }
	} else {
	  $dbh->disconnect();
	  print $cgi->header(-type => 'text/plain',
			     -status => 400,
			     -charset => 'UTF-8',
			     -Access_Control_Allow_Origin => '*' );
	  print "invalid code";
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
	print $cgi->header(-type => 'text/plain',
			   -status => 200,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print "access_token=$token|".$user->login;
	exit 0;	
      } else {
	$dbh->disconnect();
	print $cgi->header(-type => 'text/plain',
			   -status => 400,
			   -charset => 'UTF-8',
			   -Access_Control_Allow_Origin => '*' );
	print "missing parameter";
	exit 0;
      }
    } else {
      warning_message("Authentication page called with an invalid action parameter.");
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
    print qq~<br><a href="oAuthPPO.cgi">return to home</a></div>~;
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
    print qq~<br><a href="oAuthPPO.cgi">return to home</a></div>~;
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
    my $generated = "";
    my $possible = 'abcdefghijkmnpqrstuvwxyz123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    while (length($generated) < 25) {
	$generated .= substr($possible, (int(rand(length($possible)))), 1);
    }
    return $generated;
}

sub dbh {
  return DBI->connect("DBI:SQLite:dbname=".$Conf::mgrast_data."/oauth/user.db", "", "", {AutoCommit => 0, PrintError => 1});
}
