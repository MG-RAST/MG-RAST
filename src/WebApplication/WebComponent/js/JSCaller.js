// this function takes a DOM node, loads the JSON data,
// and calls the specified js functions
function processDataFromDOM (node) {
	// data is array of objects, each object having func = function
	// and optional args = [arguments] or data = {data}
	var data = node.innerHTML;

	callJSFunctions(data);
}

// loops through call objects, calling the functions
function callJSFunctions (data) {
	var calls = JSON.parse(data);

	for (var i=0; i<calls.length; i++) {
		var call = calls[i];

		// now call function, this avoids eval, which is evil!
		if (call.data) {
			var fn = processFunctionScope(call.func);
			fn(call.data);
		} else if (call.args) {
			var fn = processFunctionScope(call.func);
			fn.apply(this, call.args);
		} else {
			var fn = processFunctionScope(call.func);
			fn();
		}
	}
}

// this function tries to find the correct function scope,
// for example it would take 'Console.println', find Console,
// and check if println is a function of Console.
function processFunctionScope (fn_string) {
	try {
		var fn_scope = fn_string.split(".");
		var scope = window;
		while(fn_scope.length > 1) {
			scope = scope[fn_scope.shift()];
		}
		var fn = scope[fn_scope[0]];
		if (typeof fn == 'function') {
			return fn;
		} else {
			alert('Not a function: typeof("'+fn_string+'") is '+ typeof(fn)); 
            // do something else here
		}
	} catch (e) {
		alert(e); // and maybe do something else
	}
}
