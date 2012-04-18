/* ---------------------------------- */
/*          ModelTable Functions           */
/* ---------------------------------- */

var ColumnNames = new Array();
var SelectedModels = "";
var selected_organism = "";

function ModelProcessData (input,column,ID) {
  var ColumnNameInput = document.getElementById(ID+'_column_names');
  if (!ColumnNameInput) {
    return input;
  }

  //Initializing the column names data
  if (ID >= ColumnNames.length) {
    for (i=0; i <= ID; i++) {
      ColumnNames[i] = new Array();
    }
  }
  if (ColumnNames[ID].length == 0) {
    ColumnNames[ID] = document.getElementById(ID+'_column_names').value.split(/,/);
  }
  //Initializing the selected model list
  if (SelectedModels.length == 0 && document.getElementById('selected_models')) {
    SelectedModels = document.getElementById('selected_models').value;
  }
  //Initializing the selected organism
  if (selected_organism.length == 0 && document.getElementById('selected_organism')) {
    selected_organism = document.getElementById('selected_organism').value;
  }

  if (ColumnNames[ID][column] == "Compound") {
    if (SelectedModels == "NONE") {
      return '<a style="text-decoration:none" href="?page=CompoundViewer&compound=' + input + '" target="_blank">' + input + "</a>";
    } else {
      return '<a style="text-decoration:none" href="?page=CompoundViewer&compound=' + input + '&model=' + SelectedModels + '" target="_blank">' + input + "</a>";
    }
  } else if (ColumnNames[ID][column] == "KEGG CID") {
    return KEGGCompoundLinks(input);
  } else if (ColumnNames[ID][column] == "Reaction") {
    if (SelectedModels == "NONE") {
      return '<a style="text-decoration:none" href="?page=ReactionViewer&reaction=' + input + '" target="_blank">' + input + "</a>";
    } else {
      return '<a style="text-decoration:none" href="?page=ReactionViewer&reaction=' + input + '&model=' + SelectedModels + '" target="_blank">' + input + "</a>";
    }
  } else if (ColumnNames[ID][column] == "Enzyme") {
    return ECLinks(input);
  } else if (ColumnNames[ID][column] == "KEGG RID") {
    return KEGGReactionLinks(input);
  } else if (ColumnNames[ID][column] == "Equation") {
    return EquationLinks(input);
  } else if (ColumnNames[ID][column] == "Subsystems") {
    return SubsystemLinks(input);
  }

  return input;
}

function ECLinks(inputdata) {
	if (inputdata == "Undetermined") {
		return inputdata;
	}
	var ID_List = new Array();
	ID_List = inputdata.split(/,/);
	var output = "";
	for (i=0;i<ID_List.length;i++) {
		if (i > 0) {
			output = output + "<br>";
		}
		output = output + '<a style="text-decoration:none" href="http://www.genome.jp/dbget-bin/www_bget?enzyme+' + ID_List[i] + '" target="_blank">' + ID_List[i] + "</a>";
	}
	return output;
}

function KEGGReactionLinks(inputdata) {
	if (inputdata == "None") {
    	return inputdata;
	}  
  var ID_List = new Array();
  ID_List = inputdata.split(/,/);
  var output = "";
  for (i=0;i<ID_List.length;i++) {
    if (i > 0) {
      output = output + "<br>";
    }
    output = output + '<a style="text-decoration:none" href="http://www.genome.jp/dbget-bin/www_bget?rn+' + ID_List[i] + '" target="_blank">' + ID_List[i] + "</a>";
  }
  return output;
}

function EquationLinks(inputdata) {
    var ID_List = new Array();
    ID_List = inputdata.split(/\|/);
    var output = "";
    for (i=0;i<ID_List.length;i++) {
      output = output + ID_List[i];
      i++;
      if (i<ID_List.length) {
        if (SelectedModels == "NONE") {
          output = output + '<a style="text-decoration:none" href="?page=CompoundViewer&compound=' + ID_List[i] + '" target="_blank">' + ID_List[i] + "</a>";
        } else {
          output = output + '<a style="text-decoration:none" href="?page=CompoundViewer&compound=' + ID_List[i] + '&model=' + SelectedModels + '" target="_blank">' + ID_List[i] + "</a>";
        }
      }
    }
    return output;
}

function SubsystemLinks(inputdata) {
    if (inputdata == "None") {
    	return inputdata;
	}
    var re = new RegExp("_", "g");
    var ID_List = new Array();
    ID_List = inputdata.split(/\|/);
    var output = "";
    for (i=0;i<ID_List.length;i++) {
      if (i > 0) {
        output = output + "<br><br>";
      }
      var NeatSubsystem = ID_List[i].replace(re, " ");
      ID_List[i] = ID_List[i].replace(/\([\d\/]+\)$/,"");

      output = output + '<a style="text-decoration:none" href="seedviewer.cgi?page=Subsystems&subsystem=' + ID_List[i];
      if (selected_organism != 'none') {
        output = output + '&organism=' + selected_organism;
      }
      output = output + '" target="_blank">' + NeatSubsystem + "</a>";
    }
    return output;
}

function KEGGCompoundLinks(inputdata) {
  var ID_List = new Array();
  ID_List = inputdata.split(/,/);
  var output = "";
  for (i=0;i<ID_List.length;i++) {
    if (i > 0) {
      output = output + "<br>";
    }
    output = output + '<a style="text-decoration:none" href="http://www.genome.jp/dbget-bin/www_bget?cpd:' + ID_List[i] + '" target="_blank">' + ID_List[i] + "</a>";
  }
  return output;
}
