package WebComponent::RequestNewPassword;

# RequestNewPassword - component to request a password reset

# $Id: RequestNewPassword.pm,v 1.3 2008-09-03 21:01:19 parrello Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;


=pod

=head1 NAME

RequestNewPassword - component to request a password reset

=head1 DESCRIPTION

WebComponent to request a new password 

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
  my $self = shift->SUPER::new(@_);

  $self->application->register_action($self, 'request_new_password', 
				      $self->get_trigger('request_pw'));

  $self->{log} = 1;

  return $self;
}


=item * B<output> ()

Returns the html output of the Login component.

=cut

sub output {
  my ($self) = @_;

  my $content = $self->application->page->start_form('request_pw', 
		   { action => $self->get_trigger('request_pw') });

  $content .= "<table>";
  $content .= "<tr><td><strong>Login: </strong></td><td><input type='text' name='login'></td></tr>";
  $content .= "<tr><td><strong>Email address: </strong></td><td><input type='text' name='email'></td></tr>";
  $content .= "<td><input type='submit' class='button' value='Request new password'></td></tr>";
  $content .= "</table>";

  $content .= $self->application->page->end_form;

  return $content;
}

=item * B<request_new_password> ()

Executes the request new password action. The method will set a new password
to the user specified by login and email and sent it by email. 

=cut

sub request_new_password {
  my ($self) = @_;

  my $login = $self->application->cgi->param('login') || "";
  my $email = $self->application->cgi->param('email') || "";

  unless ($login and $email) {
    $self->application->add_message('warning', 'You must enter both login name and email address.');
    return 0;
  }

  my $user = $self->application->dbmaster->User->init({ login => $login });

  if (ref $user and $user->email eq $email) {

    if($user->has_right($self->application, 'login')) {
      $user->generate_password($self->application);
      $self->application->add_message('info', "You have successfully requested a new password for the login '$login'. You should receive an email shortly.");
      return 1;
    }
    else {
      $self->application->add_message('warning', 'You have no access to this web server. Please try to request a new password from a server you are allowed to use.');
      warn "Attempt to reset password for account '$login' (email: $email). No login right." if ($self->log);
      return 0;
    }
  }
  else {
    $self->application->add_message('warning', 'Mismatch between login name and email address.');
    warn "Attempt to reset password for account '$login' (email: $email). Mismatch." if ($self->log);
    return 0;
  }

}
 

=item * B<log> (I<bool>)

Switch to toggle logging of unsuccessful password requests. By default on. 

=cut

sub log {
  if($_[1]) {
    $_[0]->{log} = $_[1];
  }
  return $_[0]->{log};
}

