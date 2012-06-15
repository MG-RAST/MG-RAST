use Data::Dumper;
use Carp;
use Conf;

use strict;

use FIG;
my $fig = new FIG;

my $arg = shift @ARGV;
my $dir = (-d $arg) ? $arg : "$Conf::data/ACHresolution"; 


my $file = "$dir/Assertion";

my $dbf = $fig->db_handle;

$dbf->drop_table( tbl => "ACH_Assertion" );
$dbf->create_table( tbl  => "ACH_Assertion",
		    flds => "id varchar(32),
                             function varchar(500), 
                             md5 varchar(32),
                             expert varchar(100),
                             url varchar(200)"
		  );
$dbf->load_table( tbl => "ACH_Assertion",file => $file);
$dbf->create_index( idx  => "ACH_Assertion_id_ix",
		    tbl  => "ACH_Assertion",
		    type => "btree",
		    flds => "id" );
$dbf->create_index( idx  => "ACH_Assertion_expert_ix",
		    tbl  => "ACH_Assertion",
		    type => "btree",
		    flds => "id" );
$dbf->create_index( idx  => "ACH_Assertion_function_ix",
		    tbl  => "ACH_Assertion",
		    type => "btree",
		    flds => "function" );
$dbf->create_index( idx  => "ACH_Assertion_md5_ix",
		    tbl  => "ACH_Assertion",
		    type => "btree",
		    flds => "md5" );

$dbf->drop_table( tbl => "ACH_Correspondence" );

$dbf->create_table( tbl  => "ACH_Correspondence",
		    flds => "function1 varchar(500), 
                             function2 varchar(500),
                             status char(1)"
		  );

if (-s "$dir/Correspondence")
{
    $dbf->load_table( tbl => "ACH_Correspondence",file => "$dir/Correspondence") ;
}

$dbf->create_index( idx  => "ACH_Correspondence_f1_ix",
		    tbl  => "ACH_Correspondence",
		    type => "btree",
		    flds => "function1" );
$dbf->create_index( idx  => "ACH_Correspondence_f2_ix",
		    tbl  => "ACH_Correspondence",
		    type => "btree",
		    flds => "function2" );

$dbf->drop_table( tbl => "ACH_Comment_on_sequence_function" );
$dbf->create_table( tbl  => "ACH_Comment_on_sequence_function",
		    flds => "id varchar(32),
                             who varchar(100),
			     ts integer,
			     md5 varchar(32),
                             comment varchar(5000)"
		  );

if (open(COMMENTS,"<$dir/Comment_on_sequence_function"))
{
    $/ = "//\n";
    while (defined($_ = <COMMENTS>))
    {
	chomp;
	if ($_ =~ /^(\S+)\t([^\t]+)\t(\d+)\t([^\n]+)\n(.*)/s)
	{
	    my($id,$who,$ts,$md5,$comment) = ($1,$2,$3,$4,$5);
	    my $commentQ = &encode($comment);
	    $dbf->SQL("INSERT INTO ACH_Comment_on_sequence_function (id,who,ts,md5,comment) VALUES ('$id','$who',$ts,'$md5','$commentQ')");
	}
    }
    $/ = "\n";
    close(COMMENT);
}

$dbf->create_index( idx  => "ACH_Comment_on_sequence_function_peg_ix",
		    tbl  => "ACH_Comment_on_sequence_function",
		    type => "btree",
		    flds => "id" );
$dbf->create_index( idx  => "ACH_Comment_on_sequence_function_who_ix",
		    tbl  => "ACH_Comment_on_sequence_function",
		    type => "btree",
		    flds => "who" );

$dbf->drop_table( tbl => "ACH_Comment_on_status_change" );
$dbf->create_table( tbl  => "ACH_Comment_on_status_change",
		    flds => "function1 varchar(500), 
                             function2 varchar(500),
                             status char(1),
			     ts integer,
			     expert varchar(100),
                             comment varchar(5000)"
		  );

if (open(COMMENTS,"<$dir/Comment_on_status_change"))
{
    $/ = "//\n";
    while (defined($_ = <COMMENTS>))
    {
	chomp;
	if ($_ =~ /^(\S+)\t([^\t]+)\t([^\n]+)\n(.*)/s)
	{
	    my($function1,$function2,$status,$ts,$expert) = ($1,$2,$3,$4,$5);
	    my $function1Q = &encode($function1);
	    my $function2Q = &encode($function2);
	    $dbf->SQL("INSERT INTO ACH_Comment_on_status_change (function1,function2,status,ts,expert) VALUES ('$function1Q','$function2Q','$status',$ts,'$expert')");
	}
    }
    $/ = "\n";
    close(COMMENT);
}

$dbf->create_index( idx  => "ACH_Comment_on_status_change_function1_ix",
		    tbl  => "ACH_Comment_on_status_change",
		    type => "btree",
		    flds => "function1" );
$dbf->create_index( idx  => "ACH_Comment_on_status_change_function2_ix",
		    tbl  => "ACH_Comment_on_status_change",
		    type => "btree",
		    flds => "function2" );
$dbf->create_index( idx  => "ACH_Comment_on_status_change_status_ix",
		    tbl  => "ACH_Comment_on_status_change",
		    type => "btree",
		    flds => "status" );
$dbf->create_index( idx  => "ACH_Comment_on_status_change_expert_ix",
		    tbl  => "ACH_Comment_on_status_change",
		    type => "btree",
		    flds => "expert" );

sub encode {
    my($x) = @_;

    $x =~ s/\\/\\\\/g;
    $x =~ s/\'/\\'/g;
    return $x;
}
