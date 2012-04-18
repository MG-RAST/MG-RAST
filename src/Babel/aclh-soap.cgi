# Annotation Clearinghouse SOAP server cgi 

# $Id: aclh-soap.cgi,v 1.1 2009-12-01 15:22:43 wilke Exp $

use strict;
use warnings;


=pod

=head1 NAME

aclh-soap.cgi - SOAP service cgi script to access the annotation clearinghouse

=head2 DESCRIPTION

This script provides a basic SOAP interface to the search and query capabilities
of the Annotation Clearinghouse. It has to run inside a FIG environment and depends
on FigKernelPackages/AnnoClearinghouse.pm and the two configuration variables
$FIG_Config::clearinghouse_data, $FIG_Config::clearinghouse_contrib set in the 
FIG_Config.pm.

=head2 USAGE

Here is a short example on how to write a script to query the Annotation Clearinghouse
via the SOAP interface. 

use SOAP::Lite;

my $ids = [ 'fig|204669.6.peg.1397', 'tigrcmr|CT_1405' ];

my $response = SOAP::Lite                                             
  -> uri('http://www.nmpdr.org/AnnoClearinghouse_SOAP')
  -> proxy('http://clearinghouse.nmpdr.org/aclh-soap.cgi')
  -> get_annotations( $ids );

For more information about the available methods, their parameters and return values
please refer to their documentation in the section Methods. 

=head2 IMPLEMENTATION

The actual cgi service script is very basic. It uses SOAP::Transport::HTTP to dispatch
the SOAP calls to the inline package AnnoClearinghouse_SOAP.

=cut


use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI   
    -> dispatch_to('AnnoClearinghouse_SOAP')     
    -> handle;


=pod

=head2 METHODS (AnnoClearinghouse_SOAP)

=cut

package AnnoClearinghouse_SOAP;

use FIG_Config;
use AnnoClearinghouse;

=pod

=over 4

=item * B<version> ()

Returns the version string of the Annotation Clearinghouse. For now this
method will try to extract the version vXY from the path to the clearinghouse
main data. If this fails it will return the path instead. 

=cut

sub version {
    $FIG_Config::clearinghouse_data =~ /.+\/(.+)$/;
    return ($1) ? $1 : $FIG_Config::clearinghouse_data;
}


=pod

=item * B<get_annotations> (I<id_or_ids>)

Return all annotations from the main data for the provided identifiers. If 
I<id_or_ids> is a single id, then the method return an array reference of
tuples (id, source, function, organism, length).
If a reference to an array of ids was passed as parameter, the return value
will be a hash with the ids as key each with a similar array of tuples as
values.

=cut

sub get_annotations {
    my ($class, $ids) = @_;

    my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				     $FIG_Config::clearinghouse_contrib);
    
    if (ref $ids) {
	
	my $result = {};
	foreach my $id (@$ids) {
	    my $pid = $anno->lookup_principal_id($id);
	    my @r = $anno->get_annotations_by_pid($pid);
	    if (scalar(@r)) {
		$result->{$id} = \@r;
	    }
	}
	return $result;

    }
    else {
	my $pid = $anno->lookup_principal_id($ids);
	my @res = $anno->get_annotations_by_pid($pid);
	return \@res;
    }
}
    

=pod

=item * B<get_all_annotations> (I<id_or_ids>)

Return all annotations from the main data for the provided identifiers and the
expert contributed assertions. If I<id_or_ids> is a single id, then the method 
return an array reference of tuples (id, source, function, organism, length).
If a reference to an array of ids was passed as parameter, the return value
will be a hash with the ids as key each with a similar array of tuples as
values.

=cut

sub get_all_annotations {
    my ($class, $ids) = @_;

    my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				     $FIG_Config::clearinghouse_contrib);

    # check query $ids
    my $single = (ref $ids) ? 0 : $ids;
    $ids = (ref $ids) ? $ids : [ $ids ];

    my $result = {};
    foreach my $id (@$ids) {
	
	my $pid = $anno->lookup_principal_id($id);

	# get, merge and sort the data
	my @r = $anno->get_annotations_by_pid($pid);
	my @c = $anno->get_user_annotations_by_pid($pid);
	push @r, @c;
	@r = sort { $a->[0] cmp $b->[0] } @r;
	
	# fill in missing data for contribs
	my @final;
	my $org = '';
	my $len = '';
	foreach my $e (@r) {	
	    if (scalar(@$e) == 3) { 
		push @final, [ $e->[0], $e->[1], $e->[2], $org, $len ];
	    }
	    else {
		$org = $e->[3];
		$len = $e->[4];
		push @final, $e;
	    }
	}
	
	if (scalar(@final)) {
	    $result->{$id} = \@final;
	}
    }
    
    # return result
    if ($single) {
	return $result->{$single};
    }
    else {
	return $result;
    }
}
    

=pod

=item * B<get_user_annotation> (I<id_or_ids>)

This method takes a single or multiple identifiers and retrieves contributed
annotations. It returns all annotations which belong to any sequence in a 
block of (mostly) identical sequence (within the parameters used to construct  
the clearinghouse data). It does not return exactly and only an annotation if
it was made to the identifier in the query. 
For a single identifier the return value will be a reference to an array of
tuples (user, annotation). For multiple ids the method will return a hash with 
the query identifier as key and a reference to an array of such tuples as value.

=cut

sub get_user_annotations {
    my ($class, $ids) = @_;

    my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				     $FIG_Config::clearinghouse_contrib);
    if (ref $ids) {
	
	my $result = {};
	foreach my $id (@$ids) {
	    my @r = $anno->get_any_user_annotations($id);
	    if (scalar(@r)) {
		$result->{$id} = \@r;
	    }
	}
	return $result;
    }
    else {
	my @r = $anno->get_any_user_annotations($ids);
	return \@r;
    }
}


=pod

=item * B<has_user_annotation> (I<id_or_ids>)

This method does the same as B<get_user_annotations>, but omits all data in
the returned value. Instead it merely has counts of annotations. 

=cut

sub has_user_annotations {
    my ($class, $ids) = @_;

    my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				     $FIG_Config::clearinghouse_contrib);
    if (ref $ids) {
	
	my $result = {};
	foreach my $id (@$ids) {
	    my @r = $anno->get_any_user_annotations($id);
	    if (scalar(@r)) {
		$result->{$id} = scalar(@r);
	    }
	}
	return $result;
    }
    else {
	my @r = $anno->get_any_user_annotations($ids);
	return scalar(@r);
    }
}


=pod

=item * B<find_seed_equivalent> (I<non_fig_id>)

This method takes a non-SEED identifier I<non_fig_id> and tries to find a
fig id in the same organism. If successful, it will return the single id. 
If this fails, it will return a reference to an array of (id, organism) 
tuples of sequences belonging to the same principal id, but of a different
organism. The first entry of this result array is the (id,organism) tuple
of the I<non_fig_id>.

=cut

sub find_seed_equivalent {
    my ($class, $id) = @_;
    
    return $id if ($id =~ /^fig\|/);

    my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				     $FIG_Config::clearinghouse_contrib);
    
    my $organism = $anno->get_org($id);
    my $pid = $anno->lookup_principal_id($id);
    my @res = $anno->get_annotations_by_pid($pid);
    
    my $out = [];
    foreach my $r (@res) {
	my ($xid, $func, $source, $org, $len) = @$r;
	next unless ($xid =~ /^fig\|/);
	
	if ($organism eq $org) {
	    return $xid;
	}
	
	push @$out, [ $xid, $org ];
    }

    if(scalar(@$out)) {
	$out = [ [ $id, $organism ], @$out ];
    }
    return $out;

}


1;
