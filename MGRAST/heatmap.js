function heatmap_data(id){
  var re1 = new RegExp("@!", "g");
  var re2 = new RegExp("\n", "g");
  var re3 = new RegExp("---", "g");
  this.rows = convert2int(document.getElementById("rows_" + id).value.replace(re1, "'").split(/\^/));
  this.row_names = document.getElementById("row_names_" + id).value.replace(re1, "'").replace(re2, "").replace(re3, ",").split(/\^/); 

  var row_den_data = document.getElementById("row_den_" + id).value.replace(re1, "'").split("@");  
  this.row_den = new Array ();
  for (i=0;i<row_den_data.length;i++) {
    if (row_den_data[i] != "") {
      var tmp = row_den_data[i].split("^");
      this.row_den.push([parseInt(tmp[0]),parseInt(tmp[1]),parseFloat(tmp[2])]);
    }
  }

  this.columns = convert2int(document.getElementById("columns_" + id).value.replace(re1, "'").split(/\^/));
  this.column_names = document.getElementById("column_names_" + id).value.replace(re1, "'").replace(re2, "").split(/\^/);

  var column_den_data = document.getElementById("column_den_" + id).value.replace(re1, "'").split("@");  
  this.column_den = new Array ();
  for (i=0;i<column_den_data.length;i++) {
    if (column_den_data[i] != "") {
      var tmp = column_den_data[i].split("^");
      this.column_den.push([parseInt(tmp[0]),parseInt(tmp[1]),parseFloat(tmp[2])]);
    }
  }

  var table_data = document.getElementById("table_" + id).value.replace(re1, "'").split("@");  
  this.table = new Array ();
  for (i=0;i<table_data.length;i++) {
    if (table_data[i] != "") {
      this.table.push(table_data[i].split("^"));
    }
  }
}

function draw_heatmap(div, input_id, max_value, cell_w, cell_h) {
  if ( document.getElementById(div).innerHTML != ""){
    return;
  }
  // cell height / width
  cell_w = cell_w || 50;
  cell_h = cell_h || 10;

  var d = new heatmap_data(input_id);
  var cnames = d.column_names;
  for (i=0; i<cnames.length; i++) {
    cnames[i] = cnames[i].substr(2);
  }
  
  var offset_x = 250;
  var offset_y = 150;

  var image_w = (d.columns.length * cell_w) + offset_x + 300;
  var image_h = (d.rows.length * cell_h) + offset_y + 100;

  var img = Raphael(div, image_w, image_h);
  heatmap_table(img, d, max_value, cell_h, cell_w, offset_x, offset_y);
  heatmap_label(img, cnames, (offset_x + (cell_w / 2)), ((d.rows.length * cell_h) + offset_y + 5), cell_w, 1); 
  heatmap_label(img, d.row_names, ((d.columns.length * cell_w) + offset_x + 5), (offset_y + (cell_h / 2)), cell_h, 0);
  heatmap_column_dendagram(img, d.column_den, d.columns, offset_y-25, offset_x, offset_y - 5, cell_w, 0);
  heatmap_row_dendagram(img, d.row_den, d.rows, 500, offset_x-5, (offset_y + (cell_h * d.rows.length) - (cell_h/2)), cell_h, 1);
}

function heatmap_column_dendagram(img, d, d_array, height, x, y, cell_w, rotate){
  var inteval = parseInt(height / d.length);
  var pairs = new Array;
  var path = "";
  for (i in d){
    var r = new point(0,0, d_array.indexOf(Math.abs(d[i][0])) );
    var l  = new point(0,0, d_array.indexOf(Math.abs(d[i][1])) );

    if (d[i][0] < 0 && d[i][1] < 0) {
      r.x = (r.value * cell_w) + x + (cell_w / 2);
      r.y = y;
      l.x = (l.value * cell_w) + x + (cell_w / 2);
      l.y = y;
    } 
    else {
      if (d[i][0] < 0) {
	r.x = (r.value * cell_w) + x + (cell_w / 2);
	r.y = y;
      } else {
	r.x = pairs[(d[i][0]-1)][0];
	r.y = pairs[(d[i][0]-1)][1];
      }
      if (d[i][1] < 0) {
	l.x = (l.value * cell_w) + x + (cell_w / 2);
	l.y = y;
      } else {
	l.x = pairs[(d[i][1]-1)][0];
	l.y = pairs[(d[i][1]-1)][1];
      }
    }

    var h = ((r.y-inteval) < (l.y-inteval)) ? (r.y-inteval) : (l.y-inteval);    
    path += "M"+r.x+" "+r.y+"L"+r.x+" "+h+"L"+l.x+" "+h+"L"+l.x+" "+l.y;      
    pairs.push([((l.x+r.x)/2), h]);
  }
  var den = img.path(path);
}

function heatmap_row_dendagram(img, d, d_array, height, x, y, cell_w, rotate){
  var inteval = 3; /*parseInt(height / d.length);*/
  var pairs = new Array;
  var path = "";
  y += 5;
  
  for (i in d){
    var r = new point(0,0, d_array.indexOf(Math.abs(d[i][0])) );
    var l  = new point(0,0, d_array.indexOf(Math.abs(d[i][1])) );

    if (d[i][0] < 0 && d[i][1] < 0) {
      r.x = (r.value * cell_w) + x + (cell_w / 2);
      r.y = y;
      l.x = (l.value * cell_w) + x + (cell_w / 2);
      l.y = y;
    } 
    else {
      if (d[i][0] < 0) {
	r.x = (r.value * cell_w) + x + (cell_w / 2);
	r.y = y;
      } else {
	r.x = pairs[(d[i][0]-1)][0];
	r.y = pairs[(d[i][0]-1)][1];
      }
      if (d[i][1] < 0) {
	l.x = (l.value * cell_w) + x + (cell_w / 2);
	l.y = y;
      } else {
	l.x = pairs[(d[i][1]-1)][0];
	l.y = pairs[(d[i][1]-1)][1];
      }
    }

    var h = ((r.y-inteval) < (l.y-inteval)) ? (r.y-inteval) : (l.y-inteval);    
    path += "M"+r.x+" "+r.y+"L"+r.x+" "+h+"L"+l.x+" "+h+"L"+l.x+" "+l.y;      
    pairs.push([((l.x+r.x)/2), h]);
  }
  var den = img.path(path);
  den.rotate(270, x, y);
}

function heatmap_table(img, d, max_value, cell_h, cell_w, offset_x, offset_y) {  
  var colors = heatmap_colors();
  var color_interval = max_value/(colors.length-1);

  for(r=0; r<d.rows.length; r++){
    for(c=0, x=offset_x, y=((r * cell_h) + offset_y); c<d.columns.length; c++,x+=cell_w){
      cell_value = pFA(d.table[(d.rows[r]-1)][(d.columns[c]-1)].substr(0,8));
      img.rect(x,y,cell_w,cell_h).attr({fill: colors[parseInt(cell_value / color_interval)], stroke: 0, title: cell_value});
    }
  }
}

function heatmap_label(img, names, x, y, interval, rotate){
  for (n in names) {
    var label = img.text(x, y, names[n]).attr({fill: "black"});
    label.click(function (event) {
	if (this.attr("fill") == "green") {
	  this.attr({fill: "black"});
	} else {
	  this.attr({fill: "green"});
	}
      });
    if (rotate) {
      label.rotate(90);
      label.translate(0, (label.getBBox().width / 2));
      x += interval;
    } else {
      label.translate((label.getBBox().width / 2),0);
      y += interval;
    }
  }
}

function convert2int (arry){
  for(i=0;i<arry.length;i++){
    arry[i] = parseInt(arry[i]);
  }
  return arry;
}

function pFA(a) {
  var b = ~~a;
  return b + (a - b);
 }

function convert2float (arry){
  for(i=0;i<arry.length;i++){
    arry[i] = parseFloat(arry[i]);
  }
  return arry;
}

function point(x, y, value){
  this.x = x || 0;
  this.y = y || 0;
  this.value = value || "";
}

function heatmap_colors() {
  return ["FF0000","F70700","EF0F00","E71700","DF1F00","D72700","CF2F00","C73700","BF3F00","B74700","AF4F00","A75700","9F5F00","976700","8F6F00","877700","7F7F00","778700","6F8F00","679700","5F9F00","57A700","4FAF00","47B700","3FBF00","37C700","2FCF00","27D700","1FDF00","17E700","0FEF00","07F700","00FF00"];
}
