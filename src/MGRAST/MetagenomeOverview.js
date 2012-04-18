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

function draw_rank_abundance_plot(data_id, display_id, mgid, level) {
    // Grab the data
    var data_list = document.getElementById(data_id).value.split("~");
    var pdata = [];
    for (i=0;i<data_list.length;i++) {
	pdata[pdata.length] = data_list[i].split(";;");
    }
    pdata.sort(sort_data);

    var plabel = [], labels = [], data = [];
    for (i=0;i<pdata.length;i++) {
      labels[i] = pdata[i][0]; //i + 1;
      data[i]   = pdata[i][1];
      plabel[i] = pdata[i][0];
    }
    draw_generic_plot(data, labels, plabel, display_id, 'hit', 'Taxon Abundance', true, true, mgid, level);
}

function draw_histogram_plot(data_id, display_id, unit, ltext) {
    // Grab the data
    var data_list = document.getElementById(data_id).value.split("~");
    var pdata = [];
    for (i=0;i<data_list.length;i++) {
	pdata.push( data_list[i].split(";;") );
    }

    var plabel = [], labels = [], data = [];
    for (i=1;i<pdata.length;i++) {
	plabel.push( pdata[i-1][0]+' - '+pdata[i][0]+' '+unit );
	labels.push( pdata[i][0] );
	data.push( pdata[i][1] );
    }
    draw_generic_plot(data, labels, plabel, display_id, 'sequence', ltext, false, null, null);
}

function draw_generic_plot(data, labels, plabel, display_id, ptext, ltext, is_log, longtext, mgid, level) {
    // Draw
    var bonus_x = 0, bonus_y = 0;
    if (longtext) {
	bonus_x = 50;
	bonus_y = 200;
    }
     if (ltext && (! longtext)) {
	bonus_x = 30;
    }
    var width = 850,
        height = 250,
        leftgutter = 40 + bonus_x,
        bottomgutter = 30,
        topgutter = 20,
        colorhue = .6 || Math.random(),
        color = "hsb(" + [colorhue, .5, 1] + ")",
        r = Raphael(display_id, width + bonus_x, height + bonus_y),
        txt  = {font: '12px Helvetica, Arial', fill: "#fff"},
        txt1 = {font: '10px Helvetica, Arial', fill: "#fff"},
        txt2 = {font: '10px Helvetica, Arial', fill: "#000"},
        txt3 = {font: '14px Helvetica, Arial', fill: "#000"},
        X    = (width - leftgutter) / labels.length,
        max  = is_log ? Math.log(Math.max.apply(Math, data)) : Math.max.apply(Math, data),
        maxY = height - bottomgutter - topgutter,
        Y    = maxY / max;
    // Raphael.fn.drawGrid = function (x, y, w, h, wv, hv, color)
    r.drawGrid(leftgutter + X * .5 + .5, topgutter + .5, width - leftgutter - X, maxY, 10, 10, "#333");
    var path  = r.path().attr({stroke: color, "stroke-width": 4, "stroke-linejoin": "round"}),
        bgp   = r.path().attr({stroke: "none", opacity: .3, fill: color}),
        label = r.set(),
        is_label_visible = false,
        leave_timer,
        blanket = r.set();
    label.push(r.text(60, 12, data[0]+' '+ptext+'s').attr(txt));
    label.push(r.text(60, 27, plabel[0]).attr(txt1).attr({fill: "#fff"}));
    label.hide();
    var frame = r.popup(100, 100, label, "right").attr({fill: "#000", stroke: "#666", "stroke-width": 2, "fill-opacity": .7}).hide();

    var maxLabelSize = 0, labelBuffer = (labels.length * 0.5) - 20;
    for (var i = 0; i < 10; i++) {
	var scaleHeight = maxY * ((10-i) / 10);
	var scaleValue  = max * ((i+1) / 10);
	if (is_log) {
	    scaleValue = Math.round(Math.exp(scaleValue));
	} else {
	    scaleValue = Math.round(scaleValue);
	}
	r.text(leftgutter - labelBuffer - (3 * scaleValue.toString().length), Math.round(scaleHeight) + 2, scaleValue);
	maxLabelSize = Math.max(maxLabelSize, 3 * scaleValue.toString().length);
    }
    if (ltext) {
	r.text(leftgutter - labelBuffer - maxLabelSize - 30, Math.round((height - topgutter)/2), ltext).attr(txt3).rotate(270);
    }

    var p, bgpp;
    for (var i = 0, ii = labels.length; i < ii; i++) {
      var yscale = is_log ? Math.log(data[i]) : data[i];
      var y = Math.round(height - bottomgutter - Y * yscale),
	x = Math.round(leftgutter + X * (i + .5)),
	t = r.text(x, height - 12, labels[i]).attr(txt2).rotate(315).toBack();
      if (longtext) {
	t.translate(parseInt(0 - ((t.getBBox().width / 2) * Math.sin(315))), parseInt((t.getBBox().width / 2) * Math.cos(315)));
      }
      if (!i) {
	p = ["M", x, y, "C", x, y];
	bgpp = ["M", leftgutter + X * .5, height - bottomgutter, "L", x, y, "C", x, y];
      }
      if (i && i < ii - 1) {
	var Y0scale = is_log ? Math.log(data[i - 1]) : data[i - 1],
	  Y2scale = is_log ? Math.log(data[i + 1]) : data[i + 1];
	var Y0 = Math.round(height - bottomgutter - Y * Y0scale),
	  X0 = Math.round(leftgutter + X * (i - .5)),
	  Y2 = Math.round(height - bottomgutter - Y * Y2scale),
	  X2 = Math.round(leftgutter + X * (i + 1.5));
	var a = getAnchors(X0, Y0, x, y, X2, Y2);
	p = p.concat([a.x1, a.y1, x, y, a.x2, a.y2]);
	bgpp = bgpp.concat([a.x1, a.y1, x, y, a.x2, a.y2]);
      }
        var dot = r.circle(x, y, 4).attr({fill: "#000", stroke: color, "stroke-width": 2});
        blanket.push(r.rect(leftgutter + X * i, topgutter, X, height - bottomgutter).attr({stroke: "none", fill: "#fff", opacity: 0}));
        var rect = blanket[blanket.length - 1];
        (function (x, y, data, lbl, dot) {
	  var timer, i = 0;
	  rect.hover(function () {
	      clearTimeout(leave_timer);
	      var side = "right";
	      if (x + frame.getBBox().width > width) {
		side = "left";
	      }
	      label[0].attr({text: data+' '+ptext+ (data == 1 ? "" : "s")});
	      label[1].attr({text: lbl});
	      var ppp = r.popup(x, y, label, side, 1);
	      frame.show().stop().animate({path: ppp.path}, 200 * is_label_visible);
	      label[0].show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_label_visible);
	      label[1].show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_label_visible);
	      dot.attr("r", 6);
	      is_label_visible = true;
            }, function () {
	      dot.attr("r", 4);
	      leave_timer = setTimeout(function () {
		  frame.hide();
		  label[0].hide();
		  label[1].hide();
		  is_label_visible = false;
                }, 1);
	    });
	  if (is_log && level) {  // do this only for abundance plot
	      rect.click(function (event){ check_download('tax', lbl, level, mgid); });
	  }
        })(x, y, data[i], plabel[i], dot);
    }
    p = p.concat([x, y, x, y]);
    bgpp = bgpp.concat([x, y, x, y, "L", x, height - bottomgutter, "z"]);
    path.attr({path: p});
    bgp.attr({path: bgpp});
    frame.toFront();
    label[0].toFront();
    label[1].toFront();
    blanket.toFront();
}

function draw_rarefaction_curve(data_id, display_id) {
    // Grab the data
    var data_list = document.getElementById(data_id).value.split("~");
    var pdata = [];
    for (i=0;i<data_list.length;i++) {
	pdata[pdata.length] = data_list[i].split(";;");
    }
    draw_generic_curve(pdata, display_id, "Number of Reads", "Species Count", "reads", "species");
}

function draw_generic_curve(data, display_id, xlabel, ylabel, xtext, ytext) {
    // Draw
    var bonus_x = 0, bonus_y = 0;
    if (xtext) { bonus_y = 30; }
    if (ytext) { bonus_x = 30; }

    var width  = 850,
        height = 250,
        ytick  = 10,
        xtick  = 10,
        leftgutter   = 40 + bonus_x,
        bottomgutter = 30,
        topgutter    = 20,
        colorhue = .6 || Math.random(),
        color = "hsb(" + [colorhue, .5, 1] + ")",
        r = Raphael(display_id, width + bonus_x, height + bonus_y),
        txt  = {font: '12px Helvetica, Arial', fill: "#fff"},
        txt2 = {font: '10px Helvetica, Arial', fill: "#000"},
        txt3 = {font: '14px Helvetica, Arial', fill: "#000"},
        size = data.length,
        maxX = width - leftgutter,
        maxY = height - bottomgutter - topgutter,
        X    = maxX / data[size-1][0],
        Y    = maxY / data[size-1][1];
    // Raphael.fn.drawGrid = function (x, y, w, h, wv, hv, color)
    r.drawGrid(leftgutter + X * .5 + .5, topgutter + .5, maxX - X, maxY, xtick, ytick, "#333");

    // y-axis labels
    var maxLabelSizeY = 0;
    for (var i = 0; i < ytick; i++) {
	var scaleHeight = maxY * ((ytick-i) / ytick);
	var scaleValue  = Math.round(data[size-1][1] * ((i+1) / ytick));
	r.text(leftgutter - (3 * scaleValue.toString().length) - 4, Math.round(scaleHeight) + 2, scaleValue).attr(txt2);
	maxLabelSizeY = Math.max(maxLabelSizeY, 3 * scaleValue.toString().length);
    }
    r.text(leftgutter - (3 * "0".length) - 4, height - bottomgutter, "0").attr(txt2);
    if (ylabel) {
	r.text(leftgutter - maxLabelSizeY - 30, Math.round((height - topgutter)/2), ylabel).attr(txt3).rotate(270);
    }

    // x-axis labels
    var maxLabelSizeX = 0;
    for (var i = 0; i < xtick; i++) {
	var scaleWidth = maxX * ((i+1) / xtick);
	var scaleValue = Math.round(data[size-1][0] * ((i+1) / xtick));
	r.text(Math.round(scaleWidth) + leftgutter - 4, height - 10, scaleValue).attr(txt2).rotate(315).toBack();
	maxLabelSizeX = Math.max(maxLabelSizeX, 3 * scaleValue.toString().length);
    }
    r.text(leftgutter - 4, height - 15, "0").attr(txt2);
    if (xlabel) {
	r.text(Math.round(maxX/2) + leftgutter, height + (bonus_y * 0.75), xlabel).attr(txt3);
    }

    // draw path
    var x0     = leftgutter + 2,
        y0     = height - bottomgutter + 2,
        xrange = maxX / size,
        xy_pos = ["M "+x0+" "+y0],
        aPath  = r.path().attr({stroke: color, "stroke-width": 4, "stroke-linejoin": "round"}),
        labels = r.set(),
        hovers = r.set(),
        is_label_visible = false,
        leave_timer;
    labels.push(r.text(60, 12, ytext+': '+Math.round(data[0][1])).attr(txt));
    labels.push(r.text(60, 27, xtext+': '+data[0][0]).attr(txt));
    labels.hide();
    var frame = r.popup(100, 100, labels, "right").attr({fill: "#000", stroke: "#666", "stroke-width": 2, "fill-opacity": .7}).hide();

    for (var i=0; i<size; i++) {
	var pX = x0 + (X * data[i][0]);
	var pY = y0 - (Y * data[i][1]);
	xy_pos.push( "L "+pX+" "+pY );
	hovers.push( r.rect(pX, topgutter, xrange, y0).attr({stroke: "none", fill: "#fff", opacity: 0}) );
        var rect = hovers[hovers.length - 1];

        (function (xpos, ypos, xdata, ydata) {
	  var timer, i = 0;
	  rect.hover(function () {
	      clearTimeout(leave_timer);
	      var side = "right";
	      if (xpos + frame.getBBox().width > width) {
		side = "left";
	      }
	      labels[0].attr({text: ytext+': '+Math.round(ydata)});
	      labels[1].attr({text: xtext+': '+xdata});
	      var ppp = r.popup(xpos, ypos, labels, side, 1);
	      frame.show().stop().animate({path: ppp.path}, 200 * is_label_visible);
	      labels[0].show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_label_visible);
	      labels[1].show().stop().animateWith(frame, {translation: [ppp.dx, ppp.dy]}, 200 * is_label_visible);
	      is_label_visible = true;
            }, function () {
	      leave_timer = setTimeout(function () {
		  frame.hide();
		  labels[0].hide();
		  labels[1].hide();
		  is_label_visible = false;
                }, 1);
	    });
        })(pX, pY, data[i][0], data[i][1]);
    }
    aPath.attr({path: xy_pos.join(" ")});
    frame.toFront();
    labels[0].toFront();
    labels[1].toFront();
    hovers.toFront();
}

function draw_bar_plot(display_id, labels, colors, data) {
    var maxLabelSize = 0;
    for (var i=0; i<labels.length; i++) {
	maxLabelSize = Math.max(maxLabelSize, Math.round(2.2 * labels[i].split('\n')[0].length));
    }
    var barCount   = data.length,
        topgutter  = 10,
        barHeight  = 35,
        gapHeight  = 45,
        rWidth     = 375,
        rHeight    = topgutter + ((barHeight + gapHeight) * barCount) + 10,
        leftgutter = 40 + maxLabelSize,
        path = {stroke: "hsb("+[0.6, .5, 1]+")", "stroke-width": 2},
        txt1 = {font: '10px Helvetica, Arial', fill: "#fff"},
        txt2 = {font: '10px Helvetica, Arial', fill: "#000"},
        r    = Raphael(display_id, rWidth, rHeight);

    // bars w/ text
    var lineStart = '';
    for (var i=0; i<barCount; i++) {
	var total = 0, middle = 0, right = 0, r_color = '';
	if (data[i].length == 3) {
	    [ total, middle, right ] = data[i];
	} else {
	    [ total, right ] = data[i];
	}
	if (colors[i].length == 3) {
	    r_color = colors[i][2];
	} else {
	    r_color = colors[i][1];
	}
	l_color = colors[i][0];
	total   = parseInt(total);
	middle  = parseInt(middle);
	right   = parseInt(right);
	if (total == 0) { continue; }
	if ((middle + right) > total) { middle = total - right; }
	
	var barTop     = (i * barHeight) + (i * gapHeight) + topgutter;
	var barWidth   = rWidth - leftgutter;
	var leftWidth  = Math.round(((total - (middle + right)) / total) * barWidth);
	var midWidth   = Math.round((middle / total) * barWidth);
	var rightWidth = Math.round((right / total) * barWidth);
	var rightPerc  = ((right / total) * 100).toFixed(1).toString() + ' %';
	var totalNum   = comma_format(total);

	r.text(leftgutter - Math.round(2.2 * labels[i].split('\n')[0].length) - 10, barTop + Math.round(barHeight / 2), labels[i]).attr(txt2);
	if (leftWidth > 0) {
	    r.rect(leftgutter, barTop, leftWidth, barHeight, 7).attr({stroke: "#8B8989", fill: l_color});
	}
	if (rightWidth > 0) {
	    r.rect(leftgutter + leftWidth + midWidth, barTop, rightWidth, barHeight, 7).attr({stroke: "#8B8989", fill: r_color});
	}
	if ((midWidth > 0) && (colors[i].length == 3)) {
	    var midPerc = ((middle / total) * 100).toFixed(1).toString() + " %\nrRNAs";
	    rightPerc   = rightPerc + "\nORFs";
	    r.rect(leftgutter + leftWidth, barTop, midWidth, barHeight, 7).attr({stroke: "#8B8989", fill: colors[i][1]});
	    r.text(leftgutter + leftWidth + Math.round(midWidth / 2), barTop + Math.round(barHeight / 2), midPerc).attr(txt1);
	}
	if (rightWidth > 0) {
	    r.text(leftgutter + leftWidth + midWidth + Math.round(rightWidth / 2), barTop + Math.round(barHeight / 2), rightPerc).attr(txt1);
	}
	r.text(leftgutter - Math.round(2.2 * labels[i].split('\n')[0].length) - 10, barTop + Math.round(barHeight / 2), labels[i]).attr(txt2);
	r.text(leftgutter + 5, barTop + barHeight + 8, '0').attr(txt2);
	r.text(rWidth - Math.round(2.2 * totalNum.length) - 7, barTop + barHeight + 8, totalNum).attr(txt2);
	if (lineStart != '') {
	    r.path(lineStart + 'L' + leftgutter.toString() + ' ' + barTop.toString()).attr(path);
	    r.path('M' + rWidth.toString() + ' ' + (barTop - gapHeight).toString() + 'L' + rWidth.toString() + ' ' + barTop.toString()).attr(path);
	}
	lineStart = 'M' + (leftgutter + leftWidth + midWidth).toString() + ' ' + (barTop + barHeight).toString();
    }
}

function getAnchors(p1x, p1y, p2x, p2y, p3x, p3y) {
    var l1 = (p2x - p1x) / 2,
        l2 = (p3x - p2x) / 2,
        a  = Math.atan((p2x - p1x) / Math.abs(p2y - p1y)),
        b  = Math.atan((p3x - p2x) / Math.abs(p2y - p3y));
    a = p1y < p2y ? Math.PI - a : a;
    b = p3y < p2y ? Math.PI - b : b;

    var alpha = Math.PI / 2 - ((a + b) % (Math.PI * 2)) / 2,
        dx1   = l1 * Math.sin(alpha + a),
        dy1   = l1 * Math.cos(alpha + a),
        dx2   = l2 * Math.sin(alpha + b),
        dy2   = l2 * Math.cos(alpha + b);

    return {
	x1: p2x - dx1,
	y1: p2y + dy1,
	x2: p2x + dx2,
	y2: p2y + dy2
	};
}

function sort_data(a,b) {
  return b[1] - a[1];
}

function save_image(div) {
   if (document.getElementById(div+"canvas") == null) {
     var svg = document.getElementById(div).innerHTML;
    var canvas = document.createElement('canvas');
    canvas.setAttribute("width", "1000");
    canvas.setAttribute("height", "1000");
    canvas.setAttribute("id", div+"canvas");
    document.getElementById(div).parentNode.appendChild(canvas);
    canvg(canvas, svg);
  }
}

function check_download(type, obj, level, mgid) {
  if (confirm('Open analysis workbench for all sequences predicted as '+obj+' in Metagenome '+mgid)) {
    window.open("?page=Analysis&wbinit=mgoverview&metagenome="+mgid+"&type="+type+"&level="+level+"&cat="+obj, "MG-RAST - Metagenome Analysis");
    //    document.getElementById('fasta_export_cat').value = obj;
    //    document.getElementById('fasta_export_form').submit();
  }
}

function comma_format(x) {
    x = x.toString();
    var pattern = /(-?\d+)(\d{3})/;
    while (pattern.test(x))
        x = x.replace(pattern, "$1,$2");
    return x;
}

