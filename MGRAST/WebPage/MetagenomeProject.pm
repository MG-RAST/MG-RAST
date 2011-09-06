package MGRAST::WebPage::MetagenomeProject;

use base qw( WebPage );

use strict;
use warnings;
use Data::Dumper;
use IO::Handle;

use Global_Config;
use WebConfig;

use MGRAST::Metadata;
 
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

  # register actions
  $self->application->register_action($self, 'create_project', 'create');
  $self->application->register_action($self, 'upload_file', 'upload_file');
  $self->application->register_action($self, 'add_job_to_project', 'add_job_to_project');
  $self->application->register_action($self, 'share_project', 'share_project');
  $self->application->register_action($self, 'revoke_project', 'revoke_project');
  $self->application->register_action($self, 'delete_project', 'delete_project');

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

  my $user = $application->session->user;

  unless ($user) {
    # return "You must be logged in to view this page.";
  }

  if ($cgi->param('update') and $user) {
    $self->update_metadata();
  }

  my $html = "";

  if ($id) {
    $html .= $application->component('project_ajax')->output();
    
    my $jobdbm = $application->data_handle('MGRAST');
    
    if ($id eq "no_project"){
      return $self->no_project_job_list($jobdbm) ;
    }

    my $project = $jobdbm->Project->get_objects( { _id => $self->{project_id} } )->[0];
    unless($project and ref $project){
      $application->add_message('warning', "No project for ID:" . ($self->{project_id} || 'missing ID')  );
      return "";
    }
    
    unless ($project->public || ($user and $user->has_right(undef, 'view', 'project', $project->_id)) ) {
      $application->add_message('warning', "This is not a public project. You are lacking the rights to view this project.");
      return "<p>You are either not logged in or you have no right to view this project.</p>";
    }
    $self->{project} = $project;
    $self->{is_editor} = $user ? $user->has_right(undef, 'edit', 'project', $project->_id) : 0;
    my $metadbm = MGRAST::Metadata->new->_handle();
    
    my $all_meta = $metadbm->ProjectMD->get_objects( { project => $project } );
    my $meta_hash = {};
    %$meta_hash = map { $_->{tag} => $_->{value} } @$all_meta;
    $self->{meta_info} = $meta_hash;

    my $download  = "";
    my $down_info = $self->app->component('download_info');
    if ($project->public) {
      $down_info->add_tooltip('all_down', 'download all metagenomes for this project');
      $down_info->add_tooltip('meta_down', 'download project metadata');
      $down_info->add_tooltip('derv_down', 'download all derived data for metagenomes of this project');
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"all_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.raw.tar'  ><img src='./Html/mg-download.png' style='height:15px;'/><small>submitted metagenomes</small></a>";
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/metadata.project-$id.xml'><img src='./Html/mg-download.png' style='height:15px;'/><small>project metadata</small></a>";
      $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.processed.tar'><img src='./Html/mg-download.png' style='height:15px;'/><small>MG-RAST analysis</small></a>";
    }
    $html .= $down_info->output() . "<h1 style='display: inline;'>" . $project->name ."</h1>". $download . "";

    if ($self->{is_editor}) {
      my $share_html    = $self->share_info();
      my $edit_html     = $self->edit_info();
      my $delete_html   = $self->delete_info();
      my $add_job_html  = $self->add_job_info($project->_id);
      my $add_info_html = $self->add_info_info($project->_id);

      $html .= qq~<p><div class='quick_links'><ul>
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
  if (document.getElementById("delete_div").style.display == "none") {
    document.getElementById("delete_div").style.display = "inline";
  } else {
    document.getElementById("delete_div").style.display = "none";
  }'>Delete</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("add_job_div").style.display == "none") {
    document.getElementById("add_job_div").style.display = "inline";
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
<div style='display:none;' id='share_div'>$share_html</div>
<div style='display:none;' id='edit_div'>$edit_html</div>
<div style='display:none;' id='delete_div'>$delete_html</div>
<div style='display:none;' id='add_job_div'>$add_job_html</div>
<div style='display:none;' id='add_info_div'>$add_info_html</div>
~;
    }

    $html .= $self->general_info();
    $html .= "<h3>Metagenomes</h3><a name='jobs'></a>";
    $html .= $self->job_list();
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

  print STDERR "Projects:\n" , Dumper $projects ;

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
      next if $shown->{$project->_id};
      $shown->{$project->_id} = 1;
      my $jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
      my $id = $project->_id;
   
      push(@$data, [ $project->_id, "<a href='metagenomics.cgi?page=MetagenomeProject&project=$id'>".$project->name."</a>", ( join "," , ($project->data('PI_lastname') , $project->data('PI_firstname') ) ) , scalar(@$jobs) ]);
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
      if ($user->has_right(undef, 'edit', 'project', $existing->[0]->_id)) {
	$cgi->param('edit', 1);
	$cgi->param('project', $existing->[0]->_id);
	$application->add_message('info', "You had already created this project. It has been opened for editing.");
      } else {
	$application->add_message('warning', "You project name is already taken. Creation aborted.");
      }
    } else {
      my $pdir = $Global_Config::mgrast_projects;
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
			      data_id => $project->{_id},
			      granted => 1 } );
      $dbm->Rights->create( { application => undef,
			      scope => $user->get_user_scope,
			      name => 'edit',
			      data_type => 'project',
			      data_id => $project->{_id},
			      granted => 1 } );
      $application->add_message('info', "successfully created project $pname");
      $application->cgi->param('project', $project->{_id});
    }
  } else {
    $application->add_message('warning', "You must specify a project name. Creation aborted.");
  }
  
  return 1;
}

sub add_job_to_project {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $jobdbm = $application->data_handle('MGRAST');

  my $job_id = $cgi->param('job');
  my $project_id = $cgi->param('project');

  my $job = $jobdbm->Job->get_objects( { job_id => $job_id } )->[0];
  my $project = $jobdbm->Project->get_objects( { _id => $project_id } )->[0];

  my $existing = $jobdbm->ProjectJob->get_objects( { job => $job, project => $project } );
  if (scalar(@$existing)) {
    $application->add_message('warning', "This job is already part of this project.");
  } else {
    $jobdbm->ProjectJob->create( { job => $job, project => $project } );
    $application->add_message('info', "job added successfully");
  }

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
  my $project = $self->{project};
  my @pdata   = @{ $project->metagenomes_summary };

  if (@pdata > 0) {
    
    my $header = [ { name => 'MG-RAST ID', filter => 1 }, 	 
		   { name => 'Metagenome Name', filter => 1, sortable => 1 }, 	 
		   { name => 'Size (bp)', sortable => 1 }, 	 
		   { name => 'Biome', filter => 1, sortable => 1, operator => 'combobox' }, 	 
		   { name => 'Location', filter => 1, sortable => 1 }, 	 
		   { name => 'Country', filter => 1, sortable => 1 } ,
		 ] ;
    
    foreach my $row (@pdata) {
      my $id =  $project->id ;
      my $mid = $row->[0];
      my $download = "<table><tr align='center'>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.raw.tar.gz'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid/metadata.xml'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.processed.tar.gz'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a></td>
</tr></table>";
      # </tr><tr><td align='center'>submitted</td><td align='center'>metadata</td><td align='center'>analysis</td>
      $row->[0] = "<a href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a>";
      push @$row, $download if ($project->public);
    }
       
    push @$header ,  { name => 'Download' }  if ($project->public) ;
   
    my $ptable = $self->application->component('jobs_table');
    $ptable->columns( $header ); 
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
  my ($self, $pid) = @_;

  my $labels = [];
  my $values = [];
  my $html   = "";
  my $user   = $self->application->session->user;
  my $jobs   = $self->application->data_handle('MGRAST')->Job->get_jobs_for_user($user, 'edit', 1);

  if ($jobs && (@$jobs > 0)) {
    my $job_fs = $self->application->component('job_fs');
    $job_fs->name('job');
    $job_fs->size(10);
    $job_fs->width(400);
    
    foreach my $job ( sort { lc($a->name) cmp lc($b->name) } @$jobs ) {
      push(@$values, $job->job_id);
      my $gid = $job->metagenome_id || 0;
      push(@$labels, $job->name." (".$job->metagenome_id.")");
    }
    $job_fs->values($values);
    $job_fs->labels($labels);

    $html .= "<h3>Add Job</h3>";
    $html .= $self->start_form('add_job_form', {project => $pid, action => 'add_job_to_project'});
    $html .= $job_fs->output() . "<input type='submit' value='add' />";
    $html .= $self->end_form();
  }
  
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
  my $project_basedir = $Global_Config::mgrast_projects."/";

  # tables
  my $project_table_dir = "/tables";
  my $tdir = $project_basedir.$project_id.$project_table_dir;
  my @tables;
  my $dh;
  if (opendir($dh, $tdir)) {
    @tables = grep { -f "$tdir/$_" } readdir($dh);
    closedir $dh;
  }

  my $pdir = $Global_Config::mgrast_projects;
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
    my $project = $jobdbm->Project->get_objects( { _id => $project_id } )->[0];
    my $savedir = $Global_Config::mgrast_projects."/".$project->{id}."/".$cgi->param('upload_type')."s/";
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
  #return [ [ 'view', 'project', $self->application->cgi->param('project') ] ];
}

sub update_metadata {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metadbm = MGRAST::Metadata->new->_handle();
  my $jobdbm = $self->application->data_handle('MGRAST');

  unless ($metadbm && $jobdbm) {
    return "could not connect to database";
  }

  my $project = $jobdbm->Project->get_objects( { _id => $cgi->param('project') } )->[0];

  my $user = $self->application->session->user;
  unless ($user && $user->has_right(undef, 'edit', 'project', $project->_id)) {
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
  
  $content .= $self->start_form('additional_info_form', { update => 1, project => $project->{_id} });
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
  $content .= $self->start_form('delete_project', { project => $project->_id,
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
  my $content = "<h3>Share</h3>";
  $content .= $self->start_form('share_project', { project => $project->_id,
						   action  => 'share_project' });
  $content .= "<p><strong>Enter an email address or group name:</strong> <input name='email' type='textbox' value='$email'><input type='checkbox' name='editable'> <span title='check to allow the user or group to edit this project'>editable</span>";
  $content .= "&nbsp;&nbsp;&nbsp;<input type='submit' name='share_project' value=' Share project with this user or group '></p>";
  $content .= $self->end_form;
  
  # show people who can see this job at the moment
  $content .= "<p id='section_bar'><strong>This project is currently available to:</strong></p>";
  my $rights_view = $self->application->dbmaster->Rights->get_objects( { name => 'view',
									 data_type => 'project',
									 data_id => $project->_id
								       });

  my $rights_edit = $self->application->dbmaster->Rights->get_objects( { name => 'edit',
									 data_type => 'project',
									 data_id => $project->_id
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
    }
    if($r->delegated) {
      $content .= "<td>".$self->start_form('revoke_project', { project => $project->_id, 
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
  
  unless($found_one) {
    $content .= "<tr><td>This project is not shared with anyone at the moment.</td></tr>";
  }
  $content .= '</table>';

  if (scalar(@$tokens)) {
    $content .= "<p id='section_bar'><img src='./Html/rast-info.png'/>invitations which have not been claimed yet:</p>";
    $content .= "<table>";
    foreach my $token (@$tokens) {
      my ($uid, $date, $email) = $token->description =~ /^token_scope\|from_user\:(\d+)\|init_date:(\d+)\|email\:(.+)/;
      my $u = $self->application->dbmaster->User->get_objects( { _id => $uid } )->[0];
      my $t = localtime($date);
      my ($token_id) = $token->name =~ /^token\:(.+)$/;
      $content .= "<tr><td>sent by ".$u->firstname." ".$u->lastname." to $email on $t <input type='button' onclick='window.top.location=\"metagenomics.cgi?page=MetagenomeProject&project=".$project->_id."&action=cancel_token&token=$token_id\"' value='cancel'></td></tr>";
    }
    $content .= "</table>";
  }

  return $content;
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
  my $project = $jobdbm->Project->get_objects( { _id => $cgi->param('project') } )->[0];
  my $project_name = $project->name;
  my $project_id = $project->_id;

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
  my $project = $jobdbm->Project->get_objects( { _id => $cgi->param('project') } )->[0];
  my $project_name = $project->name;
  my $project_id = $project->_id;

  # check email format
  my $email = $cgi->param('email');
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

  $self->app->add_message('info', "Revoked the right to view this project from ".$scope->name_readable.".");

  return 1;

}

# get all jobs without project and display them for download
sub no_project_job_list{
  my ($self , $dbm) = @_;

  $self->title('Metagenomes not associated with any project');
# select metagenome_id , _id , public from Job where Job.public = 1 and not exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id );
  my $statement = "select metagenome_id , _id , public from Job where Job.public = 1 and not exists (select ProjectJob.job from ProjectJob where ProjectJob.job = Job._id )";
  my $data = $dbm->Job->without_project();

  my $content = ""  ;
  my $id      = '0' ;

  my @pdata = map { [ $_->[0] , $_->[1] , $_->[3] , $_->[2] ] } @$data ;

  if (@pdata > 0) {
    
    my $header = [ { name => 'MG-RAST ID', filter => 1 }, 	 
		   { name => 'Metagenome Name', filter => 1, sortable => 1 }, 	
		   { name => 'File size', sortable => 1 }, 
		   { name => 'Sequence type', filter => 1, sortable => 1, operator => 'combobox' }, 
		 ] ;
    push @$header ,  { name => 'Download' } ;

    foreach my $row (@pdata) {
    
      my $mid = $row->[0];
      my $download = "<table><tr align='center'>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.raw.tar.gz'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid/metadata.xml'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a></td>
<td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.processed.tar.gz'><img src='$Global_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a></td>
</tr></table>";
      # </tr><tr><td align='center'>submitted</td><td align='center'>metadata</td><td align='center'>analysis</td>
      $row->[0] = "<a href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a>";
      push @$row, $download ;
    }
       
   
   
    my $ptable = $self->application->component('jobs_table');
    $ptable->columns( $header ); 
    $ptable->width(800);
    #$ptable->show_export_button({title => "Export Jobs Table", strip_html => 1});
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


  return "<h1>all jobs</h1>";
}


sub format_number {
  my ($val) = @_;

  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}

  return $val;
}
