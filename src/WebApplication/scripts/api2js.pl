#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use JSON;
use LWP::UserAgent;

sub TO_JSON { return { %{ shift() } }; }

my $auth_server_url = "https://nexus.api.globusonline.org/goauth/token?grant_type=client_credentials";

sub usage {
  print "api2js.pl >>> create a JSON structure file from a REST API\n";
  print "api2js.pl -url <url to api> -outfile <file for js output> [-commandline <directory to place command line scripts> -pod <pod documentation file]\n";
}

# read in parameters
my $url     = '';
my $outfile = '';
my $commandline = '';
my $pod = '';

GetOptions ( 'url=s' => \$url,
	     'outfile=s' => \$outfile,
	     'commandline=s' => \$commandline,
	     'pod=s' => \$pod );

unless ($url and $outfile) {
  &usage();
  exit 0;
}

# initialize json object and user agent
my $json = new JSON;
my $ua = LWP::UserAgent->new;

print "\nconnecting to API...\n\n";

# retriving basic info
my $data = $json->decode($ua->get($url)->content);

my $numres = scalar(@{$data->{resources}});
print "got basic data, retrieving detail information for $numres resources...\n\n";

my $structure = { service => { url => $data->{url},
			       name => $data->{service},
			       version => $data->{version},
			       description => $data->{description} } };

# iterate over all resources
my $resources = [];
my $i = 1;
foreach my $resource (@{$data->{resources}}) {
  my $retval = $json->decode($ua->get($resource->{url})->content);
  push(@$resources, $retval);
  print "received resource ".$resource->{name}." [$i/$numres]\n";
  $i++
}

# add resources to return structure
$structure->{resources} = $resources;

# check if POD documentation should be created
if ($pod) {
  # module name and description
  my $pod_string = "=pod\n\n=head1 ".$structure->{service}->{name}."\n\n".$structure->{service}->{description}."\n\n=head1 Resources\n\n";
  
  # iterate over the resources
  foreach my $res (sort { $a->{name} cmp $b->{name} } @{$structure->{resources}}) {
    $pod_string .= "=head2 ".$res->{name}."\n\n=head3 Description\n\n".$res->{description}."\n\n=head3 Requests";
    foreach my $req (@{$res->{requests}}) {
      $pod_string .= "\n\n=head4 ".$req->{name}."\n\n=head5 Description\n\n".$req->{description}."\nThis is a ".$req->{type}." ".$req->{method}." request.";
      unless (ref($req->{attributes})) {
	$pod_string .= " This request has no parameters.";
	next;
      }
      $pod_string .= "\n\n=head5 Parameters\n\n=over4\n\n";
      foreach my $param (keys(%{$req->{parameters}->{body}})) {
	my $pm = $req->{parameters}->{body}->{$param};
	$pm->[0] =~ s/cv/controlled vocabulary/;
	$pod_string .= "=item * $param (".$pm->[0];
	if (ref($pm->[1]) eq 'ARRAY') {
	  if (! ref($pm->[0]) && $pm->[0] eq 'list') {
	    $pod_string .= " of ".$pm->[1]->[0].")\n\n";
	    $pod_string .= $pm->[1]->[1]."\n\n";
	  } else {
	    $pod_string .= ")\n\n";
	    $pod_string .= "This parameter value can be chosen from the following (the first being default):\n\n";
	    foreach my $cvitem (@{$pm->[1]}) {
	      $pod_string .= " ".$cvitem->[0]." - ".$cvitem->[1]."\n";
	    }
	    $pod_string .= "\n";
	  }
	} else {
	  $pod_string .= ")\n\n".$pm->[1]."\n\n";
	}
	$pod_string .= "This parameter must be passed in the message body.\n\n";
      }
      foreach my $param (keys(%{$req->{parameters}->{options}})) {
	my $pm = $req->{parameters}->{options}->{$param};
	$pm->[0] =~ s/cv/controlled vocabulary/;
	$pod_string .= "=item * $param (".$pm->[0];
	if (ref($pm->[1]) eq 'ARRAY') {
	  if (! ref($pm->[0]) && $pm->[0] eq 'list') {
	    $pod_string .= " of ".$pm->[1]->[0].")\n\n";
	    $pod_string .= $pm->[1]->[1]."\n\n";
	  } else {
	    $pod_string .= ")\n\n";
	    $pod_string .= "This parameter value can be chosen from the following (the first being default):\n\n";
	    foreach my $cvitem (@{$pm->[1]}) {
	      $pod_string .= " ".$cvitem->[0]." - ".$cvitem->[1]."\n";
	    }
	    $pod_string .= "\n";
	  }
	} else {
	  $pod_string .= ")\n\n".$pm->[1]."\n\n";
	}
	$pod_string .= "This is an optional parameter and may be passed in the query string.\n\n";
      }
      foreach my $param (keys(%{$req->{parameters}->{required}})) {
	my $pm = $req->{parameters}->{required}->{$param};
	$pm->[0] =~ s/cv/controlled vocabulary/;
	$pod_string .= "=item * $param (".$pm->[0];
	if (ref($pm->[1]) eq 'ARRAY') {
	  if (! ref($pm->[0]) && $pm->[0] eq 'list') {
	    $pod_string .= " of ".$pm->[1]->[0].")\n\n";
	    $pod_string .= $pm->[1]->[1]."\n\n";
	  } else {
	    $pod_string .= ")\n\n";
	    $pod_string .= "This parameter value can be chosen from the following (the first being default):\n\n";
	    foreach my $cvitem (@{$pm->[1]}) {
	      $pod_string .= " ".$cvitem->[0]." - ".$cvitem->[1]."\n";
	    }
	    $pod_string .= "\n";
	  }
	} else {
	  $pod_string .= ")\n\n".$pm->[1]."\n\n";
	}
	$pod_string .= "This is a required parameter and must be passed as a REST parameter.\n\n";
      }
      $pod_string .= "=back\n\n";
      $pod_string .= "=head5 Return Attributes\n\n=over4\n\n";
      foreach my $param (keys(%{$req->{attributes}})) {
      	my $att = $param;
      	my $att_type = $req->{attributes}->{$param}->[0];
      	my $att_desc = $req->{attributes}->{$param}->[1];
	my $att_obj;
      	while (ref($att_desc) eq 'ARRAY') {
	  unless ($att_type =~ /object/) {
	    $att_type .= " of ".$att_desc->[0]."s";
	  } else {
	    $att_obj = $att_desc->[0];
	  }
      	  $att_desc = $att_desc->[1];
      	}
      	$pod_string .= "=item * $att ($att_type)\n\n";
      	if ($att_obj) {
      	  $pod_string .= "This attribute has an object structure:\n";
      	  foreach my $key (keys(%$att_obj)) {
      	    my $obj_type = $att_obj->{$key}->[0];
      	    my $obj_att = $att_obj->{$key}->[1];
      	    while (ref($obj_att) eq 'ARRAY') {
      	      $obj_type .= " of ".$obj_att->[0]."s";
      	      $obj_att = $obj_att->[1];
      	    }
      	    $pod_string .= "$key ($obj_type) - ".$obj_att."\n";
      	  }
      	  $pod_string .= "\n";
      	} else {
      	  $pod_string .= $att_desc."\n\n";
      	}
      }
    }
  }
  $pod_string .= "=cut\n\n";
  if (open(FH, ">$pod")) {
    print FH $pod_string;
    close FH;
  } else {
    print "Could not open POD file: $@\n";
  }
}

# print result to file
if (open(FH, ">$outfile")) {
  print FH $json->pretty->encode($structure);
  close FH;
} else {
  die "could not open outfile for writing ($outfile): $@";
}

# check if the commandline option is set
if ($commandline) {

  print "creating command line scripts...\n";

  # check for target directoru
  unless (-d $commandline) {
    mkdir $commandline;
    unless (-d $commandline) {
      print "could not create command line script directory '$commandline': $@\n";
      exit;
    }
  }

  # iterate over the resources
  foreach my $resource (@$resources) {
    
    # iterate over the requests of each resource
    foreach my $request (@{$resource->{requests}}) {
      # skip info requests
      next if ($request->{name} eq 'info');
      next unless ($request->{name} eq 'instance' || $request->{name} eq 'query');
      my $resname = $resource->{name};
      my $name = lc($request->{method}).'_'.$resname;
      my $is_list = 0;
      if ($request->{name} eq 'query') {
	$name .= "_list";
	$is_list = 1;
      }
      my $code = <<"EOT";
#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use LWP::UserAgent;
use JSON;

use Bio::KBase::IDServer::Client;

sub usage {
  print "$name.pl >>> retrieve a 
EOT
chomp $code;
if ($is_list) {
  $code .= "list of ".$resname."s";
} else {
  $code .= $resname;
}
$code .= <<"EOT";
 from the communities API\\n";
  print "$name.pl -id <id of the $resname>\\n"; 
}

sub help {
  my \$text = qq~$name

retrieve a 
EOT
chomp $code;
if ($is_list) {
  $code .= "list of ".$resname."s";
} else {
  $code .= $resname;
}
$code .= <<"EOT";
 from the communities API

EOT
chomp $code;
if (! $is_list) {
  $code .= "\nParameters\n\n\tid - the is of the $resname to be retrieved from the API";
}
$code .= <<"EOT";


Options

\thelp - display this message

\tuser - username to authenticate against the API, requires a password to be set as well

\tpass - password to authenticate against the API, requires a username to be set as well

\ttoken - Globus Online authentication token

\twebkey - MG-RAST webkey to synch with the passed Globus Online authentication

\tverbosity - verbosity of the result data, can be one of [ 'minimal', 'verbose', 'full' ]

EOT
chomp $code;
if ($is_list) {
  $code .= "\n\tlimit - the maximum number of data items to be returned\n\n\toffset - the zero-based index of the first data item to be returned\n\n";
}
$code .= <<"EOT";
~;
  system "echo '\$text' | more";
}

my \$HOST      = '$url/$resname/';

EOT
chomp $code;
if (! $is_list) {
  $code .= "my \$id        = '';\n";
}
$code .= <<"EOT";
my \$user      = '';
my \$pass      = '';
my \$token     = '';
my \$verbosity = 'full';
my \$help      = '';
my \$webkey    = '';
EOT
chomp $code;
if ($is_list) {
  $code .= "\nmy \$offset    = '0';\nmy \$limit     = '10';\n";
}
$code .= <<"EOT";


GetOptions ( 
EOT
chomp $code;
if (! $is_list) {
  $code .= "'id=s' => \\\$id,\n             ";
}
$code .= <<"EOT";
'user=s' => \\\$user,
             'pass=s' => \\\$pass,
             'token=s' => \\\$token,
             'verbosity=s' => \\\$verbosity,
             'help' => \\\$help,
             'webkey=s' => \\\$webkey
EOT
chomp $code;
if ($is_list) {
  $code .= ",\n             'limit=s' => \\\$limit,\n             'offset' => \\\$offset";
}
$code .= <<"EOT";
 );

if (\$help) {
  &help();
  exit 0;
}
EOT
chomp $code;
if (! $is_list) {
  $code .= "\nunless (\$id) {\n  &usage();\n  exit 0;\n}\n";
}
$code .= <<"EOT";
\n\nif (\$id =~/^kb\\|/) {
  my \$id_server_url = "http://bio-data-1.mcs.anl.gov:8080/services/idserver";
  my \$idserver = Bio::KBase::IDServer::Client->new(\$id_server_url);
  my \$return = \$idserver->kbase_ids_to_external_ids( [ \$id ]);
  \$id = \$return->{\$id}->[1] ;
}

if (\$user || \$pass) {
  if (\$user && \$pass) {
    my \$exec = 'curl -s -u '.\$user.':'.\$pass.' -X POST "$auth_server_url"';
    my \$result = `\$exec`;
    my \$ustruct = "";
    eval {
      my \$json = new JSON;
      \$ustruct = \$json->decode(\$result);
    };
    if (\$\@) {
      die "could not reach auth server";
    } else {
      if (\$ustruct->{access_token}) {
        \$token = \$ustruct->{access_token};
      } else {
        die "authentication failed";
      }
    }
  } else {
    die "you must supply both username and password";
  }
}

my \$url = \$HOST.\$id."?verbosity=\$verbosity
EOT
chomp $code;
if ($is_list) {
  $code .= "&limit=\$limit&offset=\$offset";
}
$code .= <<"EOT";
";
if (\$webkey) {
  \$url .= "&webkey=".\$webkey;
}
my \$ua = LWP::UserAgent->new;
if (\$token) {
  \$ua->default_header('user_auth' => \$token);
}
print \$ua->get(\$url)->content;
EOT
if (open(FH, ">$commandline/$name.pl")) {
print FH $code;
close FH;
} else {
print "could not open output file '$commandline/$name.pl': $@\n";
exit;
}
    }
  }
}

print "\nall done.\n\nHave a nice day :)\n\n";

exit;
