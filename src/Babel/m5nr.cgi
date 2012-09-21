use strict;
use warnings;

use DBMaster;
use WebApplication;
use WebMenu;
use WebLayout;

my $menu = WebMenu->new();
$menu->add_category('Search', 'm5nr.cgi');
$menu->add_category('Sequence Retrieval', 'm5nr.cgi?page=Sequence');
$menu->add_category('Sources', 'm5nr.cgi?page=ViewSources');
$menu->add_category('Download', 'm5nr.cgi?page=Download');
$menu->add_category('Help', 'http://blog.metagenomics.anl.gov/mg-rast/howto/m5nr-%E2%80%94-the-m5-non-redundant-protein-database/');

$menu->add_category('Admin', 'm5nr.cgi?page=admin', undef, ['monitor']);
$menu->add_entry('Admin', 'Curate Organism Mapping', 'm5nr.cgi?page=MapOrgs', undef, ['view','organism']);
$menu->add_entry('Admin', 'View duplicates for current mapping', 'm5nr.cgi?page=MapOrgs&duplicates=1', undef, ['view','organism']);
$menu->add_entry('Admin', 'View current mapping', 'm5nr.cgi?page=ViewMappedOrgs', undef, ['view','organism']);
$menu->add_entry('Admin', 'ACH Test', 'm5nr.cgi?page=achtest');

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
$WebApp->layout->add_css('./Html/m5nr.css');
$WebApp->run();
