use strict;
use warnings;

use DBMaster;
use WebApplication;
use WebMenu;
use WebLayout;
use WebConfig;

my $layout = WebLayout->new("$Conf::cgi_url/Html/MyAppLayout.tmpl");
$layout->add_css(TMPL_PATH.'/default.css');

my $menu = WebMenu->new();
$menu->add_category('Home', 'myApp.cgi');

my $WebApp = WebApplication->new( { id       => 'MyApp',
                                    dbmaster => DBMaster->new(-database => 'WebAppBackend'),
                                    menu     => $menu,
                                    layout   => $layout,
                                    default  => 'MyFirstPage',
                                  } );

$WebApp->run();
