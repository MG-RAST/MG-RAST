// search the linked component of the venn diagram to show the filtered data

function search_linked_component (event, filter, table_id, column_id, max_col) {
  //alert(column_id);
  //table_reset_filters(table_id);

  clear_table_filters(0,max_col);
  //document.getElementById(column_id).value = "";
  //table_filter(table_id);
  document.getElementById(column_id).value = filter;
  table_filter(table_id);
}

function clear_table_filters(id,max){
   for (var i=1;i<=max;i++){
       var filter = document.getElementById('table_' + id + '_operand_' + i);
       filter.text = 'all';
       filter.selectedIndex = 0;
       filter.value = '';
   }
   check_submit_filter2("0");
}

function filter_metagenome_table (menu_id, table_id, data_columns,add_block,start_col){
  var selectgroup = document.getElementById(menu_id);
  var col_id = selectgroup.value;

  table_reset_filters(table_id);

  if (col_id.indexOf('_U_') >= 0){
    var numcols = parseInt(document.getElementById('table_cols_' + table_id).value);
    for (var i=start_col;i<=numcols;i+=add_block){
      var operator = document.getElementById('table_' + table_id + '_operator_' + i);
      var operand =  document.getElementById('table_' + table_id + '_operand_' + i);

      operator.value = 'unequal';
      operand.value = -1;
    }
    table_filter(table_id);

  }
  else if (col_id.indexOf('Unique to ') >= 0){
    var splitarray = col_id.split(' ');
    var len = splitarray.length;
    var numcols = parseInt(document.getElementById('table_cols_' + table_id).value);

    //for (var i=numcols-data_columns+1;i<=numcols;++i){
    for (var i=start_col;i<=numcols;i+=add_block){
      var operator = document.getElementById('table_' + table_id + '_operator_' + i);
      var operand =  document.getElementById('table_' + table_id + '_operand_' + i);

      if ( (col_id.indexOf(' ' + i + ' ') < 0 ) && (col_id.indexOf(' ' + i) < 0) ){
        operator.value = 'equal';
        operand.value = 0;
      }
    }
    table_filter(table_id);

  }
  else if (col_id.indexOf('_I_') >= 0){
    var splitarray = col_id.split('_I_');
    var len = splitarray.length;
    
    for (var i=0,len; i<len; ++i ){
      var operator = 'table_' + table_id + '_operator_' + splitarray[i];
      var operand =  'table_' + table_id + '_operand_' + splitarray[i];
      document.getElementById(operator).value = 'more';
      document.getElementById(operator).selectedIndex = 1;
      document.getElementById(operand).value = '0';
    }
    table_filter(table_id);

  }
  else{
    var operator = 'table_' + table_id + '_operator_' + col_id;
    var operand =  'table_' + table_id + '_operand_' + col_id;
    document.getElementById(operator).selectedIndex = 1;
    document.getElementById(operator).value = 'more';
    document.getElementById(operand).value = '0';

    table_filter(table_id);
  }

//  table_filter(table_id);
}