package PPOBackend;

# PPOBackend - abstract backend class for PPO

# $Id: PPOBackend.pm,v 1.13 2011-02-11 04:52:16 chenry Exp $

use strict;
use warnings;
use DBI;

use HTML::Strip;
use Scalar::Util qw(looks_like_number);

=pod

=head1 NAME

PPOBackend - abstract backend class for PPO

=head1 DESCRIPTION

The PPOBackend class defines an abstract wrapper around basic database operations.
Since currently we only support backends based on DBI, some of the functionality
is contained in the module for the abstract class. 

=head1 METHODS

=over 4

=item * B<new> ()

Connects to the database backend using the named parameters given. It will connect
to the database I<-database> and depending on the backend specified in I<-backend> 
it will recognise other parameters. 

I<-backend> 'MySQL' knows database host I<-host> and port I<-port>, as well as the
database user I<-user> and password I<-password>. Both are optional. If set to a username 
and it's cleartext password, those information will be used to authenticate with the database.

I<-backend> 'SQLite' only requires the database name, which has to be a file 
readable by the user running the perl script.

I<-create> causes the backend to create the database from scratch (fails if the database
already exists).

Since PPOBackend is supposed to be abstract this constructor will try to load a
class inherited from PPOBackend.

=cut

sub new {
  my $class = shift;
  my %params = @_;

  # initialise the backend module
  my $backend = $params{-backend} || 'MySQL';
  my $package = "PPOBackend::$backend";
  eval "require $package;";  
  if ($@) {
    Confess("Failed on require backend PPOBackend::$backend: $@");
  }

  if ($backend eq 'MySQL') {
    if ($params{-connect_data}) {
      return PPOBackend::MySQL->new_from_connect_data($params{-connect_data},
						      $params{-database},
						      $params{-user},
						      $params{-password},
						     );
    }
    else {
      return PPOBackend::MySQL->new($params{-host},
				    $params{-port},
				    $params{-database},
				    $params{-user},
				    $params{-password},
				    $params{-create},
				    $params{-socket},
				    $params{-file}
				   );
    }
  }
  elsif ($backend eq 'SQLite') {
    if ($params{-connect_data}) {
      return PPOBackend::SQLite->new_from_connect_data($params{-connect_data},
						       $params{-database},
						      );
    }
    else {
      return PPOBackend::SQLite->new($params{-database},
				     $params{-create},
				    );
    }
  }
  else {
    Confess("Unknown database backend $backend.");
  }
}


=pod 

=item * B<connect_data> ()

Returns the connection data string. 

=cut

sub connect_data {
  return $_[0]->{'connect'};
}


=pod 

=item * B<type> ()

Returns the type of the PPOBackend

=cut

sub type {
  ref($_[0]) =~ /\w*::(.*)/; 	
  return $1;
}


=pod 

=item * B<dbh> ()

Returns the DBI handle.

=cut

sub dbh {
  return $_[0]->{'dbhandle'};
}


=pod 

=item * B<database> ()

Returns the name of the database.

=cut


sub database {
  return $_[0]->{'source'};
}


=pod 

=item * B<get_table_name> ()

Returns the composite name of database and table for this backend,
ie 'database.table'. Necessary because sqlite always calls it's 
first database 'main'.

=cut


sub get_table_name {
  Confess("No table name given.") unless ($_[1]);
  return $_[0]->{'database_name'}.'.'.$_[1];
}


=pod

=item * B<last_insert_id> ()

Returns the row id of the last insert command. 

=cut

sub last_insert_id {
  Confess("Abstract method 'last_insert_id' called in ".__PACKAGE__.".");
}


=pod 

=item * B<get_rows> (I<table>, I<fields>, I<conditions>, I<options>)

Fetch the columns from the array reference I<fields> from the rows of table I<table> 
that meet the conditions described in I<conditions>. Both I<fields> and I<conditions> 
are optional, if both are missing, this method acts as a select all.

The parameter I<options> is optional. It is a hash reference with the following keys
currently recognised: 
sort_by: reference to an array of column names
sort_order: ascending (default) | descending
row_as_hash: return a row as a hash if set to true

Returns an array reference of array references for the fields of each row.

=cut

sub get_rows {
  my ($self, $table, $fields, $conditions, $options) = @_;
  
  my $sort_order = '';
  if ($options->{'sort_by'} and $options->{'sort_order'}) { 
    $sort_order = ($options->{'sort_order'} eq 'descending')
      ? ' DESC' : ' ASC';
  }
  
  my $statement = sprintf ("SELECT %s FROM %s%s%s",
			   (@$fields) ? join (",", @$fields) : '*',
			   $table,
			   ($conditions) ? " WHERE $conditions" : '',
			   ($options->{'sort_by'}) ? " ORDER BY ".join(',',@{$options->{'sort_by'}}) : '',
			   $sort_order,
			  );
  my $data = [];
 
  eval {
    if ($options->{'row_as_hash'}) {
      
      my $sth = $self->dbh->prepare($statement);
      $sth->execute;
      while(my $row = $sth->fetchrow_hashref()) {
	push @$data, $row;
      }
      
      $sth->finish;
      
    }	
    else {
      $data = $self->dbh->selectall_arrayref($statement);
    }
  };

  if ($@) {
    return [];
  }
  
  return $data;

}

=pod 

=item * B<get_rows_for_ids> (I<table>, I<ids>)

Get the rows that correspond to the list of ids passed.

Returns an array reference of array references for the fields of each row.

=cut

sub get_rows_for_ids {
  my ($self, $table, $ids) = @_;

  my $statement = "SELECT * FROM $table WHERE _id=?";

  my $data = [];
 
  eval {
    my $sth = $self->dbh->prepare($statement);
    foreach my $id (@$ids) {
      $sth->execute($id);
      push(@$data, $sth->fetchrow_hashref());
    }
  };

  if ($@) {
    return [];
  }
  
  return $data;
}

=pod 

=item * B<get_row> (I<table>, I<fields>, I<conditions>)

Fetch the columns given by the array reference I<fields> from the first row of table I<table> 
that meets the conditions described in I<conditions>. Both I<fields> and I<conditions> 
are optional, if both are missing, this method acts as a select all, returning just one
row.

Returns a list of fields.

=cut

sub get_row {
  my ($self, $table, $fields, $conditions) = @_;

  my $statement = sprintf ("SELECT %s FROM %s%s",
			   (@$fields) ? join (",", @$fields) : '*',
			   $table,
			   ($conditions) ? " WHERE $conditions" : ''
			  );
  
  my @data;

  eval {
    @data = $self->dbh->selectrow_array($statement);
  };
  
  if ($@) {
    return ();
  }

  return @data;
}


=pod

=item * B<insert_row> (I<table>, I<data>)

Insert a new row into the table I<table>, assigning the data given in I<data> into
the fields of the row.  The parameter I<data> is a hash reference. The keys
of the hash define the fields to be set, the values the value that fields 
will be set to.

This method takes care of quoting the values.

=cut

sub insert_row {
  my ($self, $table, $data) = @_;

  my $statement = sprintf ("INSERT INTO %s (%s) VALUES (%s)",
			   $table,
			   (keys(%$data)) ? join (",", keys(%$data)) : '',
			   (keys(%$data)) ? join (",", map { $self->quote($_) } values(%$data)) : '',
			  );

  my $id;
  eval {
    if ($self->{file}) {
      open(FH, ">>".$self->{file}) or die "could not open sql output file ".$self->{file}.": $@ $!\n";
      print FH $statement."\n";
      close FH;
    } else {
      $self->dbh->do($statement);
      $id = $self->last_insert_id;
      $self->do_commit;
    }
    
  };

  if ($@) {
    eval { $self->dbh->rollback };
    if ($@) {
#      Confess("Rollback failed: $@");
    }
    return undef;
  }

  return $id;

}


=pod

=item * B<delete_rows> (I<table>, I<conditions>)

Delete one or more rows from the table I<table> which meet the conditions defined
in I<conditions>. Note that if I<conditions> is undefined it will drop the whole 
table!

=cut

sub delete_rows {
  my ($self, $table, $conditions) = @_;

  my $statement = sprintf ("DELETE FROM %s%s", $table,
			   ($conditions) ? " WHERE $conditions" : '',
			  );
  eval {

    $self->dbh->do($statement);
    $self->do_commit;

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

=item * B<update_row> (I<table>, I<data>, I<conditions>)

Update one ore more existing rows in table I<table> which meet the conditions
described in I<conditions>. The parameter I<data> is a hash reference. The keys
of the hash define the fields to be updated, the values the value that fields 
will be set to.

This method takes care of quoting the values.

Usually this method is called with the condition _id=$id, ensuring that only one
row is updated. The method itself does no checks what so ever!

=cut

sub update_row {
  my ($self, $table, $data, $conditions) = @_;

  my $statement = sprintf ("UPDATE %s SET %s%s", $table, 
			   join(',', map { $_.'='.$self->quote($data->{$_}) } keys(%$data)), 
			   ($conditions) ? " WHERE $conditions" : '',
			  );
  eval {
    
    $self->dbh->do($statement);
    $self->do_commit;

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

=item * B<begin_batch> (I<value>)

Usually the backend will commit a database transaction after each write 
operation. To avoid this time consuming step (eg. during script runs that 
create large batches of objects) set the commit interval to some number 
here.

Some operations are exempt from this: create table, create index 
and create database. 

Note: it is important to turn of batch mode before exiting by calling
I<end_batch> or else you will suffer data loss. ;)

=cut

sub begin_batch {

  # flush
  $_[0]->end_batch;
  # set commit interval
  if ($_[1]) {
    $_[0]->{commit_interval} = $_[1];
  }
  return $_[0]->{commit_interval};
}


sub end_batch {
  eval {
    $_[0]->dbh->commit;
  };
  if ($@) {
    eval { $_[0]->dbh->rollback };
    if ($@) {
    }
    return undef;
  }
  $_[0]->{commit_interval} = undef;
  return $_[0];
}

=pod 

=item * B<do_commit>

Called by writing operations to do a commit observing a possible commit interval.
If no interval was set, the method calls commit on the db handle. If there is a
value set for the commit interval, it will check how many operations were done since
the last commit before doing another.

=cut

sub do_commit {
  # init commit count
  unless (exists $_[0]->{commit_count}) {
    $_[0]->{commit_count} = 0;
  }
  
  if (exists $_[0]->{commit_interval} and $_[0]->{commit_interval}) {
    # check if commit interval is reached
    if ($_[0]->{commit_count} > $_[0]->{commit_interval}) {
      $_[0]->dbh->commit;
      $_[0]->{commit_count} = 0;
    }
    else {
      $_[0]->{commit_count}++;
    }
  }
  else {
    $_[0]->dbh->commit;
    $_[0]->{commit_count} = 0;
  }
  return 1;
}


=pod

=item * B<quote> (I<value>)

Returns the quoted I<value>.

=cut

sub quote {
  my ($self, $value) = @_;

  my $clean_text = $value;
  if(defined $value && !looks_like_number($value)) {
    my $hs = HTML::Strip->new();
    my $clean_text = $hs->parse($value);
    $clean_text =~ s/\n//g;
    $hs->eof;
  }

  return $self->dbh->quote($clean_text);
}


=pod

=item * B<disconnect> ()

Disconnect from the database and clean up.

=cut

sub disconnect {
  $_[0]->dbh->disconnect if ref($_[0]->dbh);
}


=pod

=item * B<DESTROY> ()

Disconnects from database before destroying the PPOBackend object.

=cut

sub DESTROY {
  $_[0]->disconnect();
}

1;
