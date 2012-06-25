package resources::dataflow;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "dataflow provider",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/json" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  my @flows = ('abundance_profile', 'table_group');
  my $flow_hash = { 'abundance_profile' => qq~{ "current_step": 0,
                                                "description": "transforms an abundance profile in .biom format into a plain table grouped at the phylum level",
                                                "parameter_list": [ "metagenome", "visible_columns", "group_functions", "matrix_id" ],
                                                "parameter_examples": { "metagenome": [ "mgm4440026.3" ],
                                                                        "visible_columns": [0,0,1,0,0,0,0,0,0,1],
                                                                        "group_functions": [ "x", "sum" ],
                                                                        "matrix_id": "example_profile1" },
                                                "params": {},
                                                "internal_params": { "0": { "input_ids":       "metagenome" },
                                                                     "4": { "result_columns":  "visible_columns",
                                                                          "group_functions": "group_functions",
                                                                          "id":              "matrix_id" },
                                                                     "5": { "input_id":        "matrix_id" }},
                              	                "steps": [
  { "action": "get", "resource": "abundance_profile", "input_data_resource": "MG-RAST" },
  { "action": "merge", "resource": "abundance_profile", "data": "data", "subselect": "[0]", "merge_on": "rows[i].id", "name": "matrix", "input_ids": 0, "id": "flow_test", "merge_type": "append_column" },
  { "action": "merge", "resource": "abundance_profile", "data": "rows", "subselect": ".metadata.taxonomy", "merge_on": "rows[i].id", "name": "hash", "id": "flow_test", "input_ids": 0, "merge_type": "single_column" },
  { "action": "merge", "resource_b": "matrix", "resource_a": "hash", "input_ids": { "a": "flow_test", "b": "flow_test" }, "merge_type": "join", "merge_on_a": "i", "merge_on_b": "[0]", "name": "matrix", "id": "flow_test_result" },
  { "action": "group", "resource": "matrix", "input_id": "flow_test_result", "group_column": 2, "result_columns": [0,0,1,0,0,0,0,0,0,1], "group_functions": [ "x", "sum" ], "name": "matrix" }
                                                         ]
}~,
		    'table_group' => qq~{ "current_step": 0,
                                          "description": "groups a table by a defined column",
                                          "parameter_list": [ "input_matrix_id",
                                                              "output_matrix_id",
                                                              "visible_columns",
                                                              "group_column" ],
                                          "parameter_examples": { "input_matrix_id": "flow_test_result",
                                                                  "output_matrix_id": "example2",
                                                                  "visible_columns": [0,1,1,1,1,1,0,0,0,0],
                                                                  "group_column": 5 },
                                          "params": {},
                                          "internal_params": { "0": { "input_id": "input_matrix_id",
                                                                      "result_columns": "visible_columns",
                                                                      "group_column": "group_column",
                                                                      "id": "output_matrix_id" } },
                                          "steps": [
  { "action": "group", "resource": "matrix", "input_id": "flow_test_result", "group_column": 5, "result_columns": [0,1,1,1,1,1,0,0,0,0], "group_functions": [ "x", "x", "x", "x", "x" ], "name": "matrix", "id": "example2" }
                                                   ]
}~
};

# { "action": "prepend_data", "resource": "matrix" },
  
  if ($rest && scalar(@$rest)) {
    if ($flow_hash->{$rest->[0]}) {
      print $cgi->header(-type => 'application/json',
			 -status => 200,
			 -Access_Control_Allow_Origin => '*' );
      print $flow_hash->{$rest->[0]};
      exit 0;
    } else {
      print $cgi->header(-type => 'text/plain',
			 -status => 400,
			 -Access_Control_Allow_Origin => '*' );
      print "ERROR: invalid dataflow requested";
      exit 0;
    }
  }
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  
  print $json->encode( \@flows );
  exit 0;
}

sub TO_JSON { return { %{ shift() } }; }

1;
