#!/usr/bin/env perl

use strict;
use warnings;

use WebApplicationDBHandle;

use Getopt::Long;


sub usage {
  print "user_add.pl >>> add a user to the web application database\n";
  print "user_add.pl -firstname <fn> -lastname <ln> -login <login> -email <email> [ -comment <text> ]\n";
}

# read in parameters
my $firstname  = '';
my $lastname   = '';
my $login      = '';
my $email      = '';
my $comment    = '';

GetOptions ( 'firstname=s' => \$firstname,
	     'lastname=s' => \$lastname,
	     'login=s' => \$login,
	     'email=s' => \$email,
	     'comment=s' => \$comment,
	   );


unless ($firstname and $lastname and $login and $email) {
  &usage();
  exit 0;
}


# initialize db-master
my ($dbmaster, $error) = WebApplicationDBHandle->new();

# check if we got a dbmaster
if ($error) {
  print $error."\n";
  exit 0;
}

print "Creating user $login ($firstname $lastname, $email).\n";

# sanity checks
my $user;
if ($user = $dbmaster->User->init({ email => $email })) {
  print "This email has already been registered for ".$user->login.", aborting.\n";
  exit 0;
}

if ($user = $dbmaster->User->init({ login => $login })) {
  print "This login has already been registered for ".
    $user->firstname." ".$user->lastname.", aborting.\n";
  exit 0;
}

# create the user in the db
$user = $dbmaster->User->create( { email        => $email,
				   firstname    => $firstname,
				   lastname     => $lastname,
				   login        => $login,
				   active       => 1,
				   
				 } );

unless (ref $user and $user->isa('WebServerBackend::User')) {
  print "Unable to create user. Quit.\n";
  exit 0;
}

print "Done.\n";
