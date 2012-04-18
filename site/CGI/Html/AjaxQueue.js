AjaxQueue = new Object();
AjaxQueue.queue = new Array();
AjaxQueue.running = 0;
AjaxQueue.pointer = 0;

var topbarQueueInitialized = 0;
var topbarQueue;
var topbarNum;
var topbarImage;
var topbarExpand = 0;
var controlPanel;
var controlPanelActive = 0;

AjaxQueue.add = function (request_name, wait) {
	if (wait == null) {
		wait = 1;
	}

	var request = Ajax.getRequest(request_name);
	request.wait = wait;
	if (request.onfinish) {
		request.onfinish2 = request.onfinish;
	}
	request.onfinish = function (response) {AjaxQueue.onfinish(request, response)};

	AjaxQueue.queue.push(request_name);
}

AjaxQueue.start = function () {
	if (AjaxQueue.queue.length > 0 && AjaxQueue.running == 0) {
		AjaxQueue.running = 1;
		AjaxQueue.next();
	}
}

AjaxQueue.next = function () {
	if (AjaxQueue.pointer >= AjaxQueue.queue.length) { // finished
		AjaxQueue.running = 0;
	} else {
		var request_name = AjaxQueue.queue[AjaxQueue.pointer];
		AjaxQueue.pointer++;
		Ajax.sendRequest(request_name);
	}	
}

AjaxQueue.onfinish = function (request, response) {
	if (request.wait) {
		if (request.onfinish2) {
			if (request.type == "static") {
				determineFunctionAndCall(request.onfinish2, response);
			} else {
				determineFunctionAndCall(request.onfinish2);
			}
			request.onfinish = request.onfinish2; // reset onfinish
			delete request.onfinish2;
		}
		AjaxQueue.next();
	} else {
		AjaxQueue.next();
		if (request.onfinish2) {
			if (request.type == "static") {
				determineFunctionAndCall(request.onfinish2, response);
			} else {
				determineFunctionAndCall(request.onfinish2);
			}
			request.onfinish = request.onfinish2; // reset onfinish
			delete request.onfinish2;
		}
	}					
}

// called by AjaxQueue.pm to load ajax queue
function addJSONToAjaxQueue (jsonAjaxCalls) {
  var ajaxCalls = eval('(' + jsonAjaxCalls + ')');

  if (topbarQueueInitialized == 0) {
    addAjaxQueueToTopbar();
    topbarQueueInitialized = 1;
  }

  for (var i=0; i<ajaxCalls.length; i++) {
    var ajaxCall = ajaxCalls[i];

    // necessary to call a function with ajaxCall as parameter, google 'javascript closure' for more info
    addAjaxToQueue(ajaxCall);
  }
}

// starts the queue running (if there's something in the queue and it's not running)
function startAjaxQueue() {
  if (AjaxQueue.length > 0 && queueRunning == 0) {
    queueRunning = 1;
    topbarImage.src = './Html/loading-green.gif';
    updatePanels();
    nextInAjaxQueue();
  }
}

// send the next ajax call if the queue isn't finished
function nextInAjaxQueue() {
  if (QueuePointer >= AjaxQueue.length) { // finished
    queueRunning = 0;
    topbarImage.src = './Html/check-green.png';
  } else {
    var ajax = AjaxQueue[QueuePointer];
    ajax.status = 'loading';
    updatePanels();
    ajax.call();
    QueuePointer++;
  }
}

// add ajax object to the queue
function addAjaxToQueue (ajax) {
  if (validateAjax(ajax) == 0) return;

  ajax.id = AjaxQueue.length;
  ajax.status = 'queued';
  ajax.time = new Array();

  var post_hook = function (response) {onResponse(ajax, response)};

  if (ajax.type == 'static') {
    ajax.call = function() {execute_ajax_static(ajax.static_url, post_hook, function(httpRequest) {checkHttpRequest(httpRequest, ajax)})};
  } else {
    ajax.call = function() {execute_ajax(ajax.sub, ajax.target, ajax.source, ajax.loading_text, ajax.no_load_image, post_hook, ajax.component, ajax.additional_parameters, 0, function(httpRequest) {checkHttpRequest(httpRequest, ajax)})};
  }

  AjaxQueue.push(ajax);
  updatePanels();
}

function checkHttpRequest (httpRequest, ajax) {
  if (httpRequest.readyState == 1) {
    ajax.temptime = time();
  } else if (httpRequest.readyState == 2) {
    ajax.time.push(time() - ajax.temptime);
    ajax.temptime = time();
  } else if (httpRequest.readyState == 4) {
    ajax.time.push(time() - ajax.temptime);
    ajax.httpRequest = httpRequest;
    ajax.size = httpRequest.responseText.length;
  }
  ajax.state = httpRequest.readyState;
}

function onResponse (ajax, response) {
  ajax.status = 'processing';
  nextInAjaxQueue(); // this calls updatePanels
  ajax.temptime = time();
  if (ajax.post_hook)
    eval(ajax.post_hook + '(response)');
  onFinish(ajax);
}

function onFinish (ajax) {
  ajax.time.push(time() - ajax.temptime);
  delete ajax.temptime;
  delete ajax.state;
  ajax.status = 'finished';
  updatePanels();
}

function addAjaxQueueToTopbar () {
  var table = document.getElementById('topbar').childNodes[1];
  var newCell = table.tBodies[0].rows[0].appendChild(document.createElement('td'));

  var div = newCell.appendChild(document.createElement('div'));
  div.setAttribute('style', 'width:175px');

  var ajaxDiv = div.appendChild(document.createElement('div'));
  ajaxDiv.setAttribute('id', 'topbarAjaxQueue');
  ajaxDiv.setAttribute('style', 'width:175px;position:absolute;margin:-3px;background-color:#86D392;border:2px solid #5DA668;');

  topbarTitle = ajaxDiv.appendChild(document.createElement('div'));
  topbarTitle.setAttribute('style', 'height:16px;font-weight:bold;text-align:center;margin:3px;cursor:pointer;');
  topbarTitle.setAttribute('onclick', 'toggleQueueDiv();');
  topbarTitle.appendChild(document.createTextNode('Ajax Queue: '));

  topbarNum = topbarTitle.appendChild(document.createElement('span'));
  topbarImage = topbarTitle.appendChild(document.createElement('img'));
  topbarImage.setAttribute('style', 'width:16px;height:16px;padding-left:10px');
  topbarImage.src = './Html/pause-red.png';

  topbarQueue = ajaxDiv.appendChild(document.createElement('div'));
  topbarQueue.setAttribute('id', 'topbarQueue');
  topbarQueue.setAttribute('style', 'background-color:#D5F3C6;border-top:2px solid #5DA668;text-align:center;');
}

function toggleQueueDiv () {
  if (topbarQueue.style.display == 'none') {
    topbarQueue.style.display = '';
  } else {
    topbarQueue.style.display = 'none';
  }
}

function validateAjax(ajax) {
  if (! ajax.name) return 0;

  if (ajax.type == 'static') {
    if (! ajax.static_url) return 0;
  } else {
    if (! ajax.sub) return 0;
    if (! ajax.target) return 0;
  }

  return 1;
}

function time () {
  return (new Date()).getTime();
}

function updatePanels() {
  updateTopbarQueue();
  updateControlPanel();
}

function updateTopbarQueue() {
  var maxCalls = 4;
  var numRunning = 0;

  topbarQueue.innerHTML = '';
  var i = 0;
  if (topbarExpand == 0) {
    if (AjaxQueue.length > maxCalls) {
      i = AjaxQueue.length - maxCalls;
      var expand = document.createElement('div');
      expand.setAttribute('style', 'font-size: large; cursor: pointer;');
      expand.setAttribute('onclick', 'toggleTopbarExpand()');
      expand.innerHTML = ". . .";
      topbarQueue.appendChild(expand);
    }
  } else {
      var expand = document.createElement('div');
      expand.setAttribute('style', 'font-size: large; cursor: pointer;');
      expand.setAttribute('onclick', 'toggleTopbarExpand()');
      expand.innerHTML = "^";
      topbarQueue.appendChild(expand);
  }
  for (i; i<AjaxQueue.length; i++) {
    var ajax = AjaxQueue[i];
    var item = document.createElement('div');
    item.setAttribute('style', 'font-weight:bold;padding:3px;');
    item.innerHTML = ajax.name + ": " + ajax.status;
    topbarQueue.appendChild(item);
    if (ajax.status != 'finished') numRunning++;
  }

  var item = document.createElement('div');
  item.setAttribute('style', 'font-weight:bold;padding:3px;');
  item.innerHTML = "<a href='javascript:showControlPanel()'>Show Control Panel</a>";
  topbarQueue.appendChild(item);

  topbarNum.innerHTML = "(" + numRunning + ")";
}

function showControlPanel() {
  controlPanelActive = 1;
  customAlert('control_panel');
  updateControlPanel();
}

function hideControlPanel() {
  controlPanelActive = 0;
}

function updateControlPanel() {
  if (controlPanelActive) {
    var controlDiv = document.getElementById('controlPanel');
    controlDiv.innerHTML = '';
    var table = controlDiv.appendChild(document.createElement('table'));
    table.setAttribute('cellpadding', '10');
    table.setAttribute('style', 'text-align: center; width: 100%;');
    var header = table.appendChild(document.createElement('tr'));
    header.innerHTML = "<th>Name</th><th>Type</th><th>Status</th><th>Timing (ms)</th><th>Content Length</th>";

    for (var i=0; i<AjaxQueue.length; i++) {
      var ajax = AjaxQueue[i];

      var cells = new Array();
      cells.push(ajax.name);
      cells.push((ajax.type == 'static' ? 'static' : 'server'));
      cells.push(ajax.status);

      var timing = '<table style="width: 100%">';
      if (ajax.time[0])
        timing += "<tr title='Server Processing'><td>waiting:</td><td>" + ajax.time[0] + "</td></tr>";
      if (ajax.time[1])
        timing += "<tr title='Dowloading Content'><td>loading:</td><td>" + ajax.time[1] + "</td></tr>";
      if (ajax.time[2])
        timing += "<tr title='PostHook Functions'><td>processing:</td><td>" + ajax.time[2] + "</td></tr>";
      timing += "</table>";

      if (ajax.time.length == 0)
        timing = '---'

      cells.push(timing);

      if (ajax.size)
        cells.push(formatBytes(ajax.size));
      else
        cells.push('---');

      var row = table.appendChild(document.createElement('tr'));
      row.innerHTML = "<td>" + cells.join("</td><td>") + "</td>";
    }
  }
}

function formatBytes (num) {
  if (num < 1024) {
    return num.toPrecision(4) + " B";
  } else if (num < (1024 * 1024)) {
    return (num / 1024).toPrecision(4) + " KB";
  } else {
    return (num / (1024 * 1024)).toPrecision(4) + " MB";
  }
}

function toggleTopbarExpand() {
  if (topbarExpand == 0)
    topbarExpand = 1;
  else
    topbarExpand = 0;
  updateTopbarQueue();
}