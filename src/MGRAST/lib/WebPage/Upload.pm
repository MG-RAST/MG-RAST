package MGRAST::WebPage::Upload;

use strict;
use warnings;
no warnings('once');
use Data::Dumper;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use JSON;
use Encode;
use Number::Format qw(format_bytes);
use LWP::UserAgent;

use Conf;
use WebConfig;
use Mail::Mailer;
use MGRAST::Metadata;
use HTML::Entities;

use base qw( WebPage );

1;

=pod

=head1 NAME

Upload - upload files and display uploaded files to user for creation of jobs

=head1 DESCRIPTION

Page used by user to upload files and create jobs from uploaded files

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Data Submission");
  $self->{icon} = "<img src='./Html/mg-upload.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  $self->application->register_action($self, 'check_for_duplicates', 'check_for_duplicates');
  $self->application->register_action($self, 'send_email_for_duplicate_submission', 'send_email_for_duplicate_submission');
  $self->application->register_action($self, 'check_project_name', 'check_project_name');
  $self->application->register_action($self, 'validate_metadata', 'validate_metadata');
  $self->application->register_action($self, 'submit_to_mgrast', 'submit_to_mgrast');
  $self->application->register_action($self, 'generate_webkey', 'generate_webkey');
  $self->application->register_action($self, 'read_status_file', 'read_status_file');

  $self->application->register_component('Table', 'sequence_table');

}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  return "<p>This URL is deprecated. Please <a href='Html/mgmainv3.html?mgpage=upload'>click here</a> and then update your bookmark.</p>";
  
  my $application = $self->application;
  my $cgi         = $application->cgi;
  my $user        = $application->session->user;

  my $jobdb = $application->data_handle('MGRAST');
  
  unless ($user) {
    return "<p>You must be logged in to upload metagenome files and create jobs.</p><p>Please use the login box in the top right corner or return to the <a href='?page=Home'>start page</a>.</p>";
  }
  
  my $lock_file = $Conf::locks.'/upload.lock';
  if (-e $lock_file) {
    my $message = "We have temporarily suspended uploads for maintenance purposes, please try again later";
    if (-s $lock_file) {
      my @lines = `cat $lock_file`;
      $message  = join('', @lines);
    }
    $application->add_message('warning', $message);
    $self->title("Upload suspended");
    return '';
  }

  my $json = new JSON;
  $json = $json->utf8();
  my $ufo = { "login" => $user->login,
	      "auth" => $application->session->session_id };

  my $html = qq~<style>h3 {margin-top: 0px;}</style><div style='display: none;' id='uifo'>~.$json->encode($ufo).qq~</div><div style="width: 960px;" id="upload_area">
      <div>~;

  if ($cgi->param('create_job')) {
    my $success = $self->submit_to_mgrast();
    if ($success && @$success) {
      my $mgrast_ids = join(", ", @$success);
      $html .= qq~
<form style='margin:0;'>
  <div class="modal hide" id="successfulSubmissionModal" tabindex="-1" role="dialog" aria-labelledby="successfulSubmissionModalLabel" aria-hidden="true">
    <div class="modal-header">
      <button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>
      <h3 id="successfulSubmissionModalLabel">job submission successful</h3>
    </div>
    <div class="modal-body">
      <p>Your data has been successfully submitted to the pipeline. You can view the status of your submitted jobs <a href='?page=MetagenomeSelect'>here</a> and click on the number next to 'In Progress'.</p><p>Your MG-RAST IDs: $mgrast_ids</p>
    </div>
    <div class="modal-footer">
      <button class="btn" data-dismiss="modal" aria-hidden="true">OK</button>
    </div>
  </div>
</form>
<script>
\$('#successfulSubmissionModal').modal('show');
</script>
<div class='well'><h4>Job submission successful</h4><p>Your data has been successfully submitted to the pipeline. You can view the status of your submitted jobs <a href='?page=MetagenomeSelect'>here</a> and click on the number next to 'In Progress'.</p><p>Your MG-RAST IDs: $mgrast_ids</p></div>~;
    }
  }

  my $webkey = $self->current_webkey();

  my $user_project_ids = $user->has_right_to(undef, "edit", "project");
  my $projects = [];
  foreach my $pid (@$user_project_ids) {
    next if ($pid eq '*');
    my $p = $jobdb->Project->get_objects( { id => $pid } );
    if (scalar($p)) {
      push(@$projects, $p->[0]);
    }
  }
  my $template_link = "ftp://".$Conf::ftp_download."/data/misc/metadata/".$Conf::mgrast_metadata_template;
  $html .= qq~
<div class="well" style='width: 630px; float: left;'><h3>using the new mg-rast uploader:</h3>
<p>The tabs below will provide a workflow for you to first prepare and then submit your data.</p>
<p>Use <b>Prepare Data</b> to upload any fasta, fastq or SFF files and GSC MIxS compliant metadata files into your inbox. While metadata is not required at submission, the priority for processing data without metadata is lower. Metadata can be modified on the project page after submission. The inbox is a temporary storage location allowing you to assemble all files required for submission. After manipulating the files in your inbox, use <b>Data Submission</b> to create and/or add to existing projects. When the submission process has been successfully completed, MG-RAST ID's ("Accession numbers") will be automatically assigned and the data will be removed from your inbox.<p>

<p>You can monitor the progress of your jobs in the My Data Summary, on the Browse Metagenomes page.</p>
<p>Questions? Check out our <a href='http://blog.metagenomics.anl.gov/upload-data-v3-2/' target='blank'>tutorial and instructional videos</a>. Still having trouble? <a href="mailto:mg-rast\@mcs.anl.gov">Email us!</a></p>

<p><b>Note: All numbered sections below expand on click to display additional information and options.</b></p>
</div>
        <div class="well" style='width: 240px; float: right;'>
<h3>mini-faq</h3>
<ul class="unstyled">
<li><a href='http://metagenomics.anl.gov/metazen.cgi' target=_blank>Use MetaZen to create your metadata spreadsheet</a></li>
<li><a href='http://www.youtube.com/watch?v=pAf19exJo4o&feature=youtu.be' target=_blank>Uploading a metagenome (Video)</a></li>
<li><a href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#inbox' target=_blank>Inbox explained</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#command_line_submission' target=_blank>Automated submission via our API</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#preparing_metadata' target=_blank>Preparing metadata</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#job_priority' target=_blank>Priority assignments explained</a></li>
<li><a href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#accession_numbers' target=_blank>Obtaining Accession numbers</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#projects_on_upload_page' target=_blank>Which projects are shown in the dialogue?</a></li>
<li><a href='http://blog.metagenomics.anl.gov/upload-data-v3-2/' target=_blank>How should barcode files be formatted?</a></li>
</ul>
        </div>
<div class='clear'></div>
        <h1>Prepare Data</h1>

        <div class="row">
	  <div style="width: 960px; margin-left: 30px;">
             <ul class="nav nav-pills nav-stacked">
	      <li><a onclick="toggle('sel_mddownload_div');" class="pill_incomplete" id="sel_mddownload_pill" style="font-size: 17px; font-weight: bold;">1. prepare your metadata</a></li>
	      <div id="sel_mddownload_div" style="display: none;" class="well">
                 <h3>prepare your metadata</h3>
<p>Metadata (or data about the data) has become a necessity as the community generates large quantities of data sets.</p>
<p>We have found that the best form to capture metadata is via a simple spreadsheet with 12 mandatory terms. To get started on filling out your metadata spreadsheet, you can either download the blank template below, or you can try out <a href="http://metagenomics.anl.gov/metazen.cgi" target=_blank>Metazen</a>, a tool we have developed to try and make filling out our metadata spreadsheet a little easier.</p>
<p>Once you have filled out the blank template or the partially filled-in template from Metazen, you can upload it using the 'upload files' tab.</p>
                 <p><a href="$template_link"><img title="download metadata spreadsheet template" style="width: 20px; height: 20px;" src="./Html/mg-download.png"> download metadata spreadsheet template</a></p>
              </div>

             <li><a onclick="toggle('sel_upload_div');" class="pill_incomplete" id="sel_upload_pill" style="font-size: 17px; font-weight: bold;">2. upload files</a></li>
	     <div id="sel_upload_div" style="display: none;" class="well">
                 <h3>upload files</h4>
                 <table>
                    <tr>
                       <td>
                          <form class="form-horizontal">
                             <input class="input-file" type="file" multiple size=40 id="file_upload">
                          </form>
                       </td>
                       <td style="padding-left: 40px;">
                          <p>Select one or more files to upload to your private inbox folder.</p>
                          <p>Sequence files must be fasta, fastq, or sff format.
                             Use vaild file extensions for the appropriate format: .fasta, .fa, .ffn, .frn, .fna, .fq, .fastq, .sff </p>
                       </td>
                    </tr>
                 </table>
                 <div id="upload_progress" style="display: none;">
	              <br><h3>upload progress</h3><br>
	              <div id="uploaded_files" style="display: none;" class="alert alert-info">
	              </div>
	              <div id="progress_display">
	                 <table>
		           <tr>
                              <td colspan=2>
	                         <div class="alert alert-success" id="upload_status"></div>
                              </td>
		           </tr>
		           <tr>
		              <td style="width: 150px;"><h5>total</h5></td>
		              <td>
		                 <progress id="prog1" min="0" max="100" value="0" style="width: 400px;">0% complete</progress>
		              </td>
		           </tr>
		           <tr>
		              <td><h5>current file</h5></td>
		              <td>
		                 <progress id="prog2" min="0" max="100" value="0" style="width: 400px;">0% complete</progress>
    		              </td>
		           </tr>
                           <tr>
                              <td style="height: 50px;">
	                         <a class="btn btn-danger" href="#" onclick="cancel_upload();" style="position: relative; top: 5px; left: 435px;"><i class="icon-ban-circle"></i> cancel upload</a>
                              </td>
                           </tr>
	                </table>
 	             </div>
                  </div>
               
		  <p style='color:red;'><b>Note:</b> Uploaded files may be removed from your inbox after 72 hours.  Please perform submission of your files within that time frame.</p>
                  <p>In addition to using your web browser for uploads to the system the following alternatives are available:</p>
                  <table>
                     <tr style='display: none;'><td width="125px"><b>ftp</b></td><td>ftp://incoming.metagenomics.anl.gov/<span id="ftp_webkey">YOUR_PRIVATE_WEBKEY</span></td></tr>
                     <tr><td>http://api.metagenomics.anl.gov/1/inbox</td></tr>
                     <tr><td colspan=2 style='padding-top: 10px; padding-bottom: 10px;'><div id='generate_key'><input type='button' class='btn' onclick='generate_webkey();' value='~. ($webkey->{key} ? ($webkey->{valid} ? "view webkey" : "re-activate webkey") : "generate webkey") . qq~'></div></td></tr>
                  </table>
                  <p><b>Note:</b> The <a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#command_line_submission' target=_blank>Blog</a> lists a number of examples for data transfer.</p>

               </div>

               <li><a onclick="toggle('sel_inbox_div');" class="pill_incomplete" id="sel_inbox_pill" style="font-size: 17px; font-weight: bold;">3. manage inbox</a></li>
	       <div id="sel_inbox_div" style="display: none;" class="well">
<p>You can unpack, delete, convert and demultiplex files from your inbox below. Metadata files will automatically appear in the <i>'select metadata file'</i> section below. Sequence files will automatically appear in the <i>'select sequence file(s)'</i> section below after sequence statistics are calculated (may take anywhere from seconds to hours depending on file size).</p>
<p>Filenames in gray in your Inbox are undergoing analysis and cannot be moved or submitted to a different process until analysis is complete.  Filenames in red have encountered an error.</p>
                 <br>
                 <table border=0 cellpadding=4>
                   <tr >
                     <td colspan=2 style='font-size:14px;'><B>File Processing Operations</B></td>
                   </tr>
                   <tr>
                     <td><input type="button" class="btn" style='width:130px;' value="unpack selected" onclick="unpack_files();"></td>
                     <td width=250 style='vertical-align:middle;'>Unpacks selected zip, gzip, bzip2, tar gzip, or tar bzip2 files.</td>
                     <td><input type="button" class="btn" style='width:130px;' value="demultiplex" onclick="demultiplex_files();"></td>
                     <td width=250 style='vertical-align:middle;'>Demultiplexes selected files.</td>
                   </tr>
                   <tr>
                     <td><input type="button" class="btn" style='width:130px;' value="convert sff to fastq" onclick="convert_files();"></td>
                     <td width=250 style='vertical-align:middle;'>Converts selected sff files to fastq format.</td>
                     <td>
		       <form style='margin:0;'>
			 <div class="modal hide" id="joinPairedEndsModal" tabindex="-1" role="dialog" aria-labelledby="joinPairedEndsModalLabel" aria-hidden="true">
			   <button style="display: none;" onclick="join_paired_ends();" data-dismiss="modal" aria-hidden="true">Hidden join paired-ends button for enter key submission</button>
			   <div class="modal-header">
			     <button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>
			     <h3 id="joinPairedEndsModalLabel">join fastq-formatted paired-ends</h3>
		           </div>
			   <div class="modal-body">
			     <p>Select file 1 of your paired-ends:</p>
			     <div id="paired_end_one" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
			     <p>Select file 2 of your paired-ends:</p>
			     <div id="paired_end_two" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
			     <p>Select the index (aka barcode) file of your paired-ends (optional):</p>
			     <div id="paired_end_index" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
			     <p>Select if you would like to remove or retain non-overlapping paired-ends:</p>
			     <div id="paired_end_select" style='margin: 10px 20px 0px 20px;'>
                               <table style='margin: 0px;'><tr><td nowrap="nowrap"><input type="radio" name="paired_end_option" value="remove" checked><b> Remove</b>&nbsp;</td><td style='padding:4px 0px 0px 0px;'> - this is the default, non-overlapping paired-ends will not appear in your output file.</td></tr></table>
                               <table style='margin: 0px;'><tr><td nowrap="nowrap"><input type="radio" name="paired_end_option" value="retain"><b> Retain</b>&nbsp;</td><td style='padding:4px 0px 0px 0px;'> - non-overlapping paired-ends will be retained in your output file as individual (non-joined) sequences.</td></tr></table><br>
                             </div>
			     <p>Enter the desired name of your join paired-ends output file:</p>
			     <div id="join_paired_ends_input" style='margin-top: 10px;'><input type="text" id="join_output_filename" /></div>
		           </div>
			   <div class="modal-footer">
			     <button class="btn" data-dismiss="modal" aria-hidden="true">Cancel</button>
			     <button class="btn btn-primary" style="background-color:#3A87AD;background-image:-moz-linear-gradient(center top , #3A87AD, #3A87AD);" onclick="join_paired_ends();" data-dismiss="modal" aria-hidden="true">Join FASTQ-formatted Paired-End Reads</button>
		           </div>
			 </div>
		       </form>
                       <input type="button" class="btn" style='width:130px;' value="join paired-ends" data-toggle="modal" href="#joinPairedEndsModal"">
                     </td>
                     <td width=250 style='vertical-align:middle;'>Joins FASTQ-formatted overlapping paired-end reads.</td>
                   </tr>
                 </table>
                 <br>
                 <table>
                   <tr>
                     <td rowspan=2 style="padding-right: 20px;">
                       <form class="form-horizontal">
                         <div id="inbox" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
                       </form>
		       <table border=0 cellpadding=4>
			 <tr>
			   <td colspan=2 style='font-size:14px;'><B>Directory Management Operations</B></td>
			 <tr>
			   <td><input type="button" class="btn" style='width:130px;' value="update inbox" onclick="update_inbox();"></td>
			   <td style='vertical-align:middle;'>Refreshes the contents of your inbox.</td>
			 </tr>
			 <tr>
			   <td>
			     <div class="modal hide" id="moveModal" tabindex="-1" role="dialog" aria-labelledby="moveModalLabel" aria-hidden="true">
			       <div class="modal-header">
				 <button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>
				 <h3 id="moveModalLabel">move selected files</h3>
			       </div>
			       <div class="modal-body">
				 <p>Please select the directory where you would like to move your selected files:</p>
				 <div id="dir_list" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
			       </div>
			       <div class="modal-footer">
				 <button class="btn" data-dismiss="modal" aria-hidden="true">Cancel</button>
				 <button class="btn btn-primary" style="background-color:#3A87AD;background-image:-moz-linear-gradient(center top , #3A87AD, #3A87AD);" onclick="move_files();" data-dismiss="modal" aria-hidden="true">Move files</button>
			       </div>
			     </div>
			     <input type="button" class="btn" style='width:130px;' value="move selected" data-toggle="modal" href="#moveModal">
			   </td>
			   <td style='vertical-align:middle;'>Moves the selected files into or out of a directory.</td>
			 </tr>
			 <tr>
			   <td><input type="button" class="btn" style='width:130px;' value="delete selected" onclick="check_delete_files();"></td>
			   <td style='vertical-align:middle;'>Deletes the selected files.</td>
			 </tr>
			 <tr>
			   <td>
			     <form style='margin:0;'>
			       <div class="modal hide" id="createDirModal" tabindex="-1" role="dialog" aria-labelledby="createDirModalLabel" aria-hidden="true">
				 <button style="display: none;" onclick="create_dir();" data-dismiss="modal" aria-hidden="true">Hidden Create directory button for enter key submission</button>
				 <div class="modal-header">
				   <button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>
				   <h3 id="createDirModalLabel">create directory</h3>
				 </div>
				 <div class="modal-body">
				   <p>Please enter the name of the directory you would like to create:</p>
				   <div id="create_dir_input" style='margin-top: 10px;'><input type="text" id="create_dir_name" /></div>
				 </div>
				 <div class="modal-footer">
				   <button class="btn" data-dismiss="modal" aria-hidden="true">Cancel</button>
				   <button class="btn btn-primary" style="background-color:#3A87AD;background-image:-moz-linear-gradient(center top , #3A87AD, #3A87AD);" onclick="create_dir();" data-dismiss="modal" aria-hidden="true">Create directory</button>
				 </div>
			       </div>
			     </form>
			     <input type="button" class="btn" style='width:130px;' value="create directory" data-toggle="modal" href="#createDirModal">
			   </td>
			   <td style='vertical-align:middle;'>Creates a new directory in your inbox.</td>
			 </tr>
			 <tr>
			   <td>
			     <div class="modal hide" id="deleteDirModal" tabindex="-1" role="dialog" aria-labelledby="deleteDirModalLabel" aria-hidden="true">
			       <div class="modal-header">
				 <button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>
				 <h3 id="deleteDirModalLabel">delete directory</h3>
			       </div>
			       <div class="modal-body">
				 <p>Please select the directory you would like to delete (only empty directories can be deleted):</p>
				 <div id="delete_dir_list" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
			       </div>
			       <div class="modal-footer">
				 <button class="btn" data-dismiss="modal" aria-hidden="true">Cancel</button>
				 <button class="btn btn-primary" style="background-color:#3A87AD;background-image:-moz-linear-gradient(center top , #3A87AD, #3A87AD);" onclick="delete_dir();" data-dismiss="modal" aria-hidden="true">Delete directory</button>
			       </div>
			     </div>
			     <input type="button" class="btn" style='width:130px;' value="delete directory" data-toggle="modal" href="#deleteDirModal">
			   </td>
			   <td style='vertical-align:middle;'>Allows you to select and delete an empty directory.</td>
			 </tr>
		       </table> 
                     </td>
                   </tr>
                   <tr>
                     <td><div id="inbox_feedback"></div><div id="inbox_file_info"></div></td>
                   </tr>
                 </table>
               </div>
            </ul>
          </div>
        </div>

        <h1>Data Submission</h1>
	
	<div class="row">
	  <div style="width: 960px; margin-left: 30px;">
	    <form class="form-horizontal" name="submission_form" method='post'>
            <input type="hidden" name="page" value="Upload">
            <input type="hidden" name="create_job" value="1">
	    <ul class="nav nav-pills nav-stacked">
	      <li><a onclick="toggle('sel_md_div');" class="pill_incomplete" id="sel_md_pill" style="font-size: 17px; font-weight: bold;">1. select metadata file <i id="icon_step_1" class="icon-ok icon-white" style="display: none;"></i></a></li>
	      <div id="sel_md_div" style="display: none;" class="well">
                 <div id="sel_mdfile_div" style='float:left;'>
                 </div>
                 <div id="sel_mdfile_info_div" style='float:left; margin-top: 25px; width: 350px;'>
                   <p>Select a spreadsheet with metadata for the project you want to submit.</p>
                   <p>In order to map sequence files to metadata libraries, the names of the sequence files must exactly match the library <i>file_name</i> fields or match the library <i>metagenome_name</i> fields minus the file extension.</p>
                   <p><b>Note: While metadata is not required at submission, the priority for processing data without metadata is lower.</b></p>
                 </div><div class='clear'></div>
              </div>
	      <li><a onclick="toggle('sel_project_div');" class="pill_incomplete" id="sel_project_pill" style="font-size: 17px; font-weight: bold;">2. select project <i id="icon_step_2" class="icon-ok icon-white" style="display: none;"></i></a></li>
              <div id="sel_project_div" class="well" style="display: none;"><h3>select a project</h3><p>You have to specify a project to upload a job to MG-RAST. If you have a metadata file, the project must be specified in that file. If you choose to not use a metadata file, you can select a project here. You can either select an existing project or you can choose a new project.</p><select name="project" style="width: 420px; margin-bottom: 20px;" onchange="if(this.selectedIndex>0){document.getElementById('new_project').value='';document.getElementById('new_project').disabled=true;}else{document.getElementById('new_project').disabled=false;}" id='project'><option value=''>- new -</option>~;
  foreach my $project (@$projects) {
    next unless ($project->{name});
    $html .= "<option value='".$project->{id}."'>".encode_entities($project->{name})."</option>";
  }
  $html .= qq~</select> <input type='text' name='new_project' id='new_project' style='margin-bottom: 20px;'><br><input style='margin-bottom: 20px;' type='button' class='btn' value='select' onclick="check_project();">
<p>Note: The projects listed are those that you have write access to. The owners of other projects can provide you with write access if you do not have it.</p>
              </div>
	      <li><a onclick="toggle('sel_seq_div');" class="pill_incomplete" id="sel_seq_pill" style="font-size: 17px; font-weight: bold;">3. select sequence file(s) <i id="icon_step_3" class="icon-ok icon-white" style="display: none;"></i></a></li>
	      <div id="sel_seq_div" style="display: none;"><div class='well'><div id='available_sequences'>
              <h3>available sequence files</h3><p>Sequence files from your inbox will appear here. Please note, there is a delay between upload completion and appearing in this table due to sequence statistics calculations. This may be on the order of seconds to hours depending on file size.</p>~;
  my $seqtable = $self->application->component('sequence_table');
  $seqtable->columns([ { name => "select<br><input type=\"checkbox\" onclick=\"table_select_all_checkboxes(0,0,this.checked,1);\"> all ", input_type => 'checkbox' },
		       { name => 'directory', sortable => 1, filter => 1 },
		       { name => 'filename', sortable => 1, filter => 1 },
		       { name => 'format', sortable => 1, filter => 1 },
		       { name => 'size', sortable => 1, filter => 1 },
		       { name => 'upload date', sortable => 1, filter => 1 },
		       { name => 'bp count', sortable => 1, filter => 1 },
		       { name => 'sequencing method', sortable => 1, filter => 1, visible => 0 },
		       { name => 'sequence type', sortable => 1, filter => 1, visible => 0 },
		       { name => 'md5', sortable => 1, filter => 1, visible => 0 }]);
  $seqtable->data([[0,"-","-","-","-","-","-","-","-","-"]]);
  $seqtable->show_select_items_per_page(1);
  $seqtable->show_top_browse(1);
  $seqtable->show_bottom_browse(1);
  $seqtable->items_per_page(10);
  $seqtable->show_column_select(1);
  $html .= $seqtable->output();

  $html .= qq~<br><br><input type='button' class='btn' value='select' onclick='select_sequence_file();'></div><div id='selected_sequences'></div></div></div>
              <li><a onclick="toggle('sel_pip_div');" class="pill_incomplete" id="sel_pip_pill" style="font-size: 17px; font-weight: bold;">4. choose pipeline options <i id="icon_step_4" class="icon-ok icon-white" style="display: none;"></i></a></li>
	      <div id="sel_pip_div" style="display: none;" class="well">
		  <h3>selected pipeline options</h3>
		  <div class="control-group">
		    <label class="control-label" for="assembled"><b>assembled</b></label>
		    <div class="controls">
		      <label class="checkbox">
			<input id="assembled" type="checkbox" value="assembled" name="assembled">
			Select this option if your input sequence file(s) contain assembled data and include the coverage information within each sequence header as described <a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#assembled_pipeline' target='blank'>here</a>.
		      </label>
		    </div>

		    <label class="control-label" for="dereplication"><b>dereplication</b></label>
		    <div class="controls">
		      <label class="checkbox">
			<input id="dereplication" type="checkbox" value="dereplication" name="dereplication" checked>
			Remove artificial replicate sequences produced by sequencing artifacts <a href='http://www.nature.com/ismej/journal/v3/n11/full/ismej200972a.html' target='blank'>Gomez-Alvarez, et al, The ISME Journal (2009)</a>.
		      </label>
		    </div>

                    <label class="control-label" for="screening"><b>screening</b></label>
		    <div class="controls">
		      <label class="select">
			<select id="screening" name="screening">
                           <option value="h_sapiens">H. sapiens, NCBI v36</option>
                           <option value="m_musculus">M. musculus, NCBI v37</option>
                           <option value="r_norvegicus">R. norvegicus, UCSC rn4</option>
                           <option value="b_taurus">B. taurus, UMD v3.0</option>
                           <option value="d_melanogaster">D. melanogaster, Flybase, r5.22</option>
                           <option value="a_thaliana">A. thaliana, TAIR, TAIR9</option>
                           <option value="e_coli">E. coli, NCBI, st. 536</option>
                           <option value="s_scrofa">Sus scrofa, NCBI v10.2</option>
			   <option value="none">none</option>
                        </select>
			<br>Remove any host specific species sequences (e.g. plant, human or mouse) using DNA level matching with bowtie <a href='http://genomebiology.com/2009/10/3/R25' target='blank'>Langmead et al., Genome Biol. 2009, Vol 10, issue 3</a>
		      </label>
		    </div>

		    <label class="control-label" for="dynamic_trim"><b>dynamic trimming</b><br>(fastq only)</label>
		    <div class="controls">
		      <label class="checkbox">
			<input id="dynamic_trim" type="checkbox" value="dynamic_trim" name="dynamic_trim" checked>
			Remove low quality sequences using a modified DynamicTrim <a href='http://www.biomedcentral.com/1471-2105/11/485' target='blank'>Cox et al., (BMC Bioinformatics, 2011, Vol. 11, 485)</a>.
		      </label>
		      <label class="text">
			<input id="min_qual" type="text" value="15" name="min_qual">
			Specify the lowest phred score that will be counted as a high-quality base.
		      </label>
		      <label class="text">
			<input id="max_lqb" type="text" value="5" name="max_lqb">
			Sequences will be trimmed to contain at most this many bases below the above-specified quality.
		      </label>
		    </div>

		    <label class="control-label" for="filter_ln"><b>length filtering</b><br>(fasta only)</label>
		    <div class="controls">
		      <label class="checkbox">
			<input id="filter_ln" type="checkbox" value="filter_ln" name="filter_ln" checked>
			Filter based on sequence length when no quality score information is available.
		      </label>
		      <label class="text">
			<input id="deviation" type="text" value="2.0" name="deviation">
			Specify the multiplier of standard deviation for length cutoff (must be 1.0 or greater).
		      </label>
		    </div>

		    <label class="control-label" for="filter_ambig"><b>ambiguous base filtering</b><br>(fasta only)</label>
		    <div class="controls">
		      <label class="checkbox">
			<input id="filter_ambig" type="checkbox" value="filter_amibg" name="filter_ambig" checked>
			Filter based on sequence ambiguity base (non-ACGT) count when no quality score information is available.
		      </label>
		      <label class="text">
			<input id="max_ambig" type="text" value="5" name="max_ambig">
			Specify the maximum allowed number of ambiguous basepairs.
		      </label>
		    </div>
		  </div>

		  <input type="button" class="btn" value="select" onclick="accept_pipeline_options();" id="accept_pipeline_options_button"><span style='margin-left: 20px;'><b>Warning: Comparison of datasets processed with different pipeline options may not be valid.</b></span>
	      </div>

	      <li><a onclick="toggle('sub_job_div');" class="pill_incomplete" id="sub_job_pill" style="font-size: 17px; font-weight: bold;">5. submit <i id="icon_step_4" class="icon-ok icon-white" style="display: none;"></i></a></li>
	      <div id="sub_job_div" style="display: none;" class="well">
<h3>Submit data to the MG-RAST pipeline.</h3>

<p>Data will be private (only visible to the submitter) unless you choose to share it with other users or make it public. If you decide to make data public your data will be given priority for the computational queue.</p>

<div class="control-group">
<div class="controls">
<label class="radio"><input id="priorityOption1" type="radio" value="immediately" name="priorityOption">Data will be publicly accessible <b> immediately </b> after processing completion - Highest Priority</label>
<label class="radio"><input id="priorityOption2" type="radio" value="3months" name="priorityOption">Data will be publicly accessible <b>after 3 months</b> - High Priority</label>
<label class="radio"><input id="priorityOption2" type="radio" value="6months" name="priorityOption">Data will be publicly accessible <b>after 6 months</b> - Medium Priority</label>
<label class="radio"><input id="priorityOption2" type="radio" value="date" name="priorityOption">Data will be publicly accessible <b>eventually</b> - Lower Priority</label>
<label class="radio"><input id="priorityOption2" type="radio" checked="" value="never" name="priorityOption"><b>Data will stay private </b> (DEFAULT) - Lowest Priority</label>
</div>
</div>
<p>Please note that only private data can be deleted.</p>
<div class='clear' style='height:10px;'></div>
<div style='margin-bottom: 20px;'><input type="button" class="btn" value="submit job" onclick="submit_job();" disabled id="submit_job_button"><span style='margin-left: 20px;'><b>Note: You must complete all previous steps to enable submission.</b></span></div>
<p>Upon successful submission, MG-RAST ID's ("Accession numbers") will be automatically assigned to your datasets and data files will be removed from your inbox. Progress through the system can be viewed via the <a href="metagenomics.cgi?page=MetagenomeSelect" target='blank'>Browse page <img title="Browse" style="width: 20px; height: 20px;" src="./Html/mgrast_globe.png"></a>.</p>
</div>
	    </ul>
	  </div>
	  </form>
	</div>
      </div>       
    </div>
 </div>
 <img src='./Html/clear.gif' onload='init_all();'>~;
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/jquery.js",
	   "$Conf::cgi_url/Html/FileUploader.js",
	   "$Conf::cgi_url/Html/bootstrap.js",
	   "$Conf::cgi_url/Html/Upload.js",
	   "$Conf::cgi_url/Html/DataHandler.js" ];
}

sub require_css {
  return [ "$Conf::cgi_url/Html/bootstrap-responsive.min.css",
	   "$Conf::cgi_url/Html/bootstrap.min.css",
	   "$Conf::cgi_url/Html/Upload.css" ];
}

sub submit_to_mgrast {
  my ($self) = @_;

  my $application = $self->application;
  my $user   = $self->application->session->user;
  my $cgi    = $self->application->cgi;
  my $jobdbm = $self->application->data_handle('MGRAST');
  my $mdata  = $cgi->param('mdfile') || '';
  my $project_name = $cgi->param('new_project') || '';
  my $project_id   = $cgi->param('project') || '';
  
  my $base_dir = "$Conf::incoming";
  my $udir = $base_dir."/".md5_hex($user->login);

  my $lib_file_mgname = {};
  my $project_obj = undef;
  my $mddb = MGRAST::Metadata->new();
  my ($is_valid, $data, $log);
  
  # test if Shock-AWE are running
  my $info  = undef;
  my $agent = LWP::UserAgent->new;
  my $json  = JSON->new;
  $json = $json->utf8();
  $json->max_size(0);
  $json->allow_nonref;
  $agent->timeout(10);
  eval {
    my $get = $agent->get($Conf::shock_url);
    $info = $json->decode($get->content);
  };
  if ($@ || ($info->{id} ne 'Shock')) {
    $self->application->add_message('warning', "Unable to access MG-RAST data store. Please try again later.");
    return undef;
  }
  eval {
    my $get = $agent->get($Conf::awe_url);
    $info = $json->decode($get->content);
  };
  if ($@ || ($info->{id} ne 'AWE')) {
    $self->application->add_message('warning', "Unable to access MG-RAST pipeline. Please try again later.");
    return undef;
  }

  # get project name from metadata
  if ($mdata) {
    ($is_valid, $data, $log) = $mddb->validate_metadata($udir."/".$mdata);
    if ($is_valid) {
      $project_name = $data->{data}{project_name}{value};
      foreach my $sample ( @{$data->{samples}} ) {
	if ($sample->{libraries} && scalar(@{$sample->{libraries}})) {
	  foreach my $library (@{$sample->{libraries}}) {
	    next unless (exists($library->{data}) && exists($library->{data}{metagenome_name}));
	    if (exists $library->{data}{file_name}) {
	      my ($basename) = $library->{data}{file_name}{value} =~ /^(.*)\.(fasta|fa|ffn|frn|fna|fastq|fq)$/;
	      $lib_file_mgname->{$basename} = $library->{data}{metagenome_name}{value};
	    } else {
	      $lib_file_mgname->{$library->{data}{metagenome_name}{value}} = $library->{data}{metagenome_name}{value};
	    }
	  }
	}
      }
    } else {
      $self->application->add_message('warning', "Metadata file $mdata is invalid, aborting submission. Please re-run validation in Step 1.");
      return undef;
    }
  }
  # get project if exists from name or id
  if ($project_name) {
    my $projects = $jobdbm->Project->get_objects( { name => $project_name } );
    if (scalar(@$projects) && $user->has_right(undef, 'edit', 'project', $projects->[0]->id)) {
      $project_obj = $projects->[0];
    }
  }
  elsif ($project_id) {
    my $projects = $jobdbm->Project->get_objects( { id => $project_id } );
    if (scalar(@$projects) && $user->has_right(undef, 'edit', 'project', $projects->[0]->id)) {
      $project_obj = $projects->[0];
    }
  }
  else {
    $self->application->add_message('warning', "Unable to find project information, aborting submission. Please re-do Step 1 or 2.");
    return undef;
  }
  # make project if no metadata
  if ((! $mdata) && (! $project_obj) && $project_name) {
    $project_obj = $jobdbm->Project->create_project($user, $project_name);
  }

  my $dereplicate = $cgi->param('dereplication');
  my $bowtie = $cgi->param('screening') eq 'none' ? 0 : 1;
  my $screen_indexes = $cgi->param('screening');
  my $dynamic_trim = $cgi->param('dynamic_trim');
  my $min_qual = $cgi->param('min_qual');
  my $max_lqb = $cgi->param('max_lqb');
  my $filter_ln = $cgi->param('filter_ln');
  my $filter_ln_mult = $cgi->param('deviation');
  my $filter_ambig = $cgi->param('filter_ambig');
  my $max_ambig = $cgi->param('max_ambig');
  my $priority = $cgi->param('priorityOption');
  my $assembled = $cgi->param('assembled');

  my $seqfiles = [];
  @$seqfiles = split /\|/, $cgi->param('seqfiles');
  my $infos = {};
  foreach my $seqfile (@$seqfiles) {
    if (open(FH, "<$udir/$seqfile.stats_info")) {
      my ($filename_base, $filename_ending) = $seqfile =~ /^(.*)\.(fasta|fa|ffn|frn|fna|fastq|fq)$/;
      my $subdir = "";
      if ($filename_base =~ /\//) {
	      ($subdir, $filename_base) = $filename_base =~ /^(.*\/)(.*)/;
      }
      if (($filename_ending ne 'fastq') || ($filename_ending ne 'fna')) {
	      if ($filename_ending eq 'fq') {
	          $filename_ending = 'fastq';	  
	      } else {
	          $filename_ending = 'fna';
	      }
	      `mv '$udir/$seqfile' '$udir/$subdir$filename_base.$filename_ending'`;
	      `mv '$udir/$seqfile.error_log' '$udir/$subdir$filename_base.$filename_ending.error_log'`;
	      `mv '$udir/$seqfile.stats_info' '$udir/$subdir$filename_base.$filename_ending.stats_info'`;
          $seqfile = "$subdir$filename_base.$filename_ending";
      }
      my $name = $filename_base;
      # die if using metadata and no filename-library match
      if ($mdata) {
	if (exists $lib_file_mgname->{$filename_base}) {
	  $name = $lib_file_mgname->{$filename_base};
	}
	else {
	  close FH;
	  $self->application->add_message('warning', "$seqfile has no matching library metagenome_name or file_name in metadata $mdata, aborting submission.");
	  return undef;
	}
      }
      my $info = { 'dereplicate' => $dereplicate ? 1 : 0,
		   'bowtie' => $bowtie,
		   'screen_indexes' => $screen_indexes,
		   'dynamic_trim' => $dynamic_trim ? 1 : 0,
		   'min_qual' => $min_qual,
		   'max_lqb' => $max_lqb,
		   'filter_ln' => $filter_ln ? 1 : 0,
		   'filter_ambig' => $filter_ambig ? 1 : 0,
		   'max_ambig' => $max_ambig,
		   'file' => $seqfile,
		   'name' => $name,
		   'priority' => $priority,
		   'assembled' => $assembled ? 1 : 0
		 };
      while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	$info->{$key} = $val;
      }
      if ($filter_ln_mult) {
        if (int($filter_ln_mult) < 1) {
          $self->application->add_message('warning', "Filter length multiplier must be 1.0 or greater, aborting submission.");
          return undef;
        }
	$info->{min_ln} = int($info->{average_length} - ($filter_ln_mult * $info->{standard_deviation_length}));
	$info->{max_ln} = int($info->{average_length} + ($filter_ln_mult * $info->{standard_deviation_length}));
	if ($info->{min_ln} < 1) { $info->{min_ln} = 1; }
      }
      if ($info->{file_type} eq 'fasta') { $info->{file_type} = 'fna'; }
      $infos->{$seqfile} = $info;
      close FH;
    } else {
      $self->application->add_message('warning', "Could not open information file for $seqfile, aborting submission.");
      return undef;
    }
  }
  
  my $jobs = [];
  my $job2seq = {};
  my $job2type = {};

  # create jobs with providence data
  foreach my $seqfile (@$seqfiles) {
    my $job = $jobdbm->Job->initialize($user, $infos->{$seqfile});
    $job2seq->{$job->{job_id}} = $seqfile;
    $job2type->{$job->{job_id}} = $infos->{$seqfile}{file_type};
    if (ref($job)) {
      push(@$jobs, $job);
    }
  }

  my $successfully_created_jobs = [];
  my $err_msgs = [];
  # create metadata collections
  if ($mdata) {
    (undef, $successfully_created_jobs, $err_msgs) = $mddb->add_valid_metadata($user, $data, $jobs, $project_obj);
    # only print err_msgs and return if not all jobs were successfully submitted
    if(@$err_msgs != 0 && @{$successfully_created_jobs} != @{$jobs}) {
      my $msg = "WARNING: The user \"".$user->login."\" submitted jobs that failed. The following errors were generated:\n";      
      foreach my $err (@$err_msgs) {
        $msg .= $err."\n";
      }
      $msg .= "\nThe following jobs were partially created before this submission failed:\n";
      foreach my $job (@$jobs) {
        $msg .= $job->{job_id}."\n";
      }

      my $mailer = Mail::Mailer->new();
      $mailer->open({ From    => "mg-rast\@mcs.anl.gov",
                      To      => "mg-rast\@mcs.anl.gov",
                      Subject => "Failed Job Creation Submitted By ".$user->login
                    })
        or die "Can't open Mail::Mailer: $!\n";
      print $mailer $msg;
      $mailer->close();

      $self->application->add_message('warning', "Unable to successfully create your jobs!  Please contact MG-RAST at mg-rast\@mcs.anl.gov for more information.");
      return undef;
    }
  }
  # else just add to project
  elsif ($project_obj) {
    foreach my $job (@$jobs) {
      my $msg = $project_obj->add_job($job);
      if ($msg =~ /error/i) {
	print STDERR $msg;
      } else {
	push @$successfully_created_jobs, $job;
      }
    }
  }
  else {
    $self->application->add_message('warning', "Unable to find / create vaild project, aborting submission.");
    return undef;
  }
  # reset job options to include project and other metadata if need
  foreach my $job (@$jobs) {
    $job->set_job_options();
  }

  my $pid = fork();
  # child
  if ($pid == 0) {
    close STDERR;
    close STDOUT;
    foreach my $job (@$successfully_created_jobs) {
        # new submission script, delete from inbox if successful
        my $seqfile = $udir."/".$job2seq->{$job->{job_id}};
        my $status  = system($Conf::submit_to_awe." --job_id ".$job->{job_id}." --input_file ".$seqfile." > $seqfile.submit_log 2> $seqfile.error_log");
        if ($status == 0) {
            system("rm $seqfile $seqfile.stats_info $seqfile.submit_log $seqfile.error_log");
        }
    }
    exit;
  }
  # parent
  else {
    my $mgids = [];
    @$mgids = map { $_->{metagenome_id} } @$successfully_created_jobs;
    return $mgids;
  }
}

sub check_for_duplicates {
  my ($self) = @_;

  my $application = $self->application;
  my $user     = $self->application->session->user;
  my $cgi      = $self->application->cgi;
  my $jobdbm   = $self->application->data_handle('MGRAST');
  my $seqfiles = [];
  my $base_dir = "$Conf::incoming";
  my $udir     = $base_dir."/".md5_hex($user->login);
  my $output   = '';

  @$seqfiles = split(/\|/, $cgi->param('seqfiles'));

  my $dupes = [];
  my $missing_files = [];
  foreach my $seqfile (@$seqfiles) {
    unless (-e "$udir/$seqfile") {
      push @$missing_files, $seqfile;
    }
    if (open(FH, "<$udir/$seqfile.stats_info")) {
      my $info = {};
      while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	$info->{$key} = $val;
      }
      next unless (exists $info->{file_checksum});
      my $dupe = $jobdbm->Job->has_checksum($info->{file_checksum}, $user);
      my $file_size = "N/A";
      if(exists $info->{file_size}) {
        $file_size = format_bytes($info->{file_size});
      }
      $file_size .= "\t";
      if ($dupe) {
	      push @$dupes, [$dupe, $file_size, $seqfile, $info->{file_checksum}];
      }
    }
  }
  if (@$missing_files > 0) {
    $output = "ERROR: The following files are missing from your inbox, perhaps you alread submitted them?\n\n";
    foreach my $file (@$missing_files) {
      $output .= "$file\n";
    }
    print $cgi->header(-charset => 'UTF-8');
    print $output;
  } elsif (@$dupes > 0) {
    $output = "WARNING: The following selected files already exist in MG-RAST:\n\nExisting ID\tFile Size\t\tYour File\tMD5 checksum\n---------------\t---------------\t---------------\t---------------\n";
    map { $output .= join("\t", @$_)."\n" } @$dupes;
    $output .= "\nResubmitting jobs that already exist in MG-RAST reduces our resources and can delay the processing of jobs for all MG-RAST users.  Do you really wish to continue with this submission and create ".scalar(@$dupes)." duplicate metagenomes?";
    print $cgi->header(-charset => 'UTF-8');
    print $output;
  } else {
    print $cgi->header(-charset => 'UTF-8');
    print "unique";
  }
  exit 0;
}

sub send_email_for_duplicate_submission {
  my ($self) = @_;

  my $application = $self->application;
  my $user     = $self->application->session->user;
  my $cgi      = $self->application->cgi;
  my $jobdbm   = $self->application->data_handle('MGRAST');
  my $seqfiles = [];
  my $base_dir = "$Conf::incoming";
  my $udir     = $base_dir."/".md5_hex($user->login);
  my $msg      = '';

  @$seqfiles = split(/\|/, $cgi->param('seqfiles'));

  my $max_byte_size = 0;
  my $dupes = [];
  foreach my $seqfile (@$seqfiles) {
    if (open(FH, "<$udir/$seqfile.stats_info")) {
      my $info = {};
      while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	$info->{$key} = $val;
      }
      next unless (exists $info->{file_checksum});
      my $dupe = $jobdbm->Job->has_checksum($info->{file_checksum}, $user);
      my $file_size = "N/A";
      if(exists $info->{file_size}) {
        if($info->{file_size} > $max_byte_size) {
          $max_byte_size = $info->{file_size};
        }
        $file_size = format_bytes($info->{file_size});
      }
      if ($dupe) {
	push @$dupes, [$dupe, $file_size, $seqfile, $info->{file_checksum}];
      }
    }
  }
  if (@$dupes > 0 && $max_byte_size > $Conf::dup_job_notification_size_limit) {
    $msg = "WARNING: The user \"".$user->login."\" submitted files that already exist in MG-RAST:\n\nExisting ID, File Size, Their File, MD5 checksum\n-----------------------------------------------------------------------------------------------\n";
    map { $msg .= join(", ", @$_)."\n" } @$dupes;
    my $mailer = Mail::Mailer->new();
    $mailer->open({ From    => "mg-rast\@mcs.anl.gov",
                    To      => "mg-rast\@mcs.anl.gov",
                    Subject => "Duplicate Metagenome Submission From ".$user->login
                  })
      or die "Can't open Mail::Mailer: $!\n";
    print $mailer $msg;
    $mailer->close();
    print $cgi->header(-charset => 'UTF-8');
    print 1;
  } else {
    print $cgi->header(-charset => 'UTF-8');
    print 0;
  }

  exit 0;
}

sub check_project_name {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my $user = $self->application->session->user;
  
  my $project_name = $cgi->param('new_project');
  my $project_id = $cgi->param('project');
  my $jobdb = $self->application->data_handle('MGRAST');
  
  my $projects;
  if ($project_name) {
    $projects = $jobdb->Project->get_objects({ name => $project_name });
  } else {
    $projects = $jobdb->Project->get_objects({ id => $project_id });
  }
  if (scalar(@$projects) && ! $user->has_right(undef, 'edit', 'project', $projects->[0]->{id})) {
    print $cgi->header(-charset => 'UTF-8');
    print 0;
  } else {
    print $cgi->header(-charset => 'UTF-8');
    print 1;
  }
  exit 0;
}

sub read_status_file {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $self->application->session->user;
  my $cgi = $self->application->cgi;
  my $type = $cgi->param('type');
  my $filename = $cgi->param('filename');
  
  my $base_dir = "$Conf::incoming";
  my $udir = $base_dir."/".md5_hex($user->login);
  my $status_file = "$udir/$filename.$type";

  my $msg = "";
  if (-f $status_file) {
    $msg = `cat $status_file`;
    chomp $msg;
  }

  print $cgi->header(-charset => 'UTF-8');
  print $msg;
  exit 0;
}

sub validate_metadata {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $self->application->session->user;
  my $cgi = $self->application->cgi;
  my $fn = $cgi->param('mdfn');
  
  my $base_dir = "$Conf::incoming";
  my $udir = $base_dir."/".md5_hex($user->login);
  my $md_file = $udir."/".$fn;
  my $project_name = 'none';

  my ($is_valid, $data, $log) = MGRAST::Metadata->validate_metadata($md_file);

  my $formatted_data = "<p>Your uploaded metadata did not pass validation. Please correct the file and upload again.  If you are having trouble creating a valid metadata spreadsheet, try out <a href='http://metagenomics.anl.gov/metazen.cgi' target=_blank>MetaZen</a>.  The following errors were detected:</p>";
  if ($is_valid) {
    $formatted_data = "<p>Your metadata file successfully passed validation.</p>";
    $project_name = $data->{data}->{project_name}->{value};
    if ($project_name) {
      my $jobdbm  = $application->data_handle('MGRAST');
      my $projects = $jobdbm->Project->get_objects( { name => $project_name } );
      if (scalar(@$projects) && (! $user->has_right(undef, 'edit', 'project', $projects->[0]->id))) {
	print $cgi->header(-charset => 'UTF-8');
	print "0||taken||The project name you have chosen is already taken and you do not have edit rights to this project.\nPlease choose a different project name or ask the owner of the project for edit rights.";
	exit 0;
      } else {
	$formatted_data .= "<img src='./Html/clear.gif' onload='selected_project=".$project_name."'>";
      }
    }
    my $barcodes = {};
    my $lib_name_file = {};
    foreach my $sample ( @{$data->{samples}} ) {
      if ($sample->{libraries} && scalar(@{$sample->{libraries}})) {
	foreach my $library (@{$sample->{libraries}}) {
	  next unless (exists($library->{data}) && exists($library->{data}{metagenome_name}));
	  if (exists $library->{data}{file_name}) {
	    my ($basename) = $library->{data}{file_name}{value} =~ /^(.*)\.(fasta|fa|ffn|frn|fna|fastq|fq)$/;
	    $lib_name_file->{$library->{data}{metagenome_name}{value}} = $basename;
	  } else {
	    $lib_name_file->{$library->{data}{metagenome_name}{value}} = $library->{data}{metagenome_name}{value};
	  }
	  if (exists $library->{data}{forward_barcodes}) {
	    $barcodes->{ $lib_name_file->{$library->{data}{metagenome_name}{value}} } = $library->{data}{forward_barcodes}{value};
	  }
	}
      }
    }
    if (scalar(keys(%$barcodes))) {
      $fn =~ s/^(.*)\.xls(x)?$/$1/;
      my $barname = $fn.".barcodes";
      if (! -f $udir."/".$barname) {	  
	open(FH, ">$udir/$barname") or die "could not open barcode file for writing ($udir/$barname): ".$!."\n";
	foreach my $key (keys(%$barcodes)) {
	  print FH $barcodes->{$key}."\t".$key."\n";
	}
	close FH;
	$formatted_data .= "<p>Barcodes were detected in your metadata file. A barcode file with the provided codes has been placed in your inbox. You can use this to demultiplex your sequence file below. Select the sequence file and the barcode file ($barname) and click 'demultiplex'.</p>";
      }
    }
    $formatted_data .= "<p>You designated the administrative contact for the project <b>'".$project_name."'</b> to be ".$data->{data}->{PI_firstname}->{value}." ".$data->{data}->{PI_lastname}->{value}." (".$data->{data}->{PI_email}->{value}."). This project contains ".scalar(@{$data->{samples}})." samples with ".scalar(keys %$lib_name_file)." libraries having the following metagenome names:</p><p><table>";
    my $example = '';
    foreach my $name (sort keys %$lib_name_file) {
      $example = $name;
      $formatted_data .= "<tr><td>".$name."</td></tr>";
    }
    $formatted_data .= "</table></p>";
    if (scalar(keys %$lib_name_file) > 1) {
      $formatted_data .= "<p><b>Caution:</b> Since you have more than one library, the names of the sequence files must match the library <i>metagenome_name</i> fields minus extension (i.e. the filename for library metagenome_name $example must be $example.fastq or $example.fna) or exactly match the library <i>file_name</i> fields.<br><i><b>Note:</b> All FASTA files will automatically be renamed .fna</i></p>";
      $formatted_data .= "||".join("@@", values %$lib_name_file);
    }
  } else {
    $data = $data->{data};
    if ($data && (@$data > 0)) {
      $formatted_data .= "<table><tr><th>tab</th><th>column</th><th>row</th><th>value</th><th>error</th></tr>";
      foreach my $row (@$data) {
	$formatted_data .= "<tr><td>".$row->[0]."</td><td>".$row->[1]."</td><td>".$row->[2]."</td><td>".$row->[3]."</td><td>".$row->[4]."</td></tr>";
      }
       $formatted_data .= "</table>";
    } else {
      $formatted_data .= "<p><pre>$log</pre><p>";
    }
    $formatted_data .= "<input type='button' class='btn' value='select new metadata file' onclick='selected_metadata_file=null;update_inbox();document.getElementById(\"sel_mdfile_info_div\").style.display = \"\";'>";
  }
  print $cgi->header(-charset => 'UTF-8');
  print $is_valid."||".$project_name."||".$formatted_data;
  exit 0;
}

sub current_webkey {
  my ($self) = @_;

  my $application = $self->application();
  my $master = $application->dbmaster();
  my $user = $application->session->user();
  
  my $existing_key = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
  my $existing_date = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
  
  my $valid = 0;
  my $key = 0;
  my $date = 0;
  
  if (scalar(@$existing_key)) {
    if ($existing_date->[0]->{value} > time) {
      $valid = 1;
    }
    $key = $existing_key->[0]->{value};
    $date = $existing_date->[0]->{value};
  }

  return { "key" => $key,
	   "date" => $date,
	   "valid" => $valid };
}

sub generate_webkey {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  my $timeout = 60 * 60 * 24 * 7; # one week
  
  my $generated = "";

  my $webkey = { "key" => 0,
		 "date" => 0,
		 "valid" => 0 };

  my $existing_key = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
  my $existing_date = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
  if (scalar(@$existing_key) && ! $cgi->param('generate_new_key')) {
    $webkey->{key} = $existing_key->[0]->{value};
    $webkey->{date} = $existing_date->[0]->{value};
    if ($webkey->{date} > time) {
      $webkey->{valid} = 1;
    }

    if ($cgi->param('reactivate_key')) {
      my $tdate = time + $timeout;
      $existing_date->[0]->value($tdate);
    }
  } else {
    my $possible = 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    while (length($generated) < 25) {
      $generated .= substr($possible, (int(rand(length($possible)))), 1);
    }
    my $preference = $master->Preferences->get_objects( { value => $generated } );
    
    while (scalar(@$preference)) {
      $generated = "";
      while (length($generated) < 25) {
	$generated .= substr($possible, (int(rand(length($possible)))), 1);
      }
      $preference = $master->Preferences->get_objects( { value => $generated } );
    }
    my $tdate = time + $timeout;

    my $pref = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
    if (scalar(@$pref)) {
      $pref = $pref->[0];
    } else {
      $pref = $master->Preferences->create( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
    }
    $pref->value($tdate);
    
    $pref = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
    if (scalar(@$pref)) {
      $pref = $pref->[0];
    } else {
      $pref = $master->Preferences->create( { 'user' => $user, 'name' => 'WebServicesKey' } );
    }
    $pref->value($generated);
    $webkey->{key} = $generated;
    $webkey->{date} = $tdate;
    $webkey->{valid} = 1;
  }
    
  my $content = "";
  
  if ($webkey->{valid}) {

    my ($sec,$min,$hour,$mday,$mon,$year) = localtime($webkey->{date});  
    my $tdate_readable = ($year + 1900)." ".sprintf("%02d", $mon + 1)."-".sprintf("%02d", $mday)." ".sprintf("%02d", $hour).":".sprintf("%02d", $min).".".sprintf("%02d", $sec);

    $content .= "<b>Your current WebKey:</b> <input type='text' readOnly=1 size=25 value='" . $webkey->{key} . "'>";
    $content .= " &nbsp;&nbsp;&nbsp;<b>valid until</b>: <input type='text' readOnly=1 size=20 value='" . $tdate_readable . "'>";
    $content .= "<br><input type='button' class='btn' value='extend key validity date' onclick='generate_webkey(null, 1);' style='margin-top: 5px; margin-left: 130px;'>";

  } else {
    $content .= "<b>Your current WebKey:</b> " . $webkey->{key};
    $content .= "<br><span style='font-weight: bold; color: red; margin-top: 3px;'>your current key has timed out and is no longer valid!</span>";
    $content .= "<br><input type='button' class='btn' value='re-activate key' onclick='generate_webkey(null, 1);'>";
  }

  $content .= " <input type='button' class='btn' value='generate new key' onclick='generate_webkey(1);' style='margin-top: 5px; margin-left: 50px;'>";
#  $content .= "<img src='./Html/clear.gif' onload='document.getElementById(\"ftp_webkey\").innerHTML=\"" . $webkey->{key} . "\";document.getElementById(\"http_webkey\").innerHTML=\"" . $webkey->{key} . "\";'>";

  print $cgi->header(-charset => 'UTF-8');
  print $content;
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }
