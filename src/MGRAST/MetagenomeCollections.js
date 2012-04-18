var global_data = new Array();
var data_description = new Array();
var data_items = new Array();
var data_count = new Array();
var SORT_COLUMN_INDEX = 0;
var collection_data = new Array();

function initialize_data () {
  initialize_collections();

  var data_string = document.getElementById('mgs_input_data').value;
  var rows = data_string.split('##');
  for (i=0; i<rows.length; i++) {
    global_data[global_data.length] = rows[i].split('||');
  }
  var description_string = document.getElementById('mgs_data_description').value;
  data_description = description_string.split('|');
  
  group_data(global_data);

  if (document.getElementById('mgs_collection_select').options.length) {
    collection_to_selection();
  }
}

function initialize_collections () {
  var collection_string = document.getElementById('mgs_collection_data').value;
  var crows = collection_string.split('#');
  for (i=0; i<crows.length; i++) {
    collection_data[i] = crows[i].split('|');
  }
  var sel = document.getElementById('mgs_collection_select');
  while (sel.options.length) {
    sel.remove(0);
  }
  for (i=0; i<collection_data.length; i++) {
    sel.add(new Option(collection_data[i][0], collection_data[i][0]), null);
  }
}

function show_detail (select, selval) {
  var sel = '';
  if (select) {
    sel = select.options[select.selectedIndex].value;
  } else {
    sel = selval;
  }
  for (i=0; i<global_data.length; i++) {
    if (global_data[i][0] == sel) {
      var info = '<div class="metagenome_info"><ul style="padding-left: 0px;">';
      for (h=0; h<data_description.length; h++) {
	var style_class = '';
	if (h == 0) {
	  style_class = ' class="first"';
	}
	if (h % 2 == 1) {
	  style_class = ' class="odd"';
	}
	var view_data = global_data[i][h];
	if (data_description[h] == "genome_id") {
	  view_data = "<a href='?page=MetagenomeOverview&metagenome="+view_data+"'>"+view_data+"</a>";
	}
	info += '<li'+style_class+' style="width: 495px;"><label style="width: 185px;">'+data_description[h]+'</label><span style="width: 300px;">'+view_data+'</span></li>'
      }
      info += '</ul></div>';
      document.getElementById('mgs_detail').innerHTML = info;
      break;
    }
  }
}

function group_data (data) {
  for (i=1; i<data_description.length; i++) {
    data_items[data_description[i]] = new Array();
    SORT_COLUMN_INDEX = i;
    data.sort(sort_caseinsensitive_up);
    var lastp = '';
    var num = 1;
    for (h=0; h<data.length; h++) {
      if (data[h][i] != lastp) {
	if (lastp != '') {
	  data_count[data_description[i]+'_'+lastp] = num;
	  num = 1;
	}
	lastp = data[h][i];
	data_items[data_description[i]][data_items[data_description[i]].length] = lastp;
	
      } else {
	num++;
      }
    }
    data_count[data_description[i]+'_'+lastp] = num;
    data_items[data_description[i]].sort();
  }

  return 1;
}

function mgs_remove () {
  var opts = new Array();
  var sel = document.getElementById('mgs_current_selection');
  for (i=0; i<sel.options.length; i++) {
    if (! sel.options[i].selected) {
      opts[opts.length] = new Option(sel.options[i].label, sel.options[i].value);
    }
  }
  while (sel.options.length) {
    sel.remove(0);
  }
  for (i=0; i<opts.length; i++) {
    sel.add(opts[i], null);
  }
}

function sort_caseinsensitive_up (a, b) {
  aa = a[SORT_COLUMN_INDEX].toLowerCase();
  bb = b[SORT_COLUMN_INDEX].toLowerCase();
  if (aa==bb) return 0;
  if (aa<bb) return -1;
  return 1;
}

function collection_to_selection () {
  var sel = document.getElementById('mgs_current_selection');
  var coll = document.getElementById('mgs_collection_select').options[document.getElementById('mgs_collection_select').selectedIndex].value;
  document.getElementById('mgs_collection_name').value = coll;
  while (sel.options.length) {
    sel.remove(0);
  }
  var coll_row;
  for (i=0; i<collection_data.length; i++) {
    if (collection_data[i][0] == coll) {
      coll_row = collection_data[i];
      break;
    }
  }
  var remaining = new Array();
  for (i=0; i<global_data.length; i++) {
    for (h=0; h<coll_row.length; h++) {
      if (global_data[i][0] == coll_row[h]) {
	remaining[remaining.length] = [ global_data[i][1], global_data[i][0] ];
	break;
      }
    }
  }
  remaining.sort();
  for (i=0; i<remaining.length; i++) {
    sel.add(new Option(remaining[i][0], remaining[i][1]), null);
  }
}

function save_collection () {
  var sel = document.getElementById('mgs_current_selection');
  if (sel.options.length) {
    var collection_name = document.getElementById('mgs_collection_name').value;
    if (collection_name) {
      var ajax_params = "collection="+collection_name;
      for (h=0; h<global_data.length; h++) {
	for (i=0; i<sel.options.length; i++) {
	  if (global_data[h][0] == sel.options[i].value) {
	    ajax_params += "&cv="+global_data[h][0];
	    break;
	  }
	}
      }
      execute_ajax('update_collection', 'mgs_ajax_div', ajax_params, null, null, read_new_collections);
    } else {
      alert('your collection must have a name');
      document.getElementById('mgs_collection_name').focus();
    }
  } else {
    alert('your collection is empty');
  }
}

function read_new_collections () {
  document.getElementById('mgs_collection_data').value = document.getElementById('mgs_collection_data_new').value;
  initialize_collections();
}

function add_from_table (table_id) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  var opts = new Array();
  var data_array = table_filtered_data[data_index];
  var selection_array = table_input_columns_data[data_index];
  for (i=0;i<selection_array.length;i++) {
    if (selection_array[i][0] == 1) {
      opts[data_array[i][1]] = new Option(data_array[i][2], data_array[i][1]);
    }
  }

  var sel = document.getElementById('mgs_current_selection');
  var old_opts = new Array();
  for (i=0; i<sel.options.length; i++) {
    old_opts[sel.options[i].value] = 1;
  }
  for (var i in opts) {
    if (! old_opts[i]) {
      sel.add(opts[i], null);
    }
  }
}

function ModelProcessData (input,column,id) {
  if (id == 0) {
    if (colnum == 2) {
      var nv = input.split("|");
      input = "<a style='cursor: pointer;' onclick='show_detail(null, \""+nv[0]+"\");'>"+nv[1]+"</a>";
    }
  }

  return input;
}
