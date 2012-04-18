package MGRAST::WebPage::MetagenomeProject;

use base qw( WebPage );

use strict;
use warnings;
use Data::Dumper;
use IO::Handle;

use FIG_Config;
use WebConfig;

use MGRAST::Metadata;
use MGRAST::MetagenomeAnalysis2;
 
1;

=pod

=head1 NAME

MetagenomeProject - an instance of WebPage to create, update and view Metagenome Projects

=head1 DESCRIPTION

Project page about several metagenomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Project Overview');

  # register components
  $self->application->register_component('Ajax', 'project_ajax');
  $self->application->register_component('Table', 'project_table');
  $self->application->register_component('Table', 'jobs_table');
  $self->application->register_component('FilterSelect', 'job_fs');
  $self->application->register_component('Hover', 'download_info');
  $self->application->register_component('ListSelect', 'job_select');
  $self->application->register_component('ListSelect', 'shared_job_select');
  $self->application->register_component('ListSelect', 'public_job_select');

  # register actions
  $self->application->register_action($self, 'create_project', 'create');
  $self->application->register_action($self, 'upload_file', 'upload_file');
  $self->application->register_action($self, 'add_job_to_project', 'add_job_to_project');
  $self->application->register_action($self, 'share_project', 'share_project');
  $self->application->register_action($self, 'revoke_project', 'revoke_project');
  $self->application->register_action($self, 'delete_project', 'delete_project');
  $self->application->register_action($self, 'change_shared_metagenomes', 'change_shared_metagenomes');

  # init the metadata database
  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $id = $cgi->param('project') || "";
  $self->{project_id} = $id;

  my $html = "";
  my $user = $application->session->user;

  if ($cgi->param('update') and $user) {
    $self->update_metadata();
  }

  if ($id) {
    $html .= $application->component('project_ajax')->output();
    
    my $jobdbm  = $application->data_handle('MGRAST');
    my $metadbm = MGRAST::Metadata->new->_handle();
    
    if ($id eq "no_project"){
      return $self->no_project_job_list($jobdbm, $user);
    }

    my $project = $jobdbm->Project->init({ id => $self->{project_id} });
    unless($project and ref $project){
      $application->add_message('warning', "No project for ID:" . ($self->{project_id} || 'missing ID')  );
      return "";
    }
    
    unless ($project->public || ($user and $user->has_right(undef, 'view', 'project', $project->id)) ) {
      $application->add_message('warning', "This is not a public project. You are lacking the rights to view this project.");
      return "<p>You are either not logged in or you have no right to view this project.</p>";
    }
    
    my $all_meta  = $metadbm->ProjectMD->get_objects( { project => $project } );
    my $meta_hash = {};
    %$meta_hash   = map { $_->{tag} => $_->{value} } @$all_meta;
    $self->{meta_info} = $meta_hash;
    $self->{project}   = $project;
    $self->{is_editor} = $user ? $user->has_right(undef, 'edit', 'project', $project->id) : 0;

    my $download  = "";
    my $down_info = $self->app->component('download_info');
    my $proj_link = "http://metagenomics.anl.gov/linkin.cgi?project=".$self->{project_id};

    if ($project->public) {
      $down_info->add_tooltip('all_down', 'download all metagenomes for this project');
      $down_info->add_tooltip('meta_down', 'download project metadata');
      $down_info->add_tooltip('derv_down', 'download all derived data for metagenomes of this project');
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"all_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.raw.tar'  ><img src='./Html/mg-download.png' style='height:15px;'/><small>submitted metagenomes</small></a>";
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/metadata.project-$id.xml'><img src='./Html/mg-download.png' style='height:15px;'/><small>project metadata</small></a>";
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.processed.tar'><img src='./Html/mg-download.png' style='height:15px;'/><small>MG-RAST analysis</small></a>";
    }
    $html .= $down_info->output() . "<h1 style='display: inline;'>" . $project->name .($user and $user->has_right(undef, 'edit', 'user', '*') ? " (ID ".$project->id.")": "")."</h1>". $download;
    $html .= "<p><table>";
    $html .= "<tr><td><b>Visibility</b></td><td style='padding-left:15px;'>".($project->public ? 'Public' : 'Private')."</td></tr>";
    $html .= "<tr><td><b>Static Link</b></td><td style='padding-left:15px;'><a href='$proj_link'>$proj_link</a></td></tr></table>";

    if ($self->{is_editor}) {
      my $share_html    = $self->share_info();
      my $edit_html     = $self->edit_info();
      my $delete_html   = $self->delete_info();
      my $add_info_html = $self->add_info_info($project->id);
      my $delete_div    = $project->public ? '' : "<div style='display:none;' id='delete_div'>".$self->delete_info()."</div>";

      $html .= "<p><div class='quick_links'><ul>";
      if (! $project->public) {
	$html .= qq~<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("delete_div").style.display == "none") {
    document.getElementById("delete_div").style.display = "inline";
  } else {
    document.getElementById("delete_div").style.display = "none";
  }'>Delete</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("public_div").style.display == "none") {
    document.getElementById("public_div").style.display = "inline";
    if (document.getElementById("add_job_div").innerHTML==""){execute_ajax("make_public_info", "public_div", "project=$id");}
  } else {
    document.getElementById("public_div").style.display = "none";
  }'>Make Public</a></li>~;
      }
      $html .= qq~
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("share_div").style.display == "none") {
    document.getElementById("share_div").style.display = "inline";
  } else {
    document.getElementById("share_div").style.display = "none";
  }'>Share</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("edit_div").style.display == "none") {
    document.getElementById("edit_div").style.display = "inline";
  } else {
    document.getElementById("edit_div").style.display = "none";
  }'>Edit Data</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("add_job_div").style.display == "none") {
    document.getElementById("add_job_div").style.display = "inline";
    if (document.getElementById("add_job_div").innerHTML==""){execute_ajax("add_job_info", "add_job_div", "project=$id");}
  } else {
    document.getElementById("add_job_div").style.display = "none";
  }'>Add Job</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("add_info_div").style.display == "none") {
    document.getElementById("add_info_div").style.display = "inline";
  } else {
    document.getElementById("add_info_div").style.display = "none";
  }'>Add Info</a></li>
</ul></div></p>
$delete_div
<div style='display:none;' id='public_div'></div>
<div style='display:none;' id='share_div'>$share_html</div>
<div style='display:none;' id='edit_div'>$edit_html</div>
<div style='display:none;' id='add_job_div'></div>
<div style='display:none;' id='add_info_div'>$add_info_html</div>
~;
    }

    $html .= $self->general_info();
    $html .= "<h3>Metagenomes</h3><a name='jobs'></a>";
    $html .= "<img src='./Html/clear.gif' onload='execute_ajax(\"job_list\", \"job_list_div\", \"project=$id\");'><div id='job_list_div'></div>";
    $html .= $self->additional_info();
  }
  else {
    $html .= $self->project_list();
  }
  $html .= "<br><br><br><br>";

  return $html;
}

sub project_list {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $application->session->user;

  my $jobdbm = $application->data_handle('MGRAST');
  my $projects = ($user) ? $user->has_right_to(undef, 'view', 'project') : [];
  my $public_projects = $jobdbm->Project->get_objects( { public => 1 } );
  my $content = "<h3>select a project to view</h3>";

  if ( scalar(@$projects) || scalar(@$public_projects)  ) {
    
    my $table = $application->component('project_table');
    $table->items_per_page(25);
    $table->show_top_browse(1);
    $table->width(800);
    $table->columns( [ { name => 'id' , filter => 1 , sortable => 1},
		       { name => 'project' , filter => 1 , sortable => 1},
		       { name => 'contact' , filter => 1 , sortable => 1},
		       { name => 'jobs' , filter => 1  , sortable =>  1} ] );
    my $data = [];
    $projects = $jobdbm->Project->get_objects_for_ids($projects);
    push(@$projects, @$public_projects);
    my $shown = {};
    foreach my $project (@$projects) {
      next if $shown->{$project->id};
      $shown->{$project->id} = 1;
      my $jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
      my $id = $project->id;
   
      push(@$data, [ $project->id, "<a href='metagenomics.cgi?page=MetagenomeProject&project=$id'>".$project->name."</a>", ( join "," , ($project->data('PI_lastname') , $project->data('PI_firstname') ) ) , scalar(@$jobs) ]);
    }
    $table->data($data);
    $content .= $table->output();

  } else {
    $content .= "<p>you currently do not have access to any projects</p>";
  }

  my $collection = "";
  if ($user && $user->has_right(undef, 'edit', 'project', '*')) {
    $collection = "<input type=checkbox name='collection' value='1'> create public collection";
  }

  if ($user){
    $content .= "<p><a onclick='document.getElementById(\"create_div\").style.display=\"inline\"' style='cursor: pointer;'>create new project</a></p>";
    $content .= "<div id='create_div' style='display: none;'>".$self->start_form('new_project_form', { action => 'create' })."<table><tr><td>project name</td><td><input type='text' name='pname'>$collection</td></tr><tr><td colspan=2><input type='submit' value='create'></td></tr></table>".$self->end_form()."</div>";
  }
  return $content;
}

sub create_project {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi();
  my $user = $application->session->user();
  
  my $pname = $cgi->param('pname');

  if ($pname) {
    my $pdbm = $application->data_handle('MGRAST');
    my $existing = $pdbm->Project->get_objects( { name => $pname } );
    if (scalar(@$existing)) {
      if ($user->has_right(undef, 'edit', 'project', $existing->[0]->id)) {
	$cgi->param('edit', 1);
	$cgi->param('project', $existing->[0]->id);
	$application->add_message('info', "You had already created this project. It has been opened for editing.");
      } else {
	$application->add_message('warning', "You project name is already taken. Creation aborted.");
      }
    } else {
      my $pdir = $FIG_Config::mgrast_projects;
      my $id = $pdbm->Project->last_id + 1;
      while (-d "$pdir/$id") {
	$id++;
      }
      unless ($pdir && $id) {
	$application->add_message('warning', "Could not open project directory");
	return 0;
      }
      mkdir("$pdir/$id");
      mkdir("$pdir/$id/graphics");
      mkdir("$pdir/$id/tables");
      my $type   = 'study';
      my $public = 0 ;
      if ($cgi->param('collection')) {
	$type   = 'collection';
	$public = 1 ;
      }
      my $project = $pdbm->Project->create( { id     => $id,
					      name   => $pname,
					      type   => $type ,
					      public => $public } );
      my $dbm = $application->dbmaster;
      $dbm->Rights->create( { application => undef,
			      scope => $user->get_user_scope,
			      name => 'view',
			      data_type => 'project',
			      data_id => $project->{id},
			      granted => 1 } );
      $dbm->Rights->create( { application => undef,
			      scope => $user->get_user_scope,
			      name => 'edit',
			      data_type => 'project',
			      data_id => $project->{id},
			      granted => 1 } );
      $dbm->Scope->create( { application => undef,
			     name => 'MGRAST_project_'.$project->{id},
			     description => 'MGRAST Project scope' } );
      $application->add_message('info', "successfully created project $pname");
      $application->cgi->param('project', $project->{id});

      if ($cgi->param('from_collection')) {
	my $set = $project->{name};
	my $existing = $application->dbmaster->Preferences->get_objects( { application => $application->backend,
									   user => $user,
									   name => 'mgrast_collection' } );
	foreach my $e (@$existing) {
	  if ($e->{value} =~ /^$set\|/) {
	    $e->delete;
	  }
	}
	$self->add_job_to_project();
      }
    }
  } else {
    $application->add_message('warning', "You must specify a project name. Creation aborted.");
  }
  
  return 1;
}

sub add_job_to_project {
  my ($self) = @_;
  
  my $dbm     = $self->application->dbmaster;
  my $jobdbm  = $self->application->data_handle('MGRAST');
  my @mg_ids  = split(/,/, $self->application->cgi->param('metagenomes'));
  my $proj_id = $self->application->cgi->param('project');
  my $project = $jobdbm->Project->init({ id => $proj_id });

  unless ($project) {
    $self->application->add_message('warning', "Could not retrieve project from database");
    return "";
  }

  my $pscope = $dbm->Scope->init( { application => undef,
				    name => 'MGRAST_project_'.$project->{id} } );
  unless ($pscope) {
    $pscope = $dbm->Scope->create( { application => undef,
				     name => 'MGRAST_project_'.$project->{id},
				     description => 'MGRAST Project scope' } );
  }
  my $rights = $dbm->Rights->get_objects( { scope => $pscope } );
  my $rhash = {};
  %$rhash = map { $_->{data_id} => $_ } @$rights;

  my (@old, @new);
  foreach my $mg (@mg_ids) {
    my $job   = $jobdbm->Job->init({ metagenome_id => $mg });
    my $check = $jobdbm->ProjectJob->get_objects({ job => $job });

    next unless ref($job);
    unless (exists($rhash->{$job->{metagenome_id}}) || $job->public) {
      $dbm->Rights->create( { granted => 1,
			      name => 'view',
			      data_type => 'metagenome',
			      data_id => $job->{metagenome_id},
			      delegated => 1,
			      scope => $pscope } );
    }
    if (scalar(@$check)) {
      push @old, $job->metagenome_id;
    }
    else {
      $jobdbm->ProjectJob->create({ job => $job, project => $project });
      push @new, $job->metagenome_id;
    }
  }

  my $html = "<blockquote>";
  if (@new > 0) {
    $html .= "<img src='./Html/clear.gif' onload='execute_ajax(\"job_list\", \"job_list_div\", \"project=$proj_id\");'>";
    $html .= "<p>The following metagenomes have been added to project ".$project->name.":<br>".join(", ", @new)."</p>";
  }
  if (@old > 0) {
    $html .= "<p>The following metagenomes already belong to a project:<br>".join(", ", @old)."</p>";
  }
  $html .= "</blockquote>";

  $self->application->add_message('info', $html);

  return 1;
}

sub general_info {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $project = $self->{project};
  my $is_editor = $self->{is_editor};
  my $meta_info = $self->{meta_info};

  my $content = "" ;
  my $description = "";
  my $funding = "";
  my $admin = "";
  my $tech = "";

  $description = $meta_info->{project_description} ||  $meta_info->{study_abstract} || " - ";
  $funding = $meta_info->{project_funding} || " - ";
  $admin = "<a href='mailto:".($meta_info->{PI_email} || "")."'>".($meta_info->{PI_firstname} || "")." ".($meta_info->{PI_lastname} || "")."</a>";
  if ( $meta_info->{PI_organization_url} ) {
    
    $admin .= "(<a href='http://".($meta_info->{PI_organization_url} || "")."'>".($meta_info->{PI_organization} || "")."</a>)<br>".($meta_info->{PI_organization_address} || "") . ", " . ($meta_info->{PI_organization_country} || "") ;
  }
  else{
    $admin .= ($meta_info->{PI_organization} || "")."<br>".($meta_info->{PI_organization_address} || "").", ".($meta_info->{PI_organization_country} || "");
  }
  $tech = "<a href='mailto:".($meta_info->{email} || "")."'>".($meta_info->{firstname} || "")." ".($meta_info->{lastname} || "")."</a> (<a href='".($meta_info->{organization_url} || "")."'>".($meta_info->{organization} || "")."</a>)<br>".($meta_info->{organization_address} || "").", ".($meta_info->{organization_country} || "");
  
  my $predefined = { email => 1 ,
		     organizatioon => 1 ,
		     organization_address => 1 ,
		     organization_country => 1 ,
		     PI_email => 1 ,
		     PI_firstname => 1 ,
		     PI_lastname => 1 ,
		     PI_organization => 1 ,
		     PI_organization_url => 1 ,
		     PI_organization_address => 1 ,
		     PI_organization_country => 1 ,
		     organization => 1 ,
		     organization_url => 1 ,
		     firstname => 1 ,
		     lastname => 1 ,
		     project_funding => 1 ,
		     project_description => 1 ,
		     study_abstract => 1 ,
		     submit_to_insdc => 1 ,
		     project_name => 1 ,
		     sample_collection_id => 1 ,
		   };
  my $md = '';
  foreach my $tag (keys %$meta_info){
    next if ($predefined->{$tag}) ;    
    my $display_name = $tag ;
    my $value = $meta_info->{$tag} ;
    $md .= "<tr><th>$display_name</th><td>$value</td></tr>";
  }
  
  $content .= qq~
<h3>Description</h3>$description
<h3>Funding Source</h3>$funding
<h3>Contact</h3>
<b>Administrative<b><br>$admin<br><br>
<b>Technical<b><br>$tech
~;
  if ($md) {
    $content .= "<h3>Additional Data</h3><table>$md</table>";
  }
  
  return $content;
}

sub job_list {
  my ($self) = @_;

  my $content = "";
  my $proj_id = $self->application->cgi->param('project');
  my $project = $self->application->data_handle('MGRAST')->Project->init({ id => $proj_id });
  my @pdata   = @{ $project->metagenomes_summary };

  if (@pdata > 0) {
    my $header = [ { name => 'MG-RAST ID', filter => 1 }, 	 
		   { name => 'Metagenome Name', filter => 1, sortable => 1 },
		   { name => 'Size (bp)', sortable => 1 },
		   { name => 'Biome', filter => 1, sortable => 1, operator => 'combobox' },
		   { name => 'Location', filter => 1, sortable => 1 }, 	 
		   { name => 'Country', filter => 1, sortable => 1 },
		   { name => 'Sequence Type', filter => 1, sortable => 1, operator => 'combobox' }
		 ];
    foreach my $row (@pdata) {
      my $mid = $row->[0];
      my $download = "<table><tr align='center'>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$proj_id/$mid.raw.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$proj_id/$mid.metadata.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$proj_id/$mid.processed.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a></td>
</tr></table>";
      $row->[0] = "<a href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a>";
      push @$row, $download if ($project->public);
    }
    push @$header, { name => 'Download' } if ($project->public);
   
    my $ptable = $self->application->component('jobs_table');
    $ptable->columns($header); 
    $ptable->width(800);
    $ptable->show_export_button({title => "Export Jobs Table", strip_html => 1});

    if ( scalar(@pdata) > 50 ) {
      $ptable->show_top_browse(1);
      $ptable->show_bottom_browse(1);
      $ptable->items_per_page(50);
      $ptable->show_select_items_per_page(1); 
    }
    
    $ptable->data(\@pdata);
    $content .= $ptable->output();
  } else {
    $content .= "<p>There are currently no jobs assigned to this project</p>";
  }
  
  return $content;
}

sub add_job_info {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my $pid = $cgi->param('project');
  my $html = "";
  my $list_select = $self->application->component('job_select');
  my ($data, $groups, $types) = $self->selectable_metagenomes();

  $list_select->data($data);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->group_names($groups);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('available metagenomes');
  $list_select->right_header('selected metagenomes');
  $list_select->name('add_metagenome');
  $list_select->types($types);

  my $lid = $list_select->id;
  $html .= "<h3>Add Job</h3><div id='list_select_div'>" . $list_select->output();
  $html .= qq~<input type='button' value='ok' onclick='
var sel_elem = document.getElementById("list_select_list_b_" + $lid);
var mg_list  = [];
for (var i = 0; i < sel_elem.options.length; i++) {
  mg_list.push( sel_elem.options[i].value );
}
window.top.location="?page=MetagenomeProject&action=add_job_to_project&project=$pid&metagenomes="+mg_list.join(",");' /></div>~;
  $html .= "<div id='mgs_added_div'></div>";
  
  return $html;
}

sub add_info_info {
  my ($self, $pid) = @_;

  my $html = "<h3>Add Info</h3>";
  $html .= $self->start_form('upload_form', {project => $pid, action => 'upload_file'});
  $html .= "<select name='upload_type'><option value='graphic'>graphic</option><option value='table'>table</option></select><input type='file' name='upload_file'><input type='submit' value='upload'>";
  $html .= $self->end_form();
  return $html;
}

sub additional_info {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  my $content = "";

  my $jobdbm = $application->data_handle('MGRAST');

  my $project = $self->{project};
  my $project_id = $project->id;
  my $project_basedir = $FIG_Config::mgrast_projects."/";

  # tables
  my $project_table_dir = "/tables";
  my $tdir = $project_basedir.$project_id.$project_table_dir;
  my @tables;
  my $dh;
  if (opendir($dh, $tdir)) {
    @tables = grep { -f "$tdir/$_" } readdir($dh);
    closedir $dh;
  }

  my $pdir = $FIG_Config::mgrast_projects;
  unless (-d "$pdir/$project_id") {
    mkdir("$pdir/$project_id");
  }
  unless (-d "$pdir/$project_id/graphics") {
    mkdir("$pdir/$project_id/graphics");
  }
  unless (-d "$pdir/$project_id/tables") {
    mkdir("$pdir/$project_id/tables");
  }
  my $i = 1;
  foreach my $table (@tables) {
    my ($name) = $table =~ /(.+)\..+$/;
    $name =~ s/_/ /g;
    open(FH, $tdir."/".$table) or return "<p>Could not open file: $@ $!</p>";
    $content .= "<h3>$name</h3>";
    
    my $columns = [];
    my $data = [];
    
    while(<FH>) {
      chomp;
      if (scalar(@$columns)) {
	push(@$data, [ split(/\t/) ]);
      } else {
	@$columns = split(/\t/);
      }
    }
    close FH;

    $application->register_component('Table', 't'.$i);

    $application->component('t'.$i)->columns($columns);
    $application->component('t'.$i)->data($data);
    $content .= $application->component('t'.$i)->output();
    $i++;
  }

  # graphics
  my $project_graphics_dir = "/graphics";
  my $gdir = $project_basedir.$project_id.$project_graphics_dir;
  my @graphics;
  if (opendir($dh, $gdir)) {
    @graphics = grep { /\.png$/ && -f "$gdir/$_" } readdir($dh);
    closedir $dh;
  }

  $i = 1;
  foreach my $graphic (@graphics) {
    my ($name) = $graphic =~ /(.+)\.png$/;
    $name =~ s/_/ /g;
    $content .= "<h3>$name</h3>";
    my $img = WebGD->newFromPng($gdir."/".$graphic);
    $content .= "<img src='".$img->image_src()."'>";
    $i++;
  }

  return $content;
}

sub upload_file {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  my $project_id = $cgi->param('project');
  if ($user->has_right(undef, 'edit', 'project', $project_id)) {
    my $jobdbm = $application->data_handle('MGRAST');
    my $project = $jobdbm->Project->init({ id => $project_id });
    my $savedir = $FIG_Config::mgrast_projects."/".$project->{id}."/".$cgi->param('upload_type')."s/";
    my $filename = $cgi->param('upload_file');
    my $fh = $cgi->upload('upload_file');
    if (defined $fh) {
      if (open(OUTFILE, ">".$savedir.$filename)) {
	while (<$fh>) {
	  print OUTFILE;
	}
	close OUTFILE;
	$application->add_message('info', "file uploaded successfully");
      } else {
	$application->add_message('warning', "could not save file $!");
	return 0;
      }
    }
  } else {
    $application->add_message('warning', 'you do not have the permissions to add information to this project');
    return 0;
  }

  return 1;
}

sub required_rights {
  my ($self) = @_;

  return [];
}

sub update_metadata {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metadbm = MGRAST::Metadata->new->_handle();
  my $jobdbm = $self->application->data_handle('MGRAST');

  unless ($metadbm && $jobdbm) {
    return "could not connect to database";
  }

  my $project = $jobdbm->Project->init({ id => $cgi->param('project') });

  my $user = $self->application->session->user;
  unless ($user && $user->has_right(undef, 'edit', 'project', $project->id)) {
    return "insufficient rights, aborting";
  }

  if ($cgi->param('project_name')) {
    $project->name($cgi->param('project_name'));
  }

  my $keyval = {};
  $keyval->{project_description} = $cgi->param('project_description');
  $keyval->{project_funding} = $cgi->param('project_funding');
  $keyval->{PI_email} = $cgi->param('pi_email');
  $keyval->{PI_firstname} = $cgi->param('pi_firstname');
  $keyval->{PI_lastname} = $cgi->param('pi_lastname');
  $keyval->{PI_organization} = $cgi->param('pi_organization');
  $keyval->{PI_organization_country} = $cgi->param('pi_organization_country');
  $keyval->{PI_organization_url} = $cgi->param('pi_organization_url');
  $keyval->{PI_organization_address} = $cgi->param('pi_organization_address');
  $keyval->{email} = $cgi->param('email');
  $keyval->{firstname} = $cgi->param('firstname');
  $keyval->{lastname} = $cgi->param('lastname');
  $keyval->{organization} = $cgi->param('organization');
  $keyval->{organization_country} = $cgi->param('organization_country');
  $keyval->{organization_url} = $cgi->param('organization_url');
  $keyval->{organization_address} = $cgi->param('organization_address');

  foreach my $key (keys(%$keyval)) {
    my $existing = $metadbm->ProjectMD->get_objects( { project => $project,
						       tag => $key } );
    if (scalar(@$existing)) {
      $existing->[0]->value($keyval->{$key});
    } else {
      $metadbm->ProjectMD->create( { project => $project,
				     tag => $key,
				     value => $keyval->{$key} } );
    }
  }

  return 1;
}

sub edit_info {
  my ($self) = @_;

  my $meta_info = $self->{meta_info};
  my $project   = $self->{project};
  my $content   = "<h3>Edit Data</h3>";
  
  $content .= $self->start_form('additional_info_form', { update => 1, project => $project->{id} });
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>name</span><br><input type='text' name='project_name' style='width:250px;' value='".$project->{name}."'><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>description</span><br><textarea name='project_description' style='width:250px;'>".($meta_info->{project_description} || $meta_info->{study_abstract} || " - ")."</textarea><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>funding source</span><br><input type='text' value='".($meta_info->{project_funding} || " - ")."' name='project_funding'><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>administrative contact</span><br><table><tr><th>eMail</th><td><input type='text' value='".($meta_info->{PI_email} || " - ")."' name='pi_email'></td></tr><tr><th>firstname</th><td><input type='text' value='".($meta_info->{PI_firstname} || " - ")."' name='pi_firstname'></td></tr><tr><th>lastname</th><td><input type='text' value='".($meta_info->{PI_lastname} || " - ")."' name='pi_lastname'></td></tr><tr><th>organization</th><td><input type='text' value='".($meta_info->{PI_organization} || " - ")."' name='pi_organization'></td></tr><tr><th>organization url</th><td><input type='text' value='".($meta_info->{PI_organization_url} || " - ")."' name='pi_organization_url'></td></tr><tr><th>organization address</th><td><input type='text' value='".($meta_info->{PI_organization_address} || " - ")."' name='pi_organization_address'></td></tr><tr><th>organization country</th><td><input type='text' value='".($meta_info->{PI_organization_country} || " - ")."' name='pi_organization_country'></td></tr></table><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>technical contact</span><br><table><tr><th>eMail</th><td><input type='text' value='".($meta_info->{email} || " - ")."' name='email'></td></tr><tr><th>firstname</th><td><input type='text' value='".($meta_info->{firstname} || " - ")."' name='firstname'></td></tr><tr><th>lastname</th><td><input type='text' value='".($meta_info->{lastname} || " - ")."' name='lastname'></td></tr><tr><th>organization</th><td><input type='text' value='".($meta_info->{organization} || " - ")."' name='organization'></td></tr><tr><th>organization url</th><td><input type='text' value='".($meta_info->{organization_url} || " - ")."' name='organization_url'></td></tr><tr><th>organization address</th><td><input type='text' value='".($meta_info->{organization_address} || " - ")."' name='organization_address'></td></tr><tr><th>organization country</th><td><input type='text' value='".($meta_info->{organization_country} || " - ")."' name='organization_country'></td></tr><tr><td colspan=2><input type='submit' value='update'></td><tr></table>";    
  $content .= $self->end_form;

  return $content;
}

sub delete_info {
  my ($self) = @_;

  my $project = $self->{project};
  my $content = "<h3>Delete</h3>";
  $content .= $self->start_form('delete_project', { project => $project->id,
						    action  => 'delete_project' });
  $content .= "<p><strong>To really delete this project, type 'DELETE' into the textbox and click 'delete project'. This will delete the project and all associated metadata. The datasets (jobs) belonging to this project will <i>not</i> be touched.</strong> <input name='confirmation' type='textbox'>";
  $content .= "&nbsp;&nbsp;&nbsp;<input type='submit' name='delete_project' value='delete project'></p>";
  $content .= $self->end_form;

  return $content;
}

sub share_info {
  my ($self) = @_;

  my $email   = $self->app->cgi->param('email') || '';
  my $project = $self->{project};
  my $jobdbm = $self->application->data_handle('MGRAST');
  my $content = "<h3>Share</h3>";
  $content .= $self->start_form('share_project', { project => $project->id,
						   action  => 'share_project' });
  $content .= "<p><strong>Enter an email address or group name:</strong> <input name='email' type='textbox' value='$email'><input type='checkbox' name='editable'> <span title='check to allow the user or group to edit this project'>editable</span>";
  $content .= "&nbsp;&nbsp;&nbsp;<input type='submit' name='share_project' value=' Share project with this user or group '></p>";
  $content .= $self->end_form;
  
  # show people who can see this project at the moment
  $content .= "<p id='section_bar'><strong>This project is currently available to:</strong></p>";
  my $rights_view = $self->application->dbmaster->Rights->get_objects( { name => 'view',
									 data_type => 'project',
									 data_id => $project->id
								       });

  my $rights_edit = $self->application->dbmaster->Rights->get_objects( { name => 'edit',
									 data_type => 'project',
									 data_id => $project->id
								       });
  my $rights_edit_hash = {};
  %$rights_edit_hash = map { $_->scope->name => 1 } @$rights_edit;
  my $found_one = 0;
  $content .= '<table>';
  my $tokens = [];
  foreach my $r (@$rights_view) {
    next if ($self->app->session->user->get_user_scope->_id eq $r->scope->_id);
    if ($r->scope->name =~ /^token\:/) {
      push(@$tokens, $r->scope);
    } else {
      my $editable = "";
      if ($rights_edit_hash->{$r->scope->name}) {
	$editable = " (\/w edit rights)";
      }
      $content .= "<tr><td>".$r->scope->name_readable."$editable</td>";
      
      if($r->delegated) {
	$content .= "<td>".$self->start_form('revoke_project', { project => $project->id, 
								 action => 'revoke_project',
								 scope => $r->scope->_id,
							       });
	$content .= "<input type='submit' name='revoke_project' value=' Revoke '>";
	$content .= $self->end_form();
	$content .= "</td>";
      }
      else {
	$content .= "<td></td>";
      }
      $content .= '</tr>';
      $found_one = 1;
    }
  }
  
  unless($found_one) {
    $content .= "<tr><td>This project is not shared with anyone at the moment.</td></tr>";
  }
  $content .= '</table>';

  # check for invitations
  if (scalar(@$tokens)) {
    $content .= "<p id='section_bar'><img src='./Html/rast-info.png'/>invitations which have not been claimed yet:</p>";
    $content .= "<table>";
    foreach my $token (@$tokens) {
      my ($uid, $date, $email) = $token->description =~ /^token_scope\|from_user\:(\d+)\|init_date:(\d+)\|email\:(.+)/;
      my $u = $self->application->dbmaster->User->get_objects( { _id => $uid } )->[0];
      my $t = localtime($date);
      my ($token_id) = $token->name =~ /^token\:(.+)$/;
      $content .= "<tr><td>sent by ".$u->firstname." ".$u->lastname." to $email on $t <input type='button' onclick='window.top.location=\"metagenomics.cgi?page=MetagenomeProject&project=".$project->id."&action=cancel_token&token=$token_id\"' value='cancel'></td></tr>";
    }
    $content .= "</table>";
  }

  # show jobs shared with the project
  my $pscope = $self->application->dbmaster->Scope->init( { application => undef,
							    name => 'MGRAST_project_'.$project->id } );
  unless (ref($pscope)) {
    $pscope = $self->application->dbmaster->Scope->create( { application => undef,
							     name => 'MGRAST_project_'.$project->id } );
    my $pjs = $jobdbm->ProjectJob->get_objects( { project => $project } );
    foreach my $pj (@$pjs) {
      $self->application->dbmaster->Rights->create( { name => 'view',
						      data_type => 'metagenome',
						      data_id => $pj->job->metagenome_id,
						      granted => 1,
						      scope => $pscope } );
    }
  }
  if (ref($pscope)) {
    my $prights = $self->application->dbmaster->Rights->get_objects( { scope => $pscope } );
    my $mgs = $project->metagenomes_id_name;
    if (scalar(@$prights)) {
      $content .= "<p id='section_bar' style='font-variant: normal;'><img src='./Html/rast-info.png'/>The lists below show which metagenomes that are part of your project will be available to users that have access to this project and which metagenomes will not be available.<br><br><b>Note:</b>The metagenomes that appear in the 'shared' list, will be available to the users shown in the section 'This project is currently available to'. They will NOT be publicly available.</p>";
      
      my $data = [];
      my $preselection = [];
      my $shared_mgs = {};
      foreach my $pright (@$prights) {
	$shared_mgs->{$pright->{data_id}} = 1;
	push(@$preselection, $pright->{data_id});
      }
      foreach my $key (keys(%$mgs)) {
	push(@$data, { value => $key, label => $mgs->{$key}.' ('.$key.')' });
      }
      my $list_select = $self->application->component('shared_job_select');
      $list_select->data($data);
      $list_select->preselection($preselection);
      $list_select->multiple(1);
      $list_select->filter(1);
      $list_select->{max_width_list} = 250;
      $list_select->left_header('not shared metagenomes');
      $list_select->right_header('shared metagenomes');
      $list_select->name('shared_metagenomes');

      $content .= $self->start_form('change_shared_form', { action => 'change_shared_metagenomes', project => $project->id }).$list_select->output."<input type='button' value='change' onclick='list_select_select_all(\"".$list_select->id."\");document.forms.change_shared_form.submit();'>".$self->end_form;
    }
  }

  return $content;
}

sub change_shared_metagenomes {
  my ($self) = @_;
  
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $jobdbm = $application->data_handle('MGRAST');
  my @shared = $cgi->param('shared_metagenomes');
  my $shared_hash = {};
  %$shared_hash = map { $_ => 1 } @shared;

  my $pscope = $self->application->dbmaster->Scope->init( { application => undef,
							    name => 'MGRAST_project_'.$cgi->param('project') } );
  if (ref($pscope)) {
    # get the rights
    my $prights = $application->dbmaster->Rights->get_objects( { scope => $pscope } );

    # delete the unwanted
    foreach my $right (@$prights) {
      if (! $shared_hash->{$right->{data_id}}) {
	$right->delete;
      }
    }

    # add the new
    my $prights_hash = {};
    %$prights_hash = map { $_->{data_id} => 1 } @$prights;
    foreach my $share (@shared) {
      if (! $prights_hash->{$share}) {
	$application->dbmaster->Rights->create( { granted => 1,
						  name => 'view',
						  data_type => 'metagenome',
						  data_id => $share,
						  delegated => 1,
						  scope => $pscope });
      }
    }
  }
  
  $application->add_message('info', "The changes to the shared metagenomes for this project have been applied.");
}

sub cancel_token {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $master = $application->dbmaster;

  my $token = $cgi->param('token');
  unless ($token) {
    $application->add_message('warning', "invalid token, aborting");
    return 0;
  }
  
  my $scope = $master->Scope->get_objects( { name => "token:".$token } );
  unless (scalar(@$scope)) {
    $application->add_message('warning', "token not found, aborting");
    return 0;
  }

  my $rights = $master->Rights->get_objects( { scope => $scope->[0] } );
  foreach my $r (@$rights) {
    $r->delete();
  }
  $scope->[0]->delete();

  $application->add_message('info', "invitation canceled");

  return 1;
}

sub delete_project {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $application->session->user;
  my $cgi = $application->cgi;
  my $jobdbm = $application->data_handle('MGRAST');
  my $project = $jobdbm->Project->init({ id => $cgi->param('project') });
  my $project_name = $project->name;
  my $project_id = $project->id;

  my $conf = lc($cgi->param('confirmation'));
  if ($conf && $conf eq 'delete' && $user && $user->has_right(undef, 'edit', 'project', $project_id)) {
    my $project_jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
    foreach my $p (@$project_jobs) {
      $p->delete;
    }
    my $project_rights = $application->dbmaster->Rights->get_objects( { data_type => 'project', data_id => $project_id  } );
    foreach my $r (@$project_rights) {
      $r->delete;
    }
    my $pscope = $application->dbmaster->Scope->init( { application => undef,
							name => 'MGRAST_project_'.$project_id } );
    if ($pscope) {
      my $uhss = $application->dbmaster->UserHasScope->get_objects( { scope => $pscope } );
      foreach my $uhs (@$uhss) {
	$uhs->delete;
      }
      $pscope->delete;
    }
    my $metadbm = MGRAST::Metadata->new->_handle();
    my $project_meta = $metadbm->ProjectMD->get_objects( { project => $project } );
    foreach my $m (@$project_meta) {
      $m->delete;
    }
    $project->delete;
    $cgi->delete('project');
    $application->add_message('info', "project $project_name has been deleted");
  }

  return 1;
}

sub make_public_info {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $jobdbm = $application->data_handle('MGRAST');
  my $project = $jobdbm->Project->init({ id => $cgi->param('project') });
  my $project_jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
  my $master = $application->dbmaster;

  my $html = "<h3>Make Project Public</h3>";
  $html .= "<p style='font-variant: normal;'>When you make a project public, you should consider making the metagenomes belonging to the project public as well. The below lists show which metagenomes that are associated to this project you can make public, for which you are lacking the rights to do so and which are missing the MIGS metadata.</p><p style='font-variant: normal;'>Jobs that are missing MIGS metadata cannot be made public. You can add this information by clicking on the metagenome name. You also have the option to make these jobs public at a later time. You can only make jobs public, for which you have the edit right.</p><p style='font-variant: normal;'><b>Warning:</b> Making data publicly available is final and cannot be undone.</p>";

  my $mddb = $self->data('mddb');
  my $publicizable = [];
  my $missing_migs = [];
  my $missing_rights = [];
  foreach my $pj (@$project_jobs) {
    my $job = $pj->job;
    if ($user->has_right(undef, 'edit', 'metagenome', $job->metagenome_id)) {
      if ($mddb->is_job_compliant($job)) {
	push(@$publicizable, $job);
      } else {
	push(@$missing_migs, $job);
      }
    } else {
      push(@$missing_rights, $job);
    }
  }

  my $data = [];
  my $preselection = [];
  foreach my $pub (@$publicizable) {
    push(@$data, { value => $pub->{metagenome_id}, label => $pub->{name}.' ('.$pub->{metagenome_id}.')' });
    push(@$preselection, $pub->{metagenome_id});
  }
  my $list_select = $self->application->component('public_job_select');
  $list_select->data($data);
  $list_select->preselection($preselection);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('metagenomes not to be public');
  $list_select->right_header('metagenomes to be public');
  $list_select->name('public_metagenomes');

  $html .= $self->start_form('makepublicform', { project => $project->id, action => 'make_project_public' });

  $html .= "<p>By clicking the button below, you confirm that you have the copyright for the selected metagenomes and this project.</p>";

  if (scalar(@$missing_migs)) {
    $html .= "<b>missing metadata</b>";
    $html .= "<p>".join("<br>", map { "<a href='?page=MetaDataMG&metagenome=".$_->{metagenome_id}."' target=_blank>".$_->{name}." (".$_->{metagenome_id} .")</a>"} @$missing_migs)."</p>";
  }
  
  if (scalar(@$missing_rights)) {
    $html .= "<b>missing rights</b>";
    $html .= "<p>".join("<br>", map { $_->{name}." (".$_->{id} .")"} @$missing_rights)."</p>";
  }

  $html .= "<b>publicizable</b>";
  if (scalar(@$data)) {
    $list_select->output();
  } else {
    $html .= "<p>- no metagenomes belonging to this project can be made public -</p>";
  }
  $html .= "<p>By clicking the button below, you confirm that you have the copyright for the selected metagenomes and this project.</p><input type='button' value='make public' onclick='if(confirm(\"Do you really want to make this project and the selected metagenomes public?\")){list_select_select_all(\"".$list_select->id."\");document.forms.makepublicform.submit();}'><br><br>";
  $html .= $self->end_form();

  return $html;
}

sub make_project_public {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $project_id = $cgi->param('project');
  my @metagenomes = $cgi->param('public_metagenomes');
  my $mgrast = $application->data_handler('MGRAST');
  
  # check rights
  if ($user->has_right(undef, 'edit', 'project', $project_id)) {
    my $project = $mgrast->Project->init( { id => $project_id });
    unless (ref($project)) {
      $application->add_message('warning', "could not initialize project $project_id");
      return "";
    }
    $project->public(1);
    $application->add_message('info', "Project ".$project->name." successfully made public");
    foreach my $mg (@metagenomes) {
      if ($user->has_right(undef, 'edit', 'metagenome', $mg)) {
	my $job = $mgrast->Job->init( { metagenome_id => $mg } );
	unless (ref($job)) {
	  $application->add_message('warning', "could not initialize metagenome $mg");
	} else {
	  $job->public(1);
	  $application->add_message('info', "metagenome ".$job->name." ($mg) successfully made public");	  
	}
      } else {
	$application->add_message('warning', "You do not have the right to make the metagenome $mg public.");
      }
    }
  } else {
    $application->add_message('warning', "You do not have the right to make this project public");
  }
}

=pod

=item * B<share_project>()

Action method to grant the right to view and edit a project to the selected scope

=cut

sub share_project {
  my ($self) = @_;
  
  # get some info
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $jobdbm = $application->data_handle('MGRAST');
  my $project = $jobdbm->Project->init({ id => $cgi->param('project') });
  my $project_name = $project->name;
  my $project_id = $project->id;
  my $dbm = $application->dbmaster;

  # check email format
  my $email = $cgi->param('email');
  $email =~ s/^\s+(.*)$/$1/;
  unless ($email =~ /^[\w\-\.]+\@[\.a-zA-Z\-0-9]+\.[a-zA-Z]+$/) {
    $self->application->add_message('warning', 'Please enter a valid email address.');
    return 0;
  }

  # check if have a user with that email
  my $master = $self->application->dbmaster;  
  my $user = $master->User->init({ email => $email });
  if (ref $user) {
    
    # send email
    my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobGranted.tmpl',
				    die_on_bad_params => 0);
    $ubody->param('FIRSTNAME', $user->firstname);
    $ubody->param('LASTNAME', $user->lastname);
    $ubody->param('WHAT', "the metagenome project $project_name");
    $ubody->param('WHOM', $self->app->session->user->firstname.' '.$self->app->session->user->lastname);
    $ubody->param('LINK', $WebConfig::APPLICATION_URL."?page=MetagenomeProject&project=$project_id");
    $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    
    $user->send_email( $WebConfig::ADMIN_EMAIL,
		       $WebConfig::APPLICATION_NAME.' - new data available',
		       $ubody->output
		     );


    # grant rights if necessary
    my $rights = [ 'view' ];
    if ($cgi->param('editable')) {
      push(@$rights, 'edit');
    }
    foreach my $name (@$rights) {
      unless(scalar(@{$master->Rights->get_objects( { name => $name,
						      data_type => 'project',
						      data_id => $project_id,
						      scope => $user->get_user_scope } )})) {
	my $right = $master->Rights->create( { granted => 1,
					       name => $name,
					       data_type => 'project',
					       data_id => $project_id,
					       scope => $user->get_user_scope,
					       delegated => 1, } );

	unless (ref $right) {
	  $self->app->add_message('warning', 'Failed to create the right in the user database, aborting.');
	  return 0;
	}
      }
    }
    my $pscope = $dbm->Scope->init( { application => undef,
				      name => 'MGRAST_project_'.$project_id } );
    if ($pscope) {
      my $uhs = $dbm->UserHasScope->get_objects( { user => $user, scope => $pscope } );
      unless (scalar(@$uhs)) {
	$dbm->UserHasScope->create( { user => $user, scope => $pscope, granted => 1 } );
      }
    }

    $self->app->add_message('info', "Granted the right to view this project to ".$user->firstname." ".$user->lastname.".");
    return 1;

  } else {
    
    # create a claim token
    my $description = "token_scope|from_user:".$application->session->user->{_id}."|init_date:".time."|email:".$email;
    my @chars=('a'..'z','A'..'Z','0'..'9','_');
    my $token = "";
    foreach (1..50) {
      $token.=$chars[rand @chars];
    }
    
    # create scope for token
    my $token_scope = $master->Scope->create( { name => "token:".$token, description => $description } );
    unless (ref($token_scope)) {
      $self->application->add_message('warning', "failed to create token");
      return 0;
    }

    # add rights to scope
    my $rights = [ 'view' ];
    if ($cgi->param('editable')) {
      push(@$rights, 'edit');
    }
    my $rsave = [];
    foreach my $name (@$rights) {
      my $right = $master->Rights->create( { granted => 1,
					     name => $name,
					     data_type => 'project',
					     data_id => $project_id,
					     scope => $token_scope,
					     delegated => 1, } );
      unless (ref $right) {
	$self->app->add_message('warning', 'Failed to create the right in the user database, aborting.');
	$token_scope->delete();
	foreach my $r (@$rsave) {
	  $r->delete();
	}
	return 0;
      }

      push(@$rsave, $right);
    }

    # send token mail
    my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobToken.tmpl',
				    die_on_bad_params => 0);
    $ubody->param('WHAT', "the metagenome project $project_name");
    $ubody->param('REGISTER', $WebConfig::APPLICATION_URL."?page=Register");
    $ubody->param('WHOM', $self->app->session->user->firstname.' '.$self->app->session->user->lastname);
    $ubody->param('LINK', $WebConfig::APPLICATION_URL."?page=ClaimToken&token=$token&type=project");
    $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    

    my $mailer = Mail::Mailer->new();
    if ($mailer->open({ From    => $WebConfig::ADMIN_EMAIL,
			To      => $email,
			Subject => $WebConfig::APPLICATION_NAME.' - new data available',
		      })) {
      print $mailer $ubody->output;
      $mailer->close();
      $application->add_message('info', "invitation sent successfully");
    } else {
      $token_scope->delete();
      foreach my $r (@$rsave) {
	$r->delete();
      }
      $application->add_message('warning', "Could not send invitation mail, aborting.");
      return 0;
    }

    return 1;
  }

  return ;
}


=pod

=item * B<revoke_project>()

Action method to revoke the right to view and edit a project from the selected scope

=cut

sub revoke_project {
  my ($self) = @_;

  my $master = $self->application->dbmaster;

  # get the scope
  my $s_id = $self->app->cgi->param('scope');
  my $scope = $master->Scope->get_objects({ _id => $s_id });
  unless(@$scope) {
    $self->app->add_message('warning', 'There has been an error: missing a scope to revoke right on, aborting.');
    return 0;
  }
  $scope = $scope->[0];

  # get genome id
  my $project_id = $self->application->cgi->param('project');

  # delete the rights, double check delegated
  my $rights = [ 'view', 'edit' ];
  foreach my $name (@$rights) {
    foreach my $r (@{$master->Rights->get_objects( { name => $name,
						     data_type => 'project',
						     data_id => $project_id,
						     scope => $scope,
						     delegated => 1,
						   })}) {
      $r->delete;
    }
  }
  
  my $pscope = $master->Scope->init( { application => undef,
				       name => 'MGRAST_project_'.$project_id } );
  if (ref($pscope)) {
    my $users = $master->UserHasScope->get_objects( { scope => $scope } );
    foreach my $u (@$users) {
      my $user = $u->user;
      my $torevoke = $master->UserHasScope->get_objects( { user => $user, scope => $pscope });
      if (scalar(@$torevoke)) {
	$torevoke->[0]->delete;
      }
    }
  }

  $self->app->add_message('info', "Revoked the right to view this project from ".$scope->name_readable.".");

  return 1;

}

# get all public jobs without project and display them for download
sub no_project_job_list {
  my ($self, $dbm, $user) = @_;

  my $html = "";
  my $id   = '0';
  my @jobs = ();
  my @data = ();
  my $down_all  = "";
  my $down_info = $self->app->component('download_info');

  $down_info->add_tooltip('all_down', 'download all metagenomes for this project');
  $down_info->add_tooltip('meta_down', 'download project metadata');
  $down_info->add_tooltip('derv_down', 'download all derived data for metagenomes of this project');
  $down_all .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"all_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.raw.tar'  ><img src='./Html/mg-download.png' style='height:15px;'/><small>submitted metagenomes</small></a>";
  $down_all .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/metadata.project-$id.xml'><img src='./Html/mg-download.png' style='height:15px;'/><small>project metadata</small></a>";
  $down_all .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.processed.tar'><img src='./Html/mg-download.png' style='height:15px;'/><small>MG-RAST analysis</small></a>";

  $html .= $down_info->output() . "<h1 style='display: inline;'>public metagenomes not in any project</h1>". $down_all . "<br>";

  foreach my $j ( @{$dbm->Job->without_project()} ) { # [metagenome_id, name, sequence_type, file_size_raw, public, viewable]
    if ( ($j->[4] == 1) && ($j->[5] == 1) ) {
      push @jobs, $dbm->Job->init({ metagenome_id => $j->[0] });
    }
  }

  if (@jobs > 0) {
    my $header = [ { name => 'MG-RAST ID', filter => 1 }, 	 
		   { name => 'Metagenome Name', filter => 1, sortable => 1 },
		   { name => 'Size (bp)', sortable => 1 },
		   { name => 'Biome', filter => 1, sortable => 1, operator => 'combobox' },
		   { name => 'Location', filter => 1, sortable => 1 }, 	 
		   { name => 'Country', filter => 1, sortable => 1 },
		   { name => 'Sequence Type', filter => 1, sortable => 1, operator => 'combobox' },
		   { name => 'Download' }
		 ];

    foreach my $j (@jobs) {
      my $mid = $j->metagenome_id;
      my $biome = $j->biomes;
      my $download = "<table><tr align='center'>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.raw.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid/metadata.xml'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.processed.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a></td>
</tr></table>";

      push @data, [ "<a href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a>",
		    $j->name,
		    format_number($j->stats->{bp_count_raw}),
		    scalar(@$biome) ? join(", ", @$biome) : "-",
		    $j->location,
		    $j->country,
		    $j->sequence_type,
		    $download ];
    }
   
    my $ptable = $self->application->component('jobs_table');
    $ptable->columns( $header ); 
    $ptable->width(800);
    #$ptable->show_export_button({title => "Export Jobs Table", strip_html => 1});

    if ( scalar(@data) > 50 ) {
      $ptable->show_top_browse(1);
      $ptable->show_bottom_browse(1);
      $ptable->items_per_page(50);
      $ptable->show_select_items_per_page(1); 
    }    
    $ptable->data(\@data);
    $html .= "<br>" . $ptable->output();
  } else {
    $html .= "<p>There are currently no public jobs without projects</p>";
  }
  
  return $html;
}

sub selectable_metagenomes {
  my ($self) = @_;

  my $metagenomes = [];
  my $user  = $self->application->session->user;
  my $rast  = $self->application->data_handle('MGRAST'); 
  my $mgdb  = MGRAST::MetagenomeAnalysis2->new( $rast->db_handle );
  my $avail = $mgdb->get_all_job_ids();
  my $avail_hash = {};
  %$avail_hash = map { $_ => 1 } @$avail;

  # check for available metagenomes
  my $seq_types = {};
  my $all_mgs = [];
  my $org_seen = {};
  my $metagenomespub = [];
  my $colls = [];

  if (ref($rast)) {
    my $public_metagenomes = $rast->Job->get_objects({public => 1, viewable => 1});
    foreach my $pmg (@$public_metagenomes) {
      next if ($org_seen->{$pmg->{metagenome_id}});
      $org_seen->{$pmg->{metagenome_id}} = 1;
      next unless ($avail_hash->{$pmg->{job_id}});
      push(@$metagenomespub, { label => $pmg->{name}." (".$pmg->{metagenome_id}.")", value => $pmg->{metagenome_id}, type => $pmg->{sequence_type} ? $pmg->{sequence_type} : 'unknown' });
      if (defined($pmg->{sequence_type})) {
	$seq_types->{$pmg->{sequence_type}} = 1;
      }
    }

    if ($user) {
      my @mga = $rast->Job->get_jobs_for_user_fast($user, 'view', 1);
      my $mgs = \@mga;

      # check for collections
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $user,
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
	    if ($pmg->{job_id} == $val) {
	      $pj = $pmg;
	      last;
	    }
	  }
	  unless ($pj) {
	    foreach my $mg (@$mgs) {
	      if (ref($mg) && (ref($mg) eq 'HASH')) {
		if ($mg->{job_id} == $val) {
		  $pj = $mg;
		  last;
		}
	      }
	    }
	  }
	  if ($pj) {
	    push @{$collections->{$name}}, [ $pj->{metagenome_id}, $pj->{name} ];
	  }
	}
	foreach my $coll ( sort keys %$collections ) {
	  if ( @{$collections->{$coll}} == 0 ) { next; }
	  push(@$colls, { label => $coll." [".scalar(@{$collections->{$coll}})."]", value => join('||', map { $_->[0]."##".$_->[1] } @{$collections->{$coll}}) });
	}
      }

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
  if (scalar(@$colls)) {
    push(@$all_mgs, $colls);
    push(@$groups, 'collections');
  }
  if (scalar(@$metagenomespub)) {
    push(@$all_mgs, $metagenomespub);
    push(@$groups, 'public');
  }
  
  my $seq_types_ary = [];
  @$seq_types_ary = sort keys(%$seq_types);

  return ($all_mgs, $groups, $seq_types_ary);
}

sub format_number {
  my ($val) = @_;

  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}
