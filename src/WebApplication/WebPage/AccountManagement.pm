package WebPage::AccountManagement;

use base qw( WebPage );

1;

use strict;
use warnings;

use Conf;

use HTML::Entities;

=pod

=head1 NAME

AccountManagement - an instance of WebPage which offers users the ability to change things about their account

=head1 DESCRIPTION

Offers users the ability to change things about their account

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->application->register_action($self, 'change_user_details', 'change_user_details');
  $self->application->register_action($self, 'handle_user_requests', 'handle_user_requests');
  $self->application->register_action($self, 'impersonate_user', 'impersonate_user');
  $self->title('Account Management');
  $self->omit_from_session(1);

  return 1;
}

=item * B<output> ()

Returns the html output of the AccountManagement page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # check which scopes the user may edit
  my $editable_scopes = [];
  my $editable_users = 0;
  foreach my $scope (@{$user->scopes()}) {
    my $ess = $master->Rights->get_objects( { name => 'edit', data_type => 'scope', scope => $scope, granted => 1 } );
    foreach my $s (@$ess) {
      if ($s->data_id() ne '*') {
	push(@$editable_scopes, $s);
      }
    }
    my $eu = $master->Rights->get_objects( { name => 'view', data_type => 'user', scope => $scope, granted => 1 } );
    if (scalar(@$eu)) {
      $editable_users = 1;
    }
  }

  # check if there are open requests this user has the right to handle
  my $user_requests = [];

  # first get the scopes the user has access to
  my $user_scopes = $master->UserHasScope->get_objects( { 'user' => $user, 'granted' => 1 } );

  # now check which of these scopes the user may edit
  my $user_admin_scopes = [];
  foreach my $user_scope (@$user_scopes) {
    next if $user_scope->scope->application();
    next if $user_scope->scope->name() =~ /^project:/;
    if ($user->has_right($application, 'edit', 'scope', $user_scope->{_id})) {
      push(@$user_admin_scopes, $user_scope->scope());
    }
  }

  # check if there are any non-granted UserHasScopes for these scopes
  foreach my $user_admin_scope (@$user_admin_scopes) {
    my $scope_requests = $master->UserHasScope->get_objects( { 'granted' => 0, scope => $user_admin_scope } );
    foreach my $scope_request (@$scope_requests) {
      push(@$user_requests, { 'user' => $scope_request->user(),
			      'type' => 'group',
			      'group' => $scope_request->scope() });
    }
  }

  # check if the user may view registration requests for this application
  if ($user->has_right($application, 'view', 'registration_mail', '*')) {

    # check if there are any open requests for login rights to this application
    my $login_requests = $master->Rights->get_objects( { 'application' => $application->backend(),
							 'name' => 'login',
							 'granted' => 0 } );
    foreach my $login_request (@$login_requests) {
      my $request_user = $master->UserHasScope->get_objects( { scope => $login_request->scope() } )->[0]->user();
      push(@$user_requests, { 'user' => $request_user,
			      'type' => 'application',
			      'group' => $application->backend() });
    }
  }

  # start the html
  my $html = "<h2>Account Management</h2>";

  # this table contains the different portions of the account management
  $html .= "<table><tr><td>";

  # personal user information
  $html .= "<h2>Personal Information</h2>";

  my $formstart = undef;
  eval {
    use Conf;
    if ($Conf::secure_url) {
      $formstart = "<form method='post' id='user_form' enctype='multipart/form-data' action='".$Conf::secure_url.$self->application->url()."' style='margin: 0px; padding: 0px;'>\n".$self->application->cgi->hidden(-name=>'action', -id=>'action', -value=>'change_user_details', -override=>1).$self->application->cgi->hidden(-name=>'page', -value=>'AccountManagement', -override=>1);  
    }
  };
  if (! $formstart) {
    $formstart = $self->application->page->start_form('user_form', { action => 'change_user_details' });
  }

  $html .= $formstart;
  $html .= "<table>";
  $html .= "<tr><th> name</th><td><input type='text' name='firstname' value='" . encode_entities($user->firstname()) . "'></td></tr>";
  $html .= "<tr><th>last name</th><td><input type='text' name='lastname' value='" . encode_entities($user->lastname()) . "'></td></tr>";
  $html .= "<tr><th>eMail</th><td><input type='text' name='email' value='" . encode_entities($user->email()) . "'></td></tr>";
  $html .= "<tr><th>login</th><td>" . encode_entities($user->login()) . "</td></tr>";
  $html .= "<tr><th>password</th><td><input type='password' name='password'></td></tr>";
  $html .= "<tr><th>confirm password</th><td><input type='password' name='confirm_password'></td></tr>";
  $html .= "</table>";
  $html .= "<input type='submit' value='perform changes'>";
  $html .= $self->end_form();

  # check if the user may view or edit other users
  if ((scalar(@{$user->has_right_to(undef, 'edit', 'user')}) > 1) || ($user->has_right($application, 'edit', 'user', '*'))) {
    $html .= "<br/>";
    $html .= "<h2>Administrate Users</h2>";
    $html .= $self->start_form('manage_users_form', { page => 'UserManagement' } );
    $html .= "<p>You have the right to edit other users</p>";
    $html .= "<p>click <b>manage users</b> to do so. <input type='submit' value='manage users'></p>";
    $html .= $self->end_form();
  }

  if ($user->has_right($application, 'edit', 'user', '*')) {
    $html .= "<br/>";
    $html .= "<h2>Administrate Organizations</h2>";
    $html .= $self->start_form('manage_orgs_form', { page => 'OrganizationManagement' } );
    $html .= "<p>You have the right to edit organizations</p>";
    $html .= "<p>click <b>manage organizations</b> to do so.<br><input type='submit' value='manage organizations'></p>";
    $html .= $self->end_form();
  }

  $html .= "</td><td style='padding-left: 25px;'>";

  # show a link to the preferences
  unless ($Conf::no_prefs) {
    $html .= "<h2>Preferences</h2>";
    $html .= $self->start_form('preferences_form', { page => 'ManagePreferences' } );
    $html .= "<p>To manage your personal preferences, please click <input type='submit' value='here'></p>";
    $html .= $self->end_form();
  }

  # go through the manageable requests and offer handling options
  if (scalar(@$user_requests)) {
    $html .= "<h2>User Requests</h2>";
    $html .= $self->start_form('user_request_form', { action => 'handle_user_requests', num_requests => scalar(@$user_requests) });
    $html .= "<table><tr><th>Request</th><th>Accept</th><th>Reject</th><th>Defer</th><th>Reason</th></tr>";
    my $i=0;
    foreach my $request (@$user_requests) {
      my $request_text = $request->{user}->firstname() . " " . $request->{user}->lastname() . " is requesting access to the " . $request->{type} . " " . $request->{group}->name();
      $html .= "<tr><td>$request_text<input type='hidden' name='group_$i' value='" . $request->{group}->name() . "'><input type='hidden' name='type_$i' value='" . $request->{type} . "'><input type='hidden' name='login_$i' value=\"".$request->{user}->login()."\"></td><td><input type='Radio' name='handling_$i' value='accept'></td><td><input type='radio' name='handling_$i' value='reject'></td><td><input type='radio' name='handling_$i' value='defer' checked='checked'></td><td><input type='text' name='reason_$i' value='-'></td></tr>";
      $i++;
    }
    $html .= "</table><input type='submit' value='submit'>";
    $html .= $self->end_form();
    $html .= "<br/>";
  }

  # check which scopes the user is in
  my $user_has_scopes = $master->UserHasScope->get_objects( { user => $user, granted => 1 } );

  # check if this is a RAST server
  if ($Conf::rast_jobs) {
    $html .= "<h2>Private Organism Preferences</h2>";
    $html .= "<p style='width: 400px;'>To change the set of your private organisms to be included into your data views click <b>Private Organisms Preferences</b> below.</p><input type='button' value='Private Organism Preferences' onclick='window.top.location=\"?page=PrivateOrganismPreferences\"'>";
  }
  
  # check if the user is in more than one group (his own) and display them if so
  if (scalar(@$user_has_scopes) > 1) {
    $html .= "<h2>Your Group Memberships</h2>";
    $html .= "<p>You are part of the following groups (click to see all members)</p>";
    $html .= qq~<script>function sh_gm (id) {
var x = document.getElementById('gm'+id);
if (x.style.display == 'none') {
x.style.display = 'inline';
} else {
x.style.display = 'none';
}
}</script>~;
    my $i = 1;
    foreach my $user_has_scope (@$user_has_scopes) {
      my $scope = $user_has_scope->scope();
      next if $scope->name() =~ /^user:/;
      next if $scope->name() =~ /^project:/;
      next if $scope->name() =~/^Public/;
      my $sapp = $scope->application();
      if ($sapp) {
	$sapp = " in application ".$sapp->name();
      } else {
	$sapp = "";
      }
      
      # find out who else is in this group
      my $others = $master->UserHasScope->get_objects( { scope => $scope } );
      my $others_list = "";
      @$others = sort { lc($a->user->lastname()) cmp lc($b->user->lastname()) || lc($a->user->firstname()) cmp lc($b->user->firstname()) } @$others;
      foreach my $other (@$others) {
	$others_list .= "&nbsp;&nbsp;&nbsp;".$other->user->lastname() . ", " . $other->user->firstname() . "<br>";
      }
      $html .= "<span style='color: blue; text-decoration: underline; cursor: pointer;' onclick='sh_gm(\"$i\");'>".$scope->name().$sapp."</span><br><span id='gm$i' style='display: none;'>".$others_list."<br></span>";
      $i++;
    }
  }
  
  if (scalar(@$editable_scopes)) {
    $html .= "<h2>Administrate Groups</h2>";
    $html .= "<p>Select a group to administrate and click <b>OK</b></p>";
    $html .= $self->start_form('group_admin_form', { page => 'GroupAdmin' } );
    $html .= "<select name='group'>";
    @$editable_scopes = map { $master->Scope->get_objects( { _id => $_->data_id() } )->[0] } @$editable_scopes;
    @$editable_scopes = sort { $a->name() cmp $b->name() } @$editable_scopes;
    foreach my $scope_object (@$editable_scopes) {
	next if ($scope_object->name =~/^Public/);
	next if ($scope_object->name() =~ /^project:/);
      $html .= "<option value='" . $scope_object->name() . "'>" . $scope_object->name() . "</option>";
    }
    $html .= "</select>";
    $html .= "<input type='submit' value='OK'>";
    $html .= $self->end_form();
    $html .= "<br />";
  }

  if ($user->has_right(undef, 'impersonate', 'user', '*')) {
    $html .= "<h2>Impersonate User</h2>";
    $html .= $self->start_form('impersonate_user_form', { action => 'impersonate_user' } );
	$html .= "<p>Select user to impersonate.</p>";
	my $user_select = "<select name='login'><option></option>";
	my $users_to_impersonate = $master->User->get_objects();
	foreach $user (sort{lc($a->lastname()) cmp lc($b->lastname())}@$users_to_impersonate){
		$user_select .= "<option value='".$user->login()."'>".$user->lastname().", ".$user->firstname()." (".$user->login().")</option>";
	}
	$user_select .= "</select> <input type='submit' value='switch user'>";
    $html .= $user_select . $self->end_form();
    $html .= "<br />";
  }

  if ($user->has_right($application, 'add', 'scope')) {
    $html .= "<h2>Create Group</h2>";
    $html .= $self->start_form('create_group_form', { page => 'GroupAdmin', action => 'create_group' } );
    $html .= "<p>You have the right to create groups.</p>";
    $html .= "<p>Enter a group name and click <b>create</b> to create a group<br /><input type='text' name='new_group'><input type='submit' value='create'></p>";
    $html .= $self->end_form();
  }

#   if (scalar(@{$user->scopes()}) == 1) {
#     $html .= "<h2>Group Membership</h2>";
#     $html .= "<p>You are currently not in any group. If any of the following apply to you, please click <b>Request Group</b> below.</p>";
#     $html .= "<ul>";
#     $html .= "<li>a group administrator has provided you the name of a group you want to become a member of</li>";
#     $html .= "<li>you frequently want to delegate rights to a group of users</li>";
#     $html .= "</ul>";
#     $html .= $self->start_form('request_group_form', { page => 'RequestGroup' })."<input type='submit' value='Request Group'>".$self->end_form();
#   }

  $html .= "</td></tr></table>";

  return $html;
}

sub change_user_details {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # check for name change
  if ($cgi->param('firstname') ne $user->firstname()) {
    $user->firstname($cgi->param('firstname'));
    $application->add_message('info', 'First name changed successfully');
  }
  if ($cgi->param('lastname') ne $user->lastname()) {
    $user->lastname($cgi->param('lastname'));
    $application->add_message('info', 'Last name changed successfully');
  }

  # check for eMail change
  if ($user->email() ne $cgi->param('email')) {
    if ($master->User->init( { email => $cgi->param('email') } )) {
      $application->add_message('warning', 'Email already in use by another account, aborting email change.');
    } else {
      $user->email($cgi->param('email'));
      $application->add_message('info', 'Email changed successfully');
    }
  }

  # check for new password
  if (defined($cgi->param('password')) && $cgi->param('password') ne '') {
    if (defined($cgi->param('confirm_password')) && $cgi->param('confirm_password') eq $cgi->param('password')) {
      $user->set_password($cgi->param('password'));
      $application->add_message('info', 'You have successfully changed your password.');
    } else {
      $application->add_message('warning', 'Password and confirm password do not match, aborting password change.');
    }
  }

  return 1;
}

sub impersonate_user {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();
  
  my $user_to_impersonate = $master->User->init({ login=>$cgi->param('login') });   
  if($user->has_right(undef, 'impersonate', 'user', '*')){
  	$application->session->user($user_to_impersonate);
  	$self->application()->add_message('info', 'You are now '.$application->session->user()->login().'.' , 5);
  } else {
  	$self->application()->add_message('warning', 'You can not impersonate users.', 5);
  }
 
  return 1;
}

# handling the user request action
sub handle_user_requests {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  
  # find out how many requests we have
  my $num_requests = $cgi->param('num_requests') || 0;
  
  # iterate over the requests
  for (my $i=0; $i<$num_requests; $i++) {
    
    # get the cgi params
    my $group = $cgi->param("group_$i");
    my $type = $cgi->param("type_$i");
    my $login = $cgi->param("login_$i");
    my $handling = $cgi->param("handling_$i");
    my $reason = $cgi->param("reason_$i") || "";
    
    # sanity check if all necessary params are set
    next unless (defined($group) && defined($type) && defined($login) && defined($handling));
    
    # if the handling is defer, we don't worry about this entry
    next if ($handling eq "defer");
    
    # if we reach here, we want to do something with the requestor, get him from the db
    my $requestor = $master->User->init( { login => $login } );
    
    unless (defined($requestor)) {
      $application->add_message("warning", "Could not find user $login, request aborted.");
      next;
    }
    
    # if the request type is application, we are talking about a login right
    if ($type eq "application") {

      my $mailinglists = $application->dbmaster->Preferences->get_objects( { user => $requestor, name => 'mailinglist' } );
      
      # if the handling is reject, send the requestor note of the event and delete the request
      if ($handling eq "reject") {
	$application->add_message("info", "Login right to ".$group." denied for ".$requestor->firstname()." ".$requestor->lastname().".");
	if (scalar(@$mailinglists)) {
	  $mailinglists->[0]->delete();
	}
	$requestor->deny_login_right($application, $reason);
      }
      # the handling must now be accept, grant the login right
      else {
	$requestor->grant_login_right($application);

	# check for mailinglist
	if (scalar(@$mailinglists)) {
	  $mailinglists->[0]->delete();
	  my $ml = "https://lists.mcs.anl.gov/mailman/subscribe/mg-rast-users";
	  my $email = $requestor->email;
	  my $firstname = $requestor->firstname;
	  my $lastname = $requestor->lastname;
	  my $pw = "microbiome";
	  `curl -s "$ml?email=$email&fullname=$firstname%20$lastname&pw=$pw&pw-conf=$pw&digest=0&email-button=Subscribe"`;
	}

	$application->add_message("info", "Login right to ".$group." granted to ".$requestor->firstname()." ".$requestor->lastname().".");
      }
    }
    # if the request type is group, we want access to a group
    elsif ($type eq "group") {
      
      my $group_scope = $master->Scope->init( { name => $group, application => undef } );
      unless (defined($group_scope)) {
	$application->add_message("warning", "Group $group not found, aborting.");
	next;
      }
      
      # the handling is reject, send the requestor a note of the event and delete the request
      if ($handling eq "reject") {
	$requestor->deny_group_access($group_scope, $reason);
	$application->add_message("info", "Access to group $group denied for ".$requestor->firstname()." ".$requestor->lastname().".");
      }
      # the handling must now be accept, grant access to the group
      else {
	$requestor->grant_group_access($group_scope);$application->add_message("info", "Access to group $group granted to ".$requestor->firstname()." ".$requestor->lastname().".");
      }
    }
  }
  
  return "";
}

# rights required to view this page
sub required_rights {
  my $rights = [ [ 'login' ] ];
  if ($_[0]->app->session->user) {
    push @$rights, [ 'edit', 'user', $_[0]->app->session->user->_id ];
  }
  return $rights;
}
