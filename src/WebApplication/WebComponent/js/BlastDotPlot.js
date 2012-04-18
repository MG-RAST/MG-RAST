function move(dir, which) {
  var sel = document.getElementById(which);
  var pos = sel.selectedIndex;
  var triangle_text = sel.options[pos].text;
  var triangle_value = sel.options[pos].value;
  if (dir == 'up') {
    if (pos > 0) {
      if (sel.options.length > 1) {
	sel.options[pos] = new Option(sel.options[pos - 1].text, sel.options[pos - 1].value);
	sel.options[pos - 1] = new Option(triangle_text, triangle_value, true);
      }
    }
  } else {
    if (pos < (sel.options.length - 1)) {
      sel.options[pos] = new Option(sel.options[pos + 1].text, sel.options[pos + 1].value);
      sel.options[pos + 1] = new Option(triangle_text, triangle_value, true);
    }
  }
}

function select_all_and_submit() {
  var contigs_a = document.getElementById('contigs_a');
  var contigs_b = document.getElementById('contigs_b');
  for (i=0;i<contigs_a.options.length;i++) {
    contigs_a.options[i].selected = true;
  }
  for (i=0;i<contigs_b.options.length;i++) {
    contigs_b.options[i].selected = true;
  }
  document.forms.order_form.submit();
}

//document.onmousedown=mouseDown;
//document.onmousemove=mouseMove;
//document.onmouseup=mouseUp;
//var dragObject  = null;
//var mouseOffset = null;
//var dragTop = 0;
//var dragLeft = 0;

function mouseMove(ev){
  ev           = ev || window.event;
  var mousePos = mouseCoords(ev);
  
  if(dragObject){
    dragObject.style.height = mousePos.y - dragTop;
    dragObject.style.width = mousePos.x - dragLeft;
    
    return false;
  }
}

function mouseDown(ev){
  ev = ev || window.event;

  if (ev.target.id == 'dotplot') {
  
    var mousePos = mouseCoords(ev);

    var img = document.getElementById('dotplot');
    if ((mousePos.y - img.offsetTop) && ((mousePos.y - img.offsetTop) < 650) && ((mousePos.x - img.offsetLeft) > 100) && ((mousePos.x - img.offsetLeft) < 900)) {
    
      dragTop = mousePos.y;
      dragLeft = mousePos.x;
      
      dragObject = document.createElement('div');
      dragObject.style.border   = "1px solid black";
      dragObject.style.width    = "0px";
      dragObject.style.height   = "0px";
      dragObject.style.position = 'absolute';
      dragObject.style.top      = dragTop;
      dragObject.style.left     = dragLeft;
      document.body.appendChild(dragObject);
    }
  }

  return false;
}

function mouseUp(ev){
  ev = ev || window.event;
  if (dragObject) {
    document.body.removeChild(dragObject);
    dragObject = null;

    var img = document.getElementById('dotplot');
    var x_factor = document.getElementById('bp_a').value / 800;
    var y_factor = document.getElementById('bp_b').value / 650;
    var mousePos = mouseCoords(ev);
    document.getElementById('start_a').value = parseInt((dragLeft - 100 - img.offsetLeft) * x_factor);
    document.getElementById('stop_a').value = parseInt((mousePos.x - 100 - img.offsetLeft) * x_factor);
    document.getElementById('start_b').value = parseInt((650 - (mousePos.y - img.offsetTop)) * y_factor);
    document.getElementById('stop_b').value = parseInt((650 - (dragTop - img.offsetTop)) * y_factor);
  }
}

function mouseCoords(ev){
  if (ev.pageX || ev.pageY){
    return {x:ev.pageX, y:ev.pageY};
  }
  return { x:ev.clientX + document.body.scrollLeft - document.body.clientLeft,
      y:ev.clientY + document.body.scrollTop  - document.body.clientTop  };
}

function getPosition(e){
  var left = 0;
  var top  = 0;
  
  while (e.offsetParent){
    left += e.offsetLeft;
    top  += e.offsetTop;
    e     = e.offsetParent;
  }
  
  left += e.offsetLeft;
  top  += e.offsetTop;
  
  return {x:left, y:top};
}

function show_region (which) {
  var org = '';
  var win = '';
  var start = '';
  if (which == 'a') {
    org = document.getElementById('org_a').value;
    win = document.getElementById('stop_a').value - document.getElementById('start_a').value;
    start = document.getElementById('start_a').value;
  } else {
    org = document.getElementById('org_b').value;
    win = document.getElementById('stop_b').value - document.getElementById('start_b').value;
    start = document.getElementById('start_b').value;
  }
  if (win < 4000) {
    win = 4000;
  }
  window.open("?page=BrowseGenome&organism="+org+"&window_size="+win+"&start="+start, "browse_" + which);
}
