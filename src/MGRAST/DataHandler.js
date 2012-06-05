// global variables
var DataStore;
var TypeData;
var CallbackList;
var DataRepositories;
var DataRepositoriesCount;
var DataRepositoryDefault;

// set up / reset the DataHandler, adding initial repositories
function initialize_data_storage (repositories) {
  DataStore = [];
  TypeData = [];
  TypeData['types'] = [];
  TypeData['type_count'] = 0;
  CallbackList = [];
  DataRepositories = [];
  DataRepositoriesCount = 0;
  DataRepositoryDefault = null;

  if (repositories) {
    for (var i=0; i<repositories.length; i++) {
      DataRepositories[repositories[i].id] = repositories[i];
      DataRepositoriesCount++;
      if (DataRepositoriesCount == 1) {
	DataRepositoryDefault = DataRepositories[repositories[i].id];
      }
    }
  }
}

// generic data loader
// given a DOM id, interprets the innerHTML of the element as JSON data and loads it into the DataStore
// given a JSON data structure, loads it into the DataStore
function load_data (id_or_data, no_clear) {
  var new_data;
  if (typeof(id_or_data) == 'string') {
    var elem = document.getElementById(id);
    if (elem) {
      new_data = JSON.parse(elem.innerHTML);
      if (! no_clear) {
	document.getElementById(id).innerHTML = "";
      }
    }
  } else {
    new_data = id_or_data;
  }
  
  if (new_data.length) {
    for (var i=0; i<new_data.length; i++) {
      if (new_data[i].type) {
	var type = new_data[i].type;
	if (! TypeData['types'][type]) {
	  DataStore[type] = [];
	  TypeData['type_count']++;
	  TypeData['types'][type] = 0;
	  if (new_data[i].type_description) {
	    TypeData['type_description'][type] = new_data[i].type_description;
	  }
	}
	for (var h=0; h<new_data[i].data.length; h++) {
	  if (! DataStore[type][new_data[i].data[h].id]) {
	    TypeData['types'][type]++;
	  }
	  DataStore[type][new_data[i].data[h].id] = new_data[i].data[h];
	}
      }
    }
  }
}

// adds / replaces a repository in the DataRepositories list
function add_repository (repository) {
  if (repository && repository.id) {
    DataRepositories[repository.id] = repository;
    DataRepositoriesCount++;
    if (repository.default) {
      DataRepositoryDefault = DataRepositories[repository.id];
    }
  }
}

// removes a repository from the DataRepositories list
function remove_repository (id) {
  if (id && DataRepositories[id]) {
    DataRepositories[id] = null;
    DataRepositoriesCount--;
    if (DataRepositoryCount == 1) {
      for (var i in DataRepositories) {
	DataRepositoryDefault = DataRepositories[i];
      }
    }
  }
}

// sets the default repository
function default_repository (id) {
  if (id && DataRepositories[id]) {
    DataRepositoryDefault = DataRepositories[id];
  }
}

// event handler for an input type file element, which interprets the selected file(s)
// as JSON data and loads them into the DataStore
function dh_file_upload (evt, callback_function, callback_parameters) {
  var files = evt.target.files;
  
  if (files.length) {
    for (var i=0; i<files.length; i++) {
      var f = files[i];
      var reader = new FileReader();
      reader.onload = (function(theFile) {
	  return function(e) {
	    var new_data = JSON.parse(e.target.result);
	    load_data(new_data);
	    callback_function.call(null, callback_parameters);
	  };
	})(f);
      reader.readAsText(f);
    }
  }
}

// client side data requestor
// initiates data retrieval from a resource, saving callback functions / paramters
function get_objects (type, resource_params, callback_func, callback_params) {
  if (! CallbackList[type]) {
    CallbackList[type] = [ [ callback_func, callback_params ] ];
    get_objects_from_repository(type, resource_params);
  } else {
    CallbackList[type][CallbackList[type].length] = [ callback_func, callback_params ];
  }
  return 0;
}

// data retrieval function triggered by get_objects
// queries the default DataRepository if none is defined in resource_params
// sets requested query and REST parameters as well as authentication and initiates the asynchronous call
function get_objects_from_repository (type, resource_params) {
  var rest_params = "";
  var query_params = "?callback=1";
  var base_url = DataRepositoryDefault.url;
  var authentication = "";
  if (DataRepositoryDefault.authentication) {
    authentication = "&" + DataRepositoryDefault.authentication;
  }

  if (resource_params) {
    if (resource_params.data_repository && DataRepositories[resource_params.data_repository]) {
      base_url = DataRepositories[resource_params.data_repository].url;
      if (DataRepositories[resource_params.data_repository].authentication) {
	authentication = "&" + DataRepositories[resource_params.data_repository].authentication;
      } else {
	authentication = "";
      }
    }
    if (resource_params.rest) {
      rest_params += resource_params.rest.join("/");
    }
    if (resource_params && resource_params.query) {
      for (var i=0; i<resource_params.query.length - 1; i++) {
	query_params += "&" + resource_params.query[i] + "=" + resource_params.query[i+1];
      }
    }
  }

  base_url += type + "/" + rest_params + query_params + authentication;

  var script = document.createElement('script');
  script.setAttribute('type', 'text/javascript');
  script.setAttribute('src', base_url);
  script.setAttribute('id', 'callback_script_'+type)
  document.getElementsByTagName('head')[0].appendChild(script);
}

// called by the returned data from a get_objects_from_repository call
// loads the returned data into the DataStore, deletes the sent data from the DOM
// and initiates all callback functions for the type
function data_return (type, new_data) {
  var old_script = document.getElementById('callback_script_'+type);
  document.getElementsByTagName('head')[0].removeChild(old_script);
  load_data([ { 'type': type, 'data': new_data } ]);
  dh_callback(type);
}

// executes the callback functions for a given type
function dh_callback (type) {
  type = type.toLowerCase();
  for (var c=0;c<CallbackList[type].length;c++) {
    CallbackList[type][c][0].call(null, CallbackList[type][c][1], type);
  }
  CallbackList[type] = null;
}

// deletes an object from the DataStore
function delete_object (type, id) {
  type = type.toLowerCase();
  if (DataStore[type][id]) {
    DataStore[type][id] = null;
    TypeData['types'][type]--;
    if (TypeData['types'][type] == 0) {
      delete_object_type(type);
    }
  }
}

// deletes a set of objects from the DataStore
function delete_objects (type, ids) {
  type = type.toLowerCase();
  for (var i=0; i<ids.length; i++) {
    delete_object(type, ids[i]);
  }
}

// deletes an entire type from the DataStore
function delete_object_type (type) {
  type = type.toLowerCase();
  if (TypeData['types'][type]) {
    TypeData['types'][type] = null;
    TypeData['type_count']--;
    DataStore[type] = null;
  }
}
