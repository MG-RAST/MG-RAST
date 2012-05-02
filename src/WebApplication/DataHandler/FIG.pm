package DataHandler::FIG;

# DataHandler::FIG - data handler to SEED database via FIG/FIGV

# $Id: FIG.pm,v 1.27 2009-08-17 19:26:54 olson Exp $

use strict;
use warnings;

use base qw( DataHandler );

use FIG;
use FIGV;
use FIGM;
use FIG_Config;
use SFXlate;
use FIGRules;

1; 

=head1 FIG Data Handler

#TITLE FigPmDataHandler

=head2 Introduction

This is a subclass of [[DataHandlerPm]] that returns the FIG object for a particular
application. The object chosen depends on whether we're using a private genome directory,
the [[FIG.NmpdrWebsite]], or a vanilla [[FIG.SeedEnvironment]]. The object returned
could be a [[FigvPm]], a [[FigPm]], or an [[SFXlatePm]]. The FIGV could potentially
be a SFXlate FIGV or a FIG FIGV.

=head2 Public Methods

=head3 handle

    my $dataObject = $dh->handle($optional_id);

Return the object to be used by the application to access FIG data. The object will
implement most or all of the methods in [[FigPm]].

In most cases, the FIG_Config will determine whether your get an SFXlate object
or a FIG object. If C<$FIG_Config::nmpdr_mode> is TRUE, you get SFXlate. If it's
FALSE, you get FIG.

If you're using RAST or MG-RAST, the FIG or SFXlate object will be converted into
a FIGV automatically.

If you have set up your user profile correctly on the NMPDR Wiki, you can use the
Tracing Dashboard of the Debug Console to create a cookie that overrides the standard
rules. This means you can debug under the various environments without having to
fool around with CGI parameters and config variables.

=cut

sub handle {
  my ($self, $optional_id) = @_;
  # Get the CGI object.
  my $cgi = $self->application->cgi;
  # find out about organism/metagenome id
  my @keywords = qw( organism metagenome feature pattern );
  my $id;
  if ($optional_id) {
    $id = $optional_id;
  } else {
    foreach my $kw (@keywords) {
      if ($cgi->param($kw)) {
	$id = $cgi->param($kw);
	last;
      }
    }
    # crop feature id
    if ($id and $id =~  /fig\|(\d+\.\d+)/) {
      $id = $1;
    } else {
      $id = undef;
    }
  }

  unless(exists($self->{_fig})) {
    # Here we have to create the FIG object. Check for the environment cookie.
    my $sprout = $cgi->cookie('SPROUT');
    if (! $sprout) {
      # No cookie. Check nmpdr_mode.
      $sprout = (FIGRules::nmpdr_mode($cgi) ? 'Sprout' : 'FIG');
    } else {
      # Here we have a mode cookie override, so we put an info line in the output.
      $self->application->add_message(info => "Data source override: $sprout");
    }
    # The value here is either 'Sprout', 'FIG', 'SproutRewind', or 'FIGV,...dir...'.
    # We convert this into the two parameters required by FIGV. Note that eventually
    # there will be a SproutV, but not yet.
    my ($mode, $dir) = split /\s*,\s*/, $sprout, 2;
    if ($mode eq 'FIG') {
      $self->{_fig} = FIG->new();
    } elsif ($mode eq 'Sprout') {
      $self->{_fig} = SFXlate->new();
    } elsif ($mode eq 'SproutRewind') {
      $self->{_fig} = SFXlate->new(undef, $FIG_Config::oldSproutDB, undef, $FIG_Config::oldSproutDBD);
    } else {
      $self->{_fig} = FIGV->new($dir, $mode);
    }
  }
  # Start of FIGM part
  # check if there are rast jobs and a user
  if (exists($self->{_figm})) {
    return $self->{_figm};
  }
  if ($FIG_Config::rast_jobs && $self->application->session->user) {
    my $application = $self->application;
    my $user = $application->session->user;
    my $master = $application->dbmaster;

    # check if we have are showing an organism which might not be in the preferences,
    # but to which the user still has a right to view
    my @fig_m_dirs;
    my @ids = ();
    if ($cgi->param('organism')) {
      @ids = $cgi->param('organism');
    } elsif ($id) {
      push(@ids, $id);
    }
    
    my $jobs_dbm = $self->application->data_handle('RAST');
    if (ref($jobs_dbm)) {
      foreach my $org_id (@ids) {
	next if $self->{_fig}->is_genome($org_id);
	my $job = $jobs_dbm->Job->init({ genome_id => $org_id });
	if (ref($job) && $self->application->check_rights([ ['view', 'genome', $org_id ] ])) {
	  push(@fig_m_dirs, $job->org_dir);
	}
      }
      
      # now check if the current user has private organism preferences
      my $prefs = $master->Preferences->get_objects( { user => $user,
						       name => 'PrivateOrganismPeer' } );
      
      if (scalar(@$prefs)) {
	
	# the user has set private organism preferences, get the job information
	
	my @jobs = $jobs_dbm->Job->get_jobs_for_user_fast_no_status($user, 'view');
	unless (scalar(@jobs)) {
	  $application->add_message('warning', "Could not find any of your private organisms.");
	  return undef;
	}
      
	# hash the available genomes
	my $genomes = {};
	%$genomes = map { $_->{genome_id} => $_->{id} } @jobs;
	
	# check if all jobs in the preferences are available
	my $fig_m_orgs = [];
	my $not_found = [];
	foreach my $pref (@$prefs) {
	  next if ($id && ($pref->value eq $id));
	  if ($genomes->{$pref->value}) {
	    push(@$fig_m_orgs, $genomes->{$pref->value}."/rp/".$pref->value);
	  } else {
	    push(@$not_found, $pref->value);
	  }
	}
	push(@fig_m_dirs, map { $FIG_Config::rast_jobs . "/" . $_ } @$fig_m_orgs);
	
      }
      if (scalar(@fig_m_dirs)) {
	# create the FIGM
	$self->{_figm} = FIGM->new(undef, @fig_m_dirs);
	
	return $self->{_figm}
      }
    }
  }
  # End of FIGM part

  # return fig if there's no id
  return $self->{_fig} unless ($id);

  # check if normal fig has that organism
  return $self->{_fig} if ($id and $self->{_fig}->genome_version($id));

  # check if current id matches last id 
  if ($self->{_last_id} and $self->{_last_id} eq $id) {
    
    # return cached FIGV if available
    if (exists ($self->{_figv})) {
      return $self->{_figv};
    }
    # failed to get a FIGV previously, return a plain fig
    else {
      return $self->{_fig};
    }
  }

  # if this has a mgrast_jobs directory it might be in there
  if ($FIG_Config::mgrast_jobs) {

    # no rast on anno3, even if config variable exists
    unless ($FIG_Config::anno3_mode) {
      
      # nope, check if we have a RAST job directory
      my $jobs_dbm = $self->application->data_handle('MGRAST');
      if (ref $jobs_dbm) {
	my $job;
	eval { 
	  $job = $jobs_dbm->Job->init({ genome_id => $id });
	};
	if (ref ($job)) {
	  # check if we have a public metagenome
	  unless ($job->public) {
	    
	    unless ($self->application->check_rights([ ['view', 'metagenome', $id ] ])) {
	      return undef;
	    }
	  }
	  
	  $self->{_last_id} = $id;
	  
	  # get a FIGV
	  unless (exists ($self->{_figv})) {
	    $self->{_figv} = FIGV->new($job->org_dir);
	  }
	  
	  return $self->{_figv};
	}
      }
    }
  }
  
  return $self->{_fig}; # Don't blow up the SeedViewer. Let it just not find the genome.

}
