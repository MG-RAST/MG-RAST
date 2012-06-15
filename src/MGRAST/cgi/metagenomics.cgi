use strict;
use warnings;
no warnings 'once';

use WebApplication;
use WebMenu;
use WebLayout;
use WebConfig;

use Conf;

eval {
    &main;
};

if ($@)
{
    my $cgi = new CGI();

    print $cgi->header();
    print $cgi->start_html();
    
    # print out the error
    print '<pre>'.$@.'</pre>';

    print $cgi->end_html();

}

sub main {
    my $range = 2;
    my $random_number = int(rand($range));

    my $layout = WebLayout->new(TMPL_PATH.'MGRAST.tmpl');
    $layout->add_template(TMPL_PATH.'EmptyLayout.tmpl', ["Home2"]);
    $layout->add_template(TMPL_PATH.'MGRAST-frontpage.tmpl', ["Home"]);
    $layout->add_css("$Conf::cgi_url/Html/mgrast.css");
    $layout->add_css("$Conf::cgi_url/Html/formalize.css");
    $layout->add_javascript("$Conf::cgi_url/Html/jquery-1.4.2.min.js");
    $layout->add_javascript("$Conf::cgi_url/Html/jquery.formalize.min.js");
    $layout->add_javascript("$Conf::cgi_url/Html/raphael-min.js");
    $layout->show_icon(1);
    $layout->icon_path("$Conf::cgi_url/Html/favicon.ico");

    # build menu
    my $menu = WebMenu->new();
    $menu->style('horizontal');

    # initialize application
    my $WebApp = WebApplication->new( { id       => 'MGRAST',
					menu     => $menu,
					layout   => $layout,
					default  => 'Home',
				      } );
    $WebApp->strict_browser(1);
    $WebApp->page_title_prefix('MG-RAST - ');
    $WebApp->show_login_user_info(1);
    $WebApp->fancy_login(1);

    # run application
    $WebApp->run();

}
