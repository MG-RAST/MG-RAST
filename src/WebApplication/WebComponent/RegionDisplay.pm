package WebComponent::RegionDisplay;

# RegionDisplay - component for a graphical regions view

use strict;
use warnings;

use FIG;
use FIGV;
use PinnedRegions;
use Conf;
use BasicLocation;
use SeedViewer::SeedViewer;

use Time::HiRes qw( usleep gettimeofday tv_interval );


use base qw( WebComponent );


1;


=pod

=head1 NAME

RegionDisplay - component for a graphical regions view

=head1 DESCRIPTION

WebComponent for a graphical regions view

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);
    
    $self->application->register_component('GenomeDrawer', 'pinned_region_drawer');
    $self->application->register_component('Table',        'pinned_region_table');
    $self->application->register_component('Table',        'region_select_table');
    $self->application->register_component('Table',        'sequence_select_table');
    $self->application->register_component('TabView',      'pinned_region_tabview');
    $self->application->register_component('ToggleButton', 'toggle');
    $self->application->register_component('ListSelect',   'genome_list');
    
    $self->{fig}                    = $self->application->data_handle('FIG');

    $self->{focus}                  = undef;
    $self->{region_size}            = 16000;
    $self->{number_of_regions}      = 4;
    $self->{select_pinned_pegs}     = 'similarity';
    $self->{show_genomes}           = [];
    $self->{number_of_sims}         = 2;
    $self->{number_of_pch_pins}     = 2;
    $self->{collapse_close_genomes} = (defined($Conf::collapse_close_genomes) ?
				       $Conf::collapse_close_genomes :
				       1);
    $self->{sims_from}              = 'blast';
    $self->{sim_cutoff}             = 1e-20;
    $self->{color_sim_cutoff}       = 1e-20;
    $self->{sort_by}                = 'similarity';
    $self->{fast_color}             = 1;
    $self->{graphical_output}       = 1;
    $self->{tabular_output}         = 1;
    $self->{line_select}            = 0;
    $self->{show_genome_select}     = 0;

    $self->{window_size}            = 1000;
    $self->{control_form}           = 'regular';
    
    return $self;
}

=item * B<output> ()

Returns the html output of the RegionDisplay component.

=cut

sub output {
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $self->application->cgi();
    my $fig = $self->fig();

    # get seed user -- for when we need to flip from seed to seedviewer.
    # This should be deleted when SEED is retired, along with all other references to '$seed_user' (MJD)
    # The variable name is set as 'user' to be consistent with SEED pages
    my $seed_user = $cgi->param('user') || '';

    my $region_size = $cgi->param('region_size') || $self->region_size();
    $self->region_size($region_size);

    my @pegs = $cgi->param('feature');

    my $step_peg = {};

    if ( @pegs == 1 )
    {
	my $focus_peg = $pegs[0];
	$self->focus($focus_peg);
	# find neighboring pegs to link the step 'forward' and step 'backward' buttons to.
	# e.g. for the backward peg, link to:
	# a. the peg nearest to the edge of the region window upstream of the focus peg
	# or if no peg is found in the region
	# b. the nearest peg upstream of the focus peg 
	# or if there is no peg
	# c. the empty string ''-- in this case the button will not be displayed
	$step_peg = $self->step_pegs($focus_peg, $region_size);
    }

    my @input_column  = $cgi->param('ic0');
    my @features      = $cgi->param('features');
    my @selected_pegs = ();

    if ( @features and @input_column ) {
	# Used to deselect some regions.
	# 'ic0' and 'features' are paired -- each value of ic0 corresponds to a 
	# particular fid. If the ic0 value is 1/0, the feature is selected/deselected.
	# Taken together they are used to create a new '@pegs' list.
	
	for (my $i = 0; $i < @input_column; $i++)
	{
	    if ( $input_column[$i] ) {
		push @selected_pegs, $features[$i];
	    }
	}

	if ( @selected_pegs <= 1 ) {
	    @selected_pegs = @features;
	}
    }

    my $number_of_regions = $cgi->param('number_of_regions') || $self->number_of_regions();
    $self->number_of_regions($number_of_regions);
    my $select_pinned_pegs = $cgi->param('select_pinned_pegs') || $self->select_pinned_pegs();
    $self->select_pinned_pegs($select_pinned_pegs);

    my $number_of_sims = defined($cgi->param('number_of_sims'))? 
	                   $cgi->param('number_of_sims') :
			     $self->number_of_sims();
    $self->number_of_sims($number_of_sims);

    my $number_of_pch_pins = defined($cgi->param('number_of_pch_pins'))?
                               $cgi->param('number_of_pch_pins') :
			         $self->number_of_pch_pins();
    $self->number_of_pch_pins($number_of_pch_pins);

    my $collapse_close_genomes = defined($cgi->param('collapse_close_genomes'))? 
	                           $cgi->param('collapse_close_genomes') :
				     $self->collapse_close_genomes();
    $self->collapse_close_genomes($collapse_close_genomes);

    my $sims_from              = $cgi->param('sims_from') || $self->sims_from();
    $self->sims_from($sims_from);

    my $show_genomes = [];
    my @cgi_show_genomes = $cgi->param('show_genome');
    if ( @cgi_show_genomes ) {
	$show_genomes = \@cgi_show_genomes;
    } else {
	$show_genomes = $self->show_genomes();
    }
    $self->show_genomes($show_genomes);

    my $sim_cutoff = defined($cgi->param('sim_cutoff'))?
	               $cgi->param('sim_cutoff') :
		         $self->sim_cutoff();
    $self->sim_cutoff($sim_cutoff);

    my $color_sim_cutoff = defined($cgi->param('color_sim_cutoff')) ? 
	                     $cgi->param('color_sim_cutoff') :
			       $self->color_sim_cutoff();
    $self->color_sim_cutoff($color_sim_cutoff);

    my $sort_by = $cgi->param('sort_by') || $self->sort_by();
    $self->sort_by($sort_by);

    my $fast_color = defined($cgi->param('fast_color'))?
	               $cgi->param('fast_color') :
		         $self->fast_color();
    $self->fast_color($fast_color);

    my $control_form = $cgi->param('control_form') || $self->control_form();
    $self->control_form($control_form);

    # set these through object method, not CGI
    my $graphical_output = $self->graphical_output();
    my $tabular_output   = $self->tabular_output();

    # Input can either specify --
    #   a. number of regions and a method to select them by (similarity or PCH pins), or
    #   b. number of sims and number of PCH pins, both can be non-zero
    # a takes priority over b.    
    if ( $number_of_regions and $select_pinned_pegs )
    {
	if ( $select_pinned_pegs eq 'similarity' )
	{
	    $number_of_sims     = $number_of_regions;
	    $number_of_pch_pins = 0;
	}
	else
	{
	    $number_of_sims     = 0;
	    $number_of_pch_pins = $number_of_regions;
	}
    }

    my @pegs_desc;
    if ( @pegs == 1 ) {
	# single 'feature' argument in cgi
	if ( @selected_pegs ) {
	    # show only regions containing the selected pegs
	    @pegs_desc = @selected_pegs;
	} else {
	    # show all regions for this peg
	    @pegs_desc = @pegs;
	}
    } else {
	# multiple 'feature' arguments in cgi -- show regions for these pegs
	@pegs_desc = @pegs;
    }

    my $pin_desc = {
	             'pegs'                   => \@pegs_desc,
		     'collapse_close_genomes' => $collapse_close_genomes, 
		     'n_pch_pins'             => $number_of_pch_pins, 
		     'n_sims'                 => $number_of_sims, 
		     'show_genomes'           => $show_genomes,
		     'sim_cutoff'             => $sim_cutoff, 
		     'color_sim_cutoff'       => $color_sim_cutoff, 
		     'sort_by'                => $sort_by
		   };

    my $add_features = $self->add_features();

    # check if this is an annotator
    my $user = $self->application->session->user();
    my $is_annotator = 0;
    if ($user && user_can_annotate_genome($self->application, "*")) {
      $is_annotator = 1;
    }

    my $maps = &PinnedRegions::pinned_regions($fig, $pin_desc, $fast_color, $sims_from, $region_size, $add_features, $is_annotator);

    my $form = $self->pinned_regions_form(\@pegs, $seed_user, $step_peg);
    if ($self->control_form eq 'none') {
      $form = "";
    }

    if ( $graphical_output && $tabular_output )
    {
	my $image = $self->pinned_regions_image($maps, $seed_user);
	my $table = $self->pinned_regions_table($maps, \@pegs, $seed_user, $is_annotator);
	my $reg_form = $self->region_selection_form($maps, \@selected_pegs, \@features, $seed_user);
	my $seq_form = $self->sequence_selection_form($maps, \@selected_pegs, \@features, $seed_user);

	# check if the user has a preference which tab they want to see first
	my $whichtab = 0;
	if ($user) {
	  my $dbm = $application->dbmaster;
	  if ($dbm) {
	    my $whichtabpref = $dbm->Preferences->get_objects( { user => $user, name => 'ComparedRegionsFocusTab' });
	    if (scalar(@$whichtabpref)) {
	      if ($whichtabpref->[0]->value eq 'tabular') {
		$whichtab = 1;
	      }
	    }
	  }
	}

	my $tv = $self->application->component('pinned_region_tabview');
	$tv->width(800);
	$tv->default($whichtab);
	$tv->add_tab('Visual Region Information',  $image);
	$tv->add_tab('Tabular Region Information', $table);
	unless ($self->line_select) {
	  $tv->add_tab('Select Regions', $reg_form);
	}
	$tv->add_tab('Sequences', $seq_form);
	if ($self->show_genome_select) {
	  my $glist = $self->application->component('genome_list');
	  my $genome_info = $fig->genome_info();
	  my $genomes = [];
	  my $handled = {};
	  foreach my $genome (@$genome_info) {
	    $handled->{$genome->[0]} = 1;
	    push(@$genomes, { value => $genome->[0], label => $genome->[1] });
	  }
	  my $rast = $self->application->data_handle('RAST');
	  if ($rast && $user) {
	    my @jobs = $rast->Job->get_jobs_for_user_fast($user, 'view', 1);
	    foreach my $j (@jobs) {
	      next if $handled->{$j->{genome_id}};
	      push(@$genomes, { value =>  $j->{genome_id}, label => $j->{genome_name} });
	    }
	  }
	  @$genomes = sort { ($b->{label} =~ /^Private\: /) cmp ($a->{label} =~ /^Private\: /) || lc($a->{label}) cmp lc($b->{label}) } @$genomes;
	  $glist->data($genomes);
	  $glist->show_reset(1);
	  $glist->multiple(1);
	  $glist->left_header('available');
	  $glist->right_header('selected');
	  $glist->name('show_genome');

	  my $genome_select = $glist->output().qq~<br><input type='button' value='apply selection' onclick='show_selected_genomes("~ . $glist->id . qq~");'>~;

	  $tv->add_tab('Genome Selection', $genome_select);
	}

	# return the data
	return $form . $tv->output();
    }
    elsif ( $graphical_output )
    {
	my $image = $self->pinned_regions_image($maps, $seed_user);
	return $form . $image;
    }
    elsif ( $tabular_output )
    {
	my $table = $self->pinned_regions_table($maps, \@pegs, $seed_user, $is_annotator);
	return $form . $table;
    }
    else
    {
	return '';
    }
}

sub require_javascript {
    
    return ["$Conf::cgi_url/Html/RegionDisplay.js"];
}

sub pinned_regions_form {
    my($self, $pegs, $seed_user, $step_peg) = @_;

    my $fig = $self->fig();

    # If there is a single input PEG, the pinned region is being displayed, and the complete form
    # should be returned.
    # If there are multiple input PEGs, only regions surrounding these PEGs will be displayed. In this
    # case, some of the form options meaningless and have to be dropped.

    my $control_form = $self->control_form();
    my $application  = $self->application;
    my $toggle       = $application->component('toggle');

    my $default_button = ($control_form eq 'regular')? 0 : 1;
    my $default_style  = ($control_form eq 'regular')? 'display:none' : 'display:inline';

    $toggle->add_button('Regular','regular');
    $toggle->add_button('Advanced','advanced');

    $toggle->default_button($default_button);
    $toggle->toggle_type('action');
    $toggle->action('switch_form');

    my $form;
    my $show_genomes = $self->show_genomes();
    if ( @$show_genomes ) {
	$form = $application->page->start_form('pr_form', {show_genome => $show_genomes, user => $seed_user})."<input type='hidden' id='fid' name='feature' value='".$pegs->[0]."'>";
    } else {
	$form = $application->page->start_form('pr_form', {user => $seed_user})."<input type='hidden' id='fid' name='feature' value='".$pegs->[0]."'>";
    }
    
    $form .= "<div id='pr_genome_sel' style='display: none;'></div>";
    $form .= "<table>" .
	     "<tr><th>Display options</th><td>" . $toggle->output() . "</td></tr>" .
	     "<tr><th>Region Size (bp)</th><td><input type='text' name='region_size' value='".$self->region_size()."'></td></tr>";

    if ( @$pegs == 1 )
    {
	# Include this option only when there is a single input PEG
	$form .= "<tr><th>Number of Regions</th><td><input type='text' name='number_of_regions' value='".$self->number_of_regions()."'></td></tr>";
    } else {
      shift @$pegs;
      foreach my $p (@$pegs) {
	$form .= "<input type='hidden' name='feature' value='$p'>";
      }
    }
    
    if ( @$show_genomes )
    {

	# Create list with genome IDs and organism names
	my @genome_and_name = map {[$_,$fig->orgname_of_orgid($_)]} @$show_genomes;

	# Create list of organism links sorted by organism name
	my @org_links = map {qq(<a href=").$self->svURL.qq(seedviewer.cgi?page=Organism&organism=$_->[0]">$_->[1]</a>)} 
	                  sort {$a->[1] cmp $b->[1]} 
	                    grep {$_->[1]} @genome_and_name;

	$form .= "<tr><th>Organism restrictions</th><td>\n";
	$form .= join(',<br>', @org_links) . "\n</td></tr>\n";
    }
    
    $form .= "</table>";
    $form .= "<table id='region_display_advanced' style='$default_style;'>";

    my($check1, $check2, $check3);
    if ( @$pegs == 1 )
    {
	# Include these options only when there is a single input PEG
	($check1, $check2) = ($self->select_pinned_pegs eq 'similarity')? ('checked', '') : ('', 'checked');
	
	$form .= "<tr><th>Pinned CDS selection</th><td>" .
	         "<input type='radio' name='select_pinned_pegs' value='similarity' $check1> Similarity " .
		 "<input type='radio' name='select_pinned_pegs' value='pch_pin' $check2> PCH pin</td></tr>";
    
	($check1, $check2, $check3) = ($self->collapse_close_genomes() == 1) ? ('checked', '', '') :
	    			      (($self->collapse_close_genomes() == 2) ? ('', 'checked', '') : ('', '', 'checked'));
	$form .= "<tr><th>Genome selection</th><td>" .
	         "<input type='radio' name='collapse_close_genomes' value='1' $check1> Collapse close genomes " .
		 "<input type='radio' name='collapse_close_genomes' value='2' $check2> Collapse identical tax-ids " .
		 "<input type='radio' name='collapse_close_genomes' value='0' $check3> Show all " .
		 " </td></tr>";

	if ( $self->sort_by() eq 'similarity' ) { 
	    ($check1, $check2, $check3) = ('checked', '', '');
	} elsif ( $self->sort_by() eq 'phylogenetic_distance' ) {
	    ($check1, $check2, $check3) = ('', 'checked', '');
	} elsif ( $self->sort_by() eq 'phylogeny' ) {
	    ($check1, $check2, $check3) = ('', '', 'checked'); 
	}
	$form .= "<tr><th>Sort genomes by</th><td>" .
		 "<input type='radio' name='sort_by' value='similarity' $check1> Similarity to input CDS " .
		 "<input type='radio' name='sort_by' value='phylogenetic_distance' $check2> Phylogenetic distance to input CDS " .
	         "<input type='radio' name='sort_by' value='phylogeny' $check3> Phylogeny</td></tr>";

	if ( $self->select_pinned_pegs() eq 'similarity' )
	{
	    $form .= "<tr><th>Evalue cutoff for selection of pinned CDSs</th>" .
		     "<td><input type='text' name='sim_cutoff' value='".$self->sim_cutoff()."'></td></tr>";
	}
    }
    
    $form .= "<tr><th>Evalue cutoff for coloring CDS sets</th>" .
	"<td><input type='text' name='color_sim_cutoff' value='".$self->color_sim_cutoff()."'></td></tr>";
    
    ($check1, $check2) = ($self->fast_color() == 1)? ('checked', '') : ('', 'checked');
    $form .= "<tr><th>Coloring algorithm</th><td>" .
	     "<input type='radio' name='fast_color' value='1' $check1> Fast " .
	     "<input type='radio' name='fast_color' value='0' $check2> Slower (but exact)</td></tr></table>";
    $form .= $application->page->end_form();
    
    # create a button for the chromosomal clusters page if this is an annotator
    my $clusters_button = "";
    my $org = $fig->genome_of($pegs->[0]);
    if ($Conf::anno3_mode || (ref($fig) eq 'FIGV') || ((ref($fig) eq 'FIGM') && exists($fig->{_figv_cache}->{$org}))) {
	# print STDERR ref($self->application->session->user) . " " . $self->application->session->user->has_right(undef, 'annotate', 'genome', $org) . "\n";
      if ($self->application->session->user && user_can_annotate_genome($self->application, $org)) {
	$clusters_button = "<td><input type='button' class='button' value='annotate clusters' onclick='document.getElementById(\"cc_data\").value=table_extract_data(\"".$self->application->component('pinned_region_table')->id."\", \"9~0~more\", 1);document.forms.cc_form.submit();'>".$self->application->page->start_form('cc_form', { page => 'ChromosomalClusters' }, '_blank')."<input type='hidden' name='cc_data' value='' id='cc_data'>".$self->application->page->end_form."</td>";
      }
    }

    $form .= "<br><table width=400><tr>";
    
    if ( $step_peg->{'back2'} ) {
	my $peg_backward = $step_peg->{'back2'};
	$form .= "<td><input type='button' class='button' onclick=\"document.getElementById('fid').value='$peg_backward';document.getElementById('pr_form').submit();\" value='<<'></td>";
    }

    if ( $step_peg->{'backward'} ) {
	my $peg_backward = $step_peg->{'backward'};
	$form .= "<td><input type='button' class='button' onclick=\"document.getElementById('fid').value='$peg_backward';document.getElementById('pr_form').submit();\" value='<'></td>";
    }

    $form .= "<td><input type='button' class='button' id='draw_button' onclick='execute_ajax(\"compared_region\", \"cr\", \"pr_form\");' value='draw'></td>";

    if ( $step_peg->{'forward'} ) {
	my $peg_forward = $step_peg->{'forward'};
	$form .= "<td><input type='button' class='button' onclick=\"document.getElementById('fid').value='$peg_forward';document.getElementById('pr_form').submit();\" value='>'></td>";
    }
    
    if ( $step_peg->{'for2'} ) {
	my $peg_forward = $step_peg->{'for2'};
	$form .= "<td><input type='button' class='button' onclick=\"document.getElementById('fid').value='$peg_forward';document.getElementById('pr_form').submit();\" value='>>'></td>";
    }

    $form .= $clusters_button."</tr></table>";

    return $form;
}

sub commentary_page_form {
    my($self, $pegs, $maps, $seed_user) = @_;

    my $form = qq(<form action="chromosomal_clusters.cgi" method="POST" target="_blank">\n);

    # For now assume not in NMPDR mode
    $form .= qq(<input type="hidden" name="SPROUT" value="" />\n);

    $form .= qq(<input type="hidden" name="request" value="show_commentary" />\n);

    # The SEED commentary page does not seem too concerned about which fid gets to be 'prot',
    # If we have multiple input PEGs, use the first one.
    $form .= qq(<input type="hidden" name="prot" value="$pegs->[0]" />\n);

    $form .= qq(<input type="hidden" name="uni" value="1" />\n);

    $form .= qq(<input type="hidden" name="user" value="$seed_user" />\n);

    for (my $i = $#{$maps}; $i >= 0; $i--) 
    {
	my $map = $maps->[$i];
	my $org = $map->{'org_name'};
	$org =~ s/\s/_/g;

	my %set_occ;
	foreach my $feat ( grep {$_->{'type'} eq 'peg' and $_->{'set_number'}} @{ $map->{'features'} } )
	{
	    my $fid = $feat->{'fid'};
	    my $set = $feat->{'set_number'};

	    $set_occ{$set}++;

	    my $var = join('@', $set, $i, $fid, $org, $set_occ{$set});
	    $form .= qq(<input type="hidden" name="show" value="$var">\n);
	}
    }

    $form .= qq(<br><input type="submit" class="button" name="submit" value="commentary page" target="_new"></form>);

    return $form;
}

sub pinned_regions_image {
    my($self, $maps, $seed_user) = @_;
    return '' if ($self->graphical_output == 0);

    
    my $gd = $self->application->component('pinned_region_drawer');
    $gd->display_titles(1);
    $gd->line_select($self->line_select);
    my $region_size = $self->region_size();

    foreach my $map ( @$maps )
    {
	my $genome     = $map->{'genome_id'};
	my $org_name   = $map->{'org_name'};
	my $contig     = $map->{'contig'};
	my $min        = $map->{'beg'};
	my $mid        = $map->{'mid'};
	my $max        = $map->{'end'};
	my $pin_strand = $map->{'pinned_peg_strand'};
	
	my $features   = $map->{'features'};
	
	my $line_features = [];
	
	foreach my $feature ( @$features )
	{
	    my $fid  = $feature->{'fid'};
	    $fid =~ /(glimmer|critica)/;
	    if ($1) {
	      next if ($1 eq 'glimmer' || $1 eq 'critica');
	    }

	    my $beg1     = $feature->{'beg'};
	    my $end1     = $feature->{'end'};
	    my $func     = $feature->{'function'};
	    my $type     = $feature->{'type'};
	    my $set      = $feature->{'set_number'};
	    my $fc_score = $feature->{'fc_score'} || 0;
	    my $figfam   = $feature->{'figfam'};
	    my $subsystems = $feature->{'subsystems'} || [];
	    my $loc = FullLocation->new($self->{fig}, $genome, $feature->{'location'});
	    my $ln_bp = 0;
	    map { $ln_bp += $_->Length } @{$loc->Locs};
	    my $ln_aa    = int($ln_bp/3);          # should be integer for pegs, but let's make sure
	    my $size     = ($type eq 'peg')? "$ln_bp bp, $ln_aa aa" : "$ln_bp bp";

	    my $color;
	    if ( defined($set) )
	    {
		if ( $set == 1 )
		{
		    $color = 0;
		}
		elsif ( $set >= 1 )
		{
		    $color = $set;
		}
	    }
	    else
	    {
		$color = -1;
	    }
	    
	    $beg1 = &in_bounds($min,$max,$beg1);
	    $end1 = &in_bounds($min,$max,$end1);
	    my($beg1b, $end1b) = ($beg1, $end1);
	    
	    if ( $pin_strand eq '-' ) {
		($end1b, $beg1b) = ($max - $end1 + $min, $max - $beg1 + $min);
	    }
	    
	    my $shape = ($type eq 'peg')? 'arrow' : 'smallbox';
	    if ($type eq 'bs') {
	      $shape = 'bigbox';
	      $color = -2;
	    }

	    my $href;
	    if ( $seed_user ) {
		$href = $self->application->url."?page=Annotation&feature=$fid&user=$seed_user";
	    } else {
		$href = $self->application->url."?page=Annotation&feature=$fid";
	    }
	    
	    push(@$line_features, { 'fc_score' => $feature->{'fc_score'},
		                    'start'    => $beg1b,
				    'end'      => $end1b,
				    'title'    => 'Feature',
				    'type'     => $shape,
				    'zlayer'   => 2,
				    'label'    => $set,
				    'href'     => $href,
				    'description' => [ { title => 'ID', value => $fid },
						       { title => 'Function', value => $func || "" },
						       { title => 'Contig', value => $contig },
						       { title => 'Start', value => $beg1 },
						       { title => 'Stop', value => $end1 },
						       { title => 'Size', value => $size },
						       { title => 'Set',  value => $set } ],
				    'color'    => $color});

	    # Added later because not all PEGs will be in FigFams
	    if ( $figfam )
	    {
		push @{ $line_features->[-1]{'description'} }, { title => 'FigFam',  value => $figfam };
	    }

	    # Added later because not all PEGs will be in subsystems
	    if ( @$subsystems )
	    {
		my $ss_title = (@$subsystems == 1)? 'Subsystem' : 'Subsystems';
		my $ss_text  = join('<br>', map {join(': ', $_->[1], $_->[0])} @$subsystems);
		push @{ $line_features->[-1]{'description'} }, { title => $ss_title,  value => $ss_text };
	    }
	}
	
	# expand number of lines if features overlap
	my $lines = $self->resolve_overlays($line_features);

	# Add background shading if a feature (peg) is functionally coupled to the pinned peg
	foreach my $line ( @$lines )
	{
	    my @shading = ();
	    foreach my $line_feature ( @$line )
	    {
		if ( $line_feature->{'fc_score'} )
		{
		    delete $line_feature->{'fc_score'};

		    # Add functional coupling score in popup
		    push @{ $line_feature->{'description'} }, { title => 'Functional coupling score',  value => $line_feature->{'fc_score'} };

		    # add grey rectangular background shading box with same start and end as current PEG
		    push(@shading, { 'start'   => $line_feature->{'start'},
				     'end'     => $line_feature->{'end'},
				     'type'    => 'bigbox',
				     'zlayer'  => 1,
				     'color'   => -1 } );
		    
		}
	    }

	    # add shading boxes to current line, if any
	    push @$line, @shading;
	}

	my $genome_name = $org_name;
	my $short_name = $genome_name;
	$short_name =~ s/^(\w)\S+/$1\./;
	$short_name = substr($short_name, 0, 15);
	my $config = { 'title' => $genome_name,
		       'short_title' => $short_name,
		       'basepair_offset' => $mid - int($region_size / 2 ),
		       'select_id' => $map->{pinned_peg} };
	my $al_config = { 'basepair_offset' => $mid - int($region_size / 2 ),
			  'no_middle_line'  => 1 };

	$gd->add_line( $lines->[0], $config );
	if (scalar(@$lines) > 1) {
	  my $first = 1;
	  foreach my $add_line (@$lines) {
	    if ($first) {
	      $first = 0;
	      next;
	    }
	    $gd->add_line( $add_line, $al_config );
	  }
	}
    }

    $gd->width(700);
    $gd->window_size($region_size);
    $gd->show_legend(1);

    my $rv = $gd->output();
    unless ($self->control_form eq 'none') {
      $rv = qq~<form name='feat_form' id='feat_form'><input type='button' value='update with selected' onclick='execute_ajax(\"compared_region\", \"cr\", \"feat_form\");'><input type='button' value='uncheck all' id='allornothing' onclick="all_or_nothing(this);">~.$rv.qq~</form>~
    }
    
    return $rv;
}

sub pinned_regions_table {
    my($self, $maps, $pegs, $seed_user, $is_annotator) = @_;

    my $urlBase = $self->application->url;
    return '' if ($self->tabular_output == 0);

    my $preference = $self->application->dbmaster->Preferences->get_objects( { user => $self->application->session->user, name => "DisplayAliasInfo" } );
    my $show_aliases = scalar(@$preference) && $preference->[0]->value() eq "show";
    
    my $fig        = $self->fig();
    my %input_peg  = map {$_ => 1} @$pegs;
    my $table      = $self->application->component('pinned_region_table');
    my $table_data = [];
    # write information into tabular format                                                                               
    foreach my $map ( @$maps )
    {
 	my $org_name   = $map->{'org_name'};
	my $features   = $map->{'features'};
	# my $genome     = $map->{'genome'};
	# my $contig     = $map->{'contig'};
	# my $min        = $map->{'beg'};
	# my $mid        = $map->{'mid'};
	# my $max        = $map->{'end'};
	# my $pin_strand = $map->{'pinned_peg_strand'};


	foreach my $feature ( @$features )
	{
	    # Add left and right locations for sorting
	    ($feature->{left}, $feature->{right}) = sort {$a <=> $b} ($feature->{beg}, $feature->{end});
	}
	
	foreach my $feature ( sort {$a->{left}  <=> $b->{left} or
				    $a->{right} <=> $b->{right} or
				    $a->{fid}   cmp $b->{fid} } @$features )
	{
	    my $fid   =  $feature->{'fid'};
	    $fid      =~ /^fig\|\d+\.\d+\.(.+)/;
	    my $fid_num = $1;
	    
	    my $fid_link;
	    if ( $seed_user ) {
		$fid_link = qq(<a href="$urlBase?page=Annotation&feature=$fid&user=$seed_user">$fid</a>);
	    } else {
 		$fid_link = qq(<a href="$urlBase?page=Annotation&feature=$fid">$fid</a>);
	    }

	    my $cl_link = qq(<input type="button" class="button" onclick="window.top.location=').$self->svURL.qq(?page=HomologClusters&feature=$fid'" value='cluster'>);

	    # Create an entry for the subsystem cell in the table
	    my $ss_cell = '';
	    if ( exists $feature->{'subsystems'})
	    {
		my %seen;
		my $ss_tooltip = '';
		foreach my $rec ( @{ $feature->{'subsystems'} } )
		{
		    my($ss, $index) = @$rec;

		    if ( not $seen{$index}++ )
		    {
			$ss_tooltip .= "$index: $ss<br>\n";
		    }
		}

		my $ss_indices = join(",", sort {$a <=> $b} keys %seen);
		$ss_cell = {data => $ss_indices, tooltip => $ss_tooltip};
	    }

	    # Add a row in the table.

	    if ( $input_peg{$fid} )
	    {
		# Highlight the input peg(s)
		my $color = "#ff3c3c";
		
		if ( ref $ss_cell eq 'HASH' ) {
		    # If the input peg is in a subsystem, highlight it
		    $ss_cell->{highlight} = $color;
		} else {
		    # If the input peg is not in a subsystem, highlight an empty cell
		    $ss_cell = {data => '', highlight => $color},
		}

		my $tdata_row = [ 
				    {data => $org_name, highlight => $color},
				    {data => $fid_link, highlight => $color},
				    {data => $feature->{beg}, highlight => $color},
				    {data => $feature->{end}, highlight => $color},
				    {data => $feature->{size}, highlight => $color},
				    {data => $feature->{strand}, highlight => $color},
				    {data => $feature->{function}, highlight => $color},
				    {data => $feature->{fc_score} ? "<a href='?page=FunctionalCoupling&feature=".$feature->{fc_pin}."&to=".$feature->{fid}."' target=_blank>".$feature->{fc_score}."</a>" : $feature->{fc_score}, highlight => $color},
				    $ss_cell,
				    {data => $feature->{set_number}, highlight => $color},
				    {data => $cl_link, highlight => $color}
				];
		if ($is_annotator) {
		  push(@$tdata_row, {data => $feature->{evcodes}, highlight => $color});
		  if ($show_aliases) {
		    push(@$tdata_row, {data => $feature->{aliases}, highlight => $color});
		  }
		}

		push @$table_data, $tdata_row;
	    }
	    else
	    {
	      my $tdata_row = [ 
			       $org_name,
			       $fid_link,
			       $feature->{beg},
			       $feature->{end},
			       $feature->{size},
			       $feature->{strand},
			       $feature->{function},
			       $feature->{fc_score} ? "<a href='?page=FunctionalCoupling&feature=".$feature->{fc_pin}."&to=".$feature->{fid}."' target=_blank>".$feature->{fc_score}."</a>" : $feature->{fc_score},
			       $ss_cell,
			       $feature->{set_number},
			       $cl_link
			      ];
	      
	      if ($is_annotator) {
		push(@$tdata_row, $feature->{evcodes});
		if ($show_aliases) {
		  push(@$tdata_row, $feature->{aliases});
		}
	      }
	      
	      push @$table_data, $tdata_row;
	    }			       
	}
    }

    $table->show_export_button( { strip_html => 1 } );
    my $columns = [ { name => 'Genome', sortable => 1, filter => 1, operator => 'combobox' },
		    { name => 'ID', sortable => 1 },
		    { name => 'Start', sortable => 1 },
		    { name => 'Stop', sortable => 1 },
		    { name => 'Size (nt)', sortable => 0 },
		    { name => 'Strand', sortable => 0 },
		    { name => 'Function', sortable => 1, filter => 1 },
		    { name => 'FC', sortable => 1, tooltip => 'functionally coupled' },
		    { name => 'SS', sortable => 1, tooltip => 'Subsystems' },
		    { name => 'Set', sortable => 1, filter => 1, operator => 'equal' },
		    { name => 'CL', tooltip => 'Find Clusters from homologous genes' } ];
    if ($is_annotator) {
      push(@$columns, { name => 'Evidence' });
      if ($show_aliases) {
	push(@$columns, { name => 'Aliases', filter => 1 });
      }
    }
    $table->columns( $columns );
    $table->data( $table_data );

    return $table->output();
}

sub sequence_selection_form {
    my($self, $maps, $selected_pegs, $features, $seed_user) = @_;

    # @$features is the list of all the pinned pegs for the input parameters
    # @$selected_pegs is the list of all the pinned pegs *displayed*

    my $fig        = $self->fig();
    my $table      = $self->application->component('sequence_select_table');
    my $table_data = [];

    # assemble the data for the table -- one row for each pinned peg, i.e. each region
    if ( @$selected_pegs and @$features ) 
    {
	my %selected = map {$_ => 1} @$selected_pegs;

	foreach my $pinned_peg ( @$features )
	{
	    my $checked  = $selected{$pinned_peg}? 1 : 0;
	    my $org_name = $fig->org_of($pinned_peg);

	    push @$table_data, [$checked, $org_name, $pinned_peg];
	}
    }
    else
    {
	foreach my $map ( @$maps )
	{
	    my $org_name   = $map->{'org_name'};
	    my $pinned_peg = $map->{'pinned_peg'};
	    push @$table_data, ['1', $org_name, $pinned_peg];
	}
    }

    my $focus_peg = $self->focus();
    foreach my $row ( @$table_data )
    {
	my($checked, $org_name, $pinned_peg) = @$row;
	if ( $checked ) {
	    $checked = qq(<input type="checkbox" name="feature" value="$pinned_peg" checked>);
	} else {
	    $checked = qq(<input type="checkbox" name="feature" value="$pinned_peg">);
	}

	my $peg_link;
	if ( $seed_user ) {
	    $peg_link = qq(<a href="?page=Annotation&feature=$pinned_peg&user=$seed_user">$pinned_peg</a>);
	} else {
	    $peg_link = qq(<a href="?page=Annotation&feature=$pinned_peg">$pinned_peg</a>);
	}

	if ( $focus_peg and $pinned_peg eq $focus_peg )
	{
	    # Highlight the focus peg
	    my $color = "#ff3c3c";
	    $row = [ 
		     {data => $checked, highlight => $color},
		     {data => $org_name, highlight => $color},
		     {data => $peg_link, highlight => $color},
		     ];
	}
	else
	{
	    $row = [$checked, $org_name, $peg_link];
	}
    }

    $table->columns( [ { name => '' },
		       { name => 'Genome' },
		       { name => 'ID' } ] );

    $table->data( $table_data );

    my $application = $self->application();

    my $form = "Use this form to view, download or align sequences<p>\n";
    $form .= $application->page->start_form('sequence_form', {page => 'ShowSeqs', user => $seed_user}, '_blank');
    $form .= $table->output();

    $form .= qq(Sequence type: <input type="radio" name="Sequence" value="DNA Sequence" checked> DNA or <input type="radio" name="Sequence" value="Protein Sequence"> protein<p>\n);

    $form .= qq(If DNA, upstream region <input type="text" name="firstpoint" size=5> to <input type="text" name="secondpoint" size=5> from the start of the gene. Enter a negative number to specify a location downstream of the start. The default is the entire gene.<p>\n);
    
    my $showfastabutton = qq(<input type="submit" class="button" name="ShowFasta" value="Show Fasta">);
    my $downloadbutton  = qq(<input type="submit" class="button" name="Download" value="Download Sequences">);
    my $alignbutton     = qq(<input type="submit" class="button" name="Align" value="Align Sequences">);

    $form .= $showfastabutton . "\n";
    $form .= $downloadbutton  . "\n";
    $form .= $alignbutton     . "\n";

    $form .= $application->page->end_form();

    return $form;
}

sub region_selection_form {
    my($self, $maps, $selected_pegs, $features, $seed_user) = @_;

    # @$features is the list of all the pinned pegs for the input parameters
    # @$selected_pegs is the list of all the pinned pegs *displayed*

    my $fig        = $self->fig();
    my $table      = $self->application->component('region_select_table');
    my $table_data = [];

    # assemble the data for the table -- one row for each pinned peg, i.e. each region
    if ( @$selected_pegs and @$features ) 
    {
	my %selected = map {$_ => 1} @$selected_pegs;

	foreach my $pinned_peg ( @$features )
	{
	    my $checked  = $selected{$pinned_peg}? 1 : 0;
	    my $org_name = $fig->org_of($pinned_peg);

	    push @$table_data, [$checked, $org_name, $pinned_peg];
	}
    }
    else
    {
	foreach my $map ( @$maps )
	{
	    my $org_name   = $map->{'org_name'};
	    my $pinned_peg = $map->{'pinned_peg'};
	    push @$table_data, ['1', $org_name, $pinned_peg];
	}
    }

    my $focus_peg = $self->focus();
    foreach my $row ( @$table_data )
    {
	my $pinned_peg = $row->[2];

	my $peg_link;
	if ( $seed_user ) {
	    $peg_link = qq(<a href="?page=Annotation&feature=$pinned_peg&user=$seed_user">$pinned_peg</a>);
	} else {
	    $peg_link = qq(<a href="?page=Annotation&feature=$pinned_peg">$pinned_peg</a>);
	}
	$peg_link .= qq(<input type="hidden" name="features" value="$pinned_peg">);

	$row->[2] = $peg_link;

	if ( $focus_peg and $pinned_peg eq $focus_peg )
	{
	    # Highlight the focus peg
	    my $color = "#ff3c3c";
	    my($checked, $org_name, $peg_link) = @$row;
	    $row = [ 
		     {data => $checked, highlight => $color},
		     {data => $org_name, highlight => $color},
		     {data => $peg_link, highlight => $color},
		     ];
	}
    }

    $table->columns( [
		       { name => '', 'input_type' => 'checkbox' },
		       { name => 'Genome' },
		       { name => 'ID' } 
		      ] );

    $table->data( $table_data );

    my $application = $self->application();

    my $form = "Use the form below to deselect regions<p>\n";
    $form .= $application->page->start_form('reg_form', {user => $seed_user});
    $form .= $table->output();

    if ( $focus_peg ) {
	$form .= qq(<input type="hidden" name="feature" value="$focus_peg">);
    }

    $form .= qq^<input type="button" onclick='table_submit("1", "reg_form", "1", "1"); execute_ajax("compared_region", "cr", "reg_form");' value="update graphic with selected regions"/>\n^;

    $form .= $application->page->end_form();

    return $form;
}

# helper functions
sub in_bounds {
    my($min,$max,$x) = @_;

    if     ($x < $min)     { return $min }
    elsif  ($x > $max)     { return $max }
    else                   { return $x   }
}

# data r/w methods
sub fig {
  my ($self, $fig) = @_;

  if (defined($fig)) {
    $self->{fig} = $fig;
  }

  return $self->{fig};
}

sub focus {
  my ($self, $focus) = @_;

  if (defined($focus)) {
    $self->{focus} = $focus;
  }

  return $self->{focus};
}

sub region_size {
  my ($self, $region_size) = @_;

  if (defined($region_size)) {
    $self->{region_size} = $region_size;
  }

  return $self->{region_size};
}

sub number_of_regions {
  my ($self, $number_of_regions) = @_;

  if (defined($number_of_regions)) {
    $self->{number_of_regions} = $number_of_regions;
  }

  return $self->{number_of_regions};
}

sub select_pinned_pegs {
  my ($self, $select_pinned_pegs) = @_;

  if (defined($select_pinned_pegs)) {
    $self->{select_pinned_pegs} = $select_pinned_pegs;
  }

  return $self->{select_pinned_pegs};
}

sub number_of_sims {
  my ($self, $number_of_sims) = @_;

  if (defined($number_of_sims)) {
    $self->{number_of_sims} = $number_of_sims;
  }

  return $self->{number_of_sims};
}

sub number_of_pch_pins {
  my ($self, $number_of_pch_pins) = @_;

  if (defined($number_of_pch_pins)) {
    $self->{number_of_pch_pins} = $number_of_pch_pins;
  }

  return $self->{number_of_pch_pins};
}

sub show_genomes {
  my ($self, $show_genomes) = @_;

  if ( $show_genomes and @$show_genomes ) {
    $self->{show_genomes} = $show_genomes;
  }

  return $self->{show_genomes};
}

sub sort_by {
  my ($self, $sort_by) = @_;

  if (defined($sort_by)) {
    $self->{sort_by} = $sort_by;
  }

  return $self->{sort_by};
}

sub select_genomes {
  my ($self, $select_genomes) = @_;

  if (defined($select_genomes)) {
    $self->{select_genomes} = $select_genomes;
  }

  return $self->{select_genomes};
}

sub fast_color {
  my ($self, $fast_color) = @_;

  if (defined($fast_color)) {
    $self->{fast_color} = $fast_color;
  }

  return $self->{fast_color};
}

sub collapse_close_genomes {
  my ($self, $collapse_close_genomes) = @_;

  if (defined($collapse_close_genomes)) {
    $self->{collapse_close_genomes} = $collapse_close_genomes;
  }

  return $self->{collapse_close_genomes};
}

sub sims_from {
  my ($self, $sims_from) = @_;

  if (defined($sims_from)) {
    $self->{sims_from} = $sims_from;
  }

  return $self->{sims_from};
}

sub sim_cutoff {
  my ($self, $sim_cutoff) = @_;

  if (defined($sim_cutoff)) {
    $self->{sim_cutoff} = $sim_cutoff;
  }

  return $self->{sim_cutoff};
}

sub color_sim_cutoff {
  my ($self, $color_sim_cutoff) = @_;

  if (defined($color_sim_cutoff)) {
    $self->{color_sim_cutoff} = $color_sim_cutoff;
  }

  return $self->{color_sim_cutoff};
}

sub graphical_output {
  my ($self, $graphical_output) = @_;

  if (defined($graphical_output)) {
    $self->{graphical_output} = $graphical_output;
  }

  return $self->{graphical_output};
}

sub tabular_output {
  my ($self, $tabular_output) = @_;

  if (defined($tabular_output)) {
    $self->{tabular_output} = $tabular_output;
  }

  return $self->{tabular_output};
}

sub control_form {
  my ($self, $control_form) = @_;

  if (defined($control_form)) {
    $self->{control_form} = $control_form;
  }

  return $self->{control_form};
}

sub add_features {
  my ($self, $add_features) = @_;

  if (defined($add_features)) {
    $self->{add_features} = $add_features;
  }

  return $self->{add_features};
}


sub resolve_overlays {
  my ($self, $features) = @_;

  my $lines = [ [ ] ];
  foreach my $feature (@$features) {
    my $resolved = 0;
    my $fs = $feature->{start};
    my $fe = $feature->{end};
    if ($fs > $fe) {
      my $x = $fs;
      $fs = $fe;
      $fe = $x;
    }
    foreach my $line (@$lines) {
      my $conflict = 0;
      foreach my $item (@$line) {
	my $is = $item->{start};
	my $ie = $item->{end};
	if ($is > $ie) {
	  my $x = $is;
	  $is = $ie;
	  $is = $x;
	}
	if ((($fs < $ie) && ($fs > $is)) || (($fe < $ie) && ($fe > $is)) || (($fs < $is) && ($fe > $ie))){
	  $conflict = 1;
	  last;
	}
      }
      unless ($conflict) {
	push(@$line, $feature);
	$resolved = 1;
	last;
      }
    }
    unless ($resolved) {
      push(@$lines, [ $feature ]);
    }
  }

  return $lines;
}

sub step_pegs {
    my($self, $focus_peg, $region_size) = @_;
    
    my($peg_backward, $peg_forward, $peg_backward_double, $peg_forward_double) = ('', '', '', '');
    my $fig = $self->fig();
    
    # get genome, contig, begin and end of the focus peg
    my $g = $fig->genome_of($focus_peg);
    my ($contig,$beg,$end) = $fig->boundaries_of($fig->feature_location($focus_peg));

    # calculate the middle of the current region
    my $fmid = int($beg + (($end - $beg) / 2));
    my $rbeg =  $fmid - $region_size;
    my $rend = $fmid + $region_size;
    if ($rbeg < 1) {
      $rbeg = 1;
    }

    # get all features within the doubled size of the current region and record their midpoints
    my ($fids, undef, undef) = $fig->genes_in_region($g, $contig, $rbeg, $rend);
    my $features = [];
    foreach my $f (@$fids) {
      my ($fcontig,$fbeg,$fend) = $fig->boundaries_of($fig->feature_location($f));
      push(@$features, [ $f, int($fbeg + (($fend - $fbeg) / 2))]);
    }

    # sort features by midpoint
    @$features = sort { $a->[1] <=> $b->[1] } @$features;
    my $num = scalar(@$features);
    if ($num) {

      # set first and last feature of the enlarged region as back-full-window and forward full window
      $peg_backward_double = $features->[0]->[0];
      $peg_forward_double = $features->[$num - 1]->[0];

      # calculate the positions at 1/4th and 3/4th of the enlarged region
      my $quarter = (($rend - $rbeg) / 4);
      my $q2 = int($rbeg + $quarter);
      my $q3 = int($rbeg + ($quarter * 3));

      # find the features whose midpoint is closest to 1/4th and 3/4th and set them as
      # backward-half-window and forward-half window
      my $q2min = 9999999;
      my $q3min = 9999999;
      foreach my $f (@$features) {
	if (abs($f->[1] - $q2) < $q2min) {
	  $q2min = abs($f->[1] - $q2);
	  $peg_backward = $f->[0];
	}
	if (abs($f->[1] - $q3) < $q3min) {
	  $q3min = abs($f->[1] - $q3);
	  $peg_forward = $f->[0];
	}
      }

      # if the focus is the first / last peg in the contig, point the movers to the previous / next contig
      if (($features->[0]->[0] eq $focus_peg) || ($features->[scalar(@$features) - 1]->[0] eq $focus_peg)) {
	my @contigs = sort $fig->all_contigs($g);
	if (scalar(@contigs) > 1) {
	  my $cindex = -1;
	  for (my $i=0; $i<scalar(@contigs); $i++) {
	    if ($contigs[$i] eq $contig) {
	      $cindex = $i;
	      last;
	    }
	  }
	  if (($features->[0]->[0] eq $focus_peg) && ($cindex > 0)) {
	    my $ncontig = $contigs[$cindex - 1];
my $len = $fig->contig_ln($g, $ncontig);
	    my @flocs = map { [$_, $fig->boundaries_of($fig->feature_location($_))] } @{($fig->genes_in_region($g, $ncontig, $len - 5000, $len))[0]};
	    my $mloc = $len - 5000;
	    my $mfeat;
	    foreach my $f (@flocs) {
	      if ($f->[3] > $mloc) {
		$mfeat = $f->[0];
	      }
	    }
	    $peg_backward = $mfeat;
	    $peg_backward_double = $mfeat;
	  }
	  if (($features->[scalar(@$features) - 1]->[0] eq $focus_peg) && ($cindex < scalar(@contigs) - 1)) {
	    my $ncontig = $contigs[$cindex + 1];
	    my @flocs = map { [$_, $fig->boundaries_of($fig->feature_location($_))] } @{($fig->genes_in_region($g, $ncontig, 0, 5000))[0]};
	    my $mloc = 5001;
	    my $mfeat;
	    foreach my $f (@flocs) {
	      if ($f->[2] < $mloc) {
		$mfeat = $f->[0];
	      }
	    }
	    $peg_forward = $mfeat;
	    $peg_forward_double = $mfeat;
	  }
	}
      }
    }

#     # first try finding pegs within the region
#     my $regions  = &PinnedRegions::define_regions($fig, $region_size * 2, [$focus_peg]);
#     my $region   = $regions->[0];

#     my $features = $regions->[0]{features};

#     # RAST genomes are not getting back a sorted list from genes_in_region
#     # this hack fixes this
#     #
#     # NB when deleting this code don't miss the second segment further down
#     ##########################################################################################
#     # BEGIN: hack to sort features -- delete if genes_in_region is returning sorted features #
#     ##########################################################################################
#     my %mid_pt;
#     foreach my $feature ( @$features )
#     {
#         my $loc = $fig->feature_location($feature);
#         if ($loc) 
# 	{
#             my($contig, $beg, $end) = $fig->boundaries_of($loc);
# 	    $mid_pt{$feature} = $beg + $end;  # don't bother dividing by 2, this value only used for sorting
# 	}
#     }

#     $features = [ sort {$mid_pt{$a} <=> $mid_pt{$b}} @$features ];
    
#     ##########################################################################################
#     # END: hack to sort features -- delete if genes_in_region is returning sorted features   #
#     ##########################################################################################

#     # search for a region peg upstream of and farthest away from the focus peg
#     foreach my $fid ( @$features ) {
# 	if ( $fig->ftype($fid) eq 'peg' ) {
# 	    last if ($fid eq $focus_peg);
# 	    $peg_backward_double = $fid;
# 	    last;
# 	}
#     }

#     # search for a region peg downstream of and farthest away from the focus peg
#     for (my $i = $#{ $features }; $i >= 0; $i--) {
# 	my $fid = $features->[$i];
# 	if ( $fig->ftype($fid) eq 'peg' ) {
# 	    last if ($fid eq $focus_peg);
# 	    $peg_forward_double = $fid;
# 	    last;
# 	}
#     }

#     my $l = $fig->feature_location($focus_peg);
#     my $s = 0;
#     my $e = 0;
#     if ($l) {
#       my($contig, $beg, $end) = $fig->boundaries_of($l);
#       my $middle = $beg + (($end - $beg) / 2);
#       $s = $middle - $region_size;
#       $e = $middle + $region_size;
#     }
    
#     @$features = map { ($mid_pt{$_} > $s && $mid_pt{$_} < $e) ? $_ : () } @$features;

#     # search for a region peg upstream of and farthest away from the focus peg
#     foreach my $fid ( @$features ) {
# 	if ( $fig->ftype($fid) eq 'peg' ) {
# 	    last if ($fid eq $focus_peg);
# 	    $peg_backward = $fid;
# 	    last;
# 	}
#     }

#     # search for a region peg downstream of and farthest away from the focus peg
#     for (my $i = $#{ $features }; $i >= 0; $i--) {
# 	my $fid = $features->[$i];
# 	if ( $fig->ftype($fid) eq 'peg' ) {
# 	    last if ($fid eq $focus_peg);
# 	    $peg_forward = $fid;
# 	    last;
# 	}
#     }

#     # If one of the pegs is not found, take a large region, and find the peg closest to the focus peg
#     # within this region.
#     # This could happen if the region size is set very low, or there is an RNA operon or a long string
#     # of non-pegs in the region. 
#     # It will also happen for the first and last pegs on a contig. 
#     # It should not need to be done for the majority of cases, so the performance hit is acceptable.
#     if ( $peg_backward eq '' or $peg_forward eq '' )
#     {
# 	my $regions  = &PinnedRegions::define_regions($fig, 100000, [$focus_peg]);
# 	my $region   = $regions->[0];
# 	my $features = $regions->[0]{features};

# 	##########################################################################################
# 	# BEGIN: hack to sort features -- delete if genes_in_region is returning sorted features #
# 	##########################################################################################
# 	my %mid_pt;
# 	foreach my $feature ( @$features )
# 	{
# 	    my $loc = $fig->feature_location($feature);
# 	    if ($loc) 
# 	    {
# 		my($contig, $beg, $end) = $fig->boundaries_of($loc);
# 		$mid_pt{$feature} = $beg + $end;  # don't bother dividing by 2, this value only used for sorting
# 	    }
# 	}

# 	$features = [ sort {$mid_pt{$a} <=> $mid_pt{$b}} @$features ];
    
# 	##########################################################################################
# 	# END: hack to sort features -- delete if genes_in_region is returning sorted features   #
# 	##########################################################################################
	
# 	my $i;
# 	for ($i = 0; $i < @$features; $i++) {
# 	    last if ($features->[$i] eq $focus_peg);
# 	}
	
# 	if ( $peg_backward eq '' )
# 	{
# 	    for (my $j = ($i-1); $j >= 0; $j--) {
# 		my $fid = $features->[$j];
# 		if ( $fig->ftype($fid) eq 'peg' ) {
# 		    # first peg upstream to the focus peg
# 		    $peg_backward = $fid;
# 		    last;
# 		}
# 	    }
# 	}
	
# 	if ( $peg_forward eq '' )
# 	{
# 	    for (my $j = ($i+1); $j < @$features; $j++) {
# 		my $fid = $features->[$j];
# 		if ( $fig->ftype($fid) eq 'peg' ) {
# 		    # first peg downstream to the focus peg
# 		    $peg_forward = $fid;
# 		    last;
# 		}
# 	    }
# 	}
#     }

    return {'backward' => $peg_backward, 'forward' => $peg_forward, 'back2' => $peg_backward_double, 'for2' => $peg_forward_double };
}
    
sub line_select {
  my ($self, $ls) = @_;

  if (defined($ls)) {
    $self->{line_select} = $ls;
  }

  return $self->{line_select};
}

sub show_genome_select {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_genome_select} = $show;
  }

  return $self->{show_genome_select};
}
