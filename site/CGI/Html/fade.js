function fade(id, time){
  time = time * 1000;
  setTimeout("opacity('" + id + "', 100, 0, 5000)", time);
}

function opacity(id, opacStart, opacEnd, millisec) {
  //speed for each frame
  var speed = Math.round(millisec / 100);
  var timer = 0;

  //determine the direction for the blending, if start and end are the same nothing happens
  if(opacStart > opacEnd) {
    for(i = opacStart; i >= opacEnd; i--) {
      setTimeout("changeOpac(" + i + ",'" + id + "')",(timer * speed));
      timer++;
    }
    
  } else if(opacStart < opacEnd) {
    for(i = opacStart; i <= opacEnd; i++)
      {
	setTimeout("changeOpac(" + i + ",'" + id + "')",(timer * speed));
	timer++;
      }	
  }
}

//change the opacity for different browsers
function changeOpac(opacity, id) {
  var object = document.getElementById(id).style; 
  if(opacity == 0){
    object.display = "none";
  }
  object.opacity = (opacity / 100);
  object.MozOpacity = (opacity / 100);
  object.KhtmlOpacity = (opacity / 100);
  object.filter = "alpha(opacity=" + opacity + ")";
}
