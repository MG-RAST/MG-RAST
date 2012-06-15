package WebComponent::MFBAController;
use warnings;
use URI::Escape;
use File::Path;
use base qw( WebComponent );
1;

=pod
=head1 NAME
MFBAController - Metabolic Flux-Balance Analysis Controller
=head1 DESCRIPTION
A web-component to setup and run MFBAs.
=head1 METHODS
=over 4
=item * B<new> ()
Called when the object is initialized. Expands SUPER::new.
=cut

sub new {
	my $self = shift->SUPER::new(@_);
    $self->application->register_component('JSCaller', 'fba_jscaller');
	$self->application->register_component('FilterSelect','mediaFilterSelect');
	$self->application->register_component('Table','resultsTable');
	$self->{ajax} = undef;
	return $self;
}

=item * B<output> ()
Returns the html output of the Table component.
=cut

sub output {
	my ($self) = @_;
	return '';
}

sub outputFluxControls {
	my ($self)      = @_;
	my $application = $self->application();
	my $cgi = $application->cgi();
	my $model       = $application->data_handle('FIGMODEL');

	# User must be logged in to view models
	my $html = "<img src='./Html/clear.gif' onLoad='EM.addEvent(\"modelChange\",".
               '["outputFluxControls", "mfbaControls", "MFBAController|mfba_controller"]);\'/>';
	unless (defined( $application->session() ) and defined( $application->session()->user() ) ) {
		$html .= "You must login to run fluxes on models.";
	}
	if ( defined( $cgi->param('model') ) ) {
	    $html .= '<form id="MFBAconfig" enctype="multipart/form-data" method="post">';
	    $html .= '<input type="hidden" name="method" value="Single Growth"/>';
		$html .= "<input type='hidden' name='model' value='".$cgi->param('model')."'/>";
        $html .= '<table><tr valign=middle><td><b>Select <a href="javascript:tab_view_select(\'4\',\'5\');">media condition</a>:</b></td>';
        $html .= '<td>' . $self->media_select_box() . '</td><td>';
        $html .= '<input type="button" value="Run" onClick="FBArun(\'MFBAconfig\');"/></td></tr></table></form>';
	} else {
		$html .= "You must first select one or more models before FBA can be run.";
	}

#    <style type='text/css'>
#        .MFBAbound {
#            margin: 0 auto;
#            padding: 10px;
#        }
#
#        .MFBAclear {
#            clear: both;
#        }
#
#        .MFBAconfigureSet {
#            margin: 0 auto 10px;
#            padding: 0 0 10px;
#        }
#        .MFBAtrioSettings {
#            width: 30%;
#            float: left;
#            padding: 0 10px;
#        }
#        .MFBAduoSettings {
#            width: 45%;
#            float: left;
#            padding: 0 10px;
#        }
#        .MFBAsingleSettings {
#            width: 100%;
#            float: left;
#            padding: 0 10px;
#        }
#        .MFBAfileSettings {
#            float: right;
#            padding: 10px 10px 0;
#        }
#
#        .MFBAlistOf{
#            font-family: monospace;
#        }
#
#       .MFBAconfigure > input{
#            padding: 10 20px;
#        }
#    </style>
#<div class="MFBAbound">
#
#        <div class="MFBAtrioSettings"><h4>Select the simulation type:</h4>
#            <p><input type='radio' name='method' value='Single Growth'/>Single growth</p>
#            <p><input type='radio' name='method' value='singleKO'/>Single KO simulation <small> (aprox. 15 sec) </small></p>
#            <p><input type='radio' name='method' value='fluxVar'/>Flux variability analysis</p>
#        </div>
#        <div class="MFBAduoSettings">
#            <h4>Reactions knocked out from organism(s)</h4>
#            <div class='MFBAlistOf'>No reactions added yet. In the reaction
#            table, check the box under the column 'KO' to knock that
#            reaction out.</div>
#        </div>
#        <div class="MFBAduoSettings">
#            <h4>Reactions knocked out from organism(s)</h4>
#            <div class='MFBAlistOf'>No reactions added yet. In the reaction
#            table, check the box under the column 'KO' to knock that
#            reaction out.</div>
#        </div>
#    <div style='clear: both;'></div>
#    <div class="MFBAfileSettings"> <input type='button' name='save' value='Save to file'/></div>
#    <div style='clear: both;'></div>
#  </div>
#  <div class="MFBAconfigureSet">
#        <div class="MFBAduoSettings">&nbsp;</div>
#        <div class="MFBAduoSettings">
#            <h4>Load configuration from file:</h4>
#            <input type='file' name='configFile' size='40' value='Load from file'/>
#            <input type='button' name='parse' size='40' value='Parse file'/>
#        </div>
#        <div style='clear: both;'></div>
#  </div>
#  <div id='MFBAdummy' style='visibility:hidden;'></div>
#  <h2>Results</h2>
#  <form id="MFBAview">
#  <div style='padding: 0 0 10px;'>
#<div class='MFBAresultsTable' id='MFBAresults' >
#$html .= $self->loadResultsTable();
#$html .= "</div></div></form></div></div>";
	return $html;
}

sub outputResultsTable {
	my ($self) = @_;
	my $app = $self->application();
	unless (defined( $app->session() ) and defined( $app->session()->user() ) ) {
		return "You must login to view flux results.";
	}
	my $html = "<div id='fbaResultsTable'>".$self->loadResultsTable()."</div>";
	return $html;
}

sub loadResultsTable {
	my ($self) = @_;
	my $application = $self->application();
	my $cgi = $application->cgi();
	my $username = "anonymous";
	if (defined( $self->application->session()->user() ) ) {
		$username = $self->application->session()->user()->login();
	}
	my $figmodel = $application->data_handle('FIGMODEL');
	
	my $resultsTable = $application->component('resultsTable');
	$resultsTable->width(960);
	$resultsTable->columns([{ name => 'Select', filter => 0, sortable => 0 },
		{ name => 'Time',   filter => 0, sortable => 1 },
		{ name => 'Model',  filter => 1, sortable => 1 },
		{ name => 'Method', filter => 1, sortable => 1 },
		{ name => 'Media',  filter => 1, sortable => 1 },
		#{ name => 'cpxKO', filter => 1, sortable => 0},
		#{ name => 'rxnKO', filter => 1, sortable => 0},
		{ name => 'Growth', filter => 1, sortable => 0 }]);
	
	my $html;
	my $objects;
	my $fluxdb = $figmodel->database()->get_object_manager("fbaresult");
	if (defined($fluxdb)) {
		$objects = $fluxdb->get_objects({owner => $username});
	}
	if (defined($objects) && @{$objects} > 0) {
		my @modelRuns;
		for (my $i=0; $i < @{$objects}; $i++) {
			my $checkbox = '<input type="checkbox" value="'.$objects->[$i]->model().'_'.$objects->[$i]->_id().'"/>';
			if ($objects->[$i]->growth() eq "0") {
				$checkbox = '<input type="checkbox" class="noGrowth" value="'.$objects->[$i]->model().'_'.$objects->[$i]->_id().'"/>';
			}
			push(@modelRuns,[$checkbox,$objects->[$i]->time(),$objects->[$i]->model(),$objects->[$i]->method(),$objects->[$i]->media(),$objects->[$i]->results()]);
		}
		@modelRuns = sort { $b->[1] cmp $a->[1] } @modelRuns;
		for ( my $i = 0 ; $i < @modelRuns ; $i++ ) {
			$modelRuns[$i]->[1] = $self->_timestamp( $modelRuns[$i]->[1] );
		}
		# Build each row in the table... with checkbox and "SHOW" button
		$resultsTable->data( \@modelRuns );
		$resultsTable->show_top_browse(0);
		$resultsTable->show_bottom_browse(0);
		$resultsTable->show_select_items_per_page(0);
		#my $tabViewer = $application->component('tabletabs');
		#my $rxnId = $tabViewer->id() . "_content_1";
		#my $cpdId = $tabViewer->id() . "_content_2";
		#my $geneId = $tabViewer->id() . "_content_3";
		#my $componentId = "MFBAController|" . $self->{_id};
		$resultsTable->items_per_page( '' . @modelRuns );
		$html .= "<form id='FBAview'>".$resultsTable->output()."</form>".
            "<input type='button' value=\"View Selected Results\" onClick=\"FBAview('FBAview','4_tab_1','4_tab_4','4_tab_2','');\"/>".
            "<input type='button' value=\"Delete Selected Results\" onClick=\"FBAdelete('FBAview');\"/>";
        #    "<input type='button' onClick=\"FBAview('FBAview', '".$rxnId."', '".$geneId."', '".$cpdId.
		#	"', '".$componentId."');\" value=\"View Selected Results\"/>".
        #    "<input type='button' value=\"Delete Selected Results\" onClick=\"FBAdelete('FBAview');\"/>";
	} else {
		$html .= "<p>No results yet. Generate results with using the 'Run Flux Balance' pane inside 'Selected Models/FBA'.</p>";
	}
	return $html;
}

sub delete_results {
	my ($self) = @_;
	my $application = $self->application();
	my $username = "anonymous";
	if (defined($application->session()->user())) {
		$username = $application->session()->user()->login();
	}
	my $figmodel = $application->data_handle('FIGMODEL');
	if (defined($application->cgi()->param('fluxIds'))) {
		my $fluxdb = $figmodel->database()->get_object_manager("fbaresult");
		if (defined($fluxdb)) {
			my @fluxIds = split( /,/, $application->cgi()->param('fluxIds') );
			foreach my $fluxId (@fluxIds) {
				my @tempArray = split(/_/,$fluxId);
				$objects = $fluxdb->get_objects({_id => $tempArray[1]});
				if (defined($objects->[0])) {
					$objects->[0]->delete();
				}
			}
		}
	}
	return $self->loadResultsTable();
}

sub addColumnToCpdTable {
	my ( $self, $modelRunId ) = @_;
	my $application = $self->application();
	unless ( defined( $application->component('cpdTbl') ) ) {
		return;
	}
	my $cpdTbl = $application->component('cpdTbl');
}

sub FBArun {
	my ($self) = @_;
	my $username = "anonymous";
	if (defined( $self->application->session()->user() ) ) {
		$username = $self->application->session()->user()->login();
	}
	my $cgi    = $self->application->cgi();
	my $figmodel  = $self->application->data_handle('FIGMODEL');
	my $models = $cgi->param('model');
	my $media  = $cgi->param('media');
	my $pegKO  = $cgi->param('pegKO');
	my $rxnKO  = $cgi->param('rxnKO');
	my $method = $cgi->param('method');
	$method = "SINGLEGROWTH";
	unless (defined($models) and defined($media) and defined($method) ) {
		return '';
	}
	# models, media, cpdKO and rxnKO are comma deliminated lists
	$models = [split(/,/,$models)];
	$media =  [split(/,/,$media)];
	if (defined($pegKO)) {$pegKO = [\split( /,/, $pegKO )];}
	if (defined($rxnKO)) {$rxnKO = [\split( /,/, $rxnKO )];}
	#Running the FBA simulation using the fast fba software
    warn "RUN FBA Simulation $username $method $rxnKO $pegKO" . join(',', @$models) ." ". join(',',@$media);
	my $jobArray;
	for (my $i=0; $i < @{$models}; $i++) {
		my $mdl = $figmodel->get_model($models->[$i]);
		if (defined($mdl)) {
			my $fba = $mdl->fba();
			if (!defined($pegKO->[$i])) {
				$pegKO->[$i] = "none";
			}
			if (!defined($rxnKO->[$i])) {
				$rxnKO->[$i] = "none";
			}
			$fba->setWebFBASimulation({user => $username,media => [$media->[0]],pegKO => [[$pegKO->[$i]]],rxnKO => [[$rxnKO->[$i]]]});
			push(@{$jobArray},$fba->queueFBAJob({nohup => 1}));
		}
	}
	my $continue = 1;
	my $fba = $figmodel->fba();
	my $done;
	while ($continue) {
		$continue = 0;
		sleep(1);
		for (my $i=0; $i < @{$jobArray}; $i++) {
			if (!defined($done->{$jobArray->[$i]})) {
				my $results = $fba->returnFBAJobResults({jobid => $jobArray->[$i],nohup => 1});
				if ($results->{status} ne "complete") {
					$continue = 1;
				} else {
					$done->{$jobArray->[$i]} = 1;		
				}
			}
		}
	}
	return $self->loadResultsTable;
}

sub rxn_columns {
	my ($self)      = @_;
	my $username = "anonymous";
	if (defined( $self->application->session()->user() ) ) {
		$username = $self->application->session()->user()->login();
	}
	my $cgi = $self->application->cgi();
	my $figmodel = $self->application->data_handle('FIGMODEL');
	if (!defined($cgi->param('fluxIds')) && !defined($cgi->param('models'))) {
		return [];
	}
	#Getting flux IDs
	my $fluxNum = 1;
	my $fluxColumns;
	my $modelString = $cgi->param('models');
	my @fluxIds = split( /,/, $cgi->param('fluxIds') );
	my $fluxdb = $figmodel->database()->get_object_manager("fbaresult");
	my $allRxnHash;
	foreach my $fluxId (@fluxIds) {
		my @tempArray = split(/_/,$fluxId);
		my $objects = $fluxdb->get_objects({_id => $tempArray[1]});
		if (defined($objects->[0])) {
			my $mdlObj = $figmodel->get_model($objects->[0]->model());
			my $rxnTbl = $mdlObj->reaction_table();
			#Getting flux data
			my $fluxHash;
			if ($objects->[0]->growth() > 0) {
				my @fluxes = split(/;/,$objects->[0]->flux());
				for (my $i=0; $i < @fluxes; $i++) {
					my @temp = split(/:/,$fluxes[$i]);
					$fluxHash->{$temp[0]} = $temp[1];
				}
				@fluxes = split(/;/,$objects->[0]->drainFlux());
				for (my $i=0; $i < @fluxes; $i++) {
					my @temp = split(/:/,$fluxes[$i]);
					$fluxHash->{$temp[0]} = $temp[1];
				}
			}
			#Populating flux columns of the reaction table
			my $data;
			for (my $i=0; $i < $rxnTbl->size(); $i++) {
				$allRxnHash->{$rxnTbl->get_row($i)->{LOAD}->[0]} = 1;
				my $lower = -100;
				my $upper = 100;
				if ($rxnTbl->get_row($i)->{DIRECTIONALITY}->[0] eq "=>") {
					$lower = 0;
				} elsif ($rxnTbl->get_row($i)->{DIRECTIONALITY}->[0] eq "<=") {
					$upper = 0;
				}
				if (defined($fluxHash->{$rxnTbl->get_row($i)->{LOAD}->[0]})) {
					$data->{$rxnTbl->get_row($i)->{LOAD}->[0]} = "<span title='".$lower." ".$upper."'>".$fluxHash->{$rxnTbl->get_row($i)->{LOAD}->[0]}."</span>";
				} else {
					$data->{$rxnTbl->get_row($i)->{LOAD}->[0]} = "<span title='".$lower." ".$upper."'>0</span>";
				}
			}
			push( @{$fluxColumns},{name => 'Flux #'.$fluxNum,filter => 1,sortable => 1,data => $data});
			$fluxNum++;
		}
	}
	my @rxns = keys(%{$allRxnHash});
	for (my $i=0; $i < @rxns; $i++) {
		for (my $j=0; $j < @{$fluxColumns}; $j++) {
			if (!defined($fluxColumns->[$j]->{data}->{$rxns[$i]})) {
				$fluxColumns->[$j]->{data}->{$rxns[$i]} = "Not in model";
			}
		}
	}
    my $data = [];
    for (my $i=0; $i < @$fluxColumns; $i++) {
        push(@$data, $fluxColumns->[$i]->{'data'});
        delete $fluxColumns->[$i]->{'data'};
    }
    my $caller = $self->application()->component('fba_jscaller');
    $caller->call_function_args("MVTables['rxntable'].addColumns", [ $fluxColumns, $data ]);
    return;
}

sub cpd_column {
	my ($self) = @_;
	my $app    = $self->application();
	my $cpdTbl = $app->component('CompoundTable');
	my $cgi    = $app->cgi();
	my $run    = $cgi->param('run');
	my $num    = $cgi->param('num');
	$num += 9;
	unless ( defined($run) and defined($num) and defined($cpdTbl) ) {
		return '';
	}

	# load table from  file
	# read cpd results
	my $data = [];

	# generate column output
	my $col = { name => 'Somename', num => $num, filter => 1, sortable => 1 };
	return $cpdTbl->format_new_column_data( $col, $data );
}

sub gene_column {
	my ($self)  = @_;
	my $app     = $self->application();
	my $geneTbl = $app->component('GeneTable');
	my $cgi     = $app->cgi();
	my $run     = $cgi->param('run');
	my $num     = $cgi->param('num');
	$num += 7;
	unless ( defined($run) and defined($num) and defined($geneTbl) ) {
		return '';
	}

	# load table from  file
	# read gene results
	my $data = [];

	# generate column output
	my $col = { name => 'Somename', num => $num, filter => 1, sortable => 1 };
	return $geneTbl->format_new_column_data( $col, $data );
}

#This function creates the filter select control for selecting an FBA media
sub media_select_box {
	my ($self) = @_;
	my $figmodel = $self->application()->data_handle('FIGMODEL');
	my $mediaObjs = $figmodel->database()->get_objects("media");
	my $mediaNames = ["Complete"];
	for ( my $i = 0 ; $i < @{$mediaObjs}; $i++ ) {
		push( @{$mediaNames}, $mediaObjs->[$i]->id() );
	}
	my $mediaFilterSelect = $self->application()->component('mediaFilterSelect');
	$mediaFilterSelect->width(280);
	$mediaFilterSelect->size(10);
	$mediaFilterSelect->dropdown(1);
	$mediaFilterSelect->name('media');
	$mediaFilterSelect->labels($mediaNames);
	$mediaFilterSelect->values($mediaNames);
	$mediaFilterSelect->default('Complete');
	return $mediaFilterSelect->output();
}

sub ajax {
	my ( $self, $ajax ) = @_;
	if ( defined($ajax) ) {
		$self->{ajax} = $ajax;
	}
	return $ajax;
}

sub _timestamp {
	my ( $self, $epochTime ) = @_;
	my ( $sec, $min, $hour, $day, $month, $year ) = gmtime($epochTime);
	my $month_name = ( January, February, March, April, May, June,
		July, August, September, October, November, December
	)[$month];
	$year  += 1900;
	$month += 1;
	my $ISO8601_str =
	  "$year-$month-$day" . "T" . $hour . ":" . $min . ":" . $sec . "Z";
	my $date_str = "$month_name $day, $year";
	return " <span class='CommentTime' title='$ISO8601_str'>$date_str</span>";
}

sub require_javascript {
	return [
		"$Conf::cgi_url/Html/jquery-1.3.2.min.js",
		"$Conf::cgi_url/Html/MFAController.js"
	];
}
