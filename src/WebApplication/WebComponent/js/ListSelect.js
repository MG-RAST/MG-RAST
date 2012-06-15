var list_select_preselect = new Array();
var list_select_data = new Array();
var list_select_filtered_data = new Array();
var list_select_all_data = new Array();
var list_select_uses_groups = new Array();
var list_select_types = new Array();
var list_select_type_hash = new Array();

function initialize_list_select (id) {
  var preselect = document.getElementById('list_select_preselect_' + id).value.split(/~@/);
  var all_data = document.getElementById('list_select_data_' + id).value.split(/~~/);
  var set_select = document.getElementById('list_select_set_select_'+id);
  list_select_types[id] = new Array();
  list_select_type_hash[id] = new Array();

  var set = 0;
  list_select_uses_groups[id] = document.getElementById('list_select_uses_groups_'+id).value;
  if (list_select_uses_groups[id] && set_select) {
    set = set_select.options[set_select.selectedIndex].value;
  }
  list_select_all_data[id] = new Array();

  for (i=0;i<all_data.length;i++) {
    var data_list = all_data[i].split(/~@/);
    var data = new Array();
    for (h=0;h<data_list.length;h++) {
      data[h] = data_list[h].split(/~#/);
      if (data[h][2] != null) {
	list_select_types[id][data[h][1]] = data[h][2];
	list_select_type_hash[id][data[h][2]] = 1;
      }
    }
    list_select_all_data[id][i] = data;
    if (i==set) {
      list_select_data[id] = data;
      list_select_filtered_data[id] = data;
    }
  }
  list_select_preselect[id] = preselect;
  
  list_select_reset(id);
}

function list_select_change_current_data_set (id) {
  document.getElementById("list_select_filter_" + id).value = '';
  list_select_filtered_data[id] = list_select_data[id];
  update_list_select(null, id);
  var set_select = document.getElementById('list_select_set_select_'+id);
  var select_left = document.getElementById('list_select_list_a_'+id);
  var set = set_select.options[set_select.selectedIndex].value;
  var oldset = set_select.SaveValue;
  list_select_all_data[id][oldset] = new Array();
  for (i=0;i<select_left.options.length;i++) {
    list_select_all_data[id][oldset][i] = [ select_left.options[i].value, select_left.options[i].text ];
  }
  set_select.SaveValue = set;

  var opts_left = "";
  var active = active_types(id);
  for (i=0;i<list_select_all_data[id][set].length;i++) {
    if (list_select_types[id][list_select_all_data[id][set][i][1]] != null && active[list_select_types[id][list_select_all_data[id][set][i][1]]] == false) {
      continue;
    }
    opts_left += "<option value='"+list_select_all_data[id][set][i][0]+"'>"+list_select_all_data[id][set][i][1]+"</option>";
  }
  select_left.innerHTML = opts_left;
  list_select_data[id] = list_select_all_data[id][set];
  list_select_filtered_data[id] = list_select_all_data[id][set];
}

function list_select_add (id) {
  var select_left = document.getElementById('list_select_list_a_'+id);
  var select_right = document.getElementById('list_select_list_b_'+id);
  var options_to_add = new Array();
  var num_select_options = select_left.options.length;
  var max_selections = parseInt(document.getElementById('list_select_max_selections_'+id).value);
  var set_select = document.getElementById('list_select_set_select_'+id);

  // check for groups
  var optgroups = new Array();
  for (i=0;i<num_select_options;i++) {
    if (select_left.options[i].value.indexOf('##') > -1) {
      var optgroup = select_left.options[i].value.split("||");
      optgroups[i] = new Array();
      for (h=0; h<optgroup.length; h++) {
	optgroups[i][optgroups[i].length] = optgroup[h].split("##");
      }
    }
  }

  if (max_selections>0) {
    var num_chosen_options = select_right.options.length;
    var num_to_add = 0;
    for (i=0;i<num_select_options;i++) {
      if (select_left.options[i].selected) {
	if (optgroups[i]) {
	  num_to_add += optgroups[i].length;
	} else {
	  num_to_add++;
	}
      }
    }
    if (num_to_add + num_chosen_options > max_selections) {
      alert('The maximum number of entries may not exceed '+max_selections);
      return 1;
    }
  }
  for (i=0;i<num_select_options;i++) {
    if (select_left.options[i].selected) {
      if (optgroups[i]) {
	for (h=0; h<optgroups[i].length; h++) {
	  options_to_add[optgroups[i][h][0]] = new Option(optgroups[i][h][1], optgroups[i][h][0]);
	}
      } else {
	options_to_add[select_left.options[i].value] = new Option(select_left.options[i].text, select_left.options[i].value);
	select_left.options[i] = null;
	num_select_options--;
	i--;
      }
    }
  }
  if (document.getElementById('list_select_sorted_'+id).value == '1') {
    for (i=0;i<select_right.options.length;i++) {
      options_to_add[select_right.options[i].value] = select_right.options[i];
    }
    while (select_right.options.length) {
      select_right.options[select_right.options.length - 1] = null;
    }
    options_to_add.sort(sort_options);
    for (var i in options_to_add) {
      if (list_select_uses_groups[id] && set_select) {
	options_to_add[i].group = set_select.options[set_select.selectedIndex].value;
      }
      select_right.options[select_right.options.length] = options_to_add[i];
    }
  } else {
    var optlen = select_right.options.length;
    for (var i in options_to_add) {
      var needed = 1;
      for (h=0; h<optlen; h++) {
	if (select_right.options[h].value == options_to_add[i].value) {
	  needed = 0;
	  break;
	}
      }
      if (needed) {
	if (list_select_uses_groups[id] && set_select) {
	  options_to_add[i].group = set_select.options[set_select.selectedIndex].value;
	}
	select_right.options[select_right.options.length] = options_to_add[i];
      }
    }
  }
}

function list_select_remove (id) {
  var select_left = document.getElementById('list_select_list_a_'+id);
  var select_right = document.getElementById('list_select_list_b_'+id);
  var set_select = document.getElementById('list_select_set_select_'+id);
  var set = null;
  if (set_select) {
    set = set_select.options[set_select.selectedIndex].value;
  }
  var options_to_add = new Array();
  var num_select_options = select_right.options.length;
  for (i=0;i<num_select_options;i++) {
    if (select_right.options[i].selected) {
      options_to_add[options_to_add.length] = new Option(select_right.options[i].text, select_right.options[i].value);
      options_to_add[options_to_add.length - 1].group = select_right.options[i].group;
      select_right.options[i] = null;
      num_select_options--;
      i--;
    }
  }
  if (document.getElementById('list_select_sorted_'+id).value == '1') {
    for (i=0;i<select_left.options.length;i++) {
      options_to_add[options_to_add.length] = select_left.options[i];
    }
    while (select_left.options.length) {
      select_left.options[select_left.options.length - 1] = null;
    }
    options_to_add.sort(sort_options);
    for (i=0;i<options_to_add.length;i++) {
      if (list_select_uses_groups[id] && set_select && options_to_add[i].group > -1 && options_to_add[i].group != set) {
	list_select_all_data[id][options_to_add[i].group][list_select_all_data[id][options_to_add[i].group].length] = [ options_to_add[i].value, options_to_add[i].text ];
      } else {
	select_left.options[select_left.options.length] = options_to_add[i];
      }
    }
  } else {
    for (i=0;i<options_to_add.length;i++) {
      if (list_select_uses_groups[id] && set_select && options_to_add[i].group > -1 && options_to_add[i].group != set) {
	list_select_all_data[id][options_to_add[i].group][list_select_all_data[id][options_to_add[i].group].length] = [ options_to_add[i].value, options_to_add[i].text ];
      } else {
	select_left.options[select_left.options.length] = options_to_add[i];
      }
    }
  }
}

function sort_options (a, b) {
  if (a.text==b.text) return 0;
  if (a.text<b.text) return -1;
  return 1;
}

function list_select_reset (id) {
  var preselect = list_select_preselect[id];
  var preselect_selected = new Array();
  var data = list_select_data[id];
  var preselect_hash = new Array();
  for (i=0;i<preselect.length;i++) {
    preselect_hash[preselect[i]] = 1;
  }
  var left = document.getElementById('list_select_list_a_'+id);
  var right = document.getElementById('list_select_list_b_'+id);
  var active = active_types(id);

  var opts_left = "";
  var opts_right = "";
  for (i=0;i<data.length;i++) {
    if (list_select_types[id][data[i][1]] != null && active[list_select_types[id][data[i][1]]] == false) {
      continue;
    }
    if (preselect_hash[data[i][0]]) {
      preselect_selected[data[i][0]] = 1;
      opts_right += "<option value='"+data[i][0]+"'>"+data[i][1]+"</option>";
    } else {
      opts_left += "<option value='"+data[i][0]+"'>"+data[i][1]+"</option>";
    }
  }
  for (i=0;i<preselect.length;i++) {
    if (! preselect_selected[preselect[i]] && preselect[i]) {
      opts_right += "<option value='"+preselect[i]+"'>"+preselect[i]+"</option>";
    }
  }
  
  left.innerHTML = opts_left;
  right.innerHTML = opts_right;

  var filter = document.getElementById("list_select_filter_" + id);
  if (filter) {
    filter.value = "";
  }
}

function list_select_select_all (id) {
  var ls = document.getElementById('list_select_list_b_'+id);
  if (ls) {
    for (i=0;i<ls.options.length;i++) {
      ls.options[i].selected = true;
    }
  }
}

// check if the backspace key was pressed, if so, execute the filter
function list_select_check_backspace (e, id) {
  if (e) {
    // if the filter is reduced, reset to original array
    if (e.keyCode == 8) {
      list_select_filtered_data[id] = list_select_data[id];
    }
  }

  update_list_select(e, id);
}

// this is called when someone types something into the filter box
function update_list_select (e, id) {

  var text = document.getElementById("list_select_filter_" + id).value;

  var select = document.getElementById("list_select_list_a_" + id);
  
  var selected = document.getElementById("list_select_list_b_" + id);
  var selected_texts = new Array();
  for (i=0; i<selected.options.length; i++) {
    selected_texts[selected.options[i].text] = 1;
  }
  
  // preserve the current filtering
  var new_filtered = new Array();

  // escape the text
  var escaped_text = reg_escape(text);
  var re = new RegExp(escaped_text, "i");

  var active = active_types(id);

  var opts_select = "";
  // iterate through the items to find out which match the filter
  for (i=0; i<list_select_filtered_data[id].length; i++) {
    if (list_select_filtered_data[id][i][1].match(re)) {
      if (! selected_texts[list_select_filtered_data[id][i][1]]) {
	if (list_select_types[id][list_select_filtered_data[id][i][1]] != null && active[list_select_types[id][list_select_filtered_data[id][i][1]]] == false) {
	  continue;
	}
	opts_select += "<option value='"+ list_select_filtered_data[id][i][0]+"'>"+ list_select_filtered_data[id][i][1]+"</option>";
	new_filtered[new_filtered.length] = list_select_filtered_data[id][i];
      }
    }
  }
  select.innerHTML = opts_select;

  // update preserved filter
  list_select_filtered_data[id] = new_filtered;
  
  // select first item
  select.selectedIndex = 0;
}

/* escape string for use in regexp */
function reg_escape (text) {
  var escaped_text = "";
  for (i=0; i<text.length; i++) {
    switch (text.substr(i, 1))  {
    case '+':
      escaped_text  = escaped_text + "\\";
      break;
    case '(':
      escaped_text  = escaped_text + "\\";
      break;
    case ')':
      escaped_text  = escaped_text + "\\";
      break;
    case '\\':
      escaped_text  = escaped_text + "\\";
      break;
    case '^':
      escaped_text  = escaped_text + "\\";
      break;
    case '$':
      escaped_text  = escaped_text + "\\";
      break;
    case '{':
      escaped_text  = escaped_text + "\\";
      break;
    case '}':
      escaped_text  = escaped_text + "\\";
      break;
    case '[':
      escaped_text  = escaped_text + "\\";
      break;
    case ']':
      escaped_text  = escaped_text + "\\";
    }
    escaped_text  = escaped_text + text.substr(i, 1);
  }
  return escaped_text;
}

function active_types (id) {
  var active = new Array();
  for (var key in list_select_type_hash[id]) {
    if (document.getElementById('ls_types_'+key+'_'+id) != null) {
      active[key] = document.getElementById('ls_types_'+key+'_'+id).checked;
    }
  }
  return active;
}
