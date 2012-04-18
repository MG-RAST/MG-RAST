function navigate_plot (id, pos, deg) {
  table_goto('0', pos);
  deg = parseInt(deg) + 90;
  var dot = document.getElementById('plot_dot_'+id);
  var img = document.getElementById('plot_img_'+id);
  var middle = img.width / 2;
  var rad = 2 * Math.PI / 360;
  var x = 0 - parseInt(middle + (middle * Math.sin(rad * deg)));
  var y = 0 - parseInt(middle + (middle * Math.cos(rad * deg)));
  dot.style.top = x;
  dot.style.left = y;
}
