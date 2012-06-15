package MGRAST::WebPage::MetagenomeCollections;

use strict;
use warnings;

use base qw( WebPage );

use Conf;
use Data::Dumper;
use MGRAST::Metadata;

1;

=pod

=head1 NAME

MetagenomeCollections - an instance of WebPage which handles preferences for MetagenomeCollections

=head1 DESCRIPTION

Display preferences for MetagenomeCollections and allow manipulation thereof

=head1 METHODS

=over 4

=item * B<init> ()

Initialize the page

=cut

sub init {
  my $self = shift;
  
  $self->title('Manage Collections');
  $self->application->register_component('Ajax', 'metagenomesearch_ajax');
  $self->application->register_component('Table', 'selection_table');
  $self->{use_buffer} = 1;
  $self->{mgrast} = $self->application->data_handle('MGRAST');

  return $self;
}

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $dbmaster = $application->dbmaster;
  my $mgrast = $self->{mgrast};
  
  my $collection_prefs = $dbmaster->Preferences->get_objects( { application => $application->backend,
								user => $user,
								name => 'mgrast_collection' } );
  my $collections = {};
  foreach my $collection_pref (@$collection_prefs) {
    my ($name, $val) = split(/\|/, $collection_pref->{value});
    if (! exists($collections->{$name})) {
      $collections->{$name} = [];
    }
    push(@{$collections->{$name}}, $val);
  }
  my $new_collection_name = "Collection";
  my $cnum = 1;
  while (exists($collections->{$new_collection_name . $cnum})) {
    $cnum++;
  }
  $new_collection_name .= $cnum;
  my $collection_data = [];
  my $collection_select = "<select name='collection' id='mgs_collection_select' value='collection' onchange='collection_to_selection();'>";
  foreach my $name (sort(keys(%$collections))) {
    push(@$collection_data, $name."|".join("|", @{$collections->{$name}}));
  }
  $collection_select .= "</select>";
  my $collection_data_string = join("#", @$collection_data);

  if ($cgi->param('refresh')) {
    $self->{use_buffer} = 0;
  }

  if ($self->{use_buffer} && -f $Conf::temp."/mgs_temp_data") {
    if (open(FH, $Conf::temp."/mgs_temp_data")) {
      $self->{data} = <FH>;
      close FH;
    } else {
      $self->fetch_data();
    }
  } else {
    $self->fetch_data();
  }

  my $data_description = "job_id|jobname|metagenome_id|project|biome|feature|material|enviroment package|sequencing type|altitude|depth|location|ph|country|temperature|sequencing method|PI";

  my $table = $application->component('selection_table');
  $table->columns( [ { name => 'select', input_type => 'checkbox' },
		     { name => 'job id', visible => 0, filter => 1, sortable => 1 },
		     { name => 'job name', filter => 1, sortable => 1 },
		     { name => 'metagenome id', visible => 0, filter => 1, sortable => 1 },
		     { name => 'project', filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'biome', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'feature', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'material', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'enviroment package', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'sequencing type', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'altitude', visible => 0, filter => 1, sortable => 1 },
		     { name => 'depth', visible => 0, filter => 1, sortable => 1 },
		     { name => 'location', visible => 0, filter => 1, sortable => 1 },
		     { name => 'ph', visible => 0, filter => 1, sortable => 1 },
		     { name => 'country', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'temperature', visible => 0, filter => 1, sortable => 1 },
		     { name => 'sequencing method', visible => 0, filter => 1, operator => 'combobox', sortable => 1 },
		     { name => 'PI', visible => 0, filter => 1, sortable => 1 }] );

  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->show_select_items_per_page(1);
  $table->items_per_page(15);
  $table->show_column_select(1);
  my $data_table = [];
  foreach my $row (split(/##/, $self->{data})) {
    my @r = split(/\|\|/, $row);
    unshift(@r, '');
    $r[2] = $r[1]."|".$r[2];
    push(@$data_table, \@r);
  }
  @$data_table = sort { $a->[4] cmp $b->[4] || $a->[2] cmp $b->[2] } @$data_table;
  $table->data($data_table);

  my $html = $application->component('metagenomesearch_ajax')->output();

  $html .= "<h3>Manage Collections</h3>";
  $html .= "<p>MGRAST allows you to create collections of metagenomes. You can use these collections for comparative analyses. The also provide a method for quick access to your favorite datasets. For each of these, you will be able to select default parameters. They will be applied automatically when you perform an analysis on one of the datasets of the collection. You can create multiple collections.</p>";

  $html .= "<p><a style='cursor: pointer;' onclick='if(document.getElementById(\"coll_help\").style.display==\"none\"){this.innerHTML=\"&raquo; less info\";document.getElementById(\"coll_help\").style.display=\"\";}else{this.innerHTML=\"&raquo; more info\";document.getElementById(\"coll_help\").style.display=\"none\";};'>&raquo; more info</a></p><div id='coll_help' style='display: none;'>";

  $html .= "<p>If you already have a collection, you can select it from the dropdown to view its datasets. You can click on each dataset for details. You can select one or multiple datasets in the table on the right list and click <b><i>add to collection</i></b> to add them to the collection. Select one or more datasets from the collection and click <b><i>remove selected</i></b> to remove the selected datasets from the collection. If you click <b><i>save collection</i></b>, the datasets in the right list will be saved under the collection named by the text next to <b><i>current collection</i></b>. If a collection of that name already exists, it will be updated. If not, it will be created.</p></div>";

  $html .= "<div id='mgs_ajax_div'></div>";  
  $html .= "<input type='hidden' id='mgs_collection_data' value='$collection_data_string'>";
  $html .= "<input type='hidden' id='mgs_input_data' value='".$self->{data}."'>";
  $html .= "<input type='hidden' id='mgs_data_description' value='".$data_description."'>";
  
  $html .= "<table>";

  $html .= "<tr><td style='height: 1px;'><b>existing collections</b></td><td style='text-align: right;'>".$collection_select."</td><td></td><td rowspan=5>".$table->output()."</td></tr>";
  $html .= "<tr><td style='vertical-align: middle; height: 1px;'><b>current collection</b></td><td style='text-align: right;'><input type='text' style='width: 256px;' id='mgs_collection_name' value='$new_collection_name'></td></tr>";
  $html .= "<tr><td colspan=2 style='height: 1px;'><select style='width: 395px;' id='mgs_current_selection' multiple=multiple size=10 onchange='show_detail(this);'></select></td><td><table height=148><tr><td style='vertical-align: top;'><input type='button' value='remove selected' onclick='mgs_remove();'></td></tr><td style='vertical-align: bottom;'><input type='button' value='add to collection' onclick='add_from_table(\"".$table->id."\");'></td></tr></table></td></tr>";
  $html .= "<tr><td><input type='button' value='save collection' id='mgs_save_button' onclick='save_collection();'></td></tr><tr><td colspan=2><div id='mgs_detail'></div></td></tr></table>";
  
  $html .= "<img src='./Html/clear.gif' onload='initialize_data();'><br><br><br><br>";

  return $html;
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/MetagenomeCollections.js" ];
}

sub fetch_data {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $application->session->user;

  # get the data connections
  my $mgrast = $self->{mgrast};
  my $dbmaster = $application->dbmaster;

  # extract the initial data
  my $public_projects = $mgrast->Project->get_objects( { public => 1 } );
  my $jobs = [];
  foreach my $project (@$public_projects) {
    my $pjobs = $mgrast->ProjectJob->get_objects( { project => $project } );
    foreach my $pj (@$pjobs) {
      push(@$jobs, $pj->job);
      $jobs->[scalar(@$jobs) - 1]->{pname} = $project->{name};
      $jobs->[scalar(@$jobs) - 1]->{project} = $project;
    }
  }
  my $data  = [];
  my @mgids = map { $_->{metagenome_id} } @$jobs;
  my $jobmd = $mgrast->Job->jobs_mixs_metadata_fast(\@mgids);

  foreach my $job (@$jobmd) {
    my $row = [];
    foreach my $tag (('job_id','name','metagenome_id','project','biome','feature','material','env_package','sequence_type','altitude','depth','location','ph','country','temperature','sequencing method','pi')) {
      my $val = (exists($job->{$tag}) && ($job->{$tag} ne '')) ? $job->{$tag} : '- no data -';
      $val =~ s/'//g;
      push @$row, $val;
    }
    push @$data, $row;
  }
  $self->{data_table} = $data;

  # store the data in the html
  my $string_data = "";
  my $rows = [];
  foreach my $row (@$data) {
    push(@$rows, join('||', @$row));
  }
  $string_data = join('##', @$rows);

  $self->{data} = $string_data;

  if (open(FH, ">".$Conf::temp."/mgs_temp_data")) {
    print FH $string_data;
    close FH;
  }

  return 1;
}

sub update_collection {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $dbmaster = $application->dbmaster;
  
  my $container = $cgi->param('collection');
  my @value = $cgi->param('cv');

  my $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
							user => $user,
							name => 'mgrast_collection' } );

  my $ex_colls = {};
  foreach my $e (@$existing) {
    my ($name, $val) = split(/\|/, $e->{value});
    unless (exists($ex_colls->{$name})) {
      $ex_colls->{$name} = {};
    }
    $ex_colls->{$name}->{$val} = $e;
  }
  
  foreach my $v (@value) {
    if (exists($ex_colls->{$container}) && exists($ex_colls->{$container}->{$v})) {
      $ex_colls->{$container}->{$v} = 0;
    } else {
      $dbmaster->Preferences->create( { application => $application->backend,
					user => $user,
					name => 'mgrast_collection',
					value => $container."|".$v } );
    }
  }

  if (exists($ex_colls->{$container})) {
    foreach my $key (keys(%{$ex_colls->{$container}})) {
      if ($ex_colls->{$container}->{$key}) {
	$ex_colls->{$container}->{$key}->delete();
      }
    }
  }

  $existing = $dbmaster->Preferences->get_objects( { application => $application->backend,
						     user => $user,
						     name => 'mgrast_collection' } );
  my $collections = {};
  foreach my $collection_pref (@$existing) {
    my ($name, $val) = split(/\|/, $collection_pref->{value});
    if (! exists($collections->{$name})) {
      $collections->{$name} = [];
    }
    push(@{$collections->{$name}}, $val);
  }
  my $collection_data = [];
  foreach my $name (sort(keys(%$collections))) {
    push(@$collection_data, $name."|".join("|", @{$collections->{$name}}));
  }
  my $collection_data_string = join("##", @$collection_data);

  return "<div style='border: 1px solid black; margin-bottom: 20px;'><div style='cursor: pointer; border: 1px solid black; color: white; background-color: #BB2222; font-size: 13px; font-weight: bold; height: 13px; width: 11px; padding-bottom: 2px; padding-left: 4px; margin-top: -1px; margin-left: -1px;' onclick='document.getElementById(\"mgs_ajax_div\").innerHTML=\"\";'><sup>x</sup></div><b style='position: relative; top: -16px; left: 20px;'>Info</b><span style='position: relative; left: -15px;'>collection $container has been updated</span><input type='hidden' id='mgs_collection_data_new' value='$collection_data_string'></div>";
}


sub required_rights {
  my ($self) = @_;

  my $user = '-';
  if ($self->application->session->user) {
    $user = $self->application->session->user->_id;
  }
  
  return [ [ 'edit', 'user', $user ] ];
}
