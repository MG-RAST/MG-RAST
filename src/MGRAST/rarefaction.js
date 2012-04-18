(function () {
var tokenRegex = /\{([^\}]+)\}/g,
    objNotationRegex = /(?:(?:^|\.)(.+?)(?=\[|\.|$|\()|\[('|")(.+?)\2\])(\(\))?/g, //' matches .xxxxx or ["xxxxx"] to run over object properties
    replacer = function (all, key, obj) {
        var res = obj;
        key.replace(objNotationRegex, function (all, name, quote, quotedName, isFunc) {
            name = name || quotedName;
            if (res) {
                if (name in res) {
                    res = res[name];
                }
                typeof res == "function" && isFunc && (res = res());
            }
        });
        res = (res == null || res == obj ? all : res) + "";
        return res;
    },
    fill = function (str, obj) {
        return String(str).replace(tokenRegex, function (all, key) {
            return replacer(all, key, obj);
        });
    };
    Raphael.fn.popup = function (X, Y, set, pos, ret) {
        pos = String(pos || "top-middle").split("-");
        pos[1] = pos[1] || "middle";
        var r = 5,
            bb = set.getBBox(),
            w = Math.round(bb.width),
            h = Math.round(bb.height),
            x = Math.round(bb.x) - r,
            y = Math.round(bb.y) - r,
            gap = Math.min(h / 2, w / 2, 10),
            shapes = {
                top: "M{x},{y}h{w4},{w4},{w4},{w4}a{r},{r},0,0,1,{r},{r}v{h4},{h4},{h4},{h4}a{r},{r},0,0,1,-{r},{r}l-{right},0-{gap},{gap}-{gap}-{gap}-{left},0a{r},{r},0,0,1-{r}-{r}v-{h4}-{h4}-{h4}-{h4}a{r},{r},0,0,1,{r}-{r}z",
                bottom: "M{x},{y}l{left},0,{gap}-{gap},{gap},{gap},{right},0a{r},{r},0,0,1,{r},{r}v{h4},{h4},{h4},{h4}a{r},{r},0,0,1,-{r},{r}h-{w4}-{w4}-{w4}-{w4}a{r},{r},0,0,1-{r}-{r}v-{h4}-{h4}-{h4}-{h4}a{r},{r},0,0,1,{r}-{r}z",
                right: "M{x},{y}h{w4},{w4},{w4},{w4}a{r},{r},0,0,1,{r},{r}v{h4},{h4},{h4},{h4}a{r},{r},0,0,1,-{r},{r}h-{w4}-{w4}-{w4}-{w4}a{r},{r},0,0,1-{r}-{r}l0-{bottom}-{gap}-{gap},{gap}-{gap},0-{top}a{r},{r},0,0,1,{r}-{r}z",
                left: "M{x},{y}h{w4},{w4},{w4},{w4}a{r},{r},0,0,1,{r},{r}l0,{top},{gap},{gap}-{gap},{gap},0,{bottom}a{r},{r},0,0,1,-{r},{r}h-{w4}-{w4}-{w4}-{w4}a{r},{r},0,0,1-{r}-{r}v-{h4}-{h4}-{h4}-{h4}a{r},{r},0,0,1,{r}-{r}z"
            },
            offset = {
                hx0: X - (x + r + w - gap * 2),
                hx1: X - (x + r + w / 2 - gap),
                hx2: X - (x + r + gap),
                vhy: Y - (y + r + h + r + gap),
                "^hy": Y - (y - gap)
                
            },
            mask = [{
                x: x + r,
                y: y,
                w: w,
                w4: w / 4,
                h4: h / 4,
                right: 0,
                left: w - gap * 2,
                bottom: 0,
                top: h - gap * 2,
                r: r,
                h: h,
                gap: gap
            }, {
                x: x + r,
                y: y,
                w: w,
                w4: w / 4,
                h4: h / 4,
                left: w / 2 - gap,
                right: w / 2 - gap,
                top: h / 2 - gap,
                bottom: h / 2 - gap,
                r: r,
                h: h,
                gap: gap
            }, {
                x: x + r,
                y: y,
                w: w,
                w4: w / 4,
                h4: h / 4,
                left: 0,
                right: w - gap * 2,
                top: 0,
                bottom: h - gap * 2,
                r: r,
                h: h,
                gap: gap
            }][pos[1] == "middle" ? 1 : (pos[1] == "top" || pos[1] == "left") * 2];
            var dx = 0,
                dy = 0,
                out = this.path(fill(shapes[pos[0]], mask)).insertBefore(set);
            switch (pos[0]) {
                case "top":
                    dx = X - (x + r + mask.left + gap);
                    dy = Y - (y + r + h + r + gap);
                break;
                case "bottom":
                    dx = X - (x + r + mask.left + gap);
                    dy = Y - (y - gap);
                break;
                case "left":
                    dx = X - (x + r + w + r + gap);
                    dy = Y - (y + r + mask.top + gap);
                break;
                case "right":
                    dx = X - (x - gap);
                    dy = Y - (y + r + mask.top + gap);
                break;
            }
            out.translate(dx, dy);
            if (ret) {
                ret = out.attr("path");
                out.remove();
                return {
                    path: ret,
                    dx: dx,
                    dy: dy
                };
            }
            set.translate(dx, dy);
            return out;
    };
})();

Raphael.fn.drawGrid = function (x, y, w, h, wv, hv, color) {
    color = color || "#000";
    var path = ["M", Math.round(x) + .5, Math.round(y) + .5, "L", Math.round(x + w) + .5, Math.round(y) + .5, Math.round(x + w) + .5, Math.round(y + h) + .5, Math.round(x) + .5, Math.round(y + h) + .5, Math.round(x) + .5, Math.round(y) + .5],
        rowHeight = h / hv,
        columnWidth = w / wv;
    for (var i = 1; i < hv; i++) {
        path = path.concat(["M", Math.round(x) + .5, Math.round(y + i * rowHeight) + .5, "H", Math.round(x + w) + .5]);
    }
    for (i = 1; i < wv; i++) {
        path = path.concat(["M", Math.round(x + i * columnWidth) + .5, Math.round(y) + .5, "V", Math.round(y + h) + .5]);
    }
    return this.path(path.join(",")).attr({stroke: color});
};

function draw_rarefaction(data_id, display_id, XmaxVal, YmaxVal) {
    if (document.getElementById(display_id).innerHTML != "") {
	return;
    }

    // Grab the data
    var mgids   = [];
    var coords  = [];
    var mg_list = document.getElementById(data_id).value.split('@');
    var colors  = GooglePalette(mg_list.length);
    
    for (var i=0; i<mg_list.length; i++) {
	var sets = mg_list[i].split('~');
	var mgid = sets.shift();
	var data = [];
	for (var j=0; j<sets.length; j++) {
	    data.push( sets[j].split(';;') );
	}
	mgids.push( mgid );
	coords.push( data );
    }

    // Draw
    var width  = 900,
        height = 450,
        ytick  = 10,
        xtick  = 20,
        leftgutter   = 70,
        bottomgutter = 30,
        topgutter    = 20,
        r = Raphael(display_id, width + 30, height + 30),
        txt  = {font: '12px Helvetica, Arial', fill: "#fff"},
        txt2 = {font: '10px Helvetica, Arial', fill: "#000"},
        txt3 = {font: '14px Helvetica, Arial', fill: "#000"},
        maxX = width - leftgutter,
        maxY = height - bottomgutter - topgutter,
        X    = maxX / XmaxVal,
        Y    = maxY / YmaxVal;
    // Raphael.fn.drawGrid = function (x, y, w, h, wv, hv, color)
    r.drawGrid(leftgutter + X * .5 + .5, topgutter + .5, maxX - X, maxY, xtick, ytick, "#333");

    // y-axis labels
    var maxLabelSizeY = 0;
    for (var i = 0; i < ytick; i++) {
	var scaleHeight = maxY * ((ytick-i) / ytick);
	var scaleValue  = Math.round(YmaxVal * ((i+1) / ytick));
	r.text(leftgutter - (3 * scaleValue.toString().length) - 4, Math.round(scaleHeight) - 12, scaleValue).attr(txt2);
	maxLabelSizeY = Math.max(maxLabelSizeY, 3 * scaleValue.toString().length);
    }
    r.text(leftgutter - (3 * "0".length) - 4, height - bottomgutter, "0").attr(txt2);
    r.text(leftgutter - maxLabelSizeY - 30, Math.round((height - topgutter)/2), "Species Count").attr(txt3).rotate(270);

    // x-axis labels
    var maxLabelSizeX = 0;
    for (var i = 0; i < xtick; i++) {
	var scaleWidth = maxX * ((i+1) / xtick);
	var scaleValue = Math.round(XmaxVal * ((i+1) / xtick));
	r.text(Math.round(scaleWidth) + leftgutter - 4, height - 10, scaleValue).attr(txt2).rotate(315).toBack();
	maxLabelSizeX = Math.max(maxLabelSizeX, 3 * scaleValue.toString().length);
    }
    r.text(leftgutter - 4, height - 15, "0").attr(txt2);
    r.text(Math.round(maxX/2) + leftgutter, height + (30 * 0.75), "Number of Reads").attr(txt3);

    // draw path
    var x0     = leftgutter + 2,
        y0     = height - bottomgutter + 2,
        paths  = r.set(),
        labels = r.set(),
        popups = r.set(),
        visible = [],
        clicked = [];

    for (var i=0; i<mgids.length; i++) {
        var xy_pos = ["M "+x0+" "+y0];
	var midPos = coords[i][Math.round(coords[i].length/2) - 1];
	for (var j=0; j<coords[i].length; j++) {
	    var pX = x0 + (X * coords[i][j][0]);
	    var pY = y0 - (Y * coords[i][j][1]);
	    xy_pos.push( "L "+pX+" "+pY );
	}
	paths.push( r.path().attr({path: xy_pos.join(" "), stroke: colors[i], "stroke-width": 3, opacity: 0.7}) );
	labels.push( r.text(60, 12, mgids[i]).attr(txt).hide() );
	popups.push( r.popup(100, 100, labels[i], "right").attr({fill: "#000", stroke: "#666", "stroke-width": 2, "fill-opacity": .7}).hide() );
	visible.push( false );
	clicked.push( false );

	(function (midX, midY, color, path, label, frame, is_visible, is_clicked) {
	    path.hover( function() {
		if (! is_clicked) {
		    this.toFront();
		    this.attr("stroke", color);
		    this.attr("stroke-width", 5);
		    this.attr("opacity", 1);
		    var ppp = r.popup(midX, midY, label, 'right', 1);
		    frame.show().stop().animate({path: ppp.path}, 200 * is_visible).toFront();
		    label.show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_visible).toFront();
		    is_visible = true;
		}
	    }, function() {
                if (! is_clicked) {
		    frame.hide();
		    label.hide();
		    is_visible = false;
		    this.attr("stroke", color);
		    this.attr("stroke-width", 3);
		    this.attr("opacity", 0.7);
		}
	    });
	    path.click( function() {
                if (! is_clicked) {
		    this.toFront();
		    this.attr("stroke", color);
		    this.attr("stroke-width", 5);
		    this.attr("opacity", 1);
		    var ppp = r.popup(midX, midY, label, 'right', 1);
		    frame.show().stop().animate({path: ppp.path}, 200 * is_visible).toFront();
		    label.show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_visible).toFront();
		    is_visible = true;
		    is_clicked = true;
		} else {
		    frame.hide();
		    label.hide();
		    is_visible = false;
		    is_clicked = false;
		    this.attr("stroke", color);
		    this.attr("stroke-width", 3);
		    this.attr("opacity", 0.7);
		}
	    });
            frame.click( function() {
		if (is_clicked && is_visible) {
		    this.hide();
		    label.hide();
		    is_visible = false;
		    is_clicked = false;
		    path.attr("stroke", color);
		    path.attr("stroke-width", 3);
		    path.attr("opacity", 0.7);
		}
	    });
	    label.click( function() {
		if (is_clicked && is_visible) {
		    frame.hide();
		    this.hide();
		    is_visible = false;
		    is_clicked = false;
		    path.attr("stroke", color);
		    path.attr("stroke-width", 3);
		    path.attr("opacity", 0.7);
		}
	    });
	}) (Math.round(x0 + (X * midPos[0])), Math.round(y0 - (Y * midPos[1])), colors[i], paths[i], labels[i], popups[i], visible[i], clicked[i]);
    }

    paths.toFront();
    labels.toFront();
    popups.toFront();
}
