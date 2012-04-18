package MGRAST::WebPage::UploadMetagenome;

use strict;
use warnings;

use POSIX;
use File::Basename;
use Data::Dumper;
use File::Copy;
use File::Temp;
use Archive::Tar;
use FreezeThaw qw( freeze thaw );

use Job48;
use FIG_Config;
use WebConfig;

use base qw( WebPage );

1;


=pod

=head1 NAME

UploadMetagenome - upload a metagenome job

=head1 DESCRIPTION

Upload page for metagenomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Upload a new metagenome");
  $self->application->register_component('TabView', 'Tabs');
  $self->application->register_component('Ajax', 'upload_ajax');

}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  $self->data('done', 0);

  my $tab_view = $self->application->component('Tabs');
  $tab_view->width(800);
  $tab_view->height(180);

  my $content = '<h1>Upload a metagenome</h1>';
  $content .= "<h3>upload workflow</h3><p>The upload page will guide you through the four simple steps of the upload process.</p><p>After uploading the data file, it will go through a validation process. This will make sure that your submission will be able to successfully pass through our pipeline. To allow for transparency in comparative analyses, interpretation of results, and integration of metagenomic data, MG-RAST implements the 'Minimum Information about a MetaGenome Sequence' developed by the <a href='http://gensc.org' target=_blank>Genomic Standards Consortium (GSC)</a>. In the third step we ask you to provide this data. In a final step you will get a summary of your uploaded data.</p><p>If you encounter problems during the process, you can refer to our <a href='http://blog.metagenomics.anl.gov'>FAQ</a>.</p>";
  my $log = '';

  # step 1: file upload
  my $temp = $self->file_upload();
  if ($self->data('done')) {
    $tab_view->add_tab('upload file', $temp);
    $tab_view->add_tab('validify file', '', undef, 1);
    $tab_view->add_tab('enter metadata', '', undef, 1);
    $tab_view->add_tab('finish submission', '', undef, 1);
    $tab_view->default(0);
    $content .= $tab_view->output;
    return $content;
  }
  else {
    $log .= $temp;
  }

  # step 2: file verification
  $temp = $self->file_validification();
  if ($self->data('done')) {
    $tab_view->add_tab('upload file', '', undef, 1);
    $tab_view->add_tab('validify file', $temp);
    $tab_view->add_tab('enter metadata', '', undef, 1);
    $tab_view->add_tab('finish submission', '', undef, 1);
    $tab_view->default(1);
    $content .= $tab_view->output;
    return $content;
  }
  else {
    $log .= $temp;
  }

  # step 3: metadata
  $temp = $self->metadata();
  if ($self->data('done')) {
    $tab_view->add_tab('upload file', '', undef, 1);
    $tab_view->add_tab('validify file', '', undef, 1);
    $tab_view->add_tab('enter metadata', $temp);
    $tab_view->add_tab('finish submission', '', undef, 1);
    $tab_view->default(2);
    $content .= $tab_view->output;
    return $content;
  }
  else {
    $log .= $temp;
  }
  
  # step 4: upload summary

  # if we get here, upload is done
  $log .= $self->commit_upload();
  $tab_view->add_tab('upload file', '', undef, 1);
  $tab_view->add_tab('validify file', '', undef, 1);
  $tab_view->add_tab('enter metadata', '', undef, 1);
  $tab_view->add_tab('finish submission', $log);
  $tab_view->default(3);
  $content .= $tab_view->output."<p></p>";

  return $content;
}

=item * B<file_upload> ()

Returns the file upload page parts for metagenomes

=cut

sub file_upload {
  my ($self) = @_;
  
  # check for recent file in the upload form
  if ($self->application->cgi->param("upload")) {
    $self->save_upload_to_incoming();
  } 
  
  # check if a file was uploaded
  if ($self->application->cgi->param("upload_file")) {
    my $content = '<p><strong>Uploaded one '.$self->application->cgi->param("upload_type").' file.</strong></p>';

    #
    # Unpack data if necessary and get a listing of files.
    #

    my $flist;
    if ($self->app->cgi->param('file_list'))
    {
	($flist) = thaw($self->app->cgi->param('file_list'));
	my ($info) = thaw($self->app->cgi->param('file_info'));
	$self->data('file_info', $info);
    }
    else
    {
	my $files = $self->list_files_from_upload();
	
	#
	# Determine which of these files signify a potential job that we
	# need to process. We do this by finding the fasta files that contain
	# sequence data, and looking for .qual files that have the same file base.
	#
	
	my %bases;
	for my $file (@$files)
	{
	    my($base, $path, $suffix) = fileparse($file, qr/\.[^.]*$/);
	    my $format = $self->determine_file_format($file);
	    my $prev = $bases{$base}->{$format};
	    
	    if (defined($prev))
	    {
		warn "MGRAST file_upload(): while processing $file, already have a $format base named $prev\n";
	    }
	    
	    $bases{$base}->{$format} = $file;
	}
	$self->data('file_info', \%bases);
	
	$flist = [];
	for my $base (sort keys %bases)
	{
	    my $fa = $bases{$base}->{fasta};
	    next unless $fa;
	    push(@$flist, basename($fa));
	    
	    #
	    # Run characterize_dna_fasta to get various metrics on the fasta file,
	    # including duplicate sequence/id information.
	    #
	    if (open(P, "-|", "$FIG_Config::bin/characterize_dna_fasta", $fa))
	    {
		while (<P>)
		{
		    chomp;
		    my($k, $v) = split(/\t/);
		    $bases{$base}->{stats}->{$k} = $v;
		}
		close(P);
	    }
	}
	
	my $fr = freeze($self->data('file_info'));
	$self->app->cgi->param('file_info', $fr);
	$self->app->cgi->param('file_list', freeze($flist));
    }
    
    $self->data('files', $flist);
    warn Dumper($flist);
    
    if (scalar(@{$self->data('files')})) {
      $content .= '<p><strong>Found '.scalar(@{$self->data('files')}).' sequence file(s).</strong></p>';
    }
    else {
      $content .= "<p><em>Unfortunately I have not been able to find any fasta files in the upload.</em></p>";
      $content .= "<p> &raquo <a href='metagenomics.cgi?page=UploadMetagenome'>Start over the metagenome upload</a></p>";
      $self->data('done', 1);
    }

    return $content;
  }
  else {
  
    # upload info text
    my $content = "<h3>file requirements</h3>";
    $content .= "<p><ul>";
    $content .= "<li>the upload file must be <a href='http://www.ncbi.nlm.nih.gov/blast/fasta.shtml' target=_blank>FASTA</a> containing nucleotice sequences only</li>";
    $content .= "<li>the upload filename must end in one of the following:<br><i>.fa, .fasta, .fas, .fsa or .fna</i></li>";
    $content .= "<li>files larger than 30 MB must be compressed as <a href='http://en.wikipedia.org/wiki/Gzip' target=_blank>.tgz</a></li>";
    $content .= "<li>you may upload a <a href='http://en.wikipedia.org/wiki/Gzip' target=_blank>compressed archive</a> that includes a quality file (.qual) along with the <a href='http://www.ncbi.nlm.nih.gov/blast/fasta.shtml' target=_blank>FASTA</a> file</li>";
    $content .= "</ul></p>";
    
    $content .= $self->application->component('upload_ajax')->output();
    $content .= "<div id='ajax_upload_div'></div>";

    # create upload information form
    $content .= $self->start_form('upload_form', 1);
    $content .= "<fieldset><legend> File Upload: </legend><table>";
    $content .= "<tr><td>Sequences File</td><td><input type='file' name='upload'></td></tr>";
    $content .= "</table></fieldset>";

    $content .= "<p><input type='button' onclick='execute_ajax(\"new_upload\", \"ajax_upload_div\", \"x=y\");' value='Upload file and go to step 2'></p>";
    $content .= "<input type='hidden' name='metagenome_id' value='' id='metagenome_id'>";

    #$content .= "<p><input type='submit' name='nextstep' value='Upload file and go to step 2'></p>";
    $content .= $self->end_form();

    $self->data('done', 1);

    return $content;

  }  
}

=item * B<metadata> ()

Returns whether the uploaded file is valid

=cut

sub metadata {
  my ($self) = @_;

  my $page = $self->data('metadata_page');
  $page->{simple_mode} = 1;

  if ($self->application->cgi->param('load_meta_data')) {
    $page->load_meta_data();
  } else { 
    
    my $content = $page->output();
    
    $self->data('done', 1);
    
    return $content;
  }

  return 1;
}

=item * B<file_validification> ()

Returns whether the uploaded file is valid

=cut

sub file_validification {
  my ($self) = @_;
  
  # remove me
  return 1;
  # remove me

  my $content = "Marks Stuff here";

  $self->data('done', 1);

  return $content;
}

=item * B<project_info> ()

Returns the project info and metagenome name page parts

=cut

sub project_info {
  my ($self) = @_;

  my $form = 1;

  # check if all information were entered
  if ($self->application->cgi->param("project_name")) {
    $form = 0;

    # check names for files
    foreach (@{$self->data('files')}) {
      $form = 1 unless ($self->app->cgi->param($_.'_genome'));
    }
    
    # print summary
    unless ($form) {
      my $content = '<p><strong>Assigned project name to the upload:</strong></p>';
      $content .= '<p>'.$self->application->cgi->param("project_name").'</p>';
      $content .= '<p><strong>Assigned metagenome names and/or descriptions:</strong></p>';
  
      foreach (@{$self->data('files')}) {
	my $genome = $self->app->cgi->param($_.'_genome') || '';
	my $description = $self->app->cgi->param($_.'_description') || 'no description';
	$content .= "<p>$genome ($description)</p>";
      }
      return $content;
    }

  }

  # ask for project and metagenomes names
  if ($form) {
   
    my $content = $self->start_form('project', { 'upload_type' => $self->app->cgi->param('upload_type'),
						 'upload_file' => $self->app->cgi->param('upload_file'),
						 'file_info' => $self->app->cgi->param('file_info'),
						 'file_list' => $self->app->cgi->param('file_list'),
						 });

    $content .= '<p><strong>Please enter a project name and metagenome names for all uploaded files:</strong></p>';
    
    my $project_name = $self->app->cgi->param('project_name') || '';

    $content .= "<fieldset><legend> Project information: </legend><table>";
    $content .= "<tr><td><strong>Project Name:</strong></td>".
      "<td><input type='text' name='project_name' value='$project_name'></td></tr>\n";
    
    #
    # Captions for characterize_dna_fasta opts.
    #
    my @captions = (total_size => 'Total size of sequence data',
		    num_seq => 'Number of sequences',
		    min => "Shortest sequence size",
		    mean => "Mean sequence size",
		    max => "Longest sequence size",
		    bad_data => 'Number of sequences with bad data characters',
		    dup_id_count => "Number of duplicate sequence identifiers",
		    dup_seq_count => "Number of duplicate sequences",
		    );

    foreach (@{$self->data('files')}) {
      $content .= "<tr><td colspan='2'><strong>$_</strong></td><td></td></tr>\n";
	my($base) = /(.*)\.[^.]+$/;
	my $stats = $self->data('file_info')->{$base}->{stats};
	for (my $i = 0; $i < @captions; $i += 2)
	{
	    my($id, $capt) = @captions[$i, $i + 1];
	    my $val = $stats->{$id};
	    if (defined($val))
	    {
		$content .= "<tr><td>$capt</td><td>$val</td></tr>\n";
	    }
	}

      my $genome = $self->app->cgi->param($_.'_genome') || '';
      my $description = $self->app->cgi->param($_.'_description') || '';
      
      $content .= "<tr><td>Metagenome Name:</td><td>".
	"<input type='text' name='$_\_genome' value='$genome'></td></tr>\n";
      $content .= "<tr><td>Description:</td><td>".
	"<input type='text' name='$_\_description' value='$description'></td></tr>\n";
    }
    
    $content .= "</table></fieldset>";
    $content .= "<p><input type='submit' name='nextstep' value='Use this data and go to step 3'></p>";
    $content .= $self->end_form();

    $self->data('done', 1);
    return $content;
  }
}


=item * B<optional_info> ()

Returns the optional info and questions page parts

=cut

sub optional_info {
  my ($self) = @_;

  
  if ($self->app->cgi->param('finish')) {
    my $content = '<p><strong>Assigned metadata to the project name:</strong></p>';
    my $meta = '';
    $meta .= "<p>Longitude: ".$self->app->cgi->param('longitude')."</p>" 
      if ($self->app->cgi->param('longitude'));
    $meta .= "<p>Latitude: ".$self->app->cgi->param('latitude')."</p>" 
      if ($self->app->cgi->param('latitude'));
    $meta .= "<p>Depth or Altitude: ".$self->app->cgi->param('altitude')."</p>" 
      if ($self->app->cgi->param('altitude'));
    $meta .= "<p>Time of sample collection: ".$self->app->cgi->param('time')."</p>" 
      if ($self->app->cgi->param('time'));
    $meta .= "<p>Habitat: ".$self->app->cgi->param('habitat')."</p>" 
      if ($self->app->cgi->param('habitat'));
    $content .= ($meta) ? $meta : '<p><em>No metadata provided.</em></p>';
    
    $content .= '<p><strong>MG-RAST Annotation Settings:</strong></p>';
    if ($self->app->cgi->param('remove_duplicates')) {
      $content .= '<p>Remove exact duplicate sequences during preprocessing.</p>';
    }
    else {
      $content .= '<p>Preprocessing will retain all sequences and not remove exact duplicates.</p>';
    }

    if ($self->app->cgi->param('public')) {
      $content .= '<p>Metagenome will be made public via MG-RAST.</p>';
    }
    else {
      $content .= '<p>Metagenome will remain private.</p>';
    }      
    
    return $content;

  }
  else {

    my $content = $self->start_form('project', 1);

    $content .= '<p><strong>Please provide us with the following information where possible:</strong></p>';
    
    my $altitude = $self->app->cgi->param('altitude') || '';
    my $longitude = $self->app->cgi->param('longitude') || '';
    my $latitude = $self->app->cgi->param('latitude') || '';
    my $time = $self->app->cgi->param('time') || '';
    my $habitat = $self->app->cgi->param('habitat') || '';

    $content .= "<fieldset><legend> Project metadata: </legend>";
    $content .= "<table>";
    $content .= "<tr><td>Latitude:</td><td><input type='text' name='latitude' value='$latitude'></td><td><em>use Degree:Minute:Second (42d20m00s)</em></td></tr>\n";
    $content .= "<tr><td>Longitude:</td><td><input type='text' name='longitude' value='$longitude'></td><td><em> or Decimal Degree (56.5000)</em></td></tr>\n";
    $content .= "<tr><td>Depth or altitude:</td><td><input type='text' name='altitude' value='$altitude'></td><td><em> in Meter (m)</em></td></tr>\n";
    $content .= "<tr><td>Time of sample collection:</td><td><input type='text' name='time' value='$time'></td><td><em> in Coordinated Universal Time (UCT) YYYY-MM-DD</em></td></tr>\n";
    $content .= "<tr><td>Habitat:</td><td><input type='text' name='habitat' value='$habitat'></td><td></td></tr>\n";
    $content .= "</table></fieldset><br/>";

    $content .= "<fieldset><legend> MG-RAST Options: </legend>";
    $content .= "<table>";
    $content .= "<tr><td>Remove duplicate sequences from the uploaded data:</td>".
      "<td><input type='checkbox' name='remove_duplicates' value='1' checked='checked'></td></tr>\n";
    $content .= "<tr><td>Make this metagenome publically available via MG-RAST:</td>".
      "<td><input type='checkbox' name='public' value='1'></td></tr>\n";
    $content .= "</table></fieldset>";

    $content .= "<p><input type='submit' name='finish' value='Finish the upload'></p>";
    $content .= $self->end_form();

    $self->data('done', 1);
    return $content;
  }
}


=item * B<commit_upload> ()

Finalizes the upload by creating the job directories

=cut

sub commit_upload  {
    my ($self) = @_;
    
    my $cgi = $self->application->cgi;
    
    # prepare data to create job dirs
    my $jobs = [];

    my @optional_parameters = qw(altitude longitude latitude time habitat);
    
    foreach my $file (@{$self->data('files')})
    {
      my $job = { 'genome'      => $cgi->param($file.'_genome'),
		  'project'     => $cgi->param('project_name'),
		  'user'        => $self->app->session->user->login,
		  'taxonomy'    => '',
		  'metagenome'  => 1,
		  'meta' => { 'source_file'    => $file,
			      'project.description' => $cgi->param($file.'_description') || '',
			      'options.remove_duplicates' => $cgi->param('remove_duplicates') || 0,
			      'options.run_metagene' => $cgi->param('run_metagene') || 0,
			      'options.public' => $cgi->param('public') || 0,
			    },
		};
	for my $opt (@optional_parameters)
	{
	    my $val = $cgi->param($opt);
	    $val =~ s/\s+$//;
	    $val =~ s/^\s+//;
	    $job->{meta}->{"optional_info.$opt"} = $val;
	}
	my($base) = $file =~ /(.*)\.[^.]+$/;
	my $file_info = $self->data('file_info')->{$base};
	
	while (my($sname, $sval) = each %{$file_info->{stats}})
	{
	    $job->{meta}->{"upload_stat.$sname"} = $sval;
	}
	$job->{meta}->{source_fasta} = $file_info->{fasta};
	$job->{meta}->{source_qual} = $file_info->{qual} if exists $file_info->{qual};
      
	push @$jobs, $job;
  }
    
    
  # create the jobs
  my $ids = [];
  foreach my $job (@$jobs) {
    
    my ($jobid, $msg) = Job48->create_new_job($job);
    if ($jobid) {
      push @$ids, $jobid;
    }
    else {
      $self->app->add_message('warning', "There has been an error uploading your jobs: <br/> $msg");
    }
  }
	  
  my $content = '';
  if(scalar(@$ids)) {
    $content .= '<p><strong>Your upload will be processed as job(s) '.join(', ',@$ids).'.</strong></p>';
    $content .= "<p>Go back to the <a href='metagenomics.cgi?page=UploadMetagenome'>metagenome upload page</a>".
      " to add another annotation job.</p>";
    $content .= "<p>You can view the status of your project on the <a href='metagenomics.cgi?page=Jobs'>status page</a>.</p>";
  }
  else {
    $content .= "<p><em>Failed to upload any jobs.</em></p>";
    $content .= "<p> &raquo <a href='metagenomics.cgi?page=UploadMetagenome'>Start over the metagenome upload</a></p>";
  }

  return $content;



}

=pod

=item * B<save_upload_to_incoming> ()

Stores a file from the upload input form to the incoming directory
in the rast jobs directory. If successful the method writes back 
the two cgi parameters I<upload_file> and I<upload_type>.

=cut

sub save_upload_to_incoming {
  my ($self) = @_;

  return if ($self->application->cgi->param("upload_file") and
	     $self->application->cgi->param("upload_type"));

  if ($self->application->cgi->param("upload")) {

    my $upload_file = $self->application->cgi->param('upload');	
    my ($fn, $dir, $ext) = fileparse($upload_file, qr/\.[^.]*/);
    
    my $file = File::Temp->new( TEMPLATE => $self->app->session->user->login.'_'.
				            $self->app->session->session_id.'_XXXXXXX',
				DIR => $FIG_Config::mgrast_jobs . '/incoming/',
				SUFFIX => $ext,
				UNLINK => 0,
			      );

    my($buf, $n);
    while (($n = read($upload_file, $buf, 4096)))
    {
	print $file $buf;
    }
    $file->close();
    
    chmod 0664, $file->filename;
    
    # set info in cgi
    $self->application->cgi->param('upload_file', $file->filename);
    my $type = $self->determine_file_format($file->filename);
    $self->application->cgi->param('upload_type', $type);
  }
}


=pod

=item * B<list_files_from_upload> ()

Returns the list of individual files that have been uploaded. If a single
file was uploaded, that files name is returned. If an archive was uploaded,
a list of all files in the archive is returned. Files are returned as
full pathnames. Semantic processing of what files are of what type is
left to the caller.

=cut

sub list_files_from_upload {
    my ($self) = @_;
    
    my @files;

    if ($self->application->cgi->param("upload_file")) {
	
	my $file = $self->application->cgi->param("upload_file") || '';

	my $type = $self->application->cgi->param('upload_type');
	if ($type eq 'archive/tar' or $type eq 'archive/zip')
	{
	    #
	    # Untar the file, since we need to have it extracted at some
	    # point anyway.

	    my $targ = "$file.extract";
	    mkdir($targ);
	    my @content;
	    eval {
		if ($type eq 'archive/tar')
		{
		    @content = untar_file($file, $targ);
		}
		elsif ($type eq 'archive/zip')
		{
		    @content = unzip_file($file, $targ);
		}
	    };
	    if ($@)
	    {
		$self->application->error("Error unpacking uploaded tarfile: $@");
		return;
	    }

	    @files = @content;
#	    foreach my $file (@content)
#	    {
#		my $format = $self->determine_file_format($file);
#		push @files, basename($file) if ($self->is_acceptable_format($format));	  
#	    }

	}
	elsif ($self->application->cgi->param('upload_type') eq 'fasta') {
	    push @files, $file;
	}
	else {
	    $self->application->error('Unknown file type during upload.');
	    return;
	}
	
    }
    $self->application->cgi->param('upload_file_list', \@files);
    return \@files;
}

sub untar_file
{
    my($tar, $target_dir) = @_;

    my $comp_flag;
    if ($tar =~ /gz$/)
    {
	$comp_flag = "-z";
    }
    elsif ($tar =~ /bz2$/)
    {
	$comp_flag = "-j";
    }
    else
    {
	my $ftype = `file $tar`;
	if ($ftype =~ /gzip/)
	{
	    $comp_flag = "-z";
	}
	elsif ($ftype =~ /bzip2 compressed/)
	{
	    $comp_flag = "-j";
	}
    }
    
    my @tar_flags = ("-C", $target_dir, "-v", "-x", "-f", $tar, $comp_flag);
    
    warn "Run tar with @tar_flags\n";
    
    my(@tar_files);

    #
    # Extract and remember filenames.
    #
    # Need to do the 'safe-open' trick here since for now, tarfile names might
    # be hard to escape in the shell.
    #
    
    open(P, "-|", "tar", @tar_flags) or die("cannot run tar @tar_flags: $!");
    
    while (<P>)
    {
	chomp;
	my $path = "$target_dir/$_";
	warn "Created $path\n";
	push(@tar_files, $path);
    }
    if (!close(P))
    {
	die("Error closing tar pipe: \$?=$? \$!=$!");
    }

    return @tar_files;
}

sub unzip_file
{
    my($zip, $target_dir) = @_;

    my @unzip_flags = ("-o", $zip, "-d", $target_dir);
    
    warn "Run unzip with @unzip_flags\n";
    
    my(@files);

    #
    # Extract and remember filenames.
    #
    # Need to do the 'safe-open' trick here since for now, tarfile names might
    # be hard to escape in the shell.
    #
    
    open(P, "-|", "unzip", @unzip_flags) or die("cannot run unzip @unzip_flags: $!");
    
    while (<P>)
    {
	chomp;
	if (/^\s*[^:]+:\s+(.*?)\s*$/)
	{
	    my $path = $1;
	    if ($path !~ m,^/,)
	    {
		$path = "$target_dir/$path";
	    }
	    warn "Created $path\n";
	    push(@files, $path);
	}
    }
    if (!close(P))
    {
	die("Error closing unzip pipe: \$?=$? \$!=$!");
    }

    return @files;
}



=pod
    
=item * B<is_acceptable_format> (I<format>)

Returns true if that file format is accepted by this RAST server type

=cut

sub is_acceptable_format {
  my ($self, $format) = @_;
  
  return 1 if ($format and $format eq 'fasta');
  
  return 0;  
}


=pod

=item * B<determine_file_format> (I<filename>, I<dont_read>)

Returns the format type of the file: currently fasta, genbank or archive.
If I<dont_read> is provided and true, it will not try to read the file.

=cut

sub determine_file_format {
  my ($self, $file, $dont_read) = @_;

  my $format = '';
  my ($fn, $dir, $ext) = fileparse($file, qr/\.[^.]*/);

  # first let's try to check by file extension
  if ($ext =~ /\.(fasta|fa|fas|fsa|fna)$/i) {
    $format = 'fasta';
  }
  elsif ($ext =~ /\.(gbk|genbank|gb)$/) {
    $format = 'genbank';
  }
  elsif ($ext =~ /\.(qual)$/) {
    $format = 'qual';
  }
  elsif ($file =~ /\.tgz$/ or 
	 $file =~ /\.tar\.gz$/ or
	 $file =~ /\.gz$/) {
    $format = 'archive/tar';
  }
  elsif ($file =~ /\.zip$/) {
    $format = 'archive/zip';
  }

  warn "dff: file='$file' fn='$fn' ext='$ext' fmt=$format\n";
  return $format if ($format or $dont_read);

  # file extension didnt tell us anything, let's read some lines
  my $line = 0;
  open(FILE, "<$file") ||
    die "Unable to read file $file.";
  while(<FILE>) {
    $line++;
    chomp;
    next unless $_;
    if (/LOCUS\s+(\S+)/os) {
      $format = 'genbank';
      last;
    }
    elsif (/^>(\S+)/) {
      $format = 'fasta';
      last;
    }
    
    # after 10 lines we give up
    last if ($line>10);

  }
  close(FILE);

  return $format;

}



=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  return [ [ 'login' ], ];
}

sub new_upload {
  my ($self) = @_;

  my $application = $self->application;
  my $jobmaster = $application->data_handle('MGRAST');
  my $user = $application->session->user;

  my $job = $jobmaster->reserve_job($jobmaster, $user);
  
  my $content = "";
  
  if (ref($job)) {
    $content = "<img src='./Html/clear.gif' onload='window.open(\"metagenomics.cgi?page=MetaDataMG&from_upload=1&metagenome=".$job->genome_id."\");document.getElementById(\"metagenome_id\").value=\"".$job->genome_id."\";document.forms.upload_form.submit();'>";
  } else {
    $content = "<p style='color: red'>job creation failed</p>";
  }

  return $content;
}
