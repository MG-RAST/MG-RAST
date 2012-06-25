
function create_google_map (map_id, data_id) {
    var myOptions = {
	zoom: 2,
	center: new google.maps.LatLng(26.115986, 8.437500),
	disableDefaultUI: true,
	mapTypeId: google.maps.MapTypeId.SATELLITE,
	scrollwheel: false,
	draggable: true,
	keyboardShortcuts: false,
	navigationControl: true,
	scaleControl: true,
	disableDoubleClickZoom: false
    };
    
    var gmap = new google.maps.Map(document.getElementById(map_id), myOptions);
    var locs = document.getElementById(data_id).innerHTML.split('^');
    
    for (var i = 0; i < locs.length; i++) {
	var data = locs[i].split('~');
	var mark = new google.maps.Marker({position: new google.maps.LatLng(data[0], data[1]), map: gmap, title: data[2]});
	mark.infowin = new google.maps.InfoWindow({content: data[3]});
	google.maps.event.addListener( mark, 'click', (function(mark){ return function(){ mark.infowin.open(gmap, mark); }; })(mark) );
    }
}
