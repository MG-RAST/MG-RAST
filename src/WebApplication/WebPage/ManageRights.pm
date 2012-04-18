package WebPage::ManageRights;

use base qw( WebPage );

1;

use strict;
use warnings;

=pod

=head1 NAME

ManageRights - an instance of WebPage which allows an admin to manage the rights of all users

=head1 DESCRIPTION

Allows an admin to manage the rights of all users

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Rights Management');
  $self->application->register_action($self, 'add_right', 'add_right');
  $self->application->register_action($self, 'delete_right', 'delete_right');
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('FilterSelect', 'ScopeSelect');
  $self->application->register_component('Table', 'RightsTable');

  return 1;
}

=item * B<output> ()

Returns the html output of the ManageRights page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # get a list of all users
  my $users = $master->User->get_objects();
  @$users = sort { $a->lastname cmp $b->lastname || $a->firstname cmp $b->firstname || $a->login cmp $b->login } @$users;

  # get a list of all groups
  my $unfiltered_scopes = $master->Scope->get_objects();

  # filter out the user scopes
  my $scopes = [];  
  foreach my $scope (@$unfiltered_scopes) {
    next if ($scope->name =~ /^user\:/);
    next if ($scope->name =~ /^Admin$/);
    next if ($scope->name =~ /^inv\:/);
    push(@$scopes, $scope);
  }
  @$scopes = sort { $a->name cmp $b->name } @$scopes;

  # create a filter-select with the user/scope data
  my $scope_select = $application->component('ScopeSelect');
  my $labels = [];
  my $values = [];
  foreach my $scope (@$scopes) {
    push(@$labels, "Group: ".$scope->name);
    push(@$values, "group|".$scope->_id);
  }
  foreach my $user (@$users) {
    push(@$labels, $user->lastname.", ".$user->firstname." (".$user->login.")");
    push(@$values, "user|".$user->_id);
  }
  $scope_select->labels($labels);
  $scope_select->values($values);
  $scope_select->size(20);
  $scope_select->name('right_target');
  
  # build the html
  my $html = "";

  # add the ajax to load the user rights
  my $ajax = $application->component('ajax');
  $html .= $ajax->output();

  # create the form
  $html .= $self->start_form('user_form');
  $html .= "<input type='hidden' name='action' id='action'>";
  $html .= "<input type='hidden' name='id' id='id'>";
  $html .= "<table><tr>";
  $html .= "<td>".$scope_select->output();
  $html .= "<input type=button onclick='execute_ajax(\"user_info\", \"ui\", \"user_form\");' value='show details'></td>";
  $html .= "<td><div id='ui' name='ui'></div></td></tr></table>";
  $html .= $self->end_form();
  
  return $html;
}

sub user_info {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $master = $application->dbmaster;

  # check if we have a user/group
  my $right_target = $cgi->param('right_target');
  unless (defined($right_target)) {
    return "<h2>You must select a user or a group</h2>";
  }

  # get the scope for the user/group
  my $scope;
  my ($type, $id) = split(/\|/, $right_target);
  if ($type eq 'group') {
    $scope = $master->Scope->get_objects( { _id => $id } )->[0];
  } else {
    $scope = $master->User->get_objects( { _id => $id } )->[0]->get_user_scope();
  }

  # get the rights of that scope
  my $rights = $master->Rights->get_objects( { scope => $scope } );

  # construct the rights table
  my $table = $application->component('RightsTable');
  $table->items_per_page(20);
  $table->show_select_items_per_page(1);
  $table->show_top_browse(1);
  $table->columns( [ { name => 'name', filter => 1, sortable => 1 }, { name => 'data type', filter => 1, sortable => 1, operator => 'combobox' }, { name => 'data id', filter => 1, sortable => 1 }, { name => 'granted', sortable => 1 }, { name => 'delete' } ] );
  my $data = [];
  foreach my $right (@$rights) {
    my $app_name = "";
    if ($right->application) {
      $app_name = " (".$right->application->name.")";
    }
    my $del_button = "<input type='button' value='delete' onclick='document.getElementById(\"id\").value=\"".$right->_id."\"; document.getElementById(\"action\").value=\"delete_right\"; document.forms.user_form.submit();'>";
    push(@$data, [ $right->name.$app_name, $right->data_type, $right->data_id, $right->granted, $del_button ]);
  }
  $table->data($data);

  my $backends = $master->Backend->get_objects();
  my $b_select = "<select name='backend'>";
  $b_select .= "<option value=''>- none -</option>";
  foreach my $b (@$backends) {
    $b_select .= "<option value='" . $b->{_id} . "'>" . $b->name . "</option>";
  }
  $b_select .= "</select>";

  # construct the return html
  my $user_info = "<h2>add right</h2>";
  $user_info .= "<table>";
  $user_info .= "<tr><th>application</th><td>".$b_select."</td></tr>";
  $user_info .= "<tr><th>name</th><td><input type='text' name='right'></td></tr>";
  $user_info .= "<tr><th>data type</th><td><input type='text' name='data_type'></td></tr>";
  $user_info .= "<tr><th>data id</th><td><input type='text' name='data_id'></td></tr>";
  $user_info .= "</table><input type='button' value='add right' onclick='document.getElementById(\"action\").value=\"add_right\"; document.forms.user_form.submit();'>";
  $user_info .= "<input type='hidden' name='delegatable' value='0'>";
  $user_info .= "<h2>current rights</h2>";
  $user_info .= $table->output;

  return $user_info;
}

sub add_right {
  my ($self) = @_;
  
  # get necessary objects
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  # check cgi parameters
  my $right_target = $cgi->param('right_target');
  my $delegatable = $cgi->param('delegatable') || 0;
  my $right = $cgi->param('right');
  my $data_type = $cgi->param('data_type');
  my $data_id = $cgi->param('data_id');
  my $backend = $cgi->param('backend');

  unless (defined($right_target) && defined($right) && defined($data_type) && defined($data_id)) {
    $application->add_message('warning', 'You must select a user or group, a data type, a right and a data id, aborting.');
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
  my $right_objects;
  if (defined $backend) {
    $right_objects = $master->Rights->get_objects( { 'application' => $master->Backend->get_objects( { _id => $backend } )->[0],
						     'name' => $right,
						     'data_type' => $data_type,
						     'data_id' => $data_id,
						     'scope' => $scope_object } );
  } else {
    $right_objects = $master->Rights->get_objects( { 'name' => $right,
						     'data_type' => $data_type,
						     'data_id' => $data_id,
						     'scope' => $scope_object } );
  }
  
  # some right exists
  if (scalar(@$right_objects)) {
    $right_objects->[0]->granted(1);
    $right_object = $right_objects->[0];
  } else {
    $right_object = $master->Rights->create( { 'granted' => 1,
					       'name' => $right,
					       'data_type' => $data_type,
					       'data_id' => $data_id,
					       'scope' => $scope_object } );
    if (defined $backend) {
      my $b = $master->Backend->get_objects( { _id => $backend } )->[0];
      $right_object->application($b);
    }
  }
  
  if ($delegatable) {
    $right_object->delegated(0);
  } else {
    $right_object->delegated(1);
  }
  $application->add_message('info', "Right $right - $data_type - $data_id granted to $scope_object_name.", 6);
  
  return 1;
}

sub delete_right {
  my ($self) = @_;

  # get necessary objects
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  # check cgi parameters
  my $right_id = $cgi->param('id');

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
    $application->add_message('info', "Right ".$right->name()." - ".$right->data_type()." - ".$right->data_id() ." revoked for $rname", 6);
    $right->delete();
  } else {
    $application->add_message('warning', 'Right not found, aborting');
    return 0;
  }

  return 1;
}

sub required_rights {
  return [ [ 'edit', 'user', '*' ] ];
}
