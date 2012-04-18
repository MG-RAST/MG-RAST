var tab_ajax_requests = new Array();
var tab_ajax_request_ids = new Array();
var dynamic = new Array();

function initialize_tab_view (id) {
	if (document.getElementById('tab_view_dynamic_' + id)) {
		dynamic[id] = 1;
	} else {
		dynamic[id] = 0;
	}
}

function tab_view_select (id, tabnum, ori, subtabnum) {
	var LoadedTabList = document.getElementById(id+'_tabajax_'+tabnum);
	if (LoadedTabList) {
		var TabArray = new Array();
		TabArray = LoadedTabList.value.split(/;/);
		if (TabArray[0] == "0") {
			var index = tab_ajax_request_ids.length;
			for (i=0; i< tab_ajax_request_ids.length; i++) {
				if (typeof(tab_ajax_requests[i]) != "undefined" && tab_ajax_request_ids[i] == id+'_tabajax_'+tabnum) {
					tab_ajax_requests[i].abort();
				}
			}
			tab_ajax_request_ids[index] = id+'_tabajax_'+tabnum;
			tab_ajax_requests[index] = execute_ajax(TabArray[1],TabArray[2],TabArray[3],"Loading...",0,"post_hook",TabArray[4],"",1);
			TabArray[0] = "1";
			LoadedTabList.value = TabArray.join(";");
		}
	}
	
	if (ori) {
		for (i=0; i<1000; i++) {
			var tab = document.getElementById(id+'_tab_'+i);
			if (tab) {
				for (h=0; h<1000; h++) {
					var subtab = document.getElementById(id+'_subtab_'+i+'_'+h);
					if (subtab) {
						subtab.className = 'tab_view_title_sub_hidden';
					} else {
						break;
					}
				}
				tab.className = 'tab_view_title_vertical';
			} else {
				break;
			}
		}
		cn = 'tab_view_title_vertical_selected'
		document.getElementById(id + '_tab_' + tabnum).className = cn;
		if (! subtabnum) {
			subtabnum = 0;
		}
		
		for (i=0; i<1000; i++) {
			var subtab = document.getElementById(id + '_subtab_' + tabnum + '_' + i);
			if (subtab) {
				if (subtabnum == i) {
					subtab.className = 'tab_view_title_sub_selected';
				} else {
				subtab.className = 'tab_view_title_sub';
				}
			} else {
				break;
			}
		}

		for (i=0; i<1000; i++) {
			var content = document.getElementById(id+'_content_'+i);
			if (content) {
				content.className = 'tab_view_content';
			} else if (document.getElementById(id+'_content_'+i+'_0')) {
				for (h=0; h<1000; h++) {
					var subcontent = document.getElementById(id+'_content_'+i+'_'+h);
					if (subcontent) {
						subcontent.className = 'tab_view_content';
					} else {
						break;
					}
				}
			} else {
				break;
			}
		}

		cn = 'tab_view_content_vertical_selected';
		var subid = "";
		if (! subtabnum) {
			subtabnum = 0;
		}
		if (ori == 'sub') {
			subid = '_' + subtabnum;
		}
		var active = document.getElementById(id + '_content_' + tabnum + subid);
		if (active) {
			document.getElementById(id + '_content_' + tabnum + subid).className = cn;
		} else {
			document.getElementById(id + '_content_' + tabnum + '_0').className = cn;
		}
	} else {
		// horizontal orientation
		tabTitles = document.getElementsByName(id+'_tabs');
		for (i=0; i<tabTitles.length; i++) {
			tabTitles[i].className = 'tab_view_title';
		}
		
		// select the correct tab
		if (document.getElementById(id+'_tab_'+tabnum)) {
			document.getElementById(id+'_tab_'+tabnum).className = 'tab_view_title_selected';
		}
		
		tabContents = document.getElementsByName(id+'_contents');
		for (i=0; i<tabContents.length; i++) {
			tabContents[i].className = 'tab_view_content';
		}
		
		if (document.getElementById(id+'_content_'+tabnum)) {
			document.getElementById(id+'_content_'+tabnum).className = 'tab_view_content_selected';
		}
	}
}

/*
	Parameters:
		tabId - unique id which distinguishes the newly added tab.
			Used in case the tab is opened a second time, this will just select the tab
		tabName - the name which shows up on the tab
		tabViewId - the TabView id from the WebComponent
		subToRun - the subroutine to run within the current page.
			The return value from this subroutine will be displayed in the tab content
		additionalParams - parameters that can be sent to the subroutine within the
			cgi->params values, send as URL encoded parameters (name=value&name=value)
*/
function addTab(tabId, tabName, tabViewName, subToRun, sourceOrParams, forceReload, noDrag, onclose, post_hook) {

	if (dynamic[tabViewId] == 0) {
		return;
	}

	// get the component id from the given tabViewId
	var tabViewId = document.getElementById(tabViewName).value;
	
	var table = document.getElementById('tab_view_table_'+tabViewId);
	var tabRow = table.tBodies[0].rows[0];
	var contentTd = table.tBodies[0].rows[1].cells[0];
	
	if (tabRow.cells.length == 1) {
		table.style.display = '';
	}

	// check to see how many static tabs there are
	var numTabSpan = document.getElementById('num_'+tabViewId+'_tabs');
	if (numTabSpan == null) {
		var numTabs = tabRow.cells.length - 1;
		var numTabSpan = document.createElement('span');
		numTabSpan.setAttribute('id', 'num_'+tabViewId+'_tabs');
		numTabSpan.setAttribute('numTabs', numTabs);
		document.body.appendChild(numTabSpan);
	}

	for (var i=0; i<(tabRow.cells.length-1); i++) {
		if (tabId == tabRow.cells[i].getAttribute('tabId')) {
			if (forceReload == 1) {
				execute_ajax(subToRun, tabViewId + '_content_' + tabRow.cells[i].getAttribute('id').split("_")[2], sourceOrParams, "Loading...", 0, post_hook, "");
				return;
			}
			tab_view_select(tabViewId, tabRow.cells[i].getAttribute('id').split("_")[2]);
			return;
		}
	}
	
	var tabNum = findNewTabId(tabRow);

	var onMouseDown;
	if (noDrag == 1) {
		onMouseDown = 'tab_view_select("' + tabViewId + '", "' + tabNum + '");';
	} else {
		onMouseDown = 'tab_view_select("' + tabViewId + '", "' + tabNum + '"); dragTab(event, this, "'+tabViewId+'");';
	}

	var newTd = document.createElement('td');
	newTd.setAttribute('id', tabViewId + '_tab_' + tabNum);
	newTd.setAttribute('onmousedown', onMouseDown);
	newTd.setAttribute('class', 'tab_view_title');
	newTd.setAttribute('name', tabViewId + '_tabs');
	newTd.setAttribute('tabId', tabId);
	newTd.setAttribute('title', tabName);
	
	var closeTabString = "closeTab(event, '" + tabViewId + "', '" + tabNum + "');";
	if (onclose) {
		closeTabString += " " + onclose + "();";
	}
	
	var newImg = document.createElement('img');
	newImg.setAttribute('src', './Html/close.png');
	newImg.setAttribute('onmousedown', 'cancelEvent(event)');
	newImg.setAttribute('onclick', closeTabString);

	var newName;	
	if (tabName.length > 20) {
		newName = tabName.substring(0, 19) + "... ";
	} else {
		newName = tabName + " ";
	}
	newTd.appendChild(document.createTextNode(newName));
	newTd.appendChild(newImg);

	var numTabs = tabRow.cells.length;
	tabRow.insertBefore(newTd, tabRow.cells[numTabs-1]);

	contentTd.setAttribute('colspan', numTabs+1);

	var newDiv = document.createElement('div');
	newDiv.setAttribute('id', tabViewId + '_content_' + tabNum);
	newDiv.setAttribute('class', 'tab_view_content');
	newDiv.setAttribute('name', tabViewId + '_contents');
	newDiv.setAttribute('style', 'heigth: 100%; width: 100%');

	contentTd.appendChild(newDiv);

	execute_ajax(subToRun, tabViewId + '_content_' + tabNum, sourceOrParams, "Loading...", 0, post_hook, "");
	tab_view_select(tabViewId, tabNum);
}

function findNewTabId(tabRow) {
	var maxId = 0;
	for (i=0; i<tabRow.cells.length; i++) {
		var tabId = parseInt(tabRow.cells[i].id.split("_")[2]);
		if (tabId > maxId) {
			maxId = tabId;
		}
	}
	return maxId + 1;
}

function cancelEvent(event) {
	event.stopPropagation();
}

function closeTab(event, tabViewId, tabNum) {
	var table = document.getElementById('tab_view_table_'+tabViewId);
	var tabRow = table.tBodies[0].rows[0];
	var contentTd = table.tBodies[0].rows[1].cells[0];
	
	var tdToRemove = document.getElementById(tabViewId + '_tab_' + tabNum);
	tabRow.removeChild(tdToRemove);
	
	var divToRemove = document.getElementById(tabViewId + '_content_' + tabNum);
	contentTd.removeChild(divToRemove);
	contentTd.setAttribute('colspan', tabRow.cells.length);
	
	if (tabRow.cells.length == 1) {
		table.style.display = 'none';
	}
	
	// stop it from trying to select the now deleted tab
	event.stopPropagation();
	
	var firstTab = tabRow.cells[0].id.split("_")[2];
	tab_view_select(tabViewId, firstTab);
}

function dragTab(event, tabToDrag, tabViewId) {
	var tabPos = getTabPos(tabToDrag.parentNode);
	var tabId = tabToDrag.cellIndex;
	var tabRow = tabToDrag.parentNode;

	var newDiv = document.createElement('div');
	newDiv.setAttribute('style', 'cursor: move; width: 50px; height: 50px; position: absolute; top: 0px; left: 0px;');
	document.body.appendChild(newDiv);

	document.addEventListener("mouseup", upHandler, true);
	document.addEventListener("mousemove", moveHandler, true);
	event.stopPropagation();
	event.preventDefault();

	function upHandler(event) {
		document.body.removeChild(newDiv);
	 	document.removeEventListener("mouseup", upHandler, true);
	 	document.removeEventListener("mousemove", moveHandler, true);
	 	event.stopPropagation();
	}

	function moveHandler(event) {
		// check to see if we should scroll
/*		var offset = 10;
		if (window.pageXOffset > 0 && event.clientX <= offset) {
			console.log("Should scroll left");
			window.scrollBy(-10, 0);
		} else if (window.innerWidth && event.clientX >= (window.innerWidth - offset)) {
			console.log("Should scroll right");
			window.scrollBy(10, 0);
		}*/


		newDiv.setAttribute('style', 'cursor: move; width: 50px; height: 50px; position: absolute; top: '+(event.clientY+window.pageYOffset-25)+'px; left: '+(event.clientX+window.pageXOffset-25)+'px;');

	 	var xPos = event.clientX + window.pageXOffset;
		var numTabSpan = document.getElementById('num_'+tabViewId+'_tabs');
		var numStaticTabs = numTabSpan.getAttribute('numTabs');

		var moved = 0;
		if (tabId > numStaticTabs) {
			for (var i=tabId-1; i>=numStaticTabs; i--) {
				if (xPos < tabPos[i]) {
					moveTabLeft(tabId, tabRow);
					tabId--;
					moved = 1;
				} else {
					break;
				}
			}
		}
		if (tabId < (tabRow.cells.length-2) && (moved == 0)) {
			for (var i=tabId+1; i<=tabRow.cells.length-2; i++) {
				if (xPos > tabPos[tabId+1]) {
					moveTabRight(tabId, tabRow);
					tabId++;
					moved = 1;
				} else {
					break;
				}
			}
		}
		if (moved == 1) {
			tabPos = getTabPos(tabToDrag.parentNode);
		}

		event.stopPropagation();
	}
}

/* These work */
function getTabPos(tabRow) {
	var tabPos = new Array();
	for (var i=0; i<tabRow.cells.length; i++) {
		var pos = findPos(tabRow.cells[i]);
		tabPos.push(pos[0]);
	}
	for (var i=0; i<tabPos.length-1; i++) {
		tabPos[i] += (tabPos[i+1]-tabPos[i])/2
	}
	return tabPos;
}

function findPos(obj) {
	var curleft = curtop = 0;
	if (obj.offsetParent) {
		do {
			curleft += obj.offsetLeft;
			curtop += obj.offsetTop;
		} while (obj = obj.offsetParent);
		return [curleft,curtop];
	}
}

function moveTabLeft(tabId, tabRow) {
	tabRow.insertBefore(tabRow.cells[tabId], tabRow.cells[tabId-1]);
}

function moveTabRight(tabId, tabRow) {
	tabRow.insertBefore(tabRow.cells[tabId+1], tabRow.cells[tabId]);
}
