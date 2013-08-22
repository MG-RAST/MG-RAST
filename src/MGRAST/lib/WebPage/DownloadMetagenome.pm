package MGRAST::WebPage::DownloadMetagenome;

use strict;
use warnings;
no warnings('once');

use base qw( WebPage );
use WebConfig;
use Data::Dumper;
use File::Basename;
use Number::Format;
use XML::Simple;

use Conf;
use MGRAST::Metadata;

1;


=pod

=head1 NAME

DownloadMetagenome - displays download information about a metagenome job

=head1 DESCRIPTION

Download metagenome page 

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Metagenome Downloads");

  my $cgi = $self->application->cgi();
  my $id;
  my $stages = {  50 => { name => 'Uploaded', link => "upload" } ,
		 100 => { name => 'Preprocessing', link => "preproc" } ,
		 150 => { name => 'Dereplication', link => "derep" } ,
		 299 => { name => "Screening", link => "screen" } ,
		 350 => { name => 'Gene Calling', link => "gene" } ,
		 425 => { name => 'RNA Identification', link => "search" } ,
		 440 => { name => 'RNA Clustering 97%', link => "rna_clust" } ,
		 450 => { name => 'M5 RNA Search', link => "rna_sim" } ,
		 550 => { name => 'Protein Clustering 90%', link => "aa_clust" } ,
		 650 => { name => 'M5 Protein Search', link => "aa_sim" }
	       };
  $self->data('stages', $stages);

  # get default pipeline info
  my $default = {};
  if ( -s $Conf::mgrast_formWizard_templates."/pipeline.xml" ) {
    $default = XMLin($Conf::mgrast_formWizard_templates."/pipeline.xml", forcearray => ['stage', 'output', 'column']);
    if ($default && exists($default->{stage})) {
      %$default = map { $_->{num}, $_ } @{ $default->{stage} };
    }
  }
  $self->data('default', $default);

  # api info for download
  $self->data('api', "http://api.metagenomics.anl.gov/1");

  # get to metagenome using the metagenome or job ID
  if ( $cgi->param('metagenome') ) {
    $id = $cgi->param('metagenome');
    eval { $self->{job} = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $id }); };
  }
  elsif ( $cgi->param('job') ) {
     $id = $cgi->param('job');   
     eval { $self->{job} = $self->app->data_handle('MGRAST')->Job->init({ job_id => $id }); };
  }

  if  ($id and not $self->{job} ) {
    $self->app->add_message("info" , "Unable to retrieve the metagenome '$id'.");
    # return 1;
  }

  # option to download sims
  my $sims = $cgi->param('sims') || 1;
  $self->data('get_sims', $sims);

  # init the metadata database
  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  $self->application->register_action($self, 'download_md', 'download_md');
  $self->application->register_action($self, 'download', 'download');
  $self->application->register_action($self, 'api_download', 'api_download');
  $self->application->register_component('Table', 'project_table');
  $self->application->register_component('Hover', 'download_project_info');
  $self->application->register_component('Hover', 'download_info');
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # Parameters for highslide
  my $graphicsDir = $Conf::temp_url . "/" ;
  my $jsDir       = $Conf::cgi_url . "/Html/" ;
  my $cssDir      =  $Conf::cgi_url . "/Html/" ;
  my $css         = "<link rel=\"stylesheet\" type=\"text/css\" href=\"$cssDir/highslide.css\">";
  
  my $scripts .= qq~
<script type="text/javascript">
  hs.outlineType = 'outer-glow';
  hs.graphicsDir = '../../../highslide/highslide/graphics/';
</script>
<script>
  var baseText = null; 
  function showPopup(image,w,h) {
    alert(image + w + h);
    var popUp = document.getElementById(image);

    popUp.style.top = "200px";
    popUp.style.left = "200px";
    popUp.style.width = w + "px";
    popUp.style.height = h + "px";
 
    if (baseText == null) { baseText = popUp.innerHTML; };
    popUp.innerHTML = baseText + "<div id='statusbar'><button onclick='hidePopup(" + image + ");'>Close window<button></div>";

    var sbar = document.getElementById("statusbar");
    sbar.style.marginTop = (parseInt(h)-40) + "px";
    popUp.style.visibility = "visible";
  }
  function hidePopup(image) {
    var popUp = document.getElementById(image);
    popUp.style.visibility = "hidden";
  }
</script> ~;

my $css_tmp = qq~
<style type="text/css">
 #popupcontent{
   position: absolute;
   visibility: hidden;
   overflow: hidden;
   border:1px solid #CCC;
   background-color:#F9F9F9;
   border:1px solid #333;
   padding:5px;
}
</style>
~;

  my $content = $css_tmp;
  my $job     = $self->{job};
  
  unless ($job) {
    $self->title("Data sets available");
    $content .="<p>The following data sets are available for analysis and download. Note that downloading complete analysis might take significant time.</p>";
    $content .= $self->public_project_download_table;
    return $content;
  }

  my $stats     = $job->stats();
  my $rna_clust = exists($stats->{cluster_count_processed_rna}) ? $stats->{cluster_count_processed_rna} : 0;
  my $aa_clust  = exists($stats->{cluster_count_processed_aa}) ? $stats->{cluster_count_processed_aa} : 0;

  my $project = ''; 
  if ( $job->primary_project) {
    $project = $job->primary_project;
  }
  else {
    my $pjs = $job->_master->ProjectJob->get_objects( {job => $job} );
    $project = $pjs->[0]->project if ($pjs and scalar @$pjs);
  }
  my $pid = $project ? $project->id : '';
  my $mid = $job->metagenome_id;

  ## downloads
  my $download  = "";
  my $down_info = $self->app->component('download_info');
  my $metadata  = $self->data('mddb')->get_metadata_for_table($mid, 1, 1);
  my $mfile = "mgm".$mid.".metadata.txt";
  if (open(FH, ">".$Conf::temp."/".$mfile)) {
    foreach my $line (@$metadata) {
      print FH join("\t", @$line)."\n";
    }
    close FH;
  }
  $down_info->add_tooltip('meta_down', 'Download metadata for this metagenome');
  $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='metagenomics.cgi?page=DownloadMetagenome&action=download_md&filename=$mfile'><img src='./Html/mg-download.png' style='height:15px;'/><small>metadata</small></a>";
  if ($pid && $job->public) {
    $down_info->add_tooltip('sub_down', 'Download submitted metagenome');
    $down_info->add_tooltip('derv_down', 'Download all derived data for this metagenome');
    $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"sub_down\",".$down_info->id.")' target=_blank href='ftp://".$Conf::ftp_download."/projects/$pid/$mid/raw'><img src='./Html/mg-download.png' style='height:15px;'/><small>submitted</small></a>";
    $download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' target=_blank href='ftp://".$Conf::ftp_download."/projects/$pid/$mid/processed'><img src='./Html/mg-download.png' style='height:15px;'/><small>analysis</small></a>";
  }
  
  $self->title("Metagenome Download");
  $content .= $down_info->output()."<h1 style='display:inline;'>".$job->name." ($mid)</h1>".$download;
  $content .= "<p>On this page you can download all data related to metagenome ".$job->name."</p>";
  $content .= "<p>Data are available from each step in the <a target=_blank href='http://blog.metagenomics.anl.gov/howto/quality-control'>MG-RAST pipeline</a>. Each section below corresponds to a step in the processing pipeline. Each of these sections includes a description of the input, output, and procedures implemented by the indicated step. They also include a brief description of the output format, buttons to download data processed by the step and detailed statistics (click on &ldquo;show stats&rdquo; to make collapsed tables visible).</p>";
  
  my $pipe1  = [50, 100, 150, 299, 350, 550, 650];
  my $pipe2  = [425, 440, 450];
  my $label1 = '['.join(",", map {"'".$self->data('stages')->{$_}{name}."'"} @$pipe1).",'Done']";
  my $label2 = '['.join(",", map {"'".$self->data('stages')->{$_}{name}."'"} @$pipe2).']';
  my $link1  = '['.join(",", map {"'".$self->data('stages')->{$_}{link}."'"} @$pipe1).",'done']";
  my $link2  = '['.join(",", map {"'".$self->data('stages')->{$_}{link}."'"} @$pipe2).']';
  #$content .= "<p><div id='pipeline_image'></div><img src='./Html/clear.gif' onload='draw_pipeline_image($label1,$label2,$link1,$link2,\"pipeline_image\");'></p>";

  my $stages = {};
  my $download_dir = $job->download_dir(1) || "/mcs/bio/mg-rast/jobsv3/" . $job->job_id . "/analysis";

  opendir(DIR , $download_dir) or die "Can't open directory $download_dir!\n";
  while (my $tmp = readdir DIR) {
    if ($tmp =~/^(\d+)\.(\w+)\..*/) {
      my ($id, $name) = ($1, $2);
      # skip loadDB files
      if ( ($id == 900) && ($name ne 'abundance') ) { next; }
      # skip protein files if 'Amplicon'
      if ( ($job->sequence_type =~ /amplicon/i) && (($id == 150) || ($id == 299) || ($id == 350) || ($id == 550) || ($id == 650)) ) { next; }
      # skip clustering if not ran
      if ( ($id == 440) && ($rna_clust == 0) ) { next; }
      if ( ($id == 550) && ($aa_clust == 0) ) { next; }
      # populate data
      if ( $self->data('stages')->{$id} and ref $self->data('stages')->{$id} ) {
	$stages->{$id}->{name}   = $self->data('stages')->{$id}->{name};
	$stages->{$id}->{link}   = $self->data('stages')->{$id}->{link};
	$stages->{$id}->{stage}  = $name;
	$stages->{$id}->{prefix} = "$id.$name";
      }
      if ( exists $self->data('default')->{$id} ) {
	$stages->{$id}->{info} = $self->data('default')->{$id};
      }
    }
  }
  # raw data somewhere else
  my $rawid = 50;
  $stages->{$rawid} = $self->data('stages')->{$rawid};
  $stages->{$rawid}->{prefix} = $job->job_id;
  if ( exists $self->data('default')->{$rawid} ) {
    $stages->{$rawid}->{info} = $self->data('default')->{$rawid};
  }
  
  # prep output for every stage
  foreach my $stage (sort {$a <=> $b} keys %$stages) {
    my $dir = ($stage == 50) ? $job->download_dir() : $job->download_dir($stage);
    $content .= $self->stage_download_info($stage, $stages, $dir);
  }
  $content .= $self->api_download_builder($mid);
  return $content;
}

sub read_stats {
  my ($self, $fname, $type, $gz, $is_fastq) = @_;

  my $stats  = [];
  my $option = '';
  my $stats_file  = $fname . ".stats";
  my $source_file = $gz ? $fname . ".gz" : $fname;
  
  if ($type =~ /^protein$/i) { $option .= " -f"; }
  if ($is_fastq)             { $option .= " -t fastq"; }
  
  if (! -s $source_file) {
    return $stats;
  }
  if ((! -s $stats_file) && ($type =~ /^(protein|dna)$/i)) {
    if ($gz) { system("gunzip $source_file"); }
    system("$Conf::seq_length_stats -i $fname -o $stats_file $option");
    if ($gz) { system("gzip $fname"); }
  }
  
  if (open(FH, $stats_file)) {
    while (my $line = <FH>) {
      chomp $line;
      my ($key, $value) = split("\t", $line);
      push @$stats, [ $key, $value ];
    }
    close FH;
  }

  return $stats;
}

sub stats_table {
  my ($self, $stats, $id) = @_;

  unless (ref($stats) && (@$stats > 0)) { return ""; }

  my $html = qq(<a style='cursor: pointer;' onclick='
if (this.innerHTML == "show stats") {
  this.innerHTML = "hide stats";
  document.getElementById("stats_table_$id").style.display = "";
} else {
  document.getElementById("stats_table_$id").style.display = "none";
  this.innerHTML = "show stats";
}'>show stats</a>
<div id='stats_table_$id' style='display:none'>
<table>);

  foreach my $set (@$stats) {
    my ($key, $val) = @$set;
    $key   =~ s/_/ /g;
    $val   = format_number($val);
    $html .= "<tr><th>$key</th><td>$val</td></tr>\n";
  }

  return $html . "</table></div>";
}

sub stage_download_info {
  my ($self, $sid, $stages, $dir) = @_;
  
  my $name   = $stages->{$sid}->{name};
  my $link   = $stages->{$sid}->{link};
  my $prefix = $stages->{$sid}->{prefix};
  my @fs     = glob "$dir/$prefix.*";

  if ( $sid == 0 ) {
      push @fs, glob "$dir/*info";
  }

  my $content = "<a name='$link'><h3>$name</h3></a>\n";

  my $file_table = "<table>";
  my $info_text  = '';
  my $has_file   = 0;
  my $file_count = 0;
  
  foreach my $f (@fs) {
    my $gz     = 0;
    my $type   = "";
    my $stats  = [];
    my $count  = '';
    my @fstats = stat $f;

    if ($f =~ /^(\S+)\.gz$/) {
      $gz = 1;
      $f  = $1;
    }
    my ($fname, $path, $suffix) = fileparse($f, qr/\.[^.]*/);
    my $desc = $fname;
    $desc =~ s/^$prefix\.?//;
    $desc = $desc || 'file';

    unless ($fstats[7] > 0) { next; }

    if ($suffix eq '.info') {
      if (exists $stages->{$sid}->{info}) {
	    $info_text = parse_default_info($stages->{$sid}->{info});
      } else {
	    my $info = `cat $f | grep -v "#"`;
	    $info = ~s/\n/<br>\n/g;
	    $info_text = $info;
      }
      next;
    }
    elsif (($suffix eq '.fna') || ($suffix eq '.fastq')) {
      my $is_fastq = ($suffix eq '.fastq') ? 1 : 0;
      $type   = "DNA";
      $stats  = $self->read_stats($f, $type, $gz, $is_fastq);
      $count  = (@$stats > 0) ? format_number($stats->[1][1]) . " reads" : '';
      if ($desc eq 'file') {
	    if    ($suffix eq '.fna')   { $desc = "fasta file"; }
	    elsif ($suffix eq '.fastq') { $desc = "fastq file"; }
      }
    }
    elsif ($suffix eq '.faa') {
      $type   = "Protein";
      $stats  = $self->read_stats($f, $type, $gz, 0);
      $count  = (@$stats > 0) ? format_number($stats->[1][1]) . " reads" : '';
    }
    elsif ($suffix eq '.mapping') {
      $type  = "Cluster";
      $stats = $self->read_stats($f, $type);
      $desc .= " mapping";
    }
    elsif ($self->data('get_sims') && ($suffix eq '.sims')) {
      $type = "Sims";
      $desc = "similarity";
    }
    else {
      next;
    }

    $has_file    = 1;
    $file_count += 1;
    $file_table .= join "\n", ("<tr><form name='stage$sid' id='stage$sid'>",
			       "<td>$desc".($count ? "<br>($count)" : '')."<br>".sprintf("%.2f", ($fstats[7] / (1024 * 1024)))."MB</td>",
			       "<td>&nbsp;&nbsp;&nbsp;&nbsp;",
			       "<input type='hidden' name='stage' value='$sid'>",
			       "<input type='hidden' name='metagenome' value='".$self->{job}->metagenome_id."'>",
			       "<input type='hidden' name='page' value='DownloadMetagenome'>",
			       "<input type='hidden' name='action' value='download'>",
			       "<input type='hidden' name='file' value='$fname$suffix".($gz ? ".gz" : "")."'>",
			       "</td>",
			       "<td><input type='submit' value='$type'></td>",
			       "</form></tr>",
			       "<tr><td colspan='3'>" . ((@$stats > 0) ? $self->stats_table($stats, $sid."_".$file_count) : "") . "</td></tr>"
			      );
  }

  if ((! $info_text) && exists($stages->{$sid}->{info})) {
    $info_text = parse_default_info($stages->{$sid}->{info});
  }
  $file_table .= "</table>";
  $content    .= "<table width='100%'><tr><td align='left'>$info_text</td><td width='30%'>$file_table</td></tr></table>";
  return $has_file ? $content : "";
}

sub download_md {
  my ($self) = @_;

  my $cgi  = $self->application->cgi;
  my $file = $cgi->param('filename');
  
  if (open(FH, "<".$Conf::temp."/".$file)) {
    my $content = do { local $/; <FH> };
    close FH;
    print "Content-Type:text/plain\n";  
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=".$file."\n\n";
    print $content;
    exit;
  } else {
    $self->application->add_message('warning', "Could not open download file");
  }
  return 1;
}

sub download {
  my ($self) = @_;

  my $cgi  = $self->application->cgi;
  my $job  = $self->{job};
  my $file = $cgi->param('file');
  my $sid  = $cgi->param('stage');
  my $stats= $job->stats();

  my $dir  = ($sid == 50) ? $job->download_dir() : $job->download_dir($sid);
  my $file_path = $dir.$file;
  my $number_of_bytes = (stat ($file_path))[7];

  if (open(FH, $file_path)) {
    binmode FH;

    print "Content-Type:application/x-download\n";  
    print "Content-Length:$number_of_bytes\n";
    print "Content-Disposition:attachment;filename=" . $job->metagenome_id . "." . $cgi->param('file') . "\n\n";

    my $data;
    while ((read FH, $data, 1024) != 0) {
      print "$data";
    }
    close FH;

    exit;
  } else {
    $self->application->add_message('warning', "Could not open download file " . $job->download_dir($sid) . "/$file");
  }
  return 1;
}

sub format_number {
  my ($val) = @_;
  while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  return $val;
}

sub parse_default_info {
  my ($info) = @_;

  my $html = '';
  $html .= exists($info->{input}) ? "<p>".$info->{input}."</p>" : "";
  if (exists $info->{description}) {
      $info->{description} =~ s/&lt;/</g;
      $info->{description} =~ s/&gt;/>/g;
      $html .= "<p>".$info->{description}."</p>"
  }
  if (exists $info->{output}) {
    foreach my $out ( @{$info->{output}} ) {
      unless (exists $out->{file}) { next; }
      $html .= "<p>".$out->{file};
      if (exists $out->{column}) {
	$html .= "<br>Column fields are as follows:<ol>";
	map { $html .= "<li>$_</li>" } @{$out->{column}};
	$html .= "</ol>";
      }
      $html .= "</p>";
    }
  }

  return $html;
}

sub api_download_builder {
    my ($self, $mid) = @_;
    
    my $doc = $self->data('api')."/api.html";
    my $sim = $self->data('api')."/annotation/similarity/mgm".$mid;
    my $default = "type=organism&source=RefSeq";
    
    my $html = qq(
    <h3>Annotation Download via API</h3>
    <table width='100%'><tr><td align='left'>
      <p>Annotated reads are available through the <a href='$doc' target='_blank'>MG-RAST API</a>.<br>
         They are built dynamicly based on the chosen annotation type and source.<br>
         Column fields are as follows:<ol>
           <li>Query / read id, e.g. mgm4441681.3|12342588</li>
           <li>Hit id / md5, e.g. afcfe216e7d39b7c789d6760194b6deb</li>
           <li>percentage identity, e.g. 100.00</li>
           <li>alignment length, e.g. 107</li>
           <li>number of mismatches, e.g. 0</li>
           <li>number of gap openings, e.g. 0</li>
           <li>q.start, e.g. 1</li>
           <li>q.end, e.g. 107</li>
           <li>s.start, e.g. 1262</li>
           <li>s.end, e.g. 1156</li>
           <li>e-value, e.g. 1.7e-54</li>
           <li>score in bits, e.g. 210.0</li>
           <li>semicolon seperated list of annotation text(s) for the given type and source</li>
         </ol></p>
      <table>
        <tr><td>Annotation Type</td><td>&nbsp;&nbsp;&nbsp;&nbsp;</td><td>Data Source</td><td></td><td></td></tr>
        <tr>
          <td>
            <select id='ann_type' onchange='
                var asrc = undefined;
                var sel_type = this.options[this.selectedIndex].value;
                if (sel_type == "ontology") {
                  document.getElementById("ont_source").style.display="";
                  document.getElementById("org_source").style.display="none";
                  asrc = document.getElementById("ont_source");
                } else {
                  document.getElementById("org_source").style.display="";
                  document.getElementById("ont_source").style.display="none";
                  asrc = document.getElementById("org_source");
                }
                var params = "type="+sel_type+"&source="+asrc.options[asrc.selectedIndex].value;
                document.getElementById("api_url").innerHTML = "$sim?"+params;
                document.getElementById("api_link").href = "metagenomics.cgi?page=DownloadMetagenome&action=api_download&mid=$mid&"+params;'>
              <option>organism</option>
              <option>function</option>
              <option>ontology</option>
              <option>feature</option>
            </select></td>
          <td>&nbsp;&nbsp;&nbsp;&nbsp;</td>
          <td>
            <select id='org_source' onchange='
                var atype = document.getElementById("ann_type");
                var params = "type="+atype.options[atype.selectedIndex].value+"&source="+this.options[this.selectedIndex].value;
                document.getElementById("api_url").innerHTML = "$sim?"+params;
                document.getElementById("api_link").href = "metagenomics.cgi?page=DownloadMetagenome&action=api_download&mid=$mid&"+params;'>
              <option>RefSeq</option>
              <option>GenBank</option>
              <option>IMG</option>
              <option>SEED</option>
              <option>TrEMBL</option>
              <option>SwissProt</option>
              <option>PATRIC</option>
              <option>KEGG</option>
              <option>RDP</option>
              <option>Greengenes</option>
              <option>LSU</option>
              <option>SSU</option>
            </select>
            <select id='ont_source' style='display:none;' onchange='
                var atype = document.getElementById("ann_type");
                var params = "type="+atype.options[atype.selectedIndex].value+"&source="+this.options[this.selectedIndex].value;
                document.getElementById("api_url").innerHTML = "$sim?"+params;
                document.getElementById("api_link").href = "metagenomics.cgi?page=DownloadMetagenome&action=api_download&mid=$mid&"+params;'>
              <option>Subsystems</option>
              <option>NOG</option>
              <option>COG</option>
              <option>KO</option>
            </select></td>
          <td>&nbsp;&nbsp;&nbsp;&nbsp;</td>
          <td><a id='api_link' href='metagenomics.cgi?page=DownloadMetagenome&action=api_download&mid=$mid&$default'><b>Download</b></a></td>
        </tr>
      </table>);
      #<p><b>URL:</b>&nbsp;&nbsp;<code id='api_url'>$sim?$default</code></p>
    $html .= "</td></tr></table><br><br>";
    
    return $html;
}

sub api_download {
    my ($self) = @_;
    
    use LWP::UserAgent;
    my $agent = LWP::UserAgent->new;
    my $mid  = $self->application->cgi->param('mid');
    my $type = $self->application->cgi->param('type');
    my $src  = $self->application->cgi->param('source');
    my $url  = $self->data('api')."/annotation/similarity/mgm".$mid."?type=".$type."&source=".$src;

    my $content = undef;
    print "Content-Type:application/x-download\n";
    print "Content-Disposition:attachment;filename=mgm".$mid."_".$type."_".$src.".tab\n\n";
    eval {
        my $get  = $agent->get($url, ':read_size_hint' => 1024, ':content_cb' => sub{my ($chunk) = @_; print $chunk;});
        $content = $get->content;
    };
    if ($@) {
        $self->application->add_message('warning', "Could not download data: ".$@);
    } elsif (ref($content) && exists($content->{ERROR}) && $content->{ERROR}) {
        $self->application->add_message('warning', "Could not download data: ".$content->{ERROR});
    }
    else {
        exit;
    }
    return 1;
}

sub public_project_download_table {
  my ($self) = @_ ;
  my $application = $self->application;
  my $user = $application->session->user;

  my $jobdbm = $application->data_handle('MGRAST');
  my $public_projects = $jobdbm->Project->get_objects( { public => 1 } );
  my $projects = [] ;# ($user) ? $user->has_right_to(undef, 'view', 'project') : [];
  my $content  = "" ; # "Public projects and metagenomes." ;
  
  if ( scalar(@$projects) || scalar(@$public_projects) ) {
    my $down_info = $application->component('download_project_info');
    $down_info->add_tooltip('all_down', 'download all submitted and derived metagenome data for this project');
    $down_info->add_tooltip('meta_down', 'download project metadata');

    my $table = $application->component('project_table');
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_column_select(1);
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->show_clear_filter_button(1);
    $table->width(800);
    $table->columns( [ { name => 'Project&nbsp;ID', visible => 0, show_control => 0, filter =>1 },
		       { name => 'Metagenome&nbsp;ID', visible => 0, show_control => 1, filter =>1, unaddable => 1 },
		       { name => 'Project', filter => 1, sortable => 1 },
		       { name => 'Contact', filter => 1, sortable => 1 },
		       { name => 'Enviroment', filter => 1, sortable => 1 },
		       { name => 'Country', filter => 1, sortable => 1, visible => 0 },
		       { name => 'PubMed ID', filter => 1, sortable => 1, visible => 0 },
		       { name => 'Sequence&nbsp;type', filter => 1, sortable => 1, operator => 'combobox' },
		       { name => '#&nbsp;Metagenomes', filter => 1, operators => [ 'equal' , 'less' , 'more' ], sortable =>  1 },
		       { name => 'Project&nbsp;size (Mbp)', filter => 1, operators => [ 'equal' , 'less' , 'more' ], sortable => 1},
		       { name =>'Download' }
		     ] );
    my $data  = [];
    my $shown = {};
    $projects = $jobdbm->Project->get_objects_for_ids($projects);
    push @$projects, @$public_projects;
    foreach my $project (sort {$a->id <=> $b->id } @$projects) {
      my $id = $project->id;
      next if $shown->{$id};
      next unless ($id && $project->name);

      $shown->{$id}  = 1;
      my $formater   = new Number::Format(-thousands_sep => ',');
      my $all_mgids  = $project->all_metagenome_ids;
      my $pubmed_ids = join(",", sort @{$project->pubmed});
      my $download   = "<table><tr align='center'>
<td><a  onmouseover='hover(event,\"all_down\",".$down_info->id.")' target=_blank href='ftp://".$Conf::ftp_download."/projects/$id'><img src='$Conf::cgi_url/Html/mg-download.png' height='15'/><small>metagenomes</small></a></td>
<td><a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://".$Conf::ftp_download."/projects/$id/metadata.project-$id.xlsx'><img src='$Conf::cgi_url/Html/mg-download.png' height='15'/><small>metadata</small></a></td>
</tr></table>";

      push @$data, [ $id,
		     join(" " , @$all_mgids) || '',
		     "<a href='?page=MetagenomeProject&project=$id' title='View project'>".$project->name."</a>",
		     $project->pi,
		     join(" <br>", sort @{$project->enviroments}) || '',
		     join(" <br>", sort @{$project->countries}) || '',
		     $pubmed_ids ? "<a href='http://www.ncbi.nlm.nih.gov/pubmed/$pubmed_ids' target=_blank >$pubmed_ids</a>" : '',
		     join(", ", sort @{$project->sequence_types}) || 'Unknown',
		     scalar(@$all_mgids),
		     $formater->format_number(($project->bp_count_raw / 1000000), 0),
		     $download
		   ];
    }
    $table->data($data);
    $content .= $down_info->output;
    $content .= $table->output();
  }
  return $content;
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/pipeline.js" ];
}
