package WebPage::GroupAdmin;

use base qw( WebPage );

1;

use strict;
use warnings;

=pod

=head1 NAME

GroupAdmin - an instance of WebPage which offers users the ability to adminitstrate a group

=head1 DESCRIPTION

Offers users the ability to administrate a group

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Group Administration');
  $self->application->register_action($self, 'grant_scope', 'grant_scope');
  $self->application->register_action($self, 'revoke_scope', 'revoke_scope');
  $self->application->register_action($self, 'change_group_name', 'change_group_name');
  $self->application->register_action($self, 'create_group', 'create_group');
  $self->application->register_action($self, 'change_group_description', 'change_group_description');
  $self->application->register_action($self, 'make_group_admin', 'make_group_admin');

  return 1;
}

=item * B<output> ()

Returns the html output of the GroupAdmin page.

=cut

sub output {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();
  
  # unless there is a user, we cannot display this page
  unless ($user) {
    $application->add_message('warning', "You must be logged in to see this page.");
    return "";
  }

  my $html = "<h2>Group Management</h2>";

  # check for scope parameter
  my $scope = $cgi->param('group');
  unless(defined($scope)) {
    $application->add_message('warning', "No group selected.");
    return "";
  }

  my $scope_object;
  my $possible_scopes = $master->Scope->get_objects({ 'name' => $scope });
  if (scalar(@$possible_scopes)) {
    $scope_object = $possible_scopes->[0];
  } else {
    $application->add_message('warning', "Group with name $scope not found in database");
    return "";
  }

  unless ($user->has_right($application, 'edit', 'scope', $scope_object->_id)) {
    $application->add_message('warning', "You are lacking the rights to display this page");
    return "";
  }
  
  # get all user scopes and add form to revoke them
  my $users = $scope_object->users();
  my $users_field = "<table><tr><td colspan=2><b>Current Users</b></td></tr>";
  foreach my $user (@$users) {
    $users_field .= "<tr><td>";
    if ($application->session->user->has_right($application, 'edit', 'scope', $scope_object->_id())) {
      my $admin = "";
      if ($user->has_right(undef, 'edit', 'scope', $scope_object->_id())) {
	$admin = " [group admin]";
      } else {
	$admin = $self->start_form( 'group_form', { 'action' => 'make_group_admin',
						    'new_admin' => $user->_id(),
						    'group' => $scope_object->name(),
						    'scope' => $scope_object->_id() } )."<input type='submit' value='make admin' style='height: 20px;'>" . $self->end_form();
      }
      $users_field .= $user->firstname()." ".$user->lastname()."</td><td>".$admin."</td><td>";
      $users_field .= $self->start_form( 'group_form', { 'action' => 'revoke_scope',
							 'login' => $user->login(),
							 'group' => $scope_object->name() } )."</td><td><input type='submit' value='remove' style='height: 20px;'>";
      $users_field .= $self->end_form();
    } else {
      $users_field .= $user->firstname()." ".$user->lastname();
    }
    $users_field .= "</td></tr>";
  }
  $users_field .= "</table>";

  $users_field .= "<hr><b>Add user by eMail</b><br>".$self->start_form( 'scope_form', { 'action' => 'grant_scope', 'group' => $scope } );
  $users_field .= "eMail&nbsp;&nbsp;&nbsp;<input type='text' name='email'>";
  $users_field .= "<input type='submit' value='add'>";
  $users_field .= $self->end_form();

  # get user rights
  my $rights = $scope_object->rights(1);
  my $rights_list = [];
  my $rights_field = "";
  foreach my $right (@$rights) {
    push(@$rights_list, $right->name() . " - " . $right->data_type() . " - " . $right->data_id());
  }
  unless (scalar(@$rights_list)) {
    $rights_field = " - none -";
  } else {
    $rights_field = join('<br/>', @$rights_list);
  }

  # details
  my $scope_description = $scope_object->description() || "";
  $html .= "<table width='400'>";
  $html .= "<tr><th>Name</th><td>" . $self->start_form('group_name_form', { 'action' => 'change_group_name', 'group' => $scope }) . "<input type='text' value='$scope' name='new_group' style='width: 220px;'><input type='submit' value='change'>" .$self->end_form() . "</td></tr>";
  $html .= "<tr><th>Description</th><td>" . $self->start_form('group_description_form', { 'action' => 'change_group_description', 'group' => $scope }) . "<textarea name='group_description' cols='25' >" . $scope_description . "</textarea><input type='submit' value='change'>" .$self->end_form() . "</td></tr>";
  $html .= "<tr><th>Users</th><td>" . $users_field . "</td></tr>";
  $html .= "<tr><th>Rights</th><td>" . $rights_field . "</td></tr>";
  $html .= "</table>";

  # include link to go back to account management page
  $html .= "<br/><a href='".$application->url."?page=AccountManagement'>back to account management</a>";
  
  return $html;
}

=item * B<grant_scope> ()

Action method that grants a scope to a user.

=cut

sub grant_scope {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $scope = $cgi->param('group');
  if (defined($scope)) {
    my $poss_scopes = $master->Scope->get_objects( { 'name' => $scope } );
    if (scalar(@$poss_scopes)) {
      $scope = $poss_scopes->[0];
    } else {
      $application->add_message('warning', 'Could not retrieve group from database.');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must define a group name, aborting.');
    return 0;
  }
  my $user;
  my $user_email = $cgi->param('email');
  if (defined($user_email)) {
    $user = $master->User->init( { 'email' => $user_email } );
    unless (ref($user)) {
      $application->add_message('warning', "Could not find user for eMail $user_email.");
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must enter a valid eMail, aborting.');
    return 0;
  }

  # check if the user already has this scope
  my $uhs = $master->UserHasScope->init( { 'user' => $user, 'scope' => $scope } );
  unless (ref($uhs)) {
    $uhs = $master->UserHasScope->create( { 'user' => $user, 'scope' => $scope } );
  }
  unless (ref($uhs)) {
    $application->add_message('warning', 'Could not create group.');
    return 0;
  }

  # do the actual granting of the scope
  $uhs->granted(1);

  # add the right to view this user
  unless ($application->session->user->has_right($application, 'view', 'user', $user->login())) {
    $master->Rights->create( { application => $application->backend(),
			       name => 'view',
			       data_type => 'user',
			       data_id => $user->login() } );
  }

  $application->add_message('info', $user->firstname() . ' ' . $user->lastname() .' added to group ' . $scope->name().'.');
}

=item * B<revoke_scope> ()

Action method that revokes a scope from a user.

=cut

sub revoke_scope {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $scope = $cgi->param('group');
  if (defined($scope)) {
    my $poss_scopes = $master->Scope->get_objects( { 'name' => $scope } );
    if (scalar(@$poss_scopes)) {
      $scope = $poss_scopes->[0];
    } else {
      $application->add_message('warning', 'Could not retrieve group from database.');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must define a group name, aborting.');
    return 0;
  }

  my $user = $cgi->param('login');
  if (defined($user)) {
    $user = $master->User->init( { 'login' => $user } );
    unless (ref($user)) {
      $application->add_message('warning', 'Could not retrieve user from database.');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must define a user, aborting.');
    return 0;
  }

  my $uhs = $master->UserHasScope->init( { 'user' => $user, 'scope' => $scope } );
  if (ref($uhs)) {
    $uhs->delete();
  } else {
    $application->add_message('warning', 'User is not a member of this group.');
    return 0;
  }

  $application->add_message('info', 'User ' . $user->firstname() . ' ' . $user->lastname() . ' removed from group '.$scope->name());
}

=item * B<change_group_description> ()

Action method that changes the description of a group

=cut

sub change_group_description {
 my ($self) = @_;

 # get the objects we need
 my $application = $self->application();
 my $master = $application->dbmaster();
 my $cgi = $application->cgi();
 my $user = $application->session->user();

 # check for group description
 unless (defined($cgi->param('group_description'))) {
   $application->add_message('warning', "You must provide a description for your group.");
   return 0;
 }

 # check for group
 my $group = $cgi->param('group');
 unless (defined($group)) {
   $application->add_message('warning', "You must provide a group to change the description for.");
   return 0;
 }
	 
 # find group in database
 my $poss_groups = $master->Scope->get_objects( { name => $group } );
 unless (scalar(@$poss_groups) == 1) {
   $application->add_message('warning', "Group $group not found in database.");
   return 0;
 }

 # check if the current user has the right to change the description
 unless ($user->has_right($application, 'edit', 'scope', $poss_groups->[0]->_id())) {
   $application->add_message('warning', "You do not have the right to change the description of this group.");
   return 0;
 }

 # all sanity checks passed, change the description
 $poss_groups->[0]->description($cgi->param('group_description'));

 # inform the user of success
 $application->add_message('info', "Description of group $group changed successfully.");

 return 1;
}

=item * B<change_group_name> ()

Action method that changes the name of a group

=cut

sub change_group_name {
 my ($self) = @_;

 # get the objects we need
 my $application = $self->application();
 my $master = $application->dbmaster();
 my $cgi = $application->cgi();
 my $user = $application->session->user();

 # check for new group name
 my $new_group = $cgi->param('new_group');
 unless (defined($new_group)) {
   $application->add_message('warning', "You must provide a new name for your group.");
   return 0;
 }

 # check for old group
 my $old_group = $cgi->param('group');
 unless (defined($old_group)) {
   $application->add_message('warning', "You must provide a group to change the name of.");
   return 0;
 }
	 
 # find old group in database
 my $poss_groups = $master->Scope->get_objects( { name => $old_group } );
 unless (scalar(@$poss_groups) == 1) {
   $application->add_message('warning', "Group $old_group not found in database.");
   return 0;
 }

 # check if the current user has the right to change the name
 unless ($user->has_right($application, 'edit', 'scope', $poss_groups->[0]->_id())) {
   $application->add_message('warning', "You do not have the right to change the name of this group.");
   return 0;
 }

 # all sanity checks passed, change the name
 $poss_groups->[0]->name($new_group);

 # adjust the cgi param to the new name
 $cgi->param('group', $new_group);

 # inform the user of success
 $application->add_message('info', "Name of group $old_group changed to $new_group.");

 return 1;
}

=item * B<create_group> ()

Action method that creates a group

=cut

sub create_group {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $master = $application->dbmaster();
  my $cgi = $application->cgi();
  my $user = $application->session->user();
  
  # check for group
  my $group = $cgi->param('new_group');
  unless (defined($group)) {
    $application->add_message('warning', "You must provide a group to create.");
    return 0;
  }
  
  # find group in database
  my $poss_groups = $master->Scope->get_objects( { name => $group } );
  if (scalar(@$poss_groups)) {
    $application->add_message('warning', "Group $group already exists.");
    return 0;
  }
  
  # check if the current user has the right to change create a group
  unless ($user->has_right($application, 'add', 'scope')) {
    $application->add_message('warning', "You do not have the right to create a group.");
    return 0;
  }
  
  # all sanity checks passed, create the group
  my $scope = $master->Scope->create( { name => $group } );

  # grant the scope to the user that created it
  $master->UserHasScope->create( { user => $user, scope => $scope, granted => 1 } );

  # give the creator the right to edit, delete and view this group
  $master->Rights->create( { scope => $user->get_user_scope(),
			     name => 'edit',
			     data_type => 'scope',
			     data_id => $scope->_id(),
			     granted => 1 } );
  $master->Rights->create( { scope => $user->get_user_scope(),
			     name => 'delete',
			     data_type => 'scope',
			     data_id => $scope->_id(),
			     granted => 1 } );
  $master->Rights->create( { scope => $user->get_user_scope(),
			     name => 'view',
			     data_type => 'scope',
			     data_id => $scope->_id(),
			     granted => 1 } );

  # set group parameter in cgi
  $cgi->param('group', $group);

  # inform the user of success
  $application->add_message('info', "Group $group successfully created.");

  return 1;
}

sub make_group_admin {
  my ($self) = @_;

  # get some objects
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $application->session->user;
  my $master = $application->dbmaster;

  # get the cgi params we need
  my $scope = $cgi->param('scope');
  my $new_admin = $cgi->param('new_admin');

  # check if we have all params we need
  unless (defined($scope) && defined($new_admin)) {
    $application->add_message('warning', "You must pass a user and a group, aborting");
    return 0;
  }

  # check if the logged in user has the right to grant admin access to this group
  unless ($user && $user->has_right(undef, 'edit', 'scope', $scope)) {
    $application->add_message('warning', "You do not have the right to grant admin rights for this group");
    return 0;
  }

  # check if we can find the to-be admin
  my $new_admins = $master->User->get_objects( { _id => $new_admin } );
  if (scalar(@$new_admins)) {
    $new_admin = $new_admins->[0];
  } else {
    $application->add_message('warning', "User to grant admin right to not found.");
    return 0;
  }

  # check if the to-be admin already has the right
  my $existing = $master->Rights->get_objects( { name => 'edit',
						 data_type => 'scope',
						 data_id => $scope,
						 scope => $new_admin->get_user_scope } );
  my $na_name = $new_admin->firstname." ".$new_admin->lastname;
  if (scalar(@$existing)) {
    if (! $existing->[0]->granted) {
      $existing->[0]->granted(1);
      $application->add_message('info', "Granted admin rights for this group to $na_name");
    } else {
      $application->add_message('info', "The user $na_name was already admin of this group");
    }
  } else {
    $master->Rights->create( { name => 'edit',
			       data_type => 'scope',
			       data_id => $scope,
			       scope => $new_admin->get_user_scope,
			       granted => 1 } );
    $application->add_message('info', "Granted admin rights for this group to $na_name");
  }

  return 1;
}

=item * B<required_rights> ()

Returns the rights needed to access the page.

=cut

sub required_rights {
  return [ [ 'login' ] ];
}
