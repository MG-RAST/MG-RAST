package DataHandler::MGRAST_MIMS;

# DataHandler::OOD - data handler to the PPO OOD database

# $Id: MGRAST_MIMS.pm,v 1.1 2008-10-09 20:53:28 wilke Exp $

use strict;
use warnings;

use base qw( DataHandler );

use DBMaster;
use Conf;


=pod

=head1 NAME

DataHandler::RAST - data handler to the PPO RAST database

=head1 DESCRIPTION

This module returns the DBMaster object to the RAST database stored in the root
job directory of a RAST server. It requires the Conf.pm to specify the  
$rast_jobs directory.

Refer to WebApplication/DataHandler.pm for the full documentation.

=head1 METHODS

=over 4

=item * B<handle> ()

Returns the enclosed data handle. Returns undef if it fails to open the Jobs database

=cut

sub handle {


  unless (exists $_[0]->{_handle}) {
  
    eval {
       $_[0]->{_handle} = DBMaster->new( -database => "MG_RAST_MIMS",
 					# -host     => $Conf::mgrast_ontology_dbhost,
 					# -user     => $Conf::mgrast_dbuser,
 					-backend  => 'MySQL',
				      );
   #    $_[0]->{_handle} = DBMaster->new( -database => $Conf::mgrast_ontology,
					
# 				      );
    };
    if ($@) {
      warn "Unable to read DataHandler::MGRAST_MIMS database: $@\n";
      $_[0]->{_handle} = undef;
    }
  }
  return $_[0]->{_handle};
}

1;
