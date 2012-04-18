var lastmark = null;

function show_detail_info (hid, cid, ids, mark) {
  if (mark) {
    if (lastmark && lastmark.parentNode) {
      lastmark.parentNode.removeChild(lastmark);
    }
    var img = mark.parentNode.parentNode.firstChild;
    var top = 0;
    var left = 0;
    [ left, top ] = findPos(img);
    var coords = mark.coords;
    var ex = 0;
    var why = 0;
    var diameter = 0;
    [ ex, why, diameter ] = coords.split(',');
    left = parseInt(ex) + parseInt(left) - 3;
    top = parseInt(why) + parseInt(top) - 2;
    var newmark = document.createElement('div');
    newmark.setAttribute("style", "position: absolute; top: "+top+"px; left: "+left+"px;width: 7px; height: 7px; background-color: red;");
    mark.parentNode.parentNode.appendChild(newmark);
    lastmark = newmark;
  }
  var id_array = ids.split('|');
  var content = '';
  for (i=0;i<id_array.length;i++) {
    var obj_id = redundancies[hid]['node_'+cid+'_'+id_array[i]];
    content += document.getElementById('tooltip_'+hid+'_'+obj_id).innerHTML;
  }
  document.getElementById('phylo_detail_'+cid).innerHTML = content;
}

function findPos(obj) {
  var curleft = curtop = 0;
  if (obj.offsetParent) {
    do {
      curleft += obj.offsetLeft;
      curtop += obj.offsetTop;
    } while (obj = obj.offsetParent);
  }
  return [curleft,curtop];
}
