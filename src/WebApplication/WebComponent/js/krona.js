function generate_krona (data_field, hierarchy, from_array) {
  var data_array = [];
  if (from_array) {
    data_array = data_field;
  } else {
    var data_string = document.getElementById(data_field).value;
    data_string = data_string.replace(/@1/g, "'");
    data_string = data_string.replace(/@2/g, '"');
    var rows = data_string.split('||');
    for (i=0;i<rows.length;i++) {
      data_array[data_array.length] = rows[i].split('^^');
    }
  }

  var total_depth = hierarchy.length - 1;
  var dataset_names_hash = [];
  for (i=0;i<data_array.length;i++) {
    dataset_names_hash[data_array[i][0]] = 1;
  }
  var dataset_names = [];
  for (i in dataset_names_hash) {
    dataset_names[dataset_names.length] = i;
  }
  var dataset_name = dataset_names.join(',');
  var nodes = [];
  var all = [];
  var dataset_hash = [];
  for (i=0;i<dataset_names.length;i++) {
    dataset_hash[dataset_names[i]] = i;
    all[i] = 0;
  }
  var numcols = data_array[0].length;

  for (i=0; i<data_array.length; i++) {
    var curr_abundance = parseFloat(data_array[i][numcols - 2]);
    var curr_evalue = parseFloat(data_array[i][numcols - 1]);
    var curr_mg = data_array[i][0];
    all[dataset_hash[curr_mg]] += curr_abundance;
    krona_recursive(data_array[i], nodes, 0, total_depth, curr_abundance, curr_evalue, curr_mg);
  }

  var data = '<magnitude attribute="magnitude"><\/magnitude><attributes rank="Rank" score="Avg. log e-value" magnitude="Abundance"><\/attributes><datasets names="'+dataset_name+'"><\/datasets><color valueend="4" valuestart="-157" hueend="0" huestart="120" attribute="score"><\/color>';

  data += "<node score='1' magnitude='"+all.join(",")+"' name='all'>";

  for (var a in nodes) {
    data = krona_recursive2(nodes[a], a, hierarchy, 0, data, dataset_names);
  }

  data += "<\/node>";

  var krona_window = window.open('','krona_window_'+dataset_name);
  krona_window.document.write('<html><head><meta charset="utf-8"\/><style>body { margin:0; }<\/style><title>MG-RAST - Krona view of Metagenome '+dataset_name+'<\/title><link rel="icon" type="image/png" href="./Html/favicon.ico"><\/head><body style="padding:0;position:relative"><a href="?page=Home" style="border: none; background-color:black; position: absolute; bottom: 8px;"><img style="height: 66px; border: none;" src="./Html/MGRAST_logo.png" alt="MG-RAST Metagenomics Analysis Server" \/><\/a><a href="http://sourceforge.net/p/krona/home/krona/" target=_blank style="position: absolute; bottom: 8px; border: none; text-decoration: none; color: black; left: 260px;"><img src="./Html/krona.png" style="border: none;"> powered by Krona<\/a><div id="options" style="position:absolute;left:0;top:100px"><\/div><div id="details" style="position:absolute;top:1px;right:2px;text-align:right;"><\/div><canvas id="canvas" width="100%" height="100%"><\/canvas><img id="hiddenImage" visibility="hide" src="http://krona.sourceforge.net/img/hidden.png"><script name="tree" src="./Html/krona-1.1.js"><\/script><data>'+data+'<\/data><img src="./Html/clear.gif" onload="load()"><\/body><\/html>');
  krona_window.document.close();
}

function krona_recursive (row, parentNode, depth, maxDepth, curr_abundance, curr_evalue, curr_mg) {
  if (! parentNode[row[depth + 1]]) {
    parentNode[row[depth + 1]] = [];
    parentNode[row[depth + 1]]['mgs'] = [];
    parentNode[row[depth + 1]]['children'] = [];
  }
  if (! parentNode[row[depth + 1]]['mgs'][curr_mg]) {
    parentNode[row[depth + 1]]['mgs'][curr_mg] = [ curr_abundance, curr_evalue, 1 ];
  } else {
    parentNode[row[depth + 1]]['mgs'][curr_mg][0] += curr_abundance;
    parentNode[row[depth + 1]]['mgs'][curr_mg][1] = ((parentNode[row[depth + 1]]['mgs'][curr_mg][1] * parentNode[row[depth + 1]]['mgs'][curr_mg][2]) + curr_evalue) / (parentNode[row[depth + 1]]['mgs'][curr_mg][2] + 1);
    parentNode[row[depth + 1]]['mgs'][curr_mg][2]++;
  }
  depth++;
  if (depth <= maxDepth) {
    krona_recursive(row, parentNode[row[depth]]['children'], depth, maxDepth, curr_abundance, curr_evalue, curr_mg);
  }
  return;
}

function krona_recursive2 (parentNode, nodename, hierarchy, depth, data, dataset_names) {
  var sc = "";
  var mag = "";
  for (m=0;m<dataset_names.length;m++) {
    if (parentNode['mgs'][dataset_names[m]]) {
      sc += parentNode['mgs'][dataset_names[m]][1]+",";
      mag += parentNode['mgs'][dataset_names[m]][0]+",";
    } else {
      sc += "0,";
      mag += "0,";
    }
  }
  sc = sc.slice(0,sc.length-1);
  mag = mag.slice(0,mag.length-1);
  data += "<node rank='"+hierarchy[depth]+"' score='"+sc+"' magnitude='"+mag+"' name='"+nodename+"'>";
  
  depth++;
  if (hierarchy.length>depth) {
    for (var a in parentNode['children']) {
      data = krona_recursive2(parentNode['children'][a], a, hierarchy, depth, data, dataset_names);
    }
  }

  data += "<\/node>";

  return data;
}
