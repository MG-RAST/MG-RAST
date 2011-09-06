function switch_form(control_form) {
    var advanced_table=document.getElementById("region_display_advanced");
    if (control_form == "regular") {
	advanced_table.style.display="none";
    } else {
	advanced_table.style.display="inline";
    }
}

function all_or_nothing(which) {
  var check = 0;
  if (which.value == 'uncheck all') {
    which.value = 'check all';
  } else {
    which.value = 'uncheck all';
    check = 1;
  }
  for (i=0;i<1000;i++) {
    var box = document.getElementById('feature'+i);
    if (box) {
      box.checked = check;
    } else {
      break;
    }
  }
}

function show_selected_genomes(id) {
  var list = document.getElementById('list_select_list_b_'+id).options;
  var html = "";
  for (i=0;i<list.length;i++) {
    html += "<input type='hidden' name='show_genome' value='" + list[i].value + "'>";
  }
  document.getElementById('pr_genome_sel').innerHTML = html;
  document.getElementById('draw_button').onclick();
}
