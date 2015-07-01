package MGRAST::WebPage::PublishGenome;

use strict;
use warnings;
no warnings('once');

use MGRAST::Metadata;

use JSON;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use Conf;

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
  $self->application->register_component('Table', 'private_projects_table');
  $self->application->register_component('Table', 'DisplayMetaData');
  $self->application->register_component('Ajax', 'Display_Ajax');

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
  
  # api info for making public
  $self->data('api', $Conf::api_url || "http://api.metagenomics.anl.gov");
  
  $self->data('job', $job);
  $self->data('linkin', $Conf::cgi_url."linkin.cgi?metagenome=$id");
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
  my $mddb    = $self->data('meta');
  my $job     = $self->data('job');
  my $project = $job->primary_project;
  my $user    = $self->application->session->user;
  my $content = "<p><strong>Please confirm that the following metadata is correct:</strong><br>";
  $content .= "Labels in <font color='red'>red</font> are manditory MIxS fields, they are required to be filled out in order to publish your metagenome.</p>";
  if ($project) {
    $content .= "<p>If you wish to change any metadata in this metagenome, use the 'Upload MetaData' button within project <a href='metagenomics.cgi?page=MetagenomeProject&project=".$project->id."'>".$project->name."</a> to upload a valid metadata spreadsheet. You can obtain a metadata spreadsheet by either downloading the current metadata for this project (using the 'Export Metadata' button), or by filling out a <a href='ftp://".$Conf::ftp_download."/data/misc/metadata/".$Conf::mgrast_metadata_template."'>metadata spreadsheet template</a>.</p>";
  }

  my $mdata = $mddb->get_metadata_for_table($job);
  my $mixs  = $mddb->mixs();
  my @tdata = ();
  my @miss  = ();
  my %seen  = ();
  
  my @lib_type_rows = grep { $_->[1] eq 'investigation_type' } @$mdata;
  my $lib_type = scalar(@lib_type_rows) ? $lib_type_rows[0][2] : ($job->sequence_type ? $mddb->investigation_type_alias($job->sequence_type) : 'metagenome');
  my $no_proj_md = 0;

  foreach my $row (@$mdata) {
    my ($cat, $tag, $val) = @$row;
    next unless ($val && ($val =~ /\S/) && ($val ne '-'));
    next if (exists $seen{$cat.$tag.$val});
    my $ccat = (split(/:/, lc($cat)))[0];
    if ($ccat eq 'library') {
      if (exists $mixs->{library}{$lib_type}{$tag}) {
	push @tdata, [ "<font color='red'>$cat</font>", "<font color='red'>$tag</font>", $val ];
	$mixs->{library}{$lib_type}{$tag} = 'yes';
      } else {
	push @tdata, $row;
      }
    }
    else {
      if (exists $mixs->{$ccat}{$tag}) {
	push @tdata, [ "<font color='red'>$cat</font>", "<font color='red'>$tag</font>", $val ];
	$mixs->{$ccat}{$tag} = 'yes';
      } else {
	push @tdata, $row;
      }
    }
    $seen{$cat.$tag.$val} = 1;
  }

  foreach my $cat (keys %$mixs) {
    if ($cat eq 'library') {
      foreach my $tag (keys %{$mixs->{library}{$lib_type}}) {
	if ($mixs->{library}{$lib_type}{$tag} ne 'yes') {
	  push @miss, [ ucfirst($cat), $tag ];
	}
      }
    }
    else {
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
  }

  if ($no_proj_md && ref($project)) {
    unshift @tdata, [ "<font color='red'>Project</font>", "<font color='red'>project_name</font>", $project->name ];
  } elsif ($no_proj_md) {
    my $error = "<p><font color='red'>We are unable to publish your metagenome due to the following errors:</font></p>";
    $error .= "<p>Your metagenome does not exist in a project. Please create a new project or add it to an existing project before you can publish.</p>";

    my $projects = $self->app->data_handle('MGRAST')->Project->get_private_projects($user, 1);
    if (@$projects > 0) {
      my $pp_table = $self->application->component('private_projects_table');
      $pp_table->columns( [ { name => 'id' }, { name => 'name' }, { name => 'type' } ] );
      $pp_table->data([ map { [ $_->{id}, "<a href='?page=MetagenomeProject&project=".$_->{id}."' target=_blank>".($_->{name} ? $_->{name} : "-")."</a>", $_->{type} ] } grep { $_->{id} } @$projects ]);
      $pp_table->items_per_page(20);
      $pp_table->show_select_items_per_page(1);
      $pp_table->show_top_browse(1);
      $error .= "<p>Projects you can add metagenomes to:<br>".$pp_table->output()."<br>";
    }
    else {
      $error .= "<p>You have no existing projects, please create one: ";
    }
    $error .= "<a onclick='pname=prompt(\"Enter new project name\",\"\");if(pname.length){window.top.location=\"?page=MetagenomeProject&action=create&pname=\"+pname;}' style='cursor:pointer;font-size:11px;font-weight:bold;'>create new project</a></p>";
    return $error;
  }
  
  my $table = $self->application->component('DisplayMetaData');
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
  
  ######## use API to make public ##########
  my $response = undef;
  my $agent = LWP::UserAgent->new;
  my $json  = JSON->new;
  $json = $json->utf8();
  $json->max_size(0);
  $json->allow_nonref;
  
  my $url  = $self->data('api')."/job/public";
  my $data = {metagenome_id => 'mgm'.$job->{metagenome_id}};
  my $req  = HTTP::Request->new(POST => $url);
  $req->header('Content-Type' => 'application/json', 'auth' => $Conf::api_key);
  $req->content($json->encode($data));
  
  eval {
    my $post  = $agent->request($req);
    $response = $json->decode($post->content);
  };
  if ($@ || (! ref($response))) {
    $self->application->add_message('warning', "Could not make metagenome public: ".$@);
    return "<pre>Could not make metagenome public: ".$@."</pre>";
  } elsif (exists($response->{ERROR}) && $response->{ERROR}) {
    $self->application->add_message('warning', "Could not make metagenome public: ". $response->{ERROR});
    return "<pre>Could not make metagenome public: ".$response->{ERROR}."</pre>";
  }
  
  # send email
  $user->send_email($from, $subject, $body);

  my $content = "<h1>" . $job->name . " ($mg_id) is publicly accessible.</h1>";
  $content   .= "<p>Dear $uname, thank you for making your metagenome publicly available. You can link to your public metagenome using this link: ";
  $content   .= "<a href='".$self->data('linkin')."'>".$self->data('linkin')."</a>. If you believe this is a mistake please contact mg-rast\@mcs.anl.gov.</p>";
  return $content;
}
