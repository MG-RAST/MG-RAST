#!/soft/packages/perl/5.12.1/bin/perl

use strict;
use warnings;

use Getopt::Long;

sub usage {
  print "create_cdmi_rest_resources.pl >>> create REST resource files from the CDMI-EntityAPI.spec\n";
  print "create_cdmi_rest_resources.pl -input <input file> -output <output directory>\n";
}

my $input = "";
my $output = "";

GetOptions ( 'input=s' => \$input,
	     'output=s' => \$output );

unless ($input and $output) {
  &usage();
  exit 0;
}

my $entity_names = {};
my $entities = {};
my $real_entities = {};
my $descriptions = {};
if (open(FH, $input)) {
  my $attributes = [];
  while (<FH>) {
    chomp;
    if ($_ =~ /^typedef structure \{/) {
      $attributes = [];
    } elsif (my (undef, $att) = $_ =~ /^[\s\t]+(string|float|int|date|list<string>) ([^\s]+)[\w\s]*;$/) {
      push(@$attributes, $att);
    } elsif (my ($entity) = $_ =~ /\} fields_(\w+) ;/) {
      $entities->{$entity} = $attributes;
      my $line = <FH>;
      $line = <FH>;
      $descriptions->{$entity} = "";
      while ($line ne "*/") {
	$line = <FH>;
	if ($line ne "*/\n") {
	  $descriptions->{$entity} .= $line;
	}
	chomp $line;
      }
    } elsif (my ($entity_name) = $_ =~ /^funcdef get_entity_(\w+)\(/) {
      $entity_names->{$entity_name} = 1;
    }
  }
  close FH;
  
  foreach my $key (keys(%$entity_names)) {
    $real_entities->{$key} = $entities->{$key};
  }

  use Data::Dumper;
  print STDERR Dumper($real_entities)."\n";

  foreach my $entity (keys(%$real_entities)) {
    if (open(FH, ">$output/".lc($entity).".pm")) {
      print FH qq#package resources::#.lc($entity).qq#;

use CGI;
use JSON;

use LWP::UserAgent;

my \$cgi = new CGI;
my \$json = new JSON;
\$json = \$json->utf8();

sub about {
  my \$content = { 'description' => '#.$descriptions->{$entity}.qq#',
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/json" };

  print \$cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print \$json->encode(\$content);
  exit 0;
}

sub request {
  my (\$params) = \@_;

  my \$rest = \$params->{rest_parameters};

  if (\$rest && scalar(@\$rest) == 1 && \$rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  my \$ua = LWP::UserAgent->new;
  my \$cdmi_url = "http://bio-data-1.mcs.anl.gov/services/cdmi_api";
  if (! \$rest || ! scalar(@\$rest)) {    
    my \$data = { 'params' => [ 0, 1000000, ["id"] ],
		 'method' => 'CDMI_EntityAPI.all_entities_#.$entity.qq#',
		 'version' => "1.1" };
    
    my \$response = \$json->decode(\$ua->post(\$cdmi_url, Content => \$json->encode(\$data))->content);
    \$response = \$response->{result};

    my \$#.lc($entity).qq#_list = [];
    @\$#.lc($entity).qq#_list = map { keys(%\$_) } @\$response;

    print \$cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print \$json->encode( \$#.lc($entity).qq#_list );
    exit 0;
  }

  if (\$rest && scalar(@\$rest) == 1) {
    my \$data = { 'params' => [ [ \$rest->[0] ], [ "#.join('", "', @{$real_entities->{$entity}}).qq#" ] ],
		 'method' => 'CDMI_EntityAPI.get_entity_#.$entity.qq#',
		 'version' => "1.1" };
    
    my \$content = \$json->encode(\$data);
    \$content =~ s/\%7C/\|/g;
    my \$response = \$json->decode(\$ua->post(\$cdmi_url, Content => \$content)->content);
    my \@k = keys(%{\$response->{result}->[0]});
    my \$#.lc($entity).qq# = \$response->{result}->[0]->{\$k[0]};
    \$#.lc($entity).qq#->{url} = \$cgi->url."/#.lc($entity).qq#/".\$rest->[0];
    my \$out = \$json->encode( \$#.lc($entity).qq# );
    \$out =~ s/\%7C/\|/g;

    print \$cgi->header(-type => 'application/json',
		       -status => 200,
		       -Access_Control_Allow_Origin => '*' );
    
    print \$out;
    exit 0;
  }
}

sub TO_JSON { return { %{ shift() } }; }

1;#;
close FH;
} else {
print "could not open output file\n";
}
}

} else {
  print "could not open input file $input: $! $@\n";
  exit 1;
}
