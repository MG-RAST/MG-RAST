package MGRAST::WebPage::Analysis;

use base qw( WebPage );

use strict;
use warnings;

use Statistics::Descriptive;
use List::Util qw(first max min sum);
use Data::Dumper;
use GD;
use WebComponent::WebGD;

use MIME::Base64;

use Conf;
use MGRAST::Analysis;
use MGRAST::Metadata;
use Cache::Memcached;

use File::Temp qw/ tempfile tempdir /;
 
1;

=pod

=head1 NAME

Analysis - do various analyses

=head1 DESCRIPTION

applies a set of different analysis tools to selected data

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Analysis');
  $self->{icon} = "<img src='./Html/analysis.gif' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  $self->application->register_component('Table', "t1");
  $self->application->register_component('Table', "t2");
  $self->application->register_component('Table', 'wb_hits');
  $self->application->register_component('PhyloTree', 'tree1');
  $self->application->register_component('VerticalBarChart', 'v1');
  $self->application->register_component('VerticalBarChart', 'v2');
  $self->application->register_component('VerticalBarChart', 'v3');
  $self->application->register_component('VerticalBarChart', 'v4');
  $self->application->register_component('VerticalBarChart', 'v5');
  $self->application->register_component('VerticalBarChart', 'v6');
  $self->application->register_component('VerticalBarChart', 'v7');
  $self->application->register_component('VerticalBarChart', 'v8');
  $self->application->register_component('VerticalBarChart', 'v9');
  $self->application->register_component('ListSelect', 'ls');
  $self->application->register_component('ListSelect', 'ls2');
  $self->application->register_component('FilterSelect','fs1');
  $self->application->register_component('FilterSelect', 'fs2');
  $self->application->register_component('Hover', 'rplotHover');
  $self->application->register_component('Ajax', 'ajax');

  $self->application->register_action($self, 'workbench_blat_output', 'workbench_blat_output');
  $self->application->register_action($self, 'qiime_export_visual', 'qiime_export_visual');
  $self->application->register_action($self, 'phylogeny_visual', 'phylogeny_visual');
  $self->application->register_action($self, 'single_visual', 'single_visual');

  my $mgdb = MGRAST::Analysis->new( $self->app->data_handle('MGRAST')->db_handle );
  unless ($mgdb) {
    $self->app->add_message('warning', "Unable to retrieve the metagenome analysis database.");
    return 1;
  }
  my $id = $self->application->cgi->param('metagenome') || '';
  if ($id) {
    if ($id =~ /\d+\.\d+/) {
      $mgdb->set_jobs([$id]);
    } else {
      $self->application->add_message('warning', "Invalid metagenome id format: $id");
    }
  }
  $self->{mgdb} = $mgdb;

  $self->data('default_eval', '5');
  $self->data('default_ident', '60');
  $self->data('default_alen', '15');
  $self->data('max_ctg_num', 100);
  $self->data('min_ctg_len', 1000);
  $self->data('rplot_source', 'RefSeq');

  $self->application->register_action($self, 'download', 'download');
  $self->application->register_action($self, 'workbench_export', 'workbench_export');

  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  if ($self->{blat}) {
    return $self->{blat};
  }
  if ($self->application->cgi->param('metagenome')) {
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $self->application->cgi->param('metagenome') });
    unless (ref($job)) {
      $self->application->add_message('warning', "You do not have the right to access this metagenome");
      return "";
    }
  }

  # get the application reference
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $metagenome  = $application->cgi->param('metagenome') || '';
  my $tools = "<div class='tool_header' title='Select which MG-RAST output data type to view (either an organism or functional classification)'><img src='./Html/one_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Type</div>";
  $tools .= "<div class='category_tool'>Organism Abundance</div>";
  $tools .= "<div class='inactive_tool' style='padding-left:20px' onclick='choose_tool(\"single\");' name='tool_entry' id='single_tool' title='Report taxonomic classification of single similarity hits'>Representative Hit Classification</div>";
  $tools .= "<div class='active_tool' style='padding-left:20px' onclick='choose_tool(\"phylogeny\");' name='tool_entry' id='phylogeny_tool' title='Report taxonomic classification of best similarity hits'>&raquo;Best Hit Classification</div>";
  $tools .= "<div class='inactive_tool' style='padding-left:20px' onclick='choose_tool(\"lca\");' name='tool_entry' id='lca_tool' title='Report lowest common ancestor of the best similarity hits'>Lowest Common Ancestor</div>";
  $tools .= "<div class='category_tool'>Functional Abundance</div>";
  $tools .= "<div class='inactive_tool' style='padding-left:20px' onclick='choose_tool(\"metabolism\");' name='tool_entry' id='metabolism_tool' title='Report abundances using protein databases that support hierarchical
relationships between functions (COG, NOG, SEED, subsystems, KEGG)
'>Hierarchical Classification</div>";
  $tools .= "<div class='inactive_tool' style='padding-left:20px' onclick='choose_tool(\"annotation\");' name='tool_entry' id='annotation_tool' title='Report abundances using protein databases that include all functional labels'>All Annotations</div>";
  #$tools .= "<div class='category_tool'>Other</div>";
  #$tools .= "<div class='inactive_tool' style='padding-left:20px' onclick='choose_tool(\"recruitment_plot\");' name='tool_entry' id='recruitment_plot_tool' title='Recruits sequences to proteins in a reference genome'>Recruitment Plot</div>";

  my $html = "<input type='hidden' id='metagenome' value='$metagenome'>".$application->component('ajax')->output."<table class='analysis'><tr><td class='tool'><div id='tool' class='tool'>".$tools."<div id='progress_div'></div></div></td><td class='select'><div id='select' class='select'>".$self->phylogeny_select."</div></td><td class='buff'></td></tr><tr><td colspan=3 class='display'><div id='display' class='display'>";

  $html .= "<table class='tabs'><tr id='tabs_table'>";
  
  my $wb_title = 'Workbench (0 Features)';
  my $wb_buffer_info = "<p style='padding-left: 25px; width: 600px;'><b>There are currently no features in your workbench.</b></p><p style='padding-left: 25px; width: 600px;'>You can store a selection of features from any data view in this workbench. You can then use them to generate any other visualization, or you can download them in FASTA format.</p>";
  my $wb_data_buffer = "";
  my $wb_buffer_mgids = "";
  my $wb_inactive = 1;
  my $wb_buffer_srcs = "M5NR";
  my $started_inactive = 0;
  my $wb_backup_buffer = "";
  my $wb_buffer_activators = "";
  my $wb_fasta_style = "display: none;";
  my $wb_select_opts = "";
  my $protein_sources = $self->{mgdb}->sources_for_type('protein');
  if ($cgi->param('wbinit')) {
    $wb_inactive = 0;
    $started_inactive = 1;
    if ($cgi->param('wbinit') eq 'mgoverview') {
      my $mgdb  = $self->{'mgdb'};
      my $cat   = $cgi->param('cat');
      my $type  = $cgi->param('type') || 'tax';
      my $level = $cgi->param('level') || 'tax_phylum';
      my $md5s  = [];
      my $desc  = '';
      if ($type eq 'tax') {
	if ($level eq 'none') {
	  $desc = "organism";
	  $md5s = $mgdb->get_md5s_for_organism( [$cat] );
	} else {
	  $desc = "taxonomic level";
	  $md5s = $mgdb->get_md5s_for_tax_level( $level, [$cat] );
	}
      } else {
	if ($level eq 'none') {
	  $desc = "function";
	  $md5s = $mgdb->get_md5s_for_function( [$cat], $type );
	} else {
	  $desc = "funtional category";
	  $md5s = $mgdb->get_md5s_for_ontol_level( $type, $level, [$cat] );
	}
      }
      my $num_md5s = scalar(@$md5s);
      my $mgname = "";
      my $job = $self->application->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
      $wb_data_buffer = join(";", @$md5s);
      $wb_buffer_mgids = $metagenome;
      $wb_title = 'Workbench ('.$num_md5s.' Features)';
      $wb_buffer_info = "<p>The workbench contains $num_md5s unique features.<br><br>They represent the $desc $cat from metagenome $mgname</p>";
      my $numbaks = 0;
      $wb_backup_buffer = "<div id='bak_buf_".$numbaks."'>";
      $wb_backup_buffer .= "<span>".$wb_data_buffer."</span>";
      $wb_backup_buffer .= "<span>".$wb_buffer_mgids."</span>";
      $wb_backup_buffer .= "<span>".$wb_buffer_info."</span>";
      $wb_backup_buffer .= "<span>".$wb_title."</span>";
      $wb_backup_buffer .= "<span>".$wb_buffer_srcs."</span>";
      $wb_backup_buffer .= "</div>";
      $wb_fasta_style = "";
      map { $wb_select_opts .= "<option value='".$_->[0]."'>".$_->[0]."</option>" } sort {$a->[0] cmp $b->[0]} @$protein_sources;
      $wb_buffer_activators = "<input type='radio' name='backupselector' onclick='activate_backup(".$numbaks.");' checked=checked>&nbsp;".$num_md5s." features&nbsp;&nbsp;";
    }
  }

  my ($title, $tab) = $self->generate_tab($wb_title, "<a href='http://blog.metagenomics.anl.gov/howto/using-the-workbench' target=_blank style='float: right;'>[?] workbench help</a><strong>workbench buffers</strong><br><div id='buffer_activators'>$wb_buffer_activators</div><hr><input type='hidden' id='buffer_mgids' value='$wb_buffer_mgids'><input type='hidden' id='buffer_srcs' value='$wb_buffer_srcs'><div id='buffer_info'>".$wb_buffer_info."</div><div id='wb_fasta' style='$wb_fasta_style'><br><br><form id='wb_export_form' action='metagenomics.cgi' method='post'><input type='hidden' name='page' value='Analysis'><input type='hidden' name='action' value='workbench_export'></form><form id='wb_hits_form' action='metagenomics.cgi' method='post'></form><a style='cursor:pointer;' onclick='workbench_export();'>download metagenome dna FASTA annotated by</a><span style='padding-left:10px;'><select id='fasta_source'>$wb_select_opts</select></span><br><br><a style='cursor:pointer' onclick='workbench_hits_table();execute_ajax(\"workbench_hits_table\",\"hits_div\",\"wb_hits_form\");'>display annotated hits below</a></div><div style='display: none;' id='data_buffer'>".$wb_data_buffer."</div><div style='display: none;' id='buffer_space'></div><div style='display: none;' id='backup_buffer'>$wb_backup_buffer</div><br><div id='hits_div'></div>", 1, 1, $wb_inactive);

  my ($title2, $tab2) = $self->generate_tab('Getting Started', "<p style='padding-left: 25px; width: 600px;'>To create a visualization, first select an analysis view from the <b>Analysis Views</b> box. The default is 'Organism Classification'. Then choose the data and cutoffs you wish to use in the <b>Data Selection</b> box. Depending on the type of data, you might have a set of possible visualizations. Pick one of them and click the <b>generate</b> button.</p><p style='padding-left: 25px; width: 600px;'>You will see the generated visualizations created in separate tabs in this tab-view. In addition to the visualization, the created tabs will display the settings used to create them. Generating a new visualization will preserve the previous visualizations you created.</p><p style='padding-left: 25px; width: 600px;'>You can rename the tabs by double clicking the tab-header and entering a new title. You can remove a tab by clicking the 'x' symbol in the top right corner of the tab-header. You can switch between tabs by single clicking the tab-header.</p>", 0, 0, $started_inactive);
  
  $html .= $title.$title2;
  $html .= "<td class='spacer_disp'></td></tr></table>";
  $html .= $tab.$tab2;
  $html .= "</div></td></tr></table>";
  
  $html .= "<input type='hidden' id='grouping_storage' value=''>";

  return $html;
}

##################
# data selection
##################
sub single_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metagenome = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }

  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($mg) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $grp_sel = $self->group_select();
  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div>";
  $select .= "<form name='single_form' id='single_form' onkeypress='return event.keyCode!=13'>";
  $select .= "<input type='hidden' name='metagenome' value='".($self->application->cgi->param('metagenome')||"")."'><table id='non_wb_sel'>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;' title='Select metagenomes for comparison from the drop-down menu'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='sel_mg'><input type=radio name='mg_grp_sel' value='individual' checked=checked onclick='document.getElementById(\"mg_sel_div\").style.display=\"\";document.getElementById(\"grp_sel_div\").style.display=\"none\";'> compare individually <input type=radio name='mg_grp_sel' value='groups' onclick='document.getElementById(\"mg_sel_div\").style.display=\"none\";document.getElementById(\"grp_sel_div\").style.display=\"\";'> compare as groups <div id='mg_sel_div'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></div><div id='grp_sel_div' style='display: none;'><table><tr><td>".$grp_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$grp_sel->id."\", 1);'></td></tr></table></div></td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Select database for annotation sequence comparison from the drop-down menu'><a target=_blank href='metagenomics.cgi?page=Sources'>Annotation Sources</a></td><td id='src_sel_td'>M5NR</td><td>".$self->more_button('document.getElementById("single_sel_source").style.display="";')."</td><td style='display: none;' id='single_sel_source'>".$self->source_select('phylogeny', {'M5NR' => 1}, 1, 1)."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("single_sel_eval").style.display="";')."</td><td style='display: none;' id='single_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("single_sel_ident").style.display="";')."</td><td style='display: none;' id='single_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases.'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("single_sel_alen").style.display="";')."</td><td style='display: none;' id='single_sel_alen'>".$self->alength_select()."</td></tr></table>";
#  $select .= "<table><tr><td style='font-weight: bold; width: 200px;'>Workbench</td><td><input type='checkbox' name='use_buffer' value='' onchange='buffer_to_form(this);'> use features from workbench</td></tr></table>";
  $select .= "<br><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/vbar.png' title='A comparison tool used to visualize the approximate membership percentage within each domain included in each metagenomic sample. Can also be used to perform significance tests to identify domains that are \"significantly\" different among selected groups of samples.'></td><td style='padding-right: 15px;'><img src='./Html/tree.png' title='Produces a circular tree showing relatedness of the metagenomes chosen for comparison.'></td><td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about the known members within each metagenome.'></td>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/heatmap.jpg' title='A phylogenetic tree that organizes metagenomes based on similarity of their abundance profiles (functional or taxonomic).  Counts are represented by a red (low abundance) to green (high abundance) range. Dendrograms indicate the relation between samples (horizontal) and their respective selected content (vertical) - e.g. functional subsytems, or taxonomic species.  The analysis can use raw abundance counts, or those that have been normalized and scaled (see details) to lessen the impact of technical bias.'></td><td style='padding-right: 15px;'><img src='./Html/pca.png' title='Principal Component Analysis. A commonly used data reduction/ordination technique; metagenomic samples are clustered with respect to components of variation extracted from their normalized (see details) abundance profiles. Can be used to cluster samples based on their taxonomic or functional content.'></td>";
  #$select .= "<td style='padding-right: 15px;'><img src='./Html/rarefaction.jpg'></td>";
  $select .= "<td></td></tr>";
  $select .= "<tr><td><input type=radio name='vis_type' value='vbar'>&nbsp;barchart</td><td><input type=radio name='vis_type' value='tree'>&nbsp;tree</td><td><input type=radio name='vis_type' value='table' checked=checked>&nbsp;table</td>";
  $select .= "<td><input type=radio name='vis_type' value='heatmap'>&nbsp;heatmap</td><td><input type=radio name='vis_type' value='pca'>&nbsp;PCoA</td>";
  #$select .= "<td><input type=radio name='vis_type' value='rarefaction'>&nbsp;rarefaction</td>";
  $select .= "<td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length || document.getElementById(\"list_select_list_b_".$self->application->component('ls2')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");list_select_select_all(\"".$self->application->component('ls2')->id."\");document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"single_visual\",\"buffer_space\",\"single_form\",\"loading...\", null, load_tabs);show_progress();}else{alert(\"You did not select any metagenomes\");};'></td></tr></table></form>";

  return $select;
}

sub phylogeny_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metagenome = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }

  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($mg) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $grp_sel = $self->group_select();
  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div>";
  $select .= "<form name='phylo_form' id='phylo_form' onkeypress='return event.keyCode!=13'>";
  $select .= "<input type='hidden' name='metagenome' value='".($self->application->cgi->param('metagenome')||"")."'><table id='non_wb_sel'>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;' title='Select metagenomes for comparison from the drop-down menu'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='sel_mg'><input type=radio name='mg_grp_sel' value='individual' checked=checked onclick='document.getElementById(\"mg_sel_div\").style.display=\"\";document.getElementById(\"grp_sel_div\").style.display=\"none\";'> compare individually <input type=radio name='mg_grp_sel' value='groups' onclick='document.getElementById(\"mg_sel_div\").style.display=\"none\";document.getElementById(\"grp_sel_div\").style.display=\"\";'> compare as groups <div id='mg_sel_div'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></div><div id='grp_sel_div' style='display: none;'><table><tr><td>".$grp_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$grp_sel->id."\", 1);'></td></tr></table></div></td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Select database for annotation sequence comparison from the drop-down menu'><a target=_blank href='metagenomics.cgi?page=Sources'>Annotation Sources</a></td><td id='src_sel_td'>M5NR</td><td>".$self->more_button('document.getElementById("phylo_sel_source").style.display="";')."</td><td style='display: none;' id='phylo_sel_source'>".$self->source_select('phylogeny', {'M5NR' => 1}, 0, 1)."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("phylo_sel_eval").style.display="";')."</td><td style='display: none;' id='phylo_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("phylo_sel_ident").style.display="";')."</td><td style='display: none;' id='phylo_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases.'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("phylo_sel_alen").style.display="";')."</td><td style='display: none;' id='phylo_sel_alen'>".$self->alength_select()."</td></tr></table>";
  $select .= "<table><tr><td style='font-weight: bold; width: 200px;'>Workbench</td><td><input type='checkbox' name='use_buffer' value='' onchange='buffer_to_form(this);'> use features from workbench</td></tr></table>";
  $select .= "<br><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr><td style='padding-right: 15px;'><img src='./Html/vbar.png' title='A comparison tool used to visualize the approximate membership percentage within each domain included in each metagenomic sample. Can also be used to perform significance tests to identify domains that are \"significantly\" different among selected groups of samples.'></td><td style='padding-right: 15px;'><img src='./Html/tree.png' title='Produces a circular tree showing relatedness of the metagenomes chosen for comparison.'></td><td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about all known members within each metagenome.'></td><td style='padding-right: 15px;'><img src='./Html/heatmap.jpg' title='A phylogenetic tree that organizes metagenomes based on similarity of their abundance profiles (functional or taxonomic).  Counts are represented by a red (low abundance) to green (high abundance) range. Dendrograms indicate the relation between samples (horizontal) and their respective selected content (vertical) - e.g. functional subsytems, or taxonomic species.  The analysis can use raw abundance counts, or those that have been normalized and scaled (see details) to lessen the impact of technical bias.'></td><td style='padding-right: 15px;'><img src='./Html/pca.png' title='Principal Component Analysis. A commonly used data reduction/ordination technique; metagenomic samples are clustered with respect to components of variation extracted from their normalized (see details) abundance profiles. Can be used to cluster samples based on their taxonomic or functional content.'></td><td style='padding-right: 15px;'><img src='./Html/rarefaction.jpg'></td><td></td></tr><tr><td><input type=radio name='vis_type' value='vbar'>&nbsp;barchart</td><td><input type=radio name='vis_type' value='tree'>&nbsp;tree</td><td><input type=radio name='vis_type' value='table' checked=checked>&nbsp;table</td><td><input type=radio name='vis_type' value='heatmap'>&nbsp;heatmap</td><td><input type=radio name='vis_type' value='pca'>&nbsp;PCoA</td><td><input type=radio name='vis_type' value='rarefaction'>&nbsp;rarefaction</td><td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length || document.getElementById(\"list_select_list_b_".$self->application->component('ls2')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");list_select_select_all(\"".$self->application->component('ls2')->id."\");document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"phylogeny_visual\",\"buffer_space\",\"phylo_form\",\"loading...\", null, load_tabs);show_progress();}else{alert(\"You did not select any metagenomes\");};'></td></tr></table></form>";

  return $select;
}

sub metabolism_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metagenome = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }

  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($metagenome) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $grp_sel = $self->group_select();
  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div><form name='meta_form' id='meta_form' onkeypress='return event.keyCode!=13'>";
  $select .= "<input type='hidden' name='metagenome' value='".$self->application->cgi->param('metagenome')."'><table id='non_wb_sel'>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;' title='Select metagenomes for comparison from the drop-down menu'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='sel_mg'><input type=radio name='mg_grp_sel' value='individual' checked=checked onclick='document.getElementById(\"mg_sel_div\").style.display=\"\";document.getElementById(\"grp_sel_div\").style.display=\"none\";'> compare individually <input type=radio name='mg_grp_sel' value='groups' onclick='document.getElementById(\"mg_sel_div\").style.display=\"none\";document.getElementById(\"grp_sel_div\").style.display=\"\";'> compare as groups <div id='mg_sel_div'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></div><div id='grp_sel_div' style='display: none;'><table><tr><td>".$grp_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$grp_sel->id."\", 1);'></td></tr></table></div></td></tr>";
  $select .= "<tr><td style='font-weight: bold;'><a target=_blank href='metagenomics.cgi?page=Sources' title='Select database for annotation sequence comparison from the drop-down menu'>Annotation Sources</a></td><td id='src_sel_td'>Subsystems</td><td>".$self->more_button('document.getElementById("meta_sel_source").style.display="";')."</td><td style='display: none;' id='meta_sel_source'>".$self->source_select('metabolism', {'Subsystems' => 1}, 1)."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("meta_sel_eval").style.display="";')."</td><td style='display: none;' id='meta_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("meta_sel_ident").style.display="";')."</td><td style='display: none;' id='meta_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases.'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("phylo_sel_alen").style.display="";')."</td><td style='display: none;' id='phylo_sel_alen'>".$self->alength_select()."</td></tr></table>";
  $select .= "<table><tr><td style='font-weight: bold; width: 200px;'>Workbench</td><td><input type='checkbox' name='use_buffer' value='' onchange='buffer_to_form(this);'> use features from workbench</td></tr></table>";
  $select .= "<br><table style='border-collapse:collapse;'><tr><td><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr><td style='padding-right: 15px;'><img src='./Html/vbar.png' title='A comparison tool used to visualize the approximate membership percentage within each domain included in each metagenomic sample. Can also be used to perform significance tests to identify domains that are \"significantly\" different among selected groups of samples.'></td><td style='padding-right: 15px;'><img src='./Html/tree.png' title='Produces a circular tree showing relatedness of the metagenomes chosen for comparison.'></td><td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about all known members within each metagenome.'></td><td style='padding-right: 15px;'><img src='./Html/heatmap.jpg' title='A phylogenetic tree that organizes metagenomes based on similarity of their abundance profiles (functional or taxonomic). Counts are represented by a red (low abundance) to green (high abundance) range. Dendrograms indicate the relation between samples (horizontal) and their respective selected content (vertical) - e.g. functional subsytems, or taxonomic species. The analysis can use raw abundance counts, or those that have been normalized and scaled (see details) to lessen the impact of technical bias.'></td><td style='padding-right: 15px;'><img src='./Html/pca.png' title='Principal Component Analysis. A commonly used data reduction/ordination technique; metagenomic samples are clustered with respect to components of variation extracted from their normalized (see details) abundance profiles.  Can be used to cluster samples based on their taxonomic or functional content.'></td><td></td></tr><tr><td><input type=radio name='vis_type' value='vbar'>&nbsp;barchart</td><td><input type=radio name='vis_type' value='tree'>&nbsp;tree</td><td><input type=radio name='vis_type' value='table' checked=checked>&nbsp;table</td><td><input type=radio name='vis_type' value='heatmap'>&nbsp;heatmap</td><td><input type=radio name='vis_type' value='pca'>&nbsp;PCoA</td><td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length || document.getElementById(\"list_select_list_b_".$self->application->component('ls2')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");list_select_select_all(\"".$self->application->component('ls2')->id."\");document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"metabolism_visual\",\"buffer_space\",\"meta_form\",\"loading...\", null, load_tabs);show_progress();}else{alert(\"You did not select any metagenomes\");};'></td></tr></table></td><td><div class='select_header'>KEGG Mapper</div><img src='./Html/keggico.png' style='margin-bottom: 5px; margin-top: 2px; margin-left: 30px;'><br>&nbsp;&nbsp;&nbsp;<input type='button' value='open KEGG Mapper' onclick='window.open(\"?page=KeggMapper\");'></td></tr></table></form>";

  return $select;
}

sub annotation_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metagenome = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }

  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($metagenome) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $grp_sel = $self->group_select();
  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div><form name='ann_form' id='ann_form' onkeypress='return event.keyCode!=13'>";
  $select .= "<input type='hidden' name='metagenome' value='".$self->application->cgi->param('metagenome')."'><table id='non_wb_sel'>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;' title='Select metagenomes for comparison from the drop-down menu'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='sel_mg'><input type=radio name='mg_grp_sel' value='individual' checked=checked onclick='document.getElementById(\"mg_sel_div\").style.display=\"\";document.getElementById(\"grp_sel_div\").style.display=\"none\";'> compare individually <input type=radio name='mg_grp_sel' value='groups' onclick='document.getElementById(\"mg_sel_div\").style.display=\"none\";document.getElementById(\"grp_sel_div\").style.display=\"\";'> compare as groups <div id='mg_sel_div'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></div><div id='grp_sel_div' style='display: none;'><table><tr><td>".$grp_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$grp_sel->id."\", 1);'></td></tr></table></div></td></tr>";
  $select .= "<tr><td style='font-weight: bold;'><a target=_blank href='metagenomics.cgi?page=Sources' title='Select database for annotation sequence comparison from the drop-down menu'>Annotation Sources</a></td><td id='src_sel_td'>GenBank</td><td>".$self->more_button('document.getElementById("ann_sel_source").style.display="";')."</td><td style='display: none;' id='ann_sel_source'>".$self->source_select('annotation', {'GenBank' => 1})."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("ann_sel_eval").style.display="";')."</td><td style='display: none;' id='ann_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("ann_sel_ident").style.display="";')."</td><td style='display: none;' id='ann_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("phylo_sel_alen").style.display="";')."</td><td style='display: none;' id='phylo_sel_alen'>".$self->alength_select()."</td></tr></table>";
  $select .= "<table><tr><td style='font-weight: bold; width: 200px;'>Workbench</td><td><input type='checkbox' name='use_buffer' value='' onchange='buffer_to_form(this);'> use features from workbench</td></tr></table>";
  $select .= "<br><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about all known members within each metagenome.'></td>";
  $select .= "<td></td></tr><tr>";
  $select .= "<td><input type=radio name='vis_type' value='table' checked=checked>&nbsp;table</td>";
  $select .= "<td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length || document.getElementById(\"list_select_list_b_".$self->application->component('ls2')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");list_select_select_all(\"".$self->application->component('ls2')->id."\");document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"annotation_visual\",\"buffer_space\",\"ann_form\",\"loading...\", null, load_tabs);show_progress();}else{alert(\"You did not select any metagenomes\");};'></td></tr></table></form>";

  return $select;
}

sub lca_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  
  my $metagenome = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }
  
  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($metagenome) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $grp_sel = $self->group_select();
  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div>";
  $select .= "<form name='lca_form' id='lca_form' onkeypress='return event.keyCode!=13'>";
  $select .= "<input type='hidden' name='metagenome' value='".($self->application->cgi->param('metagenome')||"")."'><table id='non_wb_sel'>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;' title='Select metagenomes for comparison from the drop-down menu'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='sel_mg'><input type=radio name='mg_grp_sel' value='individual' checked=checked onclick='document.getElementById(\"mg_sel_div\").style.display=\"\";document.getElementById(\"grp_sel_div\").style.display=\"none\";'> compare individually <input type=radio name='mg_grp_sel' value='groups' onclick='document.getElementById(\"mg_sel_div\").style.display=\"none\";document.getElementById(\"grp_sel_div\").style.display=\"\";'> compare as groups <div id='mg_sel_div'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></div><div id='grp_sel_div' style='display: none;'><table><tr><td>".$grp_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$grp_sel->id."\", 1);'></td></tr></table></div></td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("lca_sel_eval").style.display="";')."</td><td style='display: none;' id='lca_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("lca_sel_ident").style.display="";')."</td><td style='display: none;' id='lca_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases.'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("lca_sel_alen").style.display="";')."</td><td style='display: none;' id='lca_sel_alen'>".$self->alength_select()."</td></tr></table>";
  $select .= "<br><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/vbar.png' title='A comparison tool used to visualize the approximate membership percentage within each domain included in each metagenomic sample. Can also be used to perform significance tests to identify domains that are \"significantly\" different among selected groups of samples.'></td>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/tree.png' title='Produces a circular tree showing relatedness of the metagenomes chosen for comparison.'></td>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about all known members within each metagenome.'></td>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/heatmap.jpg' title='A phylogenetic tree that organizes metagenomes based on similarity of their abundance profiles (functional or taxonomic).  Counts are represented by a red (low abundance) to green (high abundance) range. Dendrograms indicate the relation between samples (horizontal) and their respective selected content (vertical) - e.g. functional subsytems, or taxonomic species.  The analysis can use raw abundance counts, or those that have been normalized and scaled (see details) to lessen the impact of technical bias.'></td><td style='padding-right: 15px;'><img src='./Html/pca.png' title='Principal Component Analysis. A commonly used data reduction/ordination technique; metagenomic samples are clustered with respect to components of variation extracted from their normalized (see details) abundance profiles. Can be used to cluster samples based on their taxonomic or functional content.'></td>";
  $select .= "<td></td></tr><tr>";
  $select .= "<tr><td><input type=radio name='vis_type' value='vbar'>&nbsp;barchart</td>";
  $select .= "<td><input type=radio name='vis_type' value='tree'>&nbsp;tree</td>";
  $select .= "<td><input type=radio name='vis_type' value='table' checked=checked>&nbsp;table</td>";
  $select .= "<td><input type=radio name='vis_type' value='heatmap'>&nbsp;heatmap</td><td><input type=radio name='vis_type' value='pca'>&nbsp;PCoA</td>";
  $select .= "<td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length || document.getElementById(\"list_select_list_b_".$self->application->component('ls2')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");list_select_select_all(\"".$self->application->component('ls2')->id."\");document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"lca_visual\",\"buffer_space\",\"lca_form\",\"loading...\", null, load_tabs);show_progress();}else{alert(\"You did not select any metagenomes\");};'></td></tr></table></form>";

  return $select;
}


sub recruitment_plot_select {
  my ($self) = @_;

  my $metagenome = $self->application->cgi->param('metagenome') || '';
  my $source     = $self->data('rplot_source');

  my $mgname = '';
  if ($metagenome) {
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
    if (ref($job)) {
      $mgname = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome'>".$job->name()." ($metagenome)</a>";
    }
  }

  my ($refsel, $fg) = $self->ref_genome_select($metagenome, $source);
  unless (defined($fg)) { $fg = ""; }

  my $select = "<div class='select_header' title='select data set, database and parameters'><img src='./Html/two_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Selection</div><form name='rplot_form' id='rplot_form' onkeypress='return event.keyCode!=13'><table>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;'>Metagenome</td><td id='mg_sel_td'>$mgname</td><td>".$self->more_button('document.getElementById("meta_sel_mg").style.display="";')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='meta_sel_mg'>".$self->metagenome_switch($metagenome, "recruitment_plot")."</td></tr>";
  $select .= "<tr><td style='font-weight: bold; width: 200px;'>Reference Genome</td><td id='rg_sel_td'>$fg</td><td>".$self->more_button('document.getElementById("rplot_sel_rg").style.display="";')."</td></tr>";
  $select .= "<tr><td colspan=3 style='display: none;' id='rplot_sel_rg'>".$refsel."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-03</td><td>".$self->more_button('document.getElementById("rplot_sel_eval").style.display="";')."</td><td style='display: none;' id='rplot_sel_eval'>".$self->evalue_range_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;'>Abundance Scale</td><td> log2 </td><td>".$self->more_button('document.getElementById("rplot_sel_scale").style.display="";')."</td><td style='display: none;' id='rplot_sel_scale'>".$self->scale_select()."</td></tr></table>";
  $select .= "<br><div class='select_header' title='select a visualization or export format'><img src='./Html/three_white.png' style='width: 22px; margin-top: -2px; vertical-align: middle;'> Data Visualization</div><table><tr>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/circle.png' title='Produces a circular graph mapping metagenome to chosen organism.'></td>";
  $select .= "<td style='padding-right: 15px;'><img src='./Html/table.png' title='Creates a descriptive table with information about all known members within each metagenome.'></td>";
  $select .= "<td></td></tr><tr>";
  $select .= "<td><input type=radio name='vis_type' value='circle' checked=checked>&nbsp;circle map</td>";
  $select .= "<td><input type=radio name='vis_type' value='table'>&nbsp;table</td>";
  $select .= "<td><input type='hidden' name='tabnum' id='tabnum'><input type='button' value='generate' onclick='document.getElementById(\"tabnum\").value=curr_tab_num;execute_ajax(\"recruitment_plot_visual\",\"buffer_space\",\"rplot_form\",\"loading...\", null, load_tabs);show_progress();' /></td></tr></table></form>";

  return $select;
}

##################
# data retrieval
##################
sub single_data {
  my ($self) = @_;

  my $result = [];
  my $cgi        = $self->application->cgi;
  my $source     = $cgi->param('source');
  my @metas     = $cgi->param('comparison_metagenomes');
  my $evalue     = $cgi->param('evalue')   || undef;
  my $identity   = $cgi->param('identity') || undef;
  my $alength    = $cgi->param('alength')  || undef;
  my $mg_grp_sel = $cgi->param('mg_grp_sel') || '';
  my $mgrast     = $self->application->data_handle('MGRAST');
  
  my $collections = {};
  my @comparison_collections = $cgi->param('comparison_collections');
  if ($mg_grp_sel eq 'groups') {
    $cgi->param('comparison_metagenomes', @comparison_collections);
    my $collections_ary = [];
    my $projects = [];
    foreach my $entry (@comparison_collections) {
      if ($entry =~ /^project\:/) {
	push(@$projects, $entry);
      } else {
	push(@$collections_ary, $entry);
      }
    }
    if ($self->application->session->user) {
      my $comp_cols = {};
      %$comp_cols = map { $_ => 1 } @$collections_ary;
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if ($comp_cols->{$name}) {
	    $collections->{$val} = $name;
	    push(@metas, $val);
	  }
	}
      }
    }
    foreach my $project (@$projects) {
      my ($pid) = $project =~ /^project\:(\d+)$/;
      my $p = $mgrast->Project->init( { id => $pid } );
      my $pjs = $mgrast->ProjectJob->get_objects( { project => $p } );
      foreach my $pj (@$pjs) {
	push(@metas, $pj->job->job_id);
	$collections->{$pj->job->job_id} = $project;
      }
    }

    $self->{mgdb}->set_jobs(\@metas, 1);
    foreach my $key (keys(%$collections)) {
      $collections->{ $self->{mgdb}->_mg_map->{$key} } = $collections->{$key};
    }
  } else {
    $self->{mgdb}->set_jobs(\@metas);
  }

  $result = $self->{mgdb}->get_organisms_unique_for_source($source, $evalue, $identity, $alength);
  #  0        1           2         3           4            5         6            7        8        9         10      11          12         13        14       15      16
  # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
  if ($mg_grp_sel eq 'groups') {
    my $joined_data = {};
    foreach my $row (@$result) {
      $row->[0] = $collections->{$row->[0]};
      my $id_string = join("|", @$row[0..8]);
      if (exists($joined_data->{$id_string})) {
	$row->[10] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[10]) + ($row->[9] * $row->[10])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[11] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[11]) + ($row->[9] * $row->[11])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[12] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[12]) + ($row->[9] * $row->[12])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[13] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[13]) + ($row->[9] * $row->[13])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[14] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[14]) + ($row->[9] * $row->[14])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[15] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[15]) + ($row->[9] * $row->[15])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[16] = $joined_data->{$id_string}->[16].";".$row->[16];
	$row->[9] += $joined_data->{$id_string}->[9];
      }
      $joined_data->{$id_string} = $row;
    }
    @$result = map { $joined_data->{$_} } keys(%$joined_data);
  }
  
  return $result;
}

sub phylogenetic_data {
  my ($self) = @_;

  my $result = [];
  my $md5_abund = {};
  my $cgi      = $self->application->cgi;
  my @sources  = $cgi->param('source');
  my @metas    = $cgi->param('comparison_metagenomes');
  my $evalue   = $cgi->param('evalue')   || undef;
  my $identity = $cgi->param('identity') || undef;
  my $alength  = $cgi->param('alength')  || undef;
  my $mg_grp_sel = $cgi->param('mg_grp_sel') || '';
  my $mgrast = $self->application->data_handle('MGRAST');
  
  my $collections = {};
  my @comparison_collections = $cgi->param('comparison_collections');
  if ($mg_grp_sel eq 'groups') {
    $cgi->param('comparison_metagenomes', @comparison_collections);
    my $collections_ary = [];
    my $projects = [];
    foreach my $entry (@comparison_collections) {
      if ($entry =~ /^project\:/) {
	    push(@$projects, $entry);
      } else {
	    push(@$collections_ary, $entry);
      }
    }
    if ($self->application->session->user) {
      my $comp_cols = {};
      %$comp_cols = map { $_ => 1 } @$collections_ary;
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	    foreach my $collection_pref (@$coll_prefs) {
	      my ($name, $val) = split(/\|/, $collection_pref->{value});
	      if ($comp_cols->{$name}) {
	        $collections->{$val} = $name;
	        push(@metas, $val);
	      }
	    }
      }
    }
    foreach my $project (@$projects) {
      my ($pid) = $project =~ /^project\:(\d+)$/;
      my $p = $mgrast->Project->init( { id => $pid } );
      my $pjs = $mgrast->ProjectJob->get_objects( { project => $p } );
      foreach my $pj (@$pjs) {
	    push(@metas, $pj->job->job_id);
	    $collections->{$pj->job->job_id} = $project;
      }
    }

    $self->{mgdb}->set_jobs(\@metas, 1);
    foreach my $key (keys(%$collections)) {
      $collections->{ $self->{mgdb}->_mg_map->{$key} } = $collections->{$key};
    }
  } else {
    $self->{mgdb}->set_jobs(\@metas);
  }

  if ($cgi->param('vis_type') eq 'rarefaction') {
    my $mgid_alpha = {};
    my $mgid_curve = {};
    my $get_m5nr   = first {$_ =~ /^m5nr$/i} @sources;
    if ($get_m5nr) {
      while (my ($mgid, $jobid) = each %{$self->{mgdb}->_job_map}) {
	    my $jobj  = $mgrast->Job->init( {job_id => $jobid} );
	    my $alpha = $jobj->stats('alpha_diversity_shannon')->{'alpha_diversity_shannon'};
	    my $curve = $self->{mgdb}->get_rarefaction_coords($jobj->metagenome_id);
	    if ($alpha)  { $mgid_alpha->{$mgid} = $alpha; }
	    if (@$curve) { $mgid_curve->{$mgid} = $curve; }
      }
    } else {
      $mgid_alpha = $self->{mgdb}->get_rarefaction_curve(\@sources, 1);
      $mgid_curve = $self->{mgdb}->get_rarefaction_curve(\@sources);
    }
    @$result = map { [ $_, $mgid_curve->{$_}, $mgid_alpha->{$_} ] } keys %$mgid_curve;
    return (undef, $result);
  }

  if ($cgi->param('use_buffer')) {
    my @md5s = split(/;/, $cgi->param('use_buffer'));
    ($md5_abund, $result) = $self->{mgdb}->get_organisms_for_md5s(\@md5s, \@sources, $evalue, $identity, $alength);
  }
  else {
    ($md5_abund, $result) = $self->{mgdb}->get_organisms_for_sources(\@sources, $evalue, $identity, $alength);
  }

  # mgid => md5 => abundance
  # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  if ($mg_grp_sel eq 'groups') {
    my $joined_data = {};
    foreach my $row (@$result) {
      $row->[0] = $collections->{$row->[0]};
      my $id_string = join("|", @$row[0..9]);
      if (exists($joined_data->{$id_string})) {
	$row->[12] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[12]) + ($row->[10] * $row->[12])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[13] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[13]) + ($row->[10] * $row->[13])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[14] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[14]) + ($row->[10] * $row->[14])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[15] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[15]) + ($row->[10] * $row->[15])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[16] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[16]) + ($row->[10] * $row->[16])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[17] = sprintf("%.2f", (($joined_data->{$id_string}->[10] * $joined_data->{$id_string}->[17]) + ($row->[10] * $row->[17])) / ($joined_data->{$id_string}->[10] + $row->[10]));
	$row->[18] = $joined_data->{$id_string}->[18].";".$row->[18];
	$row->[10] += $joined_data->{$id_string}->[10];
	$row->[11] += $joined_data->{$id_string}->[11];
      }
      $joined_data->{$id_string} = $row;
    }
    @$result = map { $joined_data->{$_} } keys(%$joined_data);

    # join the md5 abundances
    my $md5_abund_joined = {};
    foreach my $cc (@comparison_collections) {
      $md5_abund_joined->{$cc} = {};      
    }
    foreach my $mg (keys(%$md5_abund)) {
      foreach my $md5 (keys(%{$md5_abund->{$mg}})) {
	$md5_abund_joined->{$collections->{$mg}}->{$md5} ? $md5_abund_joined->{$collections->{$mg}}->{$md5} += $md5_abund->{$mg}->{$md5} : $md5_abund_joined->{$collections->{$mg}}->{$md5} = $md5_abund->{$mg}->{$md5};
      }
    }
    $md5_abund = $md5_abund_joined;
  }
  
  return ($md5_abund, $result);
}

sub metabolic_data {
  my ($self) = @_;

  my $result   = [];
  my $md5_abund = {};
  my $cgi      = $self->application->cgi;
  my $source   = $cgi->param('source');
  my @metas    = $cgi->param('comparison_metagenomes');
  my $evalue   = $cgi->param('evalue')   || undef;
  my $identity = $cgi->param('identity') || undef;
  my $alength  = $cgi->param('alength')  || undef;
  my $mg_grp_sel = $cgi->param('mg_grp_sel') || '';
  my $mgrast = $self->application->data_handle('MGRAST');
  
  my $collections = {};
  my @comparison_collections = $cgi->param('comparison_collections');
  if ($mg_grp_sel eq 'groups') {
    $cgi->param('comparison_metagenomes', @comparison_collections);
    my $collections_ary = [];
    my $projects = [];
    foreach my $entry (@comparison_collections) {
      if ($entry =~ /^project\:/) {
	push(@$projects, $entry);
      } else {
	push(@$collections_ary, $entry);
      }
    }
    if ($self->application->session->user) {
      my $comp_cols = {};
      %$comp_cols = map { $_ => 1 } @$collections_ary;
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if ($comp_cols->{$name}) {
	    $collections->{$val} = $name;
	    push(@metas, $val);
	  }
	}
      }
    }
    foreach my $project (@$projects) {
      my ($pid) = $project =~ /^project\:(\d+)$/;
      my $p = $mgrast->Project->init( { id => $pid } );
      my $pjs = $mgrast->ProjectJob->get_objects( { project => $p } );
      foreach my $pj (@$pjs) {
	push(@metas, $pj->job->job_id);
	$collections->{$pj->job->job_id} = $project;
      }
    }

    $self->{mgdb}->set_jobs(\@metas, 1);
    foreach my $key (keys(%$collections)) {
      $collections->{ $self->{mgdb}->_mg_map->{$key} } = $collections->{$key};
    }
  } else {
    $self->{mgdb}->set_jobs(\@metas);
  }
    
  if ($cgi->param('use_buffer')) {
    my @md5s = split(/;/, $cgi->param('use_buffer'));
    ($md5_abund, $result) = $self->{mgdb}->get_ontology_for_md5s(\@md5s, $source, $evalue, $identity, $alength);
  }
  else {
    ($md5_abund, $result) = $self->{mgdb}->get_ontology_for_source($source, $evalue, $identity, $alength);
  }
  # mgid => md5 => abundance
  # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
  
  my $link   = $self->{mgdb}->link_for_source($source);
  my $id_map = $self->{mgdb}->get_hierarchy('ontology', $source);
  my $all    = [];
  foreach my $row (@$result) {
    if ( exists $id_map->{$row->[1]} ) {
      my @levels;
      foreach (@{$id_map->{$row->[1]}}) { next unless $_; $_ =~ s/_/ /g; push @levels, $_; }
      my $depth = scalar @levels;
      my $lvl1  = shift @levels;
      my $lvl2  = shift @levels;
      if ((! $lvl2) || ($lvl2 eq 'Unknown')) {
	$lvl2 = $lvl1;
      }
      
      my $new = [ $row->[0], $lvl1, $lvl2 ];
      if ($depth > 3) {
	my $lvl3 = shift @levels;
	if ((! $lvl3) || ($lvl3 eq 'Unknown')) {
	  $lvl3 = $lvl2;
	}
	push @$new, $lvl3;
      }
      else {
	push @$new, "-";
      }
      push(@$new, $row->[2]);
      if ($link && ($source ne 'Subsystems')) {
	push(@$new, "<a target=_blank href='".$link.$row->[1]."'>".$row->[1]."</a>");
      }
      else {
	push(@$new, $row->[1]);
      }
      push @$new, @$row[3..11];
      push @$all, $new;
    }
  }

  # mgid, level1, level2, level3, annotation, id, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  if ($mg_grp_sel eq 'groups') {
    my $joined_data = {};
    foreach my $row (@$all) {
      $row->[0] = $collections->{$row->[0]};
      my $id_string = join("|", @$row[0..4]);
      if (exists($joined_data->{$id_string})) {
	$row->[8] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[8]) + ($row->[6] * $row->[8])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[9] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[9]) + ($row->[6] * $row->[9])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[10] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[10]) + ($row->[6] * $row->[10])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[11] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[11]) + ($row->[6] * $row->[11])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[12] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[12]) + ($row->[6] * $row->[12])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[13] = sprintf("%.2f", (($joined_data->{$id_string}->[6] * $joined_data->{$id_string}->[13]) + ($row->[6] * $row->[13])) / ($joined_data->{$id_string}->[6] + $row->[6]));
	$row->[14] = $joined_data->{$id_string}->[14].";".$row->[14];
	$row->[6] += $joined_data->{$id_string}->[6];
	$row->[7] += $joined_data->{$id_string}->[7];
      }
      $joined_data->{$id_string} = $row;
    }
    @$all = map { $joined_data->{$_} } keys(%$joined_data);

    # join the md5 abundances
    my $md5_abund_joined = {};
    foreach my $cc (@comparison_collections) {
      $md5_abund_joined->{$cc} = {};      
    }
    foreach my $mg (keys(%$md5_abund)) {
      foreach my $md5 (keys(%{$md5_abund->{$mg}})) {
	$md5_abund_joined->{$collections->{$mg}}->{$md5} ? $md5_abund_joined->{$collections->{$mg}}->{$md5} += $md5_abund->{$mg}->{$md5} : $md5_abund_joined->{$collections->{$mg}}->{$md5} = $md5_abund->{$mg}->{$md5};
      }
    }
    $md5_abund = $md5_abund_joined;
  }

  return ($md5_abund, $all);
}

sub annotation_data {
  my ($self) = @_;

  my $result  = [];
  my $cgi     = $self->application->cgi;
  my @sources = $cgi->param('source');
  my @metas   = $cgi->param('comparison_metagenomes');
  my $evalue   = $cgi->param('evalue')   || undef;
  my $identity = $cgi->param('identity') || undef;
  my $alength  = $cgi->param('alength')  || undef;
  my $mg_grp_sel = $cgi->param('mg_grp_sel') || '';
  my $mgrast = $self->application->data_handle('MGRAST');
  
  my $collections = {};
  if ($mg_grp_sel eq 'groups') {
    my @comparison_collections = $cgi->param('comparison_collections');
    $cgi->param('comparison_metagenomes', @comparison_collections);
    my $collections_ary = [];
    my $projects = [];
    foreach my $entry (@comparison_collections) {
      if ($entry =~ /^project\:/) {
	push(@$projects, $entry);
      } else {
	push(@$collections_ary, $entry);
      }
    }
    if ($self->application->session->user) {
      my $comp_cols = {};
      %$comp_cols = map { $_ => 1 } @$collections_ary;
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if ($comp_cols->{$name}) {
	    $collections->{$val} = $name;
	    push(@metas, $val);
	  }
	}
      }
    }
    foreach my $project (@$projects) {
      my ($pid) = $project =~ /^project\:(\d+)$/;
      my $p = $mgrast->Project->init( { id => $pid } );
      my $pjs = $mgrast->ProjectJob->get_objects( { project => $p } );
      foreach my $pj (@$pjs) {
	push(@metas, $pj->job->job_id);
	$collections->{$pj->job->job_id} = $project;
      }
    }

    $self->{mgdb}->set_jobs(\@metas, 1);
    foreach my $key (keys(%$collections)) {
      $collections->{ $self->{mgdb}->_mg_map->{$key} } = $collections->{$key};
    }
  } else {
    $self->{mgdb}->set_jobs(\@metas);
  }

  if ($cgi->param('use_buffer')) {
    my @md5s = split(/;/, $cgi->param('use_buffer'));
    $result = $self->{mgdb}->get_functions_for_md5s(\@md5s, \@sources, $evalue, $identity, $alength);
  }
  else {
    $result = $self->{mgdb}->get_functions_for_sources(\@sources, $evalue, $identity, $alength);
  }
  # mgid, source, function, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  if ($mg_grp_sel eq 'groups') {
    my $joined_data = {};
    foreach my $row (@$result) {
      $row->[0] = $collections->{$row->[0]};
      my $id_string = join("|", @$row[0..2]);
      if (exists($joined_data->{$id_string})) {
	$row->[5] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[5]) + ($row->[3] * $row->[5])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[6] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[6]) + ($row->[3] * $row->[6])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[7] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[7]) + ($row->[3] * $row->[7])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[8] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[8]) + ($row->[3] * $row->[8])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[9] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[9]) + ($row->[3] * $row->[9])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[10] = sprintf("%.2f", (($joined_data->{$id_string}->[3] * $joined_data->{$id_string}->[10]) + ($row->[3] * $row->[10])) / ($joined_data->{$id_string}->[3] + $row->[3]));
	$row->[11] = $joined_data->{$id_string}->[11].";".$row->[11];
	$row->[3] += $joined_data->{$id_string}->[3];
	$row->[4] += $joined_data->{$id_string}->[4];
      }
      $joined_data->{$id_string} = $row;
    }
    @$result = map { $joined_data->{$_} } keys(%$joined_data);
  }
  
  return $result;
}

sub lca_data {
  my ($self) = @_;

  my $result = [];
  my $md5_abund = {};
  my $cgi      = $self->application->cgi;
  my @metas    = $cgi->param('comparison_metagenomes');
  my $evalue   = $cgi->param('evalue')   || undef;
  my $identity = $cgi->param('identity') || undef;
  my $alength  = $cgi->param('alength')  || undef;
  my $mg_grp_sel = $cgi->param('mg_grp_sel') || '';
  my $mgrast = $self->application->data_handle('MGRAST');

  my $collections = {};
  if ($mg_grp_sel eq 'groups') {
    my @comparison_collections = $cgi->param('comparison_collections');
    $cgi->param('comparison_metagenomes', @comparison_collections);
    my $collections_ary = [];
    my $projects = [];
    foreach my $entry (@comparison_collections) {
      if ($entry =~ /^project\:/) {
	push(@$projects, $entry);
      } else {
	push(@$collections_ary, $entry);
      }
    }
    if ($self->application->session->user) {
      my $comp_cols = {};
      %$comp_cols = map { $_ => 1 } @$collections_ary;
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if ($comp_cols->{$name}) {
	    $collections->{$val} = $name;
	    push(@metas, $val);
	  }
	}
      }
    }
    foreach my $project (@$projects) {
      my ($pid) = $project =~ /^project\:(\d+)$/;
      my $p = $mgrast->Project->init( { id => $pid } );
      my $pjs = $mgrast->ProjectJob->get_objects( { project => $p } );
      foreach my $pj (@$pjs) {
	push(@metas, $pj->job->job_id);
	$collections->{$pj->job->job_id} = $project;
      }
    }

    $self->{mgdb}->set_jobs(\@metas, 1);
    foreach my $key (keys(%$collections)) {
      $collections->{ $self->{mgdb}->_mg_map->{$key} } = $collections->{$key};
    }
  } else {
    $self->{mgdb}->set_jobs(\@metas);
  }

  $result = $self->{mgdb}->get_lca_data($evalue, $identity, $alength);
  # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv

  if ($mg_grp_sel eq 'groups') {
    my $joined_data = {};
    foreach my $row (@$result) {
      $row->[0] = $collections->{$row->[0]};
      my $id_string = join("|", @$row[0..8]);
      if (exists($joined_data->{$id_string})) {
	$row->[10] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[10]) + ($row->[9] * $row->[10])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[11] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[11]) + ($row->[9] * $row->[11])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[12] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[12]) + ($row->[9] * $row->[12])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[13] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[13]) + ($row->[9] * $row->[13])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[14] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[14]) + ($row->[9] * $row->[14])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[15] = sprintf("%.2f", (($joined_data->{$id_string}->[9] * $joined_data->{$id_string}->[15]) + ($row->[9] * $row->[15])) / ($joined_data->{$id_string}->[9] + $row->[9]));
	$row->[9] += $joined_data->{$id_string}->[9];
      }
      $joined_data->{$id_string} = $row;
    }
    @$result = map { $joined_data->{$_} } keys(%$joined_data);
  }
  
  return $result;
}

# sub recruitment_plot_data {
#   my ($self, $name, $mgid, $divid) =@_;
# 
#   my $cgi    = $self->application->cgi;
#   my $orgid  = $cgi->param('ref_genome');
#   my $eval   = $cgi->param('evalue_range');
#   my $mgdb   = $self->{mgdb};
#   my $source = $self->data('rplot_source');
#   my $cutoff = undef;
# 
#   if ($eval =~ /e-(\d+)$/) {
#     $cutoff = $1;
#   }
# 
#   my @data = ();
#   my %uniq = ();
#   my $link = $mgdb->link_for_source($source);
#   my %md5_data = map { $_->[1], [ @$_[2..10] ] } @{ $mgdb->get_md5_data_for_organism_source($name, $source, $cutoff) };
# 
#   foreach ( @{ $mgdb->ach->org2contig_data($orgid, 1) } ) {
#     my ($ctg, $md5, $id, $func, $low, $high, $strand, $clen) = @$_;
#     $strand = ($strand == 1) ? "+" : "-";
#     if (exists $md5_data{$md5}) {
#       $uniq{$md5} = 1;
#       my @curr_data = @{ $md5_data{$md5} };
#       my ($num, $seek, $len) = @curr_data[0,7,8];
#       my $read_l = qq~<a style='cursor:pointer' onclick='execute_ajax("get_reads_table", "read_div$divid", "metagenome=$mgid&md5=$md5&seek=$seek&length=$len&type=protein");'>$num</a>~;
#       my $id_l   = $link ? "<a target=_blank href='".$link.$id."'>".$id."</a>" : $id;
#       push @data, [ $id_l, $func, $read_l, $low, $high, $strand, $ctg, $clen, @curr_data[1..6], $md5 ];
#     }
#   }
# 
#   return (\@data, scalar(keys %uniq));
# }

# sub recruitment_plot_graph {
#   my ($self, $name, $mapname) = @_;
# 
#   my $cgi    = $self->application->cgi;
#   my $orgid  = $cgi->param('ref_genome');
#   my $eval   = $cgi->param('evalue_range');
#   my $log    = $cgi->param('scale');
#   my $mgdb   = $self->{mgdb};
#   my $source = $self->data('rplot_source');
#   my $colors = ['blue','green','yellow','orange','red'];
#   my $evals  = $self->get_evals;
#   my $cutoff = $self->get_eval_index($eval);
#   my $eval_set = [];
# 
#   @$evals  = @$evals[$cutoff..4];
#   @$colors = @$colors[$cutoff..4];
# 
#   my $unique_str     = join('_', ( join("_", @{$mgdb->_jobs}), $orgid, $eval, $log ));
#   my $circos_file    = "circos_$unique_str";
#   my $config_file    = "$Conf::temp/circos_$unique_str.conf";
#   my $karyotype_file = "$Conf::temp/karyotype_$unique_str.txt";
#   my $fwd_gene_file  = "$Conf::temp/genes_fwd_$unique_str.txt";
#   my $rev_gene_file  = "$Conf::temp/genes_rev_$unique_str.txt";
#   my $evals_file     = "$Conf::temp/evals_$unique_str.txt";
# 
#   if ((-s $config_file) && (-s $karyotype_file) && (-s $fwd_gene_file) && (-s $rev_gene_file) && (-s $evals_file)) {
#     my ($prev_evals, $prev_stats) = $self->get_data_from_config($config_file);
#     for (my $j=0; $j<@$prev_evals; $j++) { push @$eval_set, [ $evals->[$j], $prev_evals->[$j], $colors->[$j] ]; }
#     if (-s "$Conf::temp/$circos_file.png") {
#       return [$circos_file, $eval_set, $prev_stats];
#     } else {
#       my $r = system($Conf::circos_path." -conf $config_file -silent");
#       return ($r == 0) ? [$circos_file, $eval_set, $prev_stats] : ["Circos failed: $?",  []];
#     }
#   }
#   
#   my $num_frag = $mgdb->get_abundance_for_organism_source($name, $source);
#   my $contigs  = $mgdb->ach->org2contigs($orgid);
#   if (scalar @$contigs == 0) { return ["No contigs available for $name", []]; }
# 
#   my (%ctg_name, %job_data);
#   my %ctg_len = map { $_->[0], $_->[1] } @$contigs;
#   
#   my @eval_sums = (0, 0, 0, 0, 0);
#   @eval_sums = @eval_sums[$cutoff..4];
#   
#   my $md5_evals = $mgdb->get_md5_evals_for_organism_source($name, $source);
#   foreach my $md5 (keys %$md5_evals) {
#     my @e = @{ $md5_evals->{$md5} };
#     @e    = @e[$cutoff..4];
#     for (my $i=0; $i<@e; $i++) { $eval_sums[$i] += $e[$i]; }
#     $job_data{$md5} = \@e;
#   }
# 
#   my $i = 1;
#   open(KARF, ">$karyotype_file") || return ["Unable to open $karyotype_file", []];
#   foreach (sort {$ctg_len{$a} <=> $ctg_len{$b}} keys %ctg_len) {
#     print KARF "chr - chr$i $_ 0 $ctg_len{$_} vlblue url=$_\n";
#     $ctg_name{$_} = "chr$i";
#     $i++;
#   }
#   close KARF;
# 
#   open(FGF, ">$fwd_gene_file") || return ["Unable to open $fwd_gene_file", []];
#   open(RGF, ">$rev_gene_file") || return ["Unable to open $rev_gene_file", []];
#   open(EVF, ">$evals_file")    || return ["Unable to open $evals_file", []];
# 
#   my (@gene, @hit);
#   my $max_pos  = 0;
#   my $max_neg  = 0;
#   my $num_feat = 0;
#   my $num_hit  = 0;
#   foreach ( @{ $mgdb->ach->org2contig_data($orgid) } ) {
#     my @vals = ();
#     my ($ctg, $md5, $id, $low, $high, $strand, $clen) = @$_;
#     $num_feat += 1;
# 
#     @gene = ( $ctg_name{$ctg}, $low, $high, "color=" . (exists($job_data{$md5}) ? "red" : "black") );
#     if (exists $job_data{$md5}) {
#       $num_hit += 1;
#       @vals = map { $self->get_log($log, $_) } @{ $job_data{$md5} };
#       @hit  = ( $ctg_name{$ctg}, $low, $high );
#     }
# 
#     if ($strand == 1) {      
#       print FGF join(" ", @gene) . "\n";
#       if (exists $job_data{$md5}) {
#   my $sum  = sum @vals;
#   $max_pos = max ($max_pos, $sum);
#   print EVF join(" ", @hit) . " " . join(",", @vals) . " id=$id\n";
#       }
#     }
#     elsif ($strand == -1) {
#       print RGF join(" ", @gene) . "\n";
#       if (exists $job_data{$md5}) {
#   @vals    = map { $_ * -1 } @vals;
#   my $sum  = sum @vals;
#   $max_neg = min ($max_neg, $sum);
#   print EVF join(" ", @hit) . " " . join(",", @vals) . " id=$id\n";
#       }
#     }
#   }
#   close FGF;
#   close RGF;
#   close EVF;
# 
#   my $color_str = join(",", @$colors);
#   my $evals_str = join(",", @eval_sums);
#   my $stats_str = join(",", ($num_frag, $num_hit, $num_feat));
#   my $axis_size = int( ($max_pos + abs($max_neg)) / 20 ) || 1;
# 
#   open(CFG, ">$config_file") || return ["Unable to open $config_file", []];
#   print CFG qq~
# <colors>
# <<include etc/colors.conf>>
# </colors>
# <fonts>
# <<include etc/fonts.conf>>
# </fonts>
# <<include $Conf::config/ideogram.conf>>
# <<include $Conf::config/ticks.conf>>
# 
# karyotype = $karyotype_file
# 
# <image>
# dir  = $Conf::temp
# file = $circos_file.png
# image_map_use  = yes
# image_map_name = $mapname
# radius         = 960p
# background     = white
# angle_offset   = -90
# </image>
# 
# chromosomes_units           = 1000
# chromosomes_display_default = yes
# 
# <plots>
# <plot>
# show   = yes
# type   = tile
# file   = $fwd_gene_file
# layers = 1
# margin = 0.0001u
# r0     = 1.1r
# r1     = 1.15r
# thickness   = 15
# padding     = 5
# orientation = out
# background  = no
# layers_overflow  = collapse
# stroke_thickness = 0
# stroke_color     = white
# </plot>
# <plot>
# show   = yes
# type   = tile
# file   = $rev_gene_file
# layers = 1
# margin = 0.0001u
# r0     = 0.91r
# r1     = 0.97r
# thickness   = 15
# padding     = 5
# orientation = in
# background  = no
# layers_overflow  = collapse
# stroke_thickness = 0
# stroke_color     = white
# </plot>
# <plot>
# url  = [id]
# show = yes
# file = $evals_file
# type = histogram
# r0   = 0.35r
# r1   = 0.90r
# min  = $max_neg
# max  = $max_pos
# color      = white
# fill_color = $color_str
# fill_under = yes
# thickness  = 0
# sort_bin_values = no
# orientation    = out
# extend_bin     = no
# axis           = yes
# axis_color     = vlgrey
# axis_thickness = 1
# axis_spacing   = $axis_size
# </plot>
# </plots>
# 
# anglestep     = 0.5
# minslicestep  = 10
# beziersamples = 40
# debug         = no
# warnings      = no
# imagemap      = no
# units_ok      = bupr
# units_nounit  = n
# 
# #evals $evals_str
# #stats $stats_str
# ~;
#   close CFG;
# 
#   my $cmd = $Conf::circos_path." -conf ".$config_file." -silent 2>&1";
#   my $msg = `$cmd`;
#   for (my $j=0; $j<@eval_sums; $j++) { push @$eval_set, [ $evals->[$j], $eval_sums[$j], $colors->[$j] ]; }
#   return $msg ? ["ERROR: $msg",  [], undef] : [$circos_file, $eval_set, [$num_frag, $num_hit, $num_feat]];
# }

sub workbench_export {
  my ($self) = @_;
  
  my $cgi    = $self->application->cgi;
  my @metas  = $cgi->param('comparison_metagenomes');
  my $source = $cgi->param('comparison_sources');
  my @md5s   = split(/;/, $cgi->param('use_buffer'));

  $self->{mgdb}->set_jobs(\@metas);

  my $md5_data = {};
  my $seq_data = $self->{mgdb}->md5s_to_read_sequences(\@md5s); # [ { 'md5' => md5, 'id' => id, 'sequence' => sequence } ]
  my $src_type = $self->{mgdb}->_sources->{$source}{type};
  my $md5_ann  = $self->{mgdb}->annotation_for_md5s(\@md5s, [$source]); # [ md5_id, id, md5, function, organism, source ]

  # ontology has no organism annotation
  if ($src_type eq 'ontology') {
    # seperate id->role mapping for subsystems
    if ($source eq 'Subsystems') {
      my $ss_map = $self->{mgdb}->get_hierarchy('ontology', 'Subsystems');
      map { push @{$md5_data->{$_->[2]}}, [$ss_map->{$_->[1]}[2], $ss_map->{$_->[1]}[3]] } grep { exists $ss_map->{$_->[1]} } @$md5_ann;
    } else {
      map { push @{$md5_data->{$_->[2]}}, [$_->[1], $_->[3]] } @$md5_ann;
    }
  }
  else {
    map { push @{$md5_data->{$_->[2]}}, [$_->[1], $_->[3].($_->[4] ? " [".$_->[4]."]" : '')] } @$md5_ann;
  }

  my @fastas = ();
  foreach my $s (@$seq_data) {
    if ($s && exists($s->{md5}) && exists($md5_data->{$s->{md5}})) {
      $s->{sequence} =~ s/(.{60})/$1\n/g;
      foreach my $data ( @{$md5_data->{$s->{md5}}} ) {
	    next unless ($data->[0]);
	    push @fastas, ">".$s->{id}."|".$source."|".$data->[0].($data->[1] ? " ".$data->[1] : '')."\n".$s->{sequence};
      }
    }
  }
  my $content = join("\n", @fastas);
  my $fname   = join("_", @metas) . "_" . scalar(@fastas) . "_sequences_annotated_by_$source.fna";

  print "Content-Type:application/x-download\n";  
  print "Content-Length: " . length($content) . "\n";
  print "Content-Disposition:attachment;filename=$fname\n\n";
  print $content;
  exit;
}

sub workbench_blat_output {
  my ($self) = @_;

  $self->title('BLAT alignments');
  
  my $cgi    = $self->application->cgi;
  my @metas  = $cgi->param('comparison_metagenomes');
  my @md5s   = split(/\^/, $cgi->param('md5s'));
  my $tabnum = $cgi->param('tabnum') || 2;
  my $sorc = $self->{mgdb}->_sources;
  my $selected_source = $cgi->param('source') eq 'M5NR' ? "RefSeq" : $cgi->param('source');
  my $sources;
  @$sources = keys(%$sorc);

  $self->{mgdb}->set_jobs(\@metas);

  my $links_hash = {};   # md5 => source => id
  my $funcs      = {};   # md5 => [ source, id, function ]
  my $orgshash   = {};   # md5 => organism
  my $ncbi_ids   = {};   # organism => tax_id
  my $md5_ann    = $self->{mgdb}->annotation_for_md5s(\@md5s, $sources, 1); # [ md5_id, id, md5, function, organism, source, tax_id ]

  map { $links_hash->{$_->[2]}{$_->[5]} = $_->[1] } @$md5_ann;
  map { push @{$funcs->{$_->[2]}}, [ @$_[5,1,3] ] } grep { $_->[3] } @$md5_ann;
  map { $orgshash->{$_->[2]} = $_->[4] } grep { $_->[4] } @$md5_ann;
  map { $ncbi_ids->{$_->[4]} = $_->[6] } grep { $_->[4] && $_->[6] } @$md5_ann;
  
  my $mg_seq_data = $self->{mgdb}->md5s_to_read_sequences(\@md5s); # [ { 'md5' => md5, 'id' => id, 'sequence' => sequence } ]
  my $nr_seq_data = $self->{mgdb}->get_m5nr_sequences_from_md5s([keys %$funcs]); # fasta text

  my %fastas = ();
  foreach my $s (@$mg_seq_data) {
    $s->{sequence} =~ s/(.{60})/$1\n/g;
    $fastas{">".$s->{id}."\n".$s->{sequence}} = 1;
  }
  my $fgs_infile_content = join("\n", keys %fastas);

  # Printing some error messages to inform users if this fails.
  foreach my $mg (@metas) {
    my $mgrast = $self->application->data_handle('MGRAST');
    my $js = $mgrast->Job->get_objects( { metagenome_id => $mg } );
    my $job_stats = $js->[0]->stats();
    my $raw_len_max = exists($job_stats->{length_max_raw}) ? $job_stats->{length_max_raw} : 0;
    if($raw_len_max > 500000) {
      $self->application->add_message('warning', "The maximum sequence length in this metagenome is $raw_len_max"."bp which is over the size limit (500kbp) for this part of the analysis.");
      $self->{blat} = "<br />No results were returned.";
      return 1;
    } elsif($fgs_infile_content eq "") {
      $self->application->add_message('warning', "Unable to retrieve any sequences for this project.  If someone is sharing this data with you please contact them with inquiries.  However, if you believe you have reached this message in error please contact <a href='mailto:mg-rast\@mcs.anl.gov'>MG-RAST mailing list</a>.");
      $self->{blat} = "<br />No results were returned.";
      return 1;
    }
  }

  my ($fgs_infile, $fgs_infile_name) = tempfile( "fgs_in_XXXXXXX", DIR => $Conf::temp, SUFFIX => '.faa');
  print $fgs_infile $fgs_infile_content;
  close $fgs_infile;
  my ($nr_file, $nr_file_name) = tempfile( "nr_XXXXXXX", DIR => $Conf::temp, SUFFIX => '.faa');
  print $nr_file $nr_seq_data;
  close $nr_file;
  my $fgs_cmd = $Conf::fraggenescan_executable." -s $fgs_infile_name -o " . $fgs_infile_name . ".fgs -w 0 -t 454_30";
  `$fgs_cmd`;
  my $blat_cmd = $Conf::blat_executable." -prot -out=blast ".$nr_file_name." ".$fgs_infile_name.".fgs.faa ".$fgs_infile_name.".blat.out";
  `$blat_cmd`;

  my $fgs_output = "";
  if (open(FH, "<".$fgs_infile_name.".fgs")) {
    while (<FH>) {
      $fgs_output .= $_;
    }
    close FH;
  }
  
  my $nr_seq_formatted = "";
  my @nr_lines = split(/\n/, $nr_seq_data);
  foreach my $line (@nr_lines) {
    unless ($line =~ /^>/) {
      $line =~ s/(.{60})/$1\n/g;
    }
      $nr_seq_formatted .= $line."\n";  
  }

  my $blat_output = "<style>td { padding: 4px; }</style><p style='width: 600px; font-variant: normal'>The sequence alignments underlying functional and organismal classification are stored in MG-RAST in an abbreviated format. This page allows re-creation of these alignments using the original parameters and tools.<br><br>
<b>NOTE:</b> Since different annotation providers have different interpretation of the sequences, you can switch between <b>name spaces</b> when performing this query.
</p>";

  my $used_sorcs = {};
  my $alignments = "";
  my $overview = "<table border=1 style='border-collapse: collapse; border-left: none; border-right: none;'><tr style='background-color: #8FBC3F; color: white;'><td style='border-left: 1px solid black;'><b>fragment</b></td><td><b>organism</b></td><td><b>name space</b></td><td><b>name space ID</b></td><td><b>function</b></td><td><b>e-value<a href='http://www.ncbi.nlm.nih.gov/books/NBK21106/def-item/app42/' target=_blank><sup style='cursor: help; color: black;'>[?]</sup></a></b></td><td><b>score<a href='http://www.ncbi.nlm.nih.gov/books/NBK21106/def-item/app8/' target=_blank><sup style='cursor: help; color: black;'>[?]</sup></a></b></td><td style='border-right: 1px solid black;'><b>identity</b></td></tr>";
  my $counter = 1;
  if (open(FH, "<".$fgs_infile_name.".blat.out")) {
    my $lastid = "";
    while (<FH>) {
      if ($_ =~ /^>/) {
	chomp;
	my $line = $_;
	my ($pref, $id) = $line =~ /^(.+)\|([\w\d]+)/;
	$line = "";
	my $mainfunc = "";
	my $main_source = "";
	my $main_id = "";
	my $oname = exists($orgshash->{$id}) ? $orgshash->{$id} : "unknown";
	if (exists($funcs->{$id})) {
	  my @rows = sort { $a->[0] cmp $b->[0] } @{$funcs->{$id}};
	  my ($la, $lb) = ("", "");
	  foreach my $r (@rows) {
	    next if ($la eq $r->[0]);
	    my $sel = "display: none;";
	    $used_sorcs->{$r->[0]} = 1;
	    if ($r->[0] eq $selected_source) {
	      $sel = "";
	    }
	    $mainfunc .= "<div style='$sel' name='align' id='align_func_".$counter."_".$r->[0]."'>".$r->[2]."</div>";
	    $main_source .= "<div style='$sel' name='align' id='align_source_".$counter."_".$r->[0]."'>".$r->[0]."</div>";

	    my $id_link = ($sorc->{$r->[0]}{link} && $links_hash->{$id}{$r->[0]}) ? "<a target=_blank href='".$sorc->{$r->[0]}{link}.$links_hash->{$id}{$r->[0]}."'>".$links_hash->{$id}{$r->[0]}."</a>" : $id;
        if ($id_link) {
	      $main_id .= "<div style='$sel' name='align' id='align_id_".$counter."_".$r->[0]."'>".$id_link."</div>";
        }
	    $line .= "<div style='$sel' name='align' id='align_row_".$counter."_".$r->[0]."'>>".$r->[0].": ".($links_hash->{$id}->{$r->[0]} ? ($links_hash->{$id}->{$r->[0]}) : "" )." ".$r->[2]." [".$oname."]</div>";
	    $la = $r->[0];
	    $lb = $r->[2];
	  }
	}
	$alignments .= "<a name='anchor$counter'></a>".$line."<pre style='font-variant: normal'>";
	$line = <FH>;
	my ($score, $evalue, $identity) = ("","","");
	while ($line !~ /Database/) {
	  my ($s, $e) = $line =~ /Score = (\d+ bits \(\d+\)), Expect = (.*)/;
	  if ($s && $score eq "") {
	    chomp $e;
	    $score = $s;
	    $evalue = $e;
	  }
	  my ($iden) = $line =~ /Identities = ([^,]+)/;
	  if ($iden && $identity eq "") {
	    $identity = $iden;
	  }
	  $alignments .= $line;
	  $line = <FH>;
	}
	$alignments .= "</pre>\n\n";
	if ($lastid ne $id && $lastid ne "") {
	  $overview .= "<tr style='height: 2px;'><td colspan=7 style='height: 2px;'></td></tr>";
	}
	if ($ncbi_ids->{$oname}) {
	  $oname = "<a href='http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=".$ncbi_ids->{$oname}."' target=_blank>$oname</a>";
	}
	$overview .= "<tr><td style='border-left: 1px solid black;'><a href='#anchor$counter'>".join("&nbsp;", split(/\|/, $mg_seq_data->[$counter-1]->{id}))."</a></td><td>$oname</td><td>$main_source</td><td>$main_id</td><td><a href='http://tools.metagenomics.anl.gov/m5nr/?page=SearchResults&search_type=md5&query=".$id."' title='click for M5NR entry (opens in new window)' target=_blank>$mainfunc</a></td><td>$evalue</td><td>$score</td><td style='border-right: 1px solid black;'>$identity</td></tr>";
	$lastid = $id;
	$counter++;
      }
    }
    close FH;
  }

  $overview .= "<tr><td style='border-left: 1px solid black;'><form method=post action='download.cgi'><input type='submit' value='download all sequences' style='width: 220px;'><input type=hidden name='filename' value='metagenome_sequence.faa'><input type='hidden' value='$fgs_infile_content' name='content'></form><form method=post action='download.cgi'><input type='submit' value='download predicted coding sequences' style='width: 220px;'><input type=hidden name='filename' value='FragGeneScan.fgs'><input type='hidden' value='$fgs_output' name='content'></form></td><td></td><td></td><td><form method=post action='download.cgi'><input type='submit' value='download database sequences' style='width: 220px;'><input type=hidden name='filename' value='nr_sequence.faa'><input type='hidden' value='$nr_seq_formatted' name='content'></form></td><td></td><td></td><td></td><td style='border-right: 1px solid black;'></td></tr>";

  $overview .= "</table>";

  my $sel_all = "select annotation name space <select onchange='var sr=document.getElementsByName(\"align\");for(i=0;i<sr.length;i++){if(sr[i].id.indexOf(this.options[this.selectedIndex].value)>-1){sr[i].style.display=\"\";}else{sr[i].style.display=\"none\";}};'>";
  foreach my $s (sort(keys(%$used_sorcs))) {
    my $selected = "";
    if ($s eq $selected_source) {
      $selected = " selected=selected";
    }
    $sel_all .= "<option value='$s'$selected>$s</option>";
  }
  $sel_all .= "</select><br><br>";

  unlink $fgs_infile_name;
  unlink $nr_file_name;
  unlink $fgs_infile_name.".fgs";
  unlink $fgs_infile_name.".fgs.faa";
  unlink $fgs_infile_name.".fgs.ffn";
  unlink $fgs_infile_name.".blat.out";
  
  $self->{blat} = $blat_output.$sel_all.$overview."<br><br>".$alignments;

  return 1;
}

sub workbench_hits_table {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my @metas = $cgi->param('comparison_metagenomes');
  my @srcs  = $cgi->param('comparison_sources');
  my @md5s  = split(/;/, $cgi->param('use_buffer'));
  my @mglinks   = @metas;
  my $has_ss    = first {$_ =~ /^Subsystems$/i} @srcs;
  my $has_m5nr  = first {$_ =~ /^M5NR$/i} @srcs;
  my $has_m5rna = first {$_ =~ /^M5RNA$/i} @srcs;
  my @ach_srcs  = grep {$_ !~ /^(M5NR|M5RNA)$/i} @srcs;

  if ($has_m5rna) {
      @srcs = ('RDP','Greengenes','SSU','LSU','ITS');
      @ach_srcs = @srcs;
  }

  $self->{mgdb}->set_jobs(\@metas);
  my $analysis_data = $self->{mgdb}->get_md5_data(\@md5s);
  my $source_info   = $self->{mgdb}->_sources;
  my $ss_map        = $has_ss ? $self->{mgdb}->get_hierarchy('ontology', 'Subsystems') : {};
  my $md5_type      = $self->{mgdb}->type_for_md5s(\@md5s, 1);  # id => [md5, type]
  my $source_data   = {};   # md5 => [ source, id, function ]
  if (@ach_srcs > 0) {
      # [ md5_id, id, md5, function, organism, source ]
      map { push @{$source_data->{$_->[2]}}, [ @$_[5,1,3] ] } grep { $_->[3] } @{$self->{mgdb}->annotation_for_md5s(\@md5s, \@ach_srcs)};
  }

  my $html = "<p>Hits for " . scalar(@md5s) . " unique sequences within ";
  foreach my $mg (@mglinks) {
    my $name = '';
    my $job  = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
    if (ref($job)) {
      $name = $job->name()." ($mg)";
    }
    $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$name'>$mg</a>";
  }
  if (scalar(@mglinks) > 1) {
    my $last = pop @mglinks;
    $html .= "metagenomes ".join(", ", @mglinks)." and $last";
  } else {
    $html .= "metagenome ".$mglinks[0];
  }
  $html .= " compaired to data ";

  if (scalar(@srcs) > 1) {
    my $last = pop @srcs;
    $html .= "sources ".join(", ", @srcs)." and $last";
  } else {
    $html .= "source ".$srcs[0];
  }
  $html .= "</p>";

  my @table_data = ();
  foreach my $row ( @$analysis_data ) {
    my ($mg, $md5, $num, $seek, $len) = @$row[0,1,2,9,10];
    my $md5sum = $md5_type->{$md5}[0];
    if (exists $source_data->{$md5sum}) {
      foreach my $set ( sort {($a->[0] cmp $b->[0]) || ($a->[1] cmp $b->[1])} @{$source_data->{$md5sum}} ) {
	    if (exists $source_info->{$set->[0]}) {
	      my $id    = exists($ss_map->{$set->[1]}) ? $ss_map->{$set->[1]}[2] : $set->[1];
	      my $type  = $source_info->{$set->[0]}{type};
	      my $idl   = $source_info->{$set->[0]}{link} ? "<a target=_blank href='".$source_info->{$set->[0]}{link}.$id."'>".$id."</a>" : $set->[1];
	      my $readl = $num;
	      if ($type eq 'rna') {
	        $readl = qq~<a style='cursor:pointer' onclick='execute_ajax("get_reads_table", "read_div", "metagenome=$mg&md5=$md5sum&seek=$seek&length=$len&type=$type");'>$num</a>~;
	      } else {
	        $readl = qq~<a style='cursor:pointer' onclick='execute_ajax("get_read_align", "read_div", "metagenome=$mg&md5=$md5&seek=$seek&length=$len&type=$type");'>$num</a>~;
	      }
	      push @table_data, [ $mg,  $set->[0], $idl, $set->[2], $readl, @$row[3..8], $md5sum ];
	    }
      }
    }
    if ($has_m5nr && ($md5_type->{$md5}[1] eq 'protein')) {
      my $md5l  = "<a target=_blank href='http://tools.metagenomics.anl.gov/m5nr/?page=SearchResults&search_type=md5&query=$md5sum'>$md5sum</a>";
      my $readl = qq~<a style='cursor:pointer' onclick='execute_ajax("get_read_align", "read_div", "metagenome=$mg&md5=$md5&seek=$seek&length=$len&type=protein");'>$num</a>~;
      push @table_data, [ $mg, 'M5NR', $md5l, '', $readl, @$row[3..8], $md5sum ];
    }
  }

  my $table = $self->application->component('wb_hits');
  $table->show_select_items_per_page(1);
  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->items_per_page(25);
  $table->show_column_select(1);
  $table->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});
  
  my $columns = [ { name => 'metagenome',        sortable => 1, filter => 1,  operator => 'combobox',       tooltip => 'id of metagenomic sample' },
		  { name => 'source',            sortable => 1, filter => 1,  operator => 'combobox',       tooltip => 'database source of the hits', visible => ((@srcs == 1) ? 0 : 1) },
		  { name => 'id',                sortable => 1, filter => 1,                                tooltip => 'database source ID of the hit' },
		  { name => 'function',          sortable => 1, filter => 1,                                tooltip => 'functional annotation of sequence from source' },
		  { name => 'abundance',         sortable => 1, filter => 1,  operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		  { name => 'avg eValue',        sortable => 1, filter => 1,  operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		  { name => 'eValue std dev',    sortable => 1, visible => 0,                               tooltip => 'standard deviation of the evalue<br>, showing exponent only' },
		  { name => 'avg % ident',       sortable => 1, filter => 1,  operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		  { name => '% ident std dev',   sortable => 1, visible => 0,                               tooltip => 'standard deviation of<br>the percent identity of the hits' },
		  { name => 'avg align len',     sortable => 1, filter => 1,  operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		  { name => 'align len std dev', sortable => 1, visible => 0,                               tooltip => 'standard deviation of<br>the alignment length of the hits' },
		  { name => 'md5',               sortable => 1, visible => 0,                               tooltip => 'md5 checksum of hit sequence'  }
	       ];
	       
  $table->columns($columns);
  $table->data(\@table_data);
  $html .= $table->output;
  $html .= "<div id='read_div'></div>";

  return $html;
}

sub get_read_align {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my $mgid = $cgi->param('metagenome') || '';
  my $md5  = $cgi->param('md5') || '';
  my $type = $cgi->param('type');
  my $job  = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mgid });
  my $html = '<br>';
  
  $self->{mgdb}->set_jobs([$mgid]);
  my $md5_map  = $self->{mgdb}->decode_annotation('md5', [$md5]);
  my $md5sum   = $md5_map->{$md5};
  my $seq_data = $self->{mgdb}->md5s_to_read_sequences([$md5]); # [ { 'md5' => md5, 'id' => id, 'sequence' => sequence } ]
  my @md5_seq  = split(/\n/, $self->{mgdb}->get_m5nr_sequences_from_md5s([$md5sum])); # fasta text

  if ((@md5_seq == 2) && ($md5_seq[0] =~ /$md5sum/)) {
    my $md5_fasta = $Conf::temp."/".$md5."_".time.".faa";
    open(MD5F, ">$md5_fasta") || return $html;
    print MD5F join("\n", @md5_seq) . "\n";
    close MD5F;
    $html .= "<p>Hit alignment for ".scalar(@$seq_data)." read".((scalar(@$seq_data) > 1) ? "s" : "")." within metagenome ".$job->name()." ($mgid) against sequence ";
    $html .= ($type ne 'rna') ? "<a target=_blank href='http://tools.metagenomics.anl.gov/m5nr/?page=SearchResults&search_type=md5&query=$md5sum'>$md5sum</a>" : $md5;
    $html .= "</p>";
    
    foreach my $s (@$seq_data) {
      my (undef, $id) = split(/\|/, $s->{id});
      my $read_fasta  = $Conf::temp."/".$mgid."_".$id."_".time.".fna";
      open(READF, ">$read_fasta") || return $html;
      print READF ">" . $s->{id} . "\n" . $s->{sequence} . "\n";
      close READF;

      my $align = `bl2seq -p blastx -i $read_fasta -j $md5_fasta -F F -e 0.01 -d 6000000000`;
      if ($align =~ /(Query= .*?letters\)).*\n(\s*?Query:.*)\nLambda/s) {
	my ($query, $text) = ($1, $2);
	$query =~ s/\s+/ /g;
	$text  =~ s/\nLambda.*//s;
	$html .= "<p>$query<blockquote><pre>$text</pre></blockquote></p>";
      }
    }
  }
  return $html;
}

sub get_reads_table {
  my ($self) = @_;

  my $cgi  = $self->application->cgi;
  my $mgid = $cgi->param('metagenome') || '';
  my $md5  = $cgi->param('md5') || '';
  my $seek = $cgi->param('seek');
  my $len  = $cgi->param('length');
  my $type = $cgi->param('type');

  ## m8: query, subject, identity, length, mismatch, gaps, q_start, q_end, s_start, s_end, evalue, bit_score
  my $columns = [ { name => 'read id',      sortable => 1, filter => 1, tooltip => 'id of metagenome sequence' },
		  { name => 'md5',          visible => 0,  tooltip => 'md5 checksum of hit sequence' },
		  { name => '% identity',   sortable => 1, tooltip => 'percent identity of hit' },
		  { name => 'align length', sortable => 1, tooltip => 'alignment length of hit' },
		  { name => 'mismatch',     sortable => 1, tooltip => 'number of mismatches' },
		  { name => 'gaps',         sortable => 1, tooltip => 'number of gaps' },
		  { name => 'read start',   sortable => 1, tooltip => 'start position of alignment in read sequence' },
		  { name => 'read end',     sortable => 1, tooltip => 'end position of alignment in read sequence' },
		  { name => 'hit start',    sortable => 1, tooltip => 'start position of alignment in hit sequence' },
		  { name => 'hit end',      sortable => 1, tooltip => 'end position of alignment in hit sequence' },
		  { name => 'e-value',      sortable => 1, tooltip => 'evalue of hit' },
		  { name => 'bit score',    sortable => 1, tooltip => 'bit score of hit' },
		  { name => 'sequence',     visible => 0,  tooltip => 'sequence of metagenome read' }
	       ];

  if ($mgid && $md5 && defined($seek) && defined($len)) {
    my $job  = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mgid });
    my $sims = $self->{mgdb}->get_md5_sims($job->job_id, [[$md5, $seek, $len]]);

    if (exists($sims->{$md5}) && (@{$sims->{$md5}} > 0)) {
      my $table = $self->application->component('t1');
      my @data  = map { [ split(/\t/, $_) ] } @{$sims->{$md5}};

      ## nasty id manipulation to allow for multiple tables
      my $newid = int(rand(100000));
      $self->application->component('TableHoverComponent'.$table->id)->id($newid);
      $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$table->id);
      $self->application->component('TableAjaxComponent'.$table->id)->id($newid);
      $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$table->id);
      $table->id($newid);
      ##

      if ( @{$sims->{$md5}} > 25 ) {
	    $table->show_top_browse(1);
	    $table->show_bottom_browse(1);
	    $table->items_per_page(25);
	    $table->show_select_items_per_page(1); 
      }
      $table->show_column_select(1);
      $table->columns($columns);
      $table->data(\@data);
      my $reads = scalar( @{$sims->{$md5}} );
      my $html  = "<p>Hit table for $reads read" . (($reads > 1) ? "s" : "") . " within metagenome " . $job->name() . " ($mgid)";
      if ($type ne 'rna') {
	    $html .= " against sequence <a target=_blank href='http://tools.metagenomics.anl.gov/m5nr/?page=SearchResults&search_type=md5&query=$md5'>$md5</a>";
      }
      $html .= "</p>" . $table->output();

      return $html;
    }
    else {
      return "<p style='color:red'>No similarities available for sequence checksum: $md5</p>";
    }
  }
  else {
    return "<p style='color:red'>missing paramaters: metagenome_id, md5sum, seek, length</p>";
  }
}

sub qiime_export_data {
  my ($self, $mgs, $type) = @_;

  my $cgi      = $self->application->cgi;
  my @sources  = $cgi->param('source');
  my $evalue   = $cgi->param('evalue')   || undef;
  my $identity = $cgi->param('identity') || undef;
  my $alength  = $cgi->param('alength')  || undef;
  
  $self->{mgdb}->set_jobs($mgs);
  
  my ($tbl_type, $md_type);
  my $name_md5s  = {}; # mgid => name => { md5_int }
  my $mg_md5_abd = $self->{mgdb}->get_md5_abundance($evalue, $identity, $alength); # mgid => md5_int => abundance

  if ($type eq 'organism') {
    $tbl_type  = "Taxon table";
    $md_type   = 'taxonomy';
    $name_md5s = $self->{mgdb}->get_org_md5($evalue, $identity, $alength, \@sources, 1); # mgid => annot_id => { md5_int }
  } else {
    $tbl_type  = "Function table";
    $md_type   = 'ontology';
    $type      = 'ontology';
    $name_md5s = $self->{mgdb}->get_ontol_md5($evalue, $identity, $alength, $sources[0], 1); # mgid => annot_id => { md5_int }
  }

  my %md5_names;  # md5_int => { annot_id }
  foreach my $mg (keys %$name_md5s) {
    foreach my $name (keys %{$name_md5s->{$mg}}) {
      foreach my $md5 (keys %{$name_md5s->{$mg}{$name}}) {
	    $md5_names{$md5}{$name} = 1;
      }
    }
  }    

  my $name_hier = $self->{mgdb}->get_hierarchy($type, $sources[0], undef, 1); # annot_id => [ hierarchy ]
  my $md2pos = {};
  my $values = [];
  my $hier = [];
  my $pos = 0;

  foreach my $md5 (keys %md5_names) {
    my $counts = [];
    foreach my $mg (@$mgs) {
      push @$counts, $mg_md5_abd->{$mg}->{$md5} ? $mg_md5_abd->{$mg}->{$md5} : 0;
    }
    if ((sum @$counts) == 0) { next; }
    foreach my $n ( sort keys %{$md5_names{$md5}} ) {
      if (exists($name_hier->{$n}) && (@{$name_hier->{$n}} > 0)) {
	    my @qiime = ($type eq 'organism') ? ("Root", @{$name_hier->{$n}}, $n) : @{$name_hier->{$n}};
	    if (! exists($md2pos->{$n})) {
	      $md2pos->{$n} = $pos;
	      push(@$hier, { "id" => $n, "metadata" => { $md_type => \@qiime } });
	      $pos++;
	    }
	    for (my $i=0; $i<scalar(@$mgs); $i++) {
	      if ($mg_md5_abd->{$mgs->[$i]}->{$md5}) {
	        push @$values, [ $md2pos->{$n}, $i, int($mg_md5_abd->{$mgs->[$i]}->{$md5}) ];
	      }
	    }
      }
    }
  }

  use POSIX qw(strftime);
  my $data = { "id"                  => "",
	       "format"              => "Biological Observation Matrix 1.0",
	       "format_url"          => "http://biom-format.org",
	       "type"                => $tbl_type,
	       "generated_by"        => "MG-RAST revision ".$Conf::server_version,
	       "date"                => strftime("%Y-%m-%dT%H:%M:%S", localtime),
	       "matrix_type"         => "sparse",
	       "matrix_element_type" => "int",
	       "shape"               => [ $pos, scalar(@$mgs) ],
	       "rows"                => $hier,
	       "columns"             => [ map { { "id" => $_, "metadata" => undef } } @$mgs ],
	       "data"                => $values };

  return $data;
}

#####################
# data visualization
#####################
sub single_visual {
  my ($self) = @_;

  my $content = "";
  my $cgi = $self->application->cgi;
  my $data = $self->single_data();
  # mgid => md5 => abundance

  # new
  #  0        1           2         3           4            5         6            7        8        9         10      11          12         13        14       15      16
  # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  # old
  # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  my $tabnum = $cgi->param('tabnum') || 2;
  $tabnum--;

  unless (scalar(@$data)) {
    return "<div><div>no data</div><div>".clear_progress_image()."The visualizations you requested cannot be drawn, as no data met your selection criteria.</div></div>";
  }

  my %buffer_md5s = $cgi->param('use_buffer') ? map {$_, 1} split(/;/, $cgi->param('use_buffer')) : ();
  my $settings_preserve = "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'>";
  my @comp_mgs = $cgi->param('comparison_metagenomes');
  if ($cgi->param('mg_grp_sel') && $cgi->param('mg_grp_sel') eq 'groups') {
    $settings_preserve .= "<input type='hidden' name='mg_grp_sel' value='groups'>";
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_collections' value='".$mg."'>";
    }
  } else {
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_metagenomes' value='".$mg."'>";
    }
  }
  my $mgs = "";
  my $mgnames = [];
  @$mgnames = @comp_mgs;
  foreach my $metagenome (@$mgnames) {
    my $mgname = '';
    unless ($cgi->param('comparison_collections')) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
      $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
    }
  }
  if (scalar(@$mgnames) > 1) {
    my $last = pop(@$mgnames);
    $mgs .= "metagenomes ".join(", ", @$mgnames)." and $last";
  } else {
    $mgs .= "metagenome ".$mgnames->[0];
  }
  my $source = $cgi->param('source');
  $settings_preserve .= "<input type='hidden' name='source' value='".$source."'>";

  my $cutoffs = "a maximum e-value of 1e-" . ($cgi->param('evalue') || '0') . ", ";
  $cutoffs   .= "a minimum identity of " . ($cgi->param('identity') || '0') . " %, ";
  $cutoffs   .= "and a minimum alignment length of " . ($cgi->param('alength') || '1') . ' measured in aa for protein and bp for RNA databases';

  my $psettings = " The data has been normalized to values between 0 and 1. If you would like to view raw values, redraw using the form below.";
  if ($cgi->param('raw')) {
    $psettings = " The data is showing raw values. If you would like to view normalized values, redraw using the form below.";
  }
  my $pset = "";
  if (defined($cgi->param('pval'))) {
    $pset = "<br><br>You have chosen to calculate p-values. They will appear in brackets after the category name.";
  }

  if ($cgi->param('use_buffer')) {
    $settings_preserve .= "<input type='hidden' name='use_buffer' value='".$cgi->param('use_buffer')."'>";
  }
  $settings_preserve .= "<input type='hidden' name='evalue' value='"   . ($cgi->param('evalue') || '0')   . "'>";
  $settings_preserve .= "<input type='hidden' name='identity' value='" . ($cgi->param('identity') || '0') . "'>";
  $settings_preserve .= "<input type='hidden' name='alength' value='"  . ($cgi->param('alength') || '1')  . "'>";
  my $fid = $cgi->param('fid') || int(rand(1000000));
    
  my $settings = "<i>This data was calculated for $mgs. The data was compared to $source using $cutoffs.$pset</i><br/>";

  ## determine if any metagenomes missing from results
  my $missing_txt = "";
  my @missing_mgs = ();
  my %data_mgs    = map { $_->[0], 1 } @$data;

  foreach my $mg (@comp_mgs) {
    if (! exists $data_mgs{$mg} && ! $cgi->param('comparison_collections')) {
      push @missing_mgs, $mg;
    }
  }  

  if (@missing_mgs > 0) {
    $missing_txt = "<br>";
    foreach my $mg (@missing_mgs) {
      my $mgname = '';
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
      if (ref($job)) {
	$mgname = $job->name()." ($mg)";
      }
      $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>";
    }
    if (@missing_mgs > 1) {
      my $last = pop @missing_mgs;
      $missing_txt .= "Metagenomes " . join(", ", @missing_mgs) . " and $last contain";
    } else {
      $missing_txt .= "Metagenome " . $missing_mgs[0] . " contains";
    }
    $missing_txt .= " no organism data for the above selected sources and cutoffs. They are being excluded from the analysis.<br>";
  }
  $settings .= $missing_txt;

  if ($cgi->param('vis_type') eq 'table') {
    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->show_select_items_per_page(1);
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_column_select(1);
    $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});

    my $tcols = [ { name => 'metagenome', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'id of metagenomic sample' },
		  { name => 'domain', sortable => 1, filter => 1, operator => 'combobox' }, 
		  { name => 'phylum', sortable => 1, filter => 1 }, 
		  { name => 'class', sortable => 1, filter => 1 },
		  { name => 'order', sortable => 1, filter => 1 }, 
		  { name => 'family', sortable => 1, filter => 1 },
		  { name => 'genus', sortable => 1, filter => 1 },
		  { name => 'species', sortable => 1, filter => 1 },
		  { name => 'strain', sortable => 1, filter => 1 }, 
		  { name => 'abundance', sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		  { name => 'avg eValue', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		  { name => 'eValue std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of the evalue,<br>showing exponent only' }, 
		  { name => 'avg % ident', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		  { name => '% ident std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the percent identity of the hits' },
		  { name => 'avg align len', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		  { name => 'align len std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the alignment length of the hits' },
		  { name => 'md5s', visible => 0 },
		  { name => '# hits', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of unique hits in protein or rna database' },
		  { name => "<input type='button' onclick='buffer_data(\"table\", \"".$t->id."\", \"18\", \"16\", \"0\", \"".$source."\", \"9\");' value='to workbench'>", input_type => 'checkbox', tooltip => 'check to select features<br>to add to workbench' } ];
    
    #### do the pivoting
    unless (defined $cgi->param('group_by')) {
      $cgi->param('group_by', '2');
    }
    for (my $i=($cgi->param('group_by')+2);$i<9;$i++) {
      $tcols->[$i]->{visible} = 0;
      $tcols->[$i]->{unaddable} = 1;
    }
    my $dhash = {};
    my $colhashcount = {};
    my $newdata = [];
    foreach my $d (@$data) {
      my $range = 1 + $cgi->param('group_by');
      my $key = join(";", @$d[0..$range]);
      if (exists($dhash->{$key})) { # sum|avg|avg|avg|avg|avg|avg|hash|num_hash|sum
	$newdata->[$dhash->{$key}]->[9] = $newdata->[$dhash->{$key}]->[9] + $d->[9];
	$newdata->[$dhash->{$key}]->[10] = (($newdata->[$dhash->{$key}]->[10] * $colhashcount->{$key}) + $d->[10]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[11] = (($newdata->[$dhash->{$key}]->[11] * $colhashcount->{$key}) + $d->[11]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[12] = (($newdata->[$dhash->{$key}]->[12] * $colhashcount->{$key}) + $d->[12]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[13] = (($newdata->[$dhash->{$key}]->[13] * $colhashcount->{$key}) + $d->[13]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[14] = (($newdata->[$dhash->{$key}]->[14] * $colhashcount->{$key}) + $d->[14]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[15] = (($newdata->[$dhash->{$key}]->[15] * $colhashcount->{$key}) + $d->[15]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[16] = $newdata->[$dhash->{$key}]->[16] . ";" . join(";", @{$d->[16]});
	$colhashcount->{$key}++;
      } else {
	$dhash->{$key} = scalar(@$newdata);
	$colhashcount->{$key} = 1;
	$d->[16] = join(";", @{$d->[16]});
	push(@$newdata, $d);
      }
    }
    foreach my $d (@$newdata) {
      my %hasher = map { $_ => 1 } split(/;/, $d->[16]);
      $d->[9] = "<a onclick='abu(this, $tabnum, 16);' style='cursor:pointer'>".$d->[9]."</a>";
      $d->[10] = sprintf("%.2f", $d->[10]);
      $d->[11] = sprintf("%.2f", $d->[11]);
      $d->[12] = sprintf("%.2f", $d->[12]);
      $d->[13] = sprintf("%.2f", $d->[13]);
      $d->[14] = sprintf("%.2f", $d->[14]);
      $d->[15] = sprintf("%.2f", $d->[15]);
      $d->[16] = join(";", keys(%hasher));
      $d->[17] = scalar(keys(%hasher));
    }

    @$newdata = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] || $a->[4] cmp $b->[4] || $a->[5] cmp $b->[5] || $a->[6] cmp $b->[6] || $a->[7] cmp $b->[7] || $a->[8] cmp $b->[8] } @$newdata;
    
    $t->columns($tcols);
    $t->data($newdata);

    my ($cd, $cp, $cc, $co, $cf, $cg, $cs, $cstr) = ('', '', '', '', '', '', '', '');
    if ($cgi->param('group_by') eq '0') {
      $cd = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '1') {
      $cp = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '2') {
      $cc = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '3') {
      $co = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '4') {
      $cf = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '5') {
      $cg = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '6') {
      $cs = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '7') {
      $cstr = " selected='selected'";
    }

    #my $krona_button = "<input type='button' value='krona graph' onclick='generate_krona_data(\"".$cgi->param('group_by')."\", \"".$t->id."\", \"org\");'>";
    
    #my $qiime_button =  ( $cgi->param('mg_grp_sel') ne 'groups' ) ? "<button onclick='execute_ajax(\"qiime_export_visual\", \"qiime_div_$tabnum\", \"table_group_form_$tabnum\");show_progress();'>QIIME report</button>" : 'Export for grouped data sets currently not available.<br> Please select <b>compare individually</b> in <b>(2) Data selection</b><br> above and recreate the table.';
    my $plugin_container = '';
    #my $plugin_container = '<table style="border: 2px solid rgb(143, 188, 63); text-align: center; float: right; border-spacing: 0px;"><tbody><tr><td colspan="2" style="cursor: pointer; text-align: left;" title="click to show available plugins" onclick="if(this.parentNode.nextSibling.style.display==\'none\'){this.parentNode.nextSibling.style.display=\'\';this.parentNode.nextSibling.nextSibling.style.display=\'\';}else{this.parentNode.nextSibling.style.display=\'none\';this.parentNode.nextSibling.nextSibling.style.display=\'none\';}"><img src="./Html/plugin.png" style="width: 20px; vertical-align: middle;"> available plugins</td></tr><tr><td style="border-top: 1px solid rgb(143, 188, 63); border-right: 1px solid rgb(143, 188, 63); padding: 2px;"><img src="./Html/krona.png" style="height: 50px; cursor: pointer;" onclick="window.open(&quot;http://sourceforge.net/p/krona/home/krona/&quot;);"></td><td style="border-top: 1px solid rgb(143, 188, 63);"><img onclick="window.open(&quot;http://www.qiime.org&quot;);" style="height: 50px; cursor: pointer;" src="./Html/qiime.png"></td></tr><tr><td style="vertical-align: middle; border-right: 1px solid rgb(143, 188, 63); padding: 2px;">'.$krona_button.'</td><td style="vertical-align: middle;">'.$qiime_button.'</td></tr></tbody></table>';
    my $qiime_div = '';
    #my $qiime_div = "<div style='padding-left:15px; float: right;' id='qiime_div_$tabnum'></div>";

    my $pivot = "<form id='table_group_form_$tabnum'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='table'><input type='hidden' name='data_type' value='organism'><input type='hidden' name='ret_type' value='direct'>".$settings_preserve."<br><b>group table by</b> <select name='group_by'><option value='0'$cd>domain</option><option value='1'$cp>phylum</option><option value='2'$cc>class</option><option value='3'$co>order</option><option value='4'$cf>family</option><option value='5'$cg>genus</option><option value='6'$cs>species</option><option value='7'$cstr>strain</option></select><input type='button' value='change' onclick='execute_ajax(\"single_visual\", \"tab_div_".($tabnum+1)."\", \"table_group_form_$tabnum\");'></form><br><br>";

    if ($cgi->param('ret_type') && $cgi->param('ret_type') eq 'direct') {
      return "$settings$plugin_container$qiime_div$pivot".$t->output;
    }

    $content .= "<div><div>Representative Organism table $tabnum</div><div>".clear_progress_image()."$settings$plugin_container$qiime_div$pivot".$t->output."</div></div>";
    $tabnum++;
  }

  if ($cgi->param('vis_type') eq 'vbar') {
    my $vbardata = [];
    if ($cgi->param('single_bar_sel') && $cgi->param('single_bar_col')) {
      @$vbardata = map { ($_->[$cgi->param('single_bar_col')] && ($_->[$cgi->param('single_bar_col')] eq $cgi->param('single_bar_sel'))) ? $_ : () } @$data;
    } else {
      @$vbardata = map { $_ } @$data;
    }
    foreach my $d (@$vbardata) {
      $d = [ shift @$d, "source", @$d ];
    }
    if ($cgi->param('single_bar_col')) {
      $cgi->param('single_bar_col', $cgi->param('single_bar_col') + 1);
    }
    my $level = $cgi->param('single_bar_col') ? ($cgi->param('single_bar_col') + 1) : 2;
    my $noclick;
    if ($level > 8) {
      $noclick = 1;
    }
    my $dom_v = $self->data_to_vbar(undef, $vbardata, $level - 1, 9, ($cgi->param('top')||10), 'single', $fid, ($cgi->param('raw') || undef), $noclick);

    $settings .= "<i>$psettings</i><br>";
    # check for p-value calculation
    if (defined($cgi->param('pval'))) {
      $settings_preserve .= "<input type='hidden' name='pval' value='".$cgi->param('pval')."'>";
      $settings_preserve .= "<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'>";
      my $mg2group = {};
      map { my ($g, $m) = split /\^/; $mg2group->{$m} = $g; } split /\|/, $cgi->param('pval');
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my ($pvalgroupf, $pvalgroupn) = tempfile( "rpvalgXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalgroupf join("\t", map { $mg2group->{$_} } @comp_mgs)."\n";
      close $pvalgroupf;
      my ($pvaldataf, $pvaldatan) = tempfile( "rpvaldXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvaldataf "\t".join("\t", map { "ID".$_ } @comp_mgs)."\n";
      my $cats = $dom_v->datasets();
      my $pd = $dom_v->data();
      my $i = 0;
      foreach my $row (@$pd) {
	print $pvaldataf $cats->[$i]."\t".join("\t", map { $_->[0] } @$row)."\n";
	$i++;
      }
      close $pvaldataf;
      my ($pvalsuggestf, $pvalsuggestn) = tempfile( "rpvalsXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalsuggestf;
      my ($pvalresultf, $pvalresultn) = tempfile( "rpvalrXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalresultf;
      my ($pvalexecf, $pvalexecn) = tempfile( "rpvaleXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      my $rn = "normalized";
      if ($cgi->param('raw')) {
	$rn = "raw";
      }
      print $pvalexecf "source(\"".$Conf::bin."/suggest_stat_test.r\")\n";
      print $pvalexecf "MGRAST_suggest_test(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", paired = FALSE, file_out = \"".$pvalsuggestn."\")\n";
      close $pvalexecf;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $pvalexecn`;
      open(FH, $pvalsuggestn);
      my $res = <FH>;
      chomp $res;
      close FH;
      $settings .= "<br><i>The p-values were calculated using $res and the following groups:</i><br>";
      $settings .= "<table><tr><th>metagenome</th><th>group</th></tr>";
      foreach my $cmg (@comp_mgs) {
	$settings .= "<tr><td>$cmg</td><td>".$mg2group->{$cmg}."</td></tr>";
      }
      $settings .= "</table><br>";
      my ($pvalexec2f, $pvalexec2n) = tempfile( "rpvale2XXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalexec2f "source(\"".$Conf::bin."/do_stats.r\")\n";
      print $pvalexec2f "MGRAST_do_stats(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", sig_test = \"".$res."\", file_out = \"".$pvalresultn."\")\n";
      close $pvalexec2f;
      `$R --vanilla --slave < $pvalexec2n`;
      open(FH, $pvalresultn);
      my $header = <FH>;
      my $pval_data = {};
      while (<FH>) {
	chomp;
	my @row = split /\t/;
	my $name = substr($row[0], 1, length($row[0])-2);
	my $stat = $row[scalar(@row)-2];
	my $pval = $row[scalar(@row)-1];
	$pval_data->{$name} = [ $stat, $pval ];
      }
      close FH;
      unlink($pvalgroupn);
      unlink($pvaldatan);
      unlink($pvalexecn);
      unlink($pvalexec2n);
      unlink($pvalsuggestn);
      unlink($pvalresultn);
      my $chash = {};
      for (my $i=0; $i<scalar(@$cats); $i++) {
	$chash->{$cats->[$i]} = $pd->[$i];
      }
      
      my $cats_pos = {};
      my $cind = 0;
      foreach my $k (@$cats) {
	$cats_pos->{$k} = $cind;
	$cind++;
      }

      @$cats = sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);
      @$pd = map { $chash->{$_} } sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);

      $cind = 0;
      foreach my $nc (@$cats) {
	$cats_pos->{$cind} = $cats_pos->{$nc};
	$cind++;
      }
      my $onclicks = $dom_v->data_onclicks;
      my $onclicks_title = $dom_v->title_onclicks;
      my $newonclicks = [];
      my $newonclicks_title = [];
      $cind = 0;
      foreach (@$onclicks) {
	push(@$newonclicks, $onclicks->[$cats_pos->{$cind}]);
	push(@$newonclicks_title, $onclicks_title->[$cats_pos->{$cind}]);
	$cind++;
      }
      $dom_v->data_onclicks($newonclicks);
      $dom_v->title_onclicks($newonclicks_title);

      $dom_v->data($pd);
      foreach my $cat (@$cats) {
	if (exists($pval_data->{$cat})) {
	  $cat = $cat." [".sprintf("%.4f", $pval_data->{$cat}->[1])."]";
	} else {
	  $cat = $cat." [-]";
	}
      }
      $dom_v->datasets($cats);
    }

    # generate a stringified version of the current data for download
    my $download_data = {};
    my $ii = 0;
    foreach my $bgroup (@{$dom_v->data}) {
      my $hh = 0;
      foreach my $bmg (@$bgroup) {
	my $jj = 0;
	foreach my $bsource (@$bmg) {
	  unless (exists($download_data->{$dom_v->supersets->[$jj]})) {
	    $download_data->{$dom_v->supersets->[$jj]} = {};
	  }
	  unless (exists($download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]})) {
	    $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]} = {};
	  }
	  $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]}->{$dom_v->subsets->[$hh]} = $bsource;
	  $jj++;
	}
	$hh++;
      }
      $ii++;
    }
    my $download_data_string = "";
    foreach my $key (sort(keys(%$download_data))) {
      $download_data_string .= "$key\\n";
      $download_data_string .= "\\t".join("\\t", sort(@{$dom_v->subsets}))."\\n";
      foreach my $k2 (sort(keys(%{$download_data->{$key}}))) {
	$download_data_string .= $k2."\\t".join("\\t", map { $download_data->{$key}->{$k2}->{$_} } sort(keys(%{$download_data->{$key}->{$k2}})))."\\n";
      }
      $download_data_string .= "\\n";
    }

    $download_data_string =~ s/'/\&rsquo\;/g;
    $download_data_string =~ s/"/\&rdquo\;/g;

    if ($level == 2) {
      $content .= "<div><div>Representative Organism Barchart $tabnum</div><div>";
      my $selnorm = "";
      if (defined($cgi->param('raw'))) {
	$content = "<div>";
	if ($cgi->param('raw') == '1') {
	  $selnorm = " selected=selected";
	}
      }
      $content .= "<form id='single_drilldown$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='single_bar_sel'><input type='hidden' name='single_bar_col'><input type='hidden' name='fid'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'></form>";
      $content .= clear_progress_image()."$settings<br>";
      $content .= "<form id='single_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<div>You can redraw this barchart with different options:<br><br><table><tr><td rowspan=2 style='width: 50px;'>&nbsp;</td><td>use <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values</td><td rowspan=2 style='vertical-align: bottom; padding-left: 15px;'><input type='button' value='draw' onclick='execute_ajax(\"single_visual\", \"tab_div_".($tabnum+1)."\", \"single_redraw$fid\");'></td></tr><tr><td><input type='checkbox' value='' name='pval' onclick='check_group_selection(this, \"$tabnum\")'> calculate p-values</td></tr></table></div></form>";
      if (! defined($cgi->param('raw')) || ($cgi->param('raw') == '0')) {
	$content .= "The displayed data has been normalized to values between 0 and 1 to allow for comparison of differently sized samples.";
      }
      $content .= "<br><br>Click on a bar to drill down to the selected category (i.e. ".$vbardata->[0]->[2].")<br><br><div style='position: relative; float: right;'>".$dom_v->legend."</div><h3 style='margin-top: 0px;'>Domain Distribution <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'></h3>".$dom_v->output."<br><div id='3_$fid'></div></div></div>";
      $tabnum++;
    } else {
      my $header_names = { 3 => 'Phylum',
			   4 => 'Class',
			   5 => 'Order', 
			   6 => 'Family',
			   7 => 'Genus',
			   8 => 'Species',
			   9 => 'Strain' };
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my $md5s = {};
      foreach my $row (@$vbardata) {
	if ($row->[$level - 1] eq $cgi->param('single_bar_sel')) {
	  my @currmd5s = split /;/, $row->[scalar(@$row) - 1];
	  foreach my $cmd5 (@currmd5s) {
	    $md5s->{$cmd5} = 1;
	  }
	}
      }
      return clear_progress_image()."<h3 style='margin-top: 0px;'>".$header_names->{$level}." Distribution (".$cgi->param('single_bar_sel').") <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'> <input type='button' value='to workbench' onclick='buffer_data(\"barchart\", \"$level$fid\", \"$source phylogenetic\", \"".$cgi->param('single_bar_sel')."\", \"0\", \"".join(";",$cgi->param('source'))."\");'></h3></a>".$dom_v->output."<br><input type='hidden' id='$level$fid\_md5s' value='".join(";", keys(%$md5s))."'><input type='hidden' id='$level$fid\_mgids' value='".join(";", @comp_mgs)."'><div id='".(int($level)+1)."_$fid'></div>";
    }
  }
  
  if ($cgi->param('vis_type') eq 'tree') {
    @comp_mgs = $cgi->param('comparison_metagenomes');
    my $pt = $self->application->component('tree1');
    ## nasty id manipulation to allow for multiple trees
    my $newid = int(rand(100000));
    if ($cgi->param('oldid')) {
      $newid = $cgi->param('oldid');
    }
    $self->application->component('PhyloTreeHoverComponent'.$pt->id)->id($newid);
    $self->application->{component_index}->{'PhyloTreeHoverComponent'.$newid} = $self->application->component('PhyloTreeHoverComponent'.$pt->id);
    $self->application->component('HoverPie'.$pt->id)->id($newid);
    $self->application->{component_index}->{'HoverPie'.$newid} = $self->application->component('HoverPie'.$pt->id);
    $pt->id($newid);
    $pt->sample_names( [ $comp_mgs[0] ] );
    $pt->leaf_weight_type($cgi->param('lwt') || 'stack');
    $pt->show_tooltip(0);
    ##
    my $tree_domain_filter = 0;
    if ($cgi->param('tree_domain') && $cgi->param('tree_domain') ne 'all') {
      $tree_domain_filter = $cgi->param('tree_domain');
    }
    my $expanded_data = [];
    if (scalar(@comp_mgs) > 1) {
      $pt->coloring_method('split');
      $pt->sample_names( [ @comp_mgs ] );
      my $exp_hash = {};
      my $spec_hash = {};
      my $mg2num = {};

      for (my $hh=0; $hh<scalar(@comp_mgs); $hh++) {
	$mg2num->{$comp_mgs[$hh]} = $hh;
      }
      foreach my $row (@$data) {
	next if ($tree_domain_filter && $tree_domain_filter ne $row->[1]);
	$spec_hash->{$row->[8]} = [ @$row[1..8] ];
	unless (exists($exp_hash->{$row->[8]})) {
	  $exp_hash->{$row->[8]} = [];
	}
	$exp_hash->{$row->[8]}->[$mg2num->{$row->[0]}] = $row->[9];
      }
      foreach my $key (sort(keys(%$exp_hash))) {
	my $vals = [];
	for (my $ii=0; $ii<scalar(@comp_mgs); $ii++) {
	  push(@$vals, $exp_hash->{$key}->[$ii] || 0);
	}
	my $row = $spec_hash->{$key};
	#foreach my $r (@$row) {
	#  if ($r =~ /derived/) {
	#    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	#  }
	#}
	push(@$expanded_data, [ @$row, $vals ] );
      }    
    } else {
      foreach my $row (@$data) {
	next if ($tree_domain_filter && $tree_domain_filter ne $row->[1]);
	#foreach my $r (@$row) {
	#  if ($r =~ /derived/) {
	#    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	#  }
	#}
	push(@$expanded_data, [ @$row[1..9] ] );
      }
    }
    @$expanded_data = sort { $b->[8] <=> $a->[8] } @$expanded_data;
    $pt->data($expanded_data);
    $pt->show_leaf_weight(1);
    $pt->show_titles(1);
    $pt->shade_titles($cgi->param('title_level') || 2);
    $pt->enable_click(1);
    $pt->size(1000);
    $pt->depth($cgi->param('depth') || 4);
    $pt->level_distance(40);
    $pt->leaf_weight_space(60);
    $pt->color_leafs_only(1);
    $pt->reroot_field("reroot$tabnum");
    my $md5sel = "";
    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      $pt->reroot_id($self->application->cgi->param('reroot'));
    }

    if ($cgi->param('high_res')) {
      print $cgi->header(-charset => 'UTF-8');
      print $cgi->start_html();
      $pt->size(2500);
      $pt->level_distance(100);
      $pt->leaf_weight_space(150);
      $pt->enable_click(0);
      $pt->title_space(750);
      $pt->font_size($cgi->param('pts') || 20);
      $pt->{thick2} = 5;
      $pt->{thick} = 15;
      $pt->{style} = "width: 800; height: 800;";
      print $pt->output();
      print $cgi->end_html();
      exit;
    }
    
    my $pt_out = $pt->output;
    $pt_out = "<table><tr><td>".$pt->legend."</td><td>".$pt_out."</td></tr></table>";
    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      my $tmd5s = {};
      my $rootnode = $pt->{nodes}->{$self->application->cgi->param('reroot')};
      my $lineage = [ split(/; /, $rootnode->{lineage}) ];
      foreach my $row (@$data) {
	my $fits = 1;
	for (my $i=1; $i<scalar(@$lineage); $i++) {
	  if ($lineage->[$i] ne $row->[$i+2]) {
	    $fits = 0;
	    last;
	  }
	}
	if ($fits) {
	  foreach my $md5 (split(/;/, $row->[16])) {
	    $tmd5s->{$md5} = 1;
	  }
	}
      }
      $md5sel = "<br><br><input type='hidden' id='".$tabnum."_mgids' value='".join(";", @comp_mgs)."'><input type='hidden' id='".$tabnum."_md5s' value='".join(";", keys(%$tmd5s))."'><input type='button' value='to workbench' onclick='buffer_data(\"tree\", \"$tabnum\", \"organism classification\", \"".$rootnode->{name}."\", \"0\", \"".join(";",$cgi->param('source'))."\");'>";
    }
    my $opts = [ [ 2, 'phylum' ],
		 [ 3, 'class' ],
		 [ 4, 'order' ],
		 [ 5, 'family' ],
		 [ 6, 'genus' ],
		 [ 7, 'species' ],
		 [ 8, 'strain' ] ];
    my $explain = "Color shading of the ".$opts->[$pt->depth - 1]->[1]." names indicates ".$opts->[$pt->shade_titles - 1]->[1]." membership.";
    $explain .= " Hover over a node to view the distributions of the children of the node. Click on a node to get distributions of the entire hierarchy of this node. If you have selected a node, you can reroot the tree by checking the reroot checkbox and clicking the 'change' button. Clicking the change button with the reroot checkbox unchecked will draw the entire tree.$md5sel";
    my $change_settings_form = "<form id='pt_form$newid'>$settings_preserve<input type='hidden' name='vis_type' value='tree'><input type='hidden' name='recalc' value='1'><input type='hidden' name='oldid' value='$newid'>";
    my $check1 = ' checked=checked';
    my $check2 = '';
    if ($cgi->param('lwt') && $cgi->param('lwt') eq 'bar') {
      $check2 = ' checked=checked';
      $check1 = '';
    }
    $change_settings_form .= "<table><tr><td><b>display leaf weights as</b></td><td><input type='radio' name='lwt' value='stack'$check1> stacked bar <br><input type='radio' name='lwt' value='bar'$check2> barchart</td></tr>";
    $change_settings_form .= "<tr><td><b>maximum level</b></td><td><select name='depth'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->depth) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select></td></tr><tr><td><b>color by</b></td><td><select name='title_level'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->shade_titles) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select></td></tr>";
    $change_settings_form .= "<tr><td><b>restrict view to domain</b></td><td><select name='tree_domain'><option value='0'>all</option><option value='Bacteria'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Bacteria' ? " selected=selected" : "").">Bacteria</option><option value='Eukaryota'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Eukaryota' ? " selected=selected" : "").">Eukaryota</option><option value='Archaea'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Archaea' ? " selected=selected" : "").">Archaea</option><option value='Viruses'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Viruses' ? " selected=selected" : "").">Viruses</option></select></td></tr>";
    $change_settings_form .= "<tr><td colspan=2><input type='hidden' name='reroot' value='".($self->application->cgi->param('reroot')||"")."' id='reroot$tabnum'> <input type='checkbox' name='do_reroot'> reroot at selected node</td></tr></table> <input type='button' onclick='execute_ajax(\"single_visual\", \"pt$newid\", \"pt_form$newid\");' value='change'><input type='hidden' name='high_res' value=0 id='pt_highres$newid'><input type='hidden' name='page' value='Analysis'><input type='hidden' name='action' value='single_visual'><input type='button' onclick='var f=document.getElementById(\"pt_form$newid\");f.target=\"_blank\";document.getElementById(\"pt_highres$newid\").value=1;f.submit();' value='create high resolution image'></form>";
    if ($cgi->param('recalc')) {
      return "$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out;
    } else {
      $content .= "<div><div>Representative Organism tree $tabnum</div><div><div id='pt$newid'>".clear_progress_image()."$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out."</div></div></div>";
      $tabnum++;
    }
  }

  if ($cgi->param('vis_type') eq 'heatmap' || $cgi->param('vis_type') eq 'pca') {
    # format the data for .r analysis
    # data = [ mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s ]

    @comp_mgs = ();
    foreach my $mg ( $cgi->param('comparison_metagenomes') ) {
      if (exists $data_mgs{$mg}) {
	push @comp_mgs, $mg;
      }
    }

    if (scalar(@comp_mgs) < 2) {
      return "<div><div>no data</div><div>".clear_progress_image().$missing_txt."Heatmap and PCoA analysis require at least two metagenomes with available data.</div></div>";
    } else {
      my $heatmap_data = [ [ '', map { my $x = $_; $x =~ s/\./A/; "ID".$x } @comp_mgs ] ];
      my $hashed_data = {};
      my $mg_ind = {};
      for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	$mg_ind->{$comp_mgs[$i]} = $i;
      }
      if (defined($cgi->param('heatmap_level'))) {
	$cgi->param('heatmap_level', $cgi->param('heatmap_level') + 1);
      }
      my $level = $cgi->param('heatmap_level') || 3;
      $level--;
      my $dd_col;
      my $dd_val;
      if ($cgi->param('drilldown') && $cgi->param('drilldown_on')) {
	($dd_col, $dd_val) = split(/;/, $cgi->param('drilldown'));
      }
      foreach my $d (@$data) {
	if (defined($dd_col)) {
	  next unless ($d->[$dd_col] eq $dd_val);
	}
	next unless ($d->[$level]);
	if (exists($hashed_data->{$d->[$level]})) {
	  if ($hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}]) {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] += $d->[9];
	  } else {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[9];
	  }
	} else {
	  $hashed_data->{$d->[$level]} = [];
	  $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[9];
	}
      }
      foreach my $key (keys(%$hashed_data)) {
	my $row = [ $key ];
	foreach my $mg (@comp_mgs) {
	  if ($hashed_data->{$key}->[$mg_ind->{$mg}]) {
	    push(@$row, $hashed_data->{$key}->[$mg_ind->{$mg}]);
	  } else {
	    push(@$row, 0);
	  }
	}
	push(@$heatmap_data, $row);
      }

      # write data to a tempfile
      my ($fh, $infile) = tempfile( "rdataXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      foreach my $row (@$heatmap_data) {
	print $fh join("\t", @$row)."\n";
      }
      close $fh;
      chmod 0666, $infile;

      # preprocess data
      my $time = time;
      my $boxfile = "rdata.boxplot.$time.png";
      my ($prefh, $prefn) =  tempfile( "rpreprocessXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $prefh "source(\"".$Conf::bin."/norm_deseq.r\")\n";
      print $prefh "MGRAST_preprocessing(file_in = \"".$infile."\", file_out = \"".$Conf::temp."/rdata.preprocessed.$time\", image_out =\"".$Conf::temp."/$boxfile\", produce_fig = \"TRUE\")\n";
      close $prefh;

      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $prefn`;
      unlink($prefn);
      
      unless (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) {
	unlink $infile;
	$infile = $Conf::temp."/rdata.preprocessed.$time";
      }
      
      if ($cgi->param('vis_type') eq 'heatmap') {
	my $level_names = [ [ 1, 'domain' ],
			    [ 2, 'phylum' ],
			    [ 3, 'class' ],
			    [ 4, 'order' ],
			    [ 5, 'family' ],
			    [ 6, 'genus' ],
			    [ 7, 'species' ],
			    [ 8, 'strain' ] ];
	my $dd_sel = "";
	my $hm_level_select = "<select name='heatmap_level'>";
	foreach my $l (@$level_names) {
	  my $sel = "";
	  if ($l->[0] == $level) {
	    $sel = " selected=selected";
	  }	  
	  if (defined($dd_col) && ($l->[0] == $dd_col)) {
	    $dd_sel = $l->[1];
	  }
	  $hm_level_select .= "<option value='".$l->[0]."'$sel>".$l->[1]."</option>";
	}
	$hm_level_select .= "</select>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "<div><div>Representative Organism Heatmap $tabnum</div><div>".clear_progress_image();
	}
	$content .= "<form id='heat_drilldown$fid' onkeypress='return event.keyCode!=13'>$settings<br>The heatmap was clustered using ".($cgi->param('heatmap_clust_method') || 'ward')." with ".($cgi->param('heatmap_dist_method') || 'bray-curtis')." distance metric.<br>group heatmap by $hm_level_select <input type='hidden' name='vis_type' value='heatmap'><input type='hidden' id='tabnum2$fid' name='tabnum' value='".($tabnum+1)."'><br>";

	my $selnorm = "";
	if ($cgi->param('raw')) {
	  $selnorm = " selected=selected";
	}
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('heatmap_dist_method') && ($cgi->param('heatmap_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	my $clustopts = "";
	foreach my $d (@{$self->cluster_methods}) {
	  my $sel = ($cgi->param('heatmap_clust_method') && ($cgi->param('heatmap_clust_method') eq $d)) ? " selected=selected" : "";
	  $clustopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values, <select name='heatmap_clust_method'>$clustopts</select> clustering and <select name='heatmap_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"single_visual\", \"tab_div_".($tabnum+1)."\", \"heat_drilldown$fid\");'></div></form>";

	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"heatmap_canvas_$tabnum\");document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"\";'></div>";

	my ($col_f, $row_f) = ($Conf::temp."/rdata.col.$time", $Conf::temp."/rdata.row.$time");

	my ($heath, $heatn) =  tempfile( "rheatXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $heath "source(\"".$Conf::bin."/dendrogram.r\")\n";
	print $heath "MGRAST_dendrograms(file_in = \"".$infile."\", file_out_column = \"".$col_f."\", file_out_row = \"".$row_f."\", dist_method = \"".($cgi->param('heatmap_dist_method') || 'bray-curtis')."\", clust_method = \"".($cgi->param('heatmap_clust_method') || 'ward')."\", produce_figures = \"FALSE\")\n";
	close $heath;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $heatn`; 
	unlink($heatn);

	open(COL, "<$col_f");
	my $tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='columns_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";

	$tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='column_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='column_den_$tabnum' type='hidden' value='";
	while (<COL>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\s+/;
	}
	$content .= "'>";	

	close(COL);
	unlink($col_f);

	open(ROW, "<$row_f");
	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='rows_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";

	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='row_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='row_den_$tabnum' type='hidden' value='";
	while (<ROW>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\t/;	
	}
	$content .= "'>";
	
	close(ROW);
	unlink($row_f);

	open(D, "<$infile");
	my @values = 0;
	my $cdata = "category\t".join("\t", @comp_mgs)."\n";
	my $junk = <D>;

	$content .= "<input id='table_$tabnum' type='hidden' value='";
	while(<D>){
	  $cdata .= $_;
	  chomp;
	  my ($junk, $data) = split /\t/, $_, 2;
	  my @set = split /\t/, $data;
	  push @values, @set;
	  $content .= "@";
	  $content .= join "^", @set;
	}
	$content .= "'>";
	close(D);
	unlink $infile;

	$cdata =~ s/'/ /g;

	$content .= "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='$cdata'><input type='submit' value='download values used to generate this figure'></form>";

	my $max_val = max @values;
	$max_val  = ($max_val < 1) ? 1 : $max_val;
	$content .= $self->heatmap_scale($max_val)."<div id='heatmap_canvas_$tabnum'></div>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_heatmap(\"heatmap_canvas_$tabnum\", \"$tabnum\", \"$max_val\"); document.getElementById(\"progress_div\").innerHTML=\"\";'/>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "</div></div>";
	}
	$tabnum++;
      }
      if ($cgi->param('vis_type') eq 'pca') {
	my $time = time;
	my ($pca_data) = ($Conf::temp."/rdata.pca.$time");
	my ($pcah, $pcan) =  tempfile( "rpcaXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $pcah "source(\"".$Conf::bin."/plot_pco.r\")\n";
	print $pcah "MGRAST_plot_pco(file_in = \"".$infile."\", file_out = \"".$pca_data."\", dist_method = \"".($cgi->param('pca_dist_method') || 'bray-curtis')."\", headers = 1)\n";
	close $pcah;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $pcan`; 
	unlink($pcan);
	if (! defined($cgi->param('raw'))) {
	  $content .= "<div><div>Representative Organism PCoA $tabnum</div><div>";
	}
	$content .= "$settings<i>$psettings</i><br><br>";

	my $selnorm  = (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) ? " selected=selected" : "";
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('pca_dist_method') && ($cgi->param('pca_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "<form id='single_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='pca'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values and <select name='pca_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"single_visual\", \"tab_div_".($tabnum+1)."\", \"single_redraw$fid\");'></div></form>";
	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"pca_canvas_$tabnum\");document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"\";'></div>";

	my (@comp, @items);

	open(D, "<$pca_data");
	while(<D>){
	  chomp;
	  s/"//g; #"
	  my @fields = split /\t/;
	  if ($fields[0] =~ /^PCO\d+$/) {
	    push @comp, join("^", @fields); 
	  } elsif ($fields[0] =~ /^ID([\dA]+)$/) {
	    push @items, join("^", @fields); 
	  }
	}
	close(D);

	# metadata coloring	
	my $mddb  = MGRAST::Metadata->new;
	my $jobmd = $mddb->get_metadata_for_tables(\@comp_mgs, 1, 1);
	my $mdata = {};
	# get unique labels accross all metagenomes
	foreach my $mgid (@comp_mgs) {
	    next unless ($jobmd->{$mgid});
	    foreach my $md (@{$jobmd->{$mgid}}) {
	        next if ($md->[1] =~ /(_id|_name)$/);
	        next if ($md->[1] =~ /^PI_/);
	        $mdata->{$md->[1]}{$mgid} = $md->[2];
        }
    }
    my @md_names = sort keys %$mdata;
    my $mgmd = [];
	my $iii  = 0;
    # get values for each metagenome
    foreach my $mgid (@comp_mgs) {
	    foreach my $md (@md_names) {
	        my $val = (exists($mdata->{$md}{$mgid}) && ($mdata->{$md}{$mgid} ne '')) ? $mdata->{$md}{$mgid} : undef;
            if ($val) { $val =~ s/'//g; }
            push @{ $mgmd->[$iii] }, $val;
        }
        $iii += 1;
    }
    
	my $md_type_select = "<select id='whichmd_".$tabnum."' onchange='check_metadata(\"$tabnum\", this);'>";
	foreach my $md_name (@md_names) {
	  $md_type_select .= "<option value='$md_name'>$md_name</option>";
	}
	$md_type_select .= "</select><input type='button' value='apply' onclick='color_by_metadata(\"$tabnum\");'>";

	my $comp_control = "<br><br><br><br><table><tr><th>component</th><th>r^2</th><th>x-axis</th><th>y-axis</th></tr>";
	my $i = 0;
	foreach my $row (@comp) {
	  my ($pcname, $rsquare) = split /\^/, $row;
	  $rsquare = sprintf("%.5f", $rsquare);
	  my $sel_x = '';
	  my $sel_y = '';
	  if ($i == 0) {
	    $sel_x = " checked=checked";
	  }
	  if ($i == 1) {
	    $sel_y = " checked=checked";
	  }
	  $comp_control .= "<tr><td>$pcname</td><td>$rsquare</td><td><input type='radio' name='xcomp$tabnum' id='xcomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_x></td><td><input type='radio' name='ycomp$tabnum' id='ycomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_y></td></tr>";
	  $i++;
	}
	$comp_control .= "</table>";

	my $group_control = "<div id='grpctrl$tabnum' style='display: none;'><br><br><br><div id='feedback$tabnum'></div><table><tr><th>group</th><th>name</th><th style='width: 56px;'>save as collection</th></tr>";
	$group_control .= "<tr><td>group 1</td><td><input type='text' id='group1_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"1\");'></td></tr>";
	$group_control .= "<tr><td>group 2</td><td><input type='text' id='group2_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"2\");'></td></tr>";
	$group_control .= "<tr><td>group 3</td><td><input type='text' id='group3_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"3\");'></td></tr>";
	$group_control .= "<tr><td>group 4</td><td><input type='text' id='group4_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"4\");'></td></tr>";
	$group_control .= "<tr><td>group 5</td><td><input type='text' id='group5_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"5\");'></td></tr>";
	$group_control .= "<tr><td>group 6</td><td><input type='text' id='group6_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"6\");'></td></tr>";
	$group_control .= "<tr><td>group 7</td><td><input type='text' id='group7_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"7\");'></td></tr>";
	$group_control .= "<tr><td>group 8</td><td><input type='text' id='group8_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"8\");'></td></tr>";
	$group_control .= "<tr><td>group 9</td><td><input type='text' id='group9_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"9\");'></td></tr>";
	$group_control .= "<tr><td>group 10</td><td><input type='text' id='group10_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"10\");'></td></tr>";
	$group_control .= "</table></div>";

	my $img_control = "<table><tr><td><div style='cursor: pointer; background-color: #8FBC3F; color: white; font-weight: bold; height: 16px; width: 250px; text-align: center; padding-top: 4px;' onclick='if(document.getElementById(\"imgctrl$tabnum\").style.display==\"none\"){document.getElementById(\"imgctrl$tabnum\").style.display=\"\";document.getElementById(\"grpctrl$tabnum\").style.display=\"\";}else{document.getElementById(\"imgctrl$tabnum\").style.display=\"none\";document.getElementById(\"grpctrl$tabnum\").style.display=\"none\";}' title='click to expand'>PCoA grouping control</div></td></tr><tr><td id='imgctrl$tabnum' style='display: none;'>";
	$img_control .= "<table><tr><td><div style='width: 280px;'><b>create a grouping</b><br>You can create a grouping of your metagenomes to calculate p-values in the barchart visualization. Select a group and click the metagenome circle in the graphic. You can also drag open a square to select multiple metagenomes at a time.</div><br><br>mark clicked as <select id='group_color$tabnum'><option value='red' selected=selected>group 1</option><option value='green'>group 2</option><option value='cyan'>group 3</option><option value='purple'>group 4</option><option value='yellow'>group 5</option><option value='blue'>group 6</option><option value='orange'>group 7</option><option value='gray'>group 8</option><option value='black'>group 9</option><option value='magenta'>group 10</option></select><br><br>or select groups in the table to the right.</td><td>";
	$img_control .= "<table><tr><th>Metagenome</th><th>group</th><th>$md_type_select</th></tr>";
	my $opts = "<option value='0'>- no group -</option><option value='group1'>group 1</option><option value='group2'>group 2</option><option value='group3'>group 3</option><option value='group4'>group 4</option><option value='group5'>group 5</option><option value='group6'>group 6</option><option value='group7'>group 7</option><option value='group8'>group 8</option><option value='group9'>group 9</option><option value='group10'>group 10</option>";
	for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	  $img_control .= "<tr><td>".($comp_mgs[$i] || '')."</td><td><select id='group_list".$tabnum."_$i' onchange='change_pca_color(this, \"$tabnum\", \"$i\");'>$opts</select></td><td><span id='group_list_md_".$tabnum."_$i'>".($mgmd->[$i]->[0] || '')."</span></td></tr>";
	}
	$img_control .= "</table>";
	$img_control .= "<input type='button' value='store grouping' onclick='store_grouping(\"$tabnum\", \"".join("^", @comp_mgs)."\");'>";

	$img_control .= "<input type='hidden' id='pcamd_".$tabnum."' value='".join("~~", map { join(";;", map { defined($_) ? $_ : 'unknown' } @$_) } @$mgmd)."'></td></tr></table>";

	$img_control .= "</td></tr></table>";

	my @comp_b = @comp;
	my @items_b = @items;
	my $cmg_hash = {};
	%$cmg_hash = map { my $x = $_; $x =~ s/\./A/; "ID".$x => $_; } @comp_mgs;
	my $data_download_button = "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='PCA Component impact\n".join("\n", map { $_ =~ s/\^/\t/g; $_; } @comp_b)."\n\nData Items\nMetagenome\t".join("\t", map { $_ =~ s/(.*)\t.*/$1/; $_; } @comp_b)."\n".join("\n", map { $_ =~ s/\^/\t/g; my ($x) = $_ =~ /^([^\t]+)/; $x = $cmg_hash->{$x}; $_ =~ s/^[^\t]+(.*)/$x$1/; $_; } @items_b)."'><input type='submit' value='download values used to generate this figure'></form>";

	$content .= "<input id='pca_components_$tabnum' type='hidden' value='".join("@",@comp)."'>";
	$content .= "<input id='pca_items_$tabnum' type='hidden' value='".join("@",@items)."'>";
	$content .= $img_control;
	$content .= "<table><tr><td><div id='pca_canvas_$tabnum'></div></td><td>$data_download_button".$comp_control.$group_control."</td></tr></table>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_pca(\"pca_canvas_$tabnum\", \"$tabnum\", 1,2); document.getElementById(\"progress_div\").innerHTML=\"\";'/>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "</div></div>";
	}
	$tabnum++;
      }
    }
  }

  return $content;
}

sub phylogeny_visual {
  my ($self) = @_;

  my $content = "";
  my $cgi = $self->application->cgi;
  my ($md5_abund, $data) = $self->phylogenetic_data();
  #return "<div><div>test</div><div><pre>".clear_progress_image().Dumper($data)."</pre></div></div>";
  # mgid => md5 => abundance
  # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  my $tabnum = $cgi->param('tabnum') || 2;
  $tabnum--;

  unless (scalar(@$data)) {
    return "<div><div>no data</div><div>".clear_progress_image()."The visualizations you requested cannot be drawn, as no data met your selection criteria.</div></div>";
  }

  my %buffer_md5s = $cgi->param('use_buffer') ? map {$_, 1} split(/;/, $cgi->param('use_buffer')) : ();
  my $settings_preserve = "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'>";
  my @comp_mgs = $cgi->param('comparison_metagenomes');
  if ($cgi->param('mg_grp_sel') && $cgi->param('mg_grp_sel') eq 'groups') {
    $settings_preserve .= "<input type='hidden' name='mg_grp_sel' value='groups'>";
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_collections' value='".$mg."'>";
    }
  } else {
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_metagenomes' value='".$mg."'>";
    }
  }
  my $mgs = "";
  my $mgnames = [];
  @$mgnames = @comp_mgs;
  foreach my $metagenome (@$mgnames) {
    my $mgname = '';
    unless ($cgi->param('comparison_collections')) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
      $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
    }
  }
  if (scalar(@$mgnames) > 1) {
    my $last = pop(@$mgnames);
    $mgs .= "metagenomes ".join(", ", @$mgnames)." and $last";
  } else {
    $mgs .= "metagenome ".$mgnames->[0];
  }
  my $sorcs = "";
  my @sources = $cgi->param('source');
  foreach my $source (@sources) {
    $settings_preserve .= "<input type='hidden' name='source' value='".$source."'>";
  }
  if (scalar(@sources) > 1) {
    my $last = pop(@sources);
    $sorcs = join(", ", @sources)." and $last";
  } else {
    $sorcs = $sources[0];
  }
  my $cutoffs = "a maximum e-value of 1e-" . ($cgi->param('evalue') || '0') . ", ";
  $cutoffs   .= "a minimum identity of " . ($cgi->param('identity') || '0') . " %, ";
  $cutoffs   .= "and a minimum alignment length of " . ($cgi->param('alength') || '1') . ' measured in aa for protein and bp for RNA databases';

  my $psettings = " The data has been normalized to values between 0 and 1. If you would like to view raw values, redraw using the form below.";
  if ($cgi->param('raw')) {
    $psettings = " The data is showing raw values. If you would like to view normalized values, redraw using the form below.";
  }
  my $pset = "";
  if (defined($cgi->param('pval'))) {
    $pset = "<br><br>You have chosen to calculate p-values. They will appear in brackets after the category name.";
  }

  if ($cgi->param('use_buffer')) {
    $settings_preserve .= "<input type='hidden' name='use_buffer' value='".$cgi->param('use_buffer')."'>";
  }
  $settings_preserve .= "<input type='hidden' name='evalue' value='"   . ($cgi->param('evalue') || '0')   . "'>";
  $settings_preserve .= "<input type='hidden' name='identity' value='" . ($cgi->param('identity') || '0') . "'>";
  $settings_preserve .= "<input type='hidden' name='alength' value='"  . ($cgi->param('alength') || '1')  . "'>";
  my $fid = $cgi->param('fid') || int(rand(1000000));
    
  my $settings = "<i>This data was calculated for $mgs. The data was compared to $sorcs using $cutoffs.$pset</i><br/>";

  ## determine if any metagenomes missing from results
  my $missing_txt = "";
  my @missing_mgs = ();
  my %data_mgs    = map { $_->[0], 1 } @$data;

  foreach my $mg (@comp_mgs) {
    if (! exists $data_mgs{$mg} && ! $cgi->param('comparison_collections')) {
      push @missing_mgs, $mg;
    }
  }  

  if (@missing_mgs > 0) {
    $missing_txt = "<br>";
    foreach my $mg (@missing_mgs) {
      my $mgname = '';
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
      if (ref($job)) {
	$mgname = $job->name()." ($mg)";
      }
      $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>";
    }
    if (@missing_mgs > 1) {
      my $last = pop @missing_mgs;
      $missing_txt .= "Metagenomes " . join(", ", @missing_mgs) . " and $last contain";
    } else {
      $missing_txt .= "Metagenome " . $missing_mgs[0] . " contains";
    }
    $missing_txt .= " no organism data for the above selected sources and cutoffs. They are being excluded from the analysis.<br>";
  }
  $settings .= $missing_txt;

  if ($cgi->param('vis_type') eq 'vbar') {
    my $vbardata = [];
    if ($cgi->param('phylo_bar_sel') && $cgi->param('phylo_bar_col')) {
      @$vbardata = map { ($_->[$cgi->param('phylo_bar_col')] && ($_->[$cgi->param('phylo_bar_col')] eq $cgi->param('phylo_bar_sel'))) ? $_ : () } @$data;
    } else {
      @$vbardata = map { $_ } @$data;
    }
    my $level = $cgi->param('phylo_bar_col') ? ($cgi->param('phylo_bar_col') + 1) : 2;
    my $noclick;
    if ($level > 8) {
      $noclick = 1;
    }

    my $dom_v = $self->data_to_vbar($md5_abund, $vbardata, $level, 10, ($cgi->param('top')||10), 'phylo', $fid, undef, $noclick);

    $settings .= "<i>$psettings</i><br>";
    # check for p-value calculation
    if (defined($cgi->param('pval'))) {
      $settings_preserve .= "<input type='hidden' name='pval' value='".$cgi->param('pval')."'>";
      $settings_preserve .= "<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'>";
      my $mg2group = {};
      map { my ($g, $m) = split /\^/; $mg2group->{$m} = $g; } split /\|/, $cgi->param('pval');
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my ($pvalgroupf, $pvalgroupn) = tempfile( "rpvalgXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalgroupf join("\t", map { $mg2group->{$_} } @comp_mgs)."\n";
      close $pvalgroupf;
      my ($pvaldataf, $pvaldatan) = tempfile( "rpvaldXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvaldataf "\t".join("\t", map { "ID".$_ } @comp_mgs)."\n";
      my $cats = $dom_v->datasets();
      my $pd = $dom_v->data();
      my $i = 0;
      foreach my $row (@$pd) {
	print $pvaldataf $cats->[$i]."\t".join("\t", map { $_->[0] } @$row)."\n";
	$i++;
      }
      close $pvaldataf;
      my ($pvalsuggestf, $pvalsuggestn) = tempfile( "rpvalsXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalsuggestf;
      my ($pvalresultf, $pvalresultn) = tempfile( "rpvalrXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalresultf;
      my ($pvalexecf, $pvalexecn) = tempfile( "rpvaleXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      my $rn = "normalized";
      if ($cgi->param('raw')) {
	$rn = "raw";
      }
      print $pvalexecf "source(\"".$Conf::bin."/suggest_stat_test.r\")\n";
      print $pvalexecf "MGRAST_suggest_test(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", paired = FALSE, file_out = \"".$pvalsuggestn."\")\n";
      close $pvalexecf;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $pvalexecn`;
      open(FH, $pvalsuggestn);
      my $res = <FH>;
      chomp $res;
      close FH;
      $settings .= "<br><i>The p-values were calculated using $res and the following groups:</i><br>";
      $settings .= "<table><tr><th>metagenome</th><th>group</th></tr>";
      foreach my $cmg (@comp_mgs) {
	$settings .= "<tr><td>$cmg</td><td>".$mg2group->{$cmg}."</td></tr>";
      }
      $settings .= "</table><br>";
      my ($pvalexec2f, $pvalexec2n) = tempfile( "rpvale2XXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalexec2f "source(\"".$Conf::bin."/do_stats.r\")\n";
      print $pvalexec2f "MGRAST_do_stats(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", sig_test = \"".$res."\", file_out = \"".$pvalresultn."\")\n";
      close $pvalexec2f;
      `$R --vanilla --slave < $pvalexec2n`;
      open(FH, $pvalresultn);
      my $header = <FH>;
      my $pval_data = {};
      while (<FH>) {
	chomp;
	my @row = split /\t/;
	my $name = substr($row[0], 1, length($row[0])-2);
	my $stat = $row[scalar(@row)-2];
	my $pval = $row[scalar(@row)-1];
	$pval_data->{$name} = [ $stat, $pval ];
      }
      close FH;
      unlink($pvalgroupn);
      unlink($pvaldatan);
      unlink($pvalexecn);
      unlink($pvalexec2n);
      unlink($pvalsuggestn);
      unlink($pvalresultn);
      my $chash = {};
      for (my $i=0; $i<scalar(@$cats); $i++) {
	$chash->{$cats->[$i]} = $pd->[$i];
      }
      
      my $cats_pos = {};
      my $cind = 0;
      foreach my $k (@$cats) {
	$cats_pos->{$k} = $cind;
	$cind++;
      }

      @$cats = sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);
      @$pd = map { $chash->{$_} } sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);

      $cind = 0;
      foreach my $nc (@$cats) {
	$cats_pos->{$cind} = $cats_pos->{$nc};
	$cind++;
      }
      my $onclicks = $dom_v->data_onclicks;
      my $onclicks_title = $dom_v->title_onclicks;
      my $newonclicks = [];
      my $newonclicks_title = [];
      $cind = 0;
      foreach (@$onclicks) {
	push(@$newonclicks, $onclicks->[$cats_pos->{$cind}]);
	push(@$newonclicks_title, $onclicks_title->[$cats_pos->{$cind}]);
	$cind++;
      }
      $dom_v->data_onclicks($newonclicks);
      $dom_v->title_onclicks($newonclicks_title);

      $dom_v->data($pd);
      foreach my $cat (@$cats) {
	if (exists($pval_data->{$cat})) {
	  $cat = $cat." [".sprintf("%.6f", $pval_data->{$cat}->[1])."]";
	} else {
	  $cat = $cat." [-]";
	}
      }
      $dom_v->datasets($cats);
    }

    # generate a stringified version of the current data for download
    my $download_data = {};
    my $ii = 0;
    foreach my $bgroup (@{$dom_v->data}) {
      my $hh = 0;
      foreach my $bmg (@$bgroup) {
	my $jj = 0;
	foreach my $bsource (@$bmg) {
	  unless (exists($download_data->{$dom_v->supersets->[$jj]})) {
	    $download_data->{$dom_v->supersets->[$jj]} = {};
	  }
	  unless (exists($download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]})) {
	    $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]} = {};
	  }
	  $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]}->{$dom_v->subsets->[$hh]} = $bsource;
	  $jj++;
	}
	$hh++;
      }
      $ii++;
    }
    my $download_data_string = "";
    foreach my $key (sort(keys(%$download_data))) {
      $download_data_string .= "$key\\n";
      $download_data_string .= "\\t".join("\\t", sort(@{$dom_v->subsets}))."\\n";
      foreach my $k2 (sort(keys(%{$download_data->{$key}}))) {
	$download_data_string .= $k2."\\t".join("\\t", map { $download_data->{$key}->{$k2}->{$_} } sort(keys(%{$download_data->{$key}->{$k2}})))."\\n";
      }
      $download_data_string .= "\\n";
    }
    $download_data_string =~ s/'/\&rsquo\;/g;
    $download_data_string =~ s/"/\&rdquo\;/g;

    if ($level == 2) {
      $content .= "<div><div>Organism barchart $tabnum</div><div>";
      my $selnorm = "";
      if (defined($cgi->param('raw'))) {
	$content = "<div>";
	if ($cgi->param('raw') == '1') {
	  $selnorm = " selected=selected";
	}
      }
      $content .= "<form id='phylo_drilldown$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='phylo_bar_sel'><input type='hidden' name='phylo_bar_col'><input type='hidden' name='fid'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'></form>";
      $content .= clear_progress_image()."$settings<br>";
      $content .= "<form id='phylo_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<div>You can redraw this barchart with different options:<br><br><table><tr><td rowspan=2 style='width: 50px;'>&nbsp;</td><td>use <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values</td><td rowspan=2 style='vertical-align: bottom; padding-left: 15px;'><input type='button' value='draw' onclick='execute_ajax(\"phylogeny_visual\", \"tab_div_".($tabnum+1)."\", \"phylo_redraw$fid\");'></td></tr><tr><td><input type='checkbox' value='' name='pval' onclick='check_group_selection(this, \"$tabnum\")'> calculate p-values</td></tr></table></div></form>";
      if (! defined($cgi->param('raw')) || ($cgi->param('raw') == '0')) {
	$content .= "The displayed data has been normalized to values between 0 and 1 to allow for comparison of differently sized samples.";
      }
      $content .= "<br><br>Click on a bar to drill down to the selected category (i.e. ".$vbardata->[0]->[2].")<br><br><div style='position: relative; float: right;'>".$dom_v->legend."</div><h3 style='margin-top: 0px;'>Domain Distribution <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'></h3>".$dom_v->output."<br><div id='3_$fid'></div></div></div>";
      $tabnum++;
    } else {
      my $header_names = { 3 => 'Phylum',
			   4 => 'Class',
			   5 => 'Order', 
			   6 => 'Family',
			   7 => 'Genus',
			   8 => 'Species',
			   9 => 'Strain' };
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my $md5s = {};
      foreach my $row (@$vbardata) {
	if ($row->[$level - 1] eq $cgi->param('phylo_bar_sel')) {
	  my @currmd5s = split /;/, $row->[scalar(@$row) - 1];
	  foreach my $cmd5 (@currmd5s) {
	    $md5s->{$cmd5} = 1;
	  }
	}
      }
      return clear_progress_image()."<h3 style='margin-top: 0px;'>".$header_names->{$level}." Distribution (".$cgi->param('phylo_bar_sel').") <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'> <input type='button' value='to workbench' onclick='buffer_data(\"barchart\", \"$level$fid\", \"$sorcs phylogenetic\", \"".$cgi->param('phylo_bar_sel')."\", \"0\", \"".join(";",$cgi->param('source'))."\");'></h3></a>".$dom_v->output."<br><input type='hidden' id='$level$fid\_md5s' value='".join(";", keys(%$md5s))."'><input type='hidden' id='$level$fid\_mgids' value='".join(";", @comp_mgs)."'><div id='".(int($level)+1)."_$fid'></div>";
    }
  }
  
  if ($cgi->param('vis_type') eq 'tree') {
    @comp_mgs = $cgi->param('comparison_metagenomes');
    my $pt = $self->application->component('tree1');
    ## nasty id manipulation to allow for multiple trees
    my $newid = int(rand(100000));
    if ($cgi->param('oldid')) {
      $newid = $cgi->param('oldid');
    }
    $self->application->component('PhyloTreeHoverComponent'.$pt->id)->id($newid);
    $self->application->{component_index}->{'PhyloTreeHoverComponent'.$newid} = $self->application->component('PhyloTreeHoverComponent'.$pt->id);
    $self->application->component('HoverPie'.$pt->id)->id($newid);
    $self->application->{component_index}->{'HoverPie'.$newid} = $self->application->component('HoverPie'.$pt->id);
    $pt->id($newid);
    $pt->sample_names( [ $comp_mgs[0] ] );
    $pt->leaf_weight_type($cgi->param('lwt') || 'stack');
    $pt->show_tooltip(0);
    ##
    my $tree_domain_filter = 0;
    if ($cgi->param('tree_domain') && $cgi->param('tree_domain') ne 'all') {
      $tree_domain_filter = $cgi->param('tree_domain');
    }
    my $expanded_data = [];
    if (scalar(@comp_mgs) > 1) {
      $pt->coloring_method('split');
      $pt->sample_names( [ @comp_mgs ] );
      my $exp_hash = {};
      my $spec_hash = {};
      my $mg2num = {};

      for (my $hh=0; $hh<scalar(@comp_mgs); $hh++) {
	$mg2num->{$comp_mgs[$hh]} = $hh;
      }
      foreach my $row (@$data) {
	next if ($tree_domain_filter && $tree_domain_filter ne $row->[2]);
	$spec_hash->{$row->[9]} = [ @$row[2..9] ];
	unless (exists($exp_hash->{$row->[9]})) {
	  $exp_hash->{$row->[9]} = [];
	}
	$exp_hash->{$row->[9]}->[$mg2num->{$row->[0]}] = $row->[10];
      }
      foreach my $key (sort(keys(%$exp_hash))) {
	my $vals = [];
	for (my $ii=0; $ii<scalar(@comp_mgs); $ii++) {
	  push(@$vals, $exp_hash->{$key}->[$ii] || 0);
	}
	my $row = $spec_hash->{$key};
	#foreach my $r (@$row) {
	#  if ($r =~ /derived/) {
	#    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	#  }
	#}
	push(@$expanded_data, [ @$row, $vals ] );
      }    
    } else {
      foreach my $row (@$data) {
	next if ($tree_domain_filter && $tree_domain_filter ne $row->[2]);
	#foreach my $r (@$row) {
	#  if ($r =~ /derived/) {
	#    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	#  }
	#}
	push(@$expanded_data, [ @$row[2..10] ] );
      }
    }
    @$expanded_data = sort { $b->[8] <=> $a->[8] } @$expanded_data;
    $pt->data($expanded_data);
    $pt->show_leaf_weight(1);
    $pt->show_titles(1);
    $pt->shade_titles($cgi->param('title_level') || 2);
    $pt->enable_click(1);
    $pt->size(1000);
    $pt->depth($cgi->param('depth') || 4);
    $pt->level_distance(40);
    $pt->leaf_weight_space(60);
    $pt->color_leafs_only(1);
    $pt->reroot_field("reroot$tabnum");
    my $md5sel = "";
    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      $pt->reroot_id($self->application->cgi->param('reroot'));
    }

    if ($cgi->param('high_res')) {
      print $cgi->header(-charset => 'UTF-8');
      print $cgi->start_html();
      $pt->size(2500);
      $pt->level_distance(100);
      $pt->leaf_weight_space(150);
      $pt->enable_click(0);
      $pt->title_space(750);
      $pt->font_size($cgi->param('pts') || 20);
      $pt->{thick2} = 5;
      $pt->{thick} = 15;
      $pt->{style} = "width: 800; height: 800;";
      print $pt->output();
      print $cgi->end_html();
      exit;
    }
    
    my $pt_out = $pt->output;
    $pt_out = "<table><tr><td>".$pt->legend."</td><td>".$pt_out."</td></tr></table>";
    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      my $tmd5s = {};
      my $rootnode = $pt->{nodes}->{$self->application->cgi->param('reroot')};
      my $lineage = [ split(/; /, $rootnode->{lineage}) ];
      foreach my $row (@$data) {
	my $fits = 1;
	for (my $i=1; $i<scalar(@$lineage); $i++) {
	  if ($lineage->[$i] ne $row->[$i+2]) {
	    $fits = 0;
	    last;
	  }
	}
	if ($fits) {
	  foreach my $md5 (split(/;/, $row->[16])) {
	    $tmd5s->{$md5} = 1;
	  }
	}
      }
      $md5sel = "<br><br><input type='hidden' id='".$tabnum."_mgids' value='".join(";", @comp_mgs)."'><input type='hidden' id='".$tabnum."_md5s' value='".join(";", keys(%$tmd5s))."'><input type='button' value='to workbench' onclick='buffer_data(\"tree\", \"$tabnum\", \"organism classification\", \"".$rootnode->{name}."\", \"0\", \"".join(";",$cgi->param('source'))."\");'>";
    }
    my $opts = [ [ 2, 'phylum' ],
		 [ 3, 'class' ],
		 [ 4, 'order' ],
		 [ 5, 'family' ],
		 [ 6, 'genus' ],
		 [ 7, 'species' ],
		 [ 8, 'strain' ] ];
    my $explain = "Color shading of the ".$opts->[$pt->depth - 1]->[1]." names indicates ".$opts->[$pt->shade_titles - 1]->[1]." membership.";
    $explain .= " Hover over a node to view the distributions of the children of the node. Click on a node to get distributions of the entire hierarchy of this node. If you have selected a node, you can reroot the tree by checking the reroot checkbox and clicking the 'change' button. Clicking the change button with the reroot checkbox unchecked will draw the entire tree.$md5sel";
    my $change_settings_form = "<form id='pt_form$newid'>$settings_preserve<input type='hidden' name='vis_type' value='tree'><input type='hidden' name='recalc' value='1'><input type='hidden' name='oldid' value='$newid'>";
    my $check1 = ' checked=checked';
    my $check2 = '';
    if ($cgi->param('lwt') && $cgi->param('lwt') eq 'bar') {
      $check2 = ' checked=checked';
      $check1 = '';
    }
    $change_settings_form .= "<table><tr><td><b>display leaf weights as</b></td><td><input type='radio' name='lwt' value='stack'$check1> stacked bar <br><input type='radio' name='lwt' value='bar'$check2> barchart</td></tr>";
    $change_settings_form .= "<tr><td><b>maximum level</b></td><td><select name='depth'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->depth) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select></td></tr><tr><td><b>color by</b></td><td><select name='title_level'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->shade_titles) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select></td></tr>";
    $change_settings_form .= "<tr><td><b>restrict view to domain</b></td><td><select name='tree_domain'><option value='0'>all</option><option value='Bacteria'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Bacteria' ? " selected=selected" : "").">Bacteria</option><option value='Eukaryota'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Eukaryota' ? " selected=selected" : "").">Eukaryota</option><option value='Archaea'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Archaea' ? " selected=selected" : "").">Archaea</option><option value='Viruses'".($cgi->param('tree_domain') && $cgi->param('tree_domain') eq 'Viruses' ? " selected=selected" : "").">Viruses</option></select></td></tr>";
    $change_settings_form .= "<tr><td colspan=2><input type='hidden' name='reroot' value='".($self->application->cgi->param('reroot')||"")."' id='reroot$tabnum'> <input type='checkbox' name='do_reroot'> reroot at selected node</td></tr></table> <input type='button' onclick='execute_ajax(\"phylogeny_visual\", \"pt$newid\", \"pt_form$newid\");' value='change'><input type='hidden' name='high_res' value=0 id='pt_highres$newid'><input type='hidden' name='page' value='Analysis'><input type='hidden' name='action' value='phylogeny_visual'><input type='button' onclick='var f=document.getElementById(\"pt_form$newid\");f.target=\"_blank\";document.getElementById(\"pt_highres$newid\").value=1;f.submit();' value='create high resolution image'></form>";
    if ($cgi->param('recalc')) {
      return "$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out;
    } else {
      $content .= "<div><div>Organism tree $tabnum</div><div><div id='pt$newid'>".clear_progress_image()."$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out."</div></div></div>";
      $tabnum++;
    }
  }

  if ($cgi->param('vis_type') eq 'table') {
    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->show_select_items_per_page(1);
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_column_select(1);
    $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});

    my $tcols = [ { name => 'metagenome', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'id of metagenomic sample' },
		  { name => 'source', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'database source of the hits' },
		  { name => 'domain', sortable => 1, filter => 1, operator => 'combobox' }, 
		  { name => 'phylum', sortable => 1, filter => 1 }, 
		  { name => 'class', sortable => 1, filter => 1 },
		  { name => 'order', sortable => 1, filter => 1 }, 
		  { name => 'family', sortable => 1, filter => 1 },
		  { name => 'genus', sortable => 1, filter => 1 },
		  { name => 'species', sortable => 1, filter => 1 },
		  { name => 'strain', sortable => 1, filter => 1 }, 
		  { name => 'abundance', sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		  { name => 'workbench abundance', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of sequence features with a hit<br>from workbench features' },
		  { name => 'avg eValue', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		  { name => 'eValue std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of the evalue,<br>showing exponent only' }, 
		  { name => 'avg % ident', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		  { name => '% ident std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the percent identity of the hits' },
		  { name => 'avg align len', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		  { name => 'align len std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the alignment length of the hits' },
		  { name => 'md5s', visible => 0 },
		  { name => '# hits', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of unique hits in protein or rna database' },
		  { name => 'workbench # hits', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of unique hits in protein or rna database<br>from workbench features' },
		  { name => "<input type='button' onclick='buffer_data(\"table\", \"".$t->id."\", \"21\", \"18\", \"0\", \"1\", \"10\");' value='to workbench'>", input_type => 'checkbox', tooltip => 'check to select features<br>to add to workbench' } ];
    
    #### do the pivoting
    unless (defined $cgi->param('group_by')) {
      $cgi->param('group_by', '2');
    }
    for (my $i=($cgi->param('group_by')+3);$i<10;$i++) {
      $tcols->[$i]->{visible} = 0;
      $tcols->[$i]->{unaddable} = 1;
    }
    my $dhash = {};
    my $colhashcount = {};
    my $newdata = [];
    foreach my $d (@$data) {
      my $range = 2 + $cgi->param('group_by');
      my $key = join(";", @$d[0..$range]);
      if (exists($dhash->{$key})) { # sum|sum|avg|avg|avg|avg|avg|avg|hash|num_hash
	$newdata->[$dhash->{$key}]->[10] = $newdata->[$dhash->{$key}]->[10] + $d->[10];
	$newdata->[$dhash->{$key}]->[11] = $newdata->[$dhash->{$key}]->[11] + $d->[11];
	$newdata->[$dhash->{$key}]->[12] = (($newdata->[$dhash->{$key}]->[12] * $colhashcount->{$key}) + $d->[12]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[13] = (($newdata->[$dhash->{$key}]->[13] * $colhashcount->{$key}) + $d->[13]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[14] = (($newdata->[$dhash->{$key}]->[14] * $colhashcount->{$key}) + $d->[14]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[15] = (($newdata->[$dhash->{$key}]->[15] * $colhashcount->{$key}) + $d->[15]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[16] = (($newdata->[$dhash->{$key}]->[16] * $colhashcount->{$key}) + $d->[16]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[17] = (($newdata->[$dhash->{$key}]->[17] * $colhashcount->{$key}) + $d->[17]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[18] = $newdata->[$dhash->{$key}]->[18] . ";" . $d->[18];
	$colhashcount->{$key}++;
      } else {
	$dhash->{$key} = scalar(@$newdata);
	$colhashcount->{$key} = 1;
	push(@$newdata, $d);
      }
    }
    foreach my $d (@$newdata) {
      my $abund  = 0;
      my $subab  = 0;
      my $subhit = 0;
      my %hasher = map { $_ => 1 } split(/;/, $d->[18]);
      my $hits   = scalar(keys %hasher);

      map { $abund += $md5_abund->{$d->[0]}{$_} } grep { exists($md5_abund->{$d->[0]}{$_}) } keys %hasher;
      map { $subab += $md5_abund->{$d->[0]}{$_} } grep { exists($md5_abund->{$d->[0]}{$_}) && exists($buffer_md5s{$_}) } keys %hasher;
      map { $subhit += 1 } grep { exists($hasher{$_}) } keys %buffer_md5s;

      $d->[10] = ($abund >= $hits) ? $abund : $hits;
      $d->[10] = "<a onclick='abu(this, $tabnum, 18);' style='cursor:pointer'>".$d->[10]."</a>";
      $d->[11] = $subab;
      $d->[12] = sprintf("%.2f", $d->[12]);
      $d->[13] = sprintf("%.2f", $d->[13]);
      $d->[14] = sprintf("%.2f", $d->[14]);
      $d->[15] = sprintf("%.2f", $d->[15]);
      $d->[16] = sprintf("%.2f", $d->[16]);
      $d->[17] = sprintf("%.2f", $d->[17]);
      $d->[18] = join(";", keys(%hasher));
      $d->[19] = $hits;
      $d->[20] = $subhit;
    }

    @$newdata = sort { $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] || $a->[4] cmp $b->[4] || $a->[5] cmp $b->[5] || $a->[6] cmp $b->[6] || $a->[7] cmp $b->[7] || $a->[8] cmp $b->[8] || $a->[9] cmp $b->[9] } @$newdata;
    
    $t->columns($tcols);
    $t->data($newdata);

    my ($cd, $cp, $cc, $co, $cf, $cg, $cs, $cstr) = ('', '', '', '', '', '', '', '');
    if ($cgi->param('group_by') eq '0') {
      $cd = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '1') {
      $cp = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '2') {
      $cc = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '3') {
      $co = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '4') {
      $cf = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '5') {
      $cg = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '6') {
      $cs = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '7') {
      $cstr = " selected='selected'";
    }

    my $krona_button = "<input type='button' value='krona graph' onclick='generate_krona_data(\"".$cgi->param('group_by')."\", \"".$t->id."\", \"org\");'>";

    my $qiime_button = ($cgi->param('mg_grp_sel') && ($cgi->param('mg_grp_sel') eq 'groups')) ? 'Export for grouped data sets currently not available.<br> Please select <b>compare individually</b> in <b>(2) Data selection</b><br> above and recreate the table.' : "<button onclick='execute_ajax(\"qiime_export_visual\", \"qiime_div_$tabnum\", \"table_group_form_$tabnum\");show_progress();'>QIIME report</button>";

    my $plugin_container = '<table style="border: 2px solid rgb(143, 188, 63); text-align: center; float: right; border-spacing: 0px;"><tbody><tr><td colspan="2" style="cursor: pointer; text-align: left;" title="click to show available plugins" onclick="if(this.parentNode.nextSibling.style.display==\'none\'){this.parentNode.nextSibling.style.display=\'\';this.parentNode.nextSibling.nextSibling.style.display=\'\';}else{this.parentNode.nextSibling.style.display=\'none\';this.parentNode.nextSibling.nextSibling.style.display=\'none\';}"><img src="./Html/plugin.png" style="width: 20px; vertical-align: middle;"> available plugins</td></tr><tr><td style="border-top: 1px solid rgb(143, 188, 63); border-right: 1px solid rgb(143, 188, 63); padding: 2px;"><img src="./Html/krona.png" style="height: 50px; cursor: pointer;" onclick="window.open(&quot;http://sourceforge.net/p/krona/home/krona/&quot;);"></td><td style="border-top: 1px solid rgb(143, 188, 63);"><img onclick="window.open(&quot;http://www.qiime.org&quot;);" style="height: 50px; cursor: pointer;" src="./Html/qiime.png"></td></tr><tr><td style="vertical-align: middle; border-right: 1px solid rgb(143, 188, 63); padding: 2px;">'.$krona_button.'</td><td style="vertical-align: middle;">'.$qiime_button.'</td></tr></tbody></table>';

    my $qiime_div = "<div style='padding-left:15px; float: right;' id='qiime_div_$tabnum'></div>";

    my $pivot = "<form id='table_group_form_$tabnum'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='table'><input type='hidden' name='data_type' value='organism'><input type='hidden' name='ret_type' value='direct'>".$settings_preserve."<br><b>group table by</b> <select name='group_by'><option value='0'$cd>domain</option><option value='1'$cp>phylum</option><option value='2'$cc>class</option><option value='3'$co>order</option><option value='4'$cf>family</option><option value='5'$cg>genus</option><option value='6'$cs>species</option><option value='7'$cstr>strain</option></select><input type='button' value='change' onclick='execute_ajax(\"phylogeny_visual\", \"tab_div_".($tabnum+1)."\", \"table_group_form_$tabnum\");'></form><br><br>";

    if ($cgi->param('ret_type') && $cgi->param('ret_type') eq 'direct') {
      return "$settings$plugin_container$qiime_div$pivot".$t->output;
    }

    my $transposer = "";
#    my $transposer = "<input type='button' value='transpose' onclick='transpose_table(\"".$t->id."\", 0, [2,3,4], 10,\"transpose_space_".$tabnum."\");'><div id='transpose_space_".$tabnum."'></div>";

    $content .= "<div><div>Organism table $tabnum</div><div>".clear_progress_image()."$settings$plugin_container$qiime_div$pivot$transposer".$t->output."</div></div>";
    $tabnum++;
  }

  if ($cgi->param('vis_type') eq 'heatmap' || $cgi->param('vis_type') eq 'pca') {
    # format the data for .r analysis
    # data = [ mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s ]

    @comp_mgs = ();
    foreach my $mg ( $cgi->param('comparison_metagenomes') ) {
      if (exists $data_mgs{$mg}) {
	push @comp_mgs, $mg;
      }
    }

    if (scalar(@comp_mgs) < 2) {
      return "<div><div>no data</div><div>".clear_progress_image().$missing_txt."Heatmap and PCoA analysis require at least two metagenomes with available data.</div></div>";
    } else {
      my $heatmap_data = [ [ '', map { my $x = $_; $x =~ s/\./A/; "ID".$x } @comp_mgs ] ];
      my $hashed_data = {};
      my $mg_ind = {};
      for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	$mg_ind->{$comp_mgs[$i]} = $i;
      }
      my $level = $cgi->param('heatmap_level') || 4;
      my $dd_col;
      my $dd_val;
      if ($cgi->param('drilldown') && $cgi->param('drilldown_on')) {
	($dd_col, $dd_val) = split(/;/, $cgi->param('drilldown'));
      }
      foreach my $d (@$data) {
	if (defined($dd_col)) {
	  next unless ($d->[$dd_col] eq $dd_val);
	}
	next unless ($d->[$level]);
	if (exists($hashed_data->{$d->[$level]})) {
	  if ($hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}]) {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] += $d->[10];
	  } else {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[10];
	  }
	} else {
	  $hashed_data->{$d->[$level]} = [];
	  $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[10];
	}
      }
      foreach my $key (keys(%$hashed_data)) {
	my $row = [ $key ];
	foreach my $mg (@comp_mgs) {
	  if ($hashed_data->{$key}->[$mg_ind->{$mg}]) {
	    push(@$row, $hashed_data->{$key}->[$mg_ind->{$mg}]);
	  } else {
	    push(@$row, 0);
	  }
	}
	push(@$heatmap_data, $row);
      }
      
      # write data to a tempfile
      my ($fh, $infile) = tempfile( "rdataXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      foreach my $row (@$heatmap_data) {
	print $fh join("\t", @$row)."\n";
      }
      close $fh;
      chmod 0666, $infile;
      
      # preprocess data
      my $time = time;
      my $boxfile = "rdata.boxplot.$time.png";
      my ($prefh, $prefn) =  tempfile( "rpreprocessXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $prefh "source(\"".$Conf::bin."/norm_deseq.r\")\n";
      print $prefh "MGRAST_preprocessing(file_in = \"".$infile."\", file_out = \"".$Conf::temp."/rdata.preprocessed.$time\", image_out =\"".$Conf::temp."/$boxfile\", produce_fig = \"TRUE\")\n";
      close $prefh;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $prefn`;
      unlink($prefn);
      
      unless (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) {
	unlink $infile;
	$infile = $Conf::temp."/rdata.preprocessed.$time";
      }

      if ($cgi->param('vis_type') eq 'heatmap') {
	my $level_names = [ [ 2, 'domain' ],
			    [ 3, 'phylum' ],
			    [ 4, 'class' ],
			    [ 5, 'order' ],
			    [ 6, 'family' ],
			    [ 7, 'genus' ],
			    [ 8, 'species' ],
			    [ 9, 'strain' ] ];
	my $dd_sel = "";
	my $hm_level_select = "<select name='heatmap_level'>";
	foreach my $l (@$level_names) {
	  my $sel = "";
	  if ($l->[0] == $level) {
	    $sel = " selected=selected";
	  }	  
	  if (defined($dd_col) && ($l->[0] == $dd_col)) {
	    $dd_sel = $l->[1];
	  }
	  $hm_level_select .= "<option value='".$l->[0]."'$sel>".$l->[1]."</option>";
	}
	$hm_level_select .= "</select>";
	$content .= "<div><div>Organism Heatmap $tabnum</div><div>".clear_progress_image()."<form id='heat_drilldown$fid' onkeypress='return event.keyCode!=13'>$settings<br>The heatmap was clustered using ".($cgi->param('heatmap_clust_method') || 'ward')." with ".($cgi->param('heatmap_dist_method') || 'bray-curtis')." distance metric.<br>group heatmap by $hm_level_select <input type='hidden' name='vis_type' value='heatmap'><input type='hidden' id='tabnum2$fid' name='tabnum' value='".($tabnum+1)."'><br>";

	my $selnorm = "";
	if ($cgi->param('raw')) {
	  $selnorm = " selected=selected";
	}
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('heatmap_dist_method') && ($cgi->param('heatmap_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	my $clustopts = "";
	foreach my $d (@{$self->cluster_methods}) {
	  my $sel = ($cgi->param('heatmap_clust_method') && ($cgi->param('heatmap_clust_method') eq $d)) ? " selected=selected" : "";
	  $clustopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values, <select name='heatmap_clust_method'>$clustopts</select> clustering and <select name='heatmap_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"phylogeny_visual\", \"tab_div_".($tabnum+1)."\", \"heat_drilldown$fid\");'></div></form>";

	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"heatmap_canvas_$tabnum\");document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"\";'></div>";

	my ($col_f, $row_f) = ($Conf::temp."/rdata.col.$time", $Conf::temp."/rdata.row.$time");

	my ($heath, $heatn) =  tempfile( "rheatXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $heath "source(\"".$Conf::bin."/dendrogram.r\")\n";
	print $heath "MGRAST_dendrograms(file_in = \"".$infile."\", file_out_column = \"".$col_f."\", file_out_row = \"".$row_f."\", dist_method = \"".($cgi->param('heatmap_dist_method') || 'bray-curtis')."\", clust_method = \"".($cgi->param('heatmap_clust_method') || 'ward')."\", produce_figures = \"FALSE\")\n";
	close $heath;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $heatn`; 
	unlink($heatn);

	open(COL, "<$col_f");
	my $tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='columns_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";

	$tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='column_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='column_den_$tabnum' type='hidden' value='";
	while (<COL>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\s+/;
	}
	$content .= "'>";	

	close(COL);
	unlink($col_f);

	open(ROW, "<$row_f");
	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='rows_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";

	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='row_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='row_den_$tabnum' type='hidden' value='";
	while (<ROW>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\t/;	
	}
	$content .= "'>";
	
	close(ROW);
	unlink($row_f);

	open(D, "<$infile");
	my @values = 0;
	my $cdata = "category\t".join("\t", @comp_mgs)."\n";
	my $junk = <D>;

	$content .= "<input id='table_$tabnum' type='hidden' value='";
	while(<D>){
	  $cdata .= $_;
	  chomp;
	  my ($junk, $data) = split /\t/, $_, 2;
	  my @set = split /\t/, $data;
	  push @values, @set;
	  $content .= "@";
	  $content .= join "^", @set;
	}
	$content .= "'>";
	close(D);
	unlink $infile;

	$content .= "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='$cdata'><input type='submit' value='download values used to generate this figure'></form>";

	my $max_val = max @values;
	$max_val  = ($max_val < 1) ? 1 : $max_val;
	$content .= $self->heatmap_scale($max_val)."<div id='heatmap_canvas_$tabnum'></div>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_heatmap(\"heatmap_canvas_$tabnum\", \"$tabnum\", \"$max_val\"); document.getElementById(\"progress_div\").innerHTML=\"\";'/></div></div>";
	$tabnum++;
      }
      if ($cgi->param('vis_type') eq 'pca') {
	my $time = time;
	my ($pca_data) = ($Conf::temp."/rdata.pca.$time");
	my ($pcah, $pcan) =  tempfile( "rpcaXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $pcah "source(\"".$Conf::bin."/plot_pco.r\")\n";
	print $pcah "MGRAST_plot_pco(file_in = \"".$infile."\", file_out = \"".$pca_data."\", dist_method = \"".($cgi->param('pca_dist_method') || 'bray-curtis')."\", headers = 1)\n";
	close $pcah;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $pcan`; 
	unlink($pcan);

	$content .= "<div><div>Organism PCoA $tabnum</div><div>$settings<i>$psettings</i><br><br>";

	my $selnorm  = (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) ? " selected=selected" : "";
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('pca_dist_method') && ($cgi->param('pca_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "<form id='phylo_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='pca'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values and <select name='pca_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"phylogeny_visual\", \"tab_div_".($tabnum+1)."\", \"phylo_redraw$fid\");'></div></form>";
	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"pca_canvas_$tabnum\");document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"\";'></div>";

	my (@comp, @items);

	open(D, "<$pca_data");
	while(<D>){
	  chomp;
	  s/"//g; #"
	  my @fields = split /\t/;
	  if ($fields[0] =~ /^PCO\d+$/) {
	    push @comp, join("^", @fields); 
	  } elsif ($fields[0] =~ /^ID([\dA]+)$/) {
	    push @items, join("^", @fields); 
	  }
	}
	close(D);

	# metadata coloring	
	my $mddb  = MGRAST::Metadata->new;
	my $jobmd = $mddb->get_metadata_for_tables(\@comp_mgs, 1, 1);
	my $mdata = {};
	# get unique labels accross all metagenomes
	foreach my $mgid (@comp_mgs) {
	    next unless ($jobmd->{$mgid});
	    foreach my $md (@{$jobmd->{$mgid}}) {
	        next if ($md->[1] =~ /(_id|_name)$/);
	        next if ($md->[1] =~ /^PI_/);
	        $mdata->{$md->[1]}{$mgid} = $md->[2];
        }
    }
    my @md_names = sort keys %$mdata;
    my $mgmd = [];
	my $iii  = 0;
    # get values for each metagenome
    foreach my $mgid (@comp_mgs) {
	    foreach my $md (@md_names) {
	        my $val = (exists($mdata->{$md}{$mgid}) && ($mdata->{$md}{$mgid} ne '')) ? $mdata->{$md}{$mgid} : undef;
            if ($val) { $val =~ s/'//g; }
            push @{ $mgmd->[$iii] }, $val;
        }
        $iii += 1;
    }
	my $md_type_select = "<select id='whichmd_".$tabnum."' onchange='check_metadata(\"$tabnum\", this);'>";
	foreach my $md_name (@md_names) {
	  $md_type_select .= "<option value='$md_name'>$md_name</option>";
	}
	$md_type_select .= "</select><input type='button' value='apply' onclick='color_by_metadata(\"$tabnum\");'>";

	my $comp_control = "<br><br><br><br><table><tr><th>component</th><th>r^2</th><th>x-axis</th><th>y-axis</th></tr>";
	my $i = 0;
	foreach my $row (@comp) {
	  my ($pcname, $rsquare) = split /\^/, $row;
	  $rsquare = sprintf("%.5f", $rsquare);
	  my $sel_x = '';
	  my $sel_y = '';
	  if ($i == 0) {
	    $sel_x = " checked=checked";
	  }
	  if ($i == 1) {
	    $sel_y = " checked=checked";
	  }
	  $comp_control .= "<tr><td>$pcname</td><td>$rsquare</td><td><input type='radio' name='xcomp$tabnum' id='xcomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_x></td><td><input type='radio' name='ycomp$tabnum' id='ycomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_y></td></tr>";
	  $i++;
	}
	$comp_control .= "</table>";

	my $group_control = "<div id='grpctrl$tabnum' style='display: none;'><br><br><br><div id='feedback$tabnum'></div><table><tr><th>group</th><th>name</th><th style='width: 56px;'>save as collection</th></tr>";
	$group_control .= "<tr><td>group 1</td><td><input type='text' id='group1_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"1\");'></td></tr>";
	$group_control .= "<tr><td>group 2</td><td><input type='text' id='group2_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"2\");'></td></tr>";
	$group_control .= "<tr><td>group 3</td><td><input type='text' id='group3_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"3\");'></td></tr>";
	$group_control .= "<tr><td>group 4</td><td><input type='text' id='group4_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"4\");'></td></tr>";
	$group_control .= "<tr><td>group 5</td><td><input type='text' id='group5_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"5\");'></td></tr>";
	$group_control .= "<tr><td>group 6</td><td><input type='text' id='group6_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"6\");'></td></tr>";
	$group_control .= "<tr><td>group 7</td><td><input type='text' id='group7_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"7\");'></td></tr>";
	$group_control .= "<tr><td>group 8</td><td><input type='text' id='group8_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"8\");'></td></tr>";
	$group_control .= "<tr><td>group 9</td><td><input type='text' id='group9_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"9\");'></td></tr>";
	$group_control .= "<tr><td>group 10</td><td><input type='text' id='group10_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"10\");'></td></tr>";
	$group_control .= "</table></div>";

	my $img_control = "<table><tr><td><div style='cursor: pointer; background-color: #8FBC3F; color: white; font-weight: bold; height: 16px; width: 250px; text-align: center; padding-top: 4px;' onclick='if(document.getElementById(\"imgctrl$tabnum\").style.display==\"none\"){document.getElementById(\"imgctrl$tabnum\").style.display=\"\";document.getElementById(\"grpctrl$tabnum\").style.display=\"\";}else{document.getElementById(\"imgctrl$tabnum\").style.display=\"none\";document.getElementById(\"grpctrl$tabnum\").style.display=\"none\";}' title='click to expand'>PCoA grouping control</div></td></tr><tr><td id='imgctrl$tabnum' style='display: none;'>";
	$img_control .= "<table><tr><td><div style='width: 280px;'><b>create a grouping</b><br>You can create a grouping of your metagenomes to calculate p-values in the barchart visualization. Select a group and click the metagenome circle in the graphic. You can also drag open a square to select multiple metagenomes at a time.</div><br><br>mark clicked as <select id='group_color$tabnum'><option value='red' selected=selected>group 1</option><option value='green'>group 2</option><option value='cyan'>group 3</option><option value='purple'>group 4</option><option value='yellow'>group 5</option><option value='blue'>group 6</option><option value='orange'>group 7</option><option value='gray'>group 8</option><option value='black'>group 9</option><option value='magenta'>group 10</option></select><br><br>or select groups in the table to the right.</td><td>";
	$img_control .= "<table><tr><th>Metagenome</th><th>group</th><th>$md_type_select</th></tr>";
	my $opts = "<option value='0'>- no group -</option><option value='group1'>group 1</option><option value='group2'>group 2</option><option value='group3'>group 3</option><option value='group4'>group 4</option><option value='group5'>group 5</option><option value='group6'>group 6</option><option value='group7'>group 7</option><option value='group8'>group 8</option><option value='group9'>group 9</option><option value='group10'>group 10</option>";
	for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	  $img_control .= "<tr><td>".($comp_mgs[$i] || '')."</td><td><select id='group_list".$tabnum."_$i' onchange='change_pca_color(this, \"$tabnum\", \"$i\");'>$opts</select></td><td><span id='group_list_md_".$tabnum."_$i'>".($mgmd->[$i]->[0] || '')."</span></td></tr>";
	}
	$img_control .= "</table>";
	$img_control .= "<input type='button' value='store grouping' onclick='store_grouping(\"$tabnum\", \"".join("^", @comp_mgs)."\");'>";

	$img_control .= "<input type='hidden' id='pcamd_".$tabnum."' value='".join("~~", map { join(";;", map { defined($_) ? $_ : 'unknown' } @$_) } @$mgmd)."'></td></tr></table>";

	$img_control .= "</td></tr></table>";

	my @comp_b = @comp;
	my @items_b = @items;
	my $cmg_hash = {};
	%$cmg_hash = map { my $x = $_; $x =~ s/\./A/; "ID".$x => $_; } @comp_mgs;
	my $data_download_button = "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='PCA Component impact\n".join("\n", map { $_ =~ s/\^/\t/g; $_; } @comp_b)."\n\nData Items\nMetagenome\t".join("\t", map { $_ =~ s/(.*)\t.*/$1/; $_; } @comp_b)."\n".join("\n", map { $_ =~ s/\^/\t/g; my ($x) = $_ =~ /^([^\t]+)/; $x = $cmg_hash->{$x}; $_ =~ s/^[^\t]+(.*)/$x$1/; $_; } @items_b)."'><input type='submit' value='download values used to generate this figure'></form>";

	$content .= "<input id='pca_components_$tabnum' type='hidden' value='".join("@",@comp)."'>";
	$content .= "<input id='pca_items_$tabnum' type='hidden' value='".join("@",@items)."'>";
	$content .= $img_control;
	$content .= "<table><tr><td><div id='pca_canvas_$tabnum'></div></td><td>$data_download_button".$comp_control.$group_control."</td></tr></table>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_pca(\"pca_canvas_$tabnum\", \"$tabnum\", 1,2); document.getElementById(\"progress_div\").innerHTML=\"\";'/></div></div>";
	$tabnum++;
      }
    }
  }

  if ($cgi->param('vis_type') eq 'rarefaction') {
    # data = [ mgid, [x, y] ]
    my $rare_data  = [];
    my $alpha_data = [];
    my $colors = $self->google_colors();

    my (@allX, @allY);
    for (my $i = 0; $i < @$data; $i++) {
      my ($mgid, $coord, $alpha) = @{$data->[$i]};
      my $c_index = $i % scalar(@$colors);
      foreach (@$coord) {
	    push @allX, $_->[0];
	    push @allY, $_->[1];
      }
      push @$rare_data, $mgid . '~' . join('~', map { $_->[0] . ';;' . $_->[1] } @$coord);
      push @$alpha_data, [ "<div style='height:14px; width:56px; margin: 2 0 2 1; background-color:".$colors->[$i].";'></div>", $mgid, sprintf("%.2f", $alpha) ];
    }
    my $maxX = max @allX;
    my $maxY = max @allY;

    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->items_per_page(scalar(@$data));
    $t->columns([ {name => 'rarefaction<br>curve', tooltip => 'color of rarefaction curve'},
		  {name => 'metagenome', filter => 1, sortable => 1, tooltip => 'id of metagenomic sample'},
		  {name => 'alpha diversity', filter => 1, sortable => 1, operators => ['less','more'], tooltip => 'alpha diversity of metagenome'} ]);
    $t->data($alpha_data);
    

    $content .= "<div><div>Rarefaction Plot $tabnum</div><div>".clear_progress_image()."$settings<br>";
    $content .= "<div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"rare_canvas_$tabnum\");document.getElementById(\"rare_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"rare_canvas_$tabnum\").style.display=\"none\";'></div>";
    $content .= "<div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"rare_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"rare_canvas_$tabnum\").style.display=\"\";'></div>";
    $content .= "<div id='rare_canvas_$tabnum'></div><input type='hidden' id='rare_data_$tabnum' value='".join('@', @$rare_data)."'/>";
    $content .= "<img src='./Html/clear.gif' onload='draw_rarefaction(\"rare_data_$tabnum\", \"rare_canvas_$tabnum\", \"$maxX\", \"$maxY\");'/>";
    $content .= "<br>".$t->output."</div></div>";
    $tabnum++;
  }

  return $content;
}

sub metabolism_visual {
  my ($self) = @_;

  my $content = "";  
  my $cgi = $self->application->cgi;
  my ($md5_abund, $data) = $self->metabolic_data();
  my $tabnum = $cgi->param('tabnum') || 2;
  $tabnum--;

  # mgid => md5 => abundance
  #  0       1      2       3         4        5    6            7              8        9       10           11         12       13      14
  # mgid, level1, level2, level3, annotation, id, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s

  unless (scalar(@$data)) {
    return "<div><div>no data</div><div>".clear_progress_image()."The visualizations you requested cannot be drawn, as no data met your selection criteria.</div></div>";
  }
  
  my %buffer_md5s = $cgi->param('use_buffer') ? map {$_, 1} split(/;/, $cgi->param('use_buffer')) : ();
  my $settings_preserve = "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'><input type='hidden' name='evalue' value='".$cgi->param('evalue')."'>";
  my @comp_mgs = $cgi->param('comparison_metagenomes');
  if ($cgi->param('mg_grp_sel') && $cgi->param('mg_grp_sel') eq 'groups') {
    $settings_preserve .= "<input type='hidden' name='mg_grp_sel' value='groups'>";
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_collections' value='".$mg."'>";
    }
  } else {
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_metagenomes' value='".$mg."'>";
    }
  }
  if ($cgi->param('use_buffer')) {
    $settings_preserve .= "<input type='hidden' name='use_buffer' value='".$cgi->param('use_buffer')."'>";
  }
  my $mgs = "";
  my $mgnames = [];
  @$mgnames = @comp_mgs;
  foreach my $metagenome (@$mgnames) {
    my $mgname = '';
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
    if (ref($job)) {
      $mgname = $job->name()." ($metagenome)";
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }
  if (scalar(@$mgnames) > 1) {
    my $last = pop(@$mgnames);
    $mgs .= "metagenomes ".join(", ", @$mgnames)." and $last";
  } else {
    $mgs .= "metagenome ".$mgnames->[0];
  }
  my $sorcs = "";
  my @sources = $cgi->param('source');
  foreach my $source (@sources) {
    $settings_preserve .= "<input type='hidden' name='source' value='".$source."'>";
  }
  if (scalar(@sources) > 1) {
    my $last = pop(@sources);
    $sorcs = join(", ", @sources)." and $last";
  } else {
    $sorcs = $sources[0];
  }
  my $cutoffs = "a maximum e-value of 1e-" . ($cgi->param('evalue') || '0') . ", ";
  $cutoffs   .= "a minimum identity of " . ($cgi->param('identity') || '0') . " %, ";
  $cutoffs   .= "and a minimum alignment length of " . ($cgi->param('alength') || '1') . ' measured in aa for protein and bp for RNA databases';

  my $psettings = " The data has been normalized to values between 0 and 1. If you would like to view raw values, redraw using the form below.";
  if ($cgi->param('raw')) {
    $psettings = " The data is showing raw values. If you would like to view normalized values, redraw using the form below.";
  }
  my $settings = "<i>This data was calculated for $mgs. The data was compared to $sorcs using $cutoffs.</i><br/>";

  $settings_preserve .= "<input type='hidden' name='evalue' value='"   . ($cgi->param('evalue') || '0')   . "'>";
  $settings_preserve .= "<input type='hidden' name='identity' value='" . ($cgi->param('identity') || '0') . "'>";
  $settings_preserve .= "<input type='hidden' name='alength' value='"  . ($cgi->param('alength') || '1')  . "'>";
  my $fid = $cgi->param('fid') || int(rand(1000000));
  
  ## determine if any metagenomes missing from results
  my $missing_txt = "";
  my @missing_mgs = ();
  my %data_mgs    = map { $_->[0], 1 } @$data;

  foreach my $mg (@comp_mgs) {
    if (! exists $data_mgs{$mg}) {
      push @missing_mgs, $mg;
    }
  }  

  if (@missing_mgs > 0) {
    $missing_txt = "<br>";
    foreach my $mg (@missing_mgs) {
      my $mgname = '';
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
      if (ref($job)) {
	$mgname = $job->name()." ($mg)";
      }
      $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>";
    }
    if (@missing_mgs > 1) {
      my $last = pop @missing_mgs;
      $missing_txt .= "Metagenomes " . join(", ", @missing_mgs) . " and $last contain";
    } else {
      $missing_txt .= "Metagenome " . $missing_mgs[0] . " contains";
    }
    $missing_txt .= " no functional data for the above selected sources and cutoffs. They are being excluded from the analysis.<br>";
  }
  $settings .= $missing_txt;

  if ($cgi->param('vis_type') eq 'vbar') {
    my $has_three = 1;
    if ($data->[0]->[3] eq "-") {
      $has_three = 0;
    }
    my $bardata = [];
    foreach my $d (@$data) {
      if ($d->[1] ne "-") {
	push(@$bardata, [ @$d[0], $sources[0], @$d[1..(scalar(@$d)-1)] ]);
      }
    }
    map { $_->[1] = $sources[0]; } @$bardata;
    if ($cgi->param('meta_bar_sel') && $cgi->param('meta_bar_col')) {
      @$bardata = map { ($_->[$cgi->param('meta_bar_col')] && ($_->[$cgi->param('meta_bar_col')] eq $cgi->param('meta_bar_sel'))) ? $_ : () } @$bardata;
    }
    my $level = $cgi->param('meta_bar_col') ? ($cgi->param('meta_bar_col') + 1) : 2;
    my $noclick;
    if ($level==5) {
      $noclick = 1;
    }
    my $sup_v = $self->data_to_vbar($md5_abund, $bardata, $level, 7, 1000, 'meta', $fid, undef, $noclick);

    $settings .= "<i>$psettings</i><br>";
    # check for p-value calculation
    if (defined($cgi->param('pval'))) {
      $settings_preserve .= "<input type='hidden' name='pval' value='".$cgi->param('pval')."'>";
      $settings_preserve .= "<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'>";
      my $mg2group = {};
      map { my ($g, $m) = split /\^/; $mg2group->{$m} = $g; } split /\|/, $cgi->param('pval');
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my ($pvalgroupf, $pvalgroupn) = tempfile( "rpvalgXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalgroupf join("\t", map { $mg2group->{$_} } @comp_mgs)."\n";
      close $pvalgroupf;
      my ($pvaldataf, $pvaldatan) = tempfile( "rpvaldXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvaldataf "\t".join("\t", map { "ID".$_ } @comp_mgs)."\n";
      my $cats = $sup_v->datasets();
      my $pd = $sup_v->data();
      my $i = 0;
      foreach my $row (@$pd) {
	print $pvaldataf $cats->[$i]."\t".join("\t", map { $_->[0] } @$row)."\n";
	$i++;
      }
      close $pvaldataf;
      my ($pvalsuggestf, $pvalsuggestn) = tempfile( "rpvalsXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalsuggestf;
      my ($pvalresultf, $pvalresultn) = tempfile( "rpvalrXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalresultf;
      my ($pvalexecf, $pvalexecn) = tempfile( "rpvaleXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      my $rn = "normalized";
      if ($cgi->param('raw')) {
	$rn = "raw";
      }
      print $pvalexecf "source(\"".$Conf::bin."/suggest_stat_test.r\")\n";
      print $pvalexecf "MGRAST_suggest_test(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", paired = FALSE, file_out = \"".$pvalsuggestn."\")\n";
      close $pvalexecf;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $pvalexecn`;
      open(FH, $pvalsuggestn);
      my $res = <FH>;
      chomp $res;
      close FH;
      $settings .= "<br><i>The p-values were calculated using $res and the following groups:</i><br>";
      $settings .= "<table><tr><th>metagenome</th><th>group</th></tr>";
      foreach my $cmg (@comp_mgs) {
	$settings .= "<tr><td>$cmg</td><td>".$mg2group->{$cmg}."</td></tr>";
      }
      $settings .= "</table><br>";
      my ($pvalexec2f, $pvalexec2n) = tempfile( "rpvale2XXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalexec2f "source(\"".$Conf::bin."/do_stats.r\")\n";
      print $pvalexec2f "MGRAST_do_stats(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", sig_test = \"".$res."\", file_out = \"".$pvalresultn."\")\n";
      close $pvalexec2f;
      `$R --vanilla --slave < $pvalexec2n`;
      open(FH, $pvalresultn);
      my $header = <FH>;
      my $pval_data = {};
      while (<FH>) {
	chomp;
	my @row = split /\t/;
	my $name = substr($row[0], 1, length($row[0])-2);
	my $stat = $row[scalar(@row)-2];
	my $pval = $row[scalar(@row)-1];
	$pval_data->{$name} = [ $stat, $pval ];
      }
      close FH;
      unlink($pvalgroupn);
      unlink($pvaldatan);
      unlink($pvalexecn);
      unlink($pvalexec2n);
      unlink($pvalsuggestn);
      unlink($pvalresultn);
      my $chash = {};
      for (my $i=0; $i<scalar(@$cats); $i++) {
	$chash->{$cats->[$i]} = $pd->[$i];
      }
      
      my $cats_pos = {};
      my $cind = 0;
      foreach my $k (@$cats) {
	$cats_pos->{$k} = $cind;
	$cind++;
      }

      @$cats = sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);
      @$pd = map { $chash->{$_} } sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);

      $cind = 0;
      foreach my $nc (@$cats) {
	$cats_pos->{$cind} = $cats_pos->{$nc};
	$cind++;
      }
      my $onclicks = $sup_v->data_onclicks;
      my $onclicks_title = $sup_v->title_onclicks;
      my $newonclicks = [];
      my $newonclicks_title = [];
      $cind = 0;
      foreach (@$onclicks) {
	push(@$newonclicks, $onclicks->[$cats_pos->{$cind}]);
	push(@$newonclicks_title, $onclicks_title->[$cats_pos->{$cind}]);
	$cind++;
      }
      $sup_v->data_onclicks($newonclicks);
      $sup_v->title_onclicks($newonclicks_title);

      $sup_v->data($pd);
      foreach my $cat (@$cats) {
	if (exists($pval_data->{$cat})) {
	  $cat = $cat." [".sprintf("%.4f", $pval_data->{$cat}->[1])."]";
	} else {
	  $cat = $cat." [-]";
	}
      }
      $sup_v->datasets($cats);
    }

    # generate a stringified version of the current data for download
    my $download_data = {};
    my $ii = 0;
    foreach my $bgroup (@{$sup_v->data}) {
      my $hh = 0;
      foreach my $bmg (@$bgroup) {
	my $jj = 0;
	foreach my $bsource (@$bmg) {
	  unless (exists($download_data->{$sup_v->supersets->[$jj]})) {
	    $download_data->{$sup_v->supersets->[$jj]} = {};
	  }
	  unless (exists($download_data->{$sup_v->supersets->[$jj]}->{$sup_v->datasets->[$ii]})) {
	    $download_data->{$sup_v->supersets->[$jj]}->{$sup_v->datasets->[$ii]} = {};
	  }
	  $download_data->{$sup_v->supersets->[$jj]}->{$sup_v->datasets->[$ii]}->{$sup_v->subsets->[$hh]} = $bsource;
	  $jj++;
	}
	$hh++;
      }
      $ii++;
    }
    my $download_data_string = "";
    foreach my $key (sort(keys(%$download_data))) {
      $download_data_string .= "$key\\n";
      $download_data_string .= "\\t".join("\\t", sort(@{$sup_v->subsets}))."\\n";
      foreach my $k2 (sort(keys(%{$download_data->{$key}}))) {
	$download_data_string .= $k2."\\t".join("\\t", map { $download_data->{$key}->{$k2}->{$_} } sort(keys(%{$download_data->{$key}->{$k2}})))."\\n";
      }
      $download_data_string .= "\\n";
    }
    $download_data_string =~ s/'/\&rsquo\;/g;
    $download_data_string =~ s/"/\&rdquo\;/g;

    if ($level == 2) {
      $content .= "<div><div>Functional barchart $tabnum</div><div>";
      my $selnorm = "";
      if (defined($cgi->param('raw'))) {
	$content = "<div>";
	if ($cgi->param('raw') == '1') {
	  $selnorm = " selected=selected";
	}
      }
      $content .= "<form id='meta_drilldown$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='meta_bar_sel'><input type='hidden' name='meta_bar_col'><input type='hidden' name='fid'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'></form>";
      $content .= clear_progress_image()."$settings<br>";
      $content .= "<form id='meta_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values <input type='checkbox' value='' name='pval' onclick='check_group_selection(this, \"$tabnum\")'> calculate p-values <input type='button' value='draw' onclick='execute_ajax(\"metabolism_visual\", \"tab_div_".($tabnum+1)."\", \"meta_redraw$fid\");'></div></form>";
      if (! defined($cgi->param('raw')) || ($cgi->param('raw') == '0')) {
	$content .= "The displayed data has been normalized to values between 0 and 1 to allow for comparison of differently sized samples.";
      }

      $content .= "<br><br>Click on a bar to drill down to the selected category (i.e. ".$bardata->[0]->[2].")<br><br><div style='position: relative; float: right;'>".$sup_v->legend."</div><a name='level1$fid'><h3 style='margin-top: 0px;'>Level 1 Distribution <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'></h3>".$sup_v->output."<br><div id='3_$fid'></div></div></div>";
      $tabnum++;
    } else {
      my $header_names = { 3 => "Level 2",
			   4 => "Level 3",
			   5 => "Function" };
      if (! $has_three && $level == 4) {
	$level = 5;
      }
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my $md5s = {};
      foreach my $row (@$bardata) {
	if ($row->[$level - 1] eq $cgi->param('meta_bar_sel')) {
	  my @currmd5s = split /;/, $row->[scalar(@$row) - 1];
	  foreach my $cmd5 (@currmd5s) {
	    $md5s->{$cmd5} = 1;
	  }
	}
      }
      
      return clear_progress_image()."<h3 style='margin-top: 0px;'>".$header_names->{$level}." Distribution (".$cgi->param('meta_bar_sel').") <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'> <input type='button' value='to workbench' onclick='buffer_data(\"barchart\", \"$level$fid\", \"$sources[0] metabolic\", \"".$cgi->param('meta_bar_sel')."\", \"0\", \"$sources[0]\");'></h3></a>".$sup_v->output."<br><input type='hidden' id='$level$fid\_md5s' value='".join(";", keys(%$md5s))."'><input type='hidden' id='$level$fid\_mgids' value='".join(";", @comp_mgs)."'><div id='".(int($level)+1)."_$fid'></div>";
    }
  }

  if ($cgi->param('vis_type') eq 'tree') {
    @comp_mgs = $cgi->param('comparison_metagenomes');
    my $pt = $self->application->component('tree1');
    ## nasty id manipulation to allow for multiple trees
    my $newid = int(rand(100000));
    if ($cgi->param('oldid')) {
      $newid = $cgi->param('oldid');
    }
    $self->application->component('PhyloTreeHoverComponent'.$pt->id)->id($newid);
    $self->application->{component_index}->{'PhyloTreeHoverComponent'.$newid} = $self->application->component('PhyloTreeHoverComponent'.$pt->id);
    $self->application->component('HoverPie'.$pt->id)->id($newid);
    $self->application->{component_index}->{'HoverPie'.$newid} = $self->application->component('HoverPie'.$pt->id);
    $pt->id($newid);
    $pt->leaf_weight_type($cgi->param('lwt') || 'stack');
    $pt->sample_names( [ $comp_mgs[0] ] );
    $pt->show_tooltip(0);
    ##
    my $has_three = 1;
    if ($data->[0]->[3] eq "-") {
      $has_three = 0;
    }
    my $expanded_data = [];
    if (scalar(@comp_mgs) > 1) {

      $pt->sample_names( [ @comp_mgs ] );
      $pt->coloring_method('split');
      my $exp_hash = {};
      my $anno_hash = {};
      my $mg2num = {};

      for (my $hh=0; $hh<scalar(@comp_mgs); $hh++) {
      	$mg2num->{$comp_mgs[$hh]} = $hh;
      }

      foreach my $row (@$data) {
	next if ($row->[1] eq "-");
	next if ($row->[1] eq "Clustering-based subsystems");
	my $keystring = join("", @$row[1..4]);
	$anno_hash->{$keystring} = [ @$row[1..4] ];
      	unless (exists($exp_hash->{$keystring})) {
      	  $exp_hash->{$keystring} = [];
      	}
      	$exp_hash->{$keystring}->[$mg2num->{$row->[0]}] = $row->[6];
      }

      foreach my $key (sort(keys(%$exp_hash))) {
      	my $vals = [];
      	for (my $ii=0; $ii<scalar(@comp_mgs); $ii++) {
      	  push(@$vals, $exp_hash->{$key}->[$ii] || 0);
      	}
      	my $row = $anno_hash->{$key};
	if ($has_three) {
	  push(@$expanded_data, [ 'Metabolism', $row->[0], $row->[1], $row->[2], $row->[3], $vals ] );
	} else {
	  push(@$expanded_data, [ 'Metabolism', $row->[0], $row->[1], $row->[3], $vals ] );
	}
      }
    } else {
      foreach my $row (@$data) {
	next if ($row->[2] eq "-");
	next if ($row->[1] eq "Clustering-based subsystems");
	if ($row->[6] > 0) {
	  if ($has_three) {
	    push(@$expanded_data, [ 'Metabolism', $row->[1], $row->[2], $row->[3], $row->[4], $row->[6] ] );
	  } else {
	    push(@$expanded_data, [ 'Metabolism', $row->[1], $row->[2], $row->[4], $row->[6] ] );
	  }
	}
      }
    }

    $pt->data($expanded_data);
    $pt->show_leaf_weight(1);
    $pt->show_titles(1);
    $pt->shade_titles($cgi->param('title_level') || 2);
    $pt->enable_click(1);
    $pt->size(1000);
    $pt->depth($cgi->param('depth') || 3);
    $pt->level_distance(40);
    $pt->leaf_weight_space(60);
    $pt->color_leafs_only(1);
    $pt->reroot_field("reroot$tabnum");
    $pt->show_arcs(0);
    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      $pt->reroot_id($self->application->cgi->param('reroot'));
    }

    if ($cgi->param('high_res')) {
      print $cgi->header(-charset => 'UTF-8');
      print $cgi->start_html();
      $pt->size(2500);
      $pt->level_distance(100);
      $pt->leaf_weight_space(150);
      $pt->enable_click(0);
      $pt->title_space(750);
      $pt->font_size($cgi->param('pts') || 20);
      $pt->{thick2} = 5;
      $pt->{thick} = 15;
      $pt->{style} = "width: 800; height: 800;";
      print $pt->output();
      print $cgi->end_html();
      exit;
    }
    
    my $ptout = "<p>no data matched your query criteria</p>";
    if (scalar(@$expanded_data)) {
      $ptout = $pt->output();
      $ptout = "<table><tr><td>".$pt->legend."</td><td>".$ptout."</td></tr></table>";
    }
    
    my $opts = [ [ 1, 'Level 1' ],
		 [ 2, 'Level 2' ],
		 [ 3, 'Level 3' ],
		 [ 4, 'Level 4' ],
		 [ 5, 'Level 5' ] ];
    my $explain = "Color shading of the ".$opts->[$pt->depth - 1]->[1]." names indicates category membership.";
    $explain .= " Click on a node to get distributions of the entire hierarchy of this node. If you have selected a node, you can reroot the tree by checking the reroot checkbox and clicking the 'change' button. Clicking the change button with the reroot checkbox unchecked will draw the entire tree.";
    my $change_settings_form = "<form id='pt_form$newid'>$settings_preserve<input type='hidden' name='vis_type' value='tree'><input type='hidden' name='recalc' value='1'><input type='hidden' name='oldid' value='$newid'>";
    my $check1 = ' checked=checked';
    my $check2 = '';
    if ($cgi->param('lwt') && $cgi->param('lwt') eq 'bar') {
      $check2 = ' checked=checked';
      $check1 = '';
    }
    $change_settings_form .= "<b>display leaf weights as</b> <input type='radio' name='lwt' value='stack'$check1> stacked bar <input type='radio' name='lwt' value='bar'$check2> barchart<br>";
    $change_settings_form .= "<b>maximum level</b>&nbsp;&nbsp;<select name='depth'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->depth + 1) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select>&nbsp;&nbsp;<b>color by</b> <select name='title_level'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->shade_titles) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select> <input type='hidden' name='reroot' value='".($self->application->cgi->param('reroot')||"")."' id='reroot$tabnum'> <input type='checkbox' name='do_reroot'> reroot at selected node <input type='button' onclick='execute_ajax(\"metabolism_visual\", \"pt$newid\", \"pt_form$newid\");' value='change'></form>";
    if ($cgi->param('recalc')) {
      return "$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$ptout;
    } else {
      $content .= "<div><div>Functional tree $tabnum</div><div><div id='pt$newid'>".clear_progress_image()."$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$ptout."<input type='hidden' name='reroot' value='".($self->application->cgi->param('reroot')||"")."' id='reroot$tabnum'></div></div></div>";
      $tabnum++;
    }
  }

  if ($cgi->param('vis_type') eq 'table') {
    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->show_select_items_per_page(1);
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_column_select(1);
    $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});

    my $tdata   = [];
    my $source  = $cgi->param('source');
    my $columns = [ { name => 'metagenome', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'id of metagenomic sample' },
		    { name => 'level 1', visible => 1, sortable => 1, filter => 1, operator => 'combobox' },
		    { name => 'level 2', visible => 1, sortable => 1, filter => 1 },
		    { name => 'function', visible => 1, sortable => 1, filter => 1 },
		    { name => 'id', sortable => 1, filter => 1, visible => (($source eq "Subsystems") ? 0 : 1) },
		    { name => 'abundance', sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		    { name => 'workbench abundance', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of sequence features with a hit<br>from workbench features' },
		    { name => 'avg eValue', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		    { name => 'eValue std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of the evalue,<br>showing exponent only' },
		    { name => 'avg % ident', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		    { name => '% ident std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the percent identity of the hits' },
		    { name => 'avg align len', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		    { name => 'align len std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the alignment length of the hits' },
		    { name => 'md5s', visible => 0 },
		    { name => '# hits', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of unique hits in protein or rna database' },
		    { name => 'workbench # hits', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of unique hits in protein or rna database<br>from workbench features' } ];

    if (($source eq "COG") || ($source eq "NOG")) {
      unless (defined $cgi->param('group_by')) {
	$cgi->param('group_by', '2');
      }
    } else {
       unless (defined $cgi->param('group_by')) {
	$cgi->param('group_by', '3');
      }
    }
    my $level3opt = "";
    my ($l1, $l2, $l3, $l4) = ('', '', '', '');
    if ($cgi->param('group_by') eq '0') {
      $l1 = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '1') {
      $l2 = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '2') {
      $l3 = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '3') {
      $l4 = " selected='selected'";
    }
    my $subt = 0;
    if (($source eq "COG") || ($source eq "NOG")) {
      @$tdata = map { [ @$_[0..2], @$_[4..14] ] } @$data;
      push @$columns, { name => "<input type='button' onclick='buffer_data(\"table\", \"".$t->id."\", \"16\", \"13\", \"0\", \"".$source."\", \"5\");' value='to workbench'>", input_type => 'checkbox', tooltip => 'check to select features<br>to add to workbench' };
      for (my $i=($cgi->param('group_by')+2);$i<5;$i++) {
	$columns->[$i]->{visible} = 0;
      }
      $columns->[4]->{visible} = ($columns->[3]->{visible} == 1) ? 1 : 0;
      $subt = 1;
    } else {
      @$tdata = map { [ @$_[0..14] ] } @$data;
      splice( @$columns, 3, 0, {name => 'level 3', sortable => 1, filter => 1} );
      push @$columns, { name => "<input type='button' onclick='buffer_data(\"table\", \"".$t->id."\", \"17\", \"14\", \"0\", \"".$source."\", \"6\");' value='to workbench'>", input_type => 'checkbox', tooltip => 'check to select features<br>to add to workbench' };
      for (my $i=($cgi->param('group_by')+2);$i<6;$i++) {
	$columns->[$i]->{visible} = 0;
      }
      $columns->[5]->{visible} = (($columns->[4]->{visible} == 1) && ($source ne "Subsystems")) ? 1 : 0;
      $level3opt = "<option value='2'$l3>level 3</option>";
    }

    #### do the pivoting
    my $link  = $self->{mgdb}->link_for_source($source);
    my $dhash = {};
    my $colhashcount = {};
    my $newdata = [];
    foreach my $d (@$tdata) {
      my $range = 1 + $cgi->param('group_by');
      my $key = join(";", @$d[0..$range]);
      if (exists($dhash->{$key})) { # sum|sum|avg|avg|avg|avg|avg|avg|hash|num_hash
	$newdata->[$dhash->{$key}]->[6 - $subt] = $newdata->[$dhash->{$key}]->[6 - $subt] + $d->[6 - $subt];
	$newdata->[$dhash->{$key}]->[7 - $subt] = $newdata->[$dhash->{$key}]->[7 - $subt] + $d->[7 - $subt];
	$newdata->[$dhash->{$key}]->[8 - $subt] = (($newdata->[$dhash->{$key}]->[8 - $subt] * $colhashcount->{$key}) + $d->[8 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[9 - $subt] = (($newdata->[$dhash->{$key}]->[9 - $subt] * $colhashcount->{$key}) + $d->[9 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[10 - $subt] = (($newdata->[$dhash->{$key}]->[10 - $subt] * $colhashcount->{$key}) + $d->[10 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[11 - $subt] = (($newdata->[$dhash->{$key}]->[11 - $subt] * $colhashcount->{$key}) + $d->[11 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[12 - $subt] = (($newdata->[$dhash->{$key}]->[12 - $subt] * $colhashcount->{$key}) + $d->[12 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[13 - $subt] = (($newdata->[$dhash->{$key}]->[13 - $subt] * $colhashcount->{$key}) + $d->[13 - $subt]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[14 - $subt] = $newdata->[$dhash->{$key}]->[14 - $subt] . ";" . $d->[14 - $subt];
	$colhashcount->{$key}++;
      } else {
	$dhash->{$key} = scalar(@$newdata);
	$colhashcount->{$key} = 1;
	push(@$newdata, $d);
      }
    }
    my $test = [];
    foreach my $d (@$newdata) {
      my $abund  = 0;
      my $subab  = 0;
      my $subhit = 0;
      my %hasher = map { $_ => 1 } split(/;/, $d->[14 - $subt]);
      my $hits   = scalar(keys %hasher);
      push @$test, $hits;

      map { $abund += $md5_abund->{$d->[0]}{$_} } grep { exists($md5_abund->{$d->[0]}{$_}) } keys %hasher;
      map { $subab += $md5_abund->{$d->[0]}{$_} } grep { exists($md5_abund->{$d->[0]}{$_}) && exists($buffer_md5s{$_}) } keys %hasher;
      map { $subhit += 1 } grep { exists($hasher{$_}) } keys %buffer_md5s;

      $d->[6 - $subt]  = ($abund >= $hits) ? "<a onclick='abu(this, $tabnum, ".(14 - $subt).", \"RefSeq\");' style='cursor:pointer'>".$abund."</a>" : "<a onclick='abu(this, $tabnum, ".(14 - $subt).", \"RefSeq\");' style='cursor:pointer'>".$hits."</a>";
      $d->[7 - $subt]  = $subab;
      $d->[8 - $subt]  = sprintf("%.2f", $d->[8 - $subt]);
      $d->[9 - $subt]  = sprintf("%.2f", $d->[9 - $subt]);
      $d->[10 - $subt] = sprintf("%.2f", $d->[10 - $subt]);
      $d->[11 - $subt] = sprintf("%.2f", $d->[11 - $subt]);
      $d->[12 - $subt] = sprintf("%.2f", $d->[12 - $subt]);
      $d->[13 - $subt] = sprintf("%.2f", $d->[13 - $subt]);
      $d->[14 - $subt] = join(";", keys(%hasher));
      $d->[15 - $subt] = $hits;
      $d->[16 - $subt] = $subhit;

      if (($source eq "Subsystems") && $link) {
	my $link_term = $d->[3];
	$link_term =~ s/\s+/_/g;
	$d->[3] = "<a target=_blank href='".$link.$link_term."'>".$d->[3]."</a>";
      }
    }

    @$newdata = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] || $a->[4] cmp $b->[4] } @$newdata;    
    $t->columns($columns);
    $t->data($newdata);

    my $krona_button = "<input type='button' value='krona graph' onclick='generate_krona_data(\"".$cgi->param('group_by')."\", \"".$t->id."\", \"func\");'>";
    
    my $qiime_button = ($cgi->param('mg_grp_sel') && ($cgi->param('mg_grp_sel') eq 'groups')) ? 'Export for grouped data sets currently not available.<br> Please select <b>compare individually</b> in <b>(2) Data selection</b><br> above and recreate the table.' : "<button onclick='execute_ajax(\"qiime_export_visual\", \"qiime_div_$tabnum\", \"table_group_form_$tabnum\");show_progress();'>QIIME report</button>";
    
    my $plugin_container = '<table style="border: 2px solid rgb(143, 188, 63); text-align: center; float: right; border-spacing: 0px;"><tbody><tr><td colspan="2" style="cursor: pointer; text-align: left;" title="click to show available plugins" onclick="if(this.parentNode.nextSibling.style.display==\'none\'){this.parentNode.nextSibling.style.display=\'\';this.parentNode.nextSibling.nextSibling.style.display=\'\';}else{this.parentNode.nextSibling.style.display=\'none\';this.parentNode.nextSibling.nextSibling.style.display=\'none\';}"><img src="./Html/plugin.png" style="width: 20px; vertical-align: middle;"> available plugins</td></tr><tr><td style="border-top: 1px solid rgb(143, 188, 63); border-right: 1px solid rgb(143, 188, 63); padding: 2px;"><img src="./Html/krona.png" style="height: 50px; cursor: pointer;" onclick="window.open(&quot;http://sourceforge.net/p/krona/home/krona/&quot;);"></td><td style="border-top: 1px solid rgb(143, 188, 63);"><img onclick="window.open(&quot;http://www.qiime.org&quot;);" style="height: 50px; cursor: pointer;" src="./Html/qiime.png"></td></tr><tr><td style="vertical-align: middle; border-right: 1px solid rgb(143, 188, 63); padding: 2px;">'.$krona_button.'</td><td style="vertical-align: middle;">'.$qiime_button.'</td></tr></tbody></table>';
    
    my $qiime_div = "<div style='padding-left:15px; float: right;' id='qiime_div_$tabnum'></div>";

    my $pivot = "<form id='table_group_form_$tabnum'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='table'><input type='hidden' name='data_type' value='$source'><input type='hidden' name='ret_type' value='direct'>".$settings_preserve."<br><b>group table by</b> <select name='group_by'><option value='0'$l1>level 1</option><option value='1'$l2>level 2</option>$level3opt<option value='3'$l4>function</option></select><input type='button' value='change' onclick='execute_ajax(\"metabolism_visual\", \"tab_div_".($tabnum+1)."\", \"table_group_form_$tabnum\");'></form><br><br>";

    if ($cgi->param('ret_type') && $cgi->param('ret_type') eq 'direct') {
      return "$settings$plugin_container$qiime_div$pivot<br>".$t->output;
    }
##################

    $content .= "<div><div>Functional table $tabnum</div><div>".clear_progress_image()."$settings$plugin_container$qiime_div$pivot".$t->output."</div></div>";
    $tabnum++;
  }

  if ($cgi->param('vis_type') eq 'heatmap' || $cgi->param('vis_type') eq 'pca') {
    # format the data for .r analysis
    # data = [ mgid, level1, level2, level3, annotation, id, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s ]

    @comp_mgs = ();
    foreach my $mg ( $cgi->param('comparison_metagenomes') ) {
      if (exists $data_mgs{$mg}) {
	push @comp_mgs, $mg;
      }
    }    

    if (scalar(@comp_mgs) < 2) {
      return "<div><div>no data</div><div>".clear_progress_image().$missing_txt."Heatmap and PCoA analysis require at least two metagenomes with available data.</div></div>";
    } else {
      my $heatmap_data = [ [ '', map { my $x = $_; $x =~ s/\./A/; "ID".$x } @comp_mgs ] ];
      my $hashed_data = {};
      my $mg_ind = {};
      for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	$mg_ind->{$comp_mgs[$i]} = $i;
      }
      
      my $level = $cgi->param('heatmap_level') || 1;
      foreach my $d (@$data) {
	if (exists($hashed_data->{$d->[$level]})) {
	  if ($hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}]) {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] += $d->[6];
	  } else {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[6];
	  }
	} else {
	  $hashed_data->{$d->[$level]} = [];
	  $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[6];
	}
      }
      foreach my $key (keys(%$hashed_data)) {
	$key =~ s/,/---/g;
	my $row = [ $key ];
	foreach my $mg (@comp_mgs) {
	  if ($hashed_data->{$key}->[$mg_ind->{$mg}]) {
	    push(@$row, $hashed_data->{$key}->[$mg_ind->{$mg}]);
	  } else {
	    push(@$row, 0);
	  }
	}
	push(@$heatmap_data, $row);
      }
      
      # write data to a tempfile
      my ($fh, $infile) = tempfile( "rdataXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      foreach my $row (@$heatmap_data) {
	print $fh join("\t", @$row)."\n";
      }
      close $fh;
      chmod 0666, $infile;
      
      
      # preprocess data
      my $time = time;
      my $boxfile = "rdata.boxplot.$time.png";
      my ($prefh, $prefn) =  tempfile( "rpreprocessXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $prefh "source(\"".$Conf::bin."/norm_deseq.r\")\n";
      print $prefh "MGRAST_preprocessing(file_in = \"".$infile."\", file_out = \"".$Conf::temp."/rdata.preprocessed.$time\", image_out =\"".$Conf::temp."/$boxfile\", produce_fig = \"TRUE\")\n";
      close $prefh;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $prefn`;      
      unlink($prefn);

      unless (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) {
	unlink $infile;
	$infile = $Conf::temp."/rdata.preprocessed.$time";
      }

      if ($cgi->param('vis_type') eq 'heatmap') {
	my $hm_level_select = "<select name='heatmap_level'>";
	my $level_names = [];
	if ($data->[0]->[3] eq "-") {
	  $level_names = [ [ 1, 'level 1' ],
			   [ 2, 'level 2' ],
			   [ 4, 'function' ] ];
	} else {
	  $level_names = [ [ 1, 'level 1' ],
			   [ 2, 'level 2' ],
			   [ 3, 'level 3' ],
			   [ 4, 'function' ] ];
	}
	foreach my $l (@$level_names) {
	  my $sel = "";
	  if ($l->[0] == $level) {
	    $sel = " selected=selected";
	  }
	  $hm_level_select .= "<option value='".$l->[0]."'$sel>".$l->[1]."</option>";
	}
	$hm_level_select .= "</select>";
	$content .= "<div><div>Functional Heatmap $tabnum</div><div>".clear_progress_image()."<form id='heat_redraw$fid' onkeypress='return event.keyCode!=13'>$settings<br>The heatmap was clustered using ".($cgi->param('heatmap_clust_method') || 'ward')." with ".($cgi->param('heatmap_dist_method') || 'bray-curtis')." distance metric.<br>group heatmap by $hm_level_select<br>";

	my $selnorm = "";
	if ($cgi->param('raw')) {
	  $selnorm = " selected=selected";
	}
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('heatmap_dist_method') && ($cgi->param('heatmap_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	my $clustopts = "";
	foreach my $d (@{$self->cluster_methods}) {
	  my $sel = ($cgi->param('heatmap_clust_method') && ($cgi->param('heatmap_clust_method') eq $d)) ? " selected=selected" : "";
	  $clustopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "<input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='heatmap'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values, <select name='heatmap_clust_method'>$clustopts</select> clustering and <select name='heatmap_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"metabolism_visual\", \"tab_div_".($tabnum+1)."\", \"heat_redraw$fid\");'></div></form>";

	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"heatmap_canvas_$tabnum\");document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";;document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"\";'></div>";

	my ($col_f, $row_f) = ($Conf::temp."/rdata.col.$time", $Conf::temp."/rdata.row.$time");

	my ($heath, $heatn) =  tempfile( "rheatXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $heath "source(\"".$Conf::bin."/dendrogram.r\")\n";
	print $heath "MGRAST_dendrograms(file_in = \"".$infile."\", file_out_column = \"".$col_f."\", file_out_row = \"".$row_f."\", dist_method = \"".($cgi->param('heatmap_dist_method') || 'bray-curtis')."\", clust_method = \"".($cgi->param('heatmap_clust_method') || 'ward')."\", produce_figures = \"FALSE\")\n";
	close $heath;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $heatn`; 
	unlink($heatn);

	open(COL, "<$col_f");
	my $tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='columns_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";

	$tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='column_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='column_den_$tabnum' type='hidden' value='";
	while (<COL>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\s+/;
	}
	$content .= "'>";	

	close(COL);
	unlink($col_f);

	open(ROW, "<$row_f");
	  $tmp = <ROW>;
	  chomp $tmp;
	  $content .= "<input id='rows_$tabnum' type='hidden' value='";
	  $content .= join "^", split /,\s*/, $tmp;
	  $content .= "'>";

	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='row_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";

	$content .= "<input id='row_den_$tabnum' type='hidden' value='";
	while (<ROW>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\t/;	
	}
	$content .= "'>";
	
	close(ROW);
	unlink($row_f);

	my $cdata = "category\t".join("\t", @comp_mgs)."\n";
	open(D, "<$infile");
	my @values = 0;
	my $junk = <D>;
	$content .= "<input id='table_$tabnum' type='hidden' value='";
	while(<D>){
	  $cdata .= $_;
	  chomp;
	  my ($junk, $data) = split /\t/, $_, 2;
	  my @set = split /\t/, $data;
	  push @values, @set;
	  $content .= "@";
	  $content .= join "^", @set;
	}
	$content .= "'>";
	close(D);
	unlink $infile;
	$cdata =~ s/'/\&\#39\;/g;

	$content .= "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='$cdata'><input type='submit' value='download values used to generate this figure'></form>";

	my $max_val = max @values;
	$max_val  = ($max_val < 1) ? 1 : $max_val;
	$content .= $self->heatmap_scale($max_val)."<div id='heatmap_canvas_$tabnum'></div>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_heatmap(\"heatmap_canvas_$tabnum\", \"$tabnum\", \"$max_val\"); document.getElementById(\"progress_div\").innerHTML=\"\";'/></div></div>";
	$tabnum++;
      }
      if ($cgi->param('vis_type') eq 'pca') {
	my $time = time;
	my ($pca_data) = ($Conf::temp."/rdata.pca.$time");
	my ($pcah, $pcan) =  tempfile( "rpcaXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $pcah "source(\"".$Conf::bin."/plot_pco.r\")\n";
	print $pcah "MGRAST_plot_pco(file_in = \"".$infile."\", file_out = \"".$pca_data."\", dist_method = \"".($cgi->param('pca_dist_method') || 'bray-curtis')."\", headers = 1)\n";
	close $pcah;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $pcan`; 
	unlink($pcan);

	$content .= "<div><div>Functional PCoA $tabnum</div><div>$settings<i>$psettings</i><br><br>";
	
	my $selnorm  = (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) ? " selected=selected" : "";
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('pca_dist_method') && ($cgi->param('pca_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "<form id='meta_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='pca'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values and <select name='pca_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"metabolism_visual\", \"tab_div_".($tabnum+1)."\", \"meta_redraw$fid\");'></div></form>";
	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"pca_canvas_$tabnum\");document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"\";'></div>";

	my (@comp, @items);
	open(D, "<$pca_data");
	while(<D>){
	  chomp;
	  s/"//g;
	  my @fields = split /\t/;
	  if ($fields[0] =~ /^PCO\d+$/) {
	    push @comp, join("^", @fields); 
	  } elsif ($fields[0] =~ /^ID[\dA]+$/) {
	    push @items, join("^", @fields); 
	  }
	}
	close(D);

	# metadata coloring	
	my $mddb  = MGRAST::Metadata->new;
	my $jobmd = $mddb->get_metadata_for_tables(\@comp_mgs, 1, 1);
	my $mdata = {};
	# get unique labels accross all metagenomes
	foreach my $mgid (@comp_mgs) {
	    next unless ($jobmd->{$mgid});
	    foreach my $md (@{$jobmd->{$mgid}}) {
	        next if ($md->[1] =~ /(_id|_name)$/);
	        next if ($md->[1] =~ /^PI_/);
	        $mdata->{$md->[1]}{$mgid} = $md->[2];
        }
    }
    my @md_names = sort keys %$mdata;
    my $mgmd = [];
	my $iii  = 0;
    # get values for each metagenome
    foreach my $mgid (@comp_mgs) {
	    foreach my $md (@md_names) {
	        my $val = (exists($mdata->{$md}{$mgid}) && ($mdata->{$md}{$mgid} ne '')) ? $mdata->{$md}{$mgid} : undef;
            if ($val) { $val =~ s/'//g; }
            push @{ $mgmd->[$iii] }, $val;
        }
        $iii += 1;
    }
	my $md_type_select = "<select id='whichmd_".$tabnum."' onchange='check_metadata(\"$tabnum\", this);'>";
	foreach my $md_name (@md_names) {
	  $md_type_select .= "<option value='$md_name'>$md_name</option>";
	}
	$md_type_select .= "</select><input type='button' value='apply' onclick='color_by_metadata(\"$tabnum\");'>";

	my $comp_control = "<br><br><br><br><table><tr><th>component</th><th>r^2</th><th>x-axis</th><th>y-axis</th></tr>";
	my $i = 0;
	foreach my $row (@comp) {
	  my ($pcname, $rsquare) = split /\^/, $row;
	  $rsquare = sprintf("%.5f", $rsquare);
	  my $sel_x = '';
	  my $sel_y = '';
	  if ($i == 0) {
	    $sel_x = " checked=checked";
	  }
	  if ($i == 1) {
	    $sel_y = " checked=checked";
	  }
	  $comp_control .= "<tr><td>$pcname</td><td>$rsquare</td><td><input type='radio' name='xcomp$tabnum' id='xcomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_x></td><td><input type='radio' name='ycomp$tabnum' id='ycomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_y></td></tr>";
	  $i++;
	}
	$comp_control .= "</table>";

	my $group_control = "<div id='grpctrl$tabnum' style='display: none;'><br><br><br><div id='feedback$tabnum'></div><table><tr><th>group</th><th>name</th><th style='width: 56px;'>save as collection</th></tr>";
	$group_control .= "<tr><td>group 1</td><td><input type='text' id='group1_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"1\");'></td></tr>";
	$group_control .= "<tr><td>group 2</td><td><input type='text' id='group2_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"2\");'></td></tr>";
	$group_control .= "<tr><td>group 3</td><td><input type='text' id='group3_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"3\");'></td></tr>";
	$group_control .= "<tr><td>group 4</td><td><input type='text' id='group4_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"4\");'></td></tr>";
	$group_control .= "<tr><td>group 5</td><td><input type='text' id='group5_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"5\");'></td></tr>";
	$group_control .= "<tr><td>group 6</td><td><input type='text' id='group6_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"6\");'></td></tr>";
	$group_control .= "<tr><td>group 7</td><td><input type='text' id='group7_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"7\");'></td></tr>";
	$group_control .= "<tr><td>group 8</td><td><input type='text' id='group8_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"8\");'></td></tr>";
	$group_control .= "<tr><td>group 9</td><td><input type='text' id='group9_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"9\");'></td></tr>";
	$group_control .= "<tr><td>group 10</td><td><input type='text' id='group10_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"10\");'></td></tr>";
	$group_control .= "</table></div>";

	my $img_control = "<table><tr><td><div style='cursor: pointer; background-color: #8FBC3F; color: white; font-weight: bold; height: 16px; width: 250px; text-align: center; padding-top: 4px;' onclick='if(document.getElementById(\"imgctrl$tabnum\").style.display==\"none\"){document.getElementById(\"imgctrl$tabnum\").style.display=\"\";document.getElementById(\"grpctrl$tabnum\").style.display=\"\";}else{document.getElementById(\"imgctrl$tabnum\").style.display=\"none\";document.getElementById(\"grpctrl$tabnum\").style.display=\"none\";}' title='click to expand'>PCoA grouping control</div></td></tr><tr><td id='imgctrl$tabnum' style='display: none;'>";
	$img_control .= "<table><tr><td><div style='width: 280px;'><b>create a grouping</b><br>You can create a grouping of your metagenomes to calculate p-values in the barchart visualization. Select a group and click the metagenome circle in the graphic. You can also drag open a square to select multiple metagenomes at a time.</div><br><br>mark clicked as <select id='group_color$tabnum'><option value='red' selected=selected>group 1</option><option value='green'>group 2</option><option value='cyan'>group 3</option><option value='purple'>group 4</option><option value='yellow'>group 5</option><option value='blue'>group 6</option><option value='orange'>group 7</option><option value='gray'>group 8</option><option value='black'>group 9</option><option value='magenta'>group 10</option></select><br><br>or select groups in the table to the right.</td><td>";
	$img_control .= "<table><tr><th>Metagenome</th><th>group</th><th>$md_type_select</th></tr>";
	my $opts = "<option value='0'>- no group -</option><option value='group1'>group 1</option><option value='group2'>group 2</option><option value='group3'>group 3</option><option value='group4'>group 4</option><option value='group5'>group 5</option>";
	for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	  $img_control .= "<tr><td>".($comp_mgs[$i] || '')."</td><td><select id='group_list".$tabnum."_$i' onchange='change_pca_color(this, \"$tabnum\", \"$i\");'>$opts</select></td><td><span id='group_list_md_".$tabnum."_$i'>".($mgmd->[$i]->[0] || '')."</span></td></tr>";
	}
	$img_control .= "</table>";
	$img_control .= "<input type='button' value='store grouping' onclick='store_grouping(\"$tabnum\", \"".join("^", @comp_mgs)."\");'>";

	$img_control .= "<input type='hidden' id='pcamd_".$tabnum."' value='".join("~~", map { join(";;", map { defined($_) ? $_ : 'unknown' } @$_) } @$mgmd)."'></td></tr></table>";
	
	$img_control .= "</td></tr></table>";

	my @comp_b = @comp;
	my @items_b = @items;
	my $cmg_hash = {};
	%$cmg_hash = map { my ($x, $y) = $_ =~ /^(.*)\.(\d+)$/; "ID".$x."A".$y => $_; } @comp_mgs;
	my $data_download_button = "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='PCA Component impact\n".join("\n", map { $_ =~ s/\^/\t/g; $_; } @comp_b)."\n\nData Items\nMetagenome\t".join("\t", map { $_ =~ s/(.*)\t.*/$1/; $_; } @comp_b)."\n".join("\n", map { $_ =~ s/\^/\t/g; my ($x) = $_ =~ /^([^\t]+)/; $x = $cmg_hash->{$x}; $_ =~ s/^[^\t]+(.*)/$x$1/; $_; } @items_b)."'><input type='submit' value='download values used to generate this figure'></form>";

	$content .= "<input id='pca_components_$tabnum' type='hidden' value='".join("@",@comp)."'>";
	$content .= "<input id='pca_items_$tabnum' type='hidden' value='".join("@",@items)."'>";
	$content .= $img_control;
	$content .= "<table><tr><td><div id='pca_canvas_$tabnum'></div></td><td>$data_download_button".$comp_control.$group_control."</td></tr></table>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_pca(\"pca_canvas_$tabnum\", \"$tabnum\", 1,2); document.getElementById(\"progress_div\").innerHTML=\"\";'/></div></div>";
	$tabnum++;
      }
    }
  }
  
  return $content;
}

sub annotation_visual {
  my ($self) = @_;

  my $content = "";
  my $cgi  = $self->application->cgi;
  my $data = $self->annotation_data();
  # mgid, source, function, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
  #return "<div><div>test</div><div>".clear_progress_image()."<pre>".Dumper($data)."</pre></div></div>";

  my $tabnum = $cgi->param('tabnum') || 2;
  $tabnum--;

  unless (scalar(@$data)) {
    return "<div><div>no data</div><div>".clear_progress_image()."The visualizations you requested cannot be drawn, as no data met your selection criteria.</div></div>";
  }

  my %buffer_md5s = $cgi->param('use_buffer') ? map {$_, 1} split(/;/, $cgi->param('use_buffer')) : ();
  my $settings_preserve = "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'>";
  my @comp_mgs = $cgi->param('comparison_metagenomes');
  if ($cgi->param('mg_grp_sel') && $cgi->param('mg_grp_sel') eq 'groups') {
    $settings_preserve .= "<input type='hidden' name='mg_grp_sel' value='groups'>";
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_collections' value='".$mg."'>";
    }
  } else {
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_metagenomes' value='".$mg."'>";
    }
  }
  my $mgs = "";
  my $mgnames = [];
  @$mgnames = @comp_mgs;
  foreach my $metagenome (@$mgnames) {
    my $mgname = '';
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
    if (ref($job)) {
      $mgname = $job->name()." ($metagenome)";
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }
  if (scalar(@$mgnames) > 1) {
    my $last = pop(@$mgnames);
    $mgs .= "metagenomes ".join(", ", @$mgnames)." and $last";
  } else {
    $mgs .= "metagenome ".$mgnames->[0];
  }
  my $sorcs = "";
  my @sources = $cgi->param('source');
  foreach my $source (@sources) {
    $settings_preserve .= "<input type='hidden' name='source' value='".$source."'>";
  }
  if (scalar(@sources) > 1) {
    my $last = pop(@sources);
    $sorcs = join(", ", @sources)." and $last";
  } else {
    $sorcs = $sources[0];
  }
  my $cutoffs = "a maximum e-value of 1e-" . ($cgi->param('evalue') || '0') . ", ";
  $cutoffs   .= "a minimum identity of " . ($cgi->param('identity') || '0') . " %, ";
  $cutoffs   .= "and a minimum alignment length of " . ($cgi->param('alength') || '1') . ' measured in aa for protein and bp for RNA databases';

  my $psettings = " The data has been normalized to values between 0 and 1. If you would like to view raw values, redraw using the form below.";
  if ($cgi->param('raw')) {
    $psettings = " The data is showing raw values. If you would like to view normalized values, redraw using the form below.";
  }
  my $pset = "";
  if (defined($cgi->param('pval'))) {
    $pset = "<br><br>You have chosen to calculate p-values. They will appear in brackets after the category name.";
  }

  if ($cgi->param('use_buffer')) {
    $settings_preserve .= "<input type='hidden' name='use_buffer' value='".$cgi->param('use_buffer')."'>";
  }
  $settings_preserve .= "<input type='hidden' name='evalue' value='"   . ($cgi->param('evalue') || '0')   . "'>";
  $settings_preserve .= "<input type='hidden' name='identity' value='" . ($cgi->param('identity') || '0') . "'>";
  $settings_preserve .= "<input type='hidden' name='alength' value='"  . ($cgi->param('alength') || '1')  . "'>";
  my $fid = $cgi->param('fid') || int(rand(1000000));
    
  my $settings = "<i>This data was calculated for $mgs. The data was compared to $sorcs using $cutoffs.$pset</i><br/>";

  ## determine if any metagenomes missing from results
  my $missing_txt = "";
  my @missing_mgs = ();
  my %data_mgs    = map { $_->[0], 1 } @$data;

  foreach my $mg (@comp_mgs) {
    if (! exists $data_mgs{$mg}) {
      push @missing_mgs, $mg;
    }
  }
  
  if (@missing_mgs > 0) {
    $missing_txt = "<br>";
    foreach my $mg (@missing_mgs) {
      my $mgname = '';
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
      if (ref($job)) {
	$mgname = $job->name()." ($mg)";
      }
      $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>";
    }
    if (@missing_mgs > 1) {
      my $last = pop @missing_mgs;
      $missing_txt .= "Metagenomes " . join(", ", @missing_mgs) . " and $last contain";
    } else {
      $missing_txt .= "Metagenome " . $missing_mgs[0] . " contains";
    }
    $missing_txt .= " no organism data for the above selected sources and cutoffs. They are being excluded from the analysis.<br>";
  }
  $settings .= $missing_txt;

  if ($cgi->param('vis_type') eq 'table') {
    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->show_select_items_per_page(1);
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_column_select(1);
    $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});

    foreach my $d (@$data) {
      my %hasher = map { $_ => 1 } split(/;/, $d->[11]);
      my $hits   = scalar(keys %hasher);
      my $subhit = 0;
      map { $subhit += 1 } grep { exists($hasher{$_}) } keys %buffer_md5s;
      $d->[11] = join(";", keys %hasher);
      $d->[12] = $hits;
      $d->[13] = $subhit;
    }
    @$data = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] } @$data;

    my $columns = [ { name => 'metagenome', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'id of metagenomic sample' },
		    { name => 'source', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'database source of the hits' },
		    { name => 'function', sortable => 1, filter => 1 },
		    { name => 'abundance', sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		    { name => 'workbench abundance', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of sequence features with a hit<br>from workbench features' },
		    { name => 'avg eValue', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		    { name => 'eValue std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of the evalue,<br>showing exponent only' },
		    { name => 'avg % ident', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		    { name => '% ident std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the percent identity of the hits' },
		    { name => 'avg align len', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		    { name => 'align len std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the alignment length of the hits' },
		    { name => 'md5s2', visible => 0 },
		    { name => '# hits', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of unique hits in protein or rna database' },
		    { name => 'workbench # hits', sortable => 1, filter => 1, operators => ['less','more'], visible => ($cgi->param('use_buffer') ? 1 : 0), tooltip => 'number of unique hits in protein or rna database<br>from workbench features' },
		    { name => "<input type='button' onclick='buffer_data(\"table\", \"".$t->id."\", \"14\", \"11\", \"0\", \"1\", \"3\");' value='to workbench'>", input_type => 'checkbox', tooltip => 'check to select features<br>to add to workbench' } ];
    
    $t->columns($columns);
    $t->data($data);
    $content .= "<div><div>Annotation table $tabnum</div><div>".clear_progress_image().$settings.$t->output."</div></div>";
    $tabnum++;
  }

  return $content;
}

sub lca_visual {
  my ($self) = @_;

  my $content = "";
  my $cgi  = $self->application->cgi;
  my $data = $self->lca_data();
  # mgid, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv

  my $tabnum = $cgi->param('tabnum') || 2;
  $tabnum--;

  unless (scalar(@$data)) {
    return "<div><div>no data</div><div>".clear_progress_image()."The visualizations you requested cannot be drawn, as no data met your selection criteria.</div></div>";
  }

  my $settings_preserve = "<input type='hidden' name='metagenome' value='".$cgi->param('metagenome')."'>";
  my @comp_mgs = $cgi->param('comparison_metagenomes');
  if ($cgi->param('mg_grp_sel') && $cgi->param('mg_grp_sel') eq 'groups') {
    $settings_preserve .= "<input type='hidden' name='mg_grp_sel' value='groups'>";
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_collections' value='".$mg."'>";
    }
  } else {
    foreach my $mg (@comp_mgs) {
      $settings_preserve .= "<input type='hidden' name='comparison_metagenomes' value='".$mg."'>";
    }
  }
  my $mgs = "";
  my $mgnames = [];
  @$mgnames = @comp_mgs;
  foreach my $metagenome (@$mgnames) {
    my $mgname = '';
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
    if (ref($job)) {
      $mgname = $job->name()." ($metagenome)";
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }
  if (scalar(@$mgnames) > 1) {
    my $last = pop(@$mgnames);
    $mgs .= "metagenomes ".join(", ", @$mgnames)." and $last";
  } else {
    $mgs .= "metagenome ".$mgnames->[0];
  }

  my $cutoffs = "a maximum e-value of 1e-" . ($cgi->param('evalue') || '0') . ", ";
  $cutoffs   .= "a minimum identity of " . ($cgi->param('identity') || '0') . " %, ";
  $cutoffs   .= "and a minimum alignment length of " . ($cgi->param('alength') || '1') . ' measured in aa for protein and bp for RNA databases';

  my $psettings = " The data has been normalized to values between 0 and 1. If you would like to view raw values, redraw using the form below.";
  if ($cgi->param('raw')) {
    $psettings = " The data is showing raw values. If you would like to view normalized values, redraw using the form below.";
  }
  my $pset = "";
  if (defined($cgi->param('pval'))) {
    $pset = "<br><br>You have chosen to calculate p-values. They will appear in brackets after the category name.";
  }

  if ($cgi->param('use_buffer')) {
    $settings_preserve .= "<input type='hidden' name='use_buffer' value='".$cgi->param('use_buffer')."'>";
  }

  $settings_preserve .= "<input type='hidden' name='evalue' value='"   . ($cgi->param('evalue') || '0')   . "'>";
  $settings_preserve .= "<input type='hidden' name='identity' value='" . ($cgi->param('identity') || '0') . "'>";
  $settings_preserve .= "<input type='hidden' name='alength' value='"  . ($cgi->param('alength') || '1')  . "'>";

  my $fid = $cgi->param('fid') || int(rand(1000000));
  my $settings = "<i>This data was calculated for $mgs. The data was compared using $cutoffs.</i><br/>";

  ## determine if any metagenomes missing from results
  my $missing_txt = "";
  my @missing_mgs = ();
  my %data_mgs    = map { $_->[0], 1 } @$data;

  foreach my $mg (@comp_mgs) {
    if (! exists $data_mgs{$mg}) {
      push @missing_mgs, $mg;
    }
  } 

  my $sorcs = "lca";

  if (@missing_mgs > 0) {
    $missing_txt = "<br>";
    foreach my $mg (@missing_mgs) {
      my $mgname = '';
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
      if (ref($job)) {
	$mgname = $job->name()." ($mg)";
      }
      $mg = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>";
    }
    if (@missing_mgs > 1) {
      my $last = pop @missing_mgs;
      $missing_txt .= "Metagenomes " . join(", ", @missing_mgs) . " and $last contain";
    } else {
      $missing_txt .= "Metagenome " . $missing_mgs[0] . " contains";
    }
    $missing_txt .= " no lca data for the above selected sources and cutoffs. They are being excluded from the analysis.<br>";
  }
  $settings .= $missing_txt;
  
  if ($cgi->param('vis_type') eq 'vbar') {
    my $vbardata = [];
    if ($cgi->param('lca_bar_sel') && $cgi->param('lca_bar_col')) {
      @$vbardata = map { ($_->[$cgi->param('lca_bar_col')] && ($_->[$cgi->param('lca_bar_col')] eq $cgi->param('lca_bar_sel'))) ? $_ : () } @$data;
    } else {
      @$vbardata = map { $_ } @$data;
    }
    if ($cgi->param('lca_bar_col')) {
      $cgi->param('lca_bar_col', $cgi->param('lca_bar_col') + 1);
    }
    my $level = $cgi->param('lca_bar_col') ? ($cgi->param('lca_bar_col') + 1) : 2;
    my $noclick;
    if ($level > 8) {
      $noclick = 1;
    }
    my $dom_v = $self->data_to_vbar(undef, $vbardata, $level - 1, 10, ($cgi->param('top')||10), 'lca', $fid, ($cgi->param('raw') || undef), $noclick);

    $settings .= "<i>$psettings</i><br>";
    # check for p-value calculation
    if (defined($cgi->param('pval'))) {
      $settings_preserve .= "<input type='hidden' name='pval' value='".$cgi->param('pval')."'>";
      $settings_preserve .= "<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'>";
      my $mg2group = {};
      map { my ($g, $m) = split /\^/; $mg2group->{$m} = $g; } split /\|/, $cgi->param('pval');
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my ($pvalgroupf, $pvalgroupn) = tempfile( "rpvalgXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalgroupf join("\t", map { $mg2group->{$_} } @comp_mgs)."\n";
      close $pvalgroupf;
      my ($pvaldataf, $pvaldatan) = tempfile( "rpvaldXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvaldataf "\t".join("\t", map { "ID".$_ } @comp_mgs)."\n";
      my $cats = $dom_v->datasets();
      my $pd = $dom_v->data();
      my $i = 0;
      foreach my $row (@$pd) {
	print $pvaldataf $cats->[$i]."\t".join("\t", map { $_->[0] } @$row)."\n";
	$i++;
      }
      close $pvaldataf;
      my ($pvalsuggestf, $pvalsuggestn) = tempfile( "rpvalsXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalsuggestf;
      my ($pvalresultf, $pvalresultn) = tempfile( "rpvalrXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      close $pvalresultf;
      my ($pvalexecf, $pvalexecn) = tempfile( "rpvaleXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      my $rn = "normalized";
      if ($cgi->param('raw')) {
	$rn = "raw";
      }
      print $pvalexecf "source(\"".$Conf::bin."/suggest_stat_test.r\")\n";
      print $pvalexecf "MGRAST_suggest_test(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", paired = FALSE, file_out = \"".$pvalsuggestn."\")\n";
      close $pvalexecf;
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $pvalexecn`;
      open(FH, $pvalsuggestn);
      my $res = <FH>;
      chomp $res;
      close FH;
      $settings .= "<br><i>The p-values were calculated using $res and the following groups:</i><br>";
      $settings .= "<table><tr><th>metagenome</th><th>group</th></tr>";
      foreach my $cmg (@comp_mgs) {
	$settings .= "<tr><td>$cmg</td><td>".$mg2group->{$cmg}."</td></tr>";
      }
      $settings .= "</table><br>";
      my ($pvalexec2f, $pvalexec2n) = tempfile( "rpvale2XXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $pvalexec2f "source(\"".$Conf::bin."/do_stats.r\")\n";
      print $pvalexec2f "MGRAST_do_stats(data_file = \"".$pvaldatan."\", groups_file = \"".$pvalgroupn."\", data_type = \"".$rn."\", sig_test = \"".$res."\", file_out = \"".$pvalresultn."\")\n";
      close $pvalexec2f;
      `$R --vanilla --slave < $pvalexec2n`;
      open(FH, $pvalresultn);
      my $header = <FH>;
      my $pval_data = {};
      while (<FH>) {
	chomp;
	my @row = split /\t/;
	my $name = substr($row[0], 1, length($row[0])-2);
	my $stat = $row[scalar(@row)-2];
	my $pval = $row[scalar(@row)-1];
	$pval_data->{$name} = [ $stat, $pval ];
      }
      close FH;
      unlink($pvalgroupn);
      unlink($pvaldatan);
      unlink($pvalexecn);
      unlink($pvalexec2n);
      unlink($pvalsuggestn);
      unlink($pvalresultn);
      my $chash = {};
      for (my $i=0; $i<scalar(@$cats); $i++) {
	$chash->{$cats->[$i]} = $pd->[$i];
      }
      
      my $cats_pos = {};
      my $cind = 0;
      foreach my $k (@$cats) {
	$cats_pos->{$k} = $cind;
	$cind++;
      }

      @$cats = sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);
      @$pd = map { $chash->{$_} } sort { $pval_data->{$a}->[1] <=> $pval_data->{$b}->[1] } keys(%$chash);

      $cind = 0;
      foreach my $nc (@$cats) {
	$cats_pos->{$cind} = $cats_pos->{$nc};
	$cind++;
      }
      my $onclicks = $dom_v->data_onclicks;
      my $onclicks_title = $dom_v->title_onclicks;
      my $newonclicks = [];
      my $newonclicks_title = [];
      $cind = 0;
      foreach (@$onclicks) {
	push(@$newonclicks, $onclicks->[$cats_pos->{$cind}]);
	push(@$newonclicks_title, $onclicks_title->[$cats_pos->{$cind}]);
	$cind++;
      }
      $dom_v->data_onclicks($newonclicks);
      $dom_v->title_onclicks($newonclicks_title);

      $dom_v->data($pd);
      foreach my $cat (@$cats) {
	if (exists($pval_data->{$cat})) {
	  $cat = $cat." [".sprintf("%.4f", $pval_data->{$cat}->[1])."]";
	} else {
	  $cat = $cat." [-]";
	}
      }
      $dom_v->datasets($cats);
    }

    # generate a stringified version of the current data for download
    my $download_data = {};
    my $ii = 0;
    foreach my $bgroup (@{$dom_v->data}) {
      my $hh = 0;
      foreach my $bmg (@$bgroup) {
	my $jj = 0;
	foreach my $bsource (@$bmg) {
	  unless (exists($download_data->{$dom_v->supersets->[$jj]})) {
	    $download_data->{$dom_v->supersets->[$jj]} = {};
	  }
	  unless (exists($download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]})) {
	    $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]} = {};
	  }
	  $download_data->{$dom_v->supersets->[$jj]}->{$dom_v->datasets->[$ii]}->{$dom_v->subsets->[$hh]} = $bsource;
	  $jj++;
	}
	$hh++;
      }
      $ii++;
    }
    my $download_data_string = "";
    foreach my $key (sort(keys(%$download_data))) {
      $download_data_string .= "$key\\n";
      $download_data_string .= "\\t".join("\\t", sort(@{$dom_v->subsets}))."\\n";
      foreach my $k2 (sort(keys(%{$download_data->{$key}}))) {
	$download_data_string .= $k2."\\t".join("\\t", map { $download_data->{$key}->{$k2}->{$_} } sort(keys(%{$download_data->{$key}->{$k2}})))."\\n";
      }
      $download_data_string .= "\\n";
    }
    $download_data_string =~ s/'/\&rsquo\;/g;
    $download_data_string =~ s/"/\&rdquo\;/g;

    if ($level == 2) {
      $content .= "<div><div>LCA barchart $tabnum</div><div>";
      my $selnorm = "";
      if (defined($cgi->param('raw'))) {
	$content = "<div>";
	if ($cgi->param('raw') == '1') {
	  $selnorm = " selected=selected";
	}
      }
      $content .= "<form id='lca_drilldown$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='lca_bar_sel'><input type='hidden' name='lca_bar_col'><input type='hidden' name='fid'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<input type='hidden' name='raw' value='".($cgi->param('raw') || 0)."'></form>";
      $content .= clear_progress_image()."$settings<br>";
      $content .= "<form id='lca_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='vbar'><input type='hidden' name='top' value='1000'>$settings_preserve<div>You can redraw this barchart with different options:<br><br><table><tr><td rowspan=2 style='width: 50px;'>&nbsp;</td><td>use <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values</td><td rowspan=2 style='vertical-align: bottom; padding-left: 15px;'><input type='button' value='draw' onclick='execute_ajax(\"lca_visual\", \"tab_div_".($tabnum+1)."\", \"lca_redraw$fid\");'></td></tr><tr><td><input type='checkbox' value='' name='pval' onclick='check_group_selection(this, \"$tabnum\")'> calculate p-values</td></tr></table></div></form>";
      if (! defined($cgi->param('raw')) || ($cgi->param('raw') == '0')) {
	$content .= "The displayed data has been normalized to values between 0 and 1 to allow for comparison of differently sized samples.";
      }
      $content .= "<br><br>Click on a bar to drill down to the selected category (i.e. ".$vbardata->[0]->[2].")<br><br><div style='position: relative; float: right;'>".$dom_v->legend."</div><h3 style='margin-top: 0px;'>Domain Distribution <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'></h3>".$dom_v->output."<br><div id='3_$fid'></div></div></div>";
      $tabnum++;
    } else {
      my $header_names = { 3 => 'Phylum',
			   4 => 'Class',
			   5 => 'Order', 
			   6 => 'Family',
			   7 => 'Genus',
			   8 => 'Species',
			   9 => 'Strain' };
      @comp_mgs = $cgi->param('comparison_metagenomes');
      my $md5s = {};
      foreach my $row (@$vbardata) {
	if ($row->[$level - 1] eq $cgi->param('lca_bar_sel')) {
	  my @currmd5s = split /;/, $row->[scalar(@$row) - 1];
	  foreach my $cmd5 (@currmd5s) {
	    $md5s->{$cmd5} = 1;
	  }
	}
      }
      return clear_progress_image()."<h3 style='margin-top: 0px;'>".$header_names->{$level}." Distribution (".$cgi->param('lca_bar_sel').") <input type='button' value='download' title='click to download tabular data' onclick='myWindow=window.open(\"\",\"\",\"width=600,height=500\");myWindow.document.write(\"<pre>$download_data_string</pre>\");myWindow.focus();'> <input type='button' value='to workbench' onclick='buffer_data(\"barchart\", \"$level$fid\", \"$sorcs phylogenetic\", \"".$cgi->param('lca_bar_sel')."\", \"0\", \"".join(";",$cgi->param('source'))."\");'></h3></a>".$dom_v->output."<br><input type='hidden' id='$level$fid\_md5s' value='".join(";", keys(%$md5s))."'><input type='hidden' id='$level$fid\_mgids' value='".join(";", @comp_mgs)."'><div id='".(int($level)+1)."_$fid'></div>";
    }
  }
  
  if ($cgi->param('vis_type') eq 'tree') {
    @comp_mgs = $cgi->param('comparison_metagenomes');
    my $pt = $self->application->component('tree1');
    ## nasty id manipulation to allow for multiple trees
    my $newid = int(rand(100000));
    if ($cgi->param('oldid')) {
      $newid = $cgi->param('oldid');
    }
    $self->application->component('PhyloTreeHoverComponent'.$pt->id)->id($newid);
    $self->application->{component_index}->{'PhyloTreeHoverComponent'.$newid} = $self->application->component('PhyloTreeHoverComponent'.$pt->id);
    $self->application->component('HoverPie'.$pt->id)->id($newid);
    $self->application->{component_index}->{'HoverPie'.$newid} = $self->application->component('HoverPie'.$pt->id);
    $pt->id($newid);
    $pt->sample_names( [ $comp_mgs[0] ] );
    $pt->leaf_weight_type($cgi->param('lwt') || 'stack');
    $pt->show_tooltip(0);
    ##
    my $expanded_data = [];
    if (scalar(@comp_mgs) > 1) {
      $pt->coloring_method('split');
      $pt->sample_names( [ @comp_mgs ] );
      my $exp_hash = {};
      my $spec_hash = {};
      my $mg2num = {};

      for (my $hh=0; $hh<scalar(@comp_mgs); $hh++) {
	    $mg2num->{$comp_mgs[$hh]} = $hh;
      }
      foreach my $row (@$data) {
	    $spec_hash->{$row->[8]} = [ @$row[1..8] ];
	    unless (exists($exp_hash->{$row->[8]})) {
	      $exp_hash->{$row->[8]} = [];
	    }
	    $exp_hash->{$row->[8]}->[$mg2num->{$row->[0]}] = $row->[9];
      }
      foreach my $key (sort(keys(%$exp_hash))) {
	    my $vals = [];
	    for (my $ii=0; $ii<scalar(@comp_mgs); $ii++) {
	      push(@$vals, $exp_hash->{$key}->[$ii] || 0);
	    }
	    my $row = $spec_hash->{$key};
	    #foreach my $r (@$row) {
    	#  if ($r =~ /derived/) {
	    #    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	    #  }
	    #}
	    push(@$expanded_data, [ @$row, $vals ] );
      }
    } else {
      foreach my $row (@$data) {
	    #foreach my $r (@$row) {
	    #  if ($r =~ /derived/) {
	    #    (undef, $r) = $r =~ /^(unclassified \(derived from )(.+)(\))$/;
	    #  }
	    #}
	    push(@$expanded_data, [ @$row[1..9] ] );
      }
    }
    @$expanded_data = sort { $b->[8] <=> $a->[8] } @$expanded_data;
    $pt->data($expanded_data);
    $pt->show_leaf_weight(1);
    $pt->show_titles(1);
    $pt->shade_titles($cgi->param('title_level') || 2);
    $pt->enable_click(1);
    $pt->size(1000);
    $pt->depth($cgi->param('depth') || 4);
    $pt->level_distance(40);
    $pt->leaf_weight_space(60);
    $pt->color_leafs_only(1);
    $pt->reroot_field("reroot$tabnum");

    if ($self->application->cgi->param('reroot') && $self->application->cgi->param('do_reroot')) {
      $pt->reroot_id($self->application->cgi->param('reroot'));
    }

    if ($cgi->param('high_res')) {
      print $cgi->header(-charset => 'UTF-8');
      print $cgi->start_html();
      $pt->size(2500);
      $pt->level_distance(100);
      $pt->leaf_weight_space(150);
      $pt->enable_click(0);
      $pt->title_space(750);
      $pt->font_size($cgi->param('pts') || 20);
      $pt->{thick2} = 5;
      $pt->{thick} = 15;
      $pt->{style} = "width: 800; height: 800;";
      print $pt->output();
      print $cgi->end_html();
      exit;
    }

    my $pt_out;
    eval {
      $pt_out = $pt->output();
    };
    if ($@) {
      print STDERR $@."\n";
    }
    my $opts = [ [ 2, 'phylum' ],
		 [ 3, 'class' ],
		 [ 4, 'order' ],
		 [ 5, 'family' ],
		 [ 6, 'genus' ],
		 [ 7, 'species' ],
		 [ 8, 'strain' ] ];
    my $explain = "Color shading of the ".$opts->[$pt->depth - 1]->[1]." names indicates ".$opts->[$pt->shade_titles - 1]->[1]." membership.";
    $explain .= " Click on a node to get distributions of the entire hierarchy of this node. If you have selected a node, you can reroot the tree by checking the reroot checkbox and clicking the 'change' button. Clicking the change button with the reroot checkbox unchecked will draw the entire tree.";
    my $change_settings_form = "<form id='pt_form$newid'>$settings_preserve<input type='hidden' name='vis_type' value='tree'><input type='hidden' name='recalc' value='1'><input type='hidden' name='oldid' value='$newid'>";
    my $check1 = ' checked=checked';
    my $check2 = '';
    if ($cgi->param('lwt') && $cgi->param('lwt') eq 'bar') {
      $check2 = ' checked=checked';
      $check1 = '';
    }
    $change_settings_form .= "<b>display leaf weights as</b> <input type='radio' name='lwt' value='stack'$check1> stacked bar <input type='radio' name='lwt' value='bar'$check2> barchart<br>";
    $change_settings_form .= "<b>maximum level</b>&nbsp;&nbsp;<select name='depth'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->depth) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select>&nbsp;&nbsp;<b>color by</b> <select name='title_level'>";
    foreach my $row (@$opts) {
      my $sel = "";
      if ($row->[0] == $pt->shade_titles) {
	$sel = " selected=selected";
      }
      $change_settings_form .= "<option value='".$row->[0]."'$sel>".$row->[1]."</option>";
    }
    $change_settings_form .= "</select> <input type='hidden' name='reroot' value='".($self->application->cgi->param('reroot')||"")."' id='reroot$tabnum'> <input type='checkbox' name='do_reroot'> reroot at selected node <input type='button' onclick='execute_ajax(\"lca_visual\", \"pt$newid\", \"pt_form$newid\");' value='change'></form>";
    if ($cgi->param('recalc')) {
      return "$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out;
    } else {
      $content .= "<div><div>LCA tree $tabnum</div><div><div id='pt$newid'>".clear_progress_image()."$settings<p style='width: 800px;'>$explain</p>".$change_settings_form.$pt_out."</div></div></div>";
      $tabnum++;
    }
  }
  
  if ($cgi->param('vis_type') eq 'table') {
    my $t = $self->application->component('t1');
    ## nasty id manipulation to allow for multiple tables
    my $newid = int(rand(100000));
    $self->application->component('TableHoverComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
    $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
    $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
    $t->id($newid);
    ##
    $t->show_select_items_per_page(1);
    $t->show_top_browse(1);
    $t->show_bottom_browse(1);
    $t->items_per_page(15);
    $t->show_column_select(1);
    $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});

    my $tcols = [ { name => 'metagenome', filter => 1, operator => 'combobox', sortable => 1, tooltip => 'id of metagenomic sample' },
		  { name => 'domain', sortable => 1, filter => 1, operator => 'combobox' }, 
		  { name => 'phylum', sortable => 1, filter => 1 }, 
		  { name => 'class', sortable => 1, filter => 1 },
		  { name => 'order', sortable => 1, filter => 1 }, 
		  { name => 'family', sortable => 1, filter => 1 },
		  { name => 'genus', sortable => 1, filter => 1 },
		  { name => 'species', sortable => 1, filter => 1 },
		  { name => 'strain', sortable => 1, filter => 1 }, 
		  { name => 'abundance', sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
		  { name => 'avg eValue', visible => 1, sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
		  { name => 'eValue std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of the evalue,<br>showing exponent only' }, 
		  { name => 'avg % ident', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
		  { name => '% ident std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the percent identity of the hits' },
		  { name => 'avg align len', sortable => 1, visible => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
		  { name => 'align len std dev', visible => 0, sortable => 1, tooltip => 'standard deviation of<br>the alignment length of the hits' } ];
    
    #### do the pivoting
    unless (defined $cgi->param('group_by')) {
      $cgi->param('group_by', '2');
    }
    for (my $i=($cgi->param('group_by')+2);$i<9;$i++) {
      $tcols->[$i]->{visible} = 0;
    }
    my $dhash = {};
    my $colhashcount = {};
    my $newdata = [];
    foreach my $d (@$data) {
      my $range = 1 + $cgi->param('group_by');
      my $key = join(";", @$d[0..$range]);
      if (exists($dhash->{$key})) { # sum|avg|avg|avg|avg|avg|avg
	$newdata->[$dhash->{$key}]->[9] = $newdata->[$dhash->{$key}]->[9] + $d->[9];
	$newdata->[$dhash->{$key}]->[10] = (($newdata->[$dhash->{$key}]->[10] * $colhashcount->{$key}) + $d->[10]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[11] = (($newdata->[$dhash->{$key}]->[11] * $colhashcount->{$key}) + $d->[11]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[12] = (($newdata->[$dhash->{$key}]->[12] * $colhashcount->{$key}) + $d->[12]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[13] = (($newdata->[$dhash->{$key}]->[13] * $colhashcount->{$key}) + $d->[13]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[14] = (($newdata->[$dhash->{$key}]->[14] * $colhashcount->{$key}) + $d->[14]) / ($colhashcount->{$key} + 1);
	$newdata->[$dhash->{$key}]->[15] = (($newdata->[$dhash->{$key}]->[15] * $colhashcount->{$key}) + $d->[15]) / ($colhashcount->{$key} + 1);
	$colhashcount->{$key}++;
      } else {
	$dhash->{$key} = scalar(@$newdata);
	$colhashcount->{$key} = 1;
	push(@$newdata, $d);
      }
    }
    foreach my $d (@$newdata) {
      $d->[10] = sprintf("%.2f", $d->[10]);
      $d->[11] = sprintf("%.2f", $d->[11]);
      $d->[12] = sprintf("%.2f", $d->[12]);
      $d->[13] = sprintf("%.2f", $d->[13]);
      $d->[14] = sprintf("%.2f", $d->[14]);
      $d->[15] = sprintf("%.2f", $d->[15]);
    }

    @$newdata = sort { $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] || $a->[4] cmp $b->[4] || $a->[5] cmp $b->[5] || $a->[6] cmp $b->[6] || $a->[7] cmp $b->[7] || $a->[8] cmp $b->[8] || $a->[9] cmp $b->[9] } @$newdata;
    
    $t->columns($tcols);
    $t->data($newdata);

    my ($cd, $cp, $cc, $co, $cf, $cg, $cs) = ('', '', '', '', '', '', '');
    if ($cgi->param('group_by') eq '0') {
      $cd = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '1') {
      $cp = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '2') {
      $cc = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '3') {
      $co = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '4') {
      $cf = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '5') {
      $cg = " selected='selected'";
    } elsif ($cgi->param('group_by') eq '6') {
      $cs = " selected='selected'";
    }
    
    my $pivot = "<form id='table_group_form_$tabnum'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='table'><input type='hidden' name='ret_type' value='direct'>".$settings_preserve."<br><b>group table by</b> <select name='group_by'><option value='0'$cd>domain</option><option value='1'$cp>phylum</option><option value='2'$cc>class</option><option value='3'$co>order</option><option value='4'$cf>family</option><option value='5'$cg>genus</option><option value='6'$cs>species</option></select><input type='button' value='change' onclick='execute_ajax(\"lca_visual\", \"tab_div_".($tabnum+1)."\", \"table_group_form_$tabnum\");'></form><br><br>";

    if ($cgi->param('ret_type') && $cgi->param('ret_type') eq 'direct') {
      return "$settings$pivot<br>".$t->output;
    }

    $content .= "<div><div>LCA table $tabnum</div><div>".clear_progress_image()."$settings$pivot<br>".$t->output."</div></div>";
    $tabnum++;
  }
  
  if ($cgi->param('vis_type') eq 'heatmap' || $cgi->param('vis_type') eq 'pca') {
    # format the data for .r analysis
    # data = [ mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s ]
    
    @comp_mgs = ();
    foreach my $mg ( $cgi->param('comparison_metagenomes') ) {
      if (exists $data_mgs{$mg}) {
	push @comp_mgs, $mg;
      }
    }
    
    if (scalar(@comp_mgs) < 2) {
      return "<div><div>no data</div><div>".clear_progress_image().$missing_txt."Heatmap and PCoA analysis require at least two metagenomes with available data.</div></div>";
    } else {
      my $heatmap_data = [ [ '', map { my $x = $_; $x =~ s/\./A/; "ID".$x } @comp_mgs ] ];
      my $hashed_data = {};
      my $mg_ind = {};
      for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	$mg_ind->{$comp_mgs[$i]} = $i;
      }
      if (defined($cgi->param('heatmap_level'))) {
	$cgi->param('heatmap_level', $cgi->param('heatmap_level') + 1);
      }
      my $level = $cgi->param('heatmap_level') || 3;
      $level--;
      my $dd_col;
      my $dd_val;
      if ($cgi->param('drilldown') && $cgi->param('drilldown_on')) {
	($dd_col, $dd_val) = split(/;/, $cgi->param('drilldown'));
      }
      foreach my $d (@$data) {
	if (defined($dd_col)) {
	  next unless ($d->[$dd_col] eq $dd_val);
	}
	next unless ($d->[$level]);
	if (exists($hashed_data->{$d->[$level]})) {
	  if ($hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}]) {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] += $d->[9];
	  } else {
	    $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[9];
	  }
	} else {
	  $hashed_data->{$d->[$level]} = [];
	  $hashed_data->{$d->[$level]}->[$mg_ind->{$d->[0]}] = $d->[9];
	}
      }
      foreach my $key (keys(%$hashed_data)) {
	my $row = [ $key ];
	foreach my $mg (@comp_mgs) {
	  if ($hashed_data->{$key}->[$mg_ind->{$mg}]) {
	    push(@$row, $hashed_data->{$key}->[$mg_ind->{$mg}]);
	  } else {
	    push(@$row, 0);
	  }
	}
	push(@$heatmap_data, $row);
      }
      
      # write data to a tempfile
      my ($fh, $infile) = tempfile( "rdataXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      foreach my $row (@$heatmap_data) {
	print $fh join("\t", @$row)."\n";
      }
      close $fh;
      chmod 0666, $infile;
      
      # preprocess data
      my $time = time;
      my $boxfile = "rdata.boxplot.$time.png";
      my ($prefh, $prefn) =  tempfile( "rpreprocessXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
      print $prefh "source(\"".$Conf::bin."/norm_deseq.r\")\n";
      print $prefh "MGRAST_preprocessing(file_in = \"".$infile."\", file_out = \"".$Conf::temp."/rdata.preprocessed.$time\", image_out =\"".$Conf::temp."/$boxfile\", produce_fig = \"TRUE\")\n";
      close $prefh;
      
      my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
      `$R --vanilla --slave < $prefn`;
      unlink($prefn);
      
      unless (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) {
	unlink $infile;
	$infile = $Conf::temp."/rdata.preprocessed.$time";
      }
      
      if ($cgi->param('vis_type') eq 'heatmap') {
	my $level_names = [ [ 1, 'domain' ],
			    [ 2, 'phylum' ],
			    [ 3, 'class' ],
			    [ 4, 'order' ],
			    [ 5, 'family' ],
			    [ 6, 'genus' ],
			    [ 7, 'species' ],
			    [ 8, 'strain' ] ];
	my $dd_sel = "";
	my $hm_level_select = "<select name='heatmap_level'>";
	foreach my $l (@$level_names) {
	  my $sel = "";
	  if ($l->[0] == $level) {
	    $sel = " selected=selected";
	  }	  
	  if (defined($dd_col) && ($l->[0] == $dd_col)) {
	    $dd_sel = $l->[1];
	  }
	  $hm_level_select .= "<option value='".$l->[0]."'$sel>".$l->[1]."</option>";
	}
	$hm_level_select .= "</select>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "<div><div>LCA Heatmap $tabnum</div><div>".clear_progress_image();
	}
	$content .= "<form id='heat_drilldown$fid' onkeypress='return event.keyCode!=13'>$settings<br>The heatmap was clustered using ".($cgi->param('heatmap_clust_method') || 'ward')." with ".($cgi->param('heatmap_dist_method') || 'bray-curtis')." distance metric.<br>group heatmap by $hm_level_select <input type='hidden' name='vis_type' value='heatmap'><input type='hidden' id='tabnum2$fid' name='tabnum' value='".($tabnum+1)."'><br>";
	
	my $selnorm = "";
	if ($cgi->param('raw')) {
	  $selnorm = " selected=selected";
	}
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('heatmap_dist_method') && ($cgi->param('heatmap_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	my $clustopts = "";
	foreach my $d (@{$self->cluster_methods}) {
	  my $sel = ($cgi->param('heatmap_clust_method') && ($cgi->param('heatmap_clust_method') eq $d)) ? " selected=selected" : "";
	  $clustopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values, <select name='heatmap_clust_method'>$clustopts</select> clustering and <select name='heatmap_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"lca_visual\", \"tab_div_".($tabnum+1)."\", \"heat_drilldown$fid\");'></div></form>";
	
	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"heatmap_canvas_$tabnum\");document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"heatmap_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"heatmap_canvas_$tabnum\").style.display=\"\";'></div>";
	
	my ($col_f, $row_f) = ($Conf::temp."/rdata.col.$time", $Conf::temp."/rdata.row.$time");
	
	my ($heath, $heatn) =  tempfile( "rheatXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $heath "source(\"".$Conf::bin."/dendrogram.r\")\n";
	print $heath "MGRAST_dendrograms(file_in = \"".$infile."\", file_out_column = \"".$col_f."\", file_out_row = \"".$row_f."\", dist_method = \"".($cgi->param('heatmap_dist_method') || 'bray-curtis')."\", clust_method = \"".($cgi->param('heatmap_clust_method') || 'ward')."\", produce_figures = \"FALSE\")\n";
	close $heath;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $heatn`; 
	unlink($heatn);
	
	open(COL, "<$col_f");
	my $tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='columns_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";
	
	$tmp = <COL>;
	chomp $tmp;
	$content .= "<input id='column_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";
	
	$content .= "<input id='column_den_$tabnum' type='hidden' value='";
	while (<COL>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\s+/;
	}
	$content .= "'>";	
	
	close(COL);
	unlink($col_f);
	
	open(ROW, "<$row_f");
	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='rows_$tabnum' type='hidden' value='";
	$content .= join "^", split /,\s*/, $tmp;
	$content .= "'>";
	
	$tmp = <ROW>;
	chomp $tmp;
	$content .= "<input id='row_names_$tabnum' type='hidden' value='";
	$tmp =~ s/'/@!/g;
	$content .= join "^", split /,/, $tmp;
	$content .= "'>";
	
	$content .= "<input id='row_den_$tabnum' type='hidden' value='";
	while (<ROW>){
	  chomp;
	  $content .= "@";
	  $content .= join "^", split /\t/;	
	}
	$content .= "'>";
	
	close(ROW);
	unlink($row_f);
	
	open(D, "<$infile");
	my @values = 0;
	my $cdata = "category\t".join("\t", @comp_mgs)."\n";
	my $junk = <D>;
	
	$content .= "<input id='table_$tabnum' type='hidden' value='";
	while(<D>){
	  $cdata .= $_;
	  chomp;
	  my ($junk, $data) = split /\t/, $_, 2;
	  my @set = split /\t/, $data;
	  push @values, @set;
	  $content .= "@";
	  $content .= join "^", @set;
	}
	$content .= "'>";
	close(D);
	unlink $infile;
	
	$content .= "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='$cdata'><input type='submit' value='download values used to generate this figure'></form>";
	
	my $max_val = max @values;
	$max_val  = ($max_val < 1) ? 1 : $max_val;
	$content .= $self->heatmap_scale($max_val)."<div id='heatmap_canvas_$tabnum'></div>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_heatmap(\"heatmap_canvas_$tabnum\", \"$tabnum\", \"$max_val\"); document.getElementById(\"progress_div\").innerHTML=\"\";'/>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "</div></div>";
	}
	$tabnum++;
      }
      if ($cgi->param('vis_type') eq 'pca') {
	my $time = time;
	my ($pca_data) = ($Conf::temp."/rdata.pca.$time");
	my ($pcah, $pcan) =  tempfile( "rpcaXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
	print $pcah "source(\"".$Conf::bin."/plot_pco.r\")\n";
	print $pcah "MGRAST_plot_pco(file_in = \"".$infile."\", file_out = \"".$pca_data."\", dist_method = \"".($cgi->param('pca_dist_method') || 'bray-curtis')."\", headers = 1)\n";
	close $pcah;
	my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
	`$R --vanilla --slave < $pcan`; 
	unlink($pcan);
	if (! defined($cgi->param('raw'))) {
	  $content .= "<div><div>LCA PCoA $tabnum</div><div>";
	}
	$content .= "$settings<i>$psettings</i><br><br>";
	
	my $selnorm  = (defined($cgi->param('raw')) && ($cgi->param('raw') == '1')) ? " selected=selected" : "";
	my $distopts = "";
	foreach my $d (@{$self->distance_methods}) {
	  my $sel = ($cgi->param('pca_dist_method') && ($cgi->param('pca_dist_method') eq $d)) ? " selected=selected" : "";
	  $distopts .= "<option value='$d'$sel>$d</option>";
	}
	$content .= "<form id='lca_redraw$fid' onkeypress='return event.keyCode!=13'><input type='hidden' name='tabnum' value='".($tabnum+1)."'><input type='hidden' name='vis_type' value='pca'>$settings_preserve<div>redraw using <select name='raw'><option value='0'>normalized</option><option value='1'$selnorm>raw</option></select> values and <select name='pca_dist_method'>$distopts</select> distance <input type='button' value='draw' onclick='execute_ajax(\"lca_visual\", \"tab_div_".($tabnum+1)."\", \"lca_redraw$fid\");'></div></form>";
	$content .= "<br><div id='static$tabnum'>The image is currently dynamic. To be able to right-click/save the image, please click the static button <input type='button' value='static' onclick='document.getElementById(\"static$tabnum\").style.display=\"none\";document.getElementById(\"dynamic$tabnum\").style.display=\"\";save_image(\"pca_canvas_$tabnum\");document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"none\";'></div><div style='display: none;' id='dynamic$tabnum'>The image is currently static. You can right-click/save it. To be able to modify the image, please click the dynamic button <input type='button' value='dynamic' onclick='document.getElementById(\"static$tabnum\").style.display=\"\";document.getElementById(\"dynamic$tabnum\").style.display=\"none\";document.getElementById(\"pca_canvas_".$tabnum."canvas\").style.display=\"none\";document.getElementById(\"pca_canvas_$tabnum\").style.display=\"\";'></div>";
	
	my (@comp, @items);
	
	open(D, "<$pca_data");
	while(<D>){
	  chomp;
	  s/"//g; #"
	  my @fields = split /\t/;
	  if ($fields[0] =~ /^PCO\d+$/) {
	    push @comp, join("^", @fields); 
	  } elsif ($fields[0] =~ /^ID([\dA]+)$/) {
	    push @items, join("^", @fields); 
	  }
	}
	close(D);
	
	# metadata coloring	
	my $mddb  = MGRAST::Metadata->new;
	my $jobmd = $mddb->get_metadata_for_tables(\@comp_mgs, 1, 1);
	my $mdata = {};
	# get unique labels accross all metagenomes
	foreach my $mgid (@comp_mgs) {
	    next unless ($jobmd->{$mgid});
	    foreach my $md (@{$jobmd->{$mgid}}) {
	        next if ($md->[1] =~ /(_id|_name)$/);
	        next if ($md->[1] =~ /^PI_/);
	        $mdata->{$md->[1]}{$mgid} = $md->[2];
        }
    }
    my @md_names = sort keys %$mdata;
    my $mgmd = [];
	my $iii  = 0;
    # get values for each metagenome
    foreach my $mgid (@comp_mgs) {
	    foreach my $md (@md_names) {
	        my $val = (exists($mdata->{$md}{$mgid}) && ($mdata->{$md}{$mgid} ne '')) ? $mdata->{$md}{$mgid} : undef;
            if ($val) { $val =~ s/'//g; }
            push @{ $mgmd->[$iii] }, $val;
        }
        $iii += 1;
    }
	my $md_type_select = "<select id='whichmd_".$tabnum."' onchange='check_metadata(\"$tabnum\", this);'>";
	foreach my $md_name (@md_names) {
	  $md_type_select .= "<option value='$md_name'>$md_name</option>";
	}
	$md_type_select .= "</select><input type='button' value='apply' onclick='color_by_metadata(\"$tabnum\");'>";
	
	my $comp_control = "<br><br><br><br><table><tr><th>component</th><th>r^2</th><th>x-axis</th><th>y-axis</th></tr>";
	my $i = 0;
	foreach my $row (@comp) {
	  my ($pcname, $rsquare) = split /\^/, $row;
	  $rsquare = sprintf("%.5f", $rsquare);
	  my $sel_x = '';
	  my $sel_y = '';
	  if ($i == 0) {
	    $sel_x = " checked=checked";
	  }
	  if ($i == 1) {
	    $sel_y = " checked=checked";
	  }
	  $comp_control .= "<tr><td>$pcname</td><td>$rsquare</td><td><input type='radio' name='xcomp$tabnum' id='xcomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_x></td><td><input type='radio' name='ycomp$tabnum' id='ycomp$tabnum' onclick='check_pca_components($tabnum);' value='".($i+1)."'$sel_y></td></tr>";
	  $i++;
	}
	$comp_control .= "</table>";
	
	my $group_control = "<div id='grpctrl$tabnum' style='display: none;'><br><br><br><div id='feedback$tabnum'></div><table><tr><th>group</th><th>name</th><th style='width: 56px;'>save as collection</th></tr>";
	$group_control .= "<tr><td>group 1</td><td><input type='text' id='group1_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"1\");'></td></tr>";
	$group_control .= "<tr><td>group 2</td><td><input type='text' id='group2_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"2\");'></td></tr>";
	$group_control .= "<tr><td>group 3</td><td><input type='text' id='group3_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"3\");'></td></tr>";
	$group_control .= "<tr><td>group 4</td><td><input type='text' id='group4_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"4\");'></td></tr>";
	$group_control .= "<tr><td>group 5</td><td><input type='text' id='group5_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"5\");'></td></tr>";
	$group_control .= "<tr><td>group 6</td><td><input type='text' id='group6_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"6\");'></td></tr>";
	$group_control .= "<tr><td>group 7</td><td><input type='text' id='group7_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"7\");'></td></tr>";
	$group_control .= "<tr><td>group 8</td><td><input type='text' id='group8_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"8\");'></td></tr>";
	$group_control .= "<tr><td>group 9</td><td><input type='text' id='group9_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"9\");'></td></tr>";
	$group_control .= "<tr><td>group 10</td><td><input type='text' id='group10_collection_name' style='width: 140px;'></td><td><input type='button' value='save' onclick='save_group_to_collection(\"$tabnum\", \"10\");'></td></tr>";
	$group_control .= "</table></div>";
	
	my $img_control = "<table><tr><td><div style='cursor: pointer; background-color: #8FBC3F; color: white; font-weight: bold; height: 16px; width: 250px; text-align: center; padding-top: 4px;' onclick='if(document.getElementById(\"imgctrl$tabnum\").style.display==\"none\"){document.getElementById(\"imgctrl$tabnum\").style.display=\"\";document.getElementById(\"grpctrl$tabnum\").style.display=\"\";}else{document.getElementById(\"imgctrl$tabnum\").style.display=\"none\";document.getElementById(\"grpctrl$tabnum\").style.display=\"none\";}' title='click to expand'>PCoA grouping control</div></td></tr><tr><td id='imgctrl$tabnum' style='display: none;'>";
	$img_control .= "<table><tr><td><div style='width: 280px;'><b>create a grouping</b><br>You can create a grouping of your metagenomes to calculate p-values in the barchart visualization. Select a group and click the metagenome circle in the graphic. You can also drag open a square to select multiple metagenomes at a time.</div><br><br>mark clicked as <select id='group_color$tabnum'><option value='red' selected=selected>group 1</option><option value='green'>group 2</option><option value='cyan'>group 3</option><option value='purple'>group 4</option><option value='yellow'>group 5</option><option value='blue'>group 6</option><option value='orange'>group 7</option><option value='gray'>group 8</option><option value='black'>group 9</option><option value='magenta'>group 10</option></select><br><br>or select groups in the table to the right.</td><td>";
	$img_control .= "<table><tr><th>Metagenome</th><th>group</th><th>$md_type_select</th></tr>";
	my $opts = "<option value='0'>- no group -</option><option value='group1'>group 1</option><option value='group2'>group 2</option><option value='group3'>group 3</option><option value='group4'>group 4</option><option value='group5'>group 5</option><option value='group6'>group 6</option><option value='group7'>group 7</option><option value='group8'>group 8</option><option value='group9'>group 9</option><option value='group10'>group 10</option>";
	for (my $i=0; $i<scalar(@comp_mgs); $i++) {
	  $img_control .= "<tr><td>".($comp_mgs[$i] || '')."</td><td><select id='group_list".$tabnum."_$i' onchange='change_pca_color(this, \"$tabnum\", \"$i\");'>$opts</select></td><td><span id='group_list_md_".$tabnum."_$i'>".($mgmd->[$i]->[0] || '')."</span></td></tr>";
	}
	$img_control .= "</table>";
	$img_control .= "<input type='button' value='store grouping' onclick='store_grouping(\"$tabnum\", \"".join("^", @comp_mgs)."\");'>";
	
	$img_control .= "<input type='hidden' id='pcamd_".$tabnum."' value='".join("~~", map { join(";;", map { defined($_) ? $_ : 'unknown' } @$_) } @$mgmd)."'></td></tr></table>";
	
	$img_control .= "</td></tr></table>";
	
	my @comp_b = @comp;
	my @items_b = @items;
	my $cmg_hash = {};
	%$cmg_hash = map { my $x = $_; $x =~ s/\./A/; "ID".$x => $_; } @comp_mgs;
	my $data_download_button = "<form method=post action='download.cgi'><input type='hidden' name='filename' value='data.csv'><input type='hidden' name='content' value='PCA Component impact\n".join("\n", map { $_ =~ s/\^/\t/g; $_; } @comp_b)."\n\nData Items\nMetagenome\t".join("\t", map { $_ =~ s/(.*)\t.*/$1/; $_; } @comp_b)."\n".join("\n", map { $_ =~ s/\^/\t/g; my ($x) = $_ =~ /^([^\t]+)/; $x = $cmg_hash->{$x}; $_ =~ s/^[^\t]+(.*)/$x$1/; $_; } @items_b)."'><input type='submit' value='download values used to generate this figure'></form>";
	
	$content .= "<input id='pca_components_$tabnum' type='hidden' value='".join("@",@comp)."'>";
	$content .= "<input id='pca_items_$tabnum' type='hidden' value='".join("@",@items)."'>";
	$content .= $img_control;
	$content .= "<table><tr><td><div id='pca_canvas_$tabnum'></div></td><td>$data_download_button".$comp_control.$group_control."</td></tr></table>".&inlineImage($Conf::temp."/$boxfile", "width=600");
	$content .= "<img src='./Html/clear.gif' onload='draw_pca(\"pca_canvas_$tabnum\", \"$tabnum\", 1,2); document.getElementById(\"progress_div\").innerHTML=\"\";'/>";
	if (! defined($cgi->param('raw'))) {
	  $content .= "</div></div>";
	}
	$tabnum++;
      }
    }
  }
  
  return $content;
}

# sub recruitment_plot_visual {
#   my ($self) = @_;
# 
#   my $cgi   = $self->application->cgi;
#   my $orgid = $cgi->param('ref_genome');
#   my $mgid  = $cgi->param('metagenome');
#   my $eval  = $cgi->param('evalue_range');
#   my $map   = "circosmap";
#   my $tabnum  = $cgi->param('tabnum') || 2;
#   my $content = "";
#   $tabnum--;
# 
#   unless ($mgid) {
#     return "<div><div>Error</div><div>".clear_progress_image()."<p>No metagenome selected.</p></div></div>";
#   }
#   unless ($orgid) {
#     return "<div><div>No Data</div><div>".clear_progress_image()."<p>No refrence organisms available for the selected metagenome(s).</p></div></div>";
#   }
# 
#   $self->{mgdb}->set_jobs([$mgid]);
#   my $name_map = $self->{mgdb}->decode_annotation('organism', [$orgid]);
#   my $name = $name_map->{$orgid} ? $name_map->{$orgid} : '';
# 
#   if ($cgi->param('vis_type') eq 'circle') {
#     my ($file, $evals, $stats) = @{ $self->recruitment_plot_graph($name, $map) };
#     if (@$evals == 0) { return "<div><div>Error</div><div><p>$file</p></div></div>"; }
# 
#     my $eval_hist = $self->evalue_histogram($evals);
#     my $allctg    = $self->{mgdb}->ach->org2contignum($orgid);
#     my $plotctg   = $self->{mgdb}->ach->org2contignum($orgid, $self->data('min_ctg_len'));
# 
#     $content .= qq~<div><div>Recruitment Plot Map $tabnum</div><div>~.clear_progress_image().qq~<p><span style='font-size: 1.2em'><b>Hits for $mgid mapped on $name</b></span></p><p></p><table><tr><th>Hits Distribution by e-Value Exponent Range</th><th>Summary of Mapped Hits</th></tr><tr><td><img src="$eval_hist"/></td><td><table><tr><td>Features Mapped</td><td>$stats->[0]</td></tr><tr><td>Features Covered</td><td>$stats->[1]</td></tr><tr><td>Total Features</td><td>$stats->[2]</td></tr><tr><td>Contigs Shown</td><td>$plotctg</td></tr><tr><td>Total Contigs</td><td>$allctg</td></tr></table></td></tr></table><div><p>~.&inlineImage("$Conf::temp/$file.png", 'width=960 onmouseover="TJPzoom(this);"').qq~</p></div></div></div>~;
#     $tabnum++;
#   }
#   elsif ($cgi->param('vis_type') eq 'table') {
#     my $newid = int(rand(100000));
#     my ($data, $num_md5s) = $self->recruitment_plot_data($name, $mgid, $newid);
#     # id, low, high, strand, ctg, clen, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, abundance, md5
# 
#     my $jname = '';
#     my $job  = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mgid });
#     if (ref($job)) {
#       $jname = $job->name()." ($mgid)";
#     }
# 
#     my $settings = "<p>Contig information for $num_md5s unique sequences within metagenome <a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mgid' title='$jname'>$mgid</a> for organism $name" . (($eval ne 'None') ? " with a maximum e-value of $eval" : "") . "</p>";
# 
#     my $t = $self->application->component('t1');
#     ## nasty id manipulation to allow for multiple tables
#     $self->application->component('TableHoverComponent'.$t->id)->id($newid);
#     $self->application->{component_index}->{'TableHoverComponent'.$newid} = $self->application->component('TableHoverComponent'.$t->id);
#     $self->application->component('TableAjaxComponent'.$t->id)->id($newid);
#     $self->application->{component_index}->{'TableAjaxComponent'.$newid} = $self->application->component('TableAjaxComponent'.$t->id);
#     $t->id($newid);
#     ##
#     $t->show_select_items_per_page(1);
#     $t->show_top_browse(1);
#     $t->show_bottom_browse(1);
#     $t->items_per_page(15);
#     $t->show_column_select(1);
#     $t->show_export_button({ title => 'download this table', strip_html => 1, hide_invisible_columns => 1});
# 
#     my $columns = [ { name => $self->data('rplot_source').' id', sortable => 1, filter => 1, tooltip => 'database source ID of the hit' },
#           { name => 'function',          sortable => 1, filter => 1, tooltip => 'functional annotation of sequence' },
#           { name => '# reads hit',       sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'number of sequence features with a hit' },
#           { name => 'start position',    sortable => 1 },
#           { name => 'end position',      sortable => 1 },
#           { name => 'strand',            sortable => 1, filter => 1, operator => 'combobox' },
#           { name => 'contig name',       sortable => 1, filter => 1, operator => 'combobox' },
#           { name => 'contig length',     sortable => 1 },
#           { name => 'avg eValue',        sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average exponent of<br>the evalue of the hits' },
#           { name => 'eValue std dev',    sortable => 1, visible => 0, tooltip => 'standard deviation of the evalue<br>, showing exponent only' },
#           { name => 'avg % ident',       sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average percent identity of the hits' },
#           { name => '% ident std dev',   sortable => 1, visible => 0, tooltip => 'standard deviation of<br>the percent identity of the hits' },
#           { name => 'avg align len',     sortable => 1, filter => 1, operators => ['less','more'], tooltip => 'average alignment length of the hits' },
#           { name => 'align len std dev', sortable => 1, visible => 0, tooltip => 'standard deviation of<br>the alignment length of the hits' },
#           { name => 'md5',               visible => 0,                tooltip => 'md5 checksum of hit sequence'  }
#          ];
#     
#     $t->columns($columns);
#     $t->data($data);
#     $content .= qq~<div><div>Recruitment Plot Table $tabnum</div><div>~.clear_progress_image().$settings.$t->output.qq~<div id='read_div$newid'></div></div></div>~;
#     $tabnum++;
#   }
# 
#   return $content;
# }

sub qiime_export_visual {
  my ($self) = @_;
 
  my $content = "";
  my $type  = $self->application->cgi->param('data_type') || 'organism';
  my @mgs   = $self->application->cgi->param('comparison_metagenomes');
  my $eval  = $self->application->cgi->param('evalue')   || '0';
  my $ident = $self->application->cgi->param('identity') || '0';
  my $alen  = $self->application->cgi->param('alength')  || '1';

  use Digest::MD5 qw( md5_base64 );
  my $fn = md5_base64(join("", @mgs, $type, $eval, $ident, $alen));
  $fn =~ s/\//_/g;
  $fn =~ s/\+/\./g;

  unless (-f $Conf::temp."/download.$fn") {
    my $data = $self->qiime_export_data(\@mgs, $type);
    my $jobs = [];
    my $rast = $self->application->data_handle('MGRAST');
    foreach my $mg (@mgs) {
      my $job = $rast->Job->init( { metagenome_id => $mg } );
      if (ref($job)) {
	push(@$jobs, $job);
      }
    }
    my $meta = MGRAST::Metadata->new;
    $meta->export_metadata_for_jobs($jobs, "download.md".$fn, 'tag');
    if (ref($data)) {
      use JSON;
      my $json = new JSON;
      $json = $json->utf8();
      if (open(FH, ">".$Conf::temp."/download.$fn")) {
	print FH $json->encode($data);
	close FH;
      } else {
	return clear_progress_image()."Error - Could not write file: $! $@";
      }
    } else {
      return clear_progress_image()."Error - no data matched your query";
    }
  }
  $content = clear_progress_image()."<table><tr><td><b>click to download: </b></td><td><a href='metagenomics.cgi?page=Analysis&action=download&file=$fn&filename=QIIME.$type.data.biom'>QIIME data file</a></td></tr><tr><td></td><td><a href='metagenomics.cgi?page=Analysis&action=download&file=md$fn&filename=QIIME.$type.metadata.tsv'>QIIME metadata file</a></td></tr></table>";
  
  return $content;
}

########################
# v-bar data formatting
########################
sub data_to_vbar {
  my ($self, $md5_abund, $data, $colnum, $countrow, $topx, $source, $id, $raw, $noclick) = @_;

  my $cgi = new CGI;
  my $single = 0;
  if (($source eq 'single') || ($source eq 'lca')) {
    $single = 1;
  }
  my $selsource = $cgi->param('source') || 'lca';

  $raw = defined($self->application->cgi->param('raw')) ? $self->application->cgi->param('raw') : 0;
  my $v = $self->application->component('v'.$colnum);

  ## nasty id manipulation to allow for multiple vbars
  my $newid = int(rand(100000));
  $self->application->component('VerticalBarChartHover'.$v->id)->id($newid);
  $self->application->{component_index}->{'VerticalBarChartHover'.$newid} = $self->application->component('VerticalBarChartHover'.$v->id);
  $v->id($newid);
  ##
  
  my @mgs = $self->application->cgi->param('comparison_metagenomes');
  my @sources = $self->application->cgi->param('source') || ( 'lca' );

  $v->scale_step(0.1 * scalar(@sources));
  if ($raw) {
    $v->show_percent(1);
    $v->scale_step(10);
  }

  # calculate overview data
  my $vdata  = [];
  my $stdev  = [];
  my $counts = {};  # mg => category => source => {raw, log2, norm, scale, md5s}
  my %cats   = map { $_->[$colnum], {} } @$data; # all categories => {vals, stat} (1 source only)
  my %srcs   = map { $_->[1], {} } @$data;       # all sources => {log2, stat, norm, max, min}
  if ($single) {
    %srcs = ( $selsource => {} );
  }
  my $snum   = scalar(keys %srcs);
  my %catnum = map { $_, 0 } keys %cats;

  foreach my $row (@$data) {
    unless (defined($row->[0]) && defined($row->[$colnum]) && defined($row->[$countrow])) { next; };
    unless (exists $counts->{$row->[0]}) {
      foreach my $cat (keys %cats) {
	foreach my $src (keys %srcs) {
	  $counts->{$row->[0]}{$cat}{$src} = {raw => 0, log2 => 0, norm => 0, scale => 0, md5s => {}};	  
	}
      }
    }
    if ($single) {
      $counts->{$row->[0]}{$row->[$colnum]}{$selsource}{raw} += $row->[$countrow];
      unless ($selsource eq 'lca') {
	map { $counts->{$row->[0]}{$row->[$colnum]}{$selsource}{md5s}{$_} = 1 } @{$row->[-1]};
      }
    } else {
      map { $counts->{$row->[0]}{$row->[$colnum]}{$row->[1]}{md5s}{$_} = 1 } split(/;/, $row->[-1]);
    }
  }

  # do this by default
  unless ($raw) {
    # get log2 data
    foreach my $mg (keys %$counts) {
      foreach my $cat (keys %{$counts->{$mg}}) {
	foreach my $src (keys %{$counts->{$mg}{$cat}}) {
	  unless ($single) {
	    map { $counts->{$mg}{$cat}{$src}{raw} += $md5_abund->{$mg}{$_} } grep {exists $md5_abund->{$mg}{$_}} keys %{$counts->{$mg}{$cat}{$src}{md5s}};
	  }
	  $counts->{$mg}{$cat}{$src}{log2} = 2 * (log($counts->{$mg}{$cat}{$src}{raw} + 1) / log(2));
	  push @{ $srcs{$src}{log2} }, $counts->{$mg}{$cat}{$src}{log2};
	}
      }
    }
    foreach my $src (keys %srcs) {
      $srcs{$src}{stat} = new Statistics::Descriptive::Full;
      $srcs{$src}{stat}->add_data( @{$srcs{$src}{log2}} );
    }
    
    # normalize data
    foreach my $mg (keys %$counts) {
      foreach my $cat (keys %{$counts->{$mg}}) {
	foreach my $src (keys %{$counts->{$mg}{$cat}}) {
	  $counts->{$mg}{$cat}{$src}{norm} = ($counts->{$mg}{$cat}{$src}{log2} - $srcs{$src}{stat}->mean) / ($srcs{$src}{stat}->standard_deviation || 1);
	  push @{ $srcs{$src}{norm} }, $counts->{$mg}{$cat}{$src}{norm};
	}
      }
    }
    
    # scale data
    foreach my $src (keys %srcs) {
      $srcs{$src}{min}   = min @{ $srcs{$src}{norm} };
      $srcs{$src}{range} = (max @{ $srcs{$src}{norm} }) + abs($srcs{$src}{min});
    }
    foreach my $mg (keys %$counts) {
      foreach my $cat (keys %{$counts->{$mg}}) {
	foreach my $src (keys %{$counts->{$mg}{$cat}}) {
	  if ($srcs{$src}{min} > 0) {
	    $counts->{$mg}{$cat}{$src}{scale} = ($counts->{$mg}{$cat}{$src}{norm} - $srcs{$src}{min}) / $srcs{$src}{range};
	  } elsif ($srcs{$src}{min} < 0) {
	    $counts->{$mg}{$cat}{$src}{scale} = ($counts->{$mg}{$cat}{$src}{norm} + abs($srcs{$src}{min})) / $srcs{$src}{range};
	  }
	  # get top value per category
	  $catnum{$cat} = max ($catnum{$cat}, $counts->{$mg}{$cat}{$src}{scale});
	  # get stdev per mg group
	  if ($snum == 1) { push @{ $cats{$cat}{vals} }, $counts->{$mg}{$cat}{$src}{scale}; }
	}
      }
    }
  }
  else {
    foreach my $mg (keys %$counts) {
      foreach my $cat (keys %{$counts->{$mg}}) {
	foreach my $src (keys %{$counts->{$mg}{$cat}}) {
	  # get top value per category
	  unless ($single) {
	    map { $counts->{$mg}{$cat}{$src}{raw} += $md5_abund->{$mg}{$_} } grep {exists $md5_abund->{$mg}{$_}} keys %{$counts->{$mg}{$cat}{$src}{md5s}};
	  }
	  $catnum{$cat} = max ($catnum{$cat}, $counts->{$mg}{$cat}{$src}{raw});
	  # get stdev per mg group
	  if ($snum == 1) { push @{ $cats{$cat}{vals} }, $counts->{$mg}{$cat}{$src}{raw}; }
	}
      }
    }
  }

  if ($snum == 1) {
    foreach my $cat (keys %cats) {
      $cats{$cat}{stat} = new Statistics::Descriptive::Full;
      $cats{$cat}{stat}->add_data( @{$cats{$cat}{vals}} );
    }
  }

  # keep top topx or 10 only 
  $topx = $topx ? $topx : 10;
  my @topcat = sort { $catnum{$b} <=> $catnum{$a} } keys %catnum;
  if (scalar(@topcat) > $topx) { splice @topcat, $topx; }
  my $data_onclicks  = [];
  my $title_onclicks = [];
  my $i = 0;
  foreach my $cat (@topcat) {
    my $row = [];
    my $r2  = [];
    my $h = 0;
    $data_onclicks->[$i] = [];
    foreach my $mg (@mgs) {
      my $cell = [];
      my $c2   = [];
      my $j = 0;
      $data_onclicks->[$i]->[$h] = [];
      foreach my $src (@sources) {
	if ($raw) {
	  push @$cell, $counts->{$mg}{$cat}{$src}{raw};
	} else {
	  push @$cell, sprintf("%.3f", ($counts->{$mg}{$cat}{$src}{scale} || 0));
	}
	if ($snum == 1) { push @$c2, $cats{$cat}{stat}->standard_deviation; }
	if ($source eq 'phylo' && $id) {
	  $title_onclicks->[$i] = "document.getElementById(\"phylo_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"phylo_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"phylo_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"phylogeny_visual\",\"".(int($colnum)+1)."_$id\",\"phylo_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	  $data_onclicks->[$i]->[$h]->[$j] = "document.getElementById(\"phylo_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"phylo_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"phylo_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"phylogeny_visual\",\"".(int($colnum)+1)."_$id\",\"phylo_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	} elsif ($source eq 'meta' && $id) {
	  $title_onclicks->[$i] = "document.getElementById(\"meta_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"meta_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"meta_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"metabolism_visual\",\"".(int($colnum)+1)."_$id\",\"meta_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	  $data_onclicks->[$i]->[$h]->[$j] = "document.getElementById(\"meta_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"meta_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"meta_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"metabolism_visual\",\"".(int($colnum)+1)."_$id\",\"meta_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	} elsif ($source eq 'single' && $id) {
	  $title_onclicks->[$i] = "document.getElementById(\"single_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"single_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"single_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"single_visual\",\"".(int($colnum)+2)."_$id\",\"single_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	  $data_onclicks->[$i]->[$h]->[$j] = "document.getElementById(\"single_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"single_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"single_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"single_visual\",\"".(int($colnum)+2)."_$id\",\"single_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	} elsif ($source eq 'lca' && $id) {
	  $title_onclicks->[$i] = "document.getElementById(\"lca_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"lca_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"lca_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"lca_visual\",\"".(int($colnum)+2)."_$id\",\"lca_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	  $data_onclicks->[$i]->[$h]->[$j] = "document.getElementById(\"lca_drilldown$id\").firstChild.value=\"".$topcat[$i]."\";document.getElementById(\"lca_drilldown$id\").firstChild.nextSibling.value=\"$colnum\";document.getElementById(\"lca_drilldown$id\").firstChild.nextSibling.nextSibling.value=\"$id\";execute_ajax(\"lca_visual\",\"".(int($colnum)+2)."_$id\",\"lca_drilldown$id\",\"loading...\", null, load_tabs);show_progress();";
	}
	$j++;
      }
      push @$row, $cell;
      push @$r2, $c2;
      $h++;
    }
    push @$vdata, $row;
    push @$stdev, $r2;
    $i++;
  }
  
  # create a vertical barchart
  if ($snum == 1) { $v->error_bars($stdev); }
  $v->data($vdata);
  $v->datasets(\@topcat);
  $v->subsets(\@mgs);
  $v->supersets(\@sources);
  unless ($noclick) {
    $v->data_onclicks($data_onclicks);
    $v->title_onclicks($title_onclicks);
  }
  $v->width(800);

  return $v;
}

###################
# helper functions
###################
sub distance_methods {
  return ["bray-curtis","euclidean","maximum","manhattan","canberra","minkowski","difference"];
}

sub cluster_methods {
  return ["ward","single","complete","mcquitty","median","centroid"];
}

sub generate_tab {
  my ($self, $name, $content, $id, $no_closer, $inactive) = @_;

  my $doubleclick = " title='double-click to change title' ondblclick='mod_title(this);'";
  if ($no_closer) {
    $doubleclick = "";
  }
  my $isactive = "active_disp";
  if ($inactive) {
    $isactive = "inactive_disp";
  }
  my $header = "<td class='$isactive' name='tab_title' id='tab_title_$id' onclick='activate_tab(\"$id\");'><span>$name</span>";

  unless ($no_closer) {
    $header .= "<img src='./Html/mg-logout.png' style='width: 12px; height: 12px; position: relative; top: -6px; right: -7px; border-left: 1px solid #E6E5D3; border-bottom: 1px solid #E6E5D3;' onclick='remove_tab(\"$id\");'>";
  }
  $header .= "</td>";

  my $tab = "<div class='$isactive' id='tab_div_$id' name='tab_div'>".$content."</div>";

  return ($header, $tab);
}

sub more_button {
  my ($self, $onclicka, $onclickb) = @_;

  my $button;

  # if ($onclickb) {
#     $button = "<a style='border: 1px solid #8FBC3F; padding-left: 3px; padding-right: 3px; font-size: 8px; padding-bottom: 1px; position: relative; top: 1px; color: #8FBC3F; cursor: pointer;' onclick='if(this.innerHTML==\"+\"){this.innerHTML=\"-\";$onclicka}else{this.innerHTML=\"+\";$onclickb};'>+</a>";
#   } else {
    $button = "<a style='border: 1px solid #8FBC3F; padding-left: 3px; padding-right: 3px; font-size: 8px; padding-bottom: 1px; position: relative; top: 1px; color: #8FBC3F; cursor: pointer;' onclick='$onclicka;'>+</a>";
#  }

  return $button;
}

sub get_log {
  my ($self, $log, $num) = @_;

  if ($log < 2) { return $num; }
  if (($num == 0) || ($num == 1) || ($num == -1)) {
    return $num;
  }
  else {
    if ($num < 0) { $num =~ s/^-//; }
    return int($log * (log($num) / log($log)));
  }
}

sub get_evals {
  return [ 1e-3, 1e-5, 1e-10, 1e-20, 1e-30 ];
}

sub get_eval_index {
  my ($self, $eval) = @_;
  my $last = scalar( @{$self->get_evals} ) - 1;
  my @idxs = grep { $self->get_evals->[$_] eq $eval } 0..$last;
  return @idxs ? $idxs[0] : undef;
}

sub evalue_histogram {
  my ($self, $evals) = @_;

  my $width = 400;
  my $evalue_hist  = new WebGD($width, (scalar @$evals) * 20);
  my $evalue_range = { 1e-3  => "-3 to -5",
		       1e-5  => "-5 to -10",
		       1e-10 => "-10 to -20",
		       1e-20 => "-20 to -30",
		       1e-30 => "-30 and less" };
  my $colors = { 'white'  => $evalue_hist->colorAllocate(255,255,255),
		 'black'  => $evalue_hist->colorAllocate(0,0,0),
		 'red'    => $evalue_hist->colorAllocate(247,42,66),
		 'orange' => $evalue_hist->colorAllocate(255,136,0),
		 'yellow' => $evalue_hist->colorAllocate(255,255,0),
		 'green'  => $evalue_hist->colorAllocate(51,204,94),
		 'blue'   => $evalue_hist->colorAllocate(54,116,217)
	       };

  $evalue_hist->transparent($colors->{white});
  $evalue_hist->interlaced('true');

  my $key_size = (max map { length($_) } values %$evalue_range) * gdSmallFont->width;
  my ($hx1, $hx2, $hy1, $hy2) = (1, $key_size+6, 1, 19);
  my $x2;

  my @counts_sorted = sort {$b <=> $a} map { $_->[1] } @$evals;
  my $scale = $counts_sorted[0] / ($width - $key_size - 20);
  
  for (my $i=(@$evals-1); $i>=0; $i--) {
    $x2 = $hx2 + int($evals->[$i][1] / $scale);
    $evalue_hist->filledRectangle($hx2+2, $hy1, $x2, $hy2, $colors->{$evals->[$i][2]});
 
    $evalue_hist->filledRectangle($hx1, $hy1, $hx2, $hy2, $colors->{$evals->[$i][2]});
    $evalue_hist->string(gdSmallFont, ($hx1 + 3), ($hy1 +2), $evalue_range->{$evals->[$i][0]}, $colors->{black});

    my $stringlength = (length($evals->[$i][1]) * 5) + 5;
    $evalue_hist->string(gdSmallFont,((($x2 < ($hx2 + $stringlength)) ? ($x2+3) : ($x2-$stringlength))),($hy1+2),$evals->[$i][1],$colors->{black});
    $hy1 += 20;
    $hy2 += 20;
  }

  return $evalue_hist->image_src();
}

sub get_img_map {
  my ($self, $file) = @_;

  my $i = 1;
  my @text;
  my $tooltip = $self->app->component('rplotHover');
  my $tt_id   = $tooltip->id;

  open(FILE, "<$file") || return "";
  while (my $line = <FILE>) {
    chomp $line;
    if ($line =~ /href='(\S+?)'/) {
      my $add = qq(onmouseover='hover(event, "circos_tt_$i", "$tt_id");');
      $tooltip->add_tooltip("circos_tt_$i", $1);      
      $line =~ s/href='\S+?'/$add/;
      $line =~ s/title='\S+?'//;
      $i++;
    }
    push @text, $line;
  }
  close FILE;
  return $tooltip->output() . join("\n", @text);
}

sub get_data_from_config {
  my ($self, $file) = @_;

  my (@evals, @stats);
  open(FILE, "<$file") || return "";
  while (my $line = <FILE>) {
    chomp $line;
    if ($line =~ /#evals\s+(\S+)/) {
      @evals = split(/,/, $1);
    }
    if ($line =~ /#stats\s+(\S+)/) {
      @stats = split(/,/, $1);
    }
  }
  close FILE;

  return (\@evals, \@stats);
}

###################
# select functions
###################
sub scale_select {
  my ($self) = @_;

  my $select = "<select name='scale'>";
  $select .= "<option value='1'>linear</option>";
  $select .= "<option value='2'>log2</option>";
  $select .= "<option value='10'>log10</option>";
  $select .= "</select><input type='button' onclick='this.parentNode.previousSibling.previousSibling.innerHTML=this.previousSibling.options[this.previousSibling.selectedIndex].text;this.parentNode.style.display=\"none\";' value='ok'>";

  return $select;
}

sub evalue_range_select {
  my ($self) = @_;

  my $eval   = $self->application->cgi->param('evalue_range') || '';
  my $select = "<select name='evalue_range'>";

  foreach ( @{ $self->get_evals } ) {
    my $sel  = ($_ eq $eval) ? " selected='selected'" : "";
    $select .= "<option value='$_'$sel>$_</option>";
  }
  $select .= "</select><input type='button' onclick='this.parentNode.previousSibling.previousSibling.innerHTML=this.previousSibling.options[this.previousSibling.selectedIndex].text;this.parentNode.style.display=\"none\";' value='ok'>";

  return $select;
}

sub evalue_select {
  my ($self) = @_;

  my $eval = $self->application->cgi->param('evalue') || $self->data('default_eval');
  my $html = qq(1e-&nbsp;<input type='text' name='evalue' value='$eval' size='5' /><span>&nbsp;</span><input type='button' onclick='
var expNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(expNum) || (expNum < 0) || (expNum > 999)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer from 0 to 999";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = "1e-" + expNum;
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub identity_select {
  my ($self) = @_;

  my $ident = $self->application->cgi->param('identity') || $self->data('default_ident');
  my $html  = qq(<input type='text' name='identity' value='$ident' size='5' /><span>&nbsp;&#37;&nbsp;</span><input type='button' onclick='
var identNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(identNum) || (identNum < 0) || (identNum > 100)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer from 0 to 100";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = identNum + " %";
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub alength_select { 	 
  my ($self) = @_; 	 

  my $alen = $self->application->cgi->param('alength') || $self->data('default_alen');
  my $html = qq(<input type='text' name='alength' value='$alen' size='5' /><span>&nbsp;</span><input type='button' onclick='
var alenNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(alenNum) || (alenNum < 1)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer greater than 0";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = alenNum;
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub source_select {
  my ($self, $type, $presel, $single, $add_rna) = @_;

  my @prev_vals = $self->application->cgi->param('source') || ();
  my %prev_val_hash = map { $_ => 1 } @prev_vals;

  my @sources = ();
  if ($type eq 'phylogeny') {
    @sources = @{$self->{mgdb}->sources_for_type('protein')};
  }
  elsif ($type eq 'annotation') {
    @sources = grep {$_->[0] ne 'M5NR'} @{$self->{mgdb}->sources_for_type('protein')};
  }
  elsif ($type eq 'metabolism') {
    @sources = grep {$_->[0] !~ /^GO/} @{$self->{mgdb}->sources_for_type('ontology')};
  }

  my $size = scalar @sources;
  my @rnas = ();
  if ($add_rna) {
    @rnas = @{$self->{mgdb}->sources_for_type('rna')};
    $size += 2 + scalar(@rnas);
  }
  my $multiple = $single ? "" : " multiple='multiple'";
  my $select  .= "<select name='source'$multiple size='$size'>" . ($add_rna ? "<optgroup label='Protein'>" : "");

  foreach my $src (@sources) {
    my $sel = "";
    my ($name, $desc) = @$src;
    if ($prev_val_hash{$name} || (! scalar(keys(%prev_val_hash)) && (! $presel || $presel->{$name}))) {
      $sel = " selected=selected";
    }
    $select .= "<option style='cursor: help;' title='$desc' value='$name'$sel>$name</option>";
  }
  if ($add_rna) {
    $select .= "</optgroup><optgroup label='RNA'>";
    foreach my $src (@rnas) {
      $select .= qq(<option style='cursor: help;' title='$src->[1]' value='$src->[0]'>$src->[0]</option>);
    }
    $select .= "</optgroup>";
  }
  $select .= "</select><input type='button' value='ok' onclick='source_ok(this);' />";

  return $select;
}

sub ref_genome_select {
  my ($self, $mgid, $source) = @_;

  my $filter_select     = $self->application->component('fs1');
  my ($values, $labels) = $self->selectable_genomes($mgid, $source);
  
  $filter_select->values($values);
  $filter_select->labels($labels);
  $filter_select->name('ref_genome');
  $filter_select->width(600);

  my $fid    = "filter_select_" . $filter_select->id;
  my $select = $filter_select->output();

  $select .= qq(<input type='button' value='ok' onclick='this.parentNode.style.display="none";document.getElementById("rg_sel_td").innerHTML=document.getElementById("$fid").options[document.getElementById("$fid").selectedIndex].text;' />);

  my $first = $labels->[0];

  return ($select, $first);
}

sub selectable_genomes {
  my ($self, $mgid, $source) = @_;

  my $values = [];
  my $labels = [];
  
  if ($mgid) {
    $self->{mgdb}->set_jobs([$mgid]);
    my $available_orgs = $self->{mgdb}->get_organisms_with_contig_for_source($source, $self->data('max_ctg_num'), $self->data('min_ctg_len'));
    foreach my $org ( sort {$b->[2] <=> $a->[2]} @$available_orgs ) {
      push @$values, $org->[0];
      push @$labels, $org->[1] . " (" . $org->[2] . ")";
    }
  }

  return ($values, $labels);
}

sub metagenome_switch {
  my ($self, $mgid, $tool, $params) = @_;

  my $filter_select = $self->application->component('fs2');
  my $values = [];
  my $labels = [];

  my ($data, undef, undef) = $self->selectable_metagenomes(1);
  foreach my $mgs ( @$data ) {
    foreach my $mg ( @$mgs ) {
      push @$values, $mg->{value};
      push @$labels, $mg->{label};
    }
  }
  $filter_select->values($values);
  $filter_select->labels($labels);
  $filter_select->name('metagenome');
  $filter_select->width(600);
  $filter_select->default($mgid);

  my $fid    = "filter_select_" . $filter_select->id;
  my $select = $filter_select->output();
  $params = $params ? $params . "&" : "";

  $select .= qq(<input type='button' onclick='choose_tool("$tool","${params}metagenome="+document.getElementById("$fid").options[document.getElementById("$fid").selectedIndex].value);' value='ok'>);

  return $select;
}

sub metagenome_select {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $metagenome = $cgi->param('metagenome');
  my $list_select = $application->component('ls');
  my ($data, $groups, $types) = $self->selectable_metagenomes();
  my @preselected = ();
  if (defined($metagenome)) {
    push(@preselected, $metagenome);
  }
  if ($cgi->param('comparison_metagenomes')) {
    @preselected = $cgi->param('comparison_metagenomes');
  }

  $list_select->data($data);
  $list_select->preselection(\@preselected);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->group_names($groups);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('available metagenomes');
  $list_select->right_header('selected metagenomes');
  $list_select->name('comparison_metagenomes');
  $list_select->types($types);

  return $list_select;
}

sub group_select {
  my ($self) = @_;
  
  my $user = $self->application->session->user;
  my $memd = new Cache::Memcached {'servers' => $Conf::web_memcache, 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "analysis_groups_".($user ? $user->_id : "anonymous");
  my $cdata = $memd->get($cache_key);

  my $alldata = [];
  my $group_names = [];

  unless ($cdata) {
    my $rast = $self->application->data_handle('MGRAST');
    my $projects = $rast->Project->get_objects({ public => 1 });
    if ($self->application->session->user) {
      my $pp_ids = $self->application->session->user->has_right_to(undef, 'view', 'project');
      if (scalar(@$pp_ids)) {
	my $ps = [];
        foreach my $p (@{$rast->Project->get_objects_for_ids($pp_ids)}) {
                if($p->{name}) {
                        push(@$ps, $p);
                }
        }
        push(@$projects, @$ps);
      }
    }
    my $pdata = [];
    @$pdata = sort { lc($a->{label}) cmp lc($b->{label}) } map { { label => ($_->{name} || ''), value => 'project:'.($_->{id} || '') } } @$projects;

    $alldata = [$pdata];
    $group_names = ['projects'];
    
    if ($user) {
      my $data = [];
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $user,
									       name => 'mgrast_collection' } );
      my $collections = {};
      if (scalar(@$coll_prefs)) {
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  $collections->{$name} = 1;
	}
      }
      @$data = map { { label => $_, value => $_ } } sort(keys(%$collections));
      push(@$group_names, 'collections');
      push(@$alldata, $data);
    }
  }
  else {
    ($alldata, $group_names) = @$cdata;
  }

  $memd->set($cache_key, [$alldata, $group_names], 7200);
  $memd->disconnect_all;

  my $list_select = $self->application->component('ls2');
  $list_select->data($alldata);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('available groups');
  $list_select->right_header('selected groups');
  $list_select->name('comparison_collections');
  $list_select->group_names($group_names);

  return $list_select;
}

sub selectable_metagenomes {
  my ($self, $no_groups) = @_;

  my $user = $self->application->session->user;
  my $memd = new Cache::Memcached {'servers' => $Conf::web_memcache, 'debug' => 0, 'compress_threshold' => 10_000, };
  my $cache_key = "analysis_metagenomes_".($no_groups ? "nogroups" : "hasgroups")."_".($user ? $user->_id : "anonymous");
  my $cdata = $memd->get($cache_key);
  
  my $colls = [];
  my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
									     user => $user,
									     name => 'mgrast_collection' } );
  if (scalar(@$coll_prefs) && (! $no_groups)) {
    my $rast = $self->application->data_handle('MGRAST'); 
    my $collections = {};
    foreach my $collection_pref (@$coll_prefs) {
      my ($name, $val) = split(/\|/, $collection_pref->{value});
      if (! exists($collections->{$name})) {
	$collections->{$name} = [];
      }
      my $pj = $rast->Job->get_objects( { job_id => $val })->[0];
      push @{$collections->{$name}}, [ $pj->{metagenome_id}, $pj->{name} ];
    }
    foreach my $coll ( sort keys %$collections ) {
      if ( (! $coll) || (! $collections->{$coll}) || (@{$collections->{$coll}} == 0) ) { next; }
      push(@$colls, { label => $coll." [".scalar(@{$collections->{$coll}})."]", value => join('||', map { ($_->[0] || "")."##".($_->[1] || "") } @{$collections->{$coll}}) });
    }
  }    
  
  if ($cdata) {
    # there is cached data  
    $memd->disconnect_all;

    # if there are collections, update them in the cache data
    if ($user && scalar(@$colls)) {
      my $found_colls = 0;
      for (my $i=0; $i<scalar(@{$cdata->[1]}); $i++) {
	if ($cdata->[1]->[$i] eq 'collections') {
	  $cdata->[0]->[$i] = $colls;
	  $found_colls = 1;
	  last;
	}
      }
      unless ($found_colls) {
	push(@{$cdata->[1]}, "collections");
	push(@{$cdata->[0]}, $colls);
      }
    }

    return @$cdata;
  }

  my $metagenomes = [];  
  my $avail = $self->{mgdb}->get_all_job_ids();
  my $avail_hash = {};
  %$avail_hash = map { $_ => 1 } @$avail;
  my $seq_types = {};

  my $all_mgs = [];
  # check for available metagenomes
  my $rast = $self->application->data_handle('MGRAST'); 
  my $org_seen = {};
  my $metagenomespub = [];
  my $projs = [];
  my $mgs = [];
  if (ref($rast)) {
    my $projects = $rast->Project->get_objects({ public => 1 });

    if ($user) {
      my $pp_ids = $self->application->session->user->has_right_to(undef, 'view', 'project');
      if (scalar(@$pp_ids)) {
        my $ps = [];
        foreach my $p (@{$rast->Project->get_objects_for_ids($pp_ids)}) {
	  if($p->{name}) {
	    push(@$ps, $p);
	  }
        }
        push(@$projects, @$ps);
      }

      my @mga = $rast->Job->get_jobs_for_user_fast($user, 'view', 1);
      $mgs = \@mga;
    }

    my $p_hash = {};
    %$p_hash = map { $_->{_id} => $_ } @$projects;
    my $pjs = $rast->ProjectJob->get_objects();
    my $pj_hash = {};
    %$pj_hash = map { $_->{job} => $_; } @$pjs;
    my $public_metagenomes = $rast->Job->get_objects({public => 1, viewable => 1});
    foreach my $pmg (@$public_metagenomes) {
      next if ($org_seen->{$pmg->{metagenome_id}});
      $org_seen->{$pmg->{metagenome_id}} = 1;
      next unless ($avail_hash->{$pmg->{job_id}});
      $pj_hash->{$pmg->{_id}}->{mgid} = $pmg->{metagenome_id};
      $pj_hash->{$pmg->{_id}}->{mgname} = $pmg->{name};
      push(@$metagenomespub, { label => $pmg->{name}." (".$pmg->{metagenome_id}.")", value => $pmg->{metagenome_id}, type => $pmg->{sequence_type} ? $pmg->{sequence_type} : 'unknown' });
      if (defined($pmg->{sequence_type})) {
	$seq_types->{$pmg->{sequence_type}} = 1;
      }
    }
    my $plist = {};
    foreach my $pj (@$pjs) {
      unless (exists($plist->{$pj->{project}})) {
	$plist->{$pj->{project}} = [];
      }
      next unless ($pj->{mgid} && $pj->{mgname});
      push(@{$plist->{$pj->{project}}}, [ $pj->{mgid}, $pj->{mgname} ]);
    }
    foreach my $p ( keys %$plist ) {
      my $pname = $p_hash->{$p}->{name};
      next unless ($pname);
      next unless (scalar(@{$plist->{$p}}));
      push(@$projs, { label => $pname." [".scalar(@{$plist->{$p}})."]", value => join('||', map { $_->[0]."##".$_->[1] } @{$plist->{$p}}) });
    }
    @$projs = sort { lc($a->{label}) cmp lc($b->{label}) } @$projs;

    if ($user) {
      # build hash from all accessible metagenomes
      foreach my $mg_job (@$mgs) {
	next if ($org_seen->{$mg_job->{metagenome_id}});
	$org_seen->{$mg_job->{metagenome_id}} = 1;
	next unless ($avail_hash->{$mg_job->{job_id}});
	push(@$metagenomes, { label => ($mg_job->{name} || "")." (".$mg_job->{metagenome_id}.")", value => $mg_job->{metagenome_id}, type => ($mg_job->{sequence_type} || "unknown") });
	if (defined($mg_job->{sequence_type})) {
	  $seq_types->{$mg_job->{sequence_type}} = 1;
	}
      }
    }
  }

  my $groups = [];
  if (scalar(@$metagenomes)) {
    push(@$all_mgs, $metagenomes);
    push(@$groups, 'private');
  }
  unless ($no_groups) {
    if (scalar(@$colls)) {
      push(@$all_mgs, $colls);
      push(@$groups, 'collections');
    }
    if (scalar(@$projs)) {
      push(@$all_mgs, $projs);
      push(@$groups, 'projects');
    }
  }
  if (scalar(@$metagenomespub)) {
    push(@$all_mgs, $metagenomespub);
    push(@$groups, 'public');
  }
  
  my $seq_types_ary = [];
  @$seq_types_ary = sort keys(%$seq_types);

  $memd->set($cache_key, [$all_mgs, $groups, $seq_types_ary], 7200);
  $memd->disconnect_all;

  return ($all_mgs, $groups, $seq_types_ary);
}

sub clear_progress_image {
  return "<img src='./Html/clear.gif' onload='document.getElementById(\"progress_div\").innerHTML=\"\";'>";
}

sub download {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my $file = $Conf::temp."/download.".$cgi->param('file');
  my $fn = $cgi->param('filename') || $cgi->param('file');
  if (open(FH, $file)) {
    my $content = "";
    while (<FH>) {
      $content .= $_;
    }

    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=".$fn."\n\n";
    print $content;
    
    exit;
  } else {
    $self->application->add_message('warning', "Could not open download file");
  }

  return 1;
}

sub heatmap_scale {
  my ($self, $max) = @_;

  my $colors  = ["FF0000","F70700","EF0F00","E71700","DF1F00","D72700","CF2F00","C73700","BF3F00","B74700","AF4F00","A75700","9F5F00","976700","8F6F00","877700","7F7F00","778700","6F8F00","679700","5F9F00","57A700","4FAF00","47B700","3FBF00","37C700","2FCF00","27D700","1FDF00","17E700","0FEF00","07F700","00FF00"];

  unless ($max) { $max = 1; }
  my $nums  = scalar @$colors;
  my $range = $max / ($nums - 1);

  my $content = "<table><tr>";
  foreach my $c (@$colors) {
    $content .= "<td style='width: 50px; height: 20px; background-color: #".$c.";'></td>";
  }
  $content .= "</tr><tr>";
  $content .= "<td style='width: 50px; height: 20px;'>0.00</td>";

  foreach my $n (1..($nums-1)) {
    my $val = ($max > 99) ? int($n*$range) : ($max > 9) ? sprintf("%.1f", $n*$range) : sprintf("%.2f", $n*$range);
    $content .= "<td style='width: 50px; height: 20px;'>$val</td>";
  }
  $content .= "</tr></table>";

  return $content;
}

sub add_collection {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $dbmaster = $application->dbmaster;
  my $mgrast = $application->data_handle('MGRAST');
  my $user = $application->session->user;
  
  # check for mass addition to a set
  if ($cgi->param('newcollection')) {
    my $set = $cgi->param('newcollection');
    my @vals = split /\|/, $cgi->param('ids');
    foreach my $val (@vals) {
      my $mg = $mgrast->Job->init({ metagenome_id => $val });
      my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							    user => $user,
							    name => 'mgrast_collection',
							    value => $set."|".$mg->{job_id} } );
      unless (scalar(@$existing)) {
	$dbmaster->Preferences->create( { application => $application->backend,
					  user => $user,
					  name => 'mgrast_collection',
					  value => $set."|".$mg->{job_id} } );
      }
    }
    return "<img src='./Html/clear.gif' onload='alert(\"The selected metagenomes have been added to collection $set\");'>";
  }
  
  return "";
}

sub google_colors {
  return ["#3366cc","#dc3912","#ff9900","#109618","#990099","#0099c6","#dd4477","#66aa00","#b82e2e","#316395","#994499",
	  "#22aa99","#aaaa11","#6633cc","#e67300","#8b0707","#651067","#329262","#5574a6","#3b3eac","#b77322","#16d620",
	  "#b91383","#f4359e","#9c5935","#a9c413","#2a778d","#668d1c","#bea413","#0c5922","#743411"];
}

##################
# css / js
##################
sub require_css {
  return [ "$Conf::cgi_url/Html/Analysis.css" ];
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/Analysis.js", "$Conf::cgi_url/Html/heatmap.js", "$Conf::cgi_url/Html/pca.js", "$Conf::cgi_url/Html/canvg.js", "$Conf::cgi_url/Html/rgbcolor.js", "$Conf::cgi_url/Html/rarefaction.js", "$Conf::cgi_url/Html/zoom.js", "$Conf::cgi_url/Html/krona.js" ];
}

sub TO_JSON { return { %{ shift() } }; }

sub inlineImage {
  my ($path, $params) = @_;
  
  if (open(IMAGE, $path)) {
    my $image = do{ local $/ = undef; <IMAGE>; };
    my $encoded = encode_base64($image);
    close IMAGE;
    unlink $path;
    return '<img src="data:image/png;base64,'.$encoded.'" '.$params.'>';
  } else {
    return "<p>Error generating image</p>";
  }
}
