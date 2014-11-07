package WebServerBackend::User;

# WebServerBackend::User - object to manage user data in the web application 

# $Id: User.pm,v 1.47 2011-05-26 16:53:38 olson Exp $

use Mail::Mailer;

use Data::Dumper;
use WebConfig;
use strict;
use warnings;
no warnings 'redefine'; # Not sure why we need this, but it prevents
                        # warnings from filling up the NMPDR log.

# Uncomment this to do wiki debugging in here.                        
# use TWiki::Contrib::MissingLinkPlugin qw(:debug); 


1;

=pod

=head2 NAME

WebServerBackend::User - object to manage user data in the web application 

=head2 DESCRIPTION

This package contains methods to extend the automatically generated methods 
of the User object.

=head3 WikiNames

Inside the Wiki, users are identified by WikiNames. A WikiName is normally the first name
and last name concatenated together. However, this only works if the user's name has no
special characters and the first name is one capital letter followed by one or more small letters
or digits. If the user name does not satisfy this criterion, then the wiki name is taken from the login name
if the login name begins with C<TWiki>, and is otherwise computed by capitalizing the first letter of
the login name and putting C<NmpdrUserX> in front of it. The following table shows how this works.

| *Login* | *First Name* | *Last Name* | *Wiki Name* | *Reason* |
| parrello | Bruce | Parrello | BruceParrello |  |
| TWikiContributor | TWiki | Contributor | TWikiContributor | TWiki name |
| svs | Seigfried | von Sigmund | NmpdrUserXsvs | special character (space) in either name |
| psmith | P | Smith | NmpdrUserXpsmith | first name has no small letters |

The point of all this is it provides the ability to map a wiki name to a query against the
user table. If the wiki name begins with C<TWiki> or C<NmpdrUser>, we query the login name.
Otherwise, we split the wiki name at the second capital letter and query the first and last
names.

=head2 METHODS

=over 4

=item * B<create> ()

This method overwrites the parent method in DBObject. When creating a user, it 
will also create a user specific scope and the association between user and 
scope (UserHasScope).

If any of the three database creation calls fails, it will invoke delete upon 
the newly created user object and then die.

=cut

sub create {
  my $self = shift->SUPER::create(@_);
  
  # check if scope with this name exists
  if ($self->_master->Scope->init({ name => $self->get_user_scope_name,
				    application => undef,
				  })) {
    $self->delete;
    die "Scope '".$self->login."' does already exist.";
    
  }

  # create scope for the user
  else {
    my $scope = $self->_master->Scope->create({ name => $self->get_user_scope_name,
						description => 'automatically created user scope'
					      });

    # check if scope creation was successful
    unless (ref $scope and $scope->isa('WebServerBackend::Scope')) {
      $self->delete;
      die "Unable to create Scope '".$self->get_user_scope_name."'.";
    }
    
    # check if UserHasScope exists (really shouldnt)
    if ($self->_master->UserHasScope->init({ user => $self, 
					     scope => $scope })) {
      $self->delete;
      die "User '".$self->login."' already associated with Scope '".$scope->name."'.";	
      
    }

    # associate User with Scope
    else {
      
      my $user_has_scope = $self->_master->UserHasScope->create({ user => $self, scope => $scope, granted => 1 });

      # check if database create was successful
      unless (ref $user_has_scope and $user_has_scope->isa('WebServerBackend::UserHasScope')) {
	$self->delete;
	die "Unable to create UserHasScope for User '".$self->login."' and Scope '".$scope->name."'.";	
      }

      # create the right to manage self
      unless (scalar @{$self->_master->Rights->get_objects({ scope       => $self->get_user_scope,
							     data_type   => 'user',
							     data_id     => $self->_id,
							     name        => 'edit',
							   })} ) {
	my $right = $self->_master->Rights->create({ scope       => $self->get_user_scope,
						     data_type   => 'user',
						     data_id     => $self->_id,
						     name        => 'edit',
						     granted     => 1
						   });
	unless (ref $right) {
	  $self->delete;
	  die "Unable to create Right 'user', 'edit', '".$self->_id."'.";
	}
	
      }
      
    }

  }

  return $self;

}

=pod

=item * B<delete> ()

Before calling the super method delete, this method will delete the user 
scope and all UserHasScope associations for this user. 

=cut

sub delete {
  my $self = shift;

  # delete all rights this user has
  my $rights = $self->_master->Rights->get_objects( { scope => $self->get_user_scope } );
  foreach (@$rights) {
    $_->delete();
  }

  # try to delete user scope
  my $scope = $self->_master->Scope->init({ name => $self->get_user_scope_name,
					    application => undef,
					  });
  if (ref $scope and $scope->isa('WebServerBackend::Scope')) {
    $scope->delete;
  }

  # delete all UserHasScope objects for this user
  my $has = $self->_master->UserHasScope->get_objects({ user => $self });
  foreach (@$has) {
    $_->delete;
  }

  # delete all organization memberships for this user
  my $organization_memberships = $self->_master->OrganizationUsers->get_objects( { user => $self } );
  if (ref($organization_memberships) eq "ARRAY") {
    foreach (@$organization_memberships) {
      $_->delete;
    }
  }

  return $self->SUPER::delete();

}


=pod

=item * B<login> ()

This is the getter setter method for the login attribute. Since the Scope
name is dependant on the login, we must update that if the login is changed.

=cut

sub login {
  my ($self, $login) = @_;

  if (defined($login)) {
    my $existing_user = $self->_master->User->init( { login => $login } );
    if (defined($existing_user)) {
      die "Login $login already taken.";
    }
    my $new_scope_name = "user:$login";
    my $scope = $self->get_user_scope();
    unless (defined($scope)) {
      die "Scope could not be initialized for login " . $self->{login} . ".";
    }
    $scope->name($new_scope_name);
    $self->SUPER::login($login);
  }

  return $self->{login};
}

=pod

=item * B<get_user_scope_name> ()

Returns the name of the user scope. To get a static scope name which does
not overlap with possible application scopes, the method adds a prefix to
the login attribute of the User to generate the name of the user scope.

=cut

sub get_user_scope_name {
  return 'user:'.$_[0]->login;
}


=pod

=item * B<get_user_scope> ()

Returns the user scope of this user. To avoid repeated database queries, 
the user scope is stored in the user object. 

=cut

sub get_user_scope {
  my ($self) = @_;

  unless (ref $self->{'__user_scope'}) {
    $self->{'__user_scope'} = $self->_master->Scope->init({ name => $self->get_user_scope_name,
							    application => undef,
							  });
  }
  return $self->{'__user_scope'};
}


=pod

=item * B<send_email> (I<from>, I<subject>, I<mail_body>)

This method sends an email to this user from I<from> with the subject I<subject>.
The text of the mail will be I<mail_body>.

=cut

sub send_email {
  my ($self, $from, $subject, $body) = @_;

  my $mailer = Mail::Mailer->new();
  $mailer->open({ From    => $from,
		  To      => $self->email,
		  Subject => $subject,
		})
    or die "Can't open Mail::Mailer: $!\n";
  print $mailer $body;
  $mailer->close();
  
  return 1;

}


=pod

=item * B<add_login_right> (I<application>)

This method creates the login right for an application I<application>. The parameter
I<application> can either be an WebApplication object or a WebServerBackend::Backend
object.

=cut

sub add_login_right {
  my ($self, $backend_or_app) = @_;

  my $backend;
  if (ref $backend_or_app and $backend_or_app->isa('WebServerBackend::Backend')) {
    $backend = $backend_or_app;
  }
  elsif (ref $backend_or_app and $backend_or_app->isa('WebApplication')) {
    $backend = $backend_or_app->backend;
  }
  else {
    die "You have to give a reference to the application (backend).";
  }

  my $rights = $self->_master->Rights->get_objects({ application => $backend,
						     scope       => $self->get_user_scope,
						     data_type   => '*',
						     data_id     => '*',
						     name        => 'login',
						   });
  if (scalar @$rights ) {
    return $rights->[0];
  }
  
  my $right = $self->_master->Rights->create({ application => $backend,
					       scope       => $self->get_user_scope,
					       data_type   => '*',
					       data_id     => '*',
					       name        => 'login',
					       granted     => 0,
					       delegated   => 1,
					     });

  $self->active(1);
  
  unless (ref $right and $right->isa('WebServerBackend::Rights')) {
    die 'Unable to create Right in database.';

  }

  return $right;
}


=pod

=item * B<grant_login_right> (I<application>)

This method grants the login right for an application I<application>. The parameter
I<application> can either be an WebApplication object or a WebServerBackend::Backend
object. If a reference to a WebApplication is given, a mail will be send to the user
containing login and password.

=cut

sub grant_login_right {
  my ($self, $backend_or_app) = @_;

  # check backend (or get backend from WebApplication)
  my $backend;
  if (ref $backend_or_app and $backend_or_app->isa('WebServerBackend::Backend')) {
    $backend = $backend_or_app;
  }
  elsif (ref $backend_or_app and $backend_or_app->isa('WebApplication')) {
    $backend = $backend_or_app->backend;
  }
  else {
    die "You have to give a reference to the application (backend).";
  }

  # get login right
  my $rights = $self->_master->Rights->get_objects({ application => $backend,
						     scope       => $self->get_user_scope,
						     data_type   => '*',
						     data_id     => '*',
						     name        => 'login',
						   });
  # grant right
  if (scalar @$rights ) {
    $rights->[0]->granted(1);


    # resolve dependencies
    if(ref $WebConfig::LOGIN_DEPENDENCIES) {
      foreach my $d (@{$WebConfig::LOGIN_DEPENDENCIES->{$backend->name}}) {
	
	# get the backend
	my $d_backend = $self->_master->Backend->init({ name => $d });
	if (ref $d_backend) {
	 
	  # create and grant the login right
	  my $r = $self->add_login_right($d_backend);
	  $r->granted(1);
	}
	else {
	  die "Unable to find backend '$d'.";
	}
      }
    }					 

  } 
  else {
    die "User ".$self->login." has no login right to grant. Use add_login_right first!";
  }

  # generate a password if the user hasnt got one
  my $password;
  if ($self->password) {
    $password = '****** (this has not changed)';
  }
  else {
    $password = $self->generate_password();
  }

  # send mail
  #if (ref $backend_or_app && $backend_or_app->isa('WebApplication')) {
    
    my $body = HTML::Template->new(filename => TMPL_PATH.'EmailAcceptAccount.tmpl',
				   die_on_bad_params => 0);
    $body->param('FIRSTNAME', $self->firstname);
    $body->param('LASTNAME', $self->lastname);
    $body->param('LOGIN', $self->login);
    $body->param('NEWPASSWORD', $password);
    $body->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    $body->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
    $body->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
    
    $self->send_email( $WebConfig::ADMIN_EMAIL,
		       $WebConfig::APPLICATION_NAME.' - account request approved',
		       $body->output,
		    );
  #}
  
  return $self;
}


=pod

=item * B<deny_login_right> (I<application>)

This method revokes the login right for an application I<application>. The parameter
I<application> can either be an WebApplication object or a WebServerBackend::Backend
object. If a reference to a WebApplication is given, a mail will be send to the user
containing login and password.

=cut

sub deny_login_right {
  my ($self, $backend_or_app, $reason) = @_;

  # check backend (or get backend from WebApplication)
  my $backend;
  if (ref $backend_or_app and $backend_or_app->isa('WebServerBackend::Backend')) {
    $backend = $backend_or_app;
  }
  elsif (ref $backend_or_app and $backend_or_app->isa('WebApplication')) {
    $backend = $backend_or_app->backend;
  }
  else {
    die "You have to give a reference to the application (backend).";
  }

  # get login right
  my $rights = $self->_master->Rights->get_objects({ application => $backend,
						     scope       => $self->get_user_scope,
						     data_type   => '*',
						     data_id     => '*',
						     name        => 'login',
						   });
  # delete right
  if (scalar @$rights ) {
    $rights->[0]->delete();
  } 
  else {
    die "User ".$self->login." has no login right to deny.";
  }

  # send mail
  if (ref $backend_or_app && $backend_or_app->isa('WebApplication')) {
    
    my $body = HTML::Template->new(filename => TMPL_PATH.'EmailDenyAccount.tmpl',
				   die_on_bad_params => 0);
    $body->param('FIRSTNAME', $self->firstname);
    $body->param('LASTNAME', $self->lastname);
    $body->param('LOGIN', $self->login);
    $body->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    $body->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
    $body->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
    $body->param('REASON', $reason);

    $self->send_email( $WebConfig::ADMIN_EMAIL,
		       $WebConfig::APPLICATION_NAME.' - account request denied',
		       $body->output,
		    );
  }

  # clean up
  unless (scalar(@{$self->rights}) > 1) {
    $self->delete();
    return undef;
  }
  
  return $self;
}

=pod

=item * B<encrypt> (I<password>)

Encrypt I<password> and return the result. This is a static method that
does not require instantiating a user object in order to run.

=cut

sub encrypt {
  my ($password) = @_;

  my $seed = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
  return crypt($password, $seed);
}


=pod

=item * B<grant_group_access> (I<scope>)

This method grants the access to a scope (group) to a user. The user
will be notified via email.

=cut

sub grant_group_access {
  my ($self, $scope) = @_;
  
  unless (defined($scope)) {
    die "no scope defined in grant_group_access.\n";
  }
  
  my $group = $scope->name();
  my $user_has_scope = $self->_master->UserHasScope->get_objects( { scope => $scope, user => $self } );
  if (scalar(@$user_has_scope)) {
    $user_has_scope = $user_has_scope->[0];
    $user_has_scope->granted(1);
  } else {
    die "User ".$self->firstname()." ".$self->lastname()." has no scope ".$scope->name().".\n";
  }
  
  # send mail
  my $body = HTML::Template->new(filename => TMPL_PATH.'EmailAcceptGroupAccess.tmpl',
				 die_on_bad_params => 0);
  $body->param('FIRSTNAME', $self->firstname);
  $body->param('LASTNAME', $self->lastname);
  $body->param('GROUP', $group);
  
  $self->send_email( $WebConfig::ADMIN_EMAIL,
		     "group access to $group approved",
		     $body->output,
		   );
  
  return $self;
}

=pod

=item * B<deny_group_access> (I<scope>, I<reason>)

This method denies access to a group for a user. The user will be
notified via email, stating the reason if present. The request will
be deleted.

=cut

sub deny_group_access {
  my ($self, $scope, $reason) = @_;
  
  unless (defined($reason)) {
    $reason = "";
  }
  
  my $group = $scope->name();
  my $user_has_scope = $self->_master->UserHasScope->get_objects( { scope => $scope, user => $self } );
  if (scalar(@$user_has_scope)) {
    $user_has_scope = $user_has_scope->[0];
    $user_has_scope->delete();
  } else {
    die "User ".$self->firstname()." ".$self->lastname()." has no scope ".$scope->name().".\n";
  }
  
  # send mail
  my $body = HTML::Template->new(filename => TMPL_PATH.'EmailDenyGroupAccess.tmpl',
				 die_on_bad_params => 0);
  $body->param('FIRSTNAME', $self->firstname);
  $body->param('LASTNAME', $self->lastname);
  $body->param('GROUP', $group);
  $body->param('REASON', $reason);
  
  $self->send_email( $WebConfig::ADMIN_EMAIL,
		     "group access to $group approved",
		     $body->output,
		   );
  
  return $self;
}



=pod

=item * B<set_password> (I<password>, I<application>)

This method sets the password for a user to (I<password>). The
I<application> parameter is optional. If present, a mail will be
sent to the user with his password enclosed.

=cut

sub set_password {
  my ($self, $password, $application) = @_;

  my $new_password = encrypt($password);
  $self->password($new_password);

  if (ref $application && $application->isa('WebApplication')) {
    
    my $body = HTML::Template->new(filename => TMPL_PATH.'EmailNewPassword.tmpl',
				   die_on_bad_params => 0);
    $body->param('LOGIN', $self->login);
    $body->param('NEWPASSWORD', $password);
    $body->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    $body->param('APPLICATION_URL', $WebConfig::APPLICATION_URL);
    $body->param('EMAIL_ADMIN', $WebConfig::ADMIN_EMAIL);
    
    $self->send_email( $WebConfig::ADMIN_EMAIL,
		      $WebConfig::APPLICATION_NAME.' - new password requested',
		      $body->output,
		    );
  }
  
  return 1;
}


=pod

=item * B<generate_password> (I<application>)

This method generates a new (random) password for a user. The
I<application> parameter is optional. If present, a mail will be
sent to the user with his password enclosed. The new password 
will be returned by the method.

=cut

sub generate_password {
  my ($self, $application) = @_;
  my $new = join '', (0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64, rand 64, rand 64, rand 64, rand 64, rand 64, rand 64];
  $self->set_password($new, $application);
  return $new;
}
  

=pod

=item * B<check_password> (I<password>)

This method checks whether the passed password (I<password>) matches that of the user. 

=cut

sub check_password {
  my ($self, $password) = @_;

  if (crypt($password, $self->password) eq $self->password) {
    return 1;
  } else {
    return 0;
  }
}


=pod

=item * B<wikiname>

Return the wiki name of the current user. 

=cut

sub wikiname {
  my ($self) = @_;
  # Declare the return variable.
  my $retVal;
  # Find out if the simple case works. The simple case holds if the user's first
  # name has all its capitals at the beginning and has at least one non-capital
  # letter. In addition, the last name must begin with a capital and there can't
  # be special characters in either name.
  my ($first, $last) = ($self->firstname, $self->lastname);
  if ($first =~ /^[A-Z]+[a-z]+$/ && $last =~ /^[A-Z][A-Za-z0-9]*$/) {
    $retVal = "$first$last";
  } else {
    # Get the login name.
    my $login = $self->login;
    if ($login =~ /^TWiki/) {
      # Here we have an internal TWiki name, which is transmitted unchanged.
      $retVal = $login;
    } else {
      # Here we have a funky first or last name, so we use the login name instead.
      $retVal = "NmpdrUserX$login";
    }
  }
  # Return the result.
  return $retVal;
}

=pod

=item * B<find_by_wiki_name> (I<$db_master>, I<wiki_name>)

Find a user by his wiki name.

=cut

sub find_by_wiki_name {
    my ($db_master, $wiki_name) = @_;
    # Declare the return variable.
    my $retVal = [];
    # Parse the wiki name.
    if ($wiki_name =~ /^NmpdrUserX(.+)/) {
      # Here we have a user whose first and last names did not concatenate into a wiki name.
      # $1 contains the login name.
      my $login = $1;
      $retVal = $db_master->User->get_objects({ login => $login });
    } elsif ($wiki_name =~ /^TWiki(.+)/) {
      # Here we have one of the built-in users. The login name is in $1, except we need
      # to convert it to lower case.
      my $login = lc $1;
      $retVal = $db_master->User->get_objects({ login => $login });
    } elsif ($wiki_name =~ /([A-Z][a-z]+)(.+)/) {
      # Here we have a user whose wiki name could be computed unambiguously from the first
      # and last names.
      my ($firstName, $lastName) = ($1, $2);
      # Find the user.
      $retVal = $db_master->User->get_objects({ firstname => $firstName,
                                                lastname  => $lastName });
    }
    # Return the user objects found (if any).
    return $retVal;
}


=pod

=item * B<has_right> (I<application>, I<right>, I<data_type>, I<data_id>)

This method checks whether the user has the right (I<right>) in this application
(I<application>). I<application> may be undefined. Rights may optionally belong 
to a data type (I<data_type>) and an id (I<data_id>). 

=cut

sub has_right {
  my ($self, $application, $right, $data_type, $data_id, $delegatable) = @_;

#   my $key = join($;, {$application, $right, $data_type, $data_id, $delegatable});
#   if (exists($self->{rights_cache}->{$key}))
#   {
#       return $self->{rights_cache->{$key}};
#   }

  # check if user is active, otherwise default to false
  return undef unless ($self->active);

  # quote all things to go into the select statement
  my $dbh = $self->_master->db_handle();
  $right = $dbh->quote($right);
  if (defined($data_type)) {
    $data_type = $dbh->quote($data_type);
  }
  if (defined($data_id)) {
    $data_id = $dbh->quote($data_id);
  }

  # sanity check parameters
  my $scope_app  = 'Scope.application IS NULL';
  my $rights_app = 'Rights.application IS NULL';
  if ($application) {
    unless (ref $application && $application->isa('WebApplication')) {
      die "Method User->has_right called without a valid application parameter.\n";
    }
    my $app_id = $application->backend->_id;
    $scope_app  = "(Scope.application=$app_id OR Scope.application IS NULL)";
    $rights_app = "(Rights.application=$app_id OR Rights.application IS NULL)";
  }
  unless ($right) {
    die "Method User->has_right called without the parameter right.\n";
  }
  my $user_id = $self->_id;
  $data_type = ($data_type) ? " AND (Rights.data_type=$data_type OR Rights.data_type='*')" : '';
  $data_id = ($data_id) ? " AND (Rights.data_id=$data_id OR Rights.data_id='*')" : '';
  $delegatable = ($delegatable) ? " AND Rights.delegated=0" : '';

  my $sql = qq~SELECT data_id FROM (SELECT UserHasScope.scope FROM Scope LEFT JOIN UserHasScope ON Scope._id = UserHasScope.scope WHERE $scope_app AND UserHasScope.user=$user_id and UserHasScope.granted=1) AS t1 LEFT JOIN (SELECT data_id, scope FROM Rights WHERE $rights_app AND Rights.name=$right$data_type$data_id$delegatable AND Rights.granted=1) AS t2 ON t1.scope=t2.scope WHERE data_id IS NOT NULL;~;
  # query database
  my $sth = $self->_master->db_handle->prepare($sql);
  $sth->execute;

  my $data = $sth->fetchall_arrayref;
  $sth->finish;

  my $res = scalar(@$data);
#  $self->{rights_cache->{$key}} = $res;
  
  return $res;
}


=pod

=item * B<has_right_to> (I<application>, I<right>, I<data_type>)

This method return the data ids of the given data_type I<data_type> the user 
has the right (I<right>) to in this application (I<application>). If the list
of data ids contains the place holder '*' it will be returned as the first
entry of the list. I<application> may be undefined.

=cut

sub has_right_to {
  my ($self, $application, $right, $data_type) = @_;

  # check if user is active, otherwise default to false
  return undef unless ($self->active);

  # quote all things to go into the select statement
  my $dbh = $self->_master->db_handle();
  $right = $dbh->quote($right);
  $data_type = $dbh->quote($data_type);

  # sanity check parameters
  my $scope_app  = 'Scope.application IS NULL';
  my $rights_app = 'Rights.application IS NULL';
  if ($application) {
    unless (ref $application && $application->isa('WebApplication')) {
      die "Method User->has_right called without a valid application parameter.\n";
    }
    my $app_id = $application->backend->_id;
    $scope_app  = "(Scope.application=$app_id OR Scope.application IS NULL)";
    $rights_app = "(Rights.application=$app_id OR Rights.application IS NULL)";
  }
  unless ($right) {
    die "Method User->has_right called without the parameter right.\n";
  }
  unless ($data_type) {
    die "Method User->has_right called without the parameter data_type.\n";
  }

  my $user_id = $self->_id;

  my $sql = qq(SELECT data_id
	       FROM (SELECT UserHasScope.scope
		     FROM Scope LEFT JOIN UserHasScope ON Scope._id = UserHasScope.scope
		     WHERE $scope_app AND UserHasScope.user=$user_id AND UserHasScope.granted=1)
	       AS t1
	       LEFT JOIN (SELECT data_id, scope
			  FROM Rights
			  WHERE ($rights_app AND
				 Rights.name=$right AND
				 Rights.data_type=$data_type AND
				 Rights.granted=1))
	       AS t2 ON t1.scope=t2.scope
	       WHERE data_id IS NOT NULL);

  # query database
  my $sth = $self->_master->db_handle->prepare($sql);
  $sth->execute;

  my $data = $sth->fetchall_arrayref;
  $sth->finish;

  @$data = map { $_->[0] } @$data;

  @$data = sort { return ($a ne '*'); } @$data;
  return $data;

}

=item * B<has_star_right> (I<right>, I<data_type>)

This method return the a bool weither the user has a star right for a data type.

=cut

sub has_star_right {
  my ($self, $right, $data_type) = @_;

  # check if user is active, otherwise default to false
  return 0 unless ($self->active);

  # quote all things to go into the select statement
  my $dbh = $self->_master->db_handle();
  $right = $dbh->quote($right);
  $data_type = $dbh->quote($data_type);

  # sanity check parameters
  unless ($right) {
    die "Method User->has_star_right called without the parameter right.\n";
  }
  unless ($data_type) {
    die "Method User->has_star_right called without the parameter data_type.\n";
  }

  my $user_id = $self->_id;

  my $sql = qq(select count(_id) from (select scope from UserHasScope where user = $user_id and granted) as t1 left join (select * from Rights where name = $right and data_id = "*" and data_type = $data_type) as t2 on t1.scope=t2.scope where data_id is not null);

  # query database
  my $sth = $self->_master->db_handle->prepare($sql);
  $sth->execute;

  my $data = $sth->fetchall_arrayref;
  $sth->finish;

  # if star right found 
  return 1 if $data->[0]->[0] > 0;
  return 0;
}


=pod

=item * B<scopes> ()

Returns an array reference to all Scope objects this user is associated with.

=cut

sub scopes {
  my ($self) = @_;

  my $master = $self->_master();
  my $uhs = $master->UserHasScope->get_objects( { 'user' => $self, 'granted' => 1 } );
  my @scopes = map { $_->scope } @$uhs;

  return \@scopes;
}

=pod

=item * B<is_admin> (I<application>)

Returns true if the user is an admin for the application.

=cut

sub is_admin {
  my ($self , $application) = @_;

  my $master = $self->_master();
  my $admin_scopes = $master->Scope;
  my $uhs = $master->UserHasScope->get_objects( { 'user' => $self, 'granted' => 1 } );
  foreach my $us (@$uhs){

    if ( $us->scope->application && ($us->scope->name =~/Admin/) ){

      if ( ref $application ){
	return 1 if ( $application->name eq  $us->scope->application->name);
      }
      elsif ($application){
	return 1 if ( $application eq  $us->scope->application->name);
      }
      else{
	# return 1 unless ( $application eq  $us->scope->application->name);
      }

    }
    
  }
  

  return 0;
}

sub wants_all_rast_jobs
{
    my($self) = @_;
    return unless $self->is_admin('RAST');

    my $pref = $self->_master->Preferences->get_objects({ user => $self,
							      name => 'AdminUsersSeeAllJobs' });

    if (scalar(@$pref) && $pref->[0]->value eq 'no')
    {
	return 0;
    }
    return 1;
}

sub wants_rast_jobs_starting_with
{
    my($self) = @_;
    return unless $self->is_admin('RAST');

    my $pref = $self->_master->Preferences->get_objects({ user => $self,
							      name => 'AdminStartingJob' });

    if (scalar(@$pref) && $pref->[0]->value > 0)
    {
	return $pref->[0]->value;
    }
    else
    {
	return 1;
    }
}

=pod

=item * B<has_scope> (I<application>)

Returns true if the user has the scope for the application.

=cut

sub has_scope {
  my ($self , $scope, $application) = @_;

  my $scope_name;
  if (ref $scope){
    $scope_name = $scope->name;
  }
  else{
    $scope_name = $scope;
  }
  
  my $master = $self->_master();

  my $uhs = $master->UserHasScope->get_objects( { 'user' => $self, 'granted' => 1 } );
  foreach my $us (@$uhs){
    print STDERR $us->scope->name."\n";  
    if ( $us->scope->name =~/$scope_name/){
	print STDERR "FOUND " . $us->scope->name . "\n";
      if ( ref $application ){
	return 1 if ( $application->name eq  $us->scope->application->name);
      }
      elsif ($application){
	return 1 if ( $application eq  $us->scope->application->name);
      }
      elsif (!$application){
	return 1;
      }

    }
    
  }
  

  return 0;
}

sub has_group{
  my ($self , $scope, $application) = @_;
  return $self->has_scope($scope,$application);
}

=pod

=item * B<rights> (I<granted>, I<delegatable>)

Returns an array reference to all Rights objects this user has. Both parameters
I<granted> and I<delegatable> are optional. If present and true, the method will
only return Rights that already granted or not delegated.

=cut

sub rights {
  my ($self, $granted, $delegatable) = @_;

  my $master = $self->_master();
  my $rights = [];
  my $scopes = $self->scopes();

  foreach my $scope (@$scopes) {
    if (defined($granted)) {
      push(@$rights, @{$master->Rights->get_objects( { 'scope' => $scope, 'granted' => $granted } )});
    } else {
      push(@$rights, @{$master->Rights->get_objects( { 'scope' => $scope } )});
    }
  }

  if ($delegatable) {
    my $rights_bak = [];
    foreach my $right (@$rights) {
      unless ($right->delegated()) {
	push(@$rights_bak, $right);
      }
    }
    $rights = $rights_bak;
  }

  return $rights;
}


=pod

=item * B<check_database> (I<fix>)

This method checks the primary attributes, the User scope and the UserHasScope
association, as well as the right to edit oneself and prints to STDERR if 
problems are identified. If the optional I<fix> is provided and true, the method
will create the missing Scope, UserHasScope or rights.
Currently this is used by the script wa_user_check.pl.

=cut

sub check_database {
  my ($self, $fix) = @_;
  my $id = $self->_id();

  # check primary attributes
  unless($self->firstname) {
    print STDERR "[FATAL] User $id is missing a firstname.\n";
  }

  unless($self->lastname) {
    print STDERR "[FATAL] User $id is missing a lastname.\n";
  }

  unless($self->login) {
    print STDERR "[FATAL] User $id is missing a login name.\n";
  }

  unless($self->email) {
    print STDERR "[FATAL] User $id is missing an email address.\n";
  }

  unless($self->password) {
    if(scalar(@{$self->_master->Rights->get_objects({ scope => $self->get_user_scope,
						      name => 'login', 
						      granted => 1 })})) {
      print STDERR "[FATAL] User $id is missing a password.\n";
    }
    else {
      print STDERR "[WARN] User $id is missing a password, but has no login rights yet.\n";
    }
  }

  # check user scope
  unless($self->get_user_scope) {
    print STDERR "[FATAL] User $id has no user scope.\n";
    if ($fix) {
      print STDERR "[FIX].. creating user scope: ";
      my $scope = $self->_master->Scope->create({ 
			     name => $self->get_user_scope_name,
			     description => 'automatically created user scope'
			    });
      unless (ref $scope and $scope->isa('WebServerBackend::Scope')) {
	print STDERR " (". $self->get_user_scope_name.") failed.\n";
	return 0; # skip rest, depends on user scope!
      }
      else {
	print STDERR "done.\n";
      }
    }
  }

  # check UserHasScope
  unless($self->_master->UserHasScope->init({ user => $self, scope => $self->get_user_scope })) {
    print STDERR "[FATAL] User $id has no association to user scope.\n";
    if ($fix) {
      print STDERR "[FIX].. creating association between user and scope: ";
      my $has = $self->_master->UserHasScope->create({ user => $self, 
						       scope => $self->get_user_scope, 
						       granted => 1 }
						    );
      unless (ref $has and $has->isa('WebServerBackend::UserHasScope')) {
	print STDERR " (". $self->get_user_scope_name.") failed.\n";
	return 0; # skip rest, depends on user scope!
      }
      else {
	print STDERR "done.\n";
      }
    }
  }

  # check right to manage self
  unless (scalar @{$self->_master->Rights->get_objects({ scope       => $self->get_user_scope,
							 data_type   => 'user',
							 data_id     => $self->_id,
							 name        => 'edit',
						       })} ) {
    print STDERR "[WARN] User $id has no right to manage self (user, edit, self).\n";
    if ($fix) {
      print STDERR ".. creating right: ";
      my $right = $self->_master->Rights->create({ scope       => $self->get_user_scope,
						   data_type   => 'user',
						   data_id     => $self->_id,
						   name        => 'edit',
						   granted     => 1,
						   delegated   => 1,
						 });
      unless (ref $right) {
	print STDERR " ( user, edit $id ) failed.\n";
      }
      else {
	print STDERR "done.\n";
      }
    }
  }

  return 1;

}
