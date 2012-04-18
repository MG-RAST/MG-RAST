<!--//
function createPlacemark(job, name, lat, lon) {
  var placemark = gex.dom.addPointPlacemark([lat, lon], { name: name, style: { icon: { stockIcon: "paddle/red-circle" }}});

  google.earth.addEventListener(placemark, 'click', function(event) {
    event.preventDefault();

    var balloon = ge.createHtmlStringBalloon('');
    balloon.setFeature(event.getTarget());
    balloon.setMinWidth(200);
    balloon.setMinHeight(200);

//     html = '<div id="popup_window"></div><img src="./Html/clear.gif" onload="execute_ajax(\'display_content\', \'popup_window\', \'metagenome_id=METAGENOMEID\');"/>';
//     re = /METAGENOMEID/;
//     html = html.replace(re, job);

//     balloon.setContentString(html);
    balloon.setContentString('<a href="?page=MetagenomeOverview&metagenome='+job+'">'+name+'</a>');

    ge.setBalloon(balloon);
  });
}


function createView(lat, lon){
  // Create a new LookAt
  var lookAt = ge.createLookAt('');

  // Set the position values
  lookAt.setLatitude(lat);
  lookAt.setLongitude(lon);
  lookAt.setRange(100000.0); //default is 0.0
  
  // Update the view in Google Earth
  ge.getView().setAbstractView(lookAt);
}

function hide_show_ge(id, height){
  var map = document.getElementById('map3d');

  if(map.style.height == '0px'){
    map.style.height = height+'px';
  } else {
    map.style.height = '0px';
  }
}

//-->


var ge = null;
var gex = null;

google.load("earth", "1");

google.setOnLoadCallback(function() {
  google.earth.createInstance('map3d', function(pluginInstance) {
    ge = pluginInstance;
    ge.getWindow().setVisibility(true);
    ge.getNavigationControl().setVisibility(ge.VISIBILITY_AUTO);

    gex = new GEarthExtensions(pluginInstance);
    gex.util.lookAt([33, -117], { range: 25000000 });

   for (i in args)
     createPlacemark(args[i][0], args[i][1], args[i][2], args[i][3]);
  }, function() {});
});

