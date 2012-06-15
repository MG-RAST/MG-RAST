use strict;
use warnings;
no warnings 'once';

use FIG_Config;
use DBI;
use Data::Dumper;
use MGRAST::Metadata;
use DBMaster;
use WebApplicationDBHandle;
use Digest::MD5;
use CGI;
use Digest::MD5 qw(md5 md5_hex md5_base64);

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
    

    my $html = 0 ; 
    $html =1 if ($ENV{HTTP_USER_AGENT} =~/Mozilla/);

    print STDERR "HTML Output on" if ($html) ;

    my $meta             = MGRAST::Metadata->new();
    my $cgi              = CGI->new ;
    my $key              = $cgi->param('key');
    my $project          = $cgi->param('project') || '' ;
    my $pipeline_options = {} ;
    my $options          = {} ;
    my $sequence_type    = '16s' ;
  
    if ($html) {
	print $cgi->header('text/html') ;
	print $cgi->start_html( -title => 'Fine User Controlled Knockout' );
    }
    else{
	print $cgi->header('text/plain') ;
    }
    
    # user authentification
    my ( $user , $dbmaster , $msg , $error ) = &authentification($key);
    $options->{user} = $user ;

    if ($msg) {
	$html ? print_html($msg) : print $msg
    }
    
    foreach my $p ( $cgi->param){
	# print join "\t:" , $p , $cgi->param($p) , "\n" ;
    }

    

    # Read in text
    my $buffer ;
    $ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
    # print "Buffer : $buffer \n" ;
    # print "<pre>" ;
    # foreach my $k (keys %ENV){
	# print  join "\t" , $k , $ENV{$k} , "\n" ;
    #}
    #print "</pre>\n";
    if ($ENV{'REQUEST_METHOD'} eq "GET")
    {
	print "In progress\n";
    }
    elsif ($ENV{'REQUEST_METHOD'} eq "POST") {
	print "POST\n" ; 
	if ( defined $cgi->param('POSTDATA') ){
	    # print "\n" ,  $cgi->param('POSTDATA') , "\n" ;	    
	}
	else{
	    foreach my $p ($cgi->param){
		# print join "\t" , $p , $cgi->param($p) , "\n" ; 
	    }

	    # get file name here 
	    my $sample_name = $cgi->param('sample') || "unknown";
	    if ( $cgi->param('file') ){


		# get upload path and create directories
		my $upload_path = &upload_path($user , ($project || '') );
		my $filename = "$upload_path/".$user->_id . "-" ; 
		$filename .=  "qiime-". &timestamp ;
		
		open(FILE , ">$filename") or die "Can't open file $filename!\n";
		
		my $file = $cgi->param('file');
		while (<$file>) {
		    print FILE;
		}
		
		
		my $seq_stats  = {} ;
		my $stats = `$FIG_Config::seq_length_stats -fasta_file $filename` if (-f $filename) ;
		foreach my $line (split "\n" , $stats) {
		    my ($tag , $value) = split "\t" , $line ;
		    # print "$tag :: $value\n";
		    $seq_stats->{$tag} = $value ;
		}
		
		# get length filter cutoffs
		# Travis please
		if ($pipeline_options->{filter_ln}) {
		    $pipeline_options->{min_ln} = 0;
		    $pipeline_options->{max_ln} = 0;
		}
		
		my ($md5 , $f) = `md5sum $filename` =~/^\s*([^\s]+)\s*(\w+)/;
		
		unless($md5){
		    print "Soething wrong , can't compute md5 for $filename\n";
		    print STDERR "Something wrong , can't compute md5 for $filename\n";
		    exit;
		}
		
		
		my $job  = $meta->db->Job->reserve_job($user , $pipeline_options , $seq_stats);
		
		
		$msg .= $job->finish_upload($filename , $sequence_type) ; 
		
		$job->server_version(3) ;
		$job->name($sample_name);
		
		
		#clean up
		if ( -d $job->directory and -f $job->download_dir . "/" . $job->job_id . ".fna" ){
		    my $error = `rm $filename` ;
		} 
		else{
		print STDERR "Missing file " . $job->download_dir . "/" . $job->job_id . ".fna\n";
		
		#delete job object if creation failed

		print "ERROR , upload failed!\n";
		exit;
		}
		
		
			    
		print 	(($job and ref $job) ? "<id>" . $job->job_id . "</id>\n"  : '<id></id>\n' ) ;
		print "<md5>$md5</md5>\n";

		print STDERR (($job and ref $job) ? "<id>" . $job->job_id . "</id>\n"  : '<id></id>\n' ) ;
		print STDERR "<md5>$md5</md5>\n";
	
	    }
	}
    } 
    
    
    print $cgi->end_html() if ($html);
}


sub  print_html{ 
    my ($msg, $cgi) = @_ ;
    print "<pre>$msg</pre>" ;
}


sub authentification {
    my ($key) = @_ ;
    
    my $msg = '';
    my $dbmaster ;
    my $error = 0 ;
    my $user ;
    
    if ($key){	
	# initialize db-master
	($dbmaster, $error) = WebApplicationDBHandle->new();
	
	# check if we got a dbmaster
	if ($error) {
	    print $error."\n";
	    print STDERR $error."\n";
	    exit 0;
	}
	
	$user = WebApplicationDBHandle::authenticate_user($dbmaster, $key);
	unless ($user) {
	    $msg .= "authentication with key $key failed.\n";
	    print STDERR $msg ;
	}
    }
    else{
	$msg .= "No user authentification key given\n";
    }
    
    return ( $user , $dbmaster , $msg , $error ) ;
}

sub upload_path{
    my ($user , $prj) = @_;

    my $user_md5    =  md5_hex( $user->login );
    my $timestamp   =  &timestamp;
    
    my $base_dir    = "$FIG_Config::incoming";
    my $user_dir    = "$base_dir/$user_md5";
    my $upload_dir  = "$base_dir/$user_md5/" . ($prj ? $prj : $timestamp);

    create_dir($user_dir);
    create_dir($upload_dir);
    
    return $upload_dir ;
}

sub create_dir {
    my($dir) = @_;

    if ( -d $dir )
    {
	# check permissions
    }
    else
    {
	mkdir $dir or die "could not create directory '$dir'";
	chmod 0777, $dir;
    }
}
 
sub timestamp {
    
    my($sec, $min, $hour, $day, $month, $year) = localtime;

    $month += 1;
    $year  += 1900;

    $sec   = &pad($sec);
    $min   = &pad($min);
    $hour  = &pad($hour);
    $day   = &pad($day);
    $month = &pad($month);
    
    return join('.', $year, $month, $day, $hour, $min, $sec);
}

sub pad{
    my ($data) = @_ ;
    return ( $data=~/^\d$/ ? "0$data" : $data) ;
}
