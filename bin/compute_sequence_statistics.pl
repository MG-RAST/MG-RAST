#!/soft/packages/perl/5.12.1/bin/perl
use warnings;
use strict;

use Getopt::Long;

my ($file, $dir, $file_format);

GetOptions( 'file=s' => \$file,
	    'dir=s' => \$dir,
	    'file_format=s' => \$file_format );

### report keys:
# bp_count, sequence_count, length_max, id_length_max, length_min, id_length_min, file_size,
# average_length, standard_deviation_length, average_gc_content, standard_deviation_gc_content,
# average_gc_ratio, standard_deviation_gc_ratio, ambig_char_count, ambig_sequence_count, average_ambig_chars

my $filetype = "";
if ($file_format eq 'fastq') {
  $filetype = " -t fastq"
}

my @stats = `seq_length_stats.py -i '$dir/$file'$filetype -s`;
chomp @stats;

my $report = {};
foreach my $stat (@stats) {
  my ($key, $value) = split(/\t/, $stat);
  $report->{$key} = $value;
}
my $header = `head -1 '$dir/$file'`;
my $options = '-s '.$report->{sequence_count}.' -a '.$report->{average_length}.' -d '.$report->{standard_deviation_length}.' -m '.$report->{length_max};
my $method = `tech_guess -f '$header' $options`;

my $success = 1;
my $message = "";
if ( $stats[0] =~ /^ERROR/i ) {
  $success = 0;
  my @parts = split(/\t/, $stats[0]);
  if ( @parts == 3 ) {
    $message = $parts[1] . ": " . $parts[2];
  } else {
    $message = join(" ", @stats);
  }
}

# count unique ids
my $unique_ids = 0;
if ($file_format eq 'fasta') {
  $unique_ids = `grep '>' $dir/$file | cut -f1 -d' ' | sort -T $dir/.tmp -u | wc -l`;
  chomp $unique_ids;
}
elsif ($file_format eq 'fastq') {
  $unique_ids = `awk '0 == (NR + 3) % 4' $dir/$file | cut -f1 -d' ' | sort -T $dir/.tmp -u | wc -l`;
  chomp $unique_ids;
}

push(@stats, "unique_id_count\t$unique_ids");

# write results
open(FH, ">>$dir/$file.stats_info") or die "could not open stats file for $dir/$file.stats_info: $!";
if ($success) {
  if ($report->{sequence_count} eq "0") {
    print FH "Error\tFile contains no sequences\n";
    return 0;
  }
  foreach my $line (@stats) {
    print FH $line."\n";		
  }
  print FH "sequencing_method_guess\t$method";
} else {
  print FH "Error\t$message\n";
}
close FH;
