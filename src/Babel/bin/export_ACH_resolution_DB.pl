
use Data::Dumper;
use Carp;
use Conf;
use CGI;

my $cgi = new CGI;

use FIG;
my $fig = new FIG;

my $rdbH = $fig->db_handle;

&FIG::verify_dir("$Conf::data/ACHresolution");

if (open(ASSERTION,">$Conf::data/ACHresolution/Assertion"))
{
    my $relational_db_response = $rdbH->SQL("SELECT * FROM ACH_Assertion");
    foreach my $tuple (@$relational_db_response)
    {
	print ASSERTION join("\t",@$tuple),"\n";
    }
    close(ASSERTION);
}

if (open(CORR,">$Conf::data/ACHresolution/Correspondence"))
{
    my $relational_db_response = $rdbH->SQL("SELECT * FROM ACH_Correspondence");
    foreach my $tuple (@$relational_db_response)
    {
	print CORR join("\t",@$tuple),"\n";
    }
    close(CORR);
}

if (open(COMMENTS,">$Conf::data/ACHresolution/Comment_on_sequence_function"))
{
    my $relational_db_response = $rdbH->SQL("SELECT * FROM ACH_Comment_on_sequence_function");
    foreach my $tuple (@$relational_db_response)
    {
	my $comment = pop @$tuple;
	if (substr($comment,-1) ne "\n")
	{
	    $comment .= "\n";
	}
	$comment = &decode($comment);
	print COMMENTS join("\t",@$tuple),"\n$comment//\n";
    }
    close(COMMENTS);
}

if (open(COMMENT,">$Conf::data/ACHresolution/Comment_on_status_change"))
{
    my $relational_db_response = $rdbH->SQL("SELECT * FROM ACH_Comment_on_status_change");
    foreach my $tuple (@$relational_db_response)
    {
	print COMMENT join("\t",@$tuple),"\n";
    }
    close(COMMENT);
}

sub decode {
    my($x) = @_;

    $x =~ s/\\\\/\\/g;
    $x =~ s/\'\'/\'/g;
    return $x;
}

