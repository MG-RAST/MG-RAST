#!/usr/bin/env perl

BEGIN {
    unshift @INC, qw(
              /Users/jared/gitprojects/MG-RAST/site/lib
              /Users/jared/gitprojects/MG-RAST/site/lib/WebApplication
              /Users/jared/gitprojects/MG-RAST/site/lib/PPO
              /Users/jared/gitprojects/MG-RAST/site/lib/MGRAST
              /Users/jared/gitprojects/MG-RAST/conf
	);
}
use Data::Dumper;
use FIG_Config;
# end of tool_hdr
########################################################################
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
