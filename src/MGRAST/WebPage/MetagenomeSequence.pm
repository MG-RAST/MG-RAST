package MGRAST::WebPage::MetagenomeSequence;

# $Id: MetagenomeSequence.pm,v 1.4 2011-02-09 13:18:36 paczian Exp $

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use URI::Escape;

use WebComponent::WebGD;
use POSIX;

use MGRAST::MetagenomeAnalysis;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset is_public_metagenome );

1;


=pod

=head1 NAME

MetagenomeSequence - an instance of WebPage which shows all information about a metagenome fragment

=head1 DESCRIPTION

Details page for a metagenome fragement

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('SEED Viewer - Metagenome Sequence Details');

  # register components
  $self->application->register_component('GenomeDrawer', 'Sims');
  $self->application->register_component('Info', 'Info');
  $self->application->register_component('HelpLink', 'LimitHelp');

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
    $self->data('mgdb', $mgdb);
  }

  return 1;

}

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # get metagenome id
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  unless ($metagenome) {
    $self->application->add_message('warning', 'No metagenome id given.');
    return "<h2>An error has occured:</h2>\n".
      "<p><em>No metagenome id given.</em></p>";
  }

  my $html = "<span style='font-size: 1.6em'><b>Metagenome Sequence Details</b></span>";
  $html .= "<p>&raquo; <a href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome'>Back to Metagenome Overview</a></p>";

  my $job = $self->data('job');

  # do we have a sequence id?
  my $seq_id = $self->application->cgi->param('sequence') || '';

  # get begin and end for subsequence
  my $subseq_beg = $self->application->cgi->param('subseq_beg') || '';
  my $subseq_end = $self->application->cgi->param('subseq_end') || '';

  unless($seq_id) {
    $html .= "<p><em>No sequence id given.</em></p>";
    $html .= "<p>Please enter the a sequence id of metagenome ".$job->genome_name." (".$job->genome_id.") to retrieve it:</p>";
    $html .= "<div>";
    $html .= $self->start_form('lookup',{ page => 'MetagenomeSequence', metagenome => $metagenome});
    $html .= "<input type=textbox name='sequence' value=''>"; 
    $html .= $self->button('Search'); 
    $html .= $self->end_form;
    $html .= "</div>";
    return $html;
  }

  # add info box
  my $info = $self->application->component('Info');
  $info->content("<p>The sequence view page contains two parts:</p><p><strong>Sequence Information:</strong> Here you find where the selected sequence ID belongs to and some properties like GC content or sequence length, as well as it\'s full sequence.</p><p><strong>Similarity Data:</strong> We provide all details about sequence similarity against the different databases used as part of the Metagenomics RAST pipeline.</p>");

  # format sequence string
  my $seq_raw = $self->data('mgdb')->get_sequence($seq_id);
  my $seq_len = length($seq_raw);

  my($seg, @seq_lines);
  my $line_length = 80;
  my $offset = 0;

  # begin and end of subsequence to be colored (if defined)
  my($beg, $end) = sort {$a <=> $b} grep {/^\d+$/} ($subseq_beg, $subseq_end);

  my @seq_chars = split('', $seq_raw);

  if ( $beg and $end )
  {
      # color subsequence if required
      for (my $i = ($beg-1); $i <= ($end-1); $i++)
      {
	  $seq_chars[$i] = qq(<font color="#46EE72">) . $seq_chars[$i] . qq(</font>) ;
      }
  }

  while ( $offset < ($seq_len - 1) )
  {
      my $last = (sort {$a <=> $b} (($seq_len - 1), ($offset+$line_length-1)))[0];

      if ( defined($seg = join('', @seq_chars[$offset..$last])) )
      {
	  push(@seq_lines, $seg);
	  $offset += $line_length;
      }
  }

  my $seq_print = join('<br>', @seq_lines);

  # add general sequence data and info box
   $html .= "<h2>Sequence: ".$seq_id."</h2>\n";
  $html .= "<div><table><tr><td style='padding-right: 30px';>";
  $html .= "<table>";
  $html .= "<tr><th>Metagenome</th><td>".$job->genome_name." (".$job->genome_id.")</td></tr>";
  $html .= "<tr><th>Sequence Id</th><td>".$seq_id."</td></tr>";
  $html .= "<tr><th>Sequence length</th><td>".$seq_len."</td></tr>";
  $html .= "<tr><td colspan='2'><pre style='padding-top: 20px;'>$seq_print</pre></td></tr>";
  $html .= "<tr><td colspan='2'>The highlighted segment of the sequence matches the chosen function</td></tr>";
  $html .= "</table>";
  $html .= "</td><td>".$info->output."</td></tr>";
  $html .= "</table></div>\n";


  # similarity data
  my $cgi = $self->application->cgi;
  my $limit = $cgi->param('limit') || 10;
  my @datasets = ($cgi->param('dataset')) ? $cgi->param('dataset') : @{$self->data('dataset_select_all')};

  $html .= "<h2>Sequence Similarity Data</h2>\n";
  $html .= "<p>To view the similarities of this metagenome sequence, please select one or more datasets from the list below and the maximum number of matches per dataset you would like to see. Matches will be returned sorted from best to worst.</p>";


  # create tiny help hoverboxes
  my $limithelp = $self->application->component('LimitHelp');
  $limithelp->title('Please note:');
  $limithelp->disable_wiki_link(1);
  $limithelp->hover_width(300);
  $limithelp->text('The initial number of matches displayed per dataset is small (10) so that the page loads fast. If you wish to view a larger number of matches against a dataset please select only this single dataset and then increase the maximal number of matches.');
  
  # form to select datasets and limit
  $html .= $self->start_form('mg_sims', { metagenome => $metagenome, sequence => $seq_id });
  $html .= "<div><table>";
  $html .= "<tr><th>Select datasets: </th><td>";
  $html .= $cgi->scrolling_list( -name    => 'dataset',
				 -values  => $self->data('dataset_select_all'),
				 -default => \@datasets,
				 -size    => 6,
				 -multiple => 'true', );
  $html .= "</td></tr>";
  $html .= "<tr><td colspan='2'>".$self->button('Re-compute results').
    " &laquo; <a href='".$self->url."metagenome=$metagenome&sequence=$seq_id'>click here to reset</a>  &raquo;</td></tr>";
  $html .= "</table></div>\n";
  $html .= $self->end_form;

  $html .= "<p>The graphic below shows the location of the similarity matches on the selected metagenome sequence. The quality of the match (e-value) is color coded as detailed at the top. For more information about a match hover your mouse over the match indicated by the colored box.</p>";
  $html .= "<p><strong>For SEED identifiers (fig|*),</strong> clicking on the identifier on the left hand side will take you to the SEED Viewer Annotation page for that feature and clicking on the colored match will run a blastx alignment for the metagenome sequence and this SEED protein.</p>";
  $html .= "<p><strong>Note on SEED subsystem matches: </strong>if the functional role associated with a feature is in multiple subsystems you may see multiple matches against some features.</p>";

  # init GenomeDrawer
  my $colors = WebColors::get_palette('gradient');
  my $sims = $self->application->component('Sims');
  $sims->width(400);
  $sims->legend_width(150);
  $sims->window_size($seq_len+1);
  $sims->line_height(19);
  $sims->show_legend(1);

  $self->get_evalue_legend($sims);
  $sims->add_line([ { start => 0, end => $seq_len, type => 'smallbox', color => 2,
		      title => 'Your sequence', 
		      description => [{ title => 'Length', value => $seq_len }],
		    } 
		  ],
		  { title => $seq_id, short_title => 'Your sequence', hover_title => 'Sequence ID'});
  $sims->add_line([], { no_middle_line => 1 });

  # fetch matches from database
  foreach my $d (@datasets) {

    my $matches = $self->data('mgdb')->get_hits_for_sequence($seq_id, $d, $limit);

    $sims->add_line([], { title => $d, no_middle_line => 1 });    

    if (scalar(@$matches)) {
      foreach my $m (sort { $a->[2] <=> $b->[2] } @$matches) {
	my $evalue = sprintf("%2.2e", $self->data('mgdb')->log2evalue($m->[2]));
	my $taxa = $self->data('mgdb')->split_taxstr($m->[1]);
	my $desc = $self->data('mgdb')->key2taxa( $taxa->[ scalar(@$taxa)-1 ] );
	($m->[6], $m->[7]) = ($m->[7], $m->[6]) if ($m->[6] > $m->[7]);

	my ($color) = $self->get_evalue_color_key($evalue);
	my $link; 
	my $onclick;
	if ($m->[0] =~ /^fig\|/) {
	  $link = "window.top.location='metagenomics.cgi?page=Annotation&feature=".$m->[0]."';"; 
	  $onclick = "window.top.location='".
	    "metagenomics.cgi?page=ToolResult&tool=bl2seqx&peg=".$m->[0]."&seq_id=".$seq_id."&seq=".$seq_raw."';";
	}
	$sims->add_line([ { start => $m->[6], end => $m->[7], type => 'smallbox', color => $colors->[$color], 
			    title => 'Similarity', 
			    description => [ { title => "Target Id", value => $m->[0] },
					     { title => "Description", value => $desc },
					     { title => "Evalue", value => $evalue },
					     { title => "Score", value => $m->[3] },
					     { title => "Alignment length", value => $m->[4] },
					     { title => "Alignment % identity", value => $m->[5] },
					     { title => "Start in your sequence", value => $m->[6] },
					     { title => "End in your sequence", value => $m->[7] },
					   ],
			    onclick => $onclick,
			  } 
			],
			{ title => '', short_title => $m->[0], title_link => $link, hover_title => 'Similarity Match' });
      }
    }
    else {
      $sims->add_line([], { title => 'No similarities found.' , no_middle_line => 1 });
    }

    $sims->add_line([], { no_middle_line => 1 });

  }

  $html .= $sims->output();
  return $html;

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
      
    $gd->add_line($data, { title => 'E-Value-Key'});

    return $gd;
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
	$key = $ranges->[$i-1] . ' <==> ' . $key;
      }
      return ($color+$i, $key);
    }
  }
  return ($color+scalar(@$ranges), '> 10');
}
