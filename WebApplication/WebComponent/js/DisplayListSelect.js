// Javascript functions for the DisplayListSelect component which will add or delete columns from a table at this point

function moveOptionsRight(theSelFrom, theSelTo, tableID, ajax_function)
{
  var myBox1 = document.getElementById(theSelFrom);
  var myBox2 = document.getElementById(theSelTo);

  //alert ('START' + values[0]);
  //alert (labels[0]);
  //alert (filtered_labels);
  var selLength = myBox1.length;
  var selectedText = new Array();
  var selectedValues = new Array();
  var selectedCount = 0;
  if (document.getElementById('filter_select_1000') == null){
    var old_values = values[0];
    var old_labels = labels[0];
  }
  var i;

  // Find the selected Options in reverse order
  // and delete them from the 'from' Select.
  for(i=selLength-1; i>=0; i--)
  {
    if(myBox1.options[i].selected)
    {
      selectedText[selectedCount] = myBox1.options[i].text;
      selectedValues[selectedCount] = myBox1.options[i].value;

      // Change the hidden object status for that column to visible
      var hidden_column_id = 'column~' + myBox1.options[i].value;
      var hidden_column_obj = document.getElementById(hidden_column_id);
      hidden_column_obj.value=1;

      // if the box is a filter_select_box then remove the elements from the hidden fields of the filter
      if (document.getElementById('filter_select_values_0') != null){
         var labels_string = document.getElementById('filter_select_labels_0').value;
         var values_string = document.getElementById('filter_select_values_0').value;
         labels_string = labels_string.replace(/#/g, "'");
         values_string = values_string.replace(/#/g, "'");
         var labels_values = labels_string.split(/~/);
         var values_values = values_string.split(/~/);
         var new_values = new Array();
         var new_labels = new Array();
         var count =0;
         for (var h=0;h<old_values.length;h++){
           if (old_values[h] != myBox1.options[i].value){
             new_values[count]=old_values[h];
             new_labels[count]=old_labels[h];
             count++;
           }
         }
//         document.getElementById('filter_select_values_0').value = new_values.join('~');
//         document.getElementById('filter_select_labels_0').value = new_labels.join('~');
         values[0] = new_values;
         labels[0] = new_labels;
      }

      deleteOption(myBox1, i, selectedValues[selectedCount]);
 
      selectedCount++;
      //alert ('end ' + values[0]);
      //alert (labels[0]);
    }
  }

  // Add the selected text/values in reverse order.
  // This will add the Options to the 'to' Select
  // in the same order as they were in the 'from' Select.
  for(i=selectedCount-1; i>=0; i--)
  {
    if ( (tableID != null) && (ajax_function != null) ){
       addOption(myBox2, selectedText[i], selectedValues[i], tableID, ajax_function);
    }
    else {
       addOption(myBox2, selectedText[i], selectedValues[i]);
    }
  }

  SelectSort(myBox1);
  SelectSort(myBox2);
}

function deleteOption(theSel, theIndex, theValue)
{
  var selLength = theSel.length;
  if(selLength>0)
  {
    theSel.options[theIndex] = null;
  }
}


function deleteOptionLeft(theSel, theIndex, theValue, tableID)
{
  var selLength = theSel.length;
  if(selLength>0)
  {
      theSel.options[theIndex] = null;
      if (tableID != null){
        var myColumn = document.getElementById('col_id~' + theValue).value;
        setTimeout(function(){hide_column(tableID, myColumn);}, 100);
      }
  }
}

function addOption(theSel, theText, theValue, tableID, ajax_function)
{
  var newOpt = new Option(theText, theValue);
  var selLength = theSel.length;
  theSel.options[selLength] = newOpt;

  if (tableID != null){
    var field = document.getElementById('col_id~' + theValue);
    var col_id = field.value;

    if (col_id >= 0) {
      setTimeout(function(){show_column(tableID, col_id);}, 100);
    }
    else {
      var ids = document.getElementById('primary_ids').value;
      var ajax_target = 'table_' + tableID + '_ajax_target';
//      document.body.style.cursor = "wait";
      execute_ajax(ajax_function, ajax_target, 'colName=' + theValue + '&primary_ids=' + ids);
//      execute_ajax(ajax_function, ajax_target, 'colName=' + theValue + '&primary_ids=' + ids, 'processing table ...', 0, 'reset_cursor()');
//      alert ('hello. look at cursor');
//      document.body.style.cursor = "default";
    }
  }
}

function reset_cursor () {
   document.body.style.cursor = "default";
}

function changeHiddenField (table_id,colName){
  var col_count =  document.getElementById('table_'+ table_id).rows[0].childNodes.length;
  document.getElementById('col_id~' + colName).value = col_count;
  document.getElementById(table_id + '_column_qty').value = Math.abs(col_count) + Math.abs(1);
//  reset_cursor();
}

function moveOptionsLeft(theSelFrom, theSelTo, tableID)
{
  var myBox1 = document.getElementById(theSelFrom);
  var myBox2 = document.getElementById(theSelTo);

  var selLength = myBox1.length;
  var selectedText = new Array();
  var selectedValues = new Array();
  var selectedCount = 0;

  var i;

  // Find the selected Options in reverse order
  // and delete them from the 'from' Select.
  for(i=selLength-1; i>=0; i--)
  {
    if(myBox1.options[i].selected)
    {
      selectedText[selectedCount] = myBox1.options[i].text;
      selectedValues[selectedCount] = myBox1.options[i].value;

      // Change the hidden object status for that column to visible
      var hidden_column_id = 'column~' + myBox1.options[i].value;
      var hidden_column_obj = document.getElementById(hidden_column_id);
      hidden_column_obj.value=0;

      if (document.getElementById('filter_select_values_0')){
	     //document.getElementById('filter_select_values_0').value += '~' + myBox1.options[i].value;
         //document.getElementById('filter_select_labels_0').value += '~' + myBox1.options[i].text;
      }
	  
      // delete the column from the "to add" list
      if (tableID != null){
        deleteOptionLeft(myBox1, i, selectedValues[selectedCount], tableID);
      }
      else {
        deleteOptionLeft(myBox1, i, selectedValues[selectedCount]);
      }
      selectedCount++;
    }
  }

  // Add the selected text/values in reverse order.
  // This will add the Options to the 'to' Select
  // in the same order as they were in the 'from' Select.
  for(i=selectedCount-1; i>=0; i--)
  {
    addOptionLeft(myBox2, selectedText[i], selectedValues[i]);
  }

  SelectSort(myBox1);
  SelectSort(myBox2);
}

function addOptionLeft(theSel, theText, theValue)
{
  var newOpt = new Option(theText, theValue);
  var selLength = theSel.length;
  theSel.options[selLength] = newOpt;
}

function SelectSort(SelList)
{
    var ID='';
    var Text='';
    for (x=0; x < SelList.length - 1; x++)
    {
     	for (y=x + 1; y < SelList.length; y++)
        {
            if (SelList[x].text > SelList[y].text)
            {
                // Swap rows
                ID=SelList[x].value;
                Text=SelList[x].text;
                SelList[x].value=SelList[y].value;
                SelList[x].text=SelList[y].text;
                SelList[y].value=ID;
                SelList[y].text=Text;
            }
        }
    }
}

// function for the hover effects on the buttons
function hov(loc,cls){
   if(loc.className)
      loc.className=cls;
}


// function that sets an initial empty box to the size of the filled box
function setBoxWidth(box1,box2){
   document.getElementById(filter_select_1).width = document.getElementById(filter_select_0).width;
   alert (document.getElementById(box2).width);
}