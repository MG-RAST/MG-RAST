package MGRAST::WebPage::CreateJob;

use strict;
use warnings;
no warnings('once');

use POSIX;
use File::Basename;
use URI::Escape;

use Data::Dumper;
use File::Copy;
use File::Temp;
use Archive::Tar;
use FreezeThaw qw( freeze thaw );
use Digest::MD5 qw(md5 md5_hex md5_base64);

use Global_Config;
use WebConfig;
use MGRAST::MGRAST;

use base qw( WebPage );

$Data::Dumper::Terse  = 1;
$Data::Dumper::Indent = 1;

1;


=pod

=head1 NAME

CreateJob - upload files and display uploaded files to user for creation of jobs

=head1 DESCRIPTION

Page used by user to upload files and create jobs from uploaded files

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Upload metagenome");
  $self->{icon} = "<img src='./Html/mg-upload.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  $self->application->register_component('TabView', 'Tabs');
  $self->application->register_component('Ajax',    'AjaxForms');
  $self->application->register_component('Hover',   'FormHover');

  $self->application->register_component('Table', 'status_table');
  $self->application->register_component('Table', 'metadata_table');
  $self->application->register_component('Table', 'demultiplex_table');
  $self->application->register_component('Table', 'sample_mapping_table');
}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
    my ($self) = @_;

    my $application = $self->application;
    my $cgi         = $application->cgi;
    my $user        = $application->session->user;
    my $jobmaster  = $application->data_handle('MGRAST');

    unless ($user) {
	return "<p>You must be logged in to upload metagenome files and create jobs.</p><p>Please use the login box in the top right corner or return to the <a href='metagenomics.cgi'>start page</a>.</p>";
    }

    my $lock_file = $FIG_Config::locks . '/upload.lock';
    if ( -e $lock_file )
    {
	my $message = &lock_file_message($lock_file);
	$application->add_message('warning', $message);
	$self->title("Upload suspended");
	return '';
    }

    if ( $cgi->param('fileId') and
	 $cgi->param('fileLength') and
	 $cgi->param('fileName') and
	 $cgi->param('file') )
    {
	$self->upload_file();
    }

    my $content = '';

    if ( $cgi->param('delete_upload') ) {
      $self->delete_upload();
    } elsif ( $cgi->param('mid_tags') || $cgi->param('bc_length') || $cgi->param('barcode_file')) {
      $self->demultiplex();
    } elsif ( $cgi->param('merge_files') ) {
      $self->merge();
    } elsif ( $cgi->param('metadata') ) {
      $self->add_metadata();
    } elsif ($cgi->param('step') and $cgi->param('step') eq 'finish_submission') {
      # check for resubmitted jobs -- e.g. back button submits form for job creation a second time
      my $job_id = $self->check_job_id();
      
      if ( $job_id ) {
	my $link = qq(<a href="metagenomics.cgi?page=MetagenomeSelect&show_job_details=1">$job_id</a>);
	$self->application->add_message('info', "Your upload will be processed as job number $link");
      } else {
	$self->mark_file_as_done();
	$content .= $self->finish_submission();
      }
    }
  
    $content .= $application->component('AjaxForms')->output();

    $content .= "<input type='hidden' id='uid' value='".$user->login."'>";

    my $hover = $application->component('FormHover');
    $self->add_tooltips();
    $content .= $hover->output();    

    $content .= qq~<style>h2 { margin-top: 0px; }</style>
<script type='text/javascript'>
function uploaderFileStatusChanged( uploader, file ) {
    var status = file.getStatus();
    if (status == 2) {
        window.top.location = "?page=CreateJob";
    }
    if (status == 1) {
        document.getElementById("~. $application->component('Tabs')->id .qq~_tab_1").onclick="";
        document.getElementById("~. $application->component('Tabs')->id .qq~_tab_2").onclick="";
        document.getElementById("~. $application->component('Tabs')->id .qq~_tab_3").onclick="";
        document.getElementById("~. $application->component('Tabs')->id .qq~_tab_4").onclick="";
    }
}
</script>
~;
    $content .= '<script type="text/javascript">
    var BP_SEARCH_SERVER = "http://stage.bioontology.org";
    var BP_ontology_id = "";
    var BP_search_branch = "";
    var BP_include_definitions = true;
</script>

<script src="http://stage.bioontology.org/javascripts/widgets/quick_jump.js" type="text/javascript" charset="utf-8"></script>
<script src="http://stage.bioontology.org/javascripts/widgets/form_complete.js" type="text/javascript" charset="utf-8"></script>';

    $content .= qq~
<script type='text/javascript'>
function notEmpty(elem){
    if(elem.value.length == 0){
	alert("Please enter a metagenome name");
	elem.focus();
	return false;
    }
    return true;
}
</script>
~;
    
    $content .= $self->upload_page();

    return $content;
}

sub upload_page {
    my($self) = @_;

    my $tab_view = $self->application->component('Tabs');
    $tab_view->width(800);
    $tab_view->height(500);

    my $tab_default = 0; # use to specify which tab to display, first tab is numbered zero

    my $tab1_content = "<h2>select upload files</h2><br>".$self->jumploader_applet();
    my $rand_str      = $self->random_string();
    $tab1_content    .= qq(<p><h2><li>while your upload is in progress, other tabs will be disabled.</li></h2>\n);
    $tab1_content .= "<p><h2><li>If you cannot see the uploader window, please enable Java in your browser.<a href='http://blog.metagenomics.anl.gov/howto/' target=_blank><sup>[?]</sup></a></li></h2></p>";
    $tab_view->add_tab("<table><tr><td><img src='./Html/circ_one.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>select upload files</td></tr></table>", $tab1_content);

    my $tab2_content = $self->upload_status_table();

    my $uploads = $self->{uploads};

    if ( scalar(@$uploads) ) 
    {
      my $job_tables = $self->job_tables();
      my $i = 0;
      foreach my $jt (@$job_tables) {
	$tab2_content .= "<div id='jt_".$uploads->[$i]->[1]."' style='display: none;'>$jt</div>";
	$i++;
      }
      $tab_default = 4;

      if (! $self->{metadata_checked}) {
	$tab_default = 3;
      }
      
      if (! $self->{sample_mapping_checked}) {
	$tab_default = 2;
      }
      if (! $self->{demultiplexing_checked}) {
	$tab_default = 1;
      }
    } else {
      $tab_default = 0;
    }

    if ($self->application->cgi->param('nstep')) {
      $tab_default = $self->application->cgi->param('nstep');
    }

    $tab_view->add_tab("<table><tr><td><img src='./Html/circ_two.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>de-multiplex</td></tr></table>", $self->demultiplex_info($uploads));

    $tab_view->add_tab("<table><tr><td><img src='./Html/circ_three.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>sample mapping</td></tr></table>", $self->sample_mapping($uploads));

    my $metadata_info = $self->metadata_info($uploads);
    $tab_view->add_tab("<table><tr><td><img src='./Html/circ_four.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>metadata</td></tr></table>", $metadata_info);

    $tab_view->add_tab("<table><tr><td><img src='./Html/circ_five.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>review & finish</td></tr></table>", $tab2_content || "");    

    $tab_view->default($tab_default);
    $tab_view->orientation('vertical');
    return "<p style='width: 600px; margin-left: 160px;'>To provide you with optimal performance and analysis results, we need you to provide us with some information about your uploaded files. For a detailed guide on uploading, please refer to our <a href='http://blog.metagenomics.anl.gov/howto/' target=_blank>support pages</a>.</p>".$tab_view->output();
}

sub demultiplex_info { 
  my ($self, $uploads) = @_;

  my $application = $self->application;
  my $user        = $application->session->user;
  my $cgi         = $application->cgi;
  my $user_md5    = $self->user_md5($user);
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  my $jobmaster  = $application->data_handle('MGRAST');

  my $tab_view = $application->component('Tabs');

  my $html = "<h2>de-multiplex</h2><p>The MG-RAST upload preprocessing will try to automatically determine if your files are barcoded and need to be de-multiplexed. The best way to reliably use barcodes is to supply the barcoding information in the file_info file within an uploaded archive. For more information on file_info files, please refer to our <a href='http://blog.metagenomics.anl.gov/howto/quality-control/' target=_blank>support pages</a>.</p><p>If you feel the de-multiplexing information that has been autodetected is incorrect, you can update it here.</p>";

  my $t = $application->component('demultiplex_table');
  $t->items_per_page(20);
  $t->show_select_items_per_page(1);
  $t->show_top_browse(1);
  $t->show_bottom_browse(1);
  $t->columns( [ { name => 'file origin' },
		 { name => 'target file', filter => 1 },
		 { name => 'filedir', visible => 0 },
		 { name => 'demultiplexed', filter => 1, operator => 'combobox' },
		 { name => 'barcode' },
		 { name => 'barcode source' },
		 { name => 'details' },
	       ] );
  my $data = [];
  my $filerec = {};
  my $last_upload_dir = '';

  my $row_index = 0;
  foreach my $upload (@$uploads) {
    if ($upload->[0] ne $last_upload_dir) {
      $filerec = $self->{filerecs}->{$upload->[0]};
      $last_upload_dir = $upload->[0];
    }

    my $fn = $upload->[1];

    my $detect = "";
    my $bc_length = "";
    if (! $filerec->{$fn}->{demultiplex_checked} ) {
      if ($filerec->{$fn}->{barcode} && (($bc_length) = $filerec->{$fn}->{barcode} =~ /^autodetect\s(\d+)$/)) {
	$detect = "barcodes of length $bc_length detected<br><input type='button' value='demultiplex now' onclick='window.top.location=\"?page=CreateJob&file=$fn&dir=$last_upload_dir&bc_length=$bc_length\"'>";
      } else {
	my $full_fn = $user_dir."/".$last_upload_dir."/".$fn;
	my $res = `nmerprefix.pl -amplicon -fasta $full_fn -m 10000`;
	if ($res =~ /Barcode/) {
	  ($bc_length) = $res =~ /Barcode[\t\s]+(\d+)/;
	  $detect = "barcodes of length $bc_length detected<br><input type='button' value='demultiplex now' onclick='window.top.location=\"?page=CreateJob&file=$fn&dir=$last_upload_dir&bc_length=$bc_length\"'>";
	  $filerec->{$fn}->{barcode} = "autodetect $bc_length";
	  $self->write_processed_log($user_dir, $last_upload_dir, $filerec);
	}
      }
    }

    my $bar_upload = $self->start_form('barform', { file => $fn, dir => $last_upload_dir })."<input type='file' name='barcode_file'><input type='submit' value='upload barcode file'>".$self->end_form();

    push(@$data, [ $filerec->{$fn}->{origin} || $fn , $fn, $last_upload_dir, ($filerec->{$fn}->{barcode} && $filerec->{$fn}->{barcode} !~ /autodetect/) ? "yes" : "no", $detect || $filerec->{$fn}->{barcode} || $bar_upload, $filerec->{$fn}->{demultiplex_source} || '-', "<input type='button' value='show details' onclick='show_demult_details(\"".$t->id."\", \"$row_index\");'>"]);
    $row_index++;
  }
  $t->data($data);

  $html .= $t->output();

  $html .= "<div id='demult_detail_info'></div>";

  $html .= "<p><input type='button' value='accept and proceed to next step' onclick='window.top.location=\"?page=CreateJob&demultiplex_accepted=1\";'></p>";

  return $html;
}

sub sample_mapping {
  my ($self, $uploads) = @_;

  my $application = $self->application;
  my $user        = $application->session->user;
  my $cgi         = $application->cgi;
  my $user_md5    = $self->user_md5($user);
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  my $jobmaster  = $application->data_handle('MGRAST');

  my $tab_view = $application->component('Tabs');

  my $html = "<h2>sample mapping</h2><p>The MG-RAST upload preprocessing will try to automatically determine paired end information in your uploaded files. The best way to reliably use pairred end information, is to supply it in the file_info file within an uploaded archive. For more information on file_info files, please refer to our <a href='http://blog.metagenomics.anl.gov/howto/quality-control/' target=_blank>support pages</a>.</p><p>If you feel the sample mapping information that has been autodetected is incorrect, you can update it here.</p>";

  my $t = $application->component('sample_mapping_table');
  $t->items_per_page(20);
  $t->show_select_items_per_page(1);
  $t->show_top_browse(1);
  $t->show_bottom_browse(1);
  $t->columns( [ { name => 'file origin', filter => 1 },
		 { name => 'filedir', visible => 0 },
		 { name => 'target file' },
		 { name => 'mapping type', filter => 1, operator => 'combobox' },
		 { name => 'select', input_type => 'checkbox' },
	       ] );
  my $data = [];
  my $filerec = {};
  my $last_upload_dir = '';
  foreach my $upload (@$uploads) {
    if ($upload->[0] ne $last_upload_dir) {
      $filerec = $self->{filerecs}->{$upload->[0]};
      $last_upload_dir = $upload->[0];
    }

    my $fn = $upload->[1];

    my $mapping_type = 'not mapped';
    if ($filerec->{$fn}->{mapped}) {
      $mapping_type = 'paired end w/o overlap';
    } elsif (! $filerec->{$fn}->{sample_mapping_checked}) {
      
    }

    push(@$data, [ $filerec->{$fn}->{origin} || $fn, $last_upload_dir, $fn, $mapping_type, $last_upload_dir ]);
  }
  $t->data($data);

  $html .= "<input type='button' value='check all' onclick='table_select_all_checkboxes(\"".$t->id."\", 4, 1, 1)'><input type='button' value='uncheck all' onclick='table_select_all_checkboxes(\"".$t->id."\", 4, 0, 1)'><br>";
  $html .= $t->output();

  $html .= "<p><input type='button' value='accept and proceed to next step' onclick='window.top.location=\"?page=CreateJob&sample_mapping_accepted=1\";'></p>";

  return $html;
}

sub metadata_info {
  my ($self, $uploads) = @_;

  my $application = $self->application;
  my $user        = $application->session->user;
  my $cgi         = $application->cgi;
  my $user_md5    = $self->user_md5($user);
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  my $jobmaster  = $application->data_handle('MGRAST');

  my $tab_view = $application->component('Tabs');

  my $t = $application->component('metadata_table');
  $t->columns( [ { name => 'filename', filter => 1 },
		 { name => 'filedir', visible => 0 },
		 { name => 'investigation&nbsp;type', filter => 1, operator => 'combobox' },
		 { name => 'project&nbsp;name', filter => 1, operator => 'combobox' },
		 { name => 'latitude', filter => 1, operator => 'combobox' },
		 { name => 'longitude', filter => 1, operator => 'combobox' },
		 { name => 'location', filter => 1, operator => 'combobox' },
		 { name => 'collection&nbsp;date', filter => 1, operator => 'combobox' },
		 { name => 'biome', filter => 1, operator => 'combobox' },
		 { name => 'feature', filter => 1, operator => 'combobox' },
		 { name => 'material', filter => 1, operator => 'combobox' },
		 { name => 'environmental&nbsp;package', filter => 1, operator => 'combobox' },
		 { name => 'sequencing&nbsp;method', filter => 1, operator => 'combobox' },
		 { name => 'select', input_type => 'checkbox' },
	       ] );
  my $data = [];
  my $filerec = {};
  my $last_upload_dir = '';
  foreach my $upload (@$uploads) {
    if ($upload->[0] ne $last_upload_dir) {
      $filerec = $self->{filerecs}->{$upload->[0]};
      $last_upload_dir = $upload->[0];
    }

    my $fn = $upload->[1];

    my $avail_md = $filerec->{$fn}->{metadata} || {};
    push(@$data, [ $fn, $last_upload_dir, $avail_md->{investigation_type} || "", $avail_md->{project_name} || $avail_md->{add2project2} || "", $avail_md->{lat_lon_lat} || "", $avail_md->{lat_lon_lon} || "", $avail_md->{geo_loc_name} || "", $avail_md->{collection_date} || "", $avail_md->{biome} || "", $avail_md->{feature} || "", $avail_md->{material} || "", $avail_md->{env_package} || "", $avail_md->{seq_meth} || "" ]);
  }
  $t->data($data);

  my $project_sel = "<select name='project_name' onchange='if(this.options[this.selectedIndex].value==\"0\"){document.getElementById(\"add2project2\").style.display=\"\";}else{document.getElementById(\"add2project2\").style.display=\"none\";}'><option value='0'>- new -</option>";
  my $dbm = $application->dbmaster;
  my $pright = $dbm->Rights->get_objects( { name => 'edit', data_type => 'project', granted => 1, scope => $user->get_user_scope } );
  my $ps = [];
  if (scalar(@$pright)) {
    foreach my $pr (@$pright) {
      my $p = $jobmaster->Project->get_objects( { _id => $pr->data_id } );
      if (scalar(@$p)) {
	$project_sel .= "<option value='".$p->[0]->{name}."'>".$p->[0]->{name}."</option>";
      }
    }
  }
  $project_sel .= "</select>";

  my $metadata_info = "<h2>metadata</h2><p>Metadata is an important aspect in data mining metagenomic samples. We ask you to provide at least a minimum set of metadata, following the <a href='' target=_blankn title='Minimal information about metagenomic samples'>MIMS</a> guidelines.</p><p>You also have the option of providing extended metadata about your uploaded samples. You can do so using our metadata editor or by adding a file with metainformation in your uploaded archive. For more information, please visit our <a href='http://blog.metagenomics.anl.gov/howto/quality-control/' target=_blank>support pages</a>.</p><p><strong>Note:</strong><i> Users supplying extensive metadata information will receive a higher priority in our compute queue, as they are supporting the community by providing valuable information for data mining and comparison.</i></p>";
  $metadata_info .= "<input type='button' value='check all' onclick='table_select_all_checkboxes(\"".$t->id."\", 13, 1, 1)'><input type='button' value='uncheck all' onclick='table_select_all_checkboxes(\"".$t->id."\", 13, 0, 1)'><br>";
  $metadata_info .= $t->output()."<br><h2>add metadata to selected files</h2>";
  $metadata_info .= "<div><form name='md_form' id='md_form' onsubmit='if(document.getElementById(\"add2project2\").value==\"enter name of new project\"){document.getElementById(\"add2project2\").value=\"enter name of new project\";}'><input type='hidden' name='page' value='CreateJob'>".$self->start_form('md_form')."<input type='hidden' name='metadata' value=1><input type='hidden' name='nstep' value=3><table>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>investigation type</td><td><select name='investigation_type'><option value=''>- please select -</option><option value='metagenome'>metagenome</option><option value='eukaryote'>eukaryote</option><option value='bacteria_archaea'>bacteria / archaea</option><option value='plasmid'>plasmid</option><option value='virus'>virus</option><option value='organelle'>organelle</option><option value='mimarks-survey'>mimarks-survey</option><option value='mimarks-culture'>mimarks-culture</option></select> <sup title='Nucleic Acid Sequence Report is the root element of all MIGS/MIMS compliant reports as standardized by Genomic Standards Consortium. This field is either eukaryote,bacteria,virus,plasmid,organelle, metagenome, mimarks-survey or mimarks-culture' style='cursor: help;'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>project name</td><td>$project_sel<input type='text' name='add_to_project2' size=25 id='add2project2' value='enter name of new project' style='font-style: italic; color: gray;' onfocus='if(this.value==\"enter name of new project\"){this.value=\"\";this.style.color=\"black\";this.style.fontStyle=\"normal\";}' onblur='if(this.value==\"\"){this.value=\"enter name of new project\";this.style.color=\"gray\";this.style.fontStyle=\"italic\";}'> <sup title='Name of the project within which the sequencing was organized' style='cursor: help;'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>geographic location (latitude and longitude)</td><td><input type='text' name='lat_lon_lat' size=5 id='coord1'> lat <input type='text' name='lat_lon_lon' size=5 id='coord2'> lon <sup title='The geographical origin of the sample as defined by latitude and longitude. The values should be reported in decimal degrees and in WGS84 system' style='cursor: help;'>[?]</sup><a onclick='window.open(\"http://maps.google.com/?q=\"+document.getElementById(\"coord1\").value+\",\"+document.getElementById(\"coord2\").value);' style='color: blue; cursor: pointer; font-size: 8pt;'>click to check coordinates on Google maps</a></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>geographic location (country and/or sea,region)</td><td><input type='text' name='geo_loc_name'> <sup title='The geographical origin of the sample as defined by the country or sea name followed by specific region name. Country or sea names should be chosen from the INSDC country list, or the GAZ ontology (v1.446) (click to open)' style='cursor: help; color: blue;' onclick='window.open(\"http://insdc.org/country.html\");window.open(\"http://bioportal.bioontology.org/visualize/40651\");'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>collection date</td><td><input type='text' name='collection_date' size=10 id='DPC_collection_date'> <sup title='The time of sampling' style='cursor: help;'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>environment (biome)</td><td><input type='text' name='biome' id='biome' class='bp_form_complete-1069,1404-name' size='' data-bp_include_definitions='true'> <sup title='In environmental biome level are the major classes of ecologically similar communities of plants, animals, and other organisms. Biomes are defined based on factors such as plant structures, leaf types, plant spacing, and other factors like climate. Examples include: desert, taiga, deciduous woodland, or coral reef. EnvO (v1.53) terms listed under environmental biome can be found from the link (click to open)' style='cursor: help; color: blue;' onclick='window.open(\"http://bioportal.bioontology.org/visualize/44405/?conceptid=ENVO%3A00000428\");'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>environment (feature)</td><td><input type='text' name='feature' id='feature' class='bp_form_complete-1069,1404-name' size='' data-bp_include_definitions='true'> <sup title='Environmental feature level includes geographic environmental features. Examples include: harbor, cliff, or lake. EnvO (v1.53) terms listed under environmental feature can be found from the link (click to open)' style='cursor: help; color: blue;' onclick='window.open(\"http://bioportal.bioontology.org/visualize/44405/?conceptid=ENVO%3A00002297\");'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>environment (material)</td><td><input type='text' name='material' id='material' class='bp_form_complete-1069,1404-name' size='' data-bp_include_definitions='true'> <sup title='The environmental material level refers to the matter that was displaced by the sample, prior to the sampling event. Environmental matter terms are generally mass nouns. Examples include: air, soil, or water. EnvO (v1.53) terms listed under environmental matter can be found from the link (click to open)' style='cursor: help; color: blue;' onclick='window.open(\"http://bioportal.bioontology.org/visualize/44405/?conceptid=ENVO%3A00010483\");'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>environmental package</td><td><select name='env_package'><option value=''>- please select -</option><option value='air'>air</option><option value='host-associated'>host-associated</option><option value='human-associated'>human-associated</option><option value='human-skin'>human-skin</option><option value='human-oral'>human-oral</option><option value='human-gut'>human-gut</option><option value='human-vaginal'>human-vaginal</option><option value='microbial mat/biofilm'>microbial mat/biofilm</option><option value='miscellaneous natural environment'>miscellaneous natural environment</option><option value='miscellaneous artificial environment'>miscellaneous artificial environment</option><option value='plant-associated'>plant-associated</option><option value='sediment'>sediment</option><option value='soil'>soil</option><option value='wastewater/sludge'>wastewater/sludge</option><option value='water'>water</option></select> <sup title='MIGS/MIMS/MIMARKS extension for reporting of measurements and observations obtained from one or more of the environments where the sample was obtained. All environmental packages listed here are further defined in separate subtables. By giving the name of the environmental package, a selection of fields can be made from the subtables and can be reported' style='cursor: help;'>[?]</sup></td></tr>";
  $metadata_info .= "<tr><td style='font-weight: bold;'>sequencing method</td><td><select name='seq_meth'><option value=''>- please select -</option><option value='GS-20'>GS-20</option><option value='GS-FLX'>GS-FLX</option><option value='paired end GS-FLX'>paired end GS-FLX</option><option value='Titanium'>Titanium</option><option value='paired end Titanium'>paired end Titanium</option><option value='Illumina'>Illumina</option><option value='paired end Illumina'>paired end Illumina</option><option value='Sanger'>Sanger</option><option value='assembled contigs'>assembled contigs</option><option value='Ion Torrent'>Ion Torrent</option><option value='other'>other</option></select> <sup title='Sequencing method used; e.g. Sanger, pyrosequencing, ABI-solid' style='cursor: help;'>[?]</sup></td></tr>";
  $metadata_info .= "</table><div id='metadata_input_div'></div><input type='button' value='add' onclick='check_metadata(\"".$t->id."\");'>".$self->end_form()."<input type='button' value='accept and proceed to next step' onclick='window.top.location=\"?page=CreateJob&metadata_accepted=1\";' style='float: right;'></div>";

  return $metadata_info;
}

sub jumploader_applet {
    my($self, $form_name) = @_;

    # Use regex to filter files displayed for uploading -- no spaces, funky characters etc.
    my $regex = qq(^[a-zA-Z0-9._-]+\$);

    my $jl_applet = qq~
<applet name="jumpLoaderApplet" code="jmaster.jumploader.app.JumpLoaderApplet.class" codebase="$FIG_Config::cgi_url/Html/" archive="$FIG_Config::cgi_url/Html/signed_jumploader_z_2.19.0.jar" width="600" height="325" mayscript>
<param name="uc_uploadUrl" value="$FIG_Config::cgi_url/jumploader.cgi">
<param name="uc_fileNamePattern" value="$regex">
<param name="ac_fireUploaderStatusChanged" value="true"/>
<param name="uc_partitionLength" value="1073741824">
<param name="vc_uploadViewStartUploadButtonText" value="Start upload"/>
<param name="vc_uploadViewStartUploadButtonImageUrl" value="$FIG_Config::cgi_url/Html/upload.png"/>
<param name="vc_uploadViewStopUploadButtonText" value="Stop upload"/>
<param name="vc_uploadViewStopUploadButtonImageUrl" value="$FIG_Config::cgi_url/Html/stop_red.png"/>
</applet>
~;

#<param name="ac_mode" value="MODE_FRAMED"/>
#<param name="uc_maxFiles" value="1">

    return $jl_applet;
}

sub upload_status_table {
    my ($self) = @_;
    
    my $application = $self->application;
    my $user        = $application->session->user;
    my $cgi         = $application->cgi;
    my $user_md5    = $self->user_md5($user);
    my $base_dir    = "$FIG_Config::incoming";
    my $user_dir    = "$base_dir/$user_md5";
    my $status_file = "$base_dir/logs/upload.status";
    my $jobmaster  = $application->data_handle('MGRAST');

    my $filerecs = {};    
    my $uploads = &user_uploads($status_file, $user_md5);

    # for each status, 
    my $stati = { 
	          'upload_started'         => [ 'upload complete',          'uploading ...',                  'processing'],
		  'upload_completed'       => [ 'process file',             'waiting for processing ...',     'processing'],
		  'processing_started'     => [ 'processing completed',     'processing uploaded file ...',   'processing'],
		  'processing_completed'   => [ 'create job',               'awaiting user input',            ''],
		  'demultiplex'            => [ 'demultiplexing',           'waiting for demultiplexing ...', 'processing'],
		  'demultiplexing_started' => [ 'demultiplexing completed', 'demultiplexing ...',             'processing'],
		  'from_demultiplexing'    => [ 'create job',               'awaiting user input',            ''],
		  'processing_error'       => [ '',                         '',                               '']
	      };

    my $table = '';
    my $t = $application->component('status_table');
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_select_items_per_page(1);
    $t->columns( [ { name => 'filename', filter => 1 },
		   { name => 'dir', visible => 0 },
		   { name => 'status', filter => 1, operator => 'combobox' },
		   { name => 'info' },
		   { name => 'user supplied md5' },
		   { name => 'sequence check' },
		   { name => 'metadata', filter => 1, operator => 'combobox' },
		   { name => 'next step' },
		   { name => 'select', input_type => 'checkbox' }] );
    my $data = [];

    $self->{demultiplexing_checked} = 1;
    $self->{sample_mapping_checked} = 1;
    $self->{metadata_checked} = 1;

    my $clean_uploads = [];
    # show current uploads overview
    if ( @$uploads ) {
      my $processing = 0;
      
      $table .= "<h2>review uploads</h2>\n";
      $table .= "<p>The table below shows the current status of all your uploads which are pending to be submitted to the MG-RAST pipeline.</p>";
      my $filerec = {};
      my $last_upload_dir = '';
      foreach my $upload (@$uploads) {
	if ($upload->[0] ne $last_upload_dir) {
	  $filerec = $self->read_processed_log($user_dir, $upload->[0]);
	  $filerecs->{$upload->[0]} = $filerec;
	  $last_upload_dir = $upload->[0];
	}
	next unless exists($filerec->{$upload->[1]});
	next if $upload->[1] eq 'file_info';
	push(@$clean_uploads, $upload);
	my $status =  $upload->[2];
	$status =~ s/_/ /g;
	if ( $stati->{$upload->[2]}->[2] eq 'processing' ) {
	  $processing++;
	}
	my $fn = $upload->[1];
	my $next_step = $stati->{$upload->[2]}->[0];
	my $info = $stati->{$upload->[2]}->[1];
	if ($status eq 'processing error') {
	  if ($filerec->{$fn}->{error}) {
	    $status = "<span style='color: red;'>ERROR</span>";
	    $info = $filerec->{$fn}->{error};
	    
	    $next_step = "<input type='button' value='delete' onclick='window.top.location=\"?page=CreateJob&delete_upload=delete&dir=".$upload->[0]."&file=".$upload->[1]."&step=finish_submission\";'>";
	  }
	} elsif ($status eq 'processing completed') {
	  $status = "<span style='color: green;'>$status</span>";
	}
	if ($next_step eq 'create job') {
	  $next_step = "<input type='button' value='finish upload' onclick='show_detail(\"$fn\");'>";
	}
	my $metadata = "<span style='color: red;'>none provided</span>";
	my $avail_md = $filerec->{$fn}->{metadata} || {};
	if (! defined($cgi->param('demultiplex_accepted'))) {
	  if (! $filerec->{$fn}->{demultiplex_checked}) {
	    $self->{demultiplexing_checked} = 0;
	  }
	}
	if (! defined($cgi->param('sample_mapping_accepted'))) {
	  if (! $filerec->{$fn}->{sample_mapping_checked}) {
	    $self->{sample_mapping_checked} = 0;
	  }
	}
	if (! defined($cgi->param('metadata_accepted'))) {
	  if (! $filerec->{$fn}->{metadata_checked}) {
	    $self->{metadata_checked} = 0;
	  }
	}
	if (defined($avail_md->{biome}) && scalar(keys(%$avail_md)) > 1) {
	  $metadata = "<span style='color: orange;'>minimal information</span>";
	}
	if (scalar(keys(%$avail_md)) == 11) {
	  $metadata = "<span style='color: green;'>MIMS compliant</span>";
	}
	my $calc_md5 = $filerec->{$fn}->{'file_md5'} || "not calculated";
	my $u_md5 = "<span style='color: red;'>not supplied</span> <input type='button' value='add' onclick='add_md5(\"$fn\", \"$last_upload_dir\");'><a href='http://blog.metagenomics.anl.gov/howto/upload_info_files/' target='blank'><sup>[?]</sup></a>";
	if (defined($cgi->param('md5')) && defined($cgi->param('fn')) && defined($cgi->param('dn')) && $last_upload_dir eq $cgi->param('dn') && $fn eq $cgi->param('fn')) {
	  $filerec->{$fn}->{user_supplied_md5} = $cgi->param('md5');
	  $self->write_processed_log($user_dir, $last_upload_dir, $filerec);
	}
	if (defined($filerec->{$fn}->{user_supplied_md5}) && length($filerec->{$fn}->{user_supplied_md5})) {
	  if ($filerec->{$fn}->{'file_md5'} eq $filerec->{$fn}->{user_supplied_md5}) {
	    $u_md5 = "<span style='color: green;'>matching uploaded file</span>";
	  } else {
	    $u_md5 = "<span style='color: red;'>mismatch with uploaded file</span> <input type='button' value='change' onclick='add_md5(\"$fn\", \"$last_upload_dir\");'>";
	  }	     
	}
	if (defined($cgi->param('demultiplex_accepted'))) {
	  if (! $filerec->{$fn}->{demultiplex_checked}) {
	    $filerec->{$fn}->{demultiplex_checked} = 1;
	    $self->write_processed_log($user_dir, $last_upload_dir, $filerec);
	  }
	}
	if (defined($cgi->param('sample_mapping_accepted'))) {
	  if (! $filerec->{$fn}->{sample_mapping_checked}) {
	    $filerec->{$fn}->{sample_mapping_checked} = 1;
	    $self->write_processed_log($user_dir, $last_upload_dir, $filerec);
	  }
	}
	if (defined($cgi->param('metadata_accepted'))) {
	  if (! $filerec->{$fn}->{metadata_checked}) {
	    $filerec->{$fn}->{metadata_checked} = 1;
	    $self->write_processed_log($user_dir, $last_upload_dir, $filerec);
	  }
	}
	my $bp_check = '<span style="color: green;">OK</span>';
	if ($filerec->{$fn}{file_report}{bp_count} < ($FIG_Config::mgrast_min_upload_bp_size || 1000000)) {
	  $bp_check = "<span style='color: red;' title='too little sequence for successful computation'>below threshold</span><sup><a href='http://blog.metagenomics.anl.gov/upload/' target='_blank' title='too little sequence for successful computation'>[?]</a></sup>";
	}
	$info .= "<br><a onclick='show_detail(\"$fn\");' style='cursor: pointer; color: blue;'>&raquo; detail info</a>";
	push(@$data, [ $fn, $upload->[0], $status, $info, $u_md5, $bp_check, $metadata, $next_step, 0 ]);
      }
      $t->data($data);
      $table .= "<input type='button' value='check all' onclick='table_select_all_checkboxes(\"".$t->id."\", 8, 1, 1)'><input type='button' value='uncheck all' onclick='table_select_all_checkboxes(\"".$t->id."\", 8, 0, 1)'><br>";
      $table .= $t->output();
      
      if ( $processing ) {
	my $rand_str = $self->random_string();
	my $msg = qq(<a href="metagenomics.cgi?page=CreateJob&step=$rand_str">Please reload this page periodically to view the progress of your uploaded data set);
	if ( $processing > 1 ) {
	  $msg .= 's';
	}
	$msg .= "</a>\n";
	$msg .= "<p>Typical times would be 5-10 minutes for a 1G uploaded file.<br>During this time, closing the page, logging out or closing the browser will not affect the processing.";
	$table .= "<p>&nbsp;<p>$msg\n";
      }
    }
    
    $table .= "<div id='status_detail'></div>";
    
    # mass operations on selected files
    $table .= "<h2>mass operations</h2>";
    $table .= "<p>You can perform mass operations on all selected files in the table above. Click the checkboxes of the files you want to perform operations on. You can use the table filters in combination with the 'check all' button, to select all files that match certain criteria.</p>";
    $table .= "<p>If you submit an archive with several samples, you can add a file_info file to automatically perform these mass operations during the upload process. For a detailed guide on how to create a file_info file, please refer to <a href='http://blog.metagenomics.anl.gov/howto/file_info' target=_blank>our support pages</a>.</p>";

    $table .= "<a style='color: blue; cursor: pointer;' onclick='if(document.getElementById(\"mass_del\").style.display==\"none\"){document.getElementById(\"mass_del\").style.display=\"\";transfer_selected(\"del\", \"".$t->id."\", 8);}else{document.getElementById(\"mass_del\").style.display=\"none\";}'><b>&raquo;Delete files</b></a>".$self->start_form('mass_del_form', { step => 'finish_submission', delete_upload => 1 } )."<div id='mass_del' style='display:none;'><br><input type='button' onclick='transfer_selected(\"del\", \"".$t->id."\", 8);' value='update selected files'><br><br>selected files:<br><br><div id='metagenomes_del'></div><p><input type='button' value='delete' onclick='if(confirm(\"Do you really want to delete all selected files?\")){document.forms.mass_del_form.submit();}'>".$self->end_form." - delete all files checked in the above table</p></div><br><br>";

    $table .= "<a style='color: blue; cursor: pointer;' onclick='if(document.getElementById(\"mass_finish\").style.display==\"none\"){document.getElementById(\"mass_finish\").style.display=\"\";transfer_selected(\"finish\", \"".$t->id."\", 8);}else{document.getElementById(\"mass_finish\").style.display=\"none\";}'><b>&raquo;Finish upload</b></a>".$self->start_form('mass_finish_form', { step => 'finish_submission' })."<div id='mass_finish' style='display: none;'><br><input type='button' onclick='transfer_selected(\"finish\", \"".$t->id."\", 8);' value='update selected files'><br><br>selected files:<br><br><div id='metagenomes_finish'></div>";

    # get upload parameters
    my $project_sel = "<select name='existing_project' onchange='if(this.options[this.selectedIndex].value==\"0\"){document.getElementById(\"add2project\").style.display=\"\";}else{document.getElementById(\"add2project\").style.display=\"none\";}'><option value='0'>- new -</option>";
    my $dbm = $application->dbmaster;
    my $pright = $dbm->Rights->get_objects( { name => 'edit', data_type => 'project', granted => 1, scope => $user->get_user_scope } );
    my $ps = [];
    if (scalar(@$pright)) {
      foreach my $pr (@$pright) {
	my $p = $jobmaster->Project->get_objects( { _id => $pr->data_id } );
	if (scalar(@$p)) {
	  $project_sel .= "<option value='".$p->[0]->{name}."'>".$p->[0]->{name}."</option>";
	}
      }
    }
    $project_sel .= "</select>";
    $table .= "<table>";
    $table .= "<tr><td>add to a project" . $self->hover_text('add_to_project')."</td><td>$project_sel<input type='text' name='add_to_project' size=25 id='add2project'></td></tr>";
    $table .= "<tr><td>metagenome name prefix".$self->hover_text('mgprefix')."</a></td><td><input type='text' name='metagenome_name_prefix' size=25></td></tr>";
    $table .= '<tr><td>samples contain RNA sequences only' . $self->hover_text('rna_only')."</td><td><input type='radio' name='rna_only' value='1'>yes&nbsp;&nbsp;&nbsp;<input type='radio' name='rna_only' value='0' checked>no</td></tr>";
$table .= "<tr><td>dereplicate sequences" . $self->hover_text('dereplicate')."</td><td><input type='radio' name='dereplicate' value='1' checked>yes&nbsp;&nbsp;&nbsp;<input type='radio' name='dereplicate' value='0'>no</td></tr>";
    $table .= "<tr><td>use dynamic trimming" . $self->hover_text('dynamic_trim')."</td><td><input type='radio' name='dynamic_trim' value='1' onclick='document.getElementById(\"dynamic_trim_on\").style.display=\"inline\"; document.getElementById(\"dynamic_trim_off\").style.display=\"none\";'>yes&nbsp;&nbsp;&nbsp<input type='radio' name='dynamic_trim' value='0' checked onclick='document.getElementById(\"dynamic_trim_on\").style.display=\"none\"; document.getElementById(\"dynamic_trim_off\").style.display=\"inline\";'>no<div id='dynamic_trim_off' style='display: inline;'></div><div id='dynamic_trim_on' style='display: none;'><br>quality threshold for low-quality bases: <input type=\"text\" value=\"15\" size=3 name=\"minimum_quality_score\">" . $self->hover_text('minimum_quality_score')."<br><br>maximum number of low quality bases per read: <input type=\"text\" value=\"5\" size=3 name=\"maximum_low_quality_bases\"></div></td></tr>";
    $table .= "<tr><td>filter sequences by length</td><td><input type='radio' name='length_filter' value='1' checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type='radio' name='length_filter' value='0'>&nbsp;no<br>remove sequences over <input type='text' value='2.0' size=3 name='length_filter_stddev'> standard deviations from the mean length</td></tr>";
    $table .= "<tr><td>filter sequences with ambiguity codes" . $self->hover_text('filter_ambig')."</td><td><input type='radio' name='ambig_filter' value='1' checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type='radio' name='ambig_filter' value='0'>&nbsp;no<br>remove sequences with <input type='text' value='5' size=3 name='ambig_max_count'> or more ambiguity characters</td></tr>";
    
    my $bowtie_options = [ ['h_sapiens_asm', 'H. sapiens, NCBI v36'],
			   ['m_musculus_ncbi37', 'M. musculus, NCBI v37'],
			   ['b_taurus', 'B. taurus, UMD v3.0'],
			   ['d_melanogaster_fb5_22', 'D. melanogaster, Flybase, r5.22'],
			   ['a_thaliana', 'A. thaliana, TAIR, TAIR9'],
			   ['e_coli', 'E. coli, NCBI, st. 536'] ];
    $table .= "<tr><td>screen against model organisms using <a href='http://bowtie-bio.sourceforge.net/' target=_blank>bowtie</a>" . $self->hover_text('bowtie')."</td><td><input type='radio' name='bowtie' value='1' onclick='document.getElementById(\"bowtie_on\").style.display=\"inline\"; document.getElementById(\"bowtie_off\").style.display=\"none\";'>yes&nbsp;&nbsp;&nbsp<input type='radio' name='bowtie' value='0' checked onclick='document.getElementById(\"bowtie_on\").style.display=\"none\"; document.getElementById(\"bowtie_off\").style.display=\"inline\";'>no<div id='bowtie_off' style='display: inline;'></div><div id='bowtie_on' style='display: none;'><br>screen against: <select name='bowtie_org'>";

    foreach my $rec ( @$bowtie_options ) {
      my($short, $long) = @$rec;
      $table .= "<option value='$short'>$long</option>";
    }

    $table .= "</select></div></td></tr>";
    
    $table .= "<tr><td></td><td><input type='button' name='create_job' value='Finish upload' onclick='if(confirm(\"Do you really want to submit all files checked in the table above\nwith these options?\")){alert(\"fake finish all\");}''></td></tr>";
    
    $table .= "</table>";
    $table .= $self->end_form."</div><br>";

    $self->{filerecs} = $filerecs;
    $self->{uploads} = $clean_uploads;

    return $table;
}

sub job_tables {
    my ($self) = @_;
    
    my $application = $self->application;
    my $user        = $application->session->user;
    my $cgi         = $application->cgi;
    
    my $user_md5    = $self->user_md5($user);
    
    my $base_dir    = "$FIG_Config::incoming";
    my $user_dir    = "$base_dir/$user_md5";
    my $status_file = "$base_dir/logs/upload.status";
    
    my $uploads     = $self->{uploads};
    my $job_tables  = [];

    # show current uploads overview
     if ( @$uploads ) 
     {
	foreach my $upload ( @$uploads ) 
	{
	    my($upload_dir, $upload_file, $upload_status) = @$upload;
	    my $info = $self->upload_info($upload_dir, $user_dir);

	    if ( $upload_status eq 'upload_started' ) {
		push @$job_tables, $self->upload_started_table($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'upload_completed' ) {
		push @$job_tables, $self->upload_completed_table($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'processing_started' ) {
		push @$job_tables, $self->processing_started_table($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'processing_error' ) {
		push @$job_tables, $self->processing_error_table($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'processing_completed' ) {
		# Note that there may be multiple files from a single upload file, so multiple tables need to be created
		push @$job_tables, $self->processing_completed_tables($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'demultiplexing' ) {
		push @$job_tables, $self->demultiplex_file($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'demultiplexing' ) {
		#$job_table .= $self->demultiplex_file($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'demultiplexing_started' ) {
		#$job_table .= $self->demultiplex_file($upload_dir, $upload_file, $user_dir, $info);
	    } elsif ( $upload_status eq 'from_demultiplexing' ) {
		push @$job_tables, $self->processing_completed_tables($upload_dir, $upload_file, $user_dir, $info);
	    } else {
		#die "unknown status";
	    }
	}
    }

    return $job_tables;
}

sub upload_info {
    my($self, $upload_dir, $user_dir) = @_;

    my %info = ();
    my $logfile = $self->read_logfile($upload_dir, $user_dir);

    foreach my $line ( @$logfile )
    {
	if ( $line =~ /^(upload\S*)\t([^\t]+)/ ) 
	{
	    $info{$1} = $2;
	}
    }
    
    return \%info;
}

sub read_logfile {
    my($self, $upload_dir, $user_dir) = @_;

    my $logfile = "$user_dir/$upload_dir/logfile";
    if (open(LOG, "<$logfile")) {
      my @lines = <LOG>;
      close(LOG) or die "could not close file '$logfile': $!";
      
      chomp @lines;
      return \@lines;
    } else {
      $self->application->add_message('warning', "could not open file '$logfile': $!");
    }

    return undef;
}

sub table_top_row {
    my($self, $upload_dir) = @_;

    my $upload_date = $self->timestamp_to_date($upload_dir);
    return qq(<tr><th colspan=4>$upload_date</th></tr>\n);
}

sub table_top_row_n {
    my($self, $upload_dir) = @_;

    my $upload_date = $self->timestamp_to_date($upload_dir);
    return qq(<tr><th colspan=2>$upload_date</th></tr>\n);
}

sub table_add_row_1 {
    my($self, $t1, $t2) = @_;
    
    return qq(<tr>\n<td><b>$t1</b></td>\n<td><b>$t2</b></td>\n<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>\n<td>&nbsp;</td>\n</tr>\n);
}

sub flip_bgcolor {
    my($self, $bgcolor) = @_;

    $bgcolor->{value} ||= 'EEEEEE';
    $bgcolor->{value} = ($bgcolor->{value} eq 'EEEEEE')? 'FFFFFF' : 'EEEEEE';
}
	
sub table_add_row_1_n {
    my($self, $t1, $t2) = @_;
    
    return qq(<tr>\n<th style="padding-right:20px;">$t1</th>\n<th>$t2</th>\n</tr>\n);
}

sub table_add_row_2 {
    my($self, $t1, $t2) = @_;
    
    return qq(<tr>\n<td>&nbsp;</td>\n<td align="right">$t1</td>\n<td>&nbsp;</td>\n<td>$t2</td>\n</tr>\n);
}

sub table_add_row_2_n {
    my($self, $t1, $t2, $bgcolor) = @_;
   
    $self->flip_bgcolor($bgcolor);
    return qq(<tr bgcolor="#) . $bgcolor->{value} . qq(">\n<td style="text-align:right; padding-right:20px;">$t1</td>\n<td>$t2</td>\n</tr>\n);
}

sub timestamp_to_date {
    my($self, $timestamp) = @_;
    
    my($year, $month, $date, $hour, $min, $sec) = split(/\./, $timestamp);
    return "$year-$month-$date at $hour:$min:$sec";
    
}

sub upload_started_table {
    my($self, $upload_dir, $upload_file, $user_dir, $info) = @_;

    # get instantaneous size of file while upload is in progress
    my $file_size = -s "$user_dir/$upload_dir/$upload_file";
    my $status    = 'upload in progress';
   
    my $upload_date = $self->timestamp_to_date($upload_dir);
    my $title = "Upload in progress '" . $info->{upload_file} . "' on " . $upload_date;

    my $bgcolor = {};

    my $html = "<h2>$title</h2>\n";
    $html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);
    $html .= $self->table_add_row_1_n('Upload file information:', '');
    $html .= $self->table_add_row_2_n('file size', $self->format_number($file_size) . ' bytes', $bgcolor);
    $html .= $self->table_add_row_2_n('status', $status, $bgcolor);
    $html .= qq(</table>\n);
    
    return $html;
}

sub upload_completed_table {
    my($self, $upload_dir, $upload_file, $user_dir, $info) = @_;

    my $status = 'upload completed, processing not started';

    my $upload_date = $self->timestamp_to_date($upload_dir);
    my $title = "Upload in progress '" . $info->{upload_file} . "' on " . $upload_date;

    my $bgcolor = {};

    my $html = "<h2>$title</h2>\n";
    $html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);
    $html .= $self->table_add_row_1_n('Upload file information:', '');
    $html .= $self->table_add_row_2_n('file size', $self->format_number($info->{upload_file_size}) . ' bytes', $bgcolor);
    $html .= $self->table_add_row_2_n('md5', $info->{upload_file_md5}, $bgcolor);
    $html .= $self->table_add_row_2_n('status', $status, $bgcolor);
    $html .= "</table>";
    
    return $html;
}

sub processing_started_table {
    my($self, $upload_dir, $upload_file, $user_dir, $info) = @_;

    my $status = 'upload completed, processing started';

    my $upload_date = $self->timestamp_to_date($upload_dir);
    my $title = "Processing '" . $info->{upload_file} . "' on " . $upload_date;

    my $bgcolor = {};

    my $html = "<h2>$title</h2>\n";
    $html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);
    $html .= $self->table_add_row_1_n('Upload file information:', '');
    $html .= $self->table_add_row_2_n('file size', $self->format_number($info->{upload_file_size}) . ' bytes', $bgcolor);
    $html .= $self->table_add_row_2_n('md5', $info->{upload_file_md5}, $bgcolor);
    $html .= $self->table_add_row_2_n('status', $status, $bgcolor);
    $html .= "</table>";

    return $html;
}

sub processing_error_table {
    my($self, $upload_dir, $upload_file, $user_dir, $info) = @_;

    my $status = 'upload completed, processing error';

    my $upload_date = $self->timestamp_to_date($upload_dir);
    my $filerec = $self->{filerecs}->{$upload_dir};

    next if ( exists $filerec->{$upload_file}{deleted} );

    my $title = "Processing error: '" . $info->{upload_file} . "' on " . $upload_date;

    my $html = '';

    my $rand_str  = $self->random_string();
    my $form_name = $filerec->{$upload_file}{file_name} . '.' . $rand_str;
    $html .= $self->start_form($form_name, { dir => $upload_dir, file => $filerec->{$upload_file}{file_name}, step => 'finish_submission' });

    $html .= "<h2>$title</h2>\n";

    $html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);

    my $bgcolor = {};
    $html .= $self->table_add_row_1_n('File information:', '');
    $html .= $self->table_add_row_2_n('file name', $upload_file, $bgcolor);
    $html .= $self->table_add_row_2_n('file size', $self->format_number($info->{upload_file_size}) . ' bytes', $bgcolor);
    $html .= $self->table_add_row_2_n('md5', $info->{upload_file_md5}, $bgcolor);
    $html .= $self->table_add_row_2_n('<font color="#FF0000">ERROR</font>', $filerec->{$upload_file}{error}, $bgcolor);

    my $txt_left = '';
    my $txt_right = qq(<input type="submit" name="delete_upload" value="delete">);
    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);

    $html .= "</table>\n";
    $html .= "</form>\n";

    return $html;
}

sub hover_text {
    my($self, $type) = @_;

    my $hover = $self->application->component('FormHover');

    return "<span id=\"$type\" onmouseover=\"hover(event, '$type', " . $hover->id . ")\"><sup style=\"cursor: help\">[?]</sup></span>";
}

sub add_tooltips {
    my($self) = @_;

    # add text associated with each hover tooltip
    my $hover = $self->application->component('FormHover');

    my %text = ('ambig_char_count'      => 'Number of non-ATCG characters',
		'ambig_sequence_count'  => 'Number of sequences with non-ATCG characters',
		'average_ambig_chars'   => 'Average number of non-ATCG characters per sequence',
		'name'                  => 'Please provide a descriptive name which will be used to identify your data set in MG-RAST',
		'rna_only'              => 'This bypasses the protein similiarity search step; use this option if your sample is 16S amplicon or ITS',
		'demultiplex'           => 'If your sample is multiplexed (bar-coded), we can split it for you based on the multiplex identifier (MID) tags',
		'dereplicate'           => 'Remove all but one sequence from sets of initially-identical sequences',
		'dynamic_trim'          => 'Discard low-quality bases in reads based on quality score',
		'minimum_quality_score' => 'Specify the lowest phred score that will be counted as a high-quality base',
		'maximum_low_quality_bases' => 'Sequences will be trimmed to contain at most this many bases below the above-specified quality',
		'filter_ambig'          => 'Remove sequences with more than a specified number of non-ACTG characters',
		'bowtie'                => 'Remove sequences that are similar to the genome of the selected species',
		'mgprefix'              => 'All created jobs will be named with this prefix, followed by the filename w/o its suffix',
		'add_to_project'        => 'enter the name of a new or an existing project<br>to add the selected metagenomes to',
		);

    foreach my $key ( keys %text )
    {
	$hover->add_tooltip($key, $text{$key});
    }
}

sub processing_completed_tables {
    my($self, $upload_dir, $upload_file, $user_dir, $info) = @_;

    my @tables = ();
    
    my $upload_date = $self->timestamp_to_date($upload_dir);

    my $filerec = $self->{filerecs}->{$upload_dir};
    my $file_log = "$user_dir/$upload_dir/processed_files";

    my @fastq_files = grep {not exists $filerec->{$_}{deleted}} grep {not exists $filerec->{$_}{job_created}} grep {not exists $filerec->{$_}{error}} grep {$filerec->{$_}{file_format} eq 'fastq'} keys %$filerec;
    
    foreach my $file ( sort @fastq_files )
    {
	my $html = '';
	my $rand_str  = $self->random_string();
	my $form_name = 'form_' . $rand_str;

	$html .= qq(<form id="$form_name" method="post" action="metagenomics.cgi">\n);
	$html .= qq(<input type="hidden" name="dir" value="$upload_dir">\n);
	$html .= qq(<input type="hidden" name="file" value="$filerec->{$file}{fasta_file}">\n);
	$html .= qq(<input type="hidden" name="step" value="finish_submission">\n);
	$html .= qq(<input type='hidden' name='page' id='page' value='CreateJob'>\n);

	my $upload_date = $self->timestamp_to_date($upload_dir);
	my $title = "Uploaded file '" . $info->{upload_file} . "' on " . $upload_date;
	$html .= "<h2>$title</h2>\n";

	# put upload file information at top
	$html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);

	my $bgcolor = {};
	$html .= $self->table_add_row_1_n('Upload file information:', '');
	$html .= $self->table_add_row_2_n('file size', $self->format_number($info->{upload_file_size}) . ' bytes', $bgcolor);
	
	# print information about fasta file
	# skip the single uncompressed fastq file uploaded
	if ( $filerec->{$file}{file_name} ne $info->{upload_file} ) 
	{
	    $html .= $self->table_add_row_1_n('FASTQ file', $filerec->{$file}{file_name});
	    $html .= $self->table_add_row_2_n('file size', $self->format_number($filerec->{$file}{file_size}) . ' bytes', $bgcolor);
	}
	else
	{
	    # print fastq file information
	    $html .= $self->table_add_row_2_n('format', 'FASTQ', $bgcolor);
	}

	# print information about fasta file extracted from fastq file
	my $fasta_file = $filerec->{$file}{fasta_file};

	if ( exists $filerec->{$fasta_file}{error} )
	{
	    $html .= $self->table_add_row_2_n('ERROR', $filerec->{$fasta_file}{error}, $bgcolor);
	}
	else
	{
	    $html .= $self->table_add_row_2_n('number of sequences', $filerec->{$fasta_file}{file_report}{sequence_count}, $bgcolor);
	    $html .= $self->table_add_row_2_n('number of base pairs', $self->format_number($filerec->{$fasta_file}{file_report}{bp_count}), $bgcolor);
	    $html .= $self->table_add_row_2_n('average sequence length', $self->format_number($filerec->{$fasta_file}{file_report}{average_length}) . " bp", $bgcolor);
	    $html .= $self->table_add_row_2_n('sequence length standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_length}) . " bp", $bgcolor);
	    $html .= $self->table_add_row_2_n('average gc content', $self->format_number($filerec->{$fasta_file}{file_report}{average_gc_content}) . " %", $bgcolor);
	    $html .= $self->table_add_row_2_n('gc content standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_gc_content}) . " %", $bgcolor);
	    $html .= $self->table_add_row_2_n('average gc ratio', $self->format_number($filerec->{$fasta_file}{file_report}{average_gc_ratio}), $bgcolor);
	    $html .= $self->table_add_row_2_n('gc ratio standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_gc_ratio}), $bgcolor);

	    if ( $filerec->{$fasta_file}{file_report}{ambig_char_count} ) {
		$html .= $self->table_add_row_2_n('number of ambiguity characters' . $self->hover_text('ambig_char_count'), $self->format_number($filerec->{$fasta_file}{file_report}{ambig_char_count}), $bgcolor);
		$html .= $self->table_add_row_2_n('sequences with ambiguity characters' . $self->hover_text('ambig_sequence_count'), $self->format_number($filerec->{$fasta_file}{file_report}{ambig_sequence_count}), $bgcolor);
		$html .= $self->table_add_row_2_n('average ambiguity characters per sequence' . $self->hover_text('average_ambig_chars'), $self->format_number($filerec->{$fasta_file}{file_report}{average_ambig_chars}), $bgcolor);
	    }

	    $bgcolor = {};
	    $html .= $self->table_add_row_1_n('Create MG-RAST job', '');
	    
	    $html .= $self->table_add_row_2_n('metagenome name' . $self->hover_text('name'), qq(<input type="text" value="" size=50 name="metagenome_name" id="$rand_str">), $bgcolor);

	    my $txt_left = 'sample contains only ribosomal RNA sequences' . $self->hover_text('rna_only');
	    my $txt_right = qq(<input type="radio" name="rna_only" value="1">&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="rna_only" value="0" checked>&nbsp;no);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    
	    $txt_left = 'demultiplex sequences' . $self->hover_text('demultiplex');
	    $txt_right = qq(<input type='radio' name='demultiplex' value='1' onclick='document.getElementById("demultiplex_on_$rand_str").style.display="inline"; document.getElementById("demultiplex_off_$rand_str").style.display="none";'>&nbsp;yes) .
		         '&nbsp;&nbsp;&nbsp' .
			 qq(<input type='radio' name='demultiplex' value='0' checked onclick='document.getElementById("demultiplex_on_$rand_str").style.display="none"; document.getElementById("demultiplex_off_$rand_str").style.display="inline";'>no) .
			 qq(<div id='demultiplex_off_$rand_str' style='display: inline;'></div>) .
			 qq(<div id='demultiplex_on_$rand_str' style='display: none;'>) .
			 qq(<br>enter multiplex identifier (MID) tags:<br><textarea cols=50 rows=10 name='mid_tags'></textarea>) .
			 qq(</div>);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    
	    $txt_left = 'dereplicate sequences' . $self->hover_text('dereplicate');
	    $txt_right = qq(<input type="radio" name="dereplicate" value="1" checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="dereplicate" value="0">&nbsp;no);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    

	    if ( exists $filerec->{$fasta_file}{fastq_file} or 
		 exists $filerec->{$fasta_file}{sff_file}   or
		 $filerec->{$fasta_file}{file_format} eq 'fasta' and exists $filerec->{$fasta_file}{qual_file} )
	    {
		$txt_left = 'use dynamic trimming' . $self->hover_text('dynamic_trim');
		$txt_right = qq(<input type='radio' name='dynamic_trim' value='1' onclick='document.getElementById("dynamic_trim_on_$rand_str").style.display="inline"; document.getElementById("dynamic_trim_off_$rand_str").style.display="none";'>yes) .
		             '&nbsp;&nbsp;&nbsp' .
			     qq(<input type='radio' name='dynamic_trim' value='0' checked onclick='document.getElementById("dynamic_trim_on_$rand_str").style.display="none"; document.getElementById("dynamic_trim_off_$rand_str").style.display="inline";'>no) .
			     qq(<div id='dynamic_trim_off_$rand_str' style='display: inline;'></div>) .
			     qq(<div id='dynamic_trim_on_$rand_str' style='display: none;'>) .
			     qq(<br>quality threshold for low-quality bases: <input type="text" value="15" size=3 name="minimum_quality_score">) . $self->hover_text('minimum_quality_score') .
			     qq(<br>) .
			     qq(<br>maximum number of low quality bases per read: <input type="text" value="5" size=3 name="maximum_low_quality_bases">) .
			     qq(</div>);
		$html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    }
	    else
	    {
		if ( $filerec->{$fasta_file}{file_report}{standard_deviation_length} > 0 ) 
		{
		    $txt_left = 'filter sequences by length';
		    $txt_right = qq(<input type="radio" name="length_filter" value="1" checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="length_filter" value="0">&nbsp;no<br>) .
			qq(remove sequences over <input type="text" value="2.0" size=3 name="length_filter_stddev"> standard deviations from the mean length);
		    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
		}
		
		if ( $filerec->{$fasta_file}{file_report}{ambig_char_count} > 0 )
		{
		    $txt_left = 'filter sequences with ambiguity codes' . $self->hover_text('filter_ambig');
		    $txt_right = qq(<input type="radio" name="ambig_filter" value="1" checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="ambig_filter" value="0">&nbsp;no<br>) .
			qq(remove sequences with <input type="text" value="5" size=3 name="ambig_max_count"> or more ambiguity characters);
		    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
		}
	    }

	    # this should not be hardcoded here -- maybe put in file in bowtie index directory
	    my $bowtie_options = [ # ['hg18', 'H. sapiens, UCSC hg18'],
				   # ['hg19', 'H. sapiens, UCSC hg19'],
				   ['h_sapiens_asm', 'H. sapiens, NCBI v36'],
				   # ['h_sapiens_37_asm', 'H. sapiens, NCBI v37'],
				   # ['mm8', 'M. musculus, UCSC mm8'],
				   # ['mm9', 'M. musculus, UCSC mm9'],
				   ['m_musculus_ncbi37', 'M. musculus, NCBI v37'],
				   # ['rn4', 'R. norvegicus, UCSC rn4'],
				   ['b_taurus', 'B. taurus, UMD v3.0'],
				   # ['canFam2', 'C. familiaris, UCSC canFam2'],
				   # ['g_gallus', 'G. gallus, UCSC, galGal3'],
				   ['d_melanogaster_fb5_22', 'D. melanogaster, Flybase, r5.22'],
				   ['a_thaliana', 'A. thaliana, TAIR, TAIR9'],
				   # ['c_elegans_ws200', 'C. elegans, Wormbase, WS200'],
				   # ['s_cerevisiae', 'S. cerevisiae, CYGD'],
				   ['e_coli', 'E. coli, NCBI, st. 536'] ];
	    
	    $txt_left  = qq(screen against model organisms using <a href="http://bowtie-bio.sourceforge.net/" target=_blank>bowtie</a>) . $self->hover_text('bowtie');
	    $txt_right = qq(<input type='radio' name='bowtie' value='1' onclick='document.getElementById("bowtie_on_$rand_str").style.display="inline"; document.getElementById("bowtie_off_$rand_str").style.display="none";'>&nbsp;yes) .
		         '&nbsp;&nbsp;&nbsp' .
			 qq(<input type='radio' name='bowtie' value='0' checked onclick='document.getElementById("bowtie_on_$rand_str").style.display="none"; document.getElementById("bowtie_off_$rand_str").style.display="inline";'>no) .
			 qq(<div id='bowtie_off_$rand_str' style='display: inline;'></div>) .
			 qq(<div id='bowtie_on_$rand_str' style='display: none;'>) .
			 qq(<br>screen against: ) .
			 qq(<select name='bowtie_org'>\n);
	    
	    foreach my $rec ( @$bowtie_options )
	    {
		my($short, $long) = @$rec;
		$txt_right .= qq(<option value="$short">$long</option>\n);
	    }
	    
	    $txt_right .=qq(</select>\n) .
		         qq(</div>\n);

	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    
	    $txt_left = '';
	    $txt_right = qq(<input type="button" name="create_job" value="Finish upload" onclick="alert('I told you not to click :P');">&nbsp;&nbsp;<input type="submit" name="delete_upload" value="delete">);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	}

	$html .= "</table>\n";
	$html .= "</form>\n";

	push @tables, $html;
    }

    # only fasta files get marked with status processing_completed, others get status processing_terminated (tar, zip, etc.)
    my @fasta_files = grep {not exists $filerec->{$_}{deleted}} 
                        grep {not exists $filerec->{$_}{job_created}} 
                          grep {not exists $filerec->{$_}{error}} 
                            grep {$filerec->{$_}{file_format} eq 'fasta'} 
                              grep {$_ eq $upload_file} 
                                keys %$filerec;

    foreach my $fasta_file ( sort @fasta_files )
    {
	my $html = '';
	# fix -- to avoid files flagged as fastq which come from sff files
	# ignore fasta files which were created from fastq files (reported above)
	next if (exists $filerec->{$fasta_file}{fastq_file} and $filerec->{$fasta_file}{fastq_file} !~ /\.qual/);

	my $rand_str  = $self->random_string();
	my $form_name = 'form_' . $rand_str;

	$html .= qq(<form id="$form_name" method="post" action="metagenomics.cgi">\n);
	$html .= qq(<input type="hidden" name="dir" value="$upload_dir">\n);
	$html .= qq(<input type="hidden" name="file" value="$filerec->{$fasta_file}{file_name}">\n);
	$html .= qq(<input type="hidden" name="step" value="finish_submission">\n);
	$html .= qq(<input type='hidden' name='page' id='page' value='CreateJob'>\n);
	
	my $upload_date = $self->timestamp_to_date($upload_dir);
	my $title = "Uploaded file '" . $info->{upload_file} . "' on " . $upload_date;
	$html .= "<h2>$title</h2>\n";

	# put upload file information at top
	$html .= qq(<p><table width="100%" border="0" cellspacing="0" cellpadding="2">\n);

	my $bgcolor = {};
	$html .= $self->table_add_row_1_n('Upload file information:', '');
	$html .= $self->table_add_row_2_n('file_size', $self->format_number($info->{upload_file_size}) . ' bytes', $bgcolor);
	
	# print information about fasta file
	# skipping the single uncompressed fasta file uploaded
	if ( $filerec->{$fasta_file}{file_name} ne $info->{upload_file} ) 
	{
	    $html .= $self->table_add_row_1_n('FASTA file', $filerec->{$fasta_file}{file_name});
	    $html .= $self->table_add_row_2_n('file_size', $self->format_number($filerec->{$fasta_file}{file_size}) . ' bytes', $bgcolor);
	}

	if ( exists $filerec->{$fasta_file}{error} )
	{
	    $html .= $self->table_add_row_2_n('ERROR', $filerec->{$fasta_file}{error}, $bgcolor);
	}
	else
	{
	    $html .= $self->table_add_row_2_n('number of sequences', $self->format_number($filerec->{$fasta_file}{file_report}{sequence_count}), $bgcolor);
	    $html .= $self->table_add_row_2_n('number of base pairs', $self->format_number($filerec->{$fasta_file}{file_report}{bp_count}), $bgcolor);
#	    $html .= $self->table_add_row_2_n('shortest sequence', $self->format_number($filerec->{$fasta_file}{file_report}{length_min}) . ' bp (seq id: ' . $filerec->{$fasta_file}{file_report}{id_length_min} . ')', $bgcolor);
#	    $html .= $self->table_add_row_2_n('longest sequence',  $self->format_number($filerec->{$fasta_file}{file_report}{length_max})  . ' bp (seq id: ' . $filerec->{$fasta_file}{file_report}{id_length_max}  . ')', $bgcolor);
	    $html .= $self->table_add_row_2_n('average sequence length', $self->format_number($filerec->{$fasta_file}{file_report}{average_length}) . " bp", $bgcolor);
	    $html .= $self->table_add_row_2_n('sequence length standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_length}) . " bp", $bgcolor);
	    $html .= $self->table_add_row_2_n('average gc content', $self->format_number($filerec->{$fasta_file}{file_report}{average_gc_content}) . " %", $bgcolor);
	    $html .= $self->table_add_row_2_n('gc content standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_gc_content}) . " %", $bgcolor);
	    $html .= $self->table_add_row_2_n('average gc ratio', $self->format_number($filerec->{$fasta_file}{file_report}{average_gc_ratio}), $bgcolor);
	    $html .= $self->table_add_row_2_n('gc ratio standard deviation', $self->format_number($filerec->{$fasta_file}{file_report}{standard_deviation_gc_ratio}), $bgcolor);
	    
	    if ( $filerec->{$fasta_file}{file_report}{ambig_char_count} ) {
	      $html .= $self->table_add_row_2_n('number of ambiguity characters' . $self->hover_text('ambig_char_count'), $self->format_number($filerec->{$fasta_file}{file_report}{ambig_char_count}), $bgcolor);
	      $html .= $self->table_add_row_2_n('sequences with ambiguity characters' . $self->hover_text('ambig_sequence_count'), $self->format_number($filerec->{$fasta_file}{file_report}{ambig_sequence_count}), $bgcolor);
	      $html .= $self->table_add_row_2_n('average ambiguity characters per sequence' . $self->hover_text('average_ambig_chars'), $self->format_number($filerec->{$fasta_file}{file_report}{average_ambig_chars}), $bgcolor);
	    }
	    
	    if ( exists $filerec->{$fasta_file}{qual_file} ) {
	      my $qual_file = $filerec->{$fasta_file}{qual_file};
	      $html .= $self->table_add_row_1_n('Quality file', $filerec->{$qual_file}{file_name});
	      $html .= $self->table_add_row_2_n('file_size', $self->format_number($filerec->{$qual_file}{file_size}) . ' bytes', $bgcolor);
 	    }

	    $bgcolor = {};
	    $html .= $self->table_add_row_1_n('Create MG-RAST job:', '');
	    $html .= $self->table_add_row_2_n('metagenome name' . $self->hover_text('name'), qq(<input type="text" value="" size=50 name="metagenome_name" id="$rand_str">), $bgcolor);

	    my $txt_left  = 'sample contains RNA sequences only' . $self->hover_text('rna_only');
	    my $txt_right = qq(<input type="radio" name="rna_only" value="1">yes&nbsp;&nbsp;&nbsp;<input type="radio" name="rna_only" value="0" checked>no);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    
	    $txt_left = 'demultiplex sequences' . $self->hover_text('demultiplex');
	    $txt_right = qq(<input type='radio' name='demultiplex' value='1' onclick='document.getElementById("demultiplex_on_$rand_str").style.display="inline"; document.getElementById("demultiplex_off_$rand_str").style.display="none";'>yes) .
		         '&nbsp;&nbsp;&nbsp' .
			 qq(<input type='radio' name='demultiplex' value='0' checked onclick='document.getElementById("demultiplex_on_$rand_str").style.display="none"; document.getElementById("demultiplex_off_$rand_str").style.display="inline";'>no) .
			 qq(<div id='demultiplex_off_$rand_str' style='display: inline;'></div>) .
			 qq(<div id='demultiplex_on_$rand_str' style='display: none;'>) .
			 qq(<br>enter multiplex identifier (MID) tags:<br><textarea cols=50 rows=10 name='mid_tags'></textarea>) .
			 qq(</div>);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);

	    $txt_left = 'dereplicate sequences' . $self->hover_text('dereplicate');
	    $txt_right = qq(<input type="radio" name="dereplicate" value="1" checked>yes&nbsp;&nbsp;&nbsp;<input type="radio" name="dereplicate" value="0">no);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);

	    if ( exists $filerec->{$fasta_file}{fastq_file} or 
		 exists $filerec->{$fasta_file}{sff_file}   or
		 $filerec->{$fasta_file}{file_format} eq 'fasta' and exists $filerec->{$fasta_file}{qual_file} )
	    {
		$txt_left = 'use dynamic trimming' . $self->hover_text('dynamic_trim');
		$txt_right = qq(<input type='radio' name='dynamic_trim' value='1' onclick='document.getElementById("dynamic_trim_on_$rand_str").style.display="inline"; document.getElementById("dynamic_trim_off_$rand_str").style.display="none";'>yes) .
		             '&nbsp;&nbsp;&nbsp' .
			     qq(<input type='radio' name='dynamic_trim' value='0' checked onclick='document.getElementById("dynamic_trim_on_$rand_str").style.display="none"; document.getElementById("dynamic_trim_off_$rand_str").style.display="inline";'>no) .
			     qq(<div id='dynamic_trim_off_$rand_str' style='display: inline;'></div>) .
			     qq(<div id='dynamic_trim_on_$rand_str' style='display: none;'>) .
			     qq(<br>quality threshold for low-quality bases: <input type="text" value="15" size=3 name="minimum_quality_score">) . $self->hover_text('minimum_quality_score') .
			     qq(<br>) .
			     qq(<br>maximum number of low quality bases per read: <input type="text" value="5" size=3 name="maximum_low_quality_bases">) .
			     qq(</div>);
		$html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    }
	    else
	    {
		if ( $filerec->{$fasta_file}{file_report}{standard_deviation_length} > 0 ) 
		{
		    $txt_left = 'filter sequences by length';
		    $txt_right = qq(<input type="radio" name="length_filter" value="1" checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="length_filter" value="0">&nbsp;no<br>) .
			qq(remove sequences over <input type="text" value="2.0" size=3 name="length_filter_stddev"> standard deviations from the mean length);
		    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
		}
		
		if ( $filerec->{$fasta_file}{file_report}{ambig_char_count} > 0 )
		{
		    $txt_left = 'filter sequences with ambiguity codes' . $self->hover_text('filter_ambig');
		    $txt_right = qq(<input type="radio" name="ambig_filter" value="1" checked>&nbsp;yes&nbsp;&nbsp;&nbsp;<input type="radio" name="ambig_filter" value="0">&nbsp;no<br>) .
			qq(remove sequences with <input type="text" value="5" size=3 name="ambig_max_count"> or more ambiguity characters);
		    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
		}
	    }
	    
	    # this should not be hardcoded here -- maybe put in file in bowtie index directory
	    my $bowtie_options = [ # ['hg18', 'H. sapiens, UCSC hg18'],
				   # ['hg19', 'H. sapiens, UCSC hg19'],
				   ['h_sapiens_asm', 'H. sapiens, NCBI v36'],
				   # ['h_sapiens_37_asm', 'H. sapiens, NCBI v37'],
				   # ['mm8', 'M. musculus, UCSC mm8'],
				   # ['mm9', 'M. musculus, UCSC mm9'],
				   ['m_musculus_ncbi37', 'M. musculus, NCBI v37'],
				   # ['rn4', 'R. norvegicus, UCSC rn4'],
				   ['b_taurus', 'B. taurus, UMD v3.0'],
				   # ['canFam2', 'C. familiaris, UCSC canFam2'],
				   # ['g_gallus', 'G. gallus, UCSC, galGal3'],
				   ['d_melanogaster_fb5_22', 'D. melanogaster, Flybase, r5.22'],
				   ['a_thaliana', 'A. thaliana, TAIR, TAIR9'],
				   # ['c_elegans_ws200', 'C. elegans, Wormbase, WS200'],
				   # ['s_cerevisiae', 'S. cerevisiae, CYGD'],
				   ['e_coli', 'E. coli, NCBI, st. 536'] ];

	    $txt_left = qq(screen against model organisms using <a href="http://bowtie-bio.sourceforge.net/" target=_blank>bowtie</a>) . $self->hover_text('bowtie');
	    $txt_right = qq(<input type='radio' name='bowtie' value='1' onclick='document.getElementById("bowtie_on_$rand_str").style.display="inline"; document.getElementById("bowtie_off_$rand_str").style.display="none";'>yes) .
		         '&nbsp;&nbsp;&nbsp' .
			 qq(<input type='radio' name='bowtie' value='0' checked onclick='document.getElementById("bowtie_on_$rand_str").style.display="none"; document.getElementById("bowtie_off_$rand_str").style.display="inline";'>no) .
			 qq(<div id='bowtie_off_$rand_str' style='display: inline;'></div>) .
			 qq(<div id='bowtie_on_$rand_str' style='display: none;'>) .
			 qq(<br>screen against: ) .
			 qq(<select name='bowtie_org'>\n);

	    foreach my $rec ( @$bowtie_options )
	    {
		my($short, $long) = @$rec;
		$txt_right .= qq(<option value="$short">$long</option>\n);
	    }

	    $txt_right .=qq(</select>\n) .
		         qq(</div>\n);


	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	    
	    $txt_left = '';
	    #$txt_right = qq(<input type="button" name="create_job" value="Finish upload" onclick="if(notEmpty(document.getElementById('$rand_str'))){document.forms.$form_name.submit();};">&nbsp;&nbsp;<input type="submit" name="delete_upload" value="delete">);
	    $txt_right = qq(<input type="button" name="create_job" value="Finish upload" onclick="alert('I told you not to click :P');">&nbsp;&nbsp;<input type="submit" name="delete_upload" value="delete">);
	    $html .= $self->table_add_row_2_n($txt_left, $txt_right, $bgcolor);
	}

	$html .= "</table>\n";
	$html .= "</form>\n";

	push @tables, $html;
    }
    
    return @tables;
}

sub user_uploads {
    my($status_file, $user_md5) = @_;
    
    my $line;
    my %status;
    my @uploads = ();

    # delete this
    chmod 0666, $status_file;

    open(STATUS, "<$status_file") or die "could not open file '$status_file': $!";
    flock(STATUS, 1) or die "could not create shared lock for file '$status_file': $!";

    while ( defined($line = <STATUS>) )
    {
	# ignore lines beginning with '#'
	next if ($line =~ /^\#/);

	chomp $line;
	my($user_dir, $upload_dir, $upload_file, $upload_status) = split("\t", $line);

	if ( $user_dir eq $user_md5 )
	{
	    # later status is reported nearer the end of the file, so this will get the latest status
	    $status{$upload_dir}{$upload_file} = $upload_status;
	}
    }

    flock(STATUS, 8) or die "could not unlock file '$status_file': $!";
    close(STATUS) or die "could not close file '$status_file': $!";

    my %ignore = (
		  'deleted'               => 1,     # upload was deleted for some reason
		  'job_created'           => 1,     # job was created
		  'processing_terminated' => 1,     # no further processing, e.g. for tar files
		  'demultiplexing_completed' => 1,  # file was demultiplexed, not needed for further processing
		  );

    # Now convert to list of lists, start by looping through and getting information for individual files
    foreach my $upload_dir ( keys %status )
    {
	foreach my $upload_file ( keys %{ $status{$upload_dir} } )
	{
	    my $upload_status = $status{$upload_dir}{$upload_file};

	    if ( not exists $ignore{$upload_status} )
	    {
		push @uploads, [$upload_dir, $upload_file, $upload_status];
	    }
	}
    }

    # next sort based on $upload_dir timestamp (2010.09.10.13.36.00)
    @uploads = map {$_->[0]} sort {$b->[1] <=> $a->[1] or 
				   $b->[2] <=> $a->[2] or 
				   $b->[3] <=> $a->[3] or
				   $b->[4] <=> $a->[4] or
				   $b->[5] <=> $a->[5] or
				   $b->[6] <=> $a->[6] or
			           $a->[0][1] cmp $b->[0][1]} map {[$_, split(/\./, $_->[0])]}  @uploads;

    return \@uploads;
}

sub upload_file {

}

sub start_preprocess {
    my($user_dir, $upload_dir, $upload_filename, $opt) = @_;

    my $script  = $FIG_Config::run_preprocess;
    my $options = " --user_dir $user_dir --upload_dir $upload_dir --upload_filename '$upload_filename'";

    if ( $opt->{demultiplex} ) {
	$options .= ' --demultiplex';
    }
    
    if ( $opt->{partitioned} ) {
	$options .= ' --partitioned';
    }
    
    my $output = '';

    #eval {
    $output = `$script $options`;
    print STDERR Dumper($output)."\n";
    #};

    if ( $@ ) {
	print STDERR "could not run 'run_preprocess.pl: $@, $output\n";
	die "could not start preprocess";
    }
}

sub mark_status {
    my($self, $status_file, $data) = @_;

    open(STATUS, ">>$status_file") or die "could not open file '$status_file': $!";

    flock(STATUS, 2) or die "could not create exclusive lock for file '$status_file': $!";
    seek(STATUS, 0, 2) or die "could not seek end-of-file for file '$status_file': $!";

    print STATUS join("\t", @$data), "\n";

    flock(STATUS, 8) or die "could not unlock file '$status_file': $!";
    close(STATUS) or die "could not close file '$status_file': $!";
}

sub write_partitioned_log {
    my($self, $partitioned_file, $data) = @_;

    open(P, ">>$partitioned_file") or die "could not open file '$partitioned_file': $!";

    flock(P, 2) or die "could not create exclusive lock for file '$partitioned_file': $!";
    seek(P, 0, 2) or die "could not seek end-of-file for file '$partitioned_file': $!";

    print P join("\t", @$data), "\n";

    flock(P, 8) or die "could not unlock file '$partitioned_file': $!";
    close(P) or die "could not close file '$partitioned_file': $!";
}

sub read_partitioned_log {
    my($self, $partitioned_file, $user_md5) = @_;
    
    my $line;
    my %log;

    open(P, "<$partitioned_file") or die "could not open file '$partitioned_file': $!";
    flock(P, 1) or die "could not create shared lock for file '$partitioned_file': $!";

    while ( defined($line = <P>) )
    {
	# ignore lines beginning with '#'
	next if ($line =~ /^\#/);

	chomp $line;
	my($user_dir, $upload_dir, $filename, $fileId, $partitionIndex, $partitionCount, $status) = split("\t", $line);

	if ( $user_dir eq $user_md5 )
	{
	    push @{ $log{$filename}{$fileId} }, [$upload_dir, $partitionIndex, $partitionCount, $status];
	}
    }

    flock(P, 8) or die "could not unlock file '$partitioned_file': $!";
    close(P) or die "could not close file '$partitioned_file': $!";

    return \%log;
}

=pod

=item * B<save_upload_file> ()

Stores a file from the upload input form to the incoming directory
in the rast jobs directory. If successful the method writes back 
the two cgi parameters I<upload_file> and I<upload_type>.

=cut

sub save_upload_file {
    my ($self, $upload_dir, $numfiles) = @_;

    my $file     = $self->application->cgi->param('file');	
    my $filename = $self->application->cgi->param('fileName');

    if ( $self->application->cgi->param('partitionCount') and $self->application->cgi->param('partitionCount') > 1 )
    {
	# when partitioning is switched on files smaller than the max partition size will have the partitionCount set to 1
	$filename .= '.' . $self->application->cgi->param('partitionIndex');
    }

    my $upload_file = "$upload_dir/$filename";
    my $log_file    = "$upload_dir/logfile";
    my $timestamp   = $self->timestamp;

    open(LOG, ">>$log_file") or die "could not open file '$log_file': $!";
    print LOG "upload\tstarted\t$timestamp\n";

    my $t1 = time;
    
    open(NEW, ">$upload_file") or die "could not open file '$upload_file': $!";

    my($buf, $n, $bytes);
    while (($n = read($file, $buf, 4096)))
    {
	print NEW $buf;
	$bytes += $n;
    }
    close(NEW) or die "could not close file '$upload_file': $!";

    my $ready = 0;
    my @files = <$upload_dir/*>;
    my $count = @files;
    if ($count == $numfiles) {
      $ready = 1;
      `rm $upload_dir/../numuploads`;
    }

    my($file_md5) = (`md5sum $upload_file` =~ /^(\S+)/);
    $timestamp = $self->timestamp;
    my $dt = time - $t1;

    print LOG "upload_file\t$filename\n";
    print LOG "upload_file_size\t$bytes\n";
    print LOG "upload_file_md5\t$file_md5\n";
    print LOG "upload_time\t$dt\n";
    print LOG "upload\tcompleted\t$timestamp\n";
    close(LOG) or die "could not close file '$log_file': $!";

    chmod 0666, $log_file;
    chmod 0666, $upload_file;
}

sub user_md5 {
    my($self, $user) = @_;

    my $user_login = $user->login;
    return md5_hex($user_login);
}

sub create_user_dir {
    my($self, $user, $user_dir) = @_;

    # create directory for user (if required) with a USER file in it
    
    $self->create_dir($user_dir);
    $self->create_user_file($user_dir, $user);
}

sub create_user_file {
    my($self, $user_dir, $user) = @_;

    my $user_file = "$user_dir/USER";
    if ( ! -e $user_file )
    {
	my $user_login = $user->login;
	
	open(USER, ">$user_file") or die "could not open file '$user_file': $!";
	print USER "$user_login\n";
	close(USER) or die "could not close file '$user_file': $!";

	chmod 0666, $user_file;
    }
}

sub create_dir {
    my($self, $dir) = @_;

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

sub pad {
    my($str) = @_;

    # requires $str to be a string of length 1 or 2, left-pad with a zero if length == 1

    return (length($str) == 2)? $str : '0' . $str;
}

sub format_number {
    my($self, $x) = @_;

    if ( defined $x )
    {
	$x =~ s/\.0*$//;
	
	if ( $x =~ /^\d+$/ || $x == 0 )
	{
	    return $self->add_commas($x);
	}
	elsif ( $x >= 1 ) 
	{
	    return $self->add_commas(sprintf("%.2f", $x));
	} 
	else 
	{
	    return sprintf("%.2e", $x);
	}
    }
}

sub add_commas {
    my($self, $n) = @_;
    # from perl cookbook

    if ( defined $n )
    {
	my $text = reverse $n;
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $text;
    }
}

sub read_processed_log {
    my($self, $user_dir, $upload_dir) = @_;

    # read processed files log which are Dumper formatted
    my $file_log = "$user_dir/$upload_dir/processed_files";
    if(open(FL, "<$file_log")) {
      my @lines = <FL>;
      close(FL);
      my $filerec = eval join('', @lines);
      return $filerec;
    } else {
      $self->application->add_message('warning', "could not open file '$file_log': $!");
    }
    return undef;
}

sub backup_processed_log {
    my($self, $user_dir, $upload_dir) = @_;

    my $time         = time;
    my $file_log     = "$user_dir/$upload_dir/processed_files";
    my $file_log_bak = "$user_dir/$upload_dir/processed_files.$time";

    copy($file_log, $file_log_bak);
    chmod 0666, $file_log_bak;
}

sub write_processed_log {
    my($self, $user_dir, $upload_dir, $filerec) = @_;

    my $file_log = "$user_dir/$upload_dir/processed_files";

    if (open(FL, ">$file_log")) {
	print FL Dumper($filerec);
	close(FL);
	chmod 0666, $file_log;
    } else {
	$self->application->add_message('warning',  "could not open file '$file_log': $!");
    }
}

sub mark_file_as_done {
    my($self) = @_;

    my $application = $self->application;
    my $cgi  = $application->cgi;
    my $user = $application->session->user;

    my $user_md5    = $self->user_md5($user);
    my $base_dir    = $FIG_Config::incoming;
    my $user_dir    = "$base_dir/$user_md5";
    my $status_file = "$base_dir/logs/upload.status";

    my $upload_dir  = $cgi->param('dir');
    my $fasta_file  = $cgi->param('file');

   my $upload_dirs = {};
    my @metagenomes = $cgi->param('metagenome');
    if (scalar(@metagenomes)) {
      foreach my $mg (@metagenomes) {
	my ($ud, $uf) = split /\//, $mg;
	unless (exists($upload_dirs->{$ud})) {
	  $upload_dirs->{$ud} = [];
	}
	push(@{$upload_dirs->{$ud}}, $uf);
      }
    } else {
      $upload_dirs->{$upload_dir} = [ $fasta_file ];
    }

    foreach my $ud (keys(%$upload_dirs)) {
      $upload_dir = $ud;
      
      my $filerec = $self->read_processed_log($user_dir, $upload_dir); 

      foreach my $ff (@{$upload_dirs->{$ud}}) {
	$fasta_file = $ff;

	$self->mark_status($status_file, [$user_md5, $upload_dir, $fasta_file, 'job_created']);  
	
	# get file to be marked as having the job created
	foreach my $file ( keys %$filerec )
	  {
	    if ( $filerec->{$file}{file_name} eq $fasta_file )
	      {
		$filerec->{$file}{job_created} = 1;
	      }
	  }
      }

      $self->backup_processed_log($user_dir, $upload_dir);
      $self->write_processed_log($user_dir, $upload_dir, $filerec);
    }
}
 
sub add_metadata {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi  = $application->cgi;
  my $user = $application->session->user;

  unless ($cgi->param('metagenome')) {
    return "";
  }
  
  my $user_md5    = $self->user_md5($user);    
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  
  my $upload_dir = $cgi->param('dir');
  my $fasta_file = $cgi->param('file');
  
  my $upload_dirs = {};
  my @metagenomes = $cgi->param('metagenome');
  if (scalar(@metagenomes)) {
    foreach my $mg (@metagenomes) {
      my ($ud, $uf) = split /\//, $mg;
      unless (exists($upload_dirs->{$ud})) {
	$upload_dirs->{$ud} = [];
      }
      push(@{$upload_dirs->{$ud}}, $uf);
    }
  } else {
    $upload_dirs->{$upload_dir} = [ $fasta_file ];
  }
  
  foreach my $ud (keys(%$upload_dirs)) {
    $upload_dir = $ud;
    
    # should not get here unless processing for this upload is complete, do we need to test this from the status_file?
    (-d "$user_dir/$upload_dir") or die "directory not found";
    
    my $filerec = $self->read_processed_log($user_dir, $upload_dir);
    
    foreach my $ff (@{$upload_dirs->{$ud}}) {
      $fasta_file = $ff;
            
      # get file to be marked as having the upload deleted
      foreach my $file ( keys %$filerec ) {
	if ( $filerec->{$file}{file_name} eq $fasta_file ) {
	  unless (exists($filerec->{$file}{metadata})) {
	    $filerec->{$file}{metadata} = {};
	  }
	  if (defined($cgi->param('investigation_type')) && length($cgi->param('investigation_type'))) {
	    $filerec->{$file}{metadata}->{investigation_type} = $cgi->param('investigation_type');
	  }
	  if (defined($cgi->param('project_name')) && length($cgi->param('project_name'))) {
	    $filerec->{$file}{metadata}->{project_name} = $cgi->param('project_name');
	  }
	  if (defined($cgi->param('lat_lon_lat')) && length($cgi->param('lat_lon_lat'))) {
	    $filerec->{$file}{metadata}->{lat_lon_lat} = $cgi->param('lat_lon_lat');
	  }
	  if (defined($cgi->param('lat_lon_lon')) && length($cgi->param('lat_lon_lon'))) {
	    $filerec->{$file}{metadata}->{lat_lon_lon} = $cgi->param('lat_lon_lon');
	  }
	  if (defined($cgi->param('geo_loc_name')) && length($cgi->param('geo_loc_name'))) {
	    $filerec->{$file}{metadata}->{geo_loc_name} = $cgi->param('geo_loc_name');
	  }
	  if (defined($cgi->param('collection_date')) && length($cgi->param('collection_date'))) {
	    $filerec->{$file}{metadata}->{collection_date} = $cgi->param('collection_date');
	  }
	  if (defined($cgi->param('biome')) && length($cgi->param('biome'))) {
	    $filerec->{$file}{metadata}->{biome} = $cgi->param('biome');
	  }
	  if (defined($cgi->param('feature')) && length($cgi->param('feature'))) {
	    $filerec->{$file}{metadata}->{feature} = $cgi->param('feature');
	  }
	  if (defined($cgi->param('material')) && length($cgi->param('material'))) {
	    $filerec->{$file}{metadata}->{material} = $cgi->param('material');
	  }
	  if (defined($cgi->param('env_package')) && length($cgi->param('env_package'))) {
	    $filerec->{$file}{metadata}->{env_package} = $cgi->param('env_package');
	  }
	  if (defined($cgi->param('seq_meth')) && length($cgi->param('seq_meth'))) {
	    $filerec->{$file}{metadata}->{seq_meth} = $cgi->param('seq_meth');
	  }
	}
      }
    }
    
    $self->backup_processed_log($user_dir, $upload_dir);
    $self->write_processed_log($user_dir, $upload_dir, $filerec);
  }
}

sub demultiplex {
  my($self) = @_;
  
  my $application = $self->application;
  my $cgi  = $application->cgi;
  my $user = $application->session->user;
  
  my $user_md5    = $self->user_md5($user);    
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  
  my $upload_dir = $cgi->param('dir');
  my $fasta_file = $cgi->param('file');
  
  my @mid_tags = ();

  if ($cgi->param('barcode_file')) {
    my $upload_file = "$upload_dir/".$fasta_file.".MID_tags";
    open(NEW, ">$upload_file") or die "could not open file '$upload_file': $!";
    
    my($buf, $n);
    my $all = "";
    my $blfh = $cgi->upload('barcode_file');
    my $bfh = $blfh->handle;
    while ($n = $bfh->read($buf, 1024)) {
      print NEW $buf;
      $all .= $buf;
    }
    close(NEW) or die "could not close file '$upload_file': $!";
    @mid_tags = split(/\n/, $all);
  }

  if ($cgi->param('bc_length')) {
    push(@mid_tags, $cgi->param('bc_length'));
  } else {
    foreach my $tag ( split(/[,\s]+/, $cgi->param('mid_tags')) ) {
      if ( $tag =~ /^[acgtACGT]+$/ ) {
	push @mid_tags, $tag;
      } else {
	$application->add_message('warning', "Multiplexing identifier tag contains non-nucleotide characters '$tag'");
	return "";
      }
    }
  }

  if ( @mid_tags) {
    unless ($cgi->param('barcode_file')) {
      open(DEMX, ">$user_dir/$upload_dir/$fasta_file.MID_tags") or die "could not open file '$user_dir/$upload_dir/$fasta_file.MID_tags': $!";
      print DEMX join("\n", @mid_tags), "\n";
      close(DEMX);
    }
    
    $self->mark_status($status_file, [$user_md5, $upload_dir, $fasta_file, 'demultiplex']);
    
    # use directory names without path for $user_dir and $upload_dir
    &start_preprocess($user_md5, $upload_dir, $fasta_file, {'demultiplex' => 1});
  } else {
    $application->add_message('warning', "No multiplexing identifier tags found");
  }

  return;
}

sub delete_upload {
  my($self) = @_;
  
  my $application = $self->application;
  my $cgi  = $application->cgi;
  my $user = $application->session->user;
  
  my $user_md5    = $self->user_md5($user);    
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  
  my $upload_dir = $cgi->param('dir');
  my $fasta_file = $cgi->param('file');
  
  my $upload_dirs = {};
  my @metagenomes = $cgi->param('metagenome');
  if (scalar(@metagenomes)) {
    foreach my $mg (@metagenomes) {
      my ($ud, $uf) = split /\//, $mg;
      unless (exists($upload_dirs->{$ud})) {
	$upload_dirs->{$ud} = [];
      }
      push(@{$upload_dirs->{$ud}}, $uf);
    }
  } else {
    $upload_dirs->{$upload_dir} = [ $fasta_file ];
  }
  
  foreach my $ud (keys(%$upload_dirs)) {
    $upload_dir = $ud;
    
    # should not get here unless processing for this upload is complete, do we need to test this from the status_file?
    (-d "$user_dir/$upload_dir") or die "directory not found";
    
    my $filerec = $self->read_processed_log($user_dir, $upload_dir);
    
    foreach my $ff (@{$upload_dirs->{$ud}}) {
      $fasta_file = $ff;
      
      $self->mark_status($status_file, [$user_md5, $upload_dir, $fasta_file, 'deleted']);
      
      # get file to be marked as having the upload deleted
      foreach my $file ( keys %$filerec ) {
	if ( $filerec->{$file}{file_name} eq $fasta_file ) {
	  $filerec->{$file}{deleted} = 1;
	}
      }
    }
    
    $self->backup_processed_log($user_dir, $upload_dir);
    $self->write_processed_log($user_dir, $upload_dir, $filerec);
  }
}

sub merge {
  my($self) = @_;
  
  my $application = $self->application;
  my $cgi  = $application->cgi;
  my $user = $application->session->user;
  
  my $user_md5    = $self->user_md5($user);    
  my $base_dir    = "$FIG_Config::incoming";
  my $user_dir    = "$base_dir/$user_md5";
  my $status_file = "$base_dir/logs/upload.status";
  
  my $upload_dir = $cgi->param('dir');
  my $fasta_file = $cgi->param('file');
  my $join_name = $cgi->param('join_name');
  
  my $upload_dirs = {};
  my @metagenomes = $cgi->param('metagenome');
  if (scalar(@metagenomes)) {
    foreach my $mg (@metagenomes) {
      my ($ud, $uf) = split /\//, $mg;
      unless (exists($upload_dirs->{$ud})) {
	$upload_dirs->{$ud} = [];
      }
      push(@{$upload_dirs->{$ud}}, $uf);
    }
  } else {
    $upload_dirs->{$upload_dir} = [ $fasta_file ];
  }

  unless ($join_name) {
    $application->add_message('warning', "Could not merge files, no merge-file name given.");
    return 0;
  }
  unless (scalar(keys(%$upload_dirs))) {
    $application->add_message('warning', "Could not merge files, no files selected.");
    return 0;
  }
  my @uds = keys(%$upload_dirs);
  my $new_upload_dir = $uds[0];
  
  my $target_file = "$user_dir/$new_upload_dir/$join_name";
  `touch $target_file`;
  if (-f "$target_file") {
    foreach my $ud (keys(%$upload_dirs)) {
      $upload_dir = $ud;
      
      (-d "$user_dir/$upload_dir") or die "directory not found";
      
      my $filerec = $self->read_processed_log($user_dir, $upload_dir);
      
      foreach my $ff (@{$upload_dirs->{$ud}}) {
	$fasta_file = $ff;
	my $catfile = $filerec->{$ff}->{file_path}."$ff";
	`cat $catfile>> $target_file`;
	
	$self->mark_status($status_file, [$user_md5, $upload_dir, $fasta_file, 'deleted']);
	
	# get file to be marked as having the upload deleted
	foreach my $file ( keys %$filerec )
	  {
	    if ( $filerec->{$file}{file_name} eq $fasta_file )
	      {
		$filerec->{$file}{deleted} = 1;
	      }
	  }
      }
      
      $self->backup_processed_log($user_dir, $upload_dir);
      $self->write_processed_log($user_dir, $upload_dir, $filerec);
    }
    my $filerec = $self->read_processed_log($user_dir, $new_upload_dir);
    my($file_base, $file_path, $file_suffix) = fileparse($target_file, qr/\.[^.]*$/);
    my($file_md5)     = (`md5sum '$target_file'` =~ /^(\S+)/);
    my $file_size     = -s $target_file;
    my $first_join    = $upload_dirs->{$new_upload_dir}->[0];
    $filerec->{$join_name} = { 'file_upload'   => $filerec->{$first_join}->{file_upload},
			       'file_name'     => $join_name,
			       'file_base'     => $file_base,
			       'file_path'     => $file_path,
			       'file_suffix'   => $file_suffix,
			       'file_type'     => $filerec->{$first_join}->{file_type},
			       'file_eol'      => $filerec->{$first_join}->{file_eol},
			       'file_format'   => $filerec->{$first_join}->{file_format},
			       'file_md5'      => $file_md5,
			       'file_size'     => $file_size };
    $filerec->{$join_name}{file_report} = &fasta_report_and_stats($join_name, $file_path, $filerec);
    $self->mark_status($status_file, [$user_md5, $upload_dir, $join_name, 'processing_completed']);
    $self->backup_processed_log($user_dir, $upload_dir);
    $self->write_processed_log($user_dir, $upload_dir, $filerec);
  } else {
    $application->add_message('warning', "Could not merge files. Target file could not be opened: $@");
    return 0;
  }
}

=item * B<finish_submission> ()

Finalizes the upload by creating the job directories

=cut

sub finish_submission {
    my($self) = @_;

# get upload_dir & fasta file
# get upload options -- dereplicate, etc.
# create files from options
# create job directory

    my $application = $self->application;
    my $cgi         = $application->cgi;
    my $user        = $application->session->user;

    my $user_md5    = $self->user_md5($user);
    my $base_dir    = "$FIG_Config::incoming";
    my $user_dir    = "$base_dir/$user_md5";
    my $status_file = "$base_dir/logs/upload.status";
    my $upload_dir  = $cgi->param('dir') || "";
    my $fasta_file  = $cgi->param('file') || "";

    my $jobmaster  = $application->data_handle('MGRAST');

    my $content = '';

    my $upload_dirs = {};
    my @metagenomes = $cgi->param('metagenome');
    if (scalar(@metagenomes)) {
      foreach my $mg (@metagenomes) {
	my ($ud, $uf) = split /\//, $mg;
	unless (exists($upload_dirs->{$ud})) {
	  $upload_dirs->{$ud} = [];
	}
	push(@{$upload_dirs->{$ud}}, $uf);
      }
    } else {
      $upload_dirs->{$upload_dir} = [ $fasta_file ];
    }

    foreach my $ud (keys(%$upload_dirs)) {
      $upload_dir = $ud;

      my $filerec = $self->read_processed_log($user_dir, $upload_dir);

      foreach my $ff (@{$upload_dirs->{$ud}}) {
	$fasta_file = $ff;
	
	# get file to be multiplexed with complete path -- this should be changed so that path is not part of key
	my @files = grep { $filerec->{$_}{file_name} eq $fasta_file } keys %$filerec;
	my $file  = $files[0];  #contains path
	
	my $length_filter = $self->get_boolean($cgi->param('length_filter'), 1);
	my $min_length    = $self->get_boolean($filerec->{$file}{file_report}{length_min}, 0);
	my $max_length    = $self->get_boolean($filerec->{$file}{file_report}{length_max}, 0);
	
	if ( $length_filter ) {
	  my $length_filter_stddev = defined($cgi->param('length_filter_stddev')) ? $cgi->param('length_filter_stddev') : 2;
	  $min_length = int( $filerec->{$file}{file_report}{average_length} - ($length_filter_stddev * $filerec->{$file}{file_report}{standard_deviation_length}) );
	  $max_length = int( $filerec->{$file}{file_report}{average_length} + ($length_filter_stddev * $filerec->{$file}{file_report}{standard_deviation_length}) );
	  if ($min_length < 0) { $min_length = 0; }
	}
	
	my $ff_name = "";
	if ($fasta_file =~ /\./) {
	  ($ff_name) = $fasta_file =~ /^(.*)\..*$/;
	} else {
	  $ff_name = $fasta_file;
	}
	my $mgname = $cgi->param('metagenome_name') || ($cgi->param('metagenome_name_prefix') || "").$ff_name;
	my $job = { name          => $cgi->param('metagenome_name') || $mgname,
		    file          => $fasta_file || '',
		    file_path     => $filerec->{$file}{file_path} || '',
		    file_size     => $filerec->{$file}{file_size} || 0,
		    file_checksum => $filerec->{$file}{file_md5}  || '',
		    fastq_file    => $filerec->{$file}{fastq_file} || '',
		    data => {
			     file_type      => $filerec->{$file}{fastq_file} ? "fq" : "fna",
			     rna_only       => $self->get_boolean($cgi->param('rna_only'), 0),
			     demultiplex    => $self->get_boolean($cgi->param('demultiplex'), 0),
			     dereplicate    => $self->get_boolean($cgi->param('dereplicate'), 1),
			     bowtie         => $self->get_boolean($cgi->param('bowtie'), 0),
			     screen_indexes => $cgi->param('bowtie_org') || '',
			     dynamic_trim   => $self->get_boolean($cgi->param('dynamic_trim'), 0),
			     min_qual       => $cgi->param('minimum_quality_score') || 0,
			     max_lqb        => $cgi->param('maximum_low_quality_bases') || 0,
			     filter_ambig   => $self->get_boolean($cgi->param('ambig_filter'), 1),
			     max_ambig      => defined($cgi->param('ambig_max_count')) ? $cgi->param('ambig_max_count') : 5,
			     filter_ln      => $length_filter,
			     min_ln         => $min_length,
			     max_ln         => $max_length
			    },
		    stats => {
			      bp_count             => $filerec->{$file}{file_report}{bp_count} || 0,
			      sequence_count       => $filerec->{$file}{file_report}{sequence_count} || 0,
			      ambig_char_count     => $filerec->{$file}{file_report}{ambig_char_count} || 0,
			      ambig_sequence_count => $filerec->{$file}{file_report}{ambig_sequence_count} || 0,
			      average_ambig_chars  => $filerec->{$file}{file_report}{average_ambig_chars} || 0,
			      average_length       => $filerec->{$file}{file_report}{average_length} || 0,
			      standard_deviation_length     => $filerec->{$file}{file_report}{standard_deviation_length} || 0,
			      average_gc_content            => $filerec->{$file}{file_report}{average_gc_content} || 0,
			      standard_deviation_gc_content => $filerec->{$file}{file_report}{standard_deviation_gc_content} || 0,
			      average_gc_ratio              => $filerec->{$file}{file_report}{average_gc_ratio} || 0,
			      standard_deviation_gc_ratio   => $filerec->{$file}{file_report}{standard_deviation_gc_ratio} || 0
			     }
		  };
	
	my $job_object = $jobmaster->Job->reserve_job($user);
	
	$job_object->stage_info("upload", "completed");
	$job_object->name( $job->{name} );
	$job_object->file( $job->{file} );
	$job_object->file_size_raw( $job->{file_size} );
	
	foreach my $s (keys %{$job->{stats}}) {
	  $job_object->stats($s.'_raw', $job->{stats}{$s});
	}
	foreach my $d (keys %{$job->{data}}) {
	  $job_object->data($d, $job->{data}{$d});
	}
	
	$job_object->server_version(3);
	$job_object->set_filter_options();
	
	$job->{options}       = $job_object->set_job_options();
	$job->{metagenome_id} = $job_object->{metagenome_id};
	$job->{job_id}        = $job_object->{job_id};

	my $project_message = '';
	if ($cgi->param('exitsting_project') || $cgi->param('add_to_project')) {
	  my $project = ($cgi->param('exitsting_project') && $cgi->param('exitsting_project') ne '0') ? $jobmaster->Project->get_objects( { name => $cgi->param('exitsting_project') } ) : $jobmaster->Project->get_objects( { name => $cgi->param('add_to_project') } );
	  my $dbm = $application->dbmaster;
	  if (scalar(@$project)) {
	    my $pright = $dbm->Rights->get_objects( { name => 'edit', data_type => 'project', data_id => $project->[0]->{_id}, granted => 1, scope => $user->get_user_scope } );
	    if (scalar(@$pright)) {
	      $jobmaster->ProjectJob->create( { project => $project, job => $job_object } );
	      $project_message = "The job was added to your existing project ".$cgi->param('add_to_project');
	    } else {
	      $project_message = "Could not add the job to project ".$cgi->param('add_to_project').", because you do not have edit rights for this project.";
	    }
	  } else {
	    my $pdir = $FIG_Config::mgrast_projects;
	    my $id = $jobmaster->Project->last_id + 1;
	    while (-d "$pdir/$id") {
	      $id++;
	    }
	    unless ($pdir && $id) {
	      $project_message = "Could not open project directory";
	    } else {
	      mkdir("$pdir/$id");
	      mkdir("$pdir/$id/graphics");
	      mkdir("$pdir/$id/tables");
	      $project = $jobmaster->Project->create( { name => $cgi->param('add_to_project'),
							public => 0,
							type => 'project',
							id => $id } );
	      $dbm->Rights->create( { application => undef,
				      scope => $user->get_user_scope,
				      name => 'view',
				      data_type => 'project',
				      data_id => $project->{_id},
				      granted => 1 } );
	      $dbm->Rights->create( { application => undef,
				      scope => $user->get_user_scope,
				      name => 'edit',
				      data_type => 'project',
				      data_id => $project->{_id},
				      granted => 1 } );
	      
	      $jobmaster->ProjectJob->create( { project => $project, job => $job_object } );
	      $project_message = "The project ".$cgi->param('add_to_project')." was created and the job was added to it.";
	    }
	  }
	}
	
	my $job_id = $self->create_new_job($job);
	
	$self->write_info_file($job, $filerec);
	$self->write_job_file($job);
    
	if ( $job_id )
	  {
	    my $metagenome_id = $job->{metagenome_id};
	    my $create_job    = $cgi->param('create_job') || '';

	    if ($create_job eq "submit and enter metadata") 
	      {
		$self->application->add_message('info', "Your upload will be processed as job number $job_id");
		$self->application->redirect({ page => 'MetaDataMG', parameters => freeze({ from_upload => '1', metagenome => $metagenome_id}) });
		$self->application->do_redirect();
	      }
	    else 
	      {
		my $link = qq(<a href="metagenomics.cgi?page=MetagenomeSelect&show_job_details=1" target=_blank>$job_id</a>);
		$content .= "The upload $fasta_file will be processed as metagenome '$mgname' referenced as job number $link<br>";
	      }
	  }
	else 
	  {
	    $content .= "The creation of your job $fasta_file as metagenome '$mgname' failed. Please try again and if this error persists contact <a href='mailto:mgrast\@mg-rast.mcs.anl.gov'>support</a>.";
	  }
      }
    }

    return $content;
}

sub write_job_file {
    my($self, $job) = @_;

    my $application = $self->application;
    my $cgi         = $application->cgi;
    my $user        = $application->session->user;

    my $base_dir    = $FIG_Config::incoming;
    my $user_md5    = $self->user_md5($user);
    my $user_dir    = "$base_dir/$user_md5";
    my $upload_dir  = $cgi->param('dir') || "";
    my $fasta_file  = $cgi->param('file') || "";

    my $job_file    = "$user_dir/$upload_dir/$fasta_file.job";
    
    open(JOB, ">$job_file") or die "could not open file '$job_file': $!";
    print JOB Dumper($job);
    close(JOB) or die "could not close file '$job_file': $!";
}

sub check_job_id {
    my($self) = @_;

    # when a job is created a job file is created for the fasta file
    my $application = $self->application;
    my $cgi         = $application->cgi;
    my $user        = $application->session->user;

    my $base_dir    = $FIG_Config::incoming;
    my $user_md5    = $self->user_md5($user);
    my $user_dir    = "$base_dir/$user_md5";

    my $upload_dir  = $cgi->param('dir')  || "";
    my $fasta_file  = $cgi->param('file') || "";
    my $job_file    = "$user_dir/$upload_dir/$fasta_file.job";

    if ( -e $job_file )
    {
	# read job file which is Dumper formatted
	if ( open(JOB, "<$job_file") ) 
	{
	    my @lines = <JOB>;
	    close(JOB);
	    my $job = eval join('', @lines);
	    return $job->{job_id};
	} 
	else 
	{
	    $self->application->add_message('warning', "could not open file");
	}
    }
    else
    {
	return 0;
    }
}

sub write_info_file {
    my($self, $job, $filerec) = @_;
    
    my $application = $self->application;
    my $cgi         = $application->cgi;
    my $upload_dir  = $cgi->param('dir') || "";
    my $upload_date = $self->timestamp_to_date($upload_dir);

    my $job_dir = $FIG_Config::mgrast_jobs . '/' . $job->{job_id};
    my $info_file = "$job_dir/raw/050.upload.info";
    
    open(INFO, ">$info_file") or die "could not open file '$info_file': $!";

    print INFO "# MG-RAST - preprocess v3.0.0 - ()\n";
    print INFO "# site : metagenomics.anl.gov\n";
    print INFO "# email: mg-rast\@mcs.anl.gov\n";

    print INFO "The job was uploaded on $upload_date with a file $job->{file} of $job->{file_size} bytes and having md5 checksum $job->{file_checksum}.\n";
    print INFO "The file contains $job->{stats}{bp_count} base-pairs with $job->{stats}{sequence_count} reads, with an average length of $job->{stats}{average_length}.\n";

    if ( $job->{stats}{standard_deviation_length} == 0 ) {
	print INFO "All reads were the same length.\n";
    } else {
	print INFO "The read length distribution had a standard deviation of $job->{stats}{standard_deviation_length} bp.\n";
    }

    if ( $job->{stats}{average_ambig_chars} == 0 ) {
	print INFO "No ambiguous characters (non-ACGT) were found.\n";
    } else {
	print INFO "The reads have an average of $job->{stats}{average_ambig_chars} ambiguous characters (non-ACGT).\n";
    }
    
    print INFO "The average gc content of all the reads is $job->{stats}{average_gc_content}.\n";

    print INFO "\n";

    print INFO "At the time the job was created, options were selected which are used to select which processing steps get run and with which parameters.\n";
    if ( $job->{data}{rna_only} ) {
	print INFO "The uploaded data was labelled as containing RNA only, so some of the processing steps like gene calling will be skipped.\n";
    }

    if ( $job->{data}{dereplicate} ) {
	print INFO "The reads will be dereplicated to remove redundant 'technical replicate' sequences which are identified by binning reads with identical first 50 base-pair sequences. One copy of each 50-base-pair identical bin is retailed.\n";
    }

    if ( $job->{data}{dynamic_trim} ) {
	print INFO "The reads will be dynamically filtered based on Phred quality scores, allowing at most $job->{data}{maximum_low_quality_bases} low quality bases per read, where a quality score of $job->{data}{minimum_quality_score} was selected as the cutoff to define the low quality bases.\n";
    } else {
	if ( $job->{data}{filter_ln} ) {
	    print INFO "The reads will be filtered by length, keeping only the reads between $job->{data}{min_ln} and $job->{data}{max_ln}.\n";
	}

	if ( $job->{data}{filter_ambig} ) {
	    print INFO "The reads will be filtered based on the presence of ambiguity characters (non-ACGT), keeping only the reads with less than $job->{data}{max_ambig} ambiguity characters.\n";
	}
    }

    if ( $job->{data}{bowtie} ) {
	print INFO "The reads will be screened against the model organism $job->{data}{bowtie_org} using bowtie.\n";
    }
    close(INFO) or die "could not close file '$info_file': $!";
}

# create new job directory on disk
sub create_new_job {
  my ($self, $job) = @_;

  my $user     = $self->application->session->user;  
  my $user_md5 = $self->user_md5($user);
  
  my $cmd = $FIG_Config::create_job;
  my $jid = $job->{job_id};
  my $seq_file = $job->{fastq_file}     ? $job->{file_path} . $job->{fastq_file} : $job->{file_path} . $job->{file};
  my $is_fastq = $job->{fastq_file}     ? '--fastq' : '';
  my $rna_only = $job->{data}{rna_only} ? '--rna_only' : '';
  my $options  = $job->{options} ? "-o \"" . $job->{options} . "\"" : "";

  my $output = `$cmd -j $jid -f $seq_file $options $is_fastq $rna_only`;
#  print STDERR $output;

  return $job->{job_id};
}

sub create_new_job_local {
    my ($self, $job) = @_;
    
    my $jobs_dir = $FIG_Config::mgrast_jobs;
    my $job_dir  = $jobs_dir . '/' . $job->{job_id};
    
    unless (-d $job_dir) {
	return (undef, "The job directory '$job_dir' could not be created.");
    }

    mkdir "$job_dir/raw" or die "could not open raw directory '$job_dir/raw'";

    # save uploaded file to raw directory
    # copy quality file if found

    open(FH, ">". "$job_dir/job_record") or die "could not open job_record file in $job_dir: $!";

    foreach my $key (sort  keys %$job )
    {
	print FH "$key\t$job->{$key}\n";
    }
    close(FH);
    
    chmod 0777, $job_dir;
    chmod 0777, "$job_dir/raw";
    chmod 0666, "$job_dir/job_record";
    
    return $job->{job_id};
}

# =pod

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

sub require_javascript {
  return [ "$FIG_Config::cgi_url/Html/CreateJob.js","$FIG_Config::cgi_url/Html/datepickercontrol.js" ];
}

sub require_css {
  return [ "$FIG_Config::cgi_url/Html/datepickercontrol.css" ];
}

sub random_string {
    my($self, $length) = @_;

    # return a random string of defined length, default 10 characters
    $length ||= 10;

    return join('', map { (0..9, 'a'..'z', 'A'..'Z')[rand 62] } (1..$length));
}

sub get_boolean {
  my ($self, $val, $default) = @_;

  if ( ! defined($val) ) {
    $val = $default;
  }
  return $val ? 1 : 0;
}

sub mini_faq {
    my($self) = @_;

#     my @help = (
# 		[qq~<span style='cursor: pointer;'>&raquo; Sequence data</span>~,
# 		 qq~What type of sequence data can I upload?~,
# 		 qq~MG-RAST will accept DNA sequences and will not accept amino acid sequences. The sequences should not contain alignment information ('.' and '-' characters).~],

# 		[qq~<span style='cursor: pointer;'>&raquo; File names</span>~,
# 		 qq~Are there any restrictions on uploaded file names?~,
# 		 qq~The upload process will only accept filenames made up of alphanumeric and .-_ characters, any name that satisfies this criterion is OK.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; File formats</span>~,
# 		 qq~How does my sequence data need to be formatted?~,
# 		 qq~There are three formats accepted, fasta, fastq and sff. Both fasta and fastq need to be in plain text ASCII. Quality information can be included with a fasta file by naming it with the same prefix with the extension '.qual' and creating a zip or tar archive.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; File compression</span>~,
# 		 qq~Should I compress my sequence data?~,
# 		 qq~Yes, for files larger files than 50M. You can use zip or gzip, but not rar.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Number of files</span>~,
# 		 qq~Can I upload more than one file?~,
# 		 qq~Yes. The uploader will only accept a single file but this can be a zip or tar archive which packages multiple files. A MG-RAST job will be created for each sequence file.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Demultiplexing</span>~,
# 		 qq~How is the demultiplexing done?~,
# 		 qq~You will need to provide us with the multiplex identifier (MID) tags for your data. Sequences from your file will be split into different data sets based on the presence of the MID tags at the beginning of the sequence. Each set of sequences will be processed as a single job.~],

# #		[qq~&raquo; Processing time~,
# #		 qq~How much time will MG-RAST take to analyze my sequence data?~,
# #		 qq~To be determined ...~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Processing steps</span>~,
# 		 qq~What are the processing steps in the analysis of my job?~,
# 		 qq~Depending on the options you select:<br>Upload<br>Sequence filtering<br>Dereplication<br>Sequence screening<br>Gene calling<br>Gene Clustering<br>Calculating similarities<br>and loading the database.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Sequence filtering</span>~,
# 		 qq~What are the sequence quality filtering options?~,
# 		 qq~Sequences from SFF and fastq files can be filtered based on quality scores, sequences from FASTA files can be filtered by length and also by the presence of ambiguity characters (non-ACGT).~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Sequence screening</span>~,
# 		 qq~How is the sequence screening done?~,
# 		 qq~Sequences are screened against the selected model organism using bowtie.~],

# 		[qq~<span style='cursor: pointer;'>&raquo; Dereplication</span>~,
# 		 qq~How is the dereplication done?~,
# 		 qq~Dereplication is performed by clustering the sequences based on the 50bp prefix and keeping the longest.~],
# 		);

#     my $text = "<b>Mini FAQ:</b><p>\n";

#     for (my $i = 0; $i < @help; $i++)
#     {
# 	my($display_text, $question, $answer) = @{ $help[$i] };

# 	my $help_table = qq(
# <div style="background-color: #DDDDDD; padding: 5px; border: thin solid">
# <b>$question</b>
# <hr>
# $answer
# </div>
# );
	
# 	$text .= qq(
# <span id="help_$i" onmouseover='document.getElementById("help_on_$i").style.display="inline"; document.getElementById("help_off_$i").style.display="none";' onmouseout='document.getElementById("help_on_$i").style.display="none"; document.getElementById("help_off_$i").style.display="inline";'>$display_text</span><p>
# <div id="help_on_$i" style="display: none">$help_table</div>
# <div id="help_off_$i" style="display: inline"></div>
# 		    );
#     }

#     $text .= qq(<span><a href="http://blog.metagenomics.anl.gov/howto/quality-control" target=_blank>More Information</a></span>\n);

    my $text = "<table>";
    $text .= "<tr><td><h2>upload steps</h2></td></tr>";
    $text .= "<tr><td><img src='./Html/circ_one.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>select upload files</span></td></tr>";
    $text .= "<tr><td><img src='./Html/circ_two.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>de-multiplex</span></td></tr>";
    $text .= "<tr><td><img src='./Html/circ_three.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>sample mapping</span></td></tr>";
    $text .= "<tr><td><img src='./Html/circ_four.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>metadata</span></td></tr>";
    $text .= "<tr><td><img src='./Html/circ_five.png' style='width: 40px;'></td><td style='font-size: 15px; vertical-align: middle;'>review & finish</span></td></tr>";
    $text .= "</table>";

    return $text;
}

sub lock_file_message {
    my($lock_file) = @_;
    
    my $msg = '';

    if ( -s $lock_file )
    {
	# lock file contents displayed to user
	open(LOCK, "<$lock_file") or die "could not open lock file '$lock_file': $!";
	my @lines = <LOCK>;
	close(LOCK) or die "could not close lock file '$lock_file': $!";
	$msg = join('', @lines);
    }
    else
    {
	# default message
	$msg = "We have temporarily suspended uploads for maintenance purposes, please try again later";
    }

    return $msg;
}    

sub fasta_report_and_stats {
    my($file_name, $file_path, $filerec) = @_;

    if ( exists $filerec->{$file_name}{error} )
    {
	return {};
    }

    ### report keys:
    # bp_count, sequence_count, length_max, id_length_max, length_min, id_length_min, file_size,
    # average_length, standard_deviation_length, average_gc_content, standard_deviation_gc_content,
    # average_gc_ratio, standard_deviation_gc_ratio, ambig_char_count, ambig_sequence_count, average_ambig_chars

    my $f_eol = uri_escape( $filerec->{$file_name}{file_eol} );
    # my @stats = `seq_length_stats --fasta_file $file_path/$file_name --eol_code $f_eol --id_stats 2>&1`;
    # take out id checking for now, needs to be moved downstream of job creation
    my @stats = `seq_length_stats --fasta_file '$file_path/$file_name' --eol_code $f_eol 2>&1`;
    chomp @stats;
    
    if ( $stats[0] =~ /^ERROR/i ) {
      my @parts = split(/\t/, $stats[0]);
      if ( @parts == 3 ) {
	$filerec->{$file_name}{error} = $parts[1] . ": " . $parts[2];
	return {};
      }
      else {
	die join("\n", @stats) . "\n";
      }
    }

    my $report = {};
    foreach my $line (@stats) {
      my ($key, $val) = split(/\t/, $line);
      $report->{$key} = $val;
    }
    $report->{file_size} = -s "$file_path/$file_name";

    if ( $report->{sequence_count} == 0 ) {
      $filerec->{$file_name}{error} = "File contains no sequences.";
      return {};
    }
    return $report;
}

sub save_metadata_info {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  
  
  return "";
}
