use Data::Dumper;
use Carp;
use DBI;
use strict;
use warnings;
use M5NR;


use Getopt::Long;

my $verbose = '';
my $id      = '';
my $md5     = '';
my $seq     = '';
my $org     = '';
my $func    = '';
my $analyze = 0 ;
my $explain = 0 ;
my $source  = '';
my $help    = 0 ;
my $option  = '';

my $options = { md52id  => 1 ,
		md52seq => 1 ,
		id2md5  => 1 ,
		md52overview => 1 ,
	      } ;


GetOptions( "verbose!"   =>\$verbose,
	    "id=s"       =>\$id,
            "sequence=s" =>\$seq ,
            "md5=s"      =>\$md5,
	    "organism=s" =>\$org,
	    "function=s" =>\$func,
	    "explain!"   =>\$explain ,
	    "analyze!"   =>\$analyze ,
	    "source=s"   =>\$source ,
	    "help"       =>\$help ,
	    "option=s"   =>\$option ,
 	  );






my $fig_path = "/vol/seed-anno-mirror";
my $db = "mgrast_ach_prod";
my $dbuser = "root" || "ach" ;
my $dbhost = ''; #"kursk-3.mcs.anl.gov";
my $dbpass = '';
my $dbport = '';
my $dbh;


if ($dbhost)
{
    $dbh = DBI->connect("DBI:Pg:dbname=$db;host=$dbhost", $dbuser, $dbpass);
}

unless ($dbh) {
    # print STDERR "Error , " , DBI->error , "\n";
}

my $babel = M5NR->new( $dbh );


if($help or not ( $options->{$option} or $seq ) ){
    &help($babel) ;
    exit;
}
 

if  ($seq){
  output( [[$babel->sequence2md5($seq)]]);
}
elsif ($md5 and $option eq 'md52seq' ){
  output( [[$babel->md5s2sequences([$md5])]]);
}
elsif( $option eq 'md52id' ){
    my $rows = &md52id($babel , [$md5] , $source) ;
    output($rows);
}
elsif( $option eq 'md52overview'){
  output( $source ? $babel->md5s2sets4source([$md5] , $source) : $babel->md5s2sets([$md5]) );
}

if( $option eq 'id2md5'){
   output($babel->id2md5($id));
}

exit;

if ($md5){
  
  print "Query for $md5\n";
  foreach my $row (@{ $babel->md52id($md5) }){
    print join "\t" , @$row , "\n";
  }
  foreach my $row (@{ $babel->md52org($md5) }){
    print join "\t" , @$row , "\n";
  }
   foreach my $row (@{ $babel->md52function($md5) }){
    print join "\t" , @$row , "\n";
  }
  print $babel->md5s2sequences( [$md5 , "5b8a2c111c8258cc82c275f755a2c15d"] );
  print "\nmd5s to organisms\n";
  foreach my $row (@{ $babel->md5s2organisms( [$md5 , $md5 , "5b8a2c111c8258cc82c275f755a2c15d" ] ) } ){
    print join "\t" , @$row , "\n";
  }
  exit;
}

print "\nNext ID2... \n\n";
if ($id){
  
   print "Query for $id\n";
   foreach my $row (@{ $babel->id2md5($id) }){
     print join "\t" , @$row , "\n";
   }
  foreach my $row (@{ $babel->id2org($id) }){
    print join "\t" , @$row , "\n";
  }
   foreach my $row (@{ $babel->id2function($id) }){
     print join "\t" , @$row , "\n";
   }
   print "Query sequences for 'fig|1148.1.peg.3614' , 'fig|2465.1.peg.98'\n";
   print $babel->ids2sequences([ 'fig|1148.1.peg.3614' , 'fig|2465.1.peg.98']);
}

print "\nNext ID2... regexp \n\n";

if (0){
  
   print "Query for $id\n";
   foreach my $row (@{ $babel->id2md5($id , 1) }){
     print join "\t" , @$row , "\n";
   }
  foreach my $row (@{ $babel->id2org($id , 1) }){
    print join "\t" , @$row , "\n";
  }
   foreach my $row (@{ $babel->id2function($id , 1) }){
    print join "\t" , @$row , "\n";
  }
  
}

print "\nNext ORG2...  \n\n";

if (0){
  
   print "Query for $org\n";
   foreach my $row (@{ $babel->org2md5($org ,) }){
     print join "\t" , @$row , "\n";
   }
  foreach my $row (@{ $babel->org2id($org) }){
    print join "\t" , @$row , "\n";
  }

   foreach my $row (@{ $babel->org2function($org) }){
    print join "\t" , @$row , "\n";
  }

}


print "\nNext ORG2... regexp  \n\n";

if (0){
  
   foreach my $row (@{ $babel->org2function($org ,1) }){
    print join "\t" , @$row , "\n";
  }

}


print "\nNext Function... test \n\n";

if ($func){
  
  print "Query for md5\n";
  foreach my $row (@{ $babel->functions2md5s([$func]) }){
    print join "\t" , @$row , "\n";
  }
  
  print "Query for sets\n";
  foreach my $row (@{ $babel->functions2sets([$func , $func]) }){
    print join "\t" , @$row , "\n";
  }
  
}


sub md52id {
    my ($babel , $md5s , $source) = @_ ;
    return $source ? $babel->md5s2ids4source($md5s , $source) : $babel->md5s2ids($md5s , $source) ;
}


sub output{
    my ($rows) = @_ ;
    foreach my $row (@$rows){
	print join "\t" , @$row , "\n";
    }
}


sub help {
    my ($babel) = @_ ;


    print "$0 -option OPTION -md5 MD5 -id ID -source SOURCE -help \n";
    print "Options: " , ( join " , " , keys %$options ) , "\n" ;
    
    my $sources = $babel->sources ;

    print "Available sources:\n";
    foreach my $source ( keys %$sources ){
	my $counts = {} ;
	print "\t$source\n";
    }

}
