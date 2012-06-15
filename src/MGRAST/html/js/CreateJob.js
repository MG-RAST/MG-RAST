function uploaderFileStatusChanged( uploader, file ) {
   var status = file.getStatus();
   
   if (status == 1) {
     execute_ajax("upload_page", "upload_result", "a=b");
   }

   if (status == 2) {
     execute_ajax("upload_page", "upload_result", "a=b");
   }
}

function reload_this() {
  execute_ajax("upload_page", "upload_result", "a=b")
}
