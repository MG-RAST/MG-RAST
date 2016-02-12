package MGRAST::WebPage::DownloadMetagenome;

use strict;
use warnings;
no warnings('once');

use base qw( WebPage );
use WebConfig;

use MIME::Base64;
use Data::Dumper;
use File::Basename;
use Number::Format;
use XML::Simple;
use LWP::UserAgent;
use JSON;

use Conf;
use Auth;
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
  my $stages = {
      '050' => { name => 'Uploaded', link => "upload" },
      '100' => { name => 'Preprocessing', link => "preproc" },
      '150' => { name => 'Dereplication', link => "derep" },
      '299' => { name => "Screening", link => "screen" },
      '350' => { name => 'Gene Calling', link => "gene" },
      '425' => { name => 'RNA Identification', link => "search" },
      '440' => { name => 'RNA Clustering 97%', link => "rna_clust" },
      '450' => { name => 'M5 RNA Search', link => "rna_sim" },
      '550' => { name => 'Protein Clustering 90%', link => "aa_clust" },
      '650' => { name => 'M5 Protein Search', link => "aa_sim" }
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
  $self->data('api', $Conf::api_url || "http://api.metagenomics.anl.gov");

  # get to metagenome using the metagenome ID
  if ( $cgi->param('metagenome') ) {
    my $id = $cgi->param('metagenome');
    my $mgrast = $self->application->data_handle('MGRAST');
    my $jobs_array = $mgrast->Job->get_objects( { metagenome_id => $id } );
    unless (@$jobs_array > 0) {
      $self->app->add_message('warning', "Unable to retrieve the metagenome '$id'. This metagenome does not exist.");
      return 1;
    }
    my $job = $jobs_array->[0];
    my $user = $self->application->session->user;

    if (! $job->public) {
      if (! $user) {
        $self->app->add_message('warning', 'Please log into MG-RAST to view private metagenomes.');
        return 1;
      } elsif(! $user->has_right(undef, 'view', 'metagenome', $id)) {
        $self->app->add_message('warning', "You have no access to the metagenome '$id'.  If someone is sharing this data with you please contact them with inquiries.  However, if you believe you have reached this message in error please contact the <a href='mailto:mg-rast\@mcs.anl.gov'>MG-RAST mailing list</a>.");
        return 1;
      }
    }
    $self->{job} = $job;
  }

  # init the metadata database
  my $mddb = MGRAST::Metadata->new();
  $self->data('mddb', $mddb);

  $self->application->register_action($self, 'download_md', 'download_md');
  $self->application->register_action($self, 'download', 'download');
  $self->application->register_action($self, 'api_download', 'api_download');
  $self->application->register_component('Table', 'project_table');
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
  my $job  = $self->{job};
  my $user = $self->application->session->user;
  
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
  
  $self->title("Metagenome Download");
  $content .= $down_info->output()."<h1 style='display:inline;'>".$job->name." ($mid)</h1>".$download;
  $content .= "<p>On this page you can download all data related to metagenome ".$job->name."</p>";
  $content .= "<p>Data are available from each step in the <a target=_blank href='http://blog.metagenomics.anl.gov/howto/quality-control'>MG-RAST pipeline</a>. Each section below corresponds to a step in the processing pipeline. Each of these sections includes a description of the input, output, and procedures implemented by the indicated step. They also include a brief description of the output format, buttons to download data processed by the step and detailed statistics (click on &ldquo;show stats&rdquo; to make collapsed tables visible).</p>";
  
  # get download info from API
  my $response = undef;
  my $agent = LWP::UserAgent->new;
  my $auth  = ($user && (! $job->public)) ? $Conf::api_key : '';
  my $url   = $self->data('api')."/download/mgm".$mid;
  my $json  = JSON->new;
  $json = $json->utf8();
  $json->max_size(0);
  $json->allow_nonref;
  
  eval {
      my $get = $auth ? $agent->get($url, 'auth' => $auth) : $agent->get($url);
      $response = $json->decode( $get->content );
  };
  if ($@ || (! ref($response))) {
      $self->application->add_message('warning', "Could not retrieve file list: ".$@);
      return 1;
  } elsif (exists($response->{ERROR}) && $response->{ERROR}) {
      $self->application->add_message('warning', "Could not retrieve file list: ". $response->{ERROR});
      return 1;
  }
  
  # group by ID
  my $stages = {};
  foreach my $set (@{$response->{data}}) {
      push @{ $stages->{$set->{stage_id}} }, $set;
  }
  
  # prep output for every stage
  foreach my $stage (sort {$a <=> $b} keys %$stages) {
    $content .= $self->stage_download_info($stage, $stages->{$stage});
  }
  
  # add dynamic downloader
  $content .= $self->api_download_builder($mid);
  return $content;
}

sub stats_table {
  my ($self, $stats, $id) = @_;

  unless (ref($stats) && %$stats) { return ""; }

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

  foreach my $key (sort keys %$stats) {
    my $val = format_number($stats->{$key});
    $key  =~ s/_/ /g;
    $html .= "<tr><th>$key</th><td>$val</td></tr>\n";
  }

  return $html."</table></div>";
}

sub stage_download_info {
  my ($self, $sid, $stages) = @_;
  
  unless (exists $self->data('stages')->{$sid}) {
      return "";
  }
  
  my $name = $self->data('stages')->{$sid}->{name};
  my $link = $self->data('stages')->{$sid}->{link};
  my $content = "<a name='$link'><h3>$name</h3></a>\n";

  my $file_table = "<table>";
  my $info_text  = exists($self->data('default')->{$sid}) ? parse_default_info($self->data('default')->{$sid}) : '';
  my $has_file   = 0;
  my $file_count = 0;
  
  foreach my $info (@$stages) {
    unless (exists($info->{file_size}) && $info->{file_size}) {
        next;
    }
      
    my $stats = exists($info->{statistics}) ? $info->{statistics} : {};
    my $count = exists($stats->{sequence_count}) ? format_number($stats->{sequence_count})." reads" : '';
    my $size  = exists($info->{file_size}) ? sprintf("%.2f", ($info->{file_size} / (1024 * 1024)))."MB" : '';
    my $desc  = ($info->{data_type} eq 'sequence') ? $info->{file_format} : $info->{data_type};
    
    my $type = 'File';
    if (exists($info->{seq_format}) && ($info->{seq_format} eq 'bp')) {
        $type = 'DNA';
    }
    if (exists($info->{seq_format}) && ($info->{seq_format} eq 'aa')) {
        $type = 'Protein'
    }
    if ($info->{data_type} eq 'cluster') {
        $desc = 'mapping';
        $type = 'Cluster';
    }
    if ($desc eq 'similarity') {
        $type = 'Sims';
    }
    if (exists $info->{cluster_percent}) {
        $desc = (($info->{seq_format} eq 'aa') ? 'aa' : 'rna').$info->{cluster_percent}." ".$desc;
    }
    
    $has_file    = 1;
    $file_count += 1;
    $file_table .= join "\n", ("<tr><form name='stage$sid' id='stage$sid'>",
			       "<td>$desc".($count ? "<br>($count)" : '').($size ? "<br>$size" : '')."</td>",
			       "<td>&nbsp;&nbsp;&nbsp;&nbsp;",
			       "<input type='hidden' name='page' value='DownloadMetagenome'>",
			       "<input type='hidden' name='action' value='download'>",
			       "<input type='hidden' name='node' value='".$info->{node_id}."'>",
			       "<input type='hidden' name='name' value='".$info->{file_name}."'>",
			       "<input type='hidden' name='size' value='".$info->{file_size}."'>",
			       "</td>",
			       "<td><input type='submit' value='$type'></td>",
			       "</form></tr>",
			       "<tr><td colspan='3'>" . (%$stats ? $self->stats_table($stats, $sid."_".$file_count) : "") . "</td></tr>"
			      );
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
  my $node = $cgi->param('node');
  my $name = $cgi->param('name');
  my $size = $cgi->param('size');
  
  # get mgrast token
  #my $mgrast_token = undef;
  #if ($Conf::mgrast_oauth_name && $Conf::mgrast_oauth_pswd) {
  #    my $key = encode_base64($Conf::mgrast_oauth_name.':'.$Conf::mgrast_oauth_pswd);
  #    my $rep = Auth::globus_token($key);
  #    $mgrast_token = $rep ? $rep->{access_token} : undef;
  #}
  #### changed because globus has hard time handeling multiple tokens
  my $mgrast_token = "mgrast ".$Conf::mgrast_oauth_token || undef;
  
  my $response = undef;
  my $agent = LWP::UserAgent->new;
  # print headers
  print "Content-Type:application/x-download\n";
  print "Access-Control-Allow-Origin: *\n";
  if ($size) {
      print "Content-Length: ".$size."\n";
  }
  print "Content-Disposition:attachment;filename=".$name."\n\n";
  eval {
      my $url = $Conf::shock_url.'/node/'.$node.'?download_raw';
      my @args = (
          $mgrast_token ? ('Authorization', $mgrast_token) : (),
          ':read_size_hint', 8192,
          ':content_cb', sub{ my ($chunk) = @_; print $chunk; }
      );
      # print content
      $response = $agent->get($url, @args);
  };
  if ($@ || (! $response)) {
      $self->application->add_message('warning', "Unable to retrieve file from Shock server");
      return 1
  }
  exit 0;
}

sub format_number {
  my ($val) = @_;
  unless ($val =~ /\./) {
    while ($val =~ s/(\d+)(\d{3})+/$1,$2/) {}
  }
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
                var sel_type = this.options[this.selectedIndex].value;
                if (sel_type == "ontology") {
                  document.getElementById("ont_source").style.display="";
                  document.getElementById("org_source").style.display="none";
                } else {
                  document.getElementById("org_source").style.display="";
                  document.getElementById("ont_source").style.display="none";
                }'>
              <option>organism</option>
              <option>function</option>
              <option>ontology</option>
              <option>feature</option>
            </select></td>
          <td>&nbsp;&nbsp;&nbsp;&nbsp;</td>
          <td>
            <select id='org_source'>
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
            <select id='ont_source' style='display:none;'>
              <option>Subsystems</option>
              <option>NOG</option>
              <option>COG</option>
              <option>KO</option>
            </select></td>
          <td>&nbsp;&nbsp;&nbsp;&nbsp;</td>
          <td><a id='api_link' href='#' onclick='
            var asrc = undefined;
            var atype = document.getElementById("ann_type");
            var sel_type = atype.options[atype.selectedIndex].value;
            if (sel_type == "ontology") {
              asrc = document.getElementById("ont_source");
            } else {
              asrc = document.getElementById("org_source");
            }
            var params = "mid=$mid&type="+sel_type+"&source="+asrc.options[asrc.selectedIndex].value;
            var url = "metagenomics.cgi?page=DownloadMetagenome&action=api_download&"+params;
            if (document.getElementById("login_input_box") == null) {
                var wsCookie = getCookie("WebSession");
                if (wsCookie) {
                    url += "&auth=" + wsCookie;
                }
            }
            this.href = url;'><b>Download</b>
          </a></td>
        </tr>
      </table>
    </td></tr></table><br><br>);
    
    return $html;
}

sub api_download {
    my ($self) = @_;
    
    my $agent = LWP::UserAgent->new;
    my $mid  = $self->application->cgi->param('mid');
    my $auth = $self->application->cgi->param('auth') || undef;
    my $type = $self->application->cgi->param('type');
    my $src  = $self->application->cgi->param('source');
    my $url  = $self->data('api')."/annotation/similarity/mgm".$mid."?type=".$type."&source=".$src;

    my $content = undef;
    print "Content-Type:application/x-download\n";
    print "Content-Disposition:attachment;filename=mgm".$mid."_".$type."_".$src.".tab\n\n";
    eval {
        my $get = undef;
        if ($auth) {
            $get = $agent->get($url, 'auth' => $auth, ':read_size_hint' => 1024, ':content_cb' => sub{my ($chunk) = @_; print $chunk;});
        } else {
            $get = $agent->get($url, ':read_size_hint' => 1024, ':content_cb' => sub{my ($chunk) = @_; print $chunk;});
        }
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
		       { name => 'Project&nbsp;size (Mbp)', filter => 1, operators => [ 'equal' , 'less' , 'more' ], sortable => 1}
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

      push @$data, [ $id,
		     join(" " , @$all_mgids) || '',
		     "<a href='?page=MetagenomeProject&project=$id' title='View project'>".$project->name."</a>",
		     $project->pi,
		     join(" <br>", sort @{$project->enviroments}) || '',
		     join(" <br>", sort @{$project->countries}) || '',
		     $pubmed_ids ? "<a href='http://www.ncbi.nlm.nih.gov/pubmed/$pubmed_ids' target=_blank >$pubmed_ids</a>" : '',
		     join(", ", sort @{$project->sequence_types}) || 'Unknown',
		     scalar(@$all_mgids),
		     $formater->format_number(($project->bp_count_raw / 1000000), 0)
		   ];
    }
    $table->data($data);
    $content .= $table->output();
  }
  return $content;
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/pipeline.js", "$Conf::cgi_url/Html/MetagenomeSearch.js" ];
}
