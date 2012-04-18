package MGRAST::WebPage::MetagenomeBlastRun;

use base qw( WebPage );

1;


use strict;
use warnings;

use FIG;
use FIGV;

use base qw( WebComponent );

use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset is_public_metagenome );


=pod

=head1 NAME

MetagenomeBlastRun - an instance of WebPage which lets the user run a BLAST job.

=head1 DESCRIPTION

When called with no arguments, the page displays an input form (from the 
WebComponent 'BlastForm.pm') where the user can input a sequence and select
an organism and BLAST parameters.

Submitting the form will run the BLAST job and the output gets displayed.

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
    my ($self) = @_;
    
    $self->application->no_bot(1);

    return 1;
}

=item * B<output> ()

Returns the html output of the Blast page.

=cut

sub output {
    my ($self) = @_;

    # fetch application, cgi and fig
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');

    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }
    $self->fig($fig);

    # get the metagenome id
    my $metagenome_id = $self->application->cgi->param('metagenome') || '';

    # sanity check on job
    if ( $metagenome_id ) { 
	my $job;
	eval { $job = $self->app->data_handle('MGRAST')->Job->init({ genome_id => $metagenome_id }); };
	unless ($job) {
	    $self->app->error("Unable to retrieve the job for metagenome '$metagenome_id'.");
	    return 1;
	}
	$self->data('job', $job);
    } else {
	$self->app->error("No metagenome specified.");
	return 1;
    }

    # set up the menu
    &get_menu_metagenome($self->application->menu, $metagenome_id, $self->application->session->user);
    
    my $job = $self->data('job');

    my $html = '';
    my $act  = $cgi->param('act') || 'blast_form';
    
    if ( $act eq 'blast_form' )
    {
	$html = $self->blast_form();
    }
    elsif ( $act eq 'BLAST' )
    {
	$html = $self->run_blast();
    }

    return $html;
}

sub run_blast {
    my($self) = @_;

    # set title
    $self->title('BLAST results');

    my $job = $self->data('job');

    # get the metagenome name and id
    my $metagenome_name = $job->{'genome_name'};
    my $metagenome_id   = $job->{'genome_id'};

    # start building html
    my $output = "<span style='font-size: 1.6em'><b>BLAST against $metagenome_name ($metagenome_id)</b></span>\n";
    
    # get cgi input parameters
    my $cgi       = $self->application->cgi();
    my $fasta     = $cgi->param('fasta');
    my $seq_type  = $cgi->param('seq_type') || '';
    my $cutoff    = $cgi->param('evalue')   || 10;
    my $word_size = $cgi->param('wsize')    || 0;   # word size == 0 for default values
    my $filter    = $cgi->param('filter')   || 'F';

    # parse input -- may be fasta formatted or raw sequence
    my($seq_id, $seq) = $self->parse_fasta($fasta);

    # if user did not select a sequence type, or entered something other than nuc or aa
    if ( $seq_type ne 'nuc' and $seq_type ne 'aa' ) {
	$seq_type = ($seq =~ /^[acgtu]+$/i)? 'nuc' : 'aa';
    }

    # do some checks on input -- these arguments are going on the command line!
    if ( my $message = $self->check_input($seq_type, $metagenome_id, $word_size, $cutoff, $filter) )
    {
	return "<h2>$message</h2>";
    }

    my $fig     = $self->fig();

    my $db_path = $job->directory . "/rp/$metagenome_id";
    my $db_file = 'contigs';

    # check that database sequence file is found
    if ( ! (-d $db_path and -e "$db_path/$db_file") ) {
      print STDERR "Could not find file '$db_path/$db_file' to blast against\n";
      return "An error occurred while trying to blast against the metagenome: $metagenome_name ($metagenome_id)";
    }
    
    # having trouble with formatdb -- not permitted to run formatdb for SEED organisms
    # run formatdb if necessary
    $self->run_formatdb_if_needed($db_path, $db_file, $metagenome_name);
    
    # print input sequence to a temporary file
    my $query_file = "$FIG_Config::temp/tmp.$$.fasta";
    $self->print_fasta($seq_id, $seq, $query_file);

    # assemble blastall command
    my $cmd  = "$FIG_Config::ext_bin/blastall";
    my @args = ('-i', $query_file, '-d', "$db_path/$db_file", '-T', 'T', '-F', $filter, '-e', $cutoff, '-W', $word_size);
    push @args, ($seq_type eq 'nuc')? ('-p',  'blastn') : ('-p', 'tblastn');

    # run blast
    my $blast_output = $fig->run_gathering_output($cmd, @args);
    $output .= $self->add_links($metagenome_id, $blast_output);

    return $output;
}

sub add_links {
    my($self, $metagenome_id, $output) = @_;

    my @lines = split(/\n/, $output);
    foreach my $line ( @lines ) {
	if ( $line =~ /(\S+)(\s+<a href\s*=\s*\#\d+>)/ ) {
	    my $seq_id = $1;
	    my $seq_link = qq(<a href="?page=MetagenomeSequence&metagenome=$metagenome_id&sequence=$seq_id" target=_blank>$seq_id<\/a>);
	    $line =~ s/$1/$seq_link/;
	}
    }

    return join("\n", @lines);
}

sub print_fasta {
    my($self, $id, $seq, $fasta_file) = @_;
    # output fasta-formatted user input sequence to a temporary file

    open(TMP, ">$fasta_file") or die "could not open file '$fasta_file': $!";
    my $fig = $self->fig();
    FIG::display_id_and_seq($id, \$seq, \*TMP);
    close(TMP) or die "could not close file '$fasta_file': $!";
}    

sub run_formatdb_if_needed {
    my($self, $db_path, $db_file, $metagenome_name) = @_;
    # run formatdb if it is needed

    if ( $self->formatdb_needed($db_path, $db_file) )
    {
	my $cmd = "$FIG_Config::ext_bin/formatdb -i $db_path/$db_file -n $db_path/$db_file -p F -t '$metagenome_name' -l $db_path/formatdb.log";
	my $fig = $self->fig();
	$fig->run($cmd);
    }
}

sub formatdb_needed {
    my($self, $db_path, $db_file) = @_;
    # run formatdb if the db files are missing or older than the sequence file

    my $db_age   = -M "$db_path/$db_file";
    my @suffixes = ('nhr', 'nin', 'nsq');

    foreach my $suffix ( @suffixes )
    {
	my $fdb_file = "$db_path/$db_file" . '.' . $suffix;
	if ( (not -s $fdb_file) or ((-M $fdb_file) > $db_age) )
	{
	    return 1;
	}
    }

    return 0;
}

sub parse_fasta {
    my($self, $fasta) = @_;
    my($id, $seq);
    # input may be fasta-formatted or a raw sequence

    if ( $fasta =~ /^>/ )
    {
	my($id_line, @seq) = split(/\n/, $fasta);
	($id) = ($id_line =~ /^>(\S+)\s*\r*/);
	$seq  = join('', map {$_ =~ s/\r//; $_} @seq);
    }
    else
    {
	# not fasta format, raw sequence
	$id  =  'User_input_sequence';
	$seq =  $fasta;
	$seq =~ s/(\r\n|\n|\r)//g;
    }

    return ($id, $seq);
}

sub blast_form {
    my($self) = @_;
    # display BLAST input form

    my $application = $self->application();
    my $cgi = $application->cgi;
    my $job = $self->data('job');

    # get the metagenome name and id
    my $metagenome_name = $job->{'genome_name'};
    my $metagenome_id   = $job->{'genome_id'};

    # set title
    $self->title('BLAST input form');

    # create form for entering sequence
    # start building html
    my $html = "<span style='font-size: 1.6em'><b>BLAST against $metagenome_name ($metagenome_id)</b></span>\n";
    $html .= "<p style='width:800px;'>To BLAST against $metagenome_name, paste in your sequence below. \n";
    $html .= "Select whether you are pasting in nucleotides or amino acids and then press the button labeled <b>BLAST</b>.</p>\n";
    $html .= "<div style='padding-left: 10px;'>\n";
    $html .= $self->application->page->start_form( 'blast_form', { 'page' => 'MetagenomeBlastRun' } );
    $html .= "Sequence: <input type='radio' name='seq_type' value='nuc'>&nbsp;nucleotide&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input type='radio' name='seq_type' value='aa'>&nbsp;amino acid<br>\n";
    $html .= "<textarea style='width: 550px;height: 150px;' name='fasta'></textarea><br/>\n";
    $html .= "<input type='hidden' name='metagenome' value='$metagenome_id'>\n";
    $html .= "<br>" . $self->button('BLAST', name => 'act') . "&nbsp;&nbsp;&nbsp;<input type='reset' value='Clear'><p>&nbsp;<p>\n";
    $html .= $self->application->page->end_form();
    $html .= "</div>\n";    

    return $html;
}  

sub check_input {
    my($self, $seq_type, $metagenome_id, $word_size, $cutoff, $filter) = @_;

    # strip pre and post spaces from values coming from text boxes
    $word_size =~ s/^\s+//;
    $word_size =~ s/\s+$//;
    $cutoff    =~ s/^\s+//;
    $cutoff    =~ s/\s+$//;
    
    ($word_size eq '') && ($word_size = 0);

    ($metagenome_id =~ /^\d+\.\d+$/) or (return "Improper genome id");
    ($word_size     =~ /^\d+$/)      or (return "Improper word size");
    ($filter        =~ /^(F|T)$/)    or (return "Improper filter");
    ($cutoff        =~ /^([+]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) or (return "Improper cutoff");

    if ( $word_size != 0 )
    {
	if ( $seq_type eq 'nuc' )
	{
	    ($word_size < 4) or (return "Word size too small, should be 0 for the default (11) or else greater than 4 for nucleotide sequences");
	}
	elsif ( $seq_type eq 'aa' )
	{
	    ($word_size > 5) or (return "Word size too large, should be 0 for the default (3) or else between 1 and 5 for amino acid sequences");
	}
	else
	{
	    return 'Improper sequence type';
	}
    }

    return '';
}

sub fig {
    my($self, $fig) = @_;

    if ( defined($fig) )
    {
	$self->{fig} = $fig;
    } 

    return $self->{fig};
}
