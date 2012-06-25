package WebApplicationDBHandle;

# WebApplicationDBHandle - connector to the WebAppBackend database

use strict;
use warnings;

use Conf;
use DBMaster;

=pod

=head1 NAME

WebApplicationDBHandle - connector to the WebAppBackend database

=head1 DESCRIPTION

This module returns an array of the DBMaster object connected to the WebAppBackend database
and a possible error message. In case of an error, the dbmaster will be undef. Otherwise
the error will be undef.

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the WebApplicationDBHandle object.

=cut

sub new {

    # get the connection data from Conf.pm
    my $dbmaster;
    eval {
      $dbmaster = DBMaster->new(-database => $Conf::webapplication_db || "WebAppBackend",
				-host     => $Conf::webapplication_host || "localhost",
				-user     => $Conf::webapplication_user || "root",
				-password => $Conf::webapplication_password || "",
				-socket   => $Conf::webapplication_socket || "");
    };

    if ($@) {
      return (undef, $@);
    }

    return ($dbmaster, undef);
}

sub authenticate_user {
  my ($master, $key) = @_;

  unless (defined($master) && ref($master) eq "DBMaster") {
    die "Undefined or invalid dbmaster passed to authenticate_user in WebApplicationDBHandle";
  }

  unless (defined($key) && length($key)) {
    die "No key passed to authenticate_user in WebApplicationDBHandle";
  }
  
  my $pref = $master->Preferences->get_objects( { value => $key } );
  if (scalar(@$pref)) {
    return $pref->[0]->user;
  } else {
    return undef;
  }

}

1;
