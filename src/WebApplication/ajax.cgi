use strict;
use warnings;
use CGI;
use WebComponent::Ajax;
$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;
use IO::Handle;
#open(TICKLOG, ">/dev/pts/9") or open(TICKLOG, ">&STDERR");
#TICKLOG->autoflush(1);

use Time::HiRes 'gettimeofday';
my $start = gettimeofday;
my $time_last;
sub tick {
    my($w) = @_;
    my $now = gettimeofday;
    my $t = $now - $start;
    my $tms = int(($now - $time_last) * 1000);
    $time_last = $now;
    my ($package, $filename, $line) = caller;

#    printf TICKLOG "$$ %-40s %5d %5d %.3f\n", $filename, $line, $tms, $t;
#    TICKLOG->flush();
}


my $have_fcgi;
eval {
    require CGI::Fast;
    $have_fcgi = 1;
};


#
# If no CGI vars, assume we are invoked as a fastcgi service.
#
my $n_requests = 0;
if ($have_fcgi && $ENV{REQUEST_METHOD} eq '')
{
    #
    # Precompile modules. Find where we found one, and use that path
    # to walk for the rest.
    #
    
    my $mod_path = $INC{"WebComponent/Ajax.pm"};
    if ($mod_path && $mod_path =~ s,WebApplication/WebComponent/Ajax\.pm$,,)
    {
	local $SIG{__WARN__} = sub {};
	for my $what (qw(SeedViewer RAST WebApplication))
	{
	    for my $which (qw(WebPage WebComponent))
	    {
		opendir(D, "$mod_path/$what/$which") or next;
		my @x = grep { /^[^.]/ } readdir(D);
		for my $mod (@x)
		{
		    $mod =~ s/\.pm$//;
		    my $fullmod = join("::", $what, $which, $mod);
		    eval " require $fullmod; ";
		}
		closedir(D);
	    }
	}
    }

    my $max_requests = 100;
    while (($max_requests == 0 || $n_requests++ < $max_requests) &&
	   (my $cgi = new CGI::Fast()))
    {
	eval {
	    &main($cgi);
	};
	if ($@)
	{
	    if ($@ =~ /^cgi_exit/)
	    {
		# this is ok.
	    }
	    elsif (ref($@) ne 'ARRAY')
	    {
		warn "code died, cgi=$cgi returning error '$@'\n";
		print $cgi->header(-status => '500 error in body of cgi processing', -charset => 'UTF-8');
		print $@;
	    }
	}
    endloop:
    }

}
else
{
    my $cgi = new CGI();
    eval { &main($cgi); };

    if ($@)
    {
	my $error = $@;
	
	print CGI::header();
	print CGI::start_html();
	
	# print out the error
	print '<pre>'.$error.'</pre>';
	
	print CGI::end_html();
    }
}


sub main
{
    my($cgi) = @_;
    my ($ajaxError, @cookieList);
    
    my $app = $cgi->param('app');
    my $page = $cgi->param('page');
    my $sub_to_call = $cgi->param('sub');
    my $cookies = $cgi->param('cookies');
    # require the web page package
    my $package = $app."::WebPage::".$page;
    my $package_ = 'WebPage::'.$page;
    my $realPage = $package;
    {
	no strict;
	eval "require $package";
	if ($@) {
	    eval "require $package_";
	    $realPage = $package_;
	    if ($@) {
		$ajaxError = "Sorry, but the page '$page' was not found.";
	    }
	}
    }
    
    $cgi->delete('app');
    $cgi->delete('sub');
    $cgi->delete('cookies');
    if ($cookies && ! defined $ajaxError) {
	my $method = $realPage . "::" . $cookies;
	@cookieList = eval("$method(\$cgi)");
	if ($@) {
	    $ajaxError = $@;
	}
    }
    print $cgi->header(-cookie => \@cookieList, -charset => 'UTF-8');
    my $result;
    if (! defined $ajaxError) {
	eval {
	    $result = &WebComponent::Ajax::render($app, $realPage, $sub_to_call, $cgi);
	};
	if ($@) {
	    $ajaxError = $@;
	}
    }
    if (defined $ajaxError) {
	$result = CGI::div({style => join("\n", "margin: 20px 10px 20px 10px;",
					  "padding-left: 10px;",
					  "padding-right: 10px;",
					  "width: 80%;",
					  "color: #fff;",
					  "background: #ff5555;",
					  "border: 2px solid #ee2222;") },
			   "Failure in component: $ajaxError");
    }
    print $result;
}

1;
