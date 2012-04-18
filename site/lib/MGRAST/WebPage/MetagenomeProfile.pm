package MGRAST::WebPage::MetagenomeProfile;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use URI::Escape;

use GD;

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( :DEFAULT );

1;

=pod

=head1 NAME

MetagenomeProfile - an instance of WebPage which displays metabolic/taxonomic profiles

=head1 DESCRIPTION

Display information about the taxonomic or metabolic distribution of metagenomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  # register components
  $self->application->register_component('PieChart', 'PieToplevel');
  $self->application->register_component('PieChart', 'PieDetails1');
  $self->application->register_component('PieChart', 'PieDetails2');
  $self->application->register_component('Table', 'MGTable');
  $self->application->register_component('Ajax', 'MGAjax');
  $self->application->register_component('TabView', 'Results');
  $self->application->register_component('TabView', 'Helptext');
  $self->application->register_component('Info', 'Info');
  $self->application->register_component('PhyloTree', 'ptree');
  $self->application->register_component('RollerBlind', 'image_control');
  $self->application->register_component('RollerBlind', 'parameter_control');
  $self->application->register_component('FilterSelect', 'mgfilterselect');
  $self->application->register_component('HelpLink', 'tree_help');
  $self->title('Sequence Profile');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  # load the settings for this type
  $self->get_settings_for_dataset();

  # sanity check on job
  if ($id) {
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless ($job) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);
    
    # check if this is a new job and set according min evalue
    if ($job->id > 1200) {
      $self->data('min_evalue', '0.001');
    } else {
      $self->data('min_evalue', '0.001');
    }

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

    unless($self->app->cgi->param('evalue')){
      $self->app->cgi->param('evalue', $self->data('min_evalue'));
    }

    $mgdb->query_load_from_cgi($self->app->cgi, $self->data('dataset'));
    $self->data('mgdb', $mgdb);

    my $id2 = $self->application->cgi->param('comparison_metagenome');
    if ($id2) {
      $self->data('comp_mgdb', MGRAST::MetagenomeAnalysis->new($self->app->data_handle('MGRAST')->Job->init({ genome_id => $id2 })));
    }
  }

  return 1;
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  unless($metagenome) {
    $self->application->add_message('warning', 'No metagenome id given.');
    return "<h2>An error has occured:</h2>\n".
      "<p><em>No metagenome id given.</em></p>";
  }

  my $cgi = $self->application->cgi;
  my $job = $self->data('job');
  my $dataset =  $self->application->cgi->param('dataset');
  my $desc = $self->data('dataset_desc');

  # get sequence data
  my $seqs_num = $job->metaxml->get_metadata('preprocess.count_proc.num_seqs');
  my $seqs_in_evidence = $self->data('mgdb')->get_hits_count($dataset);
  my ($alen_min, $alen_max) = $self->data('mgdb')->get_align_len_range($dataset);


  # generate range arrays for form
  my @alen;
  my $len50 = 0;
  for( my $i = $alen_max; $i > $alen_min; $i-=10 ){
    push @alen, $i;
    $len50 = 1 if ($i == 50);
  }
  push @alen, $alen_min;
  push @alen, 50 unless ($len50);
  @alen = sort { $a <=> $b } @alen;

  my @pvalue;
  for( my $i = 200; $i >= 20; $i-=10 ){
    push @pvalue, $i;
  }

  my @identity;
  for (my $i=100; $i>=40; $i-=2 ){
    push @identity, $i;
  }
  
  my $meta_text = '';
  my $phylo_text = '';

  # write title + intro
  my $html = "<span style='font-size: 1.6em'><b>Sequence Profile </b></span>";
  $html .= "<span style='font-size: 1.6em'><b>for ".$job->genome_name." (".$job->genome_id.")</b></span>" if($job); 
  
  $html .= "<h3>Choose options</h3>";

  $meta_text .= "<div style='padding:0 5px 5px 5px; text-align: justify;'><img src=\"$FIG_Config::cgi_url/Html/metabolic.jpg\" style='width: 100; heigth: 100; float: left; padding: 5px 10px 10px 0;'><h3>Metabolic Profile with Subsystem</h3>";
  $meta_text .=  "<p>MG-RAST computes metabolic profiles based on <a href='http://www.theseed.org/wiki/Glossary#Subsystem'>Subsystems</a> from the sequences from your metagenome sample. You can modify the parameters of the calculated Metabolic Profile including e-value, p-value , percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sequence characteristics of your sample. We recommend a minimal alignment length of 50bp be used with all RNA databases.</p></div>";

  $phylo_text .= "<div style='padding:0 5px 5px 5px; text-align: justify;'><img src=\"$FIG_Config::cgi_url/Html/phylogenetic.gif\" style='width: 100; heigth: 100;float: left; padding: 5px 10px 10px 0;'><h3>Phylogenetic Profile based on RDP</h3>";
  $phylo_text .= "<p>MG-RAST computes phylogenetic profiles base on various RNA databases (RDP, GREENGENES, Silva, and European Ribosomal) the SEED database. RDP is used as a default database to show the taxonomic distributions. You can modify the parameters of the calculated Metabolic Profile including e-value, p-value , percent identity and minimum alignment length. This will allow you to refine the analysis to suit the sample and sequence characteristics of your metagenome.  The SEED database provides an alternative way to identify taxonomies in the sample. Protein encoding genes are BLASTed against the SEED database and the taxonomy of the best hit is used to compile taxonomies of the sample.</p></div>";

  $html .= "<table><tr><td>";

  # begin form with parameters
  $html .= $self->start_form('mg_stats', { metagenome => $metagenome });
  my $labels = $self->data('dataset_labels');  
  my $profile_type_select = "<table><tr><td style='vertical-align:middle;'><input type='radio' ".($dataset =~ /subsystem/ ? "checked='checked'" : '')." name='type' id='metabolic_type' value='metabolic' onclick='change_dataset_select();'></td><td style='vertical-align:middle;'></td><td style='vertical-align:middle;'><img src=\"$FIG_Config::cgi_url/Html/metabolic.jpg\" style='width: 50; heigth: 50;'></td><td style='vertical-align:middle;'><b>Metabolic Profile</b></td></tr></table>"; 
  
  $profile_type_select .= "<table><tr><td style='vertical-align:middle;'><input type='radio' name='type' value='phylogenetic' ".($dataset =~ /subsystem/ ? '' : "checked='checked'")." onclick='change_dataset_select();'></td><td style='vertical-align:middle;'><img src=\"$FIG_Config::cgi_url/Html/phylogenetic.gif\" style='width: 50; heigth: 50;'></td><td style='vertical-align:middle;'><b>Phylogenetic Profile</b></td></tr></table>";

  my $def_string = ($cgi->param('evalue') || '') . ";" . ($cgi->param('identity') || '') . ";" . ($cgi->param('align_len') || '');
  my $parameter_content = "<table>";
  $parameter_content .= "<tr><td style='width: 160px'>Profile type / Dataset</td><td>".
    ($cgi->popup_menu( -id => 'metabolic_type', -name => 'type', -style => 'margin-right: 5px', -onchange => 'change_dataset_select()', -default => $cgi->param('type') || '', -values => [ 'Metabolic', 'Phylogenetic' ])).($cgi->popup_menu( -id => 'dataset_select', -name => 'dataset', -default => $dataset, -values => $self->data('dataset_select'), ($labels ? (-labels => $labels) : ()))).
	"</td><td><select onchange='apply_preset(this.value);'><option value='$def_string'>default</option><option value='0;98;50'>match rDNA</option><option value='0;80;0'>match protein</option></select></td></tr>";
  $parameter_content .= "<tr><td>e-value</td><td>".
    ($cgi->popup_menu( -id => 'evalue',  -name => 'evalue', -default => $cgi->param('evalue') || '', -values => [ $self->data('min_evalue'), '1e-05', '1e-10', '1e-20', '1e-30', '1e-40', '1e-50', '1e-60' ])).
      "</td></tr>";
  $parameter_content .= "<tr><td>percent identity</td><td>".
    ($cgi->popup_menu( -id => 'identity', -name => 'identity', -default => $cgi->param('identity') || '', -values => [ '', @identity ])).
      "</td></tr>";
  $parameter_content .= "<tr><td>alignment length</td><td>".
    ($cgi->popup_menu( -id => 'align_len', -name => 'align_len', -default => $cgi->param('align_len') || '', -values => [ '', @alen ]))
      ."</td></tr>";
  $parameter_content .= "</table>";

  my $parameter_control = $self->application->component('parameter_control');
  $parameter_control->add_blind({ title => 'Select profile type, dataset and filter options', content => $parameter_content });
  $parameter_control->width(400);
  $html .= $parameter_control->output()."<br>";

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


  $html .= $self->button('Re-compute results', style=>'height:35px;width:150px;font-size:10pt;');
  $html .= "</div>";

  # add ajax output
  my $ajax = $self->application->component('MGAjax');
  $html .= $ajax->output;

  # add parse count data code
  $html .= count_data_js();
  
  if($dataset){
    # add div for charts
    $html .= "\n<h3>Profile results:</h3>\n";
    $html .= "<p>This ".($dataset =~ /subsystem/ ? 'Metabolic' : "Phylogenetic")." profile has been generated with the following parameters:";

    $html .= "<table>";
    $html .= "<tr><th>Dataset:</th><td>".$labels->{$dataset}."</td></tr>";
    $html .= "<tr><th>Number of sequences:</th><td>".$seqs_num."</td></tr>";
    $html .= "<tr><th>E-value:</th><td>".($cgi->param('evalue') || $self->data('min_evalue'))."</td></tr>"; 
    $html .= "<tr><th>P-value:</th><td>".$cgi->param('bitscore')."</td></tr>" if $cgi->param('bitscore');
    $html .= "<tr><th>Percent identity:</th><td>".$cgi->param('identity')."</td></tr>"  if $cgi->param('identity');
    $html .= "<tr><th>Alignment length :</th><td>".$cgi->param('align_len')."</td></tr>" if $cgi->param('align_len');
    $html .= "</table>";

    $html .= "<p style='width:800px;'>Clicking on a category below will display a pie-chart of the distribution in the subcategory. In the tabular view, each category is linked to a table of the subset. Those subsets allow <b>downloading</b> in FASTA format. The organisms in the tabular view are linked to a <b>recruitment plot</b>. To download the entire dataset, please go to the <a href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$metagenome'>download page</a>.</p>";
    if($dataset =~ /subsystem/){
      $html .= "<p>The pie charts provide actual counts of sequences that hit a given functional role based on the Subsystem database from the SEED.  You can select a given subsystem group to get more detailed information up to 3 levels. These selections are represented in the Tabular View.</p>";
    } else {
      $html .= "<p>The pie charts provide actual counts of sequences that hit a given taxonomy based on a given database.  You can select a given group to get more detailed information up to 3 levels. These selections are represented in the Tabular View.</p>";
    }
    $html .= "<p>\n".&create_classified_vs_non_bar($seqs_num, $seqs_in_evidence, 0)."\n</p>\n";

    # charts
    my $charts =  "<table><tr>\n";
    $charts .= "<td><div id='chart_0'>computing data...</div></td>";
    $charts .= "<td><div id='chart_1'></div></td>";
    $charts .= "<td><div id='chart_2'></div></td></tr>";
    $charts .= "<tr><td><div id='chart_3'></div></td>";
    $charts .= "<td><div id='chart_4'></div></td>";
    $charts .= "<td><div id='chart_5'></div></td>";
    $charts .= "</tr></table>\n\n";
    
    # table
    my $table = "<div id='table'>";
    $table .= "<img src='".IMAGES."clear.gif' onLoad='execute_ajax(\"load_table\",\"table\",\"mg_stats\",\"Loading table...\");' />";
    $table .= "</div>";
    

    # tree
    my $pt = $self->application->component('ptree');
    
    my $tree = "<div id='tree'><img src='".IMAGES."clear.gif' onLoad='execute_ajax(\"load_tree\",\"tree\",\"mg_stats\",\"Loading tree...\");' /></div>";

    # put them into tabs
    my $results = $self->application->component('Results');
    $results->width('100%');
    $results->add_tab('Charts', $charts);
    $results->add_tab('Tabular View', $table);
    $results->add_tab('Tree View', $tree);
    $html .= $results->output;
  }
  
  return $html;

}

=pod 

=item * B<load_table> ()

Returns the table. This method is invoked by an AJAX call.

=cut

sub load_table {
  my $self = shift;

  # start the timer
  my $time = time;

  # define columns and fetch best hits by dataset
  my $dataset = $self->data('dataset');
  my $desc = $self->data('dataset_desc');
  my $data;
  
  # create table
  my $table = $self->application->component('MGTable');
  my $pivot = "<fieldset style='width: 300px;'><legend>group table by</legend>";

  my $columns = [];
  if ($desc eq 'phylogenetic classification')
  {
    $columns = [ { name => 'Domain', filter => 1, operator => 'combobox',
		   visible => 0, show_control => 1 },
		 { name => '', filter => 1, operator => 'combobox', sortable => 1 },
		 { name => '', filter => 1, operator => 'combobox' },
		 { name => '', filter => 1, operator => 'combobox' },
		 { name => '', filter => 1, operator => 'combobox' },
		 { name => 'Organism Name', filter => 1 },
		 { name => '# Hits', sortable => 1 }
	       ];

    $pivot .= "<input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"6\");pivot(\"".$table->id."\", \"1\", \"6\");'> Level 2";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"6\");pivot(\"".$table->id."\", \"2\", \"6\");'> Level 3";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"6\");pivot(\"".$table->id."\", \"3\", \"6\");'> Level 4";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"6\");pivot(\"".$table->id."\", \"4\", \"6\");'> Level 5";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"6\");'> Organism Name";

    $data = $self->data('mgdb')->get_taxa_counts($dataset);
  }
  elsif ($desc eq 'metabolic reconstruction')
  {
    $columns = [ { name => 'Subsystem Hierarchy 1', filter => 1, operator => 'combobox', sortable => 1 },
		 { name => 'Subsystem Hierarchy 2', filter => 1, operator => 'combobox' },
		 { name => 'Subsystem Name', filter => 1, sortable => 1 },
		 { name => '# Hits', sortable => 1 }, 
	       ];

    $pivot .= "<input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"3\");pivot(\"".$table->id."\", \"0\", \"3\");'> Subsystem Hierarchy 1";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"3\");pivot(\"".$table->id."\", \"1\", \"3\");'> Subsystem Hierarchy 2";
    $pivot .= "<br><input type='radio' name='pivot_group' checked=checked onclick='clear_pivot(\"".$table->id."\", \"0\", \"3\");'> Subsystem Name";

    $data = $self->data('mgdb')->get_subsystem_counts($dataset);

  }
  else {
    die "Unknown dataset in ".__PACKAGE__.": $dataset";
  }

  $pivot .= "</fieldset></br>";

  # set url string for params
  my $url_params = join('&', map { $self->app->cgi->param($_) ? $_.'='.uri_escape($self->app->cgi->param($_)) : () } 
			qw( dataset metagenome evalue bitscore align_len identity )
			);

  # store the data
  my $table_data = [];
  my $count_data = '';

  if ($desc eq 'phylogenetic classification') {
    # expand data
    my $expanded_data = [];
    my $rank_0 = {};
    my $kids_0 = {};
    my $rank_1 = {};
    my $kids_1 = {};
    my $rank_2 = {};
    my $kids_2 = {};
    my $rank_3 = {};
    my $kids_3 = {};
    my $rank_4 = {};
    my $kids_4 = {};
    my $rank_5 = {};
    foreach (@$data) {
      my ($taxonomy, $count) = @$_;
      my $taxa = $self->data('mgdb')->split_taxstr($taxonomy);
      my $organism = $self->data('mgdb')->key2taxa($taxa->[scalar(@$taxa)-1]);
      
      push @$expanded_data, [ $self->data('mgdb')->key2taxa($taxa->[0]) || '',
			      $self->data('mgdb')->key2taxa($taxa->[1]) || '',
			      $self->data('mgdb')->key2taxa($taxa->[2]) || '',
			      $self->data('mgdb')->key2taxa($taxa->[3]) || '',
			      $self->data('mgdb')->key2taxa($taxa->[4]) || '',
			      $organism,
			      $count,
			      $taxonomy ];
    }
    @$expanded_data = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] || $a->[4] cmp $b->[4] || $a->[5] cmp $b->[5] } @$expanded_data;
    
    # do counts
    foreach my $row (@$expanded_data) {
      if (exists($rank_0->{$row->[0]})) {
	$rank_0->{$row->[0]} += $row->[6];
      } else {
	$rank_0->{$row->[0]} = $row->[6];
      }
      if (exists($rank_1->{$row->[1]})) {
	$rank_1->{$row->[1]} += $row->[6];
      } else {
	$rank_1->{$row->[1]} = $row->[6];
      }
      if (exists($rank_2->{$row->[2]})) {
	$rank_2->{$row->[2]} += $row->[6];
      } else {
	$rank_2->{$row->[2]} = $row->[6];
      }
      if (exists($rank_3->{$row->[3]})) {
	$rank_3->{$row->[3]} += $row->[6];
      } else {
	$rank_3->{$row->[3]} = $row->[6];
      }
      if (exists($rank_4->{$row->[4]})) {
	$rank_4->{$row->[4]} += $row->[6];
      } else {
	$rank_4->{$row->[4]} = $row->[6];
      }
      if (exists($rank_5->{$row->[5]})) {
	$rank_5->{$row->[5]} += $row->[6];
      } else {
	$rank_5->{$row->[5]} = $row->[6];
      }
      $kids_0->{$row->[0]}->{$row->[1]} = 1;
      $kids_1->{$row->[1]}->{$row->[2]} = 1;
      $kids_2->{$row->[2]}->{$row->[3]} = 1;
      $kids_3->{$row->[3]}->{$row->[4]} = 1;
      $kids_4->{$row->[4]}->{$row->[5]} = 1;
    }

    # store the counts in a html-data structure
    my $rank_0_string = join('^', map { $_ . '#' . $rank_0->{$_} } keys(%$rank_0));
    my $rank_1_string = join('^', map { $_ . '#' . $rank_1->{$_} } keys(%$rank_1));
    my $rank_2_string = join('^', map { $_ . '#' . $rank_2->{$_} } keys(%$rank_2));
    my $rank_3_string = join('^', map { $_ . '#' . $rank_3->{$_} } keys(%$rank_3));
    my $rank_4_string = join('^', map { $_ . '#' . $rank_4->{$_} } keys(%$rank_4));
    my $rank_5_string = join('^', map { $_ . '#' . $rank_5->{$_} } keys(%$rank_5));
    $rank_5_string =~ s/'//g;
    my $kids_0_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_0->{$_}})) } keys(%$kids_0));
    my $kids_1_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_1->{$_}})) } keys(%$kids_1));
    my $kids_2_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_2->{$_}})) } keys(%$kids_2));
    my $kids_3_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_3->{$_}})) } keys(%$kids_3));
    my $kids_4_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_4->{$_}})) } keys(%$kids_4));
    $kids_4_string =~ s/'//g;
    $count_data = qq~
<input type='hidden' id='rank_0' value='~.$rank_0_string.qq~'>
<input type='hidden' id='rank_1' value='~.$rank_1_string.qq~'>
<input type='hidden' id='rank_2' value='~.$rank_2_string.qq~'>
<input type='hidden' id='rank_3' value='~.$rank_3_string.qq~'>
<input type='hidden' id='rank_4' value='~.$rank_4_string.qq~'>
<input type='hidden' id='rank_5' value='~.$rank_5_string.qq~'>
<input type='hidden' id='kids_0' value='~.$kids_0_string.qq~'>
<input type='hidden' id='kids_1' value='~.$kids_1_string.qq~'>
<input type='hidden' id='kids_2' value='~.$kids_2_string.qq~'>
<input type='hidden' id='kids_3' value='~.$kids_3_string.qq~'>
<input type='hidden' id='kids_4' value='~.$kids_4_string.qq~'>
<img src=\"$FIG_Config::cgi_url/Html/clear.gif\" onload='parse_count_data();'>~;
    
    foreach my $row (@$expanded_data) {
      my $base_link = "metagenomics.cgi?page=MetagenomeSubset&".$url_params."&get=".uri_escape($row->[7]);

      if($dataset eq "SEED:seed_genome_tax"){
	push @$table_data, [ $row->[0],
			     '<a href="'.$base_link.'&rank=1">'.$row->[1]."</a>",
			     '<a href="'.$base_link.'&rank=2">'.$row->[2]."</a>",
			     '<a href="'.$base_link.'&rank=3">'.$row->[3]."</a>",
			     '<a href="'.$base_link.'&rank=4">'.$row->[4]."</a>",
			     '<a href="metagenomics.cgi?page=MetagenomeRecruitmentPlot&ref_genome='.$self->data('mgdb')->get_genome_id($row->[7]).'&metagenome='.$self->application->cgi->param('metagenome').'">'.$row->[5]."</a>",
			     $row->[6],
			   ];
      } else {
	push @$table_data, [ $row->[0],
			     '<a href="'.$base_link.'&rank=1">'.$row->[1]."</a>",
			     '<a href="'.$base_link.'&rank=2">'.$row->[2]."</a>",
			     '<a href="'.$base_link.'&rank=3">'.$row->[3]."</a>",
			     '<a href="'.$base_link.'&rank=4">'.$row->[4]."</a>",
			     '<a href="'.$base_link.'&rank=4">'.$row->[5]."</a>",
			     $row->[6],
			   ];
      }
    }
  } elsif ($desc eq 'metabolic reconstruction') {
    # expand data
    my $expanded_data = [];
    my $rank_0 = {};
    my $kids_0 = {};
    my $rank_1 = {};
    my $kids_1 = {};
    my $rank_2 = {};

    foreach (@$data) {
      my ($h1, $h2, $subsystem, $taxonomy, $count) = @$_;
      
      push @$expanded_data, [ $self->data('mgdb')->key2taxa($h1) || 'Unclassified',
			      $self->data('mgdb')->key2taxa($h2) || $self->data('mgdb')->key2taxa($h1) || 'Unclassified',
			      $self->data('mgdb')->key2taxa($subsystem) || '',
			      $count,
			      $taxonomy
			    ];
      
    }
    @$expanded_data = sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3] } @$expanded_data;

    # do counts
    foreach my $row (@$expanded_data) {
      if (exists($rank_0->{$row->[0]})) {
	$rank_0->{$row->[0]} += $row->[3];
      } else {
	$rank_0->{$row->[0]} = $row->[3];
      }
      if (exists($rank_1->{$row->[1]})) {
	$rank_1->{$row->[1]} += $row->[3];
      } else {
	$rank_1->{$row->[1]} = $row->[3];
      }
      if (exists($rank_2->{$row->[2]})) {
	$rank_2->{$row->[2]} += $row->[3];
      } else {
	$rank_2->{$row->[2]} = $row->[3];
      }
      $kids_0->{$row->[0]}->{$row->[1]} = 1;
      $kids_1->{$row->[1]}->{$row->[2]} = 1;
    }

    # store the counts in a html-data structure
    my $rank_0_string = join('^', map { $_ . '#' . $rank_0->{$_} } keys(%$rank_0));
    my $rank_1_string = join('^', map { $_ . '#' . $rank_1->{$_} } keys(%$rank_1));
    my $rank_2_string = join('^', map { $_ . '#' . $rank_2->{$_} } keys(%$rank_2));
    my $kids_0_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_0->{$_}})) } keys(%$kids_0));
    my $kids_1_string = join('^', map { $_ . '#' . join('#', keys(%{$kids_1->{$_}})) } keys(%$kids_1));
    $rank_0_string =~ s/'//g;
    $rank_1_string =~ s/'//g;
    $rank_2_string =~ s/'//g;
    $kids_0_string =~ s/'//g;
    $kids_1_string =~ s/'//g;
    $count_data = qq~
<input type='hidden' id='rank_0' value='~.$rank_0_string.qq~'>
<input type='hidden' id='rank_1' value='~.$rank_1_string.qq~'>
<input type='hidden' id='rank_2' value='~.$rank_2_string.qq~'>
<input type='hidden' id='kids_0' value='~.$kids_0_string.qq~'>
<input type='hidden' id='kids_1' value='~.$kids_1_string.qq~'>
<img src=\"$FIG_Config::cgi_url/Html/clear.gif\" onload='parse_count_data();'>~;

    my $seenGroup = {};
    foreach my $row (@$expanded_data) {
      next if $seenGroup->{$row->[2]};
      $seenGroup->{$row->[2]}++;
      my $base_link = "metagenomics.cgi?page=MetagenomeSubset&".$url_params."&get=".uri_escape($row->[4]);

      push @$table_data, [ '<a href="'.$base_link.'&rank=0">'.$row->[0]."</a>" || '',
			   '<a href="'.$base_link.'&rank=1">'.$row->[1]."</a>" || '',
			   '<a href="'.$base_link.'&rank=2">'.$row->[2]."</a>" || '',
			   $rank_2->{$row->[2]}
			 ];
    }
  } else {
    die "Unknown dataset in ".__PACKAGE__.": $dataset";
  }

  $table->show_export_button({ strip_html => 1, hide_invisible_columns => 1 });
  $table->show_clear_filter_button(1);
  if (scalar(@$data) > 50) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
  }
  $table->columns($columns);
  $table->data($table_data);
  
  my $html = $pivot.$table->output();
  $html .= "<p class='subscript'>Data generated in ".(time-$time)." seconds.</p>";
  $html .= $count_data;

  return $html;

}

sub load_chart {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my @data = split(/\^/, $cgi->param('data'));
  my $rank = $cgi->param('rank') + 1;
  my $group = $cgi->param('group');
  my $last = 6;
  my $ss = $cgi->param('ss');
  if (($group eq 'Group') ||($ss)) {
    $ss = "ss=1&";
    $last = 3;
  } else {
    $ss = '';
  }

  unless (scalar(@data)) {
    return "";
  }

  # generate a data array with the counts and write color key
  my $chart_key = '<table>';
  my $chart_data = [];
  my $total = 0;
  map { my ($key, $value) = split(/#/, $_); $total += $value; } @data;
  foreach my $d (@data) {

    my ($key, $value) = split(/#/, $d);
    my $percent = $value / $total * 100;
    $percent = sprintf("%.2f%%", $percent);
    my $color = WebColors::get_palette('excel')->[ scalar(@$chart_data) ] || [0,0,0];
    $chart_key .= "<tr><td style='width: 15px; background-color: rgb(".join(',',@$color).")';&nbsp</td>";
    my $val = "$key $percent ($value)";
    if ($rank < $last) {
      $val = qq~<a style='cursor: pointer; color: blue; text-decoration: underline;' onclick='clear_ranks("~.$rank.qq~");execute_ajax("load_chart","chart_~.$rank.qq~","~.$ss.qq~rank=~.$rank.qq~&data="+get_count_data("rank_~.$rank.qq~", "~.$key.qq~")+"&group=~.uri_escape($key).qq~","Loading chart...");'>$val</a>~;
    }
    $chart_key .= "<td>$val</td></tr>";

    push @$chart_data, { data => $value, title => $key };

  }
  $chart_key .= '</table>';

  # fill the pie chart
  my $chart = $self->application->component('PieToplevel');
  $chart->size(250);
  $chart->data($chart_data);

  # output
  my $html = "<table>";
  $html .= "<tr><th>$group</th></tr><tr><td>".$chart->output()."<br/>".$chart_key."</td></tr>";
  $html .= "</table>";

  return $html;
}


sub count_data_js {
  return qq~<script>
var rank_1_counts = new Array();
var rank_0_kids = new Array();
var rank_2_counts = new Array();
var rank_1_kids = new Array();
var rank_3_counts = new Array();
var rank_2_kids = new Array();
var rank_4_counts = new Array();
var rank_3_kids = new Array();
var rank_5_counts = new Array();
var rank_4_kids = new Array();

function parse_count_data () {
  var rank_str_1 = document.getElementById('rank_1').value;
  var rank_array_1 = rank_str_1.split('^');
  for (h=0;h<rank_array_1.length;h++) {
    var r = rank_array_1[h].split('#');
    rank_1_counts[r[0]] = r[1];
  }
  var rank_str_2 = document.getElementById('rank_2').value;
  var rank_array_2 = rank_str_2.split('^');
  for (h=0;h<rank_array_2.length;h++) {
    var r = rank_array_2[h].split('#');
    rank_2_counts[r[0]] = r[1];
  }
  if (document.getElementById('rank_3')) {
    var rank_str_3 = document.getElementById('rank_3').value;
    var rank_array_3 = rank_str_3.split('^');
    for (h=0;h<rank_array_3.length;h++) {
      var r = rank_array_3[h].split('#');
      rank_3_counts[r[0]] = r[1];
    }
    var rank_str_4 = document.getElementById('rank_4').value;
    var rank_array_4 = rank_str_4.split('^');
    for (h=0;h<rank_array_4.length;h++) {
      var r = rank_array_4[h].split('#');
      rank_4_counts[r[0]] = r[1];
    }
    var rank_str_5 = document.getElementById('rank_5').value;
    var rank_array_5 = rank_str_5.split('^');
    for (h=0;h<rank_array_5.length;h++) {
      var r = rank_array_5[h].split('#');
      rank_5_counts[r[0]] = r[1];
    }
  }
  var kids_str_0 = document.getElementById('kids_0').value;
  var kids_array_0 = kids_str_0.split('^');
  for (h=0;h<kids_array_0.length;h++) {
    var r = kids_array_0[h].split('#');
    var key = r.shift();
    rank_0_kids[key] = r;
  }
  var kids_str_1 = document.getElementById('kids_1').value;
  var kids_array_1 = kids_str_1.split('^');
  for (h=0;h<kids_array_1.length;h++) {
    var r = kids_array_1[h].split('#');
    var key = r.shift();
    rank_1_kids[key] = r;
  }
  var group = 'Group';
  var ss = 0;
  if (document.getElementById('kids_2')) {
    group = 'Domain';
    var kids_str_2 = document.getElementById('kids_2').value;
    var kids_array_2 = kids_str_2.split('^');
    for (h=0;h<kids_array_2.length;h++) {
      var r = kids_array_2[h].split('#');
      var key = r.shift();
      rank_2_kids[key] = r;
    }
    var kids_str_3 = document.getElementById('kids_3').value;
    var kids_array_3 = kids_str_3.split('^');
    for (h=0;h<kids_array_3.length;h++) {
      var r = kids_array_3[h].split('#');
      var key = r.shift();
      rank_3_kids[key] = r;
    }
    var kids_str_4 = document.getElementById('kids_4').value;
    var kids_array_4 = kids_str_4.split('^');
    for (h=0;h<kids_array_4.length;h++) {
      var r = kids_array_4[h].split('#');
      var key = r.shift();
      rank_4_kids[key] = r;
    }
  } else {
    ss = 1;
  }
  execute_ajax("load_chart","chart_0","group="+group+"&rank=0&data="+encodeURIComponent(document.getElementById('rank_0').value),"Loading chart...");
}

function get_count_data (rank, item) {
  var ret = new Array();
  if (rank == 'rank_1') {
    var kids = rank_0_kids[item];
    for (i=0;i<kids.length;i++) {
      ret[ret.length] = kids[i] + "#" + rank_1_counts[kids[i]];
    }
  } else if (rank == 'rank_2') {
    var kids = rank_1_kids[item];
    for (i=0;i<kids.length;i++) {
      ret[ret.length] = kids[i] + "#" + rank_2_counts[kids[i]];
    }    
  } else if (rank == 'rank_3') {
    var kids = rank_2_kids[item];
    for (i=0;i<kids.length;i++) {
      ret[ret.length] = kids[i] + "#" + rank_3_counts[kids[i]];
    }
  } else if (rank == 'rank_4') {
    var kids = rank_3_kids[item];
    for (i=0;i<kids.length;i++) {
      ret[ret.length] = kids[i] + "#" + rank_4_counts[kids[i]];
    }
  } else if (rank == 'rank_5') {
    var kids = rank_4_kids[item];
    for (i=0;i<kids.length;i++) {
      ret[ret.length] = kids[i] + "#" + rank_5_counts[kids[i]];
    }
  }
  return encodeURIComponent(ret.join('^'));
}

function clear_ranks (rank) {
  for (i=rank;i<6;i++) {
    if (document.getElementById('chart_'+i)) {
      document.getElementById('chart_'+i).innerHTML = '';
    }
  }
}

function apply_preset (params) {
  var p = params.split(";");
  var evalue = p[0];
  var identity = p[1];
  var align_len = p[2];
  var ev = document.getElementById('evalue');
  var id = document.getElementById('identity');
  var al = document.getElementById('align_len');
  ev.selectedIndex = 0;
  id.selectedIndex = 0;
  al.selectedIndex = 0;
  for (i=0; i<ev.options.length; i++) {
    if (ev.options[i].value == evalue) {
      ev.selectedIndex = i;
    }
  }
  for (i=0; i<id.options.length; i++) {
    if (id.options[i].value == identity) {
      id.selectedIndex = i;
    }
  }
  for (i=0; i<al.options.length; i++) {
    if (al.options[i].value == align_len) {
      al.selectedIndex = i;
    }
  }
}
</script>~;
}

sub load_tree {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $comp = $cgi->param('comparison_metagenome') || "";
  my $image_size = $cgi->param('image_size') || "600";
  my $level_distance = $cgi->param('level_distance') || "40";

  my $dataset = $self->data('dataset');
  my $desc = $self->data('dataset_desc');
  my $data;
  my $expanded_data = [];

  my $pt = $application->component('ptree');

  my $dhash = {};
  if ($self->data('comp_mgdb')) {
    if ($desc eq 'phylogenetic classification') {
      $data = $self->data('comp_mgdb')->get_taxa_counts($dataset);
      foreach (@$data) {
	my ($taxonomy, $count) = @$_;
	my $taxa = $self->data('comp_mgdb')->split_taxstr($taxonomy);
	@$taxa = map { $self->data('comp_mgdb')->key2taxa($_) } @$taxa;
	$dhash->{$taxonomy} = [ @$taxa, [ 0, $count ] ];
      }
    } elsif ($desc eq 'metabolic reconstruction') {
      $data = $self->data('comp_mgdb')->get_subsystem_counts($dataset);
      foreach (@$data) {
	my ($h1, $h2, $subsystem, $taxonomy, $count) = @$_;
	$h1 = $self->data('comp_mgdb')->key2taxa($h1) || 'Unclassified';
	$h2 = $self->data('comp_mgdb')->key2taxa($h2) || $self->data('comp_mgdb')->key2taxa($h1) || 'Unclassified';
	$subsystem = $self->data('comp_mgdb')->key2taxa($subsystem) || '';
	my $key = $h1.";".$h2.";".$subsystem;
	$dhash->{$key} = [ 'Subsystem', $h1, $h2, $subsystem, [ 0, $count] ];
      }
    }
  }

  if ($desc eq 'phylogenetic classification') {
    $data = $self->data('mgdb')->get_taxa_counts($dataset);
    foreach (@$data) {
      my ($taxonomy, $count) = @$_;
      my $taxa = $self->data('mgdb')->split_taxstr($taxonomy);
      @$taxa = map { $self->data('mgdb')->key2taxa($_) } @$taxa;
      if ($comp) {
	my $val_b = 0;
	if (exists($dhash->{$taxonomy})) {
	  $val_b = $dhash->{$taxonomy}->[scalar(@{$dhash->{$taxonomy}}) - 1]->[1];
	  delete($dhash->{$taxonomy});
	}
	push(@$expanded_data, [ @$taxa, [ $count, $val_b ] ]);
      } else {
	push(@$taxa, $count);
	push(@$expanded_data, $taxa);
      }
    }
    if ($comp) {
      foreach my $key (keys(%$dhash)) {
	push(@$expanded_data, $dhash->{$key});
      }
    }
  } elsif ($desc eq 'metabolic reconstruction') {
    $data = $self->data('mgdb')->get_subsystem_counts($dataset);
    foreach (@$data) {
      my ($h1, $h2, $subsystem, $taxonomy, $count) = @$_;
      $h1 = $self->data('mgdb')->key2taxa($h1) || 'Unclassified';
      $h2 = $self->data('mgdb')->key2taxa($h2) || $self->data('mgdb')->key2taxa($h1) || 'Unclassified';
      $subsystem = $self->data('mgdb')->key2taxa($subsystem) || '';
      if ($comp) {
	my $key = $h1.";".$h2.";".$subsystem;
	my $val_b = 0;
	if (exists($dhash->{$key})) {
	  $val_b = $dhash->{$key}->[scalar(@{$dhash->{$key}}) - 1]->[1];
	  delete($dhash->{$key});
	}
	push(@$expanded_data, [ 'Subsystem', $h1, $h2, $subsystem, [ $count, $val_b ] ]);
      } else {
	push(@$expanded_data, [ 'Subsystem', $h1, $h2, $subsystem, $count ]);
      }
    }
    if ($comp) {
      foreach my $key (keys(%$dhash)) {
	push(@$expanded_data, $dhash->{$key});
      }
    }
  } else {
    return "Invalid dataset";
  }

  if ($expanded_data && $expanded_data->[0]) {
    my $max_depth = scalar(@{$expanded_data->[0]}) - 1;
    
    if ($max_depth > 6) {
      $max_depth = 6;
    }
    my $depth = $cgi->param('depth') || 4;
    if ($depth > $max_depth) {
      $depth = $max_depth;
    }
    
    if ($comp) {
      $pt->coloring_method('difference');
    }
    $pt->data($expanded_data);
    $pt->show_leaf_weight(1);
    $pt->show_arcs(0);
    $pt->show_titles(0);
    $pt->enable_click(1);
    $pt->size($image_size);
    $pt->depth($depth);
    $pt->level_distance($level_distance);
    
    my $master = $self->app->data_handle('MGRAST');
    my $pubjobs = &get_public_metagenomes($master);
    @$pubjobs = sort { $a->{genome_name} cmp $b->{genome_name} } @$pubjobs;
    my $privjobs = [];
    if ($self->application->session->user()) {
      $privjobs = $master->Job->get_jobs_for_user($self->application->session->user(), 'view');
    }
    @$privjobs = sort { $a->{genome_name} cmp $b->{genome_name} } @$privjobs;
    
    my $fs_labels = ['none'];
    my $fs_values = ['0'];
    
    foreach my $j (@$privjobs) {
      next unless $j->{genome_id};
      push(@$fs_values, $j->{genome_id});
      push(@$fs_labels, "Private: ".$j->{genome_name});
    }
    foreach my $j (@$pubjobs) {
      push(@$fs_values, $j->{genome_id});
      push(@$fs_labels, $j->{genome_name});
    }
    
    my $filter_select = $self->application->component('mgfilterselect');
    $filter_select->labels( $fs_labels );
    $filter_select->values( $fs_values );
    $filter_select->size(8);
    $filter_select->width(250);
    if ($comp) {
      $filter_select->default($comp);
    }
    $filter_select->name('comparison_metagenome');
    
    my $image_control = $application->component('image_control');
    $image_control->add_blind({ title => 'image parameters', content => "<table><tr><td style='width: 180px;'>image size</td><td><input type='text' id='image_size' value='".$image_size."' size=4>px</td></tr><tr><td>level distance</td><td><input type='text' id='level_distance' value='".$level_distance."' size=3>px</td></tr><tr><td>depth</td><td><input type='text' name='depth' value='$depth' size=2>&nbsp;<i>(maximum depth for this data is $max_depth)</i></td></tr><tr><td>Comparison Metagenome</td><td>".$filter_select->output()."</td></tr></table>".qq~<input type='button' value='redraw' onclick='execute_ajax("load_tree","tree","mg_stats","Loading tree...",null,null,null,"comparison_metagenome="+document.getElementById("filter_select_~ . $filter_select->id . qq~").options[document.getElementById("filter_select_~ . $filter_select->id . qq~").selectedIndex].value+"&image_size="+document.getElementById("image_size").value+"&level_distance="+document.getElementById("level_distance").value);'>~ });
    $image_control->width(500);
    
    my $info = "";
    if ($comp) {
      $info = "Comparing ".$self->data('mgdb')->{job}->genome_name." (A) with ".$self->data('comp_mgdb')->{job}->genome_name." (B)<ul><li>hover over a node to view distribution statistics</li><li>click on a node to print distribution statistics of this node and all parent nodes to the page</li><li>coloring at the leaf nodes indicates relative abundance ranging from red (mostly metagenome A) over yellow (similar relative abundance in both metagenomes) to green (mostly metagenome B)</li></ul>";
    } else {
      $info = "Coloring at the leaf nodes indicates relative abundance ranging from dark blue (high abundance) to light blue (low abundance).";
    }
  
    my $help_text = $self->application->component('tree_help');
    $help_text->hover_width(400);
    $help_text->disable_wiki_link(1);
    $help_text->text($info);
    
    return "<table><tr><td>".$image_control->output() . "</td><td><p style='font-size: 11pt; font-weight: bold;'>" . $help_text->output() . "</p></td></tr></table><br>" . $pt->output();
  } else {
    return "- no data available -";
  }
}
