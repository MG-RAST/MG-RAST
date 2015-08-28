package MGRAST::WebPage::MetagenomeOverview;

# $Id: MetagenomeOverview.pm,v 1.119 2012-05-30 17:22:14 tharriso Exp $

use base qw( WebPage );

use strict;
use warnings;

use List::Util qw(first max min sum);
use POSIX;
use Data::Dumper;
use DateTime;
use Date::Parse;
use HTML::Entities;
use WebConfig;
use WebComponent::WebGD;
use GD;

use Conf;
use MGRAST::Metadata;
use MGRAST::Analysis;

1;

=pod

=head1 NAME

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
  $self->application->register_component('Table', 'func_tbl');
  $self->application->register_component('Table', 'org_tbl');
  $self->application->register_component('Ajax', 'ajax');

  $self->application->register_action($self, 'edit_name', 'edit_name');
  $self->application->register_action($self, 'chart_export', 'chart_export');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';
  unless ($id) {
    $self->app->add_message('warning', "Metagenome ID is missing.");
    return 1;
  }

  # sanity check on job
  my $mgrast = $self->application->data_handle('MGRAST');
  my $jobs_array = $mgrast->Job->get_objects( { metagenome_id => $id } );
  unless (@$jobs_array > 0) {
    $self->app->add_message('warning', "Unable to retrieve the metagenome '$id'. This metagenome does not exist.");
    return 1;
  }
  my $job = $jobs_array->[0];
  my $user = $self->application->session->user;

  if(! $job->public) {
    if(! $user) {
      $self->app->add_message('warning', 'Please log into MG-RAST to view private metagenomes.');
      return 1;
    } elsif(! $user->has_right(undef, 'view', 'metagenome', $id)) {
      $self->app->add_message('warning', "You have no access to the metagenome '$id'.  If someone is sharing this data with you please contact them with inquiries.  However, if you believe you have reached this message in error please contact the <a href='mailto:mg-rast\@mcs.anl.gov'>MG-RAST mailing list</a>.");
      return 1;
    }
  }

  my $attr = $mgrast->JobAttributes->init({ job => $job, tag => 'deleted' });
  if($attr) {
    $self->app->add_message('warning', "Unable to view metagenome '$id' because it has been deleted.");
    return 1;
  }

  unless ($job->viewable) {
    $self->app->add_message('warning', "Unable to view metagenome '$id' because it is still processing.");
    return 1;
  }
  $self->data('job', $job);

  # init the metadata database
  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  # init the metagenome database
  my $mgdb = new MGRAST::Analysis( $self->app->data_handle('MGRAST')->db_handle );
  unless ($mgdb) {
    $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
    return 1;
  }
  $mgdb->set_jobs([$id]);
  $self->data('mgdb', $mgdb);

  $self->data('bin_size', 20);
  $self->data('tax_levels', ['domain', 'phylum', 'class', 'order', 'family', 'genus', 'species']);
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

  my $non_ajax_action = $self->application->cgi->param('non_ajax_action') || '';
  if($non_ajax_action eq 'delete_job') {
    $self->delete_job();
    return "";
  }

  my $job  = $self->data('job');
  my $mgdb = $self->data('mgdb');
  my $mddb = $self->data('mddb');
  my $user = $self->application->session->user;
  my $job_id  = $job->job_id;
  my $mg_link = $Conf::cgi_url."linkin.cgi?metagenome=$mgid";

  # get project information
  my $project_link   = "";
  my $projectjob_num = 0;
  my $projectjob_url = "";
  my $jobdbm  = $self->application->data_handle('MGRAST');
  my $project = $job->primary_project;
  if ($project && ref($project)) {
    $self->{project}   = $project;
    $self->{meta_info} = $project->data;
    my $proj_jobs = $jobdbm->ProjectJob->get_objects({project => $project});
    $project_link = "<a target=_blank href='?page=MetagenomeProject&project=".$project->id."'>".$project->name."</a>";
    $projectjob_num = scalar(@$proj_jobs) - 1;
    $projectjob_url = "?page=MetagenomeProject&project=".$project->id."#jobs";
  }

  # get job metadata
  my $md_seq_type   = $job->seq_type;
  my $md_biome      = $job->biome;
  my $md_feature    = $job->feature;
  my $md_material   = $job->material;
  my $md_country    = $job->country;
  my $md_region     = $job->geo_loc_name;
  my $md_seqmethod  = $job->seq_method;
  my $md_ext_ids    = $job->external_ids;
  my $md_coordinate = $job->lat_lon;
  my $md_date_time  = $job->collection_date;
  my $md_enviroment = $job->env_package_type;

  # short info
  my $html = $self->application->component('ajax')->output;
  $html .= "<p><table><tr>";
  if ($job->public) {
    $html .= "<td style='font-size:large;'><b>MG-RAST ID</b></td>";
    $html .= "<td style='font-size:large;'>&nbsp;&nbsp;&nbsp;$mgid".($user && $user->is_admin('MGRAST') ? " <span style='color: blue;'>(".$job->job_id.")</span>" : "")."</td>";
  } else {
    $html .= "<td style='font-size:large;'>Internal Identifier</td><td style='font-size:large;'>".$job->job_id."</td>";
  }
  $html .= "<td>&nbsp;&nbsp;&nbsp;<a class='nav_top' style='color:rgb(82, 129, 176);' target=_blank href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$mgid'><img src='./Html/mg-download.png' style='width:20px;height:20px;' title='Download $mgid'> Download</a></td>";
  $html .= "<td>&nbsp;&nbsp;&nbsp;<a class='nav_top' style='color:rgb(82, 129, 176);' target=_blank href='metagenomics.cgi?page=Analysis&metagenome=$mgid'><img src='./Html/analysis.gif' style='width:20px;height:20px;' title='Analyze $mgid'> Analyze</a></td>";
  $html .= "<td>&nbsp;&nbsp;&nbsp;<a class='nav_top' style='color:rgb(82, 129, 176);' href='#search_ref'><img src='./Html/lupe.png' style='width:20px;height:20px;' title='Search $mgid'> Search</a></td>";
  $html .= "</tr></table></p>";
  $html .= "<p><div style='width: 700px'>";
  $html .= "<div style='float: left'><table>";
  $html .= "<tr><td><b>Metagenome Name</b></td><td>".$job->name."</td></tr>";
  if ($self->{project}) {
    $html .= "<tr><td><b>PI</b></td><td>".($self->{meta_info}->{PI_firstname}||"")." ".($self->{meta_info}->{PI_lastname}||"").($self->{meta_info}->{PI_email} ? " (".$self->{meta_info}->{PI_email}.")": "")."</td></tr>";
    $html .= "<tr><td><b>Organization</b></td><td>".($self->{meta_info}->{PI_organization}||"")."</td></tr>";
  }
  $html .= "<tr><td><b>Visibility</b></td><td>".($job->public ? 'Public' : 'Private')."</td></tr>";
  $html .= "<tr><td><b>Static Link</b></td><td>".($job->public ? "<a href='$mg_link'>$mg_link</a>" : "You need to <a href='?page=PublishGenome&metagenome=$mgid'>make this metagenome public</a> to publicly link it.")."</td></tr>";
  $html .= "</table></div><div style='float: right'><table>";
  $html .= "<tr><td><b>NCBI Project ID</b></td><td>".($md_ext_ids->{ncbi} ? join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/genomeprj/".$_."' target=_blank>".$_."</a>" } grep {$_ =~ /^\d+$/} split(/, /, $md_ext_ids->{ncbi})) : "-")."</td></tr>";
  $html .= "<tr><td><b>GOLD ID</b></td><td>".($md_ext_ids->{gold} ? join(", ", map { "<a href='http://genomesonline.org/cgi-bin/GOLD/bin/GOLDCards.cgi?goldstamp=".$_."' target=_blank>".$_."</a>" } grep {$_ =~ /^gm\d+$/i} split(/, /, $md_ext_ids->{gold})) : "-")."</td></tr>";
  $html .= "<tr><td><b>PubMed ID</b></td><td>".($md_ext_ids->{pubmed} ? join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/pubmed/".$_."' target=_blank>".$_."</a>" } grep {$_ =~ /^\d+$/} split(/, /, $md_ext_ids->{pubmed})) : "-")."</td></tr>";
  $html .= "</table></div></div></p>";
  $html .= "<div style='clear: both; height: 10px'></div>";
  if ($user && $user->has_right(undef, 'edit', 'metagenome', $mgid)) {
    $html .= "<p><div class='quick_links'><ul>";

    $self->{metagenome_id} = $mgid;

    if (! $job->public) {
	if($user->has_right(undef, 'delete', 'metagenome', $mgid)) {
	    $html .= qq~<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("delete_div").style.display == "none") {
    document.getElementById("delete_div").style.display = "inline";
  } else {
    document.getElementById("delete_div").style.display = "none";
  }'>Delete</a></li>~;
	}
    }
    
    $html .= "<li><a target=_blank href='?page=JobShare&metagenome=$mgid&job=".$job->job_id."'>Share</a></li>";
    $html .= qq~<li><a style='cursor:pointer;' onclick='
  if (document.getElementById("edit_name_div").style.display == "none") {
    document.getElementById("edit_name_div").style.display = "inline";
  } else {
    document.getElementById("edit_name_div").style.display = "none";
  }'>Edit Name</a></li>~;
    unless ($job->public) {
      $html .= "<li><a target=_blank href='?page=PublishGenome&metagenome=$mgid'>Make Public</a></li>";
    }

    my $attr = $job->data();
    if (!exists($attr->{priority}) || (exists($attr->{priority}) && $attr->{priority} eq 'never')) {
      $html .= "</ul></div></p><p><div style='display:none;' id='delete_div'>".$self->delete_info($job)."</div>";
    } else {
      $html .= "</ul></div></p><p><div style='display:none;' id='delete_div'><h3>Delete</h3><p>During job submission this job was marked to go public at some point in the future.  Thus, this job cannot be deleted.</p></div><br />";
    }
    $html .= "<div style='display:none;' id='edit_name_div'>".$self->edit_name_info($job)."</div></p>";
  }

  # get job stats
  my $job_dt      = DateTime->from_epoch( epoch => str2time($job->created_on) );
  my $job_stats   = $job->stats();
  my $raw_bps     = exists($job_stats->{bp_count_raw}) ? $job_stats->{bp_count_raw} : 0;
  my $qc_rna_bps  = exists($job_stats->{bp_count_preprocessed_rna}) ? $job_stats->{bp_count_preprocessed_rna} : 0;
  my $qc_bps      = exists($job_stats->{bp_count_preprocessed}) ? $job_stats->{bp_count_preprocessed} : 0;
  my $raw_seqs    = exists($job_stats->{sequence_count_raw}) ? $job_stats->{sequence_count_raw} : 0;
  my $derep_seqs  = exists($job_stats->{sequence_count_dereplication_removed}) ? $job_stats->{sequence_count_dereplication_removed} : 0;
  my $qc_rna_seqs = exists($job_stats->{sequence_count_preprocessed_rna}) ? $job_stats->{sequence_count_preprocessed_rna} : 0;
  my $qc_seqs     = exists($job_stats->{sequence_count_preprocessed}) ? $job_stats->{sequence_count_preprocessed} : 0;
  my $raw_len_avg = exists($job_stats->{average_length_raw}) ? $job_stats->{average_length_raw} : 0;
  my $qc_rna_len_avg = exists($job_stats->{average_length_preprocessed_rna}) ? $job_stats->{average_length_preprocessed_rna} : 0;
  my $qc_len_avg  = exists($job_stats->{average_length_preprocessed}) ? $job_stats->{average_length_preprocessed} : 0;
  my $raw_len_std = exists($job_stats->{standard_deviation_length_raw}) ? $job_stats->{standard_deviation_length_raw} : 0;
  my $qc_rna_len_std = exists($job_stats->{standard_deviation_length_preprocessed_rna}) ? $job_stats->{standard_deviation_length_preprocessed_rna} : 0;
  my $qc_len_std  = exists($job_stats->{standard_deviation_length_preprocessed}) ? $job_stats->{standard_deviation_length_preprocessed} : 0;
  my $raw_gc_avg  = exists($job_stats->{average_gc_content_raw}) ? $job_stats->{average_gc_content_raw} : 0;
  my $qc_rna_gc_avg = exists($job_stats->{average_gc_content_preprocessed_rna}) ? $job_stats->{average_gc_content_preprocessed_rna} : 0;
  my $qc_gc_avg   = exists($job_stats->{average_gc_content_preprocessed}) ? $job_stats->{average_gc_content_preprocessed} : 0;
  my $raw_gc_std  = exists($job_stats->{standard_deviation_gc_content_raw}) ? $job_stats->{standard_deviation_gc_content_raw} : 0;
  my $qc_rna_gc_std = exists($job_stats->{standard_deviation_gc_content_preprocessed_rna}) ? $job_stats->{standard_deviation_gc_content_preprocessed_rna} : 0;
  my $qc_gc_std   = exists($job_stats->{standard_deviation_gc_content_preprocessed}) ? $job_stats->{standard_deviation_gc_content_preprocessed} : 0;
  my $clusts      = exists($job_stats->{cluster_count_processed_aa}) ? $job_stats->{cluster_count_processed_aa} : (exists($job_stats->{cluster_count_processed}) ? $job_stats->{cluster_count_processed} : 0);
  my $clust_seq   = exists($job_stats->{clustered_sequence_count_processed_aa}) ? $job_stats->{clustered_sequence_count_processed_aa} : (exists($job_stats->{clustered_sequence_count_processed}) ? $job_stats->{clustered_sequence_count_processed} : 0);
  my $r_clusts    = exists($job_stats->{cluster_count_processed_rna}) ? $job_stats->{cluster_count_processed_rna} : 0;
  my $r_clust_seq = exists($job_stats->{clustered_sequence_count_processed_rna}) ? $job_stats->{clustered_sequence_count_processed_rna} : 0;
  my $aa_reads    = exists($job_stats->{read_count_processed_aa}) ? $job_stats->{read_count_processed_aa} : 0;
  my $rna_reads   = exists($job_stats->{read_count_processed_rna}) ? $job_stats->{read_count_processed_rna} : 0;
  my $aa_feats    = exists($job_stats->{sequence_count_processed_aa}) ? $job_stats->{sequence_count_processed_aa} : 0;
  my $rna_feats   = exists($job_stats->{sequence_count_processed_rna}) ? $job_stats->{sequence_count_processed_rna} : 0;
  my $aa_sims     = exists($job_stats->{sequence_count_sims_aa}) ? $job_stats->{sequence_count_sims_aa} : 0;
  my $rna_sims    = exists($job_stats->{sequence_count_sims_rna}) ? $job_stats->{sequence_count_sims_rna} : 0;
  my $aa_ontol    = exists($job_stats->{sequence_count_ontology}) ? $job_stats->{sequence_count_ontology} : 0;
  my $ann_reads   = exists($job_stats->{read_count_annotated}) ? $job_stats->{read_count_annotated} : 0;
  my $alpha_num   = exists($job_stats->{alpha_diversity_shannon}) ? $job_stats->{alpha_diversity_shannon} : 0;
  my $drisee_num  = exists($job_stats->{drisee_score_raw}) ? $job_stats->{drisee_score_raw} : 0;

  my $is_rna  = ($md_seq_type eq 'Amplicon') ? 1 : 0;
  my $is_gene = ($md_seq_type eq 'AmpliconGene') ? 1 : 0;
  my $qc_fail_seqs  = $raw_seqs - $qc_seqs;
  my $ann_aa_reads  = $aa_sims ? ($aa_sims - $clusts) + $clust_seq : 0;
  my $unkn_aa_reads = $aa_reads - $ann_aa_reads;
  my $ann_rna_reads = $rna_sims ? ($rna_sims - $r_clusts) + $r_clust_seq : 0;
  my $unknown_all   = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads);

  # amplicon rna numbers
  if ($is_rna) {
    $qc_fail_seqs  = $raw_seqs - $qc_rna_seqs;
    $unkn_aa_reads = 0;
    $ann_aa_reads  = 0;
    $unknown_all   = $raw_seqs - ($qc_fail_seqs + $ann_rna_reads);
    if ($raw_seqs < ($qc_fail_seqs + $ann_rna_reads)) {
	    my $diff = ($qc_fail_seqs + $ann_rna_reads) - $raw_seqs;
	    $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
    }
  }
  # amplicon gene numbers
  elsif ($is_gene) {
      $ann_rna_reads = 0;
      $unknown_all = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads);
      if ($raw_seqs < ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads)) {
          my $diff = ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads) - $raw_seqs;
          $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
      }
  }
  # wgs / mt numbers
  else {
      # get correct qc rna
      if ($qc_rna_seqs > $qc_seqs) {
          $ann_rna_reads = int((($qc_seqs * 1.0) / $qc_rna_seqs) * $ann_rna_reads);
      }
      if ($unknown_all < 0) { $unknown_all = 0; }
      if ($raw_seqs < ($qc_fail_seqs + $unknown_all + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads)) {
	      my $diff = ($qc_fail_seqs + $unknown_all + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
	      $unknown_all = ($diff > $unknown_all) ? 0 : $unknown_all - $diff;
      }
      if (($unknown_all == 0) && ($raw_seqs < ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads))) {
	      my $diff = ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
	      $unkn_aa_reads = ($diff > $unkn_aa_reads) ? 0 : $unkn_aa_reads - $diff;
      }
      ## hack to make MT numbers add up
      if (($unknown_all == 0) && ($unkn_aa_reads == 0) && ($raw_seqs < ($qc_fail_seqs + $ann_aa_reads + $ann_rna_reads))) {
	      my $diff = ($qc_fail_seqs + $ann_aa_reads + $ann_rna_reads) - $raw_seqs;
	      $ann_rna_reads = ($diff > $ann_rna_reads) ? 0 : $ann_rna_reads - $diff;
      }
      my $diff = $raw_seqs - ($qc_fail_seqs + $unkn_aa_reads + $ann_aa_reads + $ann_rna_reads);
      if ($unknown_all < $diff) {
	      $unknown_all = $diff;
      }
  }

  ($qc_fail_seqs, $unknown_all, $unkn_aa_reads, $ann_aa_reads, $ann_rna_reads) =
        (abs($qc_fail_seqs), abs($unknown_all), abs($unkn_aa_reads), abs($ann_aa_reads), abs($ann_rna_reads));
  # get charts
  my $colors = ["#6C6C6C","#dc3912","#ff9900","#109618","#3366cc","#990099"];
  my $summary_chart = $self->get_summary_chart($colors, $qc_fail_seqs, $unknown_all, $unkn_aa_reads, $ann_aa_reads, $ann_rna_reads);
  my $source_chart  = $self->get_source_chart($job, $is_rna, $is_gene, format_number($aa_sims), percent($aa_sims,$aa_feats), format_number($aa_ontol), percent($aa_ontol,$aa_sims), format_number($ann_rna_reads), percent($ann_rna_reads,$raw_seqs));
  my $taxa_chart    = $self->get_taxa_chart($job);
  my $func_chart    = $self->get_func_charts($job, $aa_feats, $aa_sims);
  my $drisee_plot   = $self->get_drisee_chart($job);
  my $bp_consensus  = $self->get_consensus_chart($job);

  # mg summary text
  $html .= "<a name='summary_ref'></a><table><tr><td>";
  $html .= "<h3>Metagenome Summary</h3><div style='width:450px;'>";
  $html .= "<p>Dataset ".$job->name." was uploaded on ".$job_dt->mdy('/')." and contains ".format_number($raw_seqs)." sequences totaling ".format_number($raw_bps)." basepairs with an average length of ".format_number($raw_len_avg)." bps. The piechart below breaks down the uploaded sequences into ".($is_rna ? '3' : ($is_gene ? '4' : '5'))." distinct categories.</p>";
  $html .= "<p>".format_number($qc_fail_seqs)." sequences (".percent($qc_fail_seqs,$raw_seqs).") failed to pass the QC pipeline. Of the sequences that passed QC, ";
  # amplicon rna text
  if ($is_rna) {
      $html .= format_number($ann_rna_reads)." sequences (".percent($ann_rna_reads,$raw_seqs).") contain ribosomal RNA genes. ".format_number($unknown_all)." (".percent($unknown_all,$raw_seqs).") of the sequences that passed QC have no rRNA genes. ".format_number($unknown_all)." (".percent($unknown_all,$raw_seqs).") of the sequences that passed QC have no rRNA genes.</p>";
  }
  # amplicon gene text
  elsif ($is_gene) {
      $html .= format_number($ann_aa_reads)." sequences (".percent($ann_aa_reads,$raw_seqs).") contain predicted proteins with known functions and ".format_number($unkn_aa_reads)." sequences (".percent($unkn_aa_reads,$raw_seqs).") contain predicted proteins with unknown function. ".format_number($unknown_all)." (".percent($unknown_all,$raw_seqs).") of the sequences that passed QC have no predicted proteins.</p>";
  }
  # wgs / mt text
  else {  
      $html .= format_number($ann_rna_reads)." sequences (".percent($ann_rna_reads,$raw_seqs).") contain ribosomal RNA genes. Of the remainder, ".format_number($ann_aa_reads)." sequences (".percent($ann_aa_reads,$raw_seqs).") contain predicted proteins with known functions and ".format_number($unkn_aa_reads)." sequences (".percent($unkn_aa_reads,$raw_seqs).") contain predicted proteins with unknown function. ".format_number($unknown_all)." (".percent($unknown_all,$raw_seqs).") of the sequences that passed QC have no rRNA genes or predicted proteins.</p>";
  }
  $html .= "<p>The analysis results shown on this page are computed by MG-RAST. Please note that authors may upload data that they have published their own analysis for, in such cases comparison within the MG-RAST framework can not be done.</p>";
  $html .= "<p><a class='nav_top' target=_blank href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$mgid'><img src='./Html/mg-download.png' style='width:20px;height:20px;' title='Download $mgid'></a>&nbsp;&nbsp;&nbsp;<span style='font-variant:small-caps'>download</span> data and annotations";
  $html .= "<br><a class='nav_top' target=_blank href='metagenomics.cgi?page=Analysis&metagenome=$mgid'><img src='./Html/analysis.gif' style='width:20px;height:20px;' title='Analyze $mgid'></a>&nbsp;&nbsp;&nbsp;<span style='font-variant:small-caps'>analyze</span> annotations in detail.";
  $html .= "<br><a class='nav_top' href='#search_ref'><img src='./Html/lupe.png' style='width:20px;height:20px;' title='Search $mgid'></a>&nbsp;&nbsp;&nbsp;<span style='font-variant:small-caps'>search</span> through annotations.</p>";
  $html .= "</div><p><span style='padding-left:15px;'><b>Sequence Breakdown</b></span>$summary_chart";
  $html .= "<em style='padding-left:25px;font-size:x-small'>Note: Sequences containing multiple predicted features are only counted in one category.</em><br>";
  $html .= "<em style='padding-left:50px;font-size:x-small'>Currently downloading of sequences via chart slices is not enabeled.</em>";
  $html .= "</p></td><td style='padding-left:25px;'></td>";
  
  # toc
  $html .= "<td><h3>Table of Contents</h3>";
  $html .= "<div style='border:2px solid #AAAAAA;padding:10px;background-color:#EEEEEE;'>";
  # tools
  $html .= "<li>Work with Metagenome Data</li>";
  $html .= "<ul style='margin:0;'>";
  $html .= "<li><a href='#download_ref'>Download</a></li>";
  $html .= "<li><a href='#analyze_ref'>Analyze</a></li>";
  $html .= "<li><a href='#search_ref'>Search</a></li>";
  $html .= "</ul>";
  # overview
  $html .= "<li style='padding-top:5px;'>Overview of Metagenome</li>";
  $html .= "<ul style='margin:0;'>";
  $html .= "<li><a href='#summary_ref'>Summary</a></li>";
  if (exists($self->{meta_info}->{project_description})) {
    $html .= "<li><a href='#project_ref'>Project Information</a></li>";
  }
  $html .= "<li><a href='#mixs_ref'>GSC MIxS Info</a></li>";
  if ($md_ext_ids->{pubmed}) {
    $html .= "<li><a href='#pub_ref'>Publication Abstracts</a></li>";
  }
  $html .= "</ul>";
  # qc
  $html .= "<li style='padding-top:5px;'>Metagenome QC</li>";
  $html .= "<ul style='margin:0;'>";
  if (exists $job_stats->{drisee_score_raw}) {
  	$html .= "<li><a href='#drisee_ref'>DRISEE</a></li>";
  }
  $html .= "<li><a href='#kmer_ref'>Kmer Profile</a></li>";
  if ($bp_consensus) {
  	$html .= "<li><a href='#consensus_ref'>Nucleotide Histogram</a></li>";
  }
  $html .= "</ul>";
  # organism
  $html .= "<li style='padding-top:5px;'>Organism Breakdown</li>";
  $html .= "<ul style='margin:0;'>";
  if ($taxa_chart) {
    $html .= "<li><a href='#org_ref'>Taxonomic Distribution</a></li>";
  }
  $html .= "<li><a href='#rank_ref'>Rank Abundance Plot</a></li>";
  $html .= "<li><a href='#rare_ref'>Rarefaction Curve</a></li>";
  $html .= "<li><a href='#alpha_ref'>Alpha Diversity</a></li>";
  $html .= "</ul>";
  # function
  if ($func_chart && (! $is_rna) && (! $is_gene)) {
    $html .= "<li style='padding-top:5px;'>Functional Breakdown</li>";
    $html .= "<ul style='margin:0;'><li><a href='#func_ref'>Functional Categories</a></li></ul>";
  }
  # technical
  $html .= "<li style='padding-top:5px;'>Technical Data</li>";
  $html .= "<ul style='margin:0;'>";
  $html .= "<li><a href='#stats_ref'>Statistics</a></li>";
  $html .= "<li><a href='#meta_ref'>Metadata</a></li>";
  if ($source_chart) {
    $html .= "<li><a href='#source_ref'>Source Distribution</a></li>";
  }

  # sequence length histogram
  my @len_raw_hist = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->metagenome_id, 'len', 'raw') };
  my @len_qc_hist  = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->metagenome_id, 'len', 'qc') };
  my $len_min = (@len_raw_hist && @len_qc_hist) ? min($len_raw_hist[0][0], $len_qc_hist[0][0]) : (@len_raw_hist ? $len_raw_hist[0][0] : (@len_qc_hist ? $len_qc_hist[0][0] : 0));
  my $len_max = (@len_raw_hist && @len_qc_hist) ? max($len_raw_hist[-1][0], $len_qc_hist[-1][0]) : (@len_raw_hist ? $len_raw_hist[-1][0] : (@len_qc_hist ? $len_qc_hist[-1][0] : 0));
  my $len_raw_bins = @len_raw_hist ? &get_bin_set(\@len_raw_hist, $len_min, $len_max, $self->data('bin_size')) : [];
  my $len_qc_bins  = @len_qc_hist  ? &get_bin_set(\@len_qc_hist, $len_min, $len_max, $self->data('bin_size')) : [];

  unless($len_max == $len_min) {
    $html .= "<li><a href='#len_ref'>Sequence Length Histogram</a></li>";
  }
  $html .= "<li><a href='#gc_ref'>Sequence GC Distribution</a></li>";
  $html .= "</ul></ul></div></td></tr></table><br>";
  
  # project description
  $html .= "<br><a name='project_ref'></a><a name='mixs_ref'></a><table><tr>";
  if ($self->{project}) {
    $html .= "<td><h3>Project Information</h3>";
    $html .= "<div style='width:375px;'><p>This dataset is part of project $project_link.</p>";
    if (exists $self->{meta_info}->{project_description}) {
      $html .= "<p>".$self->{meta_info}->{project_description}."</p>";
    }
    $html .= "<p>There are $projectjob_num other metagenomes in this project</p></div></td>";
    $html .= "<td rowspan='2' style='padding-left:25px;'></td>";
    $html .= "<td rowspan='2'>";
  } else {
    $html .= "<td>";
  }
  # gsc mixs
  $html .= "<h3>GSC MIxS Info</h3>";
  $html .= "<div class='metagenome_info' style='width: 300px;'><ul style='margin: 0; padding: 0;'>";
  $html .= "<li class='even'><label style='text-align: left;'>Investigation Type</label><span style='width: 180px'>".(($md_seq_type =~ /wgs|amplicon|mt/i) ? $mddb->investigation_type_alias($md_seq_type) : "unknown")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Project Name</label><span style='width: 180px'>".($self->{project} ? $project_link : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Latitude and Longitude</label><span style='width: 180px'>".(scalar(@$md_coordinate) ? join(", ", @$md_coordinate) : "-, -")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Country and/or Sea, Location</label><span style='width: 180px'>".(scalar(@$md_region) ? join("<br>", @$md_region) : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Collection Date</label><span style='width: 180px'>".($md_date_time ? $md_date_time : "-")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Environment (Biome)</label><span style='width: 180px'>".($md_biome ? $md_biome : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Environment (Feature)</label><span style='width: 180px'>".($md_feature ? $md_feature : "-")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Environment (Material)</label><span style='width: 180px'>".($md_material ? $md_material : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'>Environmental Package</label><span style='width: 180px'>".($md_enviroment ? $md_enviroment : "-")."</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;'>Sequencing Method</label><span style='width: 180px'>".($md_seqmethod ? $md_seqmethod : "-")."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;'><a href='#meta_ref'>More Metadata</a></label><span style='width: 180px'>&nbsp;</span></li>";
  $html .= "</ul></div></td></tr><tr><td style='vertical-align:top'><ul>";
  # link to similar mgs
  $html .= "<li style='margin-top:0.25em;margin-bottom:0.25em;list-style-type:none;'>";
  if (($projectjob_num > 0) && $projectjob_url) {
    $html .= "<a target=_blank href='$projectjob_url'>&raquo; find metagenomes within this project</a>";
  } else {
    $html .= "&raquo; find metagenomes within this project";
  }
  $html .= "</li><li style='margin-top:0.25em;margin-bottom:0.25em;list-style-type:none;'>";
  if ($md_biome) {
    $html .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=1&type_q1=metadata&match_q1=1_1&extra_q1=biome-information_envo_lite&input_q1=$md_biome'>&raquo; find metagenomes within this biome</a>";
  } else {
    $html .= "&raquo; find metagenomes within this biome";
  }
  $html .= "</li><li style='margin-top:0.25em;margin-bottom:0.25em;list-style-type:none;'>";
  if ($md_country) {
    $html .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=1&type_q1=metadata&match_q1=1_1&extra_q1=sample-origin_country&input_q1=$md_country'>&raquo; find metagenomes within this country</a>";
  } else {
    $html .= "&raquo; find metagenomes within this country";
  }
  $html .= "</li><li style='margin-top:0.25em;margin-bottom:0.25em;list-style-type:none;'>";
  if (scalar(@$md_coordinate) && ($md_coordinate->[0] =~ /^-?\d+\.?\d*$/) && ($md_coordinate->[1] =~ /^-?\d+\.?\d*$/)) {
    my ($lat, $lng) = @$md_coordinate;
    my $lat_10  = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 0.1, $lat + 0.1));
    my $lng_10  = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 0.1, $lng + 0.1));
    my $lat_30  = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 0.3, $lat + 0.3));
    my $lng_30  = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 0.3, $lng + 0.3));
    my $lat_100 = "input_q1=" . join("_", sort {$a <=> $b} ($lat - 1.0, $lat + 1.0));
    my $lng_100 = "input_q2=" . join("_", sort {$a <=> $b} ($lng - 1.0, $lng + 1.0));
    my $link = "metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=2&qnum=2&type_q1=metadata&type_q2=metadata&match_q1=2_1&match_q2=2_1&extra_q1=sample-origin_latitude&extra_q2=sample-origin_longitude";
    $html .= "&raquo; find metagenomes within <a target=_blank href='$link&$lat_10&$lng_10'>10</a> | <a target=_blank href='$link&$lat_30&$lng_30'>30</a> | <a target=_blank href='$link&$lat_100&$lng_100'>100</a> kilometers";
  } else {
    $html .= "&raquo; find metagenomes within 10 | 30 | 100 kilometers";
  }
  $html .= "</li></ul></td></tr></table><br>";

  # technical text
  $html .= "<br><a name='stats_ref'></a><table><tr><td>";
  $html .= "<h3>Analysis Flowchart</h3><div style='width:375px;'>";
  # amplicon rna text
  if ($is_rna) {
      $html .= "<p>".format_number($qc_fail_seqs)." sequences failed quality control. Of the ".format_number($qc_rna_seqs)." sequences (totaling ".format_number($qc_rna_bps)." bps) that passed quality control, ".format_number($ann_rna_reads)." (".percent($ann_rna_reads,$qc_rna_seqs).") produced a total of ".format_number($rna_sims)." identified ribosomal RNAs.</p>";
  }
  # amplicon gene text
  elsif ($is_gene) {
      $html .= "<p>".format_number($qc_fail_seqs)." sequences failed quality control. Of the ".format_number($qc_seqs)." sequences (totaling ".format_number($qc_bps)." bps) that passed quality control, ".format_number($aa_reads)." (".percent($aa_reads,$qc_rna_seqs).") produced a total of ".format_number($aa_feats)." predicted protein coding regions. Of these ".format_number($aa_feats)." predicted protein features, ".format_number($aa_sims)." (".percent($aa_sims,$aa_feats)." of features) have been assigned an annotation using at least one of our protein databases (M5NR) and ".format_number($aa_feats-$aa_sims)." (".percent($aa_feats-$aa_sims,$aa_feats)." of features) have no significant similarities to the protein database (orfans).</p>";
  }
  # wgs / mt text
  else {
      $html .= "<p>".format_number($qc_fail_seqs)." sequences failed quality control. Of those, dereplication identified ".format_number($derep_seqs)." sequences (".percent($derep_seqs,$raw_seqs)." of total) as artificial duplicate reads (ADRs). Of the ".format_number($qc_seqs)." sequences (totaling ".format_number($qc_bps)." bps) that passed quality control, ".format_number($aa_reads)." (".percent($aa_reads,$qc_seqs).") produced a total of ".format_number($aa_feats)." predicted protein coding regions. Of these ".format_number($aa_feats)." predicted protein features, ".format_number($aa_sims)." (".percent($aa_sims,$aa_feats)." of features) have been assigned an annotation using at least one of our protein databases (M5NR) and ".format_number($aa_feats-$aa_sims)." (".percent($aa_feats-$aa_sims,$aa_feats)." of features) have no significant similarities to the protein database (orfans). ".format_number($aa_ontol)." features (".percent($aa_ontol,$aa_sims)." of annotated features) were assigned to functional categories.</p>";
  }
  $html .= "</td><td rowspan='3' style='padding-left:25px;'></td>";

  # technical stats
  $html .= "<td rowspan='3'><h3>Analysis Statistics</h3>";
  $html .= "<div class='metagenome_info' style='width: 320px;'><ul style='margin: 0; padding: 0;'>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Upload: bp Count</label><span style='width: 200px'>".format_number($raw_bps)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Upload: Sequences Count</label><span style='width: 200px'>".format_number($raw_seqs)."</span></li>";
  $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Upload: Mean Sequence Length</label><span style='width: 200px'>".format_number($raw_len_avg)." &plusmn; ".format_number($raw_len_std)." bp</span></li>";
  $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Upload: Mean GC percent</label><span style='width: 200px'>".format_number($raw_gc_avg)." &plusmn; ".format_number($raw_gc_std)." %</span></li>";
  # amplicon rna text
  if ($is_rna) {
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: bp Count</label><span style='width: 200px'>".format_number($qc_rna_bps)." bp</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Sequences Count</label><span style='width: 200px'>".format_number($qc_rna_seqs)."</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean Sequence Length</label><span style='width: 200px'>".format_number($qc_rna_len_avg)." &plusmn; ".format_number($qc_len_std)." bp</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean GC percent</label><span style='width: 200px'>".format_number($qc_rna_gc_avg)." &plusmn; ".format_number($qc_gc_std)." %</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Processed: Predicted rRNA Features</label><span style='width: 200px'>".format_number($rna_feats)."</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Alignment: Identified rRNA Features</label><span style='width: 200px'>".format_number($rna_sims)."</span></li>";
  }
  # amplicon rna text
  elsif ($is_gene) {
      $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: bp Count</label><span style='width: 200px'>".format_number($qc_bps)." bp</span></li>";
      $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Sequences Count</label><span style='width: 200px'>".format_number($qc_seqs)."</span></li>";
      $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean Sequence Length</label><span style='width: 200px'>".format_number($qc_len_avg)." &plusmn; ".format_number($qc_len_std)." bp</span></li>";
      $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean GC percent</label><span style='width: 200px'>".format_number($qc_gc_avg)." &plusmn; ".format_number($qc_gc_std)." %</span></li>";
      $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Processed: Predicted Protein Features</label><span style='width: 200px'>".format_number($aa_feats)."</span></li>";
      $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Alignment: Identified Protein Features</label><span style='width: 200px'>".format_number($aa_sims)."</span></li>";
  }
  # wgs / mt text
  else {
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Artificial Duplicate Reads: Sequence Count</label><span style='width: 200px'>".format_number($derep_seqs)."</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: bp Count</label><span style='width: 200px'>".format_number($qc_bps)." bp</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Sequences Count</label><span style='width: 200px'>".format_number($qc_seqs)."</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean Sequence Length</label><span style='width: 200px'>".format_number($qc_len_avg)." &plusmn; ".format_number($qc_len_std)." bp</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Post QC: Mean GC percent</label><span style='width: 200px'>".format_number($qc_gc_avg)." &plusmn; ".format_number($qc_gc_std)." %</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Processed: Predicted Protein Features</label><span style='width: 200px'>".format_number($aa_feats)."</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Processed: Predicted rRNA Features</label><span style='width: 200px'>".format_number($rna_feats)."</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Alignment: Identified Protein Features</label><span style='width: 200px'>".format_number($aa_sims)."</span></li>";
    $html .= "<li class='even'><label style='text-align: left;white-space:nowrap;'>Alignment: Identified rRNA Features</label><span style='width: 200px'>".format_number($rna_sims)."</span></li>";
    $html .= "<li class='odd'><label style='text-align: left;white-space:nowrap;'>Annotation: Identified Functional Categories</label><span style='width: 200px'>".format_number($aa_ontol)."</span></li>";
  }
  $html .= "</ul></div></td></tr>";

  # technical flowchart
  my $fc_aa_titles  = ["Passed QC","Predicted\\nFeatures","Annotated\\nProtein","Functional\\nCategory"];
  my $fc_rna_titles = ["Passed QC","Predicted\\nrRNAs"];
  my $fc_aa_colors  = [[$colors->[0],$colors->[1]], [$colors->[1],$colors->[4],$colors->[2]], [$colors->[2],$colors->[3]], [$colors->[3],$colors->[5]]];
  my $fc_rna_colors = [[$colors->[0],$colors->[1]], [$colors->[1],$colors->[4]]];
  my $fc_aa_data    = [[$raw_seqs,$qc_seqs], [$qc_seqs,$ann_rna_reads,$aa_reads], [$aa_feats,$aa_sims], [$aa_sims,$aa_ontol]];
  my $fc_rna_data   = [[$raw_seqs,$qc_rna_seqs], [$qc_rna_seqs, ($ann_rna_reads > $qc_rna_seqs) ? $qc_rna_seqs : $ann_rna_reads]];
  
  my $fc_titles = $is_rna ? array2json($fc_rna_titles, 1) : array2json($fc_aa_titles, 1);
  my $fc_colors = $is_rna ? array2json($fc_rna_colors, 2) : array2json($fc_aa_colors, 2);
  my $fc_data   = $is_rna ? array2json($fc_rna_data, 2) : array2json($fc_aa_data, 2);
  
  $html .= "<tr><td><div id='flowchart_div'></div>";
  $html .= "<img src='./Html/clear.gif' onload='draw_bar_plot(\"flowchart_div\", $fc_titles, $fc_colors, $fc_data);'></td></tr></table>";

  # drisee score
  my $drisee_refrence = "<p>Duplicate Read Inferred Sequencing Error Estimation (<a target=_blank href='http://www.ploscompbiol.org/article/info%3Adoi%2F10.1371%2Fjournal.pcbi.1002541'>Keegan et al., PLoS Computational Biology, 2012</a>)</p>";
  my $drisee_boilerplate = qq~
  <p>DRISEE is a tool that utilizes artificial duplicate reads (ADRs) to provide a platform independent assessment of sequencing error in metagenomic (or genomic) sequencing data. DRISEE is designed to consider shotgun data. Currently, it is not appropriate for amplicon data.</p>
  <p>Note that DRISEE is designed to examine sequencing error in raw whole genome shotgun sequence data. It assumes that adapter and/or barcode sequences have been removed, but that the sequence data have not been modified in any additional way. (e.g.) Assembly or merging, QC based triage or trimming will both reduce DRISEE's ability to provide an accurate assessment of error by removing error before it is analyzed.</p>~;

  if (($drisee_num == 0) && (! $is_rna) && (! $is_gene)) {
    $html .= qq~<a name='drisee_ref'></a>
<h3>DRISEE
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#drisee' style='font-size:14px;padding-left:5px;'>[?]</a></h3>
$drisee_refrence
<p>DRISEE could not produce a profile; the sample failed to meet the minimal ADR requirements to calculate an error profile (see Keegan et al. 2012)</p>
$drisee_boilerplate
~;
  } elsif (($drisee_num > 0) && (! $is_rna) && (! $is_gene)) {
    my ($min, $max, $avg, $stdv) = @{ $jobdbm->JobStatistics->stats_for_tag('drisee_score_raw', undef, undef, 1) };
    my $drisee_score = sprintf("%.3f", $drisee_num);
    $html .= qq~<a name='drisee_ref'></a>
<h3>DRISEE
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#drisee' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("drisee_show").style.display = "";
  } else {
    document.getElementById("drisee_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='drisee_show'>
  $drisee_refrence
  <p><b>Total DRISEE Error = $drisee_score %</b></p>
  <img src='./Html/clear.gif' onload='draw_position_on_range("drisee_bar_div", $drisee_num, $min, $max, $avg, $stdv);'>
  <div id='drisee_bar_div'></div>
  <p>The above image shows the range of total DRISEE percent errors in all of MG-RAST. The min, max, and mean values are shown, with the standard deviation ranges (&sigma; and 2&sigma;) in different shades. The total DRISEE percent error of this metagenome is shown in red.</p>
  <p>DRISEE successfully calculated an error profile.</p>
  $drisee_boilerplate
  $drisee_plot
</div>~;
  } elsif ($is_rna || $is_gene) {
	$html .= qq~<a name='drisee_ref'></a>
<h3>DRISEE
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#drisee' style='font-size:14px;padding-left:5px;'>[?]</a></h3>
$drisee_refrence
<p>DRISEE could not produce a profile, this is an Amplicon dataset.</p>
$drisee_boilerplate
~;
  }

  # kmer profiles
  $html .= qq~<a name='kmer_ref'></a>
<h3>Kmer Profiles
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#kmer_profile' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("kmer_show").style.display = "";
  } else {
    document.getElementById("kmer_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='kmer_show'>
<a style='cursor:pointer;clear:both;padding-right:20px;' onclick='
    var new_type = document.getElementById("kmer_type").value;
    var new_size = document.getElementById("kmer_size").value;
    execute_ajax("get_kmer_plot", "kmer_div", "metagenome=$mgid&job=$job_id&size="+new_size+"&type="+new_type);'>
  Redraw the below plot using the following kmer-plot type:</a>
<select id='kmer_type'>
  <option value='abundance'>kmer rank abundance</option>
  <option value='ranked'>ranked kmer consumed</option>
  <option value='spectrum'>kmer spectrum</option>
</select>
<select id='kmer_size'>
  <option value='15'>15-mer</option>
  <option value='6'>6-mer</option>
</select>
  <img src='./Html/clear.gif' onload='execute_ajax("get_kmer_plot", "kmer_div", "metagenome=$mgid&job=$job_id&size=15&type=abundance");'>
  <div id='kmer_div'></div>
</div><br />~;

  # consensus plot
  if ($bp_consensus) {
    $html .= $bp_consensus;
  }

  # source hits distribution
  if ($source_chart) {
    $html .= $source_chart;
  }

  # ontology hits distrubtion
  if ($func_chart && (! $is_rna) && (! $is_gene)) {
    $html .= $func_chart
  }

  # taxa hits distribution
  if ($taxa_chart) {
    $html .= $taxa_chart;
  }

  # rank abundance plot
  my @rank_levels = @{$self->data('tax_levels')};
  shift @rank_levels;
  my $default_level = $rank_levels[0];
  my $level_opts    = '';
  foreach my $l (@rank_levels) {
    $level_opts .= "<option value='$l'>$l</option>";
  }
  $html .= qq~<a name='rank_ref'></a>
<h3>Rank Abundance Plot
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("abund_show").style.display = "";
  } else {
    document.getElementById("abund_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<a style='cursor:pointer;clear:both;padding-right:20px;' onclick='
    var new_level = document.getElementById("tax_level").value;
    execute_ajax("get_abund_plot", "rank_abund_div", "metagenome=$mgid&job=$job_id&level="+new_level);'>
  Redraw the below plot using the following taxonomic level:</a>
<select id='tax_level'>$level_opts</select><br>
<div id='abund_show'>
  <img src='./Html/clear.gif' onload='execute_ajax("get_abund_plot", "rank_abund_div", "metagenome=$mgid&job=$job_id&level=$default_level");'>
  <div id='rank_abund_div'></div>
</div>~;
  
  # rarefaction curve
  $html .= qq~<a name='rare_ref'></a>
<h3>Rarefaction Curve
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("rare_show").style.display = "";
  } else {
    document.getElementById("rare_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='rare_show'>
  <img src='./Html/clear.gif' onload='execute_ajax("get_rare_curve", "rare_curve_div", "metagenome=$mgid&job=$job_id");'>
  <div id='rare_curve_div'></div>
</div>~;

  # alpha diversity
  $html .= qq~<a name='alpha_ref'></a>
<h3>Alpha Diversity
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#alpha_diversity' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("alpha_show").style.display = "";
  } else {
    document.getElementById("alpha_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='alpha_show'>
  <img src='./Html/clear.gif' onload='execute_ajax("get_alpha", "alpha_div", "metagenome=$mgid&job=$job_id&alpha=$alpha_num");'>
  <div id='alpha_div'></div>
</div>~;

  unless($len_max == $len_min) {
    $html .= qq~<a name='len_ref'></a>
<h3>Sequence Length Histogram
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("len_show").style.display = "";
  } else {
    document.getElementById("len_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='len_show'>
<p>The histograms below show the distribution of sequence lengths in basepairs for this metagenome. Each position represents the number of sequences within a length bp range.</p><p>The data used in these graphs are based on raw upload and post QC sequences.</p>~;

    if (@$len_raw_bins > 1) {
      my $len_raw_data = join("~", map { $_->[0] .";;" . $_->[1] } @$len_raw_bins);
      my $len_raw_link = $self->chart_export_link($len_raw_bins, 'upload_len_hist');
      $html .= qq~<p>$len_raw_link</p>
<div id='static2'>
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
<img src='./Html/clear.gif' onload='draw_histogram_plot("len_data_raw", "length_hist_raw", "bps", "Number of Reads Uploaded");'>~;
    } else {
      $html .= "<p><em>Raw sequence length histogram " . (@$len_raw_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
    }
    if (@$len_qc_bins > 1) {
      my $len_qc_data = join("~", map { $_->[0] .";;" . $_->[1] } @$len_qc_bins);
      my $len_qc_link = $self->chart_export_link($len_qc_bins, 'postqc_len_hist');
      $html .= qq~<p>$len_qc_link</p>
<div id='static3'>
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
<img src='./Html/clear.gif' onload='draw_histogram_plot("len_data_qc", "length_hist_qc", "bps", "Number of Reads Post QC");'>~;
    } else {
      $html .= "<p><em>QC sequence length histogram " . (@$len_qc_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
    }
    $html .= "</div>";
  }

  # sequence gc distribution
  my @gc_raw_hist = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->metagenome_id, 'gc', 'raw') };
  my @gc_qc_hist  = sort {$a->[0] <=> $b->[0]} @{ $mgdb->get_histogram_nums($job->metagenome_id, 'gc', 'qc') };
  my $gc_raw_bins = @gc_raw_hist ? &get_bin_set(\@gc_raw_hist, 0, 100, $self->data('bin_size')) : [];
  my $gc_qc_bins  = @gc_qc_hist  ? &get_bin_set(\@gc_qc_hist, 0, 100, $self->data('bin_size')) : [];

  $html .= qq~<a name='gc_ref'></a>
<h3>Sequence GC Distribution
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("gc_show").style.display = "";
  } else {
    document.getElementById("gc_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='gc_show'>
<p>The histograms below show the distribution of the GC percentage for this metagenome. Each position represents the number of sequences within a GC percentage range. The data used in these graphs is based on raw upload and post QC sequences.</p>~;

  if (@$gc_raw_bins > 1) {
    my $gc_raw_data = join("~", map { $_->[0] .";;" . $_->[1] } @$gc_raw_bins);
    my $gc_raw_link = $self->chart_export_link($gc_raw_bins, 'upload_gc_hist');
    $html .= qq~<p>$gc_raw_link</p>
<div id='static4'>
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
<img src='./Html/clear.gif' onload='draw_histogram_plot("gc_data_raw", "gc_percent_hist_raw", "% gc", "Number of Reads Uploaded");'>~;
  } else {
    $html .= "<p><em>Raw GC distribution histogram " . (@$gc_raw_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }
  if (@$gc_qc_bins > 1) {
    my $gc_qc_data = join("~", map { $_->[0] .";;" . $_->[1] } @$gc_qc_bins);
    my $gc_qc_link = $self->chart_export_link($gc_qc_bins, 'postqc_gc_hist');
    $html .= qq~<p>$gc_qc_link</p>
<div id='static5'>
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
<img src='./Html/clear.gif' onload='draw_histogram_plot("gc_data_qc", "gc_percent_hist_qc", "% gc", "Number of Reads Post QC");'>~;
  } else {
    $html .= "<p><em>QC GC distribution histogram " . (@$gc_qc_bins ? "has insufficient data" : "not yet computed") . ".</em></p>";
  }
  $html .= "</div>";

  # download
  $html .= "<a name='download_ref'></a><h3>Download This Metagenome</h3>";
  $html .= "<p>We provide download capabilities for the submitted sequences, metadata, and all files with results that are produced in the process of MG-RAST analysis on the <a target=_blank href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$mgid'>download page for this metagenome</a>. This includes fasta files with annotations using the <a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#m5nr'>M5NR</a>.</p>";
  $html .= "<p>We also provide access to the blat alignment summaries underlying our sequence analysis work on the <a target=_blank href='metagenomics.cgi?page=DownloadMetagenome&metagenome=$mgid'>download page</a>.</p>";
  $html .= "<p>Please note: The graphs on this page allow downloading the underlying information as tables. The search results and most of the pie-charts allow selecting the fraction of sequences in an element to work with in the <a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#workbench'>workbench</a> feature on the <a target=_blank href='metagenomics.cgi?page=Analysis&metagenome=$mgid'>analysis page</a>.</p>";

  # analysis
  $html .= "<a name='analyze_ref'></a><h3>Analyze This Metagenome</h3>";
  $html .= "<p>The <a target=_blank href='metagenomics.cgi?page=Analysis&metagenome=$mgid'>analysis page</a> provides access to analysis and comparative tools including tables, bar charts, trees, principle coordinate analysis, heatmaps and various exports (including FASTA and QIIME). The <a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#workbench'>workbench</a> feature allows sub-selections of data to be used e.g. select all E. coli reads and then display the functional categories present just in E. coli reads across multiple data sets.</p>";

  # MG search
  $html .= qq~<a name='search_ref'></a>
<h3>Search This Metagenome</h3>
<p>Below searches return all predicted functions or organisms that contain the input text.</p>
<input id='func_txt' type='text' />&nbsp;&nbsp;&nbsp;
<button onclick='
  var aText=document.getElementById("func_txt").value;
  execute_ajax("search_stuff","func_div","type=func&metagenome=$mgid&text="+aText);'>Search Functions</button>
<br><div id='func_div'></div><br>
<input id='org_txt' type='text' />&nbsp;&nbsp;&nbsp;
<button onclick='
  var aText=document.getElementById("org_txt").value;
  execute_ajax("search_stuff","org_div","type=org&metagenome=$mgid&text="+aText);'>Search Organisms</button>
<br><div id='org_div'></div><br>~;

  # metadata table
  my $mdata = $mddb->get_metadata_for_table($job);
  if (@$mdata > 0) {
    my $mtable = $self->application->component('metadata_tbl');
    $mtable->width(800);
    $mtable->show_export_button({title => "Download this table", strip_html => 1});
    
    if ( scalar(@$mdata) > 25 ) {
      $mtable->show_top_browse(1);
      $mtable->show_bottom_browse(1);
      $mtable->items_per_page(25);
      $mtable->show_select_items_per_page(1); 
    }   
    $mtable->columns([ { name => 'Category', filter  => 1, sortable => 1, operator => 'combobox' },
		       { name => 'Label', filter  => 1, sortable => 1 },
		       { name => 'Value', filter  => 1, sortable => 1 }
		     ]);
    $mtable->data($mdata);
    $html .= qq~<a name='meta_ref'></a>
<h3>Metadata
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#metadata' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("metadata_show").style.display = "";
  } else {
    document.getElementById("metadata_show").style.display = "none";
    this.innerHTML = "show";
  }'>show</a></h3>
<div id='metadata_show' style='display: none;'>
<p>The table below contains contextual metadata describing sample location, acquisition, library construction, sequencing using <a target=_blank href='http://gensc.org'>GSC</a> compliant metadata.</p>~ . $mtable->output . "</div>";
  }
  
  # pubmed abstracts
  if ($md_ext_ids->{pubmed}) {
    my @ids = grep {$_ =~ /^\d+$/} split(/, /, $md_ext_ids->{pubmed});
    if (@ids > 0) {
        $html .= "<a name='pub_ref'></a><h3>Publication Abstracts";
        $html .= "<span style='font-size:12px;padding-left:15px;'>[" . join(", ", map { "<a href='http://www.ncbi.nlm.nih.gov/pubmed/".$_."' target=_blank>".$_."</a>" } @ids) . "]</span>";
        $html .= "<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='if(this.innerHTML==\"show\"){this.innerHTML=\"hide\";document.getElementById(\"abstracts\").style.display=\"\";}else{document.getElementById(\"abstracts\").style.display=\"none\";this.innerHTML=\"show\"};'>show</a></h3><div id='abstracts' style='display: none;'>";
        foreach my $id (@ids) {
            $html .= $self->get_pubmed_abstract($id)."<br><br>";
        }
        $html .= "</div>";
    }
  }

  # bottom padding
  $html .= "<br><br><br><br>";
  return $html;
}

sub edit_name_info {
  my ($self, $job) = @_;

  my $html = "<h3>Edit Metagenome Name</h3>";
  $html .= $self->start_form('edit_name', {metagenome => $job->metagenome_id, action => 'edit_name'});
  $html .= "Enter new metagenome name: <input type='text' name='new_name' style='width:250px;' value='".encode_entities($job->name)."' />";
  $html .= "<span>&nbsp;&nbsp;&nbsp;</span><input type='submit' value='update'>".$self->end_form()."<br />";
  return $html;
}

sub edit_name {
  my ($self) = @_;

  my $app  = $self->application();
  my $cgi  = $app->cgi;
  my $user = $app->session->user;
  my $mgid = $cgi->param('metagenome');
  my $name = $cgi->param('new_name') || '';
  $name =~ s/^\s+//;
  $name =~ s/\s+$//;

  if ($user && ($user->has_right(undef, 'edit', 'metagenome', $mgid))) {
    my $job  = $app->data_handle('MGRAST')->Job->init({ metagenome_id => $mgid });
    my $size = length($name);
    if ($size < 5) {
      $app->add_message('warning', "new name is too short: ".$name); return 0;
    }
    elsif ($size > 64) {
      $app->add_message('warning', "new name is too long: ".$name); return 0;
    }
    if ($name eq $job->name) {
      $app->add_message('warning', "new name same as old: ".$name); return 0;
    }
    $job->name($name);
    $app->add_message('info', "successfully changed name of $mgid to $name");
  }
  else {
    $app->add_message('warning', "you do not have the permission to edit $mgid"); return 0;
  }
  return 1;
}

sub delete_info {
  my ($self, $job) = @_;

  my $html = "<h3>Delete</h3>";
  $html .= $self->start_form('delete_job', {metagenome => $job->metagenome_id, non_ajax_action => 'delete_job'});
  $html .= "<p><strong>To delete this job, type 'DELETE' into the textbox and click 'delete job'.<br /><div style='color:red;'>THIS WILL DELETE THE JOB AND ALL ASSOCIATED METADATA PERMANENTLY!</div></strong></p>";
  $html .= "<input name='confirmation' type='text'>";
  $html .= "&nbsp;&nbsp;&nbsp;<input type='submit' value='delete job'>".$self->end_form."<br />";
  return $html;
}

sub delete_job {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $application->session->user;
  my $cgi = $application->cgi;
  my $jobdbm = $application->data_handle('MGRAST');
  my $mgid = $cgi->param('metagenome');
  my $job = $jobdbm->Job->init({ metagenome_id => $mgid });

  my $conf = lc($cgi->param('confirmation'));
  unless ($conf && $conf eq 'delete') {
    $application->add_message('warning', "Unable to delete metagenome.");
    return 1;
  }

  my ($status, $msg) = $job->user_delete($user);

  if($status) {
    $cgi->delete('metagenome_id');
    $application->add_message('info', "Metagenome $mgid has been deleted");
  } else {
    $application->add_message('warning', $msg);
  }

  return 1;
}


sub get_summary_chart {
  # failed, unknown, unknown aa, ann aa, ann rna
  my ($self, $colors, $failed, $unknown, $aa_unknown, $aa_annotated, $rna_annotated) = @_;

  my $colstr = '"'. join('","', @$colors) . '"';
  return qq~
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var color = [$colstr];
    var data  = new google.visualization.DataTable();
    data.addColumn("string", "Description");
    data.addColumn("number", "Sequences");
    data.addRow(["Failed QC", $failed]);
    data.addRow(["Unknown", $unknown]);
    data.addRow(["Unknown Protein", $aa_unknown]);
    data.addRow(["Annotated Protein", $aa_annotated]);
    data.addRow(["ribosomal RNA", $rna_annotated]);
    var chart = new google.visualization.PieChart(document.getElementById("summary_chart_div"));
    chart.draw(data, {width: 400, height: 300, colors: color, sliceVisibilityThreshold: 1/25000, chartArea: {left:25,top:0,width:"100%",height:"100%"}});
  }
</script>
<div id='summary_chart_div'></div>
~;
}

sub get_source_chart {
  my ($self, $job, $is_rna, $is_gene, $n_prot, $p_prot, $n_func, $p_func, $n_rna, $p_rna) = @_;
  
  my $mgdb = $self->data('mgdb');
  my $src_stats = $mgdb->get_source_stats($job->metagenome_id);
  my $src_html  = "";
  if (scalar(keys %$src_stats) > 0) {
    my $src_vbar  = $self->application->component('vbar1');
    my $evalues   = ["-3 to -5", "-5 to -10", "-10 to -20", "-20 to -30", "-30 & less"];
    my $legend    = ["e-value (exponent)"];
    my $colors    = [ [[54,116,217], [128,176,255]], [[51,204,94], [128,255,164]], [[255,255,0], [255,252,150]], [[255,136,0], [255,187,110]], [[247,42,66], [255,193,200]] ];
    my $sources   = $mgdb->_sources();
    my $titles    = { protein => 'functional & organism', ontology => 'functional hierarchy', rna => 'ribosomal RNA genes' };
    my (@data, @desc, @srcs, %groups, @divs, @chart);

    $sources->{ITS} = {type => 'rna', description => 'ITS rRNA Database'};
    my $num = 0;
    foreach my $type ( ('protein', 'ontology', 'rna') ) {
      next if ($is_rna && ($type ne 'rna'));
      next if ($is_gene && ($type ne 'protein'));
      my $src_num = 0;
      foreach my $src (sort grep {$sources->{$_}->{type} eq $type} keys %$sources) {
        my $src_total = 0;
	    next if ($src eq 'GO');
	    if (exists($src_stats->{$src}) && exists($src_stats->{$src}->{evalue})) {
	      $num += 1;
	      $src_num += 1;
	      push @srcs, ($src =~ /^(LSU|SSU)$/) ? 'SILVA '.$src : $src;
	      push @data, [ $src_stats->{$src}->{evalue} ];
	      push @desc, $sources->{$src}->{description};
	      push @chart, [ $src, sum @{$src_stats->{$src}->{evalue}} ];
	    }
      }
      if ($src_num > 0) {
	    my $pos = ($num - $src_num) + int($src_num / 2) - 1;
	    if ($pos < 0) { $pos = 0; }
	    $groups{$pos} = $titles->{$type};
	    push @divs, $num;
      }
    }
    pop @divs;
    my %divs  = map {$_, 1} @divs;
#    my $pmd5s = format_number( $mgdb->ach->count4md5s('protein') );
#    my $rmd5s = format_number( $mgdb->ach->count4md5s('rna') );
    my $link  = $self->chart_export_link(\@chart, 'source_hits');
    my $rtext = $is_gene ? "" : "$n_rna ($p_rna) of reads had similarity to ribosomal RNA genes. ";
    my $ptext = $is_rna ? "" : "$n_prot ($p_prot) of the predicted protein features could be annotated with similarity to a protein of known function. ";
    my $otext = ($is_gene || $is_rna) ? "" : "$n_func ($p_func) of these annotated features could be placed in a functional hierarchy. ";

    $src_vbar->width(700);
    $src_vbar->data(\@data);
    $src_vbar->subsets($legend);
    $src_vbar->datasets(\@srcs);
    $src_vbar->supersets($evalues);
    $src_vbar->data_groups(\%groups);
    $src_vbar->dividers(\%divs);
    $src_vbar->title_hovers(\@desc);
    $src_vbar->rotate_colors(1);
    $src_vbar->bar_color_set($colors);
    $src_vbar->show_counts(1);
    $src_vbar->hide_scale(1);
    $src_html .= qq~
<a name='source_ref'></a>
<h3>Source Hits Distribution
  <a target=_blank href='metagenomics.cgi?page=Sources' style='font-size:14px;padding-left:5px;'>[?]</a>
  <a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("source_show").style.display = "";
  } else {
    document.getElementById("source_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='source_show'>
<p>$ptext$otext$rtext</p>
<p>The graph below displays the number of features in this dataset that were annotated by the different databases below. These include protein databases, protein databases with functional hierarchy information, and ribosomal RNA databases. The bars representing annotated reads are colored by e-value range. Different databases have different numbers of hits, but can also have different types of annotation data.</p>~;
#<p>There are $pmd5s sequences in the M5NR protein database and $rmd5s sequences in the M5RNA ribosomal database. The M5NR protein database contains all the unique sequences from the below protein databases and the M5RNA ribosomal database contains all the unique sequences from the below ribosomal RNA databases.</p>
$src_html .= qq~<p>$link</p>
<table><tr><td>~.$src_vbar->output."</td><tr><td>".$src_vbar->legend."</td></tr></table></div><br>";
  }
  return $src_html;
}

sub get_taxa_chart {
  my ($self, $job) = @_;

  my $mgdb = $self->data('mgdb');
  my $mgid = $job->metagenome_id;
  my $jid  = $job->job_id;
  my $taxa_html = qq~
<a name='org_ref'></a>
<h3>Taxonomic Hits Distribution
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("taxa_show").style.display = "";
  } else {
    document.getElementById("taxa_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='taxa_show'>
  <p>The pie charts below illustrate the distribution of taxonomic domains, phyla, and orders for the annotations. Each slice indicates the percentage of reads with predicted proteins and ribosomal RNA genes annotated to the indicated taxonomic level.  This information is based on all the annotation source databases used by MG-RAST. An interactive <a hrep='http://sourceforge.net/p/krona/home/krona'>Krona</a> chart of the full taxonomy is also available<br>Click on a slice or legend to view all sequences annotated with the indicated taxonomic level in the analysis page.</p>
  <p><a style='cursor:pointer;clear:both;' onclick='execute_ajax("draw_krona", "krona_for_tax", "metagenome=$mgid&job=$jid&type=tax");'>View taxonomic interactive chart</a>
  <div id='krona_for_tax'></div></p>
~;

  my $taxa_charts = [];
  my @taxa_levels = @{$self->data('tax_levels')};
  pop @taxa_levels;
  foreach my $tax (@taxa_levels) {
    my $taxa_stats = $mgdb->get_taxa_stats($mgid, $tax);
    unless (@$taxa_stats > 0) {
      @$taxa_stats = map { [$_->[1], $_->[2]] } @{$mgdb->get_abundance_for_tax_level("tax_$tax")};
    }
    if (@$taxa_stats > 0) {
      my $data_rows  = join("\n", map { qq(data.addRow(["$_->[0]", $_->[1]]);) } @$taxa_stats);
      my $data_count = scalar @$taxa_stats;
      my $data_link  = $self->chart_export_link($taxa_stats, 'organism_'.$tax.'_hits');
      push @$taxa_charts, qq~
<p><table>
  <tr><td>$tax&nbsp;&nbsp;</td><td>$data_link</td></tr>
</table></p>
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var color = GooglePalette($data_count);
    var data = new google.visualization.DataTable();
    data.addColumn("string", "$tax");
    data.addColumn("number", "Hits");
    $data_rows
    var chart = new google.visualization.PieChart(document.getElementById("${tax}_chart_div"));
    chart.draw(data, {width: 450, height: 300, colors: color, chartArea: {left:50,top:0,width:"90%",height:"90%"}});
    google.visualization.events.addListener(chart, 'select', function() {
      var sel = chart.getSelection();
      if (sel.length > 0) {
        var name = data.getValue(sel[0].row, 0);
        check_download('tax', name, 'tax_$tax', '$mgid');
      }
    });
  }
</script>
<div id='${tax}_chart_div'></div>
~;
    }
  }    
  if (@$taxa_charts > 0) {
    $taxa_html .= "<table><tr>";
    for (my $i=0; $i<@$taxa_charts; $i++) {
      if (($i == 2) || ($i == 4)) { $taxa_html .= "</tr><tr>"; }
      $taxa_html .= "<td>".$taxa_charts->[$i]."</td>"
    }
    $taxa_html .= "</tr></table></div>";
    return $taxa_html;
  }
  else {
    return "";
  }
}  

sub get_func_charts {
  my ($self, $job, $pred, $ann) = @_;

  my $mgdb = $self->data('mgdb');
  my $mgid = $job->metagenome_id;
  my $jid  = $job->job_id;
  my $src_stats = $mgdb->get_source_stats($mgid);
  my $sources   = $mgdb->_sources();
  my $src_names = [];
  my $src_links = [];
  
  foreach my $s (sort keys %$sources) {
    if (($sources->{$s}{type} eq 'ontology') && ($s ne 'GO')) {
      if (exists $sources->{$s}{url}) {
	push @$src_links, "<a target=_blank href='".$sources->{$s}{url}."'>".(($s =~ /s$/) ? $s : $s.'s')."</a>";
      }
      push @$src_names, $s;
    }
  }
  if (@$src_links > 0) {
    $src_links->[-1] = 'and ' . $src_links->[-1];
  }

  my $link_text = join(', ', @$src_links);
  my $func_html = qq~
<a name='func_ref'></a>
<h3>Functional Category Hits Distribution
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#functional_hierarchy' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("ontology_show").style.display = "";
  } else {
    document.getElementById("ontology_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='ontology_show'>
  <p>The pie charts below illustrate the distribution of functional categories for $link_text at the highest level supported by these functional hierarchies. Each slice indicates the percentage of reads with predicted protein functions annotated to the category for the given source. An interactive <a hrep='http://sourceforge.net/p/krona/home/krona'>Krona</a> chart of each functional hierarchy is also available<br>Click on a slice or legend to view all sequences annotated with the indicated category in the analysis page.</p>
~;
  my $func_charts = [];
  foreach my $name (@$src_names) {
    my $func_stats = $mgdb->get_ontology_stats($mgid, $name);
    my $func_total = sum map {$_->[1]} @$func_stats;
    if ((@$func_stats > 0) && ($func_stats->[0][0])) {
      my $data_rows  = join("\n", map { qq(data.addRow(["$_->[0]", $_->[1]]);) } @$func_stats);
      my $data_count = scalar @$func_stats;
      my $data_link  =  $self->chart_export_link($func_stats, $name.'_functional_hits');
      my $t_func = "has " . format_number($func_total) ." predicted functions";
      my $p_prot = percent($func_total, $pred) . " of predicted proteins";
      my $p_func = percent($func_total, $ann) . " of annotated proteins";
      push @$func_charts, qq~
<p><table>
  <tr><td>$name&nbsp;&nbsp;</td><td>$data_link</td></tr>
  <tr><td>&nbsp;</td><td>$t_func</td></tr>
  <tr><td>&nbsp;</td><td>$p_prot</td></tr>
  <tr><td>&nbsp;</td><td>$p_func</td></tr>
  <tr><td>&nbsp;</td><td>
    <a style='cursor:pointer;clear:both;' onclick='execute_ajax("draw_krona", "krona_for_$name", "metagenome=$mgid&job=$jid&type=$name");'>View $name interactive chart</a>
    <div id='krona_for_$name'></div></p>
  </td></tr>
</table></p>
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var color = GooglePalette($data_count);
    var data = new google.visualization.DataTable();
    data.addColumn("string", "Category");
    data.addColumn("number", "Hits");
    $data_rows
    var chart = new google.visualization.PieChart(document.getElementById("${name}_chart_div"));
    chart.draw(data, {width: 450, height: 300, colors: color, chartArea: {left:50,top:0,width:"90%",height:"90%"}});
    google.visualization.events.addListener(chart, 'select', function() {
      var sel = chart.getSelection();
      if (sel.length > 0) {
        var cat = data.getValue(sel[0].row, 0);
        check_download('$name', cat, 'level1', '$mgid');
      }
    });
  }
</script>
<div id='${name}_chart_div'></div>
~;
    }
  }
  if (@$func_charts > 0) {
    $func_html .= "<table><tr>";
    for (my $i=0; $i<@$func_charts; $i++) {
      if ($i == 2) { $func_html .= "</tr><tr>"; }
      $func_html .= "<td>".$func_charts->[$i]."</td>"
    }
    $func_html .= "</tr></table></div>";
    return $func_html;
  }
  else {
    return "";
  }
}

sub draw_krona {
  my ($self) = @_;

  my $mgdb = $self->data('mgdb');
  my $mgid = $self->application->cgi->param('metagenome');
  my $jid  = $self->application->cgi->param('job');
  my $type = $self->application->cgi->param('type');

  if ($type eq 'tax') {
    my $taxa_stats = $mgdb->get_taxa_stats($mgid, 'genus'); # genus, abundance
    unless (@$taxa_stats > 0) {
      @$taxa_stats = map { [$_->[1],  $_->[2]] } @{$mgdb->get_abundance_for_tax_level("tax_genus")};
    }
    if (@$taxa_stats > 0) {
      my $taxons = $mgdb->get_taxa_to_level("genus");
      my $names  = ['Domain', 'Phylum', 'Class', 'Order', 'Family', 'Genus'];
      my $result = [];
      foreach my $tax (@$taxa_stats) {
          if (exists $taxons->{$tax->[0]}) {
              push @$result, [ $mgid, @{$taxons->{$tax->[0]}}, $tax->[1], 1 ];
          }
      }
      my $krona_data = array2json($result, 2);
      my $krona_name = '["' . join('","', @$names) . '"]';
      return "<img src='./Html/clear.gif' onload='generate_krona($krona_data, $krona_name, 1);'>";
    } else {
      return "<p><em>Insufficient data</em></p>";
    }
  }
  else {
    my $max_depth = (($type eq 'COG') || ($type eq 'NOG')) ? 3 : 4;
    my ($md5_data, $ont_data) = $mgdb->get_ontology_for_source($type);
    my @func_nums = map { [ @$_[1..3] ] } @$ont_data; # id, annotation, abundance
    if (@func_nums > 0) {
      my $ontology = $mgdb->get_hierarchy('ontology', $type);
      my $result   = [];
      foreach my $func (@func_nums) {
	if (exists $ontology->{$func->[0]}) {
	  push @$result, [ $mgid, @{$ontology->{$func->[0]}}[0..($max_depth-2)], $func->[1], $func->[2], 1 ];
	}
      }
      my $krona_data = array2json($result, 2);
      my $krona_name = '["' . join('","', map {"Level $_"} (1..($max_depth-1))) . '","Function"]';
      return "<img src='./Html/clear.gif' onload='generate_krona($krona_data, $krona_name, 1);'>";
    } else {
      return "<p><em>Insufficient data</em></p>";
    }
  }
}

sub get_drisee_chart {
  my ($self, $job) = @_;

  my $mgdb = $self->data('mgdb');
  my $drisee = $mgdb->get_qc_stats($job->metagenome_id, 'drisee');
  unless ($drisee && exists($drisee->{percents}) && $drisee->{percents}{data}) {
    return "<p><em>Not yet computed</em></p>";
  }

  # data = [ pos, A, T, C, G, N, X, total ]
  my @values_data = ($drisee->{counts}{columns}, @{$drisee->{counts}{data}});
  my @down_data   = ($drisee->{percents}{columns}, @{$drisee->{percents}{data}});
  
  my $values_link = $self->chart_export_link(\@values_data, 'drisee_values', 'Download DRISEE values');
  my $drisee_link = $self->chart_export_link(\@down_data, 'drisee_plot', 'Download DRISEE plot');
  my $drisee_rows = join(",\n", map { "[".join(',', @$_)."]" } @{$drisee->{percents}{data}});
  my $html = qq~
<p>$values_link</p>
<p>$drisee_link</p>
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var color = bpColors();
    var data = new google.visualization.arrayToDataTable([
      ['Position','A','T','C','G','N','InDel','Total'],
      $drisee_rows
    ]);
    var chart = new google.visualization.LineChart(document.getElementById("drisee_plot"));
    var opts  = { width: 800, height: 250, colors: color,
                  chartArea: { left:50, top:10, width:"80%", height:"80%" },
                  vAxis: { minValue:0, maxValue:100, title:"Percent Error", gridlines:{count:11}, textStyle:{fontSize:10} },
                  hAxis: { title:"bp Position", gridlines:{count:10}, textStyle:{fontSize:10} }
                 };
    chart.draw(data, opts);
  }
</script>
<div id='drisee_plot'></div>~;

  return $html;
}

sub get_kmer_plot {
  my ($self) = @_;

  my $mgdb = $self->data('mgdb');
  my $mgid = $self->application->cgi->param('metagenome');
  my $jid  = $self->application->cgi->param('job');
  my $type = $self->application->cgi->param('type');
  my $size = $self->application->cgi->param('size');
  my $kmer = $mgdb->get_qc_stats($mgid, 'kmer');
  my @data = ();
  my ($xscale, $yscale, $xtext, $ytext);

  unless ($kmer && exists($kmer->{$size.'_mer'}) && $kmer->{$size.'_mer'}{data}) {
    return "<p><em>Not yet computed</em></p>";
  }
  # data = [ x, y ]
  if ($type eq 'abundance') {
    @data = map { [ $_->[3], $_->[0] ] } @{$kmer->{$size.'_mer'}{data}};
    ($xscale, $yscale, $xtext, $ytext) = ('log', 'log', 'sequence size', 'kmer coverage');
  } elsif ($type eq 'ranked') {
    @data = map { [ $_->[3], (1 - (1.0 * $_->[5])) ] } @{$kmer->{$size.'_mer'}{data}};
    ($xscale, $yscale, $xtext, $ytext) = ('log', 'linear', 'sequence size', 'fraction of observed kmers');
  } elsif ($type eq 'spectrum') {
    @data = map { [ $_->[0], $_->[1] ] } @{$kmer->{$size.'_mer'}{data}};
    ($xscale, $yscale, $xtext, $ytext) = ('log', (($size == 6) ? 'linear' : 'log'), 'kmer coverage', 'number of kmers');
  } else {
    return "<p><em>Not yet computed</em></p>";
  }
  my $kmer_name = "kmer_".$size."_".$type;
  my $kmer_data = join("~", map { $_->[0] .";;" . $_->[1] } @data);
  my $kmer_link = $self->chart_export_link(\@data, $kmer_name);
  my $html = qq~
<p>The kmer abundance spectra are tools to summarize the redundancy (repetitiveness) of sequence datasets by counting the number of occurrences of 15 and 6 bp sequences.</p>
<p>The kmer spectrum plots the number of distinct N-bp sequences as a function of coverage level, placing low-coverage (rare) sequences at left and high-coverage, repetitive sequences at right. The kmer rank abundance graph plots the kmer coverage as a function of abundance rank, with the most abundant sequences at left. The ranked kmer consumed graph shows the fraction of the dataset that is explained by the most abundant kmers, as a function of the number of kmers used.</p>
<p>$kmer_link</p>
<div id='static1'>
The image is currently dynamic. To be able to right-click/save the image, please click the static button
<input type='button' value='static' onclick='
  document.getElementById("static1").style.display = "none";
  document.getElementById("dynamic1").style.display = "";
  save_image("$kmer_name");
  document.getElementById("kmer_plotcanvas").style.display = "";
  document.getElementById("kmer_plot").style.display = "none";'>
</div>
<div style='display: none;' id='dynamic1'>The image is currently static. You can right-click/save it. To enable dynamic image, please click the dynamic button
<input type='button' value='dynamic' onclick='
  document.getElementById("static1").style.display = "";
  document.getElementById("dynamic1").style.display = "none";
  document.getElementById("kmer_plotcanvas").style.display = "none";
  document.getElementById("kmer_plot").style.display = "";'>
</div>
<div><div id='kmer_plot'></div></div>
<input type='hidden' id='kmer_data' value='$kmer_data'>
<img src='./Html/clear.gif' onload='draw_kmer_curve("kmer_data", "kmer_plot", "$xscale", "$yscale", "$xtext", "$ytext");'>~;

  return $html;
}

sub get_consensus_chart {
  my ($self, $job) = @_;

  my $mgdb = $self->data('mgdb');
  my $consensus = $mgdb->get_qc_stats($job->metagenome_id, 'bp_profile');

  unless ($consensus && exists($consensus->{percents}) && $consensus->{percents}{data}) {
    return "<p><em>Not yet computed</em></p>";
  }
  
  # rows = [ pos, A, T, C, G, N ]
  # data = [ pos, N, G, C, T, A ]
  my @data = map { [$_->[0], $_->[5], $_->[4], $_->[3], $_->[2], $_->[1]] } @{$consensus->{percents}{data}};
  my $consensus_link = $self->chart_export_link(\@data, 'consensus_plot');
  my $consensus_rows = join(",\n", map { "[".join(',', @$_)."]" } @data);
  my $num_bps = scalar(@data);

  my $html .= qq~<a name='consensus_ref'></a>
<h3>Nucleotide Position Histogram
<a target=_blank href='http://blog.metagenomics.anl.gov/glossary-of-mg-rast-terms-and-concepts/#consensus_plot' style='font-size:14px;padding-left:5px;'>[?]</a>
<a style='cursor:pointer;clear:both;font-size:small;padding-left:10px;' onclick='
  if (this.innerHTML=="show") {
    this.innerHTML = "hide";
    document.getElementById("consensus_show").style.display = "";
  } else {
    document.getElementById("consensus_show").style.display = "none";
    this.innerHTML = "show";
  }'>hide</a></h3>
<div id='consensus_show'>
  <p>These graphs show the fraction of base pairs of each type (A, C, G, T, or ambiguous base "N") at each position starting from the beginning of each read up to the first $num_bps base pairs. Amplicon datasets should show consensus sequences; shotgun datasets should have roughly equal proportions of basecalls.</p>
  <p>$consensus_link</p>
  <script type="text/javascript">
    google.load("visualization", "1", {packages:["corechart"]});
    google.setOnLoadCallback(drawChart);
    function drawChart() {
      var color = bpColors();
      color.reverse().splice(0,2);
      var data = new google.visualization.arrayToDataTable([
        ['Position','N','G','C','T','A'],
        $consensus_rows
      ]);
      var chart = new google.visualization.AreaChart(document.getElementById("consensus_plot"));
      var opts  = { width: 800, height: 250, colors: color, areaOpacity: 1.0, isStacked: true,
                    chartArea: { left:50, top:10, width:"80%", height:"80%" },
                    vAxis: { minValue:0, maxValue:100, title:"Percent bp", gridlines:{count:11}, textStyle:{fontSize:10} },
                    hAxis: { title:"bp Position", gridlines:{count:10}, textStyle:{fontSize:10} }
                   };
      chart.draw(data, opts);
    }
  </script>
  <div id='consensus_plot'></div>
</div>~;

  return $html;
}

sub get_abund_plot {
  my ($self) = @_;

  my $html  = "";
  my $mgdb  = $self->data('mgdb');
  my $mgid  = $self->application->cgi->param('metagenome');
  my $jid   = $self->application->cgi->param('job');
  my $level = $self->application->cgi->param('level');

  my $aplot = $mgdb->get_taxa_stats($mgid, $level);
  unless (@$aplot > 0) {
    @$aplot = map { [$_->[1],  $_->[2]] } @{$mgdb->get_abundance_for_tax_level("tax_$level")};
  }

  if (@$aplot > 1) {
    my @sort_plot = sort { $b->[1] <=> $a->[1] } @$aplot;
    if (@sort_plot > 50) {
      @sort_plot = @sort_plot[0..49];
    }
    my $rap_data = join("~", map { $_->[0] .";;" . $_->[1] } @sort_plot);
    $rap_data =~ s/'/\&\#39\;/g;
    my $rap_link = $self->chart_export_link(\@sort_plot, 'abundance_plot');
    
    $html = qq~
<p>The plot below shows the $level abundances ordered from the most abundant to least abundant. Only the top 50 most abundant are shown. The y-axis plots the abundances of annotations in each $level on a log scale.</p>
<p>The rank abundance curve is a tool for visually representing taxonomic richness and evenness.</p>
<p>$rap_link</p>
<div id='static1'>
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
<img src='./Html/clear.gif' onload='draw_rank_abundance_plot("rap_data", "rank_abundance_plot", "$mgid", "tax_$level");'>~;
  } else {
    $html = "<p><em>" . (@$aplot ? "Insufficient data" : "Not yet computed") . ".</em></p>";
  }
  return $html;
}

sub get_rare_curve {
  my ($self) = @_;

  my $html = "";
  my $mgdb = $self->data('mgdb');
  my $mgid = $self->application->cgi->param('metagenome');
  my $jid   = $self->application->cgi->param('job');

  my $curve = $mgdb->get_rarefaction_coords($mgid);
  unless (@$curve > 0) {
    my $tmp = $mgdb->get_rarefaction_curve();
    if ($tmp && exists($tmp->{$mgid})) {
      $curve = $tmp->{$mgid};
    }
  }

  if (@$curve > 1) {
    my $rare_data = join("~", map { $_->[0] . ";;" . $_->[1] } @$curve);
    my $rare_link = $self->chart_export_link($curve, 'rarefaction_curve');

    $html = qq~
<p>The plot below shows the rarefaction curve of annotated species richness. This curve is a plot of the total number of distinct species annotations as a function of the number of sequences sampled. On the left, a steep slope indicates that a large fraction of the species diversity remains to be discovered. If the curve becomes flatter to the right, a reasonable number of individuals is sampled: more intensive sampling is likely to yield only few additional species.</p>
<p>Sampling curves generally rise very quickly at first and then level off towards an asymptote as fewer new species are found per unit of individuals collected. These rarefaction curves are calculated from the table of species abundance.  The curves represent the average number of different species annotations for subsamples of the the complete dataset.</p>
<p>$rare_link</p>
<div id='static6'>
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

sub get_alpha {
  my ($self) = @_;

  my $html  = "";
  my $mgdb  = $self->data('mgdb');
  my $jobdb = $self->app->data_handle('MGRAST');
  my $mgid  = $self->application->cgi->param('metagenome');
  my $jid   = $self->application->cgi->param('job');
  my $alpha = $self->application->cgi->param('alpha') || 0;
  my $job   = $jobdb->Job->init({ job_id => $jid });

  if ($alpha == 0) {
    my $tmp = $mgdb->get_rarefaction_curve([], 1);
    if ($tmp && exists($tmp->{$mgid})) {
      $alpha = $tmp->{$mgid};
    }
  }

  $html .= "<p><b>&alpha;-Diversity = ".sprintf("%.3f", $alpha)." species</b></p>";
  if ($job->primary_project && ref($job->primary_project)) {
    my $proj_jobs = $job->primary_project->metagenomes(1);
    my ($min, $max, $avg, $stdv) = @{ $jobdb->JobStatistics->stats_for_tag('alpha_diversity_shannon', $proj_jobs, 1) };
    $html .= "<img src='./Html/clear.gif' onload='draw_position_on_range(\"alpha_range_div\", $alpha, $min, $max, $avg, $stdv);'>";
    $html .= "<div id='alpha_range_div'></div>";
    $html .= "<p>The above image shows the range of &alpha;-diversity values in project ".$job->primary_project->name.". The min, max, and mean values are shown, with the standard deviation ranges (&sigma; and 2&sigma;) in different shades. The &alpha;-diversity of this metagenome is shown in red.</p>";
  }
  $html .= "<p>Alpha diversity summarizes the diversity of organisms in a sample with a single number. The alpha diversity of annotated samples can be estimated from the distribution of the species-level annotations.</p>";
  $html .= "<p>Annotated species richness is the number of distinct species annotations in the combined MG-RAST dataset. Shannon diversity is an abundance-weighted average of the logarithm of the relative abundances of annotated species. The species-level annotations are from all the annotation source databases used by MG-RAST.</p>";

  my $sp_abund = $mgdb->get_taxa_stats($mgid, 'species');
  if (@$sp_abund > 0) {
    $html .= "<p>" . $self->chart_export_link($sp_abund, 'species_anundance', 'Download source data') . "</p>";
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
  unshift @$bins, [ $min_num, 0 ];
  return $bins;
}

sub search_stuff {
  my ($self) = @_;

  my $html = "";
  my $mgdb = $self->data('mgdb');
  my $mgid = $self->application->cgi->param('metagenome');
  my $text = $self->application->cgi->param('text');
  my $type = $self->application->cgi->param('type');

  my $colname = ($type eq 'org') ? 'Organism' : 'Function';
  my $results = ($type eq 'org') ? $mgdb->search_organisms($text) : $mgdb->search_functions($text);

  if (exists $results->{$mgid}) {
    my $data = [];
    foreach my $d (@{$results->{$mgid}}) {
      my $source = ($type eq 'org') ? 'tax' : $d->[0];
      my $button = qq(<button onclick='check_download("$source", "$d->[1]", "none", "$mgid");'><img src='./Html/analysis.gif' style='width:20px;height:20px;'></button>);
      push @$data, [ @$d, $button ];
    }
    my @data   = map { [ @$_, qq(<button onclick='check_download("$type", "$_->[0]", "none", "$mgid");'></button>) ] } @{$results->{$mgid}};
    my $table  = $self->application->component("${type}_tbl");
    $table->width(800);
    $table->show_export_button({title => "Download this table", strip_html => 1});
    if ( scalar(@$data) > 25 ) {
      $table->show_top_browse(1);
      $table->show_bottom_browse(1);
      $table->items_per_page(25);
      $table->show_select_items_per_page(1); 
    }   
    $table->columns([ { name => 'Source', filter  => 1, sortable => 1, operator => 'combobox' },
		      { name => $colname, filter  => 1, sortable => 1 },
		      { name => 'Abundance', filter  => 1, sortable => 1, operators => ['less','more'] },
		      { name => 'Analyze' }
		    ]);
    $table->data($data);
    return "<p>".$table->output()."</p>";
  }
  else {
    return "<p>No data returned for your search query.</p>"
  }
}

sub format_number {
  my ($val) = @_;

  if ($val =~ /(\d+)\.\d/) {
    $val = $1;
  }
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}

sub percent {
  my ($num, $den) = @_;
  if ($num == 0) { return '0.0%'; }
  if ($den == 0) { return 'NA'; }
  return sprintf("%.1f", 100 * (($num * 1.0) / $den)) . '%';
}

sub array2json {
  my ($array, $depth) = @_;

  if ($depth == 1) {
    return '["' . join('","', map {krona_clean($_)} @$array) . '"]';
  }
  elsif ($depth == 2) {
    return '[' . join(',', map {'["'.join('","', map {krona_clean($_)} @$_).'"]' } grep {$_} @$array) . ']';
  }
  else {
    return '[]';
  }
}

sub krona_clean {
  my ($txt) = @_;
  unless ($txt) { return ''; }
  $txt =~ s/\'/\@1/g;
  $txt =~ s/\"/\@2/g;
  return $txt;
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

sub chart_export {
  my ($self) = @_;

  my $cgi   = $self->application->cgi;
  my $mgid  = $cgi->param('metagenome');
  my $name  = $cgi->param('name');
  my $file = $Conf::temp."/".$cgi->param('file');

  if (open(FH, "<$file")) {
    my $content = "";
    while (<FH>) {
      $content .= $_;
    }

    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=".$mgid."_".$name.".tsv\n\n";
    print $content;
    
    exit;
  } else {
    $self->application->add_message('warning', "Could not open download file");
  }

  return 1;
}

sub chart_export_link {
  my ($self, $data, $name, $text) = @_;
  
  $text = $text || "Download chart data";
  $name =~ s/\s+/_/g;
  $name =~ s/\W//g;
  my $mgid = $self->data('job')->metagenome_id;
  my $file = "download.$mgid.$name";

  if (open(FH, ">".$Conf::temp."/".$file)) {
    foreach my $d (@$data) {
      print FH join("\t", @$d)."\n";
    }
    close FH;
  }
  return "<a href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mgid&action=chart_export&name=$name&file=$file'>$text</a>";
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/MetagenomeOverview.js",
	   "$Conf::cgi_url/Html/krona.js",
	   "$Conf::cgi_url/Html/canvg.js",
	   "$Conf::cgi_url/Html/rgbcolor.js",
	   "https://www.google.com/jsapi" ];
}
