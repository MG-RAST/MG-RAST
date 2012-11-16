#!/usr/bin/perl
use strict vars;
use warnings;
use Test::More ; #tests => 378;

use Getopt::Long;
use Carp;
use DBI;
use Time::localtime;
use Data::Dumper;

# local config
use lib "/homes/dsouza/public_html/MG-RAST/conf";
use lib "/homes/dsouza/public_html/MG-RAST/site/lib" ;
use lib "/homes/dsouza/public_html/MG-RAST/site/lib/PPO" ;
use lib "/homes/dsouza/public_html/MG-RAST/site/lib/Babel/lib" ;
use lib "/homes/dsouza/public_html/MG-RAST/site/lib/WebApplication" ;

#use Babel;
use DBMaster;
use WebApplicationDBHandle;
use MGRAST::Analysis_old;
use MGRAST::Analysis_db2;

use Conf;

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


my $mgids = [] ;




my ($dbm, $error) = WebApplicationDBHandle->new();

my $user = WebApplicationDBHandle::authenticate_user($dbm, $key);
if ($user) {
  print STDERR "authenticated as ".$user->firstname . " " . $user->lastname . " (" . $user->login . ")\n";
} else {
  print STDERR "authentication with key $key failed.\n";
}

$dbm->{_user} = $user ;

my $mgrast_jobcache_db       = $Conf::mgrast_jobcache_db;
my $mgrast_jobcache_host     = $Conf::mgrast_jobcache_host;
my $mgrast_jobcache_user     = $Conf::mgrast_jobcache_user;
my $mgrast_jobcache_password = $Conf::mgrast_jobcache_password;

my $job_dbh = DBMaster->new( -database => $mgrast_jobcache_db , 
                             -host     => $mgrast_jobcache_host,
                             -user     => $mgrast_jobcache_user,
                             -password => $mgrast_jobcache_password );


# Initialize analysis objects

# Analysis DB 
my $analysis_db         = $Conf::mgrast_db;
my $analysis_dbms       = $Conf::mgrast_dbms;
my $analysis_dbuser     = $Conf::mgrast_dbuser;
my $analysis_dbhost     = $Conf::mgrast_dbhost;
my $analysis_dbpassword = $Conf::mgrast_dbpassword;

my $analysisDBH = DBI->connect("DBI:$analysis_dbms:dbname=$analysis_db;host=$analysis_dbhost", $analysis_dbuser, $analysis_dbpassword, 
			       { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
  die "database connect error.";


# Analysis2 DB 
my $analysis2_db         = $Conf::analysis2_db;
my $analysis2_dbms       = $Conf::analysis2_dbms;
my $analysis2_dbuser     = $Conf::analysis2_dbuser;
my $analysis2_dbhost     = $Conf::analysis2_dbhost;
my $analysis2_dbpassword = $Conf::analysis2_dbpassword;

my $analysis2DBH = DBI->connect("DBI:$analysis2_dbms:dbname=$analysis2_db;host=$analysis2_dbhost", $analysis2_dbuser, $analysis2_dbpassword,
				{ RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
  die "database connect error.";


#
# Initialize Analysis Objects and test them
#

my $analysisDB  = MGRAST::Analysis_old->new( $job_dbh , $analysisDBH ) ;
my $analysis2DB = MGRAST::Analysis_db2->new(  $job_dbh , $analysis2DBH );


=pod

=head1 Testing Plan

=head2 Testing always object/instance retrieval 

=over

=item Create new object

=back

=cut



my @tests = ();
my $testCount = 0;
my $maxTestNum = 2;  # increment this each time you add a new test sub.


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




# foreach my $num (@tests) {
#        my $test = "test" . $num;
#        &$test();
#        $testCount++;
# }


foreach my $num (@tests){
  my $test = "test$num";
  subtest "Subtest $num" => \&$test;
  $testCount++;
}

done_testing($testCount);
teardown();



sub setup{
  my ($class, $job_dbh) = @_;
}


# write your tests as subroutnes, add the sub name to @tests


#
#  Test - Are the methods valid?
#

sub test1 {
  my ($tmp) = @_ ;
  
  # set name for testing block
  my  $bname = "Basic functions" ;
  
  note("TEST $bname"); 
#  plan tests => 7 ; 

  my @methods = qw[new DESTROY dbh ach jcache jobs expire has_job add_jobs set_jobs set_public_jobs get_jobid_map get_jobs_tables get_seq_count job_dir analysis_dir fasta_file sim_file source_stats_file taxa_stats_file ontology_stats_file rarefaction_stats_file qc_stats_file length_hist_file gc_hist_file org_tbl func_tbl md5_tbl ontol_tbl lca_tbl get_all_job_ids get_where_str run_fraggenescan get_source_stats file_to_array get_taxa_stats get_ontology_stats get_rarefaction_coords get_qc_stats get_histogram_nums get_md5_sims nCr2ln gammaln get_sources md5_abundance_for_annotations sequences_for_md5s sequences_for_annotation metagenome_search all_read_sequences md5s_to_read_sequences get_abundance_for_organism_source get_organism_abundance_for_source get_organisms_with_contig_for_source get_md5_evals_for_organism_source get_md5_data_for_organism_source get_rarefaction_curve get_abundance_for_tax_level get_abundance_for_ontol_level get_abundance_for_hierarchy get_abundance_for_set get_rank_abundance get_set_rank_abundance get_global_rank_abundance search_organisms get_organisms_unique_for_source get_organisms_for_sources get_organisms_for_md5s search_ontology get_ontology_for_source get_ontology_for_md5s get_functions_for_sources get_functions_for_md5s get_lca_data get_md5_data get_md5_abundance get_org_md5 get_ontol_md5 get_md5s_for_tax_level get_md5s_for_organism get_md5s_for_ontol_level get_md5s_for_ontology];

  can_ok($analysisDB , @methods);

  my @methods_2 = qw[new DESTROY _dbh _ach _jcache _expire add_jobs set_jobs set_public_jobs get_all_job_ids get_source_stats get_taxa_stats get_ontology_stats get_rarefaction_coords get_qc_stats get_histogram_nums get_md5_sims get_sources md5_abundance_for_annotations sequences_for_md5s sequences_for_annotation metagenome_search all_read_sequences md5s_to_read_sequences get_abundance_for_organism_source get_organism_abundance_for_source get_organisms_with_contig_for_source get_md5_evals_for_organism_source get_md5_data_for_organism_source get_rarefaction_curve get_abundance_for_tax_level get_abundance_for_ontol_level get_abundance_for_set get_rank_abundance get_set_rank_abundance get_global_rank_abundance search_organisms get_organisms_unique_for_source get_organisms_for_sources get_organisms_for_md5s search_ontology get_ontology_for_source get_ontology_for_md5s search_functions get_functions_for_sources get_functions_for_md5s get_lca_data get_md5_data get_md5_abundance get_org_md5 get_ontol_md5 get_md5s_for_tax_level get_md5s_for_organism get_md5s_for_ontol_level get_md5s_for_ontology];

  can_ok($analysis2DB ,@methods_2);

  ok ( (ref $analysisDB->dbh eq 'DBI::db' and ref $analysis2DB->_dbh eq 'DBI::db') , 'Got DB Handles' ) ;
  ok ( (ref $analysisDB->ach eq 'Babel::lib::Babel' and ref $analysis2DB->_ach eq 'Babel::lib::Babel') , 'Got ACH Handles') ; 
  ok ( (ref $analysisDB->jcache eq 'DBMaster' and ref $analysis2DB->_jcache eq 'DBMaster') , 'Got jcache Handles') ; 

# skip jobs test:
# $analysisDB->jobs is a hash
# $analysis2DB->jobs is an array
#
#  unless (ok ( (Dumper $analysisDB->jobs) eq (Dumper $analysis2DB->jobs) , 'Identical jobs') ){
#    print STDERR join "\t" , "Error(jobs):\n" , $analysisDB->jobs , (Dumper  $analysisDB->jobs) ,  $analysis2DB->jobs , (Dumper  $analysis2DB->jobs);
#  }

  ok ( $analysisDB->expire eq $analysis2DB->_expire , 'same expire') ;

}


#
# Test jobs methods
#

sub test2{
  
  # set name for testing block
  my  $bname = "job methods" ;
  
  note("TEST $bname"); 
  plan tests => 1 ; 

#  my @methods = qw[jobs has_job add_jobs set_jobs set_public_jobs get_jobid_map get_jobs_tables job_dir get_all_job_ids];
  my @methods = qw[set_public_jobs]; #get_jobid_map get_jobs_tables job_dir get_all_job_ids];

  my @test_ids = qw[ 4440051.3 4440052.3 ];
 
  # Test without job ids
  foreach my $method (@methods){

    my $res1 = undef ;
    my $res2 = undef ;

    eval{
      $res1 =  $analysisDB->$method;
      $res2 =  $analysis2DB->$method;
    };
    
    is($@, '', "Method $method without jobs works (".$@.")");
    unless($@){
      ok ( (Dumper $res1) eq (Dumper $res2) , "Identical output for method $method and no jobs");
    }
  }

  # Test with job ids
  foreach my $method (@methods){

    my $res1 = undef ;
    my $res2 = undef ;

    eval{
      $res1 =  $analysisDB->$method(\@test_ids) ;
      $res2 =  $analysis2DB->$method(\@test_ids);
    };
    
    is($@, '', "Method $method with jobs ".  (join "," , @test_ids ) ." works (".$@.")");
    unless($@){
      ok ( (Dumper $res1) eq (Dumper $res2) , "Identical output for method $method and jobs " . (join "," , @test_ids ));
    }
  }



}





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

