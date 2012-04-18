/* ------- Update and submit functions for ModelView ------- */
var modelIds = new Array();

function initializePage() {
	var modelList = document.getElementById('model').value;
	modelIds = modelList.split(",");
}

function addModelParam (model) {
    // If no model param is currently set, set it
    if( document.getElementById('model').value == "" ) {
        document.getElementById('model').value = model;
    }// Otherwise append it
    else {
        document.getElementById('model').value += ","+model;
    }
    //parse out extra commas
    document.getElementById('model').value = document.getElementById('model').value.replace( /,,/g, ',' );
    //alert( document.getElementById('model').value );
    document.getElementById('select_models').submit();
}

function removeModelParam (model) {
    // match the model and a trailing comma (if there is one)
    var re = new RegExp( model + ',{0,1}' );
    //replace it
    document.getElementById('model').value = document.getElementById('model').value.replace( re, '' );
    //alert( document.getElementById('model').value );
    document.getElementById('select_models').submit();
}

function removeAllModels () {
    document.getElementById('model').value = "";
    document.getElementById('select_models').submit();
}

function submit_build_control (model_id) {
	var model_class = document.getElementById(model_id+'_cellWallSelect').value;
	execute_ajax("model_admin","0_content_3","build="+model_id+":"+model_class,"Rebuilding model and adjusting cell wall as needed...",0,"post_hook","");
}

function submit_autocompletion_control (model_id) {
	var acMedia = document.getElementById(model_id+'_acMediaSelect').value;
	execute_ajax("model_admin","0_content_3","gapfill="+model_id+":"+acMedia,"Rerunning autocompletion and adjusting autocompletion media as needed...",0,"post_hook","");
}

function submit_reconstruction () {
    var TargetGenome = document.getElementsByName('select_genome_for_reconstruction')[0].value;
    alert("Submitting job to reconstruct new genome-scale metabolic model for genome "+TargetGenome+".");
    tab_view_select(0,2);
    execute_ajax("user_models","0_content_2","recongenome="+TargetGenome,"Submitting new reconstruction job...",0,"post_hook","");
    execute_ajax("reconstruction_page","0_content_1","recongenome="+TargetGenome,"Submitting new reconstruction job...",0,"post_hook","");
}

function select_model (input) {
	var NewModel;
	if (input.substr(0,6) == "select") {
		NewModel = document.getElementsByName(input)[0].value;
	} else {
		if (input.length > 0) {
			NewModel = input;
		} else {
			NewModel = document.getElementById('filter_select_1').value;
		}
	}
	if (document.getElementById('model').value == "") {
		document.getElementById('model').value = NewModel;
	} else {
		document.getElementById('model').value = document.getElementById('model').value + "," + NewModel;
	}
	document.getElementById('select_models').submit();
}

function filter_model_reactions (id) {
  var table = document.getElementById('table_'+id);
  var cells = table.tBodies[0].rows[0].cells;

  for (var i=0; i<cells.length; i++) {
    if (cells[i].getElementsByTagName('span')[0].childNodes[0].nodeValue == 'Models') {
      if (document.getElementById('filterReactions_'+id).checked) {
        document.getElementById('table_'+id+'_operand_'+(i+1)).value = '';
      } else {
        document.getElementById('table_'+id+'_operand_'+(i+1)).value = 'none';
      }
      break;
    }
  }

  table_filter(id);
}

function addReactionToModel(reaction, model) {
  customAlert('add_alert');

  document.getElementById('add_rxn_span').innerHTML = reaction;
  document.getElementById('add_rxn_reaction').value = reaction;
  document.getElementById('add_model_span').innerHTML = model;
  document.getElementById('add_rxn_model').value = model;
}

function removeReactionFromModel(reaction, model) {
  customAlert('remove_alert');

  document.getElementById('remove_rxn_span').innerHTML = reaction;
  document.getElementById('remove_rxn_reaction').value = reaction;
  document.getElementById('remove_model_span').innerHTML = model;
  document.getElementById('remove_rxn_model').value = model;
}