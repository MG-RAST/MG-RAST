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
  my $stages = { 100 => { name => "Preprocessing"} ,
		 150 => { name => "Dereplication"} ,
		 299 => { name => "Screening"} ,
		 350 => { name => 'Prediction of protein coding sequences'} ,
		 440 => { name => 'RNA Clustering'} ,
		 450 => { name => 'RNA similarities'} ,
		 550 => { name => 'Gene Clustering'} ,
		 650 => { name => 'Protein similarities'} ,
		 900 => { name => 'Abundance profiles'}
	       };
  $self->data('stages', $stages);

  # get default pipeline info
  my $default = {};
  if ( -s $FIG_Config::mgrast_formWizard_templates."/pipeline.xml" ) {
    $default = XMLin($FIG_Config::mgrast_formWizard_templates."/pipeline.xml", forcearray => ['stage', 'output', 'column']);
    if ($default && exists($default->{stage})) {
      %$default = map { $_->{num}, $_ } @{ $default->{stage} };
    }
  }
  $self->data('default', $default);

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

  $self->application->register_action($self, 'download', 'download');
  $self->application->register_component('Table', 'project_table');
  $self->application->register_component('Hover', 'download_project_info');

}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  # Parameters for highslide
  my $graphicsDir = $FIG_Config::temp_url . "/" ;
  my $jsDir       = $FIG_Config::cgi_url . "/Html/" ;
  my $cssDir      =  $FIG_Config::cgi_url . "/Html/" ;
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
  if( $job->project){
    $project = $job->project->id;
  }
  else{
    my $pjs = $job->_master->ProjectJob->get_objects( {  job => $job }) ;
    $project = $pjs->[0]->project if ($pjs and scalar @$pjs) ;
  }
  my $pid = $project ? $project->id : '' ;
  my $mid = $job->metagenome_id;
  
  my $download = '';
  if ($pid) {
    $download = qq~
<a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$pid/$mid.raw.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a>
<a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$pid/$mid/metadata.xml'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a>
<a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$pid/$mid.processed.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a>~;
  }
  
  $self->title("Metagenome Download");
  $content .= "<h2 style='display:inline'>".$job->name." ($mid)"."</h2>".$download;
  $content .= "<p>On this page you can download all data related to metagenome ".$job->name."</p>";
  $content .= "<p>Data are available from each step in the <a target=_blank hrep='http://blog.metagenomics.anl.gov/howto/quality-control'>MG-RAST pipeline</a>. Each section below corresponds to a step in the processing pipeline. Each of these sections includes a description of the input, output, and procedures implemented by the indicated step. They also include a brief description of the output format, buttons to download data processed by the step and detailed statistics (click on &ldquo;show stats&rdquo; to make collapsed tables visible).</p>";

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
	$stages->{$id}->{stage}  = $name;
	$stages->{$id}->{prefix} = "$id.$name";
      }
      if ( exists $self->data('default')->{$id} ) {
	$stages->{$id}->{info} = $self->data('default')->{$id};
      }
    }
  }
  #raw data somewhere else
  $stages->{'0'}->{name}   = 'Uploaded file(s)';
  $stages->{'0'}->{prefix} = $job->job_id;
  
  # prep output for every stage
  foreach my $stage (sort {$a <=> $b} keys %$stages) {
    $content .= $self->stage_download_info($stage, $stages, $job->download_dir($stage));
  }    
  return $content;
}

sub read_stats {
  my ($self, $fname, $type, $gz) = @_;

  my $stats       = [];
  my $stats_file  = $fname . ".stats";
  my $source_file = $gz ? $fname . ".gz" : $fname;
  my $option      = ($type =~ /^protein$/i) ? "--length_only" : "";
  
  if (! -s $source_file) {
    return $stats;
  }
  if ((! -s $stats_file) && ($type =~ /^(protein|dna)$/i)) {
    if ($gz) { system("gunzip $source_file"); }
    system("$FIG_Config::seq_length_stats --fasta_file $fname --stat_file $stats_file $option");
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
  my $prefix = $stages->{$sid}->{prefix};
  my @fs     = glob "$dir/$prefix.*";

  if ( $sid == 0 ) {
      push @fs, glob "$dir/*info";
  }

  my $content = "<h3>$name</h3>\n";

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
      $type   = "DNA";
      $stats  = $self->read_stats($f, $type, $gz);
      $count  = (@$stats > 0) ? format_number($stats->[1][1]) . " reads" : '';
      if ($desc eq 'file') {
	if    ($suffix eq '.fna')   { $desc = "fasta file"; }
	elsif ($suffix eq '.fastq') { $desc = "fastq file"; }
      }
    }
    elsif ($suffix eq '.faa') {
      $type   = "Protein";
      $stats  = $self->read_stats($f, $type, $gz);
      $count  = (@$stats > 0) ? format_number($stats->[1][1]) . " reads" : '';
    }
    elsif ($suffix eq '.mapping') {
      $type  = "Cluster";
      $stats = $self->read_stats($f, $type);
      $desc .= " mapping";
    }
    elsif ($self->data('get_sims') && ($suffix eq '.sims')) {
      $type = "Sims";
      $desc = "raw";
    }
    elsif ($self->data('get_sims') && ($suffix eq '.filter')) {
      $type = "Sims";
      $desc = "filtered";
    }
    elsif ($self->data('get_sims') && ($desc eq 'expand')) {
      $type = "Sims";
      $desc = $suffix." annotated";
      $desc =~ s/^\.//;
    }
    elsif ($stages->{$sid}->{stage} && ($stages->{$sid}->{stage} eq 'abundance')) {
      $type = "Abundance";
      $desc = $suffix;
      $desc =~ s/^\.//;
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

sub download {
  my ($self) = @_;

  my $cgi  = $self->application->cgi;
  my $job  = $self->{job};
  my $file = $cgi->param('file');
  my $sid  = $cgi->param('stage');

  if (open(FH, $job->download_dir($sid) . "/" . $file)) {
    my $content = "";
    while (<FH>) {
      $content .= $_;
    }
    print "Content-Type:application/x-download\n";  
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=" . $job->metagenome_id . "." . $cgi->param('file') . "\n\n";
    print $content; 
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
  $html .= exists($info->{description}) ? "<p>".$info->{description}."</p>" : "";
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

sub public_project_download_table {
  my ($self) = @_ ;
  my $application = $self->application;
  my $user = $application->session->user;

  my $jobdbm = $application->data_handle('MGRAST');
  my $projects = [] ;# ($user) ? $user->has_right_to(undef, 'view', 'project') : [];
  my $public_projects = $jobdbm->Project->get_objects( { public => 1 } );

  my $public_jobs = {} ;
  my $list = $jobdbm->Job->get_objects( { public => 1 } );
  map { $public_jobs->{ $_->metagenome_id } = { project => 0 , job => $_ } } @$list ;

  

  my $content = "" ; # "Public projects and metagenomes." ;
  
  if ( scalar(@$projects) || scalar(@$public_projects)  ) {
    
    my $down_info = $application->component('download_project_info');
    $down_info->add_tooltip('all_down', 'download all submitted metagenomes for this project');
    $down_info->add_tooltip('meta_down', 'download project metadata');
    $down_info->add_tooltip('derv_down', 'download all derived data for metagenomes of this project');
    #$download .= "&nbsp;&nbsp;&nbsp;<a  onmouseover='hover(event,\"all_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.raw.tar'><img src='./Html/mg-download.png' style='height:15px;'/><small>submitted metagenomes</small></a>";
    #$download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/project_$id.xml'><img src='./Html/mg-download.png' style='height:15px;'/><small>project metadata</small></a>";
    #$download .= "&nbsp;&nbsp;&nbsp;<a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.processed.tar'><img src='./Html/mg-download.png' style='height:15px;'/><small>MG-RAST analysis</small></a>";


    my $table = $application->component('project_table');
    $table->items_per_page(25);
    $table->show_select_items_per_page(1);
    $table->show_column_select(1);
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->show_clear_filter_button(1);

    $table->width(800);
    $table->columns( [ { name => 'Project&nbsp;ID' , visible=> 0 , show_control=>0 , filter=>1  },
		       { name => 'Metagenome&nbsp;ID' , visible=> 0 , show_control=>1 , filter=>1  },
		       { name => 'Project' , filter => 1 , sortable => 1},
		       { name => 'Contact' , filter => 1 , sortable => 1},
		       { name => 'Biome'   , filter => 1 , sortable => 1},
		       { name => 'Country'   , filter => 1 , sortable => 1 , visible=>0 },
		       { name => 'PubMed ID'   , filter => 1 , sortable => 1 , visible=>0 },	      
		       { name => 'Sequence&nbsp;type' , filter => 1 , sortable => 1 , operator => 'combobox' } ,
		       { name => '#&nbsp;Metagenomes' , filter => 1  , operators => [ 'equal' , 'less' , 'more' ] , sortable =>  1} ,
		       { name => 'Project&nbsp;size (Mbp)' , filter => 1  , operators => [ 'equal' , 'less' , 'more' ] , sortable =>  1} ,
		       { name =>'Download' } ,
		     ] );
    my $data = [];
    $projects = $jobdbm->Project->get_objects_for_ids($projects);
    push @$projects, @$public_projects ;
    my $shown = {};
    foreach my $project (sort {$a->id <=> $b->id } @$projects) {
      next if $shown->{$project->_id};
      next unless $project->id ;
      $shown->{$project->_id} = 1;
      my $jobs = $jobdbm->ProjectJob->get_objects( { project => $project } );
      my $id = $project->id;
      
      
      my $jdownload = "<table>";
      foreach my $j (@$jobs) {
	my $id = $project->id;
	my $mid = $j->job->metagenome_id;
	
	# is in project
	$public_jobs->{$mid}->{project} = 1;
	
	# 	$jdownload .= "<tr align='center'><td><a href='?page=MetagenomeOverview&metagenome=$mid'>$mid</a></td>
	# <td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.raw.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download submitted metagenome' height='15'/><small>submitted</small></a></td>
	# <td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid/metadata.xml'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download metadata for this metagenome' height='15'/><small>metadata</small></a></td>
	# <td><a href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/$mid.processed.tar.gz'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for this metagenome' height='15'/><small>analysis</small></a></td>
	# </tr>\n"  if ($j->job->public);
      }
	#       $jdownload .= "</table>\n";
	
	
	
	next unless (scalar(@$jobs));

	
	my @f = $project->data('PI_firstname') ? $project->data('PI_firstname') : $project->data('firstname') ;
      my @l = $project->data('PI_lastname')  ? $project->data('PI_lastname')  : $project->data('lastname') ;
      my $biomes = "-" ;
      my $list =  $project->biomes;
      $biomes = join " " ,  @$list  if ( @$list ) ;  
      
      my $publications = "-" ;
      $list = $project->pubmed ;
      $publications = join "," ,  @$list if (@$list) ;

      my $countries = "-" ;
      $list = $project->countries ;
      $countries = join " " ,  @$list if (@$list) ;

      # all metagenome and sample ids
      my $mid = join " " , @{$project->all_metagenome_ids};
      $mid = "-" unless ($mid);
      
      my $sequence_types = "unknown" ;
      $list = $project->sequence_types ; #('unknown' , 'amplicon' , 'assembled' ,'wgs' , '16s' ) ;
      $sequence_types = join " <br>" , @$list if (@$list) ;

      my $project_size = $project->bp_count_raw || "-";
      my $formater = new Number::Format(-thousands_sep   => ',');
      $project_size =$formater->format_number(($project_size / 1000000), 0) unless ( $project_size eq "-" );
      
      
      
      my $download = "<table><tr align='center'>
<td><a  onmouseover='hover(event,\"all_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.raw.tar'><img src='$FIG_Config::cgi_url/Html/mg-download.png' height='15'/><small>submitted metagenomes</small></a></td>
<td><a onmouseover='hover(event,\"meta_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/metagenomes/$id/metadata.project-$id.xls'><img src='$FIG_Config::cgi_url/Html/mg-download.png' height='15'/><small>metadata</small></a></td>
<td><a onmouseover='hover(event,\"derv_down\",".$down_info->id.")' href='ftp://ftp.metagenomics.anl.gov/projects/$id.processed.tar'><img src='$FIG_Config::cgi_url/Html/mg-download.png' alt='Download all derived data for metagenomes of this project' height='15'/><small>analysis</small></a></td>
</tr></table>";
      
      push(@$data, [  $id , $mid , "<a href='?page=MetagenomeProject&project=$id' title='View project'>".$project->name."</a>", ( join "," , @l , @f  ) , $biomes , $countries ,  "<a href='http://www.ncbi.nlm.nih.gov/pubmed/$publications' target=_blank >$publications</a>" , $sequence_types , "<a href='?page=MetagenomeProject&project=$id#jobs' title='Download single metagenome from project page' >". scalar(@$jobs) . "</a>" , "$project_size" , $download ]);
    }

    
    my $all_ids_without_project = '';
    my $id                      = "no_project" ; # no_project tag  for non existent projects
    my $biomes                  = '';
    my $countries               = '';
    
    my $jdata = $jobdbm->Job->without_project();
    my $nr_without_project = scalar @$jdata ;
    $all_ids_without_project = join " " , (map { $_->[0] } @$jdata ) ; 
    
  
    
      push(@$data, [  $id , $all_ids_without_project , "<a href='?page=MetagenomeProject&project=no_project' title='View project'>ungrouped metagenomes</a>", ( '-'  ) , $biomes , $countries ,  "-" , "-" , "<a href='?page=MetagenomeProject&project=$id#jobs' title='Download single metagenome from project page' >$nr_without_project</a>" , "-" , "-" ]);
    
    
    $table->data($data);
    $content .= $down_info->output;
    $content .= $table->output();
    
  }
  return $content;
}
