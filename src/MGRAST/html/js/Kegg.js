var img;
var names = new Array();
var polys = new Array();
var submaps = new Array();
var fac = 0.25;
var buf_a = [];
var buf_b = [];
var buf_c = [];

function color_map (poly, color) {
    if (color == null) {
      color = "#f00";
    }
    var l;
    var title;
    [ title, l ] = poly.split("~");
    var list = l.split(",");
    var p = "M "+parseInt(list[0]*fac)+" "+parseInt(list[1]*fac);
    for (i=2; i<list.length; i+=2) {
      p += "L "+parseInt(list[i]*fac)+" "+parseInt(list[i+1]*fac);
    }
    var l = img.path(p);
    title = title.replace(/, /g, "+");
    title = title.replace(/ \(\w+\)/g, "");
    l.attr({fill: color, stroke: color, href: "javascript:void(window.open('http://www.genome.jp/dbget-bin/www_bget?"+title+"','_blank','width=750,height=640,resizable=yes,scrollbars=yes,status=yes,toolbar=yes,location=yes'))"});
}

function tobuff () {
  var kdata = document.getElementById('keggdata').value.split("~");
  var list = [];
  var nname;
  var nnum;
  for (i=0; i<kdata.length; i++) {
    [nname, nnum] = kdata[i].split(";");
    list[nname] = nnum;
  }
  var newtext = "<table>";
  newtext += "<tr><td><b>metagenomes</b></td><td>"+document.getElementById('mgids').value+"</td></tr>";
  newtext += "<tr><td><b>max e-value</b></td><td>"+document.getElementById('evalue').value+"</td></tr>";
  newtext += "<tr><td><b>min %-identity</b></td><td>"+document.getElementById('identity').value+"</td></tr>";
  newtext += "<tr><td><b>min alignment length</b></td><td>"+document.getElementById('alength').value+"</td></tr>";
  newtext += "</table>";
  if (document.getElementById('whichbuf').value == 'buffer_space_a') {
    buf_a = list;
    document.getElementById('buf_a_text').innerHTML = newtext;
  } else {
    buf_b = list;
    document.getElementById('buf_b_text').innerHTML = newtext;
  }
}

function export_kegg_abundance () {
  var kids = [];
  var abu = [];
  var which = [];

  if(Object.keys(buf_a).length == 0 && Object.keys(buf_b).length == 0) {
    alert('You must load a metagenome into Data A or Data B before you can export the abundance.');
    return false;
  }

  for (i in buf_a) {
    kids.push(i);
    abu.push(buf_a[i]);
    which.push('a');
  }

  for (i in buf_b) {
    kids.push(i);
    abu.push(buf_b[i]);
    which.push('b');
  }
  
  var str_kids = kids.join('~');
  var str_abu = abu.join('~');
  var str_which = which.join('~');

  var html_abundance_table = "";
  $.ajax({ async: false, type: "POST", url: "metagenomics.cgi", data: { page: "KeggMapper", action: "export_kegg_abundance", format: "html", kids: str_kids, abu: str_abu, which: str_which }, success: function (result) {
    html_abundance_table = result;
  }});

  var html = "<html><form id=\"saveTextForm\" method=\"post\" action=\"metagenomics.cgi\"><input type=\"hidden\" name=\"page\" value=\"KeggMapper\"><input type=\"hidden\" name=\"action\" value=\"export_kegg_abundance\"><input type=\"hidden\" name=\"format\" value=\"text\" /><input type=\"hidden\" name=\"kids\" value=\""+str_kids+"\" /><input type=\"hidden\" name=\"abu\" value=\""+str_abu+"\" /><input type=\"hidden\" name=\"which\" value=\""+str_which+"\" /><input type=\"submit\" value=\"Click to save as tab-delimited text file\" /></form><br /><br />";

  html += html_abundance_table+"</html>";

  var my_window = window.open("", "", "width=650,height=700,scrollbars,resizable");
  my_window.document.open('text/html');
  my_window.document.write(html);
}

function compare () {
  var all_a = [];
  var all_b = [];
  var kids = [];
  var abu = [];
  var which = [];
  for (i in buf_a) {
    kids.push(i);
    abu.push(buf_a[i]);
    which.push('a');
    if (names[i]) {
      for (h=0;h<names[i].length;h++) {
	if (all_a[names[i][h]] != null) {
	  all_a[names[i][h]] += buf_a[i];
	} else {
	  all_a[names[i][h]] = buf_a[i];
	}
      }
    }
  }

  for (i in buf_b) {
    kids.push(i);
    abu.push(buf_b[i]);
    which.push('b');
    if (names[i]) {
      for (h=0;h<names[i].length;h++) {
	if (all_b[names[i][h]] != null) {
	  all_b[names[i][h]] += buf_b[i];
	} else {
	  all_b[names[i][h]] = buf_b[i];
	}
      }
    }
  }
  
  for (i in all_a) {
    if (all_b[i]) {
      if (buf_c[i]) {
	buf_c[i] += parseInt(all_b[i]);
      } else {
	buf_c[i] = parseInt(all_a[i]) + parseInt(all_b[i]);
      }
    }
  }
 
  for (i in buf_c) {
    delete all_b[i];
    delete all_a[i];
  }

  document.getElementById('kids').value = kids.join('~');
  document.getElementById('abu').value = abu.join('~');
  document.getElementById('which').value = which.join('~');

  img.clear();

  var which = document.getElementById('result_type').options[document.getElementById('result_type').selectedIndex].value;

  if (which == 'abc' || which == 'ab' || which == 'a' || which == 'ac') {
    for (i in all_a) {
      color_map(polys[i], "#00f");
    }
  }

  if (which == 'abc' || which == 'ab' || which == 'b' || which == 'bc') {
    for (i in all_b) {
      color_map(polys[i], "#f00");
    }
  }

  if (which == 'abc' || which == 'c' || which == 'ac' || which == 'bc') {
    for (i in buf_c) {
      color_map(polys[i], "#f0f");
    }
  }

  link_submaps();
}

function clear_buffer (which) {
  if (which == 'a') {
    buf_a = [];
    if (buf_b.length) {
      for (i in buf_c) {
	buf_b[i] = buf_c[i];
      }
    }
    document.getElementById('buf_a_text').innerHTML = "";
  } else {
    buf_b = [];
    if (buf_a.length) {
      for (i in buf_c) {
	buf_a[i] = buf_c[i];
      }
    }
    buf_c = new Array();
    document.getElementById('buf_b_text').innerHTML = "";
  }
}

function scale_image () {
  fac = document.getElementById('scalefactor').value / 100;
  document.getElementById('m').style.width = parseInt(3695*fac)+"px";
  document.getElementById('m').style.height = parseInt(2250*fac)+"px";
  img.remove();
  img = Raphael(document.getElementById('raph'), parseInt(3695*fac), parseInt(2250*fac));
  document.getElementById('raph').style.top = "-"+parseInt(2250*fac)+"px";
  compare();
}

function initialize_kegg () {
  img = Raphael(document.getElementById('raph'), parseInt(3695*fac), parseInt(2250*fac));
  document.getElementById('raph').style.position = "relative";
  document.getElementById('raph').style.top = "-"+parseInt(2250*fac)+"px";
  polys = document.getElementById('polys').value.split(";");
  var ns = document.getElementById('names').value.split("~~");
  for (i=0;i<ns.length;i++) {
    var cn = ns[i].split(";");
    if (cn[0].match(/^map/)) {
      submaps[cn[0]] = cn[1];
    } else {
      names[cn[0]] = new Array();
      for (h=1;h<cn.length;h++) {
	names[cn[0]][names[cn[0]].length] = cn[h];
      }
    }
  }
}

function ok_button(lsid) {
  document.getElementById('sel_mg').style.display="none";
  document.getElementById("mg_sel_td").innerHTML="";
  for (i=0;i<document.getElementById("list_select_list_b_"+lsid).options.length;i++) {
    document.getElementById("mg_sel_td").innerHTML += "<a href='metagenomics.cgi?page=MetagenomeOverview&metagenome="+document.getElementById("list_select_list_b_"+lsid).options[i].value+"' style='cursor: help;' title='"+document.getElementById("list_select_list_b_"+lsid).options[i].text+"' target=_blank>"+document.getElementById("list_select_list_b_"+lsid).options[i].value+"</a>, ";
  }
  document.getElementById("mg_sel_td").innerHTML=document.getElementById("mg_sel_td").innerHTML.substr(0, document.getElementById("mg_sel_td").innerHTML.lastIndexOf(","));
}

function link_submaps() {
  color = "#000";
  for (h in submaps) {
    var l;
    var title;
    [ title, l ] = polys[submaps[h]].split("~");
    var list = l.split(",");
    var r = img.rect(parseInt(list[0]*fac), parseInt(list[1]*fac), parseInt((list[2] - list[0])*fac), parseInt((list[3] - list[1])*fac));
    r.attr({fill: color, opacity: 0, stroke: color, href: "javascript:submap_link('"+title+"');"});
  }
}

function submap_link(map) {
  var mapnum = map.match(/\d+/);
  document.getElementById('mapnum').value = mapnum[0];
  execute_ajax('kegg_map', 'submap', 'kmap_form');
}
