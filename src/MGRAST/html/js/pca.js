var raphs = new Array();
var pca_points = new Array();
var curr_move_square;
var curr_move_id;
var curr_move_div;
var curr_move_x;
var curr_move_y;
var curr_obj_x;
var curr_obj_y;
var pca_x_title = new Array();
var pca_y_title = new Array();

function draw_pca(div, id, c1, c2) {
  if ( document.getElementById(div).innerHTML != ""){
    return;
  }
  var size = 600;
  var offset_x = 50;
  var offset_y = 50;
  var img = Raphael(div, size+offset_x+ offset_y, size+offset_x+ offset_y);
  raphs[id] = img;

  document.getElementById(div).addEventListener('mousedown', function (e) {
      curr_move_div = this;
      curr_move_id = id;
      start_square(e);
    }, false);

  document.getElementById(div).addEventListener('mouseup', function (e) {
      end_square(e);
    }, false);

  var d = new pca_data(id);

  /*x_min, x_max, x_diff, y_min, y_max, y_diff*/  
  var mmd = min_max(d.items, c1, c2);
 
  pca_box(img, offset_x, offset_y, size, mmd[0], mmd[1], mmd[2], mmd[3], mmd[4], mmd[5], id, c1, c2);
  pca_items(img, d.items, offset_x, offset_y, size, mmd[0], mmd[2], mmd[3], mmd[5],c1, c2, id);
  
  for (i=0; i<pca_points[id].length; i++) {
    change_pca_color(document.getElementById('group_list'+id+'_'+i), id, i)
    pca_points[id][i].toFront();
  }
}

function start_square (e) {
  if (! e) { e = window.event; }
  var posx;
  var posy;
  if (e.pageX || e.pageY) 	{
    posx = e.pageX;
    posy = e.pageY;
  }
  else if (e.clientX || e.clientY) 	{
    posx = e.clientX + document.body.scrollLeft
      + document.documentElement.scrollLeft;
    posy = e.clientY + document.body.scrollTop
      + document.documentElement.scrollTop;
  }
  curr_obj_x = curr_obj_y = 0;
  var obj = curr_move_div;
  if (obj.offsetParent) {
    do {
      curr_obj_x += obj.offsetLeft;
      curr_obj_y += obj.offsetTop;
    } while (obj = obj.offsetParent);
  }
  curr_move_x = posx - curr_obj_x;
  curr_move_y = posy - curr_obj_y;

  curr_move_div.addEventListener('mousemove', function (e) {
      move_square(e);
    }, false);
  
  if (curr_move_square) {
    curr_move_square.remove();
  }
  curr_move_square = raphs[curr_move_id].rect(curr_move_x, curr_move_y, 1, 1).attr({ stroke: 'black' });
}

function move_square (e) {
  if (! e) { e = window.event; }
  var posx;
  var posy;
  if (e.pageX || e.pageY) 	{
    posx = e.pageX;
    posy = e.pageY;
  }
  else if (e.clientX || e.clientY) 	{
    posx = e.clientX + document.body.scrollLeft
      + document.documentElement.scrollLeft;
    posy = e.clientY + document.body.scrollTop
      + document.documentElement.scrollTop;
  }
  posx -= curr_obj_x;
  posy -= curr_obj_y;
  posx -= curr_move_x;
  posy -= curr_move_y;

  curr_move_square.attr( { width: posx } );
  curr_move_square.attr( { height: posy } );
}

function end_square (e) {
  if (! e) { e = window.event; }
  var posx;
  var posy;
  if (e.pageX || e.pageY) {
    posx = e.pageX;
    posy = e.pageY;
  }
  else if (e.clientX || e.clientY) {
    posx = e.clientX + document.body.scrollLeft
      + document.documentElement.scrollLeft;
    posy = e.clientY + document.body.scrollTop
      + document.documentElement.scrollTop;
  }
  posx -= curr_obj_x;
  posy -= curr_obj_y;

  curr_move_square.remove();
  curr_move_div.onmousemove = null;

  for (i in pca_points[curr_move_id]) {
    if (pca_points[curr_move_id][i].attr("cx") > curr_move_x && pca_points[curr_move_id][i].attr("cx") < posx && pca_points[curr_move_id][i].attr("cy") > curr_move_y && pca_points[curr_move_id][i].attr("cy") < posy) {
      point_clicked(pca_points[curr_move_id][i]);
    }
  }
}

function change_pca_color(sel, tabnum, id) {
  var grp = sel.options[sel.selectedIndex].value;
  if (grp == 0) {
    pca_points[tabnum][id].attr({ fill: "white" });
  } else if (grp == "group1") {
    pca_points[tabnum][id].attr({ fill: "red" });
  } else if (grp == "group2") {
    pca_points[tabnum][id].attr({ fill: "green" });
  } else if (grp == "group3") {
    pca_points[tabnum][id].attr({ fill: "cyan" });
  } else if (grp == "group4") {
    pca_points[tabnum][id].attr({ fill: "purple" });
  } else if (grp == "group5") {
    pca_points[tabnum][id].attr({ fill: "yellow" });
  } else if (grp == "group6") {
    pca_points[tabnum][id].attr({ fill: "blue" });
  } else if (grp == "group7") {
    pca_points[tabnum][id].attr({ fill: "orange" });
  } else if (grp == "group8") {
    pca_points[tabnum][id].attr({ fill: "gray" });
  } else if (grp == "group9") {
    pca_points[tabnum][id].attr({ fill: "black" });
  } else if (grp == "group10") {
    pca_points[tabnum][id].attr({ fill: "magenta" });
  }
}

function pca_items(img, items, offset_x, offset_y, size, x_min, x_diff, y_min, y_diff, c1, c2, id){
  var x, y;
  pca_points[id] = new Array();
  for (k=0;k<items.length;k++){
    x = offset_x + ((Math.abs(items[k][c1] - x_min) / x_diff)*size);
    y = (size + offset_y) - ((Math.abs(items[k][c2] - y_min) / y_diff)*size);
    img.text(x,y - 10, items[k][0].substr(2)).attr({title: items[k][c1].toFixed(6)+" : "+items[k][c2].toFixed(6)});
    pca_points[id][k] = img.circle(x, y, 4);
    pca_points[id][k].mousedown(function (event) {
	point_clicked(this);
      });
  }
}

function min_max(items, c1, c2){
  var c1_min, c1_max, c2_min, c2_max;   
  for (i=0; i<items.length; i++){
    c1_min = (c1_min && c1_min < items[i][c1]) ? c1_min : items[i][c1];
    c1_max = (c1_max && c1_max > items[i][c1]) ? c1_max : items[i][c1];
    c2_min = (c2_min && c2_min < items[i][c2]) ? c2_min : items[i][c2];
    c2_max = (c2_max && c2_max > items[i][c2]) ? c2_max : items[i][c2];
  }
  // If min == max for either axis, we want to artificially create a gap between
  //  them so that the axis has some span, otherwise the plot is messed up.
  if(c1_min == c1_max) {
    c1_min = c1_min - 0.5;
    c1_max = c1_max + 0.5;
  }
  if(c2_min == c2_max) {
    c2_min = c2_min - 0.5;
    c2_max = c2_max + 0.5;
  }
  var c1_diff = Math.abs(c1_min - c1_max);
  var c2_diff = Math.abs(c2_min - c2_max);
  return [(c1_min-(c1_diff*0.1)),(c1_max+(c1_diff*0.1)), Math.abs((c1_max+(c1_diff*0.1))-(c1_min-(c1_diff*0.1))),(c2_min-(c2_diff*0.1)),(c2_max+(c2_diff*0.1)), Math.abs((c2_max+(c2_diff*0.1))-(c2_min-(c2_diff*0.1)))];
}

function pca_box(img, offset_x, offset_y, size, x_min, x_max, x_diff, y_min, y_max, y_diff, id, xname, yname){
  img.rect(offset_x,offset_y,size,size).attr({stroke: 1});
  var points = new Array ( [ [offset_x+(size*0.1), offset_y+size], (x_min + (x_diff * 0.1))],
			   [ [offset_x+(size*0.3), offset_y+size], (x_min + (x_diff * 0.3))],
			   [ [offset_x+(size*0.5), offset_y+size], (x_min + (x_diff * 0.5))],
			   [ [offset_x+(size*0.7), offset_y+size], (x_min + (x_diff * 0.7))],
			   [ [offset_x+(size*0.9), offset_y+size], (x_min + (x_diff * 0.9))] );

  for (p in points) {
    img.path("M"+points[p][0][0]+" "+points[p][0][1]+"L"+points[p][0][0]+" "+(points[p][0][1]+5));
    img.text(points[p][0][0], (points[p][0][1]+10), fixFloat(points[p][1]));
  }

  points = new Array ( [ [offset_x, (offset_y+size)-(size*0.1)], (y_min + (y_diff * 0.1))],
		       [ [offset_x, (offset_y+size)-(size*0.3)], (y_min + (y_diff * 0.3))],
		       [ [offset_x, (offset_y+size)-(size*0.5)], (y_min + (y_diff * 0.5))],
		       [ [offset_x, (offset_y+size)-(size*0.7)], (y_min + (y_diff * 0.7))],
		       [ [offset_x, (offset_y+size)-(size*0.9)], (y_min + (y_diff * 0.9))] );

  for (p in points) {
    img.path("M"+points[p][0][0]+" "+points[p][0][1]+"L"+(points[p][0][0]-5)+" "+points[p][0][1]);
    img.text((points[p][0][0]-10), points[p][0][1], fixFloat(points[p][1])).rotate(-90);
  }

  pca_x_title[id] = img.text(img.width / 2, img.height - 15, 'PCO'+xname);
  pca_y_title[id] = img.text(15, img.height / 2, 'PCO'+yname);

}

function fixFloat(f){
  var tmp = Math.abs(f);
  if(tmp >= 0.1) {
    return f.toFixed(1);
  } else if (tmp >= 0.01) {
    return f.toFixed(2);
  } else if (tmp >= 0.001) {
    return f.toFixed(3);
  } else if (tmp >= 0.0001) {
    return f.toFixed(4);
  } else if (tmp >= 0.00001) {
    return f.toFixed(5);
  } else if (tmp >= 0.000001) {
    return f.toFixed(6);
  } else if (tmp >= 0.0000001) {
    return f.toFixed(7);
  } else if (tmp >= 0.00000001) {
    return f.toFixed(8);
  } else if (tmp >= 0.000000001) {
    return f.toFixed(9);
  } else if (tmp >= 0.0000000001) {
    return f.toFixed(10);
  } else if (tmp >= 0.00000000001) {
    return f.toFixed(11);
  } else if (tmp >= 0.000000000001) {
    return f.toFixed(12);
  } else {
    return f;
  }
}

function pca_data(id){
  var components_data = document.getElementById("pca_components_" + id).value.split("@");
  this.components = new Array();
  for (i=0;i<components_data.length;i++) {
    if (components_data[i] != "") {
      var tmp = components_data[i].split("^");
      this.components.push([tmp[0],parseFloat(tmp[1])]);
    }
  }
  var items_data = document.getElementById("pca_items_" + id).value.split("@");
  this.items = new Array();
  for (i=0;i<items_data.length;i++) {
    if (items_data[i] != "") {
      var tmp = items_data[i].split("^");
      tmp[0] = tmp[0].replace(/A/, ".");
      var tmpA = [tmp[0]];
      for (x=1; x<tmp.length; x++){
	tmpA.push(parseFloat(tmp[x]));
      }
      this.items.push(tmpA);
    }
  }
}

function pca_colors() {
  return ["FF0000","F70700","EF0F00","E71700","DF1F00","D72700","CF2F00","C73700","BF3F00","B74700","AF4F00","A75700","9F5F00","976700","8F6F00","877700","7F7F00","778700","6F8F00","679700","5F9F00","57A700","4FAF00","47B700","3FBF00","37C700","2FCF00","27D700","1FDF00","17E700","0FEF00","07F700","00FF00"];
}

function change_pca_spot(id, pos, att, sel) {
  if (att == 'color') {
    pca_points[id][pos].attr("stroke", sel.options[sel.selectedIndex].value);
  }
}

function point_clicked(dot) {
  var id;
  var ind;
  for (id=0; id<pca_points.length; id++) {
    if (pca_points[id] != null) {
      for (ind=0; ind<pca_points[id].length; ind++) {
	if (dot == pca_points[id][ind]) {
	  break;
	}
      }
      if (dot == pca_points[id][ind]) {
	break;
      }
    }
  }
  var sel = document.getElementById('group_color'+id);
  dot.attr( { fill: sel.options[sel.selectedIndex].value } );
  var list = document.getElementById('group_list'+id+'_'+ind);
  for (i=0;i<list.options.length;i++) {
    if (list.options[i].text == sel.options[sel.selectedIndex].text) {
      list.options[i].selected = true;
    } else {
      list.options[i].selected = false;
    }
  }
}

function check_pca_components(id) {
  var c1 = 0;
  var c2 = 0;
  var xcomp = document.getElementsByName('xcomp'+id);
  for (i in xcomp) {
    if (xcomp[i].checked) {
      c1 = xcomp[i].value;
    }
  }
  var ycomp = document.getElementsByName('ycomp'+id);
  for (i in ycomp) {
    if (ycomp[i].checked) {
      c2 = ycomp[i].value;
    }
  }
  document.getElementById('pca_canvas_'+id).innerHTML = '';
  draw_pca('pca_canvas_'+id, id, c1, c2);
}

function check_metadata(id, sel) {
  var metadata = document.getElementById('pcamd_'+id).value.split("~~");
  var ind = sel.selectedIndex;
  for (i=0; i<metadata.length; i++) {
    var splitmd = metadata[i].split(";;");
    document.getElementById('group_list_md_'+id+'_'+i).innerHTML = splitmd[ind];
  }
}

function color_by_metadata(id) {
  var metadata = document.getElementById('pcamd_'+id).value.split("~~");
  var grphash = new Array();
  var numgrps = 0;
  for (i=0; i<pca_points[id].length; i++) {
    var curr = document.getElementById('group_list_md_'+id+'_'+i).innerHTML;
    if (grphash[curr] == null) {
      numgrps++;
      grphash[curr] = numgrps;
    }
  }

  for (h=0; h<pca_points[id].length; h++) {
    var list = document.getElementById('group_list'+id+'_'+h);
    for (i=0;i<list.options.length;i++) {
      if (list.options[i].value == 'group'+grphash[document.getElementById('group_list_md_'+id+'_'+h).innerHTML]) {
	list.options[i].selected = true;
      } else {
	list.options[i].selected = false;
      }
    }
    change_pca_color(document.getElementById('group_list'+id+'_'+h), id, h)
  }
}

function save_group_to_collection (id, which) {
  var name = document.getElementById('group'+which+'_collection_name').value;
  if (! name.length) {
    alert('you must choose a name for the collection');
    return;
  }
  var members = new Array();
  for (h=0; h<pca_points[id].length; h++) {
    var list = document.getElementById('group_list'+id+'_'+h);
    for (i=0;i<list.options.length;i++) {
      if (list.options[i].text == 'group '+which && list.options[i].selected == true) {
	members[members.length] = list.parentNode.previousSibling.innerHTML;
      }
    }
  }
  if (! members.length) {
    alert('this group has no members');
    return;
  }
  execute_ajax('add_collection', 'feedback'+id, 'newcollection='+name+'&ids='+members.join('|'));
}
