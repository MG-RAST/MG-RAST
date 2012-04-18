// store values in memory
var options = new Array();
var filtered_attribute_options = new Array();
var filtered_options = new Array();
var has_attributes = new Array();
var attribute_names = new Array();
var attribute_types = new Array();
var visible = new Array();
var click = new Array();
var skip_keyup = new Array();

var default_text = new Array();

var DROPDOWN = 0;
var SORT_ATTRIBUTE;

// this is called when the filter select is loaded for the first time
function initialize_filter_select (id) {
  // parse labels and values
  var labels_element = document.getElementById("filter_select_labels_" + id);
  var labels_string = labels_element.value;
  labels_element.parentNode.removeChild(labels_element);

  var values_element = document.getElementById("filter_select_values_" + id);
  var values_string = values_element.value;
  values_element.parentNode.removeChild(values_element);

  labels_string = labels_string.replace(/#/g, "'");
  values_string = values_string.replace(/#/g, "'");

  var labels_array = labels_string.split(/~/);
  var values_array = values_string.split(/~/);

  // check if there are attributes
  var attribute_names_element = document.getElementById("filter_select_attribute_names_" + id);
  var attribute_types_element = document.getElementById("filter_select_attribute_types_" + id);
  var attribute_values_element = document.getElementById("filter_select_attribute_values_" + id);

  // get initial text
  default_text[id] = document.getElementById('filter_initial_text_'+id).value;

  // get dropdown value
  if (document.getElementById('filter_select_dropdown_'+id)) {
    DROPDOWN = 1;
	visible[id] = 0;
	document.getElementById("filter_select_textbox_" + id).onclick = function() {
	  empty_select(id);
	  show_filter_select(id);
	}
  } else {
  	document.getElementById("filter_select_textbox_" + id).onclick = function() {
	  empty_select(id);
	}
  }
  
  var attribute_values = null;
  if (attribute_names_element) {
    attribute_names[id] = attribute_names_element.value.split(/~/);
    attribute_names_element.parentNode.removeChild(attribute_names_element);
    attribute_types[id] = attribute_types_element.value.split(/~/);
    attribute_types_element.parentNode.removeChild(attribute_types_element);

    attribute_values = new Array();
    var attribute_values_temp = attribute_values_element.value.split(/\|/);
    for (var i=0; i<attribute_names[id].length; i++) {
      attribute_values[i] = attribute_values_temp[i].split(/~/);
    }
    attribute_values_element.parentNode.removeChild(attribute_values_element);

    has_attributes[id] = 1;
  } else {
    has_attributes[id] = 0;
  }

  var default_val = document.getElementById("filter_select_default_" + id).value;
  var select = document.getElementById("filter_select_" + id);

  var option_array = new Array();
  for (var i=0; i<labels_array.length; i++) {
    var option_attribute_values = null;
    if (has_attributes[id] == 1) {
      option_attribute_values = new Array();
      for (var j=0; j<attribute_values.length; j++) {
        option_attribute_values[j] = attribute_values[j][i];
      }
    }

    var option = new FilterOption(labels_array[i], values_array[i], option_attribute_values, id);
    option_array.push(option);
  }

  options[id] = option_array;
  filtered_options[id] = options[id].slice(0);

  if (has_attributes[id] == 1) {
    // do the initial filtering
    filtered_attribute_options[id] = new Array();
    perform_attribute_filter(id);
	if (DROPDOWN) {
      hide_filter_select(id);
    }
  } else {
    // do the initial filling
    select.options.length = 0;
    for (var i=0; i<filtered_options[id].length; i++) {
      var option = filtered_options[id][i];
      select.options[i] = option.optionElement;
      if (default_val == option.value) {
        select.options[i].selected = true;
        document.getElementById("filter_select_textbox_" + id).value = option.label;
      }
    }
    if (default_val == '') {
      select.selectedIndex = 0;
    }
  }
}

function textbox_key_down (e, id) {
  if (e) {
    var select = document.getElementById("filter_select_" + id);
    if (e.keyCode == 38) { // up arrow
	  var index = select.selectedIndex;
	  if (index > 0) {
	    select.selectedIndex = --index;
		update_select_text(id);
		if (DROPDOWN) {
          show_filter_select(id);
        }
	  }
	skip_keyup[id] = 1;
	  return;
	} else if (e.keyCode == 40) { // down arrow
	  var index = select.selectedIndex;
	  if (index < select.options.length - 1) {
	    select.selectedIndex = ++index;
		update_select_text(id);
		if (DROPDOWN) {
          show_filter_select(id);
        }
	  }
	skip_keyup[id] = 1;
	  return;
	} else if (e.keyCode == 13) { // enter
	  if (DROPDOWN) {
	    hide_filter_select(id);
	  }
	  return;
	}
  }
}

function textbox_key_up (e, id) {
  if (skip_keyup[id] == 1) {
    skip_keyup[id] = 0;
    return;
  }

  // check if backspace was pressed, if so use previous filter
  var use_filter = filtered_options[id];
  if (e) {
    var select = document.getElementById("filter_select_" + id);
    if (e.keyCode == 8) { // backspace
      if (has_attributes[id]) {
        use_filter = filtered_attribute_options[id];
      } else {
        use_filter = options[id];
      }
    }
  }

  update_select (id, use_filter);
}

function update_select (id, filter) {
  var text = document.getElementById("filter_select_textbox_" + id).value;

  // check if we actually have text
  if (text) {
    if (text == default_text[id]) {
      text = '';
    }
  }

  var select = document.getElementById("filter_select_" + id);
  select.options.length = 0;

  // escape the text
  var escaped_text = reg_escape(text);
  var escaped = escaped_text.split(" ");
  var regs = new Array();
  for (var i=0; i<escaped.length; i++) {
    regs.push(new RegExp(escaped[i], "i"));
  }

  // iterate through the items to find out which match the filter
  var ind = 0;
  for (var i=0; i<filter.length; i++) {
    var option = filter[i];
    var match = 1;
    for (var j=0; j<regs.length; j++) {
      if (!option.label.match(regs[j])) {
        match = 0;
      }
    }
    if (match) {
      select.options[ind] = option.optionElement;
      filtered_options[id][ind] = option;
      ind++;
    }
  }
  filtered_options[id].length = ind;

  // select first item
  select.selectedIndex = 0;
}

// this is called the first time someone clicks into the filter box
function empty_select (id) {
  var textbox = document.getElementById("filter_select_textbox_" + id);
  if (textbox.value == default_text[id]) {
    textbox.value = '';
  }
}

// when someone selects from the select box, update the text in the filter box
function update_select_text (id) {
  var textbox = document.getElementById("filter_select_textbox_" + id);
  var select = document.getElementById("filter_select_" + id);
  textbox.value = select.options[select.selectedIndex].text;
}

// this is called when an attribute filter checkbox is changed
function perform_attribute_filter (id) {

  if (DROPDOWN) {
    show_filter_select(id);
  }
  filtered_attribute_options[id].length = 0;

  // new array for determining whether to include the option or not
  var included_options = new Array();

  for (var j=0; j<attribute_names[id].length; j++) {
    included_options[j] = new Array();

    var attribute = attribute_names[id][j];
    if (attribute_types[id][j] != 'filter') {
      continue;
    }

    // get the attribute values for this attribute
    var allowed = new Array();
    var possible = document.getElementsByName("filter_select_" + id + "_" + attribute);
    for (i=0;i<possible.length;i++) {
      if (possible[i].checked) {
        allowed.push(possible[i].value);
      }
    }

    // iterate through the items to find out which match the filter
    for (var i=0; i<options[id].length; i++) {
      var option = options[id][i];
      for (var h=0; h<allowed.length; h++) {
        if (option.attributes[j] == allowed[h]) {
          included_options[j][i] = 1;
          break;
        }
      }
    }
  }

  for (var i=0; i<options[id].length; i++) {
    for (var j=0; j<attribute_names[id].length; j++) {
      if (attribute_types[id][j] != 'filter') {
        continue;
      }
      var add = 1;
      if (included_options[j][i] != 1) {
        add = 0;
        break;
      }
    }
    if (add == 1) {
      filtered_attribute_options[id].push(options[id][i]);
    }
  }

  update_select(id, filtered_attribute_options[id]);
}

// this is called when an attribute sort radio is changed
function perform_attribute_sort (attribute, id) {

  // default to alphabetical sort
  var sortfn = sort_alphabetical;

  // treat 'alphabetical' attribute special
  if (attribute == 'alphabetical') {
    sortfn = sort_labels;
  } else {
    // check what kind of data we have
    var example;
    for (var i=0; i<attribute_names[id].length; i++) {
      if (attribute == attribute_names[id][i]) {
        SORT_ATTRIBUTE = i;
        example = options[id][0].attributes[i];
        break;
      }
    }
    if (example.match(/^\d+\.\d+$/)) {
      sortfn = sort_genome_id;
    }
  }

  filtered_options[id].sort(sortfn);

  // get the select box and delete all items
  var select = document.getElementById("filter_select_" + id);
  select.options.length = 0;

  // recreate the select options in the new sort
  for (i=0; i<filtered_options[id].length; i++) {
    select.options[i] = filtered_options[id][i].optionElement;
  }

  // reset the text
  document.getElementById("filter_select_textbox_" + id).value = default_text[id];

  // select first item
  select.selectedIndex = 0;
}

function sort_labels (a, b) {
  var aa = a.label.toLowerCase();
  var bb = b.label.toLowerCase();
  if (aa==bb) return 0;
  if (aa<bb) return -1;
  return 1;
}

function sort_alphabetical (a, b) {
  var aa = a.attributes[SORT_ATTRIBUTE].toLowerCase();
  var bb = b.attributes[SORT_ATTRIBUTE].toLowerCase();
  if (aa==bb) return 0;
  if (aa<bb) return -1;
  return 1;
}

function sort_genome_id (a, b) {
  var re = /(\d+)\.(\d+)/;
  var ma = re.exec(a.attributes[SORT_ATTRIBUTE]);
  var mb = re.exec(b.attributes[SORT_ATTRIBUTE]);
  var a1 = parseInt(ma[1]);
  var b1 = parseInt(mb[1]);
  if (a1<b1) return -1;
  if (b1<a1) return 1;
  if (a1==b1) {
    var a2 = parseInt(ma[2]);
    var b2 = parseInt(mb[2]);
    if (a2<b2) return -1;
    if (b2<a2) return 1;
    if (a2==b2) return 0;
  }
}

// escape text to not mess up a regexp
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

function hide_filter_select(id) {
  if (visible[id] == 1) {
    document.getElementById('filter_select_'+id+'_div').style.display = 'none';
    visible[id] = 0;
	document.removeEventListener('click', click[id], false);
  }
}

function show_filter_select(id) {
  if (visible[id] == 0) {
    var div = document.getElementById('filter_select_' + id + '_div');
    div.style.display = '';
	
	visible[id] = 1;
	click[id] = function (e) {
          // call div_clicker, which checks to see if we clicked somewhere within the div
          if (div_clicker(e, id)) {
	    hide_filter_select(id);
            // reset the text
            document.getElementById("filter_select_textbox_" + id).value = default_text[id];
            var use_filter;
            if (has_attributes[id]) {
              use_filter = filtered_attribute_options[id];
            } else {
              use_filter = options[id];
            }
            update_select (id, use_filter);
	}
    }
	
	document.addEventListener('click', click[id], false);
  }
}

// return 1 if we should hide, 0 otherwise
function div_clicker(e, id) {
  // cancel the event, we only need to check once
  e.stopPropagation();

  var hide = 1;
  var element = e.target;

  // first check if it is textbox, then don't hide
  if (element.id == 'filter_select_textbox_'+id) {
    hide = 0;
  } else {
    // otherwise try to find out if we are inside the div
    while (element.tagName != "BODY") {
      if (element.id == 'filter_select_'+id+'_div') {
        hide = 0;
	    break;
      } else {
        element = element.parentNode;
      }
    }
  }
  return hide;
}

/*
Class to represent one select option and all it's data.

label - string
value - string
attributes - array of strings
*/
function FilterOption(label, value, attributes, id) {
  this.label = label;
  this.value = value;
  this.attributes = attributes;

  this.optionElement = new Option(label, value);
  if (DROPDOWN) {
    this.optionElement.onclick = function () {
	  update_select_text(id);
	  hide_filter_select(id);
	}
  }
}
