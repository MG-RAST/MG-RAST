use strict;
use warnings;
use CGI;

use WebApplication;

my $cgi = new CGI();
    
my $app = $cgi->param('app');
my $page = $cgi->param('page');
my $sub_to_call = $cgi->param('sub');
$cgi->delete('app');
$cgi->delete('sub');

my $application = WebApplication->new( { id => $app } );

# require the web page package
my $package = $app."::WebPage::".$page;
my $package_ = 'WebPage::'.$page;
my $realPage = $package;
{
    no strict;
    eval "require $package";
    if ($@) {
	print STDERR $@."\n";
	eval "require $package_";
	$realPage = $package_;
	if ($@) {
	    die $@;
	}
    }

    my $page_instance = $application->page($realPage->new($application));
    $page_instance->init();
    my $method = "\$page_instance->$sub_to_call";
    my $content;
    eval "\$content = $method";
    if ($@) {
	die $@;
    }
    print $cgi->header( -cookie => $application->session->cookie );
    print $content;
}

1;
