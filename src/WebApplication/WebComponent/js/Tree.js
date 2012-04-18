var tree_selecteds = new Array();

function expand (id, node) {
  var image = document.getElementById('tree_img_'+id+'_'+node);
  var div = document.getElementById('tree_div_'+id+'_'+node);
  var span = document.getElementById('tree_node_'+id+'_'+node);
  var mode;
  if (div.style.display == 'block') {
    div.style.display = 'none';
    mode = 'plus.gif';
  } else {
    div.style.display = 'block';
    mode = 'minus.gif';
  }
  if (image.localName != "span") {
    // change the image without changing the image directory!
    var currentSrc = image.src;
    var slashLoc = currentSrc.lastIndexOf('/');
    image.src = currentSrc.substr(0, slashLoc + 1) + mode;
  }
}

function tree_node_select (id, node) {
  if (! tree_selecteds[id]) {
    tree_selecteds[id] = new Array();
  }
  var span = document.getElementById('tree_span_'+id+'_'+node);
  var val = span.firstChild.value;
  var multiple = document.getElementById('tree_select_multiple_' + id).value;
  var container = document.getElementById('tree_selected_' + id);
  var current = container.childNodes;
  if (multiple == 1) {
    var previously_selected = 0;
    for (i=0;i<tree_selecteds[id].length;i++) {
      if (tree_selecteds[id][i] == node) {
	document.getElementById('tree_span_'+id+'_'+node).style.color = '#000000';
	container.removeChild(current[i]);
	tree_selecteds[id].splice(i,1);
	previously_selected = 1;
	break;
      }
    }
    if (! previously_selected) {
      tree_selecteds[id][tree_selecteds[id].length] = node;
      span.style.color = '#0000ff';
      var selected = document.createElement('input');
      selected.setAttribute("type", "hidden");
      selected.setAttribute("value", val);
      selected.setAttribute("name", document.getElementById('tree_name_'+id).value);
      container.appendChild(selected);
    }
  } else {
    if ( typeof(tree_selecteds[id][0]) != 'undefined' ) {
      document.getElementById('tree_span_'+id+'_'+tree_selecteds[id][0]).style.color = '#000000';
      if (container.childNodes.length) {
	container.removeChild(container.firstChild);
      }
    }
    span.style.color = '#0000ff';
    var selected = document.createElement('input');
    selected.setAttribute("type", "hidden");
    selected.setAttribute("value", val);
    selected.setAttribute("name", document.getElementById('tree_name_'+id).value);
    selected.setAttribute("id", id + document.getElementById('tree_name_'+id).value);
    container.appendChild(selected);
    tree_selecteds[id][0] = node;
  }
}
