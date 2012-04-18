use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;

use Babel::lib::M5NR;

my $verbose = 0;
my $sim     = '';
my $id      = '';
my $md5     = '';
my $seq     = '';
my $source  = '';
my $option  = '';
my $help    = 0 ;
my $options = {sequence => 1, annotation => 1};

GetOptions( "verbose!"   => \$verbose,
	    "sim=s"      => \$sim,
	    "id=s"       => \$id,
	    "md5=s"      => \$md5,
            "sequence=s" => \$seq,
	    "source=s"   => \$source,
	    "option=s"   => \$option,
	    "help!"      => \$help
 	  );

my $m5nr = new M5NR;
unless ($m5nr->dbh) {
  print STDERR "Unable to retrieve the M5NR database.\n";
  exit 1;
}

my $srcs = $m5nr->sources;
my %smap = map { $_, 1 } grep { $srcs->{$_}{type} ne 'rna' } keys %$srcs;

if ($help or ! ($options->{$option} or $seq)) {
  &help($options, \%smap);
  exit 1;
}

my $hdr = ["ID", "MD5", "Function", "Organism"];
if ($source) {
  push @$hdr, "Source";
  unless (exists $smap{$source}) {
    &help($options, \%smap);
    exit 1;
  }
}

if ($sim) {
  unless ((-s $sim) && $source) {
    &help($options, \%smap);
    exit 1;
  }
  my ($total, $count) = &process_sims($sim, $source);
  print STDERR "$count out of $total similarities annotated\n";
}
elsif ($seq) {
  &output( [[$m5nr->sequence2md5($seq)]] );
}
elsif ($md5 && ($option eq 'sequence')) {
  my $md5s = &list_from_input($md5);
  &output( [[$m5nr->md5s2sequences($md5s)]] );
}
elsif ($md5 && ($option eq 'annotation')) {
  my $md5s = &list_from_input($md5);
  if ($source) {
    &output($hdr, $m5nr->md5s2sets4source($md5s, $source));
  } else {
    &output($hdr, $m5nr->md5s2sets($md5s));
  }
}
elsif($id && ($option eq 'sequence')) {
  my $ids = &list_from_input($id);
  &output( [[$m5nr->ids2sequences($ids)]] );
}
elsif($id && ($option eq 'annotation')) {
  my %ids  = map {$_, 1} @{ &list_from_input($id) };
  my %md5s = map {$_->[0], 1} @{ $m5nr->ids2md5s([keys %ids]) };
  my @data = ();
  if ($source) {
    @data = grep {exists $ids{$_->[0]}} @{ $m5nr->md5s2sets4source([keys %md5s], $source) };
  } else {
    @data = grep {exists $ids{$_->[0]}} @{ $m5nr->md5s2sets([keys %md5s]) };
  }
  &output($hdr, \@data);
}
else {
  &help($options, \%smap);
  exit 1;
}

sub list_from_input {
  my ($input) = @_;

  my @list = ();
  if (-s $input) {
    @list = `cat $input`;
    chomp @list;
  }
  else {
    @list = split(/,/, $input);
  }
  my %set = map {$_, 1} @list;

  return [keys %set];
}

sub output {
  my ($hdr, $rows) = @_;

  if ($hdr && @$hdr) {
    print join("\t", @$hdr) . "\n";
  }
  foreach my $row (@$rows) {
    print join("\t", @$row) . "\n";
  }
}

sub process_sims {
  my ($m5nr, $file, $source) = @_;

  my $data  = {};
  my $frags = 0;
  my $total = 0;
  my $count = 0;
  my $curr  = '';

  open(INFILE, "<$file") or die "Can't open file $file!\n";
  while (my $line = <INFILE>) {
    chomp $line;
    my ($frag, $md5, @rest) = split(/\t/, $line);

    if ((! $frag) || (! $line)) { next; }
    if ($curr ne $frag) {
      if ($frags >= 5000) {
	my ($text, $num) = &annotate_hits($data, $source, $m5nr->dbh);
	print STDOUT $text;
	$data  = {};
	$frags = 0;
	$count += $num;
      }
      $curr = $frag;
      $frags += 1;
    }
    $md5 =~ s/lcl\|//;
    if (! exists $data->{$frag}{$md5}) {
      # only keep top hit for each md5
      $data->{$frag}{$md5} = \@rest;
    }
    $total += 1;
  }
  close INFILE;

  return ($total, $count);
}

sub annotate_hits {
  my ($data, $source, $dbh) = @_;

  my $total_md5s = {};
  foreach my $frag (keys %$data) {
    foreach my $md5 (keys %{$data->{$frag}}) {
      $total_md5s->{$md5} = 1;
    }
  }
  unless (scalar(keys %$total_md5s) > 0) { return; }

  my $sql = "select p.md5, f.name, o.name from md5_protein p, functions f, organisms_ncbi o, sources s where p.function = f._id and p.organism = o._id and p.source = s._id and s.name='$source' and p.md5 in (" . join(",", map {"'$_'"} keys %$total_md5s) . ")";
  my $rows = $dbh->selectall_arrayref($sql);
  
  my $md5_prots = {};
  if ($rows && @$rows) {
    foreach my $row (@$rows) {
      $md5_prots->{$row->[0]}{$row->[1]}{$row->[2]} = 1;
    }
  }

  my $count = 0;
  my $text  = "";
  my ($frag, $md5, $org, $func, $top);
  foreach $frag ( keys %$data ) {
    foreach $md5 ( keys %{$data->{$frag}} ) {
      # top: identity, length, mismatch, gaps, q_start, q_end, s_start, s_end, evalue, bit_score
      $top = $data->{$frag}{$md5};
      foreach $func ( keys %{$md5_prots->{$md5}} ) {
	foreach $org ( keys %{$md5_prots->{$md5}{$func}} ) {
	  $text .= join("\t", ($md5, $frag, $top->[0], $top->[1], $top->[8], $func, $org)) . "\n";
	  $count += 1;
	}
      }
    }
  }

  return ($text, $count);
}

sub help {
    my ($options, $smap) = @_ ;

    my $opts = join(", ", keys %$options);
    my $srcs = join(", ", sort keys %$smap);

    print STDERR qq(Usage: $0
  --sim       <similarity file>  file in blast m8 format to be annotated
  --id        <protein ids>      file or comma seperated list of protein ids
  --md5       <md5sums>          file or comma seperated list of md5sums
  --sequence  <aa sequence>      protein sequence, returns md5sum of sequence
  --source    <source name>      source for annotation, default is all
  --option    <output option>    output type, one of: $opts
  --verbose                      verbose output
  --help                         show this

  Sources: $srcs
);
}
