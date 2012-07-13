var user;
var auth;
var selected_sequence_file;
var selected_metadata_file;
var selected_project;
var selected_libraries = [];
var selected_no_metadata = 0;
var last_directory = "";
var is_a_sequence_file_ending = /(fasta|fa|ffn|frn|fna|fastq|fq)$/;

// initialization
function init_all () {
  if (document.getElementById('user')) {
    var repo = { "url": "upload.cgi/",
		 "type": "WebApp",
		 "id": "mobedac" };
    initialize_data_storage( [ repo ] );
    user = JSON.parse(document.getElementById('uifo').innerHTML);
    auth = user.auth;
    init_uploader();
    update_inbox();
  }
}

function update_inbox (data, files, action) {
  if (data) {
    var flist = DataStore['user_inbox'][user.login].files;
    var dlist = DataStore['user_inbox'][user.login].directories;
    var messages = DataStore['user_inbox'][user.login].messages;

    var sequence_files = [];
    var metadata_files = [];

    var html = '<table><tr><td rowspan=2 style="padding-right: 20px;"><form class="form-horizontal">';
    html += '<select id="inbox_select" multiple style="width: 420px; height: 200px;">';
    var seq_dlist = [];
    var seqs_in_dir = false;
    for (var i=0; i<dlist.length; i++) {
      html += "<optgroup title='this is a directory\nclick to toggle open / close' open=0 label='[ "+dlist[i]+" ] - "+DataStore['user_inbox'][user.login].fileinfo[dlist[i]].length+" files' onclick='if(event.originalTarget.nodeName==\"OPTGROUP\"){if(this.open){this.open=0;for(var i=0;i<this.childNodes.length;i++){this.childNodes[i].style.display=\"none\";}}else{this.open=1;for(var i=0;i<this.childNodes.length;i++){this.childNodes[i].style.display=\"\";}}}'>";
      for (var h=0; h<DataStore['user_inbox'][user.login].fileinfo[dlist[i]].length; h++) {
	var fn = DataStore['user_inbox'][user.login].fileinfo[dlist[i]][h];
	if (fn.match(is_a_sequence_file_ending)) {
	  seq_dlist[dlist[i]] = 1;
	  seqs_in_dir = true;
	}
	var inf = DataStore['user_inbox'][user.login].fileinfo[dlist[i]+"/"+fn];
	if ((seq_dlist[dlist[i]] == 1) && inf['file type'] && (inf['file type'] == 'malformed')) {
	  html += "<option style='display: none; padding-left: 35px; color: red;' title='this is a malformed / unidentifiable sequence file' value='"+dlist[i]+"/"+fn+"'>"+fn+"</option>";
	} else if ((seq_dlist[dlist[i]] == 1) && inf['Error']) {
	  html += "<option style='display: none; padding-left: 35px; color: red;' title='there was an error in the sequence stats computation for this file' value='"+dlist[i]+"/"+fn+"'>"+fn+"</option>";
	} else if ((seq_dlist[dlist[i]] == 1) && inf['unique id count'] && inf['sequence count'] && (inf['unique id count'] != inf['sequence count'])) {
	  html += "<option style='display: none; padding-left: 35px; color: red;' title='the unique id count does not match the sequence count' value='"+dlist[i]+"/"+fn+"'>"+fn+"</option>";
	} else if ((seq_dlist[dlist[i]] == 1) && (! inf['bp count'])) {
	  html += "<option style='display: none; padding-left: 35px; color: gray;' title='the sequence stats computation for this file is still running' value='"+dlist[i]+"/"+fn+"'>"+fn+"</option>";
	} else {
	  html += "<option style='display: none; padding-left: 35px;' value='"+dlist[i]+"/"+fn+"'>"+fn+"</option>";
	}
      }
      html += "</optgroup>";
    }
    for (var i=0; i<flist.length; i++) {
      var isSeq = flist[i].match(is_a_sequence_file_ending);
      if (isSeq) {
	sequence_files[sequence_files.length] = flist[i];
      }
      var isMet = flist[i].match(/\.xls(x)?$/);
      if (isMet) {
	metadata_files[metadata_files.length] = flist[i];
      }
      var inf = DataStore['user_inbox'][user.login].fileinfo[flist[i]];
      if ((seq_dlist[dlist[i]] == 1) && inf['file type'] && (inf['file type'] == 'malformed')) {
	html += "<option title='this is a malformed / unidentifiable sequence file' style='color: red;'>"+flist[i]+"</option>";
      } else if (isSeq && inf['Error']) {
	html += "<option title='there was an error in the sequence stats computation for this file' style='color: red;'>"+flist[i]+"</option>";
      } else if (isSeq && inf['unique id count'] && inf['sequence count'] && (inf['unique id count'] != inf['sequence count'])) {
	html += "<option title='the unique id count does not match the sequence count' style='color: red;'>"+flist[i]+"</option>";
      } else if (isSeq && (! inf['bp count'])) {
	html += "<option title='the sequence stats computation for this file is still running' style='color: gray;'>"+flist[i]+"</option>";
      } else {
	html += "<option>"+flist[i]+"</option>";
      }
    }
    html += '</select>';
    html += '</form></td><td id="inbox_feedback"></td></tr><tr><td id="inbox_file_info"></td></tr></table>';
    document.getElementById('inbox').innerHTML = html;

    if (messages.length) {
      document.getElementById('inbox_feedback').innerHTML = "<h4>Info</h4>"+messages.join("<br>");
    }

    if ((sequence_files.length || seqs_in_dir) && ! selected_sequence_file) {
      var tdata = [];
      for (var i in seq_dlist) {
	for (var h=0; h<DataStore['user_inbox'][user.login].fileinfo[i].length; h++) {
	  // 'select', 'directory', 'filename', 'format', 'size', 'upload date', 'bp count', 'sequencing method', 'sequence type', 'md5'
	  var fn = DataStore['user_inbox'][user.login].fileinfo[i][h];
	  if (fn.match(is_a_sequence_file_ending)) {
	    var inf = DataStore['user_inbox'][user.login].fileinfo[i+'/'+fn];
	      if (inf && inf['bp count'] && (inf['file type'] != 'malformed') && inf['unique id count'] && inf['sequence count'] && (inf['unique id count'] == inf['sequence count']) && (! inf['Error'])) {
	      var trow = [ 0, i, fn, inf['file type'], inf['file size'], inf['creation date'], inf['bp count'], inf['sequencing method guess'], inf['sequence type'], inf['file checksum'], tdata.length ];
	      tdata[tdata.length] = trow;
	    }
	  }
	}
      }
      
      for (var i=0; i<sequence_files.length; i++) {
	  var fn = sequence_files[i];
	  var inf = DataStore['user_inbox'][user.login].fileinfo[fn];
	  if (inf && inf['bp count'] && (inf['file type'] != 'malformed') && inf['unique id count'] && inf['sequence count'] && (inf['unique id count'] == inf['sequence count']) && (! inf['Error'])) {
	    var trow = [ 0, "-", fn, inf['file type'], inf['file size'], inf['creation date'], inf['bp count'], inf['sequencing method guess'], inf['sequence type'], inf['file checksum'], tdata.length ];
	    tdata[tdata.length] = trow;
	  }
      }
      initialize_table(0, tdata);
    }
    if (! selected_metadata_file) {
      html = "<div><h3>available metadata files</h3><table><tr><td><form class='form-horizontal'><select id='metadata_file_select' multiple style='width: 420px; height: 200px;'>";
      for (var i=0; i<metadata_files.length; i++) {
	html += "<option>"+metadata_files[i]+"</option>";
      }
      html += "</select><br><p><input type='checkbox' value='no_metadata' name='no_metadata' id='no_metadata' onclick=\"if(this.checked){alert('INFO\\nNot submitting metadata will severely lower your priority in the computation queue.\\nYou will also not be able to make your data public until you provide metadata for it.');}\"> I do not want to supply metadata</p> <input type='button' class='btn' value='select' onclick='select_metadata_file();'></form></td><td><p id='metadata_file_info' style='margin-left: 20px;'></p></td></tr></table></div>";
      document.getElementById("sel_mdfile_div").innerHTML = html;
      document.getElementById('inbox_select').onchange = function () {
	var fn = this.options[this.selectedIndex].value;
	if (DataStore.user_inbox[user.login].fileinfo && DataStore.user_inbox[user.login].fileinfo[fn]) {
	    var ptext = "<h4>File Information</h4><br>";
	    var inf = DataStore.user_inbox[user.login].fileinfo[fn]
	    if (inf['file type'] && (inf['file type'] == 'malformed')) {
		ptext += '<div class="alert alert-error"><button class="close" data-dismiss="alert" type="button">x</button><strong>Warning</strong><br>This is a malformed / unidentifiable sequence file. You will not be able to use this file for submission.</div>';
	    }
	    else if (inf['Error']) {
		ptext += '<div class="alert alert-error"><button class="close" data-dismiss="alert" type="button">x</button><strong>Warning</strong><br>There was an error in the sequence stats computation:<br><span style="padding-left: 10px;"><pre>'+inf['Error']+'</pre></span><br>You will not be able to use this file for submission.</div>';
	    }
	    else if (inf['unique id count'] && inf['sequence count'] && (inf['unique id count'] != inf['sequence count'])) {
		ptext += '<div class="alert alert-error"><button class="close" data-dismiss="alert" type="button">x</button><strong>Warning</strong><br>The unique id count does not match the sequence count. You will not be able to use this file for submission.</div>';

	    }
	    ptext += "<table>";
	  for (i in DataStore.user_inbox[user.login].fileinfo[fn]) {
	    ptext += "<tr><td><b>"+i+"</b></td><td style='padding-left: 5px;'>"+DataStore.user_inbox[user.login].fileinfo[fn][i]+"</td></tr>";
	  }
	  ptext += "</table>";
	  document.getElementById('inbox_file_info').innerHTML = ptext;
	} else {
	  document.getElementById('inbox_file_info').innerHTML = "";
	}
      }
    }
  } else {
    if (action != 'upload_complete' && document.getElementById('inbox_feedback') && document.getElementById('inbox_feedback').innerHTML.match(/^\<img/)) {
      alert('The inbox is already performing an operation.\nPlease wait for this to finish.');
      return 0;
    }

    var params = [];
    params['query'] = [];
    params['query'][params['query'].length] = 'auth';
    params['query'][params['query'].length] = user.auth;
    var loading_info = " updating...<br><br>";
    if (action && action == "upload_complete") {
      loading_info = "New files were added. If the upload contained sequence files, they will be processed for statistics. This process might take up to one minute.";
    }
    if (files) {
      params['query'][params['query'].length] = 'faction';
      params['query'][params['query'].length] = action;
      if (action == "del") {
	loading_info += "Deleting file(s):";
      } else if (action == "convert") {
	loading_info += "Converting sff file(s) to fastq. The resulting files will be processed for statistics. This will take a few minutes, depending on the file size.<br><br>";
      } else if (action == "demultiplex") {
	loading_info += "Demultiplexing in progress. The resulting files will be processed for statistics. This will take a few minutes, depending on the number of files and file size.<br><br>";
      }
      for (var i=0; i<files.length; i++) {
	params['query'][params['query'].length] = 'fn';
	params['query'][params['query'].length] = files[i];
	loading_info += "<br>"+files[i];
      }
    }
    if (document.getElementById('inbox_feedback')) {
      document.getElementById('inbox_feedback').innerHTML = "<img src='./Html/ajax-loader.gif'>"+loading_info;
    }

    get_objects('user_inbox', params, update_inbox, 1);    
  }
}

/* File Actions */
function check_delete_files () {
  if (confirm("really delete the selected files from your inbox?")) {
    var files = [];
    var filebox = document.getElementById('inbox_select');
    for (var i=0; i<filebox.options.length; i++) {
      if (filebox.options[i].selected) {
	files[files.length] = filebox.options[i].value;
      }
    }
    update_inbox(null, files, "del");
  }
}

function unpack_files () {
  var files = [];
  var filebox = document.getElementById('inbox_select');
  for (var i=0; i<filebox.options.length; i++) {
    if (filebox.options[i].selected) {
      files[files.length] = filebox.options[i].value;
    }
  }
  update_inbox(null, files, "unpack");
}

function convert_files () {
  alert("This might take some minutes, depending on filesize.\nWhen the conversion has finished, your inbox\nwill update automatically.");
  var files = [];
  var filebox = document.getElementById('inbox_select');
  for (var i=0; i<filebox.options.length; i++) {
    if (filebox.options[i].selected) {
      if (filebox.options[i].value.match(/sff$/)) {
	files[files.length] = filebox.options[i].value;
      } else {
	alert(filebox.options[i].value + " does not appear to be an sff file, it will be skipped.");
      }
    }
  }
  update_inbox(null, files, "convert");  
}

function demultiplex_files () {
  var files = [];
  var filebox = document.getElementById('inbox_select');
  for (var i=0; i<filebox.options.length; i++) {
    if (filebox.options[i].selected) {
      files[files.length] = filebox.options[i].value;
    }
  }
  
  if (files.length == 2) {
    var seqfile;
    if (files[0].match(is_a_sequence_file_ending) || files[1].match(is_a_sequence_file_ending)) {
      alert("This might take some minutes, depending on filesize.\nWhen the demultiplexing has finished, your inbox\nwill update automatically.\n\n");
      
      update_inbox(null, files, "demultiplex");
    } else {
      alert("Your selection must include a sequence file (.fasta, .fa, .ffn, .frn, .fna, .fq, or .fastq)");
      return false;
    }
  } else {
    alert("You need to select a sequence file and a barcode file to proceed with demultiplexing.");
  }
}

// upload workflow
function select_sequence_file () {
  if ((document.getElementById("sel_md_pill").className == "pill_incomplete") && (document.getElementById("sel_project_pill").className = "pill_incomplete")) {
    alert("You must either select a metadata file in Step 1\nor choose a project in Step 2 before selecting sequence file(s).");
    return false;
  }
  var sel = document.getElementById('sequence_file_select');
  selected_sequence_files = [];
  var has_fasta = 0;
  var has_fastq = 0;
  for (i=0; i<table_input_columns_data[0].length; i++) {
    if (table_input_columns_data[0][i][0] == 1) {
      var fn = table_data[0][i][2];
      if (fn.match(/(fasta|fa|ffn|frn|fna)$/)) {
	has_fasta = 1;
      }
      if (fn.match(/(fastq|fq)$/)) {
	has_fastq = 1;
      }
      if (table_data[0][i][1] != "-") {
	fn = table_data[0][i][1] + '/' + fn;
      }
      selected_sequence_files.push(fn);
    }
  }

  if (selected_sequence_files.length == 0) {
    alert("You did not select a sequence file");
  } else if (selected_sequence_files.length > 1) {
    if (selected_libraries.length == 0) {
      if (selected_no_metadata && (! selected_project)) {
	alert('WARNING: You have selected not to supply metadata but have not selected a project.\n Please select a project in Step 2.');
	return 0;
      }
      if ((document.getElementById("sel_md_pill").className == "pill_complete") && (! selected_no_metadata)) {
	alert('WARNING: You have selected more than one sequence file,\nbut you metadata file does not include any library information.\nEither select a single sequence file, or correct your metadata file.');
	return 0;
      }
    } else {
      if (selected_sequence_files.length == selected_libraries.length) {
	var valid = 1;
	var broken = "";
	for (i=0;i<selected_sequence_files.length; i++) {
	  var start = 0;
	  if (selected_sequence_files[i].indexOf('/') > -1) {
	    start = selected_sequence_files[i].lastIndexOf('/') + 1;
	  }
	  var fn = selected_sequence_files[i].substr(start, selected_sequence_files[i].lastIndexOf('.'));
	  var found = 0;
	  for (h=0; h<selected_libraries.length; h++) {
	    if (selected_libraries[h] == fn) {
	      found = 1;
	      break;
	    }
	  }
	  if (! found) {
	    valid = 0;
	    broken = selected_sequence_files[i];
	    break;
	  }
	}
	if (! valid) {
	  alert("WARNING: The libraries in your selected metadata file do\nnot match the selected sequence files, i.e. the sequence\nfile "+broken+" does not have a matching library ("+fn+").\nThe file_name or metagenome_name field in library should match your sequence file name (minus extension if using metagenome_name).\nEither correct your metadata file or change your sequence file selection.");
	  return 0;
	}
      } else if (selected_sequence_files.length < selected_libraries.length) {
	var valid = 1;
	var broken = "";
	for (i=0;i<selected_sequence_files.length; i++) {
	  var start = 0;
	  if (selected_sequence_files[i].indexOf('/') > -1) {
	    start = selected_sequence_files[i].lastIndexOf('/') + 1;
	  }
	  var fn = selected_sequence_files[i].substr(start, selected_sequence_files[i].lastIndexOf('.'));
	  var found = 0;
	  for (h=0; h<selected_libraries.length; h++) {
	    if (selected_libraries[h] == fn) {
	      found = 1;
	      break;
	    }
	  }
	  if (! found) {
	    valid = 0;
	    broken = selected_sequence_files[i];
	    break;
	  }
	}
	if (! valid) {
	  alert("WARNING: The libraries in your selected metadata file do\nnot match the selected sequence files, i.e. the sequence\nfile "+broken+" does not have a matching library.\nEither correct your metadata file or change your sequence file selection.");
	  return 0;
	} else {
	  if (! confirm("WARNING: Your metadata contains more libraries than you have sequence files selected.\nHowever, all selected sequence files have a matching library.\n\nDo you want to continue?")) {
	    return 0;
	  }
	}
      } else {
	alert("WARNING: The number of libraries in your metadata file is less than\nthe number of selected sequence files.\nEither correct your metadata file or change your sequence file selection.");
	return 0;
      }
    }
  } else if (selected_libraries.length > 1) {
    alert("WARNING: You have selected a single sequence file, but specified\nmultiple libraries in your metadata file. Either update your metadata\nfile or select more sequence files.");
    return 0;
  }

  if (has_fasta) {
    document.getElementById('filter_ln').disabled = false;
    document.getElementById('deviation').disabled = false;
    document.getElementById('filter_ambig').disabled = false;
    document.getElementById('max_ambig').disabled = false;
  } else {
    document.getElementById('filter_ln').disabled = true;
    document.getElementById('deviation').disabled = true;
    document.getElementById('filter_ambig').disabled = true;
    document.getElementById('max_ambig').disabled = true;
  }
  if (has_fastq) {
    document.getElementById('dynamic_trim').disabled = false;
    document.getElementById('min_qual').disabled = false;
    document.getElementById('max_lqb').disabled = false;
  } else {
    document.getElementById('dynamic_trim').disabled = true;
    document.getElementById('min_qual').disabled = true;
    document.getElementById('max_lqb').disabled = true;
  }
  var html = "<h4>selected sequence files</h4><br><p>The following "+selected_sequence_files.length+" sequence files have queued for submission:</p><p><i>"+selected_sequence_files.join("</i><br><i>")+"</i><br><br><input type='button' class='btn' value='unselect' onclick='unselect_sequence_file();'><input type='hidden' name='seqfiles' value='"+selected_sequence_files.join("|")+"'>";
  document.getElementById("selected_sequences").innerHTML = html;
  document.getElementById("available_sequences").style.display = 'none';
  document.getElementById("sel_seq_pill").className = "pill_complete";
  document.getElementById("icon_step_3").style.display = "";
  check_submitable();
}

function unselect_sequence_file () {
  document.getElementById('filter_ln').disabled = false;
  document.getElementById('deviation').disabled = false;
  document.getElementById('filter_ambig').disabled = false;
  document.getElementById('max_ambig').disabled = false;
  document.getElementById('dynamic_trim').disabled = false;
  document.getElementById('min_qual').disabled = false;
  document.getElementById('max_lqb').disabled = false;
  
  selected_sequence_file = "";
  document.getElementById("selected_sequences").innerHTML = "";
  document.getElementById("available_sequences").style.display = '';
  document.getElementById("sel_seq_pill").className = "pill_incomplete";
  document.getElementById("icon_step_3").style.display = "none";
  document.getElementById("sel_pip_pill").className = "pill_incomplete";
  document.getElementById("icon_step_4").style.display = "none";
  update_inbox();
  check_submitable();
}

function select_metadata_file () {
  if (document.getElementById('no_metadata').checked) {
    selected_no_metadata = 1;
    document.getElementById("sel_md_pill").className = "pill_complete";
    document.getElementById("icon_step_1").style.display = "";
    check_submitable();
  } else {
    selected_no_metadata = 0;
    var sel = document.getElementById('metadata_file_select');
    selected_metadata_file = sel.options[sel.selectedIndex].value;
    document.getElementById("sel_mdfile_div").innerHTML = "<p><img src='./Html/ajax-loader.gif'> please wait while your metadata file is being validated...</p>";
    
    $.get("?page=Upload&action=validate_metadata&mdfn="+selected_metadata_file, function (data) {
	var result = data.split(/\|\|/);
	if (result[0] != "0") {
	  var html = "<div class='well'><h4>selected metadata file</h4><br>"+result[2]+"<br><p><i>"+selected_metadata_file+"</i><br><br><input type='button' class='btn' value='unselect' onclick='unselect_metadata_file();'><input type='hidden' name='mdfile' value='"+selected_metadata_file+"'></div>";
	  selected_project = result[1]
	  if (result.length == 4) {
	    selected_libraries = result[3].split(/@@/);
	  }
	  update_inbox();
	  document.getElementById("sel_mdfile_div").innerHTML = html;
	  document.getElementById("sel_md_pill").className = "pill_complete";
	  document.getElementById("icon_step_1").style.display = "";
	  
	  var found_selected_project = 0;
	  var projsel = document.getElementById('project');
	  for (i=0;i<projsel.options.length;i++) {
	    if (projsel.options[i].text == selected_project) {
	      projsel.selectedIndex = i;
	      found_selected_project = 1;
	      break;
	    }
	  }
	  if (! found_selected_project) {
	    document.getElementById('project').selectedIndex=0;
	    document.getElementById('new_project').value=selected_project;
	    alert('The project selected in your metadata does not yet exist,\nit will be created upon job submission.');
	  } else {
	    alert('You have selected the existing project\n\n"'+selected_project+'"\n\nfor this upload. The selected jobs will be added to this project.');
	  }
	  document.getElementById("sel_project_pill").className = "pill_complete";
	  document.getElementById("icon_step_2").style.display = "";
	  check_submitable();
	} else {
	    if (result[1] == 'taken') {
		alert(result[2]);
		unselect_metadata_file();
	    } else {
		document.getElementById("sel_mdfile_div").innerHTML = result[2];
		update_inbox();
	    }
	}
      });
  }
}
function unselect_metadata_file () {
  unselect_sequence_file()
  selected_metadata_file = "";
  selected_libraries = [];
  document.getElementById("sel_md_pill").className = "pill_incomplete";
  document.getElementById("icon_step_1").style.display = "none";
  document.getElementById("sel_project_pill").className = "pill_incomplete";
  document.getElementById("icon_step_2").style.display = "none";
  update_inbox();
  check_submitable();
}

function accept_pipeline_options () {
  document.getElementById("sel_pip_pill").className = "pill_complete";
  document.getElementById("icon_step_4").style.display = "";
  toggle("sel_pip_div");
  check_submitable();
}

function check_submitable () {
  if ((document.getElementById("sel_seq_pill").className == "pill_complete") &&
      (document.getElementById("sel_md_pill").className == "pill_complete") &&
      (document.getElementById("sel_project_pill").className == "pill_complete") &&
      (document.getElementById("sel_pip_pill").className == "pill_complete")) {
      document.getElementById("sub_job_pill").className = "pill_complete";
      document.getElementById("submit_job_button").disabled = false;
      document.getElementById("submit_job_button").focus();
      document.getElementById("sub_job_div").style.display = "";
  } else {
      document.getElementById("sub_job_pill").className = "pill_incomplete";
      document.getElementById("submit_job_button").disabled = true;      
  }
}

function submit_job () {
  var seq_files = selected_sequence_files.join('|');
  $.get("?page=Upload&action=check_for_duplicates&seqfiles="+seq_files, function (data) {
      if (data == "unique") {
	  document.forms.submission_form.submit();
      } else {
	  if ( confirm(data) ) {
	      document.forms.submission_form.submit();
	  } else {
	      return false;
	  }
      }
  });
}

function toggle (id) {
  var item = document.getElementById(id);
  if (item.style.display == "none") {
    item.style.display = "";
  } else {
    item.style.display = "none";
  }
}

function check_project () {
  var sel = "";
  if (document.getElementById('project').selectedIndex > 0) {
    sel = "project="+document.getElementById('project').options[document.getElementById('project').selectedIndex].value;
    selected_project = document.getElementById('project').options[document.getElementById('project').selectedIndex].value;
  } else if (document.getElementById('new_project').value.length > 0) {
    sel = "new_project="+document.getElementById('new_project').value;
    selected_project = document.getElementById('new_project').value;
  } else {
    alert("You must either select an existing project from the dropdown menu\nor choose a name in the textbox.");
    return false;
  }
  $.get("?page=Upload&action=check_project_name&"+sel, function (data) {
      if (data == "1") {
	document.getElementById("sel_project_pill").className = "pill_complete";
	document.getElementById("icon_step_2").style.display = "";
	check_submitable();
	update_inbox();
	alert("Project chosen successfully");
      } else {
	selected_project = null;
	alert('You do not have the privileges to add jobs to this project.\nEither pick a different project or ask the owner\nof that project for edit rights.');
      }
    });
}

function change_file_dir () {
  var dlist = DataStore['user_inbox'][user.login].directories;
  var files = [];
  var filebox = document.getElementById('inbox_select');
  for (var i=0; i<filebox.options.length; i++) {
    if (filebox.options[i].selected) {
      files[files.length] = filebox.options[i].value;
    }
  }
  if (files.length) {
    var dn = prompt("Select target directory, choose 'inbox' for top level", last_directory);
    if (dn) {
      if (dn == 'inbox') {
	files.unshift('inbox');
	update_inbox(null, files, 'move');
      } else {
	var existing = 0;
	for (var i=0; i<dlist.length; i++) {
	  if (dlist[i] == dn) {
	    existing = 1;
	    break;
	  }
	}
	if (existing) {
	  files.unshift(dn);
	  update_inbox(null, files, 'move');
	} else {
	  if (! dn.match(/^[\w\d_\.\s]+$/) ) {
	    alert('Directory names may only consist of letters, numbers and the "_" character.');
	    return false;
	  }
	  if (confirm('This directory does not exist. Do you want to create it?')) {
	    files.unshift(dn);
	    update_inbox(null, files, 'move');
	  }
	}
      }
    }
  } else {
    alert("You did not select any files to move.");
  }
}

function generate_webkey (get_new) {
  var get_new_param = "";
  if (get_new) {
    get_new_param = "&generate_new_key=1";
  }
  $.get("?page=Upload&action=generate_webkey"+get_new_param, function (data) {
      document.getElementById('generate_key').innerHTML = data;
    });
}
