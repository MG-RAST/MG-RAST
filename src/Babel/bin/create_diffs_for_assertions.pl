
use Data::Dumper;
use Carp;
use Config;
use CGI;

my $cgi = new CGI;

use FIG;
my $fig = new FIG;

my $rdbH = $fig->db_handle;

&FIG::verify_dir("$Config::data/ACHresolution");

# if (open(ASSERTION,">$Config::data/ACHresolution/diffs_for_assertions"))
{
    my $relational_db_response = $rdbH->SQL("select t1.md5 , t1.function , t2.function from ACH_Assertion as t1 , ACH_Assertion as t2 where t1.md5=t2.md5 and t1.function!=t2.function group by  t1.function ,t2.function , t1.md5;");
    foreach my $tuple (@$relational_db_response)
    {
	print  join("\t",@$tuple),"\n";
    }
    # close(ASSERTION);
}


sub decode {
    my($x) = @_;

    $x =~ s/\\\\/\\/g;
    $x =~ s/\'\'/\'/g;
    return $x;
}

