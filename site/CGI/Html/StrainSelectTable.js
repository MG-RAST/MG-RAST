/* ---------------------------------- */
/*          StrainSelectTable Functions           */
/* ---------------------------------- */
var CheckBoxValues = new Array();
var orderedIntervalIds = new Array();
var orderedIntervalValues = new Array();


function ProcessData (input,column) {
  if (input.match(/CHECKEDBOX:/)) {
	var Index = input.substring(11);
	CheckBoxValues[Index] = 1;
	return '<input type="button" id="CHECKBOX_' + Index +
		'" onClick="javascript: CheckBoxClicked(\''+Index+'\');" value="remove" />';
	}
  if (input.match(/CHECKBOX:/)) {
    var Index = input.substring(9);
    if (CheckBoxValues[Index]==undefined) {
      CheckBoxValues[Index] = 0;
    }
    if (CheckBoxValues[Index] == 0 ) {
      input = '<input type="button" id="CHECKBOX_' + Index +
		'" onClick="javascript: CheckBoxClicked(\''+Index+'\');" value="add" />';
    } else {
      input = '<input type="button" id="CHECKBOX_' + Index +
		'" onClick="javascript: CheckBoxClicked(\''+Index+'\');" value="remove" />';
    }
  }

  if(orderedIntervalIds.length == 0) { setIntervalInfo(); }
  return input;
}

function setIntervalInfo() {
	orderedIntervalIds = document.getElementById('ordered_interval_ids').getAttribute('value').split(',');
	orderedIntervalValues = document.getElementById('ordered_interval_values').getAttribute('value').split(',');
}
function CheckBoxClicked (Index) {
  if (CheckBoxValues[Index] == undefined) {
    CheckBoxValues[Index] = 0;
  }
  var id = 'CHECKBOX_' + Index;
  if (CheckBoxValues[Index] == 0) {
    CheckBoxValues[Index] = 1;
    document.getElementById(id).setAttribute('value', 'remove');
  } else {
    CheckBoxValues[Index] = 0;
    document.getElementById(id).setAttribute('value', 'add');
  }
  UpdateSelected(Index);
}

function UpdateSelected (Index) {
  var SelectedText = '';
  if(orderedIntervalValues[Index] == 1) {
  	orderedIntervalValues[Index] = 0;
  } else {
  	orderedIntervalValues[Index] = 1;
  }
  for (var i = 0; i < orderedIntervalIds.length; i++) {
    if (orderedIntervalValues[i] == 1) {
		SelectedText = SelectedText + IntervalListItem(orderedIntervalIds[i]);	
	}
  }
  document.getElementById('SelectedIntervalList').innerHTML = SelectedText;
}

function IntervalListItem (IntervalId) {
	var output = '<span style="padding-right: 4px;"><a href="seedviewer.cgi?page=IntervalViewer&id=';
	return output = output + IntervalId+'">'+IntervalId+'</a></span>';
}
	

function SubmitStrain () {
  var selectedIntervals = "";
  for (var i=0;i<orderedIntervalIds.length;i++) {
    if (orderedIntervalValues[i] == 1) {
      if (selectedIntervals.length > 0) {
      	selectedIntervals = selectedIntervals + "|";
      }
      selectedIntervals = selectedIntervals + orderedIntervalIds[i];
    }
  }
  document.getElementById('intervals').setAttribute('value', selectedIntervals);
  document.getElementById('straincreateform').submit();
}
