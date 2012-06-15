package WebServiceObject;

use DBMaster;
use Config;

sub db_connect {
    my $jobdb = DBMaster->new( -database => $Config::mgrast_jobcache_db || 'JobDB',
			       -host     => $Config::mgrast_jobcache_host,
			       -user     => $Config::mgrast_jobcache_user,
			       -password => $Config::mgrast_jobcache_password );
    
    return ($jobdb, undef);
}

1;
