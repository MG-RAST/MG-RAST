/* ---------------------------------- */
/*          ModelSelectTable Functions           */
/* ---------------------------------- */
var CheckBoxValues = new Array();

function ProcessData (input,column) {
  if (input.match(/CHECKBOX:/)) {
    var Index = input.substring(9);
    if (CheckBoxValues.length <= Index) {
      CheckBoxValues[Index] = 0;
    }
    if (CheckBoxValues[Index] == 0) {
      input = '<input type="checkbox" id="CHECKBOX_'+Index+'" onClick="javascript: CheckBoxClicked(\''+Index+'\');">';
    } else {
      input = '<input type="checkbox" id="CHECKBOX_'+Index+'" onClick="javascript: CheckBoxClicked(\''+Index+'\');" checked>';
    }
  }

  return input;
}

function CheckBoxClicked (Index) {
  if (CheckBoxValues.length <= Index) {
    CheckBoxValues[Index] = 0;
  }

  if (CheckBoxValues[Index] == 0) {
    CheckBoxValues[Index] = 1;
  } else {
    CheckBoxValues[Index] = 0;
  }
}

function SubmitModelSelection (ID) {
  var CompareModels = "";
  var ModelArray = new Array();
  ModelArray = document.getElementById('model_list').value.split(/,/);
  for (var i=0;i<CheckBoxValues.length;i++) {
    if (CheckBoxValues[i] == 1) {
      if (CompareModels.length > 0) {
        CompareModels = CompareModels + ",";
      }
      CompareModels = CompareModels + ModelArray[i];
    }
  }
  document.getElementById('model').value = ID;
  document.getElementById('compare').value = CompareModels;
  document.getElementById('modelselectform').submit();
}
