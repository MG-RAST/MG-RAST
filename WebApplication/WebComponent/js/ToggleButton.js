function tiggle (index, id, value, action) {

  // get the objects
  var toggle_hidden = document.getElementById('togglevalue_'+id);
  var all_buttons = document.getElementsByName('toggle_'+id);
  var selected_button = document.getElementById('toggle_'+index+'_'+id);
  
  // unselect all buttons
  for (i=0;i<all_buttons.length;i++) {
    all_buttons[i].className = 'toggle_unselected';
  }

  // select selected button
  selected_button.className = 'toggle_selected';

  if (action==undefined) {
    // set the hidden value
    toggle_hidden.value = value;
  } else {
    // if this is an action, execute it
    action(value);
  }

  return;
}
