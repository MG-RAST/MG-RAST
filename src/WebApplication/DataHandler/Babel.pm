package DataHandler::Babel;

# DataHandler::Babel - data handler to the Babel database



use strict;
#use warnings;

use base qw( DataHandler );

use DBMaster;
use DBI;
use Conf;


=pod

=head1 NAME

DataHandler::ACH - data handler to the Babel database

=head1 DESCRIPTION

This module returns the DBMaster object to the Babel database stored in the root
job directory of a ACH server. It requires the Conf.pm to specify the  
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
    my $dbsock  = $Conf::dbsock || "";
    my $dbport  = $Conf::dbsock || "";
    
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
    elsif ($Conf::babel_db) {
      $user    = $Conf::babel_dbuser    || "ach";
      $dbpass  = $Conf::babel_dbpass    || "";
      $db      = $Conf::babel_db;
      $dbhost  = $Conf::babel_dbhost;
      $backend = $Conf::babel_dbbackend || "MySQL"; # for PPO only
      $type    = $Conf::babel_dbtype    if ($Conf::babel_dbtype);
      $dbsock  = $Conf::babel_dbsock    if ($Conf::babel_dbsock);
      $dbport  = $Conf::babel_dbport    if ($Conf::babel_dbport);

    }
    else {
      	warn "Unable to read DataHandler::Babel database: can't find Conf.pm or Babel.pm\n";
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
