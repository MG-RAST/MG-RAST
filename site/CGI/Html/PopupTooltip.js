/* ---------------------------------- */
/*      Popup Tooltip Functions       */
/* ---------------------------------- */


var DIV_WIDTH=250;
var px;     // position suffix with "px" in some cases
var initialized = false;
var ns4 = false;
var ie4 = false;
var ie5 = false;
var kon = false;
var iemac = false;
var tooltip_name='popup_tooltip_div';

function Popup_Tooltip(object, tooltip_title, tooltip_text,
                       popup_menu, use_parent_pos, head_color,  body_color) {
    // the first time an object of this class is instantiated,
    // we have to setup some browser specific settings


    if(!initialized) {
         ns4 = (document.layers) ? true : false;
         ie4 = (document.all) ? true : false;
         ie5 = ((ie4) && ((navigator.userAgent.indexOf('MSIE 5') > 0) ||
                (navigator.userAgent.indexOf('MSIE 6') > 0))) ? true : false;
         kon = (navigator.userAgent.indexOf('konqueror') > 0) ? true : false;
         if(ns4||kon) {
             //setTimeout("window.onresize = function () {window.location.reload();};", 2000);
         }
         ns4 ? px="" : px="px";
		 iemac = ((ie4 || ie5) && (navigator.userAgent.indexOf('Mac') > 0)) ? true : false;

         initialized=true;
    }
    if (iemac) {
	    return;
    }
    this.tooltip_title = tooltip_title;
    this.tooltip_text = tooltip_text;
    if (head_color) {
     this.head_color = head_color;
    }
    else {
     this.head_color = "#688fc5";
    }

    if (body_color) {
     this.body_color = body_color;
    }
    else {
     this.body_color="#ffffff";
    }


    this.popup_menu = popup_menu;
    if (use_parent_pos) {
        this.popup_menu_x = object.offsetLeft;
        this.popup_menu_y = object.offsetTop + object.offsetHeight + 3;
    }
    else {
        this.popup_menu_x = -1;
        this.popup_menu_y = -1;
    }

    // create the div if necessary
    // the div may be shared between several instances
    // of this class

    this.div = getDiv(tooltip_name);
    if (!this.div) {
        // create a hidden div to contain the information
        this.div = document.createElement("div");
        this.div.id=tooltip_name;
        this.div.style.position="absolute";
        this.div.style.zIndex=0;
        this.div.style.top="0"+px;
        this.div.style.left="0"+px;
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.tooltip_visible=0;
        this.div.menu_visible=0
        document.body.appendChild(this.div);
    }
    // register methods
    this.showTip = showTip;
    this.hideTip = hideTip;
    this.fillTip = fillTip;
    this.showMenu = showMenu;
    this.hideMenu = hideMenu;
    this.fillMenu = fillMenu;
    this.addHandler = addHandler;
    this.delHandler = delHandler;
    this.mousemove = mousemove;
    this.showDiv = showDiv;

    // object state
    this.attached = object;
    object.tooltip = this;
}

function getDiv () {
    if (ie5 || ie4) {
		return document.all[tooltip_name];
	} else if (document.layers) {
        return document.layers[tooltip_name];
    }
    else if(document.all) {
        return document.all[tooltip_name];
    }
    return document.getElementById(tooltip_name);
}

function hideTip() {
    if (this.div.tooltip_visible) {
        this.div.innerHTML="";
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.tooltip_visible=0;
    }
}

function hideMenu() {
    if (this.div && this.div.menu_visible) {
        this.div.innerHTML="";
        this.div.style.visibility=ns4?"hide":"hidden";
        this.div.menu_visible=0;
    }
}

function fillTip() {
    this.hideTip();
    this.hideMenu();
    if (this.tooltip_title && this.tooltip_text) {
        this.div.innerHTML='<table width='+DIV_WIDTH+' border=0 cellpadding=2 cellspacing=0 bgcolor="'+this.head_color+'"><tr><td class="tiptd"><table width="100%" border=0 cellpadding=0 cellspacing=0><tr><th><span class="ptt"><b><font color="#000000">'+this.tooltip_title+'</font></b></span></th></tr></table><table width="100%" border=0 cellpadding=2 cellspacing=0 bgcolor="'+this.body_color+'"><tr><td><span class="pst"><font color="#000000">'+this.tooltip_text+'</font></span></td></tr></table></td></tr></table>';
        this.div.tooltip_visible=1;
    }
}


function fillMenu() {
    this.hideTip();
    this.hideMenu();
    if (this.popup_menu) {
        this.div.innerHTML='<table cellspacing="2" cellpadding="1" bgcolor="#000000"><tr bgcolor="#eeeeee"><td><div style="max-height:300px;min-width:100px;overflow:auto;">'+this.popup_menu+'</div></td></tr></table>';
        this.div.menu_visible=1;
    }
}

function showDiv(x,y) {
    winW=(window.innerWidth)? window.innerWidth+window.pageXOffset-16 :
        document.body.offsetWidth-20;
    winH=(window.innerHeight)?window.innerHeight+window.pageYOffset :
        document.body.offsetHeight;
    if (window.getComputedStyle) {
        current_style = window.getComputedStyle(this.div,null);
        div_width = parseInt(current_style.width);
        div_height = parseInt(current_style.height);
    }
    else {
        div_width = this.div.offsetWidth;
        div_height = this.div.offsetHeight;
    }
    this.div.style.left=(((x + div_width) > winW) ? winW - div_width : x) + px;
    this.div.style.top=(((y + div_height) > winH) ? winH - div_height: y) + px;
//	this.div.style.color = "#eeeeee";
    this.div.style.visibility=ns4?"show":"visible";
}

function showTip(e,y) {
    if (!this.div.menu_visible) {
        if (!this.div.tooltip_visible) {
            this.fillTip();
        }
        var x;
        if (typeof(e) == 'number') {
            x = e;
        }
        else {
            x=e.pageX?e.pageX:e.clientX?e.clientX:0;
            y=e.pageY?e.pageY:e.clientY?e.clientY:0;
        }
        x+=2; y+=2;
				this.showDiv(x,y);
        this.div.tooltip_visible=1;
    }
}

function showMenu(e) {
    if (this.div) {
        if (!this.div.menu_visible) {
            this.fillMenu();
        }
        var x;
        var y;

        // if the menu position was given as parameter
        // to the constructor, then use that position
        // or fall back to mouse position
        if (this.popup_menu_x != -1) {
            x = this.popup_menu_x;
            y = this.popup_menu_y;
        }
        else {
            x = e.pageX ? e.pageX : e.clientX ? e.clientX : 0;
            y = e.pageY ? e.pageY : e.clientY ? e.clientY : 0;
        }
	this.showDiv(x,y);
        this.div.menu_visible=1;
    }
}

// add the event handler to the parent object
function addHandler() {

    // the tooltip is managed by the mouseover and mouseout
    // events. mousemove is captured, too

	// we totally ignore Ie on mac
	if (iemac) {
	    return;
    }

    if(this.tooltip_text) {
	this.fillTip();
	this.attached.onmouseover = function (e) {
            this.tooltip.showTip(e);
            return false;
        };
	this.attached.onmousemove = function (e) {
            this.tooltip.mousemove(e);
            return false;
        };
    }
    if (this.popup_menu) {
        this.attached.onclick = function (e) {
                   this.tooltip.showMenu(e);

                   // reset event handlers
                   if (this.tooltip_text) {
                       this.onmousemove=null;
                       this.onmouseover=null;
                       this.onclick=null;
                   }

                   // there are two mouseout events,
                   // one when the mouse enters the inner region
                   // of our div, and one when the mouse leaves the
                   // div. we need to handle both of them
                   // since the div itself got no physical region on
                   // the screen, we need to catch event for its
                   // child elements
                   this.tooltip.div.moved_in=0;
                   this.tooltip.div.onmouseout=function (e) {
                       var div = getDiv(tooltip_name);
                       if (e.target.parentNode == div) {
                           if (div.moved_in) {
                               div.menu_visible = 0;
                               div.innerHTML="";
                               div.style.visibility=ns4?"hide":"hidden";
                           }
                           else {
                               div.moved_in=1;
                           }
                           return true;
                       };
                       return true;
                   };
                   this.tooltip.div.onclick=function() {
                       this.menu_visible = 0;
                       this.innerHTML="";
                       this.style.visibility=ns4?"hide":"hidden";
                       return true;
                   }
                   return false; // do not follow existing links if a menu was defined!

        };
    }
    this.attached.onmouseout = function () {
                                   this.tooltip.delHandler();
                                   return false;
                               };
}

function delHandler() {
    if (this.div.menu_visible) {
        return true;
    }

    // clean up
    if (this.popup_menu) {
        this.attached.onmousedown = null;
    }
    this.hideMenu();
    this.hideTip();
    this.attached.onmousemove = null;
    this.attached.onmouseout = null;
    // re-register the handler for mouse over
    this.attached.onmouseover = function (e) {
                                    this.tooltip.addHandler(e);
                                    return true;
                                };
    return false;
}

function mousemove(e){
    if (this.div.tooltip_visible) {
        if(e) {
            x=e.pageX?e.pageX:e.clientX?e.clientX:0;
            y=e.pageY?e.pageY:e.clientY?e.clientY:0;
        }
        else if(event) {
            x=event.clientX;
            y=event.clientY;
        }
        else {
            x=0; y=0;
        }
        if(document.documentElement) // Workaround for scroll offset of IE
        {
            x+=document.documentElement.scrollLeft;
            y+=document.documentElement.scrollTop;
        }
        this.showTip(x,y);
    }
}

function setValue(id , val) {
   var element = document.getElementById(id);
   element.value = val;
}


// javascript to allow showing and hiding of divs using js.
// stolen unashamedly from http://www.netlobo.com/div_hiding.html

// To add this to your code, you need to do three things: 1. wrap your display in a <div id="xxx"></div>
// 2. Ensure that div#xxx is described in default.css (see the div#proteinfamilies example), and 3. add this link to your script:
// <a href="javascript:toggleLayer('xxx');" title="Show this area">Show Something</a>
// The one key is that the xxx's need to be the same.

function toggleLayer(whichLayer)
{
	if (document.getElementById)
	{
		// this is the way the standards work
		var style2 = document.getElementById(whichLayer).style;
		style2.display = style2.display? "":"block";
	}
	else if (document.all)
	{
		// this is the way old msie versions work
		var style2 = document.all[whichLayer].style;
		style2.display = style2.display? "":"block";
	}
	else if (document.layers)
	{
		// this is the way nn4 works
		var style2 = document.layers[whichLayer].style;
		style2.display = style2.display? "":"block";
	}
}

// this flips the style from "none" to "block"

function toggleOffLayer(whichLayer)
{
	var style2;
	if (document.getElementById)
	{
		// this is the way the standards work
		style2 = document.getElementById(whichLayer).style;
	}
	else if (document.all)
	{
		// this is the way old msie versions work
		style2 = document.all[whichLayer].style;
	}
	else if (document.layers)
	{
		// this is the way nn4 works
		style2 = document.layers[whichLayer].style;
	}
		style2.display = (style2.display == "none" ? "block" : "none");

}
