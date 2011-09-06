package MGRAST::WebPage::ModelView;

use base qw( WebPage );

1;

use strict;
use warnings;
use Tracer;
use URI::Escape;

use Global_Config;
use FIGMODEL;

use WebComponent::WebGD;
use WebColors;

use MGRAST::MetagenomeAnalysis;
use MGRAST::Metadata;
use MGRAST::MGRAST qw( get_menu_metagenome get_settings_for_dataset dataset_is_phylo dataset_is_metabolic get_public_metagenomes );

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

    $self->title('Model View');
    $self->application->register_component('Ajax', 'headerajax');

    $self->application->register_component('TabView', 'optionsbox');
    $self->application->register_component('TabView', 'contentbox');
    $self->application->register_component('TabView', 'tabletabs');

    $self->application->register_component('RollerBlind', 'overviewblind');
    $self->application->register_component('RollerBlind', 'mapblind');
    $self->application->register_component('RollerBlind', 'datatableblind');
    $self->application->register_component('RollerBlind', 'controlblind');
    $self->application->register_component('RollerBlind', 'fbablind');

    $self->application->register_component('FilterSelect', 'compareselect' );

    $self->application->register_component('ReactionTable', 'rxnTbl');
    $self->application->register_component('GeneTable', 'geneTbl');
    $self->application->register_component('CompoundTable', 'cpdTbl');

    $self->application->register_component('MapBundle', 'testbundle' );
    $self->application->register_component('ModelSelect', 'testmodelselect' );

    $self->application->component('rxnTbl')->base_table()->preferences_key("ModelView_rxnTbl");
    $self->application->component('cpdTbl')->base_table()->preferences_key("ModelView_cpdTbl");

    return 1;
}

=item * B<output> ()

=cut

sub output {
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');
    my $ajax = $application->component('headerajax');

    # set up the menu
    my $id = $cgi->param('model');
    $id =~ s/MGRast//;
    &get_menu_metagenome($self->application->menu, $id, $self->application->session->user);

    # Add an Ajax header
    my $html = $ajax->output();

    #Getting the list of public genomes
    my $PublicGenomeHash;
    my $genome_info = $fig->genome_info();
    foreach my $genome (@{$genome_info}) {
        $PublicGenomeHash->{$genome->[0]} = 1;
    }

    #Getting the user ID
    my $UserID = "NONE";
    if (defined($self->application->session->user)) {
      $UserID = $self->application->session->user->login;
    }

    # Process parameters
    my $model_ids = [];
    if( defined( $cgi->param('model') ) ) {
        my $NoAccessModels;
        my @models = split( /,/, $cgi->param('model') );
        # Filtering the model list based on the user's rights
        foreach my $Model (@models) {
            my $ModelData = $figmodel->GetModelData($Model);
            if (defined($ModelData) && defined($ModelData->{"ORGANISM ID"}->[0])) {
                my $OrganismID = $ModelData->{"ORGANISM ID"}->[0];
                #Checking if the user has access to the genome
                if ($figmodel->ViewModelPermission($Model,$UserID)) {
                    push(@{$model_ids},$Model);
                } else {
                    push(@{$NoAccessModels},$Model);
                }
            }
        }
        if (defined($NoAccessModels)) {
            $html .= "<p>User does not have the rights to view the models: ".join(",",@{$NoAccessModels})."</p>\n";
        }
    }

    # Use a hidden form to pass parameters, add/remove models, etc.
    $html .= "<form method='get' id='modelviewparams' action='?' enctype='multipart/form-data'>\n";
    $html .= "  <input type='hidden' id='model' name='model' value='" . join(",",@{$model_ids}) . "'>\n";
    $html .= "  <input type='hidden' id='page' name='page' value='ModelView'>\n";
    $html .= "  <input type='hidden' id='tab' name='tab' value='".($cgi->param('tab') || 0)."'>\n";
    $html .= "</form>\n";

    my $pnum = "00020";
    if( defined( $cgi->param('pathway') ) ) {
        $pnum = $cgi->param('pathway');
    }

    # Print the top of the ModelView page
    if( @$model_ids ) {
        $html .= $self->model_overview_content($model_ids);
    } else {
        $html .= $self->db_overview_content($model_ids);
    }

    # Add a KEGG Map blind
    my $mapblind = $application->component('mapblind');
    $mapblind->width( '85%' );
    my $onload = "onload=\"javascript:execute_ajax(\'output\',\'MapDiv\',\'model=".$cgi->param('model')."&pathway=".$pnum."\',\'Loading...\',0,\'post_hook\',\'MapBundle|testbundle\');\"";
    $mapblind->add_blind(   {   title => '<b>Maps (click to view)</b>',
                                content => '<div style="height:1000px;width40px;padding:10px;" id="MapDiv">'.'<img src="'.$Global_Config::cgi_url.'/Html/clear.gif" '.$onload.'>test</div>'
                            } );
    $html .= $mapblind->output().'<br>';

    # Build data tabs for the tables section
    my $tabletabs = $application->component( 'tabletabs' );
    $tabletabs->add_tab( '<b>Reactions</b>', '', ['output', "models=".$cgi->param('model'), 'ReactionTable|rxnTbl']);
    $tabletabs->add_tab( '<b>Compounds</b>', '', ['output', "models=".$cgi->param('model'), 'CompoundTable|cpdTbl']);
    $tabletabs->default(0);

    if( @$model_ids ){
        #$tabletabs->add_tab( '<b>Genes</b>', '', ['output', "models=".$cgi->param('model'), 'GeneTable|geneTbl']);
    }

    $tabletabs->width('100%');

    if( defined( $cgi->param('tab') ) ){
        #$tabletabs->default( $cgi->param('tab') )
    }

    # Add a blind for a future FBA component
    my $fbablind = $application->component('fbablind');
    $fbablind->width( '85%' );
    $fbablind->add_blind(   {   title => '<b>Flux Balance Analysis Controls <small>  (Coming soon)</small></b>',
                                content => '<div style="padding:10px;" id="FBADiv">Coming soon: a control panel making it '
                                            .'possible to run a variety of flux balance analysis studies '
                                            .'on all currently selected models.</div>'
                            } );

    $html .= $fbablind->output().'<br>'.$tabletabs->output();

    return $html;
}

sub require_javascript {
    return ["$Global_Config::cgi_url/Html/ModelView.js"];
}

sub model_overview_content
{
    my ($self, $model_ids) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');

    #Format a compare/download box
    my ($title_string, $overview ) = $self->generate_model_overview($model_ids);

    my $mselect = $self->application->component('testmodelselect');
    $mselect->{"_MGRAST select"} = 1;

    my $content = "<table style=\"padding:10px;\"><tr><td width=\"50%\">$overview</td>";
    $content .= "<td style=\"width:50px\"><!-- This just fills space! --></td>";
    $content .= "<td><div style=\"border: 1px solid #5da668;padding:-15px;\">".$mselect->output("Select a model to view.")."</div></td></tr></table>";

    # Wrap overview and compare/download in a blind
    my $overview_blind = $application->component('overviewblind');
    $overview_blind->width('95%');
    $overview_blind->add_blind({'title' => $title_string,
                                'content' => $content,
                                'active' => 1
                                });


    return $overview_blind->output(). '<br>';
}


sub db_overview_content
{
    my ($self, $model_ids) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');

    my $mselect = $self->application->component('testmodelselect');
    $mselect->{"_MGRAST select"} = 1;

    my $content = "<table style=\"padding:10px;\"><tr>";

    my ($title_string, $overview) = $self->generate_db_overview();

    # Format a nice little overview that de-emphasizes the DB statistics table
    # Replace the filter_select_content with a modelselect component later
    $content .= "<td style=\"width:400px;\">You have arrived at the Biochemistry and Model database of the MGRAST framework for genome annotation. You can select a specific model for viewing using the model select box (right), or you can browse all the database compounds and reactions in the tables below.<br><br> $overview</td>";
    $content .= "<td style=\"width:50px\"><!-- This just fills space! --></td>";
    $content .= "<td style=\"border: 1px solid #5da668;\">".$mselect->output("Select a model to view.")."</td>";
    $content .= "</tr></table>";

    # Wrap it in a blind
    my $overview_blind = $application->component('overviewblind');
    $overview_blind->width('95%');
    $overview_blind->add_blind({'title' => $title_string,
                                'content' => $content,
                                'active' => 1
                                });


    return $overview_blind->output().'<br>';
}

sub generate_model_overview {
    my ($self, $model_ids) = @_;

    my $mgrast = $self->application->data_handle('MGRAST');
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');
    my $colors = WebColors::get_palette( 'varied' );
    my $sbml_link = "http://bioseed.mcs.anl.gov/~chenry/SBMLModels/";
    my $model_string = "<tr><th style='width: 80px;'>Model ID</th>";
    my $org_string = "<tr><th style='width: 80px;'>Dataset name</th>";
    my $version_string = "<tr><th style='width: 80px;' >Version</th>";
    my $source_string = "<tr><th style='width: 80px;' >Source</th>";
    my $class_string = "<tr><th style='width: 80px;'>Class</th>";
    my $tax_string = "<tr><th style='width: 80px;' >Biome/taxonomy</th>";
    my $size_string = "<tr><th style='width: 80px;' >Size</th>";
    my $cds_string = "<tr><th style='width: 80px;' >Coding sequences (CDS)</th>";
    my $rxn_string = "<tr><th style='width: 80px;' >Reactions mapped to CDS </th>";
    my $gfill_string = "<tr><th style='width: 80px;' >Gapfilling Reactions</th>";
    my $cpd_string = "<tr><th style='width: 80px;' >Compounds</th>";
    my $download_string = "<tr><th style='width: 80px;' >Download</th>";
    my $remove_string = "<tr><td style='width: 80px; padding-top:5px'>";

    if( @$model_ids > 1 ) {
        $remove_string .= "<small>(<a href=\"javascript:removeAllModels();\">clear all</a>)</small></td>";
    } else {
        $remove_string .= "</td>";
    }
    my $mddb;
    my $mgmodeldata;

    for (my $i=0; $i < @$model_ids; $i++) {
        # Generate a color key for the rest of the page
        my $box = new WebGD( 12, 12 );
        $box->colorResolve( @{$colors->[$i]} );
        #Loading summary data for the models
        my $model_id = $model_ids->[$i];
        my $model_data = $figmodel->database()->get_row_by_key("MODELS",$model_id,"id");
        my $model_name = "Unknown";
        my $version = $self->version_select( $model_id );
        my $genome_id = $model_data->{genome}->[0];
        my $size = "NA";
        my $class = "Other";
        my $total_genes = "NA";
        my $genes_with_rxn = "NA";
        my $total_rxn = "NA";
        my $gapfilling = "NA";
        my $rxn_with_genes = "NA";
        my $taxonomy = "NA";
        my $cpds = "NA";
        #Loading metagenome stats
        if ($model_data->{source}->[0] eq "MGRAST") {
            if (!defined($mddb)) {
                $mddb = MGRAST::Metadata->new();
                my $results = $mddb->_handle()->Search->get_objects({});
                foreach (@$results){
                    $mgmodeldata->{$_->job()->genome_id} = $_;
                }
            }
            my $mgdata = $mgrast->Job->get_objects( { 'genome_id' => $genome_id } );
            my $model_tbl = $figmodel->database()->GetDBModel($model_id);
            my $model_compounds = $figmodel->database()->GetDBModelCompounds($model_id);
            $gapfilling = 0;
            my $spontaneous = 0;
            $genes_with_rxn = 0;
            for (my $i=0; $i < $model_tbl->size(); $i++) {
                my $row = $model_tbl->get_row($i);
                if (!defined($row->{"ASSOCIATED PEG"}->[0]) || $row->{"ASSOCIATED PEG"}->[0] !~ m/peg/) {
                    if ($row->{"ASSOCIATED PEG"}->[0] =~ m/SPONTANEOUS/) {
                        $spontaneous++;
                    } else {
                        $gapfilling++;
                    }
                } else {
                    for (my $j=0; $j < @{$row->{"CONFIDENCE"}}; $j++) {
                        my @ecores = split(/;/,$row->{"CONFIDENCE"}->[$j]);
                        $genes_with_rxn += @ecores;
                    }
                }
            }
            # Get summary data for metagenome
            if (defined($mgdata->[0])) {
                if (defined($mgmodeldata->{$genome_id}) && defined($mgmodeldata->{$genome_id}->biome())) {
                    $taxonomy = $mgmodeldata->{$genome_id}->biome();
                }
                $total_genes = $mgdata->[0]->genome_contig_count;
                if (!defined($total_genes)) {
                    $total_genes = "NA";
                }
                $model_name = $mgdata->[0]->genome_name;
                $size = $mgdata->[0]->size;
                while($size =~ s/(\d+)(\d{3})+/$1,$2/){
                    #Do nothing
                };
            }
            $total_rxn = $model_tbl->size();
            $rxn_with_genes = $model_tbl->size() - $spontaneous - $gapfilling;
            $cpds = $model_compounds->size();
        } else {
            # Get model stats from reaction db
            my $stats = $figmodel->GetModelStats( $model_id );
            # Get summary data from stats table
            $model_name = $stats->{'Organism name'}->[0];
            $class = $stats->{'Class'}->[0];
            $total_genes = $stats->{'Total genes'}->[0];
            $genes_with_rxn = $stats->{'Genes with reactions'}->[0];
            $total_rxn = $stats->{'Number of reactions'}->[0];
            $gapfilling = $stats->{'Gap filling reactions'}->[0];
            $rxn_with_genes = $total_rxn - $gapfilling - $stats->{'Spontaneous'}->[0] - $stats->{'Growmatch reactions'}->[0] - $stats->{'Biolog gap filling reactions'}->[0];
            $cpds = $stats->{'Metabolites'}->[0];
            $taxonomy = $fig->taxonomy_of($genome_id);
            $taxonomy = "NA" unless( defined( $taxonomy) );
            $size = $fig->genome_szdna($genome_id);
            if( defined( $size) ) {
                while($size =~ s/(\d+)(\d{3})+/$1,$2/){
                    #Do nothing
                };
            } else {
                $size = "NA";
            }
        }
        while($genes_with_rxn =~ s/(\d+)(\d{3})+/$1,$2/){
            #Do nothing
        };
        while($total_genes =~ s/(\d+)(\d{3})+/$1,$2/){
            #Do nothing
        };
        while($rxn_with_genes =~ s/(\d+)(\d{3})+/$1,$2/){
            #Do nothing
        };
        while($total_rxn =~ s/(\d+)(\d{3})+/$1,$2/){
            #Do nothing
        };
        while($cpds =~ s/(\d+)(\d{3})+/$1,$2/){
            #Do nothing
        };
        #Adding data column to the overview table
        $model_string .= "<td><img src='".$box->image_src()."'>&nbsp;".$model_id."</td>";
        $org_string .= "<td> ".$model_name." (<a href=?page=Organism&organism=".$model_data->{genome}->[0].">".$model_data->{genome}->[0]."</a>)</td>";
        $version_string .= "<td>".$version."</td>";
        if( $model_data->{source}->[0] =~ m/PMID(\d+)/ ){
            $source_string .= "<td><a href=http://www.ncbi.nlm.nih.gov/pubmed/".$1.">".$model_data->{source}->[0]."</a></td>";
        }else{
            $source_string .= "<td>".$model_data->{source}->[0]."</td>";
        }
        $class_string .= "<td>".$class."</td>";
        $tax_string .= "<td>".$taxonomy."</td>";
        $size_string .= "<td>".$size." bp</td>";
        $cds_string .= "<td title='Model genes/Total genes'>" . $genes_with_rxn. "/".$total_genes. "</td>";
        $rxn_string .= "<td title='Reactions with genes/Total reactions'>" .  $rxn_with_genes ."/".$total_rxn . "</td>";
        $gfill_string .= "<td title='Gap filling reactions/Total reactions'>" . $gapfilling ."/".$total_rxn. "</td>";
        $cpd_string .= "<td>" .$cpds . "</td>";
        $download_string .= "<td><small><a  href='$sbml_link".$model_id.".xml'>$model_id.xml</a></small></td>";
        $remove_string .= "<td style='padding-top:5px;'>"."<small>(<a href='javascript:removeModelParam(\"".$model_id."\")'>remove</a>)</small>"."</td>";
    }

    #Setting the title string
	my $title_string;
    if( @$model_ids == 1 ) {
        $title_string .=  "<b>Model Overview Page</b>";
    } else {
        $title_string .= "<b>Model Comparison Page</b>";
    }

    # Format model overview table
    my $model_overview = "<div><table>";
    $model_overview .= $model_string . "</tr>";
    $model_overview .= $org_string . "</tr>";
    $model_overview .= $version_string . "</tr>";
    $model_overview .= $source_string . "</tr>";
    $model_overview .= $class_string . "</tr>";
    $model_overview .= $tax_string . "</tr>" unless (@$model_ids > 1 );
    $model_overview .= $size_string . "</tr>";
    $model_overview .= $cds_string . "</tr>";
    $model_overview .= $rxn_string . "</tr>";
    $model_overview .= $gfill_string . "</tr>";
    $model_overview .= $cpd_string . "</tr>";
    $model_overview .= $download_string . "</tr>";
    $model_overview .= $remove_string . "</tr>";
    $model_overview .= "</table></div>";

    return ($title_string, $model_overview);
}

sub generate_db_overview {
    my ($self) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');

    my $title_string = "<h3>Database Overview</h3>";

    my $source_string = "<tr><th style='width: 100px;' >Database </th>";
    my $mdl_string = "<tr><th style='width: 100px;'>Total Models</th>";
    my $rxn_string = "<tr><th style='width: 100px;'>Total Reactions</th>";
    my $cpd_string = "<tr><th style='width: 100px;' >Total Compounds</th>";

    my $stats_table = $figmodel->database()->GetDBTable( 'MODEL STATS' );
    my $rxn_table = $figmodel->database()->GetDBTable( 'REACTIONS' );
    my $cpd_table = $figmodel->database()->GetDBTable( 'COMPOUNDS' );

    $source_string .= "<td> SEED </td>";
    $mdl_string .= "<td>" . $stats_table->size() . "</td>";
    $rxn_string .= "<td>" . $rxn_table->size() . "</td>";
    $cpd_string .= "<td>" . $cpd_table->size() . "</td>";

    my $db_overview = "<div><table>";
    $db_overview .= $source_string . "</tr>";
    $db_overview .= $mdl_string . "</tr>";
    $db_overview .= $rxn_string . "</tr>";
    $db_overview .= $cpd_string . "</tr>";
    $db_overview .= "</table></div>";

    return ($title_string, $db_overview);
}

sub download_box_content {
    my ($self, $model_ids) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');

    my $sbml_link = "http://bioseed.mcs.anl.gov/~chenry/SBMLModels/";
    my $download_string = '<div style="padding-left: 5px; padding-right: 5px; text-align: justify;">';
    $download_string .= "The SEED provides downloads of viewable models in SBML format for off-site use.<br><br>";

    my $stats_table = $figmodel->database()->GetDBTable( 'MODEL STATS' );

    if( @$model_ids ) {
        foreach my $model_id ( @$model_ids ) {
            my $row = $stats_table->get_row_by_key( $model_id , 'Model ID' );
            my $model_name = $row->{'Organism name'}->[0];
            $download_string .= "<a href='$sbml_link".$model_id.".xml'>$model_name ($model_id)</a><br><br> ";
        }
    } else {
        $download_string .= "The SEED provides downloads of model data in SBML format. ";
        $download_string .= "Once you have selected a model, check here for a download link.";
    }

    return $download_string;
}

sub version_select {
    my ($self, $model_id) = @_;

    my $application = $self->application();
    my $cgi = $application->cgi();
    my $fig = $application->data_handle('FIG');
    my $figmodel = $application->data_handle('FIGMODEL');

    my $get_model_data = $figmodel->GetModelData( $model_id );
    my $base_name = $get_model_data->{'MODEL ID'}->[0];

    my @version_list = @{$figmodel->versions_of_model( $model_id )};
    my $current = $figmodel->version_of_model( $model_id );

    # Start select tag
    my $html = "<select onchange=\"changeModelVersion( \'$model_id\',\'$base_name\' + this.value );\">";

    foreach( @version_list ){
        $html .= "<option value=\"$_\" ";
        if( $current =~ /$_/ ){
            $html .= "selected=\"selected\" ";
        }
        $html .= ">$_ </option>";
    }
    $html .= "</select>";
    return $html;
}

sub available_metagenomes {
    my ($self) = @_;

    my $mg_list = {};

    # check for available metagenomes
    my $mgrast = $self->application->data_handle('MGRAST');
    if (ref($mgrast)) {
        my ($public_metagenomes) = $mgrast->get_public_metagenomes();
        foreach my $pmg (@$public_metagenomes) {
            $mg_list->{$pmg->genome_id()} = $pmg;
        }

        if ($self->application->session->user) {
            my $mgs = $mgrast->Job->get_jobs_for_user($self->application->session->user, 'view', 1);
            # build hash from all accessible metagenomes
            foreach my $mg_job (@$mgs) {
                $mg_list->{$mg_job->genome_id()} = "private - " . $mg_job->genome_name();
            }
        }
    }

    return $mg_list;
}
