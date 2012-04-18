/* --- A custom lightbox script to use within the WebApplication framework --- */

function _get_window_size(){
    // Copied from http://andylangton.co.uk 
    var viewportwidth;
    var viewportheight;

    // the more standards compliant browsers (mozilla/netscape/opera/IE7) use window.innerWidth and window.innerHeight

    if (typeof window.innerWidth != 'undefined')
    {
        viewportwidth = window.innerWidth,
                      viewportheight = window.innerHeight
    }

    // IE6 in standards compliant mode (i.e. with a valid doctype as the first line in the document)

    else if (typeof document.documentElement != 'undefined'
            && typeof document.documentElement.clientWidth !=
            'undefined' && document.documentElement.clientWidth != 0)
    {
        viewportwidth = document.documentElement.clientWidth,
        viewportheight = document.documentElement.clientHeight
    }

    // older versions of IE

    else
    {
        viewportwidth = document.getElementsByTagName('body')[0].clientWidth,
        viewportheight = document.getElementsByTagName('body')[0].clientHeight
    }
    
    return Array(viewportwidth, viewportheight);
}

function popUp ( div_id )
{

    // Find the height of the page.
    if (window.innerHeight && window.scrollMaxY) {// Firefox
        _doc_height = window.innerHeight + window.scrollMaxY;
        _doc_width = window.innerHeight + window.scrollMaxX;
    } else if (document.body.scrollHeight > document.body.offsetHeight){ // all but Explorer Mac
        _doc_height = document.body.scrollHeight;
        _doc_width = document.body.scrollWidth;
    } else { // works in Explorer 6 Strict, Mozilla (not FF) and Safari
        _doc_height = document.body.offsetHeight;
        _doc_width = document.body.offsetWidth;
    }

    var size = _get_window_size();
    _doc_width = size[0];
    _doc_height = size[1];

    // Default values
    box_height =  '500px';
    box_width =  '21%';
    box_top = 120;
    box_left = _doc_width * 3/4;


//    if( document.getElementById( 'pop_up_close_layer' ) ){
//        document.body.removeChild( document.getElementById( 'pop_up_close_layer' ) );
//    }
//    //Cover the page with a div that closes the box onclick
//    var close_layer = document.createElement('div');
//    close_layer.id = 'pop_up_close_layer';
//    
//    // Style the box
//    close_layer.style.zIndex = 2;
//    close_layer.style.position = 'absolute';
//    close_layer.style.top = close_layer.style.left = 0;
//    close_layer.style.height = _doc_height;
//    close_layer.style.width = '100%';
//    close_layer.style.backgroundColor = 'black';
//
//    //make it clear
//    close_layer.style.opacity = '0';
//    //make it clear in IE
//    close_layer.style.filter = 'alpha(opacity=0)';
//
//    // close when clicked on
//    close_layer.onclick = function()
//    {
//                    document.body.removeChild( document.getElementById( 'pop_up_box' ) );
//                    document.body.removeChild( document.getElementById( 'pop_up_close_layer' ) );
//    }
//    //append it
//    document.body.appendChild( close_layer );
   
    if( document.getElementById( 'pop_up_box' ) ){
        document.body.removeChild( document.getElementById( 'pop_up_box' ) );
    }
    // Overlay the box on the page
    var box = document.createElement('div');
    box.id = 'pop_up_box';
    box.style.zIndex = 3;
    box.style.position = 'absolute';
    box.style.height = 'auto';
    box.style.maxHeight = '500px';
    box.style.width = box_width;
    box.style.left = box_left; 
    box.style.top = box_top;
    // style it
    box.style.position = 'fixed';
    box.style.paddingLeft = '15px';
    box.style.backgroundColor = 'white';
    box.style.overflow = 'auto';
    box.className = 'idBox';

    var inside = document.createElement('div');
    inside.style.padding = '15px';
    inside.style.paddingBottom = '20px';
    inside.innerHTML = document.getElementById( div_id ).innerHTML; 
    box.appendChild(inside);

    document.body.appendChild( box );
    
    
    // Add a close-box on the top corner
    if( document.getElementById( 'pop_up_closer' ) ){
        document.body.removeChild( document.getElementById( 'pop_up_closer' ) );
    }
    var closer = document.createElement( 'img' );
    closer.id = 'pop_up_closer';
    closer.style.left = box_left-10;
    closer.style.top = box_top-10;
    closer.style.zIndex = 4;
    closer.style.position = 'fixed';
    closer.style.cursor = 'pointer';
    closer.src = 'http://bioseed.mcs.anl.gov/~blinsay/FIG/Html/fancy_closebox.png';
    closer.onclick = function() {
                    document.body.removeChild( document.getElementById( 'pop_up_box' ) );
                    document.body.removeChild( document.getElementById( 'pop_up_closer' ) );
    }

    document.body.appendChild( closer );
}

