/*
 *  loader.js - a tool for asynchronously loading required javascript libraries
 *
 *  Usage : Defines a global object "loader" that has two functions: require() and ready()
 *  
 *      loader.require('my_js_lib.js')
 *      loader.require('my_second_lib.js', function () { // some callback routine... });
 *      loader.ready(function () { // main code goes here })
 *
 *  Scott Devoid (sdevoid@gmail.com)
 *
 */
var loader = (function () {
    var load_queue = {};
    var done_queue = [];
    var update_queue = function (src) {
        if(src) {
           delete load_queue[src];
        }
        var size = 0;
        for (key in load_queue) if (load_queue.hasOwnProperty(key)) size++;
        if(size == 0) {
            update_done();
        }
    };
    var update_done = function () {
        for(var i=0; i < done_queue.length; i++) {
            done_queue[i]();
        }
    };
    var qualifyURL = function (url) {
        var el = document.createElement("a");
        el.href = url;
        return el.href;
    }
    return {
        require : function (src, cb) {
            var tmp_src = qualifyURL(src);
            var existing = document.getElementsByTagName("script");
            for(var i=0; i<existing.length; i++) {
                var existing_src = existing[i].getAttribute("src");
                var tmp_existing_src = qualifyURL(existing_src);
                if(tmp_existing_src && tmp_existing_src == tmp_src) {
                    update_queue(); 
                    return;
                }
            }
            load_queue[src] = 0;
            var script = document.createElement("script");
            script.setAttribute("src", src);
            document.getElementsByTagName("head")[0].appendChild(script);
            if(cb) {
                cb = function () {  cb(); update_queue(src); };
            } else {
                cb = function () { update_queue(src); };
            }
            script.onreadystatechange = cb;
            script.onload = cb;
        },
        ready : function (cb) {
            done_queue.push(cb);
        }
    }
})(); 
