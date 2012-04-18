// Move a column from the fromBox to the toBox. If the type is "in" and
// there is a linked table component, the column will be shown; otherwise
// it will be hidden. Note that at the current time the user can only
// shift one column at a time.
function moveColumn(type, fromBox, toBox, linkedComponent, ajaxFunction, inFieldName,
                    selfID) {
  // Get the actual FROM and TO boxes.
  var fromSelect = document.getElementById(fromBox);
  var toSelect = document.getElementById(toBox);
  // Remember which one is the IN box.
  var inSelect = (type == 'in' ? toSelect : fromSelect);
  // Find the selected item.
  var selectedFromIdx = -1;
  for (var i = 0; selectedFromIdx < 0 && i < fromSelect.options.length; i++) {
    if (fromSelect.options[i].selected) {
      selectedFromIdx = i;
    }
  }
  // Only proceed if an item is selected.
  if (selectedFromIdx >= 0) {
    var selectedFrom = fromSelect.options[selectedFromIdx];
    var selectedColName = selectedFrom.value;
    // Move the selected item to the TO box.
    toSelect.options[toSelect.options.length] = selectedFrom;
    // Are we tracking the set of selected columns in a form field?
    if (inFieldName != '') {
      // Yes. Rebuild the form field. First we find it.
      var inField = document.getElementById(inFieldName);
      // Now create an array of selected things.
      var inSelected = new Array();
      for (var i = 0; i < inSelect.options.length; i++) {
        selected.push(inSelect.options[i].value);
      }
      // Join the array and put it in the field.
      inField.value = inSelected.join("~");
    }
    // Are we linked to a table?
    if (linkedComponent != '') {
      // Yes. Get the layout list.
      var layoutListField = document.getElementById("layout" + linkedComponent);
      var layout = layoutListField.value.split('~');
      // Try to find our column in the layout.
      var selectedColIdx = layout.indexOf(selectedColName);
      if (selectedColIdx >= 0) {
        // Life is easy. All we need to do is flip a bit.
        if (type == 'in') {
          setTimeout(function() { show_column(linkedComponent, selectedColIdx) }, 100);
        } else {
          setTimeout(function() { hide_column(linkedComponent, selectedColIdx) }, 100);
        }
      } else if (type == 'in' && ajaxFunction != '') {
        // Here we need to load the column using Ajax. First, add it to the layout.
        layout.push(selectedColName);
        layoutListField.value = layout.join('~');
        // Call the ajax function to load it.
        var rowKeyList = document.getElementById('rowKeyList' + selfID).value;
        var parmCache = document.getElementById('parmCache' + selfID).value;
        var ajaxTarget = 'table_' + linkedComponent + '_ajax_target';
        execute_ajax(ajaxFunction, ajaxTarget, 'colName=' + selectedColName +
                     ';rowKeyList=' + rowKeyList + ';parmCache=' + parmCache +
                     ';linkedComponent=' + linkedComponent);
      }
    }
  }
}