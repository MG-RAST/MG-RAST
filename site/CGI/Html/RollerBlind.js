function activate_blind (id, which) {
  var a;
  var b;
  for (i=0;i<1000;i++) {
    var blind = document.getElementById('rb_'+id+'_'+i);
    var blind_div = document.getElementById('rb_div_'+id+'_'+i);
    if (blind) {
      if ((i == which) && (blind.className != 'RollerBlindActive')) {
	a = blind;
	aa = blind_div;
      } else {
	if (blind.className == 'RollerBlindActive') {
	  b = blind;
	  bb = blind_div;
	}
      }
    } else {
      break;
    }
  }
  if (b && a) {
    a.style.overflow = 'hidden';
    b.style.overflow = 'hidden';
    b.style.height = b.offsetHeight;
    a.className = 'RollerBlindActive';
    var ah = a.offsetHeight;
    var bh = b.offsetHeight;
    a.style.height = 0;
    aa.className = 'RollerBlindBarActive';
    bb.className = 'RollerBlindBarInactive';
    if (bh > 1000) {
      b.className = 'RollerBlindInactive';
      b.style.height = null;
      b.style.overflow = 'visible';
    } else {
      slowLess(b, 0, 10, parseInt(bh / 15));
    }
    if (ah > 1000) {
      var xy = getScrollXY();
      var x = xy[0];
      var y = xy[1];
      var wh = getSize();
      var w = wh[0];
      var h = wh[1];
      var min = y;
      var max = y + h;
      var top = findTop(a.previousSibling);
      if (top < min || top > max) {
	window.scrollTo(0,top);
      }
      a.style.overflow = 'visible';
      a.style.height = ah;
    } else {
      slowMore(a, ah, 10, parseInt(ah / 15));
    }
  } else {
    if (a) {
      a.style.overflow = 'hidden';
      a.className = 'RollerBlindActive';
      var ah = a.offsetHeight;
      a.style.height = 0;
      aa.className = 'RollerBlindBarActive';
      if (ah > 1000) {
	var xy = getScrollXY();
	var x = xy[0];
	var y = xy[1];
	var wh = getSize();
	var w = wh[0];
	var h = wh[1];
	var min = y;
	var max = y + h;
	var top = findTop(a.previousSibling);
	if (top < min || top > max) {
	  window.scrollTo(0,top);
	}
	a.style.overflow = 'visible';
	a.style.height = ah;
      } else {
	slowMore(a, ah, 10, parseInt(ah / 15));
      }
    } else {
      b.style.overflow = 'hidden';
      bh = b.offsetHeight;
      b.style.height = bh;
      bb.className = 'RollerBlindBarInactive';
      if (bh > 1000) {
	b.className = 'RollerBlindInactive';
	b.style.height = null;
	b.style.overflow = 'visible';
      } else {
	slowLess(b, 0, 10, parseInt(bh / 15));
      }
    }
  }
}

slowMoreObjects = new Object();
slowMoreTimers = new Object();
slowLessObjects = new Object();
slowLessTimers = new Object();

function slowLess(object, destHeight, rate, delta){
  clearTimeout(slowLessTimers[object.sourceIndex]);
  
  var h = parseInt(object.style.height.substring(0, object.style.height.length - 2));
  var new_h = h - delta;
  if (new_h < destHeight) {
    new_h = destHeight;
  }
  object.style.height = new_h;
  if (new_h > destHeight){
    slowLessObjects[object.sourceIndex]=object;
    slowLessTimers[object.sourceIndex]=setTimeout("slowLess(slowLessObjects["+object.sourceIndex+"],"+destHeight+","+rate+","+delta+")",rate);
  } else {
    object.className = 'RollerBlindInactive';
    object.style.height = null;
    object.style.overflow = 'visible';
  }
}

function slowMore(object, destHeight, rate, delta){
  clearTimeout(slowMoreTimers[object.sourceIndex]);
  
  var h = parseInt(object.style.height.substring(0, object.style.height.length - 2));
  var new_h = h + delta;
  if (new_h > destHeight) {
    new_h = destHeight;
  }
  object.style.height = new_h;
  if (new_h < destHeight){
    slowMoreObjects[object.sourceIndex]=object;
    slowMoreTimers[object.sourceIndex]=setTimeout("slowMore(slowMoreObjects["+object.sourceIndex+"],"+destHeight+","+rate+","+delta+")",rate);
  } else {
    var xy = getScrollXY();
    var x = xy[0];
    var y = xy[1];
    var wh = getSize();
    var w = wh[0];
    var h = wh[1];
    var min = y;
    var max = y + h;
    var top = findTop(object.previousSibling);
    if (top < min || top > max) {
      window.scrollTo(0,top);
    }
    object.style.overflow = 'visible';
    object.style.height = destHeight;
  }
}

function getScrollXY() {
  var scrOfX = 0;
  var scrOfY = 0;
  if( typeof( window.pageYOffset ) == 'number' ) {
    //Netscape compliant
    scrOfY = window.pageYOffset;
    scrOfX = window.pageXOffset;
  } else if( document.body && ( document.body.scrollLeft || document.body.scrollTop ) ) {
    //DOM compliant
    scrOfY = document.body.scrollTop;
    scrOfX = document.body.scrollLeft;
  } else if( document.documentElement && ( document.documentElement.scrollLeft || document.documentElement.scrollTop ) ) {
    //IE6 standards compliant mode
    scrOfY = document.documentElement.scrollTop;
    scrOfX = document.documentElement.scrollLeft;
  }
  return [ scrOfX, scrOfY ];
}

function getSize() {
  var myWidth = 0;
  var myHeight = 0;
  if( typeof( window.innerWidth ) == 'number' ) {
    //Non-IE
    myWidth = window.innerWidth;
    myHeight = window.innerHeight;
  } else if( document.documentElement && ( document.documentElement.clientWidth || document.documentElement.clientHeight ) ) {
    //IE 6+ in 'standards compliant mode'
    myWidth = document.documentElement.clientWidth;
    myHeight = document.documentElement.clientHeight;
  } else if( document.body && ( document.body.clientWidth || document.body.clientHeight ) ) {
    //IE 4 compatible
    myWidth = document.body.clientWidth;
    myHeight = document.body.clientHeight;
  }
  return [ myWidth, myHeight ];
}

function findTop(obj) {
  var curtop = 0;
  if (obj.offsetParent) {
    do {
      curtop += obj.offsetTop;
    } while (obj = obj.offsetParent);
  }
  return curtop;
}
