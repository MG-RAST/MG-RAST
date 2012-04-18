var Console = new Object();
Console.initialized = 0;

Console.initializeDragresize = function () {
	var dragresize = new DragResize('dragresize',
	 { minWidth: 100, minHeight: 100, minLeft: 20, minTop: 20 });

	// determine which elements are the draggable elements
	dragresize.isElement = function(elm)
	{
		if (elm.className && elm.className.indexOf('drsElement') > -1) return true;
	};
	dragresize.isHandle = function(elm)
	{
		if (elm.className && elm.className.indexOf('drsMoveHandle') > -1) return true;
	};

	// apply dragsize to document to make nodes draggable
	dragresize.apply(document);
}

Console.initializeConsole = function () {
	if (Console.initialized) {
		return;
	}
	Console.initializeDragresize();
	Console.initialized = 1;

	// set up the console div
	var wrapperDiv = document.body.appendChild(document.createElement('div'));
	wrapperDiv.id = "consoleWrapper";
	wrapperDiv.className = 'drsElement';
	wrapperDiv.style.cssText = 'left: 200px; top: 200px; width: 500px; height: 400px; padding-bottom: 21px; display: none; z-index: 10; background-color: white;';

	Console.window = wrapperDiv;

	var moveDiv = wrapperDiv.appendChild(document.createElement('div'));
	moveDiv.className = 'drsMoveHandle';
	moveDiv.style.cssText = 'text-align: center; font-weight: bold;';
	moveDiv.appendChild(document.createTextNode('Console'));
	var close = moveDiv.appendChild(document.createElement('div'));
	close.style.cssText = 'position: absolute; top: 0px; right: 0px;';
	var img = close.appendChild(document.createElement('img'));
	img.src = './Html/fancy_closebox.png';
	img.height = 20;
	img.width = 20;
	img.onclick = Console.hide;
	img.style.cssText = 'cursor: pointer';

	var console = wrapperDiv.appendChild(document.createElement('div'));
	console.style.cssText = 'overflow: auto; white-space: nowrap; height: 100%';

	Console.console = console;
}

Console.print = function (m) {
	m = translateWhitespace(m);
	var lines = m.split("\n");
	Console.console.appendChild(document.createTextNode(lines[0]));
	for (var i=1; i<lines.length; i++) {
		Console.console.appendChild(document.createElement('br'));
		Console.console.appendChild(document.createTextNode(lines[i]));
	}
	Console.console.scrollTop = Console.console.scrollHeight;
}

Console.println = function (m) {
	m = translateWhitespace(m);
	var lines = m.split("\n");
	for (var i=0; i<lines.length; i++) {
		Console.console.appendChild(document.createTextNode(lines[i]));
		Console.console.appendChild(document.createElement('br'));
	}
	Console.console.scrollTop = Console.console.scrollHeight;
	};

Console.printHtml = function (m) {
	var span = Console.console.appendChild(document.createElement('span'));
	Console.console.appendChild(document.createElement('br'));
	span.innerHTML = m;
	Console.console.scrollTop = Console.console.scrollHeight;
};

Console.show = function () {
	Console.window.style.display = "";
	Console.console.scrollTop = Console.console.scrollHeight;
};

Console.hide = function() {
	Console.window.style.display = "none";
};

function translateWhitespace (string) {
	string = string.replace(/ /g, "\u00a0");
	string = string.replace(/\t/g, "\u00a0\u00a0\u00a0\u00a0");

	return string;
}