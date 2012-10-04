package WebServiceObject;

use DBMaster;
use Conf;

sub db_connect {
    my $jobdb = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobDB',
			       -host     => $Conf::mgrast_jobcache_host,
			       -user     => $Conf::mgrast_jobcache_user,
			       -password => $Conf::mgrast_jobcache_password );
    
    return ($jobdb, undef);
}

1;
