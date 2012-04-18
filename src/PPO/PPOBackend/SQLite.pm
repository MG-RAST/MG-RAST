package PPOBackend::SQLite;

# PPOBackend::SQLite - SQLite backend for PPO

# $Id: SQLite.pm,v 1.6 2009/06/02 07:46:01 paczian Exp $

use strict;
use warnings;

use DBI;

use base qw( PPOBackend );

1;


=pod

=head1 NAME

PPOBackend::SQLite - SQLite backend for PPO

=head1 DESCRIPTION

This package implements the abstract PPOBackend wrapper for use with SQLite database
server (based on the DBI perl module).

=head1 METHODS

=over 4

=item * B<new> (I<database>, I<create_flag>)

Connects to the database backend using the database file I<database>. 
If I<create_flag> is set, new will create the database before connecting
to it.

=cut

sub new {
  my ($class, $database, $create) = @_;
  
  unless ($database) {
    Confess("No database given.");
  }

  # test if database to be created already exists
  if ($create and -f $database) {
    Confess("Database $database already exists.");
  }
  
  # test if database does not exist (and we are creating one)
  unless ($create or -f $database) {
    Confess("Unable to find database file $database.");
  }
  
  # initialize database handle
  my $connect = "DBI:SQLite:dbname=$database";
  my $dbh = DBI->connect($connect, '', '', { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) || Confess("Database connect error.");
  
  my $self = { 'dbhandle' => $dbh,
	       'source'   => $database,
	       'connect'  => $connect, 
	       'database_name' => 'main',
	     };
  bless ($self,$class);

  return $self;

}

=pod

=item * B<new_from_connect_data> (I<connect_data>, I<database>)

Connects to the database backend using the I<connect_data> string which is 
stored by the PPO when an object reference is created. The parameter 
I<database_name> specifies the database to use and is mandatory. 
The SQLite backend is able to connect without any additional I<connect_data>
and just calls B<new> with the I<database> name.

=cut

sub new_from_connect_data {
  return $_[0]->new($_[2],0);
}


=pod

=item * B<last_insert_id> ()

Returns the row id of the last insert command.

=cut

sub last_insert_id {
  return $_[0]->dbh->func('last_insert_rowid');
}


=pod

=item * B<map_data_type> (I<data_type>)

Returns the mapping of a PPO datatype (read from the xml definition file) to
the column data type of the database table. 

=cut

sub map_data_type {
  my ($self, $type) = @_;
  
  $type = uc($type);

  my $types = { 'BOOLEAN'   => 'INTEGER',
		'INTEGER'   => 'INTEGER',
		'FLOAT'     => 'REAL',
		'TIMESTAMP' => 'TEXT',
		'CHAR'      => 'TEXT',
		'TEXT'      => 'TEXT',
		'TEXT LONG' => 'TEXT',
		'BLOB'      => 'BLOB',
		'BLOB LONG' => 'BLOB',
	      };
  
  # simple data type
  if (exists($types->{$type})) {
    return $types->{$type};
  }
  # special case for CHAR(n)
  elsif ($type =~ /^CHAR\(\d+\)$/ or $type =~ /^CHAR \(\d+\)$/) {
    return $types->{'CHAR'};
  }
  # error
  else {
    Confess("Unknown data type '$type'.");
  }

}


=pod

=item * B<create_table> (I<table>, I<columns>)

Create a new table I<table> in the database with the columns described in 
I<columns>. The parameter I<columns> is an array of hashes. Each hash describes
one column and has the fields 'name', 'type', 'not_null', 'auto_increment' and
'primary_key'.

=cut

sub create_table {
  my ($self, $table, $columns) = @_;

  my @cols;
  foreach my $c (@$columns) {
    unless ($c->{name} and $c->{type}) {
      die 'Method create_table called with incomplete parameters.';
    }
    my $column = $c->{name}.' '.$self->map_data_type($c->{type});
    $column .= ' NOT NULL' if ($c->{not_null}); 
    $column .= ' PRIMARY KEY' if ($c->{primary_key});
    $column .= ' AUTOINCREMENT' if ($c->{auto_increment});
    push @cols, $column;
  }

  my $statement = sprintf ("CREATE TABLE %s ( %s )", $table, join(', ', @cols));
  eval {
    
    $self->dbh->do($statement);
    $self->dbh->commit;

  };

  if ($@) {
    eval { $self->dbh->rollback };
    if ($@) {
      Confess("Rollback failed: $@");
    }
    return undef;
  }

  return 1;

}


=pod

=item * B<create_index> (I<table>, I<columns>, I<unique>)

Create a new index on table I<table> in the database with the columns indexed given 
in I<columns>. The parameter I<columns> is a reference to an array of column names. 
If I<unique> is given and evaluates to true, the method will create an unique index.

=cut

sub create_index {
  my ($self, $table, $index_name, $columns, $unique) = @_;

  my $unique_string = ($unique) ? ' UNIQUE' : '';
  my $statement = sprintf ("CREATE%s INDEX %s ON %s ( %s )", 
			   $unique_string, $index_name, $table, join(', ', @{$columns}));

  eval {
    
    $self->dbh->do($statement);
    $self->dbh->commit;

  };

  if ($@) {
    eval { $self->dbh->rollback };
    if ($@) {
      Confess("Rollback failed: $@");
    }
    return undef;
  }

  return 1;

}
