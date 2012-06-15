package DataHandler::Babel;

# DataHandler::Babel - data handler to the Babel database



use strict;
#use warnings;

use base qw( DataHandler );

use DBMaster;
use DBI;
use Config;


=pod

=head1 NAME

DataHandler::ACH - data handler to the Babel database

=head1 DESCRIPTION

This module returns the DBMaster object to the Babel database stored in the root
job directory of a ACH server. It requires the Config.pm to specify the  
$rast_jobs directory.

Refer to WebApplication/DataHandler.pm for the full documentation.

=head1 METHODS

=over 4

=item * B<handle> ()

Returns the enclosed data handle. Returns undef if it fails to open the Jobs database

=cut

sub handle {
  
  unless (exists $_[0]->{_handle}) {
    
    my $user    = "";
    my $dbpass  = "";
    my $db      = "";
    my $dbhost  = "";
    my $backend = "";
    my $type    = "SQL"; # default is not PPO
    my $dbsock  = $Config::dbsock || "";
    my $dbport  = $Config::dbsock || "";
    
    if ($WebConfig::BABELDB) {
      $user    = $WebConfig::BABELUSER      || "ach"; 
      $dbpass  = $WebConfig::BABELDBPASS    || "";
      $db      = $WebConfig::BABELDB;
      $dbhost  = $WebConfig::BABELDBHOST;
      $backend = $WebConfig::BABELDBBACKEND || "MySQL"; # for PPO only
      $type    = $WebConfig::BABELDBPTYPE   if ($WebConfig::BABELDBTYPE);
      $dbsock  = $WebConfig::BABELDBSOCK    if ($WebConfig::BABELDBSOCK);
      $dbport  = $WebConfig::BABELDBPORT    if ($WebConfig::BABELDBPORT);
    }
    elsif ($Config::babel_db) {
      $user    = $Config::babel_dbuser    || "ach";
      $dbpass  = $Config::babel_dbpass    || "";
      $db      = $Config::babel_db;
      $dbhost  = $Config::babel_dbhost;
      $backend = $Config::babel_dbbackend || "MySQL"; # for PPO only
      $type    = $Config::babel_dbtype    if ($Config::babel_dbtype);
      $dbsock  = $Config::babel_dbsock    if ($Config::babel_dbsock);
      $dbport  = $Config::babel_dbport    if ($Config::babel_dbport);

    }
    else {
      	warn "Unable to read DataHandler::Babel database: can't find Config.pm or Babel.pm\n";
	return undef;
    }

    if ($type eq "PPO") {
      eval {
	$_[0]->{_handle} = DBMaster->new( -database => $db,
					  -host     => $dbhost,
					  -user     => $user,
					  -backend  => $backend,
					);
      };
    }
    else {
      if ($dbhost) {
	$_[0]->{_handle} = DBI->connect("DBI:$type:dbname=$db;host=$dbhost", $user, $dbpass);
      }
      print STDERR $_[0]->{_handle} . "\n";
      unless ( $_[0]->{_handle} ) {
	print STDERR "Error , " , DBI->error , "\n";
      }
    }
    
    if ($@) {
      warn "Unable to read DataHandler::Babel : $@\n";
      $_[0]->{_handle} = undef;
    }
  }
  return $_[0]->{_handle};
}

1;
