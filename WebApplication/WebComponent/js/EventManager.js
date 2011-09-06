var EM = new EventManager();

function EventManager () {
    this.events = [];
    this.addEvent = function ( eventString, action ) {
        if( !(eventString in this.events)) {
            this.events[eventString] = [];
        }
        this.events[eventString].push(action);
    };
    this.raiseEvent = function ( eventString, data ) {
        var currEvents = this.events[eventString];
        if (!currEvents) return;
        var formId = document.getElementById(data);
        if (formId) {
            data = this.formDataToString(formId);
        }
        for(var i=0; i<currEvents.length; i++) {
            if(typeof(currEvents[i]) == 'function') {
                currEvents[i](eventString, data);
            } else if(typeof(currEvents[i]) == 'object') {
                var cgiStr, componentStr;
                if(currEvents[i].length == 4) {
                    cgiStr = currEvents[i][2];
                    componentStr = currEvents[i][2];
                } else if(currEvents[i].length == 3) {
                    var tmp = currEvents[i][2].split('=');
                    if (tmp.length > 1) {
                        cgiStr = currEvents[i][2];
                    } else {
                        componentStr = currEvents[i][2];
                    }
                }
                var dataObj = this.stringToObject(data);
                var cgiObj = this.stringToObject(cgiStr);
                for(item in dataObj) {
                    cgiObj[item] = dataObj[item];
                }
                cgiStr = this.objectToString(cgiObj);
                if(cgiStr && componentStr) {
                    execute_ajax(currEvents[i][0],currEvents[i][1],cgiStr,'Loading..', 0, 'posthook', componentStr);
                } else if(cgiStr) {
                    execute_ajax(currEvents[i][0],currEvents[i][1],cgiStr);
                } else if(componentStr) {
                    execute_ajax(currEvents[i][0],currEvents[i][1],'','Loading..',0,'posthook',componentStr);
                } else {
                    execute_ajax(currEvents[i][0],currEvents[i][1],'');
                }
            } else {
                console.log("There was an error: typeof(action) is " + typeof(currEvents[i]));
            }
        }
    };
    
    this.stringToObject = function (str) {
        var obj = new Array();
        if(str) {
            var parts = str.split("&");
            for(var i=0; i<parts.length; i++) {
                var nameValue = parts[i].split("=");
                obj[nameValue[0]] = nameValue[1];
            }
        }
        return obj;
    };
    
    this.objectToString = function (obj) {
        var str = '';
        if(obj) {
            for(key in obj){
                if (str.length != 0) {
                    str = str + '&';
                }
                str = str + key + '=' + obj[key];
            }       
        }
        return str;
    };
    
    this.formDataToString = function (form) {
        var form_elements = form.elements;
        var parameters = '';
        for (i=0; i<form_elements.length; i++) {
            if (! form_elements[i].name)
                continue;
            if ((form_elements[i].type =='radio') ||
                (form_elements[i].type == 'checkbox')) {
                if (form_elements[i].checked) {
                    parameters = parameters + form_elements[i].name + "=" +
                    encodeURIComponent(form_elements[i].value) + "&";
                }
            } else if (form_elements[i].type =='select-multiple') {
                for (h=0; h<form_elements[i].options.length; h++) {
                    if (form_elements[i].options[h].selected) {
                        parameters = parameters + form_elements[i].name + '=' +
                        encodeURIComponent(form_elements[i].options[h].value) + "&";
                    }
                }
            } else {
                parameters = parameters + form_elements[i].name + "=" +
                encodeURIComponent(form_elements[i].value) + "&";
            }
        }
        return parameters;
    };

}
