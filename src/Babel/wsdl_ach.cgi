#__perl__



use strict;
use warnings;
use lib '/home/redwards/perl/lib/perl5/site_perl/5.8.7/';
use Pod::WSDL;
use CGI::Carp qw(fatalsToBrowser);
use CGI qw(header);
my $url=$Config::cgi_url . "/webservices_ACH.cgi";


my $p = new Pod::WSDL(source => 'webservices_ACH.cgi', 
	location => $url,
	pretty => 1,
	withDocumentation => 1);

print header('text/plain'), $p->WSDL;
