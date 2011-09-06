function uploaderStatusChanged( uploader ) {
  if (uploader.getStatus() == 1) {
    var date = new Date();
    var attrSet = uploader.getAttributeSet();
    var attr = attrSet.createStringAttribute( 'uid', document.getElementById('uid').value+'|'+uploader.getFileCount()+'|'+date.getTime() );
    attr.setSendToServer(1);
  } else {
    window.top.location="?page=CreateJob";
  }
}

function reload_this() {
  execute_ajax("upload_page", "upload_result", "a=b")
}

function show_detail(which) {
  document.getElementById('status_detail').innerHTML = "<img src='./Html/mg-logout.png' onclick='document.getElementById(\"status_detail\").innerHTML=\"\";' style='cursor: pointer;height:20px;float:right;' title='close detail info'>"+document.getElementById('jt_'+which).innerHTML;
}

function transfer_selected (which, table_id, selcol) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  var file_names = new Array();
  var data_array = table_input_columns_data[data_index];
  for (i=0;i<data_array.length;i++) {
    var val = data_array[i][selcol];
    if (val == 1) {
      file_names[file_names.length] = table_data[data_index][i][1]+"/"+table_data[data_index][i][0];
    }
  }
  var sel_text = "";
  for (i=0;i<file_names.length;i++) {
    sel_text += "<input type='hidden' name='metagenome' value='"+file_names[i]+"'>"+file_names[i]+"<br>";
  }
  document.getElementById('metagenomes_'+which).innerHTML = sel_text;
}

function add_md5 (filename, dirname) {
  var md5 = prompt("Enter md5 sum for '"+filename+"'", "");
  if (md5.length) {
    window.top.location = "?page=CreateJob&md5="+md5+"&fn="+filename+"&dn="+dirname;
  }
}

function check_metadata(table_id) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }
  var file_names = new Array();
  var data_array = table_input_columns_data[data_index];
  for (i=0;i<data_array.length;i++) {
    var val = data_array[i][13];
    if (val == 1) {
      file_names[file_names.length] = table_data[data_index][i][1]+"/"+table_data[data_index][i][0];
    }
  }
  var sel_text = "";
  for (i=0;i<file_names.length;i++) {
    sel_text += "<input type='hidden' name='metagenome' value='"+file_names[i]+"'>";
  }
  document.getElementById('metadata_input_div').innerHTML = sel_text;
  document.forms.md_form.submit();
}

function show_demult_details (table_id, row) {
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      data_index = i;
    }
  }

  var data_row = table_data[data_index][row];
  var demult_html = '<br><br><img title="close detail info" style="cursor: pointer; height: 20px; float: right;" onclick="document.getElementById(\'demult_detail_info\').innerHTML=\'\';" src="./Html/mg-logout.png">';
  demult_html += "<h2>file "+data_row[2]+"/"+data_row[1]+"</h2>";
  if (data_row[5] == '-') {
    demult_html += "<p>This file is not selected for demultiplexing and no barcodes were autodetected</p>";
  }
  if (data_row[5] == 'info file') {
    demult_html += "<p>This file has been demultiplexed. The barcodes where uploaded by you.</p>";
  }
  if (data_row[5] == 'autodetect') {
    var bca = new Array();
    bca = data_row[4].split(/\s/);
    var bc_length = bca[2];
    demult_html += "<p>Autodetection found barcodes in this file.</p><br><input type='button' value='demultiplex now' onclick='window.top.location=\"?page=CreateJob&file="+data_row[0]+"&dir="+data_row[2]+"&bc_length="+bc_length+"\"'>";
  }
  demult_html += "<br><br><br>";

  document.getElementById('demult_detail_info').innerHTML = demult_html;
}
