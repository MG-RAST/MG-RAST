function info_field (id) {
  var info = document.getElementById('info_'+id);
  var info_button = document.getElementById('info_button_'+id);
  if (info.className == 'info_show') {
    info.className = 'info_hide';
    info_button.className = 'info_button_hide';
  } else {
    info.className = 'info_show';
    info_button.className = 'info_button_show';
  }
}
