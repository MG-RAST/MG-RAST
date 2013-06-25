var api_url = 'http://dunkirk.mcs.anl.gov/~jbischof/mgrast/api2.cgi/search/metagenome?';
var datastore = {};
var result = 'result';
var update = 1;

function queryAPI (params) {
    var type = params.type || "metadata";
    var query = params.query;
    if (params.result) {
	result = params.result;
    }

    if (query === null) {
	console.log('invalid request, missing query parameter');
	return;
    }

    var url = api_url + type + "=" + query + "&limit=100";

    jQuery.getJSON(url, function(data) {
	for (i=0;i<data.data.length;i++) {
	    datastore[data.data[i]["id"]] = data.data[i];
	}
	if (update<1) {
	    update++;
	}
	updateResults();
    });
}

function searchAll (term) {
    update = -2;
    queryAPI({"type": "metadata", "query": term});
    queryAPI({"type": "function", "query": term});
    queryAPI({"type": "organism", "query": term});
}

function clearSearch () {
    datastore = {};
}

function updateResults () {

    if (update < 1) {
	return;
    }

    var html = "<table class='table'><tr><th>Job</th><th>Metagenome</th><th>MG-RAST ID</th><th>biome</th><th>feature</th><th>material</th><th>country</th><th>location</th><th>PI</th></tr>";
    var rows = [];
    for (i in datastore) {
	if (datastore.hasOwnProperty(i)) {
	    rows.push( [ datastore[i].id, datastore[i].name ] );
	}
    }

    rows.sort(sortByName);

    for (i=0;i<rows.length;i++) {
	html += "<tr>";
	html += "<td>"+datastore[rows[i][0]]["job"]+"</td>";
	html += "<td><a href='?page=MetagenomeOverview&metagenome="+datastore[rows[i][0]]["id"]+"'>"+datastore[rows[i][0]]["name"]+"</a></td>";
	html += "<td>"+datastore[rows[i][0]]["id"]+"</td>";
	html += "<td><a href='?page=MetagenomeProject&project="+datastore[rows[i][0]]["project_id"]+"'>"+datastore[rows[i][0]]["project_name"]+"</a></td>";
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

    clearSearch();

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