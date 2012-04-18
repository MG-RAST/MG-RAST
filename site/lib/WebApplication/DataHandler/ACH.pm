package DataHandler::ACH;

# DataHandler::ACH - data handler to the ACH database



use strict;
#use warnings;

use base qw( DataHandler );

use DBMaster;
use DBrtns;
use FIG_Config;


=pod

=head1 NAME

DataHandler::ACH - data handler to the PPO ACH database

=head1 DESCRIPTION

This module returns the DBMaster object to the ACH database stored in the root
job directory of a ACH server. It requires the FIG_Config.pm to specify the  
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
    my $db      = "";
    my $dbhost  = "";
    my $backend = "";
    my $dbport  = "";
    my $dbsock  = "";
    my $dbpass  = "";
    
    defined($dbhost) ? $dbhost : $FIG_Config::dbhost;
    $dbsock = defined($dbsock) ? $dbsock : $FIG_Config::dbsock;
    my $type    = "SQL";  # use type to select the access methods
    
    if ($WebConfig::ACHDB){
      $user    = $WebConfig::ACHUSER      || "seed" ; 
      $dbpass  = $WebConfig::ACHDBPASS    || "" ;
      $db      = $WebConfig::ACHDB;
      $dbhost  = $WebConfig::ACHDBHOST;
      $backend = $WebConfig::ACHDBBACKEND || "MySQL";
      $type    = $WebConfig::ACHDBPTYPE   if  ($WebConfig::ACHDBTYPE);
      $dbsock  = $WebConfig::ACHDBSOCK    if ($WebConfig::ACHDBSOCK);
      $dbport  = $WebConfig::ACHDBPORT    if ($WebConfig::ACHDBPORT);
    }
    elsif ($FIG_Config::ACHDB) {
      $user    = $FIG_Config::ACHUSER      || "seed" ;
      $dbpass  = $FIG_Config::ACHDBPASS    || "" ;
      $db      = $FIG_Config::ACHDB;
      $dbhost  = $FIG_Config::ACHDBHOST;
      $backend = $FIG_Config::ACHDBBACKEND || "MySQL";
      $type    = $FIG_Config::ACHDBPTYPE   if  ($FIG_Config::ACHDBTYPE);
      $dbsock  = $FIG_Config::ACHDBSOCK    if ($FIG_Config::ACHDBSOCK);
      $dbport  = $FIG_Config::ACHDBPORT    if ($FIG_Config::ACHDBPORT);

    }
    else{
      	warn "Unable to read DataHandler::ACH database: can't find FIG_Config.pm or ACH.pm\n";
	return undef;
    }

    if ($type eq "PPO"){
      
      eval {
	$_[0]->{_handle} = DBMaster->new( -database => $db,
					  -host     => $dbhost,
					  -user     => $user,
					  -backend  => $backend,
					);
      };
      
      
    }
    else{
      # probably a fig db
      $_[0]->{_handle} = new DBrtns( lc($backend),$db,$user,$dbpass,$dbport, $dbhost, $dbsock);
      
    }
    
    
    if ($@) {
      warn "Unable to read DataHandler::ACH : $@\n";
      $_[0]->{_handle} = undef;
    }
  }
  return $_[0]->{_handle};
}

1;
