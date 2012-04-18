use Data::Dumper;
use Carp;
use DBI;
use strict;
use Getopt::Long;


my $filename = '';
my $dbname   = '';
my $dbhost   = 'localhost';
my $dbi      = 'mysql'; # db interface e.g. mysql , postgress
my $dbuser   = 'ach';
my $dbpass   = '';
my $dir      = '';
my $verbose  = 0;
my $dbtype   = 'mysql';


my $table = "ACH_DATA";

GetOptions ('verbose'    => \$verbose, 
	    'filename=s' => \$filename,
	    'dir=s'      => \$dir,
	    'dbhost=s'   => \$dbhost,
	    'dbname=s'   => \$dbname,
	    'dbtype=s'   => \$dbtype,
	    );

unless($filename){
    print STDERR "No file $filename\n";
    exit;
}

unless ($dbname){
    print STDERR "No DB Name, need database name to load data";
    exit;
}

my $fig_path = "/vol/seed-anno-mirror";
my $dbuser = "root";
my $dbhost = "bio-data-1.mcs.anl.gov";
my $dbpass = '';
my $dbport = '';
my $dbh;


my $org_ids = {};
my $source_ids = {};
my $func_ids = {};



my @driver_names = DBI->available_drivers;
my %drivers      = DBI->installed_drivers;

print STDERR join " " , (@driver_names , "\n") if ($verbose);

if ($dbhost)
{
    $dbh = DBI->connect("DBI:mysql:dbname=$dbname;host=$dbhost", $dbuser, $dbpass);
}

unless ($dbh) {
    print STDERR "Error , " , DBI->error , "\n";
}


# my $rv  = $dbh->do("ALTER TABLE $table DISABLE KEYS");

# print $rv , "\n" if ($verbose);


my $sth = $dbh->prepare("INSERT INTO $table (md5,id,function,organism,source) VALUES (?,?,?,?,?)");

# while(<CSV>) {
#     chomp;
#     my ($foo,$bar,$baz) = split /,/;
#     $sth->execute( $foo, $bar, $baz );
# }


print STDERR "Open $filename\n"  if ($verbose);

open (FILE , "$filename") or die "Can't open file $filename\n";

my $counter = 0;

while (my $line = <FILE> ){
    chomp $line;
    my ( $id , $func , $md5 , $source , $url ) = split "\t" , $line;

 
    unless ($id =~ m/fig\|/) {
      ($id) = $id =~ m/^[^\|]*\|(.+)/;
    }

    #$func =~ s/'/\'/mg;
    print STDERR "Getting org , source and function\n" if ($verbose);
    print join "\t" ,  $md5 , $id , get_function($dbh,$func,$func_ids) , get_org($dbh,$id) , get_source($dbh,$source,$source_ids , "Expert") , "Expert" , "\n";

  
    my $return = $sth->execute( $md5 , $id , get_function($dbh,$func,$func_ids) , get_org($dbh,$id) , get_source($dbh,$source,$source_ids , "Expert") );
    
    unless ( $return == 1 ){
	print "ERROR:\t $md5 , $id , $func , $source \n";
	exit;
    }
   
    $counter++;
    unless ( $counter % 100000){
	print "$counter\t $md5 , $id , $func , $source \n"; 
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
  my ($dbh , $id) = @_;
  
  
  my $statement = "select ACH_DATA.organism from ACH_DATA where  ACH_DATA.id=\"$id\" ";	
  my @row  = $dbh->selectrow_array($statement);
  
  if (scalar @row){
    return $row[0];
  }
  else{
    print STDERR "No Organism for $id\n";
  }

  return -1 ;
}

sub get_source {
  my ($dbh , $source , $source_ids , $type) = @_;
  
  unless ( $source_ids->{ $source } ){
      
    my $statement = "SELECT _id , name from ACH_SOURCES where name='$source' and type='$type'";	
    my @row  = $dbh->selectrow_array($statement);
    
    if (scalar @row){
      $source_ids->{ $source } = $row[0];
    }
    else{
      my $r = $dbh->do("INSERT INTO ACH_SOURCES(name , type) VALUES ('$source' , '$type')");
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
