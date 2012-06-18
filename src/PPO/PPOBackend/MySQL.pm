package PPOBackend::MySQL;

# PPOBackend::MySQL - MySQL backend for PPO

# $Id: MySQL.pm,v 1.11 2010-03-23 13:57:51 paczian Exp $

use strict;
use warnings;

use DBI;

use base qw( PPOBackend );

1;


=pod

=head1 NAME

PPOBackend::MySQL - MySQL backend for PPO

=head1 DESCRIPTION

This package implements the abstract PPOBackend wrapper for use with MySQL database
server (based on the DBI perl module).

=head1 METHODS

=over 4

=item * B<new> (I<host>, I<port>, I<database>, I<user>, I<password>, I<create_flag>)

Connects to the database backend using the database host I<host> on port I<port>. 
If either I<host> or I<port> is false (undef), it uses the default host or port. 
The parameter I<database_name> specifies the database to use and is mandatory. 

The parameters I<user> and I<password> are optional. If set to a username and it's
cleartext password, those information will be used to authenticate with the database.

If I<create_flag> is set, new will create the database before connecting
to it.

=cut

sub new {
  my ($class, $host, $port, $database, $user, $password, $create, $socket, $file) = @_;

  # build connect string from parameters
  my $connect = "DBI:mysql:".( ($create) ? '' : "database=$database" );
  $connect .= ";host=$host" if ($host);
  $connect .= ";port=$port" if ($port);
  $connect .= ";mysql_socket=$socket" if ($socket);
  my $dbsock = $Conf::dbsock;
  $connect .= ";mysql_socket=$dbsock" if ($dbsock);
  $user = (defined $user) ? $user : '';
  $password = (defined $password) ? $password : '';

  # initialize database handle.
  my $dbh = DBI->connect($connect, $user, $password, 
			 { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			   Confess("Database connect error.");
  
  my $self = { 'dbhandle' => $dbh,
	       'source'   => $database,
	       'connect'  => $connect, 
	       'database_name' => $database,
	       'file'     => $file
	     };
  bless ($self,$class);

  # create database if necessary
  if ($create && !$file) { 
    
    eval {
      $self->dbh->do( "CREATE DATABASE $database");
      $self->dbh->do( "USE $database");
      $self->dbh->commit;
      
    };
    
    if ($@) {
      eval { $self->dbh->rollback };
      if ($@) {
	Confess("Rollback failed: $@");
      }
      return undef;
    }
  }

  return $self;

}


=pod

=item * B<new_from_connect_data> (I<connect_data>, I<database>, I<user>, I<password>)

Connects to the database backend using the I<connect_data> string which is stored
by the PPO when an object reference is created. The parameter I<database_name> 
specifies the database to use and is mandatory. 

The parameters I<user> and I<password> are optional. If set to a username and it's
cleartext password, those information will be used to authenticate with the database.

=cut

sub new_from_connect_data {
  my ($class, $connect, $database, $user, $password) = @_;

  $user = (defined $user) ? $user : '';
  $password = (defined $password) ? $password : '';

  # initialize database handle
  my $dbh = DBI->connect($connect, $user, $password, 
			 { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
            Confess("Database connect error.");

  my $self = { 'dbhandle' => $dbh,
	       'source'   => $database,
	       'connect'  => $connect, 
	       'database_name' => $database,
	     };
  bless ($self,$class);
  return $self;

}

=pod

=item * B<last_insert_id> ()

Returns the row id of the last insert command.

=cut

sub last_insert_id {
  return $_[0]->dbh->{'mysql_insertid'};
}


=pod

=item * B<map_data_type> (I<data_type>)

Returns the mapping of a PPO datatype (read from the xml definition file) to
the column data type of the database table. 

=cut

sub map_data_type {
  my ($self, $type) = @_;

  $type = uc($type);

  my $types = { 'BOOLEAN'   => 'BOOLEAN',
		'INTEGER'   => 'INTEGER',
		'BIGINT'    => 'BIGINT',
		'FLOAT'     => 'DOUBLE',
		'TIMESTAMP' => 'TIMESTAMP',
		'CHAR'      => 'VARCHAR',
		'TEXT'      => 'TEXT',
		'TEXT LONG' => 'LONGTEXT',
		'BLOB'      => 'BLOB',
		'BLOB LONG' => 'LONGBLOB',
	      };
  
  # simple data type
  if (exists($types->{$type})) {
    return $types->{$type};
  }
  # special case for CHAR(n)
  elsif ($type =~ /^CHAR\((\d+)\)$/ or $type =~ /^CHAR \((\d+)\)$/) {
    return "VARCHAR($1)";
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
    $column .= ' AUTO_INCREMENT' if ($c->{auto_increment});
    push @cols, $column;
  }

  my $statement = sprintf ("CREATE TABLE %s ( %s )", $table, join(', ', @cols));
  eval {
    if ($self->{file}) {
      open(FH, ">>".$self->{file}) or die "could not open sql output file ".$self->{file}.": $@ $!\n";
      print FH $statement."\n";
      close FH;
    } else {
      $self->dbh->do($statement);
      $self->dbh->commit;
    }

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
    if ($self->{file}) {
      open(FH, ">>".$self->{file}) or die "could not open sql output file ".$self->{file}.": $@ $!\n";
      print FH $statement."\n";
      close FH;
    } else {
      $self->dbh->do($statement);
      $self->dbh->commit;
    }

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
