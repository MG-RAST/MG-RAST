package MGRAST::WebPage::MetaDataMG;

use strict;
use warnings;
use Data::Dumper;

use MGRAST::Metadata;
use FIG_Config;
use base qw( WebPage );

sub init {
  my ($self) = @_;
  
  my $cgi = $self->app->cgi;
  
  # register components
  $self->application->register_component('FormWizard', 'EditMetaData');
  $self->application->register_component('Table' , 'DisplayMetaData');
  $self->application->register_component('TabView', 'Complex');
  $self->application->register_component('Ajax', 'MDajax');

  # get job
  my $job = '';
  my $metagenome_id = $self->application->cgi->param('metagenome') || '';
  if ($metagenome_id) {
    $self->data('metagenome', $metagenome_id);
    # if job not public and user not owner, $job is undef
    eval { $job = $self->app->data_handle('MGRAST')->Job->init({metagenome_id => $metagenome_id}); };
  }
  
  if ($job) {
    $self->data('job', $job);
  } elsif ($metagenome_id) {
    $self->app->add_message('warning', "No Job for $metagenome_id.");
  } else {
    $self->app->add_message('warning', "No Job selected.");
  }

  # check cgi parameters
  my $view =  $self->app->cgi->param('view') || 'all' ;
  my $edit =  $self->app->cgi->param('edit') || '0'   ;

  $self->data('options' , { view => $view ,
			    edit => $edit,
			  }
	     );

  # set config file
  my $template = "MetaData";
  if ( $self->app->cgi->param('template') ) { $template = $self->app->cgi->param('template'); }
  my $config = $FIG_Config::mgrast_formWizard_templates . "/FormWizard_$template.xml";
  unless (-f $config) { $self->app->add_message('warning', "No template file $config"); }

  # prefill form
  my $mddb   = MGRAST::Metadata->new();
  my $user   = $self->application->session->user;
  my $coll   = $mddb->get_collection_for_job($job);
  my $prefix = "MetaData_";

  $self->data('mddb', $mddb);
  $self->data('collection', $coll);
  $self->data('FormWizardConfigFile', $config);
  $self->data('prefix', $prefix);
  $self->data("meta_data", []);
  $self->data('display', "popup");

  my $prefill;
  if ( $user ) {
    $prefill = { "${prefix}firstname" => $user->firstname,
		 "${prefix}lastname"  => $user->lastname,
		 "${prefix}email"     => $user->email     };
  }
  if ( $job && ref($job) ) {
    $prefill = { "${prefix}firstname" => $job->owner->firstname,
		 "${prefix}lastname"  => $job->owner->lastname,
		 "${prefix}email"     => $job->owner->email     };
    foreach ( @{ $mddb->get_all_for_job($job) } ) {
      push @{ $prefill->{$prefix . $_->{tag}} }, $_->{value};
    }
  }
  $self->data('prefill', $prefill);
  
  # prepare form wizard
  my $form_wizard = $self->application->component('EditMetaData');
  $form_wizard->prefill($prefill);
  $form_wizard->page($self);
  $form_wizard->form_name('MetaData');
  $form_wizard->noprefix(0);
  $form_wizard->prefix( $prefix );
  $form_wizard->width(950);
  $form_wizard->height(400);
  $form_wizard->orientation('vertical');
  $form_wizard->config_file( $self->data('FormWizardConfigFile') );
  $form_wizard->enable_ajax(1);
  $form_wizard->allow_random_navigation(1);
  $self->data('FormWizard', $form_wizard);
  $self->data('struct', $form_wizard->struct());

  # register action
  $self->application->register_action($self, 'load_meta_data', 'load_meta_data');
  $self->application->register_action($self, 'upload_meta_data', 'upload_meta_data');

  $self->title("Metadata Editor");
}

sub output {
  my ($self) = @_;
  
  my $user     = $self->application->session->user;
  my $can_edit = 0;
  my $job_msg  = '';
  if ($user && $self->data('job')) {
    $can_edit = $user->has_right(undef, 'edit', 'metagenome', $self->data('job')->metagenome_id) ? 1 : 0;
    if ( (! $can_edit) && $self->data('collection') ) {
      $can_edit = $user->has_right(undef, 'edit', 'metadata', $self->data('collection')->ID) ? 1 : 0;
    }
    if ( $user->is_admin('MGRAST') ) { $can_edit = 1; }
  }  
  if ($self->data('job')) {
    $job_msg = "You are " . ( ($can_edit and $self->data('options')->{edit} ) ? "edit" : "view") . "ing metadata for " . $self->data('job')->name . " (" . $self->data('metagenome') . ")";
  }

  my $editor_name = $self->app->cgi->param('template') || '';
  my $description = $self->start_form('MetaDataUpload', {action => "upload_meta_data", metagenome => $self->data('metagenome')}) .
                    "<p>File: <input name='upload_file' type='file'><input type='button' value='Upload' onclick='MetaDataUpload.submit();'></p>" .
                    $self->end_form;

  # start page w/ file upload
  my $content = qq~
<script>
function switch_display (ID) {
  var doc = document.getElementById(ID);
  if (doc.style.display == "none") {
      doc.style.display="inline";
      document.getElementById("expand_img").title = "less";
  } else if (doc.style.display == "inline") {
     doc.style.display="none";
     document.getElementById("expand_img").title = "more";
  }
}
</script>
~ . $self->application->component('MDajax')->output;

  

  my $intro_text = qq~<h1>Metadata</h1>
MG-RAST has implemented the use of "Minimum Information about a MetaGenome Sequence" developed by the
<a href="http://gensc.org" target=_blank >Genomic Standards Consortium</a> (GSC).
The Genomic Standards Consortium is an open-membership working body which formed in September 2005.
The goal of this international community is to promote mechanisms that standardize the description of genomes
and the exchange and integration of genomic data. MG-RAST supports this goal as it allows for transparency in
comparative analyses, interpretation of results, and integration of metagenomic data.~;
  my $view_text  ;
  my $edit_text =  qq~ <p align="left">
<table><tr>
  <td valign="center">
    <a onclick="switch_display('description');" style="cursor:pointer;color:blue">
    <img id="expand_img" src="$FIG_Config::cgi_url/Html/MGRAST-upload.png" width="50%"></a>
  </td><td style="vertical-align:middle;" id="expand_text">
    Please fill out the form below for your metagenome. You can
    <a onclick="switch_display('description');" style="cursor:pointer;color:blue">upload</a>
    a file to prefill the form. Please check all fields before updating your data.
  </td></tr>
</table></p>
<div id="description" style="display:none">$description</div>
~; 

  unless ($self->{simple_mode}) {
    $content .= $intro_text ;
    if ($can_edit and $self->data('options')->{edit} ) {
      $content .= $edit_text ;
    }
    $content .= "<p style='color:blue;'>$job_msg</p><br>";
  }

  # prepare tab view for complex display
  my $tab_view = $self->application->component('Complex');
  $tab_view->width(800);
  $tab_view->height(400);

  # prepare form wizard
  my $form_wizard = $self->data('FormWizard');
  $form_wizard->submit_button($can_edit);
  
  my $prefill = $self->data('prefill');
  my $struct  = $self->data('struct');
  my $editor  = '';
  
  if ($can_edit) {
    if ($self->{simple_mode}) {
      $editor = $self->start_form('MetaData', { load_meta_data => 1, 
						metagenome     => $self->data('metagenome'), 
						outfile        => $self->app->cgi->param('outfile') || "",
					      } );
    } else {
      $editor = $self->start_form('MetaData', { action     => "load_meta_data", 
						metagenome => $self->data('metagenome'), 
						outfile    => $self->app->cgi->param('outfile') || "",
					      } );
    }
  }
  $editor .= $form_wizard->output();
  if ($can_edit) { $editor .= $self->end_form(); }
  
  # get data for table view
  my $table;
  if ( $self->data('meta_data') && (@{$self->data('meta_data')} > 0) ) {
    # table from data entered in form
    $table = $self->get_report_table( $self->data('meta_data') );
  }
  else {
    # table from db data
    my $db_data = $self->data('mddb')->get_metadata_for_table($self->data('job'));
    if ($db_data && (@$db_data > 0)) {
      $table = $self->get_report_table( $db_data );
    } else {
      $table = "<b>no data available</b>";
    }
  }

  if ($self->data('options')->{view} eq "all") {
    $tab_view->add_tab('Editor' . $editor_name, $editor);
    if ($table) { $tab_view->add_tab('Tabular Report', $table); }
    $content .= $tab_view->output();
  }
  elsif ($self->data('options')->{view} eq "editor") { 
    $content .= $editor;
  }
  else{
    $content .= $table;
  }
						       
  return $content;
}

sub get_report_table {
  my ($self, $data) = @_;
  
  my @table_data = ();

  foreach my $row (sort {($a->[0] cmp $b->[0]) || ($a->[1] cmp $b->[1])} @$data) {
    my ($tag, $cat, $name, $val) = @$row;
    if ( $val && (! ref $val) ) { $val = [ $val ]; }
    if ( ! $val ) { next; }
    foreach ( @$val ) {
      unless ( defined($_) && ($_ =~ /\S/) ) { next; }
      push @table_data, [ $tag, $cat, $name, $_ ];
    }
  }

  my $table = $self->application->component('DisplayMetaData');
  $table->width(800);
  $table->show_export_button({title => "Export table", strip_html => 1});

  if ( scalar(@table_data) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1); 
  }
      
  $table->columns([ { name => 'Key'     , visible => 0 },
		    { name => 'Category', filter  => 1, sortable => 1, operator => 'combobox' },
		    { name => 'Question', filter  => 1, sortable => 1 },
		    { name => 'Value'   , filter  => 1, sortable => 1 }
		  ]);

  $table->data( \@table_data );
  return $table->output;
}

sub load_meta_data {
  my ($self) = @_;

  my $cgi       = $self->application->cgi;
  my $prefill   = $self->data('prefill');
  my $struct    = $self->data('struct');
  my $prefix    = $self->data('prefix');
  my $meta_data = {};
  my $data_ok   = 1;
  my %params    = $cgi->Vars();

  unless ( scalar keys %params ) { return; }

  my @data;
  while ( my ($param, $value) = each %params ) {
    my ($tag) = $param =~/^$prefix(.+)/;
    unless ($tag) { next; }
    
    # value is always an array ref
    $value = $value ? [ split(/\0/, $value) ] : [];
    
    my ($display_text, $display_cat, undef) = $struct->name2display($param);
    my (undef, undef, $question)            = $struct->name2original($param);
    next unless($display_text);
    
    my ($check, $value, @response) = $self->check_data($param, $value, $cgi->upload($param));
    
    unless ($check) {
      # data needs to be checked - don't load into DB
      $data_ok = 0;
      $self->app->add_message('warning', "Please check your entered data for $display_text in $display_cat");
      foreach my $row (@response) {
	if (ref $row) {
	  $row->[3] = " Missing or malformed data <strike>" . $row->[3] . "</strike>";  
	  for (my $i=0; $i < scalar @$row ; $i++) {
	    $row->[$i] = "<strong style='color:red'>" .  $row->[$i] . "</strong>";
	  }
	}
	else{
	  $self->app->add_message('warning', "$row");
	}
      }
    }
    push @data, @response;
    
    my $migs = exists($question->{migs}) ? $question->{migs} : 0;
    my $type = exists($question->{type}) ? $question->{type} : '';
    $meta_data->{ $tag } = [ $type, $migs, $value ];
    $prefill->{ $param } = $value;
  }
  $self->data("meta_data", \@data);
  $self->data('prefill', $prefill);

  if ( $data_ok ) {
    # update DB and write to file
    if ( $self->data('job') && (scalar(keys %$meta_data) > 0) ) {
      $self->app->add_message("info", "Updating Metadata DB");
      
      # add to MetaDataCollection table
      my $collection = $self->data('collection');
      my $curator    = $self->get_curator();

      if ($collection) {
	# update of existing
	$self->data('mddb')->add_update($collection, $curator);
      } else {
	# new addition
	$collection = $self->data('mddb')->add_collection($self->data('job'), $curator);	
      }
      # add to MetaDataEntry table
      $self->data('meta_data_checked', '1');
      $self->data('mddb')->add_entries( $collection, $self->data('job'), $meta_data );
      $self->data('mddb')->export_metadata( $self->data('job'), $self->data('job')->dir . "/MetaData" );
    }
    # write to file only
    elsif ( $cgi->param('outfile') && (scalar(keys %$meta_data) > 0) ) {
      my $text_data = map { $_, $meta_data->{$_}->[2] } keys %$meta_data;
      $self->app->add_message("info", "Writing to " . $cgi->param('outfile') );
      $self->data('mddb')->write2file( $text_data, $cgi->param('outfile') );
    }
    # no data
    else {
      my $nr = scalar(keys %$meta_data);
      $self->app->add_message("warning", "No Data ($nr keys), dump to file ='". $cgi->param('outfile')."', Job = '". $self->data('job')->job_id."'" );
    }
  }
  else {
    $self->app->add_message("warning", "Please correct your data and submit again");
    $self->data('meta_data_checked', '0');
  }
}

sub get_curator {
  my ($self) = @_;

  my $user    = $self->application->session->user;
  my $curator = $self->data('mddb')->_handle->Curator->get_objects({user => $user});
  if ($curator && (@$curator > 0)) {
    return $curator->[0];
  } else {
    return $self->data('mddb')->add_curator($user);
  }
}

sub upload_meta_data {
  my ($self) = @_;

  my $cgi = $self->app->cgi;
  unless ( $cgi->param('upload_file') ) {
    $self->app->add_message("warning", "File Upload Failed");
    return;
  }
  
  $self->app->add_message('info', 'Loading meta data from file');
  
  my $fh      = $cgi->upload("upload_file");
  my $prefill = $self->data('prefill');

  if ($fh) {
    while (my $line = <$fh>) {
      chomp $line;
      my @fields = split(/\t/, $line);
      
      if( @fields > 3){
	my ($key, $cat, $name, @val) = @fields;
	$prefill->{ $self->data('prefix').$cat."_".$key } = [ @val ];
      }
      elsif( @fields == 2){
	my ($key, @val) = @fields;
	$prefill->{ $self->data('prefix').$key } = [ @val ];
      }
    }
  }
  
  my $counter = 0 ;
  foreach my $param (keys %{$cgi->Vars}) {
    my $value = $cgi->Vars->{ $param } ;
    $prefill->{$param} = [ map { $_ =~ s/^\s+// } split(/\0/, $value) ];
  }

  $self->data('prefill', $prefill);
}

# $value must be array ref
sub check_data {
  my ($self, $tag, $value, $fh)  = @_ ;

  my $check_mandatory = 0;
  my $checked = 0;
  my @response;

  my $struct = $self->data('struct');
  my ($name, undef, $question)                     = $struct->name2original($tag);
  my ($display_text, $display_cat, $display_title) = $struct->name2display($tag);

  if (! ref $question) { return 0, "Can't find question data for tag $tag"; }

  # check for mandatory
  unless ( defined($value) && (ref($value) eq "ARRAY") && (@$value > 0) ) {
    $checked = 1 unless ( $check_mandatory and $question->{mandatory} );
    return $checked, [], ([ $name, "$display_cat : $display_title", $display_text, [] ]);
  }

  # check for defaults
  my $tmp = [];
  foreach (@$value) {
    if (($_ ne '') && ($_ !~ /(unknown|Please Select)/i)) { push @$tmp, $_; }
  }
  $value = $tmp;

  # check for envo lite
  if ($name eq "envo_lite") {
    my $ood = $self->app->data_handle('OOD');
    unless ($ood) { return 0, $value, "No connection to OOD"; }
    
    my $ood_name = $question->{ontologyName} || $question->{ood_category} || $question->{name};
    my $ood_cats = $ood->Category->get_objects({ name => $ood_name });
    unless (scalar @$ood_cats) { return 0, $value, "No OOD Category for $ood_name"; }

    my $entries = $ood->Entry->get_objects({ name => $value->[0], category => $ood_cats->[0] });
    unless (scalar @$entries) { return 0, $value, "No OOD Entries for " . $value->[0]; }

    my $entry = $entries->[0];
    if ($entry and ref $entry and $entry->user_entry) {
      while ($entry->user_entry) { $entry = $entry->parent; }
      push @response, [ "envo_user", "$display_cat : $display_title", $display_text, $value ];
      push @response, [ $name, "$display_cat : $display_title", $display_text, $entry->name ];
    }
    else {
      push @response, [ $name, "$display_cat : $display_title", $display_text, $value ];
    }
    $checked = 1;
  }
  else {
    my $error   = '';
    my $package = "WebComponent::FormWizard::" . $question->{type};

    { # check if type package exists
      no strict;
      eval "require $package;";
      $error = $@;
    }

    # check it type package has check_data function
    # check_data returns undef if bad; may change data depending on type
    unless ($error) {
      my $type = $package->new($self, $question);
      if ($type && $type->can('check_data')) {
	if ($fh) { $value = $type->check_data($value, $fh, $self->data('job')->dir . "/MetaData/"); }
	else     { $value = $type->check_data($value); }
      }
    }

    # data is bad
    unless (defined $value) { return 0, [], "Undefined value for $tag"; }

    # data is good
    push @response, [ $name, "$display_cat : $display_title", $display_text, $value ];
    $checked = 1;
  }

  return $checked, $value, @response;
}

1;
