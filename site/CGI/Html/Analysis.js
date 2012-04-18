var curr_tab_num = 2;

function remove_tab (num) {
  var h = document.getElementById('tab_title_'+num);
  var t = document.getElementById('tab_div_'+num);
  h.parentNode.removeChild(h);
  t.parentNode.removeChild(t);
}

function activate_tab (num) {
  var headers = document.getElementsByName('tab_title');
  var bodys = document.getElementsByName('tab_div');
  if (document.getElementById('tab_title_'+num) == null) {
    if (headers.length) {
      num = parseInt(headers[0].id.substr(headers[0].id.lastIndexOf("_")+1));
    } else {
      return false;
    }
  }
  for (i=0; i<headers.length; i++) {
    headers[i].className = 'inactive_disp';
    bodys[i].className = 'inactive_disp';
  }
  document.getElementById('tab_title_'+num).className = 'active_disp';
  document.getElementById('tab_div_'+num).className = 'active_disp';
} 

function parse_data () {
  var data_string = document.getElementById('phylogenetic_metabolic_data').value;
  var data_array = new Array();
  var line_array = data_string.split("##");
  for (i=0; i<line_array.length; i++) {
    data_array[data_array.length] = line_array.split("||");
  }
  cabinet['phylogenetic_metabolic'] = data_array;
}

function mod_title (td) {
  var curr = td.firstChild.innerHTML;
  if (curr.substr(0, 6) != "<input") {
    td.firstChild.innerHTML = "<input id='mod_title' type='text' value='"+curr+"' style='border: none;' title='press enter to confirm, esc to cancel' onkeypress='check_mod_title(event, this, \""+curr+"\");'>";
    document.getElementById('mod_title').focus();
  }
}

function check_mod_title (e, input, orig) {
  if (e.keyCode == 13) {
    if (input.value == "") {
      input.parentNode.innerHTML = orig;
    } else {
      input.parentNode.innerHTML = input.value;
    }
    return false;
  } else {
    if (e.keyCode == 27) {
      input.parentNode.innerHTML = orig;
      return false;
    } else {
      return true;
    }
  }
}

function choose_tool (tool, params) {
  var links = document.getElementsByName('tool_entry');
  for (i=0; i<links.length; i++) {
    if (links[i].className == 'active_tool') {
      links[i].className = 'inactive_tool';
      links[i].innerHTML = links[i].innerHTML.substr(1);
    }
  }
  var act = document.getElementById(tool+"_tool");
  act.innerHTML = "&raquo;" + act.innerHTML;
  act.className = 'active_tool';

  if (tool == 'buffer') {
    show_buffer_info();
  } else {
    if (! params) {
      params = 'metagenome='+document.getElementById('metagenome').value;
    }
    if ((tool != 'recruitment_plot') && document.getElementById('list_select_list_b_0')) {
      var list = document.getElementById('list_select_list_b_0');
      for (i=0; i<list.options.length; i++) {
	params += '&comparison_metagenomes='+list.options[i].value;
      }
    }
    execute_ajax(tool+'_select', 'select', params);
  }
  return false;
}

function load_tabs () {
  var all_tabs = document.getElementById('buffer_space').childNodes;
  for (h=0;h<all_tabs.length;h++) {
    var name = all_tabs[h].firstChild.innerHTML;
    var content = all_tabs[h].lastChild.innerHTML;
    var id = curr_tab_num;
    var header = document.createElement("td");
    header.innerHTML = "<span>"+name+"</span><img src='./Html/mg-logout.png' style='width: 12px; height: 12px; position: relative; top: -6px; right: -7px; border-left: 1px solid #E6E5D3; border-bottom: 1px solid #E6E5D3;' onclick='remove_tab(\""+id+"\");'>";
    header.setAttribute("class", "inactive_disp");
    header.setAttribute("id", "tab_title_"+id);
    header.setAttribute("onclick", "activate_tab('"+id+"')");
    header.setAttribute("title", "double-click to change title");
    header.setAttribute("ondblclick", "mod_title(this);");
    header.setAttribute("name", "tab_title");
    
    var tab = document.createElement("div");
    tab.setAttribute("class", "inactive_disp");
    tab.setAttribute("id", "tab_div_"+id+"");
    tab.setAttribute("name", "tab_div");
    tab.innerHTML = content;

    document.getElementById("tabs_table").insertBefore(header, document.getElementById("tabs_table").lastChild);
    document.getElementById("display").appendChild(tab);
    activate_tab(id);
    curr_tab_num++;
  }
  document.getElementById("buffer_space").innerHTML = "";
}

function buffer_data (source, id, selector, dataloc, mgloc, srcloc, abuloc) {
  var data_buffer = document.getElementById('data_buffer');
  var buffer_max  = 35000;
  
  if (source == 'table') {
    var mg_ids = new Array();
    var row_ids = new Array();
    var md5s = new Array();
    var src_names = new Array();
    var source_in_table = 0;
    
    if (srcloc.match(/^\d+$/)) {
      source_in_table = 1;
    }

    var data_index;
    for (i=0;i<table_list.length;i++) {
      if (id == table_list[i]) {
	data_index = i;
      }
    }
    var inf = "<table><tr>";
    for (h=0; h<selector; h++) {
      if (table_visible_columns[data_index][h] && table_visible_columns[data_index][h] != "0") {
	inf += "<th>"+document.getElementById('colname_'+id+'_col_'+(h+1)).innerHTML + "</th>";
      }
    }
    inf += "</tr>";
    var select_data = table_input_columns_data[data_index];
    var found_data = 0;
    for (i=0; i<select_data.length; i++) {
      if (select_data[i][selector] == 1) {
	found_data = 1;
	row_ids[i] = 1;
	document.getElementById(id+"_"+selector+"_"+i).checked = 0;
	table_input_columns_data[data_index][i][selector] = 0;
      }
    }
    var fragment_abundance = 0;
    var data_array = table_filtered_data[data_index]; 
    for (i=0;i<data_array.length;i++) {
      if (row_ids[data_array[i][data_array[i].length - 1]]) {
	mg_ids[data_array[i][mgloc]] = 1;
	if (abuloc) {
	  fragment_abundance += parseInt(data_array[i][abuloc].replace(HTML_REPLACE, ''));
	}
	if (source_in_table) {
	  src_names[data_array[i][srcloc]] = 1;
	}
	var curr_md5s = data_array[i][dataloc].split(";");
	for (h=0; h<curr_md5s.length; h++) {
	  if (md5s[curr_md5s[h]]) {
	    md5s[curr_md5s[h]]++;
	  } else {
	    md5s[curr_md5s[h]] = 1;
	  }
	}
	inf += "<tr>";
	for (h=0; h<selector; h++) {
	  if (table_visible_columns[data_index][h] && table_visible_columns[data_index][h] != "0") {
	    inf += "<td>"+data_array[i][h] + "</td>";
	  }
	}
	inf += "</tr>";
      }
    }
    inf += "</table>";

    if (found_data) {
      document.getElementById('buffer_info').innerHTML = inf;
      var md5array = new Array();
      var tot_prots = 0;
      for (i in md5s) {
	md5array[md5array.length] = i;
	tot_prots += md5s[i];
      }
      var num_md5s = md5array.length;
      if (num_md5s > buffer_max) {
        alert('You selected too many unique features ('+num_md5s+').\nPlease select less than '+buffer_max+' unique features.');
        return;
      }

      var abu_num = "";
      if (abuloc) {
	abu_num = ', representing '+fragment_abundance+' reads';
      }

      data_buffer.innerHTML = md5array.join(";");
      alert(num_md5s + ' unique features'+abu_num+' stored in workbench');

      document.getElementById('tab_title_1').innerHTML = "<span>Workbench ("+num_md5s+" Features)</span>";

      var mgidarray = new Array();
      for (i in mg_ids) {
	mgidarray[mgidarray.length] = i;
      }
      document.getElementById('buffer_mgids').value = mgidarray.join(";");

      if (source_in_table) {
	var sourcearray = new Array();
	for (i in src_names) {
	  sourcearray[sourcearray.length] = i;
	}
	document.getElementById('buffer_srcs').value = sourcearray.join(";");
	document.getElementById('fasta_source').innerHTML = build_opts(sourcearray.join(";"));
      } else {
	document.getElementById('buffer_srcs').value = srcloc;
	document.getElementById('fasta_source').innerHTML = build_opts(srcloc);
      }

      document.getElementById('buffer_info').innerHTML = "<p>The workbench contains "+num_md5s+" unique features.<br><br>They were selected from the following table lines:</p>" + document.getElementById('buffer_info').innerHTML;
      document.getElementById('wb_fasta').style.display = "";

      var numbaks = document.getElementById('backup_buffer').childNodes.length;
      var bak = "<div id='bak_buf_"+numbaks+"'>";
      bak += "<span>"+data_buffer.innerHTML+"</span>";
      bak += "<span>"+document.getElementById('buffer_mgids').value+"</span>";
      bak += "<span>"+document.getElementById('buffer_info').innerHTML+"</span>";
      bak += "<span>"+document.getElementById('tab_title_1').innerHTML+"</span>";
      bak += "<span>"+document.getElementById('buffer_srcs').value+"</span>";
      bak += "</div>";
      document.getElementById('hits_div').innerHTML = "";
      document.getElementById('backup_buffer').innerHTML += bak;
      document.getElementById('buffer_activators').innerHTML += "<input type='radio' name='backupselector' onclick='activate_backup("+numbaks+");' checked=checked>&nbsp;"+num_md5s+" features&nbsp;&nbsp;";
    } else {
      alert("you did not select any features");
    }
  }

  if (source == 'barchart') {
    var num_md5s = document.getElementById(id+'_md5s').value.split(";").length;
    if (num_md5s > buffer_max) {
      alert('You selected too many unique features ('+num_md5s+').\nPlease select less than '+buffer_max+' unique features.');
      return;
    }
    data_buffer.innerHTML = document.getElementById(id+'_md5s').value;
    document.getElementById('buffer_mgids').value = document.getElementById(id+'_mgids').value;
    document.getElementById('buffer_srcs').value = srcloc;
    document.getElementById('fasta_source').innerHTML = build_opts(srcloc);
    document.getElementById('buffer_info').innerHTML = "<p>The workbench contains "+num_md5s+" unique features.<br><br>They were selected from a "+selector+" barchart for the category "+dataloc+"</p>";
    document.getElementById('tab_title_1').innerHTML = "<span>Workbench ("+num_md5s+" Features)</span>";
    alert(num_md5s + ' unique features stored in workbench');
    document.getElementById('wb_fasta').style.display = "";

    var numbaks = document.getElementById('backup_buffer').childNodes.length;
    var bak = "<div id='bak_buf_"+numbaks+"'>";
    bak += "<span>"+data_buffer.innerHTML+"</span>";
    bak += "<span>"+document.getElementById('buffer_mgids').value+"</span>";
    bak += "<span>"+document.getElementById('buffer_info').innerHTML+"</span>";
    bak += "<span>"+document.getElementById('tab_title_1').innerHTML+"</span>";
    bak += "<span>"+document.getElementById('buffer_srcs').value+"</span>";
    bak += "</div>";
    document.getElementById('hits_div').innerHTML = "";
    document.getElementById('backup_buffer').innerHTML += bak;
    document.getElementById('buffer_activators').innerHTML += "<input type='radio' name='backupselector' onclick='activate_backup("+numbaks+");' checked=checked>&nbsp;"+num_md5s+" features&nbsp;&nbsp;";
  }

  if (source == 'tree') {
    var num_md5s = document.getElementById(id+'_md5s').value.split(";").length;
    if (num_md5s > buffer_max) {
      alert('You selected too many unique features ('+num_md5s+').\nPlease select less than '+buffer_max+' unique features.');
      return;
    }
    data_buffer.innerHTML = document.getElementById(id+'_md5s').value;
    document.getElementById('buffer_mgids').value = document.getElementById(id+'_mgids').value;
    document.getElementById('buffer_srcs').value = srcloc;
    document.getElementById('fasta_source').innerHTML = build_opts(srcloc);
    document.getElementById('buffer_info').innerHTML = "<p>The workbench contains "+num_md5s+" unique features.<br><br>They were selected from a "+selector+" tree for the node "+dataloc+"</p>";
    document.getElementById('tab_title_1').innerHTML = "<span>Workbench ("+num_md5s+" Features)</span>";
    alert(num_md5s + ' unique features stored in workbench');
    document.getElementById('wb_fasta').style.display = "";

    var numbaks = document.getElementById('backup_buffer').childNodes.length;
    var bak = "<div id='bak_buf_"+numbaks+"'>";
    bak += "<span>"+data_buffer.innerHTML+"</span>";
    bak += "<span>"+document.getElementById('buffer_mgids').value+"</span>";
    bak += "<span>"+document.getElementById('buffer_info').innerHTML+"</span>";
    bak += "<span>"+document.getElementById('tab_title_1').innerHTML+"</span>";
    bak += "<span>"+document.getElementById('buffer_srcs').value+"</span>";
    bak += "</div>";
    document.getElementById('hits_div').innerHTML = "";
    document.getElementById('backup_buffer').innerHTML += bak;
    document.getElementById('buffer_activators').innerHTML += "<input type='radio' name='backupselector' onclick='activate_backup("+numbaks+");' checked=checked>&nbsp;"+num_md5s+" features&nbsp;&nbsp;";
  }
}

function buffer_to_form (field) {
  if (field.checked) {
    field.value = document.getElementById('data_buffer').innerHTML;
    var mgids = document.getElementById('buffer_mgids').value.split(";");
    list_select_select_all(0);
    list_select_remove(0);
    var lsa = document.getElementById('list_select_list_a_0').options;
    for (i=0; i<lsa.length; i++) {
      lsa[i].selected = false;
    }
    for (i=0; i<lsa.length; i++) {
      for (h=0; h<mgids.length; h++) {
	if (lsa[i].value == mgids[h]) {
	  lsa[i].selected = true;
	}
      }
    }
    list_select_add(0);
    document.getElementById('mg_ok_button').onclick();
  } else {
    field.value = '';
  }
}

function show_buffer_info () {
  document.getElementById('select').innerHTML = document.getElementById('buffer_info').innerHTML;
}

function show_progress () {
  document.getElementById('progress_div').innerHTML = "<img src='./Html/ajax-loader.gif'> data generation in progress...";
}

function build_opts(data) {
  var opts  = '';
  var temp  = data.split(";");
  var items = [];

  for (i=0; i<temp.length; i++) {
    if (temp[i].toUpperCase() == 'M5NR') {
      items.push('GenBank','IMG','KEGG','PATRIC','RefSeq','SEED','SwissProt','TrEMBL','eggNOG');
    } else {
      items.push( temp[i] );
    }
  }
  items = jQuery.unique(items);
  items.sort();
  for (i=0; i<items.length; i++) {
    opts += "<option value='"+items[i]+"'>"+items[i]+"</option>";
  }
  return opts;
}

function source_ok(button) {
  button.parentNode.style.display="none";
  document.getElementById("src_sel_td").innerHTML = "";
  var opts = button.previousSibling.options;
  var html = "";
  for (i=0; i<opts.length; i++) {
    if (opts[i].selected) {
      html += "<span style='cursor: help;' title='" + opts[i].title + "'>" + opts[i].text + "</span>, ";
    }
  }
  document.getElementById("src_sel_td").innerHTML = html.substr(0, html.lastIndexOf(","));
}

function ok_button(lsid, is_group) {
  document.getElementById('sel_mg').style.display="none";
  document.getElementById("mg_sel_td").innerHTML="";
  for (i=0;i<document.getElementById("list_select_list_b_"+lsid).options.length;i++) {
    if (is_group != null) {
      document.getElementById("mg_sel_td").innerHTML += document.getElementById("list_select_list_b_"+lsid).options[i].value + ", ";
    } else {
      document.getElementById("mg_sel_td").innerHTML += "<a href='metagenomics.cgi?page=MetagenomeOverview&metagenome="+document.getElementById("list_select_list_b_"+lsid).options[i].value+"' style='cursor: help;' title='"+document.getElementById("list_select_list_b_"+lsid).options[i].text+"' target=_blank>"+document.getElementById("list_select_list_b_"+lsid).options[i].value+"</a>, ";
    }
  }
  document.getElementById("mg_sel_td").innerHTML=document.getElementById("mg_sel_td").innerHTML.substr(0, document.getElementById("mg_sel_td").innerHTML.lastIndexOf(","));
}

function workbench_export () {
  var wb_form = document.getElementById('wb_export_form');
  wb_form.innerHTML = "<input type='hidden' value='Analysis' name='page'><input type='hidden' value='workbench_export' name='action'>";
  var mgids = document.getElementById('buffer_mgids').value.split(";");
  for (i=0; i<mgids.length; i++) {
    wb_form.innerHTML += "<input type='hidden' name='comparison_metagenomes' value='"+mgids[i]+"'>";
  }
  wb_form.innerHTML += "<input type='hidden' name='comparison_sources' value='"+document.getElementById('fasta_source').value+"'>";
  wb_form.innerHTML += "<input type='hidden' name='use_buffer' value='"+document.getElementById('data_buffer').innerHTML+"'>";    
  wb_form.submit();
}

function workbench_hits_table () {
    var wb_form = document.getElementById('wb_hits_form');
    wb_form.innerHTML = "";
    var mgids = document.getElementById('buffer_mgids').value.split(";");
    var srcs  = document.getElementById('buffer_srcs').value.split(";");
    for (i=0; i<mgids.length; i++) {
      wb_form.innerHTML += "<input type='hidden' name='comparison_metagenomes' value='"+mgids[i]+"'>";
    }
    for (i=0; i<srcs.length; i++) {
      wb_form.innerHTML += "<input type='hidden' name='comparison_sources' value='"+srcs[i]+"'>";
    }
    wb_form.innerHTML += "<input type='hidden' name='use_buffer' value='"+document.getElementById('data_buffer').innerHTML+"'>";
    document.getElementById('hits_div').innerHTML = "";
}

function save_image(div) {
  if (document.getElementById(div+"canvas") == null) {
    var svg = document.getElementById(div).innerHTML;
    svg = svg.replace(/:/, "");
    svg = svg.replace(/xlink:/g, "");
    var canvas = document.createElement('canvas');
    canvas.setAttribute("width", "1000");
    canvas.setAttribute("height", "1000");
    canvas.setAttribute("id", div+"canvas");
    document.getElementById(div).parentNode.insertBefore(canvas,document.getElementById(div));
    canvg(canvas, svg);
  }
}

function store_grouping(id, mgs) {
  var mg_list = mgs.split("^");
  var grouping = '';
  for (i=0;i<mg_list.length;i++) {
    grouping += document.getElementById('group_list'+id+'_'+i).options[document.getElementById('group_list'+id+'_'+i).selectedIndex].value + "^" + mg_list[i] + "|";
  }
  document.getElementById('grouping_storage').value = grouping;
  alert('grouping stored.');
}

function check_group_selection(check, id) {
  if (check.checked) {
    var grouping = document.getElementById('grouping_storage');
    if (grouping.value == '') {
      alert('To create p-values, you first need to select groups for\nall metagenomes in question.\n\nTo do so, create a PCA plot, put all metagenomes into a\ngroup and click the store grouping button.');
      check.checked = false;
    } else {
      check.value = grouping.value;
    }
  }
}

function activate_backup(num) {
  var numbaks = document.getElementById('backup_buffer').childNodes.length;
  var newactive = document.getElementById('backup_buffer').childNodes[num];
  document.getElementById('data_buffer').innerHTML = newactive.childNodes[0].innerHTML;
  document.getElementById('buffer_mgids').value = newactive.childNodes[1].innerHTML;
  document.getElementById('buffer_info').innerHTML = newactive.childNodes[2].innerHTML;
  document.getElementById('tab_title_1').innerHTML = newactive.childNodes[3].innerHTML;
  document.getElementById('buffer_srcs').value = newactive.childNodes[4].innerHTML;
  document.getElementById('fasta_source').innerHTML = build_opts(newactive.childNodes[4].innerHTML);
  document.getElementById('hits_div').innerHTML = "";
}

function abu(t, id, md5columnindex, source) {
  var x = t.offsetParent.id;
  var m = /cell_(\d+)_\d+_(\d+)/.exec(x);

  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (m[1] == table_list[i]) {
      data_index = i;
    }
  }

  var md5string = table_data[data_index][m[2]][md5columnindex];
  var md5s = md5string.split(";");
  var mgslist = document.getElementById('table_group_form_'+id).comparison_metagenomes;
  var mgs = new Array();
  for (i=0;i<mgslist.length;i++) {
    mgs[mgs.length] = "comparison_metagenomes="+mgslist[i].value;
  }
  if (! mgslist.length) {
    mgs[0] = "comparison_metagenomes="+mgslist.value;
  }
  if (md5s.length > 100) {
    alert('abundance details are only available for the first 100 md5s');
    md5s.splice(100, md5s.length - 100);
  }
  md5string = md5s.join('^');
  if (! source) {
    source = table_data[data_index][m[2]][1];
  }
  window.open('?page=Analysis&source='+source+'&action=workbench_blat_output&tabnum='+id+'&'+mgs.join("&")+'&md5s='+md5string);
}

function generate_krona_data (depth, table_id, func_or_org) {
  //var data = '<magnitude attribute="magnitude"><\/magnitude><attributes rank="Rank" score="Avg. log e-value" magnitude="Abundance"><\/attributes><datasets names="'+dataset_name+'"><\/datasets><color valueend="4" valuestart="-157" hueend="0" huestart="120" attribute="score"><\/color>';

  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  
  var krona_data = [];
  var hierarchy = [];

  if (func_or_org == 'org') {
    hierarchy = [ 'Domain', 'Phylum', 'Class', 'Order', 'Family', 'Genus', 'Species', 'Strain' ];
    for (i=0;i<table_filtered_data[data_index].length;i++) {
      var row = table_filtered_data[data_index][i];
      krona_data[krona_data.length] = [ row[0], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10].replace(/<[^>]+>/g, ""), row[12] ];
    }
  } else {
    if (table_filtered_data[data_index][0][6].indexOf('abu(this') > -1) {
      hierarchy = [ 'Level 1', 'Level 2', 'Level 3', 'Function' ];
      for (i=0;i<table_filtered_data[data_index].length;i++) {
	var row = table_filtered_data[data_index][i];
	krona_data[krona_data.length] = [ row[0], row[1], row[2], row[3].replace(/<[^>]+>/g, ""), row[4], row[6].replace(/<[^>]+>/g, ""), row[8] ];
      }
    } else {
      hierarchy = [ 'Level 1', 'Level 2', 'Function' ];
      for (i=0;i<table_filtered_data[data_index].length;i++) {
	var row = table_filtered_data[data_index][i];
	krona_data[krona_data.length] = [ row[0], row[1], row[2].replace(/<[^>]+>/g, ""), row[3], row[5].replace(/<[^>]+>/g, ""), row[7] ];
      }
    }
  }

  generate_krona(krona_data, hierarchy, 1);

//   var nodes = [];
//   var all = [];
//   var dataset_names = dataset_name.split(",");
//   var dataset_hash = [];
//   for (i=0;i<dataset_names.length;i++) {
//     dataset_hash[dataset_names[i]] = i;
//     all[i] = 0;
//   }

//   for (i=0; i<table_filtered_data[data_index].length; i++) {
//     var curr_abundance = parseFloat(table_filtered_data[data_index][i][10].replace(/<[^>]+>/g, ""));
//     var curr_evalue = parseFloat(table_filtered_data[data_index][i][12]);
//     var curr_mg = table_filtered_data[data_index][i][0];
//     all[dataset_hash[curr_mg]] += curr_abundance;
//     krona_recursive(table_filtered_data[data_index][i], nodes, 0, depth + 1, curr_abundance, curr_evalue, curr_mg);
//   }

//   data += "<node score='1' magnitude='"+all.join(",")+"' name='all'>";
//   for (a in nodes) {
//     var sc = "";
//     var mag = "";
//     for (m=0;m<dataset_names.length;m++) {
//       if (nodes[a][dataset_names[m]]) {
// 	sc += nodes[a][dataset_names[m]][1]+",";
// 	mag += nodes[a][dataset_names[m]][0]+",";
//       } else {
// 	sc += "0,";
// 	mag += "0,";
//       }
//     }
//     sc = sc.slice(0,sc.length-1);
//     mag = mag.slice(0,mag.length-1);
//     data += "<node rank='Domain' score='"+sc+"' magnitude='"+mag+"' name='"+a+"'>";
//     if (depth > 0) {
//       for (b in nodes[a]['children']) {
// 	sc = "";
// 	mag = "";
// 	for (m=0;m<dataset_names.length;m++) {
// 	  if (nodes[a]['children'][b][dataset_names[m]]) {
// 	    sc += nodes[a]['children'][b][dataset_names[m]][1]+",";
// 	    mag += nodes[a]['children'][b][dataset_names[m]][0]+",";
// 	  } else {
// 	    sc += "0,";
// 	    mag += "0,";
// 	  }
// 	}
// 	sc = sc.slice(0,sc.length-1);
// 	mag = mag.slice(0,mag.length-1);
// 	data += "<node rank='Phylum' score='"+sc+"' magnitude='"+mag+"' name='"+b+"'>";
// 	if (depth > 1) {
// 	  for (c in nodes[a]['children'][b]['children']) {
// 	    sc = "";
// 	    mag = "";
// 	    for (m=0;m<dataset_names.length;m++) {
// 	      if (nodes[a]['children'][b]['children'][c][dataset_names[m]]) {
// 		sc += nodes[a]['children'][b]['children'][c][dataset_names[m]][1]+",";
// 		mag += nodes[a]['children'][b]['children'][c][dataset_names[m]][0]+",";
// 	      } else {
// 		sc += "0,";
// 		mag += "0,";
// 	      }
// 	    }
// 	    sc = sc.slice(0,sc.length-1);
// 	    mag = mag.slice(0,mag.length-1);
// 	    data += "<node rank='Class' score='"+sc+"' magnitude='"+mag+"' name='"+c+"'>";
// 	    if (depth > 2) {
// 	      for (d in nodes[a]['children'][b]['children'][c]['children']) {
// 		sc = "";
// 		mag = "";
// 		for (m=0;m<dataset_names.length;m++) {
// 		  if (nodes[a]['children'][b]['children'][c]['children'][d][dataset_names[m]]) {
// 		    sc += nodes[a]['children'][b]['children'][c]['children'][d][dataset_names[m]][1]+",";
// 		    mag += nodes[a]['children'][b]['children'][c]['children'][d][dataset_names[m]][0]+",";
// 		  } else {
// 		    sc += "0,";
// 		    mag += "0,";
// 		  }
// 		}
// 		sc = sc.slice(0,sc.length-1);
// 		mag = mag.slice(0,mag.length-1);
// 		data += "<node rank='Order' score='"+sc+"' magnitude='"+mag+"' name='"+d+"'>";
// 		if (depth > 3) {
// 		  for (e in nodes[a]['children'][b]['children'][c]['children'][d]['children']) {
// 		    sc = "";
// 		    mag = "";
// 		    for (m=0;m<dataset_names.length;m++) {
// 		      if (nodes[a]['children'][b]['children'][c]['children'][d]['children'][e][dataset_names[m]]) {
// 			sc += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e][dataset_names[m]][1]+",";
// 			mag += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e][dataset_names[m]][0]+",";
// 		      } else {
// 			sc += "0,";
// 			mag += "0,";
// 		      }
// 		    }
// 		    sc = sc.slice(0,sc.length-1);
// 		    mag = mag.slice(0,mag.length-1);
// 		    data += "<node rank='Family' score='"+sc+"' magnitude='"+mag+"' name='"+e+"'>";
// 		    if (depth > 4) {
// 		      for (f in nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children']) {
// 			sc = "";
// 			mag = "";
// 			for (m=0;m<dataset_names.length;m++) {
// 			  if (nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f][dataset_names[m]]) {
// 			    sc += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f][dataset_names[m]][1]+",";
// 			    mag += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f][dataset_names[m]][0]+",";
// 			  } else {
// 			    sc += "0,";
// 			    mag += "0,";
// 			  }
// 			}
// 			sc = sc.slice(0,sc.length-1);
// 			mag = mag.slice(0,mag.length-1);
// 			data += "<node rank='Genus' score='"+sc+"' magnitude='"+mag+"' name='"+f+"'>";
// 			if (depth > 5) {
// 			  for (g in nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children']) {
// 			    sc = "";
// 			    mag = "";
// 			    for (m=0;m<dataset_names.length;m++) {
// 			      if (nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g][dataset_names[m]]) {
// 				sc += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g][dataset_names[m]][1]+",";
// 				mag += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g][dataset_names[m]][0]+",";
// 			      } else {
// 				sc += "0,";
// 				mag += "0,";
// 			      }
// 			    }
// 			    sc = sc.slice(0,sc.length-1);
// 			    mag = mag.slice(0,mag.length-1);
// 			    data += "<node rank='Species' score='"+sc+"' magnitude='"+mag+"' name='"+g+"'>";
// 			    if (depth > 6) {
// 			      for (h in nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g]['children']) {
// 				sc = "";
// 				mag = "";
// 				for (m=0;m<dataset_names.length;m++) {
// 				  if (nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g]['children'][h][dataset_names[m]]) {
// 				    sc += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g]['children'][h][dataset_names[m]][1]+",";
// 				    mag += nodes[a]['children'][b]['children'][c]['children'][d]['children'][e]['children'][f]['children'][g]['children'][h][dataset_names[m]][0]+",";
// 				  } else {
// 				    sc += "0,";
// 				    mag += "0,";
// 				  }
// 				}
// 				sc = sc.slice(0,sc.length-1);
// 				mag = mag.slice(0,mag.length-1);
// 				data += "<node rank='Strain' score='"+sc+"' magnitude='"+mag+"' name='"+h+"'></node>";		  
// 				data += "<\/node>";
				
// 			      }
// 			    }
// 			    data += "<\/node>";
// 			  }
// 			}			
// 			data += "<\/node>";
// 		      }
// 		    }
// 		    data += "<\/node>";
// 		  }
// 		}
// 		data += "<\/node>";
// 	      }
// 	    }
// 	    data += "<\/node>";
// 	  }
// 	}
// 	data += "<\/node>";
//       }
//     }
//     data += "<\/node>";
//   }
//   data += "<\/node>";

//   var krona_window = window.open('','krona_window_'+dataset_name);
//   krona_window.document.write('<html><head><meta charset="utf-8"\/><style>body { margin:0; }<\/style><title>MG-RAST - Krona view of Metagenome '+dataset_name+'<\/title><link rel="icon" type="image/png" href="./Html/favicon.ico"><\/head><body style="padding:0;position:relative"><a href="?page=Home" style="border: none; background-color:black; position: absolute; bottom: 8px;"><img style="height: 66px; border: none;" src="./Html/MGRAST_logo.png" alt="MG-RAST Metagenomics Analysis Server" \/><\/a><a href="http://sourceforge.net/p/krona/home/krona/" target=_blank style="position: absolute; bottom: 8px; border: none; text-decoration: none; color: black; left: 260px;"><img src="./Html/krona.png" style="border: none;"> powered by Krona<\/a><div id="options" style="position:absolute;left:0;top:100px"><\/div><div id="details" style="position:absolute;top:1px;right:2px;text-align:right;"><\/div><canvas id="canvas" width="100%" height="100%"><\/canvas><img id="hiddenImage" visibility="hide" src="http://krona.sourceforge.net/img/hidden.png"><script name="tree" src="./Html/krona-1.1.js"><\/script><data>'+data+'<\/data><img src="./Html/clear.gif" onload="load()"><\/body><\/html>');
//   krona_window.document.close();
}

// function krona_recursive (tdata, parentNode, depth, maxDepth, curr_abundance, curr_evalue, curr_mg) {
//   if (! parentNode[tdata[depth + 2]]) {
//     parentNode[tdata[depth + 2]] = [];
//     parentNode[tdata[depth + 2]]['children'] = [];
//   }
//   if (! parentNode[tdata[depth + 2]][curr_mg]) {
//     parentNode[tdata[depth + 2]][curr_mg] = [ curr_abundance, curr_evalue, 1 ];
//   } else {
//     parentNode[tdata[depth + 2]][curr_mg][0] += curr_abundance;
//     parentNode[tdata[depth + 2]][curr_mg][1] = ((parentNode[tdata[depth + 2]][curr_mg][1] * parentNode[tdata[depth + 2]][curr_mg][2]) + curr_evalue) / (parentNode[tdata[depth + 2]][curr_mg][2] + 1);
//     parentNode[tdata[depth + 2]][curr_mg][2]++;
//   }
//   depth++;
//   if (depth < maxDepth) {
//     krona_recursive(tdata, parentNode[tdata[depth + 1]]['children'], depth, maxDepth, curr_abundance, curr_evalue, curr_mg);
//   }
//   depth--;
//   return;
// }

function transpose_table (table_id, transpose_column, displayed_columns, data_column, target_div) {
  // variable to store the table html in
  var table_html = "";

  // get the source table data
  var orig_data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      orig_data_index = i;
    }
  }
  var source_table_data = table_filtered_data[orig_data_index];

  // variable to store the transposed data
  var transposed_data = [];

  // do the transposition
  var trans_col_items = [];
  var row_items = [];
  for (i=0;i<source_table_data.length;i++) {
    var row_data = [];
    for (h=0;h<displayed_columns.length;h++) {
      row_data[row_data.length] = source_table_data[i][displayed_columns[h]];
    }
    var joined_row = row_data.join('^^'); 
    if (! transposed_data[joined_row]) {
      transposed_data[joined_row] = [];
    }
    trans_col_items[source_table_data[i][transpose_column]] = 1;
    row_items[joined_row] = 1;
    transposed_data[joined_row][source_table_data[i][transpose_column]] = source_table_data[i][data_column];
  }
  var trans_col_item_list = [];
  for (i in trans_col_items) {
    trans_col_item_list.push(i);
  }

  // create a table data structure from the transposed data
  var transposed_table_data = [];
  var rid = 0;
  for (i in row_items) {
    var curr_row = [];
    var curr_cols = i.split('^^');
    for (h=0;h<curr_cols.length;h++) {
      curr_row[curr_row.length] = curr_cols[h];
    }
    for (h=0;h<trans_col_item_list.length;h++) {
      if (transposed_data[i][trans_col_item_list[h]]) {
	curr_row[curr_row.length] = transposed_data[i][trans_col_item_list[h]].replace(HTML_REPLACE, '');
      } else {
	curr_row[curr_row.length] = '0';
      }
    }
    curr_row[curr_row.length] = rid;
    rid++;
    transposed_table_data[transposed_table_data.length] = curr_row;
  }

  // get a new index for this table
  var found = 0;
  data_index = 0;
  while (found == 0) {
    data_index++;
    found = 1;
    for (i=0;i<table_list.length;i++) {
      if (data_index == table_list[i]) {
	found = 0;
	break;
      }
    }
  }

  // create visible columns hidden
  var v = [];
  var ct = [];
  var num_cols = displayed_columns.length + trans_col_item_list.length;
  for (i=0;i<num_cols;i++) {
    v.push('1');
    ct.push('');
  }

  // hidden data
  table_html += "<input type='hidden' id='table_visible_columns_"+data_index+"' value='"+v.join('@~')+"'>";
  table_html += "<input type='hidden' id='table_combo_columns_"+data_index+"' value=''>";
  table_html += "<input type='hidden' id='table_column_types_"+data_index+"' value='"+ct.join('@~')+"'>";
  table_html += "<input type='hidden' id='table_cols_"+data_index+"' value='"+num_cols+"'>";
  table_html += "<input type='hidden' id='table_rows_"+data_index+"' value='1'>";
  table_html += "<input type='hidden' id='table_start_"+data_index+"' value='0'>";
  table_html += "<input type='hidden' id='table_hoverid_"+data_index+"' value='12345'>";
  table_html += "<input type='hidden' id='hover_redundancies_12345' value=''>";
  
  // global table surrounder
  table_html += "<table class='table_table'>";

  // select items per page
  table_html += '<tr><td style="width: 100%; text-align: center; vertical-align: middle;"><table style="width: 100%;"><tbody><tr><td align="center"><span class="table_perpage">display&nbsp;<input type="text" onkeypress="return check_submit_filter(event, &quot;'+data_index+'&quot;);" value="15" size="3" name="table_perpage_'+data_index+'" id="table_perpage_'+data_index+'">&nbsp;items per page</span></td></tr></tbody></table></td></tr>';
  
  // navigation
  table_html += '<tr><td style="width: 100%; text-align: center;"><table style="width: 100%;"><tbody><tr><td width="20%" align="left"><a name="table_first_'+data_index+'" href="javascript: table_first(&quot;'+data_index+'&quot;);" style="display: none;">«first</a>&nbsp;&nbsp;<a name="table_prev_'+data_index+'" href="javascript: table_prev(&quot;'+data_index+'&quot;);" style="display: none;">«prev</a></td><td width="60%" align="center">displaying <span id="table_start_top_'+data_index+'">1</span> - <span id="table_stop_top_'+data_index+'">1</span> of <span id="table_total_top_'+data_index+'">1</span></td><td width="20%" align="right"><a name="table_next_'+data_index+'" href="javascript: table_next(&quot;'+data_index+'&quot;);" style="display: inline;">next»</a>&nbsp;&nbsp;<a name="table_last_'+data_index+'" href="javascript: table_last(&quot;'+data_index+'&quot;);" style="display: inline;">last»</a></td></tr></tbody></table></td></tr>';

  // table columns
  table_html += "<tr><td>";
  table_html += "<table id='table_"+data_index+"' class='table_table'><tr>";
  
  // displayed columns
  var ccount = 1;
  for (i=0;i<displayed_columns.length;i++) {
    table_html += "<td id='"+data_index+"_col_"+ccount+"' class='table_first_row'>"+document.getElementById('colname_'+table_id+'_col_'+(displayed_columns[i]+1)).innerHTML+"</td>";
    ccount++;
  }

  // transposed columns
  for (i=0;i<trans_col_item_list.length;i++) {
    table_html += "<td id='"+data_index+"_col_"+ccount+"' class='table_first_row'>"+trans_col_item_list[i]+"</td>";
    ccount++;
  }
  
  table_html += "</tr></table>";
  table_html += "</td></tr>";
  
  // close surrounder
  table_html += "</table>";
  
  // fill in the html
  document.getElementById(target_div).innerHTML = table_html;
  
  // draw the table
  initialize_table(data_index, transposed_table_data);
}
