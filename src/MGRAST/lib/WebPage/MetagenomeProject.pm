package MGRAST::WebPage::MetagenomeProject;

use base qw( WebPage );

use strict;
use warnings;
use Data::Dumper;
use IO::Handle;
use File::Temp qw/ tempfile tempdir /;
use JSON;
use HTML::Entities;

use Conf;
use WebConfig;

use MGRAST::Metadata;
use MGRAST::Analysis;
 
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
  $self->application->register_component('ListSelect', 'job_select');
  $self->application->register_component('ListSelect', 'shared_job_select');
  $self->application->register_component('ListSelect', 'public_job_select');

  # register actions
  $self->application->register_action($self, 'create_project', 'create');
  $self->application->register_action($self, 'upload_file', 'upload_file');
  $self->application->register_action($self, 'download_md', 'download_md');
  $self->application->register_action($self, 'upload_md', 'upload_md');
  $self->application->register_action($self, 'add_job_to_project', 'add_job_to_project');
  $self->application->register_action($self, 'share_project', 'share_project');
  $self->application->register_action($self, 'revoke_project', 'revoke_project');
  $self->application->register_action($self, 'delete_project', 'delete_project');
  $self->application->register_action($self, 'change_shared_metagenomes', 'change_shared_metagenomes');
  $self->application->register_action($self, 'make_project_public', 'make_project_public');
  $self->application->register_action($self, 'cancel_token', 'cancel_token');

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
    my $project = $jobdbm->Project->init({ id => $self->{project_id} });
    unless($project and ref $project){
      $application->add_message('warning', "No project for ID:" . ($self->{project_id} || 'missing ID')  );
      return "";
    }
    
    unless ($project->public || ($user and $user->has_right(undef, 'view', 'project', $project->id)) ) {
      $application->add_message('warning', "This is not a public project. You are lacking the rights to view this project.");
      my $should_have_right = "";
      if ($user) {
	my $ua = $ENV{HTTP_USER_AGENT};
	$ua =~ s/\s/\%20/g;
	$should_have_right = "<br><p style='width: 800px;'>If you think this project should be public or you should be able to view it, please send us a message using this <a href='mailto:mg-rast\@mcs.anl.gov?subject=Access%20Privileges&amp;body=%0D%0A%0D%0A%0D%0A%0D%0A_____%0D%0A%0D%0Aproject%20id:%20".$self->{project_id}."%0D%0Auser:%20".$user->login."%0D%0Apage:%20".$cgi->param('page')."%0D%0Abrowser:%20".$ua."%0D%0A%0D%0A'>link</a></p>";
      }

      return "<p>You are either not logged in or you have no right to view this project.</p>".$should_have_right;
    }
    
    my $all_meta  = $metadbm->ProjectMD->get_objects( { project => $project } );
    my $meta_hash = {};
    %$meta_hash   = map { $_->{tag} => $_->{value} } @$all_meta;
    $self->{meta_info} = $meta_hash;
    $self->{project}   = $project;    
    $self->{is_editor} = 0;
    if ($user && ($user->has_right(undef, 'edit', 'project', $project->id) || $user->has_star_right('edit', 'project'))) {
      $self->{is_editor} = 1;
    }
    
    my $proj_link = $Conf::cgi_url."linkin.cgi?project=".$self->{project_id};
    $html .= "<h1 style='display: inline;'>".$project->name.(($user and $user->has_right(undef, 'edit', 'user', '*')) ? " <span style='color: blue;'>(ID ".$project->id.")</span>": "")."</h1>";
    $html .= "<p><table>";
    $html .= "<tr><td><b>Visibility</b></td><td style='padding-left:15px;'>".($project->public ? 'Public' : 'Private')."</td></tr>";
    $html .= "<tr><td><b>Static Link</b></td><td style='padding-left:15px;'>".($project->public ? "<a href='$proj_link'>$proj_link</a>" : "You need to <a href=# onclick='document.getElementById(\"make_public_link\").click();'>make this project public</a> to publicly link it.")."</td></tr></table>";

    if ($self->{is_editor}) {
      my $editable_jobs = 0;
      my %mg_rights = map { $_, 1 } @{ $user->has_right_to(undef, 'edit', 'metagenome') };      
      foreach my $mgid ( @{$project->metagenomes(1)} ) {
	if (exists($mg_rights{'*'}) || exists($mg_rights{$mgid})) {
	  $editable_jobs += 1;
	}
      }
      my $delete_div    = $project->public ? '' : "<div style='display:none;' id='delete_div'>".$self->delete_info()."</div>";
      my $share_html    = $self->share_info();
      my $edit_html     = $self->edit_info();
      my $add_md_html   = $editable_jobs ? $self->add_md_info($project->id) : '';

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
    if (document.getElementById("add_job_div").innerHTML == "") {
      execute_ajax("make_public_info", "public_div", "project=$id");
    }
  } else {
    document.getElementById("public_div").style.display = "none";
  }' id='make_public_link'>Make Public</a></li>~;
      } else {
	# if (exists $meta_hash->{ebi_submission}) {
	#   if ($meta_hash->{ebi_submission} eq 'submitted') {
	#     $html .= qq~<li><a>project </a></li>~;	  
	#   } else {
	#     $html .= qq~<li><a>EBI submission in progress</a></li>~;
	#   }
	# } else {
	#   $html .= qq~<li><a style='cursor:pointer;' onclick='submitToEBI();'>Submit to EBI</a></li>~;
	# }
      }
      $html .= qq~
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("share_div").style.display == "none") {
    document.getElementById("share_div").style.display = "inline";
  } else {
    document.getElementById("share_div").style.display = "none";
  }'>Share Project</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("add_job_div").style.display == "none") {
    document.getElementById("add_job_div").style.display = "inline";
    if (document.getElementById("add_job_div").innerHTML==""){execute_ajax("add_job_info", "add_job_div", "project=$id");}
  } else {
    document.getElementById("add_job_div").style.display = "none";
  }'>Add Jobs</a></li>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("edit_div").style.display == "none") {
    document.getElementById("edit_div").style.display = "inline";
  } else {
    document.getElementById("edit_div").style.display = "none";
  }'>Edit Project Data</a></li>~;
      if ($editable_jobs) {
	$html .= qq~
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("add_md_div").style.display == "none") {
    document.getElementById("add_md_div").style.display = "inline";
  } else {
    document.getElementById("add_md_div").style.display = "none";
  }'>Upload MetaData</a></li>~;
      }
      $html .= qq~
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("export_md_div").style.display == "none") {
    document.getElementById("export_md_div").style.display = "inline";
  } else {
    document.getElementById("export_md_div").style.display = "none";
  }'>Export MetaData</a></li>
</ul></div></p>
$delete_div
<div style='display:none;' id='public_div'></div>
<div style='display:none;' id='share_div'>$share_html</div>
<div style='display:none;' id='add_job_div'></div>
<div style='display:none;' id='edit_div'>$edit_html</div>
<img src='./Html/clear.gif' onload='execute_ajax("export_metadata", "export_md_div", "project=$id");'>
<div style='display:none;' id='export_md_div'></div>~;
      $html .= $editable_jobs ? "<div style='display:none;' id='add_md_div'>$add_md_html</div>" : "";
    } else {
      $html .= qq~<p><div class='quick_links'><ul>
<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("export_md_div").style.display == "none") {
    document.getElementById("export_md_div").style.display = "inline";
  } else {
    document.getElementById("export_md_div").style.display = "none";
  }'>Export MetaData</a></li>
</ul></div></p>
<img src='./Html/clear.gif' onload='execute_ajax("export_metadata", "export_md_div", "project=$id");'>
<div style='display:none;' id='export_md_div'></div>~;
    }

    my $jobs = $project->metagenomes(1);
    $html .= $self->general_info();
    if (@$jobs > 0) {
      $html .= "<h3>Metagenomes</h3><a name='jobs'></a>";
      $html .= "<img src='./Html/clear.gif' onload='execute_ajax(\"job_list\", \"job_list_div\", \"project=$id\");'><div id='job_list_div'></div>";
    }
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

  my $content = "<h3>select a project to view</h3>";
  my $jobdbm  = $application->data_handle('MGRAST');
  my $public_projects  = $jobdbm->Project->get_objects( {public => 1} );
  my $private_proj_ids = ($user) ? $user->has_right_to(undef, 'view', 'project') : [];
  my $private_projects = [];

  if (@$private_proj_ids && ($private_proj_ids->[0] eq '*')) {
    $private_projects = $jobdbm->Project->get_objects();
  } else {
    foreach my $pid (@$private_proj_ids) {
      push @$private_projects, @{ $jobdbm->Project->get_objects({id => $pid}) };
    }
  }

  if ( scalar(@$private_projects) || scalar(@$public_projects) ) {
    my $table = $application->component('project_table');
    $table->items_per_page(25);
    $table->show_top_browse(1);
    $table->width(800);
    $table->columns( [ { name => 'id' , filter => 1 , sortable => 1},
		       { name => 'project' , filter => 1 , sortable => 1},
		       { name => 'contact' , filter => 1 , sortable => 1},
		       { name => 'jobs' , filter => 1  , sortable =>  1} ] );
    my $data  = [];
    my $shown = {};
    foreach my $project ((@$private_projects, @$public_projects)) {
      next if $shown->{$project->id};
      $shown->{$project->id} = 1;
      my $jobs  = $jobdbm->ProjectJob->get_objects( {project => $project} );
      my $pid   = $project->id;
      my $pdata = $project->data;
      my $name  = $pdata->{PI_lastname} ? $pdata->{PI_lastname}.($pdata->{PI_firstname} ? ', '.$pdata->{PI_firstname} : '') : '';
      push(@$data, [ $pid, "<a href='metagenomics.cgi?page=MetagenomeProject&project=$pid'>".$project->name."</a>", $name, scalar(@$jobs) ]);
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
  if ($user) {
    $content .= "<p><a onclick='document.getElementById(\"create_div\").style.display=\"inline\"' style='cursor: pointer;'>create new project</a></p>";
    $content .= "<div id='create_div' style='display: none;'>".$self->start_form('new_project_form', { action => 'create' })."<table><tr><td>project name</td><td><input type='text' name='pname'>$collection</td></tr><tr><td colspan=2><input type='submit' value='create'></td></tr></table>".$self->end_form()."</div>";
  }
  return $content;
}

sub create_project {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi   = $application->cgi();
  my $user  = $application->session->user();
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
      my $project = $pdbm->Project->create_project($user, $pname);
      unless ($project && ref($project)) {
	$application->add_message('warning', "Error creating the project. Creation aborted.");
      }
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

  my (@old, @new);
  foreach my $mg (@mg_ids) {
    my $job = $jobdbm->Job->init({ metagenome_id => $mg });
    my $msg = $project->add_job($job);

    if ($msg =~ /error/i) {
      push @old, $job->metagenome_id;
    } else {
      push @new, $job->metagenome_id;
    }
  }

  my $html = "<blockquote>";
  if (@new > 0) {
    $html .= "<img src='./Html/clear.gif' onload='execute_ajax(\"job_list\", \"job_list_div\", \"project=$proj_id\");'>";
    $html .= "<p>The following metagenomes have been added to or are already in project ".$project->name.":<br>".join(", ", @new)."</p>";
  }
  if (@old > 0) {
    $html .= "<p>The following metagenomes could not be added because they are already in a different project:<br>".join(", ", @old)."</p>";
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
  my $description = $meta_info->{project_description} ||  $meta_info->{study_abstract} || " - ";
  my $funding = $meta_info->{project_funding} || " - ";
  my $admin = ($meta_info->{PI_firstname} || "")." ".($meta_info->{PI_lastname} || "");
  my $tech = ($meta_info->{firstname} || "")." ".($meta_info->{lastname} || "");

  if ($meta_info->{PI_email}) {
    $admin .= $meta_info->{PI_email} ? " (".$meta_info->{PI_email}.")": "";
  }
  if ($meta_info->{email}) {
    $tech .= $meta_info->{email} ? " (".$meta_info->{email}.")": "";
  }

  if ($meta_info->{PI_organization}) {
    my $pi_org = $meta_info->{PI_organization};
    if ($meta_info->{PI_organization_url}) {
      $meta_info->{PI_organization_url} = ($meta_info->{PI_organization_url} =~ /^http:\/\//) ? $meta_info->{PI_organization_url} : "http://".$meta_info->{PI_organization_url};
      $pi_org .= " (".$meta_info->{PI_organization_url}.")";
    }
    $admin .= "<br>$pi_org<br>".($meta_info->{PI_organization_address} || "").", ".($meta_info->{PI_organization_country} || "");
  }

  if ($meta_info->{organization}) {
    my $tech_org = $meta_info->{organization};
    if ($meta_info->{organization_url}) {
      $meta_info->{organization_url} = ($meta_info->{organization_url} =~ /^http:\/\//) ? $meta_info->{organization_url} : "http://".$meta_info->{organization_url};
      $tech_org .= " (".$meta_info->{organization_url}.")";
    }
    $tech .= "<br>$tech_org<br>".($meta_info->{organization_address} || "").", ".($meta_info->{organization_country} || "");
  }
  
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

  my $content  = "";
  my $proj_id  = $self->application->cgi->param('project');
  my $project  = $self->application->data_handle('MGRAST')->Project->init({ id => $proj_id });
  my $pdata    = $project->metagenomes_summary;
  my @complete = map { [ @$_[0..11] ] } grep { $_->[12] } @$pdata;
  my @inprogess = map { $_->[0] } grep { ! $_->[12] } @$pdata;

  unless (@$pdata > 0) {
    return "<p>There are currently no metagenomes assigned to this project.</p>";
  }

  if (@complete > 0) {
    my @c_mgids  = map { $_->[0] } @complete;
    my $metadata = $self->data('mddb')->get_metadata_for_tables(\@c_mgids, 1, 1);
    my $header   = [ { name => 'MG-RAST ID', filter => 1, visible => ($project->public ? 1 : 0) }, 	 
		     { name => 'Metagenome Name', filter => 1, sortable => 1 },
		     { name => 'bp Count', sortable => 1, filter => 1, operators => ['less','more'] },
		     { name => 'Sequence Count', sortable => 1, filter => 1, operators => ['less','more'] },
		     { name => 'Biome', filter => 1, sortable => 1, operator => 'combobox' },
		     { name => 'Feature', filter => 1, sortable => 1, operator => 'combobox' },
		     { name => 'Material', filter => 1, sortable => 1, operator => 'combobox' },
		     { name => 'Location', filter => 1, sortable => 1 }, 	 
		     { name => 'Country', filter => 1, sortable => 1 },
		     { name => 'Coordinates', filter => 1, sortable => 1 },
		     { name => 'Sequence Type', filter => 1, sortable => 1, operator => 'combobox' },
		     { name => 'Sequence Method', filter => 1, sortable => 1, operator => 'combobox' }
		   ];
    foreach my $row (@complete) {
      my $mid = $row->[0];
      my $mfile = "mgm".$mid.".metadata.txt";
      if (exists($metadata->{$mid}) && open(FH, ">".$Conf::temp."/".$mfile)) {
	foreach my $line (@{$metadata->{$mid}}) {
	  print FH join("\t", @$line)."\n";
	}
	close FH;
      }
      $row->[0] = "<a target=_blank href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a>";
      $row->[1] = "<a target=_blank href='?page=MetagenomeOverview&metagenome=$mid'>".$row->[1]."</a>";
    }
   
    my $ptable = $self->application->component('jobs_table');
    $ptable->columns($header); 
    $ptable->width(800);
    $ptable->show_export_button({title => "Export Jobs Table", strip_html => 1});

    if ( scalar(@complete) > 50 ) {
      $ptable->show_top_browse(1);
      $ptable->show_bottom_browse(1);
      $ptable->items_per_page(50);
      $ptable->show_select_items_per_page(1); 
    }
    $ptable->data(\@complete);

    if (scalar(@inprogess) == 0) {
      $content .= "<p>There are ".scalar(@$pdata)." metagenomes in this project.</p>";
    } else {
      $content .= "<p>There are ".scalar(@$pdata)." metagenomes in this project<br>".scalar(@inprogess)." are still in progress: ".join(", ", @inprogess)."</p>";
    }
    $content .= $ptable->output();
  } else {
    $content .= "<p>There are ".scalar(@$pdata)." metagenomes in this project, all of them are still in progress:<br>".join(", ", @inprogess)."</p>";
  }
  
  return $content;
}

sub export_metadata {
  my ($self) = @_;

  my $html  = "<h3>Export MetaData</h3>";
  my $json  = new JSON;
  $json = $json->utf8();
  my $pid   = $self->application->cgi->param('project');
  my $base  = "mgp".$pid."_metadata";
  my $jfile = $Conf::temp."/".$base.".json";
  my $mfile = $Conf::temp."/".$base.".xlsx";
  my $proj  = $self->application->data_handle('MGRAST')->Project->init({ id => $pid });
  my $pdata = $self->data('mddb')->export_metadata_for_project($proj, 0);

  open(JFH, ">$jfile") || return "<p>ERROR: Could not write results to file: $!</p>";
  print JFH $json->encode($pdata);
  close JFH;
  my $cmd = $Conf::export_metadata." -j $jfile -o $mfile";
  unless (system($cmd) == 0) {
    return $html."<p>ERROR: Could not transform metadata to excel format: $!</p>";
  }

  ## validate
  my ($is_valid, $mdata, $log) = $self->data('mddb')->validate_metadata($mfile);

  unless ($is_valid) {
    $pdata = $self->data('mddb')->export_metadata_for_project($proj, 1);
    open(JFH, ">$jfile") || return "<p>ERROR: Could not write results to file: $!</p>";
    print JFH $json->encode($pdata);
    close JFH;
    $cmd = $Conf::export_metadata." -j $jfile -o $mfile";
    unless (system($cmd) == 0) {
      return $html."<p>ERROR: Could not transform metadata to excel format: $!</p>";
    }
  }
  $html .= "<p><b>click to download: </b><a href='metagenomics.cgi?page=MetagenomeProject&action=download_md&filetype=xlsx&filename=$base.xlsx'>MG-RAST metadata file</a></p>";
  unless ($is_valid) {
    $html .= "<p><font color='red'>This metadata file is currently invalid:</font><br><pre>$log</pre></p>";
  }
  return $html;
}

sub download_md {
  my ($self) = @_;

  my $cgi   = $self->application->cgi;
  my $file  = $cgi->param('filename');
  my $ftype = $cgi->param('filetype') || 'text';
  my $ctype = ($ftype eq 'xlsx') ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'text/plain';
  
  if (open(FH, "<".$Conf::temp."/".$file)) {
    my $content = do { local $/; <FH> };
    close FH;
    print "Content-Type:$ctype\n";  
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=".$file."\n\n";
    print $content;
    exit;
  } else {
    $self->application->add_message('warning', "Could not open download file");
  }
  return 1;
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
  $html .= "<h3>Add Jobs</h3><div id='list_select_div'>" . $list_select->output();
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

sub add_md_info {
  my ($self, $pid) = @_;
  
  my $html = "<h3>Add / Reload MetaData</h3>";
  $html .= $self->start_form('upload_form', {project => $pid, action => 'upload_md'});
  $html .= "Map metagenome to metadata by: <select name='map_type'><option value='name'>Metagenome Name</option><option value='id'>Metagenome ID</option></select>";
  $html .= "<br><br><input type='file' name='upload_md' size ='38'><span>&nbsp;&nbsp;&nbsp;</span><input type='submit' value='upload'>";
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
  my $project_basedir = $Conf::mgrast_projects."/";

  # tables
  my $project_table_dir = "/tables";
  my $tdir = $project_basedir.$project_id.$project_table_dir;
  my @tables;
  my $dh;
  if (opendir($dh, $tdir)) {
    @tables = grep { -f "$tdir/$_" } readdir($dh);
    closedir $dh;
  }

  my $pdir = $Conf::mgrast_projects;
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

sub upload_md {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi  = $application->cgi;
  my $user = $application->session->user;
  my $mgdb = $application->data_handle('MGRAST');
  my $meta = $self->data('mddb');
  my $pid  = $cgi->param('project');
  my $skip = $cgi->param('skip') || 0;
  my $map_by_id = ($cgi->param('map_type') && ($cgi->param('map_type') eq 'id')) ? 1 : 0;

  if ($user->has_right(undef, 'edit', 'project', $pid)) {
    my ($tmp_hdl, $tmp_name) = tempfile("metadata_XXXXXXX", DIR => $Conf::temp, SUFFIX => '.xlsx');
    my $fname = $cgi->param('upload_md') || "<broken upload>";
    my $fhdl  = $cgi->upload('upload_md');
    if (defined $fhdl) {
      while (<$fhdl>) { print $tmp_hdl $_; }
      close $tmp_hdl;
      close $fhdl;
    } else {
      $application->add_message('warning', "could not save / find file: $fname");
      return 0;
    }
    ## validate
    my ($is_valid, $mdata, $log) = $meta->validate_metadata($tmp_name, $skip, $map_by_id);
    unless ($is_valid) {
      $application->add_message('warning', "uploaded metadata file is invalid, no metadata has been updated:<br><pre>".$log."</pre>");
      return 0;
    }
    my $skip_jobs = [];
    my $edit_jobs = [];
    my $project   = $mgdb->Project->init({id => $pid});
    my %mg_rights = map { $_, 1 } @{ $user->has_right_to(undef, 'edit', 'metagenome') };

    foreach my $pj ( @{ $mgdb->ProjectJob->get_objects({project => $project}) } ) {
      my $job = $pj->job;
      if (exists($mg_rights{'*'}) || exists($mg_rights{$job->metagenome_id})) {
	push @$edit_jobs, $job;
      } else {
	push @$skip_jobs, $job;
      }
    }
    if (@$edit_jobs == 0) {
      $application->add_message('warning', 'you do not have the permissions to add metadata to any job in this project');
      return 0;
    }
    if (@$skip_jobs > 0) {
      $application->add_message('warning', "you do not have the permissions to add metadata to the following jobs:<br>".join(", ", sort map {$_->metagenome_id} @$skip_jobs));
    }
    
    my (undef, $md_jobs, $err_msgs) = $meta->add_valid_metadata($user, $mdata, $edit_jobs, $project, $map_by_id, 1);
    if ((@$md_jobs == @$edit_jobs) && (@$skip_jobs == 0)) {
      $application->add_message('info', "successfully added / updated metadata to all jobs in this project");
    }
    elsif (@$md_jobs == @$edit_jobs) {
      $application->add_message('info', "successfully added / updated metadata to the following jobs:<br>".join(", ", sort map {$_->metagenome_id} @$edit_jobs));
    }
    elsif ((@$md_jobs == 0) && (@$skip_jobs == 0)) {
      $application->add_message('warning', "unable to add metadata to any job in this project:<blockquote>".join("<br>", @$err_msgs)."</blockquote>");
      return 0;
    }
    elsif (@$md_jobs == 0) {
      $application->add_message('warning', "unable to add metadata to the following jobs:<br>".join(", ", sort map {$_->metagenome_id} @$edit_jobs)."<blockquote>".join("<br>", @$err_msgs)."</blockquote>");
      return 0;
    }
    else {
      my %md_map = map { $_->metagenome_id, 1 } @$md_jobs;
      my @no_md  = grep { ! exists $md_map{$_} } map {$_->metagenome_id} @$edit_jobs;
      $application->add_message('warning', "unable to add metadata to the following jobs:<br>".join(", ", sort @no_md)."<blockquote>".join("<br>", @$err_msgs)."</blockquote>");
      $application->add_message('info', "successfully added/updated metadata to the following jobs:<br>".join(", ", sort map {$_->metagenome_id} @$md_jobs));
    }
  } else {
    $application->add_message('warning', 'you do not have the permissions to add metadata to this project');
    return 0;
  }
  return 1;
}

sub upload_file {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi  = $application->cgi;
  my $user = $application->session->user;

  my $project_id = $cgi->param('project');
  if ($user->has_right(undef, 'edit', 'project', $project_id)) {
    my $jobdbm = $application->data_handle('MGRAST');
    my $project = $jobdbm->Project->init({ id => $project_id });
    my $savedir = $Conf::mgrast_projects."/".$project->{id}."/".$cgi->param('upload_type')."s/";
    my $filename = $cgi->param('upload_file') || "<broken upload>";
    my $fh = $cgi->upload('upload_file');
    if (defined $fh) {
      if (open(OUTFILE, ">".$savedir.$filename)) {
	while (<$fh>) { print OUTFILE $_; }
	close OUTFILE;
	close $fh;
	chmod 0777, $savedir.$filename;
	$application->add_message('info', "$filename uploaded successfully");
      } else {
	$application->add_message('warning', "could not save / find file: $filename");
	return 0;
      }
    } else {
      $application->add_message('warning', "could not save / find file: $filename");
      return 0;
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
  my $content   = "<h3>Edit Project Data</h3>";
  
  $content .= $self->start_form('additional_info_form', { update => 1, project => $project->{id} });
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>name</span><br><input type='text' name='project_name' style='width:250px;' value='".encode_entities($project->{name})."'><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>description</span><br><textarea name='project_description' style='width:250px;'>".encode_entities($meta_info->{project_description} || $meta_info->{study_abstract} || "")."</textarea><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>funding source</span><br><input type='text' value='".encode_entities($meta_info->{project_funding} || "")."' name='project_funding'><br><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>administrative contact</span><br><table><tr><th>eMail</th><td><input type='text' value='".encode_entities($meta_info->{PI_email} || "")."' name='pi_email'></td></tr><tr><th>firstname</th><td><input type='text' value='".encode_entities($meta_info->{PI_firstname} || "")."' name='pi_firstname'></td></tr><tr><th>lastname</th><td><input type='text' value='".encode_entities($meta_info->{PI_lastname} || "")."' name='pi_lastname'></td></tr><tr><th>organization</th><td><input type='text' value='".encode_entities($meta_info->{PI_organization} || "")."' name='pi_organization'></td></tr><tr><th>organization url</th><td><input type='text' value='".encode_entities($meta_info->{PI_organization_url} || "")."' name='pi_organization_url'></td></tr><tr><th>organization address</th><td><input type='text' value='".encode_entities($meta_info->{PI_organization_address} || "")."' name='pi_organization_address'></td></tr><tr><th>organization country</th><td><input type='text' value='".encode_entities($meta_info->{PI_organization_country} || "")."' name='pi_organization_country'></td></tr></table><br>";
  $content .= "<span style='font-size: 14px; font-family: Arial; color: #273E53; font-weight: bold; font-style: italic;'>technical contact</span><br><table><tr><th>eMail</th><td><input type='text' value='".encode_entities($meta_info->{email} || "")."' name='email'></td></tr><tr><th>firstname</th><td><input type='text' value='".encode_entities($meta_info->{firstname} || "")."' name='firstname'></td></tr><tr><th>lastname</th><td><input type='text' value='".encode_entities($meta_info->{lastname} || "")."' name='lastname'></td></tr><tr><th>organization</th><td><input type='text' value='".encode_entities($meta_info->{organization} || "")."' name='organization'></td></tr><tr><th>organization url</th><td><input type='text' value='".encode_entities($meta_info->{organization_url} || "")."' name='organization_url'></td></tr><tr><th>organization address</th><td><input type='text' value='".encode_entities($meta_info->{organization_address} || "")."' name='organization_address'></td></tr><tr><th>organization country</th><td><input type='text' value='".encode_entities($meta_info->{organization_country} || "")."' name='organization_country'></td></tr><tr><td colspan=2><input type='submit' value='update'></td><tr></table>";    
  $content .= $self->end_form;

  return $content;
}

sub delete_info {
  my ($self) = @_;

  my $project = $self->{project};
  my $jobdbm  = $self->application->data_handle('MGRAST');  
  my $jobnum1 = $jobdbm->ProjectJob->get_objects({project => $project});
  my $jobnum2 = $jobdbm->Job->get_objects({primary_project => $project});
  my $content = "<h3>Delete</h3>";

  if ( (scalar(@$jobnum1) > 0) || (scalar(@$jobnum2) > 0) ) {
    $content .= "<p>This project contains jobs and can thus not be deleted.</p>";
  } else {
    $content .= $self->start_form('delete_project', { project => $project->id,
						    action  => 'delete_project' });
    $content .= "<p><strong>To really delete this project, type 'DELETE' into the textbox and click 'delete project'. This will delete the project and all associated metadata.</strong> <input name='confirmation' type='textbox'>";
    $content .= "&nbsp;&nbsp;&nbsp;<input type='submit' name='delete_project' value='delete project'></p>";
    $content .= $self->end_form;
  }

  return $content;
}

sub share_info {
  my ($self) = @_;

  my $email   = $self->app->cgi->param('email') || '';
  my $project = $self->{project};
  my $jobdbm  = $self->application->data_handle('MGRAST');
  my $content = "<h3>Share Project</h3>";
  $content .= $self->start_form('share_project', { project => $project->id,
						   action  => 'share_project' });
  $content .= "<p><strong>Enter an email address:</strong> <input name='email' type='textbox' value='".encode_entities($email)."'><input type='checkbox' name='editable'> <span title='check to allow the user to edit this project'>editable</span>";
  $content .= "&nbsp;&nbsp;&nbsp;<input type='submit' name='share_project' value=' Share project with this user '></p>";
  $content .= $self->end_form;

  $content .= $self->start_form('reviewer_access', { project => $project->id,
						     reviewer => 1,
						     action  => 'share_project' });
  $content .= "<p><input type='submit' value=' Create a Reviewer Access Token '></p>";
  $content .= $self->end_form();
  
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
      my ($token_id) = $token->name =~ /^token\:(.+)$/;
      if ($token->description =~ /^Reviewer_/) {
	my $num = scalar(@{$self->application->dbmaster->UserHasScope->get_objects({ scope => $token })});
	$content .= "<tr><td>Reviewer Token <b>".$WebConfig::APPLICATION_URL."?page=ClaimToken&token=$token_id&type=project</b> - currently registered by $num reviewers. <input type='button' onclick='window.top.location=\"metagenomics.cgi?page=MetagenomeProject&project=".$project->id."&action=cancel_token&token=$token_id\"' value='cancel'></td></tr>";
      } else {
	my ($uid, $date, $email) = $token->description =~ /^token_scope\|from_user\:(\d+)\|init_date:(\d+)\|email\:(.+)/;
	my $u = $self->application->dbmaster->User->get_objects( { _id => $uid } )->[0];
	my $t = localtime($date);
	$content .= "<tr><td>sent by ".$u->firstname." ".$u->lastname." to $email on $t <input type='button' onclick='window.top.location=\"metagenomics.cgi?page=MetagenomeProject&project=".$project->id."&action=cancel_token&token=$token_id\"' value='cancel'></td></tr>";
      }
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

  my $uhs = $master->UserHasScope->get_objects( { scope => $scope->[0] } );
  foreach my $u (@$uhs) {
    $u->delete();
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
    $project->delete_project($user);
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
  
  my $mddb = $self->data('mddb');
  my $publicizable = [];
  my $missing_mixs = [];
  my $missing_rights = [];
  foreach my $pj (@$project_jobs) {
    my $job = $pj->job;
    if ($user->has_right(undef, 'edit', 'metagenome', $job->metagenome_id)) {
      if ($mddb->is_job_compliant($job)) {
	push @$publicizable, $job;
      } else {
	push @$missing_mixs, $job;
      }
    } else {
      push @$missing_rights, $job;
    }
  }

  my $html = "<h3>Make Project Public</h3>";

  if (@$missing_mixs > 0) {
    $html .= "<p style='font-variant: normal;'>MG-RAST has implemented the use of <a href='http://gensc.org/gc_wiki/index.php/MIxS' target=_blank >Minimum Information about any (X) Sequence</a> (MIxS) developed by the <a href='http://gensc.org' target=_blank >Genomic Standards Consortium</a> (GSC). Metagenomes that are missing MIxS metadata cannot be made public. The below list shows which metagenomes associated with this project are missing MIxS metadata. Use the above 'Upload MetaData' button to upload a valid metadata spreadsheet. You can obtain a metadata spreadsheet by either downloading the current metadata for this project (using the 'Export Metadata' button), or by filling out a <a href='ftp://".$Conf::ftp_download."/data/misc/metadata/".$Conf::mgrast_metadata_template."'>metadata spreadsheet template</a>.</p>";
    $html .= "<blockquote>".join("<br>", map { $_->{name}." (".$_->{metagenome_id} .")"} @$missing_mixs)."</blockquote>";
  }
  
  if (@$missing_rights > 0) {
    $html .= "<p style='font-variant: normal;'>When making metagenomes public you must have edit rights. The below metagenomes are unable to be made public due to missing rights.</p>";
    $html .= "<blockquote>".join("<br>", map { $_->{name}." (".$_->{metagenome_id} .")"} @$missing_rights)."</blockquote>";
  }

  $html .= "<p style='font-variant: normal;'>When you make a project public, you should consider making the metagenomes belonging to the project public as well. The below list shows which metagenomes associated with this project can be made public.</p>";
  if (@$publicizable > 0) {
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

    $html .= "<p style='font-variant: normal;'><b>Warning:</b> Making data publicly available is final and cannot be undone.</p>";
    $html .= $self->start_form('makepublicform', { project => $project->id, action => 'make_project_public' });
    $html .= $list_select->output();
#    $html .= "<input type='checkbox' name='submitToEBI' checked=checked> submit to EBI";
    $html .= "<p>By clicking the button below, you confirm that you have the copyright for the selected metagenomes and this project.</p>";
    $html .= "<input type='button' value='make public' onclick='if(confirm(\"Do you really want to make this project and the selected metagenomes public?\")){list_select_select_all(\"".$list_select->id."\");document.forms.makepublicform.submit();}'><br><br>";
    $html .= $self->end_form();
  }
  else {
    $html .= "<p>- no metagenomes belonging to this project can be made public -</p>";
  }

  return $html;
}

sub make_project_public {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $project_id = $cgi->param('project');
  my @metagenomes = $cgi->param('public_metagenomes');
  my $mgrast = $application->data_handle('MGRAST');
  
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
	  $job->set_publication_date();
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
  
  if ($cgi->param('reviewer')) {
    # create a reviewer token
    my $description = "Reviewer_".$project_id;
    my @chars=('a'..'z','A'..'Z','0'..'9','_');
    my $token = "";
    foreach (1..50) {
      $token.=$chars[rand @chars];
    }
      
    # create scope for token
    my $token_scope = $dbm->Scope->create( { name => "token:".$token, description => $description } );
    unless (ref($token_scope)) {
      $self->application->add_message('warning', "failed to create token");
      return 0;
    }
      
    # add right to scope
    my $right = $dbm->Rights->create( { granted => 1,
					name => 'view',
					data_type => 'project',
					data_id => $project_id,
					scope => $token_scope,
					delegated => 1, } );
    unless (ref $right) {
      $self->application->add_message('warning', "failed to create right for token");
      return 0;
    }

    $self->application->add_message('info', "Reviewer Access Token created. The following link will grant view access:<br>".$WebConfig::APPLICATION_URL."?page=ClaimToken&token=$token&type=project");
    return 1;
  } else {
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
  }
  
  return;
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

sub selectable_metagenomes {
  my ($self) = @_;

  my $metagenomes = [];
  my $user  = $self->application->session->user;
  my $rast  = $self->application->data_handle('MGRAST'); 
  my $mgdb  = MGRAST::Analysis->new( $rast->db_handle );
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
