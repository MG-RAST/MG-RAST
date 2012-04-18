/*
	This is the JavaScript file for the AJAX Suggest Tutorial

	You may use this code in your own projects as long as this 
	copyright is left	in place.  All code is provided AS-IS.
	This code is distributed in the hope that it will be useful,
 	but WITHOUT ANY WARRANTY; without even the implied warranty of
 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
	
	For the rest of the code visit http://www.DynamicAJAX.com
	
	Copyright 2006 Ryan Smith / 345 Technical / 345 Group.	

*/
//Gets the browser specific XmlHttpRequest Object
function getXmlHttpRequestObject() {
  if (window.XMLHttpRequest) {
    return new XMLHttpRequest();
  } else if(window.ActiveXObject) {
    return new ActiveXObject("Microsoft.XMLHTTP");
  }
}

//Our XmlHttpRequest object to get the auto suggest
var searchReq = getXmlHttpRequestObject();

//Called from keyup on the search textbox.
//Starts the AJAX request.
function searchSuggest() {
  if (searchReq && (searchReq.readyState == 4 || searchReq.readyState == 0)) {
    var str = escape(document.getElementById('txtSearch').value);
    
    if (str=="") {
      hideSuggest();
    }
    else {
      searchReq.open("GET", 'suggest.cgi?search=' + str, true);
      searchReq.onreadystatechange = handleSearchSuggest; 
      searchReq.send(null);
    }
  }	
}

function hideSuggest() {
  document.getElementById('search_suggest').style.visibility = "hidden";
}

//Called when the AJAX response is returned.
function handleSearchSuggest() {
  if (searchReq.readyState == 4) {
    var ss = document.getElementById('search_suggest');
    document.getElementById('search_suggest').style.visibility = "visible";
    ss.innerHTML = '';
    var str = searchReq.responseText.split("\n");
    if (str.length > 1) {
      var entry = str[0].split("\t");
      ss.innerHTML += '<div class="suggest_link">hits for "' + entry[0] + '"</div>';	
      var searchString = entry[0];
      
      for(i=1; i < str.length - 1; i++) {
	var entry = str[i].split("\t");
	//Build our element string.  This is cleaner using the DOM, but
	//IE doesn't support dynamically added attributes.
	var suggest = '<div class="suggestion" onclick="javascript:setSearch(' + entry[0] + ');">' + entry[0] + '</div>';
	ss.innerHTML += suggest;
      }
    }
  }
}

//Click function
function setSearch(value) {
  document.getElementById('txtSearch').value = value;
  document.getElementById('search_suggest').innerHTML = '';
}
