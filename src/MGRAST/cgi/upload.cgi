use warnings;
use strict;

use CGI;
use JSON;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use URI::Escape;

use File::Basename;
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

my $seq_ext = "fasta|fa|ffn|frn|fna|fastq|fq";

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
    my $data = [ { type => 'user_inbox', id => $user->login, files => [], fileinfo => {}, computation_error_log => {}, locks => {}, messages => [], popup_messages => [], directories => [] }];

    # check if the user has stats calculations in the queue
    my $uname = $user->{login};
    my $count = `/usr/local/bin/qstat | grep $uname | wc -l`;
    if ($count && $count > 0) {
	push(@{$data->[0]->{messages}}, "You have $count ongoing analyses computing. The information on the files involved in these operations may be incomplete and you will not be able to select these for submisson until the computations are complete. You can reload this page or click the 'update inbox' button to update the status of your inbox.");
    }

    # check if we are supposed to do anything else than return the content of the inbox
    if ($cgi->param('faction')) {
	my $action = $cgi->param('faction');
	my @files = $cgi->param('fn');

	# delete a list of files
	if ($action eq 'del') {
	    foreach my $file (@files) {
                my $lock_msg = "";
                if (-f "$udir/$file.lock") {
		    $lock_msg = `cat $udir/$file.lock`;
		    chomp $lock_msg;
		}

		if($lock_msg eq "" || $lock_msg eq "uploading") {
		    if (-f "$udir/$file") {		    
		        `rm '$udir/$file'`;
		        if (-f "$udir/$file.stats_info") {
			    `rm '$udir/$file.stats_info'`;
		        }
		        if (-f "$udir/$file.error_log") {
			    `rm '$udir/$file.error_log'`;
                        }
		        if (-f "$udir/$file.lock") {
			    `rm '$udir/$file.lock'`;
                        }
		    }
                } else {
                    push(@{$data->[0]->{popup_messages}}, "File undergoing computation cannot be deleted: $file");
		}
	    }
	}

        # delete an empty directory
        if($action eq 'delete_dir') {
	    my $target_dir = shift(@files);
            my @dir_files = `ls $udir/$target_dir`;
            if(scalar(@dir_files) == 0) {
                # command will fail unless directory is empty
                `rmdir $udir/$target_dir`;
            } else {
                # this should never be called as the javascript will not allow it
		push(@{$data->[0]->{popup_messages}}, "Could not delete directory: $target_dir because it was not empty.");
            }
        }

	#  move a list of files
	if ($action eq 'move') {
	    my $target_dir = shift(@files);
	    if ($target_dir eq 'inbox') {
		$target_dir = $udir."/";
	    } else {
		$target_dir = "$udir/$target_dir/";
	    }
	    foreach my $file (@files) {
                if (-f "$udir/$file.lock") {
                    push(@{$data->[0]->{popup_messages}}, "File undergoing computation cannot be moved: $file");
                } else {
		    `mv $udir/$file $target_dir`;
		    if (-f "$udir/$file.stats_info") {
		        `mv $udir/$file.stats_info $target_dir`;
		    }
		    if (-f "$udir/$file.error_log") {
		        `mv $udir/$file.error_log $target_dir`;
		    }
                }
	    }
	}

        # create a directory
        if ($action eq 'create_dir') {
            my $dir = shift(@files);
            unless(-d "$udir/$dir") {
                `mkdir '$udir/$dir'`;
            }
        }
	
	# decompress a list of files
	if ($action eq 'unpack') {
	    my %files_to_filetype = ();
	    # We want to create ALL the lock files before doing any operations on the files.
	    foreach my $file (@files) {
		if (-f "$udir/$file") {
		    # This if/else block is used to get the base filename but also records the
		    # filetype so that the correct decompression can be called below and the
		    # regex's and if/else logic only need to be maintined in one location (here).
		    my $basename = $file;
		    if ($basename =~ s/^(.*)\.(tar\.gz|tgz)$/$1/) {
			$files_to_filetype{$file} = 'tar gzip';
		    } elsif ($basename =~ s/^(.*)\.zip$/$1/) {
			$files_to_filetype{$file} = 'zip';
		    } elsif ($basename =~ s/^(.*)\.(tar\.bz2|tbz|tbz2|tb2)$/$1/) {
			$files_to_filetype{$file} = 'tar bzip2';
		    } elsif ($basename =~ s/^(.*)\.gz$/$1/) {
			$files_to_filetype{$file} = 'gzip';
		    } elsif ($basename =~ s/^(.*)\.bz2$/$1/) {
			$files_to_filetype{$file} = 'bzip2';
		    }

                    my $lock_file1 = "$udir/$file.lock";
                    my $lock_file2 = "$udir/$basename.lock";
                    if (-f $lock_file1) {
                	my $lock_msg = `cat $lock_file1`;
                	chomp $lock_msg;
			push(@{$data->[0]->{popup_messages}}, "Unable to decompress $file, currently running $lock_msg.");
                    } elsif (-f $lock_file2) {
                	my $lock_msg = `cat $lock_file2`;
                	chomp $lock_msg;
			push(@{$data->[0]->{popup_messages}}, "Unable to decompress $file to $basename, currently running $lock_msg.");
                    } else {
			my $jobid = $user->{login};
                        $jobid =~ s/\s/_/g;
			`echo "decompressing" > $lock_file1`;
			`echo "decompressing" > $lock_file2`;

                        my $command = "";
			if ($files_to_filetype{$file} eq 'tar gzip') {
			    $command = "echo \"tar -xzf '$udir/$file' -C $udir &> $udir/$file.error_log; rm $lock_file1 $lock_file2;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			} elsif ($files_to_filetype{$file} eq 'zip') {
			    $command = "echo \"unzip -q -o -d $udir '$udir/$file' &> $udir/$file.error_log; rm $lock_file1 $lock_file2;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			} elsif ($files_to_filetype{$file} eq 'tar bzip2') {
			    $command = "echo \"tar -xjf '$udir/$file' -C $udir &> $udir/$file.error_log; rm $lock_file1 $lock_file2;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			} elsif ($files_to_filetype{$file} eq 'gzip') {
			    $command = "echo \"gunzip -d '$udir/$file' &> $udir/$file.error_log; rm $lock_file1 $lock_file2;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			} elsif ($files_to_filetype{$file} eq 'bzip2') {
			    $command = "echo \"bunzip2 -d '$udir/$file' &> $udir/$file.error_log; rm $lock_file1 $lock_file2;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			}
                        my $jnum = `$command`;
                        $jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
                        open(FH, ">>$udir/.tmp/jobs");
                        print FH "$jnum";
                        close FH;
		    }
		}
	    }
	}
	
	# convert a list of files from sff to fastq
	if ($action eq 'convert') {
	    foreach my $file (@files) {
		if ($file =~ /\.sff$/) {
		    if (-f "$udir/$file.fastq") {
			push(@{$data->[0]->{popup_messages}}, "File: $file exists. The conversion for this file is either already finished or in progress.");
		    } else {
			my ($success, $message) = &extract_fastq_from_sff($file, $udir);
			unless ($success) {
			    push(@{$data->[0]->{popup_messages}}, "Problem extracting sff file to fastq:\n".$message);
			}
		    }
		} else {
		    push(@{$data->[0]->{popup_messages}}, "Unknown filetype for fastq conversion for file $file.  Currently only sff is supported.");
		}
	    }
	}

        # join_paired_ends, there will be two paired-end fastq files
        if ($action eq 'join_paired_ends') {
            # do stuff
	    my $seqfile1; # paired-end file 1
	    my $seqfile2; # paired-end file 2
	    my $seqfile3; # index file
	    my $filetype1;
	    my $filetype2;
	    my $filetype3;
	    my $join_option; # option to include non-overlapping paired-ends
            my $joinfile; # output filename
	    my @files_to_verify = ($files[0], $files[1]);

	    my $has_seqs = 0;
	    if (@files == 5 && $files[0] =~ /\.$seq_ext$/ && $files[1] =~ /\.$seq_ext$/ && ($files[2] eq "none" || $files[2] =~ /\.$seq_ext$/)) {
                my $ext1 = $files[0];
                $ext1 =~ s/^\S+\.($seq_ext)$/$1/;
		$filetype1 = ($ext1 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile1  = $files[0];

                my $ext2 = $files[1];
                $ext2 =~ s/^\S+\.($seq_ext)$/$1/;
		$filetype2 = ($ext2 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile2  = $files[1];

                my $ext3 = $files[2];
                $ext3 =~ s/^\S+\.($seq_ext)$/$1/;
		$filetype3 = ($ext3 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		if($files[2] eq "none") {
		    $seqfile3 = "";
		} else {
		    $seqfile3 = $files[2];
		    push @files_to_verify, $files[2];
		}

                if($filetype1 eq 'fastq' && $filetype2 eq 'fastq' && ($seqfile3 eq "" || $filetype3 eq 'fastq')) {
		    $has_seqs = 1;
                }

		$join_option = $files[3];
		$joinfile = $files[4];
	    }

	    if ($has_seqs) {
                my $lock_file1 = "$udir/$seqfile1.lock";
                my $lock_file2 = "$udir/$seqfile2.lock";
		my $lock_file3 = "$udir/$joinfile.lock";
                if (-f $lock_file1) {
                    my $lock_msg = `cat $lock_file1`;
                    chomp $lock_msg;
		    push(@{$data->[0]->{popup_messages}}, "Unable to join paired-ends on $seqfile1 and $seqfile2, currently running $lock_msg.");
                } elsif (-f $lock_file2) {
                    my $lock_msg = `cat $lock_file2`;
                    chomp $lock_msg;
		    push(@{$data->[0]->{popup_messages}}, "Unable to join paired-ends on $seqfile1 and $seqfile2, currently running $lock_msg.");
                } elsif (-f $lock_file3) {
                    my $lock_msg = `cat $lock_file3`;
                    chomp $lock_msg;
		    push(@{$data->[0]->{popup_messages}}, "Unable to join paired-ends on $seqfile1 and $seqfile2, currently running $lock_msg.");
                } else {
		    my $fix_files_str = "";
		    my $file_types_verify = 1;
		    foreach my $input_file (@files_to_verify) {
			my ($file_type, $err_msg, $fix_str) = &verify_file_type($input_file, $udir);
			if($err_msg ne "") {
			    push(@{$data->[0]->{popup_messages}}, $err_msg);
			    $file_types_verify = -1;
			} elsif($fix_str ne "") {
			    $fix_files_str .= "$fix_str; ";
			}
		    }

		    if($file_types_verify == 1) {
			my $jobid = $user->{login};
			$jobid =~ s/\s/_/g;
			`echo "computing join paired-ends" > $lock_file1`;
			`echo "computing join paired-ends" > $lock_file2`;
			if($lock_file3 ne "") { `echo "computing join paired-ends" > $lock_file3`; }

			my $jnum = "";
			my $command = "";
			if($join_option eq 'remove') {
			    if($seqfile3 eq "") {
				$command = "echo \"$fix_files_str $Conf::pairend_join -j -m 8 -p 10 -t $udir/.tmp -o $udir/$joinfile $udir/$seqfile1 $udir/$seqfile2 2>&1 | tee -a $udir/$seqfile1.error_log > $udir/$seqfile2.error_log; rm $lock_file1 $lock_file2 $lock_file3;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			    } else {
				$command = "echo \"$fix_files_str $Conf::pairend_join -j -r -i $udir/$seqfile3 -m 8 -p 10 -t $udir/.tmp -o $udir/$joinfile $udir/$seqfile1 $udir/$seqfile2 2>&1 | tee -a $udir/$seqfile1.error_log > $udir/$seqfile2.error_log; rm $lock_file1 $lock_file2 $lock_file3;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			    }
			} else {
			    if($seqfile3 eq "") {
				$command = "echo \"$fix_files_str $Conf::pairend_join -m 8 -p 10 -t $udir/.tmp -o $udir/$joinfile $udir/$seqfile1 $udir/$seqfile2 2>&1 | tee -a $udir/$seqfile1.error_log > $udir/$seqfile2.error_log; rm $lock_file1 $lock_file2 $lock_file3;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			    } else {
				$command = "echo \"$fix_files_str $Conf::pairend_join -r -i $udir/$seqfile3 -m 8 -p 10 -t $udir/.tmp -o $udir/$joinfile $udir/$seqfile1 $udir/$seqfile2 2>&1 | tee -a $udir/$seqfile1.error_log > $udir/$seqfile2.error_log; rm $lock_file1 $lock_file2 $lock_file3;\" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp";
			    }
			}
			$jnum = `$command`;
			$jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
			open(FH, ">>$udir/.tmp/jobs");
			print FH "$jnum";
			close FH;
		    }
                }
	    } else {
		push(@{$data->[0]->{popup_messages}}, "Unknown file types for join paired-ends, please select two .fastq or .fq input sequence files.  Also, if an index file is included, that file must also be in fastq format with an appropriate file extension.");
	    }
	}
	
	# demultiplex, there will be one sequence and one barcode file
	if ($action eq 'demultiplex') {
	    my $midfile;
	    my $seqfile;
	    my $filetype;
	    my $has_seqs = 0;
	    if (@files == 2 && $files[0] =~ /\.($seq_ext)$/) {
		$filetype = ($1 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile  = $files[0];
		$midfile  = $files[1];
		$has_seqs = 1;
	    } elsif (@files == 2 && $files[1] =~ /\.($seq_ext)$/) {
		$filetype = ($1 =~ /^(fq|fastq)$/) ? 'fastq' : 'fasta';
		$seqfile  = $files[1];
		$midfile  = $files[0];
		$has_seqs = 1;
	    }
	    if ($has_seqs) {
		# Get the sub-directory
                my $subdir = "";
                if($seqfile =~ /\//) {
                    $subdir = $seqfile;
                    $subdir =~ s/^(.*\/).*/$1/;
                }

		my $fix_files_str = "";
		my $file_types_verify = 1;
		foreach my $input_file ($files[0], $files[1]) {
		    my ($file_type, $err_msg, $fix_str) = &verify_file_type($input_file, $udir);
		    if($err_msg ne "") {
			push(@{$data->[0]->{popup_messages}}, $err_msg);
			$file_types_verify = -1;
		    } elsif($fix_str ne "") {
			$fix_files_str .= "$fix_str; ";
		    }
		}

		if($file_types_verify == 1) {
		    #  Check for lock files that already exist for output filenames and
		    #  add to array if they do already exist.
		    my %output_files = ();
		    my %output_files_locked = ();
		    open IN, "$udir/$midfile" || die "Cannot open file $udir/$midfile for reading.\n";
		    while(my $line=<IN>) {
			$line =~ s/\s+$//;
			my @array = split(/\t/, $line);
			my $output_file = "$array[1]";
			chomp $output_file;
			if($filetype eq 'fastq') {
			    $output_file .= '.fastq';
			} else {
			    $output_file .= '.fna';
			}
			my $output_lock_file = "$udir/$subdir/$output_file.lock";
			if(-f $output_lock_file) {
			    $output_files_locked{$output_file} = 1;
			}
			$output_files{$output_file} = 1;
		    }
		    close IN;

                    my $lock_file = "$udir/$seqfile.lock";
                    if (-f $lock_file) {
                	my $lock_msg = `cat $lock_file`;
                	chomp $lock_msg;
			push(@{$data->[0]->{popup_messages}}, "Unable to demultiplex $seqfile, currently running $lock_msg.");
		    } elsif(keys %output_files_locked) {
			my $output_files_locked_str = join(" ", keys %output_files_locked);
			push(@{$data->[0]->{popup_messages}}, "Unable to demultiplex into files: $output_files_locked_str, those files are currently undergoing other operations.");
                    } else {
			my $jobid = $user->{login};
			$jobid =~ s/\s/_/g;
			`echo "computing demultiplex" > $lock_file`;
			my $output_lock_files_str = "";
			foreach my $output_file (keys %output_files) {
			    `echo "computing demultiplex" > $udir/$subdir/$output_file.lock`;
			    $output_lock_files_str .= "$udir/$subdir/$output_file.lock ";
			}
			my $jnum = `echo "$fix_files_str $Conf::demultiplex -f $filetype -b $udir/$midfile -i $udir/$seqfile -o $udir/$subdir 2> $udir/$seqfile.error_log; rm $lock_file; rm $output_lock_files_str;" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp`;
			$jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
			open(FH, ">>$udir/.tmp/jobs");
			print FH "$jnum";
			close FH;

			my $bc_count = `wc $udir/$midfile | awk '{print \$1}'`;
			chomp $bc_count;
			push(@{$data->[0]->{popup_messages}}, "Sequence file $seqfile is queued to be demultiplexed using $bc_count barcodes.");
		    }
                }
	    } else {
		push(@{$data->[0]->{popup_messages}}, "Unknown file types for demultiplex, please select one sequence file and one barcode file.");
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
            my $old_filename = $ufile;
            $ufile = &sanitize_filename($ufile);
            if($old_filename ne $ufile) {
                push(@{$data->[0]->{popup_messages}}, "The file '$old_filename' contained invalid characters. It has been renamed to '$ufile'.\n\nWARNING\nIf this is a sequence file associated with a library in your metadata, you will have to adjust the library file_name or metagenome_name in the metadata file!");
            }
	    
	    # check directories
	    if (-d "$udir/$ufile") {
		opendir(my $dh2, $udir."/".$ufile);
		my @numfiles = grep { /^[^\.]/ && -f $udir."/".$ufile."/".$_ } readdir($dh2);
		closedir $dh2;
		push(@{$data->[0]->{directories}}, $ufile);
		my $dirseqs = [];
		foreach my $nf (@numfiles) {
		    unless ($nf =~ /\.stats_info$/ || $nf =~ /\.lock$/ || $nf =~ /\.part$/ || $nf =~ /\.error_log$/) {
			push(@$dirseqs, $nf);
		    }
		    push(@ufiles, "$ufile/$nf");		
		}
		$data->[0]->{fileinfo}->{$ufile} = $dirseqs;
	    }
	    # check files
	    else {
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat("$udir/$ufile");
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
		    $data->[0]->{fileinfo}->{$fn} = $info;
		} elsif ($ufile =~ /^(.+)\.error_log$/) {
		    my $fn = $1;
                    my $str = "";
		    if (open(FH, "<$udir/$ufile")) {
			while (my $line=<FH>) {
			    chomp $line;
                            $str .= $line;
			}
			close FH;
		    }
		    $data->[0]->{computation_error_log}->{$fn} = $str;
		} elsif ($ufile =~ /^(.+)\.lock$/) {
		    my $fn = $1;
                    my $str = "";
		    if (open(FH, "<$udir/$ufile")) {
			while (my $line=<FH>) {
			    chomp $line;
                            $str .= $line;
			}
			close FH;
		    }
		    $data->[0]->{locks}->{$fn} = $str;
		} elsif ($ufile =~ /^(.+)\.part$/) {
                    # do nothing
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
        my $lock_file = "$udir/$sequence_file.lock";

	# create basic and extended file information if we do not yet have it and there is no lock file present
	if (! $info_files->{$sequence_file} && ! -f $lock_file) {
	    my ($file_type, $err_msg, $fix_file_str) = &verify_file_type($sequence_file, $udir);
	    if($err_msg ne "") {
		push(@{$data->[0]->{popup_messages}}, $err_msg);
	    } else {
        	`echo "computing sequence stats" > $lock_file`;
		`touch "$udir/$sequence_file.stats_info"`;
		my ($file_name, $dirs, $file_suffix) = fileparse($sequence_file, qr/\.[^.]*/);
		my $file_format = &file_format($sequence_file, $udir, $file_type, $file_suffix);
		my $file_size   = -s $udir."/".$sequence_file;
		$file_suffix =~ s/\.//;
	    
		my $info = {
		    "type" => $file_type,
			"suffix" => $file_suffix,
			"file_name" => $file_name.'.'.$file_suffix,
			"file_type" => $file_format,
			"file_size" => $file_size };
	    
		open(FH, ">$udir/$sequence_file.stats_info");
		print FH "type\t$file_type\n";
		print FH "suffix\t$file_suffix\n";
		print FH "file_type\t$file_format\n";
		print FH "file_size\t$file_size\n";
		close(FH);
		`chmod 666 $udir/$sequence_file.stats_info`;
	    
		$data->[0]->{fileinfo}->{$sequence_file} = $info;

		if($fix_file_str ne "") {
		    $fix_file_str .= ";";
		}

		# call the extended information
		# temporarily allowing file_type to be '' because that's what the current version
		# of the file command we are running returns for certain fastq files.  When file
		# is updated on our web server, we will only accept 'ASCII text' here.
		if ($file_type eq 'ASCII text' || $file_type eq '') {
		    my $jobid = $user->{login};
		    $jobid =~ s/\s/_/g;
		    my $jnum = `echo "$fix_file_str $Conf::sequence_statistics -file '$sequence_file' -dir $udir -file_format $file_format -tmp_dir $udir/.tmp 2> $udir/$sequence_file.error_log; rm $lock_file;" | /usr/local/bin/qsub -q fast -j oe -N $jobid -l walltime=60:00:00 -m n -o $udir/.tmp`;
		    $jnum =~ s/^(.*)\.mcs\.anl\.gov/$1/;
		    open(FH, ">>$udir/.tmp/jobs");
		    print FH "$jnum";
		    close FH;
		}
	    }
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
	$data->[0]->{fileinfo}->{$file}->{'file size'} = $size;
	#$data->[0]->{fileinfo}->{$file}->{'file size'} = &pretty_size($size);
    }
    
    # sort the returned files lexigraphically
    @{$data->[0]->{files}} = sort { lc $a cmp lc $b } @{$data->[0]->{files}};
    
    # return the contents of the inbox
    print $cgi->header('text/plain');
    print "data_return('user_inbox', ".$json->encode( $data ).");";
    exit 0;
}

# If we get here, this is an actual upload
# Must be careful in handling the $filename variable since it may contain spaces or
#  other funny characters because it isn't validated at this point yet.
my $filename = $cgi->param('filename');
$filename = &sanitize_filename($filename);
my $fh = $cgi->upload('upload_file')->handle;
my $bytesread;
my $buffer;

# check if file already exists
if (-f "$udir/".$filename && ! -f "$udir/$filename.part") {
    if(-f "$udir/$filename") { `rm "$udir/$filename"`; }
    if(-f "$udir/$filename.lock") { `rm "$udir/$filename.lock"`; }
    if(-f "$udir/$filename.stats_info") { `rm "$udir/$filename.stats_info"`; }
    if(-f "$udir/$filename.error_log") { `rm "$udir/$filename.error_log"`; }
}

my $lock_file = "$udir/$filename.lock";
`echo "uploading" > "$lock_file"`;

if (open(FH, ">>$udir/".$filename)) {
    while ($bytesread = $fh->read($buffer,1024)) {
        print FH $buffer;
    }
    close FH;
    `touch "$udir/$filename.part"`;
}

# return a message to the sender
print "Content-Type: text/plain\n\n";

# if this is the last chunk, remove the partial file
if ($cgi->param('last_chunk')) {
    if(-f "$udir/$filename.part") { `rm "$udir/$filename.part"`; }
    if(-f "$udir/$filename.lock") { `rm "$udir/$filename.lock"`; }
    my $md5 = `md5sum $udir/$filename`;
    $md5 =~ s/^([^\s]+).*$/$1/;
    chomp $md5;
    print $md5;
} else {
    print "chunk received";
}

exit 0;

############################
# start of methods section #
############################

# return sanitized filenames
sub sanitize_filename {
  my($file) = @_;
  if($file !~ /^[\/\w\.\-]+$/) {
    my $newfilename = $file;
    $newfilename =~ s/[^\/\w\.\-]+/_/g;
    my $count = 1;
    while (-f "$udir/$newfilename" && ! -f "$udir/$newfilename.part") {
      if ($count == 1) {
        $newfilename =~ s/^(.*)(\..*)$/$1$count$2/;
      } else {
        my $oldcount = $count - 1;
        $newfilename =~ s/^(.*)$oldcount(\..*)$/$1$count$2/;
      }
        $count++;
    }
    # If the file already exists, it is moved.
    if(-e "$udir/$file") {
      rename("$udir/$file", "$udir/$newfilename");
    }
    $file = $newfilename;
  }
  return $file;
}

# check if the user directory exists, if not create it
sub initialize_user_dir {
  unless ( -d $udir ) {
    mkdir $udir or die "could not create directory '$udir'";
    chmod 0777, $udir;
  }
  unless ( -d "$udir/.tmp") {
    mkdir "$udir/.tmp" or die "could not create directory '$udir/.tmp'";
    chmod 0777, "$udir/.tmp";
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

####################################
# basic file information functions #
####################################

# Good ASCII files return:	file_type = 'ASCII text', err_msg = "", fix_str = ""
# Fixable ASCII files return:	file_type = 'ASCII text', err_msg = "", fix_str = "command to fix file"
# Bad files return:		file_type = bad file type, err_msg = error message, fix_str = ""

sub verify_file_type {
    my($file, $dir) = @_;

    # Need to do the 'safe-open' trick here since for now, file names might
    # be hard to escape in the shell.    
    open(P, "-|", "file", "-b", "$dir/$file") or die("cannot run file command on file '$dir/$file': $!");
    my $file_type = <P>;
    close(P);

    chomp $file_type;

    if ( $file_type =~ m/\S/ ) {
	$file_type =~ s/^\s+//;   #...trim leading whitespace
	$file_type =~ s/\s+$//;   #...trim trailing whitespace
    } else {
	# file does not work for fastq -- craps out for lines beginning with '@' on mg-rast machine!
	# check first 4 lines for fastq like format
	my @lines = `cat -A '$dir/$file' 2>/dev/null | head -n4`;
	chomp @lines;

	if ( ($lines[0] =~ /^\@/) && ($lines[0] =~ /\$$/) && ($lines[1] =~ /\$$/) &&
	     ($lines[2] =~ /^\+/) && ($lines[2] =~ /\$$/) && ($lines[3] =~ /\$$/) ) {
	    $file_type = 'ASCII text';
	} else {
	    $file_type = 'unknown file type, check end-of-line characters and (if fastq) fastq formatting';
	}
    }

    if ($file_type =~ /^ASCII/) {
	# ignore some useless information and stuff that gets in when the file command guesses wrong
	$file_type =~ s/, with very long lines//;
	$file_type =~ s/C\+\+ program //;
	$file_type =~ s/Java program //;
	$file_type =~ s/English //;
    } else {
	$file_type = "binary or non-ASCII file";
    }

    if ($file_type eq 'ASCII text, with CR line terminators') {
	return ('ASCII text', "", "sed -i 's/\\r/\\n/g' '$dir/$file'");
    } elsif($file_type eq 'ASCII text, with CRLF line terminators') {
	return ('ASCII text', "", "sed -i 's/\\r//g' '$dir/$file'");
    } elsif($file_type eq 'ASCII text') {
	return ($file_type, "", "");
    } elsif((-s "$dir/$file") == 0) {
	return ("empty file", "ERROR: File '$file' is empty.", "");
    }

    return ("binary or non-ASCII or invalid end of line characters", "ERROR: File '$file' is of unsupported file type '$file_type'.", "");
}

sub file_format {
    my($file_name, $file_path, $file_type, $file_suffix) = @_;

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

    if ( -s "$dir/$without_extension.fastq" )
    {
	return (1, "$sff\tsff to fastq success, created $sff.fastq");
    }
    else
    {
	return (0, 'result files not found');
    }
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
