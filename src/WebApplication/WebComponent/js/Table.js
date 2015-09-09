/* ---------------------------------- */
/*          Table Functions           */
/* ---------------------------------- */
var SORT_COLUMN_INDEX;
var OPERAND;
var HTML_REPLACE = new RegExp("<[^><]+>","g");
var HTML_REPLACE_COMPLETE = new RegExp("<.+>","g");
var table_list = new Array();
var table_data = new Array();
var table_filtered_data = new Array();
var table_onclick_data = new Array();
var table_highlight_data = new Array();
var table_visible_columns = new Array();
var table_supercolumns = new Array();
var table_combo_columns = new Array();
var table_input_columns_data = new Array();
var table_column_types = new Array();
var updating = 0;
var table_current_pivots = new Array();

// Return the name of the download script.
function dcgiPath() {
    var metaValue = document.getElementsByName("HTML_PATH");
    var retVal = "download.cgi";
    if (metaValue.length > 0) {
        retVal = metaValue[0].content;
        var len = retVal.length;
        while (retVal != "" && retVal.charAt(--len) != '/') {
            retVal = retVal.substring(0, len);
        }
        retVal += "download.cgi";
    }
    return retVal;
}

/* set the entire visible columns array at once */
function set_visible_columns (table_id, values) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }

  for ( a=0; a<table_visible_columns[data_index].length; a++ ) {
    var b = parseInt(a,10) + 1;
    if ( values[a] == 0 ) {
      document.getElementById(table_id + '_col_' + b).style.display = 'none';
      table_visible_columns[data_index][a] = 0;
    }
    else if ( values[a] == 1 ) {
      document.getElementById(table_id + '_col_' + b).style.display = '';
      table_visible_columns[data_index][a] = 1;
    } else {
      table_visible_columns[data_index][a] = -1;
    }
  }

  reload_table(table_id);
}


/* render a column visible */
function show_column (table_id, colindex) {
  var data_index;
  var colnum = parseInt(colindex,10) + 1;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  if (document.getElementById(table_id + '_col_' + colnum) != null) {
    table_visible_columns[data_index][colindex] = 1;
    document.getElementById(table_id + '_col_' + colnum).style.display = '';

    reload_table(table_id);
  }
}

/* render a column invisible */
function hide_column (table_id, colindex) {
  var data_index;
  var colnum = parseInt(colindex,10) + 1;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  if (document.getElementById(table_id + '_col_' + colnum) != null) {
    table_visible_columns[data_index][colindex] = 0;
    document.getElementById(table_id + '_col_' + colnum).style.display = 'none';
    
    reload_table(table_id);
  }
}

function switch_column_visibility (table_id, colindex) {
  var data_index;
  var colnum = parseInt(colindex,10) + 1;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  if (table_visible_columns[data_index][colindex] == 0) {
    table_visible_columns[data_index][colindex] = 1;
    document.getElementById(table_id + '_col_' + colnum).style.display = '';
  } else {
    table_visible_columns[data_index][colindex] = 0;
    document.getElementById(table_id + '_col_' + colnum).style.display = 'none';
  }

  reload_table(table_id);
}

function get_visibility_string (table_id) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }

  return table_visible_columns[data_index].join("@~");
}

/* if there are supercolumns present, this will make sure there colspan / visibility
is set correctly due to hidden columns */
function check_supercolumns (table_id) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }

  // check if we have to worry about supercolumns
  if (table_supercolumns[data_index] && table_supercolumns[data_index][0][0]) {
    var vc = table_visible_columns[data_index];
    var sc = table_supercolumns[data_index];
    var col_in_table = 0;
    for (curr_sc_num=0;curr_sc_num<sc.length;curr_sc_num++) {
      var sc_colspan = 0;
      for (h=0;h<sc[curr_sc_num][1];h++) {
	if (vc[col_in_table] == 1) {
	  sc_colspan++;
	}
	col_in_table++;
      }
      // set colspan of sc
      var curr_sc = document.getElementById('table_sc_' + table_id + '_' + curr_sc_num);
      if (sc_colspan) {
	curr_sc.style.display = '';
	curr_sc.colSpan = sc_colspan;
      } else {
	curr_sc.style.display = 'none'
      }
    }
  }
}

/* export the currently filtered table to a new window */
function export_table (id, unfiltered, strip_html, hide_invisible_columns) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var data_array;
  if (unfiltered) {
    data_array = table_data[data_index];
  } else {
    data_array = table_filtered_data[data_index];
  }

  var data_string = "";
  var column_visibility = table_visible_columns[data_index];

  // export column headers
  var headers = new Array;
  for (i=0;i<(data_array[0].length - 1);i++) {
    if (hide_invisible_columns && (column_visibility[i] == 0 || column_visibility[i] == "0")) {
      continue;
    }
    headers[headers.length] = document.getElementById('colname_'+id+'_col_'+(i+1)).innerHTML;
  }
  data_string = headers.join("\t") + "\n";
  data_string = data_string.replace(HTML_REPLACE_COMPLETE, '');

  // iterate through the data
  for (i=0;i<data_array.length;i++) {
    var curr_line = new Array();
    var pre_curr_line = new Array();
    if (hide_invisible_columns) {
      for (h=0;h<(data_array[i].length - 1);h++) {
	if (column_visibility[h] && column_visibility[h] != "0") {
	  pre_curr_line[pre_curr_line.length] = data_array[i][h];
	}
      }
    } else {
      pre_curr_line = data_array[i];
      pre_curr_line.pop();
    }
    if (strip_html) {
      for (h=0;h<pre_curr_line.length;h++) {
	curr_line[curr_line.length] = pre_curr_line[h].toString().replace(HTML_REPLACE, '');
      }
    } else {
      curr_line = pre_curr_line;
    }
    data_string = data_string + curr_line.join("\t") + "\n";
  }
  // If we're not stripping out HTML, then replace apostrophe with HTML apostrophe code.
  if (! strip_html) {
    var noapo = new RegExp("'","g");
    data_string = data_string.replace(noapo, "&#39;");
  }
  
    try {
	data_string = window.btoa(data);
    } catch (err) {
	var utftext = "";
	for(var n=0; n<data_string.length; n++) {
	    var c=data_string.charCodeAt(n);
	    if (c<128)
		utftext += String.fromCharCode(c);
            else if((c>127) && (c<2048)) {
		utftext += String.fromCharCode((c>>6)|192);
		utftext += String.fromCharCode((c&63)|128);}
	    else {
		utftext += String.fromCharCode((c>>12)|224);
		utftext += String.fromCharCode(((c>>6)&63)|128);
		utftext += String.fromCharCode((c&63)|128);}
	}
	data_string = window.btoa(utftext);
    }

    data_string = 'data:application/octet-stream;base64,'+data_string;
	
    var anchor = document.createElement('a');
    anchor.setAttribute('download', "table.tsv");
    anchor.setAttribute('href', data_string);
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
}

/* export the currently filtered table to a cgi form and submit it */
function export_table_form (table_id, field_id, form_id) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  var data_array = table_filtered_data[data_index];

  var row_array = new Array();
  for (i=0;i<data_array.length;i++) {
    row_array[i] = data_array[i].join("^");
  }
  var data_string = row_array.join("~");
  document.getElementById(field_id).value = data_string;
  document.getElementById(form_id).submit();

}

/* submit the form surrounding the table after filling
   in any input fields from input columns of the table */
function table_submit (id, form_name, submit_all, no_submit, button_name) {

  // get the space to put the input fields into
  var input_space = document.getElementById('table_input_space_'+id);

  // assign a variable to hold the input fields
  var input_fields = "<input type='hidden' name='" + button_name + "' value='1'>";

  // get the data
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  var data_array = table_input_columns_data[data_index];

  // get the column types
  var column_types = table_column_types[data_index];

  // fill the input space with the input data
  for (i=0;i<data_array.length;i++) {
    var row = data_array[i];
    for (h=0;h<row.length;h++) {
      if (column_types[h]) {
	if (submit_all || row[h] != table_data[data_index][i][h]) {
          if(typeof row[h] == "string") {
            row[h] = row[h].replace(/\'/g, "&#39;");
          }
	  input_fields += "<input type='hidden' name='ic_" + id + "_" + h + "' value='" + row[h] + "'>";
	}
      }
    }
  }
  input_space.innerHTML = input_fields;

  // submit the form
  if (! no_submit) {
    var table_form = document.getElementById(form_name);
    table_form.submit();
  }
}

/* execute the filter function if enter was pressed in a filter field */
function check_submit_filter (e, id) {
  if (e.keyCode == 13) {
    table_filter(id);
    return false;
  } else {
    return true;
  }
}

/* execute the filter function 2 (for combo boxes) */
function check_submit_filter2 (id, all) {
  if (all == 'all') {
    table_reset_filters(id);
  } else {
    if (! updating) {
      table_filter(id);
    }
  }
  return false;
}

/* setup the table for initial display of data */
function initialize_table (id, data) {
  updating = 1;
  // check if the table already exists
  var data_index = table_list.length;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  table_list[data_index] = id;

  if (data) {
    table_data[data_index] = data;

    var visible_data = document.getElementById("table_visible_columns_" + id).value;
    table_visible_columns[data_index] = visible_data.split(/@~/);
    var combo_columns = document.getElementById("table_combo_columns_" + id).value;
    table_combo_columns[data_index] = combo_columns.split(/@~/);
    var column_types = document.getElementById("table_column_types_" + id).value;
    table_column_types[data_index] = column_types.split(/@~/);
    for (var i=0;i<data.length;i++) {
      for (var h=0;h<data[i].length-1;h++) {
	if (table_column_types[data_index][h]) {
	  if (! table_input_columns_data[data_index][i]) {
	    table_input_columns_data[data_index][i] = [];
	  }
	  table_input_columns_data[data_index][i][h] = data[i][h];
	}
      }
    }

    table_filter(id);
  } else if (document.getElementById("table_data_" + id)) {
    data = document.getElementById("table_data_" + id).value;
    var re1 = new RegExp("@1", "g");
    var re2 = new RegExp("@2", "g");
    data = data.replace(re1, "'");
    data = data.replace(re2, "\"");

    var onclick_data = document.getElementById("table_onclicks_" + id).value;
    onclick_data = onclick_data.replace(re1, "'");
    onclick_data = onclick_data.replace(re2, "\"");

    var highlight_data = document.getElementById("table_highlights_" + id).value;
    var visible_data = document.getElementById("table_visible_columns_" + id).value;
    var combo_columns = document.getElementById("table_combo_columns_" + id).value;
    var column_types = document.getElementById("table_column_types_" + id).value;
    var index = data_index;
    var supercolumns = document.getElementById("table_sc_" + id).value;
    table_supercolumns[index] = new Array();
    var sc_info = supercolumns.split(/\^/);
    for (n=0;n<sc_info.length;n++) {
      table_supercolumns[index][n] = sc_info[n].split(/~/);
    }
    table_data[index] = new Array();
    table_visible_columns[index] = visible_data.split(/@~/);
    table_onclick_data[index] = new Array();
    table_highlight_data[index] = new Array();
    table_combo_columns[index] = combo_columns.split(/@~/);
    table_column_types[index] = column_types.split(/@~/);
    table_input_columns_data[index] = new Array();
    var rows = data.split(/@~/);
    var onclick_rows = onclick_data.split(/@~/);
    var highlight_rows = highlight_data.split(/@~/);
    var numrows = rows.length;
    for (i=0; i<numrows; i++) {
      var cells = rows[i].split(/@\^/);
      var onclick_cells = onclick_rows[i].split(/@\^/);
      var highlight_cells = highlight_rows[i].split(/@\^/);
      var numcols = cells.length;
      table_data[index][i] = new Array();
      table_onclick_data[index][i] = new Array();
      table_highlight_data[index][i] = new Array();
      table_input_columns_data[index][i] = new Array();
      for (h=0; h<numcols; h++) {
	table_data[index][i][h] = cells[h];
	table_onclick_data[index][i][h] = onclick_cells[h];
	table_highlight_data[index][i][h] = highlight_cells[h];
	if (table_column_types[index][h]) {
	  table_input_columns_data[index][i][h] = cells[h];
	}
      }
      table_data[index][i][table_data[index][i].length] = i;
    }
    table_filter(id);
  }

  /* register table event handlers */
  var all_cells = document.getElementsByName('table_cell');
  for (i=0;i<all_cells.length;i++) {
    all_cells[i].onclick = table_onclick;
    all_cells[i].setAttribute("onmouseover", "hover(event, '"+all_cells[i].id+"');");
  }
	updating = 0;
}

/* handle the click events of table cells */
function table_onclick (e) {
  var cell = e.currentTarget.id;
  var m = cell.split(/_/);
  var id = m[1];
  var col = parseInt(m[2],10);

  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var start = parseInt(document.getElementById('table_start_' + id).value,10);
  var row = parseInt(m[3],10);

  var loc = table_onclick_data[data_index][row][col];
  if (loc) {
    window.top.location = loc;
  }

}

/* filter the data of the table */
function table_filter (id) {
  var numcols      = parseInt(document.getElementById('table_cols_' + id).value,10);
  var rows_perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var data_array = marray_clone(table_data[data_index]);

  /* check if we need to pivot */
  if (table_current_pivots[data_index]) {
    if (table_current_pivots[data_index][0] == 'plus') {
      pivot_plus(id, table_current_pivots[data_index][1], table_current_pivots[data_index][2], table_current_pivots[data_index][3], data_array, null, null);
    } else {
      pivot(id, table_current_pivots[data_index][1], table_current_pivots[data_index][2], data_array);
    }
    data_array = marray_clone(table_filtered_data[data_index]);
  }

  /* do the filtering step for each column that has a value entered in its filter box */
  for (z=0; z<numcols; z++) {
    var filter = document.getElementById('table_' + id + '_operand_' + (z + 1));
    SORT_COLUMN_INDEX = z;
    if (filter) {
      if (filter.value != '') {
	OPERAND = filter.value;
	operator = document.getElementById('table_' + id + '_operator_' + (z + 1)).value;
	if (operator == 'equal') {
	  data_array = array_filter(data_array, element_equal);
	} else if (operator == 'unequal') {
	  data_array = array_filter(data_array, element_unequal);
	} else if (operator == 'like') {
	  OPERAND = reg_escape(OPERAND);
	  data_array = array_filter(data_array, element_like);
	} else if (operator == 'unlike') {
	  OPERAND = reg_escape(OPERAND);
	  data_array = array_filter(data_array, element_unlike);
	} else if (operator == 'less') {
	  data_array = array_filter(data_array, element_less);
	} else if (operator == 'more') {
	  data_array = array_filter(data_array, element_more);
	} else if (operator == 'empty') {
	  data_array = array_filter(data_array, element_empty);
	} else if (operator == 'notempty') {
	  data_array = array_filter(data_array, element_notempty);
	}
      }
    }
  }

  /* put the array back into the string */
  newnumrows = data_array.length;
  document.getElementById('table_rows_' + id).value = newnumrows;
  table_filtered_data[data_index] = data_array;

  /* call a layout of the table */
  var myStart = document.getElementById('table_start_' + id).value;
  table_goto(id, myStart);
}

/* add a new column to the table */
function table_append_data (id, column_header, data) {

  // get the table data
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  // transform string data to array
  var re1 = new RegExp("@1", "g");
  var re2 = new RegExp("@2", "g");
  data = data.replace(re1, "'");
  data = data.replace(re2, "\"");
  column_header = column_header.replace(re1, "'");
  column_header = column_header.replace(re2, "\"");
  data = data.split(/@\^/);

  // make sure the new column is visible
  table_visible_columns[data_index][table_visible_columns[data_index].length] = 1;

  // get the old data
  var old_data = table_data[data_index];
  var old_onclick = table_onclick_data[data_index];
  var old_highlight = table_highlight_data[data_index];

  for (i=0; i<old_data.length; i++) {
    var rownum = old_data[i][old_data[i].length - 1];
    old_data[i][old_data[i].length - 1] = data[i];
    old_data[i][old_data[i].length] = rownum;
    old_highlight[i][old_highlight[i].length] = "";
    old_onclick[i][old_onclick[i].length] = "";
  }

  // insert the column header
  var table = document.getElementById('table_'+id);
  var last_cell = table.rows[0].cells[table.rows[0].cells.length - 1];
  var puff = 0;
  if (last_cell.title == 'show / hide columns') {
    puff = 1;
  }
  var new_cell = table.rows[0].insertCell(table.rows[0].cells.length - puff);
  new_cell.className = 'table_first_row';
  var nodename = id+'_col_'+(table.rows[0].childNodes.length);
  new_cell.setAttribute('name', nodename);
  new_cell.id = nodename;
  new_cell.innerHTML = column_header;

  table_first(id);
}

/* extract some or all data from the table and package it to a string */
function table_extract_data (id, filters, nostrip) {

  // get the table data
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  // make a copy of the table data
  var data_array = new Array();
  for (i=0;i<table_data[data_index].length;i++) {
    data_array[i] = table_data[data_index][i];
  }

  // check for filters
  if (filters) {
    var filter_array = filters.split("^");
    for (z=0; z<filter_array.length; z++) {
      var curr_filter = filter_array[z].split("~");
      SORT_COLUMN_INDEX = curr_filter[0];
      OPERAND = curr_filter[1];
      operator = curr_filter[2];
      if (operator == 'equal') {
	data_array = array_filter(data_array, element_equal);
      } else if (operator == 'unequal') {
	data_array = array_filter(data_array, element_unequal);
      } else if (operator == 'like') {
	OPERAND = reg_escape(OPERAND);
	data_array = array_filter(data_array, element_like);
      } else if (operator == 'unlike') {
	OPERAND = reg_escape(OPERAND);
	data_array = array_filter(data_array, element_unlike);
      } else if (operator == 'less') {
	data_array = array_filter(data_array, element_less);
      } else if (operator == 'more') {
	data_array = array_filter(data_array, element_more);
      }
    }
  }

  // package the result data
  var data_string = "";
  for (i=0;i<data_array.length;i++) {
    data_array[i].pop();
    data_string = data_string + data_array[i].join("~") + "^";
  }
  data_string = data_string.slice(0,-1);

  // check whether to strip html
  if (! nostrip) {
    data_string = data_string.replace(HTML_REPLACE, '');
  }

  // encode the string
  data_string = encodeURIComponent(data_string);

  // return the result
  return data_string;
}

/* extract some or all data from a column and package it to a string */
function column_extract_data (id, col, unfiltered, nostrip) {
    
  // get the table data
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var data_array;
  if (unfiltered) {
    data_array = table_data[data_index];
  } else {
    data_array = table_filtered_data[data_index];
  }

  // stringify the column data
  var col_array = new Array();
  for (i=0;i<data_array.length;i++) {
    col_array[i] = data_array[i][col];
  }
  var data_string = col_array.join("~");

  // check whether to strip html
  if (! nostrip) {
    data_string = data_string.replace(HTML_REPLACE, '');
  }

  // encode the string
  data_string = encodeURIComponent(data_string);
  
  // return the result
  return data_string;
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

/* reset the filters of the table */
function table_reset_filters (id) {
  var numcols = parseInt(document.getElementById('table_cols_' + id).value,10);

  /* reset all filters */
  for (z=0; z<numcols; z++) {
    var filter = document.getElementById('table_' + id + '_operand_' + (z + 1));
    var operator = document.getElementById('table_' + id + '_operator_' + (z + 1));
    var is_all_or_nothing = 0;
    if (operator) {
      if (operator.type == 'select-one') {
	if (operator.options.length == 3) {
	  if (operator.options[2].value == 'notempty') {
	    is_all_or_nothing = 1;
	  }
      	}
	operator.selectedIndex = 0;
	check_default_selection(operator);
      }
    }
    if (filter) {
      if (filter.type == 'select-one') {
	filter.selectedIndex = 0;
      } else {
	if (! is_all_or_nothing) {
	  filter.value = '';
	}
      }
    }
  }
  table_filter(id);
}

/* sort the given table to the given col and order */
function table_sort (id, col, dir) {
  /* get information from document */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  var data_array = table_filtered_data[data_index];
  var numcols = parseInt(document.getElementById('table_cols_' + id).value,10) + 1;
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);
  if (dir == null) {
    dir = document.getElementById('table_sortdirection_' + id).value;
  }
  col--;

  SORT_COLUMN_INDEX = col;

  /* determine data type */
  var sample_cell = '';
  for (h=0;h<data_array.length;h++) {
    if (! data_array[h][col].match(/^\s+$/) ) {
      sample_cell = data_array[h][col].replace(HTML_REPLACE, "");
      break;
    }
  }

  var sortfn = sort_caseinsensitive_up;
  if (dir == "up") {
    document.getElementById('table_sortdirection_' + id).value = "down";
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) sortfn = sort_date_up;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) sortfn = sort_date_up;
    if (sample_cell.match(/^[+-]{0,1}[\d,]+\.{0,1}\d*$/)) sortfn = sort_numeric_up;
    if (sample_cell.match(/^\d+\.{1}\d+e[+-]{1}\d+$/)) sortfn = sort_evalue_up;
    if (sample_cell.match(/^fig\|\d+\.\d+\.\w+\.\d+$/)) sortfn = sort_figid_up;
  } else {
    document.getElementById('table_sortdirection_' + id).value = "up";
    sortfn = sort_caseinsensitive_down;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) sortfn = sort_date_down;
    if (sample_cell.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) sortfn = sort_date_down;
    if (sample_cell.match(/^[+-]{0,1}[\d,]+\.{0,1}\d*$/)) sortfn = sort_numeric_down;
    if (sample_cell.match(/^\d+\.{1}\d+e[+-]{1}\d+$/)) sortfn = sort_evalue_down;
    if (sample_cell.match(/^fig\|\d+\.\d+\.\w+\.\d+$/)) sortfn = sort_figid_down;
  }

  /* execute sort */
  data_array.sort(sortfn);

  /* put the array back into the string */
  table_filtered_data[data_index] = data_array;

  /* call a layout of the table */
  table_first(id);

}

/* move the table to a selected position */
function table_goto (id, start) {
  start = parseInt(start,10);
  var start_element = document.getElementById('table_start_' + id);
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);

  var stop = start + perpage;
  var show_next = 1;
  var show_prev = 1;
  if ((start + perpage) >= numrows) {
    start = numrows - perpage;
    stop = numrows;
    show_next = 0;
  }
  if (start <= 0) {
    start = 0;
    stop = perpage;
    if (stop >= numrows) stop = numrows;
    show_prev = 0;
  }

  start_element.value = start;

  fill_table(id, start, stop, show_prev, show_next);

}

/* move to the next page of the selected table */
function table_next (id) {
  var start   = parseInt(document.getElementById('table_start_' + id).value,10);
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);

  start = start + perpage;
  var show_next = 1;
  var stop = start + perpage;
  if ((start + perpage) >= numrows) {
    start = numrows - perpage;
    stop = numrows;
    show_next = 0;
  }

  document.getElementById('table_start_' + id).value = start;

  fill_table(id, start, stop, 1, show_next);

}

/* move to the previous page of the selected table */
function table_prev (id) {
  var start   = parseInt(document.getElementById('table_start_' + id).value,10);
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);

  var stop = start;
  start = start - perpage;
  var show_prev = 1;
  if (start <= 0) {
    start = 0;
    stop = perpage;
    show_prev = 0;
  }

  document.getElementById('table_start_' + id).value = start;

  fill_table(id, start, stop, show_prev, 1);

}

/* move to the first page of the selected table */
function table_first (id) {
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);

  var start = 0;
  var stop = start + perpage;
  var show_next = 1;
  if (stop >= numrows) {
    stop = numrows;
    show_next = 0;
  }

  document.getElementById('table_start_' + id).value = start;

  fill_table(id, start, stop, 0, show_next);

}

/* move to the last page of the selected table */
function table_last (id) {
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);

  var stop = numrows;
  var start = numrows - perpage;
  var show_prev = 1;
  if (start <= 0) {
    start = 0;
    show_prev = 0;
  }

  document.getElementById('table_start_' + id).value = start;

  fill_table(id, start, stop, show_prev, 0);

}

/* reload table with current values */
function reload_table (id) {

  /* get location values for fill_table */
  var start   = parseInt(document.getElementById('table_start_' + id).value,10);
  var perpage = parseInt(document.getElementById('table_perpage_' + id).value,10);
  var numrows = parseInt(document.getElementById('table_rows_' + id).value,10);
  var stop = start + perpage;
  var show_next = 1;
  if (stop >= numrows) {
    stop = numrows;
    show_next = 0;
  }
  var show_prev = 1;
  if (start <= 0) {
    start = 0;
    show_prev = 0;
  }

  /* call fill table */
  fill_table(id, start, stop, show_prev, show_next);

}

/* get the filtered data from the document and fill the table accordingly */
function fill_table (id, start, stop, show_prev, show_next) {
  /* check for the visibility / colspan of supercolumns */
  check_supercolumns(id);

  /* This is a little nasty. Since InternetExplorer chooses to make the innerHTML
     property of Tables readonly, we have to use the old style if IE is used */
  var IE_MODE = false;
  if (navigator.userAgent.toLowerCase().indexOf("msie") != -1) {
    IE_MODE = true;
  }

  var table = "";
  var sc = null;
  var fr = null;

  if (IE_MODE) {
    table = document.getElementById('table_' + id).firstChild;
    numoldrows = table.childNodes.length - 1;
    for (i=0; i<numoldrows; i++) {
      if (table.lastChild.firstChild.className != 'table_first_row') {
	table.removeChild(table.lastChild);
      }
    }
  } else {
    /* copy the header of the old table */
    if (document.getElementById('table_'+id+'_supercolumns')) {
      sc = document.getElementById('table_'+id+'_supercolumns').cloneNode(true);
      fr = document.getElementById('table_'+id+'_supercolumns').nextSibling.cloneNode(true);
    } else {
      fr = document.getElementById('table_' + id).firstChild.firstChild.cloneNode(true);
    }
  }

  /* get data from the filtered data field */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var data_array = table_filtered_data[data_index];
  var visible_columns = table_visible_columns[data_index];
  var combo_columns = table_combo_columns[data_index];

  /* get the id of the hover component of the table */
  var hover_id = document.getElementById('table_hoverid_'+id).value;

  /* determine total number of rows */
  var numrows = data_array.length;
  document.getElementById('table_rows_' + id).value = numrows;

  /* save the branch information */
  var current_branch = new Array();
  var number_of_cols = 0;
  if (data_array[0]) {
    number_of_cols = data_array[0].length;
  }
  for (i=0;i<number_of_cols;i++) {
    current_branch[i] = ["",""];
  }

  /* iterate through the rows of the table */
  for (var rownum=start; rownum<stop; rownum++) {

    /* get the cell data for this row */
    var cells = data_array[rownum];
    var relative_rownum = cells[number_of_cols - 1];

    /* create the row element */
    var celltype = "table_row";
    var classname = 'odd_row';
    if ((rownum % 2) == 1) {
      classname = 'even_row';
    }
    var row;
    if (IE_MODE) {
      row = document.createElement("tr");
      row.name = id + "_tablerow";
      row.id = id + "_row_" + rownum;
      row.className = 'odd_row';
    } else {
      row = "<tr name='"+id+"_tablerow' id='"+id+"_row_"+rownum+"' class='"+classname+"'>";
    }

    /* iterate through the cells of this row */
    for (colnum=0; colnum<(cells.length - 1); colnum++) {

      /* this column is invisible, go to next */
      if (visible_columns[colnum] < 1) {
      	continue;
      }

      /* save cell data */
      var cell_data = ProcessData(cells[colnum],colnum,id);

      /* check for an input column */
      if (table_column_types[data_index][colnum]) {

	var re = new RegExp('@#');
        var cell_id = id + "_" + colnum + "_" + relative_rownum;

	/* this is an input column, check what kind */
	if (table_column_types[data_index][colnum] == 'checkbox') {
	  /* this is a checkbox column */
	  var checked = "";
	  if (table_input_columns_data[data_index][relative_rownum][colnum] == 1) {
	    checked = "checked='checked' ";
	  }
	  cell_data = "<input type='checkbox' id='" + cell_id + "' " + checked + "onchange='update_input_data(this.id);'>";
	} else if (table_column_types[data_index][colnum] == 'hidden') {
	  var this_data = table_input_columns_data[data_index][relative_rownum][colnum];
	  cell_data = "<input type='hidden' id='" + cell_id + "' value='" + this_data + "'>" + this_data;
	} else if (table_column_types[data_index][colnum] == 'textfield') {
          var value = table_input_columns_data[data_index][relative_rownum][colnum];
          value = value.replace(/\'/g, "&#39;");
	  cell_data = "<input type='text' id='" + cell_id + "' value='" + value +
		      "' style='width:100%;' onchange='update_input_data(this.id);'>";
	} else if (table_column_types[data_index][colnum].match(re)) {
	  var entries = table_column_types[data_index][colnum].split(/@#/);
	  var select_cell = "<select id='" + cell_id + "' style='width:100%;' onchange='update_input_data(this.id);'>";
	  for (k=0;k<entries.length;k++) {
	    var cell_selected = "";
	    if (entries[k] == table_input_columns_data[data_index][relative_rownum][colnum]) {
	      cell_selected = " selected=selected";
	    }
	    select_cell = select_cell + "<option value='" + entries[k] + "'" + cell_selected + ">" + entries[k] + "</option>";
	  }
	  select_cell = select_cell + "</select>";
	  cell_data = select_cell;
	}
      }

      if (IE_MODE) {
	/* create the cell element */
	var td = document.createElement("td");
	var span = document.createElement("span");
	var rel_span = "cell_" + id + "_" + colnum + "_" + relative_rownum;
	span.id = rel_span;
	span.name = "table_cell";
	span.innerHTML = cell_data;
	span.onclick = table_onclick;
	span.setAttribute("onmouseover", "hover(event, '"+rel_span+"');");
	if (table_onclick[data_index] && table_onclick_data[data_index][relative_rownum] && table_onclick_data[data_index][relative_rownum]) {
	  if (table_onclick_data[data_index][relative_rownum][colnum] != "") {
	    span.style.cursor = 'pointer';
	  }
	}
	td.appendChild(span);
	td.className = celltype;
	var tdname = document.createAttribute("name");
	tdname.nodeValue = id + '_col_' + (colnum + 1);
	td.setAttributeNode(tdname);
	row.appendChild(td);

	/* check for cell highlighting */
	if (table_highlight_data[data_index] && table_highlight_data[data_index][relative_rownum]) {
	  if (table_highlight_data[data_index][relative_rownum][colnum]) {
	    td.style.backgroundColor = table_highlight_data[data_index][relative_rownum][colnum];
	  }
	}
      } else {

	/* check for cell highlighting */
	var bgcolor = "";
	if (table_highlight_data[data_index] && table_highlight_data[data_index][relative_rownum] && table_highlight_data[data_index][relative_rownum][colnum]) {
	  bgcolor = " style='background-color: " + table_highlight_data[data_index][relative_rownum][colnum] + "'";
	}

	/* calculate the id of the cell */
	var cell_id = "cell_" + id + "_" + colnum + "_" + relative_rownum;

	/* check for click event */
	var click = "";
	if (table_onclick_data[data_index] && table_onclick_data[data_index][relative_rownum] && table_onclick_data[data_index][relative_rownum][colnum]) {
	  click = " onclick='table_onclick' style='cursor: pointer;'";
	} else {
	  click = " onclick='hover(event, \""+cell_id+"\", \""+hover_id+"\");'";
	}

	var tooltip = " onmouseover='hover(event, \""+cell_id+"\", \""+hover_id+"\");'";

	/* create the cell element */
	row += "<td class='"+celltype+"' name='"+id+"_col_"+(colnum + 1)+"'"+bgcolor+click+tooltip+" id='"+cell_id+"'>"+cell_data+"</td>";

      }
    }

    /* append the row to the table */
    if (IE_MODE) {
      table.appendChild(row);
    } else {
      row += "</tr>";
      table += row;
    }
  }

  if (! IE_MODE) {
    var t = document.getElementById('table_' + id);
    t.firstChild.innerHTML = table;

    t.firstChild.insertBefore(fr, t.firstChild.firstChild);
    if (sc) {
      t.firstChild.insertBefore(sc, t.firstChild.firstChild);
    }
  }

  /* get all navigation elements */
  nexts = document.getElementsByName('table_next_' + id);
  lasts = document.getElementsByName('table_last_' + id);
  prevs = document.getElementsByName('table_prev_' + id);
  firsts = document.getElementsByName('table_first_' + id);

  /* set visibility of navigation elements */
  if (show_next) {
    for (i=0; i< nexts.length; i++) { nexts[i].style.display = 'inline'; }
    for (i=0; i< lasts.length; i++) { lasts[i].style.display = 'inline'; }
  } else {
    for (i=0; i< nexts.length; i++) { nexts[i].style.display = 'none'; }
    for (i=0; i< lasts.length; i++) { lasts[i].style.display = 'none'; }
  }
  if (show_prev) {
    for (i=0; i< prevs.length; i++) { prevs[i].style.display = 'inline'; }
    for (i=0; i< firsts.length; i++) { firsts[i].style.display = 'inline'; }
  } else {
    for (i=0; i< prevs.length; i++) { prevs[i].style.display = 'none'; }
    for (i=0; i< firsts.length; i++) { firsts[i].style.display = 'none'; }
  }

  /* set values of location displays */
  var start_top = document.getElementById('table_start_top_' + id);
  var start_bottom = document.getElementById('table_start_bottom_' + id);
  if (stop == 0) {
    if (start_top) {
      start_top.innerHTML = 0;
    }
    if (start_bottom) {
      start_bottom.innerHTML = 0;
    }
  } else {
    if (start_top) {
      start_top.innerHTML = start + 1;
    }
    if (start_bottom) {
      start_bottom.innerHTML = start + 1;
    }
  }
  var stop_top = document.getElementById('table_stop_top_' + id);
  var stop_bottom = document.getElementById('table_stop_bottom_' + id);
  if (stop_top) {
    stop_top.innerHTML = stop;
  }
  if (stop_bottom) {
    stop_bottom.innerHTML = stop;
  }
  var total_top = document.getElementById('table_total_top_' + id);
  var total_bottom = document.getElementById('table_total_bottom_' + id);
  if (stop == 0) {
    if (total_top) {
      total_top.innerHTML = 0;
    }
    if (total_bottom) {
      total_bottom.innerHTML = 0;
    }
  } else {
    if (total_top) {
      total_top.innerHTML = numrows;
    }
    if (total_bottom) {
      total_bottom.innerHTML = numrows;
    }
  }

  /* filter the comboboxes */
	updating = 1;
	for (i=0; i<combo_columns.length; i++) {
		var combo_content_unique = new Array();
		var combo_content = new Array();
		for (h=0; h<data_array.length; h++) {
			var hh = data_array[h][combo_columns[i] - 1];
			if (hh) {
				hh = hh.replace(HTML_REPLACE, "");
			}
			combo_content_unique[hh] = 1;
		}
		for (h in combo_content_unique){
			combo_content.push(h);
		}
		combo_content.sort(sort_combobox);
		var select_box = document.getElementById("table_" + id + "_operand_" + combo_columns[i]);
		if (select_box) {
			while (select_box.options.length > 0) {
				select_box.remove(0);
			}
			
			try {
				select_box.add(new Option('all', ''), null);  // standards compliant browsers
			}
			catch(ex) {
				select_box.add(new Option('all', ''), 0); // IE only
			}
			for (h in combo_content) {
				try {
					select_box.add(new Option(combo_content[h], combo_content[h]), null);  // standards compliant browsers
				}
				catch(ex) {
					select_box.add(new Option(combo_content[h], combo_content[h]), 0); // IE only
				}
			}
			
			if (select_box.options.length <3) {
				select_box.selectedIndex = 1;
			}
		}
	}
	updating = 0;	
}

/* update the cell data of a changed input cell */
function update_input_data (location) {

  /* parse id, col and row from the input parameter */
  var m = location.split("_");
  var id = m[0];
  var col = m[1];
  var row = m[2];
  var input = document.getElementById(location);

  /* get the table data index */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  /* get the type of input box */
  var type = table_column_types[data_index][col];
  var re = new RegExp('@#');

  if (type == 'checkbox') {
    if (input.checked) {
      table_input_columns_data[data_index][row][col] = 1;
    } else {
      table_input_columns_data[data_index][row][col] = 0;
    }
  } else if (type == 'textfield') {
    table_input_columns_data[data_index][row][col] = input.value;
  } else if (type.match(re)) {
    table_input_columns_data[data_index][row][col] = input.options[input.selectedIndex].value;
  }
}

/* select / deselect all input checkboxes of a checkbox input column */
function table_select_all_checkboxes (id, col, sel, filtered) {
  /* get the table data index */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  if (table_column_types[data_index][col] == 'checkbox') {
    var data = table_data[data_index];
    if (filtered && sel) {
      data = table_filtered_data[data_index];
      var num_rows = table_filtered_data[data_index].length;
    } else {
      var num_rows = table_data[data_index].length;
    }
    for (row=0; row<num_rows; row++) {
      if (sel) {
	table_input_columns_data[data_index][data[row][data[row].length-1]][col] = 1;
      } else {
	table_input_columns_data[data_index][data[row][data[row].length-1]][col] = 0;
      }
    }
  }
  table_goto(id, document.getElementById('table_start_' + id).value);
}

/* apply the changes in column visibility as selected in the column select */
function apply_column_select (id) {
  /* get the table data index */
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var new_vis = new Array();
  for (i=0; i<table_visible_columns[data_index].length; i++) {
    if (document.getElementById('tcsel'+id+'_'+i)) {
      if (document.getElementById('tcsel'+id+'_'+i).innerHTML.length < 7) {
	new_vis[i] = 0;
      } else {
	new_vis[i] = 1;
      }
    } else {
      new_vis[i] = table_visible_columns[data_index][i];
    }
  }

  document.getElementById('tscs'+id).style.display = "none";
  set_visible_columns(id, new_vis);
}

/* sort functions */
function sort_combobox (a, b){
	if(typeof a == 'string' && typeof b == 'string'){
		var aa = a.toLowerCase().replace(HTML_REPLACE, "");
		var bb = b.toLowerCase().replace(HTML_REPLACE, "");
		if (aa=='unknown') return 1;
		if (aa==bb) return 0;
		if (aa<bb) return -1;
		return 1;
	} else {
		return 0;
	}
}

function sort_caseinsensitive_up (a, b) {
  aa = a[SORT_COLUMN_INDEX].toLowerCase().replace(HTML_REPLACE, "");
  bb = b[SORT_COLUMN_INDEX].toLowerCase().replace(HTML_REPLACE, "");
  if (aa==bb) return 0;
  if (aa<bb) return -1;
  return 1;
}

function sort_caseinsensitive_down (b, a) {
  aa = a[SORT_COLUMN_INDEX].toLowerCase().replace(HTML_REPLACE, "");
  bb = b[SORT_COLUMN_INDEX].toLowerCase().replace(HTML_REPLACE, "");
  if (aa==bb) return 0;
  if (aa<bb) return -1;
  return 1;
}

function sort_date_up (a, b) {
  aa = a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "");
  bb = b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "");
  if (aa.length == 10) {
    dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
  } else {
    yr = aa.substr(6,2);
    if (parseInt(yr,10) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
    dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
  }
  if (bb.length == 10) {
    dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
  } else {
    yr = bb.substr(6,2);
    if (parseInt(yr,10) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
    dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
  }
  if (dt1==dt2) return 0;
  if (dt1<dt2) return -1;
  return 1;
}

function sort_date_down (b, a) {
  aa = a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "");
  bb = b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "");
  if (aa.length == 10) {
    dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
  } else {
    yr = aa.substr(6,2);
    if (parseInt(yr,10) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
    dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
  }
  if (bb.length == 10) {
    dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
  } else {
    yr = bb.substr(6,2);
    if (parseInt(yr,10) < 50) { yr = '20'+yr; } else { yr = '19'+yr; }
    dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
  }
  if (dt1==dt2) return 0;
  if (dt1<dt2) return -1;
  return 1;
}

function sort_numeric_up (a, b) {
  aa = parseFloat(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "").replace(/,/g, ""));
  if (isNaN(aa)) return 1;
  bb = parseFloat(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "").replace(/,/g, ""));
  if (isNaN(bb)) return -1;
  return aa-bb;
}

function sort_numeric_down (b, a) {
  aa = parseFloat(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "").replace(/,/g, ""));
  if (isNaN(aa)) return -1;
  bb = parseFloat(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, "").replace(/,/g, ""));
  if (isNaN(bb)) return 1;
  return aa-bb;
}

function sort_figid_up (a, b) {
  var re = /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/;
  var aa = re.exec(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  var bb = re.exec(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  if (parseFloat(aa[1]) > parseFloat(bb[1])) {
    return 1;
  }
  if (parseFloat(aa[1]) < parseFloat(bb[1])) {
    return -1;
  }
  if (aa[2] > bb[2]) {
    return 1;
  }
  if (aa[2] < bb[2]) {
    return -1;
  }
  if (parseInt(aa[3],10) > parseInt(bb[3],10)) {
    return 1;
  }
  if (parseInt(aa[3],10) < parseInt(bb[3],10)) {
    return -1;
  }
  return 0;
}

function sort_figid_down (a, b) {
  var re = /^fig\|(\d+\.\d+)\.(\w+)\.(\d+)$/;
  var aa = re.exec(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  var bb = re.exec(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  if (parseFloat(aa[1]) > parseFloat(bb[1])) {
    return -1;
  }
  if (parseFloat(aa[1]) < parseFloat(bb[1])) {
    return 1;
  }
  if (aa[2] > bb[2]) {
    return -1;
  }
  if (aa[2] < bb[2]) {
    return 1;
  }
  if (parseInt(aa[3],10) > parseInt(bb[3],10)) {
    return -1;
  }
  if (parseInt(aa[3],10) < parseInt(bb[3],10)) {
    return 1;
  }
  return 0;
}

function sort_evalue_up (a, b) {
  var re = new RegExp(/^(\d+\.{1}\d+)e([+-]{1})(\d+)$/);
  var aa = re.exec(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  var bb = re.exec(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  if (aa[2]=='+') {
    if (bb[2]=='-') {
      return 1;
    } else if (parseFloat(aa[3])<parseFloat(bb[3])) {
      return -1;
    } else if (parseFloat(aa[3])>parseFloat(bb[3])) {
      return 1;
    } else {
      if (parseFloat(aa[1])<parseFloat(bb[1])) {
	return -1;
      } else if (parseFloat(aa[1])>parseFloat(bb[1])) {
	return 1;
      } else {
	return 0;
      }
    }
  } else {
    if (bb[2]=='+') {
      return -1;
    } else if (parseFloat(aa[3])<parseFloat(bb[3])) {
      return 1;
    } else if (parseFloat(aa[3])>parseFloat(bb[3])) {
      return -1;
    } else {
      if (parseFloat(aa[1])<parseFloat(bb[1])) {
	return 1;
      } else if (parseFloat(aa[1])>parseFloat(bb[1])) {
	return -1;
      } else {
	return 0;
      }
    }
  }
}

function sort_evalue_down (b, a) {
  var re = new RegExp(/^(\d+\.{1}\d+)e([+-]{1})(\d+)$/);
  var aa = re.exec(a[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  var bb = re.exec(b[SORT_COLUMN_INDEX].replace(HTML_REPLACE, ""));
  if (aa[2]=='+') {
    if (bb[2]=='-') {
      return 1;
    } else if (parseFloat(aa[3])<parseFloat(bb[3])) {
      return -1;
    } else if (parseFloat(aa[3])>parseFloat(bb[3])) {
      return 1;
    } else {
      if (parseFloat(aa[1])<parseFloat(bb[1])) {
	return -1;
      } else if (parseFloat(aa[1])>parseFloat(bb[1])) {
	return 1;
      } else {
	return 0;
      }
    }
  } else {
    if (bb[2]=='+') {
      return -1;
    } else if (parseFloat(aa[3])<parseFloat(bb[3])) {
      return 1;
    } else if (parseFloat(aa[3])>parseFloat(bb[3])) {
      return -1;
    } else {
      if (parseFloat(aa[1])<parseFloat(bb[1])) {
	return 1;
      } else if (parseFloat(aa[1])>parseFloat(bb[1])) {
	return -1;
      } else {
	return 0;
      }
    }
  }
}

/* filter functions */
function array_filter (data, method) {
    var new_array = [];
    var orig_length = data.length;

    for (i=0; i<orig_length; i++) {
      var cell = data[i][SORT_COLUMN_INDEX].replace(HTML_REPLACE, '');
      if (method(cell)) {
	new_array[new_array.length] = data[i];
      }
    }

    return new_array;
}

function element_like(element) {
    re = new RegExp(OPERAND, "i");
    return (re.test(element));
}

function element_unlike(element) {
    re = new RegExp(OPERAND, "i");
    return (!re.test(element));
}

function element_equal(element) {
    return (element == OPERAND);
}

function element_unequal(element) {
    return (element != OPERAND);
}

function element_less(element) {
    if (element.match(/^[+-]{0,1}[\d\.]+$/)) {
	return (parseFloat(element) < parseFloat(OPERAND));
    }
    return (element < OPERAND);
}

function element_more(element) {
    if (element.match(/^[+-]{0,1}[\d\.]+$/)) {
	return (parseFloat(element) > parseFloat(OPERAND));
    }
    return (element > OPERAND);
}

function element_empty(element) {
  if (element.match(/\S+/)) {
    return 0;
  } else {
    return 1;
  }
}

function element_notempty(element) {
  if (element.match(/\S+/)) {
    return 1;
  } else {
    return 0;
  }
}

/* -------------------------------------------------------------------------- */


// make sure that the browser remembers which selection option was chosen
function check_default_selection (which) {
  for (i=0;i<which.options.length;i++) {
    which.options[i].defaultSelected=false;
  }
  which.options[which.selectedIndex].defaultSelected=true;
}

function ProcessData (input,column,ID) {
  if(typeof window.ModelProcessData == 'function') {
    return ModelProcessData(input,column,ID);
  }
  return input;
}

// Pivot-Function
function pivot (id, pivot_col, value_col, tdata) {
  // get the table data index
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  // remember this pivot
  table_current_pivots[data_index] = [ 'norm', pivot_col, value_col ];

  // get the filtered data
  var data = table_filtered_data[data_index];

  if (tdata) {
    data = tdata;
  }

  // initialize the pivot hash
  var pivot_hash = new Array();

  // hide all columns between the pivot column and the data column
  for (i=(parseInt(pivot_col,10)+1); i<parseInt(value_col,10); i++) {
    table_visible_columns[data_index][i] = 0;
    document.getElementById(id + '_col_' + (i+1)).style.display = 'none';
  }

  // do the pivoting
  var new_data = new Array();
  for (i=0; i<data.length; i++) {
    var stripped_cell = data[i][pivot_col].replace(HTML_REPLACE, '');
    if (pivot_hash[stripped_cell] != null) {
      new_data[pivot_hash[stripped_cell]][value_col] = new String(parseFloat(new_data[pivot_hash[stripped_cell]][value_col]) + parseFloat(data[i][value_col]));
    } else {
      pivot_hash[stripped_cell] = new_data.length;
      new_data[new_data.length] = data[i];
    }
  }

  // set the data to the pivot data
  table_filtered_data[data_index] = new_data;
  newnumrows = new_data.length;
  document.getElementById('table_rows_' + id).value = newnumrows;

  if (! tdata) {
    // render the table
    table_first(id);
  }
}

function pivot_plus (id, p_cols, v_cols, c_types, tdata, catsymbol, noempty) {
  if (catsymbol == null) {
    catsymbol = ', ';
  }

  // get the table data index
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  // remember this pivot
  table_current_pivots[data_index] = [ 'plus', p_cols, v_cols, c_types ];

  // get the filtered data
  var data = marray_clone(table_filtered_data[data_index]);

  if (tdata) {
    data = tdata;
  }

  // initialize value cols and col types
  var pivot_cols = p_cols.split("|");
  var value_cols = v_cols.split("|");
  var col_types = c_types.split("|");
  var col_hash_count = new Array();
  for (i=0; i<col_types.length; i++) {
    col_hash_count[i] = new Array();
  }

  // initialize the pivot hash
  var pivot_hash = new Array();

  // hide all columns between the pivot column and the data column
  for (i=(parseInt(pivot_cols[pivot_cols.length-1],10)+1); i<parseInt(value_cols[0],10); i++) {
    table_visible_columns[data_index][i] = 0;
    document.getElementById(id + '_col_' + (i+1)).style.display = 'none';
  }

  // do the pivoting
  var new_data = new Array();
  for (i=0; i<data.length; i++) {
    var joined = new Array();
    for (j=0; j<pivot_cols.length; j++) {
      joined[joined.length] = data[i][pivot_cols[j]].replace(HTML_REPLACE, '');
    }
    var stripped_cell = joined.join("||");
    if (pivot_hash[stripped_cell] != null) {
      for (h=0; h<value_cols.length; h++) {
	if (col_types && col_types[h]) { 
	  if (col_types[h]=='avg') {
	    new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String((((parseFloat(new_data[pivot_hash[stripped_cell]][value_cols[h]]) * col_hash_count[stripped_cell][h]) + parseFloat(data[i][value_cols[h]])) / (col_hash_count[stripped_cell][h] + 1)).toFixed(2));
	    col_hash_count[stripped_cell][h]++;
	  } else if (col_types[h]=='min') {
	    if (parseFloat(data[i][value_cols[h]]) < parseFloat(new_data[pivot_hash[stripped_cell]][value_cols[h]])) {
	      new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String(parseFloat(data[i][value_cols[h]]).toExponential());
	    }
	  } else if (col_types[h]=='max') {
	    if (parseFloat(data[i][value_cols[h]]) > parseFloat(new_data[pivot_hash[stripped_cell]][value_cols[h]])) {
	      new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String(parseFloat(data[i][value_cols[h]]).toExponential());
	    }
	  } else if (col_types[h]=='cat') {
	    new_data[pivot_hash[stripped_cell]][value_cols[h]] = new_data[pivot_hash[stripped_cell]][value_cols[h]] + data[i][value_cols[h]];
	  } else if (col_types[h]=='hash') {
	    new_data[pivot_hash[stripped_cell]][value_cols[h]] = new_data[pivot_hash[stripped_cell]][value_cols[h]] +catsymbol+ data[i][value_cols[h]];
	  } else if (col_types[h]=='num') {
	    new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String(parseInt(new_data[pivot_hash[stripped_cell]][value_cols[h]],10) + 1);
	  } else {
	    new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String(parseFloat(new_data[pivot_hash[stripped_cell]][value_cols[h]]) + parseFloat(data[i][value_cols[h]]));
	  }
	} else {
	  new_data[pivot_hash[stripped_cell]][value_cols[h]] = new String(parseFloat(new_data[pivot_hash[stripped_cell]][value_cols[h]]) + parseFloat(data[i][value_cols[h]]));
	}
      }
    } else {
      if (data[i][pivot_cols[0]] != ' ') {
	pivot_hash[stripped_cell] = new_data.length;
      }
      new_data[new_data.length] = data[i];
      for (h=0; h<value_cols.length; h++) {
	if (col_types && col_types[h] && col_types[h]=='num') {
	  new_data[new_data.length-1][value_cols[h]] = '1';
	}
      }
      if (col_types) {
	col_hash_count[stripped_cell] = new Array();
	for (h=0; h<value_cols.length; h++) {
	  col_hash_count[stripped_cell][h] = 1;
	}
      }
    }
  }

  var has_hash = -1;
  for (i=0; i<col_types.length; i++) {
    if (col_types[i] == 'hash') {
      has_hash = i;
    }
  }
  if (has_hash > -1) {
    for (i=0; i<new_data.length; i++) {
      for (h=0; h<value_cols.length; h++) {
	if (col_types && col_types[h] && col_types[h]=='hash') {
	  var dh = new Array();
	  var dn = new Array();
	  var da = new_data[i][value_cols[h]].split(catsymbol);
	  for (k=0;k<da.length;k++) {
	    dh[da[k]] = 1;
	  }
	  for (k in dh) {
	    dn[dn.length] = k;
	  }
	  new_data[i][value_cols[h]] = dn.join(catsymbol);
	}
      }
    }
    for (i=0; i<new_data.length; i++) {
      for (h=0; h<value_cols.length; h++) {
	if (col_types && col_types[h] && col_types[h]=='num_hash') {
	  new_data[i][value_cols[h]] = new_data[i][value_cols[has_hash]].split(catsymbol).length;
	}
      }
    }
  }
  
  // set the data to the pivot data
  table_filtered_data[data_index] = new_data;
  newnumrows = new_data.length;
  document.getElementById('table_rows_' + id).value = newnumrows;

  if (! tdata) {
    // render the table
    reload_table(id);
  }
}

function clear_pivot (id, pivot_cols, value_col) {
  // get the table data index
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  var pcs = pivot_cols.split("||");
  var pivot_col = pcs[pcs.length - 1];

  // show all columns between the pivot column and the data column
  for (i=(parseInt(pivot_col,10)+1); i<parseInt(value_col,10); i++) {
    table_visible_columns[data_index][i] = 1;
    document.getElementById(id + '_col_' + (i+1)).style.display = '';
  }

  table_current_pivots[data_index] = null;

  table_filtered_data[data_index] = marray_clone(table_data[data_index]);

  reload_table(id);
}

function marray_clone(marray) {
  var cp = new Array();
  for (i=0;i<marray.length;i++) {
    cp[cp.length] = marray[i].slice(0);
  }
  
  return cp;
}
