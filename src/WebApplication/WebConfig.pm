package WebConfig;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw ( CSS_PATH TMPL_PATH JS_PATH IMAGES HMTL_PATH CGI_PATH TEMP_PATH TMPL_URL_PATH );
use Conf;

1;

#******************************************************************************
#* GLOBAL CONFIGURATION
#******************************************************************************

#
# File system path configurations.
#
use constant TMPL_PATH  => "$Conf::html_base/";
use constant TMPL_URL_PATH  => "./Html/";
use constant CFG_PATH   => "";
use constant TEMP_PATH  => $Conf::temp;
#
# URL path configurations.
#
use constant CGI_PATH   => "$Conf::cgi_url/";
use constant CSS_PATH   => "$Conf::cgi_url/Html/";
use constant JS_PATH    => "$Conf::cgi_url/Html/";
use constant IMAGES     => "$Conf::cgi_url/Html/";
use constant HTML_PATH  => "$Conf::cgi_url/Html/";

#
# Database settings
#
our $DBNAME = 'WebAppBackend';
our $DBHOST = 'localhost';
our $DBUSER = 'root';
our $DBPWD  = '';
our $DBPORT = undef;
our $NODB   = undef;
#
# Default values for the web application
#
our $APPLICATION_NAME = 'MG-RAST';
our $APPLICATION_URL  = "$Conf::cgi_url/";
our $ADMIN_EMAIL = 'mg-rast@mcs.anl.gov';

#
# Login dependencies are used to grant login rights
# to web applications a backend depends on. 
# rf. to User->grant_login_right
#
our $LOGIN_DEPENDENCIES = { 'MGRAST'     => [] };


#
# Method to import local configurations 
# from config/WebApplication/BackendName.cfg
#
sub import_local_config {
  my $application = shift;
  if (ref($application)) {
    $application = $application->backend->name();
  }
  no strict;
  {
    my $local = CFG_PATH.$application.'.cfg';
  }
}
