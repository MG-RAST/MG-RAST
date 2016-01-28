function update_counts (table_id) {
  for (i=0;i<table_list.length;i++) {
    if (table_id == table_list[i]) {
      table_id = i;
      break;
    }
  }

	var table_layout = { 'metagenomes': 1, 'projects' : 2, 'biomes': 6, 'features': 7, 'materials': 8, 'altitudes' : 11, 'depths' : 12, 'locations' : 13, 'phs' : 14, 'countries' : 15, 'temperatures' : 16, 'pis' : 18};
	var unique = {};
	var public_only = 0; 
	if (table_filtered_data[table_id][0].length != 25){
		public_only = 1; 
	} 
	unique['mgcounts'] = {};
	unique['mgcounts']['public'] = 0;
	unique['mgcounts']['shared'] = 0;
	unique['mgcounts']['private'] = 0;	
	for (var row in table_filtered_data[table_id]) {
		for (var key in table_layout){
			var tmp = table_filtered_data[table_id][row][table_layout[key]];
			if (key == 'public' && typeof tmp == 'string'){
				tmp = tmp.replace(/(<([^>]+)>)/ig,"");
			}
			if (!unique[key]){
				unique[key] = {};
			}
			if (tmp) {
				var values = tmp.split(', ')
				for(t in values){
					if (values[t] != " "){
						if (!unique[key][values[t]]){
							unique[key][values[t]] = 1;						
						} else {
							unique[key][values[t]]++;
						}
					}
				}
			}
		}
		if (!public_only){
			if ($("#ungrouping_link").is(":visible")){
				unique['mgcounts'][table_filtered_data[table_id][row][22].replace(/(<([^>]+)>)/ig,"")] += parseInt(table_filtered_data[table_id][row][1]);
			} else if (table_filtered_data[table_id][row][22] != undefined) {
				unique['mgcounts'][table_filtered_data[table_id][row][22].replace(/(<([^>]+)>)/ig,"")] += 1;
			}
		}
	}
	for (var key in unique){
		if (key == 'mgcounts'){
			$("#table_counts_public").html(unique[key]['public']);
			$("#table_counts_private").html(unique[key]['private']);
			$("#table_counts_shared").html(unique[key]['shared']);
		} else if (key == 'metagenomes'){
			if (public_only){
				var c = 0;
				for (var i in unique[key]){
					c++;
				}
				$("#table_counts_"+key).html(c);
			} else {
				$("#table_counts_metagenomes").html(unique['mgcounts']['shared'] + unique['mgcounts']['private'] + unique['mgcounts']['public']);
			}
		} else {
			var c = 0;
			for (var i in unique[key]){
				c++;
			}
			$("#table_counts_"+key).html(c);			
		}
	} 
}

$(document).ready( function() {
	var current_visible = '#all_metagenomes';
	var back_to_all = '<a style="cursor:pointer" id="back_to_all_metagenomes">back to all metagenomes</a>';
	var all_metagenomes_table_id = 0;
	var reid = /table_(\d+)_operand_(\d+)/;
	var grouped_by_project = 0;
	
	/*setTimeout(function() {
		update_counts(all_metagenomes_table_id);
	}, 100);*/
	
	$("input[class='filter_item']").live('keypress', function (e) {
		if (e.which == 13){	
			var table_id = reid.exec(e.target.id)[1];
			if (table_id == all_metagenomes_table_id){
				update_counts(table_id);
			}
		}
	});
	$("select[class='filter_item']").live('change', function (e) {
		var table_id = reid.exec(e.target.id)[1];
		if (table_id == all_metagenomes_table_id){
			update_counts(table_id);
		}
	});

	$("#clear_table").live('click', function () {
		table_reset_filters(all_metagenomes_table_id);
		if ($("#ungrouping_link").is(":visible")){
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7|8|10");
			pivot_plus(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7|8|10", "hash|num|hash|sum|sum|hash|hash|hash|hash", null, ", ");
		}
		update_counts(all_metagenomes_table_id);
	});
        $("#export_table").live('click', function () {
	        // pass: id, unfiltered, strip_html, hide_invisible_columns
	        export_table(all_metagenomes_table_id, 0, 1, 1);
        });

	$("#grouping_link").live('click', function () {
		switch_project_grouping();
		table_reset_filters(all_metagenomes_table_id);
	});
	$("#ungrouping_link").live('click', function () {
		switch_project_grouping();
		table_reset_filters(all_metagenomes_table_id);
	});
	function switch_project_grouping(){
		if (grouped_by_project) {
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7|8|10");
			$("#colname_"+all_metagenomes_table_id+"_col_2").html("id");
			$("#ungrouping_link").hide();
			$("#grouping_link").show();
			show_column(all_metagenomes_table_id, "22");
			$("#metagenome_counts").show();
			update_counts(all_metagenomes_table_id);
			grouped_by_project = 0;
		} else {
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7|8|10");
			pivot_plus(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7|8|10", "hash|num|hash|sum|sum|hash|hash|hash|hash", null, ", ");
			$("#colname_"+all_metagenomes_table_id+"_col_2").html("# of jobs");
			show_column(all_metagenomes_table_id, "1");
			hide_column(all_metagenomes_table_id, "22");
			$("#grouping_link").hide();
			$("#ungrouping_link").show();
			$("#metagenome_counts").hide();
			update_counts(all_metagenomes_table_id);
			grouped_by_project = 1;
		}
	}
	$("#user_complete_count").live('click', function () {
		if (grouped_by_project){
			switch_project_grouping();
		}
		table_reset_filters(all_metagenomes_table_id);
		if (current_visible != '#all_metagenomes'){
			update_title('All Metagenomes');
			update_link('');
			switch_to('#all_metagenomes');
		}
		var sel = $("#table_"+all_metagenomes_table_id+"_operand_24")['0'];
		for (var opt in sel.options){
			if (sel.options[opt].text = 'private'){
				sel.selectedIndex = opt;
				sel.value = 'private';
				break;
			}
		}
		check_submit_filter2(all_metagenomes_table_id, 'private');
		update_counts(all_metagenomes_table_id);
	});
	$("#user_in_progress_count").live('click', function () {
		update_title('Your Data (In Progress)');
		update_link(back_to_all);
		switch_to('#user_in_progress');
	});
	$("#user_shared_count").live('click', function () {
		if (grouped_by_project){
			switch_project_grouping();
		}
		table_reset_filters(all_metagenomes_table_id);
		if (current_visible != '#all_metagenomes'){
			update_title('All Metagenomes');
			update_link('');
			switch_to('#all_metagenomes');
		}
		var sel = $("#table_"+all_metagenomes_table_id+"_operand_24")['0'];
		for (var opt in sel.options){
			if (sel.options[opt].text = 'shared'){
				sel.selectedIndex = opt;
				sel.value = 'shared';
				break;
			}
		}
		check_submit_filter2(all_metagenomes_table_id, 'shared');
		update_counts(all_metagenomes_table_id);
	});
        $("#user_public_count").live('click', function () {
		if (grouped_by_project){
			switch_project_grouping();
		}
		table_reset_filters(all_metagenomes_table_id);
		if (current_visible != '#all_metagenomes'){
			update_title('All Metagenomes');
			update_link('');
			switch_to('#all_metagenomes');
		}
		var sel = $("#table_"+all_metagenomes_table_id+"_operand_24")['0'];
		for (var opt in sel.options){
			if (sel.options[opt].text = 'public'){
				sel.selectedIndex = opt;
				sel.value = 'public';
				break;
			}
		}
		check_submit_filter2(all_metagenomes_table_id, 'public');
		update_counts(all_metagenomes_table_id);
	});
	$("#user_collections_count").live('click', function () {
		update_title('Your Collections');
		update_link(back_to_all);
		switch_to('#user_collections');
	});
	$("#user_projects_count").live('click', function () {
		update_title('Your Projects');
		update_link(back_to_all);
		switch_to('#user_projects');
	});
	$("#back_to_all_metagenomes").live('click', function () {
		update_title('All Metagenomes');
		update_link('');
		switch_to('#all_metagenomes');
	});
	function switch_to(new_visible){
		$(current_visible).hide();
		$(new_visible).show();
		current_visible = new_visible;
	}
	function update_title(new_title){
	  if ((new_title=='All Metagenomes') || (new_title=='Public Metagenomes')) {
	    document.getElementById('group_link_div').style.display="";
	  } else {
	    document.getElementById('group_link_div').style.display="none";
	  }
		$('#title_bar').html(new_title);
	}
	function update_link(new_link){
		$('#title_bar_link').html(new_link);
	}
});

function add_to_collection (id) {
  var ids = new Array();
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  for (i=0; i<table_filtered_data[data_index].length; i++) {
    var relrow = table_filtered_data[data_index][i][table_filtered_data[data_index][i].length - 1];
    if (table_input_columns_data[data_index][relrow][24] == 1) {
      var newids = table_filtered_data[data_index][i][0].split(", ");
      for (h=0; h<newids.length; h++) {
	ids[ids.length] = newids[h];
      }
    }
  }
  if (ids.length) {
    var collname = prompt("Enter a name for this collection.\nIf you enter the name of an existing\ncollection, the selected metagenomes\nwill be added to it.", "Collection 1");
    execute_ajax("change_collection", "collection_target", "newcollection="+collname+"&ids="+ids.join("|"));
  } else {
    alert('you did not select any metagenomes');
  }
}

function remove_from_collection (id) {
  var ids = new Array();
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }
  for (i=0; i<table_input_columns_data[data_index].length; i++) {
    if (table_input_columns_data[data_index][i][2] == 1) {
      ids[ids.length] = table_data[data_index][i][0];
    }
  }
  if (ids.length) {
    if (confirm('do you really want to delete the selected entries?')) {
      execute_ajax("change_collection", "collection_target", "remove_entries=1&ids="+ids.join("|"));
    }
  } else {
    alert('you did not select any entries');
  }
}

function remove_single (id) {
  if (confirm('do you really want to delete this entry?')) {
    execute_ajax("change_collection", "collection_target", "remove_entries=1&ids="+id);
  }
}

function rename_collection () {
  var newname = document.getElementById('newname').value;
  var oldname = document.getElementById('user_collection_detail_name').innerHTML;
  if (newname) {
    document.getElementById('newname_div').style.display = 'none';
    document.getElementById('newname').value = '';
    execute_ajax("change_collection", "collection_target", "oldname="+oldname+"&newname="+newname);
  }
}

function share_collection (id, cname) {
  if (confirm("To share a collection you need to convert it\ninto a project. You can then share the project\nwith other users.\n\nDo you want to do this now?")) {
    var data_string = document.getElementById('collection_detail_data_'+id).value;
    var row_array = data_string.split("^^");
    var mgs = [];
    for (i=0;i<row_array.length;i++) {
      row_array[i].match(/\((\d+\.\d+)\)/);
      mgs[mgs.length] = RegExp.$1;
    }
    window.top.location = "?page=MetagenomeProject&from_collection=1&action=create&pname="+cname+"&metagenomes="+mgs.join(",");
  }
}

function update_collection_data (id) {
  document.getElementById("user_collections_count").innerHTML = document.getElementById('new_collection_num').value;
  document.getElementById('user_collection_details').style.display = 'none';
  document.getElementById('ajax_return').innerHTML = document.getElementById('return_message').value;

  var newrows = document.getElementById('new_collection_data').value.replace(/@1/g, "'").split("|");
  var newdata = new Array();
  for (i=0;i<newrows.length;i++) {
    newdata[i] = newrows[i].split("^");
    newdata[i][newdata[i].length] = i;
  }

  initialize_table(id, newdata);
}

function show_collection_detail (id, tid, cname) {
  var data_string = document.getElementById('collection_detail_data_'+id).value;
  var row_array = data_string.split("^^");
  var data = [];
  for (i=0;i<row_array.length;i++) {
    row_array[i] = row_array[i].replace(/@1/g, '"'); 
    row_array[i] = row_array[i].replace(/@2/g, "'");
    data[data.length] = row_array[i].split("~~");
  }
  
  document.getElementById('user_collection_detail_name').innerHTML = cname;
  document.getElementById('user_collection_details').style.display = "";
  initialize_table(tid, data);
}
