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
use DBMaster;
use AnnoClearinghouse;
use FIG;

my 	$dbmaster = DBMaster->new(-database => 'WebAppBackend' ,
				  -backend  => 'MySQL',
				  -host     => 'bio-app-authdb.mcs.anl.gov' ,
				  -user     => 'mgrast',
				  );

my $fig = new FIG;

my $cgi = new CGI;                        # create new CGI object
print $cgi->header;                    # create the HTTP header
#     $cgi->start_html('hello world'), # start the HTML
#     $cgi->h1('hello world'),         # level 1 header
#     $cgi->end_html;                  # end the HTML


my $mode   = $cgi->param('mode')   | '';
my $login  = $cgi->param('login')  | '';
my $passwd = $cgi->param('passwd') | '';
my $expert = $cgi->param('expert') | '';


my $aclh = AnnoClearinghouse->new( $FIG_Config::clearinghouse_data , $FIG_Config::clearinghouse_contrib , 0 , $fig->db_handle);


# print "Params:\n" , join (" " , $cgi->param) , "\n";
# foreach my $key ( $cgi->param ){
#     print "$key\t".$cgi->param( $key )."\n";
# }



if ( $mode eq "get_assertions" ) {
    
    my $user_annotations = $aclh->get_all_user_annotations($expert);
    
    foreach my $var ( @$user_annotations ) {
	print join "\t" , @$var , "\n";
    }

}
elsif( $mode eq "load_assertions" ){

#	print "Load assertions\n";

    unless( $login and $passwd ) {
	print "Can not import file, invalid parameters\n";
#	exit;
    }

    my $file = "/tmp/upload.tmp";
    open(FILE , ">$file") or die "Can't open file!\n";

    if ( $cgi->param('file') ){
	my $filename = $cgi->param('file');
#	while (<$filename>) {
#	    print FILE;
#	}

	my $bad_list = [];
	print "Importing list for $login \n";
	my $result = $aclh->import_user_annotations($login, $filename, $bad_list);
	print "$result\n";
	# my @user_annotations = $aclh->get_all_user_annotations($login);
	# print "Done" , scalar @user_annotations,"\n";
    }
    else{
	print "No file\n";
    }

   close(FILE);
}
else{

    print "Nothing to do\n";

}
