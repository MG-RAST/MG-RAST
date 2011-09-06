package MGRAST::WebPage::MetagenomeRecruitmentPlot;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use URI::Escape;

use FIG;
use GD;
use WebColors;
use WebComponent::WebGD;

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset is_public_metagenome );

1;

=pod

=head1 NAME

MetagenomeRecruitmentPlot 

=head1 DESCRIPTION


=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut


sub init {
  my ($self) = @_;

  $self->title('Recruitment Plot');

  # register components
  $self->application->register_action($self, 'download_fragments', 'download_fragments');
  $self->application->register_component('Table', 'Fragments_table');
  $self->application->register_component('Ajax', 'DisplayPlot');
  $self->application->register_component('FilterSelect', 'OrganismSelect');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  # sanity check on job
  if ($id) { 
    my $job;
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $id }); };
    unless ($job) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);
    
    # init the metagenome database
    my $mgdb = MGRAST::MetagenomeAnalysis->new($job);
    unless ($mgdb) {
      #
      # See if this job is a mgrast1 job
      #
      if (-f $job->directory() . "/proc/taxa.gg.allhits")
      {
	  my $g = $job->genome_id();
	  my $jid = $job->id();
	  my $url = "http://metagenomics.nmpdr.org/v1/index.cgi?action=ShowOrganism&initial=1&genome=$g&job=$jid";
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'. <p>" .
			    "This job appears to have been processed in the MG-RAST Version 1 server. You may " .
			    "browse the job <a href='$url'>using that system</a>.");
      }
      else
      {
	  $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      }
      return 1;
    }
    #
    # hardcoded badness
    #
    unless($self->app->cgi->param('evalue')){
      $self->app->cgi->param('evalue', '0.01');
    }
    $mgdb->query_load_from_cgi($self->app->cgi, "SEED:seed_genome_tax");
    $self->data('mgdb', $mgdb);
  }

  return 1;
}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # init some variables
  my $error = '';
  my $job = $self->data('job');
  my $cgi = $self->application->cgi;
  my $fig = new FIG;
  my $application = $self->application;
  my $html = "";

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';

  unless($metagenome) {
    $error = "<p><em>No metagenome id given.</em></p>";
    $self->application->add_message('warning', 'No metagenome id given.');
  }

  # put metagenome name together
  my $mg_name = ($job) ? $job->genome_name." (".$job->genome_id.")" : '';

  # reference genome
  my $ref_genome = $cgi->param('ref_genome') || ''; 
  unless($ref_genome){
    $html = "<p><span style='font-size: 1.6em'><b>Recruitment Plot for $mg_name</b></span></p><p style='width: 600px;'>Please select a reference genome below. The list of organisms is ordered by the number metagenome fragments that map to the organism as shown in parentheses. Note a genome will not be shown in this list unless it has at least one hit.</p>";

    # get a rast master
    my $rast = $application->data_handle('MGRAST');

    # create the select organism component
    my $organism_select_component = $application->component('OrganismSelect');
    
    #get genomes hit
    my $data = $self->data('mgdb')->get_taxa_counts("SEED:seed_genome_tax");
    my $genome_list = [];
    
    foreach (@$data){
      my ($taxonomy, $count) = @$_;
      my $taxa = $self->data('mgdb')->split_taxstr($taxonomy);
      my $organism = $self->data('mgdb')->key2taxa($taxa->[scalar(@$taxa)-1]);
      my $genome_id = $self->data('mgdb')->get_tax2genomeid($taxonomy);

      push(@$genome_list, [$genome_id, $organism." (".$count.")", $count]);
    }

    my @sorted_genome_list = sort {$b->[2] <=> $a->[2]} @$genome_list;
    my $org_values = [];
    my $org_labels = [];
    foreach my $line (@sorted_genome_list) {
      push(@$org_values, $line->[0]);
      push(@$org_labels, $line->[1]);
    }
    $organism_select_component->values( $org_values );
    $organism_select_component->labels( $org_labels );
    $organism_select_component->name('ref_genome');
    $organism_select_component->width(600);
    
    $html .= $self->start_form('select_comparison_organism_form', { 'metagenome' => $metagenome } );
    $html .= "<div id='org_select'>".$organism_select_component->output() . "<input type='submit' value='select'>" . $self->end_form()."</div>";
 
    return $html;
  } 

  my ($ref_genome_name, $ref_genome_length, $ref_genome_num_PEGs, $ref_genome_num_RNAs, $ref_genome_tax) = $fig->get_genome_stats($ref_genome);  

  #check if contig is specified
  my $use_contig = $cgi->param('contig') || ''; 
  
  # abort if error
  if ($error) {
    return "<h2>An error has occured:</h2>\n".$error;
  }

  #Ajax to html
  $html = $application->component('DisplayPlot')->output();

  # write title + intro
  my $genome_link = "<a href='http://www.nmpdr.org/linkin.cgi?genome=fig|" . $ref_genome . "' target='_Blank'>" . $ref_genome . "</a>";

  $html .= "<p><span style='font-size: 1.6em'><b>Recruitment Plot for $mg_name</b></span></p>";
  $html .= "<p><span style='font-size: 1.2em'><b> Fragments mapped on ".$ref_genome_name." (".$genome_link.")</b></span></p><br>";
  $html .= "<div id='plot_div'></div>";
  $html .= "<img src='./Html/clear.gif' onload='execute_ajax(\"loadPlot\", \"plot_div\", \"plot_load\");'><br><br>";

  $html .= $self->start_form('plot_load', { metagenome => $metagenome, ref_genome => $ref_genome, evalue => ($cgi->param("evalue") || ""), bitscore => ($cgi->param("bitscore") || ""), identity => ($cgi->param('identity') || ""), align_len => ($cgi->param('align_len') || "")});
  $html .= $self->end_form();
  return $html;

}

sub loadPlot {
  my ($self) = @_;
  
  # init some variables
  my $cgi = $self->application->cgi;
  my $fig = new FIG;
  my $application = $self->application;
  my $html = "";
  my $ref_genome = $cgi->param('ref_genome');
  my $metagenome = $cgi->param('metagenome');

  # default production values
#   my $width = 1000;
#   my $height = 250;
#   my $offset = 5; 

#   my $contig_height = 7;

#   my $peg_offset = 15;
#   my $peg_height = 5; 

#   my $fragment_offset = 25;
#   my $fragment_height = 5;
#   my $fragment_diff = 3;

  # special
  my $width = 960;
  my $height = 200;
  my $offset = 5; 

  my $show_contig = 0;
  my $contig_height = 7;

  my $peg_offset = ($show_contig ? ($contig_height * 2) : 2);
  my $peg_height = 5; 

  my $fragment_offset = ($show_contig ? ($contig_height * 2) : 2) + $peg_height + 5;
  my $fragment_height = 2;
  my $fragment_diff = 2;

  my $image_center = ($width-($offset * 2))/2;

  my $fragments_table = $application->component('Fragments_table');
  my $fragment_data = [];

  # some reference genome details
  my ($ref_genome_name, $ref_genome_length, $ref_genome_num_PEGs, $ref_genome_num_RNAs, $ref_genome_tax) = $fig->get_genome_stats($ref_genome);

  #query database. returns @$ where rows are: fragment_id, peg_id, beginning, end, e-value
  my $query = $self->data('mgdb')->get_recruitment_plot_data($ref_genome);

  #if empty quit
  if(scalar @$query == 0){
    return "<p>No fragments found for <b>" . $ref_genome_name ." (" . $ref_genome . ")</b></p><p>» <a href='metagenomics.cgi?page=MetagenomeRecruitmentPlot&metagenome=" . $metagenome . "'>click to select new reference genome</a></p>";
  }
  
  my %data;
  my %pegs_hit;
  foreach my $row (@$query){
    my $peg_name_start_stop = $fig->feature_location($row->[1]);
    next unless $peg_name_start_stop;
    my $contig_name = $fig->contig_of($peg_name_start_stop);

    unless(exists $data{$contig_name}->{Frag}){
      $data{$contig_name}->{Frag} = [];
    }

    unless(exists $data{$contig_name}->{Peg}){
      $data{$contig_name}->{Peg} = [];
    }


    if($peg_name_start_stop =~ /(\d+)_(\d+)$/){      
      my($peg_start,$peg_end, $peg_strand)=($1, $2, 0);
      if($peg_end < $peg_start){
	my $tmp;
	$tmp = $peg_start;
	$peg_start = $peg_end;
	$peg_end = $tmp;
	$peg_strand = 1;
      }
      unless(defined $pegs_hit{$row->[1]}){
	push(@{$data{$contig_name}->{Peg}}, [$row->[1], $peg_start, $peg_end, 1, $peg_strand]);
	$pegs_hit{$row->[1]}=1;
      }
      
      my($frag_start,$frag_end)=($row->[2], $row->[3]);
      my $temp_fuction = $fig->function_of($row->[1]);
      push(@{$data{$contig_name}->{Frag}}, [$row->[0], ($frag_start + $peg_start), ($frag_end + $peg_start), $row->[4], $peg_strand, $row->[1], $temp_fuction, $contig_name]);
    }
  }

  my $total_ln = 0;
  $ref_genome_num_PEGs = 0;  
  foreach my $contig_name (keys %data){
    $data{$contig_name}->{Length} = $fig->contig_ln($ref_genome, $contig_name);
    $total_ln += ($data{$contig_name}->{Length} || 0);

    my $additional_pegs = $fig->all_features_detailed_fast($ref_genome, undef, undef, $contig_name);
    $ref_genome_num_PEGs += scalar @$additional_pegs; 
    foreach my $features (@$additional_pegs){
      if($features->[3] eq "peg"){
	next if defined $pegs_hit{$features->[0]};
	my ($peg_start, $peg_end, $peg_strand) = (undef, undef, 0);
	if($features->[1] =~ /(\d+)_(\d+)$/){
	  $peg_start = $1;
	  $peg_end = $2;
	}
	if($peg_end < $peg_start){
	  my $tmp;
	  $tmp = $peg_start;
	  $peg_start = $peg_end;
	  $peg_end = $tmp;
	  $peg_strand = 1;
	}
	push(@{$data{$contig_name}->{Peg}}, [$features->[0], $peg_start, $peg_end, 0, $peg_strand]);
      }
    }
  }

  my ($display_region, $region_start,  $region_end, $scale);

  $display_region = $total_ln;
  $region_start = 0;
  $region_end = $total_ln;
 
  my $center = $height / 2;
  my $image = new WebGD($width, $height);
  my $image_map = '<map name="plotmap">';

  $scale = (($total_ln) / ($width-($offset * 2)));
 
  my $white = $image->colorAllocate(255,255,255);
  my $black = $image->colorAllocate(0,0,0);
  my $alt_black = $image->colorAllocate(59,59,59);
  my $gray = $image->colorAllocate(211,211,211);
  my $alt_gray = $image->colorAllocate(169,169,169);
  my $blue = $image->colorAllocate(104,143,197);
  my $alt_blue = $image->colorAllocate(100,149,237);
  my $border_green = $image->colorAllocate(93,166,104);
  my $background_green = $image->colorAllocate(134,211,146);
 
  my $colors;
  foreach(@{WebColors::get_palette('gradient')}){
    push(@$colors, $image->colorAllocate($_->[0], $_->[1], $_->[2]));
  }
 
  $image->transparent($white);
  $image->interlaced('true');
  
  #draw 
  my $y1 = $center-$contig_height;
  my $y2 = $center+$contig_height;
  my @contig_colors = ([$border_green, $background_green], [$blue, $alt_blue]);
  my $color_flag = 0;

  my $bp_coverage = 0;
  my $num_frag = 0;
  my @contig_info;
  my $contig_num = 0;
  my @contig_keys = ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'W', 'X', 'Y', 'Z');
  my %fragments_for_download;

  my $contig_start = $offset;
  foreach my $contig (keys %data){ 
    my ($x1, $x2);
    
    $x1 = $contig_start;
    $x2 = $contig_start + (($data{$contig}->{Length} || 1) / $scale);

    if($show_contig){
      $image->filledRectangle($x1, $y1 , $x2, $y2, $contig_colors[$color_flag]->[0]);
      $image->filledRectangle($x1+2, $y1+2 , $x2-2, $y2-2, $contig_colors[$color_flag]->[1]);
    }

    my $contig_key = (($contig_num < 25) ? $contig_keys[$contig_num] : ( ($contig_keys[(int($contig_num / 25) - 1)]) . $contig_keys[($contig_num - (int($contig_num / 25) * 25))]));
    
    push @contig_info , [ $contig_key, $contig, $data{$contig}->{Length}];
    $contig_num++;
    
    if(($x2 - $x1) > (((length($contig) + length($contig_key)) * 5) + 6)){
      $image->string(gdSmallFont, ($x1 + 3), ($y1+1), $contig_key." ".$contig, $white);
    } elsif(($x2 - $x1) > ((length($contig_key) * 5) + 5)){
      $image->string(gdSmallFont, ($x1 + 3), ($y1+1), $contig_key, $white);
    }

    foreach my $peg (sort {$a->[3] <=> $b->[3]} @{$data{$contig}->{Peg}}){
      my ($x1, $x2, $y1, $y2);
      
      $x1 = $contig_start + ($peg->[1] / $scale);
      $x2 = $contig_start + ($peg->[2] / $scale);
            
      unless($peg->[4]){
	$y1 = $center-($peg_offset + $peg_height);
	$y2 = $center-$peg_offset;
      } else {
	$y1 = $center+$peg_offset;
	$y2 = $center+($peg_offset + $peg_height);
      }
      
      my($color, $alt_color);
      if($peg->[3]){
	$color = $black;
	$alt_color = $alt_black;
      } else {
	$color = $gray;
	$alt_color = $alt_gray;
      }
      
      $image->filledRectangle($x1, $y1, $x2, $y2, $color);
      $image->rectangle($x1, $y1, $x2, $y2, $alt_color);
      
    } 

    #draw fragments 
    my $prev_x2_plus = 0;
    my $prev_y1_plus = 0;
    my $prev_x2_neg = 0; 
    my $prev_y1_neg = 0;
    foreach my $frag (sort {$a->[1] <=> $b->[1]} @{$data{$contig}->{Frag}}){
      my ($x1, $x2, $y1, $y2, $fill_y);

      $num_frag++;

      $x1 = $contig_start + ($frag->[1] / $scale);
      $x2 = $contig_start + ($frag->[2] / $scale);

      $bp_coverage += ($frag->[2] - $frag->[1]);      

      unless($frag->[4]){
	if($x1 >= $prev_x2_plus){
	  $y1 = $center-($fragment_offset + $fragment_height);
	  $y2 = $center-$fragment_offset; 
	} else {
	  $y1 = $prev_y1_plus-($fragment_height+$fragment_diff);
	  $y2 = $prev_y1_plus-$fragment_diff;
	} 
      } else {
	if($x1 >= $prev_x2_neg){
	  $y1 = $center+$fragment_offset;
	  $y2 = $center+($fragment_offset + $fragment_height);
	} else {
	  $y1 = $prev_y1_neg+($fragment_height+$fragment_diff);
	  $y2 = $prev_y1_neg+($fragment_height+$fragment_height+$fragment_diff);
	}
      }
      
      my $evalue = sprintf("%2.2e", $self->data('mgdb')->log2evalue($frag->[3]));
      my ($color) = $self->get_evalue_color_key($evalue);
      
      if($x1 eq $x2){ #|| $x1 < $x2){
	#$x2++;	
	$x2 = $x1 + 1;
      }
      
      $image->filledRectangle($x1, $y1, $x2, $y2, $colors->[$color]); 
      
      push @$fragment_data, ["<a href='metagenomics.cgi?page=MetagenomeSequence&metagenome=$metagenome&sequence=".$frag->[0]."' target='_Blank'>".$frag->[0]."</a>", $frag->[7], "<a href='http://www.nmpdr.org/linkin.cgi?id=".$frag->[5]."' target='_Blank'>".$frag->[5]."</a>", $frag->[6], $frag->[1], $frag->[2], $evalue]; 

      unless(defined $fragments_for_download{all}){
	$fragments_for_download{all} = ();
      } 
      push @{$fragments_for_download{all}}, $frag->[0];
      unless(defined $fragments_for_download{$frag->[7]}){
	$fragments_for_download{$frag->[7]} = ();
      }
      push @{$fragments_for_download{$frag->[7]}}, $frag->[0];

      unless($frag->[4]){
	$prev_x2_plus = $x2;
	$prev_y1_plus = $y1;
	$prev_x2_neg = 0;
	$prev_y1_neg = 0;
      } else {
	$prev_x2_plus = 0;
	$prev_y1_plus = 0;
	$prev_x2_neg = $x2;
	$prev_y1_neg = $y1;
      }
    }
    if($color_flag){$color_flag=0;} else {$color_flag=1;}
    $contig_start = $x2;
  }

  my $display_ln = int(($region_end - $region_start) / 1000);
  if($display_ln > 1000){
    $display_ln = ($display_ln / 1000);
    $display_ln =~ s/^(\d+\.\d).*/$1 Mbp/g;
  } else {
    $display_ln .= " Kbp";
  }

  #additional analysis
  my %hist_data;
  foreach my $contig (keys %data){
    foreach my $frag (@{$data{$contig}->{Frag}}){
      my ($tmp) = $self->get_evalue_color_key(sprintf("%2.2e", $self->data('mgdb')->log2evalue($frag->[3])));
      unless(exists $hist_data{$tmp}){
	$hist_data{$tmp} = 1;
      } else {
	$hist_data{$tmp} += 1;
      }
    }
  }

  my $genome_link = "<a href='http://www.nmpdr.org/linkin.cgi?genome=fig|" . $ref_genome . "' target='_Blank'>" . $ref_genome . "</a>"; 
 
  my $display_ref_ln = int($ref_genome_length / 1000);
  if($display_ref_ln > 1000){
    $display_ref_ln = ($display_ref_ln / 1000);
    $display_ref_ln =~ s/^(\d+\.\d).*/$1 Mbp/g;
  } else {
    $display_ref_ln .= " Kbp";
  }
  
  my ($num_features) = (0);
  foreach my $cont (keys %data){
    map {if($_->[3] eq 1){$num_features++}} @{$data{$cont}->{Peg}};
  }

  my $percent_cov = $bp_coverage / $ref_genome_length;
  if ($percent_cov =~ /e/) {
    my ($temp_y, $temp_z) = split(/e/, $percent_cov);
    $percent_cov = sprintf("%.3f", $temp_y) . 'e' . $temp_z;
  } else {
    $percent_cov = sprintf("%.3f", $percent_cov);
  }

#   $html .= "<div style='float: left; height: 75px; width : 300px; padding-right: 10px;'>";
#   $html .= "<table>";
#   $html .= "<tr><td class='table_first_row'># Fragments mapped</td><td class='table_first_row'># Features covered</td><td class='table_first_row'>Total # of features</td>";
#   $html .= "<tr><td><center>".$self->format_number($num_frag)."</center></td><td><center>".$self->format_number($num_features)."</center></td><td><center>".$self->format_number($ref_genome_num_PEGs)."</center></td></tr>";
#   $html .= "</table>";
#   $html .= "</div>";

  $html .= "<ul style='margin: 0; padding: 0;  padding-bottom: 10px; padding-right: 15px; float: left; width: 300px; text-align: right; list-style-image:none; list-style-position:outside; list-style-type:none; color:#273E53; font-size:12px; line-height:12px;'>";

  $html .= "<li style='padding-top:5px; height: 20px; background:#F7F7F7; border-bottom:1px dashed #D2DADA; border-top:1px dashed #D2DADA;'>".
    "<span style='float: left; text-align: left; color:black; font-style: italic;'># of fragments hitting features</span>".$self->format_number($num_frag)."</li>";

  $html .= "<li style='padding-top:5px; height: 20px; 1px dashed #D2DADA; border-bottom:1px dashed #D2DADA;'>".
    "<span style='float: left; text-align: left; color:black; font-style: italic;'># of features hit</span>".$self->format_number($num_features)."</li>";

  $html .= "<li style='padding-top:5px; height: 20px; 1px dashed #D2DADA; background:#F7F7F7; border-bottom:1px dashed #D2DADA;'>".
    "<span style='float: left; text-align: left; color:black; font-style: italic;'># of features in reference genome</span>".$self->format_number($ref_genome_num_PEGs)."</li>";

  $html .= "</ul>";

  $html .= "<div style='width : 960px;'>The reference genome " . $ref_genome_name  . " (" . $genome_link . ") contains ".$fig->number_of_contigs($ref_genome)." contig(s) and is ".$display_ref_ln. (($display_ref_ln eq $display_ln) ?  ".</p>" : " of which ".(scalar keys %data)." contig(s) and ".$display_ln. " are displayed.");
  $html .= $self->format_number($num_frag)." fragments map to ".$self->format_number($num_features)." of ".$self->format_number($ref_genome_num_PEGs)." features from the ".$ref_genome_name." genome. The total base pair length of all sequences mapping to this genome in ".$self->data('job')->genome_name." (".$self->data('job')->genome_id.")"." is ".$self->format_number($bp_coverage)." bp, resulting in approximately ".$percent_cov."X coverage.</div>";

  $html .= "<h3>Display options</h3>";

  # $html .= "<style type='text/css'>".
#     "div.plot_overview_image:hover {border: 2px dashed #273E53;}".
#     "</style>"; 

  my $num_sections = int( $ref_genome_length / 40000 );  
  my $section_width = 960 / $num_sections;

  $html .= "<div style='width: 960; height: 210px; overflow: hidden; margin-bottom: 15px;'>";
#"<div class='plot_overview_image' style='float: left; height: 200px; width: ".$section_width."; overflow:visible;'>".
  $html .= "<img src='".$image->image_src()."'/>";
#. "</div>";
  
  # for (my $i=0; $i < $num_sections; $i++){
#      $html .= "<div class='plot_overview_image' style='float: left; height: 200px; width: ".$section_width.";'></div>";
#   }
  
  $html .= "</div>";
  
  $html .= "<div style='clear:both; margin:0;'></div>";

  $html .= "<table>";
  $html .= "<tr><td>";
  $html .= '<h3>Distibution of hits by evalue</h3><img src="' .  $self->evalue_histagram(\%hist_data) . '">';
  $html .= "</td><td>";
  # Filter selections
  $html .= "<h3>Select filter options</h3>";
  $html .= $self->start_form('mg_stats', { metagenome => $metagenome, ref_genome => $ref_genome});
  $html .= '<div><table>';

  my @pvalue;
  for( my $i = 200; $i >= 20; $i-=10 ){
    push @pvalue, $i;
  }

  my @identity;
  for (my $i=100; $i>=40; $i-=2 ){
    push @identity, $i;
  }

  my ($alen_min, $alen_max) = $self->data('mgdb')->get_align_len_range("SEED:seed_genome_tax");
  my @alen;
  my $len50 = 0;
  for( my $i = $alen_max; $i > $alen_min; $i-=10 ){
    push @alen, $i;
    $len50 = 1 if ($i == 50);
  }
  push @alen, $alen_min;
  push @alen, 50 unless ($len50);
  @alen = sort { $a <=> $b } @alen;

  $html .= "<tr><th>Maximum e-value</th><td>" . 
    $cgi->popup_menu( -name => 'evalue', -default => $cgi->param("evalue") || 1e-3, 
		      -values => [0.01, 1e-3, 1e-5, 1e-7, 1e-10, 1e-15, 1e-20, 1e-25, 1e-30, 1e-40, 1e-50]) . "</td></tr>";
  #$html .= "<tr><th>Minimum p-value</th><td>".
  #  $cgi->popup_menu( -name => 'bitscore', 
  #		      -default => $cgi->param("bitscore") || '', -values => ['', @pvalue]);
  #$html .= " <em>leave blank for all</em></td></tr>";

  $html .= "<tr><th>Minimum percent identity</th><td>". 
    $cgi->popup_menu( -name => 'identity', -default => $cgi->param('identity') || '',
		      -values => ['', @identity ]);
  $html .= " <em>leave blank for all</em></td></tr>";

  $html .= "<tr><th>Minimum alignment length</th><td>". 
    $cgi->popup_menu( -name => 'align_len', -default => $cgi->param('align_len') || '',
		      -values => [ '', @alen ]);
  $html .= " <em>leave blank for all</em></td></tr>";

  $html .= "<tr><td style='height:5px;'></td></tr><tr><td colspan='2'>".$cgi->submit(-value=>'Re-compute results', -style=>'height:35px;width:150px;font-size:10pt;').
    " &laquo; <a href='".$self->url."metagenome=$metagenome&ref_genome=$ref_genome'>click here to reset</a>  &raquo;</td></tr>";

  $html .= "</table></div>";
  $html .= $self->end_form();
  $html .= "</td></tr>";
  $html .= "</table>";
  $html .= '<h3>Mapped Fragments</h3>';
  $html .= '<p>To download fragments in fasta form select contig and click <i>download</i> below. Additionally clicking the <i>export table</i> button will export the table below in tab seperated format.<p>';
  $html .= $self->start_form( 'download_fragments_form', { action => 'download_fragments', metagenome => $metagenome});
  $html .= "<table><tr><th>Fragments that map to </th><td><select name='fragment_ids'>";
  $html .= "<option value='".(join ",", @{$fragments_for_download{all}})."'>All contigs</option>";
  if(scalar keys %fragments_for_download > 2){
    foreach (@contig_info){
      $html .= "<option value='".(join ",", @{$fragments_for_download{$_->[1]}})."'>".$_->[0]." ".$_->[1]."</option>";
    }
  }
  $html .= "</select></td><td>".$cgi->submit(-value=>'Download')."</td></tr></table><br>";
  $html .= $self->end_form();

  $fragments_table->data($fragment_data);
  $fragments_table->columns( [{ 'name' => 'Fragment ID', 'filter' => 1, sortable => 1 },
			      { 'name' => 'Contig', 'filter' => 1, sortable => 1, operator => "combobox"},
			      { 'name' => 'Feature ID', 'filter' => 1, sortable => 1},
			      { 'name' => 'Function', 'filter' => 1, sortable => 1}, 
			      { 'name' => 'Contig Start', sortable => 1 },
			      { 'name' => 'Contig Stop', sortable => 1},
			      { 'name' => 'Evalue', sortable => 1} ] );
  $fragments_table->show_export_button({strip_html=>1, unfiltered=>1, title=>"Export table"});
  $fragments_table->show_top_browse(1);
  $fragments_table->show_bottom_browse(1);
  $fragments_table->items_per_page(50);
  $fragments_table->show_select_items_per_page(1);
  $html .= $fragments_table->output();
  
  return $html;
}

=pod

=item * B<evalue_histagram>()

Returns a creates a histagram from evalues data

=cut

sub evalue_histagram {
  my ($self, $data) = @_;

  my $width = 300;
  my $heigth = (scalar keys %$data) * 20;
  my $evalue_hist = new WebGD($width, $heigth);
  my $white = $evalue_hist->colorAllocate(255,255,255);
  my $black = $evalue_hist->colorAllocate(0,0,0);
  my $blue = $evalue_hist->colorAllocate(104,143,197);

  my $colors;
  foreach(@{WebColors::get_palette('gradient')}){
    push(@$colors, $evalue_hist->colorAllocate($_->[0], $_->[1], $_->[2]));
  }

  $evalue_hist->transparent($white);
  $evalue_hist->interlaced('true');
  my @data_sorted = (sort {$data->{$b} <=> $data->{$a}} keys %$data);
  my $scale = $data->{$data_sorted[0]} / ($width - 60);
  my @evalues = @{$self->get_evalue_ranges()};

#  my ($x1, $x2, $y1, $y2) = (41, 59, 0, ($heigth)); 
  my ($hx1, $hx2, $hy1, $hy2) = (1, 40, 1, 19); 
  my $x2;
  
  foreach my $key (sort {$a <=> $b} keys %$data){
    $x2 = 40 + int($data->{$key} / $scale);
 
    $evalue_hist->filledRectangle($hx2+2, $hy1, $x2, $hy2, $colors->[$key]);
 
    $evalue_hist->filledRectangle($hx1, $hy1, $hx2, $hy2, $colors->[$key]);
    $evalue_hist->string(gdSmallFont, ($hx1 + 3), ($hy1 +2), $evalues[$key], $white);

    my $stinglength = (length($data->{$key}) * 5) + 5;
    $evalue_hist->string(gdSmallFont,((($x2 < (40 + $stinglength)) ? ($x2+3) : ($x2-$stinglength))),($hy1+2),$data->{$key},$black);
    $hy1 += 20;
    $hy2 += 20;
  }
  return $evalue_hist->image_src();
}


=pod

=item * B<get_evalue_ranges>()

Returns a reference to an array of evalues

=cut

sub get_evalue_ranges {
  return [ 1e-50, 1e-40, 1e-30, 1e-25, 1e-20, 1e-15, 1e-10, 1e-7, 1e-5, 1e-3, 0.01];
}


=pod

=item * B<get_evalue_color_key>()

Returns the evalue color key

=cut

sub get_evalue_color_key {
  my ($self, $evalue) = @_;

  my $color = 0; # start with the first color in the palette
  my $ranges = $self->get_evalue_ranges;

  for (my $i=0; $i<scalar(@$ranges); $i++) {
    if ($evalue<=$ranges->[$i]) { 
      my $key = $ranges->[$i];
      if ($i==0) {
	$key = '< '.$key;
      }
      elsif ($i==scalar(@$ranges)-1) {
	$key = '> '.$key;
      }
      else {
	$key = $key.' <==> '.$ranges->[$i-1];
      }
      return ($color+$i, $key);
    }
  }
  return ($color+scalar(@$ranges), '> 10');
}

sub format_number{
  my ($self , $number) = @_;

  $number = $self unless (ref $self);

  my @reversed;
  my $counter = 3;
  
  my ($int , $float) = split( /\./ , $number); 
  my @digits = split "", $int;
  
  while ( @digits ){
    $counter--;
    my $dig = pop @digits ;
    push @reversed , $dig ;
    unless ($counter){
      push @reversed , "," if ( @digits );
      $counter = 3;
    }  
  }
  
  $int = reverse @reversed;
  $int = $int.".".$float if $float;
  
  return $int;
}

sub download_fragments {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();

  my @ids = split ",", $cgi->param('fragment_ids');

  my $content = $self->data('mgdb')->get_sequences_fasta(\@ids);
  
  print "Content-Type:application/x-download\n";  
  print "Content-Length: " . length($content) . "\n";
  print "Content-Disposition:attachment;filename=fasta_download.fna\n\n";
  print $content;

  exit;

}
