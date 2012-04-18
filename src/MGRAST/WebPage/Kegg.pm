package MGRAST::WebPage::Kegg;

use base qw( WebPage );

1;

use strict;
use warnings;
use Tracer;
use URI::Escape;

use FIG_Config;

use MGRAST::MGRAST qw( get_menu_metagenome get_public_metagenomes );

=pod

=head1 NAME

Kegg - an instance of WebPage which maps organism data onto a KEGG map

=head1 DESCRIPTION

Map organism data onto a KEGG map

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('KEGG map');
  $self->application->register_component('FilterSelect', 'OrganismSelect');
  $self->application->register_component('FilterSelect', 'MapSelect');
  $self->application->register_component('Hover', 'KeggMapHover');
  $self->application->register_component('ListSelect', 'MGSelect');

  # get metagenome id
  my $id = $self->application->cgi->param('metagenome') || '';

  # set up the menu
  &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

  return 1;
}

=item * B<output> ()

Returns the html output of the Organism page.

=cut

sub output {
    my ($self) = @_;

    # initialize objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $hover = $application->component('KeggMapHover');

    # get a rast master
    my $rast = $application->data_handle('MGRAST');	

    # check if we have a valid fig
    unless ($fig) {
	$application->add_message('warning', 'Invalid organism id');
	return "";
    }

    my $metagenome = $cgi->param('metagenome') || '';
    my $genome = $cgi->param('organism') || $cgi->param('previous_organism') || '';

    # get hash of all accessible organisms, metagenomes
    my $genome_list = $self->all_genome_list($application, $fig, $rast);

    # make sure that the user has access to the comparison organisms
    my %ok_genome = map {$_->[0] => 1} @$genome_list;
    my @comparison_organisms = $cgi->param('sim_display_list_in') || ();
    @comparison_organisms = grep {exists $ok_genome{$_}} @comparison_organisms;

    # limit number of organisms selected for comparison
    if ( @comparison_organisms > 4 ) {
	@comparison_organisms = @comparison_organisms[0..3];
    }

    # load select mg component
    my $MGSelect = $self->application->component('MGSelect');
    $MGSelect->left_header('Columns not in display');
    $MGSelect->right_header('Columns in display');
    $MGSelect->show_reset(1);
    $MGSelect->multiple(1);
    $MGSelect->filter(1);
    $MGSelect->{max_width_list} = 250;
    if ($cgi->param('sim_display_list_in')) {
      $MGSelect->preselection(\@comparison_organisms);
    }
    $MGSelect->name('sim_display_list_in');
    my $gdata = [];
    @$gdata = map { { value => $_->[0], label => $_->[1]." (".$_->[0].")" } } @$genome_list;
    $MGSelect->data($gdata);
    
    my $select_box = $MGSelect->output();

    # set up the menu
    if ( &genome_system($fig, $genome) eq 'mgrast' ) {
	&get_menu_metagenome($self->application->menu, $genome, $self->application->session->user);
    }

    my $base_path = $FIG_Config::kegg_maps || "/vol/biodb/kegg/pathway/map";

    # get all maps with ecs
    my $map_ecs = &map_ecs($application, $base_path);

    # get map number to map name
    my $num_to_name = &map_num_to_name($application, $base_path);
    
    # metabolic top map -- overview of metabolism, no ECs
    my $top_map = '01100';

    # metabolic overview maps below the top map which have maps below them and no ECs
    my @mid_maps = &sub_maps($application, $base_path, $top_map);
    
    # the bottom maps are the ones with pathways and ECs, they can be connected laterally to other bottom maps
    my @bottom_maps = keys %$map_ecs;

    # $kegg_map is the map to be displayed, if necessary, default to highest level KEGG map -- 01100
    my $kegg_map = $cgi->param('map') || '01100';

    my $conf_file = &conf_file($application, $base_path, $kegg_map);

    my %map_to_ec;
    if ( $kegg_map eq $top_map )
    {
	foreach my $mid_map ( @mid_maps )
	{
	    my $mid_conf = &conf_file($application, $base_path, $mid_map);
	    foreach my $bottom_map ( &conf_maps($mid_conf) )
	    {
		foreach my $ec ( @{ $map_ecs->{$bottom_map} } )
		{
		    $map_to_ec{$mid_map}{$ec} = 1;
		}
	    }
	}
    }
    else
    {
	foreach my $bottom_map ( &conf_maps($conf_file) )
	{
	    foreach my $ec ( @{ $map_ecs->{$bottom_map} } )
	    {
		$map_to_ec{$bottom_map}{$ec} = 1;
	    }
	}
    }
    
    my $map_coords = &map_coords($conf_file);
    my $ec_coords  = &ec_coords($application, $base_path, $kegg_map);

    # create the select map component
    my $map_select_component = $application->component('MapSelect');

    my $map_values = [];
    my $map_labels = [];
    # order maps with top map first, followed by mid maps, followed by bottom maps
    foreach my $map ( $top_map, 
		      (sort {uc($num_to_name->{$a}) cmp uc($num_to_name->{$b})} @mid_maps),
		      (sort {uc($num_to_name->{$a}) cmp uc($num_to_name->{$b})} @bottom_maps) )
    {
	my $name = $num_to_name->{$map} || $map;
	push @$map_values, $map;
	push @$map_labels, $name;
    }

    $map_select_component->default($kegg_map);
    $map_select_component->values( $map_values );
    $map_select_component->labels( $map_labels );
    $map_select_component->size(7);
    $map_select_component->name('map');
    
    my $divs = "";
    my $ec_of_org = {};
    my $map_data;
    my $ec_table = '';

    my $hidden;
    my $headline = "<h2>Please select an organism  and a map to display</h2>";
    if ( $genome )
    {
	$hidden .= "<input type='hidden' name='previous_organism' value='$genome'>";

	my %genome_name;
	foreach my $org ( $genome, @comparison_organisms )
	{
	    my $system = &genome_system($fig, $org);

	    my $fignew;
	    if ( $system eq 'seed' ) 
	    {
		$fignew = $fig;
	    }
	    else   # $system is 'rast' or 'mgrast'
	    {
		if ( $org == $fig->{_genome} ) 
		{
		    $fignew = $fig;
		} 
		else 
		{
		    my $rast    = $application->data_handle('MGRAST');
		    my $jobs    = $rast->Job->get_objects( {genome_id => $org, viewable => 1} );
		    my $jobnum  = $jobs->[0]{id};
		    my $job_dir = $FIG_Config::mgrast_jobs;
		    my $org_dir = "$job_dir/$jobnum/rp/$org";
		    $fignew     = new FIGV($org_dir);
		}
	    }

	    $genome_name{$org} = $fignew->genus_species($org);
	    $genome_name{$org} =~ s/_/ /g;

	    my $features = $fignew->all_features_detailed_fast($org);

	    # hack to get function format -- wantarray returns array now, should actually be a scalar
	    my $func_type = ref($features->[0][6]);

	    foreach my $feature (@$features) {
		my $func = ''; 
		if ( $func_type eq 'ARRAY' ) {
		    $func = $feature->[6][1];
		} else {
		    $func = $feature->[6];
		}

		if ( $func )
		{
		    my %seen;
		    foreach my $ec ( $func =~ /EC\s*(\d+\.(?:\d+|-)\.(?:\d+|-)\.(?:\d+|-))/g )
		    {
			next if $seen{$ec}++;

			# store fragment ids (as contig_beg_end) for mgrast, store fids for others (SEED, rast)
			if ( $system eq 'mgrast' ) {
			    push @{ $ec_of_org->{$org}{$ec} }, $feature->[1];
			} else {
			    push @{ $ec_of_org->{$org}{$ec} }, $feature->[0];
			}
			
		    }
		}
	    }
	
	    foreach my $map ( keys %$map_coords )
	    {
		$map_data->{$map}{'n_ecs_in_map'} = scalar keys %{ $map_to_ec{$map} };
		
		if ( $map_data->{$map}{'n_ecs_in_map'} )
		{
		    $map_data->{$org}{$map}{'n_ecs_found'} = grep {exists $ec_of_org->{$org}{$_}} keys %{ $map_to_ec{$map} };
		    $map_data->{$org}{$map}{'ec_pcntg'}    = sprintf "%.1f", ($map_data->{$org}{$map}{'n_ecs_found'} * 100/$map_data->{$map}{'n_ecs_in_map'});
		}
		else
		{
		    $map_data->{$org}{$map}{'n_ecs_found'} = 0;
		    $map_data->{$org}{$map}{'ec_pcntg'}    = '';
		}
	    }
	}

	$headline = "<h2>KEGG map <i>".$num_to_name->{$kegg_map}."</i> for <i>$genome_name{$genome}</i> ($genome)</h2>";

	my $divnum = 0;
	foreach my $ec ( keys %$ec_coords )
	{
	    # add divs for ECs
	    if ( exists $ec_of_org->{$genome}{$ec} )
	    {
		foreach my $location ( @{ $ec_coords->{$ec} } )
		{
		    my ($x1, $y1, $x2, $y2) = @$location;
		    
		    # calculate width and height
		    my $width = $x2 - $x1 - 1;
		    my $height = $y2 - $y1 - 1;

		    # create popup and red div
		    if ( @{ $ec_of_org->{$genome}{$ec} } == 1 )
		    {
			# single id found for this EC
			my $id = $ec_of_org->{$genome}{$ec}[0];

			my($info, $link);
			if ( $id =~ /^fig/ )
			{
			    # RAST or SEED feature
			    my($peg_num) = ($id =~ /fig\|.+peg\.(\d+)/);
 			    $info = "<table><tr><th>$ec</th></tr><tr><td>$peg_num</td></tr></table>";
			    $link = "?page=Annotation&feature=$id";
			}
			else
			{
			    # mg-rast fragment -- contig_beg_end
			    my($frag_id, $beg, $end) = ($id =~ /^(.+)_(\d+)_(\d+)$/);
 			    $info = "<table><tr><th>$ec</th></tr><tr><td>$frag_id</td></tr></table>";
			    $link = "?page=MetagenomeSequence&metagenome=$genome&sequence=$frag_id&subseq_beg=$beg&subseq_end=$end";
			}

			$hover->add_tooltip($ec, $info);
			$divs .= "<div name='posdiv' id='posdiv_$divnum' style='cursor: pointer; border: 1px solid green;opacity: 0.6;-moz-opacity: 0.6;filter: alpha(opacity=60);background-color: green;width: $width;height: $height;position: absolute; left: $x1; top: $y1;' onMouseover='hover(event, \"$ec\");' onclick='window.open(\"$link\", \"kegg\");'></div>";
		    }
		    else
		    {
			# multiple ids found for this EC
			my $title = "EC: $ec";
			my @id_numbers = ();
			my $link;

			if ( $ec_of_org->{$genome}{$ec}[0] =~ /^fig/ )
			{
			    # RAST or SEED features
			    @id_numbers = map {/fig\|.+peg\.(\d+)/; $1} @{ $ec_of_org->{$genome}{$ec} };
			    $link = "?page=MetagenomeFeatureList&title=$title&feature=" . join('&feature=', @{ $ec_of_org->{$genome}{$ec} });
			}
			else
			{
			    # mg-rast fragments -- contig_beg_end
			    @id_numbers = map {/^(.+)_\d+_\d+$/; $1} @{ $ec_of_org->{$genome}{$ec} };
			    $link = "?page=MetagenomeFeatureList&title=$title&metagenome=$genome&feature=" . join('&feature=', @{ $ec_of_org->{$genome}{$ec} });
			}

			my $n_features = scalar @{ $ec_of_org->{$genome}{$ec} };
			my $id_list = join(', ', @id_numbers);
			my $info = "<table><tr><th>$ec ($n_features features)</th></tr><tr><td>$id_list</td></tr></table>";
			$hover->add_tooltip($ec, $info);

			$divs .= "<div name='posdiv' id='posdiv_$divnum' style='cursor: pointer; border: 1px solid green;opacity: 0.6;-moz-opacity: 0.6;filter: alpha(opacity=60);background-color: green;width: $width;height: $height;position: absolute; left: $x1; top: $y1;' onMouseover='hover(event, \"$ec\");' onclick='window.open(\"$link\", \"features\");'></div>";
		    }

		    $divnum++;
		}
	    }
	}
	
	# add divs for maps
	foreach my $map ( keys %$map_coords )
	{
	    my($x1, $y1, $x2, $y2) = @{ $map_coords->{$map} };
	    
	    # calculate width and height
	    my $width = $x2 - $x1 - 1;
	    my $height = $y2 - $y1 - 1;
	    
	    # create popup
	    my $info = "<table><tr><th>$num_to_name->{$map}</th></tr><tr><td>$map_data->{$genome}{$map}{n_ecs_found} ECs found out of $map_data->{$map}{n_ecs_in_map} ($map_data->{$genome}{$map}{ec_pcntg} %)</td></tr></table>";
	    
	    # create red div
	    $hover->add_tooltip( $map, $info );
	    
	    # create blue div
	    $divs .= "<div name='posdiv' id='posdiv_$divnum' style='cursor: pointer; border: 1px solid blue;opacity: 0.6;-moz-opacity: 0.6;filter: alpha(opacity=60);width: $width;height: $height;position: absolute; left: $x1; top: $y1;' onMouseover='hover(event, \"$map\");' onclick='window.open(\"?page=Kegg&map=$map&organism=$genome\", \"kegg\");'></div>";
	    
	    $divnum++;
	}

	if ( scalar keys %$map_coords )
	{
	    # if there are sub-maps (or connecting maps) from the current map, create a table
	    # with some statistics
	    $ec_table = qq(<table><tr><th>KEGG map</th><th>Distinct ECs</th>);
	    
	    foreach my $org ( $genome, @comparison_organisms )
	    {
		$ec_table .= qq(<th>$genome_name{$org}</th>);
	    }
	    
	    $ec_table .= "</tr>\n";
	    
	    foreach my $map ( sort {$num_to_name->{$a} cmp $num_to_name->{$b}} keys %$map_coords )
	    {
		$ec_table .= "<tr><td>$num_to_name->{$map}</td><td>$map_data->{$map}{'n_ecs_in_map'}</td>\n";
		
		foreach my $org ( $genome, @comparison_organisms )
		{
		    # add other organisms into link to preserve comparison
		    my $comp_org_args = '';
		    my @comp_orgs = grep {$_ ne $org} ($genome, @comparison_organisms);
		    if ( @comp_orgs ) {
			$comp_org_args = '&comparison_organism=' . join('&comparison_organism=', @comp_orgs);
		    }
		    
		    my $link = qq(<a href="?page=Kegg&organism=$org$comp_org_args&map=$map">$map_data->{$org}{$map}{'n_ecs_found'}</a>);
		    if ( $map_data->{$org}{$map}{'n_ecs_found'} )
		    {
			my $width1 = sprintf "%.0f", $map_data->{$org}{$map}{'ec_pcntg'};
			my $width2 = 100 - $width1;
			
			$ec_table .= qq(<td><table border="0" width="100" cellspacing="0" cellpadding="0"><tr><td colspan="2">$link ($map_data->{$org}{$map}{'ec_pcntg'} %)</td></tr><tr>) .
			             qq(<td width="$width1" height="5" bgcolor="#00EE00"></td>\n) .
				     qq(<td width="$width2" height="5" bgcolor="#F9F9F9"></td></tr></table></td>\n);
		    }
		    else
		    {
			$ec_table .= qq(<td><table border="0" width="100" cellspacing="0" cellpadding="0"><tr><td>$link</td></tr><tr>) .
			    qq(<td width="100" height="5" bgcolor="#F9F9F9"></td></tr></table></td>\n);
		    }
		}
		
		$ec_table .= "</tr>\n";
	    }
	    $ec_table .= "</table>\n";
	}
    }

    my %comp_org = map{$_ => 1} @comparison_organisms;
    my $select_orgs = qq(<select name="comparison_organism" multiple size="4">\n);
        
    my $form = $self->start_form('comp_form') .
	       qq(<table border="0"><tr>\n) .
	       qq(<th>Select KEGG metabolic map:</th>) .
	       qq(<td>&nbsp;&nbsp;&nbsp;&nbsp;</td>) .
	       qq(<th>Select up to 4 organisms for comparison:</th></tr>\n<tr><td>) .
	       $map_select_component->output() .
	       qq(</td><td></td><td>\n) .
	       $select_box .
	       qq(</td></tr></table>\n) .
	       $hidden .	       
	       "<input type='button' value='Select' onclick='list_select_select_all(\"".$MGSelect->id."\");document.forms.comp_form.submit();'>" . "<br />" .
	       "<input type='hidden' name='metagenome' value='".$metagenome."'>" .
	       $self->end_form() .
	       '<br/>';

    my $link_to_ipath = "";
    my $ecs = [];
    if ($genome && $ec_of_org->{$genome}) {
      @$ecs = keys(%{$ec_of_org->{$genome}});
      @$ecs = map { "E".$_ } @$ecs;
      my $ec_string = join("\n", @$ecs);
      $link_to_ipath .= "<form target='_blank' method='post' action='http://pathways.embl.de/map_modular.cgi'><input type='hidden' name='default_opacity' value='0.3'><input type='hidden' name='default_width' value='3'><input type='hidden' name='bgcolor' value='white'><input type='hidden' name='selection' value='$ec_string'><input type='submit' value='show overview in iPath (external)'></form>"
    }

    my $kegg_map_image = "<img src='kegg_map_image.cgi?map=$kegg_map' id='kegg_map' onload='position_divs(document.getElementById(\"kegg_map\"));'>";
    my $html = $headline . $form . $link_to_ipath . $ec_table . $kegg_map_image . $hover->output() . $divs;
    return $html;
}


sub all_genome_list {
    my($self, $application, $fig, $rast) = @_;
    my @genome_list = ();
    my %org_seen;

    # get the list of public metagenomes
    my $public_metagenomes = [];
    if ( ref $rast ) {
	foreach my $job (@{&get_public_metagenomes($rast)}) {
	    $org_seen{$job->genome_id} = 1;
	    push @$public_metagenomes, [$job->genome_id, $job->genome_name];
	}
    }

    @genome_list = map {$_->[1] = "Public: $_->[1]"; $_} sort {$a->[1] cmp $b->[1]} @$public_metagenomes;

    # check for private genomes (RAST) or metagenomes (MG-RAST)
    # for now, public metagenomes get reported here as private, remove them
    my $private = [];
    my $user = $application->session->user();
    if ($user) {
	
	my $orgs = $user->has_right_to(undef, 'view', 'metagenome');
	
	if (ref($rast)) {
	    # if this is true, the user has at least one right concerning private organisms
	    if (scalar(@$orgs)) {
		
		# check if user has access to all organisms
		if ($orgs->[0] eq '*') {
		    @$orgs = map { $_->genome_id() } @{$rast->Job->get_objects()};
		}
		
		# there is at least one organism
		if (scalar(@$orgs)) {
		    
		    foreach my $org (@$orgs) {
			next if $org_seen{$org};
			my $job = $rast->Job->get_objects( { genome_id => $org, viewable => 1 } );
			my $orgname = "";
			if (scalar(@$job)) {
			    $orgname = $job->[0]->genome_name();
			    push @$private, [$org, $orgname];
			    $org_seen{$org} = 1;
			}
		    }
		}
	    }
	}
    }
    
    push @genome_list, map {$_->[1] = "Private: $_->[1]"; $_} sort {$a->[1] cmp $b->[1]} @$private;
    
    # get the list of public (SEED) genomes
    my $seed_genomes = $fig->genome_list();

    push @genome_list, sort {$a->[1] cmp $b->[1]} @$seed_genomes;
    Trace("KEGG genome list has " . scalar(@genome_list) . " entries.") if T(3);
    return \@genome_list;
}

sub column_metadata {
    my ($self, $genome, $genome_list) = @_;
    my $column_metadata = {};

    foreach my $rec ( @$genome_list )
    {
	my($id, $name) = @$rec;
	
	$column_metadata->{$id} = {'value' => $name};
	if ($id eq $genome) {
#	    $column_metadata->{$id}->{order} = $next_col;
	    $column_metadata->{$id}->{visible} = 1;
	    $column_metadata->{$id}->{group} = 'permanent';
	}
	else{
	    $column_metadata->{$id}->{visible} = 0;
	    $column_metadata->{$id}->{group} = 'metagenomes';
	}
    }

    return $column_metadata;

    my $desc = $self->data('dataset_desc');
    my $metagenome = $self->application->cgi->param('metagenome') || '';
#    my $next_col;

    # add your metagenome to permanent and add the other possible metagenomes to the select listbox
    # check for available metagenomes
    my $rast = $self->application->data_handle('MGRAST');  
    my $available = {};
    my $org_seen;
    if (ref($rast)) {
	my $public_metagenomes = &get_public_metagenomes($self->app->dbmaster, $rast);
	foreach my $pmg (@$public_metagenomes) {
	    $column_metadata->{$pmg->[0]} = {'value' => 'Public - ' . $pmg->[1]};
	    if ($pmg->[0] eq $genome){
#		$column_metadata->{$pmg->[0]}->{order} = $next_col;
		$column_metadata->{$pmg->[0]}->{visible} = 1;
		$column_metadata->{$pmg->[0]}->{group} = 'permanent';
	    }
	    else{
		$column_metadata->{$pmg->[0]}->{visible} = 0;
		$column_metadata->{$pmg->[0]}->{group} = 'metagenomes';
	    }
	    $org_seen->{$pmg->[0]}++;
	}

	if ($self->application->session->user) {
      
	    my $mgs = $rast->Job->get_jobs_for_user($self->application->session->user, 'view', 1);
      
	    # build hash from all accessible metagenomes
	    foreach my $mg_job (@$mgs) {
		next if ($org_seen->{$mg_job->genome_id});
		$column_metadata->{$mg_job->genome_id} = {'value' => 'Private - ' . $mg_job->genome_name,
							  'header' => { name => $mg_job->genome_id,
									filter => 1,
									operators => ['equal', 'unequal', 'less', 'more'],
									sortable => 1,
									width => 150,
									tooltip => $mg_job->genome_name . '(' . $mg_job->genome_id . ')'
									},
									};
		if ( ($mg_job->metagenome) && ($mg_job->genome_id eq $metagenome) ) {
#		    $column_metadata->{$mg_job->genome_id}->{order} = $next_col;
		    $column_metadata->{$mg_job->genome_id}->{visible} = 1;
		    $column_metadata->{$mg_job->genome_id}->{group} = 'permanent';
		}
		else{
		    $column_metadata->{$mg_job->genome_id}->{visible} = 0;
		    $column_metadata->{$mg_job->genome_id}->{group} = 'metagenomes';  
		}
	    }
	}
    }
    else {
    # no rast/user, no access to metagenomes
    }
  
    return $column_metadata;
}


sub map_ecs {
    my($application, $base_path) = @_;
    my(%map_ecs, $line);

    open(TAB, "<$base_path/ec_map.tab") or $application->add_message('warning', "Could not open KEGG file 'ec_map.tab': $!");
    while ( defined($line = <TAB>) )
    {
	chomp $line;
	my($ec, @maps) = split(/\s+/, $line);
	foreach my $map ( @maps )
	{
	    push @{ $map_ecs{$map} }, $ec;
	}
    }
    close(TAB);
    
    return \%map_ecs;
}


sub conf_file {
    my($application, $base_path, $kegg_map) = @_;
    my @lines = ();

    my $conf_file = $base_path . '/map' . $kegg_map . '.conf';

    if ( -f $conf_file )
    {
	open(CONF, "<$conf_file") or $application->add_message('warning', "Could not open KEGG map file for $kegg_map: $!");
	@lines = <CONF>;
	close(CONF);
	
	chomp @lines;
    }

    return \@lines;
}

sub sub_maps {
    my($application, $base_path, $top_map) = @_;
    
    my $conf = &conf_file($application, $base_path, $top_map);
    return &conf_maps($conf);
}

sub conf_maps {
    my($conf_file) = @_;
    my %map;

    foreach my $line ( @$conf_file )
    {
	if ( $line =~ /\/kegg\/pathway\/map\/map(\d+)\.html/ )
	    # or $line =~ /http.+get_linkdb\?pathway\+map(\d+)/ )
	{
	    $map{$1} = 1;
	}
    }

    return keys %map;
}

sub map_num_to_name {
    my($application, $base_path) = @_;
    my($line, %num_to_name);
    
    open(TAB, "<$base_path/../map_title.tab") or $application->add_message('warning', "Could not open KEGG tab file: $!");
    while ( $line = <TAB> ) 
    {
	chomp $line;
	my($num, $name) = split(/\t/, $line);
	$num_to_name{$num} = $name;
    }
    close(TAB);
    
    return \%num_to_name;
}

sub map_coords {
    my($conf) = @_;
    my %coords;

    foreach my $line ( @$conf )
    {
	if ( $line =~ /rect\s\((\d+),(\d+)\)\s+\((\d+),(\d+)\).+map(\d+)\.html/ )
	    # or $line =~ /rect\s\((\d+),(\d+)\)\s+\((\d+),(\d+)\).+http.+get_linkdb\?pathway\+map(\d+)/ )
	{
	    my($x1,$y1,$x2,$y2,$map) = ($1,$2,$3,$4,$5);
	    $coords{$map} = [$x1,$y1,$x2,$y2];
	}
    }

    return \%coords;
}

sub ec_coords {
    my($application, $base_path, $kegg_map) = @_;
    my(%coords, $line);

    my $file = $base_path . '/map' . $kegg_map . '_ec.coord';
    open(COORDS, "<$file") or $application->add_message('warning', "Could not open KEGG file: $!");

    while ( $line = <COORDS> ) 
    {
	chomp $line;
	my($ec, $x1, $y1, $x2, $y2) = split(/\s+/, $line);
	push @{ $coords{$ec} }, [$x1,$y1,$x2,$y2];
    }
    close(COORDS);

    return \%coords;
}

sub genome_system {
    my($fig, $org) = @_;
    my $system = '';
    
    # using FIG is_genome will tell you if the genome_id is a SEED genome
    # mg-rast genome ids begin with 444
    # all other genome ids are RAST
	
    if ( $org =~ /^444\d+\.\d+$/ ) {
	$system = 'mgrast';
    } elsif ( $fig->is_genome($org) ) {
	$system = 'seed';
    } else {
	$system = 'rast'; 
    }

    return $system;
}

sub require_javascript {
  return ["$FIG_Config::cgi_url/Html/PositionDivs.js"];
}
