package MGRAST::WebPage::MetagenomeUpload;

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
use Conf;
use WebConfig;
use base qw( WebPage );

1;


=pod

=head1 NAME

MetagenomeUpload - upload a metagenome job

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
  $self->application->register_component('Ajax', 'ajax');

}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  unless ($user) {
    return "<p>You must be logged in to upload a metagenome.</p><p>Please use the login box in the top right corner or return to the <a href='metagenomics.cgi'>start page</a>.</p>";
  }

  my $content = '<h1>Upload a metagenome</h1>';

  $content .= $application->component('ajax')->output();

  my $current_step = $cgi->param('step') || "file_upload";
  
  my $tab_view = $self->application->component('Tabs');
  $tab_view->width(800);
  $tab_view->height(180);

  if ($current_step eq "file_upload") {
    $tab_view->add_tab('upload file', $self->file_upload());
    $tab_view->add_tab('validate file', '', undef, 1);
    $tab_view->add_tab('finish submission', '', undef, 1);
    $tab_view->default(0);
    $content .= $tab_view->output;
    return $content;
  } elsif ($current_step eq "validate_file") {
    $tab_view->add_tab('upload file', '', undef, 1);
    $tab_view->add_tab('validate file', $self->validate_file());
    $tab_view->add_tab('finish submission', '', undef, 1);
    $tab_view->default(1);
    $content .= $tab_view->output;
    return $content;
  } elsif ($current_step eq "finish_submission") {
    $tab_view->add_tab('upload file', '', undef, 1);
    $tab_view->add_tab('validate file', '', undef, 1);
    $tab_view->add_tab('finish submission', $self->finish_submission());
    $tab_view->default(2);
    $content .= $tab_view->output;
    return $content;
  } else {
    $application->add_message('warning', "unknown step in upload process");
    return "";
  }
}

=item * B<file_upload> ()

Returns the initial file upload page for metagenomes

=cut

sub file_upload {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi = $application->cgi;

  # upload info text
  my $content = "<h3>file requirements</h3>";
  $content .= "<p><li>The upload sequence data must be in <a href='http://en.wikipedia.org/wiki/Fasta_format' target=_blank>FASTA format</a> containing nucleotide sequences only in a plain text file,</li>";
  $content .="<li>large files can be compressed using <a href='http://en.wikipedia.org/wiki/Gzip' target=_blank>gzip</a> or <a href='http://en.wikipedia.org/wiki/ZIP_%28file_format%29' target=_blank>zip</a>,</li>"; 
  $content .= "<li>you may upload multiple files in a single archived file created with <a href='http://en.wikipedia.org/wiki/Tar_%28file_format%29' target='_blank'>tar</a> and gzip or as a <a href='http://en.wikipedia.org/wiki/Zip_archive' target=_blank>zip archive.</a>,</li>";
  $content .= "<li>a compressed archive file can contain multiple sequence files, each will be treated as a distinct metagenome MG-RAST job,</li>";
  $content .= "<li>you may upload a quality file (.qual) along with each FASTA file in the archive,</li>";
  $content .= "<li>you may upload an abundance file (.abundance) along with each FASTA file in the archive,</li>";
  $content .= "<li>you can split a single FASTA file (demultiplex) into multiple MG-RAST jobs by supplying the multiplex identifiers (MID) tags</li>";
  $content .= "</ul></p>";

  # create upload information form
  
  $content .= $self->start_form('upload_form');

  $content .= "Create ";
  $content .= "<input type='radio' name='sample_number' value='one' onclick='document.getElementById(\"one_sample\").style.display=\"inline\"; document.getElementById(\"multiple_samples\").style.display=\"none\";'>a single MG-RAST job";
  $content .= "<input type='radio' name='sample_number' value='more_than_one' onclick='document.getElementById(\"one_sample\").style.display=\"none\"; document.getElementById(\"multiple_samples\").style.display=\"inline\";'>multiple MG-RAST jobs<p>";

  $content .= "<div id='one_sample' style='display: none;'>";
  $content .= "<div id='ajax_upload_div'></div>";
  $content .= "<fieldset><legend> File Upload: </legend>";
  $content .= "<table>";
  $content .= "<tr><td>Sequence File</td><td><input type='file' name='upload_one_sample' size='50'></td></tr>";
  $content .= "</table></fieldset>";
  $content .= "<input type='hidden' name='metagenome_id' value='' id='metagenome_id'><input type='hidden' name='step' value='validate_file'>";
  $content .= "<p><input type='button' value='Upload file and go to step 2, also open new window with metadata editor' onclick='execute_ajax(\"new_upload\", \"ajax_upload_div\", \"x=y\");'></p>";
  $content .= "</div>";

  $content .= "<div id='multiple_samples' style='display: none;'>";
  $content .= "<fieldset><legend> File Upload: </legend>";
  $content .= "<table>";
  $content .= "<tr><td>Sequence File</td><td><input type='file' name='upload_multiple_samples' size='50'></td></tr>";
  $content .= "<tr><td>Multiplex tags</td><td><textarea cols=50 rows=10 name='mid_tags'></textarea></td></tr>";
  $content .= "</table></fieldset>";
  $content .= "<p><input type='submit' value='Upload file and go to step 2'></p>";
  $content .= "</div>";

  $content .= $self->end_form();

  return $content;
}

sub validate_file {
    my ($self) = @_;
    
    my $application = $self->application;
    my $jobmaster   = $application->data_handle('MGRAST');
    my $user        = $application->session->user;

    my $cgi = $application->cgi;
    
    # check for recent file in the upload form
    unless ($cgi->param("upload_one_sample") or $cgi->param('upload_multiple_samples')) {
	$application->add_message('warning', "no upload file received, aborting");
	return "";
    } else {
	my $upload;
	if ( $cgi->param('upload_one_sample') ) {
	    $cgi->param(-name=>'upload', -value=>$cgi->param('upload_one_sample'));
	} else {
	    $cgi->param(-name=>'upload', -value=>$cgi->param('upload_multiple_samples'));
	}
 	my @mid_tags = ();
 	if ( $cgi->param('mid_tags') ) {
 	    foreach my $tag ( split(/[,\s]+/, $cgi->param('mid_tags')) ) {
 		if ( $tag =~ /^[acgtACGT]+$/ ) {
 		    push @mid_tags, $tag;
 		} else {
 		    $application->add_message('warning', "Multiplexing identifier tag contains non-nucleotide characters '$tag', aborting");
 		    return "";
 		}
 	    }
 	}

	my($filename, $type) = $self->save_upload_to_incoming();

	my $content;
	
	if ( $type eq 'not found' ) {
	    $content = '<p><strong>The upload failed, please try again from the beginning</strong></p>';
	    return $content;
	}
	elsif ( $type eq 'zero size' ) {
	    $content = '<p><strong>The uploaded file does not contain any data, please check your local file and try again from the beginning</strong></p>';
	    return $content;
	}
	elsif ( $type eq 'ASCII text, with CR, LF line terminators' or
		$type eq 'ASCII text, with CRLF, LF line terminators' or
		$type eq 'ASCII text, with CRLF, CR line terminators' ) {
	    $content = '<p><strong>The uploaded file contains mixed end of line characters, please make it consistent and resubmit</strong></p>';
	    return $content;
	} 
	elsif ( $type eq 'bzip2 compressed data' ) {
	    $content = '<p><strong>The uploaded file contains is compressed with bzip2, please use gzip or Zip and resubmit</strong></p>';
	    return $content;
	}
	elsif ( $type eq 'RAR archive' ) {
	    $content = '<p><strong>The uploaded file is an RAR archive, please use gzip and tar or Zip and resubmit</strong></p>';
	    return $content;
	}
	elsif ( $type eq 'ISO-8859 text' ) {
	    $content = '<p><strong>The uploaded file is formatted as ISO-8859 text, please edit it to make it plain ASCII and resubmit</strong></p>';
	    return $content;
	}
	elsif ( $type eq 'Rich text format' ) {
	    $content = '<p><strong>The uploaded file is formatted as Rich Text Format (RTF), please edit it to make it plain ASCII and resubmit</strong></p>';
	    return $content;
	}
	else
	{
	    #
	    # Unpack data if necessary and get a listing of files.
	    #
	    
	    my $flist;
	    my $files = [];
	    $content = "<p><strong> uploaded one $type file</srtong><p>"; # ''; # '<p><strong>Uploaded one **'.$type.'** file. </strong></p>';
	    
	    # don't create target directory here, may not be needed
	    my $target_dir = $filename . '.extract';
	    
	    if ( $type eq 'tar archive' ) {
		$files = &untar_file($filename, $target_dir);
	    }
	    elsif ( $type eq 'gzip compressed data' ) {
		$files = &gunzip_file($filename, $target_dir);
	    }
	    elsif ( $type eq 'Zip archive data' ) {
		$files = &unzip_file($filename, $target_dir);
	    }
	    else {
		$files = [$filename];
	    }

	    if ( @$files == 1 and @mid_tags )
	    {
		# multiplexed file, report original file data before demultiplexing
		my $file        = $files->[0];
		my $file_report = &file_report($file);
		my $file_type   = &file_type($file);
		my $file_eol    = &file_eol($file_type);
		my $target_dir  = $file . '.mid_extract';
		$files          = &split_fasta_by_mid_tag($files->[0], $file_eol, $target_dir, \@mid_tags);
		my($file_base, $file_path, $file_suffix) = fileparse($file, qr/\.[^.]*$/);

		$content .= "<table width=\"100%\"><tr><th colspan='2'>Uploaded file:</th></tr>\n";

		my %bases;
		    
		if ( ref $file_report ) 
		{
		    $bases{$file_base}{fasta} = $file;
		    
		    $content .= "<tr><th align='left'>$file_base$file_suffix</th><th>&nbsp;</th></tr>\n";
		    $content .= "<tr><td align='right'>size:</td><td>$file_report->{size} bytes</td></tr>\n";
		    $content .= "<tr><td align='right'>\# sequences:</td><td>$file_report->{n_ids}</td></tr>\n";
		    $content .= "<tr><td align='right'>sequence data:</td><td>$file_report->{bp} bp</td></tr>\n";
		    $content .= "<tr><td align='right'>average sequence length:</td><td>$file_report->{average_length} bp</td></tr>\n";
		    $content .= "<tr><td align='right'>longest sequence length:</td><td>$file_report->{longest_length} bp ($file_report->{longest_id})</td></tr>\n";
		    $content .= "<tr><td align='right'>shortest sequence length:</td><td>$file_report->{shortest_length} bp ($file_report->{shortest_id})</td></tr>\n";
			
		    if ( @{ $file_report->{duplicate_seq} } ) {
			$content .= "<tr><td align='right'>duplicate sequences:</td><td>yes</td></tr>\n";
		    }
		    else {
			$content .= "<tr><td align='right'>duplicate sequences:</td><td>none</td></tr>\n";
		    }
		    
		    if ( @{ $file_report->{duplicate_id} } ) {
			$content .= "<tr><td align='right'>duplicate IDs:</td><td><font color='#CC0000'>yes</font></td></tr>\n";
		    }
		    else {
			$content .= "<tr><td align='right'>duplicate IDs:</td><td>none</td></tr>\n";
		    }
		} 
		else 
		{
		    $content .= "<tr><th>$file_base$file_suffix</th><th><font color='#CC0000'>$file_report</font></th></tr>\n";
		    $content .= "</table>\n";
		    return $content;
		}
	    }
	    
	    if ( @$files ) 
	    {
		my $sample_number = $cgi->param('sample_number');

		if ( $sample_number eq 'one' and @$files > 1 )
		{
		    # a single metagenome ID has already been assigned and the metadata editor was opened for this metagenome ID, 
		    # multiple jobs cannot be handled at this stage

		    my $file_list = "<ul><li>" . join("\n<li>", sort @$files) . "\n</ul>";
		    $self->app->add_message('warning', "There has been an error uploading your jobs: <br/> The option single sample was selected and more than one fasta file was found<br>$file_list");
		    return;
		}
		elsif ( $sample_number eq 'more_than_one' and @$files == 1 )
		{
		    # no metagenome IDs assigned, metadata editor was not opened, 
		    # can handle either multiple OR single file
		    # issue warning, not fatal

		    my $file_list = "<ul><li>" . join("\n<li>", sort @$files) . "\n</ul>";
		    $self->app->add_message('warning', "The option multiple samples was selected and only one fasta file was found<br>$file_list");
		}

		$content .= $self->start_form('validation_form', { metagenome_id => $cgi->param('metagenome_id'), step => 'finish_submission' });

		my $title = @mid_tags? 'De-multiplexed files' : 'Uploaded files';
		$content .= "<table width=\"100%\"><tr><th colspan='2'>$title:</th></tr>\n";
		
		$content .= "<tr><th align='right'>Project Name:</th><th><input type='text' value='' name='project_name' size=50></th></tr>\n";

		
		my %bases;
		foreach my $file ( @$files )
		{
		    my($file_base, $file_path, $file_suffix) = fileparse($file, qr/\.[^.]*$/);
		    if ( $file_suffix eq '.qual' ) {
			$bases{$file_base}{qual} = $file;
		    } elsif ( $file_suffix eq '.abundance' ) {
			$bases{$file_base}{abundance} = $file;
		    }
		}
		
		# iterate through the unpacked or de-multiplexed files
		my $i = 0;
		foreach my $file ( sort @$files )
		{
		    my($file_base, $file_path, $file_suffix) = fileparse($file, qr/\.[^.]*$/);
		    $file_suffix ||= '';

		    next if ($file_suffix eq '.qual');

		    # fasta file if reached here
		    $i++;

		    if ( $cgi->param('metagenome') )
		    {
			$content .= "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'>\n";
		    }

		    my $file_report = &file_report($file);

		    if ( ref $file_report ) 
		    {
			$bases{$file_base}{fasta} = $file;
			
			$content .= "<input type='hidden' name='upload_fasta_file.$i' id='upload_fasta_file' value='$file'>\n";
			$content .= "<input type='hidden' name='file_size.$i' value='$file_report->{size}'>\n";
			$content .= "<input type='hidden' name='file_number_sequences.$i' value='$file_report->{n_ids}'>\n";			
			$content .= "<input type='hidden' name='file_number_base_pairs.$i' value='$file_report->{bp}'>\n";
			$content .= "<input type='hidden' name='sequence_average_length.$i' value='$file_report->{average_length}'>\n";
			$content .= "<input type='hidden' name='sequence_longest_length.$i' value='$file_report->{longest_length}'>\n";
			$content .= "<input type='hidden' name='sequence_shortest_length.$i' value='$file_report->{shortest_length}'>\n";
			$content .= "<input type='hidden' name='sequence_longest_id.$i' value='$file_report->{longest_id}'>\n";
			$content .= "<input type='hidden' name='sequence_shortest_id.$i' value='$file_report->{shortest_id}'>\n";

			$content .= "<tr><th align='left' colspan=2>$i. $file_base$file_suffix</th></tr>\n";
			$content .= "<tr><th align='right'>Metagenome Name:</th><th><input type='text' value='' name='metagenome_name.$i' size=50></th></tr>\n";
			$content .= "<tr><td align='right'>size:</td><td>$file_report->{size} bytes</td></tr>\n";
			$content .= "<tr><td align='right'>\# sequences:</td><td>$file_report->{n_ids}</td></tr>\n";
			$content .= "<tr><td align='right'>sequence data:</td><td>$file_report->{bp} bp</td></tr>\n";
			$content .= "<tr><td align='right'>average sequence length:</td><td>$file_report->{average_length} bp</td></tr>\n";
			$content .= "<tr><td align='right'>longest sequence length:</td><td>$file_report->{longest_length} bp ($file_report->{longest_id})</td></tr>\n";
			$content .= "<tr><td align='right'>shortest sequence length:</td><td>$file_report->{shortest_length} bp ($file_report->{shortest_id})</td></tr>\n";
			
			if ( @{ $file_report->{duplicate_seq} } ) {
			    $content .= "<tr><td align='right'>duplicate sequences:</td><td>yes</td></tr>\n";
			    $content .= "<input type='hidden' name='duplicate_sequences.$i' value='1'>\n";
			}
			else {
			    $content .= "<tr><td align='right'>duplicate sequences:</td><td>none</td></tr>\n";
			    $content .= "<input type='hidden' name='duplicate_sequences.$i' value='0'>\n";
			}
			
			if ( @{ $file_report->{duplicate_id} } ) {
			    $content .= "<tr><td align='right'>duplicate IDs:</td><td><font color='#CC0000'>yes</font></td></tr>\n";
			    $content .= "<input type='hidden' name='duplicate_sequence_ids.$i' value='1'>\n";
			}
			else {
			    $content .= "<tr><td align='right'>duplicate IDs:</td><td>none</td></tr>\n";
			    $content .= "<input type='hidden' name='duplicate_sequence_ids.$i' value='0'>\n";
			}
			
			if ( exists $bases{$file_base}{qual} ) {
			    $content .= "<tr><td align='right'>quality file:</td><td>$file_base\.qual</td></tr>\n";
			    $content .= "<input type='hidden' name='upload_qual_file.$i' id='upload_qual_file' value='$file'>\n";
			}
			else {
			    $content .= "<tr><td align='right'>quality file:</td><td>not found</td></tr>\n";
			}

			if ( exists $bases{$file_base}{abundance} ) {
			    $content .= "<tr><td align='right'>abundance file:</td><td>$file_base\.abundance</td></tr>\n";
			    $content .= "<input type='hidden' name='upload_abundance_file.$i' id='upload_abundance_file' value='$file'>\n";
			}
			else {
			    $content .= "<tr><td align='right'>abundance file:</td><td>not found</td></tr>\n";
			}
		    }
		    else {
			$content .= "<tr><th>$file_base$file_suffix</th><th><font color='#CC0000'>$file_report</font></th></tr>\n";
		    }
		}
		
		$content .= "<tr><th colspan='2'>Options:</th></tr>\n";
		
		$content .= "<tr><td align='right'>RNA sequences only:</td>\n";
		$content .= "<td><input type='radio' name='rna_only' value='0' checked>&nbsp;no&nbsp;&nbsp;&nbsp;<input type='radio' name='rna_only' value='1'>&nbsp;yes\n</td></tr>";
		
		$content .= "<tr><td align='right'>dereplicate sequences:</td>\n";
		$content .= "<td><input type='radio' name='dereplicate' value='0' checked>&nbsp;no&nbsp;&nbsp;&nbsp;<input type='radio' name='dereplicate' value='1'>&nbsp;yes\n</td></tr>";
	    

		$content .= "<tr><td align='right'>assembled sequences:</td>\n";
		$content .= "<td><input type='radio' name='assembled' value='0' checked>&nbsp;no&nbsp;&nbsp;&nbsp;<input type='radio' name='assembled' value='1'>&nbsp;yes\n</td></tr>";
	    
		$content .= "</table>\n";
		$content .= "<p><input type='submit' value='Approve options and go to step 3'></p>";
		$content .= $self->end_form();
		
		return $content;
	    }
	    else
	    {
		$content .= "<p><em>Unfortunately I have not been able to unpack any files from the upload.</em></p>";
		$content .= "<p> &raquo <a href='metagenomics.cgi?page=MetagenomeUpload'>Please check the file format and start the metagenome upload again.</a></p>";
		
		return $content;
	    }
	}
    }
}

=item * B<finish_submission> ()

Finalizes the upload by creating the job directories

=cut

sub finish_submission {
    my ($self) = @_;
    
    my $application = $self->application;
    my $cgi = $application->cgi;
    my $user = $application->session->user;

    # prepare data to create job dirs
    my $jobs = [];

    # get indices for fasta files from cgi args like upload_fasta_file.1, upload_fasta_file.2, ...
    my @index_list = sort {$a <=> $b} map {/^upload_fasta_file\.(\d+)/; $1} grep {/^upload_fasta_file/} $cgi->param;

    foreach my $index ( @index_list )
    {
	my $job = {
	            'project'     => $cgi->param('project_name'),
 		    'genome'      => $cgi->param("metagenome_name.$index"),

		    'upload'      => $cgi->param("upload_fasta_file.$index"),
		    'qual'        => $cgi->param("upload_qual_file.$index") || '',
		    'abundance'   => $cgi->param("upload_abundance_file.$index") || '',
		    
 		    'user'        => $user->login,
 		    'taxonomy'    => '',
 		    'metagenome'  => 1,
 		    'meta'        => { 
			               'source_file'    => $cgi->param("upload_fasta_file.$index"),
			               'qual_file'      => $cgi->param("upload_qual_file.$index") || 'not_found',
			               'abundance_file' => $cgi->param("upload_abundance_file.$index") || 'not_found',

				       'file_size'                => $cgi->param("file_size.$index"),
				       'file_number_base_pairs'   => $cgi->param("file_number_base_pairs.$index"),
				       'sequence_average_length'  => $cgi->param("sequence_average_length.$index"),
				       'sequence_longest_length'  => $cgi->param("sequence_longest_length.$index"),
				       'sequence_shortest_length' => $cgi->param("sequence_shortest_length.$index"),
				       'sequence_longest_id'      => $cgi->param("sequence_longest_id.$index"),
				       'sequence_shortest_id'     => $cgi->param("sequence_shortest_id.$index"),

				       'options.rna_only'    => $cgi->param('rna_only') || 0,
				       'options.dereplicate' => $cgi->param('dereplicate') || 0,
				       'options.assembled'   => $cgi->param('assembled') || 0,
				   },
		};
	
	push @$jobs, $job;
    }

    # create the jobs
    my $ids = [];
    my $first = 1;
    my @job_ids = ();
    my @metagenome_ids = ();

    foreach my $job (@$jobs) 
    {
	my $jobmaster = $application->data_handle('MGRAST');
    
	my $job_object;
	if ($cgi->param('metagenome_id')) {
	    $job_object = $jobmaster->Job->get_objects( { genome_id => $cgi->param('metagenome_id') } );
	    $job_object = $job_object->[0];
	} else {
	    $job_object = $jobmaster->Job->reserve_job($jobmaster, $user);
	}

	$job->{metagenome_id} = $job_object->{genome_id};
	$job->{jobnumber} = $job_object->{id};
	
	my ($jobid, $msg) = $self->create_new_job_local($job);
	if ($jobid) {
	    push @$ids, $jobid;
	    push @metagenome_ids, $job->{metagenome_id};
	}
	else {
	    $self->app->add_message('warning', "There has been an error uploading your jobs: <br/> $msg");
	}
    }
    
    my $content = '';
    if(scalar(@$ids)) {
	$content .= '<p><strong>Your upload will be processed as job(s) '.join(', ', @$ids).'.</strong></p>';

	if ( @metagenome_ids > 1 )
	{
	    my $metadata_href = "metagenomics.cgi?page=MetaDataMG&from_upload=1&metagenome=". join(',', @metagenome_ids);
	    $content .= "<p><strong>Next please enter the <a href='$metadata_href'>metadata</a> for these jobs to complete the upload process.</strong></p>";
	    $content .= "<p>When you are completed you can go back to the <a href='metagenomics.cgi?page=MetagenomeUpload'>metagenome upload page</a> to add another annotation job.</p>";
	}
	else
	{
	    $content .= "<p>Go back to the <a href='metagenomics.cgi?page=MetagenomeUpload'>metagenome upload page</a> to add another annotation job.</p>";
	}


	$content .= "<p>The status of your jobs can be checked on the <a href='metagenomics.cgi?page=Jobs'>status page</a>.</p>";
    }
    else {
	$content .= "<p><em>Failed to upload any jobs.</em></p>";
	$content .= "<p> &raquo <a href='metagenomics.cgi?page=MetagenomeUpload'>Start over the metagenome upload</a></p>";
    }
    
    return $content;
}

#
# create new job directory on disk
#
sub create_new_job_local {
    my ($self, $job) = @_;
    
    my $jobs_dir = $Conf::mgrast_jobs;
    my $job_dir  = $jobs_dir . '/' . $job->{jobnumber};
    
    unless (-d $job_dir) {
	return (undef, 'The job directory could not be created.');
    }
    
    mkdir "$job_dir/raw" or die "could not open raw directory '$job_dir/raw'";

    # save uploaded file to raw directory
    my $raw_fasta_file = "$job_dir/raw/" . $job->{metagenome_id} . '.fa';
    copy($job->{upload}, $raw_fasta_file) or die "could not copy file to $raw_fasta_file: $!";

    # copy quality file if found
    if ( $job->{qual} ) {
	my $raw_qual_file = "$job_dir/raw/" . $job->{metagenome_id} . '.qual';
	copy($job->{qual}, $raw_qual_file) or die "could not copy file to $raw_qual_file: $!";
    }

    # copy abundance file if found
    if ( $job->{abundance} ) {
	my $raw_abundance_file = "$job_dir/raw/" . $job->{metagenome_id} . '.abundance';
	copy($job->{abundance}, $raw_abundance_file) or die "could not copy file to $raw_abundance_file: $!";
    }

    open(FH, ">". "$job_dir/MGRAST3");
    close(FH);

    open(FH, ">" . $job_dir . "/GENOME") or die "could not open GENOME file in $job_dir: $!";
    print FH $job->{genome}."\n";
    close FH;
    
    open(FH, ">" . $job_dir . "/PROJECT") or die "could not open PROJECT file in $job_dir: $!";
    print FH $job->{project}."\n";
    close FH;
  
#    open(FH, ">" . $job_dir . "/TAXONOMY") or die "could not open TAXONOMY file in $job_dir: $!\n";
#    print FH $job->{'taxonomy'}."\n";
#    close FH;
  
    open(FH, ">" . $job_dir . "/GENOME_ID") or die "cannot open GENOME_ID file in $job_dir: $!";
    print FH $job->{metagenome_id}."\n";
    close(FH);
  
    open(FH, ">" . $job_dir . "/USER") or die "cannot open USER file in $job_dir: $!";
    print FH $job->{user}."\n";
    close(FH);

#    $meta->add_log_entry("genome", "Created metadata files.");
  
    open(FH, ">" . $job_dir . "/ACTIVE") or die "cannot open ACTIVE file in $job_dir: $!";
    close(FH);

    open(FH, ">" . $job_dir . "/META") or die "cannot open META file in $job_dir: $!";
    if (defined $job->{'meta'} and ref $job->{meta} eq 'HASH') 
    {
	$job->{meta}{'upload.timestamp'} = time;
	$job->{meta}{'status.uploaded'}  = 'complete';

	foreach my $key ( sort keys %{ $job->{meta} } ) {
	    print FH $key, "\t", $job->{meta}{$key}, "\n";
	}
    }  
    close(FH);
    
    return ($job->{jobnumber}, '');
}

=pod

=item * B<save_upload_to_incoming> ()

Stores a file from the upload input form to the incoming directory
in the rast jobs directory. If successful the method writes back 
the two cgi parameters I<upload_file> and I<upload_type>.

=cut

sub save_upload_to_incoming {
  my ($self) = @_;

  my $upload_file = $self->application->cgi->param('upload');	
  my ($fn, $dir, $ext) = fileparse($upload_file, qr/\.[^.]*/);
  
  my $file = File::Temp->new( TEMPLATE => $self->app->session->user->login.'_'.
			      $self->app->session->session_id.'_XXXXXXX',
			      DIR => $Conf::mgrast_jobs . '/incoming/',
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
  
  my $type = &file_type($file->filename);

  return ($file->filename, $type);
}


=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  return [ [ 'login' ], ];
}


=pod

=item * B<new_upload>()

Ajax method which reserves a job, sets the metagenome field in the upload
form to the metagenome id of the reserved job, submits the upload form and
simultaniously opens a window for the MetaData Editor, passing the metagenome
id.

=cut

sub new_upload {
  my ($self) = @_;

  my $application = $self->application;
  my $jobmaster = $application->data_handle('MGRAST');
  my $user = $application->session->user;

  my $job = $jobmaster->Job->reserve_job($jobmaster, $user);

  my $content = "";

  if (ref($job)) {
    $content = "<img src='./Html/clear.gif' onload='window.open(\"metagenomics.cgi?page=MetaDataMG&from_upload=1&metagenome=".$job->genome_id."\");document.getElementById(\"metagenome_id\").value=\"".$job->genome_id."\";document.forms.upload_form.submit();'>";
  } else {
    $content = "<p style='color: red'>job creation failed</p>";
  }

  return $content;
}
