#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;

sub usage {
  print "create the module containing the list of rights supported by the application.\n";
  print "create_application_rights_module.pl -path <path_to_current> -application <application_name>\n";
}

# read in parameters
my $path  = '';
my $app  = '';

GetOptions ( 'path=s' => \$path, 'application=s' => \$app );

unless ($app and $path) {
  &usage();
  exit 0;
}

unshift(@INC, "$path/WebApplication");
unshift(@INC, "$path/$app");

opendir(DIR, "$path/$app/WebPage");
my @web_pages_app = readdir DIR;
closedir DIR;
opendir(DIR, "$path/WebApplication/WebPage");
my @web_pages_wa = readdir DIR;
closedir DIR;

my @rights;
foreach my $entry (@web_pages_wa) {
  if ($entry =~ /^\w+\.pm$/) {
    $entry =~ s/\.pm//;
    {
      no strict;
      my $package = "WebPage::".$entry;
      eval "require $package;";
      my $page_rights = eval "WebPage::".$entry."->supported_rights()";
      if (ref($page_rights) && scalar(@$page_rights)) {
	push(@rights, @$page_rights);
      }
    }
  }
}

foreach my $entry (@web_pages_app) {
  if ($entry =~ /^\w+\.pm$/) {
    $entry =~ s/\.pm//;
    {
      no strict;
      my $package = $app."::WebPage::".$entry;
      eval "require $package;";
      my $page_rights = eval $app."::WebPage::".$entry."->supported_rights()";
      if (ref($page_rights) && scalar(@$page_rights)) {
	push(@rights, @$page_rights);
      }
    }
  }
}
@rights = map { [ "'".$_->[0]."'", "'".$_->[1]."'", "'".$_->[2]."'" ] } @rights;

umask 0002;
open(FH, ">$path/$app/MyAppRights.pm") or die "Could not open file for writing: $@\n";
print FH "package $app\::MyAppRights;\n\n1;\n\nuse strict;\nuse warnings;\n\n";
print FH "sub rights {\n\treturn [ ";
foreach my $right (@rights) {
  print FH "[ ".join(",", @$right)." ], ";
}
print FH "];\n}\n";
close FH;
