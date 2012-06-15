package DataHandler::MGRAST;

# DataHandler::RAST - data handler to the PPO RAST database

# $Id: MGRAST.pm,v 1.2 2009-10-12 13:40:43 paczian Exp $

use strict;
use warnings;

use base qw( DataHandler );

use DBMaster;
use Conf;

=pod

=head1 NAME

DataHandler::MGRAST - data handler to the PPO MGRAST database

=head1 DESCRIPTION

This module returns the DBMaster object to the MGRAST database stored in the root
job directory of a MGRAST server. It requires the Conf.pm to specify the  
$mgrast_jobs directory.

Refer to WebApplication/DataHandler.pm for the full documentation.

=head1 METHODS

=over 4

=item * B<handle> ()

Returns the enclosed data handle. Returns undef if it fails to open the Jobs database

=cut

sub handle {
  my ($self) = @_;

  unless (exists $self->{_handle}) {
    eval {
      $self->{_handle} = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'JobCacheMGRast',
					-host     => $Conf::mgrast_jobcache_host,
					-user     => $Conf::mgrast_jobcache_user,
					-password => $Conf::mgrast_jobcache_password );
    };
    if ($@) {
      warn "Unable to connect to MGRAST database: $@\n";
      $self->{_handle} = undef;
    }
  }

  $self->{_handle}->{_application} = $self->application;
  $self->{_handle}->{_user} = $self->application->session->user;

  return $self->{_handle};
}

1;
