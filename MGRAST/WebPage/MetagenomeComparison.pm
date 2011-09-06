package MGRAST::WebPage::MetagenomeComparison;

use base qw( WebPage );

1;

use strict;
use warnings;

use WebConfig;
use WebColors;
use GD;
use WebComponent::WebGD;
use URI::Escape;
use AnnotationClearingHouse::ACH;
use Data::Dumper;

use POSIX qw(ceil);

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset dataset_is_phylo dataset_is_metabolic get_public_metagenomes );

=pod

=head1 NAME

MetagenomeComparison - an instance of WebPage to compare multiple metagenome to 
each other

=head1 DESCRIPTION

Comparison of multiple metagenome profiles

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Compare Metagenomes');
  $self->application->register_component('Table', 'MGTable');
  $self->application->register_component('TabView', 'HistogramTabs');
  $self->application->register_component('HelpLink', 'PhyloHelp');
  $self->application->register_component('HelpLink', 'MetaHelp');
  $self->application->register_component('Ajax', 'MGAjax');
  $self->application->register_component('HelpLink', 'DataHelp');
  $self->application->register_component('ListSelect', 'MGSelect');
  $self->application->register_component('Ajax', 'SelectLevelAjax');
  $self->application->register_component('RollerBlind', 'settings_blind');

  # get metagenome id(s)
  my $id = $self->application->cgi->param('metagenome') || '';
  my @metagenome_selected = $self->application->cgi->param('comparison_metagenomes');
  unshift @metagenome_selected, $id;

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  # load the settings for this type
  &get_settings_for_dataset($self);
  
  # init the metagenome database
  foreach my $id (@metagenome_selected) {
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless($job) {
      #
      # See if this job is a mgrast1 job
      #
      if (-f $job->directory() . "/proc/taxa.gg.allhits")
      {
	  my $g = $job->genome_id();
	  my $jid = $job->id();
	  my $url = "http://metagenomics.nmpdr.org/v1/index.cgi?action=ShowOrganism&initial=1&genome=$g&job=$jid";
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'. <p>" .
			    "This job appears to have been processed in the MG-RAST Version 1 server. You may " .
			    "browse the job <a href='$url'>using that system</a>.");
      }
      else
      {
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      }
      return 1;
    }
    $self->data("job_$id", $job);

    my $mgdb = MGRAST::MetagenomeAnalysis->new($job);
    unless($mgdb) {
      $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      return 1;
    }

    $mgdb->query_load_from_cgi($self->app->cgi, $self->data('dataset'));
    $self->data("mgdb_$id", $mgdb);

  }
  # sanity check on job
  if ($id) { 
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless ($job) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);

    # init the metagenome database
    my $mgdb = MGRAST::MetagenomeAnalysis->new($job);
    unless ($mgdb) {
      #
      # See if this job is a mgrast1 job
      #
      if (-f $job->directory() . "/proc/taxa.gg.allhits")
      {
	  my $g = $job->genome_id();
	  my $jid = $job->id();
	  my $url = "http://metagenomics.nmpdr.org/v1/index.cgi?action=ShowOrganism&initial=1&genome=$g&job=$jid";
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'. <p>" .
			    "This job appears to have been processed in the MG-RAST Version 1 server. You may " .
			    "browse the job <a href='$url'>using that system</a>.");
      }
      else
      {
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      }
      return 1;
    }
    $mgdb->query_load_from_cgi($self->app->cgi, $self->data('dataset'));
    $self->data('mgdb', $mgdb);
  }

  return 1;
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $error = '';

  # get metagenome id(s)
  my $metagenome = $self->application->cgi->param('metagenome') || '';

  # write title and intro
  my $job = $self->data('job');
  my $html = "<span style='font-size: 1.6em'><b>Metagenome Heat Map for ".$job->genome_name." (".$job->genome_id.")</b></span>";
  $html .= "<div class='clear' style='height:15px;'></div>";

  # abort if error
  if ($error) {
    $html .= $error;
    return $html;
  }

  my $datahelp = $self->application->component('DataHelp');
  $datahelp->title($self->data('dataset'));
  $datahelp->disable_wiki_link(1);
  $datahelp->hover_width(300);
  $datahelp->text($self->data('dataset_intro'));

  # init arrays for form 
  my @evalue = ( '0.01', '1e-05', '1e-10', '1e-20', '1e-30', '1e-40', '1e-50', '1e-60' );

  my @pvalue;
  for( my $i = 200; $i >= 20; $i-=10 ){
    push @pvalue, $i;
  }

  my @identity;
  for (my $i=100; $i>=40; $i-- ){
    push @identity, $i;
  }

  my @alen;
  for( my $i = 10; $i <= 200; $i+=10 ){
    push @alen, $i;
  }

  my $labels = $self->data('dataset_labels');
  $html .= $self->js();

  foreach(@{$self->data('dataset_select_metabolic')}){
    $html .= $labels->{$_} . '", "';
  }
  $html .= qq~"];
   var options_phylo = ["~.join('", "', @{$self->data('dataset_select_phylogenetic')}).qq~"];
   var labels_phylo = ["~;
  foreach(@{$self->data('dataset_select_phylogenetic')}){
    $html .= $labels->{$_} . '", "';
  }
  $html .= qq~"]; 
   var options_used = [];
   var labels_used = [];

   if(radio_meta.checked){
      options_used = options_meta;
      labels_used = labels_meta;
   } else {
      options_used = options_phylo;
      labels_used = labels_phylo;
   }

   select.options.length = 0;
   for(i=0; i<options_used.length; i++){
       select.options[i] = new Option(labels_used[i], options_used[i]);
   } 
} </script>~;

  my $meta_text .= "<div style='padding:0 5px 5px 5px;'><img src=\"$Global_Config::cgi_url/Html/metabolic.jpg\" style='width: 100; heigth: 100; float: left; padding: 5px 10px 10px 0;'><h3 style='text-align: left;'>Metabolic Comparison with Subsystem</h3>";
  $meta_text .=  "<p>MG-RAST computes metabolic profiles based on Subsystems from the sequences from your metagenome sample. You can modify the parameters of the calculated Metabolic Profile including e-value, percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sequence characteristics of your sample. We recommend a minimal alignment length of 50bp be used with all RNA databases.</p></div>";

  my $phylo_text .= "<div style='padding:0 5px 5px 5px;'><img src=\"$Global_Config::cgi_url/Html/phylogenetic.gif\" style='width: 100; heigth: 100;float: left; padding: 5px 10px 10px 0;'><h3 style='text-align: left;'>Phylogenetic Comparison based on RDP</h3>";
  $phylo_text .= "<p>MG-RAST computes phylogenetic profiles based on various RNA databases (RDP, GREENGENES, Silva, and European Ribosomal) the SEED database. RDP is used as a default database to show the taxonomic distributions. You can modify the parameters of the calculated Metabolic Profile including e-value, percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sample and sequence characteristics of your metagenome.  The SEED database provides an alternative way to identify taxonomies in the sample. Protein encoding genes are BLASTed against the SEED database and the taxonomy of the best hit is used to compile taxonomies of the sample.</p></div>";

  my $help_met = $self->application->component('MetaHelp');
  $help_met->hover_width(400);
  $help_met->disable_wiki_link(1);
  $help_met->text($meta_text.$phylo_text);
  my $help_phyl = $self->application->component('PhyloHelp');
  $help_phyl->hover_width(400);
  $help_phyl->disable_wiki_link(1);
  $help_phyl->text($phylo_text);

  # start form
  my $cgi = $self->application->cgi;
  my $dataset = $self->data('dataset');

  my $comparison_type = ($cgi->popup_menu( -id => 'metabolic_type', -name => 'type', -style => 'margin-right: 5px', -onchange => 'change_dataset_select()', -default => $cgi->param('type') || '', -values => [ 'Metabolic', 'Phylogenetic' ])).($cgi->popup_menu( -id => 'dataset_select', -name => 'dataset', -default => $dataset, -values => $self->data('dataset_select'), ($labels ? (-labels => $labels) : ())));

 $html .= qq~<script>
  function change_dataset_select () {
   var dataset_select = document.getElementById("dataset_select");
   var profile_select = document.getElementById("metabolic_type");
   var options_meta = ["~.join('", "', @{$self->data('dataset_select_metabolic')}).qq~"];
   var labels_meta = ["~;
  foreach(@{$self->data('dataset_select_metabolic')}){
    $html .= $labels->{$_} . '", "';
  }
  $html .= qq~"];
   var options_phylo = ["~.join('", "', @{$self->data('dataset_select_phylogenetic')}).qq~"];
   var labels_phylo = ["~;
  foreach(@{$self->data('dataset_select_phylogenetic')}){
    $html .= $labels->{$_} . '", "';
  }

  $html .= qq~"]; 
   var options_used = [];
   var labels_used = [];

   if(profile_select.value == "Metabolic"){
      options_used = options_meta;
      labels_used = labels_meta;
   } else {
      options_used = options_phylo;
      labels_used = labels_phylo;
   }

   dataset_select.options.length = 0;
   for(i=0; i<options_used.length; i++){
       dataset_select.options[i] = new Option(labels_used[i], options_used[i]);
   } 
} </script>~;

  my $data_set .= $cgi->popup_menu(-id => 'dataset_select', -name => 'dataset', -default => $self->data('dataset'),
				   -values => $self->data('dataset_select'),
				   ($labels ? (-labels => $labels) : ()));
  my $filter = "<table width=100%><tr><td>Maximum e-value</td>";
  $filter .= "<td align=right>".$cgi->popup_menu( -name => 'evalue', -default => $cgi->param('evalue') || '', -values => \@evalue )."</td></tr>";
  $filter .= "<tr><td>Minimum percent identity</td>";
  $filter .= "<td align=right>".$cgi->popup_menu( -name => 'identity', -default => $cgi->param('identity') || '', -values => [ '', @identity ])."</td></tr>";
  $filter .= "<tr><td>Minimum alignment length</td>";
  $filter .= "<td align=right>".$cgi->popup_menu( -name => 'align_len', -default => $cgi->param('align_len') || '', -values => [ '', @alen ])."</td></tr></table>";

  # load select mg component
  my $list_select = $self->application->component('MGSelect');
  my $data = $self->selectable_metagenomes();
  my @preselected = $cgi->param('comparison_metagenomes');
  unshift(@preselected, $metagenome);
  $list_select->data($data);
  $list_select->preselection(\@preselected);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->max_selections(5);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('available columns');
  $list_select->right_header('selected columns');
  $list_select->name('comparison_metagenomes');

  my $metagenome_select = $list_select->output();

  my $additional = "<table width=100%><tr><td>apply 'heat map' style coloring</td>";
  my $coloring = 1;
  if (defined($cgi->param('colouring'))) {
    $coloring = $cgi->param('colouring');
  }
  $additional .=  "<td align=right>".$cgi->checkbox( -name => 'colouring', -checked => $coloring, -value => 1, -label => '')."</td></tr>";
  $additional .= "<tr><td>number of groups used in coloring</td>";
  $additional .= "<td align=right>".$cgi->popup_menu( -name => 'groups', -default => $cgi->param('groups') || 10, -values => [ '4', '5', '6', '7', '8', '9', '10' ])."</td></tr>";
  $additional .= "<tr><td>maximum relative score as upper limit for coloring</td>";
  $additional .= "<td align=right>".$cgi->popup_menu( -name => 'effective_max', -default => $cgi->param('effective_max') || '0.3', -values => [ '0.01', '0.1', '0.2', '0.3', '0.4', '0.5' ])."</td></tr></table>";

  my $button = "<input type='button' value='Re-compute results' style='height:35px;width:150px;font-size:10pt;' onclick='list_select_select_all(\"" . $list_select->id . "\");document.forms.mg_heatmap.submit();'>";#$self->button('Re-compute results', style => 'height:35px;width:150px;font-size:10pt;');

  my $blind = $self->application->component('settings_blind');
  $blind->width(320);
  $blind->add_blind( { title => 'select comparison type'.$help_met->output(), content => $comparison_type, active => 1 } );
  $blind->add_blind( { title => 'set filters', content => $filter } );
  $blind->add_blind( { title => 'additional options', content => $additional } );

  $html .= $self->start_form('mg_heatmap', {metagenome=>$metagenome});
  $html .= "<table><tr><td style='margin-right: 20px;'><h3>Choose options</h3>".$blind->output()."</td><td><h3>Select metagenomes</h3><div style='width: 575px; margin-bottom: 10px;'>".$metagenome_select."</div></td></tr></table>";
  $html .= $button;
  $html .= $self->end_form();

  # add ajax output
  $html .= $self->application->component('MGAjax')->output;

  $self->application->register_component('HelpLink', 'VennHelp');
  my $VennHelp = $self->application->component('VennHelp');
  $VennHelp->hover_width(400);
  $VennHelp->disable_wiki_link(1);
  $VennHelp->text("<div style='padding:0 5px 5px 5px;'><h3>Distribution & Venn Diagram</h3><p>The table and Venn diagram below shows the classification distribution of the metagenomes. You can select to which hierarchical level you wish to see the classification distribution. The Venn diagram is used as a visual aid in comparing multiple metagenomes. The diagram is currently enabled when comparing two or three metagenomes. The points in each of the sections of the diagram represent classified metagenomic sequences against phylogeny or metabolic data (depending on the dataset selected). You can select which section of the Venn diagram to view on the table below by selecting the appropiate section in this dropdown menu.</p></div>");
  $html .= "<h3>Classification distribution diagram and table " . $VennHelp->output() . "</h3>";

  $html .= "<div id='table'>";
  #$html .= "<img src='".IMAGES."clear.gif' onLoad='execute_ajax(\"load_table\",\"table\",\"mg_heatmap\",\"Loading table...\");' />";
  $html .= $self->load_table();
  $html .= "</div>";

  return $html;

}


=pod 

=item * B<load_table> ()

Returns the table. This method is invoked by an AJAX call.

=cut

sub load_table {
  my $self = shift;

  my $time = time;

  # get metagenome id(s)
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  my @metagenome_selected = $self->application->cgi->param('comparison_metagenomes');
  unshift(@metagenome_selected, $metagenome);

  unless (scalar(@metagenome_selected)) {
    return "<p><em>No metagenomes selected.</em></p>";
  }

  # collect the data for each metagenome 
  my $dataset = $self->data('dataset');
  my $desc = $self->data('dataset_desc');
  my $data = {};
  my $url_params = {};
  my $labels = $self->data('dataset_labels');
  my $job_description = {};

  my $seen = {};
  foreach my $id (@metagenome_selected ) {
    next if ($seen->{$id});
    $seen->{$id} = 1;
    my $job = $self->data("job_$id");
    $job_description->{$id} = $job->genome_name;
    $data->{$id} = {} unless (exists $data->{$id});
    $data->{$id}->{sequence_count} = $job->metaxml->get_metadata('preprocess.count_proc.total');
    $data->{$id}->{fullname} = $job->genome_name." (".$job->genome_id.")";

    # set url string for params
    $url_params->{$id} = join('&', map { $_.'='.uri_escape($self->app->cgi->param($_)) }
			      qw( dataset evalue bitscore align_len identity )
			     );
    $url_params->{$id} .= '&metagenome=' . $id;

    # fetch best hits by dataset
    if (dataset_is_phylo($desc)) {
      
      $data->{$id}->{data} = $self->data("mgdb_$id")->get_taxa_counts($dataset);
  
    }
    elsif (dataset_is_metabolic($desc)) {

      $data->{$id}->{data} = $self->data("mgdb_$id")->get_subsystem_counts($dataset);

    }
    else {
      die "Unknown dataset in ".__PACKAGE__.": $dataset $desc";
    }
    
  }

  # define the columns for the table
  my $columns = [];
  my $class_cols = 0;
  my $linked_columns = {};

  if (dataset_is_phylo($desc)) {
    $columns = [ { name => 'Domain', filter => 1, operator => 'combobox', visible => 1 },
		 { name => '', filter => 1, operator => 'combobox', sortable => 1, width => 150, visible => 1 },
		 { name => '', filter => 1, operator => 'combobox', width => 150, visible => 0 },
		 { name => '', filter => 1, operator => 'combobox', width => 150, visible => 0 },
		 { name => 'Organism Name', filter => 1, visible => 0 },
	       ];
    $class_cols = 5;
    $linked_columns->{0} = {'max_level'=>1, 'add_block' =>10, 'start_col' => 6, 'first_stat' => 6};
    $linked_columns->{1} = {'level_1' => 1, 'max_level'=>2, 'add_block' =>10, 'start_col' => 6, 'first_stat' => 8};
    $linked_columns->{2} = {'level_1' => 1, 'level_2' => 2, 'max_level'=>3, 'add_block' =>10, 'start_col' => 6, 'first_stat' => 10};
    $linked_columns->{3} = {'level_1' => 1, 'level_2' => 2, 'level_3'=>3, 'max_level'=>4, 'add_block' =>10, 'start_col' => 6, 'first_stat' => 12};
    $linked_columns->{4} = {'level_1' => 1, 'level_2' => 2, 'level_3'=>3, 'level_4'=>4, 'max_level'=>5, 'add_block' =>10, 'start_col' => 6, 'first_stat' => 14};
  }
  elsif (dataset_is_metabolic($desc)) {
    $columns = [ { name => 'Subsystem Hierarchy 1', filter => 1, operator => 'combobox', width => 150, sortable => 1, visible=> 1 },
		 { name => 'Subsystem Hierarchy 2', filter => 1, width => 150, visible => 1  },
		 { name => 'Subsystem Name', filter => 1, sortable => 1,  width => 150, visible => 0  },
	       ];
    $class_cols = 3;
    $linked_columns->{0} = {'max_level'=>1, 'add_block' => 6, 'start_col' => 4, 'first_stat' => 4};
    $linked_columns->{1} = {'level_1' => 1, 'max_level'=>2, 'add_block' => 6, 'start_col' => 4, 'first_stat' => 6};
    $linked_columns->{2} = {'level_1' => 1, 'level_2' => 2, 'max_level'=>3, 'add_block' => 6, 'start_col' => 4, 'first_stat' => 8};
  }
  else {
    die "Unknown dataset in ".__PACKAGE__.": $dataset";
  }

  my $add_cols = 1;
  # add column for each metagenome in comparison
  foreach my $id (keys(%$data)) {
    for (my $i=1;$i<=$class_cols;$i++){
      my $visible;
      if ($i == 2){ $visible = 1} else {$visible=0}
      push @$columns, { name => "ID ".$id,
			filter => 1,
			sortable => 1,
			width => 150,
			visible => $visible,
			hide_filter => 1,
			tooltip => $data->{$id}->{fullname}
		      };

      my $hash = { name => "ID ".$id,
			filter => 1,
			sortable => 1,
			hide_filter => 1,
			width => 150,
			visible => 0,
			tooltip => $data->{$id}->{fullname}
		      };
      if ($i == 2) {
	$hash->{operand} = -1;
	$hash->{operator} = 'unequal';
      }
      push @$columns, $hash;
    }
  
    $add_cols++;
  }

  # get the counts for the different levels of taxonomy
  my $level_counts={};
  my $all_data;
  my $histogram_counts={};

  # get all the taxonomy data available
  my $lineage_list = $self->get_lineages;
  my $ach = $self->connect_to_ach;

  my ($id_colors, $mini_graphs, my $org_taxonomies);

  # I will temporaryly disable the md5 check ... in order to enable, just unconmment the next if statement, and comment the other if statement
#  if (dataset_is_phylo($desc) && $dataset =~ /SEED/) {
  if (dataset_is_phylo($desc) && $dataset =~ /SEEDY/) {
      foreach my $id (keys(%$data)) {
	  my $db = $self->data("mgdb_$id");
	  push @$all_data, @{$data->{$id}->{data}};
	  
	  # get the additional MD5 sequences from metagenome subset methods
	  my ($md5_counts, $org_list) = $self->get_md5_counts($dataset, $id, $lineage_list, $ach);
	  foreach my $level (keys %$md5_counts)
	  {
	      foreach my $taxa (keys %{$md5_counts->{$level}})
	      {
		  # get the count
		  $level_counts->{$id}->{$taxa} += $md5_counts->{$level}->{$taxa};
		  $histogram_counts->{$level}->{$taxa}->{$id} += $md5_counts->{$level}->{$taxa} if ($level ne "organism_level");
		  $org_taxonomies->{$id}->{$taxa} = $org_list->{$taxa} if ($level eq "organism_level");
	      }
	  }
      }
      # create the histogram
      ($id_colors, $mini_graphs) = $self->create_graph_comparison($histogram_counts, $metagenome);
  }
# I will temporaryly disable the md5 check ... in order to enable, just unconmment the next if statement, and comment the other if statement
#  elsif (dataset_is_phylo($desc) && $dataset !~ /SEED/) {
  elsif (dataset_is_phylo($desc)) {
      foreach my $id (keys(%$data)) {
	  my $db = $self->data("mgdb_$id");
	  push @$all_data, @{$data->{$id}->{data}};
	  foreach my $d (@{$data->{$id}->{data}}) {
	      my $taxonomy = $d->[0];
	      my $taxa = $db->split_taxstr($taxonomy);

	      for (my $level=0;$level<=3;$level++)
	      {
	          # get the count
		unless (scalar(@$taxa) >= $level+1) {
		  $taxa->[$level] = $taxa->[scalar(@$taxa) - 1];
		}
		  $level_counts->{$id}->{$level}->{$db->key2taxa($taxa->[$level])} += $d->[scalar(@$d)-1];
		  $histogram_counts->{$level}->{$db->key2taxa($taxa->[$level])}->{$id} += $d->[scalar(@$d)-1];
	      }
	      $level_counts->{$id}->{4}->{$db->key2taxa($taxa->[scalar(@$taxa)-1])} = $d->[scalar(@$d)-1];
	  }
      }
      # create the histogram
      ($id_colors, $mini_graphs) = $self->create_graph_comparison($histogram_counts, $metagenome);
  }
  elsif (dataset_is_metabolic($desc)){
    foreach my $id (keys(%$data)) {
      my $db = $self->data("mgdb_$id");
      push @$all_data, @{$data->{$id}->{data}};
      foreach my $d (@{$data->{$id}->{data}}) {
	my $taxonomy = $d->[3];
	my $top_level = ($db->key2taxa($d->[0]) || 'Unclassified');
	my $second_level = ($db->key2taxa($d->[1]) || 'Unclassified');
	my $third_level = $db->key2taxa($d->[2]);
	$level_counts->{$id}->{$top_level} += $d->[scalar(@$d)-1];
	$level_counts->{$id}->{$top_level . '~' . $second_level} += $d->[scalar(@$d)-1];
	$level_counts->{$id}->{$top_level . '~' . $second_level . '~' . $third_level} += $d->[scalar(@$d)-1];
      }
    }
  }
  else {
    die "Unknown dataset in ".__PACKAGE__.": $dataset";
  }
  
  # build hash over all data samples
  my $join = {};
  my $i = $class_cols; 
  my $vennData = {};
  my $seen_taxa={};

  foreach my $id (keys(%$data)) {
      # total count of matches
      my $total = 0;
      map { $total += $_->[ scalar(@$_)-1 ] } @{$data->{$id}->{data}};
      $data->{$id}->{total} = $total;
      
      # start the group data for the venn Diagram
      my $groupData = {};
      for (my $group=0;$group< $class_cols;$group++){
	  push @{$groupData->{$group}}, $id;
      }
      
      my (@send_array, $seen_row);
      
      # read all data from each sample
      my $array = [];
      push @$array, @$all_data;
      
      # I will temporaryly disable the md5 check ... in order to enable, just unconmment the next if statement, and comment the other if statement
#      if (dataset_is_phylo($desc) && $dataset =~ /SEED/) {
      if (dataset_is_phylo($desc) && $dataset =~ /SEEDY/) {
	  foreach my $hit (keys %{$org_taxonomies->{$id}}) {

	      # get the classification
	      my @c; my $key; my $taxonomy; my $rank;

	      $taxonomy = $org_taxonomies->{$id}->{$hit};
	      my @taxa = split(/\; /, $taxonomy);
	      
	      next if ($seen_row->{$hit});
	      $seen_row->{$hit}++;

	      $rank = scalar(@taxa) - 2;
	      push @c, $taxa[0],
	      $taxa[1],
	      $taxa[2],
	      $taxa[3],
	      $hit;
	      
	      $key = join(',', @c);
	      @send_array = @c;

	      # init join hash for that key
	      # get the count
	      unless (exists($join->{$key})) {
		  $join->{$key} = [];
		  push @{$join->{$key}}, @c;
	      }
	      
	      
	      push @{$join->{$key}}, &load_count_cells(\@send_array, $level_counts, $id,$total,$seen_taxa);
	  
	      # write in the stats for the initial taxonomy levels (domain, phyla, etc)
	      for (my $l=0;$l<$class_cols;$l++){
		  # get the count
		  my $col_num = scalar (@{$join->{$key}}) - (($class_cols*2)-($l*2)) +1;
		  my  $absolute_score = $join->{$key}->[$col_num];
		  next if ($absolute_score <= 0);
		  my $score = sprintf("%.4f",$absolute_score/$total);
		  my $base_link = "?page=MetagenomeSubset&".$url_params->{$id}."&get=".uri_escape( $taxonomy );
		  
		  my $mult = $l*2;
		  $join->{$key}->[$col_num-1] = { 'data' => '<a href="' . $base_link . '&rank=' . $l . '">' . $score . '</a>'};
		  $join->{$key}->[$col_num] = { 'data' => '<a href="' . $base_link . '&rank=' . $l . '">' . $absolute_score . '</a>'};
		  
		  # gather the data for the venn diagram
		  #push (@$groupData,  $c[scalar(@c) - 1]);
		  $linked_columns->{$l}->{$id} = $col_num;
		  push @{$groupData->{$l}}, $c[$l] ;
		  
		  # apply colouring
		  if ($self->app->cgi->param('colouring') and $absolute_score) {
		      my $c = ceil( ($absolute_score*$self->app->cgi->param('groups'))/($total*$self->app->cgi->param('effective_max')) );
		      $c = $self->app->cgi->param('groups') if ($c > $self->app->cgi->param('groups'));
		      $join->{$key}->[$col_num-1]->{highlight} = 'rgb('.join(',',@{WebColors::get_palette('vitamins')->[$c-1]}).')';
		      $join->{$key}->[$col_num]->{highlight} = 'rgb('.join(',',@{WebColors::get_palette('vitamins')->[$c-1]}).')';
		  }
	      }
	  }
	  for (my $group=0;$group<$class_cols;$group++){
	      push @{$vennData->{$group}}, $groupData->{$group};
	  }
      }
      # I will temporaryly disable the md5 check ... in order to enable, just unconmment the next if statement, and comment the other if statement
      elsif ((dataset_is_metabolic($desc)) || (dataset_is_phylo($desc))) {
#      elsif ((dataset_is_metabolic($desc)) || (dataset_is_phylo($desc) && $dataset !~ /SEED/ )) {
	  my $db = $self->data("mgdb_$id");
	  foreach my $d (@$array){
	  
	      # get the classification
	      my @c; my $key; my $taxonomy; my $rank;

	      if (dataset_is_phylo($desc)) {
		  $taxonomy = $d->[0];
		  my $taxa = $db->split_taxstr($taxonomy);
		  next if ($seen_row->{$db->key2taxa($taxa->[scalar(@$taxa)-1])});
		  $seen_row->{$db->key2taxa($taxa->[scalar(@$taxa)-1])}++;
		  
		  $rank = scalar(@$taxa) - 2;
		  push @c, $db->key2taxa($taxa->[0]),
		  $db->key2taxa($taxa->[1]),
		  $db->key2taxa($taxa->[2]),
		  $db->key2taxa($taxa->[3]),
		  $db->key2taxa($taxa->[scalar(@$taxa)-1]);
		  
		  $key = join(',', @c);
		  @send_array = @c;
	      }
	      elsif (dataset_is_metabolic($desc)) {

		  $taxonomy = $d->[3];
	      
		  next if ($seen_row->{$db->key2taxa($d->[2])});
		  $seen_row->{$db->key2taxa($d->[2])}++;
		  
		  $rank = 2;
		  push @c, ($db->key2taxa($d->[0]) || 'Unclassified'), 
		  ($db->key2taxa($d->[1]) || 'Unclassified'), 
		  $db->key2taxa($d->[2]);
		  
		  @send_array = ($c[0], $c[0].'~'.$c[1], join('~', @c));
		  
		  $key = join(',', @c);
	      }
	      # init join hash for that key
	      # get the count
	      unless (exists($join->{$key})) {
		  $join->{$key} = [];
		  push @{$join->{$key}}, @c;
	      }
	  
	      push @{$join->{$key}}, &load_count_cells(\@send_array, $level_counts, $id,$total,$seen_taxa);
	  
	      # write in the stats for the initial taxonomy levels (domain, phyla, etc)
	      for (my $l=0;$l<$class_cols;$l++){
		  # get the count
		  my $col_num = scalar (@{$join->{$key}}) - (($class_cols*2)-($l*2)) +1;
		  my  $absolute_score = $join->{$key}->[$col_num];
		  next if ($absolute_score <= 0);
		  my $score = sprintf("%.4f",$absolute_score/$total);
		  my $base_link = "?page=MetagenomeSubset&".$url_params->{$id}."&get=".uri_escape( $taxonomy );
		  
		  my $mult = $l*2;
		  $join->{$key}->[$col_num-1] = { 'data' => '<a href="' . $base_link . '&rank=' . $l . '">' . $score . '</a>'};
		  $join->{$key}->[$col_num] = { 'data' => '<a href="' . $base_link . '&rank=' . $l . '">' . $absolute_score . '</a>'};
		  
		  # gather the data for the venn diagram
		  #push (@$groupData,  $c[scalar(@c) - 1]);
		  $linked_columns->{$l}->{$id} = $col_num;
		  push @{$groupData->{$l}}, $c[$l] ;
		  
		  # apply colouring
		  if ($self->app->cgi->param('colouring') and $absolute_score) {
		      my $c = ceil( ($absolute_score*$self->app->cgi->param('groups'))/($total*$self->app->cgi->param('effective_max')) );
		      $c = $self->app->cgi->param('groups') if ($c > $self->app->cgi->param('groups'));
		      $join->{$key}->[$col_num-1]->{highlight} = 'rgb('.join(',',@{WebColors::get_palette('vitamins')->[$c-1]}).')';
		      $join->{$key}->[$col_num]->{highlight} = 'rgb('.join(',',@{WebColors::get_palette('vitamins')->[$c-1]}).')';
		  }
	      }
	  }
	  for (my $group=0;$group<$class_cols;$group++){
	      push @{$vennData->{$group}}, $groupData->{$group};
	  }
      }
      else {
	  die "Unknown dataset in ".__PACKAGE__.": $dataset";
      }
  }
 
  # transform to array of array expected by table component
  my $table_data = [];
  foreach my $key (sort(keys(%$join))) {
      push @$table_data, $join->{$key};
  }
  
  # create table
  my $table = $self->application->component('MGTable');
  $table->show_export_button({strip_html => 1, hide_invisible_columns => 1});
  if (scalar(@$table_data) > 50) {
      $table->show_top_browse(1);
      $table->show_bottom_browse(1);
      $table->items_per_page(50);
      $table->show_select_items_per_page(1);
  }
  $table->columns($columns);
  $table->data($table_data);
  
  my $html;
  
  # create the Venn Diagram figure for each stat level
  my $vennDiagrams = {};
  for (my $group=0;$group<$class_cols;$group++){
      $self->application->register_component('VennDiagram', 'metagenome' . $group);
      my $vennD = $self->application->component('metagenome' . $group);
      $vennD->width(400);
      $vennD->height(400);
      $vennD->linked_component($table);
      $vennD->linked_columns($linked_columns->{$group});
      $vennD->data($vennData->{$group});
      my $visible = "";
      if ($group+1 == 2){
	  $visible .= "style='visibility:visible;display:block'";
      }
      else{
	  $visible .= "style='visibility:hidden;display:none;'";      
      }
      $html .= qq~<div name='venn_~ . ($group+1) . qq~' id='venn_~ . ($group+1) . qq~' $visible>~;
      $html .= $vennD->output() if (defined $vennD->output);
      $html .= qq~</div>~;
  }
  my $cgi = $self->application->cgi;
  
  $html .= "<div id='select_box'><table>";
  my $bg_colors = {'1'=>[230, 230, 250], '2'=>[255, 228, 225], '3'=>[240, 230, 140]};
  my $colorcount = 1;
  foreach my $id (keys(%$data)) {
      if (defined $bg_colors->{$colorcount}){
	  $html .= "<tr><th style='background-color:rgb(" . join(",", @{$bg_colors->{$colorcount}}) . ")'>" . $job_description->{$id} . " ($id)</th><td><em>Found ".$data->{$id}->{total}." matches in ".
	      scalar(@{$data->{$id}->{data}})." " . $labels->{$dataset} . " classifications.</td></tr>";
      }
      else{
	  $html .= "<tr><th>" . $job_description->{$id} . " ($id)</th><td><em>Found ".$data->{$id}->{total}." matches in ".
	      scalar(@{$data->{$id}->{data}})." " . $labels->{$dataset} . " classifications.</td></tr>";
      }
      $colorcount++;
  }
  $html .= "<tr><th>Color key:</th><td>".
      $self->create_color_code($self->app->cgi->param('groups'), $self->app->cgi->param('effective_max')).'</td></tr>'
      if ($self->app->cgi->param('colouring'));
  
  
  # create a help button for the table statistics
  $self->application->register_component('HelpLink', 'SelectHelp');
  my $selectHelp = $self->application->component('SelectHelp');
  $selectHelp->hover_width(200);
  $selectHelp->disable_wiki_link(1);
  
  my ($checkbox_js, $select_labels, $select_values);
  if (dataset_is_phylo($desc)){
      $selectHelp->title('Metagenome Phylogeny Statistics');
      $selectHelp->text('Select on a phylogeny level to see the statistics of your metagenome against the database selected.');
      
      $select_labels = {1=>'Domain', 2=>'Level 2', 3=>'Level 3', 4=>'Level 4', 5=>'Organism Level' };
      $select_values = ['1','2','3','4','5'];
      $html .= "<tr><th>Select Taxonomy Level Display:</th>";
      $checkbox_js = qq~<label><input type='checkbox' name='display_absolute' id='display_absolute' onClick='javascript:display_org_toggle1();'><b>Display Absolute Values</b></label>~;
  }
  elsif (dataset_is_metabolic($desc)){
      $selectHelp->title('Metagenome Metabolic Statistics');
      $selectHelp->text('Select on a subsystem hierarchy level to see the statistics of your metagenome against the database selected.');
      $select_labels = {1=>'Subsystem Hierarchy 1', 2=>'Subsystem Hierarchy 2', 3=>'Subsystem'};
      $select_values = ['1','2','3'];
      $html .= "<tr><th>Select Subsystem Hierarchy Level to Display:</th>";
      $checkbox_js = qq~<label><input type='checkbox' name='display_absolute' id='display_absolute' onClick='javascript:display_org_toggle1("metabolic");'><b>Display Absolute Values</b></label>~;
  }
  $html .= "<td>" . $cgi->popup_menu(-name=> 'select_level',
				     -id=> 'select_level',
				     -labels=> $select_labels,
				     -values=> $select_values,
				     -onChange=>"javascript:set_clicked($class_cols);",
				     -default=> '2') . $selectHelp->output();; 
  $html .= "&nbsp;" x 10 . $checkbox_js;
  $html .= "</td></tr>";
  
  $html .= "</table></div><br>";
  
  
  $html .= $self->start_form('mg_select_level', {metagenome=>$metagenome});
  $html .= $cgi->button(-id=>'clear_all_filters', -class=>'button',
			-name=>'clear_all_filters',
			-value=>'clear all filters',
			-onClick=>'javascript:clear_table_filters(0,' . $class_cols . ');');
  $html .= $cgi->hidden(-id=>'last_clicked',
			-name=>'last_clicked',
			-value=>2);
  $html .= $cgi->hidden(-id=>'mg_selected_qty',
			-name=>'mg_selected_qty',
			-value=> scalar @metagenome_selected);
  
  # show histrograms
  if (dataset_is_phylo($desc)){
      my $visible = "";
      for (my $i=0;$i<4;$i++) {
	  if ($i+1 == 2){
	      $visible = "style='visibility:visible;display:block'";
	  }
	  else{
	      $visible = "style='visibility:hidden;display:none;'";
	  }
	  my $text_level = $i+1;
	  $html .= qq~<div name='histogram_~ . ($i+1) . qq~' id='histogram_~ . ($i+1) . qq~' $visible>~;
	  $html .= "<h3>Phylogenetic Histogram for Level $text_level</h3>";
	  $html .= "<p>The phylogenetic histogram is a graphical representation of the number of fragment hits in the metagenome to the database selected.</p>";
	  
	  # add a tabs box here
	  $self->application->register_component('TabView', 'HistogramTabs_'.$i);
	  my $tab_view_component = $self->application->component('HistogramTabs_'.$i);
	  $tab_view_component->width(1050);
	  $tab_view_component->height(100);
	  my $percent_view = "<div>\n".$self->read_png($Global_Config::temp.'/'.$metagenome.'tax_histogram_percent_'.$i.'.png')."\n</div>\n";
	  my $absolute_view = "<div>\n".$self->read_png($Global_Config::temp.'/'.$metagenome.'tax_histogram_absolute_'.$i.'.png')."\n</div>\n";
	  $tab_view_component->add_tab('Percent Counts', $percent_view);
	  $tab_view_component->add_tab('Absolute Counts', $absolute_view);
	  $html .= $tab_view_component->output();
	  
	  $html .= qq~</div>~;
      }
  }
  
  $html .= $self->end_form();
  $html .= $table->output();
  $html .= "<p class='subscript'>Data generated in ".(time-$time)." seconds.</p>";
  
  return $html;
  
}


=item * B<create_color_code> (I<number_of_groups>, I<maximum>)

This method draws a horizontal bar with the color code. I<number_of_groups> is the 
number of colors. The value I<maximum> is used to write a key to the color legend.

=cut

sub create_color_code {
  my ($self, $groups, $max) = @_;

  # set graphic
  my $bar_height = 20;
  my $bar_width  = 50*$groups;
  my $group_width = $bar_width/$groups;

  # create the image
  my $img = WebGD->new($bar_width, $bar_height);
  my $white = $img->colorResolve(255,255,255);  
  my $black = $img->colorResolve(0,0,0);

  # draw the color code
  foreach (my $i=0; $i<$groups; $i++) {
    my $c = WebColors::get_palette('vitamins')->[$i];
    my $upper = ($i+1)*($max/$groups);
    $img->filledRectangle( $i*$group_width, 0,
			   $i*$group_width+$group_width, $bar_height, 
			   $img->colorResolve(@$c) 
			 );
    $img->string(GD::gdSmallFont, $i*$group_width+8, 3, sprintf("%.3f",$upper), $black);
  }

  return '<img src="'.$img->image_src.'">';
}

sub selectable_metagenomes {
  my ($self) = @_;
  my $metagenomes = [];
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  
  # check for available metagenomes
  my $rast = $self->application->data_handle('MGRAST'); 
  my $org_seen = {}; 
  if (ref($rast)) {
    my ($public_metagenomes) = &get_public_metagenomes($rast);
    if ($self->application->session->user) {
      my $mgs = $rast->Job->get_jobs_for_user($self->application->session->user, 'view', 1);

      # check for collections
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );
      if (scalar(@$coll_prefs)) {
	my $collections = {};
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if (! exists($collections->{$name})) {
	    $collections->{$name} = [];
	  }
	  my $pj;
	  foreach my $pmg (@$public_metagenomes) {
	    if ($pmg->{_id} == $val) {
	      $pj = $pmg;
	      last;
	    }
	  }
	  unless ($pj) {
	    foreach my $mg ($mgs) {
	      if ($mg->{_id} == $val) {
		$pj = $mg;
		last;
	      }
	    }
	  }
	  if ($pj) {
	    push(@{$collections->{$name}}, [ $pj->{genome_id}, $pj->{genome_name} ]);
	  }
	}

	foreach my $coll (sort(keys(%$collections))) {
	  push(@$metagenomes, { label => 'Collection - '.$coll." [".scalar(@{$collections->{$coll}})."]", value => join('||', map { $_->[0]."##".$_->[1] } @{$collections->{$coll}}) });
	}
      }

      # build hash from all accessible metagenomes
      foreach my $mg_job (@$mgs) {
	next if ($org_seen->{$mg_job->genome_id});
	$org_seen->{$mg_job->genome_id} = 1;
	push(@$metagenomes, { label => 'Private - ' . $mg_job->genome_name." (".$mg_job->genome_id.")", value => $mg_job->genome_id });

      }
    }    
    
    foreach my $pmg (@$public_metagenomes) {
      next if ($org_seen->{$pmg->{genome_id}});
      push(@$metagenomes, { label => 'Public - ' . $pmg->{genome_name}." (".$pmg->{genome_id}.")", value => $pmg->{genome_id} });
      $org_seen->{$pmg->{genome_id}} = 1;
    }
  }
  
  return $metagenomes;
}

sub load_count_cells{
  my ($taxas, $level_counts, $id, $total, $seen_taxa) = @_;

  my @cells;
  my $i = 0;
  foreach my $tax (@$taxas){
    if ($level_counts->{$id}->{$i}->{$tax}){
      my ($absolute_score,$score);
      if ($seen_taxa->{$id}->{$tax}){
	$absolute_score=-1; $score=-1;
      }
      else{
	$seen_taxa->{$id}->{$tax}++;
	$absolute_score = $level_counts->{$id}->{$i}->{$tax};
	$score = sprintf("%.4f",$absolute_score/$total);
      }
      push (@cells, ($score, $absolute_score));
    }
    else{
      push (@cells, (0,0));
    }
    $i++;
  }
  return @cells;
}


sub require_javascript {
    return ["$Global_Config::cgi_url/Html/VennDiagram.js"];
}

sub js {
  my ($self) = @_;

  return qq~<script>
function set_clicked(max_cols){
   document.getElementById('select_box').style.cursor="wait";
      var select_obj = document.getElementById('select_level');
      var select = document.getElementById("last_clicked");
      var level = select_obj.value;
      select.value = level;
      if (max_cols == 5){
         display_org_toggle1();
      }
      else {
         display_org_toggle1('metabolic');
      }
      for (var i=level-1;i>=1;i--){
	  show_column(0,i);
      }
      for (var i=level;i<max_cols;i++){
	  hide_column(0,i);
      }
     
      // show or hide the corresponding venn diagram
      for (var i=1;i<=max_cols;i++){
         if (i==level){
            document.getElementById('venn_' + i).style.visibility = 'visible';
            document.getElementById('venn_' + i).style.display = 'block';
            document.getElementById('histogram_' + i).style.visibility = 'visible';
            document.getElementById('histogram_' + i).style.display = 'block';
         }
         else{
            document.getElementById('venn_' + i).style.visibility = 'hidden';
            document.getElementById('venn_' + i).style.display = 'none';
            document.getElementById('histogram_' + i).style.visibility = 'hidden';
            document.getElementById('histogram_' + i).style.display = 'none';
         }
      }
   document.getElementById('select_box').style.cursor="default";
}
function add_new_list(last_clicked){
    var new_field = last_clicked+1;
    var next_box = document.getElementById('level' + new_field);
    var box = document.getElementById('level' + last_clicked);
    var selLength = box.length;

    var new_box_options = new Array();
    for(i=selLength-1; i>=0; i--)
    {
	if(box.options[i].selected){
	    var box_options = document.getElementById(box.options[i].value).value;
	    var tmp = box_options.split("\~");
	    for (var j=0;j<tmp.length;j++){
		new_box_options[new_box_options.length] = tmp[j];
	    }
	}
    }
    new_box_options.sort;
    for (var i=0; i<new_box_options.length;i++){
	var newOpt = new Option(new_box_options[i] + ' (' + document.getElementById(new_box_options[i] + '_count').value + ')', new_box_options[i]);
	next_box.options[i] = newOpt;
    }
}
function clearfield (field){
    for (var j=field;j<=5;j++){
        if (j<5){
	   hide_column(0,j-1);
       }
	var box = document.getElementById('level'+j);
	var selLength = box.length;
	for(i=selLength-1; i>=0; i--)
	{
	    box.options[i] = null;
	}
    }
}
function display_org_toggle (){
    var checkboxid = document.getElementById('display_org');
    var qty = document.getElementById('mg_selected_qty').value;
    var select = document.getElementById("last_clicked").value;
    if (checkboxid.checked){
	show_column(0,4);
	for (var i=0;i<=qty-1;i++){
	    var adder = (i*10)+5;
	    for (var j=0;j<8;j++){
		hide_column(0,j+adder);
	    }
	    show_column(0,adder+8);
	    show_column(0,adder+9);
	}
	uncollapse_rows();
    }
    else{
	hide_column(0,4);
	for (var i=0;i<=qty-1;i++){
           var adder = (i*10)+5;
            for(var j=0;j<10;j++){
		hide_column(0,j+adder);
            }

	   if (select == 1){
	       show_column(0,adder);
	       show_column(0,adder+1);
	   }
	   else if (select == 2){
	       show_column(0,adder+2);
	       show_column(0,adder+3);	       
	   }
	   else if (select == 3){
	       show_column(0,adder+4);
	       show_column(0,adder+5);
	   }
	   else if (select == 4){
	       show_column(0,adder+6);
	       show_column(0,adder+7);
	   }
       }
	collapse_rows(select-1);
    }
}
function display_org_toggle1 (is_metabolic){
    var checkboxid = document.getElementById('display_absolute');
    var qty = document.getElementById('mg_selected_qty').value;
    var select = document.getElementById("last_clicked").value;
    if (is_metabolic == null){
	var precols = 5;
	var max = 10;
        for (var i=0;i<=qty-1;i++){
	  var adder = (i*max)+precols;
	  for(var j=0;j<max;j++){
	    hide_column(0,j+adder);
	  }
        }
	collapse_rows(select-1);
    }
    else{
	var precols = 3;
	var max = 6;
        for (var i=0;i<=qty-1;i++){
	  var adder = (i*max)+precols;
	  for(var j=0;j<max;j++){
	    hide_column(0,j+adder);
	  }
        }
        collapse_rows(select-1,is_metabolic);
    }

    for (var i=0;i<=qty-1;i++){
	var adder = (i*max)+precols;
	
	if (select == 1){
	    if (checkboxid.checked){
		show_column(0,adder+1);
	    }
	    else{
		show_column(0,adder);
	    }
	}
	else if (select == 2){
	    if (checkboxid.checked){
		show_column(0,adder+3);
	    }
	    else{
		show_column(0,adder+2);	       
	    }
	}
	else if (select == 3){
	    if (checkboxid.checked){
		show_column(0,adder+5);
	    }
	    else{
		show_column(0,adder+4);
	    }
	}
	else if (select == 4){
	    if (checkboxid.checked){
		show_column(0,adder+7);
	    }
	    else{
		show_column(0,adder+6);
	    }
	}
	else if (select == 5){
	    if (checkboxid.checked){	    
		show_column(0,adder+9);
	    }
	    else{
		show_column(0,adder+8);
	    }
	}

    }

}

function collapse_rows(level,metabolic) {
    var col;
    var col_diff;
    var col_class;
    if (metabolic == null){
       col_class = 10;
       col_diff = 0;
    }
    else{
       col_class = 6;
       col_diff = 2;
    }

    table_reset_filters(0);
    var qty = document.getElementById('mg_selected_qty').value;
    if (level == 0){
	col = 6-col_diff;
    } else if (level == 1){
	col = 8-col_diff;
    } else if (level == 2){
	col = 10-col_diff;
    } else if (level == 3){
	col = 12-col_diff;
    } else if (level == 4){
	col = 14-col_diff;
    }

    for (var i=0;i<qty;i++){
	var new_col = col + (i*col_class);
	var operator = document.getElementById('table_0_operator_' + new_col);
	var operand =  document.getElementById('table_0_operand_' + new_col);

	operator.value = 'unequal';
	operator.selectedIndex=1;
	operand.value = '-1';
    }
    table_filter(0);

}
function uncollapse_rows(){
    var i=0;
    while (document.getElementById('cell_0_0_' + i) != null){
	document.getElementById('0_row_' + i).style.display = 'table-cell';
	i++;
    }
    reload_table(0);
}
function clear_table_filters(id,max){
   for (var i=1;i<=max;i++){
       var filter = document.getElementById('table_' + id + '_operand_' + i);
       filter.text = 'all';
       filter.selectedIndex = 0;
       filter.value = '';
   }
   check_submit_filter2("0");
}
function change_dataset_select () {
   var select = document.getElementById("dataset_select");
   var radio_meta = document.getElementById("metabolic_type");
   var options_meta = ["~.join('", "', @{$self->data('dataset_select_metabolic')}).qq~"];
   var labels_meta = ["~;

}

sub create_graph_comparison {
    my ($self, $levels, $metagenome) = @_;

    my $job = $self->data('job');

    my $bin_max = 0;
    my $labels = {};
    my $ids = {};
    my $graph_sizes = {};
    my $bin_sizes = {};
    my $id_colors = {};
    my $mini_graphs = {};

    foreach my $level (keys %$levels) {
        foreach my $tax (keys %{$levels->{$level}})
        {
            $graph_sizes->{$level}->{text_width} = length ($tax) unless ($graph_sizes->{$level}->{text_width} > length ($tax));
            $graph_sizes->{$level}->{taxa}++;
            foreach my $id (keys %{$levels->{$level}->{$tax}})
            {
                $graph_sizes->{$level}->{max_width} = $levels->{$level}->{$tax}->{$id} unless ($graph_sizes->{$level}->{max_width} > $levels->{$level}->{$tax}->{$id});
                $bin_sizes->{$level}->{$id} += $levels->{$level}->{$tax}->{$id};
                $ids->{$id}++;
            }
        }
    }
    my @ids_array = keys %$ids;

    # set histogram sizes
    my $padding_bottom = GD::gdSmallFont->height*2+2;
    my $bar_width = 10;
    my $bar_spacing = 2;
    my $bar_spacing2 = 4;
    my $font_width = GD::gdSmallFont->width();

    # set bin parameter and compute binning
    my $width = 1000;

    foreach my $graph_type ('absolute', 'percent') {
        foreach my $level (keys %$levels) {
            # create the image
            my $total_bars = $graph_sizes->{$level}->{taxa}*(scalar(@ids_array));
            my $height = 35 + ($total_bars*$bar_width) + ($total_bars*$bar_spacing) + (($total_bars/scalar(@ids_array))*$bar_spacing2);
            my $img = GD::Image->new($width, $height+$padding_bottom);
            my $white = $img->colorResolve(255,255,255);
            my $black = $img->colorResolve(0,0,0);

            my $color_count=0;
            my $legend_x = $width-40;
            my $legend_y = 5;
            $img->string(GD::gdMediumBoldFont, ($width/2)-100, $legend_y, 'Phylogenetic histogram with '.$graph_type.' values', $black);
            $legend_y += 12;
            if ($graph_type eq 'absolute') {
		$img->string(GD::gdSmallFont, ($width/2)-50, $legend_y, '(maximum value is '.$graph_sizes->{$level}->{max_width}.')', $black);
            }

            foreach my $id (@ids_array)
            {
                $img->filledRectangle($legend_x,$legend_y,$legend_x+30,$legend_y+10, $img->colorResolve(@{WebColors::get_palette('many')->[$color_count]}));
                $img->string(GD::gdSmallFont, $legend_x-(length($id)*6), $legend_y, $id, $black);
                $id_colors->{$id} = WebColors::get_palette('many')->[$color_count];
		$legend_y += 12;
                $color_count++;
            }
            my $start_bar_x = 6*$graph_sizes->{$level}->{text_width};
            my $x = $start_bar_x;
            my $y = 35;
            my $graph_width = $width - $start_bar_x - 100;
            my $bar_width_mod = $graph_width/1;

            foreach my $tax (keys %{$levels->{$level}}) {
                for (my $n = 0; $n < scalar @ids_array; $n++) {
                    my $id = $ids_array[$n];
                    my $count = $levels->{$level}->{$tax}->{$id} || 0;
                    my $percent = sprintf ("%.2f", ($count / $bin_sizes->{$level}->{$id})*100);
                    my ($bar_text, $x2);
                    if ($graph_type eq 'absolute') {
                        $bar_width_mod = ($graph_width)/$graph_sizes->{$level}->{max_width} if ($graph_sizes->{$level}->{max_width});
                        $x2 = $x+($count*$bar_width_mod);
                        $bar_text = $count;
                    }
                    else {
                        $bar_width_mod = $graph_width/100;
                        $x2 = $x+($percent*$bar_width_mod);
                        $bar_text = $percent . '%';
                    }
                    $img->filledRectangle( $x, $y, $x2, $y+$bar_width, $img->colorResolve(@{WebColors::get_palette('many')->[$n]}) );
                    my $text_x = $x-(length($tax)*6)-2;
                    $img->string(GD::gdSmallFont, $text_x, $y, $tax, $black) if ($n == 0);
                    $img->string(GD::gdSmallFont, $x2+5, $y, $bar_text, $black);
                    $y += ($bar_width+($bar_spacing));
                }
                $y += ($bar_spacing2);
            }

            $img->line( $start_bar_x, 35, $start_bar_x, $height, $black );
            $img->line( $start_bar_x, $height, $start_bar_x + $graph_width + 5, $height, $black);
            $img->line( $start_bar_x+ $graph_width, $height-2, $start_bar_x+$graph_width, $height+2, $black);

            if ($graph_type eq 'absolute') {
                $img->string(GD::gdSmallFont, $start_bar_x+ $graph_width, $height+10, $graph_sizes->{$level}->{max_width}, $black);
            }
            else {
                $img->string(GD::gdSmallFont, $start_bar_x+ $graph_width, $height+10, '100%', $black);
            }

            # write to file
            my $file = $Global_Config::temp.'/'.$metagenome.'tax_histogram_'.$graph_type.'_'.$level.'.png';
            #print STDERR "FILE: $file";
            open (PNG, ">$file") || die "Unable to write png file $file: $@";
            binmode PNG;
            print PNG $img->png;
            close (PNG);
        }
    }
    return ($id_colors, $mini_graphs);

}

=pod

=item * B<read_png> (I<png_filename>)

Small helper method that reads a png from disk and embeds it as WebGD image.

=cut

sub read_png {
    my ($self, $file) = @_;

    my $img = WebGD->newFromPng($file);
    if($img) {
        return '<img src="'.$img->image_src.'">';
    }
    else {
        return '<p><em>Not yet computed.</em></p>';
    }

}

sub connect_to_ach {
    my ($self) = @_;

        ## connect to the ACH database
    my $table = "ACH_DATA";
    my $fig_path = "/vol/seed-anno-mirror";
    my $db = "ACH_TEST";
    my $dbuser = "ach";
    my $dbhost = "bio-data-1.mcs.anl.gov";
    my $dbpass = '';
    my $dbport = '';
    my $dbh;
    if ($dbhost)
    {
        $dbh = DBI->connect("DBI:mysql:dbname=$db;host=$dbhost", $dbuser, $dbpass);
    }

    unless ($dbh) {
        print STDERR "Error , " , DBI->error , "\n";
    }

    my $ach = AnnotationClearingHouse::ACH->new( $dbh );

    return $ach;
}

sub get_md5_counts {
    my ($self, $dataset, $id, $lineages, $ach) = @_;

    my $data = $self->data('mgdb')->get_all_sequence_hits($dataset);

    my $ids = [];
    my $id_count = 0;
    foreach my $row (@$data) {
        push @$ids, $row->[2];

	last if ($id_count > 100000);
	$id_count++;
    }

    my $lineage_counts = {};
    my $org_list = {};
    # get all the ids2sets data

    if (scalar @$ids > 0)
    {
	my $count = 0;
	my $md5_hits = {};
	my $id_list;

	foreach my $row (@{ $ach->ids2organisms($ids) }){
	    my $lineage;
	    
	    # get the lineage of each organism for counting hits
	    my $genus = $row->[0];
	    
	    next if ($genus =~ /organism not parsed/);
	    if (defined $lineages->{uc($genus)})
	    {
		$lineage = $lineages->{uc($genus)};
	    }
	    else
	    {
		my @values = split(/\s+/, $genus);
		
		if (defined $lineages->{uc($values[0])})
		{
		    $lineage = $lineages->{uc($values[0])};
		}
		else
		{
		    $lineage = "";
		}
	    }
	    
	    # split the lineage to the top 4 levels
	    if ($lineage)
	    {
		my @values = split (/\; /, $lineage);
		for (my $i=0;$i<=3;$i++)
		{
		    $lineage_counts->{$i}->{$values[$i]}++;
		}
		$lineage_counts->{organism_level}->{$genus}++;
		$org_list->{$genus} = $lineage;
		$count++;
	    }
	}
    }
    return ($lineage_counts, $org_list);
}

sub get_lineages
{
    my ($self) = @_;

    my $fig = new FIG;
    my $tax_list = $fig->taxonomy_list;
    my $lineages = {};

    foreach my $tax ( keys %$tax_list)
    {
	$lineages->{uc($fig->genus_species($tax))} = $tax_list->{$tax};
	my $name = $fig->genus_species($tax);
	if ($name =~ /\s+/)
        {
	    my @values = split (/\s+/, $name);
            $lineages->{uc($values[0])}= $tax_list->{$tax};
	}
    }
    return $lineages;
}
