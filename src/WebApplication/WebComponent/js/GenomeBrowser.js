document.onmousemove = mouseMove;
document.onmouseup   = mouseUp;
document.onmousedown = mouseDown;

var dragObject  = null;
var mouseOffset = null;
var navi_bar_left = 0;
var navi_bar_right = 0;

function positionNavigation(){
  var re = new RegExp("px");
  var navi = document.getElementById('genome_browser_navi');
  var navi_width = parseInt(navi.style.width.replace(re,""));
  var navi_pos = getPosition(navi);
  var navi_bar = document.getElementById('genome_browser_navi_bar');
  var navi_bar_pos = getPosition(navi_bar);
  navi_bar_left = navi_bar_pos.x;
  var navi_bar_width = navi_bar.style.width.replace(re, "");
  navi_bar_right = parseInt(navi_bar_width) + parseInt(navi_bar_left) - navi_width;
  navi.style.left = navi_pos.x + navi_bar_left;
}

function getMouseOffset(target, e){
  if (!e) var e = window.event;
  
  var docPos    = getPosition(target);
  var mousePos  = mouseCoords(e);
  return {x:mousePos.x - docPos.x, y:mousePos.y - docPos.y};
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

function mouseMove(e){
  if(dragObject){
    if (!e) var e = window.event;
    var mousePos = mouseCoords(e);
    mousePos.x = mousePos.x - mouseOffset.x;
    if (mousePos.x > navi_bar_left && mousePos.x < navi_bar_right) {
      dragObject.style.left = mousePos.x;
      
      return false;
    }
  }
}

function mouseDown(e){
  var targ;
  if (!e) var e = window.event;
  if (e.target) targ = e.target;
  else if (e.srcElement) targ = e.srcElement;
  if (targ.nodeType == 3) // defeat Safari bug
    targ = targ.parentNode;
  if (targ == document.getElementById('genome_browser_navi')) {
    dragObject = targ;
    mouseOffset = getMouseOffset(targ, e);
  }
}

function mouseUp(){
  if (dragObject) {
    var re = new RegExp("px");
    document.getElementById('mouse_navi').value = parseInt(dragObject.style.left.replace(re,"")) - navi_bar_left;
    dragObject = null;
    document.forms.genome_browser_form.submit();
  }
}

function mouseCoords(e) {
  var posx = 0;
  var posy = 0;
  if (!e) var e = window.event;
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
  return {x:posx,y:posy};
}
