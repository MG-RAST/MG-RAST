package resources2::sequenceset;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name}       = "sequenceset";
    $self->{attributes} = { "data" => [ 'file', 'requested sequence file' ] };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "A set / subset of genomic sequences of a metagenome from a specific stage in its analysis",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a single sequence file.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "unique sequence set identifier - to get a list of all identifiers for a metagenome, use the setlist request" ] },
							 'body'        => {} } },
				    { 'name'        => "setlist",
				      'request'     => $self->cgi->url."/".$self->name."/{ID}",
				      'description' => "Returns a list of sets of sequence files for the given id.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "stage_name" => [ "string", "name of the stage in processing of this sequence file" ],
							 "file_name"  => [ "string", "name of the sequence file" ],
							 "stage_type" => [ "string", "type of the sequence file within a stage, i.e. passed or removed for quality control steps" ],
							 "id"         => [ "string", "unique identifier of the sequence file" ],
							 "stage_id"   => [ "string", "three digit numerical identifier of the stage" ],
							 "url"        => [ "string", "url for retrieving this sequence file" ] },
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "unique metagenome identifier" ] },
							 'body'        => {} } },
				  ]
		  };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # check id format
    my $show_list = 0;
    my $rest = $self->rest;
    my ($pref, $mgid, $stageid, $stagenum) = $rest->[0] =~ /^(mgm)?([\d\.]+)-(\d+)-(\d+)$/;
    if (! $mgid && scalar(@$rest)) {
        ($pref, $mgid) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
        if (! $mgid) {
            $self->return_data({"ERROR" => "invalid id format: ".$rest->[0] }, 400);
        } else {
            $show_list = 1;
        }
    }

    # get database
    my $master = $self->connect_to_datasource();
  
    # get data
    my $job = $master->Job->get_objects( {metagenome_id => $mgid, viewable => 1} );
    unless ($job && ref($job)) {
        $self->return_data( {"ERROR" => "id $mgid does not exists"}, 404 );
    }
    $job = $job->[0];
    
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $job->{metagenome_id}) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    if ($show_list) {
        $self->setlist($job);
    }
    
    my $filedir  = ($stageid eq "050") ? $job->download_dir : $job->analysis_dir;
    my $prefix   = ($stageid eq "050") ? '' : $stageid;
    my $filename = '';
	if (opendir(my $dh, $filedir)) {
	    my @files = sort grep { /^$prefix.*(fna|fastq)(\.gz)?$/ && -f "$filedir/$_" } readdir($dh);
	    closedir $dh;
	    $filename = $files[$stagenum - 1];
	} else {
	    $self->return_data( {"ERROR" => "could open job directory"}, 404 );
	}
	
	$self->return_file($filedir, $filename);
}

sub setlist {
    my ($self, $job) = @_;

    my $rdir   = $job->download_dir;
    my $adir   = $job->analysis_dir;
    my $stages = [];
    
    if (opendir(my $dh, $rdir)) {
        my @rawfiles = sort grep { /^.*(fna|fastq)(\.gz)?$/ && -f "$rdir/$_" } readdir($dh);
        closedir $dh;
        my $fnum = 1;
        foreach my $rf (@rawfiles) {
            my ($jid, $ftype) = $rf =~ /^(\d+)\.(fna|fastq)(\.gz)?$/;
            push(@$stages, { id         => "mgm".$job->metagenome_id."-050-".$fnum,
		                     url        => $self->cgi->url.'/sequenceset/'."mgm".$job->metagenome_id."-050-".$fnum,
		                     stage_id   => "050",
		                     stage_name => "upload",
		                     stage_type => $ftype,
		                     file_name  => $rf });
            $fnum += 1;
        }
    } else {
        $self->return_data( {"ERROR" => "job directory could not be opened"}, 404 );
    }
    
    if (opendir(my $dh, $adir)) {
        my @stagefiles = sort grep { /^.*(fna|faa)(\.gz)?$/ && -f "$adir/$_" } readdir($dh);
        closedir $dh;
        my $stagehash = {};
        foreach my $sf (@stagefiles) {
            my ($stageid, $stagename, $stageresult) = $sf =~ /^(\d+)\.([^\.]+)\.([^\.]+)\.(fna|faa)(\.gz)?$/;
            next unless ($stageid && $stagename && $stageresult);
            if (exists($stagehash->{$stageid})) {
	            $stagehash->{$stageid}++;
            } else {
	            $stagehash->{$stageid} = 1;
            }
            push(@$stages, { id         => "mgm".$job->metagenome_id."-".$stageid."-".$stagehash->{$stageid},
		                     url        => $self->cgi->url.'/sequenceset/'."mgm".$job->metagenome_id."-".$stageid."-".$stagehash->{$stageid},
		                     stage_id   => $stageid,
		                     stage_name => $stagename,
		                     stage_type => $stageresult,
		                     file_name  => $sf });
        }
    } else {
        $self->return_data( {"ERROR" => "job directory could not be opened"}, 404 );
    }
    
    if (@$stages > 0) {
        $self->return_data($stages);
    } else {
        $self->return_data( {"ERROR" => "no stagefiles found"}, 404 );
    }
}

1;
