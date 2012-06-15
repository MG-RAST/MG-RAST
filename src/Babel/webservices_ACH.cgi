#__perl__

use strict;
use Carp;
use CGI::Carp qw(fatalsToBrowser); # this makes debugging a lot easier by throwing errors out to the browser
use SOAP::Lite;
use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI   
-> dispatch_to('ACHWebServices')     
-> handle;


package ACHWebServices;

use FIG;
use AnnoClearinghouse;
use Data::Dumper;

=begin WSDL
_IN Gene_ID  $string 
_IN ID_type  $string 
_RETURN @string
_DOC Given a protein ID from any source we know about, returns a list of ID's of the requested type. If no type is given, returns all corresponding iD's
=cut
sub get_corresponding_ids {
	my ($class, $id, $type) = @_;

	my $fig = new FIG;

	my $ach = new AnnoClearinghouse( $FIG_Config::clearinghouse_data ,
					 $FIG_Config::clearinghouse_contrib , 
					 0,
					 my $dbf = $fig->db_handle);
	
	my @ids = $ach->get_corresponding_ids( $id , $type);

	return @ids;
}

=begin WSDL
_IN ID  $string  
_RETURN $string
_DOC Given a protein ID from any source we know about, returns the organism name for this ID
=cut

sub get_organism_name{
    my ($class , $id) = @_;

    my $fig = new FIG;

    my $ach = new AnnoClearinghouse( $FIG_Config::clearinghouse_data ,
				     $FIG_Config::clearinghouse_contrib , 
				     0,
				     my $dbf = $fig->db_handle);
	
    return  $ach->get_organism_name( $id );
}
