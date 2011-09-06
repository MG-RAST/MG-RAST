package MGRAST::WebPage::MetagenomeOverview;

# $Id: MetagenomeOverview.pm,v 1.71 2011-06-07 14:21:41 tharriso Exp $

use base qw( WebPage );

use strict;
use warnings;

use List::Util qw(first max min sum);
use Math::Round;
use Data::Dumper;
use WebConfig;
use WebComponent::WebGD;
use GD;

use Global_Config;
use MGRAST::Metadata;
use MGRAST::MetagenomeAnalysis2;

1;

=pod

=head1 NAME
s
MetagenomeOverview - an instance of WebPage which gives overview information about a metagenome

=head1 DESCRIPTION

Overview page about a metagenome

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Overview');

  $self->application->register_component('VerticalBarChart', 'vbar1');
  $self->application->register_component('PieChart', 'pchart1');
  $self->application->register_component('Table', 'metadata_tbl');
  $self->application->register_component('Ajax', 'ajax');

  $self->application->register_action($self, 'fasta_export', 'fasta_export');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # sanity check on job
  if ($id) { 
    my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $id });
    unless (ref($job)) {
      $self->app->error("Unable to retrieve the job for metagenome '$id'.");
      return 1;
    }
    $self->data('job', $job);
  }

  # init the metadata database
  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  # init the metagenome database
  my $mgdb = new MGRAST::MetagenomeAnalysis2( $self->app->data_handle('MGRAST')->db_handle );
  unless ($mgdb) {
    $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
    return 1;
  }
  $self->data('mgdb', $mgdb);

  $self->data('bin_size', 20);
  $self->data('tax_level', 'tax_phylum');
  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # get metagenome id
  my $mgid = $self->application->cgi->param('metagenome') || '';
  unless ($mgid) {
    $self->application->redirect('MetagenomeSelect');
    $self->application->add_message('info', 'Redirected from Metagenome Overview: No metagenome id given.');
    $self->application->do_redirect();
    exit;
  }

  my $job  = $self->data('job');
  my $mgdb = $self->data('mgdb');
  my $mddb = $self->data('mddb');
  my $user = $self->application->session->user;

  my $is_rna = $job->data('rna_only') ? 1 : 0;

  # get project information
  my $project_link = "";
  my $jobdbm = $self->application->data_handle('MGRAST');
  my $projectjob = $jobdbm->ProjectJob->get_objects( { job => $job } );
  my $project_jobs = [];
  if (scalar(@$projectjob)) {
    my $project = $projectjob->[0]->project;
    $project_jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
    $self->{project} = $project;
    my $all_meta = $jobdbm->ProjectMD->get_objects( { project => $project } );
    my $meta_hash = {};
    %$meta_hash = map { $_->{tag} => $_->{value} } @$all_meta;
    $self->{meta_info} = $meta_hash;
    $project_link = "<a href='?page=MetagenomeProject&project=".$self->{project}->_id."'>".$self->{project}->name."</a>";
  }

  # get job metadata
  my $md_seq_type   = $job->sequence_type || '';
  my $md_biome      = $jobdbm->MetaDataEntry->get_objects( { tag => 'biome-information_envo_lite', job => $job } );
  my $md_location   = $jobdbm->MetaDataEntry->get_objects( { tag => 'sample-origin_location', job => $job } );
  my $md_country    = $jobdbm->MetaDataEntry->get_objects( { tag => 'sample-origin_country', job => $job } );
  my $md_seqmethod  = $jobdbm->MetaDataEntry->get_objects( { tag => 'sequencing_sequencing_method', job => $job } );
  my $md_pubmed     = $jobdbm->MetaDataEntry->get_objects( { tag => 'external-ids_pubmed_id', job => $job } );
  my $md_ncbi       = $jobdbm->MetaDataEntry->get_objects( { tag => 'external-ids_project_id', job => $job } );
  my $md_greengenes = $jobdbm->MetaDataEntry->get_objects( { tag => 'external-ids_greengenes_study_id', job => $job } );
  my $md_gold       = $jobdbm->MetaDataEntry->get_objects( { tag => 'external-ids_gold_id', job => $job } );
  my $md_mims       = $jobdbm->MetaDataEntry->get_objects( { tag => 'external-ids_mims_id', job => $job } );
  my $md_coordinate = $self->data('mddb')->get_coordinates($job);
  my $md_date_time  = $self->data('mddb')->get_date_time($job);
  my $md_enviroment = $self->data('mddb')->get_env_package($job);
  my $md_region     = [];

  foreach my $md (($md_location, $md_country)) {
    if (@$md > 0) { push @$md_region, $mddb->unencode_value($md->[0]->{tag}, $md->[0]->{value}); }
  }

  # short info
  my $html = $self->application->component('ajax')->output . "<p><table><tr>";
  $html .= "<td style='font-size:large;'><b>MG-RAST ID</b></td>";
  $html .= "<td style='font-size:large;'>&nbsp;&nbsp;&nbsp;$mgid</td>";
  $html .= "<td>&nbsp;&nbsp;&nbsp;<a class='nav_top' href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$mgid'><img src='./Html/mg-download.png' style='width: 20px; height: 20px;' title='Download $mgid'></a></td>";
  $html .= "<td>&nbsp;&nbsp;&nbsp;<a class='nav_top' href='metagenomics.cgi?page=Analysis&metagenome=$mgid'><img src='./Html/analysis.gif' style='width: 20px; height: 20px;' title='Analyze $mgid'></a></td>";
  $html .= "</tr></table></p>";
  $html .= "<p><div style='width: 660px'>";
  $html .= "<div style='float: left'><table>";
  $html .= "<tr><td><b>Metagenome Name</b></td><td>".$job->name."</td></tr>";
  $html .= "<tr><td><b>MG-RAST Job Number</b></td><td>".$job->job_id."</td></tr>";
  if ($self->{project}) {
    $html .= "<tr><td><b>PI</b></td><td><a href='mailto:".($self->{meta_info}->{PI_email}||"")."'>".($self->{meta_info}->{PI_firstname}||"")." ".($self->{meta_info}->{PI_lastname}||"")."</a></td></tr>";
    $html .= "<tr><td><b>Organization</b></td><td>".($self->{meta_info}->{PI_organization}||"")."</td></tr>";
  }
  $html .= "</table></div><div style='float: right'><table>";
  $html .= "<tr><td><b>NCBI Project ID</b></td><td>".(scalar(@$md_ncbi) ? join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/genomeprj/".$_."' target=_blank>".$_."</a>" } split(/, /, $md_ncbi->[0]->{value})) : "-")."</td></tr>";
  $html .= "<tr><td><b>GOLD ID</b></td><td>".(scalar(@$md_gold) ? join(", ", map { "<a href='http://genomesonline.org/cgi-bin/GOLD/bin/GOLDCards.cgi?goldstamp=".$_."' target=_blank>".$_."</a>" } split(/, /, $md_gold->[0]->{value})) : "-")."</td></tr>";
  $html .= "<tr><td><b>PubMed ID</b></td><td>".(scalar(@$md_pubmed) ? join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/pubmed/".$_."' target=_blank>".$_."</a>" } split(/, /, $md_pubmed->[0]->{value})) : "-")."</td></tr>";
  $html .= "</table></div></div></p>";
  if ($self->{project}) {
    $html .= "<div style='clear: both; height: 10px'></div>";
  }
  if ($user && $user->has_right(undef, 'edit', 'metagenome', $mgid)) {    
    $html .= "<p><div class='quick_links'><ul>";
    $html .= "<li><a href='?page=JobShare&metagenome=$mgid&job=".$job->job_id."'>Share</a></li>";
    $html .= "<li><a href='?page=MetaDataMG&metagenome=$mgid'>Edit Metadata</a></li>";
    $html .= "<li><a href='?page=PublishGenome&metagenome=$mgid&job=".$job->job_id."'>Make Public</a></li></ul></div></p>";
  }

  # get sequence data
  my $job_stats   = $job->stats();
  my $raw_bps     = exists($job_stats->{bp_count_raw}) ? $job_stats->{bp_count_raw} : 0;
  my $qc_bps      = exists($job_stats->{bp_count_preprocessed}) ? $job_stats->{bp_count_preprocessed} : 0;
  my $raw_seqs    = exists($job_stats->{sequence_count_raw}) ? $job_stats->{sequence_count_raw} : 0;
  my $qc_seqs     = exists($job_stats->{sequence_count_preprocessed}) ? $job_stats->{sequence_count_preprocessed} : 0;
  my $raw_len_avg = exists($job_stats->{average_length_raw}) ? $job_stats->{average_length_raw} : 0;
  my $qc_len_avg  = exists($job_stats->{average_length_preprocessed}) ? $job_stats->{average_length_preprocessed} : 0;
  my $raw_len_std = exists($job_stats->{standard_deviation_length_raw}) ? $job_stats->{standard_deviation_length_raw} : 0;
  my $qc_len_std  = exists($job_stats->{standard_deviation_length_preprocessed}) ? $job_stats->{standard_deviation_length_preprocessed} : 0;
  my $raw_gc_avg  = exists($job_stats->{average_gc_content_raw}) ? $job_stats->{average_gc_content_raw} : 0;
  my $qc_gc_avg   = exists($job_stats->{average_gc_content_preprocessed}) ? $job_stats->{average_gc_content_preprocessed} : 0;
  my $raw_gc_std  = exists($job_stats->{standard_deviation_gc_content_raw}) ? $job_stats->{standard_deviation_gc_content_raw} : 0;
  my $qc_gc_std   = exists($job_stats->{standard_deviation_gc_content_preprocessed}) ? $job_stats->{standard_deviation_gc_content_preprocessed} : 0;

  $html .= "<p><div style='width: 710px;'>";
  $html .= "<table><tr><th>Statistic Summary</th><th>GSC MIxS info</th></tr>";
  $html .= "<tr><td><div class='metagenome_info' style='width: 350px;'><ul style='margin: 0; padding: 0;'>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Upload: Size</label><span style='width: 230px'>".format_number($raw_bps)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Upload: Sequences Count</label><span style='width: 230px'>".format_number($raw_seqs)."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Upload: Mean Sequence Length</label><span style='width: 230px'>".format_number($raw_len_avg)." &plusmn; ".format_number($raw_len_std)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Upload: Mean GC percent</label><span style='width: 230px'>".format_number($raw_gc_avg)." &plusmn; ".format_number($raw_gc_std)." %</span></li>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Size</label><span style='width: 230px'>".format_number($qc_bps)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Sequences Count</label><span style='width: 230px'>".format_number($qc_seqs)."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean Sequence Length</label><span style='width: 230px'>".format_number($qc_len_avg)." &plusmn; ".format_number($qc_len_std)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean GC percent</label><span style='width: 230px'>".format_number($qc_gc_avg)." &plusmn; ".format_number($qc_gc_std)." %</span></li>";
  $html .= "</ul></div></td><td><div class='metagenome_info' style='width: 300px; margin-left: 10px;'><ul style='margin: 0; padding: 0;'>";
  $html .= "<li class='even'><label style='text-align: left;'>Investigation Type</label><span style='width: 180px'>Metagenome".(($md_seq_type =~ /wgs|amplicon/i) ? ": $md_seq_type" : "")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Project Name</label><span style='width: 180px'>".($self->{project} ? $project_link : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Latitude and Longitude</label><span style='width: 180px'>".(scalar(@$md_coordinate) ? join(", ", @$md_coordinate) : "-, -")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Region, Country and/or Sea</label><span style='width: 180px'>".(scalar(@$md_region) ? join("<br>", @$md_region) : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Collection Date</label><span style='width: 180px'>".($md_date_time ? $md_date_time : "-")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Environment (Biome)</label><span style='width: 180px'>".(scalar(@$md_biome) ? $md_biome->[0]->{value} : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Environment (Feature)</label><span style='width: 180px'>-</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Environment (Material)</label><span style='width: 180px'>-</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Environmental Package</label><span style='width: 180px'>".($md_enviroment ? $md_enviroment : "-")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Sequencing Method</label><span style='width: 180px'>".(scalar(@$md_seqmethod) ? $md_seqmethod->[0]->{value} : "-")."</span></li>";
  $html .= "</ul></div></td></tr></table>";
  $html .= "</div></p>";

  # link to similar mgs
  $html .= "<p>";
  if (scalar(@$md_biome)) {
    $html .= "<a href='metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=1&type_q1=metadata&match_q1=1_1&extra_q1=biome-information_envo_lite&input_q1=".$md_biome->[0]->{value}."'>&raquo; find metagenomes within this biome</a><br>";
  } else {
    $html .= "&raquo; find metagenomes within this biome<br>";
  }
  if (scalar(@$md_country)) {
    $html .= "<a href='metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=1&type_q1=metadata&match_q1=1_1&extra_q1=sample-origin_country&input_q1=".$mddb->unencode_value($md_country->[0]->{tag}, $md_country->[0]->{value})."'>&raquo; find metagenomes within this country</a><br>";
  } else {
    $html .= "&raquo; find metagenomes within this country<br>";
  }
  if (scalar @$md_coordinate) {
    my ($lat, $lng) = @$md_coordinate;
    my $lat_10  = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 0.1, $lat + 0.1));
    my $lng_10  = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 0.1, $lng + 0.1));
    my $lat_30  = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 0.3, $lat + 0.3));
    my $lng_30  = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 0.3, $lng + 0.3));
    my $lat_100 = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 1.0, $lat + 1.0));
    my $lng_100 = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 1.0, $lng + 1.0));
    my $link = "metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=2&type_q1=metadata&type_q2=metadata&match_q1=2_1&match_q2=2_1&extra_q1=sample-origin_latitude&extra_q2=sample-origin_longitude";
    $html .= "&raquo; find metagenomes within <a href='$link&$lat_10&$lng_10'>10</a> | <a href='$link&$lat_30&$lng_30'>30</a> | <a href='$link&$lat_100&$lng_100'>100</a> kilometers of these coordinates";
  } else {
    $html .= "&raquo; find metagenomes within 10 | 30 | 100 kilometers of these coordinates";
  }
  $html .= "</p>";
  
  # project jobs
  if (exists($self->{meta_info}->{project_description})) {
    $html .= "<h3>Project Information</h3><div style='width:800px;'>".$self->{meta_info}->{project_description}."</div>";
  }

  # domain hits distribution
  my $dom_stats = $mgdb->get_domain_stats($job->job_id);
  my $dom_html  = '';
  if (@$dom_stats > 0) {
    my $total = 0;
    map {  $_->[1] ? $total += $_->[1] : '' } @$dom_stats;

    my $dom_pie = $self->application->component('pchart1');
    my @data = map { $total ? {title => $_->[0], 'data' => $_->[1], tooltip => sprintf("%.2f", ($_->[1] || 0) / $total * 100 )  . '%'} : { title => $_->[0] || 'unknown' ,
																	 data => $_->[1] || 'unknown' ,
																       } } @$dom_stats;

    $dom_pie->data(\@data);
    $dom_pie->size(200);
    $dom_pie->show_tooltip(1);
    $dom_pie->show_legend(1);
    $dom_pie->show_percent(1);
    
    $dom_html  = "<h3>Domain Hits Distribution</h3>";
    $dom_html .= "<p>The pie chart below is based on the combined taxonimic domain infomation of all the annotation source databases used by MG-RAST</p><br>";
    $dom_html .= $dom_pie->output();
  }

  # source hits distribution
  my $src_stats = $mgdb->get_source_stats($job->job_id);
  my $src_html  = '';
  if (scalar(keys %$src_stats) > 0) {
    my $src_vbar  = $self->application->component('vbar1');
    my $evalues   = ["-3 to -5", "-5 to -10", "-10 to -20", "-20 to -30", "-30 & less"];
    my $legend    = ["e-value (exponent)"];
    my $colors    = [ [[54,116,217], [128,176,255]], [[51,204,94], [128,255,164]], [[255,255,0], [255,252,150]], [[255,136,0], [255,187,110]], [[247,42,66], [255,193,200]] ];
    my $sources   = $mgdb->ach->sources();
    my (@data, @desc, @srcs);

    foreach my $type ( ('protein', 'ontology', 'rna') ) {
      foreach my $src (sort grep {$sources->{$_}->{type} eq $type} keys %$sources) {
	next if ($src eq 'GO');
	if (exists($src_stats->{$src}) && exists($src_stats->{$src}->{evalue})) {
	  push @srcs, $src;
	  push @data, [ $src_stats->{$src}->{evalue} ];
	  push @desc, $sources->{$src}->{description};
	}
      }
    }
    
    $src_vbar->data(\@data);
    $src_vbar->subsets($legend);
    $src_vbar->datasets(\@srcs);
    $src_vbar->supersets($evalues);
    $src_vbar->title_hovers(\@desc);
    $src_vbar->rotate_colors(1);
    $src_vbar->bar_color_set($colors);
    $src_vbar->show_percent(1);
    $src_vbar->scale_step(2);
    $src_vbar->show_counts(1);
    
    $src_html  = "<h3>Source Hits Distribution<a target=_blank href='metagenomics.cgi?page=Sources' style='font-size:14px;padding-left:10px;'>[?]</a></h3>";
    $src_html .= "<p>The barchart below shows the number of hits from each annotation source.  The hits are broken down by what e-value range.  Each bar segment represents a percentage of the total hits across all sources, allowing for cross compairison of hits within different sources and e-value ranges.</p>";
    $src_html .= "<table><tr><td>" . $src_vbar->output . "</td><tr><td>" . $src_vbar->legend . "</td></tr></table>";
  }

  if ($dom_html && $src_html) {
    $html .= "<br><br><table><tr><td>$dom_html</td><td>$src_html</td></tr></table><br>";
  }
  elsif ($dom_html) {
    $html .= "<br><br>$dom_html<br>";
  }
  elsif ($src_html) {
    $html .= "<br><br>$src_html<br>";
  }

  # rank abundance plot
  $html .= qq~<h3>Rank Abundance Plot</h3>
<p>The plot below shows the species abundances in a ranked plot. On the x-axis you will see the abundance rank from left to right. The most abundant species is ranked first, the second most abundant is next and so on. Only the top 50 abundant species are shown. On the Y-axis you will see a log scale of the relative abundance.</p>
<p>The rank abundance curve provide a means for visually representing species richness and species evenness. Species richness can be viewed as the number of different species on the chart i.e., how many species were ranked. Species evenness is derived from the slope of the line that fits the graph. A steep gradient indicates low evenness as the high ranking species have much higher abundances than the low ranking species. A shallow gradient indicates high evenness as the abundances of different species are similar.</p>
<img src='./Html/clear.gif' onload='execute_ajax("get_abund_plot", "rank_abund_div", "metagenome=$mgid");'>
<div id='rank_abund_div'></div>~;
  
  # rarefaction curve
  $html .= qq~<h3>Rarefaction Curve</h3>
<p>The plot below shows the species richness as represented by a rarefaction curve. This curve is a plot of the number of species as a function of the number of individuals sampled. On the left, a steep slope indicates that a large fraction of the species diversity remains to be discovered. If the curve becomes flatter to the right, a reasonable number of individuals is sampled: more intensive sampling is likely to yield only few additional species.</p>
<p>Sampling curves generally rise very quickly at first and then level off towards an asymptote as fewer new species are found per unit of individuals collected. Rarefaction curves are created by randomly re-sampling the pool of N samples multiple times and then plotting the average number of species found in each sample (1,2, ... N).</p>
<img src='./Html/clear.gif' onload='execute_ajax("get_rare_curve", "rare_curve_div", "metagenome=$mgid");'>
<div id='rare_curve_div'></div>~;

  # sequence length histogram
  my @len_raw_hist = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->job_id, 'len', 'raw') };
  my @len_qc_hist  = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->job_id, 'len', 'qc') };

  my $len_min = min($len_raw_hist[0][0], $len_qc_hist[0][0]);
  my $len_max = max($len_raw_hist[-1][0], $len_qc_hist[-1][0]);

  my $len_raw_bins = @len_raw_hist ? &get_bin_set(\@len_raw_hist, $len_min, $len_max, $self->data('bin_size')) : [];
  my $len_qc_bins  = @len_qc_hist  ? &get_bin_set(\@len_qc_hist, $len_min, $len_max, $self->data('bin_size')) : [];
  my $len_raw_data = join("~", map { $_->[0] .";;" . $_->[1] } @$len_raw_bins);
  my $len_qc_data  = join("~", map { $_->[0] .";;" . $_->[1] } @$len_qc_bins);

  $html .= "<h3>Sequence Length Histogram</h3>";
  $html .= "<p>The histograms below show the distribution of sequence lengths in basepairs for this metagenome. Each position represents the number of sequences within a length bp range.</p><p>The data used in these graphs are based on raw upload and post QC sequences.</p>";

  if (@$len_raw_bins > 1) {
    $html .= qq~<div id='static2'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static2").style.display = "none";
  document.getElementById("dynamic2").style.display = "";
  save_image("length_hist_raw");
  document.getElementById("length_hist_rawcanvas").style.display = "";
  document.getElementById("length_hist_raw").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic2'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static2").style.display = "";
  document.getElementById("dynamic2").style.display = "none";
  document.getElementById("length_hist_rawcanvas").style.display = "none";
  document.getElementById("length_hist_raw").style.display = "";'>
</div>
<div><div id='length_hist_raw'></div></div>
<input type='hidden' id='len_data_raw' value='$len_raw_data'>
<img src='./Html/clear.gif' onload='draw_histogram_plot("len_data_raw", "length_hist_raw", "bps", "Upload");'>~;
  } else {
    $html .= "<p><em>Raw sequence length histogram " . (@$len_raw_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }
  if (@$len_qc_bins > 1) {
    $html .= qq~<div id='static3'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static3").style.display = "none";
  document.getElementById("dynamic3").style.display = "";
  save_image("length_hist_qc");
  document.getElementById("length_hist_qccanvas").style.display = "";
  document.getElementById("length_hist_qc").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic3'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static3").style.display = "";
  document.getElementById("dynamic3").style.display = "none";
  document.getElementById("length_hist_qccanvas").style.display = "none";
  document.getElementById("length_hist_qc").style.display = "";'>
</div>
<div><div id='length_hist_qc'></div></div>
<input type='hidden' id='len_data_qc' value='$len_qc_data'>
<img src='./Html/clear.gif' onload='draw_histogram_plot("len_data_qc", "length_hist_qc", "bps", "Post QC");'>~;
  } else {
    $html .= "<p><em>QC sequence length histogram " . (@$len_qc_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }

  # sequence gc distribution
  my @gc_raw_hist = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->job_id, 'gc', 'raw') };
  my @gc_qc_hist  = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->job_id, 'gc', 'qc') };

  my $gc_raw_bins = @gc_raw_hist ? &get_bin_set(\@gc_raw_hist, 0, 100, $self->data('bin_size')) : [];
  my $gc_qc_bins  = @gc_qc_hist  ? &get_bin_set(\@gc_qc_hist, 0, 100, $self->data('bin_size')) : [];
  my $gc_raw_data = join("~", map { $_->[0] .";;" . $_->[1] } @$gc_raw_bins);
  my $gc_qc_data  = join("~", map { $_->[0] .";;" . $_->[1] } @$gc_qc_bins);

  $html .= "<h3>Sequence GC Distribution</h3>";
  $html .= "<p>The histograms below show the distribution of the GC percentage for this metagenome. Each position represents the number of sequences within a GC percentage range.</p><p>The data used in these graphs is based on raw upload and post QC sequences.</p>";

  if (@$gc_raw_bins > 1) {
    $html .= qq~<div id='static4'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static4").style.display = "none";
  document.getElementById("dynamic4").style.display = "";
  save_image("gc_percent_hist_raw");
  document.getElementById("gc_percent_hist_rawcanvas").style.display = "";
  document.getElementById("gc_percent_hist_raw").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic4'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static4").style.display = "";
  document.getElementById("dynamic4").style.display = "none";
  document.getElementById("gc_percent_hist_rawcanvas").style.display = "none";
  document.getElementById("gc_percent_hist_raw").style.display = "";'>
</div>
<div><div id='gc_percent_hist_raw'></div></div>
<input type='hidden' id='gc_data_raw' value='$gc_raw_data'>
<img src='./Html/clear.gif' onload='draw_histogram_plot("gc_data_raw", "gc_percent_hist_raw", "% gc", "Upload");'>~;
  } else {
    $html .= "<p><em>Raw GC distribution histogram " . (@$gc_raw_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }
  if (@$gc_qc_bins > 1) {
    $html .= qq~<div id='static5'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static5").style.display = "none";
  document.getElementById("dynamic5").style.display = "";
  save_image("gc_percent_hist_qc");
  document.getElementById("gc_percent_hist_qccanvas").style.display = "";
  document.getElementById("gc_percent_hist_qc").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic5'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static5").style.display = "";
  document.getElementById("dynamic5").style.display = "none";
  document.getElementById("gc_percent_hist_qccanvas").style.display = "none";
  document.getElementById("gc_percent_hist_qc").style.display = "";'>
</div>
<div><div id='gc_percent_hist_qc'></div></div>
<input type='hidden' id='gc_data_qc' value='$gc_qc_data'>
<img src='./Html/clear.gif' onload='draw_histogram_plot("gc_data_qc", "gc_percent_hist_qc", "% gc", "Post QC");'>~;
  } else {
    $html .= "<p><em>QC GC distribution histogram " . (@$gc_qc_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }

  # metadata table
  my $mdata = $mddb->get_metadata_for_table($job);
  if (@$mdata > 0) {
    my $mtable = $self->application->component('metadata_tbl');
    $mtable->width(800);
    $mtable->show_export_button({title => "Download Metadata", strip_html => 1});
    
    if ( scalar(@$mdata) > 25 ) {
      $mtable->show_top_browse(1);
      $mtable->show_bottom_browse(1);
      $mtable->items_per_page(25);
      $mtable->show_select_items_per_page(1); 
    }   
    $mtable->columns([ { name => 'Key'     , visible => 0 },
		       { name => 'Category', filter  => 1, sortable => 1, operator => 'combobox' },
		       { name => 'Question', filter  => 1, sortable => 1 },
		       { name => 'Value'   , filter  => 1, sortable => 1 }
		     ]);
    $mtable->data($mdata);
    $html .= "<h3>Metadata</h3>The table below contains contextual metadata describing sample location, acquisition, library construction, sequencing using <a href='http://gensc.org'>GSC</a> compliant metadata.<br><br>" . $mtable->output;
  }
  
  # pubmed abstracts
  if (scalar @$md_pubmed) {
    $html .= "<h3>Publication Abstracts";
    $html .= "<span style='font-size:12px;padding-left:15px;'>[" . join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/pubmed/".$_."' target=_blank>".$_."</a>" } split(/, /, $md_pubmed->[0]->{value})) . "]</span></h3>";
    $html .= "<a style='cursor: pointer; clear: both' onclick='if(this.innerHTML==\"show\"){this.innerHTML=\"hide\";document.getElementById(\"abstracts\").style.display=\"\";}else{document.getElementById(\"abstracts\").style.display=\"none\";this.innerHTML=\"show\"};'>show</a><div id='abstracts' style='display: none;'>";
    my @ids = split /, /, ( $md_pubmed->[0]->{value} || '' );
    foreach my $id (@ids) {
      $html .= $self->get_pubmed_abstract($id)."<br><br>";
    }
    $html .= "</div>";
  }

  # bottom padding
  $html .= "<br><br><br><br>";

  # form for fasta export
  $html .= $self->start_form('fasta_export_form');
  $html .= "<input type='hidden' name='metagenome' value='".$self->application->cgi->param('metagenome')."'>";
  $html .= "<input type='hidden' value='fasta_export' name='action'>";
  $html .= "<input type='hidden' name='cat' value='' id='fasta_export_cat'>";
  $html .= $self->end_form();

  return $html;
}

sub get_abund_plot {
  my ($self) = @_;

  my $html = "";
  my $mgdb = $self->data('mgdb');
  $mgdb->set_jobs([$self->application->cgi->param('metagenome')]);
  my $phylos = $mgdb->get_abundance_for_tax_level( $self->data('tax_level') );

  if (@$phylos > 1) {
    my @sort_phy = sort { $b->[2] <=> $a->[2] } @$phylos;
    if (@sort_phy > 50) {
      @sort_phy = @sort_phy[0..49];
    }
    my $rap_data = join("~", map { $_->[1] .";;" . $_->[2] } @sort_phy);
    
    $html = qq~<div id='static1'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static1").style.display = "none";
  document.getElementById("dynamic1").style.display = "";
  save_image("rank_abundance_plot");
  document.getElementById("rank_abundance_plotcanvas").style.display = "";
  document.getElementById("rank_abundance_plot").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic1'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static1").style.display = "";
  document.getElementById("dynamic1").style.display = "none";
  document.getElementById("rank_abundance_plotcanvas").style.display = "none";
  document.getElementById("rank_abundance_plot").style.display = "";'>
</div>
<div><div id='rank_abundance_plot'></div></div>
<input type='hidden' id='rap_data' value='$rap_data'>
<img src='./Html/clear.gif' onload='draw_rank_abundance_plot("rap_data", "rank_abundance_plot");'>~;
  } else {
    $html = "<p><em>" . (@$phylos ? "Insufficient data" : "Not yet computed") . ".</em></p>";
  }
  return $html;
}

sub get_rare_curve {
  my ($self) = @_;

  my $html = "";
  my $mgdb = $self->data('mgdb');
  my $mgid = $self->application->cgi->param('metagenome');
  $mgdb->set_jobs([$mgid]);
  my $curve = $mgdb->get_rarefaction_curve();

  if (exists($curve->{$mgid}) && (scalar(@{$curve->{$mgid}}) > 1)) {
    my $rare_data = join("~", map { $_->[0] . ";;" . $_->[1] } @{$curve->{$mgid}});
    #return "<pre>".Dumper($curve->{$mgid})."</pre>";

    $html = qq~<div id='static6'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static6").style.display = "none";
  document.getElementById("dynamic6").style.display = "";
  save_image("rarefaction_curve");
  document.getElementById("rarefaction_curvecanvas").style.display = "";
  document.getElementById("rarefaction_curve").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic6'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static6").style.display = "";
  document.getElementById("dynamic6").style.display = "none";
  document.getElementById("rarefaction_curvecanvas").style.display = "none";
  document.getElementById("rarefaction_curve").style.display = "";'>
</div>
<div><div id='rarefaction_curve'></div></div>
<input type='hidden' id='rare_data' value='$rare_data'>
<img src='./Html/clear.gif' onload='draw_rarefaction_curve("rare_data", "rarefaction_curve");'>~;
  } else {
    $html = "<p><em>Insufficient data.</em></p>";
  }
  return $html;
}

sub get_bin_set {
  my ($num_val, $min_num, $max_num, $bin_size) = @_;

  my $range = ($max_num - $min_num) / $bin_size;
  $range    = ($range == int($range)) ? $range : int($range + 1);
  my $bins  = [];

  foreach my $i (1 .. ($bin_size - 1)) {
    push @$bins, [ $min_num + ($i * $range), 0 ];
  }
  if ($max_num > $bins->[-1][0]) {
    push @$bins, [ $max_num, 0 ];
  }

  foreach my $set (@$num_val) {
    my ($num, $val) = @$set;
    for (my $i = 0; $i < @$bins; $i++) {
      if ($num <= $bins->[$i][0]) {
	$bins->[$i][1] += $val;
	last;
      }
    }
  }
  unshift @$bins, [ $min_num, "" ];
  return $bins;
}

sub format_number {
  my ($val) = @_;

  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}

  return $val;
}

sub get_pubmed_abstract {
  my ($self, $pmid) = @_;
  
  use HTTP::Request::Common;
  my $ua = LWP::UserAgent->new;
  my $retval = $ua->request(GET "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=$pmid&rettype=abstract&retmode=text");
  my $content = $retval->content();

  $content =~ s/\n/<br>/g;

  return $content;
}

sub fasta_export {
  my ($self) = @_;

  my $job  = $self->data('job');
  my $mgdb = $self->data('mgdb');
  $mgdb->set_jobs([$self->application->cgi->param('metagenome')]);

  my $cat  = $self->application->cgi->param('cat');
  my $md5s = $mgdb->get_md5s_for_tax_level( $self->data('tax_level'), [ $cat ] );
  my $data = $mgdb->md5s_to_read_sequences($md5s);

  foreach my $d (@$data) {
    $d->{sequence} =~ s/(.{60})/$1\n/g;
  }
  my $content = join("\n", map { ">".$_->{id}."\n".$_->{sequence} } @$data);

  $cat =~ s/\s+/_/g;
  $cat =~ s/\W//g;
  print "Content-Type:application/x-download\n";  
  print "Content-Length: ".length($content)."\n";
  print "Content-Disposition:attachment;filename=".$job->metagenome_id."_".$cat.".fna\n\n";
  print $content;
  exit;
}

sub require_javascript {
  return ["$Global_Config::cgi_url/Html/MetagenomeOverview.js", "$Global_Config::cgi_url/Html/canvg.js", "$Global_Config::cgi_url/Html/rgbcolor.js"];
}
