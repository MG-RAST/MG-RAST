use strict;
use warnings;
no warnings 'once';


use DBI;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use XML::Simple;
use CGI;

use MGRAST::Metadata;
use DBMaster;
use WebApplicationDBHandle;
#use MGRAST::CreateV2Job;
use FIG_Config;

my $t ="services.cgi";

eval {
    &main;
};

if ($@)
{
    my $cgi = new CGI();
    print $cgi->header() , $cgi->start_html() ;  
    # print out the error
    print '<pre>'.$@.'</pre>';
    print $cgi->end_html();

}

sub main {
    
    my $cgi = CGI->new ;
    
    my $key = $cgi->param('key');
    my $html = 0 ; 
    my @data ;
    my $msg = '' ;
    my $options = {};
    my $qiime =  $ENV{HTTP_USER_AGENT} =~/qiime/i ;
   
    my ( $user , $dbmaster , $error ) ;
     

    $ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
    $html =1 if ($ENV{HTTP_USER_AGENT} =~/Mozilla/);

    #if ($qiime) { print STDERR "QIIME call\n" } ;

    # print STDERR "HTML Output on" if ($html) ;

    #init db connections
    my $meta   = MGRAST::Metadata->new();
  


    # init header
    if ($html) {
	if($cgi->param('rest') =~/raw/){
	    #print $cgi->header('application/x-download') ;
	    print "Content-Type:application/x-download\n";  
	}
	else{
	    print $cgi->header('text/html') ;
	    print $cgi->start_html( -title => 'Fine User Controlled Knockout' );
	}
    }
    else{
	print $cgi->header('text/xml') ;
    }

    my $procedure = { debug       => \&print_debug ,
		      study       => \&study ,
		      sample      => \&sample ,
		      preparation => \&sequence_prep ,
		      prep        => \&sequence_prep ,
		      reads       => \&reads ,
		      sequence    => \&reads ,
		      register    => \&register ,
    };

    if ( defined $cgi->param('POSTDATA') or  ($ENV{'REQUEST_METHOD'} eq "POST" ) ){
	my @params = split "&" , $ENV{QUERY_STRING} ;
	foreach my $param (@params){
	    my ($key , $value) = split "=" , $param ;
	    $cgi->param($key , $value) unless ($cgi->param($key) );
	}
	#print  $cgi->param('POSTDATA') ;
	# print STDERR "Method : " . $ENV{'REQUEST_METHOD'} . "\n";
    }

    # walk through options
    if ($cgi->param('rest')){
	my $path = $cgi->param('rest') ;
	$path =~ s/^service\///;
	my @options = split "/" , $path ;

	my $opt = shift @options ;

	# user authentification
	if ($opt and length($opt) == 25 ){
	    # user authentification
	    ( $user , $dbmaster , $msg , $error ) = &authentification($opt);
	    $meta->db->{_user} = $user;
	    if ($error or !(ref $user)){
		print_html($msg) ;
		exit;
	    }
	    #print $user->login , "\n" ;
	    $options->{user} = $user ;
	    $opt = shift @options ;
	}
	
	if ($opt) {
	    #print STDERR "$opt\t" , length($opt) , "\n";
	    if ($opt =~ /debug/){
		print_debug($html , $cgi);
	    }
	    else{
		
		if ( $ENV{'REQUEST_METHOD'} =~/post/i and not ref $user){
		    #print STDERR "Calling POST without user!\n";
		    $msg .= "Trying to upload data without valid identification.\n" ;
		}
		elsif (exists $procedure->{ $opt } ){
		    my ($message , $data ) = $procedure->{ $opt }(  { method          =>  $ENV{'REQUEST_METHOD'} , 
								      metadata_handle => $meta , 
								      params          => \@options , 
								      user            => $user ,
								      cgi             => $cgi,
								      master          => $dbmaster,
								    }) ;
		    push @data , $data ;
		    $msg .= $message ;
		}
		else{
		    print "Service ". $opt ." does not exists!\n";
		}
	    }
	}
    }
    else{
	print STDERR "$t: Missing cgi param rest\n";
	foreach my $k ($cgi->param){
	    print "$k\t".$cgi->param($k)."\n";
	}
	print_debug($msg . "\n" . $html , $cgi ) ;
    }
    
    
    $html ? print_html($msg) : print $msg ;
    $html ? print_html( join "\n" , @data ) : print join"\n" , @data  ;
   
    exit 1;
}


sub  print_html{ 
    my ($msg, $cgi) = @_ ;
    print "<pre>$msg</pre>" ;
}

sub print_debug{
    my ($html , $cgi) = @_ ;
    
    my $msg = '' ;
    
    $msg .= "CGI:\n\n" ;
    if ($cgi and ref $cgi){
	foreach my $p ($cgi->param){
	    $msg .= join "\t" , $p , $cgi->param($p) , "\n" ; 
	}
    }
    else{
	$msg .= "no cgi\n";
    }

    $msg .= "\nENV:\n\n";
     foreach my $k (keys %ENV){
	$msg .=  join "\t" , $k , $ENV{$k} , "\n" ;
    }

    $html ? print_html($msg) : print $msg ;

    return 1;
}

sub authentification {
    my ($key) = @_ ;
    
    my $msg = '';
    my ( $dbmaster , $user ) ;
    my $error = 0 ;
    
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
	    print STDERR $msg ; }
    }
    else{ $msg .= "No user authentification key $key given\n"; }
    
    return ( $user , $dbmaster , $msg , $error ) ;
}


# services
# study          GET  get all study ids a user has access to
#                PUT  create new study
# study/id/1234/ GET  get study for id
#                POST update study 

sub study {
    my ($params) = @_ ;
 
    my $method = $params->{method} ;
    my $meta   = $params->{metadata_handle};
    my $opts   = $params->{params} ;
    my $user   = $params->{user};
    my $cgi    = $params->{cgi} ;
    my $master = $params->{master} ;


  
    my $data   = '' ;
    my $msg    = '' ;
    my $tag    = '' ;
    
    if ($opts and @$opts){
	$tag = shift @$opts ;
    }

    # get global ids/all public ?
    if ( $method eq "GET" ){
	
	if ( $tag eq "id" ){
	    
	    my $value = shift @$opts ;
	    #print "ID\t$value\n";
	    return ( "missing value for id"  , '') unless ($value);
	    
	    my $prjs ;
	    if ($user){
		
		my $prj = $meta->db->Project->init( { id => $value });
		if ( $user->has_right(undef, 'view' , 'project', $value ) or ( $prj->public and $prj->type eq "project" ) ){
		    push @$prjs , $prj ;
		}
		else{
		    $msg  .= "<success>0</success>\n<error>you don't have the right to view project $value</error>" ;
		}
	    }
	    else{
		$prjs = $meta->db->Project->get_objects( { id => $value , public => 1 , type => 'project' });
	    }
	    
	    my $action = scalar @$opts ? shift @$opts : '' ;
	    foreach my $prj (@$prjs){
		if($action){
		    if ($action eq "raw"){
			my $id = $prj->id ;	
			print "Content-Disposition:attachment; filename=project-" . $id . ".raw.tar;\n\n";
			print `cd /mcs/bio/ftp/mg-rast/metagenomes/ ; tar cf - $id/*/raw/* $id/*/meta* $id/meta*` ;
			exit;
		    }
		}
		else{
		    $data .= $prj->xml ;
		}
	    }
	    
	}
	else{
	    my $ids = $meta->get_projects ;
	    $data .= join "\n" , "<projects>" , (map { "<project_id>".$_."</project_id>" } @$ids ) , "</projects>" ;
	}
    }
    elsif( $method eq "POST"){ 
   
	my ($s , $e , $ids) = create_study( $master , $meta , $user , $cgi->param('POSTDATA') ) ; 
	$msg  .= "<success>$s</success>\n<error>$e</error>" ;
	if ($ids and scalar @$ids){
	    foreach my $id (@$ids){
		$data .= "<project_id>$id</project_id>" ;
	    }
	}
    }
    elsif ( $method eq "PUT" ){
	$msg  .= "<success>0</success>\n<error>not implemented</error>" ;
    }
    elsif ( $method eq "DELETE"){
	$msg  .= "<success>0</success>\n<error>not implemented</error>" ;
    }
    
    # Called post or put without parameters
    else{ 
	$msg  .= "<success>0</success>\n<error>Missing arguments for $method</error>" ;
        return ($msg , '') ;
    }
    
    return ($msg , "\n<data>".$data."\n</data>") ;
}


sub create_study {
    my ($master , $meta , $user , $data) = @_ ;
    my $success  = 1 ;
    my $error    = 0 ;
    my @study_ids ;
    
    # parse xml structure
    my $xs = XML::Simple->new();
    my $block = $xs->XMLin( $data , ForceArray => [ 'study' , 'sample' , 'study_id' ]);
    
    $data .= Dumper $block ;
   
    
    # single study without <daba_block>
    push @{ $block->{study} } , $block unless ($block->{study}) ;

    foreach my $study ( @{ $block->{study} } ){
	
	my $project ;
	
	# study name must exists
	return ( 0 , 'no study name', \@study_ids  ) unless ( $study->{study_name} ) ;
	# check for existing project name
	if  ($project = $meta->db->Project->init( { name => $study->{study_name} }) ){
	    
	    
	    print STDERR "$t: Duplicate project name " . $study->{study_name} . "\n" ;
	    
	    if ($user and $user->has_right(undef, 'edit' , 'project', $project->id )){
		print STDERR "$t: deleting project metadata\n";
		map { $_->delete } @{ $meta->db->ProjectMD->get_objects( { project => $project } ) };
		
	    }
	    else{
		push @study_ids , $project->id ;
		return ( 0 , 'duplicate project name ' . $study->{study_name} , \@study_ids  ) ;
	    }
	}

	# get curator
	my $curator ;
	my $curators = $meta->db->Curator->get_objects( { user => $user } ) ;
	# not a Curator , create one
	unless(ref $curators and scalar @$curators){
	    my $curator = $meta->db->Curator->create( { user  => $user ,
							name  => $user->firstname . " " . $user->lastname ,
							email => $user->email ,
							type  => $study->{submission_system} || '' ,
							url   => '' ,
							ID    => $user->_id ,
						      });
	    
	    unless($curator and ref $curator){
	    print STDERR "Can't creat Curator for user " . $user->login ;
	    exit;
	    }
	
	}
	else{
	    $curator = $curators->[0] ;
	}
	

	my $id      =  ($meta->db->Project->last_id) + 1 ;

	unless($project and ref $project){
	    $project =  $meta->db->Project->create( { creator => $curator , 
						      id      => $id , 
						      name    => $study->{study_name} , 
						      public  => 0 , 
						      type    => 'project' ,
						    } ) ;
	    
	    # create right for new project
	    my $view_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							data_type => 'project', 
							data_id   => $id , 
							name      => 'view', 
							granted   => 1 ,
						  } );
	    my $edit_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							data_type => 'project', 
							data_id   => $id , 
							name      => 'edit', 
							granted   => 1 ,
						      } );
	}
	
	push @study_ids ,  $project->id ;
	
	# preserve study id
	#$study->{metadata}->{study_id} = $study->{ study_id } ;
	foreach my $id (@{ $study->{study_id} } ){
	    $study->{metadata}->{id} = ( $id->{namespace} ?  $id->{namespace} . ":" . $id->{content} : $id->{content} ) ;
	}
	
	#add tag , value pairs
	foreach my $tag (keys %{$study->{metadata}}){
	    if (ref  $study->{metadata}->{$tag}){
		$error .= "invalid/complex data structure for key $tag , skipping entry!\n";
		print STDERR "$t: " . ( Dumper $study->{metadata}->{$tag} ) , "\n";
		next;
	    }

	    my $pmd = $meta->db->ProjectMD->create( { project => $project ,
						      tag     => $tag ,
						      value   => $study->{metadata}->{$tag} ,
						    } ) ;
	}
	
    }
    return ( $success , $error ,\@study_ids ) ;
}


sub sample {
    my ($params) = @_ ;
    
    my $method = $params->{method} ;
    my $meta   = $params->{metadata_handle};
    my $opts   = $params->{params} ;
    my $user   = $params->{user};
    my $cgi    = $params->{cgi} ;
    my $master = $params->{master} ;


    
    my $data   = '' ;
    my $msg    = '' ;
    my $tag    = '' ;
    
    if ($opts and @$opts){
	$tag = shift @$opts ;
    }

    # get global ids/all public ?
    if ( $method eq "GET" ){
	my $samples = [] ;
	
	if ( $tag eq "id" ){
	    



	    if ($user){
		my $value = shift @$opts ;
		
		if ( $value and $user->has_right(undef, 'view' , 'sample', $value ) ){
		    $samples = $meta->db->MetaDataCollection->get_objects( { ID => $value } );
		}
		else{
		    $msg  .= "<success>0</success>\n<error>you don't have the right to view sample $value</error>" ;
		}
	    }
	    else{
		$msg  .= "<success>0</success>\n<error>no public samples defined</error>" ;
	    }
	    
	    foreach my $sample (@$samples){
		    $data .= $sample->xml ;
	    }

	   
	}
	elsif ($tag){

	}
	else{
	   # my $ids = $meta->get_samples ;
	}
    }
    elsif( $method eq "POST"){ 
	if ($user){
	    $data .= $cgi->param('POSTDATA') ;
	    #print STDERR "Creating Samples\n";
	    my ($s , $e , $ids) = create_sample($master , $meta , $user , $cgi->param('POSTDATA') ) ; 
	    #print STDERR scalar @$ids . " Samples Created.\n";
	    $msg  .= "<success>$s</success>\n<error>$e</error>" ;
	    foreach my $id (@$ids){
		$data = "<sample_id>$id</sample_id>\n";
	    }
	}
    }
    
    # Called post or put without parameters
    else{ $msg .= "Missing arguments for $method" ; return ($msg , '') }
       
    return ($msg , "\n<data>".$data."\n</data>") ;

};


sub create_sample {
    my ($master , $meta , $user , $data) = @_ ;
    my $success  = 1 ;
    my $error    = 0 ;
    my $msg      = '';
    my @sample_ids ;
    my $collection ;
    

    # parse sample xml
    my $xs = XML::Simple->new();
    my $block = $xs->XMLin( $data , ForceArray => [ 'study' , 'sample' , 'sample_id' , 'study_id' ]);
  
    # single study without <daba_block>
    push @{ $block->{sample} } , $block unless ($block->{sample}) ;


    foreach my $sample ( @{ $block->{sample} } ){
    
	# get curator
	my $curator ;
	my $curators = $meta->db->Curator->get_objects( { user => $user } ) ;
	# not a Curator , create one
	unless(ref $curators and scalar @$curators){
	    my $curator = $meta->db->Curator->create( { user  => $user ,
							name  => $user->firstname . " " . $user->lastname ,
							email => $user->email ,
							type  => $sample->{submission_system} || '' ,
							url   => '' ,
							ID    => "R". $user->_id ,
						      });
	    
	    unless($curator and ref $curator){
		print STDERR "Can't creat Curator for user " . $user->login ;
		exit;
	    }
	    
	}
	else{
	    $curator = $curators->[0] ;
	}
	
	
	# get project
	my $project = '';
	my $pid     = $sample->{ project_id } || 0 ;
	
	# check for mgrast project id
	unless($pid){ 
	    foreach my $p (@{ $sample->{study_id} }){
		$pid = $p->{content} if ($p->{namspace} =~/mgrast|mg-rast/i);
	    }
	}
	if ( $pid and $user->has_right(undef, 'edit' , 'project', $pid ) ){
	    $project =   $meta->db->Project->init( { id => $pid } ) ;
	}
	else{
	    $msg .= "no project id or no rights to edit project" . ( $pid ? "($pid)\n" : '') ;
	}


	# check for existing meta data / qiime will submit samples twice

	
	my $cids    = {} ;
	# number of all metadata fields
	my $nr_tags = keys %{$sample->{metadata}} ;
	
	# sample ids 
	my @sids ;
	if (  @{$sample->{ study_id }} ){
	    $sample->{metadata}->{study_id}    = join ";" , map { $_->{namespace} .":". $_->{content} } @{$sample->{ study_id }};
	}

	if (  @{$sample->{ sample_id }} ){
	    print STDERR "Dear tharriso we found samples\n"; 
	    print STDERR "Dear tharriso please go to www.newcarforall.com to make your donation today.\n"; 

	    my @cids;
	    map { push @cids , $_->{content} if ($_->{namespace} =~/mgrast|mg-rast/i) } @{$sample->{ sample_id }} ;	    
	    my @sids = map { $_->{namespace} ? $_->{namespace} .":". $_->{content} : $_->{content} } @{$sample->{ sample_id }};
	    $sample->{metadata}->{sample_id}   = join ";" , map { $_->{namespace} .":". $_->{content} } @{$sample->{ sample_id }};
	    
	    # container for collection _ids
	    my $collections = {} ;
	    my $dbh = $meta->db->db_handle;

	    
	    if(@cids){
		# get collections _ids for ID from Collection
		foreach my $id (@cids){
		    my $res = $dbh->selectall_arrayref(qq(select _id , ID from MetaDataCollection where  ID = "$id";));
		    map { push @{$collections->{$_->[0] } } , $_->[1]  ; $_->[0] || 0 } @$res ;
		}
		# check for mapped sample_id 
		# here @sids
	    }
	    elsif(@sids){
		# get collections _ids for sample_id in MetaDataEntry
		foreach my $id (@sids){
		    print STDERR "$t: Searching for $id\n";
		    my $res = $dbh->selectall_arrayref(qq(select collection , job , _id from MetaDataEntry where tag = "sample_id"  and value regexp "$id" group by collection , job ;));
		    map { push @{$collections->{$_->[0] }} , $_->[1]  ; $_->[0] || 0 } @$res ;
		}
	    }
	    
	    if(	my @ids = sort {$a<=> $b} keys %$collections ){
	
		print  STDERR "$t: Found ". scalar @ids ." existing samples\n";
	
		
		# replace sample
		my $cid = shift @ids ;
		my $cs = $meta->db->MetaDataCollection->get_objects( { _id => $cid } );
		my $c = shift @$cs ;
		print STDERR "$t: " , $c->ID , "\n";
		if ( $user->has_right(undef, 'view' , 'sample', $c->ID ) ){
		    
		    #deleting meta data entries
		    my $mds =  $meta->db->MetaDataEntry->get_objects( {collection => $c } );
		    map { $_->delete }  @$mds ;
		    $collection = $c ;
		}
		else{
		    print STDERR "$t: No right for user " .$user->login ." to edit collection ".$c->ID." !\n";
		    return ( 0 , "Mising right to modify " . $c->ID , [] );
		}
	    }
	}
	
	if ($collection and ref $collection){
	    print STDERR "$t: Replacing data for " . $collection->ID , "\n";
	}
	else{
	    print STDERR "$t: Creating new sample\n";
	    my $id         =  ($meta->db->MetaDataCollection->last_id) + 1 ;
	    $collection = $meta->db->MetaDataCollection->create( { creator => $curator , 
								   ID      => $id , 
								   source  => $sample->{submission_system}      || 'unknown' , 
								   url     => $sample->{submission_system_url } || ''  , 
								   type    => 'sample' ,
								 } ) ;

	    # create rights for collection/sample
	    my $view_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							data_type => 'sample', 
							data_id   => $id , 
							name      => 'view', 
							granted   => 1 ,
						      } );
	    my $edit_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							data_type => 'sample', 
							data_id   => $id , 
							name      => 'edit', 
							granted   => 1 ,
						      } );
	}

	
	

	
	# connect sample to study/project
	if ($project){
	    my $pmd = $meta->db->ProjectMD->create( { project => $project ,
						      tag     => 'sample_collection_id' ,
						      value   => $collection->ID ,
						    } ) ;

	    if ($sample->{job_id}){
		my $job = $meta->db->Job->init( { job_id => $sample->{job_id} } );
		$job->sample($collection);
		$job->project($project);
		$collection->job($job);
		my $pjs =  $meta->db->ProjectJob->get_objects( {job => $job , project => $project } );
		unless(ref $pjs and scalar @$pjs){
		    my $pj =  $meta->db->ProjectJob->create( {job => $job , project => $project } );
		}
	    }
	}
	
	
	# preserve study id
	$sample->{metadata}->{study_id}    = join ";" , map { $_->{namespace} .":". $_->{content} } @{$sample->{ study_id }};
	$sample->{metadata}->{sample_id}   = join ";" , map { $_->{namespace} .":". $_->{content} } @{$sample->{ sample_id }};
	$sample->{metadata}->{sample_name} = $sample->{ sample_name } if ( $sample->{ sample_name } );
	
	#add tag , value pairs
	foreach my $tag (keys %{$sample->{metadata}}){

	    unless ($sample->{metadata}->{$tag}){
		#print STDERR "$tag " . ( $sample->{metadata}->{$tag} || "no value" ) ;
		#next ;
	    }
	    if (ref $sample->{metadata}->{$tag}){
		print "Hi Doug , here is something wrong with the data structure , please send me your structure so that I can adapt my parser.\n Andreas\n";
		if ($user->login =~/douginator2000\@gmail.com/){
		    
		}
		$msg = 'Complex data structure where string expected.\n' . Dumper  $sample->{metadata}->{$tag} ;
		return ( 0 , $msg , [] );
		
	    }
	    if ($collection->job){
		my $smd = $meta->db->MetaDataEntry->create( { collection => $collection ,
							      job        => $collection->job ,
							      tag        => $tag ,
							      value      => $sample->{metadata}->{$tag} ,
							    } ) ;
	    }
	    else{
		my $smd = $meta->db->MetaDataEntry->create( { collection => $collection ,
							      tag        => $tag ,
							      value      => $sample->{metadata}->{$tag} ,
							    } ) ;
	    }
	}

	push @sample_ids , $collection->ID ;
    }
    return ( $success , $error , \@sample_ids ) ;
}
   

#### QIIME sample preparation for sequencing

sub sequence_prep {
    my ($params) = @_ ;
    
    my $method = $params->{method} ;
    my $meta   = $params->{metadata_handle};
    my $opts   = $params->{params} ;
    my $user   = $params->{user};
    my $cgi    = $params->{cgi} ;
    my $master = $params->{master} ;


    
    my $data   = '' ;
    my $msg    = '' ;
    my $tag    = '' ;
    
    if ($opts and @$opts){
	$tag = shift @$opts ;
    }

    # get global ids/all public ?
    if ( $method eq "GET" ){
	my $samples = [] ;
	
	if ( $tag eq "id" ){

	    if ($user){
		my $value = shift @$opts ;
		
		if ( $value and $user->has_right(undef, 'view' , 'sample', $value ) ){
		    $samples = $meta->db->MetaDataCollection->get_objects( { ID => $value } );
		}
		else{
		    $msg  .= "<success>0</success>\n<error>you don't have the right to view sample $value</error>" ;
		}
	    }
	    else{
		$msg  .= "<success>0</success>\n<error>no public samples defined</error>" ;
	    }
	    
	    foreach my $sample (@$samples){
		    $data .= $sample->xml ;
	    }

	   
	}
	elsif ($tag){

	}
	else{
	   # my $ids = $meta->get_samples ;
	}
    }
    elsif( $method eq "POST"){ 
	
	$data .= '' ; #$cgi->param('POSTDATA') ;
	#print STDERR "Creating sample prep\n";
	my ($s , $e , $ids) = create_sequence_prep($master , $meta , $user , $cgi->param('POSTDATA') ) ; 
	#print STDERR scalar @$ids . " SamplePrep IDs \n";
	$msg  .= "<success>$s</success>\n<error>$e</error>" ;
	foreach my $id (@$ids){
	    $data .= "<sample_id namespace='mgrast'>$id</sample_id>\n";
	}
    }
    
    # Called post or put without parameters
    else{ $msg .= "Missing arguments for $method" ; return ($msg , '') }
       
    return ($msg , "\n<data>".$data."</data>\n") ;

};

sub create_sequence_prep {
    my ($master , $meta , $user , $data) = @_ ;
    my $success  = 1 ;
    my $error    = 0 ;
    my $msg      = '';
    my @prep_ids ;
    

    # parse sample xml
    my $xs = XML::Simple->new();
    my $block = $xs->XMLin( $data , ForceArray => [ 'study' , 'sample' , 'sample_id' , 'sequence_prep' , 'sample_prep' ]);
  
    # single study without <daba_block>
   
    $block->{sequence_prep} = $block->{sample_prep} if ($block->{sample_prep}) ;
    push @{ $block->{sequence_prep} } , $block unless ($block->{sequence_prep}) ;

    # print Dumper $block ;

    foreach my $prep ( @{ $block->{sequence_prep} } ){
	print STDERR "$t: Reading prep file\n";	
	return ( 0 , "no prep id (row_number)\n" .(Dumper $prep) , [] ) unless (exists $prep->{row_number} and  $prep->{row_number} ge '0') ;
	
	#print STDERR "Reading prep file 2\n";
	# get curator
	my $curator ;
	my $curators = $meta->db->Curator->get_objects( { user => $user } ) ;
	# not a Curator , create one
	unless(ref $curators and scalar @$curators){
	    my $curator = $meta->db->Curator->create( { user  => $user ,
							name  => $user->firstname . " " . $user->lastname ,
							email => $user->email ,
							type  => $prep->{submission_system} || '' ,
							url   => '' ,
							ID    => $user->_id ,
						      });
	    
	    unless($curator and ref $curator){
		print STDERR "Can't creat Curator for user " . $user->login ;
		exit;
	    }
	    
	}
	else{
	    $curator = $curators->[0] ;
	}
    
	# get project
	my $project = '';
	if ( $prep->{ project_id } and $user->has_right(undef, 'edit' , 'project', $prep->{ project_id } ) ){
	    $project =   $meta->db->Project->init( { id => $prep->{ project_id } } ) ;
	}
	else{
	    $msg .= "no project id or no rights to edit project\n" ;
	}

	print STDERR "$t: Got project " . $project->id , "\n"; 
	
	# get sample 
	my $sample = '';
	my $sid    = 0 ;
	if ( $prep->{ sample_id } ){
	    unless (ref $prep->{ sample_id }){
		$sid       = $prep->{ sample_id } || 0 ;
	    }
	}
	
	
	# check for mgrast sample id
	unless($sid){ 
	    foreach my $s (@{ $prep->{sample_id} }){
		
		unless (ref $s){
		    $sid       = $s || 0 ;
		}
		else{
		    $sid = $s->{content} if ($s->{namespace} =~/mgrast|mg-rast/i);
		}
	    }
	}

	print STDERR "$t: Fetching sample for " . $sid , "\n";
	if ( $sid and $user->has_right(undef, 'edit' , 'sample', $sid ) ){
	    $sample =   $meta->db->MetaDataCollection->init( { ID => $sid } ) ;

	    unless($sample and ref $sample){
		$msg .= "missing sample for $sid ;" ;
		return ( 0 , $msg , [] );
	    }
	}
	else{
	    $msg .= "no sample id or no rights to edit sample\n"  . ( $sid ? "($sid)\n" : '') ;
	    return ( 0 , $msg , [] );
	}

	print STDERR "$t: Got sample " . $sample->ID , "\n";

	# connect sample to prep
	if ($sample and ref $sample){
	    
	    my $prepID      = ( $sample->ID . "." . $prep->{row_number} ) ;
	    print STDERR "searching for $prepID\n";
	    my $preparation =   $meta->db->MetaDataCollection->init( { ID => $prepID } ) ;
	    

	    if(ref $preparation){
		print STDERR "$t: prep exists , delete entries\n";
		
		foreach my $entry (@{ $meta->db->MetaDataEntry->get_objects( { collection => $preparation } ) }){
		    $entry->delete;
		}
		
		#return ( 0 , "preparation $prepID exists" , [ $preparation->ID ]) ;
	    }
	    else{
		$preparation = $meta->db->MetaDataCollection->create( { creator => $curator , 
									ID      => $prepID , 
									source  => $prep->{submission_system}      || 'unknown' , 
									url     => $prep->{submission_system_url } || ''  , 
									type    => 'sample' ,
								      } ) ;

		# create rights for collection/sample
		my $view_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							    data_type => 'sample', 
							    data_id   => $prepID , 
							    name      => 'view', 
							    granted   => 1 ,
							  } );
		my $edit_right = $master->Rights->create( { scope     => $user->get_user_scope, 
							    data_type => 'sample', 
							    data_id   => $prepID , 
							    name      => 'edit', 
							    granted   => 1 ,
							  } );
		
		# it is a sample from qiime , flag existing sample as template
		$sample->type('template');
	    }
	    
	    
	    # copy data from sample to preparation
	    
	    foreach my $entry (@{ $meta->db->MetaDataEntry->get_objects( { collection => $sample } ) }){

		unless (ref $entry ){
		    print STDERR Dumper $entry ;
		    Return (0 , 'Serious error , no object: ' . Dumper $entry , [] );
		}
		
		if ($sample->job){
		    my $smd = $meta->db->MetaDataEntry->create( { collection => $preparation ,
								  job        => $sample->job ,
								  tag        => $entry->tag ,
								  value      => $entry->value ,
								} ) ;
		}
		else{
		    my $smd = $meta->db->MetaDataEntry->create( { collection => $preparation ,
								  tag        => $entry->tag ,
								  value      => $entry->value,
								} ) ;
		}
	    
			
	    }
	    
	    #add tag , value pairs
	    foreach my $tag (keys %{$prep->{metadata}}){
		
		if ($prep->{metadata}->{$tag} and $prep->{metadata}->{$tag} eq ''){
		    print STDERR "$tag " . ( $prep->{metadata}->{$tag} || "no value" ) ;
		    next ;
		}
		if ($sample->job){
		    my $smd = $meta->db->MetaDataEntry->create( { collection => $preparation ,
								  job        => $sample->job ,
								  tag        => $tag ,
								  value      => $prep->{metadata}->{$tag} ,
								} ) ;
		}
		else{
		    my $smd = $meta->db->MetaDataEntry->create( { collection => $preparation ,
								  tag        => $tag ,
								  value      => $prep->{metadata}->{$tag} ,
								} ) ;
		}
	    }	   
	    push @prep_ids , $preparation->ID if (ref $preparation);
	}
    }
    
    return ( $success , $error , \@prep_ids ) ;
}





sub reads {
    my ($params) = @_ ;
    
    my $method = $params->{method} ;
    my $meta   = $params->{metadata_handle};
    my $opts   = $params->{params} ;
    my $user   = $params->{user};
    my $cgi    = $params->{cgi} ;
    my $master = $params->{master} ;


    
    my $data   = '' ;
    my $msg    = '' ;
    my $tag    = '' ;
    
    if ($opts and @$opts){
	$tag = shift @$opts ;
    }

    # get global ids/all public ?
    if ( $method eq "GET" ){
	my $jobs = [] ;
	
	if ( $tag eq "id" ){
	    



	    if ($user){
		my $value = shift @$opts ;
		
		if ( $value ){
		    $jobs = $meta->db->Job->get_objects( { job_id => $value } );
		    @$jobs = map { $_ if ( $user->has_right(undef, 'view' , 'metagenome', $_->metagenome_id ) ) } @$jobs ;
		    	   
		}
		else{
		    $msg  .= "<success>0</success>\n<error>you don't have the right to get sequences $value</error>" ;
		}
	    }
	    else{
		$msg  .= "<success>0</success>\n<error>no public sequences</error>" ;
	    }
	    
	    foreach my $job (@$jobs){
		print STDERR "Downloading data for job " . $job->job_id ;
		$data .= $job->download('') ;
	    }

	   
	}
	elsif ($tag){

	}
	else{
	   # my $ids = $meta->get_samples ;
	}
    }
    elsif( $method eq "POST"){ 
	
	# debug option
	$data .= $cgi->param('POSTDATA') if (0) ;
	#print STDERR "Creating Job\n";
	
	# only create if a user is present 
	if ($user and ref $user){
	    my ($s , $e , $ids , $md5s ) = create_job($master , $meta , $user , $cgi->param('POSTDATA') ) ; 

	    $msg  .= "<success>$s</success>\n<error>$e</error>" ;
	    foreach my $id (@$ids){
		$data = "<job_id>$id</job_id>\n";
	    }
	    $data .="<md5sum>" . (join " ; " , @$md5s) ."<md5sum>\n" if ($md5s and ref $md5s);
	}
	else{
	    print Dumper $user ;
	    print STDERR Dumper $user ;
	    $msg .= 'missing user authentification or authentification failed\nPlease yell at contact.\n';
	}
    }
    
    # Called post or put without parameters
    else{ $msg .= "Missing arguments for $method" ; return ($msg , '') }
       
    return ($msg , "\n<data>".$data."\n</data>") ;

};



sub create_job {
    my ($master , $meta , $user , $data) = @_ ;
    my $success  = 1 ;
    my $error    = 0 ;
    my $msg      = '';
    my @job_ids ;
    my @md5s ;
    my $pipeline_options = {};

    # parse sample xml
    my $xs = XML::Simple->new();
    my $block = $xs->XMLin( $data , ForceArray => [ 'study' , 'sample' , 'samples' , 'sample_id' , 'filter_reference_sequence_set' ,] , KeyAttr => [] );
  
    # single study without <daba_block>
    push @{ $block->{files} } , $block unless ($block->{files}) ;


    #print STDERR Dumper $block ;

    foreach my $data ( @{ $block->{files} } ){

	my $prep_id = '';
	if (exists $data->{row_number} and  $data->{row_number}=~/\d+/){
	    $prep_id = ".".$data->{row_number} ;
	}
    
	# get curator
	my $curator ;
	my $curators = $meta->db->Curator->get_objects( { user => $user } ) ;
	# not a Curator , create one
	unless(ref $curators and scalar @$curators){
	    my $curator = $meta->db->Curator->create( { user  => $user ,
							name  => $user->firstname . " " . $user->lastname ,
							email => $user->email ,
							type  => $data->{submission_system} || '' ,
							url   => '' ,
							ID    => $user->_id ,
						      });
	    
	    unless($curator and ref $curator){
		print STDERR "Can't creat Curator for user " . $user->login ;
		exit;
	    }
	    
	}
	else{
	    $curator = $curators->[0] ;
	}
	
	
	# get project
	my $project = '';
	if ( $data->{ project_id } and $user->has_right(undef, 'edit' , 'project', $data->{ project_id } ) ){
	    $project =   $meta->db->Project->init( { id => $data->{ project_id } } ) ;
	    return (0 , "No Project for " . $data->{ project_id } , [] ) unless($project and ref $project);
	}
	else{
	    $msg .= "no project id or no rights to edit project\n" ;
	    return ;
	}
	
	# get sample
	#my @samples ;
	my @samples=  ($data->{sample} and ref $data->{sample}) ? @{ $data->{sample} } : () ;
	my $collection = '';
 	
	my $sample = '' ;
	foreach my $s ( @{ $data->{sample} }){
	    $sample = $s if (!($s->{namespace}) or ( $s->{namespace} =~ /mgrast|mg-rast/i)) ;
	}
	unless($sample){
	    foreach my $s ( @{ $data->{sample_id} }){
		unless( ref $s){
		    $sample = $s ;
		}
		else{
		    $sample = $s->{content} if ( $s->{namespace} =~ /mgrast|mg-rast/i ) ;
		}
	    }
	}
	
	# adding row number to ID ;

	$sample .= $prep_id ;

	if ($sample and $user->has_right(undef, 'edit' , 'sample', ($sample) ) ){
	    $collection =   $meta->db->MetaDataCollection->init( { ID => $sample } ) ;
	    unless($collection and ref $collection){
		return ( 0 , "No sample for $sample" , [] ) ;
	    }
	    
	}
	else{
	    $msg .= "no sample id or no rights to edit sample ($sample)\n" . Dumper $sample ;
	    return ( 0 , $msg , [] ) ;
	}
	
	if (exists $data->{options} ){
	    %$pipeline_options = %{ $data->{options} } ;
	    print STDERR Dumper  $data->{options} ;
	    
	    if ( $pipeline_options->{filter_reference_sequence_set} ){
		# concatinate list and remove array ref
		if (ref $pipeline_options->{filter_reference_sequence_set} ){
		    $pipeline_options->{contaminant_filter_orgs}       = join ";" , @{$pipeline_options->{filter_reference_sequence_set}} ;
		    $pipeline_options->{filter_reference_sequence_set} = join ";" , @{$pipeline_options->{filter_reference_sequence_set}} ;
		}
		else{
		    $pipeline_options->{contaminant_filter_orgs} = $pipeline_options->{filter_reference_sequence_set}
		}
	    }
	    
	    if ($pipeline_options->{filter_ambiguous_base_calls} and ref $pipeline_options->{filter_ambiguous_base_calls}){
		foreach my $k (keys %{  $pipeline_options->{filter_ambiguous_base_calls} }){
		     $pipeline_options->{ "filter_ambiguous_base_calls." . ( $k =~ /content/ ? "on" : $k ) } =  $pipeline_options->{filter_ambiguous_base_calls}->{$k};
		}
		delete $pipeline_options->{filter_ambiguous_base_calls} ;
	    }

	    if ($pipeline_options->{filter_length}) {
		if (ref $pipeline_options->{filter_length}) {
		    $pipeline_options->{length_filter} = $pipeline_options->{filter_length}->{content} ;
		    foreach my $k (keys %{ $pipeline_options->{filter_length} }){
			$pipeline_options->{ "filter_length." . ( $k =~ /content/ ? "on" : $k ) } =  $pipeline_options->{ "filter_length" }->{ $k };
		    }
		    delete $pipeline_options->{filter_length};
		}
		else{
		    $pipeline_options->{length_filter} = $pipeline_options->{filter_length} ;
		}
		
	    }

	    $pipeline_options->{filter_ln}            = $pipeline_options->{filter_length}        if ($pipeline_options->{filter_length}) ;
	    $pipeline_options->{contaminant_filter}   = 1                                         if ($pipeline_options->{filter_reference_sequence_set}) ;
	    $pipeline_options->{filter_ambig}         = ( $pipeline_options->{filter_ambiguous_base_calls}->{content} 
						    || 0 )                                  if ($pipeline_options->{filter_ambiguous_base_calls}) ;
	    $pipeline_options->{max_ambig}            = ( $pipeline_options->{filter_ambiguous_base_calls}->{max_allowed} 
						    || '' )                                 if ($pipeline_options->{filter_ambiguous_base_calls}) ;

	    unless($pipeline_options->{rna_only}){
		$pipeline_options->{rna_only}  =  ($data->{sequences}->{type} and $data->{sequences}->{type} =~/rna/i) ? 1 : 0 ;
	    }

	}
	
	if (exists $data->{sequences} ){

	    # get upload path and create directories
	    my $upload_path = &upload_path($user , ($project ? $project->id : '') );
	    my $filename = "$upload_path/".$user->_id . "-" ; 
	    $filename .= (ref $collection ? $collection->ID : $data->{sample}->[0]->{id} ) . "-". &timestamp ;

	    # set sequence type
	    my $sequence_type = (ref $data->{sequences} and $data->{sequences}->{type}) ? $data->{sequences}->{type} : '' ;
	    
	    # set pipeline options
	    if ($sequence_type =~ /16s|rna/i){
		$pipeline_options->{rna_only} = 1 ;
		$sequence_type = '16s' ;
	    }
	    
	    open(FILE , ">$filename") or die "Can't open $filename for writing!\n";
	    if (ref $data->{sequences} and exists $data->{sequences}->{content}){
		my $content = $data->{sequences}->{content} ; 
		$content  =~ s/^\s+//;  
		print FILE $content ;
	    }
	    else{

		if (ref  $data->{sequences}){
		    print  Dumper  $data->{sequences} ;
		    exit ;
		}
		my $content = $data->{sequences} ; 
		$content  =~ s/^\s+//;  
		$content  =~ s/\s+$//g; 
		print FILE $content ;
	    }

	    my $seq_stats  = {} ;
	    my $stats = `$FIG_Config::seq_length_stats -fasta_file $filename` if (-f $filename) ;
	    foreach my $line (split "\n" , $stats) {
		my ($tag , $value) = split "\t" , $line ;
		# print "$tag :: $value\n";
		$seq_stats->{$tag} = $value ;
	    }

	    # get length filter cutoffs
	    if ($pipeline_options->{filter_ln}) {
		$pipeline_options->{min_ln} = int( $pipeline_options->{average_length} - (2 * $pipeline_options->{standard_deviation_length}) );
		$pipeline_options->{max_ln} = int( $pipeline_options->{average_length} + (2 * $pipeline_options->{standard_deviation_length}) );
		if ($pipeline_options->{min_ln} < 0) { $pipeline_options->{min_ln} = 0; }
	    }

	    my ($md5 , $f) = `md5sum $filename` =~/^\s*([^\s]+)\s*(\w+)/;
	 
	    unless($md5){
		print "Soething wrong , can't compute md5 for $filename\n";
		print STDERR "Something wrong , can't compute md5 for $filename\n";
		exit;
	    }

	    #check for md5 in system
	    my $jobs = $meta->db->Job->get_objects( { owner => $user , 
						      file_checksum_raw => $md5 ,
						    } ) ;
						    
	    
	    if (ref $jobs and scalar @$jobs){
		return ( 0 , 'Duplicate file' , [ map { $_->job_id } @$jobs ] , [ $md5 ]) ;
	    }

	    push @md5s , $md5 ;
	    
	    print STDERR "Creating Job\n";
	    my $job  = $meta->db->Job->reserve_job($user , $pipeline_options , $seq_stats);
	    if ($job and ref $job){ push @job_ids , $job->job_id ;               }
	    else                  { return (0 , "Can't create job in DB" , [] ) ;}
	   
	   
	    
	    $job->server_version(3) ;
	    $job->name($collection->ID);
	    $job->file_checksum_raw($md5) ;

	    # connect sample and job
	    $job->sample($collection) ;
	    unless(ref $collection->job){
		$collection->job($job) ;
	    }

	    # add job to project
	    if ( $project and ref $project){
		$job->project($project) unless ($job->project) ;
		
		my $pjs = $meta->db->ProjectJob->get_objects( { job     => $job ,
								project => $project ,
							      } ) ;
		unless (ref $pjs and scalar @$pjs){
		    $pjs = $meta->db->ProjectJob->create( { job     => $job ,
							    project => $project ,
							  } ) ;
		}

	
	    }
	    
	    $msg .= $job->finish_upload($filename , $sequence_type) ; 

	    #clean up
	    if ( -d $job->directory and -f $job->download_dir . "/" . $job->job_id . ".fna" ){
		my $error = `rm $filename` ;
	    } 
	    else{
		print STDERR "Missing file " . $job->download_dir . "/" . $job->job_id . ".fna\n";
		return ( 0 , "Creation of job failed.\n$msg" , \@job_ids , \@md5s) ;
	    }

	    # call mgrast job method here
	    my @jobs ;
	    push @jobs , $job->job_id if (ref $job);
	    print STDERR "Created job " . $job->job_id , "\n" ;
	    $msg = '' ;
	    #return (0 , "$msg\nnot implemented yet. File /tmp/$filename" , \@jobs , $md5) ;
	}
	else{
	    print STDERR "no sequences!\n";
	    $msg .= "no sequences" ; 
	}
	#push @job_ids , $job->job_id ;
    }
    $error .= "\n\n$msg\n";
    return ( $success , $error , \@job_ids , \@md5s) ;
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

sub register {};
