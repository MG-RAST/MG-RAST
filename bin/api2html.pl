#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use JSON;
use LWP::UserAgent;

sub TO_JSON { return { %{ shift() } }; }

sub usage {
  print "api2html.pl >>> create an HTML API documentation file from a REST API\n";
  print "api2html.pl -url <url to api> -site_name <name of site> -outfile <file for html output>\n";
}

# read in parameters
my $url       = '';
my $site_name = '';
my $outfile   = '';

GetOptions ( 'url=s' => \$url,
             'site_name=s' => \$site_name,
	     'outfile=s' => \$outfile );

unless ($url and $site_name and $outfile) {
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

# start the template
my $html = template_start($site_name);

# build the navigation
$html .= '<li><a href="#overview">overview</a></li>';
foreach my $res (sort { $a->{name} cmp $b->{name} } @{$structure->{resources}}) {
  $html .= '<li><a href="#'.$res->{name}.'">'.$res->{name}.'</a></li>';
}
$html .= qq~</ul>	
    </div>
    <div class="span12" style="margin-left: 270px;">
~;

$html .= "<h1><a name='overview' style='padding-top: 50px;'>".$site_name." Overview</a></h1><p>".$structure->{service}->{description}."</p><hr>";

my %param_types = ( body => "<p>This parameter must be passed in the message body.</p>",
                    options => "<p>This is an optional parameter and may be passed in the query string.</p>",
                    required => "<p>This is a required parameter and must be passed as a REST parameter.</p>" );

# iterate over the resources
foreach my $res (sort { $a->{name} cmp $b->{name} } @{$structure->{resources}}) {
    print $res->{name}."\n";
    $html .= "<h1><a name='".$res->{name}."' style='padding-top: 50px;'>".$res->{name}."</a></h1><h2>Description</h2><p>".$res->{description}."</p>";
    foreach my $req (@{$res->{requests}}) {
        print "\t".$req->{name}."\n";
        $html .= "<h2>".$req->{name}." - request</h2><h3>Description</h3><p>".$req->{description}."</p><p>This is a ".$req->{type}." ".$req->{method}." request.";
        unless (ref($req->{attributes})) {
            $html .= " This request has no parameters.";
            next;
        }
        $html .= "</p><h3>Parameters</h3><ul>";
        # iterate over paramaters
        foreach my $ptype (sort keys %param_types) {
            foreach my $param (sort keys(%{$req->{parameters}->{$ptype}})) {
                my $pm = $req->{parameters}->{$ptype}->{$param};
                $pm->[0] =~ s/cv/controlled vocabulary/;
                $html .= "<li><b>$param</b> (".$pm->[0];
                if (ref($pm->[1]) eq 'ARRAY') {
	                if (! ref($pm->[0]) && $pm->[0] eq 'list') {
	                    $html .= " of ".$pm->[1]->[0].")</li><p>";
	                    $html .= $pm->[1]->[1]."</p>";
	                } else {
	                    $html .= ")</li><p>";
	                    $html .= "This parameter value can be chosen from the following (the first being default):</p><ul style='list-style: none;'>";
	                    foreach my $cvitem (@{$pm->[1]}) {
	                        $html .= "<li><b>".$cvitem->[0]."</b> - ".$cvitem->[1]."</li>";
	                    }
	                    $html .= "</ul><br>";
	                }
                } else {
	                $html .= ")</p><p>".$pm->[1]."</p>";
                }
                $html .= $param_types{$ptype};
            }
        }
        $html .= "</ul>";
        if (exists $req->{example}) {
            $html .= "<h3>Example</h3><ul>";
            $html .= "<li>".$req->{example}[0]."<li>".$req->{example}[1]."</ul>";
        }
        $html .= "<h3>Return Attributes</h3><ul>";
        # iterate over attributes
        foreach my $param (sort keys(%{$req->{attributes}})) {
            my ($att_obj, $att_hash);
            my $att = $param;
            my $att_type = $req->{attributes}->{$param}->[0];
            my $att_desc = $req->{attributes}->{$param}->[1];
            if ($att_type eq 'cv') {
                $html .= "<li><b>$att</b> (controlled vocabulary)</li><p>";
                $html .= "This parameter value can be chosen from the following (the first being default):</p><ul style='list-style: none;'>";
                foreach my $cvitem (@$att_desc) {
                    $html .= "<li><b>".$cvitem->[0]."</b> - ".$cvitem->[1]."</li>";
                }
                $html .= "</ul><br>";
            } else {
                while (ref($att_desc) eq 'ARRAY') {
                    if ($att_type =~ /object/) {
                        $att_obj = $att_desc->[0];
                    } elsif (($att_type =~ /hash/) && ref($att_desc) eq 'ARRAY') {
                        $att_hash = $att_desc->[0];
                    } else {
                        $att_type .= " of ".$att_desc->[0]."s";
                    }
                    $att_desc = $att_desc->[1];
                }
                $html .= "<li><b>$att</b> ($att_type)</li><p>";
                if ($att_obj) {
	                $html .= "This attribute has an object structure:</p><ul style='list-style: none;'>";
	                foreach my $key (sort keys(%$att_obj)) {
	                    my $obj_type = $att_obj->{$key}->[0];
	                    my $obj_att = $att_obj->{$key}->[1];
	                    while (ref($obj_att) eq 'ARRAY') {
	                        $obj_type .= " of ".$obj_att->[0]."s";
	                        $obj_att = $obj_att->[1];
	                    }
	                    $html .= "<li><b>$key ($obj_type)</b> - ".$obj_att."</li>";
	                }
	                $html .= "</ul><br>";
                } elsif ($att_hash) {
                    $html .= "This attribute has a hash structure:</p><ul style='list-style: none;'>";
	                foreach my $key (('key', 'value')) {
	                    my $hash_type = $att_hash->{$key}->[0];
	                    my $hash_att = $att_hash->{$key}->[1];
	                    while (ref($hash_att) eq 'ARRAY') {
	                        $hash_type .= " of ".$hash_att->[0]."s";
	                        $hash_att = $hash_att->[1];
	                    }
	                    $html .= "<li><b>$key ($hash_type)</b> - ".$hash_att."</li>";
	                }
	                $html .= "</ul><br>";
                } else {
	                $html .= $att_desc."</p>"
                }
            }
        }
        $html .= "</p></ul>";
    }
    $html .= "<hr>";
}

$html .= template_end();

# print result to file
if (open(FH, ">$outfile")) {
  print FH $html;
  close FH;
} else {
  die "could not open outfile for writing ($outfile): $@";
}

print "\nall done.\n\nHave a nice day :)\n\n";

exit;

sub template_start {
  my $site_name = shift;
  return qq~
<!DOCTYPE html>
<html>
  <head>
    <title>$site_name API</title>
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <script type="text/javascript" src="bootstrap.min.js"></script>
    <link rel="stylesheet" type="text/css" href="bootstrap.min.css" />
  </head>

  <body style="background-color: white; margin: 15px;">
    <div class="navbar navbar-inverse navbar-fixed-top">
      <div class="navbar-inner">
	<div class="container">
	  <a class="brand" href="./index.html">$site_name API documentation</a>
	</div>
      </div>
    </div>

    <div class="row" style="margin-top: 50px;">
      <div name="index" class="span3" style="position: fixed; width: 130px;">
	<ul class="nav nav-list">
	  <li class="nav-header">Resources</li>
~;
}

sub template_end {
  return qq~
</ul>
    </div>
  </body>

</html>
~;
}
