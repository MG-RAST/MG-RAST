package WebComponent::Register;

# Register - component for request of new user accounts

use strict;
use warnings;

use WebConfig;
use HTML::Strip;

use LWP::UserAgent;
use CGI;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

use base qw( WebComponent );

1;


=pod

=head1 NAME

Register - component for requesting user accounts

=head1 DESCRIPTION

WebComponent for requesting user accounts

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
  my $self = shift->SUPER::new(@_);

  $self->{successful_request} = 0;
  $self->{use_recaptcha} = 1;

  $self->application->register_action($self, 'perform_registration', $self->get_trigger('register'));
  $self->application->register_action($self, 'claim_invitation', $self->get_trigger('claim'));
  $self->application->register_component('TabView', 'RegisterTV');

  return $self;
}


=pod

=item * B<output> ()

Returns the html output of the Register component.

=cut

sub output {
  my ($self) = @_;

  # get the cgi params
  my $cgi = $self->application->cgi;
  my $firstname = $cgi->param('firstname') || "";
  my $lastname = $cgi->param('lastname') || "";
  my $login = $cgi->param('login') || "";
  my $email = $cgi->param('email') || "";
  my $group = $cgi->param('group') || "";
  my $tab = $cgi->param('tab') || "";

  # reset them if we had a successful registration
  my $request_result = $self->application->get_action_result($self->get_trigger('register'));
  if (defined($request_result) && $request_result) {
    $firstname = "";
    $lastname = "";
    $login = "";
    $email = "";
    $group = "";
  }

  # prepare the country codes
  my $country_codes = &country_codes();
  my $country_values;
  @$country_values = sort { $country_codes->{$a} cmp $country_codes->{$b} } keys(%$country_codes);


  # FORMS START HERE
  
  # form for invitation
  if ($cgi->param('invite')) {

    my $code = $cgi->param('invite');

    # check if a valid invitation
    my $invite = $self->application->dbmaster->User->init({ login => $code });
    unless(ref $invite and $invite->email eq $email) {
      my $content = "<p><strong>This is not a valid invitation request.</strong></p>";
      $content .= "<p>If you didn't click on the url in your email program and e.g. copy and pasted it, ".
	"please make sure the url matches 100% and is not truncated.</p>";
      $content .= "<p> &raquo <a href='".$self->application->url."'>Back to the start page</a></p>";
      return $content;
    }

    # generate the form
    my $iform = $self->application->page->start_form('claimform', { action => $self->get_trigger('claim'),
								    invite => $cgi->param('invite'),
								  });
    $iform .= "<table>";
    $iform .= "<tr><td>First Name</td><td><input type='text' name='firstname' value='" . $firstname . "'></td></tr>";
    $iform .= "<tr><td>Last Name</td><td><input type='text' name='lastname' value='" . $lastname . "'></td></tr>";
    $iform .= "<tr><td>Login</td><td><input type='text' name='login' value='" . $login . "'></td></tr>";
    $iform .= "<tr><td>eMail</td><td><input type='text' name='email' readonly='readonly' value='" . $email . "'></td></tr>";
    $iform .= "<tr><td>Organization</td><td><input type='text' name='organization'></td></tr>";
    $iform .= "<tr><td>URL</td><td>http://<input type='text' name='lru'></td></tr>";
    $iform .= "<tr><td>Country</td><td>" . $cgi->popup_menu( -name => 'country', -values => $country_values, -labels => $country_codes, -default => 'US' ) . "</td></tr>";

    if ($self->{use_recaptcha}) {
      $iform .= &recaptcha();
    }

    $iform .= "<td><input type='submit' class='button' value='Request'></td></tr>";
    $iform .= "</table>";
    
    $iform .= $self->application->page->end_form;
    
    return $iform;
  
  }

  # normal registration form
  else {
  
    if ($self->{successful_request}) {
      
      my $content = "<p style='width:800px;'>Your account request was successful. An administrator of this application will process your request at their earliest opportunity. Since this is a manual step, please allow some time for processing.</p><p>If you would like to request another account, please click <a href='?page=Register'>here.</a></p>";
      
      return $content;
      
    } else {
      
      # get the tab view
      my $tv = $self->application->component('RegisterTV');
      $tv->width(550);

      my $mlist_msg = "(We encourage you to subscribe as the list is used to inform you about major changes to the MG-RAST service and announce MG-RAST workshops. Email originates from the MG-RAST team only and is quite rare.)";

      # form for new account
      my $new_account = $self->application->page->start_form;
      $new_account .= "<input type='hidden' name='action' value='" . $self->get_trigger('register') . "' >";
      $new_account .= "<p style='font-size:8pt; font-style: italic;'>Fields indicated with <span style='color:red;'>*</span> are mandatory.</p>";
      $new_account .= "<table>";
      $new_account .= "<tr><td>First Name<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='firstname' value='" . $firstname . "'></td></tr>";
      $new_account .= "<tr><td>Last Name<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='lastname' value='" . $lastname . "'></td></tr>";
      $new_account .= "<tr><td>Login<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='login' value='" . $login . "'></td></tr>";
      $new_account .= "<tr><td>eMail<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='email' value='" . $email . "'></td></tr>";
      $new_account .= "<tr><td>Organization</td><td><input type='text' name='organization'></td></tr>";
      $new_account .= "<tr><td>URL</td><td>http://<input type='text' name='lru'></td></tr>";
      $new_account .= "<tr><td>Country</td><td>" . $cgi->popup_menu( -name => 'country', -values => $country_values, -labels => $country_codes, -default => 'US' ) . "</td></tr>";
      $new_account .= "<tr><td>Group Name</td><td><input type='text' name='group' value='" . $group . "'><br><i>(only enter if assigned by a group administrator)</i></td></tr>";
      if ($self->application->backend->name eq 'MGRAST') {
	$new_account .= "<tr><td>Add me to the MG-RAST mailing-list</td><td><input type='checkbox' name='mailinglist' checked='checked'><br><i>$mlist_msg</i></td></tr>";
      }
      $new_account .= "<tr><td>&nbsp;</td><td><input type='submit' class='button' value='Request'></td></tr>";
      $new_account .= "</table>";

      if ($self->{use_recaptcha}) {
	$new_account .= &recaptcha();
      }
      
      $new_account .= $self->application->page->end_form;
      
      # form for existing account
      my $existing_account = $self->application->page->start_form;
      $existing_account .= "<input type='hidden' name='action' value='" . $self->get_trigger('register') . "' >";
      $existing_account .= "<p style='font-size:8pt; font-style: italic;'>Fields indicated with <span style='color:red;'>*</span> are mandatory.</p>";
      $existing_account .= "<table>";
      $existing_account .= "<tr><td>Login<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='login' value='" . $login . "'></td></tr>";
      $existing_account .= "<tr><td>eMail<sup><span style='color: red;'>*</span></sup></td><td><input type='text' name='email' value='" . $email . "'></td></tr>";
      $existing_account .= "<tr><td>Group Name</td><td><input type='text' name='group' value='" . $group . "'><br><i>(only enter if assigned by a group administrator)</i></td></tr>";
      $existing_account .= "<tr><td>&nbsp;</td><td><input type='submit' class='button' value='Request'></td></tr>";
      $existing_account .= "</table>";

      if ($self->{use_recaptcha}) {
	$existing_account .= &recaptcha();
      }
      
      $existing_account .= $self->application->page->end_form;
      
      # fill tab view
      $tv->add_tab('New Account', $new_account);
      $tv->add_tab('Existing Account', $existing_account);
      if($tab eq "existing"){
	$tv->default(1);
      }
      
      my $content = $tv->output();
      
      return $content;
      
    }
  }

}


=pod

=item * B<perform_registration> ()

Executes the registration process. Sends a mail to the admin with the requested
user information. Also enters this request into the user db.

=cut

sub perform_registration {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  # DO NOT MOVE THIS TEST FOR ILLEGAL CHARACTERS DOWN!  THIS SHOULD BE THE FIRST TEST!!!
  # not allowing potential, partial html tags in these fields
  # note: complete html tags should be removed in WebApplication CGI
  foreach my $var ('email', 'login', 'firstname', 'lastname') {
    my $cgi_var = $cgi->param($var);
    if($cgi_var =~ /[<>\'\"]/) {
      $application->add_message('warning', 'Single or double quotes and the symbols > and < are not allowed in the \''.$var.'\' field');
      $cgi->param(-name=>$var, -value=>'');
      return 0;
    }
  }
  
  # check recaptcha
  if ($self->{use_recaptcha}) {
    if (! &check_answer()) {
      $application->add_message('warning', 'reCAPTCHA incorrect, please retry.');
      return 0;
    }
  }

  # check for an email address
  unless ($cgi->param('email')) {
    $application->add_message('warning', 'You must enter an eMail address.');
    return 0;
  }

  # check if email address is valid
  unless ($cgi->param('email') =~ /[\d\w\.\'-]+\@[\d\w\.-]+\.[\w+]/) {
    $application->add_message('warning', 'You must enter a valid eMail address.');
    return 0;
  }

  # check login
  unless ($cgi->param('login')) {
    $application->add_message('warning', 'You must enter a login.');
    return 0;
  }

  # check if the login is valid
  unless ($cgi->param('login') =~ /^[\d\w]+$/) {
    $application->add_message('warning', 'Login may only consist of alphanumeric characters.');
    return 0;
  }

  # check if firstname and lastname are distinct
  if ($cgi->param('firstname') && $cgi->param('lastname')) {
    if ($cgi->param('firstname') eq $cgi->param('lastname')) {
      $application->add_message('warning', 'First- and lastname must be distinct.');
      return 0;
    }
  }

  my $user;
  
  # check login
  my $user_by_login = $application->dbmaster->User->init( { login => $cgi->param('login') } );
  if (ref($user_by_login)) {
    
    unless ($user_by_login->email eq $cgi->param('email')) {
      $application->add_message('warning', 'This login is already taken.');
      return 0;
    }
    $user = $user_by_login;
    
  }
  else {

    # check email 
    my $user_by_email = $application->dbmaster->User->init( { email => $cgi->param('email') } );
    if (ref($user_by_email)) {
      
      unless ($user_by_email->login eq $cgi->param('login')) {
	$application->add_message('warning', 'This email is already taken.');
	return 0;
      }
      $user = $user_by_email;
      
    }
  }

  # check whether the user has requested a group
  my $group_name = "";
  my $admin_notified = 0;

  # existing user
  if ($user && $user->has_right($application, 'login')) {
      $application->add_message('warning', 'You are already registered for this application.');
      return 0;
  }
    
  # check if we want a group
  my $group;
  if (defined($cgi->param('group')) && $cgi->param('group')) {
    my $hs = HTML::Strip->new();
    $group_name = $hs->parse($cgi->param('group'));
    my $possible_groups = $application->dbmaster->Scope->get_objects( { name => $group_name } );
      if (scalar(@$possible_groups) == 1) {
	unless ($possible_groups->[0]->application) {
	  $group = $possible_groups->[0];
	} else {
	  $application->add_message('warning', "This group is not accessible, aborting.");
	  return 0;
	}
      } else {
	$application->add_message('warning', "The group $group_name does not exist, request not created. Group information is optional, leave blank or contact group administrator for correct spelling of group name.");
	return 0;
      }
  }
    
  # we do not yet have a user, let's try to create one
  unless (ref($user)) {
      
    # check if scope exists
    if ($application->dbmaster->Scope->init( { application => undef,
					       name => $cgi->param('login') } )) {
      $application->add_message('warning', 'This login is already taken.');
      return 0;
    }
      
    # check first name
    unless ($cgi->param('firstname')) {
      $application->add_message('warning', 'You must enter a first name.');
      return 0;
    }
      
    # check last name
    unless ($cgi->param('lastname')) {
      $application->add_message('warning', 'You must enter a last name.');
      return 0;
    }

    my $email = 
    # create the user in the db
    $user = $application->dbmaster->User->create( { email        => $cgi->param('email'),
						    firstname    => $cgi->param('firstname'),
						    lastname     => $cgi->param('lastname'),
						    login        => $cgi->param('login') } );
      
    # check for success
    unless (ref($user)) {
      $application->error('Could not create user.');
      return 0;
    }
  }

  # check for organization information
  my $user_org = "";
  my $org_found = 0;
  my $url = "";

  if($cgi->param('organization')) {
    my $hs = HTML::Strip->new();
    $user_org = $hs->parse($cgi->param('organization'));
  }

  if($cgi->param('lru')) {
    my $hs = HTML::Strip->new();
    $url = $hs->parse($cgi->param('lru'));
  }

  if ($user_org) {
      
    # check if we find this organization by name
    my $existing_org = $application->dbmaster->Organization->init( { name => $user_org } );
      
    # check if we have a url to compare
    if ($url) {
      $url =~ s/(.*)\/$/$1/;
      $url = "http://".$url;
      $existing_org = $application->dbmaster->Organization->get_objects( { url => $url } );
      if (scalar($existing_org)) {
	$existing_org = $existing_org->[0];
      }
    }
      
    # check if we found an existing org
    if ($existing_org) {
      $user_org = $existing_org->name();
      unless (scalar(@{$application->dbmaster->OrganizationUsers->get_objects( { organization => $existing_org,
										 user => $user } )})) {
	$application->dbmaster->OrganizationUsers->create( { organization => $existing_org,
							     user => $user } );
      }
      $org_found = 1;
    }
  }

  # prepare admin email
  my $abody = HTML::Template->new(filename => TMPL_PATH.'EmailReviewNewAccount.tmpl',
				  die_on_bad_params => 0);
  $abody->param('FIRSTNAME', $user->firstname);
  $abody->param('LASTNAME', $user->lastname);
  $abody->param('LOGIN', $user->login);
  $abody->param('EMAIL_USER', $user->email);
  $abody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
  $abody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  $abody->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
  $abody->param('URL', $url);
  if ($cgi->param('country')) {
      my $hs = HTML::Strip->new();
      my $country = $hs->parse( $cgi->param('country') );
      $abody->param('COUNTRY', $country);
  }
  if ($user_org) {
    $abody->param('ORGANIZATION', $user_org);
    if ($org_found) {
      $abody->param('ORG_FOUND', "This organization was already present in the database.");
    } else {
      $abody->param('ORG_FOUND', "This organization does not yet exist. Please create it on the Organization page.");
    }
  }
    
  # the requested group has been found, add the user to the group
  # do not set the granted flag, so the user technically does not yet have the group
  if ($group) {
    $application->dbmaster->UserHasScope->create( { 'user' => $user, 'scope' => $group } );
      
    # find out who has the right to administrate this group
    my $group_admins;
    my $group_admin_rights = $application->dbmaster->Rights->get_objects( { granted => 1,
									    name => 'edit',
									    data_type => 'scope',
									    data_id => $group->_id() } );
    foreach my $garight (@$group_admin_rights) {
      push(@$group_admins, @{$garight->scope->users()});
    }
      
    # prepare group admin email
    $abody->param('GROUP', $group_name);
      
    foreach my $group_admin (@$group_admins) {
      $group_admin->send_email( $WebConfig::ADMIN_EMAIL,
				$WebConfig::APPLICATION_NAME." - new account requested for $group_name",
				$abody->output
			      );
      $admin_notified = 1;
    }
      
    $group_name .= "\nThe administrators of this group have been notified of the request.\n";
  }
  
  # add registration request (non granted login right)
  $user->add_login_right( $application );

  # check if user wants to be on the mailinglist
  if ($cgi->param('mailinglist')) {
    $application->dbmaster->Preferences->create( { user => $user,
						   name => 'mailinglist',
						   value => 'mgrast' } );
  }
      
  # send user email
  my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailNewAccount.tmpl',
				   die_on_bad_params => 0);
  $ubody->param('FIRSTNAME', $user->firstname);
  $ubody->param('LASTNAME', $user->lastname);
  $ubody->param('LOGIN', $user->login);
  $ubody->param('EMAIL_USER', $user->email);
  $ubody->param('GROUP', $group_name);
  $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
  $ubody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  $ubody->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
    
  $user->send_email( $WebConfig::ADMIN_EMAIL,
		     $WebConfig::APPLICATION_NAME.' - new account requested',
		     $ubody->output
		   );

  unless ($admin_notified) {
    
    # retrieve accounts to receive registration mail
    my $registration_rights = $application->dbmaster->Rights->get_objects( { 'application' => $application->backend(),
									     'granted' => 1,
									     'data_type' => 'registration_mail',
									     'name' => 'view' } );
    my $admin_users = [];
    foreach my $right (@$registration_rights) {
      push(@$admin_users, @{$right->scope->users()});
    }
    
    # warn if no admins found
    unless (scalar(@$admin_users)) {
      warn "No administrators found to review registration requests.";
    }
    
    # send admin mail
    foreach my $admin (@$admin_users) {
      $admin->send_email( $WebConfig::ADMIN_EMAIL,
			  $WebConfig::APPLICATION_NAME.' - new account requested',
			  $abody->output
			);
    }
  }

  # create success message
  $application->add_message('info', 'Your registration request has been sent. You will be notified as soon as your request has been processed.');
  
  # set success flag
  $self->{successful_request} = 1;

  return 1;
}


=pod

=item * B<claim_invitation> ()

Executes the registration by invitation process. 

=cut

sub claim_invitation {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  
  # check for invitation code 
  unless ($cgi->param('invite')) {
    $self->application->add_message('warning', 'Invalid invitation.');
    return 0;
  }

  # check if email address is valid
  unless ($cgi->param('email') and $cgi->param('email') =~ /[\d\w]+\@[\d\w\.]+\.[\w+]/) {
    $self->application->add_message('warning', 'You must enter a valid eMail address.');
    return 0;
  }

  # check login
  unless ($cgi->param('login')) {
    $self->application->add_message('warning', 'You must enter a login.');
    return 0;
  }

  # check if firstname and lastname are distinct
  unless ($cgi->param('firstname') && $cgi->param('lastname') &&
	  $cgi->param('firstname') ne $cgi->param('lastname')) {
    $self->application->add_message('warning', 'First- and lastname must be given and distinct.');
    return 0;
  }

  # check if a valid invitation
  my $user = $self->application->dbmaster->User->init({ login => $cgi->param('invite') });
  unless(ref $user and $user->email eq $cgi->param('email')) {
    $self->application->add_message('warning', 'This is not a valid invitation request');
    return 0;
  }

  # check if login is taken
  if (ref($self->application->dbmaster->User->init( { login => $cgi->param('login') } ))) {
    $self->application->add_message('warning', 'This login is already taken.');
    return 0;
  }

  # update the user information
  $user->login( $cgi->param('login') );
  $user->firstname( $cgi->param('firstname') );
  $user->lastname( $cgi->param('lastname') );
  
    
  # check for organization information
  my $user_org = $cgi->param('organization') || "";
  my $url = $cgi->param('lru') || "";
  if ($user_org) {
      
    # check if we find this organization by name
    my $org = $self->application->dbmaster->Organization->init( { name => $user_org } );
      
    # check if we have a url to compare
    if ($url) {
      $url =~ s/(.*)\/$/$1/;
      $url = "http://".$url;
      $org = $self->application->dbmaster->Organization->get_objects( { url => $url } );
      if (scalar($org)) {
	$org = $org->[0];
      }
    }
      
    # if there is an existing org, put the user into it
    if ($org) {
      $user_org = $org;
      unless (scalar(@{$self->application->dbmaster->OrganizationUsers->get_objects( { organization => $org,
										       user => $user } )})) {
	$self->application->dbmaster->OrganizationUsers->create( { organization => $org,
								   user => $user } );
      }
    }
  }
  
      
  # send user email
  my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailNewAccount.tmpl',
				   die_on_bad_params => 0);
  $ubody->param('FIRSTNAME', $user->firstname);
  $ubody->param('LASTNAME', $user->lastname);
  $ubody->param('LOGIN', $user->login);
  $ubody->param('EMAIL_USER', $user->email);
  $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
  $ubody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  $ubody->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
    
  $user->send_email( $WebConfig::ADMIN_EMAIL,
		     $WebConfig::APPLICATION_NAME.' - new account requested',
		     $ubody->output
		   );


  # prepare admin email
  my $abody = HTML::Template->new(filename => TMPL_PATH.'EmailReviewNewAccount.tmpl',
				  die_on_bad_params => 0);
  $abody->param('FIRSTNAME', $user->firstname);
  $abody->param('LASTNAME', $user->lastname);
  $abody->param('LOGIN', $user->login);
  $abody->param('EMAIL_USER', $user->email);
  $abody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
  $abody->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
  $abody->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
  $abody->param('URL', $url);
  $abody->param('COUNTRY', $cgi->param('country'));
  if ($user_org) {
    $abody->param('ORGANIZATION', $user_org);
    if (ref $user_org) {
      $abody->param('ORG_FOUND', "This organization was already present in the database.");
    } else {
      $abody->param('ORG_FOUND', "This organization does not yet exist. Please create it on the Organization page.");
    }
  }
  
  # find users to send admin mail to
  my $notify = $self->application->dbmaster->Rights->get_objects( { 'application' => $self->application->backend(),
								    'granted' => 1,
								    'data_type' => 'registration_mail',
								    'name' => 'view',
								  } );
  my $admin_users = [];
  foreach my $n (@$notify) {
    push(@$admin_users, @{$n->scope->users()});
  }
  
  # warn if no admins found
  unless (scalar(@$admin_users)) {
    warn "No administrators found to review registration requests.";
  }
  
  # send admin mail
  foreach my $admin (@$admin_users) {
    $admin->send_email( $WebConfig::ADMIN_EMAIL,
			$WebConfig::APPLICATION_NAME.' - new account requested',
			$abody->output
		      );
  }

  # create success message
  $self->application->add_message('info', 'Your registration request has been sent. You will be notified as soon as your request has been processed.');
  
  return 1;

}



sub country_codes {
  return { 'TV' => 'Tuvalu',
	   'FJ' => 'Fiji',
	   'SR' => 'Suriname',
	   'TZ' => 'Tanzania',
	   'FR' => 'France',
	   'CI' => 'Ivory Coast',
	   'ZW' => 'Zimbabwe',
	   'TD' => 'Chad',
	   'GQ' => 'Equatorial Guinea',
	   'AN' => 'Netherlands Antilles',
	   'US' => 'United States',
	   'GU' => 'Guam',
	   'ZA' => 'South Africa',
	   'GF' => 'French Guiana',
	   'NZ' => 'New Zealand',
	   'FI' => 'Finland',
	   'UG' => 'Uganda',
	   'NE' => 'Niger',
	   'KI' => 'Kiribati',
	   'AQ' => 'British Antarctic Territory',
	   'IL' => 'Israel',
	   'VU' => 'Vanuatu',
	   'PL' => 'Poland',
	   'EG' => 'Egypt',
	   'HM' => 'Heard Island and McDonald Islands',
	   'AQ' => 'Peter I Island',
	   'PN' => 'Pitcairn Islands',
	   'TK' => 'Tokelau',
	   'TT' => 'Trinidad and Tobago',
	   'BH' => 'Bahrain',
	   'MA' => 'Morocco',
	   'AX' => 'Aland',
	   'SM' => 'San Marino',
	   'GW' => 'Guinea-Bissau',
	   'SE' => 'Sweden',
	   'UM' => 'Johnston Atoll',
	   'NF' => 'Norfolk Island',
	   'HU' => 'Hungary',
	   'ME' => 'Montenegro',
	   'PA' => 'Panama',
	   'BY' => 'Belarus',
	   'BV' => 'Bouvet Island',
	   'MV' => 'Maldives',
	   'CH' => 'Switzerland',
	   'BA' => 'Bosnia and Herzegovina',
	   'AQ' => 'Queen Maud Land',
	   'DK' => 'Denmark',
	   'PR' => 'Puerto Rico',
	   'SN' => 'Senegal',
	   'LC' => 'Saint Lucia',
	   'PW' => 'Palau',
	   'CA' => 'Canada',
	   'DJ' => 'Djibouti',
	   'VC' => 'Saint Vincent and the Grenadines',
	   'BD' => 'Bangladesh',
	   'AU' => 'Ashmore and Cartier Islands',
	   'MQ' => 'Martinique',
	   'SO' => 'Somalia',
	   'AT' => 'Austria',
	   'NA' => 'Namibia',
	   'SL' => 'Sierra Leone',
	   'RE' => 'Reunion',
	   'BW' => 'Botswana',
	   'TA' => 'Tristan da Cunha',
	   'FO' => 'Faroe Islands',
	   'CD' => 'Congo',
	   'GL' => 'Greenland',
	   'BZ' => 'Belize',
	   'AW' => 'Aruba',
	   'IN' => 'India',
	   'GD' => 'Grenada',
	   'MT' => 'Malta',
	   'CM' => 'Cameroon',
	   'KZ' => 'Kazakhstan',
	   'IT' => 'Italy',
	   'MU' => 'Mauritius',
	   'BT' => 'Bhutan',
	   'ZM' => 'Zambia',
	   'BS' => 'Bahamas',
	   'NO' => 'Norway',
	   'NR' => 'Nauru',
	   'SK' => 'Slovakia',
	   'MK' => 'Macedonia',
	   'MP' => 'Northern Mariana Islands',
	   'TR' => 'Turkey',
	   'KG' => 'Kyrgyzstan',
	   'CO' => 'Colombia',
	   'MR' => 'Mauritania',
	   'LT' => 'Lithuania',
	   'CK' => 'Cook Islands',
	   'PY' => 'Paraguay',
	   'PS' => 'Palestinian Territories (Gaza Strip and West Bank)',
	   'TO' => 'Tonga',
	   'LS' => 'Lesotho',
	   'MS' => 'Montserrat',
	   'AM' => 'Armenia',
	   'SJ' => 'Svalbard',
	   'SB' => 'Solomon Islands',
	   'SI' => 'Slovenia',
	   'ER' => 'Eritrea',
	   'HT' => 'Haiti',
	   'AL' => 'Albania',
	   'FK' => 'Falkland Islands (Islas Malvinas)',
	   'SG' => 'Singapore',
	   'TF' => 'French Southern and Antarctic Lands',
	   'PF' => 'French Polynesia',
	   'AQ' => 'Australian Antarctic Territory',
	   'UM' => 'Midway Islands',
	   'SH' => 'Saint Helena',
	   'UZ' => 'Uzbekistan',
	   'GB' => 'United Kingdom',
	   'KM' => 'Comoros',
	   'VA' => 'Vatican City',
	   'UY' => 'Uruguay',
	   'LR' => 'Liberia',
	   'TC' => 'Turks and Caicos Islands',
	   'EH' => 'Western Sahara',
	   'JP' => 'Japan',
	   'AR' => 'Argentina',
	   'TN' => 'Tunisia',
	   'ID' => 'Indonesia',
	   'RW' => 'Rwanda',
	   'AF' => 'Afghanistan',
	   'AC' => 'Ascension',
	   'LY' => 'Libya',
	   'GS' => 'South Georgia and the South Sandwich Islands',
	   'GA' => 'Gabon',
	   'BI' => 'Burundi',
	   'HN' => 'Honduras',
	   'KE' => 'Kenya',
	   'UM' => 'Palmyra Atoll',
	   'PF' => 'Clipperton Island',
	   'AD' => 'Andorra',
	   'TJ' => 'Tajikistan',
	   'SV' => 'El Salvador',
	   'GP' => 'Saint Martin',
	   'MN' => 'Mongolia',
	   'GP' => 'Saint Barthelemy',
	   'MG' => 'Madagascar',
	   'RU' => 'Russia',
	   'IO' => 'British Indian Ocean Territory',
	   'DZ' => 'Algeria',
	   'OM' => 'Oman',
	   'CU' => 'Cuba',
	   'DO' => 'Dominican Republic',
	   'VE' => 'Venezuela',
	   'MX' => 'Mexico',
	   'KW' => 'Kuwait',
	   'UM' => 'Kingman Reef',
	   'BB' => 'Barbados',
	   'ET' => 'Ethiopia',
	   'EE' => 'Estonia',
	   'RS' => 'Serbia',
	   'AZ' => 'Nagorno-Karabakh',
	   'CZ' => 'Czech Republic',
	   'GI' => 'Gibraltar',
	   'CC' => 'Cocos (Keeling) Islands',
	   'VG' => 'British Virgin Islands',
	   'UA' => 'Ukraine',
	   'CY' => 'Cyprus',
	   'VN' => 'Vietnam',
	   'AE' => 'United Arab Emirates',
	   'YE' => 'Yemen',
	   'BF' => 'Burkina Faso',
	   'IS' => 'Iceland',
	   'NG' => 'Nigeria',
	   'TM' => 'Turkmenistan',
	   'MW' => 'Malawi',
	   'TH' => 'Thailand',
	   'WF' => 'Wallis and Futuna',
	   'NU' => 'Niue',
	   'LB' => 'Lebanon',
	   'SA' => 'Saudi Arabia',
	   'LI' => 'Liechtenstein',
	   'MO' => 'Macau',
	   'GE' => 'Georgia',
	   'LU' => 'Luxembourg',
	   'AQ' => 'Ross Dependency',
	   'KN' => 'Saint Kitts and Nevis',
	   'QA' => 'Qatar',
	   'MD' => 'Moldova',
	   'IM' => 'Isle of Man',
	   'AU' => 'Coral Sea Islands',
	   'JM' => 'Jamaica',
	   'UM' => 'Navassa Island',
	   'CR' => 'Costa Rica',
	   'BN' => 'Brunei',
	   'MM' => 'Myanmar (Burma)',
	   'CN' => 'China',
	   'BE' => 'Belgium',
	   'YT' => 'Mayotte',
	   'JO' => 'Jordan',
	   'PK' => 'Pakistan',
	   'DM' => 'Dominica',
	   'BR' => 'Brazil',
	   'TL' => 'Timor-Leste (East Timor)',
	   'GG' => 'Guernsey',
	   'SO' => 'Somaliland',
	   'NP' => 'Nepal',
	   'NC' => 'New Caledonia',
	   'MZ' => 'Mozambique',
	   'MD' => 'Pridnestrovie (Transnistria)',
	   'FM' => 'Micronesia',
	   'IE' => 'Ireland',
	   'NI' => 'Nicaragua',
	   'AI' => 'Anguilla',
	   'DE' => 'Germany',
	   'UM' => 'Howland Island',
	   'GE' => 'South Ossetia',
	   'AU' => 'Australia',
	   'KH' => 'Cambodia',
	   'KY' => 'Cayman Islands',
	   'GR' => 'Greece',
	   'EC' => 'Ecuador',
	   'BM' => 'Bermuda',
	   'HK' => 'Hong Kong',
	   'PG' => 'Papua New Guinea',
	   'PM' => 'Saint Pierre and Miquelon',
	   'UM' => 'Wake Island',
	   'GN' => 'Guinea',
	   'LK' => 'Sri Lanka',
	   'GP' => 'Guadeloupe',
	   'UM' => 'Baker Island',
	   'GH' => 'Ghana',
	   'PE' => 'Peru',
	   'LA' => 'Laos',
	   'WS' => 'Samoa',
	   'BG' => 'Bulgaria',
	   'NL' => 'Netherlands',
	   'AS' => 'American Samoa',
	   'SZ' => 'Swaziland',
	   'PT' => 'Portugal',
	   'PH' => 'Philippines',
	   'ML' => 'Mali',
	   'AZ' => 'Azerbaijan',
	   'SC' => 'Seychelles',
	   'CV' => 'Cape Verde',
	   'CX' => 'Christmas Island',
	   'AQ' => 'Antarctica',
	   'CF' => 'Central African Republic',
	   'GY' => 'Guyana',
	   'ES' => 'Spain',
	   'BO' => 'Bolivia',
	   'TG' => 'Togo',
	   'HR' => 'Croatia',
	   'BJ' => 'Benin',
	   'UM' => 'Jarvis Island',
	   'AO' => 'Angola',
	   'CL' => 'Chile',
	   'JE' => 'Jersey',
	   'CS' => 'Kosovo',
	   'MY' => 'Malaysia',
	   'KR' => 'South Korea',
	   'GM' => 'Gambia',
	   'AG' => 'Antigua and Barbuda',
	   'GT' => 'Guatemala',
	   'MC' => 'Monaco',
	   'GE' => 'Georgia',
	   'CY' => 'Northern Cyprus',
	   'LV' => 'Latvia',
	   'MH' => 'Marshall Islands',
	   'ST' => 'Sao Tome and Principe',
	   'VI' => 'U.S. Virgin Islands',
	   'RO' => 'Romania' };
}

sub recaptcha {
  return '<script type="text/javascript" src="https://www.google.com/recaptcha/api/challenge?k=6Lf1FL4SAAAAAO3ToArzXm_cu6qvzIvZF4zviX2z"></script><noscript><iframe src="https://www.google.com/recaptcha/api/noscript?k=6Lf1FL4SAAAAAO3ToArzXm_cu6qvzIvZF4zviX2z" height="300" width="500" frameborder="0"></iframe><br><textarea name="recaptcha_challenge_field" rows="3" cols="40"></textarea><input type="hidden" name="recaptcha_response_field" value="manual_challenge"></noscript>';
}

sub check_answer {
  my $cgi = CGI->new();
  my $ua = LWP::UserAgent->new();
  $ua->env_proxy();

  my $resp =  $ua->post( 'https://www.google.com/recaptcha/api/verify',
    {
      privatekey => '6Lf1FL4SAAAAAIJLRoCYjkEgie7RIvfV9hQGnAOh',
      remoteip   => $ENV{'REMOTE_ADDR'},
      challenge  => $cgi->param('recaptcha_challenge_field'),
      response   => $cgi->param('recaptcha_response_field')
    }
  );

  if ( $resp->is_success ) {
    my ( $answer, $message ) = split( /\n/, $resp->content, 2 );
    if ( $answer =~ /true/ ) {
      return 1;
    }
    else {
      return 0;
    }
  }
  else {
    return 0;
  }
}
