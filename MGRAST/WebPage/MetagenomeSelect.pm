package MGRAST::WebPage::MetagenomeSelect;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use WebComponent::WebGD;
use GD;
use Data::Dumper;

use MGRAST::MGRAST qw( :DEFAULT );
use MGRAST::MetagenomeAnalysis2;
use MGRAST::Metadata;

1;

=pod

=head1 NAME

MetagenomeSelect - an instance of WebPage which lets the user select a metagenome

=head1 DESCRIPTION

Display an metagenome select box

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title("Browse Metagenomes");
  $self->{icon} = "<img src='./Html/mgrast_globe.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  # register components
  $self->application->register_component('Ajax', 'ajax');
 # $self->application->register_component('DataFinder', "d");
  $self->application->register_component('Hover', 'help');
  $self->application->register_component('Table', 'all_metagenomes');
  $self->application->register_component('Table', 'user_complete');
  $self->application->register_component('Table', 'user_in_progess');
  $self->application->register_component('Table', 'user_shared');
  $self->application->register_component('Table', 'collection_table');
  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the MetagenomeSelect page.

=cut

sub output {
  my ($self) = @_;
  
  my $application = $self->application;
  my $dbmaster = $application->dbmaster;
  my $user = $application->session->user;
  my $cgi  = $application->cgi;
  
  # check for MGRAST
  my $html = "";
  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
    $html .= "<h2>The MG-RAST is currently offline. We apologize for the inconvenience. Please try again later.</h2>";
    return $html;
  }
  $self->{mgrast} = $mgrast;
  
  
#  my $data_description = [ 'job_id', 'jobname', 'metagenome_id', 'project', 'biome', 'altitude', 'depth', 'location', 'ph', 'country', 'temperature', 'sequencing method', 'PI' ];
  
  #my $data_table = $self->fetch_data();
  my $data_table = $mgrast->Job->fetch_browsepage_viewable($user);
  my $genome_id2job_id = {};
  my $genome_id2jobname = {};  

  my $data = {};
  my $biomes = {};
  my $pis = {};
  
  foreach my $row (@$data_table){
    $genome_id2job_id->{$row->{'metagenome_id'}} = $row->{'job_id'};
    $genome_id2jobname->{$row->{'metagenome_id'}} = $row->{'name'};
    if (exists $row->{'biome'} and $row->{'biome'} ne '' and $row->{'biome'} ne ' ' and $row->{'biome'} ne '0' and $row->{'biome'} ne ' - ' and $row->{'biome'} ne "unknown") {
	  my @tmp_biomes = split ', ', $row->{'biome'};
	  foreach my $b (@tmp_biomes){
		$biomes->{$b} = 1;
	  }      
    }
    if (exists $row->{'pi'}) {
      $pis->{$row->{'pi'}} = 1;
    }
    $data->{$row->{'job_id'}} = {};
    $data->{$row->{'job_id'}}->{jobname} = [ $row->{'metagenome_id'} ];
  }
  $self->{'num_biomes'} = scalar(keys(%$biomes));
  $self->{'num_pis'} = scalar(keys(%$pis));
  
  my $collection_prefs = $dbmaster->Preferences->get_objects( { application => $application->backend,
								user => $user,
								name => 'mgrast_collection' } );
  my $cdata_hash = {};
  foreach my $collection_pref (@$collection_prefs) {
    my ($name, $val) = split(/\|/, $collection_pref->{value});
    if (! exists($cdata_hash->{$name})) {
      $cdata_hash->{$name} = [ $val ];
    } else {
      push(@{$cdata_hash->{$name}}, $val);
    }
  }
  my $cdata = [];
  foreach my $k (keys(%$cdata_hash)) {
    foreach my $v (@{$cdata_hash->{$k}}) {
      push(@$cdata, [ $k, $v, $data->{$v}->{jobname}->[0], $genome_id2jobname->{$data->{$v}->{jobname}->[0]} ]);
    }
  }

  my $ctable = $application->component('collection_table');
  $ctable->{sequential_init} = 1;
  $ctable->columns( [ { name => 'collection', filter => 1, operator => 'combobox' }, { name => 'job id', sortable => 1, filter => 1, visible => 0 }, { name => 'metagenome id', filter => 1, sortable => 1, visible => 0 }, { name => 'job name', filter => 1, sortable => 1 }, { name => 'select<div style="margin-top:4px; margin-left: 2px;"><input type="checkbox" onclick="table_select_all_checkboxes(\''.$ctable->id.'\', \'4\', this.checked, 1)">&nbsp;all</div>', visible => 1, width => 36, input_type => 'checkbox' } ] );
  $ctable->data($cdata);
  $ctable->items_per_page(20);
  $ctable->show_top_browse(1);
  $ctable->show_bottom_browse(1);
  $ctable->show_select_items_per_page(1);
  $ctable->show_column_select(1);
  
#   my $d = $application->component('d');
#   $d->data($data);
#   $d->visible(1);
#   #$d->target_function('update_set');
#   $d->tag_order([ 'personal collection', 'project', 'PI', 'biome', 'altitude', 'depth', 'location', 'ph', 'country', 'temperature', 'sequencing method' ]);
#   $d->tag_expansion({ 'collection' => 0, 'project' => 0, 'PI' => 0, 'biome' => 0, 'altitude' => 0, 'depth' => 0, 'location' => 0, 'ph' => 0, 'country' => 0, 'temperature' => 0, 'sequencing method' => 0 });
  
  $html .= $self->application->component('ajax')->output();
  
  my $private_data = "";
  my $in_progress_table = "";
  if ($user) {
    $html .= "<input type='hidden' id='logged_in' value='1'>";
    
    my $count_shared = 0;
    my $count_completed = 0;
    my $count_computing = $mgrast->Job->fetch_browsepage_in_progress($user, 1);
	$count_computing = 0 if ref $count_computing;
#    print STDERR Dumper($count_computing);
    foreach my $row (@$data_table){
      unless ($row->{'public'}){
	if ( $row->{'shared'} ) {
	  $count_shared++;
	} else {
	  $count_completed++;
	}
      }
    }
    
    my $collections_mgs = "none";
    my $num_collections = 0;
    if (scalar(@$collection_prefs)) {
      $collections_mgs = "";
      my $col = {};
      foreach my $collection_pref (@$collection_prefs) {
	my ($name, $val) = split(/\|/, $collection_pref->{value});
# 	if (exists($col->{$name})) {
# 	  push(@{$col->{$name}}, $genome_id2job_id->{$val}.";;".$data->{$val}->{jobname}->[0]);
# 	} else {
	  $col->{$name} = 1;#[ $genome_id2job_id->{$val}.";;".$data->{$val}->{jobname}->[0] ];
#	}
      }
#       foreach my $key (sort(keys(%$col))) {
# 	$collections_mgs .= $key."---".join("||", @{$col->{$key}})."<br>";
#       }
      $num_collections = scalar(keys(%$col));
    }
    
    # projects
    my $projects_mgs = "none" ;
    my $data_ids = $user->has_right_to(undef, 'view', 'project') ;
    my $num_projects = scalar @$data_ids || 0 ;
    
    
    my $help = $application->component('help');
    $help->add_tooltip( 'available_help', 'Datasets that you have processed by the MG-RAST pipeline and are now available for use with online analysis tools.' );
    $help->add_tooltip( 'progress_help', 'Datasets that you have uploaded and are progressing through the MG-RAST pipeline.' );
    $help->add_tooltip( 'share_help', 'Datasets that have been been shared with you by other users.' );
    $help->add_tooltip( 'collections_help', 'A set of metagenomes that can be quickly accessed from tool pages. See FAQ/Support for more information.' );
    $help->add_tooltip( 'projects_help', 'A set of metagenomes grouped by a study/project. See FAQ/Support for more information.' );
    $private_data .= $help->output();
    
    $private_data .= "<div class='sidebar_headline'>Your Data Summary</div>";
    $private_data .= "<div class='sidebar_box'>";
    
    $private_data .= "<div class='sidebar_subitem'>Available for analysis";
    $private_data .= "<span id='available_help' onmouseover='hover(event, \"available_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_complete_count'>".$count_completed."</a></div>";
    #$private_data .= "<div id='completed_div' class='sidebar_hidden'>$completed_mgs</div></div>";
    
    $private_data .= "<div class='sidebar_subitem'>In Progress";
    $private_data .= "<span id='progress_help' onmouseover='hover(event, \"progress_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_in_progress_count'>".$count_computing."</a></div>";
    #$private_data .= "<div id='computing_div' class='sidebar_hidden'>$computing_mgs</div></div>";
    
    $private_data .= "<div class='sidebar_subitem'>Shared with you";
    $private_data .= "<span id='share_help' onmouseover='hover(event, \"share_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_shared_count'>".$count_shared."</a></div>";
    #$private_data .= "<div id='shared_div' class='sidebar_hidden'>$shared_mgs</div></div>";
    
    $private_data .= "<div class='sidebar_subitem'>Collections";
    $private_data .= "<span id='collections_help' onmouseover='hover(event, \"collections_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_collections_count'>".$num_collections."</a></div>";
    #$private_data .= "<div id='collections_div' class='sidebar_hidden'>$collections_mgs</div></div>";
    
    # projects
    #$private_data .= "<div class='sidebar_subitem'>Projects";
    #$private_data .= "<span id='projects_help' onmouseover='hover(event, \"projects_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    #$private_data .= "<a class='sidebar_link' id='user_projects_count'>".$num_projects."</a></div>";
    #$private_data .= "<div id='projects_div' class='sidebar_hidden'>$projects_mgs</div></div>";
    
    $private_data .= "<div class='sidebar_text' style='margin-top: 10px;'>Click on the blue links above to browse just your data. For more information visit the <a href='http://blog.metagenomics.anl.gov'>Support page</a>.</div>";
    $private_data .= "</div>";
    
  } else {
    $html .= "<input type='hidden' id='logged_in' value='0'>";
    $private_data .= "<div class='sidebar_headline'>Your Data Summary</div>";
    $private_data .= "<div class='sidebar_box'>";
    $private_data .= "<div class='sidebar_text'>Login to view your datasets.</div>";
    $private_data .= "</div>";
  }
  
  # get data for summary
  my $jobs = $mgrast->Job->get_objects( { public => 1, viewable => 1} );
  my $num_bps = 0;
  my $num_seqs = 0;
  foreach my $j (@$jobs) {
    $num_seqs += $j->stats->{sequence_count_raw} || 0;
    $num_bps += $j->stats->{bp_count_raw} || 0;
  } 
  $num_bps = int($num_bps / 1000000000)." Gbp";
  $num_seqs = int($num_seqs / 1000000)." million";
  my $num_mgs = scalar(@$jobs);
  my $num_projects = scalar(@{$mgrast->Project->get_objects( { public => 1 } )});
  my $num_biomes = $self->{'num_biomes'};
  my $num_pis = $self->{'num_pis'};
  
  my $pub_sidebar = "";
  $pub_sidebar .= "<div class='sidebar_headline'>Public Data Summary</div>";
  $pub_sidebar .= "<div class='sidebar_box'>";
  $pub_sidebar .= "<div class='sidebar_text' style='margin-bottom: 10px;'>MG-RAST has large number of datasets that users have provided for public use.</div>";
  $pub_sidebar .= "<div class='sidebar_subitem'># of Metagenomes<span class='sidebar_stat'>$num_mgs<span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'># of Projects<span class='sidebar_stat'>$num_projects<span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Base pairs<span class='sidebar_stat'>$num_bps<span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Sequences<span class='sidebar_stat'>$num_seqs<span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Biomes<span class='sidebar_stat'>$num_biomes<span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>PI's<span class='sidebar_stat'>$num_pis<span></div>";
  $pub_sidebar .= "<div class='sidebar_text' style='margin-top: 10px;'>To make your dataset(s) public, select one of your datasets and click the <i>Make Public</i> link.</div>";
  $pub_sidebar .= "</div>";
  
  # space for ajax status
  $html .= "<div id='ajax_return'></div>";
  
  $html .= "<table><tr><td>";
  $html .= "<div style='font: 12px sans-serif;margin-right:10px;'>$private_data<br>$pub_sidebar</div>";
  $html .= "</td><td>";
  $html .= "<div style='font: 12px sans-serif;margin: 0 0 0 10px;'>";
  if ($user) {
    $html .= "<h3 id='title_bar'>All Metagenomes</h3>";
  } else {
    $html .= "<h3 id='title_bar'>Public Metagenomes</h3>";
  }
  $html .= "<div id='title_bar_link' style='float: left; font-size: 10px; margin-bottom: 3px; margin-top: 3px; padding: 1px;'></div>";
  
  # all metagenomes
  my $all_metagenomes_table = $self->application->component('all_metagenomes');
  $all_metagenomes_table->{sequential_init} = 1;
  $all_metagenomes_table->items_per_page(25);
  $all_metagenomes_table->show_top_browse(1);
  $all_metagenomes_table->show_bottom_browse(1);
  $all_metagenomes_table->show_select_items_per_page(1); 
  $all_metagenomes_table->width(700);
  $all_metagenomes_table->show_column_select(1); 
  my $all_metagenomes_cols = [ { name => 'job #', filter => 1, visible => 0, sortable => 1, width => 52 },
			       { name => 'id', filter => 1, visible => 0, sortable => 1, width => 60 },
			       { name => 'project', filter => 1, sortable => 1 },
			       { name => 'name', filter => 1, visible => 1, sortable => 1 },
			       { name => 'biome', filter => 1, sortable => 1, visible => 0 },
			       { name => 'biome', filter => 1, operator => 'combobox', sortable => 1 },
			       { name => 'type', filter => 1, operator => 'combobox', sortable => 1 },
			       { name => 'altitude', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'depth', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'location', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'ph', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'country', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'temperature', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'sequencing&nbsp;method', filter => 1, operator => 'combobox', visible => 0},
			       { name => 'pi', filter => 1, operator => 'combobox', visible => 0} ];
  if ($user) {
    push @$all_metagenomes_cols, { name => '', filter => 1, operator => 'combobox', visible => 1, width => 40};
    push @$all_metagenomes_cols, { name => 'select<div style="margin-top:4px; margin-left: 2px;"><input type="checkbox" onclick="table_select_all_checkboxes(\''.$all_metagenomes_table->id.'\', \''.scalar(@$all_metagenomes_cols).'\', this.checked, 1)">&nbsp;all</div>', visible => 1, width => 36, input_type => 'checkbox', unaddable => 1 };
  }
  $all_metagenomes_table->columns($all_metagenomes_cols);
  my @all_metagenome_data = ();
  my $private_color = "#8FBC3F";
  my $shared_color = "#FF9933";
  # goofiness to sort on shared to get private, shared, public
  my %sort_order = ( 0 => 1, 1 => 2, '' => 3 );
  
  foreach my $row (@$data_table){
	$row->{'biome'} =~ s/envo://gi if $row->{'biome'};
    my $id_link = "<a href='?page=MetagenomeOverview&metagenome=".$row->{'metagenome_id'}."' target='_blank'>".$row->{'metagenome_id'}."</a>";
    my $name_link = "<a href='?page=MetagenomeOverview&metagenome=".$row->{'metagenome_id'}."' target='_blank'>".$row->{'name'}."</a>";
    my $project_link = ($row->{'project'}) ? "<a href='?page=MetagenomeProject&project=".$row->{'project_id'}."' target='_blank'>".$row->{'project'}."</a>" : "unknown";

    my $table_row = [ $row->{'job_id'}, $id_link, $project_link, $name_link, sanitize($row->{'biome'}), sanitize($row->{'biome'}), sanitize($row->{'sequence_type'}), $row->{'altitude'}, $row->{'depth'}, sanitize($row->{'location'}), $row->{'ph'}, sanitize($row->{'country'}), $row->{'temperature'}, sanitize($row->{'sequencing method'}), sanitize($row->{'pi'})];
    if ($user) {
      push @$table_row, ($row->{'public'}) ? { 'data'=> 'public' } : ($row->{'shared'}) ? { 'data'=> '<span style=\'color: white;\'>shared</span>', highlight=> $shared_color } : { 'data'=> '<span style=\'color: white;\'>private</span>', highlight=> $private_color};
      push @$table_row, "<div style='margin-top:2px; margin-left: 10px;'><input type='checkbox' name='table_selection' value='".$row->{'metagenome_id'}."'>";
    }
    push @all_metagenome_data, $table_row;
  }
  
  $all_metagenomes_table->data(\@all_metagenome_data);

  # grouping buttons
  $html .= "<div id='group_link_div'><a id='grouping_link' style='cursor: pointer;'>group by project</a><a id='ungrouping_link' style='cursor: pointer; display: none;'>clear grouping</a></div>";

  $html .= "<div class='clear' style='height:10px;'></div>";

  $html .= "<div id='all_metagenomes'>";
  #$html .= "<p>The table below contains all metagenomes you have access to. </p>"; 
  $html .= "<input type='hidden' id='all_metagenomes_table_id' value='".$all_metagenomes_table->id()."'>";
  $html .= "<div  style='font-weight:bold;'>";	
  $html .= "<div style='width: 685px; font-size: 14px;'>Current table counts";
  if ($user) {
    $html .= "<span id='metagenome_counts'><span style='float:right; font-size: 11px;'>public&nbsp;(<span id='table_counts_public'>0</span>)&nbsp;&nbsp;private&nbsp;(<span id='table_counts_private'>0</span>)&nbsp;&nbsp;shared&nbsp;(<span id='table_counts_shared'>0</span>)</span></span>";
  }
  $html .= "</div>";	
  $html .= "<div class='clear' style='height:2px;'></div>";
  $html .= "<div class='table_counts'>metagenomes<div id='table_counts_metagenomes'>0</div></div>";
  $html .= "<div class='table_counts'>projects<div id='table_counts_projects'>0</div></div>";
  $html .= "<div class='table_counts'>biomes<div id='table_counts_biomes'>0</div></div>";
  $html .= "<div class='table_counts'>altitudes<div id='table_counts_altitudes'>0</div></div>";
  $html .= "<div class='table_counts'>depths<div id='table_counts_depths'>0</div></div>";
  $html .= "<div class='table_counts'>locations<div id='table_counts_locations'>0</div></div>";
  $html .= "<div class='table_counts'>ph's<div id='table_counts_phs'>0</div></div>";
  $html .= "<div class='table_counts'>countries<div id='table_counts_countries'>0</div></div>";
  $html .= "<div class='table_counts'>temperatures<div id='table_counts_temperatures'>0</div></div>";
  $html .= "<div class='table_counts'>sequencing methods<div id='table_counts_sequencing_methods'>0</div></div>";
  $html .= "<div class='table_counts'>pi's<div id='table_counts_pi'>0</div></div>";
  $html .= "<div class='clear' style='height:15px;'></div>";
  $html .= "<div style='width: 685px; font-size: 11px;'><a id='clear_table' style='cursor:pointer;'>clear table filters</a>";
  if ($user){
    $html .= "<span style='float:right;'><a id='collection_selection' style='cursor:pointer;' onclick='add_to_collection(\"".$all_metagenomes_table->id."\");'>add selected to a collection<img style='background: none repeat scroll 0 0 #2F2F2F; height: 12px; padding: 2px; width: 12px; margin-left: 4px; margin-top:-4px;' src='./Html/mg-cart.png'></a></span>";
  }
  $html .= "</div>";
  $html .= "<div class='clear' style='height:0px;'></div>";
  $html .= "</div>";
  $html .= $all_metagenomes_table->output();
  push(@{$self->application->js_init_functions()}, "update_counts('" . $all_metagenomes_table->id . "');");
  $html .= "<img src='./Html/clear.gif' id='init_table_counts'>";
  $html .= "</div>";
  
  # all projects
  # $html .= "<div id='all_projects' style='display:none;'>all projects</div>";
  
  # user complete
  $html .= "<div id='user_complete' style='display:none;'>user complete</div>";
  
  # user shared
  $html .= "<div id='user_shared' style='display:none;'>user shared</div>";
  
  # user in progress
  $html .= "<script>function prog_table_init () { initialize_table(\"".$self->application->component('user_in_progess')->id."\"); }</script><div id='user_in_progress' style='display:none;'><button onclick='execute_ajax(\"get_in_progress_table\", \"user_in_progress_table\", null, null, null, prog_table_init);'>refresh</button><div id='user_in_progress_table'><img src='./Html/clear.gif' onload='execute_ajax(\"get_in_progress_table\", \"user_in_progress_table\", null, null, null, prog_table_init);'/></div></div>";
  
  # user projects
  $html .= "<div id='user_projects' style='display:none;'>user projects</div>";
  
  # user collections
  $html .= "<div id='user_collections' style='display:none;'><a onclick='remove_from_collection(\"".$ctable->id."\");' style='cursor: pointer;'>delete selected entries</a>".$ctable->output."</div>";
  
  $html .= "</div>";
  $html .= "<div class='clear' style='height:100px;'></div>";
  $html .= "</td></tr></table>";
  
  return $html;
}

sub sanitize {
  my ($input) = @_;
  return $input if ($input and $input ne '' and $input ne ' ' and $input ne '0' and $input ne ' - ' and $input ne "unknown");
  return 'unknown';
}

sub get_in_progress_table {
  my ($self) = @_;	
  my $user = $self->application->session->user;
  my $mgrast = $self->application->data_handle('MGRAST');
  my @stages = ('upload', 'preprocess', 'dereplication', 'screen', 'genecalling', 'cluster_aa90', 'loadAWE', 'loadDB_ALL', 'done');
  my %stage_info = ( 'upload'        => ['Upload', 3], 
					 'preprocess'    => ['Sequence Filtering', 4],
					 'dereplication' => ['Dereplication', 5],
					 'screen'        => ['Sequence Screening', 6],
					 'genecalling'   => ['Gene Calling', 7],
					 'cluster_aa90'  => ['Gene Clustering', 8],
					 'loadAWE'       => ['Calculating Sims', 9],
					 'loadDB_ALL'    => ['Loading Database', 10],
					 'done'          => ['Finalizing Data', 11] );
  my $html = "";
  my $data_table = $mgrast->Job->fetch_browsepage_in_progress($user);
  
  # populate in progress table
  my $in_progress = $self->application->component('user_in_progess');
  $in_progress->{sequential_init} = 1;
  $in_progress->items_per_page(25);
  $in_progress->show_bottom_browse(1);
  $in_progress->show_select_items_per_page(1); 
  $in_progress->width(700);
  $in_progress->show_column_select(1); 
  $in_progress->columns([ { name => 'job #', filter => 1, visible => 1, sortable => 1, width => 55 },
						  { name => 'id', filter => 1, visible => 1, sortable => 1, width => 60 },
						  { name => 'name', filter => 1, visible => 1, sortable => 1 },
						  { name => 'progress', width => 120 },
						  { name => 'status', filter => 1, sortable => 1 } ]);
  
  my $data = [];
  foreach my $row (sort {$b->[0] <=> $a->[0]} @$data_table){
	my @in_progress = ();
	my $last_stage = '';
	foreach my $s (@stages){
	  if ($s eq 'upload'){
		push @in_progress, $self->color_box_for_state('completed', $s);
		$last_stage = $s;
	  } else {
		push @in_progress, $self->color_box_for_state($row->[$stage_info{$s}->[1]], $s);
	  }
	  $last_stage = $s if $row->[$stage_info{$s}->[1]];
	}
	if ($last_stage eq 'loadAWE'){
	  $row->[$stage_info{$last_stage}->[1]] = 'running';
	  $in_progress[6] = $self->color_box_for_state('running', 'loadAWE');
	}
	push @$data, [$row->[0], $row->[2], $row->[1], "<div>".join("", @in_progress)."</div>", ($last_stage) ? $stage_info{$last_stage}->[0]." : ".(($row->[$stage_info{$last_stage}->[1]]) ? $row->[$stage_info{$last_stage}->[1]] : "completed") : "" ];
  }
  $in_progress->data($data);
  
  $html .= $in_progress->output();  
  return $html;	
}

sub color_box_for_state {
  my ($self, $state, $stage) = @_;
  my %state_to_color = ( 'running' => "#FFBE1E",
						 'completed' => "#3CA53C",
						 'unknown' => "#B9B9B9",
						 'error' => "red" );
  
  if ($state and exists $state_to_color{$state}){
    return "<div title='".$stage."' style='float:left; height: 14px; width: 12px; margin: 2 0 2 1; background-color:".$state_to_color{$state}.";'></div>";
  } else {
    return "<div title='".$stage."' style='float:left; height: 14px; width: 12px; margin: 2 0 2 1; background-color:".$state_to_color{'unknown'}.";'></div>";
  }
}

sub format_number {
  my ($val) = @_;
  
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  
  return $val;
}

sub require_css {
  return [ "$Global_Config::cgi_url/Html/MetagenomeSelect.css" ];
}

sub require_javascript {
  return [ "$Global_Config::cgi_url/Html/MetagenomeSelect.js" ];
}

sub processing_info {
  my ($self) = @_;
  
  my $id  = $self->application->cgi->param('metagenome');
  my $jobdbm = $self->app->data_handle('MGRAST');
  my $job = $jobdbm->Job->init({ metagenome_id => $id });

  my $content = "<div style='text-align: left;'><h3>Jobs Details #".$job->job_id."</h3>";

  # general info
  $content .= "<div class='metagenome_info' style='width: 600px; margin-bottom: 30px; float: none;'><ul style='margin: 0; padding: 0;'>";
  $content .= "<li class='first'><label style='text-align: left; width: 220px;'>Metagenome ID - Name</label><span style='width: 360px'>".$job->metagenome_id." - ".$job->name."</span></li>";
  $content .= "<li class='odd'><label style='text-align: left; width: 220px;'>Job</label><span style='width: 360px'>".$job->job_id."</span></li>";
  $content .= "<li class='even'><label style='text-align: left; width: 220px;'>User</label><span style='width: 360px'>".$job->owner->login."</span></li>";
  $content .= "<li class='odd'><label style='text-align: left; width: 220px;'>Date</label><span style='width: 360px'>".$job->created_on."</span></li>";

  my $seqs_num = $jobdbm->JobStatistics->get_objects({ job => $job, tag => 'sequence_count_raw'});
  if (scalar($seqs_num)) {
    $seqs_num = $seqs_num->[0]->{value} || 0;
  } else {
    $seqs_num = 0;
  }
  my $bp_num = $jobdbm->JobStatistics->get_objects({ job => $job, tag => 'bp_count_raw'});
  if (scalar($bp_num)) {
    $bp_num = $bp_num->[0]->{value} || 0;
  } else {
    $bp_num = 0;
  }

  $content .= "<li class='even'><label style='text-align: left; width: 220px;'>Number of uploaded sequences</label><span style='width: 360px'>".$seqs_num."</span></li>";
  $content .= "<li class='odd'><label style='text-align: left; width: 220px;'>Total uploaded sequence length</label><span style='width: 360px'>".$bp_num."</span></li>";
  $content .= "</ul></div>";

  # check for downloads
  my $downloads = $job->downloads();
  if (scalar(@$downloads)) {
    my @values = map { $_->[0] } @$downloads;
    my %labels = map { $_->[0] => $_->[1] || $_->[0] } @$downloads;
    $content .= $self->start_form('download', { page => 'DownloadFile', job => $job->job_id });
    $content .= '<p> &raquo; Available downloads for this job: ';
    $content .= $self->app->cgi->popup_menu( -name => 'file',
					     -values => \@values,
					     -labels => \%labels, );
    $content .= "<input type='submit' value=' Download '>";
    $content .= $self->end_form;
  }
  else {
    if ($job->viewable) {
      $content .= '<p> &raquo; No downloads available for this metagenome yet.</p>';
    }
  }

  $content .= "</div><br><br><br><br>";

  return $content;
}


sub genome_entry {
    my ($self, $job, $image_cache, $colors) = @_;
    
    my $image_source;
    my $ver = $job->{server_version} || "";
    my $stage_txt = "";
    my $sims_done = 0;
    my $stages    = [ [ 'Sequence Filtering', 'preprocess' ],
					  [ 'Dereplication',      'dereplication' ],
					  [ 'Sequence Screening', 'screen' ],
					  [ 'Gene Calling',       'genecalling' ],
					  [ 'Gene Clustering',    'cluster_aa90' ],
					  [ 'Calculating Sims',   'loadAWE' ],
					  [ 'Loading Database',   'loadDB_ALL' ],
					  [ 'Finalizing Data',    'done' ]
		];
    
    unless($job->{viewable}) {
      my $state = '';
      my $curr_status = $self->application->data_handle('MGRAST')->Job->get_stages_fast($job->{_id});
      my $num_stages  = scalar(@$stages);

      for (my $i = 0; $i < $num_stages; $i++) {
		  my ($desc, $stage) = @{ $stages->[$i] };
		  my $status    = exists($curr_status->{$stage}) ? $curr_status->{$stage} : "not_started";
		  my $stage_num = $i + 1;
		  
		  $state .= $stage . $status;
		  
		  if ($status eq 'error') {
			  # use first stage with error status
			  $stage_txt = "$desc: Error";
			  last;
		  }
		  elsif ($status ne 'not_started') {
			  # use last stage with not_started status
			  if (($stage eq 'loadAWE') && ($status eq 'completed')) {
				  $status = 'running';
			  }
			  if ($stage eq 'loadDB_ALL') {
				  $sims_done = 1;
			  }
			  my $txt = ($status eq 'running') ? "In Progress" : ucfirst($status);
			  $stage_txt = "$desc: $txt";
		  }
      }
      
      if ( not exists $image_cache->{$state} ) {
	    my $box_height = 14; 
	    my $box_width  = 12;
	    
	    if ( not exists $image_cache->{$num_stages} ) {
		# create a new image
		my $image = WebGD->new($num_stages * $box_width, $box_height);
		
		# allocate some colors
		$colors = $self->get_colors($image);
		
		# make the background transparent and interlaced
		$image->transparent($colors->{'white'});
		$image->interlaced('true');
		
		# cache the image object and colors
		$image_cache->{$num_stages}{image_obj} = $image;
		$image_cache->{$num_stages}{colors}    = $colors;
	    }
	    
	    # use the cached image object and colors
	    my $image  = $image_cache->{$num_stages}{image_obj};
	    my $colors = $image_cache->{$num_stages}{colors};
	    
	    for (my $i = 0; $i < $num_stages; $i++) {
	      my ($desc, $stage) = @{ $stages->[$i] };
	      my $status = exists($curr_status->{$stage}) ? $curr_status->{$stage} : "not_started";
	      if (($stage eq 'loadAWE') && ($status ne 'not_started') && (! $sims_done)) {
		$status = 'running';
	      }

	      if ( exists $colors->{$status} ) {
		$image->filledRectangle($i * $box_width, 0, 10 + ($i * $box_width), $box_height, $colors->{$status});
	      }
	      else {
		die "Found unknown status '$status' for stage '$stage' in job ".$job->{job_id}."\n";
	      }
	    }
	    
	    # cache the image code
	    $image_cache->{$state} = $image->image_src;
	}
	
	# use the cached image source
	$image_source = $image_cache->{$state};
    } 
    else {
      $stage_txt = "All stages: Completed";
      if ($ver eq "2") {
		  $image_source = "./Html/job_complete.png";
      } else {
		  $image_source = "./Html/old_job_complete.png";
      }
    }

    if (($ver ne '3') && (! $stage_txt)) {
		$stage_txt = "Recomputing";
    } elsif (($ver eq '3') && (! $stage_txt)) {
		$stage_txt = "Upload: Completed";
    }
    
    my $name_display = 'Unknown';
    if ($self->{users} && $job->{owner} && $self->{users}->{$job->{owner}}) {
		my $firstname = $self->{users}->{$job->{owner}}->{firstname};
		my $lastname  = $self->{users}->{$job->{owner}}->{lastname};
		if ( $firstname and $lastname ) {
			$name_display = "$lastname, $firstname";
		}
    }
    
    my $creation_date = "Unknown";
    if($job->{created_on} =~ /(\d+-\d+-\d+)\s/){
      $creation_date = $1;
    }
    
    my $size = $job->{file_size_raw} || 0;
    
    return [ $job->{job_id},
	     $name_display,
	     $job->{metagenome_id},
	     $job->{name},
	     $size,
	     $creation_date,
	     "<img src='$image_source' />",
	     $stage_txt,
	   ];
}

sub get_colors {
  my ($self, $image) = @_;
  return { 'white' => $image->colorResolve(255,255,255),
		   'black' => $image->colorResolve(0,0,0),
		   'not_started' => $image->colorResolve(185,185,185),
		   'queued' => $image->colorResolve(30,120,220),
		   'in_progress' => $image->colorResolve(255,190,30),
		   'running' => $image->colorResolve(255,190,30),
		   'load_in_progress' => $image->colorResolve(255,190,30),
		   'requires_intervention' => $image->colorResolve(255,30,30),
		   'error' => $image->colorResolve(175,45,45),
		   'complete' => $image->colorResolve(60,165,60),
		   'completed' => $image->colorResolve(60,165,60),
  };
}


sub change_collection {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $dbmaster = $application->dbmaster;
  my $mgrast = $application->data_handle('MGRAST');
  my $user = $application->session->user;

  my $return_msg = "";

  # check for mass deletion
  if ($cgi->param('remove_entries')) {
    my @vals = split /\|/, $cgi->param('ids');
    foreach my $val (@vals) {
      my ($set, $v) = split /\^/, $val;
      my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							    user => $user,
							    name => 'mgrast_collection',
							    value => $set."|".$v } );
      if (scalar(@$existing)) {
	$existing->[0]->delete;
      }
    }
    $return_msg = "The selected collection entries have been removed.";
  }


  # check for mass addition to a set
  if ($cgi->param('newcollection')) {
    my $set = $cgi->param('newcollection');
    my @vals = split /\|/, $cgi->param('ids');
    foreach my $val (@vals) {
      my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							    user => $user,
							    name => 'mgrast_collection',
							    value => $set."|".$val } );
      unless (scalar(@$existing)) {
	$dbmaster->Preferences->create( { application => $application->backend,
					  user => $user,
					  name => 'mgrast_collection',
					  value => $set."|".$val } );
      }
    }
    $return_msg = "The selected metagenomes have been added to collection $set";
  }

  # return updated collection info
  my $collection_prefs = $dbmaster->Preferences->get_objects( { application => $application->backend,
 								user => $user,
 								name => 'mgrast_collection' } );
  my $data_table = $mgrast->Job->fetch_browsepage_viewable($user);
  my $genome_id2job_id = {};
  my $genome_id2jobname = {};  

  my $data = {};
  foreach my $row (@$data_table){
    $genome_id2job_id->{$row->{'metagenome_id'}} = $row->{'job_id'};
    $genome_id2jobname->{$row->{'metagenome_id'}} = $row->{'name'};
    $data->{$row->{'job_id'}} = {};
    $data->{$row->{'job_id'}}->{jobname} = [ $row->{'metagenome_id'} ];
  }

  my $cdata_hash = {};
  foreach my $collection_pref (@$collection_prefs) {
    my ($name, $val) = split(/\|/, $collection_pref->{value});
    if (! exists($cdata_hash->{$name})) {
      $cdata_hash->{$name} = [ $val ];
    } else {
      push(@{$cdata_hash->{$name}}, $val);
    }
  }
  my $cdata = [];
  foreach my $k (keys(%$cdata_hash)) {
    foreach my $v (@{$cdata_hash->{$k}}) {
      push(@$cdata, [ $k, $v, $data->{$v}->{jobname}->[0], $genome_id2jobname->{$data->{$v}->{jobname}->[0]} ]);
    }
  }
  my $collections_data = join('|', map { join('^', @$_) } @$cdata);
  my $num_collections = scalar(keys(%$cdata_hash));

  return "$return_msg<div style='display:none;'><input type='hidden' id='new_collection_num' value='$num_collections'><input type='hidden' id='new_collection_data' value='$collections_data'><img src='./Html/clear.gif' onload='update_collection_data(\"".$application->component('collection_table')->id."\");'></div>";
}
