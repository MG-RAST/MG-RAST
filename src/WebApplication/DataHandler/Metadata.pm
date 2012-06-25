package DataHandler::Metadata;

# DataHandler::RAST - data handler to the PPO RAST database

# $Id: Metadata.pm,v 1.1 2010-08-18 20:38:30 tharriso Exp $

use strict;
use warnings;

use base qw( DataHandler );

use DBMaster;
use Conf;

=pod

=head1 NAME

DataHandler::Metadata - data handler to the PPO MGRAST metadata database

=head1 DESCRIPTION

This module returns the DBMaster object to the Metadata database stored in the root
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
      $self->{_handle} = DBMaster->new( -database => $Conf::mgrast_jobcache_db || 'MGRASTMetadata',
					-host     => $Conf::mgrast_jobcache_host,
					-user     => $Conf::mgrast_jobcache_user,
					-password => $Conf::mgrast_jobcache_password || "");
    };
    if ($@) {
      warn "Unable to connect to MGRAST metadata database: $@\n";
      $self->{_handle} = undef;
    }
  }

  $self->{_handle}->{_application} = $self->application;
  $self->{_handle}->{_user} = $self->application->session->user;

  return $self->{_handle};
}

1;
