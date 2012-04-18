package MGRAST::WebPage::PrivateMetagenomes;

# $Id: PrivateMetagenomes.pm,v 1.6 2010-11-19 12:41:52 paczian Exp $

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;

use MGRAST::MGRAST qw( :DEFAULT );
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

  $self->title('PrivateMetagenomes');

  # register components
  $self->application->register_component('Ajax', 'ajax');

  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the MetagenomeSelect page.

=cut

sub output {
  my ($self) = @_;

  my $html = "";
  $html .= $self->application->component('ajax')->output();
  $html .= '<div id="main_container">';

  # check for MGRAST
  my $mgrast = $self->application->data_handle('MGRAST');
  unless ($mgrast) {
      $html .= "<h2>The MG-RAST is currently offline. We apologize for the inconvenience. Please try again later.</h2>";
      return $html;
  }

  my $results = $self->data('mddb')->_handle()->Search->get_objects({});
  
  my $metadata = {}; 
  foreach (@$results){
    $metadata->{$_->job()->genome_id} = $_;
  }
  
  $html .= "<h3>Browse Private Metagenomes<a href='metagenomics.cgi?page=MetagenomeSelect' style='font-weight: normal; padding-left: 100px; font-size: 12px;'>Browse Public Metagenomes</a></h3>";

  # quick links
  $html .= "<div class='quick_links'>";
  $html .= "<ul>";
  $html .= "<li><a href='metagenomics.cgi?page=UploadMetagenome'>Upload a new Metagenome</a></li>";
  $html .= "<li><a href='metagenomics.cgi?page=Jobs'>Jobs Overview</a></li>";
  $html .= "</ul>";
  $html .= "</div>";

  my $processing_container = "";
  my $shared_container = "";
  my $private_container = "";

  my $num_proc = 0;
  my $num_shared = 0;
  my $num_priv = 0;

  # if logged in, check for private organisms
  if ($self->application->session->user()) {
    my $count_private = 0;
    my $count_shared = 0;
    my $count_processing = 0;
    
    my $available_metagenomes = $mgrast->Job->get_jobs_for_user($self->application->session->user(), 'view');

    my $private_metagenomes = [];
    my $shared_metagenomes = [];
    my $processing_metagenomes = [];

    foreach my $g (@$available_metagenomes) {
      if (! $g->viewable) {
	push(@$processing_metagenomes, $g);
      } elsif ($g->owner->login eq $self->application->session->user->login) {
	push(@$private_metagenomes,$g);
      } else {
	push(@$shared_metagenomes, $g);
      }
    }

    $private_container = "<div id='priv_table' style='width: 920px; border: 1px solid rgb(143, 188, 63); padding: 20px; font-weight: bold;'>you currently have no private metagenomes</div>";
    my $odd_even = 1;
    $count_private = scalar @$private_metagenomes;
    $num_priv = $count_private;
    if ($count_private) {
      $private_container = "<div id='priv_table' style='width: 960px; border: 1px solid rgb(143, 188, 63); height: 200px; overflow-x: hidden; overflow-y: auto;'>";
    }
    foreach my $mg (sort { $a->genome_name cmp $b->genome_name } @$private_metagenomes) {
      $private_container .= "<div class='metagenome_item".($odd_even ? "_odd" : "_even")."'><div class='metagenome_item_title'><a class='metagenome_link' href='metagenomics.cgi?page=MetagenomeOverview&metagenome=".$mg->genome_id."'>".$mg->genome_name."</a></div>";
      $private_container .= "<div class='metagenome_item_content'>";

      $private_container .= "<table><tr><td style='color:#848484; font-size: 0.8em; width: 300px;'>PROJECT</td>".
	"<td style='color:#848484; font-size: 0.8em; width:100px;'>ID</td>".
	  "<td style='color:#848484; font-size: 0.8em; width:100px;'>JOB</td>".
	      "<td style='color:#848484; font-size: 0.8em;'>SIZE</td></tr>";
      
      my $mg_size = $mg->size || 0;
      $mg_size = &format_number($mg_size);
      $private_container .= "<tr><td style='color:#374F44; font-size: 0.9em; width: 300px;'><b>".$mg->project_name."</b></td>".
 	"<td style='color:#374F44; font-size: 0.8em; padding-right:5px;'><b>".$mg->genome_id."</b></td>".
 	  "<td style='color:#374F44; font-size: 0.8em; padding-right:5px;'><b>".$mg->id."</b></td>".
	      "<td style='color:#374F44; font-size: 0.8em;'><b>".$mg_size."</b></td>".
		  "</tr></table></div></div>";

      if($odd_even){ $odd_even = 0 } else { $odd_even = 1 }; 
    }
    if ($count_private) {
      $private_container .= "</div>";
    }

    $shared_container = "<div id='shared_table' style='width: 920px; border: 1px solid rgb(143, 188, 63); padding: 20px; font-weight: bold;'>you currently have no shared metagenomes</div>";
    $odd_even = 1;
    $count_shared = scalar @$shared_metagenomes;
    if ($count_shared) {
      $shared_container = "<div id='shared_table' style='width: 960px; border: 1px solid rgb(143, 188, 63); height: 200px; overflow-x: hidden; overflow-y: auto;'>";
    }
    $num_shared = $count_shared;
    if ($count_shared > 500) {
      $num_shared = "500 of $count_shared total";
    }
    @$shared_metagenomes = sort { $b->_id <=> $a->_id } @$shared_metagenomes;
    splice(@$shared_metagenomes, 500);
    foreach my $mg (sort { $a->genome_name cmp $b->genome_name } @$shared_metagenomes) {
      $shared_container .= "<div class='metagenome_item".($odd_even ? "_odd" : "_even")."'><div class='metagenome_item_title'><a class='metagenome_link' href='metagenomics.cgi?page=MetagenomeOverview&metagenome=".$mg->genome_id."'>".$mg->genome_name."</a></div>";
      $shared_container .= "<div class='metagenome_item_content'>";

      $shared_container .= "<table><tr><td style='color:#848484; font-size: 0.8em; width: 250px;'>PROJECT</td>".
	"<td style='color:#848484; font-size: 0.8em; width:100px;'>OWNER</td>".
	  "<td style='color:#848484; font-size: 0.8em; width:100px;'>ID</td>".
	    "<td style='color:#848484; font-size: 0.8em; width:100px;'>JOB</td>".
	      "<td style='color:#848484; font-size: 0.8em;'>SIZE</td></tr>";
      
      my $mg_size = $mg->size || 0;
      $mg_size = &format_number($mg_size);
      $shared_container .= "<tr><td style='color:#374F44; font-size: 0.9em; width: 250px;'><b>".$mg->project_name."</b></td>".
	"<td style='color:#374F44; font-size: 0.8em; padding-right:5px;'><b>".$mg->owner->firstname ." ".$mg->owner->lastname."</b></td>".
 	"<td style='color:#374F44; font-size: 0.8em; padding-right:5px;'><b>".$mg->genome_id."</b></td>".
 	  "<td style='color:#374F44; font-size: 0.8em; padding-right:5px;'><b>".$mg->id."</b></td>".
	      "<td style='color:#374F44; font-size: 0.8em;'><b>".$mg_size."</b></td>".
		  "</tr></table></div></div>";

      if($odd_even){ $odd_even = 0 } else { $odd_even = 1 }; 
    }
    if ($count_shared) {
      $shared_container .= "</div>";
    }

    $processing_container = "<div style='width: 920px; padding: 20px; font-weight: bold;' id='proc_table'>you currently have no metagenomes processing</div>";
    $odd_even = 1;
    $count_processing = scalar @$processing_metagenomes;
    if ($count_processing) {
      $processing_container = "<div style='width: 960px; border: 1px solid rgb(143, 188, 63); height: 200px; overflow-x: hidden; overflow-y: auto;' id='proc_table'><table width=960 style='border-collapse: collapse;'><thead><tr><th style='width: 200px;'>Name</th><th style='width: 200px;'>Project</th><th style='width: 100px;'>User</th><th style='width: 50px;'>ID</th><th style='width: 50px;'>Job</th><th style='width: 80px;'>Size</th><th style='width: 200px;'>Status</th></tr></thead><tbody>";
    }
    $num_proc = $count_processing;
    foreach my $mg (sort { $a->genome_name cmp $b->genome_name } @$processing_metagenomes) {
      my $mg_size = $mg->size || 0;
      $mg_size = &format_number($mg_size);
      my $mg_status = "";
      my $n_stages = @{$mg->stages};
      for (my $i = 0; $i < $n_stages; $i++) {
	my $stage  = $mg->stages->[$i];
	my $s      = $mg->status($stage);
	$mg_status = (ref $s) ? $s->status : 'not_started';
	next if ($mg_status eq 'complete');
	my $stage_number = $i + 1;
	$mg_status =~ s/_/ /g;
	$stage =~ s/_/ /g;
	$stage =~ s/status\.//;
	$mg_status = "[$stage_number/$n_stages] $stage: $mg_status";
	last;
      }
      my $owner_string = " - ";
      if ($mg->owner) {
	$owner_string = $mg->owner->firstname." ".$mg->owner->lastname;
      }
      $processing_container .= "<tr style='border-bottom: 1px solid gray; cursor: pointer;' onclick='window.top.location=\"metagenomics.cgi?page=JobDetails&job=".$mg->id."\"'><td>".($mg->genome_name||"-")."</td><td>".($mg->project_name||"-")."</td><td>$owner_string</td><td>".($mg->genome_id||"-")."</td><td>".($mg->id||"-")."</td><td>".($mg_size||"-")."</td><td>".($mg_status||"-")."</td></tr>";
      
      if($odd_even){ $odd_even = 0 } else { $odd_even = 1 }; 
    }
    $processing_container .= "</tbody></table></div>";
    
  }

  $html .= "<div style='background-color: rgb(143, 188, 63); color: white; width: 450px; font-weight: bold; padding-left: 5px; padding-top: 3px; padding-bottom: 3px; text-align: center; cursor: pointer;' onclick='if(document.getElementById(\"proc_table\").style.display==\"none\"){document.getElementById(\"proc_table\").style.display=\"\";}else{document.getElementById(\"proc_table\").style.display=\"none\";};'>currently processing metagenomes ($num_proc)</div>";
  $html .= $processing_container."<br>";
  $html .= "<div style='background-color: rgb(143, 188, 63); color: white; width: 450px; font-weight: bold; padding-left: 5px; padding-top: 3px; padding-bottom: 3px; text-align: center; cursor: pointer;' onclick='if(document.getElementById(\"priv_table\").style.display==\"none\"){document.getElementById(\"priv_table\").style.display=\"\";}else{document.getElementById(\"priv_table\").style.display=\"none\";};'>completed private metagenomes ($num_priv)</div>";
  $html .= $private_container;
  $html .= "<br>";
  $html .= "<div style='background-color: rgb(143, 188, 63); color: white; width: 450px; font-weight: bold; padding-left: 5px; padding-top: 3px; padding-bottom: 3px; text-align: center; cursor: pointer;' onclick='if(document.getElementById(\"shared_table\").style.display==\"none\"){document.getElementById(\"shared_table\").style.display=\"\";}else{document.getElementById(\"shared_table\").style.display=\"none\";};'>completed metagenomes shared by others ($num_shared)</div>";
  $html .= $shared_container;
  
  return $html;
}

sub format_number {
  my ($val) = @_;

  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}

  return $val;
}

sub make_nice {
  my ($val) = @_;
  if($val =~ /(-?\d+\.\d\d)\d+/){
    return $1;
  }   
  return $val;
}

sub display_content {
 return "blah";
}

=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub supported_rights {
  return [ [ 'view', 'metagenome', '*' ] ];
}

