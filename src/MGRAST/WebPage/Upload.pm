package MGRAST::WebPage::Upload;

use strict;
use warnings;
no warnings('once');
use Data::Dumper;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use JSON;
use Encode;

use FIG_Config;
use WebConfig;
use MGRAST::MGRAST;
use MGRAST::Metadata;

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

  $self->application->register_action($self, 'download_template', 'download_template');
  $self->application->register_action($self, 'check_project_name', 'check_project_name');
  $self->application->register_action($self, 'validate_metadata', 'validate_metadata');
  $self->application->register_action($self, 'submit_to_mgrast', 'submit_to_mgrast');
  $self->application->register_action($self, 'generate_webkey', 'generate_webkey');

  $self->application->register_component('Table', 'sequence_table');

}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi         = $application->cgi;
  my $user        = $application->session->user;

  my $jobdb = $application->data_handle('MGRAST');
  
  unless ($user) {
    return "<p>You must be logged in to upload metagenome files and create jobs.</p><p>Please use the login box in the top right corner or return to the <a href='?page=Home'>start page</a>.</p>";
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
      $html .= "<div class='well'><h4>Job submission successful</h4><p>Your data has been successfully submitted to the pipeline. You can view the status of your submitted jobs <a href='?page=MetagenomeSelect'>here</a> and click on the number next to 'In Progress'.</p><p>Your MG-RAST IDs: ".join(", ", @$success)."</p></div>";
    }
  }

  my $user_project_ids = $user->has_right_to(undef, "edit", "project");
  my $projects = [];
  foreach my $pid (@$user_project_ids) {
    next if ($pid eq '*');
    my $p = $jobdb->Project->get_objects( { id => $pid } );
    if (scalar($p)) {
      push(@$projects, $p->[0]);
    }
  }

  $html .= qq~
<div class="well" style='width: 630px; float: left;'><h3>using the new mg-rast uploader:</h3>
<p>The new data uploader and submission site provides a more convenient way to upload and process your data! You can upload all of your sequence files and metadata at once and have the files modified and validated before submitting.</p>

<p>In short, use <b>Prepare Data</b> to upload any fasta, fastq or SFF files and GSC MIxS compliant metadata files into your inbox. While metadata is not required at submission, the priority for processing data without metadata is lower. Metadata can be modified on the project page after submission. The inbox is a temporary storage location allowing you to assemble all files required for submission. After manipulate the files in your inbox, use <b>Data Submission</b> to create and add to existing projects. When the submission process has been successfully completed, MG-RAST ID's ("Accession numbers") will be automatically assigned and the data will be removed from your inbox.<p>

<p>You can monitor the progress of your jobs in the My Data Summary, on the Browse Metagenomes page.</p>
<p>Questions? Check out our <a href='http://blog.metagenomics.anl.gov/upload-data-v3-2/' target='blank'>tutorial and instructional videos</a>. Still having trouble? <a href="mailto:mg-rast\@mcs.anl.gov">Email us!</a></p>

<p><b>Note: All numbered sections below expand on click to display additional information and options.</b></p>
</div>
        <div class="well" style='width: 240px; float: right;'>
<h3>mini-faq</h3>
<ul class="unstyled">
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-how-to-videos/#upload_single' target=_blank>Upload a single metagenome (Video)</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-how-to-videos/#upload_multiple' target=_blank>Upload multiple metagenomes (Video)</a></li>
<li><a href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#inbox' target=_blank>Inbox explained</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#command_line_submission' target=_blank>Using cmd-line tools for submission</a></li>
<li><a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#api_submission' target=_blank>Automated submission via our API</a></li>
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
	      <li><a onclick="toggle('sel_mddownload_div');" class="pill_incomplete" id="sel_mddownload_pill" style="font-size: 17px; font-weight: bold;">1. download metadata spreadsheet template</a></li>
	      <div id="sel_mddownload_div" style="display: none;" class="well">
                 <h3>download metadata spreadsheet template</h3>
<p>Metadata (or data about the data) has become a necessity as the community generates large quantities of data sets.</p>
	         <p>Using community generated questionnaires we capture this metadata. MG-RAST has implemented the use of <a href='http://gensc.org/gc_wiki/index.php/MIxS' target=_blank>Minimum Information about any (X) Sequence</a> developed by the <a href='http://gensc.org' target=_blank >Genomic Standards Consortium</a> (GSC).</p>
<p>The best form to capture metadata is via a simple spreadsheet with 12 mandatory terms. You can download the spreadsheet file here, fill in the required data fields later upload it to your inbox.</p>
<p>While the MIxS required data fields capture only the most minimal metadata, many areas of study have chosen to require more elaborate questionnaires ("environmental packages") to help with analysis and comparison. These are marked as optional in the spreadsheet. If the "environmental package" for your area of study has not been created yet, please <a href="mailto:mg-rast\@mcs.anl.gov">contact MG-RAST staff</a> and we will forward your inquiry to the appropriate GSC working group.</p>
<p>Once you have filled out the template, you can upload it below and it will be validated and appear in the metadata selection section.</p>
                 <p><a href="?page=Upload&action=download_template"><img title="download metadata spreadsheet template" style="width: 20px; height: 20px;" src="./Html/mg-download.png"> download metadata spreadsheet template</a></p>
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
                       <td style="padding-left: 240px;">
                          <p>Select one or more files to upload to your private inbox folder.</p>
                          <p>Sequence files must be fasta, fastq, or sff format.
                             Use vaild file extensions for the appropriate format: .fasta, .faa, .fa, .ffn, .frn, .fna, .fastq, .fq, .sff</p>
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
	                </table>
	                <a class="btn btn-danger" href="#" onclick="cancel_upload();" style="position: relative; top: 9px; left: 435px;"><i class="icon-ban-circle"></i> cancel upload</a>
 	             </div>
                  </div>
               
               <p>Alternative upload is available via the command line and ftp. Please refer to our <a href='http://blog.metagenomics.anl.gov/mg-rast-v3-2-faq/#command_line_submission' target=_blank>blog</a> for a detailed description.</p>
               <p>To generate a webkey needed for this procedure, please click the following <b>'generate webkey'</b> button. <div id='generate_key'><input type='button' class='btn' value='generate webkey' onclick='generate_webkey();'></div>

               </div>

               <li><a onclick="toggle('sel_inbox_div');" class="pill_incomplete" id="sel_inbox_pill" style="font-size: 17px; font-weight: bold;">3. manage inbox</a></li>
	       <div id="sel_inbox_div" style="display: none;" class="well">
<p>You can unpack, delete, convert and demultiplex files from your inbox below. Sequence files will automatically appear in the <i>'select sequence file(s)'</i> section below. Metadata files will automatically appear in the <i>'select metadata file'</i> section below.</p>
                  <input type="button" class="btn" value="delete selected" onclick="check_delete_files();">
                  <input type="button" class="btn" value="unpack selected" onclick="unpack_files();">
                  <input type="button" class="btn" value="convert sff to fastq" onclick="convert_files();">
                  <input type="button" class="btn" value="demultiplex" onclick="demultiplex_files();">
                  <input type="button" class="btn" value="update inbox" onclick="update_inbox();">
                  <input type="button" class="btn" value="change file directory" onclick="change_file_dir();">
                  <div id="inbox" style='margin-top: 10px;'><br><br><img src="./Html/ajax-loader.gif"> loading...</div>
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
                 <div id="sel_mdfile_div" style='float:left;'></div><div style='float:left; margin-top: 25px; width: 350px;'><p>Select a spreadsheet with metadata for the project you want to submit. Uploaded spreedsheets will appear here after successful validation.</p><p><b>Note: While metadata is not required at submission, the priority for processing data without metadata is lower.</b></p></div><div class='clear'></div>
              </div>
	      <li><a onclick="toggle('sel_project_div');" class="pill_incomplete" id="sel_project_pill" style="font-size: 17px; font-weight: bold;">2. select project <i id="icon_step_2" class="icon-ok icon-white" style="display: none;"></i></a></li>
              <div id="sel_project_div" class="well" style="display: none;"><h3>select a project</h3><p>You have to specify a project to upload a job to MG-RAST. If you have a metadata file, the project must be specified in that file. If you choose to not use a metadata file, you can select a project here. You can either select an existing project or you can choose a new project.</p><select name="project" style="width: 420px; margin-bottom: 20px;" onchange="if(this.selectedIndex>0){document.getElementById('new_project').value='';document.getElementById('new_project').disabled=true;}else{document.getElementById('new_project').disabled=false;}" id='project'><option value=''>- new -</option>~;
  foreach my $project (@$projects) {
    next unless ($project->{name});
    $html .= "<option value='".$project->{id}."'>".$project->{name}."</option>";
  }
  $html .= qq~</select> <input type='text' name='new_project' id='new_project' style='margin-bottom: 20px;'> <input style='margin-bottom: 20px;' type='button' class='btn' value='select' onclick="check_project();">
<p>The projects shown in the list above are the ones you have write access to. Note that the owners of the projects can provide you with write access</p>
              </div>
	      <li><a onclick="toggle('sel_seq_div');" class="pill_incomplete" id="sel_seq_pill" style="font-size: 17px; font-weight: bold;">3. select sequence file(s) <i id="icon_step_3" class="icon-ok icon-white" style="display: none;"></i></a></li>
	      <div id="sel_seq_div" style="display: none;"><div class='well'><div id='available_sequences'><h3>available sequence files</h3>~;
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
                           <option value="h_sapiens_asm">H. sapiens, NCBI v36</option>
                           <option value="m_musculus_ncbi37">M. musculus, NCBI v37</option>
                           <option value="b_taurus">B. taurus, UMD v3.0</option>
                           <option value="d_melanogaster_fb5_22">D. melanogaster, Flybase, r5.22</option>
                           <option value="a_thaliana">A. thaliana, TAIR, TAIR9</option>
                           <option value="e_coli">E. coli, NCBI, st. 536</option>
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
			Specify the multiplicator of standard deviation for length cutoff.
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

		  <input type="button" class="btn" value="accept" onclick="accept_pipeline_options();" id="accept_pipeline_options_button"><span style='margin-left: 20px;'><b>Warning: Comparison of datasets processed with different pipeline options may not be valid.</b></span>
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
<p>Upon successful submission MG-RAST ID's ("Accession numbers") will be automatically assigned and data files will be removed from your inbox. Progress through the system can be viewed via the <a href="metagenomics.cgi?page=MetagenomeSelect" target='blank'>Browse page <img title="Browse" style="width: 20px; height: 20px;" src="./Html/mgrast_globe.png"></a>.</p>
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
  return [ "$FIG_Config::cgi_url/Html/jquery.js",
	   "$FIG_Config::cgi_url/Html/FileUploader.js",
	   "$FIG_Config::cgi_url/Html/bootstrap.min.js",
	   "$FIG_Config::cgi_url/Html/Upload.js",
	   "$FIG_Config::cgi_url/Html/DataHandler.js" ];
}

sub require_css {
  return [ "$FIG_Config::cgi_url/Html/bootstrap-responsive.min.css",
	   "$FIG_Config::cgi_url/Html/bootstrap.min.css",
	   "$FIG_Config::cgi_url/Html/Upload.css" ];
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
  
  my $base_dir = "$FIG_Config::incoming";
  my $udir = $base_dir."/".md5_hex($user->login);

  my $libraries = {};
  my $project_obj = undef;
  my $mddb = MGRAST::Metadata->new();
  my ($is_valid, $data, $log);

  # get project name from metadata
  if ($mdata) {
    ($is_valid, $data, $log) = $mddb->validate_metadata($udir."/".$mdata);
    $project_name = $data->{data}->{project_name}->{value};
    foreach my $sample ( @{$data->{samples}} ) {
      if ($sample->{libraries} && scalar(@{$sample->{libraries}})) {
	foreach my $library (@{$sample->{libraries}}) {
	  $libraries->{$library->{name}} = 1;
	}
      }
    }
  }
  # get project if exists from name or id
  if ($project_name) {
    my $projects = $jobdbm->Project->get_objects( { name => $project_name } );
    if (scalar(@$projects) && $user->has_right(undef, 'view', 'project', $projects->[0]->id)) {
      $project_obj = $projects->[0];
    }
  }
  elsif ($project_id) {
    my $projects = $jobdbm->Project->get_objects( { id => $project_id } );
    if (scalar(@$projects) && $user->has_right(undef, 'view', 'project', $projects->[0]->id)) {
      $project_obj = $projects->[0];
    }
  }
  else {
    $self->application->add_message('warning', "Unable to find project information, aborting submission.");
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

  my $seqfiles = [];
  @$seqfiles = split /\|/, $cgi->param('seqfiles');
  my $infos = {};
  foreach my $seqfile (@$seqfiles) {
    if (open(FH, "<$udir/$seqfile.stats_info")) {
      my ($filename_base, $filename_ending) = $seqfile =~ /^(.*)\.(fasta|faa|fa|ffn|frn|fna|fastq|fq)$/;
      if ($filename_ending ne 'fastq') {
	$filename_ending = 'fna';
	`mv '$udir/$seqfile' '$udir/$filename_base.$filename_ending'`;
	$seqfile = "$filename_base.$filename_ending";
      }
      my $name = $filename_base;
      # die if using metadata and no filename-library match
      if ($mdata && (! exists($libraries->{$filename_base}))) {
	close FH;
	$self->application->add_message('warning', "Mismatch in library name and sequence filename, aborting submission.");
	return undef;
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
		   'priority' => $priority
		 };
      while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	$info->{$key} = $val;
      }
      if ($filter_ln_mult) {
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
  # check if sequence file already has a job
  foreach my $seqfile (@$seqfiles) {
    if ($jobdbm->Job->has_checksum($infos->{$seqfile}{file_checksum}, $user)) {
      $self->application->add_message('warning', "A job already exists in MG-RAST for file $seqfile, aborting submission.");
      return undef;
    }
  }
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
  # create metadata collections
  if ($mdata) {
    $successfully_created_jobs = $mddb->add_valid_metadata($user, $data, $jobs, $project_obj);
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

  my $mgids = [];
  foreach my $job (@$successfully_created_jobs) {
    my $create_job_script = $FIG_Config::create_job;
    my $seqfile = $job2seq->{$job->{job_id}};
    my $jid = $job->{job_id};
    my $is_fastq = ($job2type->{$job->{job_id}} eq 'fastq') ? " --fastq" : "";
    my $options  = $job->{options} ? ' -o "'.$job->{options}.'"' : "";
    print STDERR qq~create command: $create_job_script -j $jid -f "$udir/$seqfile"$options$is_fastq\n~;
    my $result = `$create_job_script -j $jid -f "$udir/$seqfile"$options$is_fastq`;
    push @$mgids, $job->{metagenome_id};
  }
  
  return $mgids;
}

sub download_template {
  my $fn = $FIG_Config::html_base.'/'.$FIG_Config::mgrast_metadata_template;

  if (open(FH, $fn)) {
    print "Content-Type:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\n";  
    print "Content-Length: " . (stat($fn))[7] . "\n";
    print "Content-Disposition:attachment;filename=".$FIG_Config::mgrast_metadata_template."\n\n";
    while (<FH>) {
      print $_;
    }
    close FH;
  }
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
    print $cgi->header();
    print 0;
  } else {
    print $cgi->header();
    print 1;
  }
  exit 0;
}

sub validate_metadata {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $self->application->session->user;
  my $cgi = $self->application->cgi;
  my $fn = $cgi->param('mdfn');
  
  my $base_dir = "$FIG_Config::incoming";
  my $udir = $base_dir."/".md5_hex($user->login);
  my $md_file = $udir."/".$fn;

  my ($is_valid, $data, $log) = MGRAST::Metadata->validate_metadata($md_file);

  my $formatted_data = "<p>Your uploaded metadata did not pass validation. Please correct the file and upload again. The following errors were detected:</p>";
  if ($is_valid) {
    $formatted_data = "<p>Your metadata file successfully passed validation.</p>";
    my $project_name = $data->{data}->{project_name}->{value};
    if ($project_name) {
      my $jobdbm  = $application->data_handle('MGRAST');
      my $projects = $jobdbm->Project->get_objects( { name => $project_name } );
      if (scalar(@$projects) &&  ! $user->has_right(undef, 'view', 'project', $projects->[0]->id)) {	
	$is_valid = 0;
	$formatted_data = "<p>The project name you have chosen is already taken and you do not have edit rights to this project. Please choose a different project name or ask the owner of the project for edit rights.</p>";
      } else {
	$formatted_data .= "<img src='./Html/clear.gif' onload='selected_project=".$project_name."'>";
      }
    }
    if ($is_valid) {
      my $barcodes = {};
      my $libraries = [];
      foreach my $sample ( @{$data->{samples}} ) {
	if ($sample->{libraries} && scalar(@{$sample->{libraries}})) {
	  foreach my $library (@{$sample->{libraries}}) {
	    push(@$libraries, $library->{name});
	    if ($library->{name} &&$library->{data} && $library->{data}->{forward_barcodes} && $library->{data}->{forward_barcodes}->{value}) {
	      $barcodes->{$library->{name}} = $library->{data}->{forward_barcodes}->{value};
	    }
	  }
	}
      }
      if (scalar(keys(%$barcodes))) {
	$fn =~ s/^(.*)\.xlsx$/$1/;
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
      $formatted_data .= "<p>You designated the administrative contact for the project <b>'".$project_name."'</b> to be ".$data->{data}->{PI_firstname}->{value}." ".$data->{data}->{PI_lastname}->{value}." (".$data->{data}->{PI_email}->{value}."). The project contains ".scalar(@{$data->{samples}})." samples with ".scalar(@$libraries)." libraries:</p><table>";
      foreach my $lib (@$libraries) {
	$formatted_data .= "<tr><td>".$lib."</td></tr>";
      }
      $formatted_data .= "</table>";
      if (scalar(@$libraries) > 1) {
	$formatted_data .= "<p><b>Caution:</b> Since you have more than one library, the names of the sequence files must match the library names, i.e. the filename for your library ".$libraries->[0]." must be ".$libraries->[0].".fastq or ".$libraries->[0].".fna (<i>Note: All FASTA files will automatically be renamed .fna</i>)</p>";
	$formatted_data .= "||".join("@@", @$libraries);
      }
    }
  } else {
    $data = $data->{data};
    $formatted_data .= "<table><tr><th>tab</th><th>column</th><th>row</th><th>value</th><th>error</th></tr>";
    foreach my $row (@$data) {
      $formatted_data .= "<tr><td>".$row->[0]."</td><td>".$row->[1]."</td><td>".$row->[2]."</td><td>".$row->[3]."</td><td>".$row->[4]."</td></tr>";
    }
    $formatted_data .= "</table><input type='button' class='btn' value='select new metadata file' onclick='selected_metadata_file=null;update_inbox();'>";
  }
  print $cgi->header;
  print $is_valid."||".$formatted_data;
  exit 0;
}

sub generate_webkey {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  my $generated = "";

  my $existing_key = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServicesKey' } );
  my $existing_date = $master->Preferences->get_objects( { 'user' => $user, 'name' => 'WebServiceKeyTdate' } );
  if (scalar(@$existing_key) && ! $cgi->param('generate_new_key')) {
    $existing_key = $existing_key->[0]->{value};
    $existing_date = $existing_date->[0]->{value};
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
    my $timeout = 60 * 60 * 24 * 7; # one week
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
    $existing_key = $generated;
    $existing_date = $tdate;

    # create a symlink
    
  }
    
  my $content = "<b>Your current WebKey:</b> <input type='text' readOnly=1 size=25 value='" . $existing_key . "'>";
  
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime($existing_date);  
  my $tdate_readable = ($year + 1900)." ".sprintf("%02d", $mon + 1)."-".sprintf("%02d", $mday)." ".sprintf("%02d", $hour).":".sprintf("%02d", $min).".".sprintf("%02d", $sec);
  $content .= " <b>valid until</b>: <input type='text' readOnly=1 size=20 value='" . $tdate_readable . "'>";
  $content .= "<br><b>Your temporary ftp url is:</b> ftp://ftp.mcs.anl.gov/".$existing_key."<br><br>";
  $content .= " <input type='button' class='btn' value='generate new key' onclick='generate_webkey(1);'>";
  
  print $cgi->header;
  print $content;
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }
