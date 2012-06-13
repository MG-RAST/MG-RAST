package MGRAST::WebPage::Jobs;

use strict;
use warnings;

use base qw( WebPage );

use WebComponent::WebGD;
use WebConfig;

1;


=pod

=head1 NAME

Jobs - an instance of WebPage which displays an overview over all jobs

=head1 DESCRIPTION

Job overview page 

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Jobs Overview");
  $self->application->register_component('Table', 'Jobs');
  $self->application->register_component('Table', 'JobStatistics');
  $self->application->register_component('Table', 'MonthStatistics');
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;
  
  my $app  = $self->application->backend;
  my $user = $self->app->session->user;
  my $user_is_admin = $user->is_admin($app);
  
  my $content = '<h1>Jobs Overview</h1>';
  
  $content .= '<p>The overview below list all genomes currently processed and the progress on the annotation. '.
    'To get a more detailed report on an annotation job, please click on the progress bar graphic in the overview.</p>';
  $content .= '<p>In case of questions or problems using this service, please contact: <a href="mailto:mg-rast@mcs.anl.gov">mg-rast@mcs.anl.gov</a>.</p>';
  
  $content .= $self->get_color_key();
  
  $content .= '<h2>Jobs you have access to :</h2>';
  
  my $mgrast;
  my $data = [];
  my $jobs;
  eval { 
    @$jobs = $self->app->data_handle('MGRAST')->Job->get_jobs_for_user_fast($self->application->session->user);
  };
  unless (defined $jobs) {
    $self->app->error("Unable to retrieve the job overview.");
    print STDERR "Error: $!\n$@\n";
    return '';
  }

  if (scalar(@$jobs)) {
    
    my $udbh = $self->application->session->user->_master->db_handle;
    my %users = map { $_->{owner} => 1 } @$jobs;
    if (scalar(keys(%users))) {
      my $user_cond = join(", ", keys %users);
      my $userlist = $udbh->selectall_hashref(qq(SELECT _id, firstname, lastname, email FROM User WHERE _id IN ($user_cond)), '_id');
      $self->{users} = $userlist;
    }
    
    my $image_cache = {};  # use to cache progress bar images and various image stuff
    
    @$jobs = sort { $b->{id} <=> $a->{id} } @$jobs;
    foreach my $job (@$jobs) {
      push @$data, $self->genome_entry($job, $user_is_admin, $image_cache);
    }
    
    # create table
    my $table = $self->application->component('Jobs');
    $table->width(1000);
    if (scalar(@$data) > 50) {
      $table->show_top_browse(1);
      $table->show_bottom_browse(1);
      $table->items_per_page(50);
      $table->show_select_items_per_page(1);
    }
    
    if($user_is_admin){
      $table->columns([ { name => 'Job', filter => 1, sortable => 1 }, 
			{ name => 'Owner', filter => 1, },
			{ name => 'ID', filter => 1 },
			{ name => 'Name', filter => 1 },
			{ name => 'Size (bp)', sortable => 1 },
			{ name => 'Creation Date' },
			{ name => 'Progress' }, 
			{ name => 'Status', filter=> 1, sortable => 1, operator => "combobox" },
		      ]);
    } else {
      $table->columns([ { name => 'Job', filter => 1, sortable => 1 }, 
			{ name => 'Owner', filter => 1, },
			{ name => 'ID', filter => 1 },
			{ name => 'Name', filter => 1 },
			{ name => 'Size (bp)', sortable => 1 },
			{ name => 'Creation Date' },
			{ name => 'Annotation Progress' }, 
			{ name => 'Status', filter=> 1, sortable => 1, operator => "combobox", visible => 0 },
		      ]);

    }
    $table->data($data);
    $content .= $table->output();

      # create statistics tables
      if ( $user_is_admin )
      {
	  my $job_stats = $self->job_stats($data);

	  my $job_stats_table = $self->application->component('JobStatistics');

	  $job_stats_table->columns([ { name => 'Progress'},
				      { name => 'Status'}, 
				      { name => '# jobs'},
				      { name => 'bp'},
				      { name => 'bp'},
				      { name => 'Earliest'},
				      { name => 'Latest'},
				      ]);

	  $job_stats_table->width(1000);
	  $job_stats_table->data($job_stats);

	  $content .= '<p><h2>Statistics for jobs:</h2>';
	  $content .= $job_stats_table->output();

	  my $month_stats = $self->month_stats($data);

	  my $month_stats_table = $self->application->component('MonthStatistics');

	  $month_stats_table->columns([ { name => 'Month', sortable => 1},
					{ name => 'bp', sortable => 1}, 
					{ name => 'bp'},
					{ name => 'bp cumulative'},
					{ name => 'bp cumulative'},
					]);

	  $month_stats_table->width(1000);
	  $month_stats_table->data($month_stats);
	  $month_stats_table->show_export_button(1);

	  $content .= '<p><h2>Monthly statistics for completed jobs:</h2>';
	  $content .= $month_stats_table->output();
      }
  }
  else {
    $content .= "<p>You currently have no jobs.</p>";
    $content .= "<p> &raquo <a href='metagenomics.cgi?page=UploadMetagenome'>Upload a new metagenome</a></p>";
  }

  return $content;
}

=pod

=item * B<genome_entry> (I<job>)

Returns one entry row for the overview table, containing job id, user, 
genome info and the progress bar graphic. I<job> has to be the reference 
to a RAST::Job object.

=cut

sub genome_entry {
  my ($self, $job, $user_is_admin, $image_cache, $colors) = @_;
  
  my $image_source;
  my $info = '';       # popup text for progress bar image
  my $error_txt = '';  # Status column
  my $stage_txt = '';  # Status column
  
  my $stagesort = { 'status.uploaded' => 0,
		    'status.preprocess' => 1,
		    'status.sims' => 2,
		    'status.check_sims' => 3,
		    'status.create_seed_org' => 4,
		    'status.export' => 5,
		    'status.final' => 6 };

  my $revsort = { 0 => 'status.uploaded',
		  1 => 'status.preprocess',
		  2 => 'status.sims',
		  3 => 'status.check_sims',
		  4 => 'status.create_seed_org',
		  5 => 'status.export',
		  6 => 'status.final' };
  
  unless($job->{viewable}){
    my $state    = '';
    my $n_stages = 7;
    
    for (my $i = 0; $i < $n_stages; $i++)
      {
	my $stage  = $revsort->{$i};
	my $status = $job->{status}->{$stage} || 'not_started';
	
	$state .= $stage . $status;
	
	my $stage_number = $i + 1;
	
	if ($status ne 'not_started')
	  {
	    if ($status eq 'error') 
	      {
		# use first stage with error status
		$error_txt ||= $job->{server_version} . ".$stage_number: $stage error";
	      }
	    else
	      {
		# use last stage with not_started status
		$status =~ s/_/ /g;
		$info = "$stage_number of $n_stages steps, current step: $status";
		$stage_txt = $job->{server_version} . ".$stage_number: $stage $status";
	      }
	  }
      }
    
    if ( not exists $image_cache->{$state} )
      {
	my $box_height = 14; 
	my $box_width  = 12;
	
	if ( not exists $image_cache->{$n_stages} )
	  {
	    # create a new image
	    my $image = WebGD->new($n_stages*$box_width,$box_height);
	    
	    # allocate some colors
	    $colors = $self->get_colors($image);
	    
	    # make the background transparent and interlaced
	    $image->transparent($colors->{'white'});
	    $image->interlaced('true');
	    
	    # cache the image object and colors
	    $image_cache->{$n_stages}{image_obj} = $image;
	    $image_cache->{$n_stages}{colors}    = $colors;
	  }
	
	# use the cached image object and colors
	my $image  = $image_cache->{$n_stages}{image_obj};
	my $colors = $image_cache->{$n_stages}{colors};
	
	for (my $i = 0; $i < $n_stages; $i++)
	  {
	    my $stage  = $revsort->{$i};
	    my $status = $job->{status}->{$stage} || 'not_started';
	    if (exists($colors->{$status})) {
	      $image->filledRectangle($i*$box_width,0,10+$i*$box_width,$box_height,$colors->{$status});
	    }
	    else {
	      die "Found unknown status '$status' for stage '$stage' in job ".$job->{id}."\n";
	    }
	  }
	
	# cache the image code
	$image_cache->{$state} = $image->image_src;
      }
    
    # use the cached image source
    $image_source = $image_cache->{$state};
  } 
  else 
    {
      $stage_txt = $job->{server_version} . ': complete';
      $info      = 'all steps completed';
      if($job->{server_version} eq "2"){
	$image_source = "./Html/job_complete.png";
      } else {
	$image_source = "./Html/old_job_complete.png";
      }
    }
  
  my $progress  = '<img style="border: none;" src="'.$image_source.'"/>';
  my $link_img  = "<a title='".($info || "")."' href='metagenomics.cgi?page=JobDetails&job=".$job->{id}."'>$progress</a>";
  my $link_text = "<a href='metagenomics.cgi?page=JobDetails&job=".$job->{id}."'><em> view details </em></a>";
  
  my $name_display = 'unknown';
  if ($self->{users} && $job->{owner} && $self->{users}->{$job->{owner}}) {
    
    my $email     = $self->{users}->{$job->{owner}}->{email};
    my $firstname = $self->{users}->{$job->{owner}}->{firstname};
    my $lastname  = $self->{users}->{$job->{owner}}->{lastname};
    
    if ( $firstname and $lastname ) {
      if ( $email and $user_is_admin ) {
	$name_display = qq(<a href="mailto:$email, mg-rast\@mcs.anl.gov">$lastname, $firstname</a>);
      } else {
	$name_display = "$lastname, $firstname";
      }
    }
  }
  
  my $creation_date = "unknown";
  if($job->{created_on} =~ /(\d+-\d+-\d+)\s/){
    $creation_date = $1;
  }
  
  my $size = $job->{size} || 0;
  
  my $status_txt = $error_txt || $stage_txt || 'could not determine status';
  $status_txt =~ s/_/ /g;
  $status_txt =~ s/status\./ /;
  $status_txt =~ s/uploaded/upload/;
  $status_txt = '<nobr>' . $status_txt . '</nobr>';
  
  return [
	  $job->{id},
	  $name_display,
	  $job->{genome_id},
	  $job->{genome_name},
	  $size,
	  $creation_date,
	  $link_img.'<br/>'.$link_text,
	  $status_txt,
	 ];
}

=pod

=item * B<job_stats> ()

Returns a hash reference with various statistics about all the jobs

=cut

sub job_stats {
    my($self, $job_data) = @_;
    my %count;

    foreach my $job_rec ( @$job_data )
    {
	my($size, $date, $image, $status) = @$job_rec[4..7];
	$count{$status}{bp} += $size;
	$count{$status}{jobs} += 1;
	push @{ $count{$status}{dates} }, $date;
	$count{$status}{image}  = $image;
    }

    my @job_stats;
    foreach my $status ( sort keys %count )
    {
	my $image = $count{$status}{image};
	$image =~ s/<br.+//;
	my $bph = &human_readable($count{$status}{bp});
	my($first_date, $last_date) = (sort @{ $count{$status}{dates} })[1,-1];
	push @job_stats, [$image, $status, $count{$status}{jobs}, $bph, $count{$status}{bp}, $first_date, $last_date];
    }

    return \@job_stats;
}

=pod

=item * B<month_stats> ()

Returns a hash reference with various monthly statistics about completed jobs

=cut

sub month_stats {
    my($self, $job_data) = @_;
    my %count;

    foreach my $job_rec ( @$job_data )
    {
	my($size, $date, $status) = @$job_rec[4,5,7];
	
	if ( $status =~ /\d:\s+complete/ ) {
	    my $month = ($date =~ /(\d+-\d+)-\d+/)? $1 : 'unknown';
	    $count{$month}{bp} += $size;
	}
    }

    my @month_stats;
    my($bp, $bp_total);
    foreach my $month ( sort keys %count )
    {
	$bp = $count{$month}{bp};
	$bp_total += $bp;

	my $bph = &human_readable($bp);
	my $bph_total = &human_readable($bp_total);
	push @month_stats, [$month, $bp, $bph, $bp_total, $bph_total];
    }

    return \@month_stats;
}

sub human_readable {
    my($n) = @_;

    if ( $n < 1e3 ) {
	return "$n bp";
    } elsif ( $n < 1e6 ) {
	($n) = map {my $x = $_; $x =~ s/(\.\d\d)\d+/$1/; $x} ($n/1e3);
	return "$n Kbp";
    } elsif ( $n < 1e9 ) {
	($n) = map {my $x = $_; $x =~ s/(\.\d\d)\d+/$1/; $x} ($n/1e6);
	return "$n Mbp";
    } elsif ( $n < 1e12 ) {
	($n) = map {my $x = $_; $x =~ s/(\.\d\d)\d+/$1/; $x} ($n/1e9);
	return "$n Gbp";
    } elsif ( $n < 1e15 ) {
	($n) = map {my $x = $_; $x =~ s/(\.\d\d)\d+/$1/; $x} ($n/1e12);
	return "$n Tbp";
    } else {
	return "$n bp";
    }
}

=pod

=item * B<get_color_key> ()

Returns the html of the color key used in the progress bars.

=cut

sub get_color_key {
  my ($self) = @_;

  my $keys = [ [ 'not_started', 'not started' ],
	       [ 'queued', 'queued for computation' ],
	       [ 'in_progress', 'in progress' ],
	       [ 'requires_intervention' => 'requires user input' ],
	       [ 'error', 'failed with an error' ],
	       [ 'complete', 'successfully completed' ] ];

  my $html = "<h4>Progress bar color key:</h4>";
  foreach my $k (@$keys) {
    
    my $image = WebGD->new(10, 14);
    my $colors = $self->get_colors($image);
    $image->filledRectangle(0,0,10,14,$colors->{$k->[0]});
    $html .= '<img style="border: none;" src="'.$image->image_src.'"/> '.$k->[1].'<br>';
    
  }

  return $html;
}


=pod

=item * B<get_colors> (I<gd_image>)

Returns the reference to the hash of allocated colors. I<gd_image> is mandatory and
has to be a GD Image object reference.

=cut

sub get_colors {
  my ($self, $image) = @_;
  return { 'white' => $image->colorResolve(255,255,255),
	   'black' => $image->colorResolve(0,0,0),
	   'not_started' => $image->colorResolve(185,185,185),
	   'queued' => $image->colorResolve(30,120,220),
	   'in_progress' => $image->colorResolve(255,190,30),
	   'load_in_progress' => $image->colorResolve(255,190,30),
	   'requires_intervention' => $image->colorResolve(255,30,30),
	   'error' => $image->colorResolve(175,45,45),
	   'complete' => $image->colorResolve(60,165,60),
	 };
}

=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  return [ [ 'login' ], ];
}
