package DataHandler::FIGMODEL;
# DataHandler::FIGMODEL - data handler to SEED database via FIGMODEL
# Primary author: Christopher Henry (chenry@mcs.anl.gov), MCS Division, Argonne National Laboratory
# Created: 4/13/2009
use strict;
use warnings;
use Data::Dumper;
use base qw( DataHandler );
use lib '/vol/model-prod/Model-SEED-core/config/';
use ModelSEEDbootstrap;
use ModelSEED::FIGMODEL;

=head1 FIGMODEL Data Handler
#TITLE FIGMODELpmDataHandler
=head2 Introduction
=head2 Public Methods
=head3 handle
	my $FIGMODELObject = $dh->handle($optional_id);
=cut
sub handle {
  my ($self, $optional_id) = @_;
  my $cgi = $self->application->cgi;
  if (!defined($self->{'FIGMODEL'})) {
  	my $user = $self->application()->session->user;
  	$self->{'FIGMODEL'} = ModelSEED::FIGMODEL->new();
  	$self->{'FIGMODEL'}->web()->cgi($cgi);
  	if ($user) {
  		$self->{'FIGMODEL'}->setuser($user);
  	}
  }
  return $self->{'FIGMODEL'};
}

1;
