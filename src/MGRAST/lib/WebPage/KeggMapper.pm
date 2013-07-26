package MGRAST::WebPage::KeggMapper;

use base qw( WebPage );

use strict;
use warnings;

use Data::Dumper;
use Conf;

use MGRAST::Analysis;

1;

=pod

=head1 NAME

KeggMapper - a KEGG mapping page

=head1 DESCRIPTION

page to display the KEGG global pathway and map lists / search

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->application->register_action($self, 'export_kegg_abundance', 'export_kegg_abundance');

  $self->title('KeggMapper');

  $self->application->register_component('ListSelect', 'ls');
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('KEGGMap', 'kmap');

  my $mgdb = MGRAST::Analysis->new( $self->app->data_handle('MGRAST')->db_handle );
  unless ($mgdb) {
    $self->app->add_message('warning', "Unable to retrieve the metagenome analysis database.");
    return 1;
  }
  my $id = $self->application->cgi->param('metagenome') || '';
  if ($id) {
    $mgdb->set_jobs([$id]);
  }
  $self->{mgdb} = $mgdb;

  $self->data('default_eval', '5');
  $self->data('default_ident', '60');
  $self->data('default_alen', '15');

  return 1;
}

=pod 

=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $html = "";

  open(FH, $Conf::mgrast_data . "/kegg/keggdata.poly") or die "oh noes! $@ $!";
  my $polys = <FH>;
  chomp $polys;
  close FH;

  my $names = [];
  open(FH, $Conf::mgrast_data . "/kegg/keggdata.names") or die "oh noes! $@ $!";
  while (<FH>) {
    chomp;
    push(@$names, $_);
  }
  close FH;

  my $nstring = join("~~", @$names);
  $nstring =~ s/'//g;

  $html .= $self->application->component('ajax')->output();

  $html .= "<input type='hidden' id='polys' value='".$polys."'>";

  $html .= "<input type='hidden' id='names' value='".$nstring."'>";

  $html .= "<div id='kdatabuf'></div>";

  $html .= "<table><tr><td style='padding-right: 30px;'>".$self->highlight_select()."</td>";
  $html .= "<td style='border: 1px solid black; width: 250px; padding: 5px;'><h2>Data A</h2><div style='width: 50px; height: 20px; float: right; background-color: #00F; position: relative; top: -35px;'></div>";
  $html .= "<div id='buf_a_text' style='height: 100px;'></div>";
  $html .= "<input type='button' value='clear' onclick='clear_buffer(\"a\");'>";
  $html .= "</td>";
  $html .= "<td style='border: 1px solid black; width: 250px; padding: 5px;'><h2>Data B</h2><div style='width: 50px; height: 20px; float: right; background-color: #F00; position: relative; top: -35px;'></div>";
  $html .= "<div id='buf_b_text' style='height: 100px;'></div>";
  $html .= "<input type='button' value='clear' onclick='clear_buffer(\"b\");'>";
  $html .= "</td></tr></table>";

  $html .= "Show unique data from <select id='result_type'><option value='abc'>Data A, Data B and overlaps (purple)</option><option value='ac'>Data A and overlaps (purple)</option><option value='a'>Data A</option><option value='ab'>Data A and Data B</option><option value='bc'>Data B and overlaps (purple)</option><option value='b'>Data B</option><option value='c'>overlaps (purple)</option></select>";
  $html .= "<input type='button' value='highlight loaded data' onclick='compare();'>";
  $html .= "&nbsp;&nbsp;&nbsp;image size <input type='text' id='scalefactor' value='25' size=3>%&nbsp;&nbsp;";
  $html .= "<input type='button' value='scale image' onclick='scale_image();'>";
  $html .= "<input type='button' value='export kegg abundance' onclick='export_kegg_abundance();' />\n";

  $html .= "<img src='./Html/map01100.png' id='m' style='height: 563px; width: 924px;' border='0' />";
  $html .= "<div id='raph'></div>";
  $html .= "<img src='./Html/clear.gif' onload='initialize_kegg();'>";

  $html .= "<form id='kmap_form'><input type='hidden' name='mapnum' id='mapnum'><input type='hidden' name='kids' id='kids'><input type='hidden' name='abu' id='abu'><input type='hidden' name='which' id='which'></form>";
  $html .= "<a href='#top' id='bottom'>top</a><div id='submap'></div>";

  return $html;
}

sub export_kegg_abundance {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $format = $cgi->param('format');
  my @kids = split(/~/, $cgi->param('kids'));
  my @abu = split(/~/, $cgi->param('abu'));
  my @which = split(/~/, $cgi->param('which'));

  my %master_hash = ();
  for(my $i=0; $i<@kids; ++$i) {
    $master_hash{$which[$i]}{$kids[$i]} = $abu[$i];
  }

  if($format eq 'html') {
    my $content = "<table><tr><td style='vertical-align:top;width:300px'>\n";
    $content .= "<h2>Data A</h2><table border=1><tr><td>EC number</td><td>Abundance</td></tr>";
    my $dataset = 'a';
    foreach my $kid (sort {$master_hash{$dataset}{$b} <=> $master_hash{$dataset}{$a}} keys %{$master_hash{$dataset}}) {
      $content .= "<tr><td><a href=\"http://www.genome.jp/dbget-bin/www_bget?ec:$kid\" target=\"_blank\">$kid</a></td>".
                  "<td>$master_hash{$dataset}{$kid}</td></tr>";
    }
    $content .= "</table></td><td style='vertical-align:top;width:300px'>";
    $content .= "<h2>Data B</h2><table border=1><tr><td>EC number</td><td>Abundance</td></tr>";
    $dataset = 'b';
    foreach my $kid (sort {$master_hash{$dataset}{$b} <=> $master_hash{$dataset}{$a}} keys %{$master_hash{$dataset}}) {
      $content .= "<tr><td><a href=\"http://www.genome.jp/dbget-bin/www_bget?ec:$kid\" target=\"_blank\">$kid</a></td>".
                  "<td>$master_hash{$dataset}{$kid}</td></tr>";
    }
    $content .= "</table></td></tr></table>";
    print "Content-Type: text/html\n\n";
    print $content;
    exit;
  } elsif($format eq 'text') {
    my $content = "Dataset\tEC number\tAbundance\n";
    foreach my $dataset (keys %master_hash) {
      foreach my $kid (sort {$master_hash{$dataset}{$b} <=> $master_hash{$dataset}{$a}} keys %{$master_hash{$dataset}}) {
        $content .= uc($dataset)."\t$kid\t$master_hash{$dataset}{$kid}\n";
      }
    }
    print "Content-Type:application/x-download\n";
    print "Content-Length: " . length($content) . "\n";
    print "Content-Disposition:attachment;filename=filename\n\n";
    print $content;
    exit;
  }
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/Kegg.js", "$Conf::cgi_url/Html/raphael-min.js", "$Conf::cgi_url/Html/canvg.js"];
}

sub highlight_select {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $metagenome = '';
  my $mg = '';
  if ($cgi->param('metagenome')) {
    $metagenome = $cgi->param('metagenome');
    $mg = $metagenome || '';
    my $mgname = '';
    if ($metagenome) {
      my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $metagenome });
      if (ref($job)) {
	$mgname = $job->name()." ($metagenome)";
      }
    }
    $metagenome = "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$metagenome' title='$mgname'>$metagenome</a>";
  }

  if ($cgi->param('comparison_metagenomes')) {
    $metagenome = '';
    my @all = $cgi->param('comparison_metagenomes');
    foreach my $mg (@all) {
      my $mgname = '';
      if ($metagenome) {
	my $job = $self->app->data_handle('MGRAST')->Job->init({ metagenome_id => $mg });
	if (ref($job)) {
	  $mgname = $job->name()." ($mg)";
	}
      }
      $metagenome .= "<a target=_blank href='metagenomics.cgi?page=MetagenomeOverview&metagenome=$mg' title='$mgname'>$mg</a>, ";
    }
    $metagenome = substr($metagenome, 0, length($metagenome) - 2);
  }

  my $mg_sel = $self->metagenome_select();
  my $select = "<h2>Data Selection</h2><form name='meta_form' id='meta_form' onkeypress='return event.keyCode!=13'><input type='hidden' name='metagenome' value='".$mg."'><table id='non_wb_sel'><tr><td style='font-weight: bold; width: 200px;'>Target Buffer</td><td><select id='tbuff' name='tbuff'><option value='buffer_space_a'>Data A</option><option value='buffer_space_b'>Data B</option></select></td></tr><tr><td style='font-weight: bold; width: 200px;'>Metagenomes</td><td id='mg_sel_td'>".$metagenome."</td><td>".$self->more_button('document.getElementById("sel_mg").style.display="";', 'ok_button("'.$mg_sel->id.'");')."</td></tr><tr><td colspan=3 style='display: none;' id='sel_mg'><table><tr><td>".$mg_sel->output()."</td><td><input type='button' value='ok' onclick='ok_button(\"".$mg_sel->id."\");'></td></tr></table></td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Choose maximum probability that there is a sequence with a higher similarity to your target sequence than the one provided.'>Max. e-Value Cutoff</td><td>1e-".$self->data('default_eval')."</td><td>".$self->more_button('document.getElementById("meta_sel_eval").style.display="";')."</td><td style='display: none;' id='meta_sel_eval'>".$self->evalue_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Define the minimum percent identity between your selected metagenomes and existing sBLAT sequences.'>Min. % Identity Cutoff</td><td>".$self->data('default_ident')." %</td><td>".$self->more_button('document.getElementById("meta_sel_ident").style.display="";')."</td><td style='display: none;' id='meta_sel_ident'>".$self->identity_select()."</td></tr>";
  $select .= "<tr><td style='font-weight: bold;' title='Minimum length of matching sequences considered sufficient to be \"aligned\", measured in aa for protein and bp for RNA databases.'>Min. Alignment Length Cutoff</td><td>".$self->data('default_alen')."</td><td>".$self->more_button('document.getElementById("phylo_sel_alen").style.display="";')."</td><td style='display: none;' id='phylo_sel_alen'>".$self->alength_select()."</td></tr></table>";
  $select .= "<input type='button' value='load data' onclick='if(document.getElementById(\"list_select_list_b_".$self->application->component('ls')->id."\").options.length){list_select_select_all(\"".$self->application->component('ls')->id."\");execute_ajax(\"get_kegg_data\",\"kdatabuf\",\"meta_form\",\"loading...\", null, tobuff);}else{alert(\"You did not select any metagenomes\");};'><input type='hidden' name='source' value='KO'></form>";

  return $select;
}

sub get_kegg_data {
  my ($self) = @_;

  my $result   = [];
  my $cgi      = $self->application->cgi;
  my $source   = $cgi->param('source');
  my @metas   = $cgi->param('comparison_metagenomes');
  my $evalue   = $cgi->param('evalue');
  my $identity = $cgi->param('identity');
  my $alength  = $cgi->param('alength');

  $self->{mgdb}->set_jobs(\@metas);

  $result = $self->{mgdb}->get_ontology_for_source($source, $evalue, $identity, $alength);
  my $id_map = $self->{mgdb}->get_hierarchy('ontology', $source);
  my $funcs = {};

  foreach my $row (@$result) {
    if ( exists $id_map->{$row->[1]} ) {
      my @levels;
      foreach (@{$id_map->{$row->[1]}}) { next unless $_; $_ =~ s/_/ /g; push @levels, $_; }
      my $depth = scalar @levels;
      my $lvl1  = shift @levels;
      my $lvl2  = shift @levels;
      if ((! $lvl2) || ($lvl2 eq 'Unknown')) {
	$lvl2 = $lvl1;
      }
      my $new = [ $row->[0], $lvl1, $lvl2 ];

      if ($depth > 3) {
	my $lvl3 = shift @levels;
	if ((! $lvl3) || ($lvl3 eq 'Unknown')) {
	  $lvl3 = $lvl2;
	}
	push @$new, $lvl3;
      }
      else {
	push @$new, "-";
      }
      push @$new, @$row[2..9];
      my ($ec) = $new->[4] =~ /EC\:(.*)/;
      if ($ec) {
	$ec =~ s/\]//;
	unless (exists($funcs->{$ec})) {
	  $funcs->{$ec} = 0;
	}
	$funcs->{$ec} += $new->[5];
      }
    }
  }

  my $retval = join("~", map { $_.";".$funcs->{$_} } keys(%$funcs));

  my $html = "<input type='hidden' id='keggdata' value='$retval'>";
  $html .= "<input type='hidden' id='whichbuf' value='".$cgi->param('tbuff')."'>";
  $html .= "<input type='hidden' id='mgids' value='".join(", ", @metas)."'>";
  $html .= "<input type='hidden' id='evalue' value='$evalue'>";
  $html .= "<input type='hidden' id='identity' value='$identity'>";
  $html .= "<input type='hidden' id='alength' value='$alength'>";

  return $html;
}

sub more_button {
  my ($self, $onclicka) = @_;

  my $button = "<a style='border: 1px solid #8FBC3F; padding-left: 3px; padding-right: 3px; font-size: 8px; padding-bottom: 1px; position: relative; top: 1px; color: #8FBC3F; cursor: pointer;' onclick='$onclicka;'>+</a>";

  return $button;
}

sub metagenome_select {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $metagenome = $cgi->param('metagenome') || '';
  my $list_select = $application->component('ls');
  my ($data, $groups) = $self->selectable_metagenomes();
  my @preselected = ( $metagenome );
  if ($cgi->param('comparison_metagenomes')) {
    @preselected = $cgi->param('comparison_metagenomes');
  }
  $list_select->data($data);
  $list_select->preselection(\@preselected);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->group_names($groups);
  $list_select->{max_width_list} = 250;
  $list_select->left_header('available metagenomes');
  $list_select->right_header('selected metagenomes');
  $list_select->name('comparison_metagenomes');

  return $list_select;
}

sub selectable_metagenomes {
  my ($self, $no_coll) = @_;
  my $metagenomes = [];
  my $metagenome = $self->application->cgi->param('metagenome') || '';
  
  my $avail = $self->{mgdb}->get_all_job_ids();
  my $avail_hash = {};
  %$avail_hash = map { $_ => 1 } @$avail;

  my $all_mgs = [];
  # check for available metagenomes
  my $rast = $self->application->data_handle('MGRAST'); 
  my $org_seen = {};
  my $metagenomespub = [];
  my $colls = [];
  if (ref($rast)) {
    my $public_metagenomes = $rast->Job->get_objects({public => 1, viewable => 1});
    foreach my $pmg (@$public_metagenomes) {
      next if ($org_seen->{$pmg->{metagenome_id}});
      $org_seen->{$pmg->{metagenome_id}} = 1;
      next unless ($avail_hash->{$pmg->{job_id}});
      push(@$metagenomespub, { label => $pmg->{name}." (".$pmg->{metagenome_id}.")", value => $pmg->{metagenome_id} });
    }
    if ($self->application->session->user) {
      my @mga = $rast->Job->get_jobs_for_user_fast($self->application->session->user, 'view', 1);
      my $mgs = \@mga;

      # check for collections
      my $coll_prefs = $self->application->dbmaster->Preferences->get_objects( { application => $self->application->backend,
										 user => $self->application->session->user,
										 name => 'mgrast_collection' } );

      if (scalar(@$coll_prefs) && (! $no_coll)) {
	my $collections = {};
	foreach my $collection_pref (@$coll_prefs) {
	  my ($name, $val) = split(/\|/, $collection_pref->{value});
	  if (! exists($collections->{$name})) {
	    $collections->{$name} = [];
	  }
	  my $pj;
	  foreach my $pmg (@$public_metagenomes) {
	    if ($pmg->{job_id} == $val) {
	      $pj = $pmg;
	      last;
	    }
	  }
	  unless ($pj) {
	    foreach my $mg (@$mgs) {
	      if (ref($mg) && ref($mg) eq 'HASH') {
		if ($mg->{job_id} == $val) {
		  $pj = $mg;
		  last;
		}
	      }
	    }
	  }
	  if ($pj) {
	    push(@{$collections->{$name}}, [ $pj->{metagenome_id}, $pj->{name} ]);
	  }
	}
	foreach my $coll ( sort keys %$collections ) {
	  if ( @{$collections->{$coll}} == 0 ) { next; }
	  push(@$colls, { label => $coll." [".scalar(@{$collections->{$coll}})."]", value => join('||', map { $_->[0]."##".$_->[1] } @{$collections->{$coll}}) });
	}
      }

      # build hash from all accessible metagenomes
      foreach my $mg_job (@$mgs) {
	next if ($org_seen->{$mg_job->{metagenome_id}});
        $org_seen->{$mg_job->{metagenome_id}} = 1;
        next unless ($avail_hash->{$mg_job->{job_id}});
        push(@$metagenomes, { label => ($mg_job->{name} || "")." (".$mg_job->{metagenome_id}.")", value => $mg_job->{metagenome_id}});
      }
    }
  }
  my $groups = [];
  if (scalar(@$metagenomes)) {
    push(@$all_mgs, $metagenomes);
    push(@$groups, 'private');
  }
  if (scalar(@$colls)) {
    push(@$all_mgs, $colls);
    push(@$groups, 'collections');
  }
  if (scalar(@$metagenomespub)) {
    push(@$all_mgs, $metagenomespub);
    push(@$groups, 'public');
  }
  
  return ( $all_mgs, $groups );
}

sub get_evals {
  return [ 0.001, 1e-5, 1e-10, 1e-20, 1e-30 ];
}

sub get_eval_index {
  my ($self, $eval) = @_;
  my $last = scalar( @{$self->get_evals} ) - 1;
  my @idxs = grep { $self->get_evals->[$_] == $eval } 0..$last;
  return @idxs ? $idxs[0] : undef;
}

sub get_idents {
  return [ 0, 60, 80, 90, 97 ];
}

sub get_ident_index {
  my ($self, $ident) = @_;
  my $last = scalar( @{$self->get_idents} ) - 1;
  my @idxs = grep { $self->get_idents->[$_] == $ident } 0..$last;
  return @idxs ? $idxs[0] : undef;
}

sub get_alens {
  return [ 0, 50, 100, 250, 1000 ];
}
	  	 
sub get_alen_index {
  my ($self, $alen) = @_;
  my $last = scalar( @{$self->get_alens} ) - 1;
  my @idxs = grep { $self->get_alens->[$_] == $alen } 0..$last;
  return @idxs ? $idxs[0] : undef;
}

sub get_log {
  my ($self, $log, $num) = @_;

  if ($log < 2) { return $num; }
  if (($num == 0) || ($num == 1) || ($num == -1)) {
    return $num;
  }
  else {
    if ($num < 0) { $num =~ s/^-//; }
    return int($log * (log($num) / log($log)));
  }
}

sub evalue_select {
  my ($self) = @_;

  my $eval = $self->application->cgi->param('evalue') || $self->data('default_eval');
  my $html = qq(1e-&nbsp;<input type='text' name='evalue' value='$eval' size='5' /><span>&nbsp;</span><input type='button' onclick='
var expNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(expNum) || (expNum < 0) || (expNum > 999)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer from 0 to 999";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = "1e-" + expNum;
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub identity_select {
  my ($self) = @_;

  my $ident = $self->application->cgi->param('identity') || $self->data('default_ident');
  my $html  = qq(<input type='text' name='identity' value='$ident' size='5' /><span>&nbsp;&#37;&nbsp;</span><input type='button' onclick='
var identNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(identNum) || (identNum < 0) || (identNum > 100)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer from 0 to 100";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = identNum + " %";
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub alength_select { 	 
  my ($self) = @_; 	 

  my $alen = $self->application->cgi->param('alength') || $self->data('default_alen');
  my $html = qq(<input type='text' name='alength' value='$alen' size='5' /><span>&nbsp;</span><input type='button' onclick='
var alenNum = parseInt(this.previousSibling.previousSibling.value);
if (isNaN(alenNum) || (alenNum < 1)) {
  this.parentNode.previousSibling.previousSibling.innerHTML = "Please enter integer greater than 0";
} else {
  this.parentNode.previousSibling.previousSibling.innerHTML = alenNum;
  this.parentNode.style.display="none";
}' value='ok' />);

  return $html;
}

sub kegg_map {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  # get the data from the cgi
  my @ids = split /~/, $cgi->param('kids');
  my @abundances = split /~/, $cgi->param('abu');
  my @which = split /~/, $cgi->param('which');

  # hash out the data
  my $data = {};
  for (my $i=0; $i<scalar(@ids); $i++) {
    if (exists($data->{$ids[$i]})) {
      if (exists($data->{$ids[$i]}->{$which[$i]})) {
	$data->{$ids[$i]}->{$which[$i]} += $abundances[$i];
      } else {
	$data->{$ids[$i]}->{$which[$i]} = $abundances[$i];
      }
    } else {
      $data->{$ids[$i]} = { $which[$i] => $abundances[$i] };
    }
  }

  my $highlights = [];
  foreach my $key (keys(%$data)) {
    my $color;
    my $tooltip;
    if (scalar(keys(%{$data->{$key}})) > 1) {
      $tooltip = $data->{$key}->{'a'}." hits blue, ".$data->{$key}->{'b'}." hits red";
      $color = [ [ 0, 0, 255 ], [ 255, 0, 0 ] ];
    } elsif ($data->{$key}->{'b'}) {
      $tooltip = $data->{$key}->{'b'}." hits";
      $color = [ 255, 0, 0 ];
    } else {
      $tooltip = $data->{$key}->{'a'}." hits";
      $color = [ 0, 0, 255 ];
    }
    push(@$highlights, { id => $key,
			 tooltip => $tooltip,
			 color => $color,
			 link => "http://www.genome.jp/dbget-bin/www_bget?".$key,
			 target => "_blank" });
  }

  my $kegg_component = $application->component('kmap');
  $kegg_component->map_id($cgi->param('mapnum'));
  $kegg_component->highlights($highlights);

  return $kegg_component->output()."<img src='./Html/clear.gif' onload='location.href=\"#bottom\";document.getElementById(\"submap\").scrollIntoView(true);'>";
}
