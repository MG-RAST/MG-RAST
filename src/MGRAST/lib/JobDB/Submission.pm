package JobDB::Submission ;

use strict;
use warnings;
use Data::Dumper;

1;


sub _webserviceable {
    return 2;
}

sub _webservice_get_objects {
    my ($self, $params, $user) = @_;

    my $objects = {
	ID => 'test' , 
	name =>"2670" , #name for the metagenome
	type => 'amplicon' , #metagenome type , e.g. shotgun , amplicon  (is also in library)
	project=> '83' , #project ID
	sample => 'mgs2670', # sample ID
	library => 'mgl2670.15' , #library ID
	reads => 'mgm4457145.3' , # sequence_set ID
	options => {  #hash of run parameters
	    VAMPS => {
		domain => '' , #Archaeal, Bacterial, ...
		action => 'process' , #processing action receiver should take: store , process ?
		user => 'mgrast' , # 'user identification
		project_name_code => 'AW01' , # <PI initials>_<3 or 4 letter project code>
	    }
	    MGRAST => {
		dereplicate => '1' ,
		filter => '' ,
	    },
	    QIIME => {},
	};
	
    return bless $objects;
}
