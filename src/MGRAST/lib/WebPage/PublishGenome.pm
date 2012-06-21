package MGRAST::WebPage::PublishGenome;

use strict;
use warnings;

use MGRAST::Metadata;
use Data::Dumper;

use WebConfig;
use base qw( WebPage );

1;


=pod

=head1 NAME

Publish Genome - make a metagenome public

=head1 DESCRIPTION

Publish Genome - checks if all neccessary metadata and rights
are available and then makes a metagenome public

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;
  
  $self->title("Make metagenome publicly accessible");

  # register components
  $self->application->register_component('Table', 'DisplayMetaData');
  $self->application->register_component('Ajax', 'Display_Ajax');
  $self->application->register_action($self, 'download_template', 'download_template');

  # init data
  my $meta = MGRAST::Metadata->new();
  $self->data('meta', $meta);
  
  # sanity check on job
  my $id = $self->application->cgi->param('metagenome') || '';
  my $job;
  $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $id });
  unless ($job) {
    $self->app->error("Unable to retrieve the job '$id'.");
    return;
  }
  $self->data('job', $job);
  $self->data('linkin', "http://metagenomics.anl.gov/linkin.cgi?metagenome=$id");
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # init
  my $job   = $self->data('job');
  my $user  = $self->application->session->user;
  my $uname = $user->firstname." ".$user->lastname;
  
  # set output
  my $content = $self->application->component('Display_Ajax')->output() . "<div id='status_div'>";

  unless ($job->public()) {
    if ($user && $user->has_right($self->application, 'edit', 'metagenome', $job->metagenome_id)) {
      $content .= '<h1>' . $job->name . ' (' . $job->metagenome_id . ')</h1>';
      $content .= "<p style='width:800px; text-align: justify;'>Please note: You will not be able to make your metagenome private again from this website. In order to do so you will have to contact mg-rast\@mcs.anl.gov.</p>";
      $content .= "<p>Metadata (or data about the data) has become a necessity as the community generates large quantities of data sets.<br>";
      $content .= "Using community generated questionnaires we capture this metadata. MG-RAST has implemented the use of <a href='http://gensc.org/gc_wiki/index.php/MIxS' target=_blank >Minimum Information about any (X) Sequence</a> (MIxS) developed by the <a href='http://gensc.org' target=_blank >Genomic Standards Consortium</a> (GSC).</p>";
      $content .= "<div id='display_div'></div>";
      $content .= "<img src='./Html/clear.gif' onload='execute_ajax(\"meta_info\", \"display_div\", \"metagenome=" . $job->metagenome_id . "\");'>";
    } else {
      $content .= '<h1>' . $job->name . ' (' . $job->metagenome_id . ') is unaccessible.</h1>';
      $content .= "<p>$uname is not the owner of this metagenome, and has no rights to make it publicly accessible.</p>";
    }
  }
  else {
    $content .= '<h1>' . $job->name . ' (' . $job->metagenome_id . ') is publicly accessible.</h1>';
    $content .= "<p>Metagenome " . $job->metagenome_id . " is already publicly available. You can link to this public metagenome using the following link: ";
    $content .= "<a href='".$self->data('linkin')."'>".$self->data('linkin')."</a>. If you believe this is a mistake please contact mg-rast\@mcs.anl.gov.</p>";
  }
  
  return $content . "</div>";
}

sub meta_info {
  my ($self) = @_;

  my $mg_id   = $self->application->cgi->param('metagenome');
  my $job     = $self->data('job');
  my $project = $job->primary_project;
  my $user    = $self->application->session->user;
  my $content = "<p><strong>Please confirm that the following metadata is correct:</strong><br>";
  $content .= "Labels in <font color='red'>red</font> are manditory MIxS fields, they are required to be filled out in order to publish your metagenome.</p>";
  if ($project) {
    $content .= "<p>If you wish to change any metadata in this metagenome, use the 'Upload MetaData' button within project <a href='metagenomics.cgi?page=MetagenomeProject&project=".$project->id."'>".$project->name."</a> to upload a valid metadata spreadsheet. You can obtain a metadata spreadsheet by either downloading the current metadata for this project (using the 'Export Metadata' button), or by filling out a <a href='metagenomics.cgi?page=PublishGenome&metagenome=$mg_id&action=download_template'>metadata spreadsheet template</a>.</p>";
  }

  my $mdata = $self->data('meta')->get_metadata_for_table($job);
  my $mixs  = $self->data('meta')->mixs();
  my $table = $self->application->component('DisplayMetaData');
  my @tdata = ();
  my @miss  = ();
  my %seen  = ();
  
  my $no_proj_md = 0;
  foreach my $row (@$mdata) {
    my ($cat, $tag, $val) = @$row;
    next unless ($val && ($val =~ /\S/) && ($val ne '-'));
    next if (exists $seen{$cat.$tag.$val});
    my $ccat = (split(/:/, lc($cat)))[0];
    if (exists $mixs->{$ccat}{$tag}) {
      push @tdata, [ "<font color='red'>$cat</font>", "<font color='red'>$tag</font>", $val ];
      $mixs->{$ccat}{$tag} = 'yes';
    } else {
      push @tdata, $row;
    }
    $seen{$cat.$tag.$val} = 1;
  }

  foreach my $cat (keys %$mixs) {
    foreach my $tag (keys %{$mixs->{$cat}}) {
      if ($mixs->{$cat}{$tag} ne 'yes') {
	if ($cat =~ /project/i) {
	  $no_proj_md = 1;
	} else {
	  push @miss, [ ucfirst($cat), $tag ];
	}
      }
    }
  }
  if ($no_proj_md && ref($project)) {
    unshift @tdata, [ "<font color='red'>Project</font>", "<font color='red'>project_name</font>", $project->name ];
  } elsif ($no_proj_md) {
    my $error = "<p><font color='red'>We are unable to publish your metagenome due to the following errors:</font></p>";
    $error .= "<p>Your metagenome does not exist in a project. Please create a new project or add it to an existing project before you can publish.<br>";
    $error .= "This can be done through the Browse Page: <a title='Browse Metagenomes' href='?page=MetagenomeSelect'>";
    $error .= "<img style='padding-left:15px; height:25px;' src='./Html/mgrast_globe.png'></a></p>";
    return $error;
  }
  
  if ( scalar(@tdata) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
  }
  $table->width(800);
  $table->columns([ { name => 'Category', filter  => 1, sortable => 1, operator => 'combobox' },
		    { name => 'Label', filter  => 1, sortable => 1 },
		    { name => 'Value', filter  => 1, sortable => 1 }
		  ]);
  $table->data(\@tdata);

  if (scalar(@miss) > 0) {
    $content .= "<p>You are missing the following ".scalar(@miss)." manditory MIxS field(s):";
    $content .= "<blockquote><table><tr><th>Category</th><th>Label</th></tr>";
    map { $content .= "<tr><td>".$_->[0]."</td><td>".$_->[1]."</td></tr>" } @miss;
    $content .= "</table></blockquote>";
  } else {
    my $pub_button = qq(<button style='cursor:pointer;' onclick="execute_ajax('publish', 'status_div', 'metagenome=$mg_id');">Publish Metagenome</button>);
    $content .= "<p>If you are satisfied with the below metadata, click here:<span style='padding-left:10px'>$pub_button</span></p>";
  }
  $content .= $table->output();
  return $content; 
}

sub publish {
  my ($self) = @_;

  my $job     = $self->data('job');
  my $mg_id   = $self->application->cgi->param('metagenome');
  my $user    = $self->application->session->user;
  my $uname   = $user->firstname." ".$user->lastname;
  my $from    = 'Metagenomics Analysis Server <mg-rast@mcs.anl.gov>';
  my $subject = "Metagenome $mg_id is now publicly available";
  my $body    = "Dear $uname,\n\nYour metagenome '" . $job->name . "' ($mg_id) is now public. You can link to the metagenome using:\n" . $self->data('linkin') .
                "\n\nThis is an automated message.  Please contact mg-rast\@mcs.anl.gov if you have any questions or concerns.";
  
  $job->public(1);
  $user->send_email($from, $subject, $body);

  my $content = "<h1>" . $job->name . " ($mg_id) is publicly accessible.</h1>";
  $content   .= "<p>Dear $uname, thank you for making your metagenome publicly available. You can link to your public metagenome using this link: ";
  $content   .= "<a href='".$self->data('linkin')."'>".$self->data('linkin')."</a>. If you believe this is a mistake please contact mg-rast\@mcs.anl.gov.</p>";
  return $content;
}

sub download_template {
  my $fn = $Conf::html_base.'/'.$Conf::mgrast_metadata_template;

  if (open(FH, $fn)) {
    print "Content-Type:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\n";  
    print "Content-Length: " . (stat($fn))[7] . "\n";
    print "Content-Disposition:attachment;filename=".$Conf::mgrast_metadata_template."\n\n";
    while (<FH>) {
      print $_;
    }
    close FH;
  }
}
