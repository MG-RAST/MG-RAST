package WebServerBackend::Session;

# Session - simple session management to support WebApplication

# $Id: Session.pm,v 1.9 2008-02-22 16:29:23 paarmann Exp $

use strict;
use warnings;

use CGI;
use CGI::Cookie;
use Digest::MD5;
use Time::Local;
use FreezeThaw qw( freeze thaw );

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

use constant MAX_SESSION_ENTRIES => 3;
use constant SESSION_TIMEOUT => '+2h';
use constant SESSION_TIMEOUT_SECS => 2*3600;


=pod

=head1 NAME

Session - simple session management to support WebApplication

=head1 DESCRIPTION

TODO

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the Session object. This overwritten version of the 
method will retrieve a Session if the session_id already exists.

=cut

sub create {
  my ($self, $cgi) = @_;

  # check if we are called properly
  unless (ref $self) {
    die "Not called as an object method.";
  }
  
  my $session_id = $self->init_session_id();

  # get session from database
  my $sessions = $self->_master->Session->get_objects({ 'session_id' => $session_id });
  if (scalar(@$sessions)) {
    $self = $sessions->[0];
  }

  # or create a new one
  else { 
    my $session = $self->SUPER::create({ 'session_id' => $session_id,
					 'creation'   => $self->_timestamp() });
    if (ref $session) {
      $self = $session;
    }
    else {
      die "Failure creating a session in __PACKAGE__.";
    }
  }

  # create a cookie
  $self->{'_cookie'} = CGI::Cookie->new( -name    => 'WebSession',
					 -value   => $session_id,
					 -expires => SESSION_TIMEOUT );
  
  # add cgi to object
  $self->{'_cgi'} = $cgi || CGI->new();

  return $self;

}


=pod

=item * B<cookie> ()

Return the session cookie

=cut

sub cookie {
  return $_[0]->{'_cookie'};
}


=pod

=item * B<expire> ()

Expire the session cookie.

=cut

sub expire {
  my ($self) = @_;

  # create new cookie in the past
  $self->{'_cookie'} = CGI::Cookie->new( -name    => 'WebSession',
					 -value   => '',
					 -expires => '-1d' );

}


=pod

=item * B<age> ()

Returns the age of the session in seconds. Age is determined by the latest 
use of it, ie. the timestamp of the last Session entry or the creation date
(which ever is more recent).

=cut

sub age {
  my $e = $_[0]->get_entry;
  my $timestamp = (ref $e) ? $e->timestamp : $_[0]->creation;
  return time() - $_[0]->_timestamp_as_epoch($timestamp);

}


=pod

=item * B<is_expired> ()

Returns true if the age of the session is older than the SESSION_TIMEOUT_SECS. 

=cut

sub is_expired {
  return $_[0]->age > SESSION_TIMEOUT_SECS;
}


=pod

=item * B<init_session_id> ()

Returns the id of the current session. If a cookie already exists it tries to 
retrieve the session id from there, else it creates a unique id.

=cut

sub init_session_id {
    my $self = shift;

    my $cgi = CGI->new();

    my $session_id = undef;

    # read existing cookie
    my $cookie = $cgi->cookie('WebSession');
    if ($cookie) {
      $session_id = $cookie;
    }

    # or create new one
    else { 
      
      # get 'random' data
      my $host= $cgi->remote_host();
      my $rand = int(int(time)*rand(100));
      
      # hide it behind a md5 sum (32 char hex)
      my $md5 = Digest::MD5->new;
      $md5->add($host, $rand);
      my $id = $md5->hexdigest;
      
      $session_id = $id;	
      
    }

    # return session id or die
    if (defined $session_id) {
      return $session_id;
    }
    else {
      die "Could not generate a session id."
    }

}


=pod

=item * B<add_entry> ()

Adds a session entry to the current session.

=cut

sub add_entry {
  my ($self) = @_;

  my $page = ($self->_cgi->param('page')) ? $self->_cgi->param('page') : undef;

  my $parameters = {};
  foreach my $p ($self->_cgi->param()) {
    my @v = $self->_cgi->param($p); 
    $parameters->{$p} = \@v;
  }

  my $entry = $self->_master->SessionItem->create({ 'timestamp' => $self->_timestamp(),
						    'page' => $page,
						    'parameters' => freeze($parameters),
						  });

  if (defined $entry and ref $entry eq 'WebServerBackend::SessionItem') {
  
    # limit the number of entries
    while (scalar(@{$self->entries()}) >= MAX_SESSION_ENTRIES) {
      my $e = shift @{$self->entries()};
      $e->delete();
    }

    push @{$self->entries()}, $entry;

  }
  else {
    die "Unable to add entry to the session.";
  }

  return $self;

}


=pod

=item * B<get_entry> ()

Retrieve a SessionItem from the current Session. The method accepts the following
(mutually exclusive) parameters:
$session->get_entry( -current => 1 );
$session->get_entry( -previous => 1 );
If no paramaters are given, the current entry will be returned. To retrieve all 
entries use $session->entries().

=cut

sub get_entry {
  my $self = shift;
  my %params = @_;

  if ($params{-current} or scalar(keys(%params)) == 0 ) {
    return $self->entries->[ scalar(@{$self->entries})-1 ];
  }
  elsif ($params{-previous}) {
    if (scalar(@{$self->entries}) >= 2) {
      return $self->entries->[ scalar(@{$self->entries})-2 ];
    }
  }
  return undef;
}


=pod

=back

=head1 INTERNAL METHODS

Internal or overwritten default perl methods. Do not use from outside!

=over 4

=item * B<_timestamp> ()

Constructs a mysql compatible timestamp from time() (GMT)

=cut

sub _timestamp {
  my $self = shift;
  my ($sec,$min,$hour,$day,$month,$year) = gmtime();
  $year += 1900;
  $month += 1;
  return $year."-".$month.'-'.$day.' '.$hour.':'.$min.':'.$sec;
}


=pod

=item * B<_timestamp_as_epoch> ()

Converts a msql timestamp back to epoch seconds

=cut

sub _timestamp_as_epoch {
  my ($self, $time) = @_;
  $time =~ /^(\d+)-(\d+)-(\d+) (\d+)\:(\d+)\:(\d+)$/;
  return timegm($6,$5,$4,$3,$2-1,$1);
}


=pod

=item * B<_cgi> ()

Returns the reference to the cgi object instance of this session.

=cut

sub _cgi {
  return $_[0]->{'_cgi'};
}


=pod

=item * B<delete> ()

Before calling the super method delete, this method will clean up all referenced
data.

=cut

sub delete {
  
  foreach (@{$_[0]->entries}) {
    $_->delete;
  }

  return $_[0]->SUPER::delete();

}

1;
