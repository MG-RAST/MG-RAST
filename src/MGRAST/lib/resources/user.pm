package resources::user;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "returns information about a user",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/json" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  my $user = $params->{user};

  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  unless ($user) {
    print $cgi->header(-type => 'text/plain',
		       -status => 401,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid authentication for user call";
    exit 0;
  }

  if ($rest && scalar(@$rest) == 1) {
    unless ($user->has_right(undef, 'edit', 'user', $user->{_id})) {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: insufficient permissions for user call";
      exit 0;
    }
  } else {
    unless ($user->has_right(undef, 'edit', 'user', '*')) {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: insufficient permissions for user call";
      exit 0;
    }
  }

  use WebApplicationDBHandle;
  use DBMaster;

  my ($dbmaster, $error) = WebApplicationDBHandle->new();
  if ($error) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: could not connect to user database - $error";
    exit 0;
  }

  my $data;
  if ($rest && scalar(@$rest) == 1) {
    my $u = $dbmaster->User->get_objects( { login => $rest->[0] } );
    if (scalar(@$u)) {
      $u = $u->[0];
      $data = { firstname => $u->{firstname},
		email => $u->{email},
		comment => $u->{comment},
		entry_date => $u->{entry_date},
		active => $u->{active},
		lastname => $u->{lastname},
		login => $u->{login} };
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 401,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: user not found";
      exit 0;
    }
  } else {    
    $data = [];

    my $users = $dbmaster->User->get_objects();
    foreach my $u (@$users) {
      push(@$data, { firstname => $u->{firstname},
		     email => $u->{email},
		     comment => $u->{comment},
		     entry_date => $u->{entry_date},
		     active => $u->{active},
		     lastname => $u->{lastname},
		     login => $u->{login},
		     id => $u->{login} } );
    }
  }

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode( $data );
}

sub TO_JSON { return { %{ shift() } }; }

1;
