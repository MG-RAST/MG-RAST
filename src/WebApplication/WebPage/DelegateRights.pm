package WebPage::DelegateRights;

use base qw( WebPage );

1;

use strict;
use warnings;

=pod

=head1 NAME

DelegateRights - an instance of WebPage which offers users the ability to pass on their rights to others

=head1 DESCRIPTION

Offers users the ability to pass on their rights to others

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Rights Management');
  $self->application->register_action($self, 'grant_right', 'grant_right');
  $self->application->register_action($self, 'revoke_right', 'revoke_right');
  $self->application->register_component('Table', 'revokable_rights_table');
  $self->application->register_component('TabView', 'grant_revoke_tv');

  return 1;
}

=item * B<output> ()

Returns the html output of the DelegateRights page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # get all delegatable rights the user has
  my $rights = $user->rights(1, 1);
  
  # group the rights
  my $grouped_rights = {};
  my $revokable_rights = [];
  foreach my $right (@$rights) {
    next if ($right->data_type() eq '*');
    my $name = $right->name();
    my $type = $right->data_type();
    my $id = $right->data_id();
    my $app = $right->application() || 'undef';

    # get all non-delegated rights
    push(@$revokable_rights, @{$master->Rights->get_objects( { name => $name,
							       data_type => $type,
							       data_id => $id,
							       granted => 1,
							       application => $right->application() } )});
    

    # handle special cases
    if (! exists($grouped_rights->{$type}) ) {
      $grouped_rights->{$type} = {};
    }
    if (! exists($grouped_rights->{$type}->{$name}) ) {
      $grouped_rights->{$type}->{$name} = {};
    }
    if ($id eq '*') {
      my $all_rights_for_type = $master->Rights->get_objects( { name => $name,
								data_type => $type });
      foreach my $rft (@$all_rights_for_type) {
	my $rft_id = $rft->data_id();
	$app = $rft->application() || 'undef';
	$grouped_rights->{$type}->{$name}->{$rft_id} = $app;
      }
    } else {
      $grouped_rights->{$type}->{$name}->{$id} = $app;
    }
  }

  # prepare rights data
  my $data_types = "";
  my $right_names = "";
  my $data_ids = "";

  foreach my $data_type (keys(%$grouped_rights)) {
    $data_types .= "<div onclick='disp(\"$data_type\")' name='type_div' id='type_$data_type' style='color: blue; text-decoration: underline; cursor: pointer; padding: 0px; margin: 0px;'>$data_type</div>\n";
    $right_names .= "<div style='display: none; cursor: pointer; padding: 0px; margin: 0px;' id='right_$data_type' name='right_div'>\n";
    foreach my $right_name (keys(%{$grouped_rights->{$data_type}})) {
      $right_names .= "<div onclick='disp(\"$data_type\", \"$right_name\")' id='right_div_$data_type\_$right_name' name='div_right' style='color: blue; text-decoration: underline; padding: 0px; margin: 0px;'>$right_name</div>\n";
      $data_ids .= "<div style='display: none; padding: 0px; margin: 0px;' id='data_$data_type\_$right_name' name='data_div'>";
      foreach my $data_id (keys(%{$grouped_rights->{$data_type}->{$right_name}})) {
	$data_ids .= "<div onclick='disp(\"$data_type\", \"$right_name\", \"$data_id\", \"" . $grouped_rights->{$data_type}->{$right_name}->{$data_id} . "\")' id='id_div_$data_type\_$right_name\_$data_id' name='div_id' style='color: blue; text-decoration: underline; padding: 0px; margin: 0px; cursor: pointer;'>$data_id</div>\n";
      }
      $data_ids .= "</div>\n";
    }
    $right_names .= "</div>\n";
  }

  my $viewable_user_ids;
  @$viewable_user_ids = map { $_->_id() } @{$master->User->get_objects()};
  my $viewable_scope_ids;
  my $viewable_scopes = $master->Scope->get_objects();
  foreach my $viewable_scope (@$viewable_scopes) {
    next if $viewable_scope->name() =~ /^user:/;
    next if $viewable_scope->application();
    push(@$viewable_scope_ids, $viewable_scope->_id());
  }

  # compose the html
  my $html = &js();

  my $grant = "";
  $grant .= $self->start_form( 'grant_right_form', { action => 'grant_right' });

  # select right
  $grant .= "<h2>1. Select a right to delegate</h2>Select the data type, then the right and then the data id.";
  $grant .= "<table>";
  $grant .= "<tr><th>Data type</th><th>Right</th><th>Data ID</th></tr>";
  $grant .= "<tr><td>" . $data_types . "</td><td>" . $right_names . "</td><td>" . $data_ids . "</td></tr>";
  $grant .= "</table>";

  # select user or group
  $grant .= "<h2>2. Select a group or user to delegate to</h2>";
  my $select_list = [];
  foreach my $g (@$viewable_scope_ids) {
    my $group_name = 'Group: '.$master->Scope->get_objects( { _id => $g } )->[0]->name();
    push(@$select_list, { name => $group_name, type => 'group', id => $g } );
  }
  
  foreach my $u (@$viewable_user_ids) {
    my $uo = $master->User->get_objects( { _id => $u } )->[0];
    my $user_name = $uo->lastname() . ", " . $uo->firstname();
    push(@$select_list, { name => $user_name, type => 'user', id => $u });
  }

  @$select_list = sort { ($b->{name} =~ /^Group\: /) <=> ($a->{name} =~ /^Group\: /) || lc($a->{name}) cmp lc($b->{name}) } @$select_list;

  $grant .= "<select name='right_target'>";
  foreach my $select (@$select_list) {
    $grant .= "<option value='".$select->{type}."|".$select->{id}."'>".$select->{name}."</option>";
  }
  $grant .= "</select>";

  # check for delegatable
  $grant .= "<h2>3. Should the user be able to delegate the right?</h2>";
  $grant .= "<p style='width: 350px; text-align: justify;'>By default, the user cannot pass the right you give to them on to other users. If you wish for the user to be able to do this, check the following box.</p>";
  $grant .= "delegatable <input type='checkbox' name='delegatable'>";

  # create a submit button
  $grant .= "<h2>4. Grant the right</h2>";
  $grant .= "<input type='hidden' id='result' name='result'>";
  $grant .= "<input type='submit' value='grant'>";

  # end the form
  $grant .= $self->end_form();

  # create part to revoke rights
  my $revoke = "";
  my $rr_table = $application->component('revokable_rights_table');
  $rr_table->columns( [ { name => 'Owner', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'Right', filter => 1, sortable => 1, operator => 'combobox'  }, { name => 'Type', filter => 1, sortable => 1, operator => 'combobox'  }, { name => 'ID', filter => 1, sortable => 1  }, "Revoke" ] );
  $rr_table->show_select_items_per_page(1);
  $rr_table->items_per_page(15);
  $rr_table->show_top_browse(1);
  $rr_table->show_bottom_browse(1);
  my $rr_table_data = [];
  if (scalar(@$revokable_rights)) {
    foreach my $right (@$revokable_rights) {
      my $rname = "";
      my $rscope = $right->scope();
      if ($rscope->name() =~ /^user:/) {
	my $ruser = $master->UserHasScope->get_objects( { scope => $rscope })->[0]->user();
	$rname = $ruser->lastname(). ", " . $ruser->firstname() ;
      } else {
	$rname = " Group: ".$rscope->name();
      }
      push(@$rr_table_data, [ $rname, $right->name(), $right->data_type(), $right->data_id(), $self->start_form('revoke', { action => 'revoke_right' })."<input type='hidden' name='right' value='".$right->_id()."'><input type='submit' value='revoke'>".$self->end_form() ]);
    }
    @$rr_table_data = sort { $a->[0] cmp $b->[0] } @$rr_table_data;
    $rr_table->data($rr_table_data);
    $revoke .= $rr_table->output();
  }

  my $tv = $application->component('grant_revoke_tv');
  $tv->width(750);
  $tv->add_tab('Grant Rights', "<div style='padding: 4px;'>".$grant."</div>");
  $tv->add_tab('Revoke Rights', $revoke);

  # include link to go back to account management page
  $html .= $tv->output()."<br/><a href='".$application->url."?page=AccountManagement'>back to account management</a>";

  # return the html
  return $html;
}

sub grant_right {
  my ($self) = @_;
  
  # get necessary objects
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  # check cgi parameters
  my $right_target = $cgi->param('right_target');
  my $delegatable = $cgi->param('delegatable');
  my ($right, $data_type, $data_id, $app) = split(/\|/, $cgi->param('result'));

  unless (defined($right) && defined($data_type) && defined($data_id)) {
    $application->add_message('warning', 'You must select a data type, a right and a data id, aborting.');
    return 0;
  }

  if ($app eq 'undef') {
    $app = undef;
  } else {
    $app = $master->Backend->get_objects( { _id => $app } )->[0];
  }
  
  unless (defined($right_target)) {
    $application->add_message('warning', 'No user or group selected, aborting.');
    return 0;
  }

  # determine target scope
  my $scope_object;
  my $scope_object_name = "";
  my ($type, $target) = split(/\|/, $right_target);
  if ($type eq 'group') {
    $scope_object = $master->Scope->get_objects( { _id => $target} )->[0];
    $scope_object_name = "group " . $scope_object->name();
  } else {
    my $suser = $master->User->get_objects( { _id => $target } )->[0];
    $scope_object = $suser->get_user_scope();
    $scope_object_name = $suser->firstname() . " " . $suser->lastname();
  }

  # check if the right already exists
  my $right_object;
  my $right_objects = $master->Rights->get_objects( { 'application' => $app,
						      'name' => $right,
						      'data_type' => $data_type,
						      'data_id' => $data_id,
						      'scope' => $scope_object } );
  
  # some right exists
  if (scalar(@$right_objects)) {
    $right_objects->[0]->granted(1);
    $right_object = $right_objects->[0];
  } else {
    $right_object = $master->Rights->create( { 'application' => $app,
					       'granted' => 1,
					       'name' => $right,
					       'data_type' => $data_type,
					       'data_id' => $data_id,
					       'scope' => $scope_object } );
  }
  
  if ($delegatable) {
    $right_object->delegated(0);
  } else {
    $right_object->delegated(1);
  }
  $application->add_message('info', "Right $right - $data_type - $data_id granted to $scope_object_name.");
  
  return 1;
}

sub revoke_right {
  my ($self) = @_;

  # get necessary objects
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  # check cgi parameters
  my $right_id = $cgi->param('right');

  # check if the right exists
  my $right;
  my $right_objects = $master->Rights->get_objects( { '_id' => $right_id } );
  
  # some right exists
  if (scalar(@$right_objects)) {
    $right = $right_objects->[0];
    my $rname = "";
    my $rscope = $right->scope();
    if ($rscope->name() =~ /^user:/) {
      my $ruser = $master->UserHasScope->get_objects( { scope => $rscope })->[0]->user();
      $rname = $ruser->firstname() . " " . $ruser->lastname();
    } else {
      $rname = "Group ".$rscope->name();
    }
    $application->add_message('info', "Right ".$right->name()." - ".$right->data_type()." - ".$right->data_id() ." revoked for $rname");
    $right->delete();
  } else {
    $application->add_message('warning', 'Right not found, aborting');
    return 0;
  }

  return 1;
}

sub required_rights {
  return [ [ 'login' ] ];
}

sub js {
  return qq~<script>
function disp (type, right, id, app) {
  var all_types = document.getElementsByName('type_div');
  var all_rights = document.getElementsByName('right_div');
  var all_data_ids = document.getElementsByName('data_div');
  var all_div_rights = document.getElementsByName('div_right');
  var all_div_ids = document.getElementsByName('div_id');
  for (i=0; i<all_rights.length; i++) {
    all_rights[i].style.display = 'none';
  }
  for (i=0; i<all_data_ids.length; i++) {
    all_data_ids[i].style.display = 'none';
  }
  for (i=0; i<all_types.length; i++) {
    all_types[i].style.backgroundColor = 'white';
  }
  for (i=0; i<all_div_rights.length; i++) {
    all_div_rights[i].style.backgroundColor = 'white';
  }
  for (i=0; i<all_div_ids.length; i++) {
    all_div_ids[i].style.backgroundColor = 'white';
  }
  document.getElementById('type_'+type).style.backgroundColor = '#c0c0c0';
  document.getElementById('right_'+type).style.display = 'inline';
  if (right) {
    document.getElementById('data_'+type+'_'+right).style.display = 'inline';
    document.getElementById('right_div_'+type+'_'+right).style.backgroundColor = '#c0c0c0';
  }
  document.getElementById('result').innerHTML = '';
  if (id) {
    document.getElementById('id_div_'+type+'_'+right+'_'+id).style.backgroundColor = '#c0c0c0';
    document.getElementById('result').value = right + '|' + type + '|' + id + '|' + app;
  }
}
</script>~;
}
