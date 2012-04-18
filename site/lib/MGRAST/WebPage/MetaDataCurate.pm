package MGRAST::WebPage::MetaDataCurate;

use strict;
use warnings;
use Data::Dumper;

use DBMaster;
use MGRAST::Metadata;
use FIG_Config;

use base qw( WebPage );


sub init {
  my ($self) = @_;
  
  my $cgi = $self->app->cgi;

  # register components
  $self->application->register_component('Table', 'CurateProjMD');
  $self->application->register_component('Table', 'CurateJobMD');
  $self->application->register_component('Table', 'CurateTagMD');
  $self->application->register_component('Ajax', 'MDajax');

  # get db handles
  my $md_db  = MGRAST::Metadata->new();
  my $mg_dbh = $md_db->{_handle}->db_handle();

  # set config file
  my $template = "MetaData";
  if ( $self->app->cgi->param('template') ) { $template = $self->app->cgi->param('template'); }
  my $config = $FIG_Config::mgrast_formWizard_templates . "/FormWizard_$template.xml";
  unless (-f $config) { $self->app->add_message('warning', "No template file $config"); }

  my $struct = $md_db->get_template_data($config);
  my %form   = map { $_, $struct->{$_}->[0] . " : " . $struct->{$_}->[1] } keys %$struct;

  # get data
  my (%projs, %jobs);
  my $p_ids = join(",", map {qq('$_')} @{ $md_db->get_projects() });
  if ($p_ids) {
    my $pl = $mg_dbh->selectall_arrayref("SELECT _id, id, name FROM Project WHERE _id IN ($p_ids)");
    %projs = ($pl && scalar(@$pl)) ? (map {$_->[0], $_} grep {$_->[2] =~ /\S/} @$pl) : {};
  }

  my $j_ids = join(",", map {qq('$_')} @{ $md_db->get_jobs() });
  if ($j_ids) {
    my $jl = $mg_dbh->selectall_arrayref("SELECT _id, job_id, metagenome_id, name FROM Job WHERE _id IN ($j_ids)");
    %jobs  = ($jl && scalar(@$jl)) ? (map {$_->[0], $_} grep {$_->[2] =~ /\S/} @$jl) : {};
  }
  my %cols = map {$_, 1} @{ $md_db->get_collections() };
  my %tags = map {$_, $form{$_}} grep {exists $form{$_}} @{ $md_db->get_tags() };

  # set data
  $self->data('struct', $struct);
  $self->data('mddb', $md_db);
  $self->data('projs', \%projs);
  $self->data('jobs', \%jobs);
  $self->data('cols', \%cols);
  $self->data('tags', \%tags);

  $self->application->register_action($self, 'update_proj_data', 'update_proj_data');
  $self->application->register_action($self, 'update_col_data', 'update_col_data');
  $self->application->register_action($self, 'update_job_data', 'update_job_data');
  $self->application->register_action($self, 'update_tag_data', 'update_tag_data');
}

sub output {
  my ($self) = @_;

  my $user = $self->app->session->user;
  if ( ! $user ) {
    $self->app->add_message('warning', "You are not a registered user.");
    return '';
  } elsif ( ! $user->is_admin('MGRAST') ) {
    $self->app->add_message('warning', "You do not have access to curate metadata.");
    return '';
  }

  # start page with genome or tag select
  my $scripts = qq~
<script type="text/javascript">
\$(document).ready( function() {
  var curSel = '';
  \$("#selPJ").change( function() {
    \$("#divCurate").html("");
    curSel = 'selPJ';
    execute_ajax('get_proj_data', 'divCurate', 'id=' + \$(this).val() + '&view=' + \$("#selView").val());
  });
  \$("#selCL").change( function() {
    \$("#divCurate").html("");
    curSel = 'selCL';
    execute_ajax('get_col_data', 'divCurate', 'id=' + \$(this).val() + '&view=' + \$("#selView").val());
  });
  \$("#selMG").change( function() {
    \$("#divCurate").html("");
    curSel = 'selMG';
    execute_ajax('get_job_data', 'divCurate', 'id=' + \$(this).val() + '&view=' + \$("#selView").val());
  });
  \$("#selQS").change( function() {
    \$("#divCurate").html("");
    curSel = 'selQS';
    execute_ajax('get_tag_data', 'divCurate', 'id=' + \$(this).val() + '&view=' + \$("#selView").val());
  });
  \$("#selView").change( function() {
    if (curSel == 'selMG') {
      execute_ajax('get_job_data', 'divCurate', 'id=' + \$("#selMG").val() + '&view=' + \$(this).val());
    } else if (curSel == 'selPJ') {
      execute_ajax('get_proj_data', 'divCurate', 'id=' + \$("#selPJ").val() + '&view=' + \$(this).val());
    }
  });
});
</script>
~ . $self->application->component('MDajax')->output;

  my $projs = $self->data('projs');
  my $jobs  = $self->data('jobs');
  my $tags  = $self->data('tags');
  my $cols  = $self->data('cols');
  my $pj_options = join( "\n", map {qq(<option value="$_->[0]">$_->[0] - $_->[2]</option>)} sort {$a->[2] cmp $b->[2]} values %$projs );
  my $cl_options = join( "\n", map {qq(<option value="$_">$_</option>)} sort keys %$cols );
  my $mg_options = join( "\n", map {qq(<option value="$_->[0]">$_->[2]</option>)} sort {$a->[2] cmp $b->[2]} values %$jobs );
  my $qs_options = join( "\n", map {qq(<option value="$_">$tags->{$_}</option>)} sort {$tags->{$a} cmp $tags->{$b}} keys %$tags );
  my $view_sel   = qq(
<td><select id="selView">
    <option value="min" selected="selected">Anwsered Questions</option>
    <option value="max">All Questions</option>
</select></td>
);

  my $html = "<div><table><tr>\n";
  if (scalar keys %$projs) { $html .= "<th>Curate Metadata of Project</th>\n"; }
  if (scalar keys %$jobs)  { $html .= "<th>Curate Metadata of Metagenome</th>\n"; }
  if ((scalar keys %$jobs) || (scalar keys %$projs)) { $html .= "<th>View Options</th>\n"; }
  $html .= "</tr><tr>\n";
  if (scalar keys %$projs) { $html .= qq(<td><select id="selPJ">$pj_options</td>\n); }
  if (scalar keys %$jobs)  { $html .= qq(<td><select id="selMG">$mg_options</td>\n); }
  if ((scalar keys %$jobs) || (scalar keys %$projs)) { $html .= $view_sel; }
  $html .= "</tr></table><br>\n<table><tr>\n";
  if (scalar keys %$cols) { $html .= "<th>Curate Metagenome Collection</th>\n"; }
  if (scalar keys %$tags) { $html .= "<th>Curate Metagenome Metadata by Question</th>\n"; }
  $html .= "</tr><tr>\n";
  if (scalar keys %$cols) { $html .= qq(<td><select id="selCL">$cl_options</td>\n); }
  if (scalar keys %$tags) { $html .= qq(<td><select id="selQS">$qs_options</td>\n); }
  $html .= qq(</tr></table></div>\n<br><div id="divCurate"></div>\n);

  return $scripts . $html;
}

sub get_col_data {
  my ($self) = @_;

  my $cgi  = $self->app->cgi;
  my $cid  = $cgi->param('id');
  my $view = $cgi->param('view');
  my $cPPO = $self->data('mddb')->get_all_for_collection($cid);  
  my $html = $self->start_form('col_data_form', { action     => 'update_col_data',
						  ID         => $cid,
						  creator_ID => $cPPO->creator->ID });

  $html .= "<table>\n<tr><td>Collection ID</td><td>$cid</td></tr>";
  $html .= "<tr><td>Job ID</td><td>" . $cPPO->job->job_id . "</td></tr>\n";
  $html .= "<tr><td>Genome ID</td><td>" . $cPPO->job->metagenome_id . "</td></tr>\n";
  $html .= "<tr><td>Genome Name</td><td>" . $cPPO->job->name . "</td></tr>\n";
  $html .= "<tr><td>Source</td><td>" . $cgi->textfield(-name => "source", -value => $cPPO->source) . "</td></tr>\n";
  $html .= "<tr><td>URL</td><td>" . $cgi->textfield(-name => "url", -value => $cPPO->url) . "</td></tr>\n";
  $html .= "<tr><td>Entry Date</td><td>" . $cgi->textfield(-name => "entry_date", -value => $cPPO->entry_date) . "</td></tr>\n";
  $html .= "<tr><td>Creator ID</td><td>" . $cPPO->creator->ID . "</td></tr>\n";
  $html .= "<tr><td>Creator Name</td><td>" . $cgi->textfield(-name => "creator_name", -value => $cPPO->creator->name) . "</td></tr>\n";
  $html .= "<tr><td>Creator Type</td><td>" . $cgi->textfield(-name => "creator_type", -value => $cPPO->creator->type) . "</td></tr>\n";
  $html .= "<tr><td>Creator Status</td><td>" . $cgi->textfield(-name => "creator_status", -value => $cPPO->creator->status) . "</td></tr>\n";
  $html .= "<tr><td>Creator URL</td><td>" . $cgi->textfield(-name => "creator_url", -value => $cPPO->creator->url) . "</td></tr>\n";
  $html .= "<tr><td>Creator Date</td><td>" . $cgi->textfield(-name => "creator_date", -value => $cPPO->creator->date) . "</td></tr>\n";
  $html .= qq(</table>\n<button type="submit" name="action" value="update_col_data">Update</button>) . $self->end_form();
  
  return $html;
}

sub get_proj_data {
  my ($self) = @_;

  my $cgi   = $self->app->cgi;
  my $pid   = $cgi->param('id');
  my $view  = $cgi->param('view');
  my $tags  = {};
  my $table = $self->application->component('CurateProjMD');
  
  my @table_data;
  foreach ( @{$self->data('mddb')->get_all_for_project($pid)} ) {
    my ($id, $tag, $val) =  @$_;
    if ( ($view eq 'min') && ((! defined($val)) || ($val !~ /\S/)) ) { next; }

    my $proj = $self->data('projs')->{$pid};
    push @table_data, [ $id, $tag, $val ];
  }
  
  if (@table_data == 0) {
    return "<br><p>No metadata avilable for project " . $self->data('proj')->{$pid}[2] . ".</p>";
  }

  $table->width(850);
  if ( scalar(@table_data) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1); 
  }
  
  $table->columns([ { name => '_id'   , input_type => 'hidden', visible => 0 },
		    { name => 'Name'  , sortable   => 1 }, 
		    { name => 'Value' , input_type => 'textfield' }
		  ]);

  $table->data( \@table_data );

  return $self->start_form('proj_table_form', {action => 'update_proj_data', proj_id => $pid, table_id => $table->id()}) .
         $table->output() . $table->submit_button({form_name => 'proj_table_form'}) . $self->end_form();
}

sub get_job_data {
  my ($self) = @_;

  my $cgi   = $self->app->cgi;
  my $jid   = $cgi->param('id');
  my $view  = $cgi->param('view');
  my $gid   = $self->data('jobs')->{$jid}[2];
  my $table = $self->application->component('CurateJobMD');

  my $job = '';
  eval { $job = $self->app->data_handle('MGRAST')->Job->init({metagenome_id => $gid}); };
  unless ($job && ref($job)) { return "<br><p>No metadata avilable for genome $gid.</p>"; }
  
  my %tags;
  foreach ( @{$self->data('mddb')->get_all_for_job($job)} ) {
    push @{ $tags{$_->{tag}} }, [ $_->{type}, $_->{migs}, $_->{value} ];
  }

  my @table_data;
  while ( my ($tag, $cat) = each %{$self->data('struct')} ) {
    if ( exists $tags{$tag} ) {
      foreach my $set ( @{$tags{$tag}} ) {
	my ($type, $migs, $val) = @$set;
	$type = $type || '';
	$migs = $migs || '';
	$val  = $val  || '';
	
	if ( ($view eq 'min') && ((! defined($val)) || ($val !~ /\S/)) ) { next; }
	push @table_data, [ $tag, $cat->[0], $cat->[1], $val, $type, $migs ];
      }
    }
    elsif ( $view eq 'max' ) {
      push @table_data, [ $tag, $cat->[0], $cat->[1], '', '', '' ];
    }
  } 
  if (@table_data == 0) { return "<br><p>No metadata avilable for genome $gid.</p>"; }

  $table->width(850);
  if ( scalar(@table_data) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1); 
  }
  
  $table->columns([ { name => 'tag'     , input_type => 'hidden', visible => 0 },
		    { name => 'Category', sortable   => 1, filter => 1, operator => 'combobox' },
		    { name => 'Question', sortable   => 1, filter => 1 },
		    { name => 'Value'   , input_type => 'textfield', sortable => 1 },
		    { name => 'Type'    , input_type => 'textfield', sortable => 1 },
		    { name => 'MIGS'    , input_type => 'textfield', sortable => 1 }
		  ]);

  $table->data( \@table_data );

  return $self->start_form('job_table_form', {action => 'update_job_data', job_id => $jid, metagenome_id => $gid, table_id => $table->id()}) .
         $table->output() . $table->submit_button({form_name => 'job_table_form'}) . $self->end_form();
}

sub get_tag_data {
  my ($self) = @_;

  my $cgi   = $self->app->cgi;
  my $tag   = $cgi->param('id');
  my $jobs  = {};
  my $table = $self->application->component('CurateTagMD');
  my $table_id = $table->id();

  my @table_data;
  foreach my $row ( @{$self->data('mddb')->get_all_for_tag($tag, 1)} ) {
    my ($id, $jid, $val) =  @$row;
    my $job = $self->data('jobs')->{$jid};
    unless ( defined($val) && ($val =~ /\S/) ) { next; }
    push @table_data, [ $id, $job->[1], $job->[2], $job->[3], $val ];
  }
 
  if (@table_data == 0) {
    return "<br><p>No jobs available with metadata for $tag.</p>";
  }

  $table->width(850);
  if ( scalar(@table_data) > 50 ) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
  }
      
  $table->columns([ { name => '_id'        , input_type => 'hidden', visible => 0 },
		    { name => 'Job ID'     , sortable   => 1 },
		    { name => 'Genome ID'  , sortable   => 1, filter => 1 },
		    { name => 'Genome Name', sortable   => 1, filter => 1 },
		    { name => 'Value'      , input_type => 'textfield' }
		  ]);

  $table->data( \@table_data );

  return $self->start_form('tag_table_form', {action => 'update_tag_data', tag_id => $tag, table_id => $table->id()}) .
         $table->output() . $table->submit_button({form_name => 'tag_table_form'}) . $self->end_form();
}

sub update_col_data {
  my ($self) = @_;
  
  my $cgi     = $self->app->cgi;
  my $collect = $cgi->param('ID');
  my $creator = $cgi->param('creator_ID');

  my $collect_attr = { source     => $cgi->param('source'),
		       url        => $cgi->param('url'),
		       entry_date => $cgi->param('entry_date') };
  my $creator_attr = { name   => $cgi->param('creator_name'),
		       type   => $cgi->param('creator_type'),
		       status => $cgi->param('creator_status'),
		       url    => $cgi->param('creator_url'),
		       date   => $cgi->param('creator_date') };

  #$self->app->add_message('info', '<pre>' . Dumper($collect_attr) . '</pre>');
  #$self->app->add_message('info', '<pre>' . Dumper($creator_attr) . '</pre>');
  $self->data('mddb')->update_collection($collect, $collect_attr);
  $self->data('mddb')->update_curator($creator, $creator_attr);
}

sub update_proj_data {
  my ($self) = @_;

  my $cgi  = $self->app->cgi;
  my $proj = $cgi->param('proj_id');
  my $tid  = $cgi->param('table_id');
  my @keys = $cgi->param("ic_${tid}_0");
  my @vals = $cgi->param("ic_${tid}_4");

  unless (@keys && @vals && (exists $self->data('proj')->{$proj})) { return 0; }

  my @data;
  for (my $i=0; $i<@keys; $i++) {
    if (defined($vals[$i]) && ($vals[$i] =~ /\S/)) { push @data, [ $keys[$i], $vals[$i] ]; }
  }

  #$self->app->add_message('info', '<pre>' . Dumper(\@data) . '</pre>');
  $self->data('mddb')->update_project_value(\@data);
}

sub update_job_data {
  my ($self) = @_;

  my $cgi  = $self->app->cgi;
  my $jid  = $cgi->param('job_id');
  my $gid  = $cgi->param('metagenome_id');
  my $tid  = $cgi->param('table_id');
  my @tags = $cgi->param("ic_${tid}_0");
  my @vals = $cgi->param("ic_${tid}_4");
  my @typs = $cgi->param("ic_${tid}_5");
  my @migs = $cgi->param("ic_${tid}_6");

  my $job  = $self->app->data_handle('MGRAST')->Job->init({metagenome_id => $gid});
  my $coll = $self->data('mddb')->get_collection_for_job($job);
  unless ($job && ref($job) && $coll && ref($coll) && @tags && @vals && @typs && @migs) { return 0; }

  my (%tag_val, %data);
  for (my $i=0; $i<@tags; $i++) {
    if (defined($vals[$i]) && ($vals[$i] =~ /\S/)) {
      push @{ $tag_val{ $tags[$i] } }, $vals[$i];
    }
    $data{ $tags[$i] } = [ $typs[$i], $migs[$i], [] ];
  }
  foreach (keys %tag_val) { $data{$_}->[2] = $tag_val{$_}; }

  #$self->app->add_message('info', '<pre>' . Dumper(\%data) . '</pre>');
  $self->data('mddb')->add_entries($coll, $job, \%data);
}

sub update_tag_data {
  my ($self) = @_;

  my $cgi  = $self->app->cgi;
  my $tag  = $cgi->param('tag_id');
  my $tid  = $cgi->param('table_id');
  my @keys = $cgi->param("ic_${tid}_0");
  my @vals = $cgi->param("ic_${tid}_4");

  unless (@keys && @vals && (exists $self->data('tags')->{$tag})) { return 0; }

  my @data;
  for (my $i=0; $i<@keys; $i++) {
    $vals[$i] =~ s/^\s+//;
    $vals[$i] =~ s/\s+$//;
    unless ($vals[$i] eq '') { push @data, [ $keys[$i], $vals[$i] ]; }
  }

  #$self->app->add_message('info', '<pre>' . Dumper(\@data) . '</pre>');
  $self->data('mddb')->update_entry_value(\@data);
}

1;
