package GoogleAnalytics;

use strict ;
use warnings;

use CGI;

use LWP::UserAgent;
use URI::Escape;

use constant GA_ACCOUNT => 'UA-39491359-1';
use constant VERSION => '4.4sp';

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

# Track a page view, updates all the cookies and campaign tracker,
# makes a server side request to Google Analytics and writes the transparent
# gif byte data to the response.
sub track_page_view {
  my ($uid, $debug) = @_;

  my $query = new CGI;

  my $domain_name = "";
  if (exists($ENV{'SERVER_NAME'})) {
    $domain_name = $ENV{'SERVER_NAME'};
  }

  my $document_referer = "-";
  if (defined($ENV{'HTTP_REFERER'})) {
    $document_referer = $ENV{'HTTP_REFERER'};
  }
  my $document_path = "";
  if (defined($ENV{'REQUEST_URI'})) {
    $document_path = uri_unescape($ENV{'REQUEST_URI'});
  }

  my $account = GA_ACCOUNT;
  my $user_agent = "";
  if (exists($ENV{'HTTP_USER_AGENT'})) {
    $user_agent = $ENV{'HTTP_USER_AGENT'};
  }

  my $visitor_id = $uid || &get_random_number();

  my $url = "http://www.google-analytics.com/collect";

  my $remote_address = "";
  if (exists($ENV{'REMOTE_ADDR'})) {
    $remote_address = $ENV{'REMOTE_ADDR'};
  }

  # Construct the payload
  my $content = 'v=' . VERSION .
    '&tid=' . $account .
    '&cid=' . anonymize_ip($remote_address) .
    '&t=pageview' . 
    '&vid=' . $visitor_id .
    '&dl=' . uri_escape($document_path);

  my $ua = LWP::UserAgent->new;

  if (exists($ENV{'HTTP_ACCEPT_LANGUAGE'})) {
    $ua->default_header('Accept-Language' => $ENV{'HTTP_ACCEPT_LANGUAGE'});
  }
  if (exists($ENV{'HTTP_USER_AGENT'})) {
    $ua->agent($ENV{'HTTP_USER_AGENT'});
  }

  my $ga_output = $ua->post($url, Content => $content);

  if (defined($debug) && !$ga_output->is_success) {
    print STDERR $ga_output->status_line;
  }
}

#
#  Helper functions
#

# The last octect of the IP address is removed to anonymize the user.
sub anonymize_ip {
  my ($ip) = @_;
  if ($ip eq "") {
    return "";
  }

 # Capture the first three octects of the IP address and replace the forth
 # with 0, e.g. 124.455.3.123 becomes 124.455.3.0
  if ($ip =~ /^((\d{1,3}\.){3})\d{1,3}$/) {
    return $1 . "0";
  } else {
    return "";
  }
}

# Get a random number string.
sub get_random_number {
  return int(rand(0x7fffffff));
}

1;
