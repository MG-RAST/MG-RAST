var data_finder_data = new Array(); // id -> tag -> array of values
var data_finder_filtered_data = new Array();
var data_finder_search_data = new Array();
var data_finder_tags = new Array(); // tag -> value -> array of ids
var data_finder_tag_order = new Array();
var data_finder_tag_expansion = new Array();
var curr_tag = new Array();
var data_finder_target_function;

function initialize_data_finder () {
  var dstring = document.getElementById('data_finder_data').value;
  var ids = dstring.split('##');
  for (var i in ids) {
    var tags = ids[i].split(';;');
    var id = tags.shift();
    data_finder_data[id] = new Array();
    for (var h in tags) {
      var tag_vals = tags[h].split('||');
      var tag = tag_vals.shift();
      for (var j in tag_vals) {
	var x = tag_vals[j];
	if (x == "") {
	  x = 'not specified';
	}
	if (data_finder_data[id][tag]) {
	  data_finder_data[id][tag][data_finder_data[id][tag].length] = x;
	} else {
	  data_finder_data[id][tag] = [ x ];
	}
      }
    }
  }

  data_finder_tag_order = document.getElementById('data_finder_tag_order').value.split("||");
  data_finder_tag_expansion = document.getElementById('data_finder_tag_expansion').value.split("||");
  data_finder_filtered_data = data_finder_data;
  data_finder_derive_tags(data_finder_filtered_data);
  data_finder_draw();
  data_finder_target_function = document.getElementById('data_finder_target_function').value;
  if (data_finder_target_function) {
    eval(data_finder_target_function)();
  }
}

function data_finder_derive_tags (d) {
  data_finder_tags = [];
  for (var id in d) {
    for (var tag in d[id]) {
      for (var value in d[id][tag]) {
	if (! data_finder_tags[tag]) {
	  data_finder_tags[tag] = new Array();
	}
	if (! data_finder_tags[tag][d[id][tag][value]]) {
	  data_finder_tags[tag][d[id][tag][value]] = new Array();
	}
	data_finder_tags[tag][d[id][tag][value]][data_finder_tags[tag][d[id][tag][value]].length] = id;
      }
    }
  }
}

function df_sort (a, b) {
  if (curr_tag[a].length==curr_tag[b].length) return 0;
  if (curr_tag[a].length<curr_tag[b].length) return 1;
  return -1;
}

function data_finder_search (e) {
   if (e.keyCode == 13) {
     // do the search
     var searchtext = document.getElementById('data_finder_search').value.toLowerCase();
     searchtext = searchtext.replace(/^\s+|\s+$/g, '');
     if (searchtext.length) {
       var found_something = 0;
       var new_filtered_data = new Array();
       for (var id in data_finder_filtered_data) {
	 for (var tag in data_finder_filtered_data[id]) {
	   for (var i=0; i<data_finder_filtered_data[id][tag].length; i++) {
	     if (data_finder_filtered_data[id][tag][i].toLowerCase().indexOf(searchtext) > -1) {
	       found_something = 1;
	       if (! new_filtered_data[id]) {
		 new_filtered_data[id] = new Array();
	       }
	       if (! new_filtered_data[id][tag]) {
		 new_filtered_data[id][tag] = new Array();
	       }
	       new_filtered_data[id][tag][new_filtered_data[id][tag].length] = data_finder_filtered_data[id][tag][i];
	     }
	   }
	 }
       }
       if (! found_something) {
	 alert('no results found');
       }
       data_finder_search_data = new_filtered_data;
       data_finder_derive_tags(data_finder_search_data);
       data_finder_expand_all();
     }
     return false;
   } else {
     return true;
   }
}

function data_finder_collapse_all () {
  for (var i=0; i<data_finder_tag_expansion.length; i++) {
    var h = 0;
    for (var j in data_finder_tags[data_finder_tag_order[i]]) {
      h++;
    }
    if (h > 1) {
      data_finder_tag_expansion[i] = 0;
    } else {
      data_finder_tag_expansion[i] = 1;
    }
  }
  data_finder_draw();
}

function data_finder_expand_all () {
  for (var i=0; i<data_finder_tag_expansion.length; i++) {
    data_finder_tag_expansion[i] = 1;
  }
  data_finder_draw();
}

function data_finder_draw () {
  var target = document.getElementById('data_finder_main');
  target.innerHTML = "";
  var max_elements = document.getElementById('data_finder_max_elements').value;
  for (var i=0; i<data_finder_tag_order.length; i++) {
    var tag = data_finder_tag_order[i];
    var coll = "collapse_tag(this, \""+tag+"\");'>-";
    var curr_elements = 1;
    var remaining_elements = 0;
    var tag_html_hidden = "";
    var values_sorted = [];
    for (var value in data_finder_tags[tag]) {
      values_sorted[values_sorted.length] = value;
    }
    curr_tag = data_finder_tags[tag];
    values_sorted.sort(df_sort);
    var coll2 = "";
    if (data_finder_tag_expansion[i] == 0) {
      coll = "expand_tag(this, \""+tag+"\");'>"+values_sorted.length;
      coll2 = " style='display: none;'";
    }
    var tag_space = document.createElement('div');
    tag_space.className = 'data_finder_tag_space';
    var tag_html = "<div class='datafinder_tag_title'>"+tag+"<a id='data_finder_tag_a_"+tag+"' style='float: right; font-size: 10px;' onclick='data_finder_"+coll+"</a></div><div class='data_finder_values_space'"+coll2+">";
    for (var h=0; h<values_sorted.length; h++) {
      var value = values_sorted[h];
      if (curr_elements > max_elements) {
	remaining_elements++;
	tag_html_hidden += "<div class='data_finder_value_div'><a onclick='data_finder_filter(\""+tag+"\", \""+value+"\");'>"+value+"</a> ("+String(data_finder_tags[tag][value].length)+")</div>";
      } else {
	tag_html += "<div class='data_finder_value_div'><a onclick='data_finder_filter(\""+tag+"\", \""+value+"\");'>"+value+"</a> ("+String(data_finder_tags[tag][value].length)+")</div>";
      }
      if (max_elements) {
	curr_elements++;
      }
    }
    if (remaining_elements) {
      tag_html += "<div class='data_finder_value_div' id='data_finder_hidden_vals_more_" + tag + "'>[ + ] <a onclick='document.getElementById(\"data_finder_hidden_vals_" + tag + "\").style.display=\"\";document.getElementById(\"data_finder_hidden_vals_less_" + tag + "\").style.display=\"\";document.getElementById(\"data_finder_hidden_vals_more_" + tag + "\").style.display=\"none\";'>view all</a> ("+String(remaining_elements)+" more)</div>";
      tag_html += "<span id='data_finder_hidden_vals_" + tag + "' style='display: none;'>" + tag_html_hidden + "</span>";
      tag_html += "<div class='data_finder_value_div' id='data_finder_hidden_vals_less_" + tag + "' style='display: none;'>[ - ] <a onclick='document.getElementById(\"data_finder_hidden_vals_" + tag + "\").style.display=\"none\";document.getElementById(\"data_finder_hidden_vals_more_" + tag + "\").style.display=\"\";document.getElementById(\"data_finder_hidden_vals_less_" + tag + "\").style.display=\"none\";'>view less</a></div>";
    }
    tag_html += "</div>";
    tag_space.innerHTML = tag_html;
    target.appendChild(tag_space);
  }
  if (data_finder_target_function) {
    eval(data_finder_target_function)();
  }
}

function data_finder_collapse_tag (tag, tagname) {
  for (var i=0; i<data_finder_tag_order.length; i++) {
    if (data_finder_tag_order[i] == tagname) {
      data_finder_tag_expansion[i] = 0;
      break;
    }
  }
  tag.parentNode.nextSibling.style.display = 'none';
  var tagnums = 0;
  for (var i in data_finder_tags[tagname]) {
    tagnums++;
  }
  tag.innerHTML = tagnums;
  tag.setAttribute('onclick', "data_finder_expand_tag(this, '"+tagname+"');");
}

function data_finder_expand_tag (tag, tagname) {
  for (var i=0; i<data_finder_tag_order.length; i++) {
    if (data_finder_tag_order[i] == tagname) {
      data_finder_tag_expansion[i] = 1;
      break;
    }
  }
  tag.parentNode.nextSibling.style.display = '';
  tag.innerHTML = "-";
  tag.setAttribute('onclick', "data_finder_collapse_tag(this, '"+tagname+"');");}

function data_finder_filter (tag, value) {
  var crumbs = document.getElementById('data_finder_breadcrumbs').innerHTML;
  crumbs = crumbs.substr(3);
  crumbs = crumbs.split(" » ");
  var filtered = 0;
  for (var i=0; i<crumbs.length; i++) {
    crumbs[i] = crumbs[i].split(": ");
    if (crumbs[i][0] == tag) {
      filtered = 1;
    }
  }
  if (! filtered) {
    var ids = data_finder_tags[tag][value];
    var new_filtered_data = new Array();
    for (var h in ids) {
      for (var id in data_finder_filtered_data) {
	if (id == ids[h]) {
	  new_filtered_data[id] = data_finder_filtered_data[id];
	  break;
	}
      }
    }
    document.getElementById('data_finder_breadcrumbs').innerHTML += " &raquo; " + tag + ": " + value;
    data_finder_filtered_data = new_filtered_data;
    data_finder_derive_tags(data_finder_filtered_data);
    data_finder_collapse_all();
  }
}

function data_finder_trail () {
  var crumbs = document.getElementById('data_finder_breadcrumbs').innerHTML;
  crumbs = crumbs.substr(3);
  crumbs = crumbs.split(" » ");
  for (var i=0; i<crumbs.length; i++) {
    crumbs[i] = crumbs[i].split(": ");
  }

  return crumbs;
}

function data_finder_follow_trail (trail) {
  var new_filtered_hash = new Array();
  var new_filtered_data = new Array();

  for (i=0; i<trail.length; i++) {
    if (data_finder_tags[trail[i][0]][trail[i][1]] != null) {
      for (h=0; h<data_finder_tags[trail[i][0]][trail[i][1]].length; h++) {
	new_filtered_hash[data_finder_tags[trail[i][0]][trail[i][1]][h]] = 1;
      }
    }
  }

  for (var i in new_filtered_hash) {
    new_filtered_data[new_filtered_data.length] = i;
  }

  return new_filtered_data;
}

function data_finder_reset_filter (initial) {
  document.getElementById('data_finder_breadcrumbs').innerHTML = "";
  data_finder_filtered_data = data_finder_data;
  data_finder_derive_tags(data_finder_filtered_data);
  data_finder_collapse_all();

  if (initial != null) {
    var ilist = initial.split("|");
    var trail = [];
    for (i=0; i< ilist.length; i+=2) {
      var tag = ilist[i];
      var value = ilist[i+1];
      data_finder_filter(tag, value);
    }
  } 
}
