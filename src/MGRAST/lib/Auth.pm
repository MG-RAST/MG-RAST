package Auth;

use CGI;
use JSON;
use LWP::UserAgent;
use URI::Escape;

#use WebApplicationDBHandle;
#use DBMaster;

sub authenticate {
  return undef;
  
  # my ($key) = @_;

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
