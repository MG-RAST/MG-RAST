package MGRAST::MGRAST;

use strict;
use warnings;

use GD;

use base qw( Exporter );
our @EXPORT = qw ( get_menu_metagenome get_settings_for_dataset dataset_is_phylo dataset_is_metabolic is_public_metagenome get_public_metagenomes get_menu_job create_set add_to_set remove_from_set get_set_names get_set display_get_set display_add_to_set display_execute_add_to_set display_execute_remove_from_set display_use_set create_classified_vs_non_bar);

eval {
  require FortyEightMeta::SimDB;
};

1;

sub get_menu_job {
  my ($menu, $job) = @_;
 
  if ($job) {
    my $jobmenu = 'Job&nbsp;#'.$job->id;
    $menu->add_category($jobmenu, "?page=JobDetails&job=".$job->id);
    $menu->add_entry($jobmenu, 'Debug this job', 
      '?page=JobDebugger&job='.$job->id, undef, [ 'debug' ]);
    $menu->add_entry($jobmenu, 'Change job priority', 
      '?page=JobPriority&job='.$job->id, undef, [ 'debug' ]);
    $menu->add_entry($jobmenu, 'Delete this job', 
      '?page=JobDelete&job='.$job->id, undef, ['delete', 'metagenome', $job->genome_id ]);
  }

  return 1;

}

sub get_menu_metagenome {
  my ($menu, $id, $user) = @_;

  #
  # Load up the database info.
  #
  my $db = FortyEightMeta::SimDB->new();

  my @dbs = $db->databases();
  my @analyses = map { $db->get_analyses($_->{name}, $_->{version}) } @dbs;
  
  my @phylo = grep { $_->{desc} eq 'phylogenetic classification' } @analyses;
  my @metab = grep { $_->{desc} eq 'metabolic reconstruction' } @analyses;
  
  my $menu_name = "";
  if ($id) {
    # Menu entry for current Metagenome
    $menu_name = 'Current&nbsp;Metagenome';
    $menu->add_category($menu_name);
    $menu->add_entry($menu_name, 'Overview', "?page=MetagenomeOverview&metagenome=$id");
    my $dataset = $metab[0]->{'db_name'}.":".$metab[0]->{'name'};
    $menu->add_entry($menu_name, 'Sequence Profile', "?page=MetagenomeProfile&dataset=$dataset&metagenome=$id");
    $menu->add_entry($menu_name, 'BLAST', "?page=MetagenomeBlastRun&metagenome=$id");
    $menu->add_entry($menu_name, 'Download',"?page=DownloadMetagenome&metagenome=$id");

    # Menu entry for comparison tools
    $menu_name = 'Compare&nbsp;Metagenomes';
    $menu->add_category($menu_name);
    $dataset = $metab[0]->{'db_name'}.":".$metab[0]->{'name'};
    $menu->add_entry($menu_name, 'Heat map', "?page=MetagenomeComparison&dataset=$dataset&metagenome=$id");
    $dataset = $phylo[0]->{'db_name'}.":".$phylo[0]->{'name'};
    $menu->add_entry($menu_name, 'Recruitment plot', "?page=MetagenomeRecruitmentPlot&metagenome=$id");
    $menu->add_entry($menu_name, 'Model', "?page=ModelView&model=MGRast$id");
    $menu->add_entry($menu_name, 'KEGG', "?page=Kegg&metagenome=$id");
  }

  if ($user) {
    # Menu entry for managing jobs
    $menu_name = 'Manage&nbsp;Private&nbsp;Data';
    $menu->add_category($menu_name);
    $menu->add_entry($menu_name, 'Upload new job',"?page=UploadMetagenome");
    $menu->add_entry($menu_name, 'Jobs overview',"?page=Jobs");
    if ($id && $user->has_right(undef, 'edit', 'metagenome', $id)) {
      $menu->add_entry($menu_name, 'Share',"?page=JobShare&metagenome=$id");
      $menu->add_entry($menu_name, 'Make Public',"?page=PublishGenome&metagenome=$id");
      $menu->add_entry($menu_name, 'Edit Metadata',"?page=MetaDataMG&metagenome=$id");
    }
  }

  return 1;
}

sub get_settings_for_dataset{
  my ($page) = @_;

  my $settings = 
    { Subsystem => { title => 'Metabolic Reconstruction with Subsystem',
		     intro => "<p>Subsystems represent the collection of functional roles that make up a metabolic pathway, a complex (e.g., the ribosome), or a class of proteins (e.g., two-component signal-transduction proteins within Staphylococcus aureus). Construction of a large set of curated populated subsystems is at the center of the NMPDR and SEED annotation efforts.</p>\n<p><strong>Note: </strong>A match against a coding sequence in our SEED database will result in multiple counts in the metabolic reconstruction if its functional role is part of more than one subsystem, thus the number of counts in the graph and the table may be higher than the number of sequences with hits.</p>\n",
		     desc => 'metabolic reconstruction',
		     select => [ 'Subsystem' ]
		   },
      SEED => { title => 'Phylogenetic Reconstruction based on the SEED',
		intro => "<p>The SEED is a cooperative effort focused on the development of a comparative genomics environment and, more importantly, on the development of curated genomic data based on subsystems. The phylogenetic reconstruction was done using the underlying non-redundant protein database. The advantage of this approach is that we use a lot more data than is available for the 16S analysis, however, the disadvantage of this approach is that it is obviously limited to those genomes that are in our underlying SEED database.</p>\n",
		desc => 'phylogenetic classification',
		select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	      },
      RDP => { title => 'Phylogenetic Reconstruction based on RDP',
	       intro => "<p>The Ribosomal Database Project (RDP) provides ribosome related data services, including online data analysis, rRNA derived phylogenetic trees, and aligned and annotated rRNA sequences. </p><p style='font-size: 8pt;'>For more information refer to: <em>Cole, J. R., B. Chai, R. J. Farris, Q. Wang, A. S. Kulam-Syed-Mohideen, D. M. McGarrell, A. M. Bandela, E. Cardenas, G. M. Garrity, and J. M. Tiedje. 2007. The ribosomal database project (RDP-II): introducing <i>myRDP</i> space and quality controlled public data. <i>Nucleic Acids Res.</i> 35 (Database issue): D169-D172; doi: 10.1093/nar/gkl889 [<a href='http://nar.oxfordjournals.org/cgi/content/abstract/35/suppl_1/D169'>Abstract</a>]</em>.</p>\n",
	       desc => 'phylogenetic classification',
	       select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	     },
      Greengenes => { title => 'Phylogenetic Reconstruction based on Greengenes',
		      intro => "<p>Greengenes provides access to a comprehensive 16S rRNA gene database and workbench. </p><p style='font-size: 8pt;'>More information is available in <em>DeSantis, T. Z., P. Hugenholtz, N. Larsen, M. Rojas, E. L. Brodie, K. Keller, T. Huber, D. Dalevi, P. Hu, and G. L. Andersen. 2006. Greengenes, a Chimera-Checked 16S rRNA Gene Database and Workbench Compatible with ARB. Appl Environ Microbiol 72:5069-72.</em>.</p>\n",
		      desc => 'phylogenetic classification',
		      select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
		    },
      LSU =>  { title => 'Phylogenetic Reconstruction based on European Ribosomal Database',
		intro => "<p>A database on the structure of ssu/lsu ribosomal subunit RNA which is being maintained at the Department of Plant Systems Biology, University of Gent, Belgium.</p><p style='font-size: 8pt;'>For more information please refer to: <em>Wuyts, J., Perriere, G. & Van de Peer, Y. (2004), The European ribosomal RNA database., <i>Nucleic Acids Res.</i> 32, D101-D103, [<a href='http://nar.oupjournals.org/cgi/content/full/32/suppl_1/D101'>Full text</a>]</em>.</p>\n",
		desc => 'phylogenetic classification',
		select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	      },
      SSU => { title => 'Phylogenetic Reconstruction based on European Ribosomal Database',
	       intro => "<p>A database on the structure of ssu/lsu ribosomal subunit RNA which is being maintained at the Department of Plant Systems Biology, University of Gent, Belgium.</p><p style='font-size: 8pt;'>For more information please refer to: <em>Wuyts, J., Perriere, G. & Van de Peer, Y. (2004), The European ribosomal RNA database., <i>Nucleic Acids Res.</i> 32, D101-D103, [<a href='http://nar.oupjournals.org/cgi/content/full/32/suppl_1/D101'>Full text</a>]</em>.</p>\n",
	       desc => 'phylogenetic classification',
	       select => [ 'SEED', 'RDP', 'Greengenes', 'LSU', 'SSU' ],
	     },
    };
      
  
  my $dataset = $page->application->cgi->param('dataset') || 'SEED:subsystem_tax'; # was 'SEED:Subsystem'

  $page->data('dataset', $dataset);

  my ($dbname, $type) = split(/:/, $dataset);
  
  my $db = FortyEightMeta::SimDB->new();

  my @dbs = $db->databases();
  my @analyses = map { $db->get_analyses($_->{name}, $_->{version}) } @dbs;

  $page->data('dataset_select_all',
	      [map { "$_->{db_name}:$_->{name}" } @analyses]);
  
  $page->data('dataset_select', $page->data('dataset_select_all'));

  my %labels = map { ("$_->{db_name}:$_->{name}", $_->{menu_name}) } @analyses;

  my @mine = grep { $_->{db_name} eq $dbname and $_->{name} eq $type } @analyses;

  $page->data('dataset_labels', \%labels);

  if (@mine)
  {
    my $s = $mine[0];
    $page->data('dataset_title', $s->{title});
    $page->data('dataset_intro', $s->{intro});
    $page->data('dataset_desc', $s->{desc});
    
    $page->data('dataset_select',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq $s->{desc} } @analyses]);
    $page->data('dataset_select_metabolic',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq "metabolic reconstruction" } @analyses]);
    $page->data('dataset_select_phylogenetic',
		[map { "$_->{db_name}:$_->{name}" } grep { $_->{desc} eq "phylogenetic classification" } @analyses]);
  }
  else {
      #$page->application->error("Unknown dataset '$type'.");
      #return undef;
  }

  return $page;

}

sub dataset_is_phylo
{
    my($desc) = @_;
    return $desc eq 'phylogenetic classification';
}

sub dataset_is_metabolic
{
    my($desc) = @_;
    return $desc eq 'metabolic reconstruction';
}

sub is_public_metagenome {
  die "call to deprecated method is_public metagenome, call Job->public instead";
}

sub get_public_metagenomes {
  my ($mgrast) = @_;

  if (ref($mgrast) eq 'WebAppBackend') {
    die "deprecated call to get_public_metagenomes, call with mgrast master only";
  }

  unless (ref($mgrast) eq 'DBMaster') {
    die "get_public_metagenomes called without mgrast master";
  }

  # return all public metagenomes
  return $mgrast->Job->get_objects( { public => 1 } );
}

sub create_classified_vs_non_bar {
  my ($total, $classified, $no_classifed_text) = @_;

  # set graphic
  my $bar_height = 20;
  my $bar_width  = 500;
  my $legend_height = ($no_classifed_text ? 0 : GD::gdSmallFont->height+5);
  my $gap = ($no_classifed_text ? 0 : 1);
  my $font_width = GD::gdSmallFont->width();
  my $font_height = GD::gdSmallFont->height();

  my $perc = 100/$total*$classified;

  # create the image
  my $img = WebGD->new($bar_width, $bar_height+$legend_height);
  my $white = $img->colorResolve(255,255,255);
  my $black = $img->colorResolve(0,0,0);
  my $class = $img->colorResolve(70,130,180);
  my $non = $img->colorResolve(176,196,222);

  unless($no_classifed_text){
    $img->string(GD::gdSmallFont, 0, 0, "Classified sequences vs. non-classified:", $black);
  } 
  $img->filledRectangle( 0, $legend_height+$gap, $bar_width/100*$perc, $legend_height+$gap+$bar_height, $class );
  $img->filledRectangle( $bar_width/100*$perc+1, $legend_height+$gap, $bar_width, $legend_height+$gap+$bar_height, $non );
  my $key1 = sprintf("%.2f%%",$perc)." ($classified)";
  my $key2 = sprintf("%.2f%%",100-$perc)." (".($total-$classified).")";
  my $key_y = $legend_height+$gap+(int(($bar_height-$font_height)/2));
  my $key1_x = $font_width;
  my $key2_x = $bar_width-((length($key2)+1)*$font_width);
  $img->string(GD::gdSmallFont, $key1_x, $key_y, $key1, $black);
  $img->string(GD::gdSmallFont, $key2_x, $key_y, $key2, $black);

  return '<img src="'.$img->image_src.'">';

}

###
# Set Management
###

sub create_set {
  my ($self, $name, $ids, $user) = @_;

  my $application = $self->application;
  my $master = $application->dbmaster;
  unless ($user) {
    $user = $application->session->user;
  }

  unless ($user) {
    $application->add_message('warning', "Cannot create a preference without a user");
    return undef;
  }

  my $existing = $master->Preferences->get_objects( { user => $user, name => "MGSET".$name } );
  if (scalar(@$existing)) {
    $application->add_message('warning', "A set with this name already exists");
    return undef;
  }

  if ($ids && ref($ids) && scalar(@$ids)) {
    foreach my $id (@$ids) {
      $master->Preferences->create( { user => $user, name => "MGSET".$name, value => $id } );
    }
  } elsif ($ids) {
      $master->Preferences->create( { user => $user, name => "MGSET".$name, value => $ids } );
  } else {
      $master->Preferences->create( { user => $user, name => "MGSET".$name } );
  }

  return 1;
}

sub add_to_set {
  my ($self, $name, $ids, $user) = @_;

  my $application = $self->application;
  my $master = $application->dbmaster;
  unless ($user) {
    $user = $application->session->user;
  }

  unless ($user) {
    $application->add_message('warning', "Cannot create a preference without a user");
    return undef;
  }

  unless ($ids) {
    $application->add_message('warning', "Cannot create a preference without an id");
    return undef;
  }

  my $existing = $master->Preferences->get_objects( { user => $user, name => "MGSET".$name } );
  unless (scalar(@$existing)) {
    $self->create_set($name, $ids);
  } else {
    unless ($existing->[0]->value) {
      $existing->[0]->delete;
      $self->create_set($name, $ids);
    } else {
      my $existing_vals = {};
      foreach my $val (@$existing) {
	$existing_vals->{$val->value} = 1;
      }
      if (ref($ids) && (scalar(@$ids))) {
	foreach my $id (@$ids) {
	  unless ($existing_vals->{$ids}) {
	    $master->Preferences->create( { user => $user, name => "MGSET".$name, value => $id } );
	  }
	}
      } else {
	unless ($existing_vals->{$ids}) {
	  $master->Preferences->create( { user => $user, name => "MGSET".$name, value => $ids } );
	}
      }
    }
  }

  return 1;
}

sub remove_from_set {
  my ($self, $name, $ids, $user) = @_;

  my $application = $self->application;
  my $master = $application->dbmaster;
  unless ($user) {
    $user = $application->session->user;
  }

  unless ($user) {
    $application->add_message('warning', "Cannot delete a preference without a user");
    return undef;
  }

  my $existing = $master->Preferences->get_objects( { user => $user, name => "MGSET".$name } );
  if ($ids && ref($ids) && scalar(@$ids)) {
    my $ids_hash = {};
    foreach my $id (@$ids) {
      $ids_hash->{$id} = 1;
    }
    foreach my $entry (@$existing) {
      if ($ids_hash->{$entry->value}) {
	$entry->delete;
      }
    }
  } elsif ($ids) {
    foreach my $entry (@$existing) {
      if ($ids eq $entry->value) {
	$entry->delete;
      }
    }
  } else {
    foreach my $entry (@$existing) {
      $entry->delete;
    }
  }

  return 1;
}

sub get_set_names {
  my ($self, $user) = @_;

  my $application = $self->application;
  my $master = $application->dbmaster;
  unless ($user) {
    $user = $application->session->user;
  }

  unless ($user) {
    $application->add_message('warning', "Cannot get a preference without a user");
    return undef;
  }

  my $existing = $master->Preferences->get_objects( { user => $user } );
  my $sets = {};
  foreach my $entry (@$existing) {
    my ($set) = $entry->{name} =~ /^MGSET(.+)/;
    if ($set) {
      $sets->{$set} = 1;
    }
  }

  my @rv = keys(%$sets);

  return \@rv;
}

sub get_set {
  my ($self, $name, $user) = @_;

  my $application = $self->application;
  my $master = $application->dbmaster;
  unless ($user) {
    $user = $application->session->user;
  }
  
  unless ($user) {
    $application->add_message('warning', "Cannot get a preference without a user");
    return undef;
  }

  my $existing = $master->Preferences->get_objects( { user => $user, name => "MGSET".$name } );
  my $ids = [];
  foreach my $entry (@$existing) {
    if ($entry->{value}) {
      push(@$ids, $entry->{value});
    }
  }

  return $ids;
}

sub display_add_to_set {
  my ($self, $id) = @_;

  $self->application->register_component('Ajax', 'mgset_ajax');

  my $sets = $self->get_set_names;
  my $select = qq~<select name='mgset' id='mgsetselect' onchange="execute_ajax('display_get_set', 'mg_set_inner_div', 'mgset='+this.options[this.selectedIndex].value+'&mgid=~ . $id . qq~', 'checking...');">~;
  foreach my $set (@$sets) {
    $select .= "<option value='$set'>$set</option>";
  }
  $select .= "</select>";

  my $ids = $self->get_set($sets->[0]);
  my $first = "<select size=5>";
  foreach (@$ids) {
    $first .= "<option value='$_'>$_</option>";
  }
  $first .= "</select>";

  my $button = qq~<input type='button' value='add to set' id='ats_button' onclick="this.nextSibling.style.display='inline';this.style.display='none';">~;

  my $form = $button . "<div id='mg_set_outer_div' style='display: none;'><table><tr><th>set name</th><th>metagenomes</th><th></th></tr><tr><td style='vertical-align: top;'>" . $select . "</td><td><span id='mg_set_inner_div'>".$first."</span></td><td>" . qq~<span id='mgsetbuttonspan1'><input type="button" value="add to set" onclick="document.getElementById('mgsetbuttonspan2').style.display='inline';document.getElementById('mgsetbuttonspan1').style.display='none';execute_ajax('display_execute_add_to_set', 'mg_set_inner_div', 'mgset='+document.getElementById('mgsetselect').options[document.getElementById('mgsetselect').selectedIndex].value+'&mgid=~ . $id . qq~', 'adding...');"><br><br><br><input type='button' value='cancel' onclick="document.getElementById('ats_button').style.display='inline';document.getElementById('mg_set_outer_div').style.display='none';"></span><span id='mgsetbuttonspan2' style='display: none'><input type='button' value='done' onclick="document.getElementById('ats_button').style.display='inline';document.getElementById('mg_set_outer_div').style.display='none';document.getElementById('mgsetbuttonspan1').style.display='inline';document.getElementById('mgsetbuttonspan2').style.display='none';"><br><br><br><input type="button" value="undo" onclick="document.getElementById('mgsetbuttonspan1').style.display='inline';document.getElementById('mgsetbuttonspan2').style.display='none';execute_ajax('display_execute_remove_from_set', 'mg_set_inner_div', 'mgset='+document.getElementById('mgsetselect').options[document.getElementById('mgsetselect').selectedIndex].value+'&mgid=~ . $id . qq~', 'canceling...');"></span></td></tr></table>~ . "</div>";

  $form .= $self->application->component('mgset_ajax')->output;

  return $form;
}

sub display_use_set {
  my ($self) = @_;

  $self->application->register_component('Ajax', 'mguseset_ajax');

  my $sets = $self->get_set_names;
  my $select = qq~<select name='mgset' onchange="execute_ajax('display_get_set', 'mg_set2_div', 'mgset='+this.options[this.selectedIndex].value, 'loading...');">~;
  foreach my $set (@$sets) {
    $select .= "<option value='$set'>$set</option>";
  }
  $select .= "</select>";

  my $ids = $self->get_set($sets->[0]);
  my $first = "<select size=5 multiple name='metagenome'>";
  foreach (@$ids) {
    $first .= "<option value='$_'>$_</option>";
  }
  $first .= "</select>";

  my $button = $self->application->component('mguseset_ajax')->output;
  $button .= qq~<input type='button' value='select set' id='mgusesetbutton' onclick="this.nextSibling.style.display='inline';this.style.display='none';">~;
  $button .= qq~<div id='mg_set_div' style='display: none;'><table><tr><th>set name</th><th>metagenomes</th><th></th></tr><tr><td style='vertical-align: top;'>~ . $select . qq~</td><td><span id='mg_set2_div'>~.$first.qq~</span></td><td><input type='button' value='cancel' onclick="document.getElementById('mgusesetbutton').style.display='inline';document.getElementById('mg_set_div').style.display='none';"></td></tr></table>~;

  return $button;
}

sub display_get_set {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $set_name = $cgi->param('mgset');

  my $ids = $self->get_set($set_name);
  my $select = "<select size=5 multiple name='metagenome'>";
  foreach my $id (@$ids) {
    $select .= "<option value='$id'>$id</option>";
  }
  $select .= "</select>";
}

sub display_execute_add_to_set {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $mgid = $cgi->param('mgid');
  my $set = $cgi->param('mgset');
  $self->add_to_set($set, $mgid);

  return $self->display_get_set;
}

sub display_execute_remove_from_set {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $mgid = $cgi->param('mgid');
  my $set = $cgi->param('mgset');
  $self->remove_from_set($set, $mgid);

  return $self->display_get_set;
}
