use Data::Dumper;
use Carp;
use FIG_Config;

use strict;

use FIG;
my $fig = new FIG;

my $file = "$FIG_Config::data/ACHresolution/ACH_id_table";

my $dbf = $fig->db_handle;

my $fig_path = "/vol/seed-anno-mirror";
my $db = "ACH_TEST";
my $dbuser = "root";
my $dbhost = "bio-data-1.mcs.anl.gov";
my $dbpass = '';
my $dbport = '';
my $dbh;

if ($dbhost)
{
    $dbh = DBI->connect("DBI:mysql:dbname=$db;host=$dbhost", $dbuser, $dbpass);
}

unless ($dbh) {
    print STDERR "Error , " , DBI->error , "\n";
}


my $baz = '';
my $statement = "CREATE TABLE ACH_ID2GROUP ( _id int NOT NULL AUTO_INCREMENT,
_mtime timestamp(14) NOT NULL,
_ctime timestamp(14) NOT NULL,
md5 varchar(32) NOT NULL,
id varchar(32),
function varchar(500),
source integer,
organism integer,
organism_group integer,
KEY (md5),
PRIMARY KEY (_id)
);";

my $index = "CREATE INDEX ID2GROUP_id ON ACH_ID2GROUP (id);
CREATE INDEX ID2GROUP_organismGroup ON ACH_ID2GROUP (organism_group);
CREATE INDEX ID2GROUP_md5 ON ACH_ID2GROUP (md5);";



# $sth = $dbh->prepare("SELECT md5, id FROM ACH_ID2GROUP WHERE id=?");

my $response = $dbh->do( $statement );

my $response = $dbh->do( $index );
exit;

my $sth = $dbh->prepare($statement);


$sth->execute( $baz );

#    $sth = $dbh->prepare("INSERT INTO table(foo,bar,baz) VALUES (?,?,?)");

# while(<CSV>) {
#     chomp;
#     my ($foo,$bar,$baz) = split /,/;
#     $sth->execute( $foo, $bar, $baz );
# }



exit;

if (-f $file){
  $dbf->drop_table( tbl => "ACH_ID2Function" );
}
else{
  print STDERR "Can not drop ID tabel, no new file to load!"
}

$dbf->create_table( tbl  => "ACH_ID2Group",
		    flds => "id varchar(32),
                             function varchar(500), 
                             md5 varchar(32),
                             source varchar(100),
                             "
		  );
$dbf->load_table( tbl => "ACH_ID2Group",file => $file) if (-f $file); 
$dbf->create_index( idx  => "ACH_ID2Group_id_ix",
		    tbl  => "ACH_ID2Group",
		    type => "btree",
		    flds => "id" );
$dbf->create_index( idx  => "ACH_ID2Group_expert_ix",
		    tbl  => "ACH_ID2Group",
		    type => "btree",
		    flds => "id" );
$dbf->create_index( idx  => "ACH_ID2Group_function_ix",
		    tbl  => "ACH_ID2Group",
		    type => "btree",
		    flds => "function" );
$dbf->create_index( idx  => "ACH_ID2Group_md5_ix",
		    tbl  => "ACH_ID2Group",
		    type => "btree",
		    flds => "md5" );

$dbf->drop_table( tbl => "ACH_ProteinSequence2MD5" );

$dbf->create_table( tbl  => "ACH_Sequence2MD5",
		    flds => "sequence text, 
                             md5 varchar(100),
                            "
		  );

if (-s "$FIG_Config::data/ACHresolution/ACH_Sequence2MD5")
  {
    $dbf->load_table( tbl => "ACH_Sequence2MD5",file => "$FIG_Config::data/ACHresolution/ACH_Sequence2MD5") ;
  }

$dbf->create_index( idx  => "ACH_Sequence2MD5_f1_ix",
		    tbl  => "ACH_Sequence2MD5",
		    type => "btree",
		    flds => "sequence" );
$dbf->create_index( idx  => "ACH_Sequence2MD5_f2_ix",
		    tbl  => "ACH_Sequence2MD5",
		    type => "btree",
		    flds => "md5" );


