package JobMetaDBHandle;

# JobMetaDBHandle - connector to the Job Metainformation database

use strict;
use warnings;

use Conf;
use DBMaster;

=pod

=head1 NAME

JobMetaDBHandle - connector to the Job Metainformation database

=head1 DESCRIPTION

This module returns an array of the DBMaster object connected to the JobMeta database
and a possible error message. In case of an error, the dbmaster will be undef. Otherwise
the error will be undef.

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the JobMetaDBHandle object.

=cut

sub new {

    # get the connection data from Conf.pm
    my $dbmaster;
    eval {
      $dbmaster = DBMaster->new(-database => $Conf::mgrast_jobcache_db || "MGRASTMetadata",
				-host     => $Conf::mgrast_jobcache_host || "localhost",
				-user     => $Conf::mgrast_jobcache || "root",
				-password => $Conf::mgrast_jobcache_password || "");
    };

    if ($@) {
      return (undef, $@);
    }

    return ($dbmaster, undef);
}

1;
