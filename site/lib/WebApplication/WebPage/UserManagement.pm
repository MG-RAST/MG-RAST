
package WebPage::UserManagement;

use base qw( WebPage );

1;

use strict;
use warnings;

=pod

=head1 NAME

UserManagement - an instance of WebPage which offers an admin the ability to change things about other accounts

=head1 DESCRIPTION

Offers adminss the ability to change things about other accounts

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('User Management');
  $self->application->register_component('Table', 'UserTable');
  $self->application->register_component('Table', 'UserRightsTable');
  $self->application->register_action($self, 'change_user_details', 'change_user_details');

  return 1;
}

=item * B<output> ()

Returns the html output of the UserManagement page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # get the users which the logged in user may view
  my $viewable_ids = $user->has_right_to(undef, 'view', 'user');
  if ($user->has_right($application, 'view', 'user', '*')) {
    $viewable_ids = [ '*' ];
  }
  my $viewable_users = [];
  foreach my $id (@$viewable_ids) {
    if ($id eq '*') {
      $viewable_users = $master->User->get_objects();
      last;
    }
    push(@$viewable_users, $master->User->get_objects( { _id => $id } )->[0]);
  }

  # pre-sort the users by lastname, firstname
  @$viewable_users = sort { $a->lastname cmp $b->lastname || $a->firstname cmp $b->firstname } @$viewable_users;

  # get the users which the logged in user may edit
  my $editable_ids = $user->has_right_to(undef, 'edit', 'user');
  if ($user->has_right($application, 'edit', 'user', '*')) {
    $editable_ids = [ '*' ];
  }
  my $editable_users = {};
  foreach my $id (@$editable_ids) {
    if ($id eq '*') {
      my $all_users = $master->User->get_objects();
      %$editable_users = map { $_->{_id} => 1 } @$all_users;
      last;
    }
    $editable_users->{$id} = 1;
  }

  # set up the user table
  my $user_table = $application->component('UserTable');
  $user_table->show_top_browse(1);
  $user_table->show_bottom_browse(1);
  $user_table->show_select_items_per_page(1);
  $user_table->items_per_page(20);
  $user_table->width(750);
  $user_table->columns( [ { name => 'Firstname', sortable => 1, filter => 1 },
			  { name => 'Lastname', sortable => 1, filter => 1 },
			  { name => 'Login', sortable => 1, filter => 1 },
			  { name => 'eMail', sortable => 1, filter => 1 },
			  { name => 'Entry Date', sortable => 1 },
			  { name => 'Active', sortable => 1, filter => 1, operator => 'combobox' },
			  { name => 'Edit' } ] );

  # push the users into the user table
  my $user_table_data = [];
  foreach my $vu (@$viewable_users) {
    my $edit_button = "";
    if ($editable_users->{$vu->{_id}}) {
      $edit_button = "<input type='button' onclick='window.top.location=\"".$application->url."?page=UserManagement&edit_user=" . $vu->{_id} . "\"' value='edit'>";
    }

    push(@$user_table_data, [ $vu->firstname, $vu->lastname, $vu->login, $vu->email, $vu->entry_date, $vu->active, $edit_button ]);
  }
  $user_table->data($user_table_data);

  # construct the html
  my $html = "";

  # create a layouting table
  $html .= "<table><tr><td><h2>List of Manageable Users</h2>";

  # add the user table to the content
  $html .= $user_table->output();

  $html .= "</td><td>";

  # if edit user is requested, check if the logged in user has the right to edit
  # (someone might have tweaked the url) then display the editable details
  if ($cgi->param('edit_user')) {
    my $edit_user = $master->User->get_objects( { _id => $cgi->param('edit_user') } );
    if (scalar(@$edit_user)) {
      $edit_user = $edit_user->[0];

      if ($user->has_right(undef, 'edit', 'user', $edit_user->{_id}) || $user->has_right($application, 'edit', 'user', '*')) {

	# check if the user is in an organization
	my $org_users = $master->OrganizationUsers->get_objects( { user => $edit_user } );
	my $org = "-";
	if (scalar(@$org_users)) {
	  $org = "<a href='?page=OrganizationManagement&edit=".$org_users->[0]->organization->{_id}."'>".$org_users->[0]->organization->name."</a>";
	}
	
	$html .= "<h2>User Information</h2>";
	$html .= $self->start_form('edit_user_form', { action => 'change_user_details', edit_user => $edit_user->{_id} } );
	$html .= "<table>";
	$html .= "<tr><th>first name</th><td><input type='text' name='firstname' value='" . $edit_user->firstname() . "'></td></tr>";
	$html .= "<tr><th>last name</th><td><input type='text' name='lastname' value='" . $edit_user->lastname() . "'></td></tr>";
	$html .= "<tr><th>eMail</th><td><input type='text' name='email' value='" . $edit_user->email() . "'></td></tr>";
	$html .= "<tr><th>login</th><td>" . $edit_user->login() . "</td></tr>";
	$html .= "<tr><th>Organization</th><td>".$org."</td></tr>";
	$html .= "</table>";
	$html .= "<input type='submit' class='button' value='perform changes'>";
	$html .= $self->end_form();

	# get the user's group information
	my $eugroups = $edit_user->scopes();
	$html .= "<h2>User Groups</h2>";
	$html .= "<table><tr><th>Name</th><th>Application</th></tr>";
	foreach my $eugroup (@$eugroups) {
	  my $euapplication = '-';
	  if ($eugroup->application()) {
	    $euapplication = $eugroup->application->name();
	  }
	  $html .= "<tr><td>".$eugroup->name()."</td><td>".$euapplication."</td></tr>";
	}
	$html .= "</table>";

	# get the user's rights
	$html .= "<h2>User Rights</h2>";
	my $eurights = $edit_user->rights();
	my $rights_table = $application->component('UserRightsTable');
	$rights_table->columns( [ { name => 'Type', filter => 1, operator => 'combobox' }, { name => 'Name', filter => 1, operator => 'combobox' }, { name => 'ID', filter => 1 }, { name => 'Application', filter => 1, operator => 'combobox' }, { name => 'granted', filter => 1, operator => 'combobox' } ] );
	$rights_table->show_top_browse(1);
	$rights_table->show_bottom_browse(1);
	$rights_table->items_per_page(15);
	my $rights_data = [];
	foreach my $euright (@$eurights) {
	  my $euapplication = "-";
	  if ($euright->application()) {
	    $euapplication = $euright->application->name();
	  }
	  push(@$rights_data, [$euright->data_type(),$euright->name(),$euright->data_id(),$euapplication,$euright->granted()]);
	}
	$rights_table->data($rights_data);
	$html .= $rights_table->output();

      } else {
	$application->add_message("warning", "You do not have the right to edit this user.");
      }
    } else {
      $application->add_message("warning", "User to change could not be found in the database.");
    }
  }

  $html .= "</td></tr></table>";
  
  # return the content
  return $html;
}

# rights required to view this page
sub required_rights {
  return [ [ 'login' ] ];
}

sub change_user_details {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  my $edit_user = $master->User->get_objects( { _id => $cgi->param('edit_user') } );
  if (scalar(@$edit_user)) {
    $edit_user = $edit_user->[0];
  } else {
    $application->add_message("warning", "User to change could not be found in the database.");
    return 0;
  }

  if ($user->has_right(undef, 'edit', 'user', $edit_user->{_id}) || $user->has_right($application, 'edit', 'user', '*')) {
    
    # check for name change
    if ($cgi->param('firstname') ne $edit_user->firstname()) {
      $edit_user->firstname($cgi->param('firstname'));
      $application->add_message('info', 'First name changed successfully');
    }
    if ($cgi->param('lastname') ne $edit_user->lastname()) {
      $edit_user->lastname($cgi->param('lastname'));
      $application->add_message('info', 'Last name changed successfully');
    }
    
    # check for eMail change
    if ($edit_user->email() ne $cgi->param('email')) {
      if ($master->User->init( { email => $cgi->param('email') } )) {
	$application->add_message('warning', 'Email already in use by another account, aborting email change.');
      } else {
	$edit_user->email($cgi->param('email'));
	$application->add_message('info', 'Email changed successfully');
      }
    }
    
#     # check for login change
#     if ($edit_user->login() ne $cgi->param('login')) {
#       if ($master->User->init( { login => $cgi->param('login') } )) {
# 	$application->add_message('warning', 'Login already in use by another account, aborting login change.');
#       } else {
# 	$edit_user->login($cgi->param('login'));
# 	$application->add_message('info', 'Login changed successfully');
#       }
#     }
    
  } else {
    $application->add_message("warning", "You do not have the right to edit this user.");
  }
  return 1;
}
