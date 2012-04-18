package WebComponent::Login;

# Login - component for user authentication

# $Id: Login.pm,v 1.14 2011-05-06 16:06:58 paczian Exp $

use strict;
use warnings;

use base qw( WebComponent );

1;


=pod

=head1 NAME

Login - component for user authentication input form

=head1 DESCRIPTION

WebComponent for user authentication input form

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  $self->{'small_login'} = 0;
  $self->{'target_page'} = '';

  $self->application->register_action($self, 'perform_login', 'perform_login');
  $self->application->page->omit_from_session(1);

  return $self;
}

=item * B<output> ()

Returns the html output of the Login component.

=cut

sub output {
  my ($self) = @_;

  # start the form
  my $content = $self->application->page->start_form('login_form', { page => $self->application->page->name });

  # check for small version of login
  if ($self->small_login) {
    if ($self->application->session->user) {
      return "";
    } 
    else {
      $content .= "<span style='font-size: 8pt;'>Login</span><br>";
      $content .= "<input type=text name=login style='width: 80px;'>";
      $content .= "<br>";
      $content .= "<span style='font-size: 8pt;'>Password</span><br>";
      $content .= "<input type=password name=password style='width: 80px;'><input type='submit' style='display: none;'>";
      $content .="&nbsp;<img src=\"$FIG_Config::cgi_url/Html/login.png\" onclick='document.getElementById(\"login_form\").submit();' title='Login' style='width: 24px; height: 24px; cursor: pointer;'>";
      $content .= "<input type='hidden' name='action' value='perform_login'>";
    }
  }

  # display the simple form
  else {
    $content .= "<table>";
    $content .= "<tr><td>Login</td><td><input type=text name=login></td></tr>";
    $content .= "<tr><td>Password</td><td><input type=password name=password></td>";
    $content .= "<td><input type=submit class=button value='Login'></td></tr>";
    $content .= "</table>";
    $content .= "<input type='hidden' name='action' value='perform_login'>";
  }

  # close the form
  $content .= $self->application->page->end_form;

  return $content;
}


=item * B<perform_login> ()

This action will check the authentication of the user

=cut

sub perform_login {
  my ($self) = @_;

  $self->application->cgi->delete('action');
  
  my $login = $self->application->cgi->param('login');
  my $password = $self->application->cgi->param('password');
  
  unless (defined($login) && defined($password)) {
    $self->application->add_message('warning', 'You must enter both login and password.');
    return 1;
  }

  # try to initialize user
  my $user = $self->application->dbmaster->User->init( { login => $login } );
  if (ref $user and crypt($password, $user->password) eq $user->password) {

    if ($user->active and ($user->has_right($self->application, 'login') || $FIG_Config::open_gates)) {

      $self->application->session->user($user);
      
      my $to = $self->{'target_page'} 
	|| $self->application->session->get_entry(-current => 1) 
	  || $self->application->default;
      $self->application->redirect($to);
      
    }
    else {
      $self->application->add_message('warning', "Sorry, you have no access to this web server. <a href='".$self->application->url."?page=Register&tab=existing&login=".$user->login."&email=".$user->email."'>Request access</a>");
      return 0;
    }
  } 
  else {
    $self->application->add_message('warning', 'Login or Password incorrect. Please try again.');
    return 0;
  }
  
  return 1;
}

=item * B<login_target_page> (I<page>)

Getter/Setter for the name of the page the login component should redirect to after a
successful login. If not set, the default behaviour is to go to the default page or
coming from a page which requires login to the previous session item.

=cut

sub login_target_page {
  if (scalar(@_) > 1) {
    $_[0]->{'target_page'} = $_[1];
  }
  return $_[0]->{'target_page'};
}


=item * B<small_login> (I<status>)

Getter/Setter for the boolean small_login attribute of this component. Default is false.
If set to true, the output method will return a small version of the login, if there 
currently is no user.

=cut

sub small_login {
  if (scalar(@_) > 1) {
    $_[0]->{'small_login'} = $_[1];
  }
  return $_[0]->{'small_login'};
}


sub require_css {
  return "$FIG_Config::cgi_url/Html/Login.css";
}
