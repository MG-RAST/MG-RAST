package DataHandler::RAST;

# DataHandler::RAST - data handler to the PPO RAST database

# $Id: RAST.pm,v 1.7 2009-03-16 00:25:26 parrello Exp $

use strict;
use warnings;

use base qw( DataHandler );

use DBMaster;
use FIG_Config;

=pod

=head1 NAME

DataHandler::RAST - data handler to the PPO RAST database

=head1 DESCRIPTION

This module returns the DBMaster object to the RAST database stored in the root
job directory of a RAST server. It requires the FIG_Config.pm to specify the  
$rast_jobs directory.

Refer to WebApplication/DataHandler.pm for the full documentation.

=head1 METHODS

=over 4

=item * B<handle> ()

Returns the enclosed data handle. Returns undef if it fails to open the Jobs database

=cut

sub handle {

  unless (exists $_[0]->{_handle}) {
    if (! $FIG_Config::rast_jobcache_db) {
      # Denote no RAST without putting a confession in the error log.
      $_[0]->{_handle} = undef;
    } else {
      eval {
	$_[0]->{_handle} = DBMaster->new( -database => $FIG_Config::rast_jobcache_db || 'JobCacheRast',
					  -host     => $FIG_Config::rast_jobcache_host,
					  -user     => $FIG_Config::rast_jobcache_user,
					  -password => $FIG_Config::rast_jobcache_password );
      };
      if ($@) {
	warn "Unable to connect to RAST database: $@\n";
	$_[0]->{_handle} = undef;
      }
    }
  }
  return $_[0]->{_handle};
}

1;
