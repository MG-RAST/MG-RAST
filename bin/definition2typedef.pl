#!/usr/bin/perl
use strict;
use warnings;

use JSON;
use Getopt::Long;

use Data::Dumper;

# usage message
sub usage {
  print "definition2typedef - creates a typedef document that can be compiled by the typespec compiler from a json structure\n";
  print "usage: definition2typedef -json <json input file> -typedef <typedef output file> [-verbose <print status messages>]\n\n";
  exit;
}

# initialize some variables
my ($file, $typedef, $verbose, $struct) ;

# get input parameters
GetOptions ( 'json=s' => \$file,
	     'typedef=s' => \$typedef,
	     'verbose=s' => \$verbose);

# print usage if called with invalid or no parameters
unless ($file && $typedef) {
  usage();
}

# initialize JSON OO-interface
my $json = JSON->new->allow_nonref;
$json = $json->pretty([1]);
$json = $json->relaxed([1]);

# check input file existence
if (-f $file){
  
  my $json_text = undef ;

  # read in the input file
  if ($verbose) {
    print "opening input file\n";
  }
  if (open( my $fh, '<', $file )) {
    while(<$fh>){
      $json_text .= $_ ;
    }
    close($fh);
  } else {
    print "Could not open input file for reading ($file): $@\n";
    exit;
  }

  # try to parse the loaded data as json
  if ($verbose) {
    print "parsing json\n";
  }
  eval {
    $struct = $json->decode( $json_text );
  };
  if ($@) {
    print "parsing json failed: $@\n";
    exit;
  }
} else{
  print "Could not find input file: $file\nprocess aborted.\n";
  exit;
}

# create the typedef structure
if ($verbose) {
  print "creating typedef structure\n";
}

# string to hold the typedef
my $definition_string = "";

my $pod_string = "";

# buffer all functions and types
my $funcs = [];
my $types = {};
my $func_descriptions = [];

# get the module name
if (exists($struct->{service})) {
  if ($struct->{service}->{name}) {
    $struct->{service}->{name} =~ s/-/_/g;
    $pod_string .= "=pod\n\n=head1 module ".$struct->{service}->{name}."\n\n".$struct->{service}->{description}."\n\n";
    $definition_string .= "/*\n\n".$struct->{service}->{description}."\n\n*/\n";
    $definition_string .= "module ".$struct->{service}->{name}." : ".$struct->{service}->{name}." {\n";
  } else {
    print "service object is missing the name attribute, aborting.\n\n";
    exit;
  }
} else {
  print "JSON structure is missing a service object, aborting.\n\n";
  exit;
}


# check if we have resources
unless (exists($struct->{resources})) {
  print "definition has no resources, aborting.\n\n";
  exit;
}

# check if the resources attribute is an array
unless (ref($struct->{resources}) eq "ARRAY") {
  print "resources attribute of the definition must be an array, aborting.\n\n";
  exit;
}

# iterate over the resources
foreach my $resource (@{$struct->{resources}}){

  # check if the resource has a name
  unless ($resource->{name}) {
    print "resource without a name, skipping.\n";
    next;
  }
  my $name = lc $resource->{name};

  # check if we have requests
  unless (exists($resource->{requests})) {
    print "resource ".$resource->{name}." has no requests, skipping.\n";
    next;
  }

  # check if requests is an array
  unless (ref($resource->{requests}) eq "ARRAY") {
    print "the requests attribute of resource ".$resource->{name}." is not an array, skipping.\n";
    next;
  }

  # iterate over the requests
  foreach my $request (@{$resource->{requests}}){

    # variable to hold the data of this function
    my $func = "\tfuncdef ";
    
    # check if we have a method
    my $method = "get";
    if ($request->{method}) {
      $method = lc($request->{method});
    }

    # check if we have a request name
    unless (exists($request->{name})) {
      print "request without name in resource ".$resource->{name}.", skipping.\n";
      next;
    }
    
    # compose function name
    my $func_name_uc = $method."_".$resource->{name}."_".$request->{name};
    my $func_name = camel($method).camel($resource->{name}).camel($request->{name});

    # hold parameters
    my $params = {};

    # check parameters
    if ($request->{parameters}) {
      if (ref($request->{parameters}) eq 'HASH') {
    
	# check optional parameters
	if ($request->{parameters}->{options}) {
	  if (ref($request->{parameters}->{options}) eq 'HASH') {
	    foreach my $key (keys(%{$request->{parameters}->{options}})) {
	      $params->{$key} = $request->{parameters}->{options}->{$key};
	    }
	  } else {
	    if ($verbose) {
	      print "the option attribute of method ".$request->{name}." in resource ".$resource->{name}." is not a hash (not fatal)\n";
	    }
	  }
	} else {
	  if ($verbose) {
	    print "method ".$request->{name}." in resource ".$resource->{name}." does not have an options attribute (not fatal)\n";
	  }
	}

	# check required parameters
	if ($request->{parameters}->{required}) {
	  if (ref($request->{parameters}->{required}) eq 'HASH') {
	    foreach my $key (keys(%{$request->{parameters}->{required}})) {
	      $params->{$key} = $request->{parameters}->{required}->{$key};
	    }
	  } else {
	    if ($verbose) {
	      print "the required attribute of method ".$request->{name}." in resource ".$resource->{name}." is not a hash (not fatal)\n";
	    }
	  }
	} else {
	  if ($verbose) {
	    print "method ".$request->{name}." in resource ".$resource->{name}." does not have a required attribute (not fatal)\n";
	  }
	}

	# check body parameters
	if ($request->{parameters}->{body}) {
	  if (ref($request->{parameters}->{body}) eq 'HASH') {
	    foreach my $key (keys(%{$request->{parameters}->{body}})) {
	      $params->{$key} = $request->{parameters}->{body}->{$key};
	    }
	  } else {
	    if ($verbose) {
	      print "the body attribute of method ".$request->{name}." in resource ".$resource->{name}." is not a hash (not fatal)\n";
	    }
	  }
	} else {
	  if ($verbose) {
	    print "method ".$request->{name}." in resource ".$resource->{name}." does not have a body attribute (not fatal)\n";
	  }
	}

      } else {
	if ($verbose) {
	  print "the parameters attribute of method ".$request->{name}." in resource ".$resource->{name}." is not a hash (not fatal)\n";
	}
      }
    } else {
      if ($verbose) {
	print "method ".$request->{name}." in resource ".$resource->{name}." does not have a parameters attribute (not fatal)\n";
      }
    }

    # create return object name
    my $retname = ucfirst($resource->{name}) . ucfirst($request->{name});

    # check if we have attributes
    my @atts = ();
    if (exists($request->{attributes})) {
      if (ref($request->{attributes}) eq "HASH") {
	@atts = parse_types($request->{attributes});
      } else {
	if ($verbose) {
	  print "the attributes attribute of method ".$request->{name}." in resource ".$resource->{name}." is not a hash (not fatal)\n";
	}
	next;
      }
    } else {
      if ($verbose) {
	print "method ".$request->{name}." in resource ".$resource->{name}." does not have an attributes attribute (not fatal)\n";
      }
    }

    # parse through the parameters
    my @parameters = parse_parameters($params);
    $pod_string .= "=head2 $func_name\n\n=head3 Description\n\n".$resource->{description}."\n".$request->{description}."\n\n=head3 Parameters\n\n=over4\n\n";

    # check if the function has parameters
    if (scalar(@parameters)) {
      $definition_string .= "\ttypedef structure {\n";
      foreach my $pm (@parameters) {
	my $p = $pm->[0];
	my $podp = $p;
	$podp =~ s/;//;
	$pod_string .= "=item * $podp\n\n";
	if (ref($pm->[1]) eq 'ARRAY') {
	  $pod_string .= "This parameter value can be chosen from the following (the first being default):\n\n";
	  $definition_string .= "/*\n\nThis parameter value can be chosen from the following (the first being default):\n\n";
	  foreach my $cvitem (@{$pm->[1]}) {
	    $pod_string .= " ".$cvitem->[0]." - ".$cvitem->[1]."\n";
	    $definition_string .= "\t".$cvitem->[0]." - ".$cvitem->[1]."\n";
	  }
	  $pod_string .= "\n";
	  $definition_string .= "\n*/\n";
	} else {
	  $pod_string .= $pm->[1]."\n\n";
	  $definition_string .= "/*\n\n\t".$pm->[1]."\n\n*/\n";
	}
	$definition_string .= "\t\t$p\n";
      }
      $pod_string .= "\n=back\n\n";
      $definition_string .= "\t} ".$func_name."Params;\n";
      
      # create function spec
      $func .= $func_name_uc."(".$func_name."Params) returns (";

    }
    
    # this function is parameterless
    else {
      $pod_string .= "This function has no parameters.\n\n";

      # create function spec
      $func .= $func_name_uc."() returns (";
    }

    # finish the function line and push it
    $func .= $retname . ");\n";
    push(@$func_descriptions, $resource->{description}."\n".$request->{description});
    push(@$funcs, $func);
    
    # create typedef for the return object
    $definition_string .= "\ttypedef structure {\n";
    $pod_string .= "=head3 Return Attributes\n\n=over4\n\n";
    foreach my $att_tuple (@atts) {
      my $att = $att_tuple->[0];
      $pod_string .= "=item * $att\n\n".$att_tuple->[1]."\n\n";
      $definition_string .= "/*\n\t".$att_tuple->[1]."\n*/\n";
      $definition_string .= "\t\t$att;\n";
    }
    $definition_string .= "\t} $retname;\n";
  }
  $pod_string .= "=cut\n\n";
}

# add the function definitions to the structure
my $fnum = 0;
foreach my $f (@$funcs) {
  $definition_string .= "\n\n/* ".$func_descriptions->[$fnum]."\n*/\n";
  $definition_string .= $f;
  $fnum++;
}

# close the definition
$definition_string .= "};";

# print the definition to the output file
if ($verbose) {
  print "writing output file\n";
}
if (open(FH, ">$typedef")) {
  print FH $definition_string;
  close FH;
  print "all done.\nHave a nice day :)\n\n";
} else {
  print "could not open output file for writing ($typedef): $@\naborting process.\n\n";
  exit;
}

if (open(FH, ">$typedef.pod")) {
  print FH $pod_string;
  close FH;
  print "pod done.\n\n";
} else {
  print "could not open output file for writing ($typedef): $@\naborting process.\n\n";
  exit;
}

exit;


# parses a hash of defined types
# returns an array of type names
sub parse_types {
  my ($params) = @_;

  my $simple_types = { 'string' => 'string',
		       'integer' => 'int',
		       'int' => 'int',
		       'file' => 'string',
		       'boolean' => 'int',
		       'float' => 'float',
		       'uri' => 'string',
		       'date' => 'string',
		       'reference' => 'string',
		       'cv' => 'string',
		       'object' => 'mapping<string, string>',
		       'hash' => 'mapping<string, string>' };

  my @types = ();
  foreach my $key (keys(%$params)) {
    if (ref($params->{$key}) eq "ARRAY") {
      if ($params->{$key}->[0]) {
	$params->{$key}->[0] =~ s/(reference)\s\w+/$1/;
	if ($simple_types->{$params->{$key}->[0]}) {
	  my $desc = $params->{$key}->[1];
	  if (ref($desc) eq 'ARRAY') {
	    $desc = $desc->[1];
	  }
	  push(@types, [ $simple_types->{$params->{$key}->[0]}." $key", $desc ]);
	} else {
	  if ($params->{$key}->[0] eq 'list') {
	    my $tt = $params->{$key}->[1];
	    my $type = "list<";
	    my $closer = ">";
	    while ($tt->[0] eq 'list') {
	      $type .= "list<";
	      $closer .= ">";
	      $tt = $tt->[1];
	    }
	    if ($simple_types->{$tt->[0]}) {
	      my $desc = $tt->[1];
	      if (ref($desc) eq 'ARRAY') {
		$desc = $tt->[1]->[1];
	      }
	      push(@types, [ $type.$simple_types->{$tt->[0]}.$closer." $key", $desc ]);
	    } else {
	      if ($verbose) {
		print "attribute $key has an invalid type ".$params->{$key}->[0].", skipping.\n";
	      }
	    }
	  } else {
	    if ($verbose) {
	      print "attribute $key has an invalid type ".$params->{$key}->[0].", skipping.\n";
	    }
	  }
	}
      }
    } else {
      if ($verbose) {
	print "attribute $key has an invalid structure, skipping.\n";
      }
    }
  }

  return @types;
}

# parses the optional and required parameters
sub parse_parameters {
  my ($params) = @_;

  my @parameters = ();
  
  my $valid_types = { 'string' => 'string',
		      'integer' => 'int',
		      'int' => 'int',
		      'file' => 'string',
		      'uri' => 'string',
		      'float' => 'float',
		      'list' => 'list',
		      'boolean' => 'int',
		      'cv' => 'string' };

  foreach my $key (keys(%$params)) {
    my $param_desc = $params->{$key};

    # check if the parameter description has a valid format
    if (ref($param_desc) eq "ARRAY") {
      if ($param_desc->[0]) {
	if ($valid_types->{$param_desc->[0]}) {
	  if ($param_desc->[0] eq 'list') {
	    if (ref($param_desc->[1]) eq 'ARRAY') {
	      if ($valid_types->{$param_desc->[1]->[0]}) {
		if (ref($param_desc->[1]->[1]) eq 'ARRAY') {
		  push(@parameters, [ "list<".$valid_types->{$param_desc->[1]->[0]}."> $key;", $param_desc->[1]->[1]->[1]]);
		} else {
		  push(@parameters, [ "list<".$valid_types->{$param_desc->[1]->[0]}."> $key;", $param_desc->[1]->[1]]);
		}
	      } else {
		if ($verbose) {
		  print "the element data type of the list of parameter $key has an unknown type ".$param_desc->[1]->[0].", skipping\n";
		}
	      }
	    } else {
	      if ($verbose) {
		print "parameter $key is of type list, but has no element data type, skipping.\n";
	      }
	    }
	  } else {
	    if (ref($param_desc->[1]) eq 'ARRAY' && $param_desc->[0] ne 'cv') {
	      push(@parameters, [ $valid_types->{$param_desc->[0]}." $key;", $param_desc->[1]->[1] ]);
	    } else {
	      push(@parameters, [ $valid_types->{$param_desc->[0]}." $key;", $param_desc->[1] ]);
	    }
	  }
	} else {
	  if ($verbose) {
	    print "parameter $key has invalid type ".$param_desc->[0].", skipping.\n";
	  }
	}
      } else {
	if ($verbose) {
	  print "parameter description for $key is empty, skipping.\n";
	}
      }
    } else {
      if ($verbose) {
	print "invalid parameter description for option $key, skipping.\n";
      }
    }
    
  }

  return @parameters;
}

sub camel {
  my ($word) = @_;
  
  my ($f, $r) = $word =~ /^(\w)(\w+)$/;

  return uc($f).lc($r);
}
