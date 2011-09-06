use strict;
use warnings;
use FIG;
use WebApplicationDBHandle;
use DBMaster;

my $db = DBMaster->new(-database => 'WebAppBackend' ,
		       -backend  => 'MySQL',
		       -host     => 'bio-app-authdb.mcs.anl.gov' ,
		       -user     => 'mgrast',); 





my $query = "select md5 , id , function , expert from ACH_Assertion";

my $fig = new FIG;
my $dbf = $fig->db_handle;	
my $assertions = $dbf->SQL( $query );

my $user = {};

foreach my $row (@$assertions){
    my $login = $row->[3];
    unless ($user->{ $login } ){
	$user->{ $login } = &get_user($db , $login);
    }
    $row->[3] = $user->{ $login };
    
    print join "\t" , @$row , "\n";
    
}





sub get_user{
  my ($db , $login) = @_;
  my $user = $db->User->init({ login => $login });
  my $name = "unknown" ;
  $name =  $user->firstname.' '.$user->lastname if (ref $user);
  return $name;
}
