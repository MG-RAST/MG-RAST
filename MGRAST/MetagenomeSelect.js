function update_counts (table_id) {
	var table_layout = { 'metagenomes': 1, 'projects' : 2, 'biomes': 4, 'altitudes' : 7, 'depths' : 8, 'locations' : 9, 'ph' : 10, 'countries' : 11, 'temperatures' : 12, 'sequencing_methods' : 13, 'pi' : 14};
	var unique = {};
	var public_only = 0; 
	if (table_filtered_data[table_id][0].length != 18){
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
				unique['mgcounts'][table_filtered_data[table_id][row][15].replace(/(<([^>]+)>)/ig,"")] += parseInt(table_filtered_data[table_id][row][1]);
			} else if (table_filtered_data[table_id][row][15] != undefined) {
				unique['mgcounts'][table_filtered_data[table_id][row][15].replace(/(<([^>]+)>)/ig,"")] += 1;
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
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7");
			pivot_plus(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7", "hash|num|hash|hash|hash|hash|hash", null, ", ");
		}
		update_counts(all_metagenomes_table_id);
	});
	$("#grouping_link").live('click', function () {
		switch_project_grouping();
	});
	$("#ungrouping_link").live('click', function () {
		switch_project_grouping();
	});
	function switch_project_grouping(){
		if (grouped_by_project) {
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6");
			$("#colname_"+all_metagenomes_table_id+"_col_2").html("id");
			$("#ungrouping_link").hide();
			$("#grouping_link").show();
			show_column(all_metagenomes_table_id, "15");
			$("#metagenome_counts").show();
			update_counts(all_metagenomes_table_id);
			grouped_by_project = 0;
		} else {
			clear_pivot(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7");
			pivot_plus(all_metagenomes_table_id, "2", "0|1|3|4|5|6|7", "hash|num|hash|hash|hash|hash|hash", null, ", ");
			$("#colname_"+all_metagenomes_table_id+"_col_2").html("# of jobs");
			show_column(all_metagenomes_table_id, "1");
			hide_column(all_metagenomes_table_id, "15");
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
		var sel = $("#table_"+all_metagenomes_table_id+"_operand_16")['0'];
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
		var sel = $("#table_"+all_metagenomes_table_id+"_operand_16")['0'];
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
    if (table_input_columns_data[data_index][relrow][16] == 1) {
      var newids = table_filtered_data[data_index][i][0].split(", ");
      for (h=0; h<newids.length; h++) {
	ids[ids.length] = newids[h];
      }
    }
  }
  if (ids.length) {
    var collname = prompt("Enter a name for this collection", "Collection 1");
    execute_ajax("change_collection", "ajax_return", "newcollection="+collname+"&ids="+ids.join("|"));
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
    if (table_input_columns_data[data_index][i][4] == 1) {
      ids[ids.length] = table_data[data_index][i][0] + "^" + table_data[data_index][i][1];
    }
  }
  if (ids.length) {
    if (confirm('do you really want to delete the selected entries?')) {
      execute_ajax("change_collection", "ajax_return", "remove_entries=1&ids="+ids.join("|"));
    }
  } else {
    alert('you did not select any entries');
  }
}

function update_collection_data (id) {
  document.getElementById("user_collections_count").innerHTML = document.getElementById('new_collection_num').value;
  var data_index;
  for (i=0;i<table_list.length;i++) {
    if (id == table_list[i]) {
      data_index = i;
    }
  }

  var newrows = document.getElementById('new_collection_data').value.split("|");
  var newdata = new Array();
  for (i=0;i<newrows.length;i++) {
    newdata[i] = newrows[i].split("^");
    newdata[i][newdata[i].length] = 0;
    newdata[i][newdata[i].length] = i;
  }

  table_data[data_index] = newdata;
  reload_table(id);
  table_reset_filters(id);
}
