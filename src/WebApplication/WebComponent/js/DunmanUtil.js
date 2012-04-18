var checkedExperiments = new Array();
var currCount = new Array();
currCount[1] = 1;
currCount[2] = 1;


function setChecked (checkbox) {
   if (checkedExperiments.length <= 1) {
      checkedExperiments.push(checkbox.value);
   } else {
      checkedExperiments.shift();
      checkedExperiments.push(checkbox.value);
   }
} 


function setForm () {
    if (checkedExperiments.length != 2) {
        alert("You must select two expriments to run the analysis against.");
        return;
    }
    var exp1 = checkedExperiments.shift();
    var exp2 = checkedExperiments.shift();
    window.location.href = "seedviewer.cgi?page=UploadMicroarray&exp1="+exp1+"&exp2="+exp2;
}

function addAnotherUpload (num) {
    currCount[num]++;
    $('#rep'+num+' table').append("<tr><td>CHP File "+currCount[num]+":</td><td><input type='file' name='upload_"+num+"_"+currCount[num]+"'></td></tr>");
}
$(document).ready( function () {  
    $('#UploadForm').submit(function () {
        currCount[1] = 0;
        $('#rep1 table tr').each( function(index) {
            currCount[1]++;
            });
        currCount[1]--; // for the name field
        $('#rep1Count').attr('value', currCount[1]);
        currCount[2] = 0;
        $('#rep2 table tr').each( function(index) {
            currCount[2]++;
            });
        currCount[2]--; // for the name field
        $('#rep2Count').attr('value', currCount[2]);
        return true;
    });
});
