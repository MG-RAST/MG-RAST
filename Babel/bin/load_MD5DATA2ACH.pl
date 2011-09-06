use Data::Dumper;
use Carp;
use DBI;
use strict;

my $file = shift @ARGV;

my $table = shift @ARGV || "ACH_DATA";


unless(-f $file){
    print STDERR "No file $file\n";
    exit;
}

my $fig_path = "/vol/seed-anno-mirror";
my $db = "ACH_TEST";
my $dbuser = "root";
my $dbhost = "bio-data-1.mcs.anl.gov";
my $dbpass = '';
my $dbport = '';
my $dbh;


my $org_ids = {};
my $source_ids = {};
my $func_ids = {};

if ($dbhost)
{
    $dbh = DBI->connect("DBI:mysql:dbname=$db;host=$dbhost", $dbuser, $dbpass);
}

unless ($dbh) {
    print STDERR "Error , " , DBI->error , "\n";
}


my $rv  = $dbh->do("ALTER TABLE $table DISABLE KEYS");
# print $rv , "\n";


my $sth = $dbh->prepare("INSERT INTO $table (md5,id,function,organism,source) VALUES (?,?,?,?,?)");

# while(<CSV>) {
#     chomp;
#     my ($foo,$bar,$baz) = split /,/;
#     $sth->execute( $foo, $bar, $baz );
# }


open (FILE , "$file") or die "Can't open file $file\n";

my $counter = 0;

while (my $line = <FILE> ){
    chomp $line;
    my ( $md5 , $id , $func , $org , $source ) = split "\t" , $line;

    $func =~ s/'/\'/mg;
    $org  =~ s/'/\\\'/mg; 
    # $org  =~ s/\./\\\./mg;
    my $return = $sth->execute( $md5 , $id , get_function($dbh,$func,$func_ids) , get_org($dbh,$org,$org_ids) , get_source($dbh,$source,$source_ids) );
    
    unless ( $return == 1 ){
	print "ERROR:\t $md5 , $id , $func , $org , $source \n";
	exit;
    }
   
    $counter++;
    unless ( $counter % 100000){
	print "$counter\t $md5 , $id , $func , $org , $source \n"; 
    } 
}

my $rv  = $dbh->do("ALTER TABLE $table ENABLE KEYS");

my $baz = '';
my $statement = "";



# $sth = $dbh->prepare("SELECT md5, id FROM ACH_ID2GROUP WHERE id=?");

#my $response = $dbh->do( $statement );

#my $response = $dbh->do( $index );
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


sub get_org {
    my ($dbh , $org , $org_ids) = @_;

    unless ( $org_ids->{ $org } ){
	my $sth = $dbh->prepare("INSERT INTO ACH_ID2GROUP(md5,id,function,organism,source) VALUES (?,?,?,?,?)");
	my $statement = "SELECT _id , name from ACH_ORGANISMS where name=\"$org\"";	
	my @row  = $dbh->selectrow_array($statement);
	
	if (scalar @row){
	    $org_ids->{ $org } = $row[0];
	}
	else{
	    print "Adding organism : $org \n";
	 
	    my $r = $dbh->do("INSERT INTO ACH_ORGANISMS(name) VALUES ('$org')");
	    my @row  = $dbh->selectrow_array($statement);
	    $org_ids->{ $org } = $row[0];
	}
    }
    
    return $org_ids->{ $org } ;
}

sub get_source {
    my ($dbh , $source , $source_ids) = @_;

    unless ( $source_ids->{ $source } ){

	my $statement = "SELECT _id , name from ACH_SOURCES where name='$source'";	
	my @row  = $dbh->selectrow_array($statement);
	
	if (scalar @row){
	    $source_ids->{ $source } = $row[0];
	}
	else{
	    my $r = $dbh->do("INSERT INTO ACH_SOURCES(name) VALUES ('$source')");
	    my @row  = $dbh->selectrow_array($statement);
	    $source_ids->{ $source } = $row[0];
	}
    }
    
    return $source_ids->{ $source } ;

}

sub get_function {
    my ($dbh , $func , $func_ids) = @_;

    unless ( $func_ids->{ $func } ){
      my $tmp = $func;
      my $count = $tmp =~ s/'/\\'/gc;
      if ($count){
	print $func , "\n";
	print $tmp , "\n";

      }
	my $statement = "SELECT _id , function from ACH_FUNCTIONS where function='$tmp'";	
	my @row  = $dbh->selectrow_array($statement);
	
	if (scalar @row){
	    $func_ids->{ $func } = $row[0];
	}
	else{

	  my $r = $dbh->do("INSERT INTO ACH_FUNCTIONS(function) VALUES ('$tmp')");
	  my @row  = $dbh->selectrow_array($statement);
	  $func_ids->{ $func } = $row[0];
	}
    }
    
    return $func_ids->{ $func } ;

}
