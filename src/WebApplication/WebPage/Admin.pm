package WebPage::Admin;

use base qw( WebPage );

1;

use strict;
use warnings;

use WebConfig;

use Data::Dumper;

=pod

=head1 NAME

Admin - an instance of WebPage which offers administrative functions

=head1 DESCRIPTION

Offer administrative functions

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('SEED Viewer - Administration Panel');

  $self->application->register_component('Table', 'user_table');
  $self->application->register_component('Table', 'rights_table');
  $self->application->register_component('Table', 'scopes_table');
  $self->application->register_component('Table', 'new_users_table');
  $self->application->register_component('TabView', 'admin_tabview');
  $self->application->register_action($self, 'add_user', 'add_user');
  $self->application->register_action($self, 'activate_users', 'activate_users');
  $self->application->register_action($self, 'add_scope', 'add_scope');
  $self->application->register_action($self, 'add_right', 'add_right');
  $self->application->register_action($self, 'grant_scope', 'grant_scope');
  $self->application->register_action($self, 'revoke_scope', 'revoke_scope');
  $self->application->register_action($self, 'grant_right', 'grant_right');
  $self->application->register_action($self, 'revoke_right', 'revoke_right');
  $self->application->register_action($self, 'change_email', 'change_email');

  return 1;
}

=item * B<output> ()

Returns the html output of the Admin page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $html = "";

  my $tv = $application->component('admin_tabview');
  $tv->width(800);
  my $numtabs = 0;

  # new user requests
  if ($application->session->user->has_right($application, 'edit', 'scope') || $application->session->user->has_right($application, 'edit', 'user', '*')) {
    my $new_users .= "<table><tr><td><h2>Current List of Users Requesting Access</h2>";
    $new_users .= $self->new_users_list();
    $new_users .= "</td></tr></table>";
    $tv->add_tab('User Requests', $new_users);
    $numtabs++;
  }

  # administrate users
  if ($application->session->user->has_right($application, 'view', 'user')) {
    my $admin_users = "<table><tr>";
    $admin_users .= "<td style='padding-right: 25px;'>";
    $admin_users .= "<h2>Current List of Users (click login for details)</h2>";
    $admin_users .= $self->user_list();
    $admin_users .= "</td>";
  
    if (defined($cgi->param('login'))) {
      $tv->default($numtabs);
      $admin_users .= "<td>";
      $admin_users .= "<h2>User Details</h2>";
      $admin_users .= $self->user_details();
      $admin_users .= "</td>";
    }
    $admin_users .= "</tr></table>";
    $tv->add_tab('Administrate Users', $admin_users);
    $numtabs++;
  }

  # administrate scopes
  if ($application->session->user->has_right($application, 'edit', 'scope')) {
    my $admin_scopes .= "<table><tr><td style='padding-right: 25px;'>";
    $admin_scopes .= "<h2>Current List of Groups<br>(click name for details)</h2>";
    $admin_scopes .= $self->scopes_list();
    $admin_scopes .= "</td>";
    if (defined($cgi->param('scope'))) {
      $tv->default($numtabs);
      $admin_scopes .= "<td>";
      $admin_scopes .= "<h2>Group Details</h2>";
      $admin_scopes .= $self->scope_details();
      $admin_scopes .= "</td>";
    }
    $admin_scopes .= "</tr></table>";
    $tv->add_tab('Administrate Groups', $admin_scopes);
    $numtabs++;
  }

  # create users and scopes
  if ($application->session->user->has_right($application, 'add', 'user', '*') || $application->session->user->has_right($application, 'add', 'scope', '*')) {
    my $create .= "<table><tr>";
    if ($application->session->user->has_right($application, 'add', 'user', '*')) {
      $create .= "<td>";
      $create .= "<h2>Create a new User</h2>";
      $create .= $self->new_user_form();
      $create .= "</td>";
    }
    if ($application->session->user->has_right($application, 'add', 'scope', '*')) {
      $create .= "<td>";
      $create .= "<h2>Create a new Group</h2>";
      $create .= $self->new_scope_form();
      $create .= "</td>";
    }
    $tv->add_tab('Create Users and Groups', $create);
    $numtabs++;
  }

  $html .= $tv->output();

  return $html;

}

##########
# Rights #
##########

### Right Display Functions

sub rights_list {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  my $table = $application->component('rights_table');

  my $rights = $master->Rights->get_objects();
  $table->columns( [ 'Application', 'Right', 'Data Type', 'Data ID', 'Scope', 'Granted' ] );
  my $data = [];
  foreach my $right (@$rights) {
    my $app = "";
    if (defined($right->application)) {
      $app = $right->application->name();
    }
    push(@$data, [ $app,
		   $right->name(),
		   $right->data_type(),
		   $right->data_id(),
		   $right->scope->name(),
		   $right->granted() ] );
  }
  $table->data($data);
  $html .= $table->output();

  return $html;
}

sub new_right_form {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  my $scopes = $master->Scope->get_objects();

  $html .= $self->start_form( 'add_right_form', { 'action' => 'add_right' } );
  $html .= "<table>";
  $html .= "<tr><th>Name</th><td><input type='text' name='right'></td></tr>";
  $html .= "<tr><th>Data Type</th><td><input type='text' name='data_type'></td></tr>";
  $html .= "<tr><th>Data ID</th><td><input type='text' name='data_id'></td></tr>";
  $html .= "<tr><th>Scope</th><td><select name='scope'>";
  foreach my $scope (@$scopes) {
    $html .= "<option value='" . $scope->name() . "'>" . $scope->name() . "</option>";
  }
  $html .= "</select></td><td><input type='submit' value='Create'></td></tr>";
  $html .= "</table>";
  $html .= $self->end_form();

  return $html;
}

### Right Action Functions

sub add_right {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $right = $cgi->param('right');
  unless (defined($right)) {
    $application->add_message('warning', 'You must define a right name, aborting.');
    return 0;
  }
  my $scope = $cgi->param('scope');
  if (defined($scope)) {
    $scope = $master->Scope->init( { 'name' => $scope, 'application' => $application->backend() } );
    unless (ref($scope)) {
      $application->add_message('warning', 'Could not retrieve scope from database, aborting.');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must define a scope, aborting.');
    return 0;
  }

  my $data_type = $cgi->param('data_type') || "*";
  my $data_id = $cgi->param('data_id') || "*";

  my $right_object = $master->Rights->create( { 'name'        => $right,
						'application' => $application->backend(),
						'data_type'   => $data_type,
						'data_id'     => $data_id,
						'scope'       => $scope,
						'granted'     => 1 } );
  unless (ref($right_object)) {
    $application->add_message('warning', 'Could not create right');
    return 0;
  }

  $application->add_message('info', "Right $right added successfully.");

  return 1;
}

sub grant_right {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  my $login = $cgi->param('login');
  my $scope = $cgi->param('scope');
  my $delegatable = $cgi->param('delegatable');

  my ($app, $right, $data_type, $data_id) = split(/ - /, $cgi->param('right'));

  if ($app ne 'undef') {
    $app = $master->Backend->get_objects( { _id => $app} )->[0];
  } else {
    $app = undef;
  }

  my $scope_object;
  if (defined($scope)) {
    $scope_object = $master->Scope->init( { 'application' => $application->backend(), 'name' => $scope } );
    unless (ref($scope_object)) {
      $application->add_message('warning', "Could not retrieve scope $scope from database, aborting.");
      return 0;
    }
  } elsif (defined($login)) {
    my $user = $master->User->init( { 'login' => $login } );
    $scope_object = $user->get_user_scope();
    unless (ref($user)) {
      $application->add_message('warning', 'Could not get user from database, aborting');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must pass either login or scope, aborting.');
    return 0;
  }

  unless (defined($right) && defined($data_type) && defined($data_id)) {
    $application->add_message('warning', 'Grant right called with missing parameters, aborting.');
    return 0;
  }

  my $right_object;
  my $right_objects = $master->Rights->get_objects( { 'application' => $app,
						      'name' => $right,
						      'data_type' => $data_type,
						      'data_id' => $data_id,
						      'scope' => $scope_object } );
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
  $application->add_message('info', "Right $right - $data_type - $data_id granted.");
  
  return 1;
}

sub revoke_right {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $login = $cgi->param('login');
  my $scope = $cgi->param('scope');
  my $right = $cgi->param('right');
  my $data_type = $cgi->param('data_type');
  my $data_id = $cgi->param('data_id');

  unless (defined($right) && defined($data_type) && defined($data_id)) {
    $application->add_message('warning', 'revoke right called with missing parameters, aborting.');
    return 0;
  }

  my $scope_object;
  if (defined($scope)) {
    my $scope_object = $master->Scope->init( { 'application' => $application->backend(), 'name' => $scope } );
    unless (ref($scope_object)) {
      my $scope_objects = $master->Scope->get_objects( { 'name' => $scope } );
      if (scalar(@$scope_objects)) {
	$scope_object = $scope_objects->[0];
      } else {
	$application->add_message('warning', "Could not retrieve scope $scope from database, aborting.");
	return 0;
      }
    }
  } elsif (defined($login)) {
    my $user = $master->User->init( { 'login' => $login } );
    $scope_object = $user->get_user_scope();
    unless (ref($user)) {
      $application->add_message('warning', 'Could not get user from database, aborting');
      return 0;
    }
  } else {
    $application->add_message('warning', 'You must pass either login or scope, aborting.');
    return 0;
  }
  my $right_objects = $master->Rights->get_objects( { 'application' => $application->backend(),
						      'name' => $right,
						      'data_type' => $data_type,
						      'data_id' => $data_id,
						      'scope' => $scope_object } );

  unless (scalar(@$right_objects)) {
    $right_objects = $master->Rights->get_objects( { 'name' => $right,
						     'data_type' => $data_type,
						     'data_id' => $data_id,
						     'scope' => $scope_object } );
    unless (scalar(@$right_objects)) {
      $application->add_message('warning', 'right not found, aborting');
      return 0;
    }
  }

  $right_objects->[0]->granted(0);

  $application->add_message('info', "Right $right - $data_type - $data_id revoked.");

  return 1;
}

### End of Right Section

#########
# Users #
#########

### User Display Functions

sub user_list {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $html = "";

  my $table = $application->component('user_table');

  my $master = $application->dbmaster();
  my $users = $master->User->get_objects();
  
  $table->items_per_page(15);
  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->columns( [ { 'name' => 'Firstname', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'Lastname', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'Login', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'eMail', 'sortable' => 1, 'filter' => 1 },
		     { 'name' => 'Date', 'sortable' => 1 } ] );
  my $data = [];
  foreach my $user (@$users) {
    next unless $application->session->user->has_right($application, 'view', 'user', $user->login());
    if (scalar(@{$master->Rights->get_objects( { 'application' => $application->backend(),
						 'name' => 'login',
						 'scope' => $user->get_user_scope() } )})) {
      push(@$data, [ $user->firstname(),
		     $user->lastname(),
		     { 'data' => $user->login(), 'onclick' => $self->url . "login=" . $user->login() },
		     $user->email(),
		     $user->entry_date() ]);
    }
  }
  $table->data($data);

  $html .= $table->output();
  
  return $html;
}

sub user_details {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  my $login = $cgi->param('login');
  my $user = $master->User->init({ 'login' => $login });
  unless (ref($user)) {
    $application->add_message('warning', "user with login $login not found in database");
    return "";
  }

  # get all user scopes and add form to revoke them
  my $scopes = $user->scopes();
  my $scopes_field = "<b>Group Memberships</b><br>";
  foreach my $scope (@$scopes) {
    next if ref($scope->application()) && $scope->application()->name() ne $application->backend->name();
    if (!($application->session->user->has_right($application, 'edit', 'user', $login))) {
      $scopes_field .= $scope->name()."<br>";
    } elsif ($scope->name() ne 'user:'.$login) {
      $scopes_field .= $self->start_form( 'scope_form', { 'action' => 'revoke_scope',
							  'login' => $login,
							  'scope' => $scope->name() } );
      $scopes_field .= $scope->name()."<input type='submit' value='revoke'>";
      $scopes_field .= $self->end_form();
    }
  }

  # get all application scopes and check whether the user already has them, otherwise allow granting
  my $app_scopes = $master->Scope->get_objects();
  my $addable_scopes = [];
  foreach my $scope (@$app_scopes) {
    next unless $application->session->user->has_right($application, 'edit', 'scope', $scope->_id());
    next if $scope->name() =~ /^user:/;
    next if ref($scope->application()) && $scope->application()->name() ne $application->backend->name();
    my $has_scope = 0;
    foreach my $uscope (@$scopes) {
      if ($uscope->name() eq $scope->name()) {
	$has_scope = 1;
	last;
      }
    }
    unless ($has_scope) {
      push(@$addable_scopes, $scope);
    }
  }
  if (scalar(@$addable_scopes)) {
    
    $scopes_field .= "<hr><b>Available Groups</b><br>".$self->start_form( 'scope_form', { 'action' => 'grant_scope',
											  'login' => $login } );
    $scopes_field .= "<select name='scope'>";
    foreach my $scope (@$addable_scopes) {
      $scopes_field .= "<option value='" . $scope->name(). "'>" . $scope->name() . "</option>";
    }
    $scopes_field .= "</select><input type='submit' value='grant'>";
    $scopes_field .= $self->end_form();
  }

  # get user rights
  my $rights = $user->rights(1);
  my $rights_field = "<b>Granted Rights</b><table style='layout: fixed;'>";
  foreach my $right (@$rights) {
    next if ($right->application() && ($right->application->name() ne $application->backend->name()));
    if ($right->scope->name() ne $user->get_user_scope->name()) {
      $rights_field .= "<tr style='height: 20px;'><td>".$right->name() . " - " . $right->data_type() . " - " . $right->data_id() . " (from group " . $right->scope->name() . ")</td></tr>";
    } elsif (! $application->session->user->has_right($application, 'edit', 'user', $login)) {
      $rights_field .= "<tr style='height: 20px;'><td>".$right->name() . " - " . $right->data_type() . " - " . $right->data_id() . "</td></tr>";
    } else {
      $rights_field .= "<tr style='height: 20px;'><td>".$self->start_form( 'right_form', { 'action' => 'revoke_right',
											   'login' => $login,
											   'right' => $right->name(),
											   'data_type' => $right->data_type(),
											   'data_id' => $right->data_id() } );
      $rights_field .= $right->name() . " - " . $right->data_type() . " - " . $right->data_id() . "<input type='submit' value='revoke' style='height: 20px;'>";
      $rights_field .= $self->end_form()."</td></tr>";
    }
  }
  $rights_field .= "</table>";

  my $addable_rights = [];
  if ($application->session->user->has_right($application, 'edit', 'user', $login)) {
    # get all application rights and check whether the user already has them, otherwise allow granting
    my $app_rights = $application->rights();
    foreach my $right (@$app_rights) {
      next unless $application->session->user->has_right($application, $right->[0], $right->[1], $right->[2], 1);
      my $has_right = 0;
      foreach my $uright (@$rights) {
	next if ($uright->application() && ($uright->application->name() ne $application->backend->name()));
	if (($uright->name() eq $right->[0]) && ($uright->data_type() eq $right->[1]) && ($uright->data_id() eq $right->[2])) {
	  $has_right = 1;
	  last;
	}
      }
      unless ($has_right) {
	push(@$right, $application->backend());
	push(@$addable_rights, $right);
      }
    }
    # get all delegatable rights of the logged in user
    my $user_rights = $application->session->user->rights(1,1);
    foreach my $right (@$user_rights) {
      if (! $right->application() || $right->application->name() eq $application->backend->name()) {
	my $has_right = 0;
	foreach my $uright (@$rights) {
	  if (($uright->name() eq $right->name()) && ($uright->data_type() eq $right->data_type()) && ($uright->data_id() eq $right->data_id())) {
	    $has_right = 1;
	    last;
	  }
	}
	unless ($has_right) {
	  push(@$addable_rights, [ $right->name(), $right->data_type(), $right->data_id(), $right->application() ]);
	}
      }
    }
  }

  # if there are rights the user does not yet have, make them available for adding
  if (scalar(@$addable_rights)) {
    
    my $added_rights = {};
    $rights_field .= "<hr><b>Available Rights</b><br>".$self->start_form( 'right_form', { 'action' => 'grant_right',
											  'login' => $login } );
    $rights_field .= "<select name='right'>";
    foreach my $right (@$addable_rights) {
      my $right_display =  $right->[0] . " - " . $right->[1] . " - " . $right->[2];
      unless (exists($added_rights->{$right_display})) {
	my $app = $right->[3];
	if ($app) {
	  $app = $app->_id();
	} else {
	  $app = 'undef';
	}
	$rights_field .= "<option value='" . $app . " - $right_display'>$right_display</option>";
	$added_rights->{$right_display} = 1;
      }
    }
    $rights_field .= "</select><input type='checkbox' name='delegatable'>delegatable<input type='submit' value='grant'>";
    $rights_field .= $self->end_form();
  }

  # make email address editable
  my $email_field = $self->start_form('email_form', { login => $user->login(), action => 'change_email' });
  $email_field .= "<input type='text' name='email' value='" . $user->email() . "'><input type='submit' value='change'>";
  $email_field .= $self->end_form();  
  
  # details
  $html .= "<table width='400'>";
  $html .= "<tr><th>Firstname</th><td>" . $user->firstname() . "</td></tr>";
  $html .= "<tr><th>Lastname</th><td>" . $user->lastname() . "</td></tr>";
  $html .= "<tr><th>Login</th><td>" . $user->login() . "</td></tr>";
  $html .= "<tr><th>eMail</th><td>" . $email_field . "</td></tr>";
  $html .= "<tr><th>Date</th><td>" . $user->entry_date() . "</td></tr>";
  $html .= "<tr><th>Active</th><td>" . $user->active() . "</td></tr>";
  $html .= "<tr><th>Groups</th><td>" . $scopes_field . "</td></tr>";
  $html .= "<tr><th>Rights</th><td>" . $rights_field . "</td></tr>";
  $html .= "</table>";

  return $html;
}

sub new_users_list {
  my ($self) = @_;
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $html = "<div style='padding-left: 100px;'>- no new requests -</div>";
  
  # get all users that have an ungranted login right
  my $rights = $master->Rights->get_objects( { 'name' => 'login', 'granted' => 0, 'application' => $application->backend() } );
  if (scalar(@$rights)) {
    # get all groups that the user may administrate
    my $ascopes = $application->session->user->scopes();
    my $agroup_scopes = {};
    foreach my $scope (@$ascopes) {
      unless ($scope->application()) {
	if ($application->session->user->has_right($application, 'edit', 'scope', $scope->_id())) {
	  $agroup_scopes->{$scope->name()} = 1;
	}
      }
    }

    # there are open requests, print them
    my $table = $application->component('new_users_table');
    $table->columns( [ 'Firstname', 'Lastname', 'login', 'eMail', 'Date', 'Accept', 'Reject', 'Reason' ] );
    my $data = [];
    foreach my $right (@$rights) {
      $right->scope->name() =~ /^user\:(.+)$/;
      my $user = $master->User->init( { 'login' => $1 } );
      next unless $user;
      
      # check whether the currently logged in user may see this request
      my $may_see = 0;

      # if the current user has the explicit right
      if ($application->session->user->has_right($application, 'edit', 'user', $user->login())) {
	$may_see = 1;
      }

      # get all groups the requesting user is in
      my $uscopes = $user->scopes();
      foreach my $scope (@$uscopes) {
	if ($agroup_scopes->{$scope->name()}) {
	  # current user has the implicit right, because he owns the group
	  # the new user wants to be part of
	  $may_see = 1;
	}
      }
      
      if($may_see) {
	push(@$data, [ $user->firstname(), $user->lastname(),$user->login(), $user->email(), $user->entry_date(), "<input type='checkbox' name='" . $user->login() . ":accept'>", "<input type='checkbox' name='" . $user->login() . ":reject'>", "<input type='text' name='reason' value='-'>" ]);
      }
    }

    $table->data($data);
    $html = $self->start_form( 'user_activation_form', { 'action' => 'activate_users' } ).$table->output()."<input type='submit' value='submit'>".$self->end_form();
  }

  return $html;
}

sub new_user_form {
  my ($self) = @_;
  
  my $form = $self->start_form();
  $form .= "<table>";
  $form .= "<tr><th>Firstname</th><td><input type='text' name='firstname'></td></tr>";
  $form .= "<tr><th>Lastname</th><td><input type='text' name='lastname'></td></tr>";
  $form .= "<tr><th>eMail</th><td><input type='text' name='email'></td></tr>";
  $form .= "<tr><th>Login</th><td><input type='text' name='login'></td></tr>";
  $form .= "<tr><th>Password</th><td><input type='password' name='password'></td></tr>";
  $form .= "<tr><th>Confirm Password</th><td><input type='password' name='password_confirm'></td><td><input type='submit' value='Create'></td></tr></table><input type='hidden' name='action' value='add_user'>";
  $form .= $self->end_form();

  return $form;
}

### User Action Functions

sub add_user {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # get values from cgi
  my $email = $cgi->param('email');
  my $firstname = $cgi->param('firstname');
  my $lastname = $cgi->param('lastname');
  my $login = $cgi->param('login');
  my $password = $cgi->param('password');
  my $confirm_password = $cgi->param('password_confirm');

  # sanity checks
  unless (defined($email)) {
    $application->add_message('warning', 'You must enter an email address, aborting');
    return 0;
  }

  unless (defined($firstname)) {
    $application->add_message('warning', 'You must enter a first name, aborting');
    return 0;
  }

  unless (defined($lastname)) {
    $application->add_message('warning', 'You must enter a last name, aborting');
    return 0;
  }

  unless (defined($login)) {
    $application->add_message('warning', 'You must enter a login, aborting');
    return 0;
  }

  unless (defined($password)) {
    $application->add_message('warning', 'You must enter a password, aborting');
    return 0;
  }

  unless (defined($confirm_password)) {
    $application->add_message('warning', 'You must enter a confirmation of your password, aborting');
    return 0;
  }

  unless ($password eq $confirm_password) {
    $application->add_message('warning', 'Password and Confirm Password do not match, aborting');
    return 0;
  }

  my $user;
  if ($user = $master->User->init({ email => $email })) {
    $application->add_message('warning', "This email has already been registered for ".$user->login.", aborting.\n");
    return 0;
  }
  
  if ($user = $master->User->init({ login => $login })) {
    $application->add_message('warning',  "This login has already been registered for ".$user->firstname." ".$user->lastname.", aborting.\n");
    return 0;

  }
  
  # create the user in the db
  $user = $master->User->create( { email        => $email,
				   firstname    => $firstname,
				   lastname     => $lastname,
				   login        => $login,
				   active       => 1 } );
  
  $user->set_password($password);
  $user->add_login_right($application);
  $user->grant_login_right($application);

  $application->add_message('info', "User " . $user->firstname() . " " . $user->lastname() . " successfully added.");

  return 1;
}

sub activate_users {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $alist = [];
  my $dlist = [];
  my $drlist = [];

  my @reasons = $cgi->param('reason');
  my @params = $cgi->param();
  foreach my $param (@params) {
    if ($param =~ /^(.+)\:accept$/) {
      push(@$alist, $1);
      shift @reasons;
    } elsif ($param =~ /^(.+)\:reject$/) {
      push(@$dlist, $1);
      push(@$drlist, shift @reasons);
    }
  }

  foreach my $login (@$alist) {
    my $user = $master->User->init( { 'login' => $login } );
    if (ref($user)) {
      eval {
	$user->grant_login_right($application);
      };
      if ($@) {
	warn $@;
	$application->add_message('warning', "Could not grant login right from database for $login, aborting accept account request.");
      }
      else {
	$application->add_message('info', "Account request for $login accepted.");
      }
    } 
    else {
      $application->add_message('warning', "User $login not found, aborting accept account request.");
    }
  }

  foreach my $login (@$dlist) {
    my $user = $master->User->init( { 'login' => $login } );
    if (ref($user)) {
      my $reason = shift @$drlist;
      $reason = '' if ($reason eq '-');
      eval {
	$user->deny_login_right($application, $reason);
      };
      if ($@) {
	warn $@;
	$application->add_message('warning', "Could not deny login right from database for $login, aborting accept account request.");
      }
      else {
	$application->add_message('info', "Account request for $login denied.");
      }
    }
    else {
      $application->add_message('warning', "User $login not found, aborting deny account request.");
    }
  }

  return 1;
}

sub change_email {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  unless (defined($cgi->param('email')) && defined($cgi->param('login'))) {
    $application->add_message('warning', 'could not change email - insufficient parameters');
    return 0;
  }

  my $user = $master->User->init( { login => $cgi->param('login') } );
  
  # check if a new email was submitted
  if ($master->User->init( { email => $cgi->param('email') } ) ) {
    $application->add_message('warning', "email " . $cgi->param('email') . " already in use. User email will <b>not</b> change.");
  } else {
    $user->email($cgi->param('email'));
      $application->add_message('info', "user email successfully changed to ".$user->email());
  }

  return 1;
}

### End of User Section

##########
# Scopes #
##########

### Scope displays

sub scopes_list {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  my $table = $application->component('scopes_table');

  my $scopes = $master->Scope->get_objects();
  $table->columns( [ 'Name', 'Description' ] );
  my $data = [];
  foreach my $scope (@$scopes) {
    next if ($scope->name() =~ /^user\:/);
    next if ref($scope->application()) && $scope->application()->name() ne $application->backend->name();
    next unless $application->session->user->has_right($application, 'edit', 'scope', $scope->_id());
    push(@$data, [ { 'data' => $scope->name(), 'onclick' => $self->url . "scope=" . $scope->name() },
		   $scope->description() ] );
  }
  $table->data($data);
  $html .= $table->output();
}

sub scope_details {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  my $scope = $cgi->param('scope');
  my $scope_object = $master->Scope->init({ 'name' => $scope, 'application' => $application->backend() });
  unless (ref($scope_object)) {
    my $possible_scopes = $master->Scope->get_objects({ 'name' => $scope });
    if (scalar(@$possible_scopes)) {
      $scope_object = $possible_scopes->[0];
    } else {
      $application->add_message('warning', "scope with name $scope not found in database");
      return "";
    }
  }

  # get all user scopes and add form to revoke them
  my $users = $scope_object->users();
  my $users_field = "<b>Users</b><br>";
  foreach my $user (@$users) {
    if ($application->session->user->has_right($application, 'edit', 'scope', $scope_object->_id())) {
      my $pending = "";
      unless ($user->has_right($application, 'login')) {
	$pending = " (authorization pending)";
      }
      $users_field .= $self->start_form( 'scope_form', { 'action' => 'revoke_scope',
							 'login' => $user->login(),
							 'scope' => $scope_object->name() } );
      $users_field .= $user->firstname()." ".$user->lastname().$pending."<input type='submit' value='remove'>";
      $users_field .= $self->end_form();
    } else {
      $users_field .= $user->firstname()." ".$user->lastname()."<br>";
    }
  }

  # get all application users and check whether the scope already has them, otherwise allow granting
  if ($application->session->user->has_right($application, 'edit', 'scope', $scope_object->_id())) {
    my $app_users = $master->User->get_objects();
    my $addable_users = [];
    foreach my $user (@$app_users) {
      if (scalar(@{$master->Rights->get_objects( { 'application' => $application->backend(),
						   'name' => 'login',
						   'scope' => $user->get_user_scope() } )})) {
	next unless $application->session->user->has_right($application, 'view', 'user', $user->login());
	my $has_user = 0;
	foreach my $suser (@$users) {
	  if ($suser->login() eq $user->login()) {
	    $has_user = 1;
	    last;
	  }
	}
	unless ($has_user) {
	  push(@$addable_users, $user);
	}
      }
    }
    if (scalar(@$addable_users)) {
      
      $users_field .= "<hr><b>Available Users</b><br>".$self->start_form( 'scope_form', { 'action' => 'grant_scope',
											  'scope' => $scope } );
      $users_field .= "<select name='login'>";
      foreach my $user (@$addable_users) {
	$users_field .= "<option value='" . $user->login(). "'>" . $user->firstname() . " " . $user->lastname() . "</option>";
      }
      $users_field .= "</select><input type='submit' value='add'>";
      $users_field .= $self->end_form();
    }
  }

  # get user rights
  my $rights = $scope_object->rights(1);
  my $rights_field = "<b>Granted Rights</b><br>";
  foreach my $right (@$rights) {
    next if ($right->application() && ($right->application->name() ne $application->backend->name()));
    if ($application->session->user->has_right($application, 'edit', 'scope', $scope_object->_id())) {
      $rights_field .= $self->start_form( 'right_form', { 'action' => 'revoke_right',
							  'scope' => $scope,
							  'right' => $right->name(),
							  'data_type' => $right->data_type(),
							  'data_id' => $right->data_id() } );
      $rights_field .= $right->name() . " - " . $right->data_type() . " - " . $right->data_id() . "<input type='submit' value='revoke'>";
      $rights_field .= $self->end_form();
    } else {
      $rights_field .= $right->name() . " - " . $right->data_type() . " - " . $right->data_id();
    }
  }

  if ($application->session->user->has_right($application, 'edit', 'scope', $scope_object->_id())) {
    
    # get all application rights and check whether the scope already has them, otherwise allow granting
    my $app_rights = $application->rights();
    my $addable_rights = [];
    foreach my $right (@$app_rights) {
      next unless $application->session->user->has_right($application, $right->[0], $right->[1], $right->[2]);
      my $has_right = 0;
      foreach my $uright (@$rights) {
	next if ($uright->application() && ($uright->application->name() ne $application->backend->name()));
	if (($uright->name() eq $right->[0]) && ($uright->data_type() eq $right->[1]) && ($uright->data_id() eq $right->[2])) {
	  $has_right = 1;
	  last;
	}
      }
      push(@$right, $application);
      unless ($has_right) {
	push(@$addable_rights, $right);
      }
    }

    # get all delegatable rights of the logged in user
    my $user_rights = $application->session->user->rights(1,1);
    foreach my $right (@$user_rights) {
      if (! $right->application() || $right->application->name() eq $application->backend->name()) {
	my $has_right = 0;
	foreach my $uright (@$rights) {
	  if (($uright->name() eq $right->name()) && ($uright->data_type() eq $right->data_type()) && ($uright->data_id() eq $right->data_id())) {
	    $has_right = 1;
	    last;
	  }
	}
	unless ($has_right) {
	  push(@$addable_rights, [ $right->name(), $right->data_type(), $right->data_id(), $right->application() ]);
	}	
      }
    }
    
    # if there are rights the scope does not yet have, make them available for adding
    if (scalar(@$addable_rights)) {

      my $added_rights = {};
      $rights_field .= "<hr><b>Available Rights</b><br>".$self->start_form( 'right_form', { 'action' => 'grant_right',
											    'scope' => $scope } );
      $rights_field .= "<select name='right'>";
      foreach my $right (@$addable_rights) {
	my $right_display =  $right->[0] . " - " . $right->[1] . " - " . $right->[2];
	unless (exists($added_rights->{$right_display})) {
	  my $app = $right->[3];
	  if ($app) {
	    $app = $app->{_id};
	  } else {
	    $app = 'undef';
	  }
	  $rights_field .= "<option value='" . $app . " - $right_display'>$right_display</option>";
	  $added_rights->{$right_display} = 1;
	}
      }
      $rights_field .= "</select><input type='submit' value='grant'>";
      $rights_field .= $self->end_form();
    }
  }

  # details
  $html .= "<table width='400'>";
  $html .= "<tr><th>Name</th><td>" . $scope . "</td></tr>";
  $html .= "<tr><th>Description</th><td>" . $scope_object->description() . "</td></tr>";
  $html .= "<tr><th>Users</th><td>" . $users_field . "</td></tr>";
  $html .= "<tr><th>Rights</th><td>" . $rights_field . "</td></tr>";
  $html .= "</table>";
  
  return $html;
}

sub new_scope_form {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $html = "";

  $html .= $self->start_form( 'add_scope_form', { 'action' => 'add_scope' } );
  $html .= "<table>";
  $html .= "<tr><th>Name</th><td><input type='text' name='scope'></td></tr>";
  $html .= "<tr><th>Description</th><td><input type='text' name='description'></td><td><input type='submit' value='Create'></td></tr>";
  $html .= "</table>";
  $html .= $self->end_form();

  return $html;
}

### Scope actions

sub add_scope {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $scope = $cgi->param('scope');
  unless (defined($scope)) {
    $application->add_message('warning', 'You must define a group name, aborting.');
    return 0;
  }
  my $description = $cgi->param('description') || "";

  my $scope_object = $master->Scope->init( { 'name' => $scope, 'application' => $application->backend() } );
  if (ref($scope_object)) {
    $application->add_message('warning', 'Group $scope already exists, aborting.');
    return 0;
  } else {
    $scope_object = $master->Scope->create( { 'name' => $scope, 'description' => $description } );
    $master->Rights->create( { 'application' => $application->backend(),
			       'name' => 'edit',
			       'data_type' => 'scope',
			       'data_id' => $scope_object->_id(),
			       'granted' => 1,
			       'scope' => $application->session->user->get_user_scope() } );
  }
  unless (ref($scope_object)) {
    $application->add_message('warning', 'Could not create group');
    return 0;
  }

  $application->add_message('info', "Group $scope added successfully.");

  return 1;
}

sub grant_scope {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $scope = $cgi->param('scope');
  if (defined($scope)) {
    $scope = $master->Scope->get_objects( { 'name' => $scope } );
    if (scalar(@$scope)) {
      $scope = $scope->[0];
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

  $application->add_message('info', $user->firstname() . ' ' . $user->lastname() .' added to group ' . $scope->name().'.');
}

sub revoke_scope {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  my $scope = $cgi->param('scope');
  if (defined($scope)) {
    my $poss_scopes = $master->Scope->get_objects( { 'name' => $scope } );
    $scope = $master->Scope->init( { 'name' => $scope, 'application' => $application->backend() } );
    unless (ref($scope)) {
      if (scalar(@$poss_scopes) == 1) {
	$scope = $poss_scopes->[0];
      } else {
	$application->add_message('warning', 'Could not retrieve scope from database.');
	return 0;
      }
    }
  } else {
    $application->add_message('warning', 'You must define a scope name, aborting.');
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

### End of Scope Section

sub required_rights {
  return [ [ 'login' ] ];
}

sub supported_rights {
  return [ [ 'view', 'user', '*' ], [ 'add', 'user', '*' ], [ 'delete', 'user', '*' ], [ 'edit', 'user', '*' ], [ 'view', 'scope', '*' ], [ 'add', 'scope', '*' ], [ 'delete', 'scope', '*' ], [ 'edit', 'scope', '*' ] ];
}
