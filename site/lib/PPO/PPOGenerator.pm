package PPOGenerator;

# PPOGenerator - PPO class to generate perl modules and database

# $Id: PPOGenerator.pm,v 1.5 2010-08-16 20:12:06 wilke Exp $

use strict;
use warnings;

use XML::Simple;

use PPOBackend;

use constant TABLE_TYPE_OBJECT  => 1;
use constant TABLE_TYPE_DERIVED => 2;

use constant ID_DATA_TYPE => 'INTEGER';

use constant RESERVED => qw(
			    ADD
			    ALL 	
			    ALTER
			    ANALYZE
			    AND
			    AS
			    ASC
			    ASENSITIVE
			    BEFORE
			    BETWEEN
			    BIGINT
			    BINARY
			    BLOB
			    BOTH
			    BY
			    CALL
			    CASCADE
			    CASE
			    CHANGE
			    CHAR
			    CHARACTER
			    CHECK
			    COLLATE
			    COLUMN
			    CONDITION
			    CONNECTION
			    CONSTRAINT
			    CONTINUE
			    CONVERT
			    CREATE
			    CROSS
			    CURRENT_DATE
			    CURRENT_TIME
			    CURRENT_TIMESTAMP
			    CURRENT_USER
			    CURSOR
			    DATABASE
			    DATABASES
			    DAY_HOUR
			    DAY_MICROSECOND
			    DAY_MINUTE
			    DAY_SECOND
			    DEC
			    DECIMAL
			    DECLARE
			    DEFAULT
			    DELAYED
			    DELETE
			    DESC
			    DESCRIBE
			    DETERMINISTIC
			    DISTINCT
			    DISTINCTROW
			    DIV
			    DOUBLE
			    DROP
			    DUAL
			    EACH
			    ELSE
			    ELSEIF
			    ENCLOSED
			    ESCAPED
			    EXISTS
			    EXIT
			    EXPLAIN
			    FALSE
			    FETCH
			    FLOAT
			    FLOAT4
			    FLOAT8
			    FOR
			    FORCE
			    FOREIGN
			    FROM
			    FULLTEXT
			    GRANT
			    GROUP
			    HAVING
			    HIGH_PRIORITY
			    HOUR_MICROSECOND
			    HOUR_MINUTE
			    HOUR_SECOND
			    IF
			    IGNORE
			    IN
			    INDEX
			    INFILE
			    INNER
			    INOUT
			    INSENSITIVE
			    INSERT
			    INT
			    INT1
			    INT2
			    INT3
			    INT4
			    INT8
			    INTEGER
			    INTERVAL
			    INTO
			    IS
			    ITERATE
			    JOIN
			    KEY
			    KEYS
			    KILL
			    LEADING
			    LEAVE
			    LEFT
			    LIKE
			    LIMIT
			    LINES
			    LOAD
			    LOCALTIME
			    LOCALTIMESTAMP
			    LOCK
			    LONG
			    LONGBLOB
			    LONGTEXT
			    LOOP
			    LOW_PRIORITY
			    MATCH
			    MEDIUMBLOB
			    MEDIUMINT
			    MEDIUMTEXT
			    MIDDLEINT
			    MINUTE_MICROSECOND
			    MINUTE_SECOND
			    MOD
			    MODIFIES
			    NATURAL
			    NOT
			    NO_WRITE_TO_BINLOG
			    NULL
			    NUMERIC
			    ON
			    OPTIMIZE
			    OPTION
			    OPTIONALLY
			    OR
			    ORDER
			    OUT
			    OUTER
			    OUTFILE
			    PRECISION
			    PRIMARY
			    PROCEDURE
			    PURGE
			    RAID0
			    READ
			    READS
			    REAL
			    REFERENCES
			    REGEXP
			    RELEASE
			    RENAME
			    REPEAT
			    REPLACE
			    REQUIRE
			    RESTRICT
			    RETURN
			    REVOKE
			    RIGHT
			    RLIKE
			    SCHEMA
			    SCHEMAS
			    SECOND_MICROSECOND
			    SELECT
			    SENSITIVE
			    SEPARATOR
			    SET
			    SHOW
			    SMALLINT
			    SONAME
			    SPATIAL
			    SPECIFIC
			    SQL
			    SQLEXCEPTION
			    SQLSTATE
			    SQLWARNING
			    SQL_BIG_RESULT
			    SQL_CALC_FOUND_ROWS
			    SQL_SMALL_RESULT
			    SSL
			    STARTING
			    STRAIGHT_JOIN
			    TABLE
			    TERMINATED
			    THEN
			    TINYBLOB
			    TINYINT
			    TINYTEXT
			    TO
			    TRAILING
			    TRIGGER
			    TRUE
			    UNDO
			    UNION
			    UNIQUE
			    UNLOCK
			    UNSIGNED
			    UPDATE
			    USAGE
			    USE
			    USING
			    UTC_DATE
			    UTC_TIME
			    UTC_TIMESTAMP
			    VALUES
			    VARBINARY
			    VARCHAR
			    VARCHARACTER
			    VARYING
			    WHEN
			    WHERE
			    WHILE
			    WITH
			    WRITE
			    X509
			    XOR
			    YEAR_MONTH
			    ZEROFILL
			   );


1;


=pod

=head1 NAME

PPOGenerator - PPO class to generate perl modules and database

=head1 DESCRIPTION

This module reads the object schema from the xml definition file. It's methods
generate perl packages for each object and create the database and tables for 
storage of the persistent perl objects.

=head1 METHODS

=over 4

=item * B<new> (I<xml_definition_file>)

Connects to the database backend using the database file I<database_filename>.

=cut

sub new {
  my ($class, $xmlfile) = @_;

  # open and read the xml file
  my $xml = XMLin($xmlfile, ForceArray => 1 );

  # reserved words
  my %r = map { lc($_) => 1 } RESERVED;

  my $self = { 'xmlfile' => $xmlfile,
	       'definition' => $xml,
	       'objects' => $xml->{'object'},
	       'module' => $xml->{'label'},
	       'tables' => {},
	       'reserved' => \%r,
	       };
  bless $self, $class;

  # check if module name starts with a capital letter
  unless ($self->module =~ /^[A-Z]+/) {
    die "Module name must start with a capital Letter.";
  }

  # iterate through all objects of the data schema and generate tables
  foreach my $object (@{$self->objects}) {
    $self->mktable($object) || die "Could not make table\n";
  }

  # check for reserved words
  foreach my $table (keys(%{$self->tables})) {
    if ($self->is_reserved($table)) {
      die "Object definition contains a reserved word: $table\n";
    }
    foreach my $col (keys(%{$self->tables->{$table}->{cols}})) {
      if ($self->is_reserved($col)) {
	die "Object definition contains a reserved word: ${table}::$col\n";
      }
    }
  }

  return $self;

}


=pod 

=item * B<mktable> (I<object>)

Internal method which reads an object description from the xml and turns it
into a relational table. It also collects the information necessary to create
(unique) indexes on the tables.

=cut

sub mktable {
  my ($self, $object) = @_;
  
  $self->tables->{ $object->{label} }->{type} = TABLE_TYPE_OBJECT;

  # process arrays
  if (exists($object->{array})) {
    foreach my $array (@{$object->{array}}) {

      # create table for array object references
      if (exists($array->{object_ref})) {
	foreach my $array_obj (@{$array->{object_ref}}) {
	  
	  if (defined($array_obj->{mandatory})) {
	    $self->tables->{$object->{label}}->{mandatory}->{$array_obj->{label}} = $array_obj->{mandatory};
	  }

	  my $array_table_label = $object->{label}.'_'.$array_obj->{label};
	  $self->tables->{ $array_table_label }->{type} = TABLE_TYPE_DERIVED;
	  $self->tables->{ $array_table_label }->{cols}->{_array_index} = ID_DATA_TYPE;
	  $self->tables->{ $array_table_label }->{cols}->{_source_id} = ID_DATA_TYPE;
	  $self->tables->{ $array_table_label }->{cols}->{_target_id} = ID_DATA_TYPE;
	  $self->tables->{ $array_table_label }->{cols}->{_target_db} = ID_DATA_TYPE;

	  $self->tables->{ $object->{label} }->{cols}->{ $array_obj->{label} } = 'array ' .$array_obj->{type};
	  
	}
      }
      
      # create table for array scalars
      if (exists($array->{scalar})) {	
	foreach my $array_scalar (@{$array->{scalar}}) {
	  
	  if (defined($array_scalar->{mandatory})) {
	    $self->tables->{$object->{label}}->{mandatory}->{$array_scalar->{label}} = $array_scalar->{mandatory};
	  }

	  my $array_table_label = $object->{label}.'_'.$array_scalar->{label};
	  $self->tables->{ $array_table_label }->{type} = TABLE_TYPE_DERIVED;
	  $self->tables->{ $array_table_label }->{cols}->{_array_index} = ID_DATA_TYPE;
	  $self->tables->{ $array_table_label }->{cols}->{_source_id} = ID_DATA_TYPE;
	  $self->tables->{ $array_table_label }->{cols}->{_value} = $array_scalar->{type};

	  $self->tables->{ $object->{label} }->{cols}->{ $array_scalar->{label} } = 'array';
	  
	}
      }
    }
  }
  
  # process scalar attributes
  if (exists($object->{scalar})) {
    foreach my $scalar (@{$object->{scalar}}) {

      if (defined($scalar->{mandatory})) {
	$self->tables->{$object->{label}}->{mandatory}->{$scalar->{label}} = $scalar->{mandatory};
      }

      if (defined($scalar->{default})) {
	$self->tables->{$object->{label}}->{defaults}->{$scalar->{label}} = $scalar->{default};
      }
      $self->tables->{$object->{label}}->{cols}->{$scalar->{label}} = $scalar->{type};
    }
  }

  # process object attributes
  if (exists($object->{object_ref})) {
    foreach my $object_ref (@{$object->{object_ref}}) {

      if (defined($object_ref->{mandatory})) {
	$self->tables->{ $object->{label} }->{mandatory}->{ $object_ref->{label} } = $object_ref->{mandatory};
      }

      if (defined($object_ref->{default})) {
	$self->tables->{ $object->{label} }->{defaults}->{ $object_ref->{label} } = $object_ref->{default};
      }
      $self->tables->{ $object->{label} }->{cols}->{ $object_ref->{label} } = "fkey " . $object_ref->{type};
    }
  }

  # process unique indeces
  if (exists($object->{unique_index})) {
    foreach my $index (@{$object->{unique_index}}) {
      my $current_index = [];
      foreach (@{$index->{attribute}}) {
	push(@$current_index, $_->{label});
      }
      push(@{$self->tables->{$object->{label}}->{unique_indices}}, $current_index);
    }
  }

  # process indeces
  if (exists($object->{index})) {
    foreach my $index (@{$object->{index}}) {
      my $current_index = [];
      foreach (@{$index->{attribute}}) {
	push(@$current_index, $_->{label});
      }
      push(@{$self->tables->{$object->{label}}->{indices}}, $current_index);
    }
  }

  return $self;
}


=pod 

=item * B<tables> ()

Returns the reference to the tables hash.

=cut

sub tables {
  return $_[0]->{'tables'};
}


=pod 

=item * B<module> ()

Returns the name of the module.

=cut

sub module {
  return $_[0]->{'module'};
}


=pod 

=item * B<objects> ()

Returns the reference to the objects hash.

=cut

sub objects {
  return $_[0]->{'objects'};
}


=pod 

=item * B<is_reserved> (I<word>)

Returns true if I<word> is a reserved word, else undef.

=cut

sub is_reserved {
  return exists($_[0]->{'reserved'}->{lc($_[1])});
}



sub generate_perl {
  my ($self, $target_dir) = @_;

  my $module = $self->module;
  my $dir = $target_dir.$module;
  unless (-d $dir) {
    mkdir($dir, 0755);
  }

  # create ObjectBase.pm code
  my $perl = <<PERL_END;
use strict;
use warnings;
no warnings qw(redefine);

1;

# this class is AUTOGENERATED and will be AUTOMATICALLY REGENERATED
# all work done in this module will be LOST

PERL_END
  
  foreach my $key (keys(%{$self->tables})) {

    # get every object table
    if ($self->tables->{$key}->{type} eq TABLE_TYPE_OBJECT) {

      # get all the attributes
      my $attributes = "";
      foreach my $attribute (keys(%{$self->tables->{$key}->{cols}})) {
	
	my $type = $self->tables->{$key}->{cols}->{$attribute};
	
	my $parsedtype = "";
	if ($type =~ /^array$/) {
	  $parsedtype = "DB_ARRAY_OF_SCALARS, undef, ";
	} 
	elsif ($type =~ /^array (.+)/) {
	  my $object_type = $1;
	  unless ($object_type =~ /::/) {
	    $object_type = $module . "::" . $object_type;
	  }
	  $parsedtype = "DB_ARRAY_OF_OBJECTS, \"$object_type\", ";
	} 
	elsif ($type =~ /^fkey (.+)/) {
	  my $object_type = $1;
	  unless ($object_type =~ /::/) {
	    $object_type = $module . "::" . $object_type;
	  }
	  $parsedtype = "DB_OBJECT, \"$object_type\", ";
	} 
	else {
	  $parsedtype = "DB_SCALAR, undef, ";
	}
	
	# check for mandatory attribute
	$parsedtype .= $self->tables->{$key}->{mandatory}->{$attribute} ? '1, ' : '0, ';

	# check for default attribute value
	$parsedtype .= (exists($self->tables->{$key}->{defaults}->{$attribute})) 
	  ? '"'.$self->tables->{$key}->{defaults}->{$attribute}.'"' : 'undef';

	$attributes .= "\t\t$attribute => [ $parsedtype ],\n";
      }

      # get all unique indices
      my $unique_indices = "\t\t[\n";
      foreach my $unique_index (@{$self->tables->{$key}->{unique_indices}}) {
	$unique_indices .= "\t\t\t[ " . join(', ', map { "\"" . $_ . "\"" } @$unique_index) . " ],\n";
      }
      $unique_indices .= "\t\t]";

      # get all indices
      my $indices = "\t\t[\n";
      foreach my $index (@{$self->tables->{$key}->{indices}}) {
	$indices .= "\t\t\t[ " . join(', ', map { "\"" . $_ . "\"" } @$index) . " ],\n";
      }
      $indices .= "\t\t]";
      
      # write package into ObjectBase.pm
      $perl .= <<PERL_END;

package $module\::$key;

use DBObject;
use base qw(DBObject);

sub attributes {
     return {
$attributes\t};
}

sub unique_indices {
     return 
$unique_indices;
}

sub indices {
     return 
$indices;
}

1;
PERL_END

      # write object stub code
      unless (-f "$dir/$key\.pm") {

        my $stub = <<PERL_END;
package $module\::$key;

use strict;
use warnings;

1;

# this class is a stub, this file will not be automatically regenerated
# all work in this module will be saved

PERL_END

        open(STUB, "> $dir/$key\.pm") || die "can't open $dir/$key\.pm\n";
        print STUB $stub;
        close(STUB);
      } 
    }
  }
  
  # write ObjectBase.pm file
  open(FILE, "> $dir/ObjectBase\.pm") || die "can't open $dir/ObjectBase\.pm\n";
  print FILE $perl;
  close(FILE);

  return 1;
}



sub create_database {
  my $self = shift;
  my $backend = PPOBackend->new(@_);

  if (ref $backend) {
    
    # meta information table
    $backend->create_table( '_metainfo', [ { 'name' => '_id', 'type' => ID_DATA_TYPE, 'not_null' => 1, 
					     'primary_key' => 1, 'auto_increment' => 1 },
					   { 'name' => 'info_name', 'type' => 'CHAR(255)' },
					   { 'name' => 'info_value', 'type' => 'CHAR(255)' }, 
					 ] 
			  );

    $backend->insert_row( '_metainfo', { 'info_name'  => 'module_name',
					 'info_value' => $self->module } );


    # object reference table
    $backend->create_table( '_references', [ { 'name' => '_id', 'type' => ID_DATA_TYPE, 'not_null' => 1, 
					       'primary_key' => 1, 'auto_increment' => 1 },
					     { 'name' => '_database', 'type' => 'CHAR(512)' },
					     { 'name' => '_backend_type', 'type' => 'CHAR(255)' },
					     { 'name' => '_backend_data', 'type' => 'CHAR(1024)' },
					   ] 
			  );

    # objects table
    $backend->create_table( '_objects', [ { 'name' => '_id', 'type' => ID_DATA_TYPE, 'not_null' => 1, 
					    'primary_key' => 1, 'auto_increment' => 1 },
					  { 'name' => 'object', 'type' => 'CHAR(255)' },
					] 
			  );
    
    # build the individual tables
    foreach my $table (keys(%{$self->tables})) {

      # add to objects table if an object (that is not a derived table)
      if ($self->tables->{$table}->{type} eq TABLE_TYPE_OBJECT) {
	$backend->insert_row( '_objects', { 'object'  => $table } );
      }

      # start with the primary key index
      my $columns = [ { 'name' => '_id', 'type' => ID_DATA_TYPE, 'not_null' => 1, 
			'primary_key' => 1, 'auto_increment' => 1 } ];
 
      foreach my $attribute (keys(%{$self->tables->{$table}->{cols}})) {
	
	my $type = $self->tables->{$table}->{cols}->{$attribute};
	
	# array attributes
	if ($type =~ /^array/) {
	  next;
	}
	# object attributes
	elsif ($type =~ /^fkey/) {
	  push @$columns, { 'name' => $attribute, 'type' => ID_DATA_TYPE };
	  push @$columns, { 'name' => '_'.$attribute.'_db', 'type' => ID_DATA_TYPE };
	}
	# scalar attribute
	else {
	  push @$columns, { 'name' => $attribute, 'type' => $type };
	}

      }
		
      $backend->create_table( $table, $columns );
      
      # TODO: index on TEXT

      # create all requested unique indexes
      my $uindex = 0;
      foreach my $ui_cols (@{$self->tables->{$table}->{unique_indices}}) {
	$backend->create_index( $table, $table.'_unique_'.$uindex, 
				$self->process_index_columns($table, $ui_cols), 1 );
	$uindex++;
      }


      # create all requested non-unique indexes
      my $index = 0;
      foreach my $i_cols (@{$self->tables->{$table}->{indices}}) {
	$backend->create_index( $table, $table.'_'.$index, 
				$self->process_index_columns($table, $i_cols) );
	$index++;
      }
          
    }

    $backend->disconnect;
    return 1;
        
  }
  else {
    die "Unable to connect to database backend.";
  }
}



sub process_index_columns {
  my ($self, $table, $cols) = @_;

  # process index columns
  my $new = [];
  foreach (@$cols) {
    if (exists $self->tables->{$table}->{cols}->{$_}) {
      my $type = $self->tables->{$table}->{cols}->{$_};
	    
      # array attributes
      if ($type =~ /^array/) {
	die "Died on attempt to build index on array attribute '$_' in $table.";
      }
      # object attributes
      elsif ($type =~ /^fkey/) {
	push @$new, ($_, '_'.$_.'_db'); 
      }
      # scalar attribute
      else {
	push @$new, $_;
      }
    }
    else {
      die "Unknown attribute '$_' in index definition.";
    }
  }
  
  return $new;
}
