package WebComponent::ObjectTable;
use strict;
use warnings;
use base qw( WebComponent );
use Conf;

1;

=pod

=head1 NAME

ModelSelect - a select box for models

=head1 DESCRIPTION

WebComponent for a model select box

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
	my $self = shift->SUPER::new(@_);
	my $index = 0;
	while (defined($self->application->{'_basetable'.$index})) {
		$index++;
	}
	$self->application->{'_basetable'.$index} = 1;
	$self->application->register_component('Table','basetable'.$index);
	$self->{_tablecomponent} = 'basetable'.$index;
	
	my $defaults = {width => "*"};
	my @keyList = keys(%{$defaults});
	for (my $i=0; $i < @keyList; $i++) {
		$self->{"_table_parameters"}->{$keyList[$i]} = $defaults->{$keyList[$i]};
	}
	
	return $self;
}

=head3 set_type
Definition:
	DBmaster:database master for input type = ObjectTable->set_type(string:object type);
Description:
	Sets the type of the objects contained in the table and returns the database master for the input type
=cut
sub set_type {
	my ($self,$type) = @_;
 	my $figmodel = $self->application()->data_handle('FIGMODEL');
 	#Setting the type
 	$self->{_type} = $type;
 	#Getting the database manager for the input type
 	$self->{_master} = $figmodel->database()->get_object_manager($type);
 	if (defined($self->{_master})) {
		return undef;
	}
 	return $self->{_master};
}

=head3 get_objects
Definition:
	[FIGMODELObjects]:list of objects to be included in the table = ObjectTable->get_objects({string:attribute=>string:value});
Description:
	Uses the set database master to get a list of the objects to be contained in the table
=cut
sub get_objects {
	my ($self,$parameters) = @_;
	if (!defined($self->{_master})) {
		print STDERR "ObjectTable:get_objects:Need to have database handler before objects can be retrieved\n";
		return undef;
	}
	my $figmodel = $self->application()->data_handle('FIGMODEL');
	my $objects = $figmodel->database()->get_objects($self->{_type},$parameters);
	if (defined($objects) && defined($objects->[0])) {
		push(@{$self->{_objects}},@{$objects});
	} 
	return $self->{_objects};
}

=head3 set_objects
Definition:
	ObjectTable->set_objects([FIGMODELObjects]:list of objects to be included in the table);
Description:
	Allows one to obtain a list of objects outside of the object table
=cut
sub set_objects {
	my ($self,$objects) = @_;
	$self->{_objects} = $objects;
}

=head3 add_columns
Definition:
	[{}]:list of table columns = ObjectTable->add_columns([{}]);
Description:
	Adds the input vector of columns to the list of columns for the table and returns the total list. 
	Two columns with the same label will not be added twice; instead, the new column will overwrite the old.
=cut
sub add_columns {
	my ($self,$columns) = @_;
	
	for (my $i=0; $i < @{$columns}; $i++) {
		if (defined($columns->[$i]->{name})) {
			my $add = 1;
			if (defined($self->{_columns})) {
				for (my $j=0; $j < @{$self->{_columns}}; $j++) {
					if ($self->{_columns}->[$j]->{name} eq $columns->[$i]->{name}) {
						$self->{_columns}->[$j] = $columns->[$i];
						$add = 0;
					}
				}
			}
			if ($add == 1) {
				push(@{$self->{_columns}},$columns->[$i]);
			}
		}
	}
	
	return $self->{_columns};
}

=head3 set_table_parameter
Definition:
	ObjectTable->set_table_parameter(string:parameter,string:value);
Description:
	Sets a parameter for the table.
=cut
sub set_table_parameter {
	my ($self,$parameter,$value) = @_;
	$self->{"_table_parameters"}->{$parameter} = $value;
}

=head3 set_table_parameters
Definition:
	ObjectTable->set_table_parameters({string:parameter => string:value});
Description:
	Sets a parameter for the table.
=cut
sub set_table_parameters {
	my ($self,$parameters) = @_;
	my @keyList = keys(%{$parameters});
	for (my $i=0; $i < @keyList; $i++) {
		$self->{"_table_parameters"}->{$keyList[$i]} = $parameters->{$keyList[$i]};
	}
}

=head3 output
Definition:
	string:html = ObjectTable->output(string:type,[{}]:columns,{string:attribute=>string:value}:parameters,{}:table parameters);
Description:
	Generates html for the object table. All input parameters are optional and exist only so the table can be created in a single line
=cut
sub output {
	my ($self,$type,$columns,$parameters,$tableParameters) = @_;
	#Getting objects associated with the webpage
	$self->{_FIGMODEL} = $self->application()->data_handle('FIGMODEL');
	#Setting type
	if (defined($type)) {
		$self->set_type($type);
	}
	#Setting columns
	if (defined($columns)) {
		$self->add_columns($columns);
	}
	#Getting objects
	if (defined($parameters)) {
		$self->get_objects($parameters);
	}
	#Setting table parameters
	if (defined($tableParameters)) {
		my @keyList = keys(%{$tableParameters});
		for (my $i=0; $i < @keyList; $i++) {
			$self->{"_table_parameters"}->{$keyList[$i]} = $tableParameters->{$keyList[$i]};;
		}
	}
	#Checking that all necessary entities exist
	if (!defined($self->{_objects})) {
		print STDERR "ObjectTable:output:Cannot create table without objects\n";
		return undef;
	}
	if (!defined($self->{_columns})) {
		print STDERR "ObjectTable:output:Cannot create table without columns\n";
		return undef;
	}
	#Filling out the table object
	my $table = $self->base_table();
	#Setting table parameters
	if (defined($self->{"_table_parameters"})) {
		my @keyList = keys(%{$self->{"_table_parameters"}});
		for (my $i=0; $i < @keyList; $i++) {
			if ($keyList[$i] ne "sort_column" && $keyList[$i] ne "sort_descending") {
				my $function = $keyList[$i];
				$table->$function($self->{"_table_parameters"}->{$keyList[$i]});
			}
		}
	}
	$table->columns($self->{_columns});
	#Setting default values for columns
	my $dataAccess;
	for (my $i=0; $i < @{$self->{_columns}}; $i++) {
		if (!defined($self->{_columns}->[$i]->{call})) {
			$self->{_columns}->[$i]->{call} = "HASH:".$self->{_columns}->[$i]->{name};
		}
		if (!defined($self->{_columns}->[$i]->{delimiter})) {
			$self->{_columns}->[$i]->{delimiter} = ", ";
		}
		if (defined($self->{_columns}->[$i]->{function})) {
			my @tempList = split(/:/,$self->{_columns}->[$i]->{function});
			$dataAccess->{$tempList[0]} = 1;
		}
	}
	#Getting data access entities as needed for columns
	my @keyList = keys(%{$dataAccess});
	for (my $i=0; $i < @keyList; $i++) {
		if (!defined($self->{"_".$keyList[$i]})) {
			if ($keyList[$i] eq "FIGMODELweb") {
				$self->{"_".$keyList[$i]} = $self->{_FIGMODEL}->web();
			} elsif ($keyList[$i] eq "FIGMODELdatabase") {
				$self->{"_".$keyList[$i]} = $self->{_FIGMODEL}->database();
			} elsif ($keyList[$i] eq "FIG") {
				$self->{"_".$keyList[$i]} = $self->{_FIGMODEL}->fig();
			} elsif ($keyList[$i] =~ m/FIGMODELmodel\((.+)\)/) {
				$self->{"_".$keyList[$i]} = $self->{_FIGMODEL}->get_model($1);
			}
		}
	}
	#Creating data table from object list
	my $DataTable;
	for (my $i=0; $i < @{$self->{_objects}}; $i++) {
		$DataTable->[$i] = $self->load_object_data_into_table_row($self->{_objects}->[$i]);
	}
	#Sorting
	if (defined($self->{_table_parameters}->{sort_column})) {
		my $columnIndex = 0;
		for (my $i=0; $i < @{$self->{_columns}}; $i++) {
			if ($self->{_columns}->[$i]->{name} eq $self->{_table_parameters}->{sort_column}) {
				$columnIndex = $i;
				last;
			}	
		}
		if (defined($DataTable)) {
			if (defined($self->{_table_parameters}->{sort_descending}) && $self->{_table_parameters}->{sort_descending} == 1) {
				@{$DataTable} = sort { $b->[$columnIndex] cmp $a->[$columnIndex] } @{$DataTable};
			} else {
				@{$DataTable} = sort { $a->[$columnIndex] cmp $b->[$columnIndex] } @{$DataTable};
			}
		}
	}
	#Placing the data in the table
	$table->data($DataTable);
	#Generating html
	my $ColumnNames;
	for (my $i=0; $i < @{$self->{_columns}}; $i++) {
		push(@{$ColumnNames},$self->{_columns}->[$i]->{name});
	}
	my $html = $table->output();
  	$html .= "\n".'<input type="hidden" id="'.$table->id().'_column_names" value="'.join(",",@{$ColumnNames}).'">'."\n";
	return $html;
}

sub require_javascript {
	return ["$Conf::cgi_url/Html/ModelTable.js"];
}

=head3 load_object_data_into_table_row
Definition:
	[string]:table row = ObjectTable->load_object_data_into_table_row(Object:Input object for row);
Description:
	Loads the input object into a table row and returns the row reference
=cut
sub load_object_data_into_table_row {
	my ($self,$object) = @_;

	my $output;
	for (my $i=0; $i < @{$self->{_columns}}; $i++) {
		#First obtaining the raw data
		my $rawData = [""];
		if ($self->{_columns}->[$i]->{call} =~ m/HASH:(.+)/) {
			my $temp = $object->{$1};
			if (ref($temp) eq "ARRAY") {
				$rawData = [];
				push(@{$rawData},@{$temp});
			} else {
				$rawData->[0] = $temp;
			}
		} elsif ($self->{_columns}->[$i]->{call} =~ m/FUNCTION:(.+)/) {
			my $temp = $object->$1();
			if (ref($temp) eq "ARRAY") {
				$rawData = [];
				push(@{$rawData},@{$temp});
			} else {
				$rawData->[0] = $temp;
			}
		} elsif ($self->{_columns}->[$i]->{call} eq "THIS") {
			$rawData->[0] = $object;
		}
		#Processing raw data with the specified function
		if (defined($self->{_columns}->[$i]->{function})) {
			my @tempList = split(/:/,$self->{_columns}->[$i]->{function});
			for (my $j=0; $j < @{$rawData}; $j++) {
				my $function = $tempList[1];
				my @arguments;
				if ($function =~ m/\((.+)\)/) {
					@arguments = split(",",$1);
					$function = substr($function,0,length($function)-2-length($1));
				}
				if ($self->{_columns}->[$i]->{input}) {
					$self->{_columns}->[$i]->{input}->{data} = $rawData->[$j];
					$rawData->[$j] = $self->{"_".$tempList[0]}->$function($self->{_columns}->[$i]->{input});
				} else {
					$rawData->[$j] = $self->{"_".$tempList[0]}->$function($rawData->[$j],@arguments);
				}
			}
		}
		#Joining by the specified delimiter
		for (my $j=0; $j < @{$rawData}; $j++) {
			if (!defined($rawData->[$j])) {
				$rawData->[$j] = "";	
			}	
		}
		$output->[$i] = join($self->{_columns}->[$i]->{delimiter},@{$rawData});
	}
	return $output;
}


=head3 base_table
Definition:
	Table:base table component = ObjectTable->base_table();
Description:
	Returns the base table component inherited by the ObjectTable
=cut
sub base_table {
	my ($self) = @_;
	return $self->application()->component($self->{_tablecomponent});
}
