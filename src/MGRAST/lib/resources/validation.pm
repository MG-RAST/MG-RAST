package resources::validation;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);
use JSON;

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "validation";
    $self->{md_node} = $Conf::mgrast_md_node_id || "";
    $self->{md_template} = $Conf::mgrast_md_template_node_id || "";
    $self->{attributes} = { "template" => { "valid" => [ 'boolean', "boolean indicating whether the examined template is valid or not" ],
					    "error" => [ 'array', [ "string", "array of invalid entries" ] ] },
			    "data" => { "valid" => [ 'boolean', "boolean indicating whether the examined template is valid or not" ],
					"error" => [ 'array', [ "string", "array of invalid entries" ] ] }
    	                  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "validates templates for correct structure and data to fit a valid template",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options' => {},
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "template",
				      'request'     => $self->cgi->url."/".$self->name."/template/{ID}",				      
				      'description' => "Checks if the referenced JSON structure is a valid template",
				      'example'     => [ $self->cgi->url."/".$self->name."/template/".$self->{md_template},
				                         'validate the communities metagenomics template' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes->{template},
				      'parameters'  => { 'options'     => {},
							 'required'    => { "id" => [ "string", "SHOCK template id" ] },
							 'body'        => {} } },
				    { 'name'        => "data",
				      'request'     => $self->cgi->url."/".$self->name."/data/{ID}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->cgi->url."/".$self->name."/data/".$self->{md_node}."?template=".$self->{md_template},
  				                         'validate a JSON data structure against the MG-RAST metagenome metadata template' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes->{data},
				      'parameters'  => { 'options'     => { 'template' => [ 'string', "SHOCK template id, default is MG-RAST metagenome metadata template" ] },
							 'required'    => { "id" => [ "string", "SHOCK data id" ] },
							 'body'        => {} } },
				  ]
		  };
    
    $self->return_data($content);
}


# Override parent request function
sub request {
    my ($self) = @_;
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
      $self->info();
    } elsif (($self->rest->[0] eq 'template')  && (scalar(@{$self->rest}) == 2)) {
      $self->template($self->rest->[1]);
    } elsif (($self->rest->[0] eq 'data')  && (scalar(@{$self->rest}) == 2)) {
      $self->data($self->rest->[1], $self->cgi->param('template'));
    } elsif ($self->rest->[0] eq 'mgrast_template') {
      $self->reformat_template();
    } else {
      $self->info();
    }
}

sub template {
  my ($self, $id) = @_;

  # get the shock template node attributes
  my $node = $self->get_shock_node($id, $self->{token});
  my $attributes = $node->{attributes};
  unless($attributes) {
    $attributes = {};
  }

  # get the shock template file
  my ($template_str, $err) = $self->get_shock_file($id, undef, $self->{token});
  if ($err) {
      $self->return_data( {"ERROR" => $err}, 500 );
  }
  my $json = JSON->new->allow_nonref;
  my $template = $json->decode($template_str);
  
  my $template_status = { "valid" => 1,
			  "error" => [] };	
  
  if (! exists $template->{name}) {
    push(@{$template_status->{error}}, 'template name missing');
  } else {
    if (ref $template->{'name'}) {
      push(@{$template_status->{error}}, 'template name is not a string');
    } else {
      if (! exists $template->{'label'}) {
	$template->{'label'} = $template->{'name'};
      }
    }
  }
  
  if (! exists $template->{'description'}) {
    $template->{'description'} = "";
  } elsif (ref $template->{'description'}) {
    push(@{$template_status->{error}}, 'template description is not a string');
  }
  
  if (! exists $template->{'cvs'} ) {
    $template->{'cvs'} = {};
  } else {
    if (ref $template->{'cvs'} ne 'HASH') {
      push(@{$template_status->{error}}, 'template cvs is not an object');
    } else {
      foreach my $cv (keys(%{$template->{'cvs'}})) {
	if (! ref $template->{'cvs'}->{$cv} eq 'HASH') {
	  push(@{$template_status->{error}}, 'the cv '.$cv.' is not an object');
	}
      }
    }
  }
  
  if (! exists $template->{'groups'}) {
    if (! exists $template->{'fields'}) {
      push(@{$template_status->{error}}, 'template has neither groups nor fields');
    } else {
      if (ref $template->{'fields'} ne "HASH") {
	push(@{$template_status->{error}}, 'the fields attribute is not an object');
      } else {
	&check_fields($template->{'fields'}, 'default', $template_status, $template);
	$template->{'groups'} = { "default" => { "name" => "default",
						 "label" => "default",
						 "description" => "",
						 "fields" => $template->{'fields'} } };
      }
    }
  } elsif (ref $template->{'groups'} ne 'HASH') {
    push(@{$template_status->{error}}, 'template groups is not an object');
  } else {
    my $subgroups = {};
    foreach my $g (keys(%{$template->{'groups'}})) {
      my $group = $template->{'groups'}->{$g};
      if (! exists $group->{'name'}) {
	$group->{'name'} = $g;
      } elsif (ref $group->{'name'}) {
	push(@{$template_status->{error}}, 'name of group '.$g.' is not a string');
      }
      if (! exists $group->{'label'}) {
	$group->{'label'} = $group->{'name'};
      }
      if (! exists $group->{'mandatory'}) {
	$group->{'mandatory'} = 0;
      }
      if (! exists $group->{'toplevel'}) {
	$group->{'toplevel'} = 0;
      }
      if (! exists $group->{'description'}) {
	$group->{'description'} = "";
      } elsif (ref $group->{'description'}) {
	push(@{$template_status->{error}}, 'description of group '.$g.' is not a string');
      }
      if (! exists $group->{'fields'}) {
	if (! exists $group->{'subgroups'}) {
	  push(@{$template_status->{error}}, 'group '.$g.' has no fields or subgroups');
	}
      } elsif (ref $group->{'fields'} ne 'HASH') {
	push(@{$template_status->{error}}, 'group '.$g.' fields attribute is not an object');
      } else {
	&check_fields($group->{'fields'}, $g, $template_status, $template);
      }

      if (! exists $group->{'subgroups'} ) {
	$group->{'subgroups'} = {};
      } elsif (ref $group->{'subgroups'} eq 'HASH') {
	foreach my $s (keys(%{$group->{'subgroups'}})) {
	  $subgroups->{$s} = $g;
	  my $subgroup = $group->{'subgroups'}->{$s};
	  if (ref $subgroup eq "HASH") {
	    if (exists $subgroup->{'type'}) {
	      if (! ref $subgroup->{'type'}) {
		if ($subgroup->{'type'} ne "instance" && $subgroup->{'type'} ne "list") {
		  push(@{$template_status->{error}}, 'the type attribute of subgroup '.$s.' of group '.$g.' is '.$subgroup->{'type'}." (must be 'list' nor 'instance')");
		}
	      } else {
		push(@{$template_status->{error}}, 'the type attribute of subgroup '.$s.' of group '.$g.' is not a string');
	      }
	    } else {
	      $subgroup->{'type'} = "list";
	    }
	    
	    if (exists $subgroup->{'label'}) {
	      if (ref $subgroup->{'label'}) {
		push(@{$template_status->{error}}, 'the label attribute of subgroup '.$s.' of group '.$g.' is not a string');
	      }
	    } else {
	      $subgroup->{'label'} = $s;
	    }
	    
	    if (exists $subgroup->{'mandatory'}) {
	      $subgroup->{'mandatory'} = 0;
	    } else {
	      if ($subgroup->{'mandatory'} != 0 && $subgroup->{'mandatory'} != 1) {
		push(@{$template_status->{error}}, 'the mandatory attribute of subgroup '.$s.' of group '.$g.' is not a boolen');
	      }
	    }
	  } else {
	    push(@{$template_status->{error}}, 'subgroup '.$s.' of group '.$g.' is not an object');
	  }
	}
      } else {
	push(@{$template_status->{error}}, 'subgroups property of group '.$g.' is not an object');
      }
    }
    
    foreach my $s (keys(%$subgroups)) {
      if (! exists $template->{'groups'}->{$s}) {
	push(@{$template_status->{error}}, 'subgroup '.$s.' referenced in group '.$subgroups->{$s}.' does not exist in template');
      }
    }
  }

  if (scalar(@{$template_status->{error}})) {
    $template_status->{valid} = 0;
  } else {
    $attributes->{type} = 'metadata';
    $attributes->{data_type} = 'template';
    $attributes->{template} = 'mgrast';
    $attributes->{file_format} = 'json';
    $self->update_shock_node($id, $attributes, $self->{token});
  }

  $self->return_data($template_status);
}

sub check_fields {
  my ($fields, $g, $template_status, $template) = @_;

  foreach my $f (keys(%$fields)) {
    my $field = $fields->{$f};
    if (ref $field eq 'HASH') {
      if (! exists $field->{'name'}) {
	$field->{'name'} = $f;
      } elsif (ref $field->{'name'}) {
	push(@{$template_status->{error}}, 'the name of field '.$f.' in group '.$g.' is not a string');
      }
      if (! exists $field->{'label'} ) {
	$field->{'label'} = $field->{'name'};
      } elsif (ref $field->{'label'}) {
	push(@{$template_status->{error}}, 'the label of field '.$f.' in group '.$g.' is not a string');
      }
      if (! exists $field->{'description'}) {
	$field->{'description'} = "";
      } elsif (ref $field->{'description'}) {
	push(@{$template_status->{error}}, 'the description of field '.$f.' in group '.$g.' is not a string');
      }
      if (exists $field->{'type'}) {
	if (ref $field->{'type'}) {
	  push(@{$template_status->{error}}, 'the type of field '.$f.' in group '.$g.' is not a string');
	}
      } else {
	$field->{'type'} = 'text';
      }
      if (exists $field->{'mandatory'}) {
	if ($field->{'mandatory'} && $field->{'mandatory'} != "0" && $field->{'mandatory'} ne "false") {
	  $field->{'mandatory'} = 1;
	} else {
	  $field->{'mandatory'} = 0;
	}
      } else {
	$field->{'mandatory'} = 0;
      }
      if (! exists $field->{'default'}) {
	$field->{'default'} = undef;
      }
      if (exists $field->{'validation'}) {
	if (ref $field->{'validation'} eq 'HASH') {
	  if (exists $field->{'validation'}->{'type'}) {
	    if (! ref $field->{'validation'}->{'type'}) {
	      if ($field->{'validation'}->{'type'} ne 'none') {
		if (exists $field->{'validation'}->{'value'}) {
		  if ($field->{'validation'}->{'type'} eq 'cv') {
		    if (ref $field->{'validation'}->{'value'}) {
		      push(@{$template_status->{error}}, 'the validation type of the field '.$f.' in group '.$g.' is cv, but the validation value of the field is not a string');
		    } else {
		      if (! exists $template->{'cvs'}->{$field->{'validation'}->{'value'}}) {
			push(@{$template_status->{error}}, 'the referenced cv of the validation of field '.$f.' in group '.$g.' does not exist');
		      }
		    }
		  } elsif ($field->{'validation'}->{'type'} eq 'expression') {
		    if (ref $field->{'validation'}->{'value'}) {
		      push(@{$template_status->{error}}, 'the value of the expression validation of field '.$f.' in group '.$g.' is notr a RegExp');
		    }
		  } else {
		    push(@{$template_status->{error}}, 'the validation of field '.$f.' in group '.$g.' has an invalid type');
		  }
		} else {
		  push(@{$template_status->{error}}, 'validation of field '.$f.' in group '.$g.' has no value');
		}
	      }
	    } else {
	      push(@{$template_status->{error}}, 'validation type of field '.$f.' in group '.$g.' is not a string');
	    }
	  } else {
	    push(@{$template_status->{error}}, 'the validation of field '.$f.' in group '.$g.' has no type');
	  }
	} else {
	  push(@{$template_status->{error}}, 'the validation of field '.$f.' in group '.$g.' is not an object');
	}
      } else {
	$field->{'validation'} = { "type" => "none" };
      }
    }
  }
  
  return;
}

sub data {
  my ($self, $data_id, $template_id) = @_;
  my $json = JSON->new->allow_nonref;

  # if no template id is passed, get the MG-RAST template
  my $template;
  my $template_attributes;
  if ($template_id) {
    # getting node
    my $template_node = $self->get_shock_node($template_id, $self->{token});
    $template_attributes = $template_node->{attributes};

    # getting file
    my ($template_str, $err) = $self->get_shock_file($template_id, undef, $self->{token});
    if ($err) {
        $self->return_data( {"ERROR" => $err}, 500 );
    }
    $template = $json->decode($template_str);

    # unless ($template_attributes->{data_type} eq 'template') {
    #   $self->return_data( {"ERROR" => "template id does not point to a valid template"}, 400 );
    # }
  } else {
    # getting node
    my $template_node = $self->get_shock_node($self->{md_template}, $self->mgrast_token);
    $template_attributes = $template_node->{attributes};

    # getting file
    my ($template_str, $err) = $self->get_shock_file($self->{md_template}, undef, $self->mgrast_token);
    if ($err) {
        $self->return_data( {"ERROR" => $err}, 500 );
    }
    $template = $json->decode($template_str);
  }
  # check shock type to be template

  my ($data_str, $err) = $self->get_shock_file($data_id, undef, $self->{token});
  if ($err) {
      $self->return_data( {"ERROR" => $err}, 500 );
  }
  my $data = $json->decode($data_str);

  my $data_status = { "valid" => 1,
		      "error" => [],
		      "warning" => [] };

  if (ref $data eq 'HASH') {
    foreach my $d (keys(%$data)) {
      if (exists $template->{'groups'}->{$d}) {
	my $item = $data->{$d};
	my $group = $template->{'groups'}->{$d};
	if (ref $item eq 'HASH') {
	  &check_group($item, $group, $template, $data_status);
	} else {
	  push(@{$data_status->{error}}, 'data item '.$d.' is not an object');
	}
      } else {
	push(@{$data_status->{error}}, 'group '.$d.' does not exist in template');
      }
    }
  } else {
    push(@{$data_status->{error}}, 'the data is not an object');
  }

  if (scalar(@{$data_status->{error}})) {
    $data_status->{valid} = 0;
  } else {
    $data_status->{data} = $data;
  }

  $self->return_data($data_status);
}

sub check_group {
  my ($item, $group, $template, $data_status) = @_;

  if (ref $item ne 'ARRAY') {
    foreach my $field (keys(%$item)) {
      if (exists $group->{'fields'}->{$field}) {
  	&check_field($item->{$field}, $field, $group, undef, $template, $data_status);
      } else {
	my $found = 0;
	foreach my $key (keys(%{$group->{'subgroups'}})) {
	  if ($group->{'subgroups'}->{$key}->{'label'} eq $field) {
	    &check_group($item->{$field}, $template->{'groups'}->{$key}, $template, $data_status);
	    $found = 1;
	    last;
	  }
	}
	unless ($found) {
	  push(@{$data_status->{warning}}, 'additional field '.$field.' found in group '.$group->{'name'}.' of the template');
	}
      }
    }
    foreach my $field (keys(%{$group->{'fields'}})) {
      if ($group->{'fields'}->{$field}->{'mandatory'} && ! exists $item->{$field}) {
  	push(@{$data_status->{error}}, 'mandatory field '.$field.' missing in group '.$group->{'name'});
      }
    }
  } else {
    for (my $h=0; $h<scalar(@$item); $h++) {
      if (ref $item->[$h] eq 'HASH') {
  	foreach my $j (keys(%{$item->[$h]})) {
	  if (exists $group->{'fields'}->{$j}) {
	    &check_field($item->[$h]->{$j}, $j, $group, $h, $template, $data_status);
	  } else {
	    my $found = 0;
	    foreach my $key (keys(%{$group->{'subgroups'}})) {
	      if ($group->{'subgroups'}->{$key}->{'label'} eq $j) {
		&check_group($item->[$h]->{$j}, $template->{'groups'}->{$key}, $template, $data_status);
		$found = 1;
		last;
	      }
	    }
	    unless ($found) {
	      push(@{$data_status->{warning}}, 'additional field '.$j.' found in group '.$group->{'name'}.' of the template');
	    }
	  }
	}
	foreach my $j (keys(%{$group->{'fields'}})) {
  	  if ($group->{'fields'}->{$j}->{'mandatory'} && ! exists $item->[$h]->{$j}) {
  	    push(@{$data_status->{error}}, 'mandatory field '.$j.' missing in group '.$group->{'name'}.' instance '.$h);
  	  }
  	}
      } else {
  	push(@{$data_status->{error}}, 'instance '.$h.' of group '.$group->{'name'}.' is not an object');
      }
    }
  }
}

sub check_field {
  my ($value, $fieldname, $group, $location, $template, $data_status) = @_;

  my $error = "field ".$fieldname;
  if (! ref $group) {
    $error = " of group ".$group;
  }
  if (defined $location) {
    $error .= " instance ".$location;
  }
  
  if (exists $group->{'fields'}->{$fieldname}) {
    my $field = $group->{'fields'}->{$fieldname};
    if ($field->{'mandatory'} && ! length $field) {
      push(@{$data_status->{error}}, 'mandatory field '.$fieldname.' missing');
    }
    if (exists $field->{'validation'}) {
      if ($field->{'validation'}->{'type'} eq 'cv') {
	if (! $template->{'cvs'}->{$field->{'validation'}->{'value'}}->{'value'}) {
	  push(@{$data_status->{error}}, 'field '.$fieldname.' was not found in the controlled vocabulary '.$field->{'validation'}->{'value'});
	}
	return;
      } elsif ($field->{'validation'}->{'type'} eq 'expression') {
	my $reg = $field->{'validation'}->{'value'};
	if ($value !~ /$reg/) {
	  push(@{$data_status->{error}}, 'field '.$fieldname.' has an invalid value');
	}
	return;
      } else {
	return;
      }
    }
  } else {
    push(@{$data_status->{error}}, 'field '.$fieldname.' does not exist in group '.$group->{name}.' of the template');
    return;
  }
}

sub reformat_template {
  my ($self) = @_;

  return;

  use LWP::UserAgent;
  use JSON;
  my $ua = LWP::UserAgent->new;
  my $json = new JSON;
  my $data = $json->decode($ua->get(($Conf::api_url || 'http://api.metagenomics.anl.gov/1/').'metadata/template')->content);

  my $template = { "name" => "mgrast",
		   "label" => "MG-RAST",
		   "description" => "MG-RAST metagenome submission metadata template",
		   "cvs" => { "gender" => { "male" => 1,
					    "female" => 1 } },
		   "groups" => { "project" => { "name" => "project",
						"label" => "project",
						"toplevel" => 1,
						"mandatory" => 1,
						"description" => "project",
						"subgroups" => { "sample" => { "type" => "list",
									       "mandatory" => 1,
									       "label" => "samples" } },
						"fields" => {} },
				 "sample" => { "name" => "sample",
					       "label" => "sample",
					       "description" => "sample",
					       "subgroups" => { "libraries" => { "type" => "list",
										 "mandatory" => 1,
										 "label" => "libraries" },
								"envPackage" => { "type" => "instance",
										  "mandatory" => 1,
										  "label" => "envPackage" } },
					       "fields" => { } },
				 "libraries" => { "name" => "libraries",
						  "label" => "library",
						  "description" => "library",
						  "subgroups" => { "mimarks-survey" => { "type" => "instance",
											 "mandatory" => 0,
											 "label" => "mimarks-survey" },
								   "metagenome" => { "type" => "instance",
										     "mandatory" => 0,
										     "label" => "metagenome" },
								   "metatranscriptome" => { "type" => "instance",
											    "mandatory" => 0,
											    "label" => "metatranscriptome" } } },
				 "envPackage" => { "name" => "envPackage",
						   "label" => "envPackage",
						   "description" => "envPackage",
						   "subgroups" => {} } }
		 };
  
  # get project fields
  foreach my $i (keys(%{$data->{'project'}->{'project'}})) {
    my $field = $data->{'project'}->{'project'}->{$i};
    my $l = $i;
    $l =~ s/_/ /g;
    $template->{'groups'}->{'project'}->{'fields'}->{$i} = { "name" => $i,
							     "label" => $l,
							     "description" => $field->{'definition'},
							     "type" => $field->{'type'},
							     "mandatory" => $field->{'required'} == 0 ? 0 : 1 };
  }
  
  # get sample fields
  foreach my $i (keys(%{$data->{'sample'}->{'sample'}})) {
      my $field = $data->{'sample'}->{'sample'}->{$i};
      my $l = $i;
      $l =~ s/_/ /g;
      $template->{'groups'}->{'sample'}->{'fields'}->{$i} = { "name" => $i,
							      "label" => $l,
							      "description" => $field->{'definition'},
							      "type" => $field->{'type'},
							      "mandatory" => $field->{'required'} == 0 ? 0 : 1 };
  }
  
  # get library types
  foreach my $i (keys(%{$data->{'library'}})) {
    $template->{'groups'}->{$i} = { "name" => $i,
				    "label" => $i,
				    "description" => $i,
				    "fields" => {} };
    foreach my $h (keys(%{$data->{'library'}->{$i}})) {
      my $field = $data->{'library'}->{$i}->{$h};
      my $l = $h;
      $l =~ s/_/ /g;
      $template->{'groups'}->{$i}->{'fields'}->{$h} = { "name" => $h,
							"label" => $l,
							"description" => $field->{'definition'},
							"type" => $field->{'type'},
							"mandatory" => $field->{'required'} == 0 ? 0 : 1 };
    }
  }
  
  # get ep types
  foreach my $i (keys(%{$data->{'ep'}})) {
      $template->{'groups'}->{'envPackage'}->{'subgroups'}->{$i} = { "type" => "instance",
								     "mandatory" => 0,
								     "label" => $i };
      $template->{'groups'}->{$i} = { "name" => $i,
				      "label" => $i,
				      "description" => $i,
				      "fields" => {} };
      foreach my $h (keys(%{$data->{'ep'}->{$i}})) {
	my $field = $data->{'ep'}->{$i}->{$h};
	my $l = $h;
	$l =~ s/_/ /g;
	$template->{'groups'}->{$i}->{'fields'}->{$h} = { "name" => $h,
							  "label" => $l,
							  "description" => $field->{'definition'},
							  "type" => $field->{'type'},
							  "mandatory" => $field->{'required'} == 0 ? 0 : 1 };
      }
  }

  my $node = $self->set_shock_node("mgrast", undef, $template, $self->mgrast_token);

  return $self->return_data($node);
}

1;
