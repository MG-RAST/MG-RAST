#!/usr/bin/env perl

opendir(DIR, ".") || die "can't opendir: $!";
@imgs = grep { /^map\d+\.gif$/ } readdir(DIR);
closedir DIR;
foreach my $img (@imgs) {
  my ($prefix) = $img =~ /(map\d+)/;
  `convert -transparent white $img $prefix.png`;
}
