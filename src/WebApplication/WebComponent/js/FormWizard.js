function check_mandatory (id, step_nr) {

  var hiddens = document.getElementsByName('mandatory_hiddens_'+step_nr+'_'+id);
  for (i=0; i<hiddens.length; i++) {

    var name = hiddens[i].value.split(/\|/)[0]; 
    var title = hiddens[i].value.split(/\|/)[1];
    var elem = document.getElementsByName(name)[0];

      if (! elem) {
	 elem = document.getElementsByName("selectall_" + name)[0];
      }
      

    var val = 0;
    if (elem.type == 'select-one') {
      val = elem.options[elem.selectedIndex].value.length;
    } else if (elem.type == 'text') {
      val = elem.value.length;
    } else if (elem.type == 'select-many') {
      if (elem.selectedIndex > -1) {
	val = 1;
      }
    } else if (elem.type == 'select-multiple') {
      if (elem.selectedIndex > -1) {
	val = 1;
      }
    } else if (elem.type =='hidden') {
      val = elem.value.length ; 
    } else {
      alert( "Can't check " + title + ", don't recognize " + elem.type );
    }
    if (! val) {
      elem.focus();
      alert('You need to enter a value for "'+title + '".');
      return false;
    }
  }
  return true;
}

function validate_time (field) {
  field.value.toLowerCase();
  field.value = field.value.replace(/\s/g, "");
  field.value = field.value.replace(/\./g, ":");
  field.value = field.value.replace(/,/g, ":");
  if (field.value.match(/^\d\:/)) {
      field.value = "0" + field.value;
  }
  if (field.value.match(/^\d\d\:\d\d$/)) {
    field.value += ":00";
  }
}

function enable_subtab (inp, id, tab, num) {
  var tds = document.getElementsByName(inp.name);
  for (i=0; i< tds.length; i++) {
    document.getElementById(id+'_subtab_'+tab+'_'+i).onclick = '';
  }
  document.getElementById(id+'_subtab_'+tab+'_'+num).onclick = 'tab_view_select("'+id+'", "'+tab+'", "sub", "'+num+'");';
  tab_view_select(id, tab, "sub", num);
}



function switch_category_display ( MENU) {
  
  var menu      = document.getElementById(MENU);
  var selection = menu.options[menu.options.selectedIndex].value;
  var old_selection = document.getElementById( 'current_selection_' + MENU ).value ;


  var new_div = document.getElementById( "div_sub_" + selection );
  var old_div = document.getElementById( "div_sub_" + old_selection );

  document.getElementById( 'current_selection_' + MENU ).value = selection ;
    if ( new_div ) {
	new_div.style.display="inline";
    }
    if ( old_div ) {
	old_div.style.display="none";
    }
}

function CheckInput () {
    alert("Checking input!");
  for (i = 0; i < document.forms[0].elements.length; ++i)
    if (document.forms[0].elements[i].type == "select-multiple") {
      alert( document.forms[0].elements[i].value + " = " + document.forms[0].elements[i].value );
      document.forms[0].elements[i].focus();
      return false;
    }
  return true;
}

