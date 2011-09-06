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

function buffer_data (source, id, selector, dataloc, mgloc, srcloc) {
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
    var data_array = table_filtered_data[data_index]; 
    for (i=0;i<data_array.length;i++) {
      if (row_ids[data_array[i][data_array[i].length - 1]]) {
	mg_ids[data_array[i][mgloc]] = 1;
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

      data_buffer.innerHTML = md5array.join(";");
      alert(num_md5s + ' unique features stored in workbench');

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
