var current_hover = '';
var redundancies = new Array();

function hover(event, obj_id, hover_id) {
  if (hover_id == undefined) {
    hover_id=0;
  }

  var is_menu = false;
  if (document.getElementById('menu_titles_'+ hover_id + '_' + obj_id)) {
    if ((document.getElementById('tooltip_' + hover_id + '_' + obj_id) && event.type == 'click') || (! document.getElementById('tooltip_' + hover_id + '_' + obj_id))) {
      is_menu = true;
    }
  }

  if (! is_menu ) {
    if (! redundancies[hover_id] || ! redundancies[hover_id][obj_id]) {
      var redundancies_string = document.getElementById('hover_redundancies_'+hover_id).value;
      var hover_ids = redundancies_string.split(/~#/);
      redundancies[hover_id] = new Array();
      for (i=0;i<hover_ids.length;i++) {
	var content_ids = hover_ids[i].split(/~@/);
	for (h=0;h<content_ids.length;h++) {
	  redundancies[hover_id][content_ids[h]] = content_ids[0];
	}
      }
    }
    if (redundancies[hover_id][obj_id]) {
      obj_id = redundancies[hover_id][obj_id];
    }
  }

  obj_id = hover_id + '_' + obj_id;
  if (!obj_id) event = window.event;

  // determine position of object
  var curleft = 0;
  var curtop = 0;
  if (!event) event = window.event;
  if (event.pageX || event.pageY) {
    curleft = event.pageX;
    curtop = event.pageY;
  }
  else if (event.clientX || event.clientY) {
    curleft = event.clientX + document.body.scrollLeft
      + document.documentElement.scrollLeft;
    curtop = event.clientY + document.body.scrollTop
      + document.documentElement.scrollTop;
  }
  curleft += 9;
  curtop += 11;
  
  if (is_menu && event.type != 'mouseover') {
      var titles = document.getElementById('menu_titles_'+obj_id).innerHTML.split(/~#/);
      var links = document.getElementById('menu_links_'+obj_id).innerHTML.split(/~#/);

      // create the element
      if (! document.getElementById(obj_id + '_hm')) {
	var item_table = document.createElement("table");
	item_table.className = "hm_table";
	for (i=0;i<titles.length;i++) {
	  var row = document.createElement("tr");
	  var cell = document.createElement("td");
	  cell.className = "hm_td";
	  var srcID = obj_id + '_source';
	  if (event.target) targ = event.target;
	  else if (event.srcElement) targ = event.srcElement;
	  if (targ.nodeType == 3) // defeat Safari bug
	    targ = targ.parentNode;
	  if (targ.id!=undefined) {
	    srcID = targ.id;
	  }
	  cell.name = srcID;
	  cell.innerHTML = titles[i];
	  cell.id = obj_id + '_hm_td_' + i;
	  if (links[i]) {
	    cell.onclick = function (e) {
	      if (!e) e = window.event;
	      if (e.target) targ = e.target;
	      else if (e.srcElement) targ = e.srcElement;
	      if (targ.nodeType == 3) // defeat Safari bug
		targ = targ.parentNode;
	    
	      var re = /(\w+)_hm_td_(\d+)/;
	      var m = re.exec(targ.id);
	      var links = document.getElementById('menu_links_'+m[1]).innerHTML.split(/~#/);
	      location = links[m[2]];
	      document.body.removeChild(item_table);
	    };
	  }
	  row.appendChild(cell);
	  item_table.appendChild(row);
	}
      
	item_table.id = obj_id + '_hm';
	item_table.style.position = "absolute";
	item_table.style.top = curtop + "px";
	item_table.style.left = curleft + "px";
	var table_width = 150;
	if (document.getElementById('menu_width_'+obj_id)) {
	  table_width = document.getElementById('menu_width_'+obj_id).value;
	}
	item_table.style.width = table_width + "px";
	document.body.appendChild(item_table);
	// check if we stay inside the window
	if ((curtop + item_table.clientHeight + 18 - window.scrollY) > window.innerHeight) {
	  item_table.style.top = window.innerHeight - item_table.clientHeight - 18 + window.scrollY;
	}
	if ((curleft + item_table.clientWidth + 15 - window.scrollX) > window.innerWidth) {
	  item_table.style.left = window.innerWidth - item_table.clientWidth - 15 + window.scrollX;
	}
	var timeout = 8000;
	if (document.getElementById('menu_timeout_'+obj_id)) {
	  timeout = document.getElementById('menu_timeout_'+obj_id).value;
	}
	setTimeout("killTip('"+obj_id+"_hm')", timeout);
      }
  }
  else {
    // create the element
    if (! document.getElementById(obj_id + '_ht') && document.getElementById('tooltip_'+obj_id)) {
      // kill the previous hover if it still exists
      var old = document.getElementById(current_hover);
      if (old) {
	document.body.removeChild(old);
      }
      // create the new
      var ht = document.createElement("div");
      ht.innerHTML = document.getElementById('tooltip_'+obj_id).innerHTML;
      ht.id = obj_id + '_ht';
      current_hover = ht.id;
      ht.className = "ht_div";
      ht.style.position = "absolute";
      var targ = event.target;
      if (! targ) {
	targ = event.srcElement;
      }
      if (targ.nodeType == 3) {
	targ = targ.parentNode;
      }
      targ.onmouseout = function (event) {
	if (!event) event = window.event;
	if(document.getElementById(obj_id+'_ht')) {
	  killTip(obj_id+'_ht');
          var targ = event.target;
	  if (! targ) {
	    targ = event.srcElement;
	  }
	  if (targ.nodeType == 3) {
	    targ = targ.parentNode;
	  }
	  targ.onmouseout = null;
	  targ.onmousemove = null;
	}
      }
      targ.onmousemove = function (event) {
	if (!event) event = window.event;
	var ht = document.getElementById(obj_id+'_ht');
	if(ht) {
	  
	  // determine position of object
	  var curleft = 0;
	  var curtop = 0;
	  if (!event) event = window.event;
	  if (event.pageX || event.pageY) {
	    curleft = event.pageX;
	    curtop = event.pageY;
	  }
	  else if (event.clientX || event.clientY) 	{
	    curleft = event.clientX + document.body.scrollLeft
	      + document.documentElement.scrollLeft;
	    curtop = event.clientY + document.body.scrollTop
	      + document.documentElement.scrollTop;
	  }
	  curleft += 9;
	  curtop += 11;
	  
	  // check if we stay inside the window
	  if ((curtop + ht.clientHeight + 18 - window.scrollY) > window.innerHeight) {
	    curtop = window.innerHeight - ht.clientHeight - 18 + window.scrollY;
	  }
	  if ((curleft + ht.clientWidth + 15 - window.scrollX) > window.innerWidth) {
	    curleft = curleft - ht.clientWidth - 15 + window.scrollX;
	  }
	  ht.style.top = curtop + "px";
	  ht.style.left = curleft + "px";
	}
      }
      var table_width = 'auto';
      if (document.getElementById('tooltip_width_'+obj_id)) {
	table_width = document.getElementById('tooltip_width_'+obj_id).value + 'px';
      }
      ht.style.width = table_width;
      ht.style.top = curtop + "px";
      ht.style.left = curleft + "px";

      document.body.appendChild(ht);

      // check if we stay inside the window
      if ((curtop + ht.clientHeight + 18 - window.scrollY) > window.innerHeight) {
	ht.style.top = window.innerHeight - ht.clientHeight - 18 + window.scrollY;
      }
      if ((curleft + ht.clientWidth + 15 - window.scrollX) > window.innerWidth) {
	ht.style.left = curleft - ht.clientWidth - 15 + window.scrollX;
      }

      var timeout = 20000;
      if (document.getElementById('tooltip_timeout_'+obj_id)) {
	timeout = document.getElementById('tooltip_timeout_'+obj_id).value;
      }
      setTimeout("killTip('"+obj_id+"_ht')", timeout);
    }
  }
}

function killTip(tip_id) {
  if (document.getElementById(tip_id)) {
    document.body.removeChild(document.getElementById(tip_id));
  }
}
