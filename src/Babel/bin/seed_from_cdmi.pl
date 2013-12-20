#!/usr/bin/env perl

use strict;
use warnings;

use LWP::UserAgent;
use JSON;
use Data::Dumper;

# initialize json, the user agent and the cdmi url
my $json = new JSON;
my $ua = LWP::UserAgent->new;
my $cdmi_url = "https://www.kbase.us/services/cdmi_api";

# get all subsystem names / ids (which is the same thing)
print "retrieving subsystem names...\n";
print "checking for file...\n";
my $subsystems = [];
if (-f "ssnames") {
  open(FH, "<ssnames") or die "error opening existing subsystem names file: $@\n";
  my $data;
  while (<FH>) {
    chomp;
    push(@$subsystems, $_);
  }
  close FH;
  print scalar(@$subsystems)." subsystem names loaded.\n";
} else {
  print "no file, getting from server...\n";
  my $get_subsystems = get([ 0, 1000000, ["id"] ], "all_entities", "Subsystem");
  @$subsystems = keys(%{$get_subsystems->[0]});
  open(FH, ">ssnames") or die "error opening subsystem names file for writing: $@\n";
  foreach my $sn (@$subsystems) {
    print FH "$sn\n";
  }
  close FH;
  print "received ".scalar(@$subsystems)." names.\n";
}

# get the superclass for each subsystem
print "retrieving subsystem classifications...\n";
print "checking for file...\n";
my $s2c = {};
if (-f "ssclass") {
  open(FH, "<ssclass") or die "error opening subsystem classification file: $@\n";
  my $count = 0;
  while (<FH>) {
    chomp;
    $count++;
    my ($k, $v1, $v2) = split /\t/;
    $k =~ s/_/ /g;
    $s2c->{$k} = [ $v1, $v2 ];
  }
  close FH;
  print "loaded $count classifications.\n";
} else {
  print "no file, getting from server...\n";
my $sub2class = get([ $subsystems, [ "id" ], [], [ "id" ] ], "get_relationship", "IsInClass");
  @$sub2class = $sub2class->[0];
  
  # parse the superclass-subsystem mapping data into a hash
  open(FH, ">ssclass") or die "could not open subsystem class file for writing: $@\n";
  my $count = 0;
  foreach my $item (@$sub2class) {
     foreach my $subitem (@$item) {
       $count ++;
       $s2c->{$subitem->[0]->{id}} = $subitem->[2]->{id};
       print FH $subitem->[0]->{id} ."\t". $subitem->[2]->{id} . "\n";
     }
   }
   close FH;

   print "received $count classifications.\n";}

# get all roles that are in a subsystem
print "retrieving roles...\n";
print "checking for file...\n";
my $roles = [];
my $role2ssname = {};
if (-f "roles") {
  open(FH, "<roles") or die "error opening roles file: $@\n";
  while (<FH>) {
    chomp;
    my ($r, $c) = split /\t/;
    push(@$roles, $r);
    $role2ssname->{$r} = $c;
  }
  close FH;
  print scalar(@$roles)." roles loaded.\n";
} else {
  print "no file, getting from server...\n";
  $roles = get([ $subsystems, [ "id" ], [], [ "id" ] ], "get_relationship", "Includes");
  $roles = $roles->[0];
  foreach my $role (@$roles) {
    $role2ssname->{$role->[2]->{id}} = $role->[0]->{id};
  }
  @$roles = sort(keys(%$role2ssname));
  open(FH, ">roles") or die "could not open roles file for writing: $@\n";
  foreach my $r (sort(keys(%$role2ssname))) {
    print FH $r."\t".$role2ssname->{$r}."\n";
  }
  close FH;
  print "received ".scalar(@$roles)." roles.\n";
}

# purge subsytems variable from memory
$subsystems = undef;

# create the id2subsystem table
print "checking for id2subsystems file...\n";
my $role2ss = {};
if (-f "id2subsystems") {
  print "found. Loading role to subsystem mapping...\n";
  open(FH, "<role2ss") or die "could not open role to subsystems mapping file: $@\n";
  while (<FH>) {
    chomp;
    my ($k, $v) = split /\t/;
    $role2ss->{$k} = $v;
  }
  close FH;  
} else {
  print "not found, calculating...\n";
  my $subsystem_table = [];
  my $count = 1;
  my $ssid = "SS000000";
  my $lastss = $roles->[0];
  my $ssids = {};
  open(FH, ">role2ss") or die "could not open role to subsystems mapping file: $@\n";
  foreach my $role (@$roles) {
    if ($lastss ne $role) {
      $count++;
      $lastss = $role;
    }
    my $c1 = "unclassified";
    my $c2 = "unclassified";
    if ($s2c->{$role2ssname->{$role}} && $s2c->{$role2ssname->{$role}} ne "NULL") {
      $c1 = $s2c->{$role2ssname->{$role}};
    }
    push(@$subsystem_table, [ $c1, $role2ssname->{$role}, $role, substr($ssid, 0, 7 - length($count)) . $count ]);
    $ssids->{$role2ssname->{$role}} = substr($ssid, 0, 7 - length($count)) . $count;
    $role2ss->{$role} = substr($ssid, 0, 7 - length($count)) . $count;
    print FH $role ."\t". substr($ssid, 0, 7 - length($count)) . $count . "\n";
  }
  close FH;
  
  print "done.\nwriting id2subsystems file...\n";

  # write the id2subsystem table to a file
  if (open(FH, ">id2subsystems")) {
    foreach my $row (@$subsystem_table) {
      print FH join("\t", @$row)."\n";
    }
    close FH;
  } else {
    die "oh noes: $@ $!\n";
  }
}

# purge s2c variable from memory
$s2c = undef;

print "done.\n";

# build feature to role table
print "building role to feature table...\n";
print "checking for file...\n";
my $r2f = {};
unless (-f "r2f") {
  `touch r2f`;
  print "no file, creating...\n";
}

my $comp_roles = `wc -l r2f`;
($comp_roles) = $comp_roles =~ /(\d+)/;
print "existing file contains $comp_roles out of ".scalar(@$roles)." roles.\n";
my $totnum = scalar(@$roles);
my $currnum = $comp_roles;
if ($comp_roles < $totnum) {
  print "file incomplete, continuing at role ".($comp_roles + 1).":\n";
  my @rolechunk = splice @$roles, $comp_roles;
  open(FH, ">>r2f") or die "could not open role to function file for appending: $@\n";
  foreach my $role (@rolechunk) {
    $currnum++;
    print "[ $currnum - $totnum ] ".$role."\n";
    if ($role eq "hypothetical protein") {
      print FH $role."\t\n";
      next;
    }

    my $features = get([ [ $role ], [ "id" ], [], [ "id" ] ], "get_relationship", "IsFunctionalIn");
    $features = $features->[0];
    print FH $role."\t".join("\t", map { $_->[2]->{id} } @$features)."\n";
    
  }
  close FH;
} else {
  print "file complete, loading...\n";
  open(FH, "<r2f") or die "could not open role to feature file: $@\n";
  my $rnum = 0;
  my $fnum = 0;
  while (<FH>) {
    chomp;
    my @row = split /\t/;
    $r2f->{shift @row} = \@row;
    $rnum++;
    $fnum += scalar(@row);
  }
  close FH;
  print "loaded $rnum roles with a total of $fnum features.\n";
}

# purge the roles variable from memory
$roles = undef;

# get the organism names
print "building organism name list...\n";
print "checking file...\n";
my $organisms = {};
if (-f "organisms") {
  open(FH, "organisms") or die "could not open organisms file: $@\n";
  while (<FH>) {
    chomp;
    my ($k, $v) = split /\t/;
    $organisms->{$k} = $v;
  }
  close FH;
  print scalar(keys(%$organisms)) . " organism names loaded.\n";
} else {
  print "no file, getting from server...\n";
  my $orgs = get([ 0, 1000000, ["id","scientific-name"] ], "all_entities", "Genome");
  $orgs = $orgs->[0];
  my $orgnames = {};
  foreach my $key (keys(%$orgs)) {
    $orgnames->{$key} = $orgs->{$key}->{scientific_name};
  }
  foreach my $key (keys(%$r2f)) {
    if (defined($r2f->{$key})) {
      foreach my $f (@{$r2f->{$key}}) {
	my ($id) = $f =~ /^(kb\|g\.\d+)/;
	next unless defined($id);
	$organisms->{$id} = $orgnames->{$id};
      }
    }
  }
  open(FH, ">organisms") or die "could not open organisms file for writing: \n";
  foreach my $key (keys(%$organisms)) {
    print FH $key."\t".$organisms->{$key}."\n";
  }
  close FH;

  print "received ".scalar(keys(%$organisms))." organism names.\n";
}

# build feature per organism list
print "building active features per organism list...\n";
print "checking file...\n";
my $org2feature = {};
if (-f "org2feature") {
  print "found file, loading...\n";
  open(FH, "<org2feature") or die "could not open org2feature file: $@\n";
  my $ocount = 0;
  my $fcount = 0;
  while (<FH>) {
    chomp;
    my @row = split /\t/;
    $org2feature->{shift @row} = \@row;
    $ocount++;
    $fcount += scalar(@row);
  }
  close FH;
  print "read $fcount active features in $ocount organisms\n";
} else {
  print "no file, calculating...\n";
  my $org2featureh = {};
  foreach my $key (keys(%$organisms)) {
    $org2featureh->{$key} = {};
    $org2feature->{$key} = [];
  }
  foreach my $key (keys(%$r2f)) {
    foreach my $f (@{$r2f->{$key}}) {
      my ($oid) = $f =~ /^(kb\|g\.\d+)/;
      next unless defined($oid);
      $org2featureh->{$oid}->{$f} = 1;
    }
  }
  open(FH, ">org2feature") or die "could not open org2feature file for writing: $@\n";
  my $ocount = 0;
  my $fcount = 0;
  foreach my $key (keys(%$org2featureh)) {
    $ocount++;
    my @fs = keys(%{$org2featureh->{$key}});
    $fcount += scalar(@fs);
    $org2feature->{$key} = \@fs;
    print FH $key."\t".join("\t",@fs)."\n";
  }
  close FH;

  print "received $fcount active features in $ocount organisms\n";  
}

# get the sequences
print "building sequence files...\n";
unless (-d "sequences") {
  `mkdir sequences`;
}
foreach my $org (keys(%$org2feature)) {
  my ($oid) = $org =~ /^kb\|g.(\d+)/;
  next unless defined($oid);
  unless (-f "sequences/$oid") {
    print "getting active sequences for ".$organisms->{$org}." ($org)\n";
    my $sequences = get([ $org2feature->{$org}, [ "id" ], [], [ "id", "sequence" ] ], "get_relationship", "Produces");
    $sequences = $sequences->[0];
    open(FH, ">sequences/$oid") or die "could not open sequence file for writing: $@\n";
    foreach my $sequence (@$sequences) {
      print FH $sequence->[0]->{id}."\t".$sequence->[2]->{id}."\t".$sequence->[2]->{sequence}."\n";
    }
    close FH;
    print "received ".scalar(@$sequences)." sequences.\n";
  }
}

# build md52seq
print "checking md5 to sequence file...\n";
if (-f "md52seq") {
  print "already built.\n";
} else {
  print "needs to be built. Loading sequences for ".scalar(keys(%$organisms)) ." active genomes:\n";
  my $md52seq = {};
  my $curr = 1;
  my $tot = scalar(keys(%$organisms));
  foreach my $key (keys(%$organisms)) {
    next unless $key;
    my ($num) = $key =~ /^kb\|g\.(\d+)$/;
    print "[ $curr - $tot ] ".$organisms->{$key}." ($num)\n";
    unless (-f "sequences/$num") {
      print $key." ".$num." ".$organisms->{$key}."\n";
      die;
    }
    $curr++;
    open(FH, "<sequences/$num") or die "could not open sequence file $num: $@\n";    
    while (<FH>) {
      chomp;
      my @row = split /\t/;
      $md52seq->{$row[1]} = $row[2];
    }
    close FH;
    print scalar(keys(%$md52seq))." distinct sequences in memory\n";
  }

  print "sequences loaded, starting file creation...\n";
  open(FH, ">md52seq") or die "could not open md52seq file for writing: $@\n";
  foreach my $key (sort(keys(%$md52seq))) {
    print FH $key."\t".$md52seq->{$key}."\n";
  }
  close FH;
  print "done.\n";
}

# load feature2seq_md5
print "loading feature to sequence id mapping...\n";
my $f2sid = {};
my $curr = 1;
my $tot = scalar(keys(%$organisms));
foreach my $key (keys(%$organisms)) {
  next unless $key;
  my ($num) = $key =~ /^kb\|g\.(\d+)$/;
  print "[ $curr - $tot ] ".$organisms->{$key}." ($num)\n";
  unless (-f "sequences/$num") {
    print $key." ".$num." ".$organisms->{$key}."\n";
    die;
  }
  $curr++;
  open(FH, "<sequences/$num") or die "could not open sequence file $num: $@\n";    
  while (<FH>) {
    chomp;
    my @row = split /\t/;
    $f2sid->{$row[0]} = $row[1];
  }
  close FH;
  print scalar(keys(%$f2sid))." features loaded\n";
}

# build md52id2ontology
# seq md5 | role ss | feature role | 'Subsystem'
print "building md52id2ontology file...\n";
print "checking file...\n";
if (-f "md52id2ontology") {
  print "already built.\n";
} else {
  print "no file, building...\n";
  open(FH, ">md52id2ontology") or die "could not open md52id2ontology file for writing: $@\n";
  my $c = 1;
  my $t = scalar(keys(%$r2f));
  foreach my $role (sort(keys(%$r2f))) {
    my $rows = {};
    foreach my $feature (@{$r2f->{$role}}) {
      if (defined($feature) && defined($role) && defined($f2sid->{$feature}) && defined($role2ss->{$role})) {
	$rows->{$f2sid->{$feature}} = [ $f2sid->{$feature}, $role2ss->{$role}, $role, "Subsystem" ];
      } else {
	print "no sequence available - feature: $feature role: $role\n";
      }
    }
    foreach my $key (sort(keys(%$rows))) {
      print FH join("\t", @{$rows->{$key}})."\n";
    }
    print "[ $c - $t ]\r";
    $c++;
  }
  close FH;
  print "\ndone.\n";
}
$f2sid = undef;

# build md52id2func2org
# seq md5 | feature id | feature role | feature org name | 'SEED'
print "building md52id2func2org file...\n";
print "checking file...\n";
if (-f "md52id2func2org") {
  print "already built.\n";
} else {
  print "no file, building...\n";

  print "calculating feature to role hash\n";
  my $f2r = {};
  foreach my $role (keys(%$r2f)) {
    foreach my $feature (@{$r2f->{$role}}) {
      if (defined($f2r->{$feature})) {
	push(@{$f2r->{$feature}}, $role);
      } else {
	$f2r->{$feature} = [ $role ];
      }
    }
  }
  print "done.\n";
  print "parsing organism sequence files...\n";

  open(FB, ">md52id2func2org") or die "could not open md52id2func2org file for writing: $@\n";
  $curr = 1;
  foreach my $key (keys(%$organisms)) {
    next unless $key;
    my ($num) = $key =~ /^kb\|g\.(\d+)$/;
    print "[ $curr - $tot ] ".$organisms->{$key}." ($num)\n";
    unless (-f "sequences/$num") {
      print $key." ".$num." ".$organisms->{$key}."\n";
      die;
    }
    $curr++;
    open(FH, "<sequences/$num") or die "could not open sequence file $num: $@\n";    
    while (<FH>) {
      chomp;
      my @row = split /\t/;
      my ($o) = $row[0] =~ /^(kb\|g\.\d+)/;
      foreach my $role (@{$f2r->{$row[0]}}) {
	print FB $row[1]."\t".$row[0]."\t".$role."\t".$organisms->{$o}."\tSEED\n";
      }
      $f2sid->{$row[0]} = $row[1];
    }
    close FH;
    print scalar(keys(%$f2sid))." features written\n";
  }
  close FB;
}
print "done.\n";

print "all done.\nHave a nice day :)\n\n";

1;

# function to get data from the CDMI
# setting verbose to true will dump the response to STDERR
sub get {
  my ($params, $entity, $name, $verbose) = @_;

  my $data = { 'params' => $params,
	       'method' => "CDMI_EntityAPI.".$entity."_".$name,
	       'version' => "1.1" };

  my $response = $ua->post($cdmi_url, Content => $json->encode($data))->content;
  eval {
    $response = $json->decode($response);
  };
  if ($@) {
    print STDERR $response."\n";
  }
  if ($verbose) {
    print STDERR Dumper($response)."\n";
  }
  $response = $response->{result};

  return $response;
}
