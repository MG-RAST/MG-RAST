#!/usr/bin/env perl

use strict;
use warnings; 

use PPOGenerator;
use Getopt::Long;

use constant KNOWN_BACKENDS => { 'MySQL' => 1, 'SQLite' => 1 };

# usage message 
sub usage {
  my $error = shift;
  print "Usage: ppo_generate.pl -xml xml_file [-backend db_backend -database db_name] [-file sql output filename] [-host hostname] [-user username] [-password passwd] [-port port] [-socket socket] [-perl_target target_dir/]\n";
  print "Error: $error\n" if($error);
  exit;
}

print "PPO Generator:\n";

# get command line parameters
my %options = ();
GetOptions (\%options, 
	    "xml=s",
	    "backend=s", "database=s",
	    "perl_target=s",
	    "file=s",
	    "user=s", "password=s",
	    "host=s", "port=s", "socket=s",
	   ); 


# check for xml file
unless(exists($options{xml}) and -f $options{xml}) {
  &usage("No xml definition file given or file not found.");
}

# read in xml definition
my $generator;
eval { 
  $generator = PPOGenerator->new($options{xml}) 
};
if (ref $generator) {
  print "XML definition successfully read.\n";
  
  # generate perl modules
  if ($options{perl_target}) {
    print "Creating perl modules for PPO... ";
    eval { $generator->generate_perl($options{perl_target}) };
    if ($@) {
      print "failed.\n .. with $@";
    }
    else {
      print "done.\n";
    }
  }
  
  # create database
  if ($options{backend} and $options{database}) {
    print "Creating database for PPO... ";
    if (KNOWN_BACKENDS->{$options{backend}}) {
      eval { $generator->create_database( -backend => $options{backend},
					  -database => $options{database},
					  -host => ($options{host}) ? $options{host} : '',
					  -port => ($options{port}) ? $options{port} : '',
					  -user => ($options{user}) ? $options{user} : '',
					  -password => ($options{password}) ? $options{password} : '',
					  -create => 1,
					  -socket => ($options{socket}) ? $options{socket} : '',
					  -file => ($options{file}) ? $options{file} : undef ) };
      if ($@) {
	print "failed.\n .. with $@";
      }
      else {
	print "done.\n";
      }
    }
    else {
      print "failed.\n .. with Unknown backend type.\n";
    }
  }

}
elsif ($@) { 
  &usage("Invalid xml definition:\n $@"); 
}
else {
  &usage("Unable to read xml defintion (PPOGenerator->new returned undef).");
}

print "Bye.\n";

exit 1;
