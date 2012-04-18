package WebPage::RequestGroup;

use base qw( WebPage );

1;

use strict;
use warnings;

use WebConfig;

=pod

=head1 NAME

RequestGroup - an instance of WebPage which offers users the ability to request to become member
of a group or to request a new group to be created

=head1 DESCRIPTION

Offers users the ability to request to become member of a group or to request a new group to be created

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Request Group');
  $self->application->register_action($self, 'request_group_membership', 'request_group_membership');
  $self->application->register_action($self, 'request_new_group', 'request_new_group');

  return 1;
}

=item * B<output> ()

Returns the html output of the RequestGroup page.

=cut

sub output {
  my ($self) = @_;
  
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  my $html = "<h2>Request Group</h2>";
  
  $html .= "<p>If a group administrator has provided you the name of a group you want to become a member of,<br/>please fill it into the field below and click <b>Request Membership</b></p>";
  $html .= $self->start_form('request_membership_form', { action => 'request_group_membership' })."<input type='text' name='group_name'><input type='submit' value='Request Group Membership'>".$self->end_form();
  $html .= "<p>If you frequently want to delegate rights to a group of users, you can request a new group to be created. <br />Please fill in the group name of your choice and click <b>Request new Group</b></p>";
  $html .= $self->start_form('request_new_group_form', { action => 'request_new_group' })."<input type='text' name='group_name'><input type='submit' value='Request new Group'>".$self->end_form();
  
  return $html;
}

=item * B<request_group_membership> ()

Action that creates a group membership request.

=cut

sub request_group_membership {
  my ($self) = @_;

  # get objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # check for group name
  my $group = $cgi->param('group_name');
  unless (defined($group)) {
    $application->add_message('warning', 'You must provide a group name when requesting to become member of a group.');
    return 0;
  }

  # check whether the group exists
  my $poss_groups = $master->Scope->get_objects( { name => $group });
  unless (scalar(@$poss_groups) == 1 && ! $poss_groups->[0]->application()) {
    $application->add_message('warning', "The group $group was not found in the database.");
    return 0;
  }

  # check whether there is a previous request of this user
  my $has_scope = $master->UserHasScope->init( { user => $user, scope => $poss_groups->[0] } );
  if ($has_scope) {

    # the user is already a member, duh!
    if ($has_scope->granted()) {
      $application->add_message('warning', "You are already a member of group $group.");
      return 0;
    }
    
    # the user has already requested to become a member
    else {
      $application->add_message('warning', "You have already requested to become a member of group $group. The group administrator will process your request at their discretion.");
      return 0;
    }
  }

  # all sanity checks passed, create request
  $master->UserHasScope->create( { user => $user, scope => $poss_groups->[0] } );

  # find out who has the right to administrate this group
  my $group_admins;
  my $group_admin_rights = $master->Rights->get_objects( { granted => 1,
							   name => 'edit',
							   data_type => 'scope',
							   data_id => $poss_groups->[0]->_id() } );
  foreach my $garight (@$group_admin_rights) {
    push(@$group_admins, @{$garight->scope->users()});
  }
	  
  # prepare group admin email
  my $gabody = HTML::Template->new(filename => TMPL_PATH.'EmailReviewGroupAccess.tmpl',
				   die_on_bad_params => 0);
  $gabody->param('USERNAME', $user->firstname." ".$user->lastname);
  $gabody->param('LOGIN', $user->login);
  $gabody->param('EMAIL_USER', $user->email);
  $gabody->param('GROUP', $group);
  $gabody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
  $gabody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  $gabody->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
  
  foreach my $group_admin (@$group_admins) {
    $group_admin->send_email( $WebConfig::ADMIN_EMAIL,
			      $WebConfig::APPLICATION_NAME." - user requested access for $group",
			      $gabody->output
			    );
  }

  # inform user of success
  $application->add_message('info', "You have successfully requested to become a member of group $group. The group administrator will process your request at their discretion.");

  return 1;
}

=item * B<request_new_group> ()

Action that creates a new group request.

=cut

sub request_new_group {
  my ($self) = @_;

  # get objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();
  my $user = $application->session->user();

  # check for group name
  my $group = $cgi->param('group_name');
  unless (defined($group)) {
    $application->add_message('warning', 'You must provide a group name when requesting a new group.');
    return 0;
  }

  # check whether the group exists
  my $poss_groups = $master->Scope->get_objects( { name => $group });
  if (scalar(@$poss_groups)) {
    $application->add_message('warning', "The group $group already exists.");
    return 0;
  }

  # prepare a mail to the admins
  my $abody = HTML::Template->new(filename => TMPL_PATH.'EmailReviewNewGroup.tmpl',
				    die_on_bad_params => 0);
  $abody->param('USERNAME', $user->firstname . " " . $user->lastname);
  $abody->param('GROUP', $group);
  $abody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  
  # retrieve accounts to receive request mail
  my $registration_rights = $master->Rights->get_objects( { 'application' => $application->backend(),
							    'granted' => 1,
							    'data_type' => 'group_request_mail',
							    'name' => 'view' } );
  my $admin_users = [];
  foreach my $right (@$registration_rights) {
    push(@$admin_users, @{$right->scope->users()});
  }
    
  # warn if no admins found
  unless (scalar(@$admin_users)) {
    die "No administrators found to review registration requests.";
  }
    
  # send admin mail
  foreach my $admin (@$admin_users) {
    $admin->send_email( $WebConfig::ADMIN_EMAIL,
			$WebConfig::APPLICATION_NAME.' - new group requested',
			$abody->output
		      );
  }
  
  # inform the user of success
  $application->add_message('info', "You have successfully requested the group $group. An administrator will handle your request at their first opportunity.");

  return 1;
}

sub supported_rights {
  return [ [ 'view', 'group_request_mail', '*' ] ];
}
