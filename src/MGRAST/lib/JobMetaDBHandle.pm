package JobMetaDBHandle;

# JobMetaDBHandle - connector to the Job Metainformation database

use strict;
use warnings;

use FIG_Config;
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

    # get the connection data from FIG_Config.pm
    my $dbmaster;
    eval {
      $dbmaster = DBMaster->new(-database => $FIG_Config::mgrast_metadata_db || "MGRASTMetadata",
				-host     => $FIG_Config::mgrast_metadata_host || "localhost",
				-user     => $FIG_Config::mgrast_metadata_user || "root",
				-password => $FIG_Config::mgrast_metadata_password || "");
    };

    if ($@) {
      return (undef, $@);
    }

    return ($dbmaster, undef);
}

1;
