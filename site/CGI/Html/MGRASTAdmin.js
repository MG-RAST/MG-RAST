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

function draw_generic_plot(data, labels, plabel, display_id, ptext, ltext, is_log, longtext) {
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
	  if (is_log) {  // do this only for abundance plot
	    rect.click(function (event){ check_download(lbl); });
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

 function stat_graph (which, dname) {
  var data_id = which+'_stats_data';
  var display_id = which+'_stats';
  
  // Grab the data
  var data_list = document.getElementById(data_id).value.split(";");
  var plabel = [ '-30d', '-29d', '-28d', '-27d', '-26d', '-25d', '-24d', '-23d', '-22d', '-21d', '-20d', '-19d', '-18d', '-17d', '-16d', '-15d', '-14d', '-13d', '-12d', '-11d', '-10d', '-9d', '-8d', '-7d', '-6d', '-5d', '-4d', '-3d', '-48h', '-24h' ], labels = [ '-30d', '-29d', '-28d', '-27d', '-26d', '-25d', '-24d', '-23d', '-22d', '-21d', '-20d', '-19d', '-18d', '-17d', '-16d', '-15d', '-14d', '-13d', '-12d', '-11d', '-10d', '-9d', '-8d', '-7d', '-6d', '-5d', '-4d', '-3d', '-48h', '-24h' ], data = [];
  draw_generic_plot(data_list, labels, plabel, display_id, dname, dname, false, false);
 }

 function load_dashboard () {
   var data1  = new google.visualization.DataTable();
   var data2  = new google.visualization.DataTable();
   var data3  = new google.visualization.DataTable();
   var data4  = new google.visualization.DataTable();
   var data5  = new google.visualization.DataTable();

   var data1b  = new google.visualization.DataTable();
   var data2b  = new google.visualization.DataTable();
   var data3b  = new google.visualization.DataTable();
   var data4b  = new google.visualization.DataTable();
   var data5b  = new google.visualization.DataTable();

   var data6  = new google.visualization.DataTable();
   var data7  = new google.visualization.DataTable();
   var data8  = new google.visualization.DataTable();
   var data11  = new google.visualization.DataTable();

   var up_data = document.getElementById('upload_stats_data').value.split(";");
   var fin_data = document.getElementById('finished_stats_data').value.split(";");
   var proc_data = document.getElementById('processing_stats_data').value.split(";");
   var broken_data = document.getElementById('broken_stats_data').value.split(";");
   var user_data = document.getElementById('user_stats_data').value.split(";");
   var average_size_data = document.getElementById('average_size_data').value.split(";");
   var average_size_filtered_data = document.getElementById('average_size_filtered_data').value.split(";");
   var average_size_filtered2_data = document.getElementById('average_size_filtered2_data').value.split(";");
   var average_size_cols = document.getElementById('average_size_cols').value.split(";");
   var size_distribution = document.getElementById('size_distribution').value.split(";");

   var thirty_days = document.getElementById('thirty_days_dates').value.split(";");

   data1.addColumn('string', 'Gbp');
   data2.addColumn('string', 'Gbp');
   data3.addColumn('string', 'Gbp');
   data4.addColumn('string', 'Jobs');
   data5.addColumn('string', 'User');

   data1b.addColumn('string', 'Gbp');
   data2b.addColumn('string', 'Gbp');
   data3b.addColumn('string', 'Gbp');
   data4b.addColumn('string', 'Jobs');
   data5b.addColumn('string', 'User');

   data6.addColumn('string', 'Mbp');
   data7.addColumn('string', 'Mbp');
   data8.addColumn('string', 'Mbp');
   data11.addColumn('string', '%');

   data1.addColumn('number', 'uploaded');
   data2.addColumn('number', 'finished');
   data3.addColumn('number', 'processing');
   data4.addColumn('number', 'error');
   data5.addColumn('number', 'user');

   data1b.addColumn('number', 'uploaded');
   data2b.addColumn('number', 'finished');
   data3b.addColumn('number', 'processing');
   data4b.addColumn('number', 'error');
   data5b.addColumn('number', 'user');

   data6.addColumn('number', 'average jobsize < 5Mb');
   data6.addColumn('number', 'average jobsize > 5Mb < 50Mb');
   data6.addColumn('number', 'average jobsize > 50Mb');
   data7.addColumn('number', 'average jobsize');
   data8.addColumn('number', 'average jobsize');
   data11.addColumn('number', '< 5Mb');
   data11.addColumn('number', '> 5Mb < 50Mb');
   data11.addColumn('number', '> 50 Mb');

   data1.addRows(7);
   data2.addRows(7);
   data3.addRows(7);
   data4.addRows(7);
   data5.addRows(7);

   data1b.addRows(30);
   data2b.addRows(30);
   data3b.addRows(30);
   data4b.addRows(30);
   data5b.addRows(30);

   data6.addRows(48);
   data7.addRows(48);
   data8.addRows(48);
   data11.addRows(48);

   for (h=0;h<30;h++) {
     data1b.setValue(h, 0, thirty_days[h]);//'-'+(29 - h));
     data2b.setValue(h, 0, thirty_days[h]);//'-'+(29 - h));
     data3b.setValue(h, 0, thirty_days[h]);//'-'+(29 - h));
     data4b.setValue(h, 0, thirty_days[h]);//'-'+(29 - h));
     data5b.setValue(h, 0, thirty_days[h]);//'-'+(29 - h));
     data1b.setValue(h, 1, parseFloat(up_data[h]));
     data2b.setValue(h, 1, parseFloat(fin_data[h]));
     data3b.setValue(h, 1, parseFloat(proc_data[h]));
     data4b.setValue(h, 1, parseFloat(broken_data[h]));
     data5b.setValue(h, 1, parseFloat(user_data[h]));
   }
   for (h=0;h<48;h++) {
     data6.setValue(h, 0, average_size_cols[h]);
     data7.setValue(h, 0, average_size_cols[h]);
     data8.setValue(h, 0, average_size_cols[h]);
     data6.setValue(h, 1, parseFloat(average_size_data[h]));
     data6.setValue(h, 2, parseFloat(average_size_filtered_data[h]));
     data6.setValue(h, 3, parseFloat(average_size_filtered2_data[h]));
     data7.setValue(h, 1, parseFloat(average_size_filtered_data[h]));
     data8.setValue(h, 1, parseFloat(average_size_filtered2_data[h]));
     var d11row = size_distribution[h].split("|");
     data11.setValue(h, 0, average_size_cols[h]);
     data11.setValue(h, 1, parseFloat(d11row[0]));
     data11.setValue(h, 2, parseFloat(d11row[1]));
     data11.setValue(h, 3, parseFloat(d11row[2]));
   }
   for (h=22;h<29;h++) {
     data1.setValue(h - 22, 0, thirty_days[h]);//'-'+(29 - h));
     data2.setValue(h - 22, 0, thirty_days[h]);//'-'+(29 - h));
     data3.setValue(h - 22, 0, thirty_days[h]);//'-'+(29 - h));
     data4.setValue(h - 22, 0, thirty_days[h]);//'-'+(29 - h));
     data5.setValue(h - 22, 0, thirty_days[h]);//'-'+(29 - h));
     data1.setValue(h - 22, 1, parseFloat(up_data[h]));
     data2.setValue(h - 22, 1, parseFloat(fin_data[h]));
     data3.setValue(h - 22, 1, parseFloat(proc_data[h]));
     data4.setValue(h - 22, 1, parseFloat(broken_data[h]));
     data5.setValue(h - 22, 1, parseFloat(user_data[h]));
   }

   var chart1 = new google.visualization.LineChart(document.getElementById('dash_0'));
   chart1.draw(data1, {width: 350, height: 240, title: 'Basepairs uploaded in Gbp', legend: 'none', vAxis: {minValue: 0}});
   var chart2 = new google.visualization.LineChart(document.getElementById('dash_1'));
   chart2.draw(data2, {width: 350, height: 240, title: 'Basepairs finished in Gbp', legend: 'none', vAxis: {minValue: 0}});
   var chart3 = new google.visualization.LineChart(document.getElementById('dash_2'));
   chart3.draw(data3, {width: 350, height: 240, title: 'Basepairs processing in Gbp', legend: 'none', vAxis: {minValue: 0}});
   var chart4 = new google.visualization.LineChart(document.getElementById('dash_3'));
   chart4.draw(data4, {width: 350, height: 240, title: 'Number of Jobs with error status', legend: 'none', vAxis: {minValue: 0}});
   var chart5 = new google.visualization.LineChart(document.getElementById('dash_4'));
   chart5.draw(data5, {width: 350, height: 240, title: 'New users', legend: 'none', vAxis: {minValue: 0}});

  var chart1b = new google.visualization.LineChart(document.getElementById('dash_0_b'));
   chart1b.draw(data1b, {width: 750, height: 240, title: 'basepairs uploaded in Gbp', legend: 'none', vAxis: {minValue: 0}});
   var chart2b = new google.visualization.LineChart(document.getElementById('dash_1_b'));
   chart2b.draw(data2b, {width: 750, height: 240, title: 'basepairs finished in Gbp', legend: 'none', vAxis: {minValue: 0}});
   var chart3b = new google.visualization.LineChart(document.getElementById('dash_2_b'));
   chart3b.draw(data3b, {width: 750, height: 240, title: 'basepairs processing in Gbp', legend: 'none', vAxis: {minValue: 0}});
   
   var chart4b = new google.visualization.LineChart(document.getElementById('dash_3_b'));
   chart4b.draw(data4b, {width: 750, height: 240, title: 'Number of Jobs with error status', legend: 'none', vAxis: {minValue: 0}});
   var chart5b = new google.visualization.LineChart(document.getElementById('dash_4_b'));
   chart5b.draw(data5b, {width: 750, height: 240, title: 'New users', legend: 'none', vAxis: {minValue: 0}});

   var chart6 = new google.visualization.LineChart(document.getElementById('dash_6'));
   chart6.draw(data6, {width: 750, height: 240, title: 'Average jobsize / month in Mbp on log scale', legend: 'none', curveType: "function", vAxis: {minValue: 0, logScale: true }});
   //var chart7 = new google.visualization.LineChart(document.getElementById('dash_7'));
   //chart7.draw(data7, {width: 750, height: 240, title: 'Average jobsize / month in Mbp >5Mbp <50Mbp', legend: 'none', curveType: "function", vAxis: {minValue: 0}});
   //var chart8 = new google.visualization.LineChart(document.getElementById('dash_8'));
   //chart8.draw(data8, {width: 750, height: 240, title: 'Average jobsize / month in Mbp >50Mbp', legend: 'none', curveType: "function", vAxis: {maxValue: 100}});

   var data9 = new google.visualization.DataTable();
   var all_users_countries = document.getElementById('all_users_countries').value.split(";");
   var all_users_nums = document.getElementById('all_users_nums').value.split(";");
   data9.addRows(all_users_nums.length);
   data9.addColumn('string', 'Country');
   data9.addColumn('number', 'Users');
   for (i=0;i<all_users_nums.length;i++) {
     data9.setValue(i, 0, all_users_countries[i]);
     data9.setValue(i, 1, parseInt(all_users_nums[i]));
   }
   var geochart1 = new google.visualization.GeoChart(document.getElementById('dash_9'));
   geochart1.draw(data9, {width: 556, height: 347});

   var data10 = new google.visualization.DataTable();
   var curr_users_countries = document.getElementById('curr_users_countries').value.split(";");
   var curr_users_nums = document.getElementById('curr_users_nums').value.split(";");
   data10.addRows(curr_users_nums.length);
   data10.addColumn('string', 'Country');
   data10.addColumn('number', 'Users');
   for (i=0;i<curr_users_nums.length;i++) {
     data10.setValue(i, 0, curr_users_countries[i]);
     data10.setValue(i, 1, parseInt(curr_users_nums[i]));
   }
   var geochart2 = new google.visualization.GeoChart(document.getElementById('dash_10'));
   geochart2.draw(data10, {width: 556, height: 347});

   var chart11 = new google.visualization.AreaChart(document.getElementById('dash_11'));
   chart11.draw(data11, {width: 750, height: 240, title: 'upload volume contribution in %', legend: 'right', isStacked: 'true', curveType: "function" });

   for (h=0;h<5;h++) {
     document.getElementById('dash_'+h+'_b').style.display = 'none';
   }
 }

 function switch_days() {
   var but = document.getElementById('dash_0_button');
   if (but.value == 'show 30 days') {
     but.value = 'show 7 days';
     for (which=0;which<5;which++) {
       document.getElementById('dash_'+which).style.display = 'none';
       document.getElementById('dash_'+which+'_b').style.display = '';
     }
   } else {
     but.value = 'show 30 days';
     for (which=0;which<5;which++) {
       document.getElementById('dash_'+which).style.display = '';
       document.getElementById('dash_'+which+'_b').style.display = 'none';
     }
   }
 }
 
