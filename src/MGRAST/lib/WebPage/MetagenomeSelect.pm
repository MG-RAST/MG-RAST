package MGRAST::WebPage::MetagenomeSelect;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use WebComponent::WebGD;
use GD;
use Data::Dumper;
use MGRAST::Analysis;
use MGRAST::Metadata;

1;

=pod
=cut

sub init {
  my ($self) = @_;

  $self->title("Browse Metagenomes");
  $self->{icon} = "<img src='./Html/mgrast_globe.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  # register components
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('Hover', 'help');
  $self->application->register_component('Table', 'all_metagenomes');
  $self->application->register_component('Table', 'user_complete');
  $self->application->register_component('Table', 'user_in_progess');
  $self->application->register_component('Table', 'user_shared');
  $self->application->register_component('Table', 'collection_table');
  $self->application->register_component('Table', 'collection_table_detail');
  $self->application->register_component('Table', 'private_projects_table');
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
  
  my $projects = $mgrast->Project->get_objects();
  my $project_hash = {};
  %$project_hash = map { $_->{name} => $_ } @$projects;
  
  my $data_table = $mgrast->Job->fetch_browsepage_viewable($user);
  my $genome_id2job_id = {};
  my $genome_id2jobname = {};
  my $genome_id2project = {};
  my $genome_id2env = {};

  my $data = {};
  my $envs = {};
  my $pis = {};
  
  foreach my $row (@$data_table) {
    $genome_id2job_id->{$row->{'metagenome_id'}} = $row->{'job_id'};
    $genome_id2jobname->{$row->{'metagenome_id'}} = $row->{'name'};
    $genome_id2project->{$row->{'metagenome_id'}} = $row->{'project'};
    if (exists($row->{'env_package'}) && $row->{'env_package'}) {
      $genome_id2env->{$row->{'metagenome_id'}} = $row->{'env_package'};
      $envs->{$row->{'env_package'}} = 1;
    }
    if (exists $row->{'pi'}) {
      $pis->{$row->{'pi'}} = 1;
    }
    $data->{$row->{'job_id'}} = {};
    $data->{$row->{'job_id'}}->{jobname} = [ $row->{'metagenome_id'} ];
  }
  $self->{'num_envs'} = scalar(keys(%$envs));
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

  my $cdtable = $application->component('collection_table_detail');
  $cdtable->columns( [ 'metagenome', 'project', 'type', 'enviroment', 'remove' ] );
  $cdtable->items_per_page(25);
  $cdtable->show_top_browse(1);
  $cdtable->show_bottom_browse(1);
  $cdtable->data([['-','-','-','-','-']]);

  my $cdata = [];
  my $cddata_string = "";
  my $row_ind = 0;
  foreach my $k (keys(%$cdata_hash)) {
    my $cddata = [];
    my $ind = 0;
    foreach my $v (@{$cdata_hash->{$k}}) {
      next unless ($v && $data->{$v}{jobname} && $data->{$v}{jobname}[0]);
      my $name_link = "<a href='?page=MetagenomeOverview&metagenome=".$data->{$v}{jobname}[0]."' target='_blank'>".$genome_id2jobname->{$data->{$v}{jobname}[0]}." (".$data->{$v}{jobname}[0].")</a>";
      my $pid = $genome_id2project->{$data->{$v}{jobname}[0]} ? $project_hash->{$genome_id2project->{$data->{$v}{jobname}[0]}}->{id} : "";
      my $project_link = $genome_id2project->{$data->{$v}{jobname}[0]} ? "<a href='?page=MetagenomeProject&project=$pid' target=_blank>".$genome_id2project->{$data->{$v}{jobname}[0]}."</a>" : "-";
      my $project_type = $genome_id2project->{$data->{$v}{jobname}[0]} ? $project_hash->{$genome_id2project->{$data->{$v}{jobname}[0]}}->{type} : "-";
      my $cds = $name_link."~~".$project_link."~~".$project_type."~~".($genome_id2env->{$data->{$v}{jobname}[0]} || "-")."~~<input type='button' value='remove' onclick='remove_single(&quot;$k^$v&quot;);'>~~".$ind;
      $cds =~ s/"/\@1/g;
      $cds =~ s/'/\@2/g;
      push(@$cddata, $cds);
      $ind++;
    }
    $cddata_string .= "<input type='hidden' id='collection_detail_data_$row_ind' value='".join("^^", @$cddata)."'>";
    push(@$cdata, [ $k, scalar(keys(@{$cdata_hash->{$k}})), 0, "<input type='button' value='delete' onclick='remove_single(\"$k\");'>", "<input type='button' value='share' onclick='share_collection($row_ind,\"$k\");'>", "<input type='button' value='edit' onclick='show_collection_detail($row_ind, ".$cdtable->id.", \"$k\");'>" ]);
    $row_ind++;
  }

  my $ctable = $application->component('collection_table');
  $ctable->{sequential_init} = 1;
  $ctable->columns( [ { name => 'collection', sortable => 1 },
		      { name => '# jobs', sortable => 1 },
		      { name => 'select', visible => 1, width => 36, input_type => 'checkbox', unaddable => 1 },
		      { name => "" },
		      { name => "" },
		      { name => "" } ] );
  $ctable->data($cdata);

  $html .= $self->application->component('ajax')->output();
  
  my $private_data = "";
  my $in_progress_table = "";
  my $private_projects = [];
  if ($user) {
    $html .= "<input type='hidden' id='logged_in' value='1'>";
    
    my $count_shared = 0;
    my $count_completed = 0;
    my $count_computing = $mgrast->Job->fetch_browsepage_in_progress($user, 1);
    $count_computing = 0 if ref $count_computing;
    
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
	$col->{$name} = 1;
      }
      $num_collections = scalar(keys(%$col));
    }
    
    # projects
    my $projects_mgs  = "none";
    $private_projects = $mgrast->Project->get_private_projects($user);
    my $num_projects  = scalar(@$private_projects);
    
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
    
    $private_data .= "<div class='sidebar_subitem'>In Progress";
    $private_data .= "<span id='progress_help' onmouseover='hover(event, \"progress_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_in_progress_count'>".$count_computing."</a></div>";
    
    $private_data .= "<div class='sidebar_subitem'>Shared with you";
    $private_data .= "<span id='share_help' onmouseover='hover(event, \"share_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_shared_count'>".$count_shared."</a></div>";
    
    $private_data .= "<div class='sidebar_subitem'>Collections";
    $private_data .= "<span id='collections_help' onmouseover='hover(event, \"collections_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_collections_count'>".$num_collections."</a></div>";
    
    # projects
    $private_data .= "<div class='sidebar_subitem'>Projects";
    $private_data .= "<span id='projects_help' onmouseover='hover(event, \"projects_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
    $private_data .= "<a class='sidebar_link' id='user_projects_count'>".$num_projects."</a></div>";
    
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
  my $num_envs = $self->{'num_envs'};
  my $num_pis = $self->{'num_pis'};
  
  my $pub_sidebar = "";
  $pub_sidebar .= "<div class='sidebar_headline'>Public Data Summary</div>";
  $pub_sidebar .= "<div class='sidebar_box'>";
  $pub_sidebar .= "<div class='sidebar_text' style='margin-bottom: 10px;'>MG-RAST has large number of datasets that users have provided for public use.</div>";
  $pub_sidebar .= "<div class='sidebar_subitem'># of Metagenomes<span class='sidebar_stat'><a style='cursor:pointer;' id='user_public_count'>$num_mgs</a></span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'># of Projects<span class='sidebar_stat'><a target='_blank' href='?page=MetagenomeProject'>$num_projects</a></span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Base pairs<span class='sidebar_stat'>$num_bps</span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Sequences<span class='sidebar_stat'>$num_seqs</span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>Enviroments<span class='sidebar_stat'>$num_envs</span></div>";
  $pub_sidebar .= "<div class='sidebar_subitem'>PI's<span class='sidebar_stat'>$num_pis</span></div>";
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
  my $all_metagenomes_cols = [ { name => 'job&nbsp;&#35;', filter => 1, visible => 0, sortable => 1, width => 52 },
			       { name => 'id', filter => 1, visible => 0, sortable => 1, width => 60 },
			       { name => 'project', filter => 1, sortable => 1 },
			       { name => 'name', filter => 1, sortable => 1 },
			       { name => 'bps', filter => 1, sortable => 1, operators => ['less','more'] },
			       { name => 'sequences', filter => 1, sortable => 1, operators => ['less','more'] },
			       { name => 'biome', filter => 1, operator => 'combobox', sortable => 0 },
			       { name => 'feature', filter => 1, operator => 'combobox', sortable => 0 },
			       { name => 'material', filter => 1, operator => 'combobox', sortable => 0 },
			       { name => 'enviroment&nbsp;package', filter => 1, operator => 'combobox', sortable => 1, visible => 0 },
			       { name => 'disease&nbsp;status', filter => 1, operator => 'combobox', sortable => 0, visible => 0 },
			       { name => 'sequencing&nbsp;type', filter => 1, operator => 'combobox', sortable => 1 },
			       { name => 'altitude', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'depth', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'location', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'ph', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'country', filter => 1, visible => 0 },
			       { name => 'temperature', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'sequencing&nbsp;method', filter => 1, operator => 'combobox', visible => 0 },
			       { name => 'pi', filter => 1, visible => 0 },
			       { name => 'avg&nbsp;seq&nbsp;length', filter => 1, sortable => 1, operators => ['less','more'], visible => 0 },
			       { name => 'drisee', filter => 1, sortable => 1, operators => ['less','more'], visible => 0 },
			       { name => '&alpha;-diversity', filter => 1, sortable => 1, operators => ['less','more'], visible => 0 }
			     ];
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
  
  foreach my $row (@$data_table) {
    my $id_link = "<a href='?page=MetagenomeOverview&metagenome=".$row->{'metagenome_id'}."' target='_blank'>".$row->{'metagenome_id'}."</a>";
    my $name_link = "<a href='?page=MetagenomeOverview&metagenome=".$row->{'metagenome_id'}."' target='_blank'>".($row->{'name'} ? $row->{'name'} : "-")."</a>";
    my $project_link = ($row->{'project'}) ? "<a href='?page=MetagenomeProject&project=".$row->{'project_id'}."' target='_blank'>".$row->{'project'}."</a>" : "unknown";

    my $table_row = [ $row->{'job_id'},
		      $id_link,
		      $project_link,
		      $name_link,
		      $row->{'bp_count'},
		      $row->{'sequence_count'},
		      sanitize($row->{'biome'}),
		      sanitize($row->{'feature'}),
		      sanitize($row->{'material'}),
		      sanitize($row->{'env_package'}),
		      $row->{'health_disease_stat'},
		      $row->{'sequence_type'} || 'Unknown',
		      $row->{'altitude'},
		      $row->{'depth'},
		      sanitize($row->{'location'}),
		      $row->{'ph'},
		      sanitize($row->{'country'}),
		      $row->{'temperature'},
		      sanitize($row->{'sequencing method'}),
		      sanitize($row->{'pi'}),
		      $row->{'average_length'} ? sprintf("%.3f",$row->{'average_length'}) : '',
		      $row->{'drisee'} ? sprintf("%.3f",$row->{'drisee'}) : '',
		      $row->{'alpha_diversity'} ? sprintf("%.3f",$row->{'alpha_diversity'}) : ''
		    ];
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
  $html .= "<div class='table_counts'>features<div id='table_counts_features'>0</div></div>";
  $html .= "<div class='table_counts'>materials<div id='table_counts_materials'>0</div></div>";
  $html .= "<div class='table_counts'>altitudes<div id='table_counts_altitudes'>0</div></div>";
  $html .= "<div class='table_counts'>depths<div id='table_counts_depths'>0</div></div>";
  $html .= "<div class='table_counts'>locations<div id='table_counts_locations'>0</div></div>";
  $html .= "<div class='table_counts'>ph's<div id='table_counts_phs'>0</div></div>";
  $html .= "<div class='table_counts'>countries<div id='table_counts_countries'>0</div></div>";
  $html .= "<div class='table_counts'>temperatures<div id='table_counts_temperatures'>0</div></div>";
  $html .= "<div class='table_counts'>pi's<div id='table_counts_pis'>0</div></div>";
  $html .= "<div class='clear' style='height:15px;'></div>";
  $html .= "<div style='width: 685px; font-size: 11px;'><a id='clear_table' style='cursor:pointer;'>clear table filters</a>";
  if ($user) {
    $html .= "<span style='float:right;'><a id='collection_selection' style='cursor:pointer;' onclick='add_to_collection(\"".$all_metagenomes_table->id."\");'>add selected to a collection<img style='background: none repeat scroll 0 0 #2F2F2F; height: 12px; padding: 2px; width: 12px; margin-left: 4px; margin-top:-4px;' src='./Html/mg-cart.png'></a></span>";
  }
  $html .= "</div>";
  $html .= "<div class='clear' style='height:0px;'></div>";
  $html .= "</div>";
  $html .= $all_metagenomes_table->output();
  $html .= "<div class='clear' style='height:5px;'></div>";
  $html .= "<a id='export_table' style='cursor:pointer;font-size:11px;font-weight:bold;'>export table data</a>";
  push(@{$self->application->js_init_functions()}, "update_counts('" . $all_metagenomes_table->id . "');");
  $html .= "<img src='./Html/clear.gif' id='init_table_counts'>";
  $html .= "</div>";
  
  # user complete
  $html .= "<div id='user_complete' style='display:none;'>user complete</div>";
  
  # user shared
  $html .= "<div id='user_shared' style='display:none;'>user shared</div>";
  
  # user in progress
  $html .= "<script>function prog_table_init () { initialize_table(\"".$self->application->component('user_in_progess')->id."\"); }</script><div id='user_in_progress' style='display:none;'><button onclick='execute_ajax(\"get_in_progress_table\", \"user_in_progress_table\", null, null, null, prog_table_init);'>refresh</button><div id='user_in_progress_table'><img src='./Html/clear.gif' onload='execute_ajax(\"get_in_progress_table\", \"user_in_progress_table\", null, null, null, prog_table_init);'/></div></div>";
  
  # user projects
  $html .= "<div id='user_projects' style='display:none;'>";
  my $pp_table = $application->component('private_projects_table');
  $pp_table->columns( [ { name => 'id' }, { name => 'name' }, { name => 'type' } ] );
  $pp_table->data([ map { [ $_->{id}, "<a href='?page=MetagenomeProject&project=".$_->{id}."' target=_blank>".($_->{name} ? $_->{name} : "-")."</a>", $_->{type} ] } grep { $_->{id} } @$private_projects ]);
  $pp_table->items_per_page(20);
  $pp_table->show_select_items_per_page(1);
  $pp_table->show_top_browse(1);
  $pp_table->show_bottom_browse(1);
  $html .= $pp_table->output()."<br>";
  $html .= "<a onclick='pname=prompt(\"Enter new project name\",\"\");if(pname.length){window.top.location=\"?page=MetagenomeProject&action=create&pname=\"+pname;}' style='cursor:pointer;font-size:11px;font-weight:bold;'>create new project</a>";
  $html .= "</div>";
  
  # user collections
  $html .= "<div style='display: none;' id='collection_target'>".$cddata_string."</div>";
  $html .= "<div id='user_collections' style='display:none;'>";
  $html .= "<p style='width: 600px; font-variant: normal;'>To create a new collection, click the 'back to all metagenomes' link and check the checkboxes of the metagenomes you wish to add to the collection in the 'All Metagenomes'-table. Then click the 'add selected to a collection' link on the top left of that table. Upon entering a name for your new collection, it will be created.<br><br>A collection is simply a persistent, named list of metagenomes, which is private to you. Collections can be selected anywhere you need to specify a list of metagenomes. They provide a shortcut for you to quickly find your favorite selection.</p>";
  $html .='<div style="margin-top:4px; margin-left: 2px;"><input type="checkbox" onclick="table_select_all_checkboxes(\''.$ctable->id.'\', \'2\', this.checked, 1)">&nbsp; select all&nbsp;&nbsp;&nbsp;&nbsp;<a onclick="remove_from_collection(\''.$ctable->id.'\');" style="cursor: pointer;font-size:11px;font-weight:bold;">delete selected entries</a></div>'.$ctable->output."<div id='user_collection_details' style='display: none;'><br><br><h3 id='collection_detail_name'><span id='user_collection_detail_name'></span>&nbsp;&nbsp;<input type='button' value='change' onclick='if(document.getElementById(\"newname_div\").style.display==\"none\"){document.getElementById(\"newname_div\").style.display=\"\";}else{document.getElementById(\"newname_div\").style.display=\"none\";};'></h3><div id='newname_div' style='display: none;'>&nbsp;&nbsp;&nbsp;new name: <input type='text' id='newname'><input type='button' value='rename' onclick='rename_collection();'></div>".$cdtable->output()."</div></div>";
  
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
			  { name => 'progress', width => 135 },
			  { name => 'status', filter => 1, sortable => 1 } ]);

  my $data = [];
  foreach my $row (sort {$b->{job_id} <=> $a->{job_id}} @$data_table){
    my @in_progress = map { $self->color_box_for_state($_->{status}, $_->{stage}) } @{$row->{states}};
    push @$data, [ $row->{job_id}, $row->{metagenome_id}, $row->{metagenome_name}, "<div>".join("", @in_progress)."</div>", $row->{status} ];
  }
  $in_progress->data($data);
  
  $html .= $in_progress->output();  
  return $html;	
}

sub color_box_for_state {
  my ($self, $state, $stage) = @_;
  my %state_to_color = ( 'completed' => "green",
			 'in-progress' => "blue",
			 'queued' => "orange",
			 'pending' => "gray",
			 'error' => "red",
			 'init' => 'gray' );
  
  if ($state and exists $state_to_color{$state}){
    return "<div title='".$stage."' style='float:left; height: 14px; width: 12px; margin: 2px 0px 2px 1px; background-color:".$state_to_color{$state}.";'></div>";
  } else {
    return "<div title='".$stage."' style='float:left; height: 14px; width: 12px; margin: 2px 0px 2px 1px; background-color:gray;'></div>";
  }
}

sub format_number {
  my ($val) = @_;
  
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  
  return $val;
}

sub require_css {
  return [ "$Conf::cgi_url/Html/MetagenomeSelect.css" ];
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/MetagenomeSelect.js" ];
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
  my $cdtable = $application->component('collection_table_detail');

  my $return_msg = "";

  # check for mass deletion
  if ($cgi->param('remove_entries')) {
    my @vals = split /\|/, $cgi->param('ids');
    foreach my $val (@vals) {
      my ($set, $v) = split /\^/, $val;
      if (! defined($v)) {
	my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							      user => $user,
							      name => 'mgrast_collection' } );
	foreach my $e (@$existing) {
	  if ($e->{value} =~ /^$set\|/) {
	    $e->delete;
	  }
	}

      } else {
	my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							      user => $user,
							      name => 'mgrast_collection',
							      value => $set."|".$v } );
	if (scalar(@$existing)) {
	  $existing->[0]->delete;
	}
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

  # check for renaming
  if ($cgi->param('newname') && $cgi->param('oldname')) {
    my $coll_to_change = $dbmaster->Preferences->get_objects( { application => $application->backend,
								user => $user,
								name => 'mgrast_collection',
								value => [ $cgi->param('oldname').'|%', 'like' ] } );
    foreach my $ctc (@$coll_to_change) {
      my ($c, $v) = split(/\|/, $ctc->{value});
      $ctc->value($cgi->param('newname')."|".$v);
    }
  }

  # return updated collection info
  my $collection_prefs = $dbmaster->Preferences->get_objects( { application => $application->backend,
 								user => $user,
 								name => 'mgrast_collection' } );
  
  my $projects = $mgrast->Project->get_objects();
  my $project_hash = {};
  %$project_hash = map { $_->{name} => $_ } @$projects;

  my $data_table = $mgrast->Job->fetch_browsepage_viewable($user);
  my $genome_id2job_id = {};
  my $genome_id2jobname = {};  
  my $genome_id2project = {};
  my $genome_id2env = {};

  my $data = {};
  my $envs = {};
  my $pis = {};
  
  foreach my $row (@$data_table){
    $genome_id2job_id->{$row->{'metagenome_id'}} = $row->{'job_id'};
    $genome_id2jobname->{$row->{'metagenome_id'}} = $row->{'name'};
    $genome_id2project->{$row->{'metagenome_id'}} = $row->{'project'};
    if (exists($row->{'env_package'}) and ($row->{'env_package'} =~ /\S/)) {
      $genome_id2env->{$row->{'metagenome_id'}} = $row->{'env_package'};
      $envs->{$row->{'env_package'}} = 1;
    }
    if (exists $row->{'pi'}) {
      $pis->{$row->{'pi'}} = 1;
    }
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
  my $cddata_string = "";
  my $row_ind = 0;
  foreach my $k (keys(%$cdata_hash)) {
    my $cddata = [];
    my $ind = 0;
    foreach my $v (@{$cdata_hash->{$k}}) {
      my $name_link = "<a href='?page=MetagenomeOverview&metagenome=".$data->{$v}{jobname}[0]."' target='_blank'>".$genome_id2jobname->{$data->{$v}{jobname}[0]}." (".$data->{$v}{jobname}[0].")</a>";
      my $pid = $genome_id2project->{$data->{$v}{jobname}[0]} ? $project_hash->{$genome_id2project->{$data->{$v}{jobname}[0]}}->{id} : "";
      my $project_link = $genome_id2project->{$data->{$v}{jobname}[0]} ? "<a href='?page=MetagenomeProject&project=$pid' target=_blank>".$genome_id2project->{$data->{$v}{jobname}[0]}."</a>" : "-";
      my $project_type = $genome_id2project->{$data->{$v}{jobname}[0]} ? $project_hash->{$genome_id2project->{$data->{$v}{jobname}[0]}}->{type} : "-";
      my $cds = $name_link."~~".$project_link."~~".$project_type."~~".($genome_id2env->{$data->{$v}{jobname}[0]} || "-")."~~<input type='checkbox'>~~".$ind;
      $cds =~ s/"/\@1/g;
      $cds =~ s/'/\@2/g;
      push(@$cddata, $cds);
      $ind++;
    }
    $cddata_string .= "<input type='hidden' id='collection_detail_data_$row_ind' value='".join("^^", @$cddata)."'>";
    push(@$cdata, [ $k, scalar(keys(@{$cdata_hash->{$k}})), 0, '<input type="button" value="delete" onclick="remove_single(@1'.$k.'@1);>', '<input type="button" value="share" onclick="share_collection('.$row_ind.', @1'.$k.'@1);">', '<input type="button" value="edit" onclick="show_collection_detail('.$row_ind.', '.$cdtable->id.', @1'.$k.'@1);">' ]);
    $row_ind++;
  }
  my $collections_data = join('|', map { join('^', @$_) } @$cdata);
  my $num_collections = scalar(keys(%$cdata_hash));

  return "<input type='hidden' id='return_message' value='$return_msg'><input type='hidden' id='new_collection_num' value='$num_collections'><input type='hidden' id='new_collection_data' value='$collections_data'>$cddata_string<img src='./Html/clear.gif' onload='update_collection_data(\"".$application->component('collection_table')->id."\");'>";
}

sub commafy {
  my ($val) = @_;
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}
