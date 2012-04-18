function position_divs(map_img) {
    var curleft = curtop = 0;
    positions = findPos(map_img);
    for (i=0;i<1000;i++) {
      var div = document.getElementById('posdiv_'+i);
      if (div) {
        div.style.left = (div.offsetLeft + positions[0]) + "px";
        div.style.top = (div.offsetTop + positions[1]) + "px";
      } else {
	break;
      }
    }
    tab_view_select('0', 0);
}

function findPos(obj) {
	var curleft = curtop = 0;
	if (obj.offsetParent) {
		curleft = obj.offsetLeft
		curtop = obj.offsetTop
		while (obj = obj.offsetParent) {
			curleft += obj.offsetLeft
			curtop += obj.offsetTop
		}
	}
	return [curleft,curtop];
}
