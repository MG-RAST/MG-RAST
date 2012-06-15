use CGI;
use JSON;

use FIG_Config;

use WebApplicationDBHandle;
use DBMaster;

use strict;
use warnings;
use Data::Dumper ;

# create cgi and json objects
my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

# get upload path from config
my $incoming = "" ; # "/mcs/bio/mg-rast/uploads/" ;


# get request method
$ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
my $request_method = $ENV{'REQUEST_METHOD'};

# get REST parameters
my $abs = $cgi->url(-relative=>1);
if ($abs !~ /\.cgi/) {
    $abs = $cgi->url(-base=>1);
}
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\/?//;
my @rest_parameters = split m#/#, $rest;


# get the resource
my $user_dir = shift @rest_parameters;

# get CGI parameters
my @cgi_names = $cgi->param;
my $cgi_parameters = {};
%$cgi_parameters = map { $_ => $cgi->param($_) } @cgi_names;



unless ( $user_dir and -d $incoming.$user_dir) {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: upload directory not found ($user_dir)";
    exit 0;
}


# check for auth parameter and aquire request body
my $request_body;
my $auth;
if ($ENV{'REQUEST_METHOD'} eq "POST") {
    $request_body = $cgi->param('POSTDATA');
    
    if($cgi->upload()){
	print Dumper $cgi->upload ;
	exit;
    }
    if($cgi->upload('file')){
	my $fh = $cgi->upload('file');
	$fh =~ m/([^\/]*)$/; # strip the remote path and keep the filename 
	my $name = $1;
	
	if (-d "$incoming/$user_dir"){
	    
	    open(FILE , ">$incoming/$user_dir/$name") or die "Problem in open file $incoming/$user_dir/$name for writing!" ;
	    
	    while (my $line = <$fh> ){
		
		print FILE $line ;
		
	    }
	}
	else{
	    print $cgi->header(-type => 'text/plain',
			       -status => 500,
			       -Access_Control_Allow_Origin => '*' );
	    print "ERROR: no upload directory";
	    exit 0;
	}
    }
 
    
    # start processing
}

sub TO_JSON { return { %{ shift() } }; }

1;
