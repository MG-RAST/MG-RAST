#!/kb/runtime/bin/perl
use strict vars;
use warnings;
use Test::More ; #tests => 378;

use Getopt::Long;
use Carp;
use DBI;
use Time::localtime;
use Data::Dumper;

# local config
use lib "/Users/Andi/Development/MG-RAST/conf";
use lib "/Users/Andi/Development/MG-RAST/site/lib" ;
use lib "/Users/Andi/Development/MG-RAST/site/lib/PPO" ;
use lib "/Users/Andi/Development/MG-RAST/site/lib/Babel/lib" ;
use lib "/Users/Andi/Development/MG-RAST/site/lib/WebApplication" ;

#use Babel;
use DBMaster;
use WebApplicationDBHandle;
use MGRAST::Analysis;
use MGRAST::Analysis_db2;

use constant DEFAULT_RANGE => 2 ;



my $key ;
my $mid = '4443362.3';

GetOptions ( 'key=s'         => \$key ,
             'metagenome=s'  => \$mid ,
           );

unless ($key) {
  print STDERR "No auth key provided!\n";
  exit 0;
}




# Analysis DB 
my $analysis_db         = "mgrast_analysis";
my $analysis_dbms       = "Pg";
my $analysis_dbuser     = "mgrastprod";
my $analysis_dbhost     = "kursk-3.mcs.anl.gov";
my $analysis_dbpassword = '';

my $analysisDB = DBI->connect("DBI:$analysis_dbms:dbname=$analysis_db;host=$analysis_dbhost", $analysis_dbuser, $analysis_dbpassword, 
			      { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
  die "database connect error.";

# Analysis2 DB 
my $analysis2_db         = "mgrast_analysis";
my $analysis2_dbms       = "Pg";
my $analysis2_dbuser     = "mgrastprod";
my $analysis2_dbhost     = "kharkov-1.igsb.anl.gov";
my $analysis2_dbpassword = '' ;


my $analysis2DB = DBI->connect("DBI:$analysis2_dbms:dbname=$analysis2_db;host=$analysis2_dbhost", $analysis2_dbuser, $analysis2_dbpassword, 
			       { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
  die "database connect error.";



my $jobDB   = DBMaster->new( -database => 'JobDB',
			     -host     => "kursk-3.mcs.anl.gov",
			     -user     => "mgrast",
			     -password => "");


my $mgids = [] ;





my ($dbm, $error) = WebApplicationDBHandle->new();

my $user = WebApplicationDBHandle::authenticate_user($dbm, $key);
if ($user) {
  print STDERR "authenticated as ".$user->firstname . " " . $user->lastname . " (" . $user->login . ")\n";
} else {
  print STDERR "authentication with key $key failed.\n";
}

$dbm->{_user} = $user ;

my $job_dbh = DBMaster->new( -database => $FIG_Config::mgrast_jobcache_db , 
                             -host     => $FIG_Config::mgrast_jobcache_host,
                             -user     => $FIG_Config::mgrast_jobcache_user,
                             -password => $FIG_Config::mgrast_jobcache_password );




my $babel = Babel::lib::Babel->new();
my $mg    =  MGRAST::MetagenomeAnalysis2->new($job_dbh->db_handle);





=pod

=head1 Testing Plan

=head2 Testing always object/instance retrieval 

=over

=item Create new object

=back

=cut



my @tests = ();
my $testCount = 0;
my $maxTestNum = 4;  # increment this each time you add a new test sub.


# keep adding tests to this list
unless (@ARGV) {
       for (my $i=1; $i <= $maxTestNum; $i++) {
               push @tests, $i;
       }
}

else {
       # need better funtionality here
       @tests = @ARGV;
}

# do anything here that is a pre-requisiste
my ($client) = setup();




foreach my $num (@tests) {
       my $test = "test" . $num;
       &$test($client);
       $testCount++;
}

done_testing($testCount);
teardown();

# write your tests as subroutnes, add the sub name to @tests


#
#  Test - Are the methods valid?
#

sub test1 {

    
}


# Test - Abundance Profile



# initialize db-master








# this should be called after all tests are done to clean up the filesystem, etc.
sub teardown {
}










#----------------------------------------------------------------------------
#
#  Test the returned results
#	1.	Test for an error
#	2.	Test that the returned attribute is expected
#	3.	Test that the returned attribute is the right type
#	4.	If verbosity is 'full' make sure that all of them returned
#

