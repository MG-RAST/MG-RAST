var request_collection = new Array();
window.onUnload = abort_requests();

// Return the path to the HTML directory.
function htmlPath() {
    var metaValue = document.getElementsByName("HTML_PATH");
    var retVal = "./Html";
    if (metaValue.length > 0) {
        retVal = metaValue[0].content;
    }
    return retVal;
}


function abort_requests () {
  for (i=0; i<request_collection.length; i++) {
    request_collection[i].abort();
  }
}

function execute_ajax (sub, target, source, loading_text, no_load_image, post_hook, component, additional_parameters, return_object) {
  var http_request;
  var agt=navigator.userAgent.toLowerCase();
  if (agt.indexOf("msie") != -1) {
    no_load_image = 1;
    try {
      http_request = new ActiveXObject("Microsoft.XMLHTTP");
    }
    catch (err) {
      alert('You must enable ActiveX in your security settings to view all features of this page.');
    }
  } else {
    http_request = new XMLHttpRequest();
    http_request.overrideMimeType('text/plain');
  }

  var source_form = document.getElementById(source);
  var parameters = "";
  if (source_form) {
    var form_elements = source_form.elements;
    for (i=0; i<form_elements.length; i++) {
      if (! form_elements[i].name) {
	continue;
      }
      if ((form_elements[i].type =='radio') || (form_elements[i].type == 'checkbox')) {
	if (form_elements[i].checked) {
	  parameters = parameters + form_elements[i].name + "=" + encodeURIComponent(form_elements[i].value) + "&";
	}
      } else if (form_elements[i].type =='select-multiple') {
	for (h=0; h<form_elements[i].options.length; h++) {
	  if (form_elements[i].options[h].selected) {
	    parameters = parameters + form_elements[i].name + '=' + encodeURIComponent(form_elements[i].options[h].value) + "&";
	  }
	}
      } else {
	parameters = parameters + form_elements[i].name + "=" + encodeURIComponent(form_elements[i].value) + "&";
      }
    }
  } else {
    parameters = source + "&";
  }
  parameters = parameters + "sub=" + sub + "&";
  if (component) {
    parameters = parameters + "component=" + component + "&";
  }
  if (additional_parameters) {
    parameters = parameters + additional_parameters + "&";
  }
  parameters = parameters + document.getElementById('ajax_params').value;

  if (! no_load_image) {
    if (! loading_text) {
      loading_text = "Loading...";
    }

    var content = document.getElementById(target);
    var img_div = document.createElement('div');
    var img = document.createElement('img');
    img.src = htmlPath() + '/ajax-loader.gif';
    img.style.width = '20px';
    img.style.height = '20px';
    img_div.appendChild(img);
    img_div.appendChild(document.createTextNode(loading_text));
    img_div.style.position = 'absolute';
    img_div.style.top = content.pageY;
    img_div.style.left = content.pageX;
    img_div.style.background = '#fff';
    img_div.style.padding = '1px';
    content.insertBefore(img_div, document.getElementById(target).firstChild);
  }

  var script_url = document.getElementById('ajax_url').value;
  http_request.onreadystatechange = function() { ajax_result(http_request, target, post_hook); };

  http_request.open('POST', script_url, true);
  http_request.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
  http_request.send(parameters);

  // save a reference to the request
  request_collection[request_collection.length] = http_request;
  if (return_object == 1) {
    return http_request;
  }
}

function ajax_result (http_request, target, post_hook) {
  if (http_request.readyState == 4) {
    document.getElementById(target).innerHTML = http_request.responseText;
    if (typeof(post_hook) == 'function') {
      post_hook();
    }
  }
}
