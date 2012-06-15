
function draw_pipeline_image(l1lables, l2lables, l1link, l2link, display_id) {
    var width   = 700;
    var height  = 215;
    var border  = 35; 
    var color   = "hsb(" + [.6, .5, 1] + ")";
    var canvas  = Raphael(display_id, width, height);	
    var centerx = width/2;
    var centery = height/2+height/8;
    
    var l1points = [];
    var l2points = [];
    
    var l1y = centery - height/4;
    var l2y = centery + height/4;
    var pointspacing = (width - (2*border)) / (l1lables.length-1);
    
    for (var i=0;i<l1lables.length;i++){
	var p = canvas.circle((border+(i*pointspacing)),l1y,7).attr({'stroke-width': 3, fill: 'white'});
	var t = canvas.text((border+(i*pointspacing)),l1y,l1lables[i]).attr({'font-weight':'bold'})
	var tw = t.getBBox().width * (5/6);
	t.translate(tw/2 + 9, -(tw/3) - 9).rotate(-35);
	l1points.push([p,t]);
    }	
    var f = l1points[0][0].attr();
    var l = l1points[l1points.length-1][0].attr();
    canvas.path("M"+f.cx+" "+f.cy+"L"+l.cx+" "+l.cy).attr({stroke: color, 'stroke-width': 5}).toBack();
    
    var offset = 2 * pointspacing;
    pointspacing = ((l1lables.length - 5) * pointspacing)/(l2lables.length-1);
    for (var i=0;i<l2lables.length;i++){
	var p = canvas.circle((offset+border+(i*pointspacing)),l2y,7).attr({'stroke-width': 3, fill: 'white'});
	var t = canvas.text((offset+border+(i*pointspacing)),l2y,l2lables[i]).attr({'font-weight':'bold'}); 
	var tw = t.getBBox().width * (5/6);
	t.translate(tw/2 + 9, -(tw/3) - 9).rotate(-35);
	l2points.push([p,t]);				
    }
    var l1_f = l1points[1][0].attr();
    var l2_f = l2points[0][0].attr();
    var l2_l = l2points[l2points.length-1][0].attr();
    var l1_l = l1points[l1points.length-2][0].attr();		
    canvas.path("M"+l1_f.cx+" "+l1_f.cy+"L"+l2_f.cx+" "+l2_f.cy+"L"+l2_l.cx+" "+l2_l.cy+"L"+l1_l.cx+" "+l1_l.cy).attr({stroke: color, 'stroke-width': 5, 'stroke-dasharray': '-', "stroke-linejoin": "round"}).toBack();
    
    attach_onmouse(l1points, l1link);
    attach_onmouse(l2points, l2link);
}

function attach_onmouse(points, links) {
    for (var i=0; i<points.length; i++) {
	/*points[i][0].node.onclick = function(event) {
	    var p = event.currentTarget.raphael;
	    if (p.attr("fill") == "red") {
		p.attr("fill", "white");	
	    } else {
		p.attr("fill", "red");
	    }
	}*/
	//points[i][0].node.onclick = location.href = '#'+links[i];
    }
}
