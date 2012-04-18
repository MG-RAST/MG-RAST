// ModelDBServer.js a simple interface into the ModelDBServer
// requires loader.js

loader.require("Html/jquery.min.js");
//loader.require("Html/FIG_Config.js");
loader.require("Html/json2.js");
var modelDb;
loader.ready(function () {
modelDb = (function() {
    var address = 'ModelDB_server.cgi'; //FIG_Config['cgi_base'] + '/ModelDBServer.cgi';
    var _init_object = function (data, type) {
        function DataObject(data, type) {
            this._db = modelDb;
            this._type = type;
            this._attr = data;
            for (key in data) if (data.hasOwnProperty(key)) {
                this.__defineGetter__(key, function(k){ return function () {return this._attr[k]};}(key));
                this.__defineSetter__(key, function (k){
                    return function (val) {
                            this._attr[k] = val;
                            _call_fn_args('set_attribute', { 'key' : k, 'value' : val,
                                'type' : this._type, 'object' : { '_id' : this._attr['_id'] }});
                            return this._attr[k];
                   };
                }(key));
            }
        }
        return new DataObject(data, type);
    };
    var _call_fn_args = function (f, args, cb) {
        var data = "function=" + f + "&encoding=json&args=" + JSON.stringify(args);
        var settings = {
            url : address,
            data : data,
            type : 'POST',
            error : function (msg) {
                console.log(msg);
            },
        };
        if(cb) {
            settings.success = function (data) {
                data = JSON.parse(data);
                if(data.success == 'true' && data.failure == 'false') {
                    cb(data.response);
                } else {
                    console.log(data.msg); 
                }
            };
        }
        $.ajax(settings);
    };
    return {
        get_object : function (type, query, cb) {
            _call_fn_args('get_object', { 'type' : type, 'query' : query || {}},
                function (data) {
                    var obj = _init_object(data, type);
                    if(cb) cb(obj);
                });
        },
        get_objects : function (type, query, cb) {
            _call_fn_args('get_objects', { 'type' : type, 'query' : query},
                function (data) {
                    var arr = [];
                    for(var i=0; i<data.length; i++) {
                        arr.push(_init_object(data[i], type));
                    }
                    if(cb) cb(arr);
                });
        },
        create_object : function (type, obj, cb) {
            _call_fn_args('create_object', { 'type' : type, 'object' : obj}, cb);
        },
    };
    })();
});
