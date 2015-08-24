var api_url = typeof RetinaConfig === "undefined" ? 'http://api.metagenomics.anl.gov/1/metagenome?verbosity=mixs&' : RetinaConfig.mgrast_api + "/metagenome?verbosity=mixs&";
var datastore = {};
var result = 'result'; // div where results are to be displayed
var saved_params = {};
var result_count = 0;
var MAX_LIMIT = 1000000;
var mgs = {};

// THE CODE COMMENTED OUT HERE IS FOR SELECTALL CAPABILITY ON THE MG SEARCH PAGE.  NOT ENABLING THIS FEATURE
// AT THE MOMENT BECAUSE USERS MAY CREATE COLLECTIONS THAT ARE TOO LARGE.  MAY USE CODE IN THE FUTURE.
//
// The variables below (selectAll, selected{}, deselected{}) are used to keep track of which metagenomes
// have been selected for creation of a collection.  There are two possible states:
//
//   1) selectAll has not been performed (or deselectAll HAS been) and selected{} contains the metagenomes
//      that have been manually selected.
//   2) selectAll has been performed and deselected{} contains the metagenomes that have been manually
//      deselected.
//
// This is done rather than querying the API/Solr for all metagenomes returned by the query and storing them
// in a large associative array to save time and disk space.
//
// Each time selectAll or deselectAll is performed, both associative arrays must be emptied.
//
// If selectAll is performed, we'll still have to perform the API query to retrieve all metagenomes, but this
// will postpone the operation to the time of the "create collection" task which will take some time anyway.

// var selectAll = 0;
// var selected = {};
// var deselected = {};

function queryAPI (params) {
    var type = params.type || [ "metadata" ];
    var query = params.query;
    var sort = params.sort || "name";
    var sortDir = params.sortDir || "asc";
    var offset = params.offset || 0;
    var limit = params.limit || 10;

    if (params.result) {
        result = params.result;
    }

    // Save these search params in case user decides to search results by a different column.
    saved_params['type'] = type;
    saved_params['query'] = query;
    saved_params['sort'] = sort;
    saved_params['sortDir'] = sortDir;
    saved_params['offset'] = offset;
    saved_params['limit'] = limit;
    saved_params['result'] = result;

    if (typeof type == "string") {
        type = [ type ];
    }

    if (query === null) {
        console.log('invalid request, missing query parameter');
        return;
    }

    var query_str = "";
    for (h=0;h<type.length; h++) {
        if(query_str == "") {
            query_str = type[h] + "=" + query;
        } else {
            query_str += "&" + type[h] + "=" + query;
        }
    }

    var url = api_url + query_str + "&order=" + sort + "&direction=" + sortDir + "&match=any" + "&limit=" + limit + "&offset=" + offset;
    if (document.getElementById('login_input_box') == null) {
        var wsCookie = getCookie("WebSession");
        if(wsCookie) {
            url += "&auth=" + wsCookie;
        }
    }
    jQuery.getJSON(url, function(data) {
        for (i=0;i<data.data.length;i++) {
            datastore[data.data[i]["id"]] = data.data[i];
        }
        result_count = data.total_count;
        updateResults(offset, limit, sort, sortDir);
    });

    return;
}

//function selectAllMgms () {
//    selectAll = 1;
//    selected = {};
//    deselected = {};
//}

//function deselectAllMgms () {
//    selectAll = 0;
//    selected = {};
//    deselected = {};
//}

function updateSelection (id) {
    if(document.getElementById(id).checked) {
        mgs[id] = 1;
    } else {
        delete mgs[id];
    }
}

function sortQuery (sort, sortDir) {
    queryAPI({type: saved_params['type'], query: saved_params['query'], result: saved_params['result'], sort: sort, sortDir: sortDir});
    return;
}

function firstQuery () {
    queryAPI({type: saved_params['type'], query: saved_params['query'], result: saved_params['result'], sort: saved_params['sort'], sortDir: saved_params['sortDir'], offset: 0, limit: saved_params['limit']});
    return;
}

function prevQuery () {
    var limit = saved_params['limit'];
    var offset = saved_params['offset'] - limit;
    if(offset < 0) {
        offset = 0;
    }
    queryAPI({type: saved_params['type'], query: saved_params['query'], result: saved_params['result'], sort: saved_params['sort'], sortDir: saved_params['sortDir'], offset: offset, limit: limit});
    return;
}

function nextQuery () {
    var limit = saved_params['limit'];
    var offset = saved_params['offset'] + limit;
    if(offset + limit > result_count) {
        offset = result_count - limit;
    }
    queryAPI({type: saved_params['type'], query: saved_params['query'], result: saved_params['result'], sort: saved_params['sort'], sortDir: saved_params['sortDir'], offset: offset, limit: limit});
    return;
}

function lastQuery () {
    var limit = saved_params['limit'];
    var offset = result_count - limit;
    queryAPI({type: saved_params['type'], query: saved_params['query'], result: saved_params['result'], sort: saved_params['sort'], sortDir: saved_params['sortDir'], offset: offset, limit: limit});
    return;
}

function updateResults (offset, limit, sort, sortDir) {
    if(result_count == 0) {
        var target = document.getElementById(result);
        target.innerHTML = "<span style='color:red;font-weight:bold;'>No results were found from your query.</span>";
        datastore = {};
        return;
    }
    var html = "Note: To create a collection, first select the metagenomes in the first column, then click \"create collection\".<br /><br />\n";
    html += "<div id='dResult2'></div><br />\n" +
            "<button onclick=\"execute_ajax('get_mg_col','dResult2','mg_set='+getMgsString());\">create collection</button><br /><br />\n" +
            "<table style=\"width: 100%;\"><tr>" +
            "<td align=\"left\"><a onclick=\"firstQuery();\" style=\"cursor: pointer\">&#171;first</a> " +
                               "<a onclick=\"prevQuery();\" style=\"cursor: pointer\">&#171;prev</a></td>" +
            "<td align=\"center\">Displaying " + (offset + 1) + "-" + Math.min(offset+limit, result_count) + " of " + result_count + " results</td>" +
            "<td align=\"right\"><a onclick=\"nextQuery();\" style=\"cursor: pointer\">next&#187;</a> " +
                                "<a onclick=\"lastQuery();\" style=\"cursor: pointer\">last&#187;</a></td></tr></table><br />\n";
    html += "<table class='table'><tr><th>Select</th>";
    var fields = ["sequence_type", "name", "id", "project_name", "biome", "feature", "material", "country", "location"];
    var fnames = ["Seq&nbsp;Type", "Metagenome", "MG-RAST&nbsp;ID", "Project", "Biome", "Feature", "Material", "Country", "Location"];
    for (i=0;i<fields.length;i++) {
        html += "<th>"+fnames[i]+"<img onclick=\"sortQuery(\'"+fields[i]+"\', \'asc\');\" src=\"./Html/up-arrow.gif\" style=\"cursor: pointer\" />"+
                "<img onclick=\"sortQuery(\'"+fields[i]+"\', \'desc\');\" src=\"./Html/down-arrow.gif\" style=\"cursor: pointer\" />";

        if (sort == fields[i]) {
            if (sortDir == 'asc') {
                html += "<br /><span style=\"font-weight:normal\"><i>(ascending)</i></span>";
            } else {
                html += "<br /><span style=\"font-weight:normal\"><i>(descending)</i></span>";
            }
        }
        html += "</th>";
    }
    html += "</tr>";

    var rows = [];
    for (i in datastore) {
        if (datastore.hasOwnProperty(i)) {
            rows.push( [ datastore[i].id, datastore[i].name ] );
        }
    }
        
    for (i=0;i<rows.length;i++) {
        datastore[rows[i][0]]["project_id"] = datastore[rows[i][0]]["project_id"].substr(3);
        datastore[rows[i][0]]["id"] = datastore[rows[i][0]]["id"].substr(3);

        html += "<tr>";
        if(datastore[rows[i][0]]["id"] in mgs) {
            html += "<td><input id=" + datastore[rows[i][0]]["id"] + " type=\"checkbox\" onclick=\"updateSelection("+datastore[rows[i][0]]["id"]+");\" checked />\n";
        } else {
            html += "<td><input id=" + datastore[rows[i][0]]["id"] + " type=\"checkbox\" onclick=\"updateSelection("+datastore[rows[i][0]]["id"]+");\" />\n";
        }
        html += "<td>"+datastore[rows[i][0]]["sequence_type"]+"</td>";
        html += "<td><a href='?page=MetagenomeOverview&metagenome="+datastore[rows[i][0]]["id"]+"' target=_blank>"+datastore[rows[i][0]]["name"]+"</a></td>";
        html += "<td>"+datastore[rows[i][0]]["id"]+"</td>";
        html += "<td><a href='?page=MetagenomeProject&project="+datastore[rows[i][0]]["project_id"]+"' target=_blank>"+datastore[rows[i][0]]["project_name"]+"</a></td>";
        html += "<td>"+datastore[rows[i][0]]["biome"]+"</td>";
        html += "<td>"+datastore[rows[i][0]]["feature"]+"</td>";
        html += "<td>"+datastore[rows[i][0]]["material"]+"</td>";
        html += "<td>"+datastore[rows[i][0]]["country"]+"</td>";
        html += "<td>"+datastore[rows[i][0]]["location"]+"</td>";
        html += "</tr>";
    }
        
    html += "</table>";
    
    var target = document.getElementById(result);
    target.innerHTML = html;
    
    datastore = {};

    return;
}

function getCookie(c_name) {
    var c_value = document.cookie;
    var c_start = c_value.indexOf(" " + c_name + "=");
    if (c_start == -1) {
        c_start = c_value.indexOf(c_name + "=");
    }

    if (c_start == -1) {
        c_value = null;
    } else {
        c_start = c_value.indexOf("=", c_start) + 1;
        var c_end = c_value.indexOf(";", c_start);
        if (c_end == -1) {
            c_end = c_value.length;
        }
        c_value = unescape(c_value.substring(c_start,c_end));
    }
    return c_value;
}

function getMgsString() {
    var i = 0;
    var str = "";
    for (key in mgs) {
        str += key + "~";
    }
    return str.substring(0, str.length - 1);
}
