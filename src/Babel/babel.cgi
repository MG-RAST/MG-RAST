use strict;
use warnings;

use DBMaster;
use WebApplication;
use WebMenu;
use WebLayout;

my $menu = WebMenu->new();
$menu->add_category('Search', 'babel.cgi');
$menu->add_category('Sequence Retrieval', 'babel.cgi?page=Sequence');
$menu->add_category('Sources', 'babel.cgi?page=ViewSources');			      

#$menu->add_category('ACH Resolution', 'http://clearinghouse.nmpdr.org/aclh.cgi?page=main');
#$menu->add_entry('ACH Resolution', 'Main', 'http://clearinghouse.nmpdr.org/aclh.cgi?page=main', undef, ['login','ACH']);
#$menu->add_entry('ACH Resolution', 'Categorize possible conflicts', 'http://clearinghouse.nmpdr.org/aclh.cgi?page=correspondences', undef, ['login','ACH']);
#$menu->add_entry('ACH Resolution', 'Comment conflicts', 'http://clearinghouse.nmpdr.org/aclh.cgi?page=conflict', undef, ['login','ACH']);
#$menu->add_category('Upload', 'babel.cgi?page=UploadAnnotation');

$menu->add_category('Admin', 'babel.cgi?page=admin', undef, ['monitor']);
$menu->add_entry('Admin', 'Curate Organism Mapping', 'babel.cgi?page=MapOrgs', undef, ['view','organism']);
$menu->add_entry('Admin', 'View duplicates for current mapping', 'babel.cgi?page=MapOrgs&duplicates=1', undef, ['view','organism']);
$menu->add_entry('Admin', 'View current mapping', 'babel.cgi?page=ViewMappedOrgs', undef, ['view','organism']);
$menu->add_entry('Admin', 'ACH Test', 'babel.cgi?page=achtest');

#$menu->add_category('Logout', '?page=Logout', undef, ['login'], 99);

my $WebApp = WebApplication->new( { id       => 'Babel',
                                    dbmaster => DBMaster->new(-database => 'WebAppBackend' ,
							      -backend  => 'MySQL',
							      -host     => 'bio-app-authdb.mcs.anl.gov' ,
							      -user     => 'mgrast',
							      ),
                                    menu     =>  $menu,
                                    layout   =>  WebLayout->new('./Html/WebLayoutBabel.tmpl'),
                                    default  => 'Search',
                                  } );

$WebApp->layout->add_css('./Html/default.css');
$WebApp->layout->add_css('./Html/babel.css');
$WebApp->run();
