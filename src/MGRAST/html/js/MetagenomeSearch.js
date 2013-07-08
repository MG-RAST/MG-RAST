var api_url = 'http://dunkirk.mcs.anl.gov/~jbischof/mgrast/api2.cgi/search/metagenome?';
var datastore = {};
var result = 'result';
var promises = 0;

function queryAPI (params) {
    var type = params.type || [ "metadata" ];
    var query = params.query;
    if (params.result) {
	result = params.result;
    }
    var limit = params.limit || 100;

    if (typeof type == "string") {
	type = [ type ];
    }

    if (query === null) {
	console.log('invalid request, missing query parameter');
	return;
    }

    var promises = type.length;
    for (h=0;h<type.length; h++) {
	var url = api_url + type[h] + "=" + query + "&limit=" + limit;
	jQuery.getJSON(url, function(data) {
	    for (i=0;i<data.data.length;i++) {
		datastore[data.data[i]["id"]] = data.data[i];
	    }
	    promises--;
	    updateResults;
	});
    }

    return;
}

function updateResults () {

    if (promises == 0) {

	var html = "<table class='table'><tr><th>Job</th><th>Metagenome</th><th>MG-RAST ID</th><th>Project</th><th>biome</th><th>feature</th><th>material</th><th>country</th><th>location</th><th>PI</th></tr>";
	var rows = [];
	for (i in datastore) {
	    if (datastore.hasOwnProperty(i)) {
		rows.push( [ datastore[i].id, datastore[i].name ] );
	    }
	}
	
	rows.sort(sortByName);
	
	for (i=0;i<rows.length;i++) {
	    datastore[rows[i][0]]["project_id"] = datastore[rows[i][0]]["project_id"].substr(3);
	    datastore[rows[i][0]]["id"] = datastore[rows[i][0]]["id"].substr(3);
	    
	    html += "<tr>";
	    html += "<td>"+datastore[rows[i][0]]["job"]+"</td>";
	    html += "<td><a href='?page=MetagenomeOverview&metagenome="+datastore[rows[i][0]]["id"]+"' target=_blank>"+datastore[rows[i][0]]["name"]+"</a></td>";
	    html += "<td>"+datastore[rows[i][0]]["id"]+"</td>";
	    html += "<td><a href='?page=MetagenomeProject&project="+datastore[rows[i][0]]["project_id"]+"' target=_blank>"+datastore[rows[i][0]]["project_name"]+"</a></td>";
	    html += "<td>"+datastore[rows[i][0]]["biome"]+"</td>";
	    html += "<td>"+datastore[rows[i][0]]["feature"]+"</td>";
	    html += "<td>"+datastore[rows[i][0]]["material"]+"</td>";
	    html += "<td>"+datastore[rows[i][0]]["country"]+"</td>";
	    html += "<td>"+datastore[rows[i][0]]["location"]+"</td>";
	    html += "<td>"+datastore[rows[i][0]]["PI_lastname"]+"</td>";
	    html += "</tr>";
	}
	
	html += "</table>";
	
	var target = document.getElementById(result);
	target.innerHTML = html;
	
	datastore = {};
    }

    return;
}

function sortByName (a, b) {
    if (a[1]<b[1]) {
	return 1;
    } else if (a[1]>b[1]) {
	return -1;
    } else {
	return 0;
    }
}