package JobDBHandle;

# JobDBHandle - connector to the Job database

use strict;
use warnings;

use Global_Config;
use DBMaster;

=pod

=head1 NAME

JobDBHandle - connector to the Job database

=head1 DESCRIPTION

This module returns an array of the DBMaster object connected to the Job database
and a possible error message. In case of an error, the dbmaster will be undef. Otherwise
the error will be undef.

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the JobDBHandle object.

=cut

sub new {

    # get the connection data from Global_Config.pm
    my $dbmaster;
    eval {
      $dbmaster = DBMaster->new(-database => $Global_Config::mgrast_jobcache_db || "jobcache_MG_prod",
				-host     => $Global_Config::mgrast_host || "localhost",
				-user     => $Global_Config::mgrast_user || "root",
				-password => $Global_Config::mgrast_password || "");
    };

    if ($@) {
      return (undef, $@);
    }

    return ($dbmaster, undef);
}

1;
