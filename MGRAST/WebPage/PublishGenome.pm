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

MetaData - collects meta information for uploaded genome or metagenome

=head1 DESCRIPTION

Page for collecting meta data for genomes or metagenomes

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
  $self->data('linkin', "http://test.metagenomics.anl.gov/metagenomics.cgi?page=MetagenomeOverview&metagenome=" . $job->metagenome_id);
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
      $content .= "<p>MG-RAST has implemented the use of \"Minimum Information about a MetaGenome Sequence\" developed by the <a href='http://gensc.org' target=_blank >Genomic Standards Consortium</a> (GSC). The Genomic Standards Consortium is an open-membership working body which formed in September 2005. The goal of this international community is to promote mechanisms that standardize the description of genomes and the exchange and integration of genomic data. MG-RAST supports this goal as it allows for transparency in comparative analyses, interpretation of results, and integration of metagenomic data.</p>";
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
  my $user    = $self->application->session->user;
  my $uname   = $user->firstname." ".$user->lastname;
  my $content = "<p><strong>Dear $uname, please confirm that the following meta-data is correct:</strong><br>";
  $content   .= "If you are satisfied with the below meta-data, click 'Publish Metagenome'.  If you wish to change any meta-data, click 'Edit Meta-Data'.<br>";
  $content   .= "Questions in <font color='red'>red</font> are manditory MIGS fields, they are required to be filled out in order to publish your metagenome.</p>";
  
  my %meta_data = map { $_->[0], $_ } @{ $self->data('meta')->get_metadata_for_table( $self->data('job') ) };
  my $all_meta  = $self->data('meta')->get_template_data();
  my $migs_tags = $self->data('meta')->get_migs_tags();
  my $table     = $self->application->component('DisplayMetaData');
  my @miss_migs = ();
  my @tbl_data  = ();

  foreach my $tag (keys %$all_meta) {
    my ($cat, $quest) = @{$all_meta->{$tag}};
    if (exists $meta_data{$tag}) {
      if (exists $migs_tags->{$tag}) { $quest = "<font color='red'>$quest</font>"; }    
      push @tbl_data, [ $tag, $cat, $quest, $meta_data{$tag}[3] ];
    }
    elsif (exists($migs_tags->{$tag}) && ($migs_tags->{$tag}->{mandatory})) {
      push @miss_migs, $cat . " : " . $quest;
      push @tbl_data, [ $tag, $cat, "<font color='red'>$quest</font>", "" ];
    }
  }

  if ( scalar(@tbl_data) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1); 
  }
  $table->width(800);
  $table->columns([ { name => 'Key'     , visible => 0 },
		    { name => 'Category', filter  => 1, sortable => 1, operator => 'combobox' },
		    { name => 'Question', filter  => 1, sortable => 1 },
		    { name => 'Value'   , filter  => 1, sortable => 1 }
		  ]);

  $table->data(\@tbl_data);
  $content .= $table->output();

  my $md_button  = qq(<button onClick="parent.location='?page=MetaDataMG&metagenome=$mg_id&edit=1&view=all'">Edit Meta-Data</button>);
  my $pub_button = qq(<button onclick="execute_ajax('publish', 'status_div', 'metagenome=$mg_id');">Publish Metagenome</button>);

  if (@miss_migs > 0) {
    $content .= "<p>You are missing the following " . scalar(@miss_migs) . " manditory MIGS field(s):<blockquote>" . join(", ", @miss_migs) . "</blockquote>";
    $content .= "Please update the meta-data for your metagenome:<span style='padding-left:10px'>$md_button</span></p>";
  } else {
    $content .= "<p><table width='800'><tr><td align='center'>$md_button</td><td align='center'>$pub_button</td></tr></table></p>";
  }
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
