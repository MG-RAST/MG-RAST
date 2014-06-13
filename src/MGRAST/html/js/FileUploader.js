var fu_curr_files;
var fu_curr_file = 0;
var fu_curr_offset = 0;
var fu_md5s = [];
var fu_curr_size;
var fu_total_size;
var fu_total_uploaded = 0;
const BYTES_PER_CHUNK = 1024 * 1024; // 1MB chunk sizes.
var incomplete_files = [];
var pending_uploads = [];
var chunk_multiplier = 1;

function init_uploader () {
  document.querySelector("#file_upload").addEventListener('change', function(e) {
      fu_curr_files = this.files;
      start_upload();
    }, false);
}

function start_upload () {
  if (fu_curr_files) {
    if (fu_curr_files.length > fu_curr_file) {
      
      var blob = fu_curr_files[fu_curr_file];
      const SIZE = blob.size;
      if (SIZE > 1024 * 1024 * 100) {
	chunk_multiplier = 10;
      } else {
	chunk_multiplier = 1;
      }
      fu_curr_size = blob.size;
      fu_total_size = 0;
      for (var i=0; i<fu_curr_files.length; i++) {
	fu_total_size += fu_curr_files[i].size;
      }
      
      var start = fu_curr_offset;
      if (incomplete_files[blob.name]) {
	alert("partial upload of file '"+blob.name+"' detected, resuming upload.");
	start = incomplete_files[blob.name];
	incomplete_files[blob.name] = null;
      }
      var end = start + (BYTES_PER_CHUNK * chunk_multiplier);
      var chunk;
      document.getElementById('progress_display').style.display = "";

      if (start < SIZE) {
	  var blobSlice = File.prototype.slice || File.prototype.mozSlice || File.prototype.webkitSlice;
	  chunk = blobSlice.call(blob, start, end);
	  	
	document.getElementById("upload_progress").style.display = "";
	document.querySelector("#upload_status").innerHTML = "<b>current file</b> " + blob.name + "<br><b>file</b> " + (fu_curr_file+1) + " of " + fu_curr_files.length + "<br><b>size</b> " + pretty_size(blob.size) + "<br><b>type</b> " + pretty_type(blob.type);
	fu_curr_offset = end;
	upload(chunk, blob.name);
      } else {
	var cfiles = document.getElementById("uploaded_files");
	cfiles.style.display = "";
	if (fu_curr_file == 0) {
	  cfiles.innerHTML = "<h4>completed files</h4>";
	}
	cfiles.innerHTML += "<p>"+blob.name+" ("+pretty_size(blob.size)+") <i class='icon-ok'></i></p>";

	fu_total_uploaded += fu_curr_files[fu_curr_file].size;
	fu_curr_file++;
	fu_curr_offset = 0;
	update_inbox(null, null, "upload_complete");
	start_upload();
      }
    } else {
      var cfiles = document.getElementById("uploaded_files");
      cfiles.style.display = "";
      if (fu_curr_file == 0) {
	cfiles.innerHTML = "<h4>completed files</h4>";
      }
      cfiles.innerHTML += "<p>upload complete</p>";
      document.getElementById('progress_display').style.display = "none";

      fu_curr_files = null;
      fu_curr_file = 0;
      fu_curr_offset = 0;
      fu_total_uploaded = 0;
      document.querySelector("#prog1").value = 100;
      document.querySelector("#prog2").value = 100;
    }
  }
}

function upload(blobOrFile, fn) {
  var xhr = new XMLHttpRequest();
  xhr.open('POST', "upload.cgi", true);
  xhr.onload = function(e) {
    if (this.status == 200) {
      console.log(this.response);
    }
  };
  var progressBar1 = document.querySelector("#prog1");
  var progressBar2 = document.querySelector("#prog2");
  xhr.upload.onprogress = function(e) {
    if (e.lengthComputable) {
      progressBar1.value = ((e.loaded + fu_curr_offset + fu_total_uploaded - (BYTES_PER_CHUNK * chunk_multiplier)) / fu_total_size) * 100;
      progressBar2.value = ((e.loaded + fu_curr_offset - (BYTES_PER_CHUNK * chunk_multiplier)) / fu_curr_size) * 100;
    }
  };
  xhr.addEventListener("load", uploadComplete, false);
  xhr.addEventListener("error", uploadFailed, false);
  xhr.addEventListener("abort", uploadCanceled, false);

  var fd = new FormData();
  fd.append("upload_file", blobOrFile);
  fd.append('filename', fn);
  fd.append('auth', auth);
  if (fu_curr_offset >= fu_curr_size) {
    fd.append('last_chunk', 1);
  }
 
  xhr.send(fd);
  pending_uploads[pending_uploads.length] = xhr;
}

function cancel_upload () {
  if (confirm('Do you really want to cancel the current upload?')) {
    for (var i=0; i<pending_uploads.length; i++) {
      pending_uploads[i].abort();
    }
    fu_curr_files = null;
    fu_curr_file = 0;
    fu_curr_offset = 0;
    fu_total_uploaded = 0;
  }
}

function uploadComplete (evt) {
    var md5 = this.responseText;
    if (md5 != 'chunk received') {
	fu_md5s[fu_curr_file] = md5;
	if (fu_curr_files.length == (fu_curr_file + 1)) {
	    var old = document.getElementById("md5check");
	    if (old) {
		jQuery('#md5check').remove();
	    }
	    var msg = document.createElement('div');
	    msg.setAttribute('id', 'md5_check');
	    var msg_html = '\
<div id="md5check" class="modal hide fade" tabindex="-1" role="dialog" aria-labelledby="md5checklabel" aria-hidden="true">\
<div class="modal-header">\
<button type="button" class="close" data-dismiss="modal" aria-hidden="true">x</button>\
<h1 id="md5checklabel">md5 check</h1>\
</div>\
<div class="modal-body">\
<p>To check the integrity of your uploaded files, paste their md5 sum into the boxes below and click <b>\'check\'</b>.</p>';
	    for (i=0;i<fu_curr_files.length;i++) {
		msg_html += '<b>'+fu_curr_files[i].name+'</b><br>';
		msg_html += '<input type="text" style="width: 230px;" id="usermd5'+i+'"><input type="text" disabled value="'+fu_md5s[i]+'" style="width:230px;"><button class="btn" onclick="checkmd5(this, \''+i+'\');">check</button><br>';
	    }
	    msg_html += '</div>\
<div class="modal-footer">\
<button class="btn" data-dismiss="modal" aria-hidden="true">Close</button>\
</div>\
</div>';
	    msg.innerHTML = msg_html;
	    document.body.appendChild(msg);
	    jQuery('#md5check').modal('show');
	}
    }
    start_upload();
}

function checkmd5 (button, which) {
    if (fu_md5s[which] == document.getElementById("usermd5"+which).value) {
	alert('MD5 sums match');
	button.setAttribute('class', 'btn btn-success');
    } else {
	alert('WARNING: md5sum does not match, the upload is probably corrupted!');
	button.setAttribute('class', 'btn btn-danger');
    }
}

function uploadFailed (evt) {
  document.querySelector("#upload_status").innerHTML = "the upload has failed";
}

function uploadCanceled (evt) {
  document.querySelector("#upload_status").innerHTML = "the upload was canceled";
}

function pretty_size (size) {
  var magnitude = "B";
  if (size > 1024) {
    size = size / 1024;
    magnitude = "KB"
  }
  if (size > 1024) {
    size = size / 1024;
    magnitude = "MB";
  }
  if (size > 1024) {
    size = size / 1024;
    magnitude = "GB";
  }
  size = size.toFixed(1);
  size = addCommas(size);
  size = size + " " + magnitude;

  return size;
}

function pretty_type (type) {
  return type;
}

function addCommas(nStr)
{
	nStr += '';
	x = nStr.split('.');
	x1 = x[0];
	x2 = x.length > 1 ? '.' + x[1] : '';
	var rgx = /(\d+)(\d{3})/;
	while (rgx.test(x1)) {
		x1 = x1.replace(rgx, '$1' + ',' + '$2');
	}
	return x1 + x2;
}
