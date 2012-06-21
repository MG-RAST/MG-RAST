use warnings;
use strict;

use CGI;
use JSON;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use URI::Escape;

use WebApplicationDBHandle;
use DBMaster;
use Conf;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

my ($master, $error) = new WebApplicationDBHandle();
my $user;
my $session = $master->UserSession->get_objects( { session_id => $cgi->param('auth') } );
if (scalar(@$session)) {
    $user = $session->[0]->user;
}

my $seq_ext = "fasta|faa|fa|ffn|frn|fna|fastq|fq";

# if there is no user, abort the request
unless ($user) {
    print "Content-Type: text/plain\n\n";
    print "unauthorized request";
    exit 0;
}

# get the REST parameters
my $abs = $cgi->url(-absolute=>1);
my $rest = $cgi->url(-path_info=>1);
$rest =~ s/^.*$abs\/?//;
my @rest = split m#/#, $rest;
map {$rest[$_] =~ s#forwardslash#/#gi} (0 .. $#rest);

# set the directory
my $base_dir = "$Conf::incoming";
my $udir = $base_dir."/".md5_hex($user->login);

# check if the user directory exists
&initialize_user_dir();

# check if this is a request for the inbox or an upload
if (scalar(@rest) && $rest[0] eq 'user_inbox') {
    
    # prepare return data structure
    my $data = [ { type => 'user_inbox', id => $user->login, files => [], fileinfo => {}, messages => [], directories => [] }];

    # check if the user has stats calculations in the queue
    my $uname = $user->{login};
    my $count = `/usr/local/bin/qstat | grep $uname | wc -l`;
    if ($count && $count > 0) {
	push(@{$data->[0]->{messages}}, "You have $count sequence files with ongoing statistics computation. The information on these files will be incomplete and you will not be able to select these for submisson until the computation is complete. You can reload this page or click the 'update inbox' button to update the status.");
    }

    # check if we are supposed to do anything else than return the content of the inbox
    if ($cgi->param('faction')) {
	my $action = $cgi->param('faction');
	my @files = $cgi->param('fn');

	# delete a list of files
	if ($action eq 'del') {
	    foreach my $file (@files) {
		if (-f "$udir/$file") {		    
		    `rm '$udir/$file'`;
		    if (-f "$udir/$file.stats_info") {
			`rm '$udir/$file.stats_info'`;
		    }
		    
		    # check if the file is in a directory
		    if ($file =~ /\//) {		      
			my ($dn) = $file =~ /^(.*)\//;
			$dn = $udir."/".$dn;

			# if the directory is empty, delete it
			my @fls = <$dn/*>;
			if (! scalar(@fls)) {
			    `rmdir $dn`;
			}
		    }
		}
	    }
	}

	#  move a list of files
	if ($action eq 'move') {
	    my $target_dir = shift(@files);
	    if ($target_dir eq 'inbox') {
		$target_dir = $udir."/";
	    } else {
		unless (-d "$udir/$target_dir") {
		    `mkdir '$udir/$target_dir'`;
		}
		$target_dir = "$udir/$target_dir/";
	    }
	    foreach my $file (@files) {
		`mv $udir/$file $target_dir`;
		if (-f "$udir/$file.stats_info") {
		    `mv $udir/$file.stats_info $target_dir`;
		}
	    }
	}
	
	# decompress a list of files
	if ($action eq 'unpack') {
	    foreach my $file (@files) {
		my @msg;
		if (-f "$udir/$file") {
		    if ($file =~ /\.(tar\.gz|tgz)$/) {
			@msg = `tar -xzf '$udir/$file' -C $udir 2>&1`;
		    } elsif ($file =~ /\.zip$/) {
			@msg = `unzip -d $udir '$udir/$file' 2>&1`;
		    } elsif ($file =~ /\.(tar\.bz2|tbz|tbz2|tb2)$/) {
			@msg = `tar -xjf '$udir/$file' -C $udir 2>&1`;
		    } elsif ($file =~ /\.gz$/) {
			@msg = `gunzip -d '$udir/$file' 2>&1`;
		    } elsif ($file =~ /\.bz2$/) {
			@msg = `bunzip2 -d '$udir/$file' 2>&1`;
		    }
		    
		    push(@{$data->[0]->{messages}}, join("<br>",@msg));
		}
	    }
	}
	
	# convert a list of files from sff to fastq
	if ($action eq 'convert') {
	    foreach my $file (@files) {
		if ($file =~ /\.sff$/) {
		    if (-f "$udir/$file.fastq") {
			push(@{$data->[0]->{messages}}, "The conversion for $file is either already finished or in progress.");
		    } else {
			my ($success, $message) = &extract_fastq_from_sff($file, $udir);
			unless ($success) {
			    push(@{$data->[0]->{messages}}, $message);
			}
		    }
		} else {
		    push(@{$data->[0]->{messages}}, "Unknown filetype for fastq conversion, currently only sff is supported.");
		}
	    }
	}
	
	# demultiplex, there will be one sequence and one barcode file
	if ($action eq 'demultiplex') {
	    my $midfile;
	    my $seqfile;
	    my $filetype;
	    my $has_seqs = 0;
	    if ($files[0] =~ /\.($seq_ext)$/) {
		$filetype = ($1 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile  = $files[0];
		$midfile  = $files[1];
		$has_seqs = 1;
	    } elsif ($files[1] =~ /\.($seq_ext)$/) {
		$filetype = ($1 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile  = $files[1];
		$midfile  = $files[0];
		$has_seqs = 1;
	    }
	    if ($has_seqs) {
		open(MID, "<$udir/$midfile") or die "could not open file '$udir/$midfile': $!";
		my @mid_tags;
		my $tagnames = {};
		my $tag;
		my $tagname;
		while ( defined($tag = <MID>) ) {
		    chomp $tag;
		    if ($tag =~ /\t/) {
			($tag, $tagname) = split(/\t/, $tag);
			$tagnames->{$tag} = $tagname;
		    }
		    push @mid_tags, $tag;
		}
		close(MID);
		
		my $retfiles = [];
		if (my ($bc_length) = $mid_tags[0] =~ /^(\d+)$/) {
		    $retfiles = &split_fasta_by_bc_length($seqfile, $udir, $filetype, $bc_length);
		} else {
		    $retfiles = &split_fasta_by_mid_tag($seqfile, $udir, $filetype, \@mid_tags, $tagnames);
		}
		if (scalar(@$retfiles)) {
		    push(@{$data->[0]->{messages}}, "successfully demultiplexed ".$seqfile." into ".scalar(@$retfiles)." files.");
		} else {
		    push(@{$data->[0]->{messages}}, "There was an error during demultiplexing.");
		}
	    }
	    else {
		push(@{$data->[0]->{messages}}, "Unknown file types for demultiplex, please select one sequence file and one barcode file.");
	    }
	}
    }
    
    # read the contents of the inbox
    my $info_files = {};
    my $sequence_files = [];
    my $indir = {};
    my @ufiles;
    if (opendir(my $dh, $udir)) {
	
	# ignore . files and the USER file
	@ufiles = grep { /^[^\.]/ && $_ ne "USER" } readdir($dh);
	closedir $dh;
	
	# iterate over all entries in the user inbox directory
	foreach my $ufile (@ufiles) {

	    # check for sane filenames
	    if ($ufile !~ /^[\/\w\.\-]+$/) {
		my $newfilename = $ufile;
		$newfilename =~ s/[^\/\w\.\-]+/_/g;
		my $count = 1;
		while (-f "$udir/$newfilename") {
		    if ($count == 1) {
			$newfilename =~ s/^(.*)(\..*)$/$1$count$2/;
		    } else {
			my $oldcount = $count - 1;
			$newfilename =~ s/^(.*)$oldcount(\..*)$/$1$count$2/;
		    }
		    $count++;
		}
		`mv '$udir/$ufile' '$udir/$newfilename'`;
		push(@{$data->[0]->{messages}}, "<br>The file <b>'$ufile'</b> contained invalid characters. It has been renamed to <b>'$newfilename'</b>.");
		$ufile = $newfilename;
	    }
	    
	    # check directories
	    if (-d "$udir/$ufile") {
		opendir(my $dh2, $udir."/".$ufile);
		my @numfiles = grep { /^[^\.]/ && -f $udir."/".$ufile."/".$_ } readdir($dh2);
		closedir $dh2;
		if (scalar(@numfiles)) {
		    push(@{$data->[0]->{directories}}, $ufile);
		    my $dirseqs = [];
		    foreach my $nf (@numfiles) {
			unless ($nf =~ /\.stats_info$/) {
			    push(@$dirseqs, $nf);
			}
			push(@ufiles, "$ufile/$nf");		
		    }
		    $data->[0]->{fileinfo}->{$ufile} = $dirseqs;
		} else {
		    `rmdir $udir/$ufile`;
		}
	    }
	    # check files
	    else {
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat("$udir/$ufile");
		if ($size == 0) {
		    `rm -f "$udir/$ufile"`;
		    next;
		}
		if ($ufile =~ /\.($seq_ext)$/) {
		    push(@$sequence_files, $ufile);
		}
		if ($ufile =~ /^(.+)\.stats_info$/) {
		    my $fn = $1;
		    $info_files->{$fn} = 1;
		    my $info = {};
		    if (open(FH, "<$udir/$ufile")) {
			while (<FH>) {
			    chomp;
			    my ($key, $val) = split /\t/;
			    $key =~ s/_/ /g;
			    $info->{$key} = $val;
			}
			close FH;
		    }
		    if ($info->{'file type'} && $info->{'file type'} eq 'malformed') {
			push(@{$data->[0]->{messages}}, "WARNING: The sequnce file $fn seems to be malformed. You will not be able to submit this file.");
		    }
		    $data->[0]->{fileinfo}->{$fn} = $info;
		} else {
		    unless ($ufile =~ /\//) {
			push(@{$data->[0]->{files}}, $ufile);
		    }
		}
	    }
	}
    }
    
    # iterate over all sequence files found in the inbox
    foreach my $sequence_file (@$sequence_files) {

	# create basic and extended file information if we do not yet have it
	if (! $info_files->{$sequence_file}) {
	    my $file_type     = &file_type($sequence_file, $udir);
	    my $file_eol      = &file_eol($file_type);
	    my ($file_suffix) = $sequence_file =~ /^.*\.(.+)$/;
	    my $file_format   = &file_format($sequence_file, $udir, $file_type, $file_suffix, $file_eol);
	    my $file_seq_type = &file_seq_type($sequence_file, $udir, $file_eol);
	    my ($file_md5)    = (`md5sum '$udir/$sequence_file'` =~ /^(\S+)/);
	    my $file_size     = -s $udir."/".$sequence_file;
	    
	    my $info = { "type" => $file_type,
			 "suffix" => $file_suffix,
			 "file_type" => $file_format,
			 "sequence type" => $file_seq_type,
			 "file_checksum" => $file_md5,
			 "file_size" => $file_size };
	    
	    open(FH, ">$udir/$sequence_file.stats_info");
	    print FH "type\t$file_type\n";
	    print FH "suffix\t$file_suffix\n";
	    print FH "file_type\t$file_format\n";
	    print FH "sequence type\t$file_seq_type\n";
	    print FH "file_checksum\t$file_md5\n";
	    print FH "file_size\t$file_size\n";
	    close(FH);
	    
	    $data->[0]->{fileinfo}->{$sequence_file} = $info;
	    
	    # call the extended information
	    my $compute_script = $Conf::sequence_statistics;
	    my $jobid = $user->{login};
	    my $exec_line = "echo $compute_script -file '$sequence_file' -dir $udir -file_format $file_format | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir";
	    my $jnum = `echo $compute_script -file '$sequence_file' -dir $udir -file_format $file_format | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp`;
	    $jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
	    open(FH, ">>$udir/.tmp/jobs");
	    print FH "$jnum";
	    close FH;
	}
    }

    # add basic file information to all files
    foreach my $file (@ufiles) {
	next unless (-f "$udir/$file");
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat("$udir/$file");
	unless (exists($data->[0]->{fileinfo}->{$file})) {
	    $data->[0]->{fileinfo}->{$file} = {};
	}
	$data->[0]->{fileinfo}->{$file}->{'creation date'} = &pretty_date($ctime);
	$data->[0]->{fileinfo}->{$file}->{'file size'} = &pretty_size($size);
    }
    
    # sort the returned files lexigraphically
    @{$data->[0]->{files}} = sort { lc $a cmp lc $b } @{$data->[0]->{files}};
    
    # return the contents of the inbox
    print $cgi->header('text/plain');
    print "data_return('user_inbox', ".$json->encode( $data ).");";
    exit 0;
}

# If we get here, this is an actual upload
my $filename = $cgi->param('filename');
my $fh = $cgi->upload('upload_file')->handle;
my $bytesread;
my $buffer;

# check if this is the first block, if so, create the file
if (-f "$udir/".$filename && ! -f "$udir/$filename.part") {
    print "Content-Type: text/plain\n\n";
    print "file already exists";
    exit 0;
}
# otherwise, append to the file
else {
    if (open(FH, ">>$udir/".$filename)) {
	while ($bytesread = $fh->read($buffer,1024)) {
	    print FH $buffer;
	}
	close FH;
	`touch $udir/$filename.part`;
    }
}

# return a message to the sender
print "Content-Type: text/plain\n\n";

# if this is the last chunk, remove the partial file
if ($cgi->param('last_chunk')) {
    print "file received";
    `rm $udir/$filename.part`
} else {
    print "chunk received";
}

exit 0;

############################
# start of methods section #
############################

# check if the user directory exists, if not create it
sub initialize_user_dir {
  unless ( -d $udir ) {
    mkdir $udir or die "could not create directory '$udir'";
    chmod 0777, $udir;
  }
  unless ( -d "$udir/.tmp") {
    mkdir "$udir/.tmp" or die "could not create directory '$udir/.tmp'";
    chmod 0777, "$udir/.temp";
  }
  my $user_file = "$udir/USER";
  if ( ! -e $user_file ) {	
    if (open(USER, ">$user_file")) {
      print USER $user->login."\n";
      close(USER) or die "could not close file '$user_file': $!";
      chmod 0666, $user_file;
    } else {
      die "could not open file '$user_file': $!";
    }
  }
}

#############################
# extended file information #
#############################

sub fasta_report_and_stats {
    my($file, $dir, $file_format) = @_;

    ### report keys:
    # bp_count, sequence_count, length_max, id_length_max, length_min, id_length_min, file_size,
    # average_length, standard_deviation_length, average_gc_content, standard_deviation_gc_content,
    # average_gc_ratio, standard_deviation_gc_ratio, ambig_char_count, ambig_sequence_count, average_ambig_chars

    my $filetype = "";
    if ($file_format eq 'fastq') {
	$filetype = " -t fastq"
    }

    my @stats = `$Conf::seq_length_stats -i '$dir/$file'$filetype -s`;
    chomp @stats;

    my $report = {};
    foreach my $stat (@stats) {
	my ($key, $value) = split(/\t/, $stat);
	$report->{$key} = $value;
    }
    my $header = `head -1 '$dir/$file'`;
    my $options = '-s '.$report->{sequence_count}.' -a '.$report->{average_length}.' -d '.$report->{standard_deviation_length}.' -m '.$report->{length_max};
    my $method = `$Conf::tech_guess -f '$header' $options`;

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

    return 0;
}

sub file_unique_id_count {
    my($file_name, $file_path, $file_format) = @_;

    my $unique_ids = 0;
    if (! -d $file_path.'/.sort') {
       mkdir $file_path.'/.sort', 775;
    }
    if ($file_format eq 'fasta') {
       	$unique_ids = `grep '>' $file_path/$file_name | cut -f1 -d' ' | sort -T $file_path/.sort -u | wc -l`;
        chomp $unique_ids;
    }
    elsif ($file_format eq 'fastq') {
        $unique_ids = `awk '0 == (NR + 3) % 4' $file_path/$file_name | cut -f1 -d' ' | sort -T $file_path/.sort -u | wc -l`;
	chomp $unique_ids;
    }
    return $unique_ids;
}

####################################
# basic file information functions #
####################################

sub file_type {
    my($file, $dir) = @_;

    # Need to do the 'safe-open' trick here since for now, file names might
    # be hard to escape in the shell.    
    open(P, "-|", "file", "-b", "$dir/$file") or die("cannot run file command on file '$dir/$file': $!");
    my $file_type = <P>;
    close(P);

    chomp $file_type;

    if ( $file_type =~ m/\S/ ) 
    {
	$file_type =~ s/^\s+//;   #...trim leading whitespace
	$file_type =~ s/\s+$//;   #...trim trailing whitespace
    }
    else
    {
	# file does not work for fastq -- craps out for lines beginning with '@' on mg-rast machine!
	# check first 4 lines for fastq like format

	my @lines = `cat -A '$dir/$file' 2>/dev/null | head -n4`;

	chomp @lines;

	if ( $lines[0] =~ /^\@/  and $lines[0] =~ /\$$/ and
	     $lines[1] =~ /\$$/ and
	     $lines[2] =~ /^\+/  and $lines[2] =~ /\$$/ and
	     $lines[3] =~ /\$$/ )
	{
	    $file_type = 'ASCII text';
	}
	else
	{
	    $file_type = 'unknown file type, check end-of-line characters and (if fastq) fastq formatting';
	}
    }

    return $file_type;
}

sub file_seq_type {
    my($file_name, $file_path, $file_eol) = @_;

    my $max_chars = 10000;

    # read first $max_chars characters of sequence data to check for protein sequences
    # this does NOT do validation of fasta format

    my $old_eol = $/;
    $/ = $file_eol;

    my $seq = '';
    my $line;
    open(TMP, "<$file_path/$file_name") or die "could not open file '$file_path/$file_name': $!";
    while ( defined($line = <TMP>) )
    {
	chomp $line;
	if ( $line =~ /^\s*$/ or $line =~ /^>/ ) 
	{
	    next;
	}
	else
	{
	    $seq .= $line;
	}

	last if (length($seq) >= $max_chars);
    }
    close(TMP);

    $/ = $old_eol;

    $seq =~ tr/A-Z/a-z/;

    my %char_count;
    foreach my $char ( split('', $seq) )
    {
	$char_count{$char}++;
    }

    $char_count{a} ||= 0;
    $char_count{c} ||= 0;
    $char_count{g} ||= 0;
    $char_count{t} ||= 0;
    $char_count{n} ||= 0;
    $char_count{x} ||= 0;
    $char_count{'-'} ||= 0;
    
    # find fraction of a,c,g,t characters from total, not counting '-', 'N', 'X'
    my $bp_char = $char_count{a} + $char_count{c} + $char_count{g} + $char_count{t};
    my $n_char  = length($seq) - $char_count{n} - $char_count{x} - $char_count{'-'};
    my $fraction = $n_char ? $bp_char/$n_char : 0;

    if ( $fraction <= 0.6 ) {
	return "protein";
    }
    else {
	return 'DNA';
    }
}

sub file_eol {
    my($file_type) = @_;

    my $file_eol;

    if ( $file_type =~ /ASCII/ )
    {
	# ignore some useless informationa and stuff that gets in when the file command guesses wrong
	$file_type =~ s/, with very long lines//;
	$file_type =~ s/C\+\+ program //;
	$file_type =~ s/Java program //;
	$file_type =~ s/English //;

	if ( $file_type eq 'ASCII text' )
	{
	    $file_eol = $/;
	}
	elsif ( $file_type eq 'ASCII text, with CR line terminators' )
	{
	    $file_eol = "\cM";
	}
	elsif ( $file_type eq 'ASCII text, with CRLF line terminators' )
	{
	    $file_eol = "\cM\cJ";
	}
	elsif ( $file_type eq 'ASCII text, with CR, LF line terminators' )
	{
	    $file_eol = "ASCII file has mixed (CR, LF) line terminators";
	}
	elsif ( $file_type eq 'ASCII text, with CRLF, LF line terminators' ) 
	{
	    $file_eol = "ASCII file has mixed (CRLF, LF) line terminators";
	}
	elsif ( $file_type eq 'ASCII.*text, with CRLF, CR line terminators' ) 
	{
	    $file_eol = "ASCII file has mixed (CRLF, CR) line terminators";
	}
	elsif ( $file_type eq 'ASCII text, with no line terminators' ) 
	{
	    $file_eol = "ASCII file has no line terminators";
	}
	else 
	{
	    # none of the above? use default and see what happens
	    $file_eol = $/;
	}
    }
    else
    {
	# non-ASCII?
	$file_eol = $/;
    }
	
    return $file_eol;
}

sub file_format {
    my($file_name, $file_path, $file_type, $file_suffix, $file_eol) = @_;

    if ( $file_name eq 'file_info' ) {
	return 'info';
    }

    if ( $file_suffix eq '.qual' )
    {
	return 'qual';
    }

    if ( $file_type eq 'data' and $file_suffix eq '.sff' )
    {
	return 'sff';
    }

    # identify fasta or fastq
    if ( $file_type =~ /^ASCII/ )
    {
	my @chars;
	my $old_eol = $/;
	my $line;
	my $i;
	open(TMP, "<$file_path/$file_name") or die "could not open file '$file_path/$file_name': $!";
	
	while ( defined($line = <TMP>) and chomp $line and $line =~ /^\s*$/ )
	{
	    # ignore blank lines at beginning of file
	}

	close(TMP) or die "could not close file '$file_path/$file_name': $!";
	$/ = $old_eol;

	if ( $line =~ /^LOCUS/ ) 
	{
	    return 'genbank';
	}
	elsif ( $line =~ /^>/ ) 
	{
	    return 'fasta';
	}
	elsif ( $line =~ /^@/ )
	{
	    return 'fastq';
	}
	else
	{
	    return 'malformed';
	}
    }
    else
    {
	return 'unknown';
    }
}

###########################
# SFF to FASTQ conversion #
###########################
sub extract_fastq_from_sff {
    my($sff, $dir) = @_;
    
    my ($without_extension) = $sff =~ /^(.*)\.sff$/;
    eval {
	    `$Conf::sff_extract -s '$dir/$without_extension.fastq' -Q '$dir/$sff'`;
    };
    
    if ($@)
    {
	return (0, "$sff\tError unpacking uploaded sff file '$dir/$sff': $@");
    }

    if ( -s "$dir/$sff.fastq" )
    {
	return (1, "$sff\tsff to fastq success, created $sff.fastq");
    }
    else
    {
	return (0, 'result files not found');
    }
}

##################
# demultiplexing #
##################
sub split_fasta_by_mid_tag {
    my($filename, $dir, $type, $mid_tags, $tagnames) = @_;

    my $file_eol;
    open(FH, "<$dir/$filename.stats_info") or die "could not open info file: '$dir/$filename.stats.info': $!";
    while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	if ($key eq 'type') {
	    $file_eol = &file_eol($val);
	    last;
	}
    }
    close FH;
    unless ($file_eol) {
	die "could not determine end of line character for '$dir/$filename'";
    }

    # split a fasta file by the multiplex ID (MID) tag
     my ($file_base, $ext) = $filename =~ /(.+)\.($seq_ext)$/;

    # open file for each MID tag and one for unmatched sequences and store the filehandles in a hash
    my %filehandle;
    foreach my $file_ext ( @$mid_tags, 'no_MID_tag' ) {
	my $file = $dir . '/' . $file_base . '_' . $file_ext . '.' . $type;
	if ($tagnames->{$file_ext}) {
	    $file = $dir . '/' . $tagnames->{$file_ext} . '.' . $type;
	}
	$filehandle{$file_ext} = &newopen($file);
    }

    my $rec;
    my $old_eol = $/;
    if ($type eq 'fasta') {
	$/ = $file_eol . '>';
    }

    open(SEQ, "<$dir/$filename") or die "could not open file '$dir/$filename': $!";
    while ( defined($rec = <SEQ>) ) {
	chomp $rec;
	my($id_line, @lines) = split($file_eol, $rec);
	
	my $seq;
	my $plus;
	my $qual;
	if ($type eq 'fasta') {
	    $seq = join('', @lines);
	} else {
	    $seq = <SEQ>;
	    chomp $seq;
	    $plus = <SEQ>;
	    chomp $plus;
	    $qual = <SEQ>;
	    chomp $qual;
	}

	my $file_ext = '';	
	# search for a MID tag
	foreach my $mid_tag ( @$mid_tags ) {
	    if ( $seq =~ /^$mid_tag/i ) {
		$file_ext = $mid_tag;
		
		# trim off a segment same length as the MID tag
		$seq = substr($seq, length($mid_tag));
		if ($qual) {
		    $qual = substr($qual, length($mid_tag));
		}
		last;
	    }
	}
	
	if ( ! $file_ext ) {
	    $file_ext = 'no_MID_tag';
	}

	my $fh = $filehandle{$file_ext};

	if ($type eq 'fasta') {
	    my $formatted_seq = &fasta_formatted_sequence($seq, 60);
	    print $fh ">$id_line\n$formatted_seq";
	} else {
	    print $fh $id_line."\n".$seq."\n".$plus."\n".$qual."\n";
	}
    }
    close(SEQ);

    $/ = $old_eol;

    my @files = ();
    # close all filehandles
    foreach my $file_ext ( @$mid_tags, 'no_MID_tag' ) {
	my $file = $dir . '/' . $file_base . '_' . $file_ext . '.' . $type;
	if ($tagnames->{$file_ext}) {
	    $file = $dir . '/' . $tagnames->{$file_ext} . '.' . $type;
	}
	my $fh = $filehandle{$file_ext};
	close($fh);
	chmod 0666, $file;
	push @files, $file;
    }

    return \@files;
}

sub split_fasta_by_bc_length {
    my ($filename, $dir, $type, $bc_length) = @_;

    my $file_eol;
    open(FH, "<$dir/$filename.stats_info") or die "could not open info file: '$dir/$filename.stats.info': $!";
    while (<FH>) {
	chomp;
	my ($key, $val) = split /\t/;
	if ($key eq 'type') {
	    $file_eol = &file_eol($val);
	    last;
	}
    }
    close FH;
    unless ($file_eol) {
	die "could not determine end of line character for '$dir/$filename'";
    }

    # split a fasta file by the multiplex ID (MID) tag
    my ($file_base, $ext) = $filename =~ /(.+)\.($seq_ext)$/;

    # open file for each MID tag and one for unmatched sequences and store the filehandles in a hash
    my %filehandle;

    my $rec;
    my $old_eol = $/;
    if ($type eq 'fasta') {
	$/ = $file_eol . '>';
    }

    my $mid_tags = [];

    open(SEQ, "<$dir/$filename") or die "could not open file '$dir/$filename': $!";
    while ( defined($rec = <SEQ>) ) {
	chomp $rec;
	my($id_line, @lines) = split($file_eol, $rec);
	
	my $seq;
	my $qual;
	my $plus;
	if ($type eq 'fasta') {
	    $seq = join('', @lines);
	} else {
	    $seq = <SEQ>;
	    chomp $seq;
	    $plus = <SEQ>;
	    chomp $plus;
	    $qual = <SEQ>;
	    chomp $qual;
	}
	
	my $file_ext = substr($seq, 0, $bc_length);

	unless (exists($filehandle{$file_ext})) {
	  my $file = $dir . '/' . $file_base . '_' . $file_ext . '.'.$type;
	  $filehandle{$file_ext} = &newopen($file);
	  push(@$mid_tags, $file_ext);
	}
		
	# trim off a segment same length as the MID tag
	$seq = substr($seq, $bc_length);
	if ($qual) {
	    $qual = substr($qual, $bc_length);
	}
		
	my $fh = $filehandle{$file_ext};
	
	if ($type eq 'fasta') {
	    my $formatted_seq = &fasta_formatted_sequence($seq, 60);
	    print $fh ">$id_line\n$formatted_seq";
	} else {
	    print $fh $id_line."\n".$seq."\n".$plus."\n".$qual."\n";
	}
    }
    close(SEQ) or die "oh noes: $@";

    $/ = $old_eol;

    my @files = ();
    # close all filehandles
    foreach my $file_ext ( @$mid_tags ) {
	my $file = $dir . '/' . $file_base . '_' . $file_ext . '.' . $type;
	my $fh   = $filehandle{$file_ext};
	close($fh) or die "could not close file '$file': $!";
	chmod 0666, $file;
	push @files, $file;
    }

    return \@files;
}

##################
# Helper Methods #
##################

sub fasta_formatted_sequence {
    my($seq, $line_length) = @_;
    my($seg, @seq_lines);

    $line_length ||= 60;
    my $offset     = 0;
    my $seq_ln     = length($seq);

    while ( $offset < ($seq_ln - 1) and defined($seg = substr($seq, $offset, $line_length)) )
    {
        push(@seq_lines, $seg);
        $offset += $line_length;
    }

    my $fasta_sequence = join("\n", @seq_lines) . "\n";
    return $fasta_sequence;
}

sub newopen {
    my($file) = @_;
    local *FH;  # not my!

    open (FH, ">$file") || die "could not open file '$file': $!";
    return *FH;
}

sub pretty_date {
    my ($date) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($date);
    $year += 1900;
    my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    $hour = $hour < 10 ? "0".$hour : $hour;
    $min = $min < 10 ? "0".$min : $min;
    $sec = $sec < 10 ? "0".$sec : $sec;
    $mday = $mday < 10 ? "0".$mday : $mday;

    my $pretty_date = "$year $abbr[$mon] $mday $hour:$min:$sec";

    return $pretty_date;
}

sub pretty_size {
    my ($size) = @_;
    my $magnitude = "B";
    if ($size > 1024) {
	$size = $size / 1024;
	$magnitude = "KB"
    }
    if ($size > 1024) {
	$size = $size / 1024;
	$magnitude = "MB";
    }
    if ($size > 1024) {
	$size = $size / 1024;
	$magnitude = "GB";
    }
    $size = sprintf("%.1f", $size);
    $size = &addCommas($size);
    $size = $size . " " . $magnitude;
    
    return $size;
}

sub addCommas {
    my ($nStr) = @_;
    $nStr .= '';
    my @x = split(/\./, $nStr);
    my $x1 = $x[0];
    my $x2 = scalar(@x) > 1 ? '.' . $x[1] : '';
    while ($x1 =~ /(\d+)(\d{3})/) {
	$x1 =~ s/(\d+)(\d{3})/$1,$2/;
    }
    return $x1 . $x2;
}
