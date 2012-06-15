use Data::Dumper;
use Carp;
use Config;

use FIG;
my $fig = new FIG;

my $old  = shift @ARGV;
my $dest = shift @ARGV || ".";

unless (-f $old) {
    print STDERR "No file $old!";
    exit;
}


$/ = "\n//\n";
open(NEW,">$dest/Comment_on_sequence_function") || die "bad";
foreach $_ (`cat $old`)
{
    if ($_ =~ /^(\S+)\t[^\t]+\t([^\n]+)\n(.*)/s)
    {
	$peg = $1;
	$who = $2;
	$txt = $3;
	$ts  = time;
	$md5 = $fig->md5_of_peg($peg) || '';
	print NEW "$peg\t$who\t$ts\t$md5\n$txt";
	print     "$peg\t$who\t$ts\t$md5\n$txt";
    }
}
