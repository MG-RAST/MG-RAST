package MGRAST::WebPage::MetagenomeSubset;

# $Id: MetagenomeSubset.pm,v 1.15 2010-11-19 12:41:52 paczian Exp $

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use URI::Escape;

use WebComponent::WebGD;
use GD;
use FIG;
use FIG_Config;


use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset is_public_metagenome dataset_is_metabolic );

1;


=pod

=head1 NAME

MetagenomeSubset - an instance of WebPage which displays the metagenome 
sequences belonging to a given classification

=head1 DESCRIPTION

For any given classification (like a subsystem category or a taxonomy node)
retrieve all sequences of the metagenome.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Sequence Subset');

  # register components
  $self->application->register_component('Table', 'MGTable');
  $self->application->register_component('Ajax', 'MGAjax');
  $self->application->register_component('HelpLink', 'DataHelp');

  # get the metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  # load the settings for this type
  &get_settings_for_dataset($self);

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
      $self->app->error("Unable to retrieve the analysis database for metagenome '$id'.");
      return 1;
    }
    $mgdb->query_load_from_cgi($self->app->cgi, $self->data('dataset'));
    $self->data('mgdb', $mgdb);
  }

  return 1;
}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;
  my $cgi = $self->app->cgi;

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  unless($metagenome) {
    $self->application->error('No metagenome id given.');
  }

  # get the EC number if specified
  my $ec = $self->application->cgi->param('ec') || '';

  # check for download
  if ($self->app->cgi->param('download')) {
    $self->download_fasta();
    return;
  }
  elsif ($self->app->cgi->param('align_sequences')) {
    my $content = $self->align_sequences();
    return $content;
  }

  # get parameters
  my $rank = $self->app->cgi->param('rank') || 0;
  my $taxonomy = $self->app->cgi->param('get') || '';
  $taxonomy = uri_unescape($taxonomy);
  my $filter_taxa = $self->data('mgdb')->split_taxstr($taxonomy);
  my $get = [];
  foreach (my $i=0; $i<=$rank; $i++) {
    push @$get, $filter_taxa->[$i];
  }
  my $genome = $self->app->cgi->param('genome') || '';

  # write title + intro
  my $metagenome_name = $self->data('job')->genome_name." (".$self->data('job')->genome_id.")";
  my $html;
  if ( $ec ) {
      $html = "<p><span style='font-size: 1.6em'><b>Sequence Subset from $metagenome_name for EC $ec</b></span></p>\n";
  } else {
      $html = "<p><span style='font-size: 1.6em'><b>Sequence Subset from $metagenome_name</b></span></p>\n";
  }
  $html .= "<h3><em>".join(' &raquo; ', map { my $t = $self->data('mgdb')->key2taxa($_); 
					      $t =~ s/_/ /g; $t; } @$get)."</em></h3>\n";  

  # add little help thing
  my $datahelp = $self->application->component('DataHelp');
  $datahelp->title($self->data('dataset'));
  $datahelp->disable_wiki_link(1);
  $datahelp->hover_width(300);
  $datahelp->text($self->data('dataset_intro'));


  # summarize parameters
  $html .= "<p>The following options were used to select these sequences:</p>";
  $html .= "<div><table>";

  my @pvalue;
  for( my $i = 200; $i >= 20; $i-=10 ){
    push @pvalue, $i;
  }
  
  my @identity;
  for (my $i=100; $i>=40; $i-=2 ){
    push @identity, $i;
  }
  
  my ($alen_min, $alen_max) = $self->data('mgdb')->get_align_len_range($self->data('dataset'));
  my @alen;
  my $len50 = 0;
  for( my $i = $alen_max; $i > $alen_min; $i-=10 ){
    push @alen, $i;
    $len50 = 1 if ($i == 50);
  }
  push @alen, $alen_min;
  push @alen, 50 unless ($len50);
  @alen = sort { $a <=> $b } @alen;

  $html .= $self->start_form('subset_select', {metagenome => $metagenome, rank => $rank, get => $taxonomy, dataset => $self->data('dataset')});
  if($genome){
    $html .= "<input type='hidden' value='".$genome."'  name='genome'>";
  }

  if($ec){
    $html .= "<input type='hidden' value='".$ec."'  name='ec'>";
  }
  $html .= "<tr><th>Based on metabolic reconstruction by:</th><td>" . $self->data('dataset'). "</td></tr>";
  $html .= "<tr><th>Maximum e-value</th><td>" . 
    $cgi->popup_menu( -name => 'evalue', -default => $cgi->param("evalue") || 0.1, 
		      -values => [0.1, 0.01, 1e-3, 1e-5, 1e-7, 1e-10, 1e-15, 1e-20, 1e-25, 1e-30, 1e-40, 1e-50]) . "</td></tr>";
#  $html .= "<tr><th>Minimum p-value</th><td>".
#    $cgi->popup_menu( -name => 'bitscore', 
#		      -default => $cgi->param("bitscore") || '', -values => ['', @pvalue]);
#  $html .= " <em>leave blank for all</em></td></tr>";

  $html .= "<tr><th>Minimum percent identity</th><td>". 
    $cgi->popup_menu( -name => 'identity', -default => $cgi->param('identity') || '',
		      -values => ['', @identity ]);
  $html .= " <em>leave blank for all</em></td></tr>";

  $html .= "<tr><th>Minimum alignment length</th><td>". 
    $cgi->popup_menu( -name => 'align_len', -default => $cgi->param('align_len') || '',
		      -values => [ '', @alen ]);
  $html .= " <em>leave blank for all</em></td></tr>";

  if ($self->data('dataset') =~ /SEED/){
      $html .= "<tr><th>Show Alignment Graphic</th><td>".
	  $cgi->checkbox( -name => 'show_align', -default => $cgi->param('show_align') || '',
			  -label => 'Show Alignment');
      $html .= " <em>This will add a column to the table showing a graphic alignment between your fragment and hit</em></td></tr>";
  }

  $html .= "<tr><td style='height:5px;'></td></tr><tr><td colspan='2'>".$self->button('Re-compute results', -style=>'height:35px;width:150px;font-size:10pt;')."</td></tr>";  
#  $html .= "<tr><td style='height:5px;'></td></tr><tr><td colspan='2'>".$cgi->submit(-value=>'Re-compute results', -style=>'height:35px;width:150px;font-size:10pt;')."</td></tr>";  
  $html .= "</table></div>\n";
  $html .= $self->end_form;


  # start timer
  my $time = time;

  # get the data
  my $filter = $self->data('mgdb')->join_taxstr($get);
  my $data;
  unless($genome){
      if ( $ec ) {
	  # tax_str obtained here is fake -- real tax_str in table contains taxonomy data, not functional assignment as in subsystem_tax
	  $data = $self->data('mgdb')->get_hits_for_ec($ec);
      } else {
	  $data = $self->data('mgdb')->get_sequence_subset($self->data('dataset'), $filter);
      }
  } else {
      $data = $self->data('mgdb')->get_sequence_subset_genome($genome);
  }

  # download link
  $html .= "<p>Found ".scalar(@$data);
#  $html .= " sequences matching these criteria. <a href=\"metagenomics.cgi?page=MetagenomeSubset&dataset=".$self->app->cgi->param('dataset');
  $html .= " sequences matching these criteria. <a href=\"metagenomics.cgi?page=MetagenomeSubset&dataset=".$self->data('dataset');
  $html .= "&metagenome=".$self->app->cgi->param('metagenome');
  $html .= "&evalue=".($self->app->cgi->param('evalue')||'');
  $html .= "&ec=".($self->app->cgi->param('ec')||'');
  $html .= "&bitscore=".($self->app->cgi->param('bitscore')||'');
  $html .= "&align_len=".($self->app->cgi->param('align_len')||'');
  $html .= "&identity=".($self->app->cgi->param('identity')||'');
  $html .= "&rank=".($self->app->cgi->param('rank')||'0');
  $html .= "&download=1&get=".(uri_escape($self->app->cgi->param('get'))||'');
  $html .= "&genome=".($genome || "")."\">download as FASTA</a>";

  # shrink data set if too large
  my $max_rows = 10000;
  if (scalar(@$data) > $max_rows) {
    @$data = splice @$data, 0, $max_rows;
    $html .= "<br>Displaying only the first $max_rows entries in the table below.";
  }
  $html .= "</p>\n";

  # add links to data array
  my $data_copy;
  $self->application->register_component('Info', 'Info');
  $self->application->register_component('HelpLink', 'LimitHelp');
  my $dataset = $self->data('dataset');

  my $fig = new FIG;

  # figure out the lengths of the hit sequences (for rdp, greengenes, etc)
  my $seqLengths = {};

  foreach my $row (@$data) {
    my $max;
    if ($row->[10] > $row->[9]){
      $max = $row->[10];
    }
    else{
      $max = $row->[9];
    }
    
    if ((defined $seqLengths->{$row->[2]} && $seqLengths->{$row->[2]} < $max) || (!defined $seqLengths->{$row->[2]})) {
      $seqLengths->{$row->[2]} = $max;
    }

  }
######## BABEL test
  my $kegg_img_data = {};
  my $dids = [];
  @$dids = map { $_->[2] } @$data;
  use Babel;
  use DBI;
  my $dbh = DBI->connect("DBI:mysql:dbname=Babel;host=bio-data-1.mcs.anl.gov", "ach", "");
  my $ach = Babel->new( $dbh );
  my $result = $ach->ids2allidswithfuncandsource($dids);
  foreach my $id (keys(%$result)) {
    my $res = $result->{$id};
    if (scalar(@$res)) {
      $kegg_img_data->{$id} = {};
      foreach my $r (@$res) {
	if ($r->[2] eq "KEGG") {
	  $kegg_img_data->{$id}->{kegg} = [ $r->[0], $r->[1] ]; 
	}
	if ($r->[2] eq "IMG_Expert") {
	  $kegg_img_data->{$id}->{img} = [ $r->[0], $r->[1] ]; 
	}
      }
    }
  }
############
  foreach my $row (@$data) {
    my ($row_copy, $length);
    my $input = qq~<input type='checkbox' id='select_sequences' name='select_sequences' value='~ . $row->[0] . qq~'>~;
    push(@$row_copy, $input);
    my $seq_id = uri_escape($row->[0]);

    $row->[0] = "<a href='metagenomics.cgi?page=MetagenomeSequence&metagenome=$metagenome&sequence=$seq_id'>".$row->[0]."</a>";
    my $hit_id;
    if ( ($row->[2] =~ /^fig\|/) && ($fig->translation_length($row->[2])) ) {
	$length = $fig->translation_length($row->[2]);
	$hit_id = $row->[2];
	$row->[2] = "<img src='./Html/seed-logo-icon.png'>&nbsp;<a href='http://seed-viewer.theseed.org/seedviewer.cgi?page=Annotation&feature=".$row->[2]."' target=_blank>".$row->[2]."</a>";
    }
    elsif ($self->data('dataset') =~ /Silva:ssu/) {
	my $ssu_id = $row->[2];
	$hit_id = $row->[2];
	($ssu_id) = $row->[2] =~ m/(.*?)\./;
	$ssu_id = "<a href='http://www.arb-silva.de/browser/ssu/$ssu_id' target='_blank'>".$ssu_id."</a>";
	$row->[2] = $ssu_id;
    }
    elsif ($self->data('dataset') =~ /Silva:lsu/) {
	my $lsu_id = $row->[2];
	$hit_id = $row->[2];
	($lsu_id) = $row->[2] =~ m/(.*?)\./;
	$lsu_id = "<a href='http://www.arb-silva.de/browser/lsu/$lsu_id' target='_blank'>".$lsu_id."</a>";
	$row->[2] = $lsu_id;	
    }
    else{
	if (defined $seqLengths->{$row->[2]}){
	    $length =  $seqLengths->{$row->[2]};
	}
	else{
	    $length = abs($row->[10] - $row->[9]);
	}
	$hit_id = $row->[2];
    }

    my $taxa = $self->data('mgdb')->split_taxstr($row->[3]);
    my $evalue = sprintf("%2.2e", $self->data('mgdb')->log2evalue($row->[4]));
    $row->[3] = $self->data('mgdb')->key2taxa($taxa->[scalar(@$taxa)-1]);
    if ($ec) {
      $row->[3] = $fig->function_of($hit_id);
    }
    
    push(@$row_copy, $row->[0],$row->[1],$evalue,$row->[6],$row->[5],$row->[7]." - ".$row->[8],$row->[3],$row->[2]);

    if ($kegg_img_data->{$hit_id} && $kegg_img_data->{$hit_id}->{kegg}) {
      push(@$row_copy, @{$kegg_img_data->{$hit_id}->{kegg}});
    } else {
      push(@$row_copy, "", "");
    }

    if (($self->data('dataset') =~ /SEED/) && ($cgi->param('show_align'))){
      # register components
      $self->application->register_component('GenomeDrawer', $seq_id);
      my $colors = WebColors::get_palette('gradient');
      my $sims = $self->application->component($seq_id);
      $sims->width(400);
      $sims->legend_width(75);
      $sims->window_size(150);
      $sims->line_height(19);
      $sims->show_legend(1);
      my $evalue = sprintf("%2.2e", $self->data('mgdb')->log2evalue($row->[4]));
      my ($color) = $self->get_evalue_color_key($evalue);
      
      my $multiplier = $sims->window_size / $length;

      $sims->add_line([ { start => $row->[9] * $multiplier, end => $row->[10] * $multiplier, type => 'smallbox', color => $colors->[$color],
			  title => 'Similarity',
			  description => [ { title => 'Fragment Id', value => $seq_id},
					   { title => "Start in fragment", value => $row->[7] },
					   { title => "End in fragment", value => $row->[8] },
					   { title => 'Alignment Length', value => $row->[1]}
					 ] 
			}
		      ],
		      { title => $seq_id, short_title => 'Fragment', hover_title => 'Similarity Match' });
      
      $sims->add_line([ { start => 0, end => $sims->window_size, type => 'smallbox', color => 2,
			  title => 'Hit',
			  description => [ { title => "Hit Id", value => $hit_id },
					   { title => 'Hit Length', value => $length },
					   { title => "Evalue", value => $evalue },
					   { title => "Score", value => $row->[5] },
					   { title => "Alignment length", value => $row->[1] },
					   { title => "Alignment % identity", value => $row->[6] }
					 ]
			}
		      ],
		      { title => $hit_id, short_title => 'Hit', hover_title => 'Sequence ID'});
      
      push(@$row_copy, $sims->output());
    }    
    push (@$data_copy, $row_copy);
  }

  # create table
  my $table = $self->application->component('MGTable');

  # init GenomeDrawer
  $self->application->register_component('GenomeDrawer', 'Sims_legend');  
  my $colors = WebColors::get_palette('gradient');
  my $sims_legend = $self->application->component('Sims_legend');
  $sims_legend->width(400);
  $sims_legend->legend_width(75);
  $sims_legend->window_size(150);
  $sims_legend->line_height(19);
  $sims_legend->show_legend(1);

  $self->get_evalue_legend($sims_legend);

  my $tax_or_ss_col_name;
  if ($ec) {
    $tax_or_ss_col_name = "Functional Assignment";
  } elsif (dataset_is_metabolic($self->data('dataset_desc'))){
    $tax_or_ss_col_name = "Functional Role Assignment";
  }
  else{
    $tax_or_ss_col_name = "Taxonomy Assignment";
  }

  my $columns = [{ name => 'Select' . qq~<br><input type='button' class='btn' value='All' onmouseover="hov(this,'btn btnhov')" onmouseout="hov(this,'btn')" onclick="checkAllorNone('MGTableForm','click_check','select_sequences')" id='click_check'>~, width => 25 },
		 { name => 'Sequence ID', sortable => 1, filter => 1, width => 150 },
		 { name => 'Alignment Length', sortable => 1, width => 100 }, 
		 { name => 'E-value', sortable => 1, width => 100 },
		 { name => '% Identity', sortable => 1, width => 100 },
		 { name => 'Bit Score', sortable => 1, width => 100 },
		 { name => 'Fragment (Start - End)', width => 100 },
		 { name => $tax_or_ss_col_name, width => 250, filter => 1, sortable => 1 },
		 { name => 'Best Hit ID', sortable => 1, filter => 1, width => 200 },
		 { name => 'KEGG id', filter => 1, sortable => 1, visible => 0 },
		 { name => 'KEGG function', filter => 1, sortable => 1, visible => 0 }
		 ];
  push (@$columns,  { name => 'Alignment' . $sims_legend->output, width => 400}) if (($self->data('dataset') =~ /SEED/) && ($cgi->param('show_align')));
  $table->show_export_button({strip_html => 1});
  if ( (defined $data_copy) && (scalar(@$data_copy) > 50) ){
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
    $table->show_column_select(1);
  }
  $table->columns($columns);
  $table->data($data_copy);
  
  $html .= $self->start_form('MGTableForm', { dataset => $self->data('dataset'), metagenome => $self->app->cgi->param('metagenome'), evalue => $self->app->cgi->param('evalue'), bitscore => $self->app->cgi->param('bitscore'), align_len => $self->app->cgi->param('align_len'), identity => $self->app->cgi->param('identity'), rank => $self->app->cgi->param('rank'), get => uri_escape($self->app->cgi->param('get'))}); 
  $html .= $table->output();
  $html .= $self->app->cgi->submit(-name => 'align_sequences', -value => 'Align Sequences', -onclick => 'table_submit("0", "MGTableForm", "1");');
  $html .= $self->end_form();
  $html .= "<p class='subscript'>Data generated in ".(time-$time)." seconds.</p>";
  return $html;

}

sub download_fasta {
  my ($self) = @_;

  # get parameters
  my $rank = $self->app->cgi->param('rank') || 0;
  my $taxonomy = $self->app->cgi->param('get') || '';
  my $genome = $self->app->cgi->param('genome') || '';
  my $filter_taxa = $self->data('mgdb')->split_taxstr($taxonomy);
  my $get = [];
  foreach (my $i=0; $i<=$rank; $i++) {
    push @$get, $filter_taxa->[$i];
  }

  # get the data
  my ($data);
  unless($genome){
      my $filter = $self->data('mgdb')->join_taxstr($get);
      $data = $self->data('mgdb')->get_sequence_subset($self->data('dataset'), $filter);
  } else {
      $data = $self->data('mgdb')->get_sequence_subset_genome($genome);
  }

  my @ids = map { $_->[0] } @$data;
  my $content = $self->data('mgdb')->get_sequences_fasta(\@ids);
  
  print "Content-Type:application/x-download\n";  
  print "Content-Length: " . length($content) . "\n";
  print "Content-Disposition:attachment;filename=fasta_download.faa\n\n";
  print $content;

  exit;

}

sub align_sequences {
  my ($self) = @_;
  my $content;

  my (@selected_seqs) = $self->app->cgi->param('select_sequences');
  if (scalar @selected_seqs > 0){
    my $job_id = time();
    my $temp_file = "$FIG_Config::temp/$job_id.fasta";
    my $fasta = $self->data('mgdb')->get_sequences_fasta(\@selected_seqs);
    
    open (OUT, ">$temp_file");
    print OUT $fasta;
    close OUT;
    
    $ENV{HOME_4_TCOFFEE} = "$FIG_Config::temp/";
    $ENV{DIR_4_TCOFFEE} = "$FIG_Config::temp/.t_coffee/";
    $ENV{CACHE_4_TCOFFEE} = "$FIG_Config::temp/cache/";
    $ENV{TMP_4_TCOFFEE} = "$FIG_Config::temp/tmp/";
    $ENV{METHOS_4_TCOFFEE} = "$FIG_Config::temp/methods/";
    $ENV{MCOFFEE_4_TCOFFEE} = "$FIG_Config::temp/mcoffee/";

    my @cmd = ("$FIG_Config::ext_bin/t_coffee","$temp_file", "-output", "score_html", "-outfile", "$FIG_Config::temp/$job_id.html", "-run_name", "$FIG_Config::temp/$job_id","-quiet","$FIG_Config::temp/junk.txt");

    my $command_string = join(" ",@cmd);
    open(RUN,"$command_string |");
    while($_ = <RUN>){}
    close(RUN);
    open(HTML,"$FIG_Config::temp/$job_id.html");
    while($_ = <HTML>){
      $_ =~s/<html>//;
      $_ =~s/<\/html>//;
      $content .= $_;
    }

  }
  else{
    $content .= "No sequences given as input\n";
  }

  return $content;
}

=pod

=item * B<get_evalue_ranges>()

Returns a reference to an array of evalues

=cut

sub get_evalue_ranges {
    return [ 1e-50, 1e-40, 1e-30, 1e-25, 1e-20, 1e-15, 1e-10, 1e-5, 1e-3, 0.01, 0.1 ];
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

=pod

=item * B<get_evalue_legend>()

Adds a line with the evalue key to the genome drawer

=cut

sub get_evalue_legend {
    my ($self, $gd) = @_;

    my $ranges = $self->get_evalue_ranges;
    my $window_size = $gd->window_size-2;
    my $interval = $window_size/scalar(@$ranges);
    my $data = [];
    my $colors = WebColors::get_palette('gradient');

    for (my $i=0; $i<scalar(@$ranges); $i++) {
	my ($color, $key) = $self->get_evalue_color_key($ranges->[$i]);
	push @$data,  { "title" => "Evalue Key",
                      "start" => $interval*$i,
                      "end" =>  $interval*($i+1),
                      "type"=> 'box',
                      "color"=> $colors->[$color],
			"description" => [ { title => "Evalue Range",
					     value => $key }],
                    };
    }

    $gd->add_line($data, { title => 'E-Value-Key', no_middle_line => 1});

    return $gd;
}


sub require_javascript{
    return ["$FIG_Config::cgi_url/Html/checkboxes.js"];
}
