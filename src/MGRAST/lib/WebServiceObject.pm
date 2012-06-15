package WebServiceObject;

use DBMaster;
use FIG_Config;

sub db_connect {
    my $jobdb = DBMaster->new( -database => $FIG_Config::mgrast_jobcache_db || 'JobDB',
			       -host     => $FIG_Config::mgrast_jobcache_host,
			       -user     => $FIG_Config::mgrast_jobcache_user,
			       -password => $FIG_Config::mgrast_jobcache_password );
    
    return ($jobdb, undef);
}

1;
