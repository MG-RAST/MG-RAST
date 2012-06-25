package MGRAST::WebPage::ToolResult;

use strict;
use warnings;

use base qw( WebPage );
use Data::Dumper;
use FIG;
use HTML;
use Observation qw(get_objects);

use URI::Escape;


1;

sub output {
    my ($self) = @_;

    $self->application->no_bot(1);

    my $content;
    my $application = $self->application();
    my $cgi = $application->cgi;
    my $state;
    if (defined($cgi->param('peg1'))) {
      $cgi->param('feature', $cgi->param('peg1'));
    }
    if (defined($cgi->param('peg'))) {
      $cgi->param('feature', $cgi->param('peg'));
    }
    my $fig = $application->data_handle('FIG');
    my $result;
    $self->title('Tool Result');

    if($cgi->param('tool') eq "bl2seq"){
        my $peg1 = $cgi->param('peg1');
	my $peg2 = $cgi->param('peg2');
        my $job_id1 = time() - 1;
        my $temp_file1 = "$Conf::temp/$job_id1.seq1.fasta";
	my $temp_file2 = "$Conf::temp/$job_id1.seq2.fasta";
	my $temp_out = "$Conf::temp/$job_id1.out";
        open(OUT,">$temp_file1");
	my $seq = $fig->get_translation($peg1);
	print OUT ">$peg1\n$seq\n";
	close OUT;

	open(OUT,">$temp_file2");
	$seq = $fig->get_translation($peg2);
	print OUT ">$peg2\n$seq\n";
        close OUT;

	system("$Conf::ext_bin/bl2seq -p blastp -i $temp_file1 -j $temp_file2 > $temp_out");
	open (FH, $temp_out);
	while (my $line = <FH>){
	    if ($line =~ /Expect =/){
		my ($garbage) = $line =~ /(Expect .*)/;
		$line =~ s/$garbage//ig;
	    }
	    $result .= $line;
	}
	$content .= qq(<p><b><u>Blast Alignment - bl2seq</u></b></p>);
	$content .= "<pre>$result</pre>";
	return ($content);
    }
    elsif ($cgi->param('tool') eq "bl2seqx"){
        my $peg = $cgi->param('peg');
	my $seq_id = $cgi->param('seq_id');
	my $seq = $cgi->param('seq');
        my $job_id1 = time() - 1;
        my $temp_file1 = "$Conf::temp/$job_id1.seq1.fasta";
	my $temp_file2 = "$Conf::temp/$job_id1.seq2.fasta";
	my $temp_out = "$Conf::temp/$job_id1.out";

	open(OUT,">$temp_file1");
	print OUT ">$seq_id\n$seq\n";
        close OUT;

        open(OUT,">$temp_file2");
	my $pegseq = $fig->get_translation($peg);
	print OUT ">$peg\n$pegseq\n";
	close OUT;

	system("$Conf::ext_bin/bl2seq -p blastx -i $temp_file1 -j $temp_file2 > $temp_out");
	open (FH, $temp_out);
	while (my $line = <FH>){
	    if ($line =~ /Expect =/){
		my ($garbage) = $line =~ /(Expect .*)/;
		$line =~ s/$garbage//ig;
	    }
	    $result .= $line;
	}
	$content .= qq(<p><b><u>Blast Alignment - bl2seqx</u></b></p>);
	$content .= "<pre>$result</pre>";
	return ($content);
    }
}
