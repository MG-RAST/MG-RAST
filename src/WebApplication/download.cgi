use strict;
use warnings;
use CGI;

my $cgi = new CGI();

my $fn = $cgi->param('filename');
my $content = $cgi->param('content');

print "Content-Type:application/x-download\n";  
print "Content-Length: " . length($content) . "\n";
print "Content-Disposition:attachment;filename=$fn\n\n";
print $content;
