package WebComponent::MapBundle;

use strict;
use warnings;

use base qw( WebComponent );

1;

use File::Temp;

use Conf;
use WebComponent::WebGD;

use WebColors;

=pod

=head1 NAME

ModelMap - Visualization of the reactions in a model

=head1 DESCRIPTION

WebComponent that produces a KEGGMap colored by the reactions in
a list of models

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new
{
    my $self = shift->SUPER::new(@_);
    $self->application->register_component('ModelMap', 'viewmap');
    $self->application->register_component('Ajax', 'ajaxMapBundle');
    $self->application->register_component('Table', 'keggtable');
    $self->application->register_component('TabView', 'keggMapTabs');
    $self->application->register_component('RollerBlind', 'blind');
    return $self;
}

=item * B<output> ()

Returns the html output of the ModelMap component.

=cut

sub output
{
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');

    my $table = $application->component('keggtable');

    my $colors = WebColors::get_palette( 'varied' );

    #Parse CGI params - PLACEHOLDER
    my $model_ids = [];

    if( defined( $cgi->param('model') ) )
    {
        my @models = split( /,/, $cgi->param('model') );
        $model_ids = \@models;
    }


    # Build summary table
    my $tabledata = [];
    my $keggdata = $figmodel->database()->get_table("KEGGMAPDATA");

    for(my $i=0; $i < $keggdata->size(); $i++ )
    {
        my $row = $keggdata->get_row($i);

        # Skip maps with no name or no ID
        next unless( defined( $row->{'ID'} ) && defined( $row->{'NAME'} ) );
        # Skip maps with no compounds and no reactions
        next unless( defined( $row->{'COMPOUNDS'} ) || defined($row->{'REACTIONS'} ) );

        my $component = "ModelMap|viewmap";

        my $rxn_size = 0;
        $rxn_size = @{$row->{'REACTIONS'}} if defined( $row->{'REACTIONS'} );
        my $cpd_size = 0;
        $cpd_size = @{$row->{'COMPOUNDS'}} if defined( $row->{'REACTIONS'} );
        my $ec_size = 0;
        $ec_size = @{$row->{'ECNUMBERS'}} if defined( $row->{'REACTIONS'} );

#        my $name_col =  "<a href=\"javascript:execute_ajax(\'build_map\',\'modelmap_target\',\'pathway=".$row->{'ID'}->[0]."&model=".$cgi->param('model')."\', \'Loading KEGG pathway ".$row->{'ID'}->[0]."...\', 0, \'post_hook\', \'$component\');\">"
#                        .$row->{'NAME'}->[0] . "</a>";

	my $modelSyntax = "";
	if (defined($cgi->param('model'))) {
		$modelSyntax = "&model=".$cgi->param('model');
	}
	my $addTab = "addTab(\'" . $row->{'ID'}->[0] . "\', \'" . $row->{'NAME'}->[0] . "\', \'keggMapTabs\', \'build_map\',\'mapInNewTab=keggMapTabs&pathway=" . $row->{'ID'}->[0] .$modelSyntax. "&component=$component');";
	my $name_col = "<a href=\"javascript:$addTab\">" . $row->{'NAME'}->[0] . "</a>";

        my $rxn_col = "";
        my $cpd_col = "";
        my $ecs_col = "";

        my $j = 0;
        foreach my $model_id (@$model_ids)
        {
        	my $modelobj = $figmodel->get_model($model_id);
            my $model_rxn_table = $modelobj->reaction_table();
            my $model_cpd_table = $modelobj->compound_table();

            next unless (defined( $model_rxn_table)  && defined ($model_cpd_table ));

            my $rgb_string = "rgb(".$colors->[$j][0].",".$colors->[$j][1].",".$colors->[$j][2].")";

            my $model_rxn = 0;
            my $model_cpd = 0;
            my $model_ecs = 0;

            if( defined( $row->{'REACTIONS'} ) )
            {
                foreach( @{$row->{'REACTIONS'}} )
                {
                    if( defined( $model_rxn_table->get_row_by_key( $_, "LOAD" ) ) )
                    {
                        $model_rxn++;
                    }
                }
            }
            if( defined( $row->{'COMPOUNDS'} ) )
            {
                foreach( @{$row->{'COMPOUNDS'}} )
                {
                    if( defined( $model_cpd_table->get_row_by_key( $_, "DATABASE" ) ) )
                    {
                        $model_cpd++;
                    }
                }
            }

            $rxn_col .= " (<b style=\"color:$rgb_string\">$model_rxn</b>)";
            $cpd_col .= " (<b style=\"color:$rgb_string\">$model_cpd</b>)";
            $j++;
        }

    push @$tabledata, [  $name_col,
                        "$rxn_col $rxn_size",
                        "$cpd_col $cpd_size",
                        $ec_size ];

    }

    # Format table and maps
    $table->data($tabledata);
    $table->columns( [  { 'name' => 'Name', 'filter' => 1 },
                        { 'name' => 'Reactions', 'sortable' => 1 },
                        { 'name' => 'Compounds', 'sortable' => 1 },
                        { 'name' => 'EC Numbers', 'sortable' => 1 }
                     ] );

    $table->items_per_page(6);
    $table->show_select_items_per_page(1);
    $table->show_bottom_browse(1);
    $table->width(900);

    my $blind = $application->component('blind');
    $blind->add_blind({ 'title' => "Map Select",
			'content' => "<div style='padding:5px;'>".$table->output()."</div><br>",
			'info' => 'click to show/hide',
			'active' => 1 });
    $blind->width(1000);
    
    my $mapTabs = $application->component('keggMapTabs');
    $mapTabs->dynamic(1);
    #$mapTabs->name('keggMapTabs');

    my $html = $blind->output();
    $html .= "<div style=\"padding:10px; padding-right:20px\">".$self->build_key($model_ids)."</div><br>";
    $html .= $mapTabs->output();

    return $html;
}

sub build_key
{
    my ($self, $model_ids) = @_;

    # Get web objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');

    my $colors = WebColors::get_palette( 'varied' );

    my $key = "";
    if( @$model_ids ){
        $key = "<table>";
        #Start a table.
        # Two rows, one for reactions one for compoudns
        $key .= "<tr><th style=\"background: #ffffff\">Reactions:</th><td style=\"width:5px;\"></td>";

        # Add an entry for each model
        for( my $i=0; $i < @$model_ids; $i++ ){
            my $box = new WebGD( 12, 12 );
            $box->colorResolve( @{$colors->[$i]} );
            my $name = "Unknown";
            my $mdl = $figmodel->get_model($model_ids->[$i]);
            if (defined($mdl)) {
            	$name = $mdl->name();
            }
            $key .= "<td style=\"padding-left:5px\"><img src='".$box->image_src()."'></td><td><a style=\"color:rgb(".$colors->[$i][0].",".$colors->[$i][1].",".$colors->[$i][2].");\">".$name." (". $model_ids->[$i].")</a></td>";
        }

        # Get boxes for each of the compounds colors and gapfilling
        my $red = new WebGD( 12, 12 );
        $red->colorResolve( 255,0,0 );
        my $green = new WebGD( 12, 12 );
        $green->colorResolve( 0,255,0 );
        my $blue = new WebGD( 12, 12 );
        $blue->colorResolve( 0,0,255 );
        my $purple = new WebGD( 12, 12 );
        $purple->colorResolve( 128,0,128 );

        # Add gapfilling, and then start a new row
        $key .= "<td style=\"padding-left:5px\"><img src='".$purple->image_src()."'></td><td><a style=\"color:rgb(128,0,128);\">Gapfilled</a></td></tr>";
        # Add compound row
        $key .= "<tr><th style=\"background:#ffffff;\">Compounds:</th><td style=\"width:5px;\"></td>";
        $key .= "<td style=\"padding-left:5px\"><img src='".$green->image_src()."'></td><td><a style=\"color:rgb(0,255,0);\">Biomass</a></td>";
        $key .= "<td style=\"padding-left:5px\"><img src='".$red->image_src()."'></td><td><a style=\"color:rgb(255,0,0);\">Transported</a></td>";
        $key .= "<td style=\"padding-left:5px\"><img src='".$blue->image_src()."'></td><td><a style=\"color:rgb(0,0,255);\">Represented</a></td></tr>";

        $key .= "</table>";
    }

    return $key;
}
