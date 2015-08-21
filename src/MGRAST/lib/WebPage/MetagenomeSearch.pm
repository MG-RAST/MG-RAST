package MGRAST::WebPage::MetagenomeSearch;

use base qw( WebPage );

use strict;
use warnings;

use URI::Escape;
use Data::Dumper;
use HTML::Strip;

use Conf;
use MGRAST::Analysis;
use MGRAST::Metadata;

1;

=pod

=head1 NAME

MetagenomeSelect - an instance of WebPage which lets the user select a metagenome

=head1 DESCRIPTION

Display a metagenome select box

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Metagenome Search');
  $self->{icon} = "<img src='./Html/lupe.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  $self->application->register_component('Table', "sResult");
  $self->application->register_component('Ajax', 'sAjax');
  $self->application->register_component('Hover', 'help');

  my @mgs  = $self->app->cgi->param('metagenomes');
  my $jmap = {};
  my $pmap = {};
  my $jobs;
#  my $jobs = $self->get_user_jobs(\@mgs);
#  foreach (keys %$jobs) {
#    last;
#    $jmap->{ $jobs->{$_}{_id} } = $_;
#    if (exists $jobs->{$_}{project_id}) {
#      push @{ $pmap->{ $jobs->{$_}{project_id} } }, $_;
#    }
#  }
  my $mddb = MGRAST::Metadata->new();
  my $mgdb = MGRAST::Analysis->new( $self->app->data_handle('MGRAST')->db_handle );
  
  my $type = [ ["function", "Function", ""],
	       ["organism", "Organism", "taxon"],
	       ["Subsystems", "SEED Subsystem", "hier2"],
	       ["KO", "KEGG Orthology", "hier2"],
	       ["COG", "COG", "hier1"],
	       ["NOG", "NOG", "hier1"],
	       ["metadata", "Metadata", "meta"]
	     ];
  my $meta = [ ["all", "All", "text"],
	       ["project", "Project Name", "text"],
	       ["name", "Metagenome Name", "text"],
	       ["metagenome_id", "Metagenome ID", "text"],
	       ["pi", "Principal Investigator", "text"],
	       ["biome", "Biome", "select"],
	       ["feature", "Feature", "select"],
	       ["material", "Material", "select"],
	       ["env_package", "Enviromental Package", "select"],
	       ["country", "Country", "select"],
	       ["latitude", "Latitude", "range"],
	       ["longitude", "Longitude", "range"],
	       ["location", "Location", "text"],
	       ["altitude", "Altitude", "range"],
	       ["depth", "Depth", "range"],
	       ["temperature", "Temperature", "range"],
	       ["ph", "pH", "range"],
	       ["sequencing method", "Sequencing method", "select"],
	       ["bp_count", "bp Count", "range"],
	       ["sequence_count", "Sequence Count", "range"],
	       ["alpha_diversity", "Alpha Diversity", "range"],
	       ["drisee", "DRISEE Score", "range"]
	     ];
  my $taxon = [ ['name', 'Organism Name', "text"],
		['tax_family', 'Family', "text"],
		['tax_order', 'Order', "text"],
		['tax_class', 'Class', "text"],
		['tax_phylum', 'Phylum', "select"],
		['tax_domain', 'Domain', "select"],
		['ncbi_tax_id', 'NCBI Taxonomy ID', "text"]
	      ];
  my $match = { text   => [ ["0_1", "contains"], ["0_0", "does not contain"], ["1_1", "is equal to"], ["1_0", "is not equal to"] ],
		select => [ ["1_1", "is equal to"], ["1_0", "is not equal to"] ],
		range  => [ ["2_1", "is within range"], ["2_0", "is outside range"] ]
	      };
  my $hier1 = [ ["level3", "Name or ID", "text"], ["level2", "Level 2", "select"], ["level1", "Level 1", "select"] ];
  my $hier2 = [ ["level4", "Name or ID", "text"], ["level3", "Level 3", "text"], ["level2", "Level 2", "select"], ["level1", "Level 1", "select"] ];

  $self->data('jobs', $jobs);
  $self->data('jmap', $jmap);
  $self->data('pmap', $pmap);
  $self->data('mddb', $mddb);
  $self->data('mgdb', $mgdb);
  $self->data('type', $type);
  $self->data('meta', $meta);
  $self->data('taxon', $taxon);
  $self->data('match', $match);
  $self->data('hier1', $hier1);
  $self->data('hier2', $hier2);
  $self->data('max_results', 500000);

  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the MetagenomeSelect page.

=cut

sub output {
  my ($self) = @_;

  my $msg_count = 1;

  my $cgi    = $self->app->cgi;
  my $qnum   = $cgi->param('qnum')  || 0;
  my $mode   = $cgi->param('smode') || 1;
  my $torun  = $cgi->param('run_now') || 0;
  my $mddb   = $self->data('mddb');
  my $mgdb   = $self->data('mgdb');
  my $match  = $self->data('match');
  my $modes  = { 1 => "dSimple", 2 => "dAdvanced" };
  my $extras = {};
#  my $extras = { "metadata"   => { "biome"       => $self->get_unique_job_info('biome'),
#				   "feature"     => $self->get_unique_job_info('feature'),
#				   "material"    => $self->get_unique_job_info('material'),
#				   "env_package" => $mddb->get_cv_list('env_package'),
#				   "country"     => $self->get_unique_job_info('country'),
#				   "sequencing method" => $mddb->get_cv_list('seq_meth') },
#		 "organism"   => { "tax_phylum" => $mgdb->ach->get_taxonomy4level("tax_phylum"),
#				   "tax_domain" => $mgdb->ach->get_taxonomy4level("tax_domain") },
#		 "Subsystems" => { "level1" => $mgdb->ach->get_level4ontology("Subsystems","level1"),
#				   "level2" => $mgdb->ach->get_level4ontology("Subsystems","level2") },
#		 "KO"         => { "level1" => $mgdb->ach->get_level4ontology("KO","level1"),
#				   "level2" => $mgdb->ach->get_level4ontology("KO","level2") },
#		 "COG"        => { "level1" => $mgdb->ach->get_level4ontology("COG","level1"),
#				   "level2" => $mgdb->ach->get_level4ontology("COG","level2") },
#		 "NOG"        => { "level1" => $mgdb->ach->get_level4ontology("NOG","level1"),
#				   "level2" => $mgdb->ach->get_level4ontology("NOG","level2") }
#	       };
  
  my $taxon_sel = $self->build_select("sel_extra", $self->data('taxon'));
  my $hier1_sel = $self->build_select("sel_extra", $self->data('hier1'));
  my $hier2_sel = $self->build_select("sel_extra", $self->data('hier2'));
  my $metad_sel = $self->build_select("sel_extra", $self->data('meta'));
  my $txt_match = $self->build_select("sel_match", $match->{text});
  my $sel_match = $self->build_select("sel_match", $match->{select});
  my $rng_match = $self->build_select("sel_match", $match->{range});
  my $text_sel  = "<input name='txt_adv' type='text' value=''/>";
  my $range_sel = "<input name='rng1_adv' type='text' value='' size='7'/>&nbsp;to&nbsp;<input name='rng2_adv' type='text' value='' size='7'/>";
  my $adv_deflt = $self->get_advanced_search();
  
  my (@adv_list, $adv_srch);
  my $to_hide  = ($mode == 2) ? $modes->{1} : $modes->{2};

  if ($qnum && ($qnum > 0) && ($mode == 2)) {
    foreach my $i (1..$qnum) {
      last;
      my $qtype  = $cgi->param("type_q$i");
      my $qmatch = $cgi->param("match_q$i");
      my $qinput = uri_unescape( $cgi->param("input_q$i") );
      my $qextra = $cgi->param("extra_q$i") || "";

      push @adv_list, "query$i";
      $adv_srch .= "<tr id='query$i'>" . $self->get_advanced_search($qtype, $qmatch, $qinput, $qextra, $extras) . "</tr>";
    }
  } else {
    $qnum = 1;
    push @adv_list, "query1";
    $adv_srch = qq(<tr id='query1'>$adv_deflt</tr>);
  }

  my @ext_set = ();
  foreach my $t (keys %$extras) {
    last;
    foreach my $e (keys %{$extras->{$t}}) {
      push @ext_set, qq("${t}_$e" : ") . $self->build_select("sel_adv", $extras->{$t}{$e}) . qq(");
    }
  }
  my $ext_json = "{ " . join(",", @ext_set) . " }";
  my $qlist    = "[ " . join(",", map {"'$_'"} @adv_list) . " ]";

  my $stext = $cgi->param('text') || "";
  my $stype = $cgi->param('type') || "metadata,function,organism";
  if ($cgi->param('init_search')) {
    $stext = $cgi->param('init_search');
    $stype = "metadata,function,organism";
    $torun = 1;
  }

  my $set_types = "";
  my %types = map { $_, 1 } split(/,/, $stype);
  if ((scalar(keys %types) < 3) && ($mode == 1)) {
    $set_types .= exists($types{metadata}) ? '$("#metaSimple").attr("checked", true); ' : '$("#metaSimple").attr("checked", false); ';
    $set_types .= exists($types{function}) ? '$("#funcSimple").attr("checked", true); ' : '$("#funcSimple").attr("checked", false); ';
    $set_types .= exists($types{organism}) ? '$("#orgSimple").attr("checked", true); '  : '$("#orgSimple").attr("checked", false); ';
  }

  my $search_now = "";
  if ($torun) {
    if ($mode == 1) {
      $search_now = "document.getElementById(\"bSimpleAll\").click();";
#      $search_now = "simple_search('$stext', [" . join(',', map {"'$_'"} keys %types) . "]);";
    }
    elsif ($mode == 2) {
      $search_now = '$("#dSimple").hide(); $("#dAdvanced").show(); adv_search();';
    }
  } elsif ($mode == 2) {
    $search_now = "switch_mode(2);";
  }
  
  my $scripts  = qq~
<script type="text/javascript" src="http://maps.google.com/maps/api/js?sensor=false"></script>
<script type="text/javascript" src="Html/js/config.js"></script>
<script type="text/javascript">
\$(document).ready( function() {
  var qList = $qlist;
  var qNum  = $qnum;
  var eMap  = $ext_json;
  
  switch_sub();
  \$("#$to_hide").hide();
  \$("#SwitchToAdv").live('click', function() { switch_mode(2); });
  \$("#SwitchSearchType").live('click', function() {
    if (\$("#dAdvanced").is(':visible')) {
      switch_mode(1);
    } else {
      switch_mode(2);
    }
  });
  \$("#tQuery select[name='sel_type']").live('change', function() {
    var match_td = \$(this).parent().next();
    var input_td = match_td.next();
    var msg_td   = input_td.next()
    var extra_td = msg_td.next();
    var subsel   = "";
    var msg_txt  = 'within';
    if (\$(this).val() == 'organism') {
      subsel = "$taxon_sel";
    } else if (\$(this).val() == 'function') {
      msg_txt = "";
    } else if ((\$(this).val() == 'Subsystems') || (\$(this).val() == 'KO')) {
      subsel = "$hier2_sel";
    } else if ((\$(this).val() == 'COG') || (\$(this).val() == 'NOG')) {
      subsel = "$hier1_sel";
    } else if (\$(this).val() == 'metadata') {
      subsel = "$metad_sel";
    }
    match_td.html("$txt_match");
    input_td.html("$text_sel");
    msg_td.html(msg_txt);
    extra_td.html(subsel);
  });
  \$("#tQuery select[name='sel_extra']").live('change', function() {
    var input_td  = \$(this).parent().prev().prev();
    var match_td  = input_td.prev();
    var type_val  = match_td.prev().find("select[name='sel_type']").val();
    var opt_title = \$(this).children(":selected").attr('title');
    if (opt_title == 'select') {
      var eKey = type_val + '_' + \$(this).val();
      if ( eMap.hasOwnProperty(eKey) ) {
        input_td.html( eMap[eKey] );
        match_td.html("$sel_match");
      } else {
        input_td.html("$text_sel");
        match_td.html("$txt_match");
      }
      match_td.html("$sel_match");
    } else if (opt_title == 'range') {
      input_td.html("$range_sel");
      match_td.html("$rng_match");
    } else {
      input_td.html("$text_sel");
      match_td.html("$txt_match");
    }
  });
  \$("#tQuery button[name='but_add']").live('click', function() {
    qNum += 1;
    var row = \$(this).parent().parent();
    var idx = qList.indexOf(row.attr('id'));
    var nid = "query" + qNum;
    row.after("<tr id='" + nid + "'>$adv_deflt</tr>");
    qList.splice(idx+1, 0, nid);
    switch_sub();
  });
  \$("#tQuery button[name='but_sub']").live('click', function() {
    if (qNum == 1) { return 0; }
    qNum -= 1;
    var row = \$(this).parent().parent();
    var idx = qList.indexOf(row.attr('id'));
    row.remove();
    qList.splice(idx, 1);
    switch_sub();
  });
  function switch_sub() {
    if (qList.length == 1) {
      \$("#"+qList[0]+" button[name='but_sub']").attr('disabled', true);
    } else if (qList.length > 1) {
      \$("#"+qList[0]+" button[name='but_sub']").attr('disabled', false);
    }
  }
  \$("#bSimpleAll").click( function() {
    var sText  = clean_text( \$("#tSimpleAll").val() );
    var sTypes = [];
    if ( \$("#metaSimple").attr('checked') ) { sTypes.push('metadata'); }
    if ( \$("#funcSimple").attr('checked') ) { sTypes.push('function'); }
    if ( \$("#orgSimple").attr('checked') )  { sTypes.push('organism'); }
    var result = document.getElementById("dResult"); 
    result.innerHTML = "<img src='./Html/loading-green.gif' />";
    queryAPI({type: sTypes, query: sText, result: "dResult"});
  });
  \$("#bSimpleMeta").click( function() {
    var sText = clean_text( \$("#tSimpleMeta").val() );
    switch_mode(1);
    \$("#tSimpleMeta").val('')
    \$("#tSimpleAll").val(sText);
    \$("#metaSimple").attr('checked', true);
    \$("#funcSimple").attr('checked', false);
    \$("#orgSimple").attr('checked', false);
    var result = document.getElementById("dResult"); 
    result.innerHTML = "<img src='./Html/loading-green.gif' />";
    queryAPI({type: ['metadata'], query: sText, result: "dResult"});
  });
  \$("#bSimpleFunc").click( function() {
    var sText = clean_text( \$("#tSimpleFunc").val() );
    switch_mode(1);
    \$("#tSimpleFunc").val('')
    \$("#tSimpleAll").val(sText);
    \$("#metaSimple").attr('checked', false);
    \$("#funcSimple").attr('checked', true);
    \$("#orgSimple").attr('checked', false);
    var result = document.getElementById("dResult"); 
    result.innerHTML = "<img src='./Html/loading-green.gif' />";
    queryAPI({type: ['function'], query: sText, result: "dResult"});
  });
  \$("#bSimpleOrg").click( function() {
    var sText = clean_text( \$("#tSimpleOrg").val() );
    switch_mode(1);
    \$("#tSimpleOrg").val('')
    \$("#tSimpleAll").val(sText);
    \$("#metaSimple").attr('checked', false);
    \$("#funcSimple").attr('checked', false);
    \$("#orgSimple").attr('checked', true);
    var result = document.getElementById("dResult"); 
    result.innerHTML = "<img src='./Html/loading-green.gif' />";
    queryAPI({type: ['organism'], query: sText, result: "dResult"});
  });
  \$("#bAdvanced").click( function() {
    adv_search();
  });
  function adv_search() {
    var param = ['smode=2', 'qnum=' + qNum];
    var rnum  = 0;
    var msg   = "";
    \$("#tQuery tr").each( function() {
      rnum += 1;
      var aText  = '';
      var inputs = \$(this).find("td[name='input_adv']").children("*[name\$='_adv']");
      if ( inputs.length == 2 ) {
        var ranges = [];
        inputs.each(function(){ ranges.push( clean_text(\$(this).val()) ); });
        if ( isNaN(ranges[0]) || isNaN(ranges[1]) ) {
          msg = "<p><b style='color:red'>Range values ('" + ranges.join("' and '") + "') must be numeric only.</b></p>";
        } else {
          if (parseFloat(ranges[0]) > parseFloat(ranges[1])) { ranges = ranges.reverse(); }
          aText = ranges.join("_");
        }
      } else {
        aText = clean_text( inputs.val() );
        msg   = test_text( aText );
      }
      \$("#dResult").html(msg);
      var extra = \$(this).find("td[name='extra']");
      if ( extra.find("select").val() ) {
        param.push( 'extra_q' + rnum + '=' + extra.find("select").val() );
      }
      param.push( 'input_q' + rnum + '=' + encodeURIComponent(aText) );
      param.push( 'match_q' + rnum + '=' + \$(this).find("select[name='sel_match']").val() );
      param.push( 'type_q'  + rnum + '=' + \$(this).find("select[name='sel_type']").val() );
    });
    if ( ! \$("#showGroup").attr('checked') ) { param.push('show_match=1'); }
    if (msg == "") { execute_ajax( 'get_advanced_table', 'dResult', param.join("&") ); }
  }
  function simple_search( sText, sTypes ) {
    var cText = clean_text(sText);
    var msg   = test_text(cText);
    var items = cText.split(",");
    var types = sTypes.join(',');
    var param = [ 'smode=1', 'text=' + encodeURIComponent(cText), 'type=' + types ];
    if ((msg == "") && (items.length > 1)) {
      msg = "<p><span style='color:red'>Only one search term is allowed.</span><br>" +
            "To use multiple search terms please use <a id='SwitchToAdv' style='cursor:pointer;'>advanced search</a> mode. " +
            "Please select which of the following searches you wish to run:<blockquote>";
      for (var i=0; i<items.length; i++) {
        var cItem = clean_text(items[i]);
        msg += "<a href='metagenomics.cgi?page=MetagenomeSearch&run_now=1&smode=1&type=" + types + "&text=" + cItem + "'>" + cItem + "</a>,&nbsp;&nbsp;";
      }
      msg += "</blockquote></p>";
    }
    \$("#dResult").html(msg);
    if ((msg == "") && (items.length == 1)) {
      if (cText.match(/^mgm\\d+\\.\\d+\$/)) {
        window.location = "?page=MetagenomeOverview&metagenome="+cText.substring(3);
      } else if (cText.match(/^mgp\\d+\$/)) {
        window.location = "?page=MetagenomeProject&project="+cText.substring(3);
      } else {
        execute_ajax( 'get_simple_table', 'dResult', param.join("&") );
      }
    }
  }
  function switch_mode( aMode ) {
    if (aMode == 1) {
      \$("#dAdvanced").hide();
      \$("#dSimple").show();
      \$("#SwitchSearchType").html("Advanced Search");
      \$("#tSimpleAll").val('');
    } else if (aMode == 2) {
      \$("#dSimple").hide();
      \$("#dAdvanced").show();
      \$("#SwitchSearchType").html("Simple Search");
      \$("#tQuery").html("<tr id='query1'>$adv_deflt</tr>");
      qList = ['query1'];
      qNum  = 1;
      \$("#query1 button[name='but_sub']").attr('disabled', true);
    }
  }
  function test_text( aText ) {
    if (aText == '') {
      return "<p><b style='color:red'>Empty text field detected. Please make sure all text fields are filled out.</b></p>";
    } else if (aText.length < 3) {
      return "<p><b style='color:red'>Search string '"+aText+"' is to short.  Please enter a longer query.</b></p>";
    } else {
      return "";
    }
  }
  function clean_text( aText ) {
    return \$.trim( aText.replace(/\\s+/g, ' ') );
  }
  $set_types
  $search_now
});
</script>
~ . $self->application->component('sAjax')->output;

  my $html = '';
  my $help = $self->app->component('help');
  $help->add_tooltip( 'match_help', 'Uncheck boxes to restrict the search to only values you are interested in.<br>This can be useful if you are searching on common terms.' );
  $help->add_tooltip( 'groupby_help', 'Unchecking this option will cause the search to display a row for every match to the metagenomes instead of aggregating them together.<br>Often this will result in thousands of matches in the case of protein and organism searches.' );
  $html .= $help->output();

  my @colors = ('#3674D9', '#52B95E', '#FF9933');
  $html .= "<div id='dSimple' style='padding-top:20px; float: left;'>";
  $html .= "<label for='tSimpleAll' style='font-size: 14px; font-weight:bold;'>Search for Metagenomes<br></label>";
  $html .= "<input id='tSimpleAll' type='text' placeholder='by metadata / MG-RAST id (name, biome, project name, 4441137.3), function or organism...' value='".$stext."' style='width:580px;' onkeyup='if (event.keyCode == 13) { document.getElementById(\"bSimpleAll\").click(); }'>";
  $html .= "&nbsp;&nbsp;<button type='button' id='bSimpleAll'>Search</button><br>";
  $html .= "<div style='padding-top: 5px; font:12px sans-serif;'>Match<span id='share_help' onmouseover='hover(event, \"match_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
  $html .= "&nbsp;&nbsp;<input type='checkbox' name='resType' id='metaSimple' checked/>&nbsp;<span style='font-weight: bold; color: ".$colors[0]."'>metadata / MG-RAST id</span>";
  $html .= "&nbsp;&nbsp;<input type='checkbox' name='resType' id='funcSimple' checked/>&nbsp;<span style='font-weight: bold; color: ".$colors[1]."'>function</span>";
  $html .= "&nbsp;&nbsp;<input type='checkbox' name='resType' id='orgSimple' checked/>&nbsp;<span style='font-weight: bold; color: ".$colors[2]."'>organism</span></div>";
  $html .= "</div>";
  $html .= "<div id='dAdvanced' style='padding-top:20px; visiblity: hidden; float: left;'>";
  $html .= "<label for='tAdvanced' style='font-size: 14px; font-weight:bold;'>Search for Metagenomes containing all the following condition(s):<br></label>";
  $html .= "<table id='tQuery'>".$adv_srch."</table>";
  $html .= "<fieldset style='width: 413px; margin-top: 10px; margin-bottom: 10px;'>";
  $html .= "<legend>Results options</legend>";
  $html .= "<input type='checkbox' id='showGroup' checked/>&nbsp;&nbsp;Group by metagenome<span id='share_help' onmouseover='hover(event, \"groupby_help\", " . $help->id . ")'><sup style='cursor: help;'>[?]</sup></span>";
  $html .= "</fieldset>";
  $html .= "<button id='bAdvanced'>Search</button> or <a id='SwitchSearchType' style='cursor:pointer;'>Simple Search</a>";
  $html .= "</div>";
  $html .= "<div class='clear' style='height: 20px;'></div><div class='clear' style='height: 25px;'></div>";
  $html .= "<div>";
  $html .= "<div style='margin:5px; padding: 20px; float:left; width:260; height:60px; border: 2px dashed ".$colors[0].";'>";
  $html .= "<label for='tSimpleMeta' style='font-weight:bold;'>Find by metadata / mg-rast id<br></label>";
  $html .= "<input id='tSimpleMeta' type='text' placeholder='MG-RAST id, name, biome, project name...' value='' style='width:260px;' onkeyup='if (event.keyCode == 13) { document.getElementById(\"bSimpleMeta\").click(); }'><br><button id='bSimpleMeta'>Search</button>";
  $html .= "</div>";
  $html .= "<div style='margin:5px; padding: 20px; float:left; width:260; height:60px; border: 2px dashed ".$colors[1].";'>";
  $html .= "<label for='tSimpleFunc' style='font-weight:bold;'>Find by function or functional category<br></label>";
  $html .= "<input id='tSimpleFunc' type='text' placeholder='BatE, 3.4.11.9, RNA Metabolism...' value='' style='width:260px;' onkeyup='if (event.keyCode == 13) { document.getElementById(\"bSimpleFunc\").click(); }'><br><button id='bSimpleFunc'>Search</button>";
  $html .= "</div>";
  $html .= "<div style='margin:5px; padding: 20px; float:left; width:260; height:60px; border: 2px dashed ".$colors[2].";'>";
  $html .= "<label for='tSimpleOrg' style='font-weight:bold;'>Find by organism<br></label>";
  $html .= "<input id='tSimpleOrg' type='text' placeholder='Firmicutes, Mobiluncus curtisii...' value='' style='width:260px;' onkeyup='if (event.keyCode == 13) { document.getElementById(\"bSimpleOrg\").click(); }'><br><button id='bSimpleOrg'>Search</button>";
  $html .= "</div>";
  $html .= "</div>"; 
  $html .= "<div class='clear' style='height: 25px;'></div>";
  $html .= "<div id='dResult'></div>";
  $html .= "<div class='clear' style='height: 15px;'></div>";

  return $scripts . $html;
}

sub get_simple_table {
  my ($self) = @_;

  my $hs = HTML::Strip->new();
  my $text = uri_unescape($self->app->cgi->param('text'));
  if ($text) {
      $text = $hs->parse($text);
  }
  my $types = $self->app->cgi->param('type') || "metadata,function,organism";
  my $table = $self->application->component('sResult');
  my $jobs  = $self->data('jobs');
  my $mgdb  = $self->data('mgdb');
  my $mgs   = [ keys %$jobs ];

  my %type_set = map {$_, 1} split(/,/, $types);
  my $tomany   = "<p><b style='color:red'>Your search request returned to many results.<br>Please try again with more specific criteria.</b></p>";
  my $show_md  = [['biome','feature','material','country','location','pi'], ['Biome','Feature','Material','Country','Location','PI']];
  my %type_map = map { $_->[0], $_->[1] } @{ $self->data('type') };
  my %meta_map = map { $_->[0], $_->[1] } @{ $self->data('meta') };
  my @data     = ();
  my $uniq_job = {};
  my $uniq_hit = {};

  if (exists $type_set{'function'}) {
    ### jobs function search
    my $ffuncs  = $self->search_annotation('function', [['name',$text,0,1]]);
    if(scalar(keys %$ffuncs) > 0) {
      my $fwhere  = $self->get_where_str(["id IN (".join(",", keys %$ffuncs).")"], 1);
      my $jd_func = $self->get_jobdata('function', $fwhere, $mgs, $ffuncs);
      foreach my $j ( keys %$jd_func ) {
        my $hits = {};
        foreach my $r ( @{$jd_func->{$j}} ) {
          $hits->{ $ffuncs->{$r} } = 1;
          $uniq_hit->{function}{ $ffuncs->{$r} } = 1;
        }
        $uniq_job->{$j}{function} = scalar(keys %$hits);
      }
    }
    ### jobs ontology search
    my $ofuncs = $self->search_annotation('ontology', [['name',$text,0,1]]);
    if(scalar(keys %$ofuncs) > 0) {
      my $owhere = $self->get_where_str(["id IN (".join(",", keys %$ofuncs).")"], 1);
      my $jd_ont = $self->get_jobdata('ontology', $owhere, $mgs, $ofuncs);
      foreach my $j ( keys %$jd_ont ) {
        my $hits = {};
        foreach my $r ( @{$jd_ont->{$j}} ) {
          $hits->{ $ofuncs->{$r} } = 1;
          $uniq_hit->{function}{ $ofuncs->{$r} } = 1;
        }
        $uniq_job->{$j}{function} += scalar(keys %$hits);
      }
    }
  }
  if (exists $type_set{'organism'}) {
    ### jobs organism search
    my $orgs   = $self->search_annotation('organism', [['name',$text,0,1]]);
    if(scalar(keys %$orgs) > 0) {
      my $where  = $self->get_where_str(["id IN (".join(",", keys %$orgs).")", "source=".$mgdb->_src_id->{'M5NR'}], 1);
      my $jd_org = $self->get_jobdata('organism', $where, $mgs, $orgs);
      foreach my $j ( keys %$jd_org ) {
        my $hits = {};
        foreach my $r ( @{$jd_org->{$j}} ) {
          $hits->{ $orgs->{$r} } = 1;
          $uniq_hit->{organism}{ $orgs->{$r} } = 1;
        }
        $uniq_job->{$j}{organism} = scalar(keys %$hits);
      }
    }
  }
  if (exists $type_set{'metadata'}) {
    ### metadata search
    my $md_jobs = $self->search_metadata([['value',$text,0,1]], $mgs);
    foreach my $j ( keys %$md_jobs ) {
      my $hits = {};
      foreach my $r ( @{$md_jobs->{$j}} ) {
	my $val = exists($r->{value}) ? $r->{value} : "";
	$hits->{$val} = 1;
	$uniq_hit->{metadata}{$val} = 1;
      }
      $uniq_job->{$j}{metadata} = scalar(keys %$hits);
    }
    ### jobcache search
    foreach my $j ( keys %$jobs ) {
      my $qtext = quotemeta($text);
      my $mg_id = $jobs->{$j}{metagenome_id};
      my $gname = $jobs->{$j}{name};
      my $pname = $jobs->{$j}{project} || '';
      if ($mg_id =~ /$qtext/i) {
	$uniq_job->{$j}{metadata} += 1;
	$uniq_hit->{metadata}{$mg_id} = 1;
      }
      if ($gname =~ /$qtext/i) {
	$uniq_job->{$j}{metadata} += 1;
	$uniq_hit->{metadata}{$gname} = 1;
      }
      if ($pname && ($pname =~ /$qtext/i)) {
	$uniq_job->{$j}{metadata} += 1;
	$uniq_hit->{metadata}{$pname} = 1;
      }
    }
  }
  
  if (scalar(keys %$uniq_job) > 0) {
    foreach my $j (keys %$uniq_job) {
      my $row = [ $j,
		  '<a href="?page=MetagenomeOverview&metagenome='.$jobs->{$j}{metagenome_id}.'">'.$jobs->{$j}{name}.'</a>',
		  $jobs->{$j}{metagenome_id},
		  $jobs->{$j}{project} ? '<a href="?page=MetagenomeProject&project='.$jobs->{$j}{project_id}.'">'.$jobs->{$j}{project}.'</a>' : '',
		  $jobs->{$j}{public} ];
      if (scalar(keys %type_set) > 1) {
	push @$row, join(", ", sort keys %{$uniq_job->{$j}});
      }
      my @counts = map { $uniq_job->{$j}{$_} } sort keys %{$uniq_job->{$j}};
      push @$row, join(", ", sort @counts);
      
      foreach my $t (@{$show_md->[0]}) {
	push @$row, $jobs->{$j}{$t};
      }
      push @data, $row;
    }
  }

  unless (@data > 0) { return "<p><b style='color:red'>No Metagenomes found for the above search criteria.</b></p>"; }

  my $hit_str = "Found " . scalar(keys %$uniq_job) . " metagenomes containing ";
  if (scalar(keys %type_set) > 1) {
    $hit_str .= "these unique matches:<br><table style='padding-left:20px;'>";
    foreach (sort keys %type_set) {
      $hit_str .= "<tr><td>" . (exists($uniq_hit->{$_}) ? scalar(keys %{$uniq_hit->{$_}}) : 0) . "</td><td>" . $type_map{$_} . "</td></tr>";
    }
    $hit_str .= "</table>";
  } else {
    $hit_str .= (exists($uniq_hit->{$types}) ? scalar(keys %{$uniq_hit->{$types}}) : 0) . " $types matches.";
  }

  my $cols = [ { name => 'Job Number', visible => 0, sortable => 1 },
	       { name => 'Metagenome', filter => 1, operator => 'like', sortable => 1 },
	       { name => 'MG-RAST ID', filter => 1, operator => 'like', visible  => 1 },
	       { name => 'Project'   , filter => 1, operator => 'combobox', sortable => 1 },
	       { name => 'Public'    , filter => 1, operator => 'combobox' } ];
  if (scalar(keys %type_set) > 1) {
    push @$cols, { name => 'Match Types', filter => 1, operator => 'combobox', sortable => 1 };
  }
  push @$cols, { name => 'Match Counts', sortable => 1 };

  foreach my $md ( @{$show_md->[1]} ) {
    my $col = { name => $md, filter => 1, operator => 'combobox', sortable => 1 };
    push @$cols, $col;
  }

  my $tid = $table->id();
  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->items_per_page(25);
  $table->show_select_items_per_page(1); 
  $table->show_column_select(1);
  $table->show_export_button({title => "download results table", strip_html => 1});
  $table->show_clear_filter_button(1);
  $table->other_buttons([ qq(<button onclick="var mgs = column_extract_data($tid,0,0,1); execute_ajax('get_mg_map','dResult2','mg_set='+mgs);">map metagenomes</button>), qq(<button onclick="var mgs = column_extract_data($tid,0,0,1); execute_ajax('get_mg_col','dResult2','mg_set='+mgs);">create collection</button>) ]);
  $table->columns($cols);
  $table->data(\@data);

  return "<div id='dResult2'></div><p>$hit_str</p>" . $table->output();
}

sub get_advanced_table {
  my ($self) = @_;

  my $hs  = HTML::Strip->new();
  my $cgi = $self->app->cgi;
  my $table = $self->application->component('sResult');
  my $qnum  = $cgi->param('qnum');
  my $show  = $cgi->param('show_match') || 0;
  my $jobs  = $self->data('jobs');
  my $mgdb  = $self->data('mgdb');
  my $tomany  = "<p><b style='color:red'>Your search request returned to many results.<br>Please try again with more specific criteria.</b></p>";
  my $empty   = "<p><b style='color:red'>No Metagenomes found for the above selected criteria.</b></p>";
  my $show_md = [['biome','feature','material','country','location','pi'], ['Biome','Feature','Material','Country','Location','PI']];
  my $max     = 0;
  my $limit   = $self->data('max_results');

  my $type_map  = {};
  my $hier_map  = {};
  my $extra_map = {};
  foreach my $t (@{ $self->data('type') }) {
    if ($t->[2]) {
      my %tmp = map { $_->[0], $_->[1] } @{ $self->data($t->[2]) };
      $hier_map->{$t->[0]}  = $t->[2];
      $extra_map->{$t->[0]} = \%tmp;
    }
    $type_map->{$t->[0]} = $t->[1];
  }

  ### parse cgi params
  my $c_order  = [];  # [ cat1, cat2, .. ] , based on mapping from type & extra
  my $searches = {};  # type => extra => [ [text, eql, has] ]

  foreach my $i (1..$qnum) {
    my $type  = $cgi->param("type_q$i");
    my $input = uri_unescape($cgi->param("input_q$i"));
    if ($input) {
        $input = $hs->parse($input);
    }
    my $extra = $cgi->param("extra_q$i") || $type;
    my ($eql, $has) = split(/_/, $cgi->param("match_q$i"));
    $hs->eof;
    
    if ($type eq "metadata") {
      if ($extra eq "all") {
	      push @$c_order, $extra_map->{$type}{all} . " " . $type_map->{$type};
      }
      else {
	      push @$c_order, $extra_map->{$type}{$extra};
      }
    }
    elsif ($type eq "function") {
      push @$c_order, $type_map->{$type};
      $extra = $type;
    }
    else {
      push @$c_order, $type_map->{$type} . " : " . $extra_map->{$type}{$extra};
    }
    push @{ $searches->{$type}{$extra} }, [$input, $eql, $has];
  }

  ## uniquify order
  my %seen = ();
  my @cats = ();
  foreach my $cat (@$c_order) {
    if (exists $seen{$cat}) { next; }
    push @cats, $cat;
    $seen{$cat} = 1;
  }

  my $results = {};  ### jobid => cat => { val }
  my $cur_mgs = [ keys %$jobs ];

  foreach my $type (keys %$searches) {
    if ($type eq 'metadata') {
      if (exists $searches->{$type}{all}) {
	    # search all metadata dbs using 'OR' matching
	    my $cat = $extra_map->{$type}{all} . " " . $type_map->{$type};
	    my $srch_info = $searches->{$type}{all};
	    my $to_search = $self->get_search_list({value => $srch_info});
	    my $md_data   = $self->search_metadata($to_search, $cur_mgs);
	    foreach my $j (keys %$md_data) {
	      foreach my $r (@{$md_data->{$j}}) {
	        my $name = $r->{cat} . ": " . $r->{tag};
	        if ($max > $limit) { return $tomany; }
	        $results->{$j}{$cat}{ "$name<br>" . $r->{value} } = 1;
	        $max += 1;
	      }
	    }
	    my %merge = map { $_, 1 } keys %$md_data;
	    foreach my $jc_item (('project', 'name', 'metagenome_id')) {
	      $to_search  = $self->get_search_list({$jc_item => $srch_info});
	      my $jc_data = $self->search_jobcache($to_search, $cur_mgs);
	      foreach my $j (keys %$jc_data) {
	        if ($max > $limit) { return $tomany; }
	        $results->{$j}{$cat}{ "$jc_item<br>" . $jc_data->{$j}{$jc_item} } = 1;
	        $max += 1;
	        $merge{$j} = 1;
	      }
	    }
	    @$cur_mgs = keys %merge;
	    unless ($cur_mgs && (@$cur_mgs > 0)) { return $empty; }
      }
      my %remaining = map { $_, $searches->{$type}{$_} } grep {$_ !~ /all/} keys %{$searches->{$type}};
      if (scalar(keys %remaining) > 0) {
	    my $to_search = $self->get_search_list($searches->{$type});
	    my %tag_set = map { $_->[0], 1 } @$to_search;
	    my $jdata = $self->search_jobcache($to_search, $cur_mgs);
	    foreach my $j (keys %$jdata) {
	      foreach my $t (keys %tag_set) {
	        next unless (exists($jdata->{$j}{$t}) && exists($extra_map->{$type}{$t}));
	        my $cat = $extra_map->{$type}{$t};
	        if ($max > $limit) { return $tomany; }
	        $results->{$j}{$cat}{ $jdata->{$j}{$t} } = 1;
	        $max += 1;
	      }
	    }
	    @$cur_mgs = keys %$jdata;
	    unless ($cur_mgs && (@$cur_mgs > 0)) { return $empty; }
      }
    }
    elsif ($type eq "function") {
      my $to_search = $self->get_search_list({'name' => $searches->{$type}{$type}});
      my $funcs = $self->search_annotation($type, $to_search);
      if(scalar(keys %$funcs) > 0) {
        my $where = $self->get_where_str(["id IN (".join(",", keys %$funcs).")"], 1);
        my $jdata = $self->get_jobdata($type, $where, $cur_mgs);
        foreach my $j (keys %$jdata) {
          foreach my $r (@{$jdata->{$j}}) {
            if ($max > $limit) { return $tomany; }
            $results->{$j}{ $type_map->{$type} }{ $funcs->{$r} } = 1;
            $max += 1;
          }
        }
        @$cur_mgs = keys %$jdata;
        unless ($cur_mgs && (@$cur_mgs > 0)) { return $empty; }
      }
    }
    elsif ($type eq "organism") {
      foreach my $tax (keys %{$searches->{$type}}) {
	    my $to_search = [];
	    my $name_map  = {};
	    my $org_data  = {};
	    if ($tax eq 'name') {
	      $to_search = $self->get_search_list({'name' => $searches->{$type}{$tax}});
	      $name_map  = $self->search_annotation($type, $to_search);
	    }
	    elsif ($tax eq 'ncbi_tax_id') {
	      my @taxs  = map { $_->[0] } @{$searches->{$type}{$tax}};
	      $name_map = $self->data('mgdb')->organisms_for_taxids(\@taxs);
	    }
	    else {
	      $to_search = $self->get_search_list({$tax => $searches->{$type}{$tax}});
	      $name_map  = $self->search_taxonomy($to_search, $tax);
	    }
        if (scalar(keys %$name_map) > 0) {
          my $cat    = $type_map->{$type} . " : " . $extra_map->{$type}{$tax};
          my $where  = $self->get_where_str(["id IN (".join(",", keys %$name_map).")", "source=".$mgdb->_src_id->{'M5NR'}], 1);
          $org_data  = $self->get_jobdata('organism', $where, $cur_mgs);
	      foreach my $j (keys %$org_data) {
	        foreach my $r (@{$org_data->{$j}}) {
	          if ($max > $limit) { return $tomany; }
	          $results->{$j}{$cat}{ $name_map->{$r} } = 1;
	          $max += 1;
	        }
	      }
        }
	    @$cur_mgs = keys %$org_data;
	    unless ($cur_mgs && (@$cur_mgs > 0)) { return $empty; }
      }
    }
    else {
      my $end = ($hier_map->{$type} eq 'hier2') ? "level4" : "level3";
      foreach my $lvl (keys %{$searches->{$type}}) {
	    my $to_search = [];
	    my $name_map  = {};
	    my $func_data = {};
	    if ($lvl eq $end) {
	      $to_search = $self->get_search_list({'name' => $searches->{$type}{$lvl}});
	      $name_map  = $self->search_annotation('ontology', $to_search);
	    }
	    else {
	      $to_search = $self->get_search_list({$lvl => $searches->{$type}{$lvl}});
	      $name_map  = $self->search_ontology($to_search, $lvl, $type);
	    }
	    if (scalar(keys %$name_map) > 0) {
	      my $cat = $type_map->{$type} . " : " . $extra_map->{$type}{$lvl};
	      my $where  = $self->get_where_str(["id IN (".join(",", keys %$name_map).")", "source=".$mgdb->_src_id->{$type}], 1);
          $func_data = $self->get_jobdata('ontology', $where, $cur_mgs);
	      foreach my $j (keys %$func_data) {
	        foreach my $r (@{$func_data->{$j}}) {
	          if ($max > $limit) { return $tomany; }
	          $results->{$j}{$cat}{ $name_map->{$r} } = 1;
	          $max += 1;
	        }
	      }
        }
	    @$cur_mgs = keys %$func_data;
	    unless ($cur_mgs && (@$cur_mgs > 0)) { return $empty; }
      }
    }
  }

  ## keep only jobs that hit all search criteria
  my %hmap  = ();
  my %final = ();
  JOB: foreach my $j (@$cur_mgs) {
      my @tmp = ();
      foreach my $c (@cats) {
	unless (exists($results->{$j}{$c}) && (scalar(keys %{$results->{$j}{$c}}) > 0)) {
	  $results->{$j} = {};
	  next JOB;
	}
	foreach my $t (keys %{$results->{$j}{$c}}) {
	  $hmap{$c}{$t} = 1;
	}
	push @tmp, [ keys %{$results->{$j}{$c}} ];
      }
      $final{$j} = \@tmp;
      $results->{$j} = {};
    }

  my @hits    = map { [scalar(keys %{$hmap{$_}}), $_] } @cats;
  my $hit_str = "Found " . scalar(keys %final) . " metagenomes containing ";
  if (@hits > 1) {
    $hit_str .= "these unique matches:<br><table style='padding-left:20px;'>";
    foreach (@hits) {
      $hit_str .= qq(<tr><td>$_->[0]</td><td>$_->[1]</td></tr>);
    }
    $hit_str .= "</table>";
  } else {
    $hit_str .= qq($hits[0][0] $hits[0][1] matches.);
  }
  %hmap = ();
  
  ## build data with all category combinations
  $max = 0;
  my @data = ();
  foreach my $j (keys %final) {
    my $job = $jobs->{$j};
    my $num = scalar @{ $final{$j} };
    my @set = ();

    if (! $show) {
      my $row = [ $j,
		  '<a href="?page=MetagenomeOverview&metagenome='.$job->{metagenome_id}.'">'.$job->{name}.'</a>',
		  $job->{metagenome_id},
		  $job->{project} ? '<a href="?page=MetagenomeProject&project='.$job->{project_id}.'">'.$job->{project}.'</a>' : '',
		  $job->{public} ];
      foreach my $t ( @{$show_md->[0]} ) {
	push @$row, $job->{$t};
      }
      push @data, $row;
      next;
    }

    if    ($num == 1) { @set = map {[$_]} @{ $final{$j}[0] }; }
    elsif ($num > 1)  { @set = $self->combinations( $final{$j} ); }
    $final{$j} = [];

    foreach my $line ( @set ) {
      if ($max > $limit) { return $tomany; }
      my $row = [ $j,
		  '<a href="?page=MetagenomeOverview&metagenome='.$job->{metagenome_id}.'">'.$job->{name}.'</a>',
		  $job->{metagenome_id},
		  $job->{project} ? '<a href="?page=MetagenomeProject&project='.$job->{project_id}.'">'.$job->{project}.'</a>' : '',
		  $job->{public},
		  @$line ];
      foreach my $t ( @{$show_md->[0]} ) {
	push @$row, $job->{$t};
      }
      push @data, $row;
      $max += 1;
    }
  }
  
  unless (@data > 0) { return $empty; }

  ## create table
  my $cols = [ { name => 'Job'       , visible => 0, sortable => 1 },
	       { name => 'Metagenome', filter => 1, operator => 'like', sortable => 1 },
	       { name => 'ID'        , filter => 1, operator => 'like', visible  => 0 },
	       { name => 'Project'   , filter => 1, operator => 'combobox', sortable => 1 },
	       { name => 'Public'    , filter => 1, operator => 'combobox' }
	     ];
  if ($show) {
    foreach my $cat ( @cats ) {
      push @$cols, { name => $cat, filter => 1, operator => 'like', sortable => 1 };
    }
  }
  foreach my $md ( @{$show_md->[1]} ) {
    my $col = { name => $md, filter => 1, operator => 'combobox', visible => ($show ? 0 : 1) };
    push @$cols, $col;
  }
  
  my $tid = $table->id();
  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->items_per_page(25);
  $table->show_select_items_per_page(1); 
  $table->show_column_select(1);
  $table->show_export_button(1, {title => 'download results table', strip_html => 1});
  $table->show_clear_filter_button(1);
  $table->other_buttons([ qq(<button onclick="var mgs = column_extract_data($tid,0,0,1); execute_ajax('get_mg_map','dResult2','mg_set='+mgs);">map metagenomes</button>), qq(<button onclick="var mgs = column_extract_data($tid,0,0,1); execute_ajax('get_mg_col','dResult2','mg_set='+mgs);">create collection</button>) ]);
  $table->columns($cols);

  $table->data(\@data);
  return "<div id='dResult2'></div><p>$hit_str</p>" . $table->output();
}

## recursive loop returns a 2d array of all combinations of original 2d array
sub combinations {
  my ($self, $list) = @_;

  unless ($list && @$list) { return; }

  my @array = grep { $_ ne '' } @{ shift @$list };
  my @subs  = $self->combinations($list);
  if (! @subs) {
    return map { [$_] } @array;
  }
  
  my @out;
  foreach my $item ( @array ) {
    foreach my $sub ( @subs ) {
      push @out, [ $item, @$sub ];
    }
  }
  return @out;
}

sub get_mg_map {
  my ($self) = @_;

  my $jobs = $self->data('jobs');
  my $set  = $self->app->cgi->param('mg_set') || "";
  my %mgs  = map { $_, 1 } split(/~/, $set);
  my $locs = {};
  my @data = ();

  foreach my $j (keys %mgs) {
    my $bio = $jobs->{$j}{biome};
    my $lat = $jobs->{$j}{latitude};
    my $lng = $jobs->{$j}{longitude};
    unless (defined($lat) && defined($lng)) { next; }
    my $key = sprintf("%.0f",$lat) . "~" . sprintf("%.0f",$lng);
    push @{ $locs->{$key} }, { id => $jobs->{$j}{metagenome_id}, name => $jobs->{$j}{name}, lat => $lat, lng => $lng, biome => $bio };
  }

  if (scalar(keys %$locs) == 0) {
    return "<p><b style='color:red'>None of the selected metagenomes contain geographic coordinates.</b></p>";
  }
  
  foreach my $key (keys %$locs) {
    my $num   = 0;
    my $td_c  = "class='table_row'";
    my $names = join(", ", map {$_->{id}} @{$locs->{$key}});
    my $table = "<p><table class='table_table'>";
    foreach my $mg ( @{$locs->{$key}} ) {
      $num += 1;
      my $tr_c = (($num % 2) == 0) ? "class='even_row'" : "class='odd_row'";
      $table .= "<tr $tr_c><td $td_c>".$mg->{name}."</td><td $td_c>".$mg->{id}."</td><td $td_c>".$mg->{lat}."&deg;, ".$mg->{lng}."&deg;</td><td $td_c>".$mg->{biome}."</td></tr>";
    }
    $table .= "</table></p>";
    push @data, "$key~$names~$table";
  }

  my $html = qq(
<div id='map_region'>
  <button onclick="document.getElementById('map_region').style.display = 'none';">Remove Map</button>
  <div id='map_canvas' style='width:100%; height:100%'></div>
  <div id='map_data' style='display:none;'>) . join("^", @data) . qq(</div>
  <img src='./Html/clear.gif' onload="create_google_map('map_canvas', 'map_data');">
</div>);
  return $html;
}

sub get_mg_col {
  my ($self) = @_;
  my $set = $self->app->cgi->param('mg_set') || "";

  return qq(
<table><tr>
  <td>Enter Collection Name:</td>
  <td style='padding-left:10px'>
    <input id='col_name' name='col_name' type='text' value='' /></td>
  <td style='padding-left:10px'>
    <button onclick="var name = document.getElementById('col_name').value; execute_ajax('set_mg_col','dResult2','mg_set=$set&col_name='+name);">Submit</button></td>
</tr></table>
);
}

sub set_mg_col {
  my ($self) = @_;

  my $app  = $self->application;
  my $user = $app->session->user;
  my $set  = $app->cgi->param('mg_set') || "";
  my $col  = $app->cgi->param('col_name') || "";
  my %ids  = map { $_, 1 } split(/~/, $set);

  if (! $user) {
    return "<p><b style='color:red'>Must be logged in to create collection.</b></p>";
  }
  elsif ((! $set) || (scalar(keys %ids) == 0)) {
    return "<p><b style='color:red'>No metagenomes selected for collection.</b></p>";
  }
  elsif (! $col) {
    return "<p><b style='color:red'>No name entered for collection.</b></p>";
  }

  my $num = 0;
  foreach my $id (keys %ids) {
    my $job = $app->data_handle('MGRAST')->Job->init({ metagenome_id => $id });
    unless(ref($job)) {
      next;
    }
    my $jid = $job->job_id;

    my $existing = $app->dbmaster->Preferences->get_objects( { application => $app->backend,
							       user => $user,
							       name => 'mgrast_collection',
							       value => $col."|".$jid } );
    unless (scalar(@$existing)) {
      $num += 1;
      $app->dbmaster->Preferences->create( { application => $app->backend,
					     user => $user,
					     name => 'mgrast_collection',
					     value => $col."|".$jid } );
    }
  }

  return "<p><b>Collection '$col' of $num metagenomes created.</b></p>";
}

### search functions: queries are all 'AND'
# $to_search = [ [column (string), text (string), equal (bool), has (bool)] ]

sub search_jobcache {
  my ($self, $to_search, $jobs) = @_;
  
  my %jdata = %{ $self->data('jobs') };
  
  if ($jobs && (@$jobs > 0)) {
    my %tmp = ();
    foreach my $j (@$jobs) {
      if (exists $jdata{$j}) { $tmp{$j} = $jdata{$j}; }
    }
    %jdata = %tmp;
  }
  foreach my $srch (@$to_search) {
    my ($cat, $text, $eql, $has) = @$srch;
    my %tmp = ();
    foreach my $j (keys %jdata) {
      unless (exists $jdata{$j}{$cat}) { next; }
      my $val = $jdata{$j}{$cat};
      next unless (defined($val) && ($val =~ /\S/));
      if ($eql == 2) {
	my @rng = split(/_/, $text);
	if (($val =~ /^\s*([+-]?\d*\.?\d+)/) && (@rng == 2)) {
	  my $num = $1 * 1.0;
	  if    ($has && ($rng[0] <= $num) && ($num <= $rng[1]))   { $tmp{$j} = $jdata{$j}; }
	  elsif ((! $has) && ($num < $rng[0]) && ($rng[1] > $num)) { $tmp{$j} = $jdata{$j}; }
	}
      }
      elsif ($eql     && $has     && ($val eq $text))    { $tmp{$j} = $jdata{$j}; }
      elsif ($eql     && (! $has) && ($val ne $text))    { $tmp{$j} = $jdata{$j}; }
      elsif ((! $eql) && $has     && ($val =~ /$text/i)) { $tmp{$j} = $jdata{$j}; }
      elsif ((! $eql) && (! $has) && ($val !~ /$text/i)) { $tmp{$j} = $jdata{$j}; }
    }
    %jdata = %tmp;
  }
  return \%jdata;
}

sub search_metadata {
  my ($self, $to_search, $jobs) = @_;

  my $db_hdl   = $self->app->data_handle('MGRAST')->db_handle;
  my $all_jobs = $self->data('jobs');
  my $data = {};
  my $wstr = '';
  if ($to_search && (@$to_search > 0)) {
    my @where = map { $self->get_search_str('mysql', $_->[0], $_->[1], $_->[2], $_->[3]) } @$to_search;
    $wstr = $self->get_where_str(\@where);
  }
  my $cdata = {};
  my $pdata = {};
  foreach my $row (@{$db_hdl->selectall_arrayref("SELECT collection, tag, value FROM MetaDataEntry".$wstr)}) {
    next unless ($row->[2] && ($row->[2] =~ /\S/));
    push @{ $cdata->{$row->[0]} }, { tag => $row->[1], value => $row->[2] };
  }
  foreach my $row (@{$db_hdl->selectall_arrayref("SELECT project, tag, value FROM ProjectMD".$wstr)}) {
    next unless ($row->[2] && ($row->[2] =~ /\S/));
    push @{ $pdata->{$row->[0]} }, { tag => $row->[1], value => $row->[2], cat => 'project' };
  }

  my @search_jobs = ($jobs && (@$jobs > 0)) ? @$jobs : keys %$all_jobs;
  foreach my $j (@search_jobs) {
    if (exists $pdata->{$all_jobs->{$j}{_id_project}}) {
      push @{ $data->{$j} }, @{ $pdata->{$all_jobs->{$j}{_id_project}} };
    }
    if (exists $cdata->{$all_jobs->{$j}{_id_sample}}) {
      map { $_->{cat} = 'sample' } @{ $cdata->{$all_jobs->{$j}{_id_sample}} };
      push @{ $data->{$j} }, @{ $cdata->{$all_jobs->{$j}{_id_sample}} };
    }
    if (exists $cdata->{$all_jobs->{$j}{_id_library}}) {
      map { $_->{cat} = 'library' } @{ $cdata->{$all_jobs->{$j}{_id_library}} };
      push @{ $data->{$j} }, @{ $cdata->{$all_jobs->{$j}{_id_library}} };
    }
    if (exists $cdata->{$all_jobs->{$j}{_id_ep}}) {
      map { $_->{cat} = 'enviroment' } @{ $cdata->{$all_jobs->{$j}{_id_ep}} };
      push @{ $data->{$j} }, @{ $cdata->{$all_jobs->{$j}{_id_ep}} };
    }
  }
  return $data;
  # hash: job_id => [ {tag=>'tag', value=>'value', cat=>'category'} ]
}

sub get_jobdata {
  my ($self, $type, $where, $jobs) = @_;

  my $filter_jobs = 0;
  my $mgdb = $self->data('mgdb');
  my $max  = $self->data('max_results');
  my $data = {};
  my $jmap = {};
      
  if ($jobs && (@$jobs > 0)) {
    $filter_jobs = 1;
    %$jmap = map {$_, 1} @$jobs;
  }

  my $num = 0;
  my $sql = "SELECT job, id FROM ".$mgdb->_jtbl->{$type}.$where." AND ".$mgdb->_qver;
  foreach my $row (@{ $mgdb->_dbh->selectall_arrayref($sql) }) {
    if ($filter_jobs && (! exists $jmap->{$row->[0]})) { next; }
    if ($num >= $max) { last; }
    push @{$data->{$row->[0]}}, $row->[1];
    $num += 1;
  }
  return $data;
}

sub search_annotation {
  my ($self, $type, $to_search) = @_;
  
  my $mgdb  = $self->data('mgdb');
  my $data  = {};
  my $where = [];
  if ($to_search && (@$to_search > 0)) {
    @$where = map {$self->get_search_str('psql', $_->[0], $_->[1], $_->[2], $_->[3])} @$to_search;
  }
  
  my $sql  = "SELECT _id, name FROM ".$mgdb->_atbl->{$type}.$self->get_where_str($where);
  my $rows = $mgdb->_dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], $_->[1] } @$rows;
  }
  return $data;  # ann_id => ann_name
}

sub search_taxonomy {
  my ($self, $to_search, $tax) = @_;

  my $data  = {};
  my $where = [];
  if ($to_search && (@$to_search > 0)) {
    @$where = map {$self->get_search_str('psql', $_->[0], $_->[1], $_->[2], $_->[3])} @$to_search;
  }
  push @$where, "ncbi_tax_id IS NOT NULL";

  my $sql  = "SELECT _id, $tax FROM organisms_ncbi".$self->get_where_str($where);
  my $rows = $self->data('mgdb')->_dbh->selectall_arrayref($sql);
  if ($rows && (@$rows > 0)) {
    %$data = map { $_->[0], $_->[1] } @$rows;
  }
  return $data;  # org_id => tax_level_name
}

sub search_ontology {
  my ($self, $to_search, $lvl, $type) = @_;
  
  my %data  = ();
  my ($idx) = $lvl =~ /(\d)$/;  ## index of level is level# - 1
  my $ontol = $self->data('mgdb')->get_hierarchy('ontology', $type, undef, 1);

  foreach my $srch (@$to_search) {
    my ($lvl, $text, $eql, $has) = @$srch;
    foreach my $id (keys %$ontol) {
      my $node = $ontol->{$id}->[$idx-1];  # index of level is level# - 1
      my $func = $ontol->{$id}->[-1];      # func name is last in list
      if    (($type eq 'Subsystems') && ($idx == 3))      { $text =~ s/\s+/_/g; }
      if    ($eql     && $has     && ($node eq $text))    { $data{$id} = $node; }
      elsif ($eql     && (! $has) && ($node ne $text))    { $data{$id} = $node; }
      elsif ((! $eql) && $has     && ($node =~ /$text/i)) { $data{$id} = $node; }
      elsif ((! $eql) && (! $has) && ($node !~ /$text/i)) { $data{$id} = $node; }
    }
  }
  return \%data;  # func_id => node_level_name
}

### helper functions

sub get_user_jobs {
  my ($self, $mgs) = @_;

  my $user   = $self->app->session->user;
  my $mgrast = $self->app->data_handle('MGRAST');
  my $data   = {};
  map { $data->{$_->{job_id}} = $_ } @{ $mgrast->Job->fetch_browsepage_viewable($user, $mgs) };

  my $sql = "SELECT parent, _id FROM MetaDataCollection WHERE type='ep' AND parent IS NOT NULL";
  my $tmp = $mgrast->db_handle->selectall_arrayref($sql);
  my %eps = map { $_->[0], $_->[1] } @$tmp;

  $sql = "SELECT job_id, primary_project, sample, library FROM Job WHERE job_id IN (".join(",", keys %$data).")";
  $tmp = $mgrast->db_handle->selectall_arrayref($sql);
  foreach my $row (@$tmp) {
    last;
    $data->{$row->[0]}{_id_project} = $row->[1] ? $row->[1] : 0;
    $data->{$row->[0]}{_id_sample}  = $row->[2] ? $row->[2] : 0;
    $data->{$row->[0]}{_id_library} = $row->[3] ? $row->[3] : 0;
    $data->{$row->[0]}{_id_ep} = exists($eps{$data->{$row->[0]}{_id_sample}}) ? $eps{$data->{$row->[0]}{_id_sample}} : 0;
  }
  return $data;
}

sub get_unique_job_info {
  my ($self, $item) = @_;

  my $set = {};
  my $all_jobs = $self->data('jobs');
  map { $set->{ $all_jobs->{$_}{$item} } = 1 }
    grep { exists($all_jobs->{$_}{$item}) && defined($all_jobs->{$_}{$item}) && ($all_jobs->{$_}{$item} ne '') }
      keys %$all_jobs;
  return [ sort keys %$set ];
}

sub get_where_str {
  my ($self, $items, $no_max) = @_;

  my @text;
  unless ($items && (@$items > 0)) { return ""; }
  foreach my $i (@$items) {
    if ($i && ($i =~ /\S/)) {
      push @text, $i;
    }
  }
  my $max = " LIMIT " . $self->data('max_results');

  if (@text == 1) {
    return " WHERE " . $text[0] . ($no_max ? '' : $max);
  } elsif (@text > 1) {
    return " WHERE " . join(" AND ", @text) . ($no_max ? '' : $max);
  } else {
    return $no_max ? '' : $max;
  }
}

sub get_search_str {
  my ($self, $db, $col, $txt, $eql, $has) = @_;

  unless ($col && $txt) { return ""; }

  $txt =~ s/\\//g;

  my $qtxt = '';
  if ($db eq 'psql') {
      $qtxt = $self->data('mgdb')->_dbh->quote($txt);
  } elsif ($db eq 'mysql') {
      $qtxt = $self->data('mgdb')->_jcache->quote($txt);
  } else {
      return "";
  }
  if (length($qtxt)) { $qtxt = substr($qtxt, 1, length($qtxt) - 2); }
  
  if ($eql == 2) {
    my @rng = split(/_/, $txt);
    if (@rng != 2) { return ""; }
    if ($has)      { return "$col BETWEEN $rng[0] AND $rng[1]"; }
    else           { return "$col NOT BETWEEN $rng[0] AND $rng[1]"; }
  }
  elsif ($eql     && $has)     { return "$col = '$qtxt'"; }
  elsif ($eql     && (! $has)) { return "$col != '$qtxt'"; }
  elsif ((! $eql) && $has)     { return ($db eq 'psql') ? "$col ILIKE '$qtxt\%'" : "$col LIKE '\%$qtxt\%'"; }
  elsif ((! $eql) && (! $has)) { return ($db eq 'psql') ? "$col NOT ILIKE '$qtxt\%'" : "$col NOT LIKE '\%$qtxt\%'"; }
}

sub get_advanced_search {
  my ($self, $type, $match, $text, $extra, $extra_map) = @_;
  
  my $d_txt = $text || "";
  my $style = "style='padding-left:10px'";
  my $match_type = "text";
  my $input_html = "<input name='txt_adv' type='text' value='$d_txt'/>";
  my $extra_html = "";
  my $extra_msg  = "";

  if ($type) {
    my @extras = map { $_->[2] } grep { $_->[0] eq $type } @{ $self->data('type') };
    if ($extras[0] && (@extras == 1)) {
      $extra_html = $self->build_select("sel_" . $extras[0], $self->data($extras[0]), $extra);
      $extra_msg  = "within";
      if ($extra) {
	my @e = grep { $_->[0] eq $extra } @{ $self->data($extras[0]) };
	if ((@e == 1) && (scalar(@{$e[0]}) == 3) && (exists $self->data('match')->{$e[0][2]})) {
	  $match_type = $e[0][2];
	}
      }
    }
  }
  if ($text && ($match_type eq 'range')) {
    my @rngs    = split(/_/, $text);
    if (@rngs == 2) {
      $input_html = "<input name='rng1_adv' type='text' value='$rngs[0]' size='7'/>&nbsp;to&nbsp;<input name='rng2_adv' type='text' value='$rngs[1]' size='7'/>";
    }
  } elsif ($extra && ($match_type eq 'select')) {
    if (exists $extra_map->{$type}{$extra}) {
      $input_html = $self->build_select("sel_adv", $extra_map->{$type}{$extra}, $text);
    }
  }

  my $html = "<td>" . $self->build_select("sel_type", $self->data('type'), $type) . "</td>" .
             "<td $style>" . $self->build_select("sel_match", $self->data('match')->{$match_type}, $match) . "</td>" .
	     "<td $style name='input_adv'>$input_html</td>" .
             "<td $style>$extra_msg</td>" .
	     "<td $style name='extra'>$extra_html</td>" .
	     "<td $style><button name='but_add'><b>+</b></button></td>" .
	     "<td $style><button name='but_sub'><b>-</b></button></td>";

  return $html;
}

sub build_select {
  my ($self, $name, $list, $sel) = @_;

  my $html = "<select name='$name'>";
  foreach (@$list) {
    if (ref($_)) {
      my $title = (@$_ > 2) ? qq( title='$_->[2]') : "";
      if ($sel && ($sel eq $_->[0])) {
	$html .= qq(<option value='$_->[0]'$title selected='selected'>$_->[1]</option>);
      } else {
	$html .= qq(<option value='$_->[0]'$title>$_->[1]</option>);
      }
    } else {
      if ($sel && ($sel eq $_)) {
	$html .= qq(<option value='$_' selected='selected'>$_</option>);
      } else {
	$html .= qq(<option value='$_'>$_</option>);
      }
    }    
  }
  return $html . "</select>";
}

sub get_search_list {
  my ($self, $set) = @_;

  my $to_search = [];
  foreach my $cat ( keys %$set ) {
    foreach my $srch ( @{$set->{$cat}} ) {
      push @$to_search, [$cat, @$srch];
    }
  }
  return $to_search;
}

sub require_css {
        return [ "$Conf::cgi_url/Html/bootstrap.min.css" ];
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/MetagenomeSearch.js" ];
}
