package WebApplication;

# WebApplication - framework to develop application-like web sites

use strict;
use warnings;

use FreezeThaw qw( freeze thaw );

use CGI;
use CGI::Cookie;
use HTML::Strip;
use DBMaster;
use Scalar::Util qw/reftype/;

# include default WebPages
use WebMenu;
use WebConfig;
use WebPage::Error;
use WebApplicationDBHandle;

use Conf;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

1;


=pod

=head1 WebApplication

=head2 DESCRIPTION

The WebApplication is a framework to support fast, comprehesible and componentalized
creation of applications on the web. Main features include:

=over 4

=item * menus

=item * user authentication

=item * page oriented structure

=item * session management

=item * action management

=item * reusable components

=back

For setup and usage, please refer to the WebApplication Tutorial.

=head2 METHODS

=head3 B<new> ($params)

B<Returns:> a reference to a WebApplication object

Creates a new instance of the WebApplication object.
$params is a hash which supports the following values:

=over 4

=item dbmaster

An instance of the PPO DBMaster which points to the user database.
If this parameter is omitted, a dbmaster will be created with the following settings in
WebConfig, located in FIGdisk/config/WebApplication/$appname.cfg:

=over 8

=item * DBNAME

=item * DBHOST

=item * DBUSER

=item * DBPWD

=back

If the configuration file is not present, these values will default to the ones set in
WebConfig

=item menu

An instance of WebMenu which will represent the current structure of the navigation menu.
If this is omitted it will default to an empty menu.

=item default

The name of the page to be displayed when no $cgi->param('page') is present.

=item layout

An instance of WebLayout which represents the layout of the page.

=item id

A string representing the name of the application. This is used to identify the application
in the database. If this does not yet exist in the database, it will be created.

=item cgi

An instance of the CGI object. If omitted, this will default to CGI->new()

=item noTrace

If TRUE, tracing will not be activated. This is useful when you want to activate
tracing before constructing the WebApplication object.

=back

=cut

sub new {
  my ($class, $params) = @_;
  
  my $dbmaster     = $params->{'dbmaster'};
  my $menu         = $params->{'menu'} || WebMenu->new();
  my $default      = $params->{'default'};
  my $layout       = $params->{'layout'};
  my $backend_name = $params->{'id'};
  my $cgi          = $params->{'cgi'} || CGI->new();

  my $hs = HTML::Strip->new();
  my @cgi_params = $cgi->param;
  foreach my $p (@cgi_params) {
    my @plist = $cgi->param($p);
    foreach my $p1 (@plist) {
      if ($p1 && defined(reftype($p1)) && (reftype($p1) eq "")) {
        $p1 = $hs->parse($p1);
      }
    }
    $cgi->param($p, @plist);
  }
  $hs->eof;

  my $self = { cgi         => $cgi,
	       menu        => $menu,
	       menu_backup => freeze($menu),
	       layout      => $layout,
	       backend     => undef,
	       page        => undef,
	       default     => $default,
	       error       => undef,
	       redirect    => undef,
	       show_login_user_info => 0,
	       fancy_login => 0,
	       messages    => {},
	       components  => {},
	       component_index => {},
	       data_handlers => {},
	       actions     => {},
	       time        => time,
	       page_title_prefix => '',
	       test_bot    => $cgi->param('test_bot') || 0,
	       no_bot      => 0,
	       bot_no_follow => 0,
	       metatags    => [],
	       strict_browser => 0,
	       anonymous_mode => $Conf::anonymous_mode || 0,
               transmitted  => 0,
	       require_terms_of_service => $Conf::require_terms_of_service || 0,
	       in_request => 0,
	       js_init_functions => [],
	     };

  bless $self, $class;
  # Generate an event if we're tracking this user.
  # read in local configuration into global WebConfig
  &WebConfig::import_local_config($backend_name);
  
  # create a dbmaster
  unless (defined($dbmaster) || $WebConfig::NODB) {
    my $error;
    ($dbmaster, $error) = WebApplicationDBHandle->new();
    if ($error) {
      print STDERR $@;
    }
  }
  $self->{dbmaster} = $dbmaster;
  if ($dbmaster && !$self->anonymous_mode()) {
    $self->{session} = $dbmaster->UserSession->create($cgi);
    
    # check if application is registered
    my $backend = $dbmaster->Backend->init({ 'name' => $backend_name });
    if (ref $backend and $backend->isa('WebServerBackend::Backend')) {
      $self->{'backend'} = $backend;
    }
    else {
      $self->{'backend'} = $dbmaster->Backend->create({ 'name' => $backend_name });
    }
    
    unless ($self->backend) {
    }
  } else {

    # create a backend stub
    my $backend = Backend->new( $backend_name );
    {
      package Backend;
      sub new {
	my $self = { name => $_[1] };
	bless $self, 'Backend';
      }
      sub name {
	return $_[0]->{name};
      }
      sub init {
	return undef;
      }
    }
    $self->{backend} = $backend;
    
    # create a session stub
    my $session = UserSession->new();
    {
      package UserSession;
      sub new {
	my $self = { user => undef };
	bless $self, 'UserSession';
      }
      sub add_entry { return undef; }
      sub get_entry { return undef; }
      sub user { return $_[0]->{user}; }
      sub cookie {
	my ($self) = @_;
	my $uname = '0';
	if (defined($self->user)) {
	  $uname = $self->user->login;
	}
	return CGI::Cookie->new( -name    => 'AnonWebSession',
				 -value   => $uname,
				 -expires => '+2h' );
      }
    }
    $self->{session} = $session;
  }
  
  return $self;
}
  


#******************************************************************************
#* ACCESSOR METHODS
#******************************************************************************

=pod

=head3 B<default> ()

B<Returns:> a scalar string

Getter for the default attribute. The default attribute determines the initial page
to be displayed if no $cgi->param('page') is given.

=cut

sub default {
  return $_[0]->{default};
}


=pod

=head3 B<dbmaster> ()

B<Returns:> a reference to a DBMaster object

Getter for the dbmaster attribute. See above description for details.

=cut

sub dbmaster {
  return $_[0]->{dbmaster};
}


=pod

=head3 B<session> ()

B<Returns:> a reference to a WebServerBackend::Session object

Getter for the session attribute. This is an instance of the Session object, which
stores the current user and a history of three last visited pages.

=cut

sub session {
  return $_[0]->{session};
}


=pod

=head3 B<cgi> ()

B<Returns:> a reference to a CGI object

Getter for the cgi attribute. This the instance of the CGI object used throughout the
WebApplication.

=cut

sub cgi {
  my ($self, $cgi) = @_;

  if (defined($cgi)) {
    $self->{cgi} = $cgi;
  }
  
  return $self->{cgi};
}


=pod

=head3 B<menu> ()

B<Returns:> a reference to a WebMenu object

Getter for the menu attribute. This is an instance of the WebMenu object which stores
the structure of the menu.

=cut

sub menu {
  return $_[0]->{menu};
}


=pod

=head3 B<layout> ()

B<Returns:> a reference to a WebLayout object

Getter for the layout attribute. This is an instance of the WebLayout object which
stores required javascript, css and the html template.

=cut

sub layout {
  return $_[0]->{layout};
}


=pod

=head3 B<backend> ()

B<Returns:> a reference to a WebServerBackend object

Getter for the backend attribute. This is an instance of the WebServerBackend object
which is used to identify the current application.

=cut

sub backend {
  return $_[0]->{'backend'};
}

=pod

=head3 B<url> (I<url>)

B<Returns:> a scalar string

Getter / setter for the url attribute. This will return the name of the cgi script of
this application (e.g. index.cgi).

=cut

sub url {
  my ($self, $url) = @_;

  if (defined($url)) {
    $self->{url} = $url;
  }

  unless (defined($self->{url})) {
    my $cgi = $_[0]->{'cgi'};
    $url = $cgi->url(-relative=>1);
    $url =~ s/\.cgi.*$/\.cgi/;
    $self->{url} = $url
  }

  return $self->{url};
}


=pod

=head3 B<error> (I<error>)

B<Returns:> a scalar string

Getter / setter for the current error status. If the optional parameter I<error> is
given, the error status is stored in the application. Setting this parameter will cause
the application to not display the current page, but an error page stating this
error message instead.

=cut

sub error {
  my ($self, $message) = @_;
  if (defined $message) {
    $self->{error} = $message;
  }
  return $self->{error};
}


=pod

=head3 B<page> (I<page>)

B<Returns:> a reference to a WebPage object

Returns a reference to the current WebPage object. If the optional parameter I<page> is
given, the page object is stored in the application.

=cut

sub page {
  if ($_[1]) { 
    $_[0]->{'page'} = $_[1];
  }
  return $_[0]->{'page'};
}


=pod 

=head3 B<show_login_user_info> (I<BOOL>)

B<Returns:> a scalar boolean

Get/set the flag if the login box should be inserted into the user info template. The
default value is false.

=cut

sub show_login_user_info {
  if (scalar(@_) > 1) {
    $_[0]->{show_login_user_info} = $_[1];
  }
  return $_[0]->{show_login_user_info};
}

=pod 

=head3 B<fancy_login> (I<BOOL>)

B<Returns:> a scalar boolean

Get/set the flag if the fancy login box should be inserted into the user info template. The
default value is false.

=cut

sub fancy_login {
  if (scalar(@_) > 1) {
    $_[0]->{fancy_login} = $_[1];
  }
  return $_[0]->{fancy_login};
}


=pod

=head3 B<rights> ()

B<Returns:> a reference to an array of Right objects

Returns a reference to an array of Rights objects this application supports.

=cut

sub rights {
  my ($self) = @_;

  # check if the rights have been loaded
  unless (defined($self->{'rights'})) {
    
    # set the rights
    {
      no strict;
      my $rights_method = $self->backend->name()."::MyAppRights::rights()";
      my $rights_module = "require " .$self->backend->name()."::MyAppRights;";
      eval($rights_module);
      $self->{'rights'} = eval($rights_method);
    }
  }

  return $self->{'rights'};
}



#******************************************************************************
#* WEB COMPONENTS
#******************************************************************************

=pod

=head3 B<register_component> (I<component_name>, I<identifier>)

B<Returns:> a reference to a WebComponent object

Register a web component of the name I<component_name> where I<component_name>
is a module in the WebComponent directory. Web components are re-usable html 
blocks to include into web pages like default dialogs, tables, charts and so on.
This method returns a reference to a WebComponent object.
I<identifier> is a unique name which is used to later reference that component.

=cut

sub register_component {
  my ($self, $component, $id) = @_;

  # require web component
  $component = 'WebComponent::'.$component;
  {
    no strict;
    eval "require $component;";
  }

  # init internal component cache if necessary
  unless ($self->{'components'}->{$component}) {
    $self->{'components'}->{$component} = [];
  }

  # check for singleton
  my $web_component;
  if (scalar(@{$self->{'components'}->{$component}}) && $self->{'components'}->{$component}->[0]->{singleton}) {
    
    # get the existing component
    $web_component = $self->{'components'}->{$component}->[0];

  } else {

    # init new web component
    $web_component = $component->new($self, scalar(@{$self->{'components'}->{$component}}), $component);
    $web_component->{_id} = $id;

    push @{$self->{'components'}->{$component}}, $web_component;
  }

  # update index
  $self->{'component_index'}->{$id} = $web_component;

  return $web_component;

}


=pod

=head3 B<component> (I<identifier>)

B<Returns:> a reference to a WebComponent object

Retrieve the web component registered with the unique name I<identifier> from
the component repository of the WebApplication. The method confesses if called
with an unknown identifier.

=cut

sub component {
  my ($self, $id) = @_;

  unless ($self->{'component_index'}->{$id}) {
    return undef;
  }
  return $self->{'component_index'}->{$id};

}



#******************************************************************************
#* DATA HANDLING
#******************************************************************************

=pod

=head3 B<data_handle> (I<type>, I<options>)

B<Returns:> a reference to an object

Request the DataHandler of the given type I<type>. Some DataHandlers may accept
additional parameters, those can be passed by providing the optional parameter
I<options>.

=cut

sub data_handle {
  my ($self, $type, $options) = @_;
  
  # get from internal data cache if possible
  unless ($self->{'data_handlers'}->{$type}) {

    # require the data handler package
    my $package = $self->backend->name().'::DataHandler::'.$type;
    {
      no strict;
      eval "require $package";
      my $error = "";
      if ($@) {
	$error = $@;
	$package = 'DataHandler::'.$type;
	eval "require $package";
	if ($@) {
	  return undef;
	}
      }
    }
    
    my $data = $package->new($self);
    $self->{'data_handlers'}->{$type} = $data;
    
  }

  if ($options) {
    return $self->{'data_handlers'}->{$type}->handle($options);
  }

  return $self->{'data_handlers'}->{$type}->handle;
 
}



#******************************************************************************
#* ACTION MANAGEMENT
#******************************************************************************

=pod

=head3 B<register_action> (I<object>, I<method>, I<trigger>)

B<Returns:> a reference to a WebApplication object

Registers an action with the web application framework. If the WebApplication is
called with the cgi parameter I<action>, it will check if the action has been registered.
If not, it will throw an error. If the action is registered, it's method will be
executed in between WebPage->init and WebPage->output.

=cut

sub register_action {
  my ($self, $object, $method, $trigger) = @_;
  
  $self->{'actions'}->{$trigger} = [ $object, $method ];

  return $self;

}

=pod 

=head3 B<execute_action> ()

Checks if a cgi param parameter 'action' is present and if it is registered as a trigger,
then executes the action (invokes the method on the WebPage or WebComponent object).

=cut

sub execute_action {
  my ($self) = @_;

  return unless ($self->cgi->param('action'));
  my $action = $self->cgi->param('action');

  if ($self->{'actions'}->{$action}) {
    my ($object, $method) = @{$self->{'actions'}->{$action}};
    if (ref $object and $method) {
      my $result = $object->$method();
      push @{$self->{'actions'}->{$action}}, $result;
    }
  }
  else {
    $self->error("This page was called with an unregistered action parameter '".
		 $self->cgi->param('action')."'.");
  }

} 


=pod 

=head3 B<get_action_result> (I<trigger>)

B<Returns:> whatever the according action method returns

Return the result of an action registered with the trigger I<trigger>. If the
action has not been executed this will return undef.

=cut

sub get_action_result {
  my ($self, $trigger) = @_;
  if ($self->{'actions'}->{$trigger}) {
    return $self->{'actions'}->{$trigger}->[2];
  }
} 



#******************************************************************************
#* APPLICATION MESSAGES
#******************************************************************************

=pod

=head3 B<add_message> (I<msg_type>, I<message>)

B<Returns:> a reference to a WebApplication object

Adds a message with the content of I<message> to the output of the page. The
message type I<msg_type> determines the css formatting and position of the
html output.
The following message type are recognised: 'warning', 'info'.

=cut

sub add_message {
  my ($self, $type, $msg, $fadetimer) = @_;

  # check type

  # check msg
  unless ($msg) {
    print STDERR "Empty message in method add_message.";
    $msg = '';
  }

  # init message type if necessary
  unless ($self->{'messages'}->{$type}) {
    $self->{'messages'}->{$type} = [];
  }

  my $fade_flag = 1;
  foreach(@{$self->{'messages'}->{$type}}){
    if($_ =~ /onload/){
      $fade_flag = 0; 
    }
  }

  if($fadetimer && $fade_flag){
    my $div_id;
    if ($type eq 'warning'){
      $div_id = 'warning';
    } else {
      $div_id = 'info';
    }
    $msg .= "<img src=\"$Conf::cgi_url/Html/clear.gif\" onload='fade(\"" . $div_id . "\", ". $fadetimer . ");'>";
  }
  
  push @{$self->{'messages'}->{$type}}, $msg;
  return $self;


}


=pod

=head3 B<get_messages> (I<msg_type>)

B<Returns:> a scalar string

Returns an array reference to all message of the type I<msg_type>.
The following message type are recognised: 'warning', 'info'.

=cut

sub get_messages {
  my ($self, $type) = @_;

  my $msg = [];

  # get messages of that type
  if ($self->{'messages'}->{$type}) {
    $msg = $self->{'messages'}->{$type};
  }

  return $msg;

}



#******************************************************************************
#* PAGE REDIRECTION
#******************************************************************************

=pod

=head3 B<redirect> (I<page>)

B<Returns:> a scalar string

Request a redirect to another WebApplication page. I<params> is mandatory 
and expects either the name of a page module or a hash containing the page 
module name and the frozen cgi parameters

=cut

sub redirect {
  my ($self, $params) = @_;

  if ($params) {
    if (ref($params) eq 'HASH') {
      $self->{redirect} = $params;
      unless (defined($params->{page}) && length($params->{page})) {
	$self->{redirect}->{page} = $self->default;
      }
    } else {
      $self->{redirect} = { page => $params };
    }
  }

  return $self->{redirect};
}


=pod

=head3 B<do_redirect> ()

Executes the actual redirect to another WebPage available in the current WebApplication.
If the page redirected from is omitted from the session, the redirect will flush all
CGI parameters before the redirect. 
If the redirect is with frozen CGI parameters, tose CGI parameters are restored.

=cut

sub do_redirect {
  my ($self) = @_;

  # check if we have at least a page to redirect to
  unless ($self->redirect->{page}) {
    die "redirect called without page to redirect to.\n";
  }

  # check for recursive call of redirect
  if ($self->{last_redirect} && ($self->{last_redirect} eq $self->redirect->{page})) {
    die "recursive call of redirect.\n";
  }

  # clear cgi params from omitted pages
  $self->cgi->delete_all() if ($self->page->omit_from_session);

  # set up new cgi data
  if ($self->redirect->{parameters}) {
    $self->cgi->delete_all();
    my @t = thaw($self->redirect->{parameters});
    my $params = $t[0];
    foreach my $p (keys(%$params)) {
      $self->cgi->param( -name => $p, -values => $params->{$p});
    }
  }

  # set the page parameter
  $self->cgi->param('page', $self->redirect->{page});

  # reset application and re-run
  $self->{last_redirect} = $self->redirect->{page};
  $self->reset_application;
  $self->run;

}


=pod

=head3 B<reset_application> ()

Resets all internal variables of the WebApplication except for already generated 
messages. This will also restore the default menu from the backup copy.

=cut

sub reset_application {
  my $self = shift;
  my ( $menu ) = thaw( $self->{'menu_backup'} );
  $self->{'menu'}            = $menu;
  $self->{'error'}           = undef;
  $self->{'redirect'}        = undef;
  $self->{'components'}      = {};
  $self->{'component_index'} = {};
  $self->{'actions'}         = {};

}

#******************************************************************************
#* CONTENT GENERATION
#******************************************************************************


=pod 

=head3 B<check_for_maintenance> (I<read_maintenance_msg_flag>)

B<Returns:> an array of $flag and $msg or a scalar string

Returns true if the server is locked down for maintenance. The method checks
for the presence of a I<Backend_name>.disabled file at the location of the 
script running the WebApplication. 
If the optional parameter I<read_maintenance_msg_flag> is provided and true,
the method will read out the content of the file and return it. This is used
by the Maintenance page to disabled a non default maintenance notification.

=cut

sub check_for_maintenance {
  my $disabled = $_[0]->backend->name.".disabled";
  my $flag = (-e $disabled);
  my $msg;
  if ($flag and $_[1]) {
    open(MSG, "$disabled");
    $msg = <MSG>;
    close(MSG);
    return ($flag, $msg);
  }

  return $flag;
}


=pod

=head3 B<check_for_silent_login> ()

This method checks for the presence of the CGI parameter I<silent_login>
to allow authenticating as a user from an URL. If present, this CGI param
will be read as loginname:password and the WebApplication tries to login
as that user.

=cut

sub check_for_silent_login {
  if ($_[0]->cgi->param('silent_login')) {
    $_[0]->cgi->param('silent_login') =~ /^([^:.]+)\:(.+)$/ ;
    
    my $user = $_[0]->dbmaster->User->init( { login => $1 } );
    if (ref $user and $user->active and 
	crypt($2, $user->password) eq $user->password) {
      $_[0]->session->user($user);   
      warn "Silent authentication successful: $1\n";
    }
    else {
      warn "Silent authentication failed: $1\n";
    }
    
  }
}

=pod

=head3 B<check_for_anonymous_login> ()

This method checks for the presence of the CGI parameter I<anonymous_login>
to keep the chosen name of the current user if the application is running in
anonymous mode.

=cut

sub check_for_anonymous_login {
  my ($self) = @_;
  
  return undef unless $self->anonymous_mode;
  
  my $cgi = $self->cgi;
  my $cookie = $cgi->cookie('AnonWebSession');
  my $uname = $cgi->param('anonymous_login') || $cookie;
  
  if ($uname) {
    if ($uname eq 'logout') {
      $self->session->{user} = undef;
    } else {
      $self->session->{user} = User->new( $uname );
      {
	package User;
	sub new {
	  my $self = { firstname => $_[1] };
	  bless $self, 'User';
	}
	sub has_right { return 1; }
	sub firstname { return $_[0]->{firstname}; }
	sub lastname { return '';  }
	sub login { return $_[0]->{firstname}; }
	sub has_right_to { return []; }
	sub get_user_scope { return {} };
	sub is_admin { return 0; }
	sub _id { return undef; }
      }
    }
}

# create a dbmaster stub
my $dbmaster = Local::DBMaster->new( $self );
{
  package Local::DBMaster;
  sub new {
    my $self = { application => $_[1],
		 session => $_[1]->session };
    bless $self, 'Local::DBMaster';
  }
  sub Preferences {
    return Preferences->new( $_[0]->{session} );
  }
  
  sub Rights {
    return Rights->new();
  }
  
  sub Backend {
    return $_[0]->{application}->{backend};
  }
  
  package Preferences;
  sub new {
    my $self = { session => $_[1] };
    bless $self, 'Preferences';
  }
  
  sub get_objects {
    if ($_[1]->{name} && $_[1]->{name} eq 'SeedUser') {
      return [ Preference->new( $_[0]->{session} ) ];
    } else {
      return [];
    }
  }
  
  sub create {
    return undef;
  }
  
  package Preference;
  sub new {
    my $self = { session => $_[1] };
    bless $self, 'Preference';
  }
  
  sub name {
    my $name = '';
    if ($_[0]->value) {
      $name = 'SeedUser';
    }
    return $name;
  }
  
  sub value {
    my ($self) = @_;
    my $user = 0;
    if ($self->{session}->user) {
      $user = $self->{session}->user->login;
    }
    return $user;
  }
  
  package Rights;
  sub new {
    my $self = {};
    bless $self, 'Rights';
  }
  
  sub get_objects {
    return [];
  }
  
  sub create {
    return Right->new;
  }
  
  package Right;
  sub new {
    my $self = {};
    bless $self, 'Right';
  }
}
$self->{dbmaster} = $dbmaster;
return;
}


=pod

=head3 B<check_rights> ()

This method takes a rights array and checks if the user has all the necessary 
rights to proceed. If no user is logged in, the method redirects to the login
page, if the user is missing a right an error page will be shown. If everything 
is fine, it will return true.
The run method automatically calls this method with the page required rights
as input. 

=cut

sub check_rights {
  my ($self, $rights) = @_;

  if(scalar(@$rights)) {
    unless ($self->session->user) {
      $self->redirect('Login');
      $self->do_redirect();
      die 'cgi_exit';
    }
    else {
      my $loginName = $self->session->user->login;
      foreach my $right (@$rights) {
	unless ($self->session->user->has_right($self, $right->[0], $right->[1], $right->[2], $right->[3])) {
	  $self->error( "Sorry, but you are lacking the rights required for this page." );
	  last;
	}
      }
    }
  }

  return $self;

}


=pod

=head3 B<check_requirements> ()

This method queries the WebPage and WebComponents for javascript and/or css
requirements and adds those files to the page output.

=cut

sub check_requirements {
  my ($self) = @_;

  # build a hash over all required css and javascript files
  # to make sure to include each file only once
  my $css = {};
  my $js  = {};
  my $orderedCSS = [];
  my $orderedJS = [];
  my $addedCSS = {};
  my $addedJS = {};

  # include IE compatibility script and style
  my $user_agent = $ENV{HTTP_USER_AGENT};
  if ($user_agent && $user_agent =~ /MSIE/) {
    $self->layout->add_css_reverse("$Conf::cgi_url/Html/ie7-css.css");
    $js->{"$Conf::cgi_url/Html/ie7-standard-p.js"} = 1;
  }

  # include message fade script
  $js->{"$Conf::cgi_url/Html/fade.js"} = 1;

  # Depth-first addition of ordered JS and CSS files 
  my $obj = $self->page();
  my $tail = [];
  do {
      while ( defined($obj->{'childComponents'}) &&
              @{$obj->{'childComponents'}} > 0 ) {
        push(@$tail, $obj);
        $obj = shift @{$obj->{'childComponents'}};
      } # bottoming out at deepest component, add CSS, JS
      foreach my $cssFile (@{$obj->{'_orderedCSS'}}) {
        unless(defined($addedCSS->{$cssFile})) {
            push(@$orderedCSS, $cssFile);
            $addedCSS->{$cssFile} = 1;
        }
      }
      foreach my $jsFile (@{$obj->{'_orderedJS'}}) {
        unless(defined($addedJS->{$jsFile})) {
            push(@$orderedJS, $jsFile);
            $addedJS->{$jsFile} = 1;
        }
      }
      $obj = pop(@$tail); # then begin climbing back up
  } while ( defined($obj) ); # until we reach the top
  
  # check page requirements
  foreach (@{$self->page->require_css}) {
    $css->{$_} = 1;
  }

  foreach (@{$self->page->require_javascript}) {
    $js->{$_} = 1;
  }

  # check components requirements
  foreach my $type (keys %{$self->{'components'}}) {
    foreach my $component (@{$self->{'components'}->{$type}}) {
      
      if ($component->require_css) {
	$css->{$component->require_css} = 1;
      }

      foreach (@{$component->require_javascript}) {
	$js->{$_} = 1;
      }

    }
  }

  # generate css / js head block
  foreach (keys %$css) {
    $self->layout->add_css($_);
  }
  foreach (@$orderedCSS) {
    $self->layout->add_css($_);
  }
  foreach (keys %$js) {
    $self->layout->add_javascript($_);
  }
  foreach (@$orderedJS) {
    $self->layout->add_javascript($_);
  }

}

# checks whether the current browser is supported
sub check_browser {
  my $user_agent = $ENV{HTTP_USER_AGENT};

  # check for each of the supported browsers
  if ($user_agent &&
      (
       (($user_agent =~ /Firefox\/(\d+)/) && $1 > 1) ||
       (($user_agent =~ /Chrome\/(\d+\.\d+)/) && $1 > 0.2) ||
       ($user_agent =~ /Safari/) ||
       (($user_agent =~ /MSIE (\d+\.\d+)/) && $1 > 5))) {
	  return (1, '');
  } else {
    return (0, "You are using an unsupported browser. Some of the features of this application may not be available. We are currently developing for Firefox 2.x, Safari 2.x, MS InternetExplorer 6.x, Chrome 0.2, and higher versions.");
  }
}

sub check_browser_strict {
  my ($self) = @_;
  my $user_agent = $ENV{HTTP_USER_AGENT};
  
  my $ua = '';
  if ($user_agent =~ /Chrome\/(\d+\.\d+)/) {
    $ua = "Chrome";
  } elsif ($user_agent =~ /MSIE (\d+\.\d+)/) {
    $ua = "Microsoft Internet Explorer";
  } elsif ($user_agent =~ /Safari/) {
    $ua = "Safari";
  } else {
    $ua = "an unknown browser";
  }

  # check for each of the supported browsers
  if ($user_agent =~ /Firefox\/(\d+)/) {
    return (1, '');
  } else {
    my $popup = "<img src='./Html/clear.gif' onload='if (! confirm(\"This application has been optimized for the Firefox browser. Since you are using $ua, many features will not be available and / or behave incorrectly. Click OK to continue or CANCEL to download Firefox.\")){window.top.location=\"http://www.mozilla.org/firefox/\";}'>";
    if ($self->session->user && scalar(@{$self->dbmaster->Preferences->get_objects( { user => $self->session->user, name => 'confirm_proceed_non_ff_browser', value => 1 } )})) {
      $popup = "";
    }

    return (0, "$popup This application has been optimized for the Firefox browser. Since you are using $ua, many features will not be available and / or behave incorrectly.<br><br>Firefox is freely available <a href='http://www.mozilla.org/firefox/'>here</a>.");
  }
}

=pod

=head3 B<get_user_info> ()

B<Returns:> a scalar string

Return the content of the user info template. This will display a link to the user
management page, a logout button and the full name of the user if a user is logged
in, otherwise a login and password form.

=cut

sub get_user_info {
  my ($self) = @_;

  my $session = $self->session;

  my $info = '';
  if ($session->user) {
    if ($self->fancy_login) {
      $info .= "<div id='user'>";
      $info .= "<div style='float:left; padding-top:4px; color: #8FBC3F; font-size: 1.4em;'>".$session->user->firstname . " " . $session->user->lastname."</div><div style='float:left;'>";
      if ($session->user->has_right($self, 'edit', 'user', $session->user->_id) && ! $self->anonymous_mode ) {
	$info .= "<a href='".$self->url."?page=AccountManagement'><img class='imglink' style='padding-left: 10px; height:20px;'  src='".IMAGES.
	  "mg-account.png' title='Account Management' /></a>\n";	
      }
      if ($self->anonymous_mode) {
	$info .= "<a href='".$self->url."?anonymous_login=logout'></a>";
      } else {
	$info .= "<a href='".$self->url."?page=Logout'><img class='imglink' style='height:20px;' src='".IMAGES."mg-logout.png' title='Logout' /></a>\n";
      }
      $info .= "</div></div>";
    } elsif (0) { # compact
	my $username = $session->user->firstname . " " . $session->user->lastname;
	$info .= "<div id='menu'><ul id='nav'><li><div>$username</div>";
	$info .= "<ul>";
	if ($session->user->has_right($self, 'edit', 'user', $session->user->_id) && ! $self->anonymous_mode ) {
	    $info .= "<li><a href='".$self->url."?page=AccountManagement'>Manage Account</a></li>";
	}
	$info .= "<li>";
	if ($self->anonymous_mode) {
	    $info .= "<a href='".$self->url."?anonymous_login=logout'>Log out</a>\n";
	} else {
	    $info .= "<a href='".$self->url."?page=Logout'>Log out</a>\n"; 
	}
	$info .= "</li></ul></div>\n";
    } else {
      $info .= "<div id='user'>";
      if ($session->user->has_right($self, 'edit', 'user', $session->user->_id) && ! $self->anonymous_mode ) {
	$info .= "<a href='".$self->url."?page=AccountManagement'><img class='imglink' src='".IMAGES.
	  "wac_people.png' title='Account Management' /></a>\n";
      }
      if ($self->anonymous_mode) {
	$info .= "<a href='".$self->url."?anonymous_login=logout'><img class='imglink' src='".IMAGES."wac_logout.png' title='Logout' /></a>\n";
      } else {
	$info .= "<a href='".$self->url."?page=Logout'><img class='imglink' src='".IMAGES."wac_logout.png' title='Logout' /></a>\n"; 
      }
      $info .= $session->user->firstname . " " . $session->user->lastname;
      $info .= "</div>";
    }
  }
  else {
    if ($self->show_login_user_info) {
      $info .= "<div id='login'>";
      if ($self->anonymous_mode) {
	$info .= $self->page->start_form('login_form', { page => $self->default });
	$info .= "<input type='text' title='Enter your login name here.' name='anonymous_login'>";
	$info .= "<input type='submit' value='login' style='width:40px;cursor: pointer;' title='Click here to login!'>\n" .$self->page->end_form();
      } elsif ($self->fancy_login) { 

	my $formstart = undef;
	eval {
	  use Conf;
	  if ($Conf::secure_url) {
	    $formstart = "<form method='post' id='login_form' enctype='multipart/form-data' action='".$Conf::secure_url.$self->url()."' style='margin: 0px; padding: 0px;'>\n".$self->cgi->hidden(-name=>'action', -id=>'action', -value=>'perform_login', -override=>1).$self->cgi->hidden(-name=>'page', -id=>'page', -value=>'Login', -override=>1);  
	  }
	};
	if (! $formstart) {
	  $formstart = $self->page->start_form('login_form', { action => 'perform_login', 'page' => 'Login' });
	}

	$info .= $formstart;
	$info .= "<div id='login_box'><div id='login_left_txt'>EXISTING USERS &raquo;</div>";
	$info .= "<div id='login_input_box'><div id='login_input_header'>LOGIN<a class='forgot' href='?page=Register' style='margin-left:32px;' title='click to register a new account'>REGISTER</a></div><div id='login_input_box'><input type='text' title='Enter your login name here.' name='login'></div></div>";
	$info .= "<div id='login_input_box'>";
	$info .= "<div>";
	$info .= "<div style='float: left;' id='login_input_header'>PASSWORD</div><div id='login_input_header_forgot'><a class='forgot' href='?page=RequestNewPassword'>FORGOT?</a></div>";
	$info .= "</div>";
	$info .= "<div id='login_input_box'><input type='password' title='Enter your password.' name='password'></div></div>";
	$info .= "<div id='login_submit'><input type='submit' value='login' style='margin-right: 0; width:45px;cursor: pointer;' title='Click here to login!'></div>";
#	$info .= "<img src='./Html/google_login.jpg' style='cursor: pointer; width: 22px; height: 22px; margin-left: 5px; margin-top: 13px;' title='login via your google account' onclick='window.top.location=\"test.cgi\"'>";
	$info .= "</div>" .$self->page->end_form();
      } else {
	$info .= $self->page->start_form('login_form', { page => 'Login', action => 'perform_login' });
	$info .= "<input type='text' title='Enter your login name here.' name='login'>&nbsp;".
	  "<input type='password' title='Enter your password.' name='password'>\n";
	$info .= "<input type='submit' value='login' style='width:40px;cursor: pointer;' title='Click here to login!'>\n" .$self->page->end_form();
      }
      $info .= "</div>";
    }
  }
  return $info;
}

=pod

=head3 B<page_title_prefix> ()

B<Returns:> a scalar string

Gets / sets the prefix for the title of every displayed page.

=cut

sub page_title_prefix {
  my ($self, $prefix) = @_;

  if (defined($prefix)) {
    $self->{page_title_prefix} = $prefix;
  }

  return $self->{page_title_prefix};
}


=pod

=head3 B<run> ()

B<Returns:> 1

Produces the web page output.

Note that unless the caller has set the C<no_site_meter> member, the tracking code will be
added to the content.

=cut

sub run {
  my $self = shift;
  # sanity check on cgi param 'page'
  my $page = $self->default;
  if ( $self->cgi->param('page') and 
       $self->cgi->param('page') =~ /^\w+$/ ) {
    $page = $self->cgi->param('page');
  }

  # immediate redirect to maintenance page if 
  # file 'application_backend_name.disabled' is present in apache doc root
  $page = "Maintenance" if $self->check_for_maintenance();

  # check for silent login
  $self->check_for_silent_login();

  # check for anonymous login
  $self->check_for_anonymous_login();

  # check for terms of service
  if ($self->require_terms_of_service && $self->session->user && $page ne "TermsofService" && $page ne "Logout") {
    my $pref = $self->dbmaster->Preferences->get_objects( { user => $self->session->user,
							    name => 'AgreeTermsOfService' } );
    unless (scalar(@$pref) && $pref->[0]->value && $self->require_terms_of_service <= $pref->[0]->value) {
      $page = "TermsofService";
    }
  }

  # require the web page package
  my $package = $self->backend->name().'::WebPage::'.$page;
  {
    no strict;
    eval "require $package";

    if ($@) {
      my $possible_error = $@;
      my $last_error = $!;
      $package = 'WebPage::'.$page;
      eval "require $package";
      if ($@) {
  	print STDERR "Loading package '$package' failed: $possible_error \n";
	print STDERR "Fallback to default failed: $@ \n";
	print STDERR "Last errors: $! \n";
	print STDERR "$last_error \n";
	if ($Conf::developer_mode)
	{
	    $self->error("<h2>Error loading page module for $page.</h2>\n$@");
	}
	else
	{
	    $self->error( "Sorry, but the page '$page' was not found.");
	}
      }
    }
  }

  my $content;

  unless ($self->error) {
    # init the requested web page object
    $self->page($package->new($self));
    unless (ref $self->page) {
      $self->error( "Sorry, unable to initialize page object '$package'.\n" );
    }

    # initialize the page
    $self->page->init;

    # write to session
    unless ($self->page->omit_from_session) {
      $self->session->add_entry();
    }
    # check for required rights
    $self->check_rights($self->page->required_rights);
    
    unless ($self->error) {

      # execute actions
      $self->execute_action();
      
      # if either the page init or the executed actions
      # require a redirect, do it now
      if ($self->redirect) {
	
	$self->do_redirect();
	return;
      }

      else {

	# if this is the default page and there is a message of the day
	# file, add an info box with the content of the motd
	my $motd_file = $self->backend->name.".motd";
	if (($self->page->name eq $self->default) && -f $motd_file) {
	  if (open(FILE, $motd_file)) {
	    my $msg = "";
	    while (<FILE>) {
	      $msg .= $_;
	    }
	    close FILE;
	    $self->add_message('info', $msg);
	  } else {
	    print STDERR "Could not open message of the day file: $@\n";
	  }
	}

	# check for browser support
	if ($self->page->name eq $self->default) {
	  my ($supported, $msg);
	  if ($self->strict_browser) {
	    ($supported, $msg) = $self->check_browser_strict();
	  } else {
	    ($supported, $msg) = $self->check_browser();
	  }
	  unless ($supported) {
	    $self->add_message('warning', $msg);
	  }
	}
	
	# generate the page content;
	# this is done here to allow the page to change the 
	# application and session during runtime
	eval { $content = $self->page->output; };
	if ($@) {
	  my $error = $@;
	  if ($Conf::developer_mode) {
	    $self->error("<h2>Error generating page output for $page.</h2>\n$error");
	  }
	}

	# checking for any js calls via the JSCaller Web Component
	if (defined($self->{components}->{'WebComponent::JSCaller'})) {
	    # then append the calls to the content (this only adds hidden info)
	    $content .= $self->{components}->{'WebComponent::JSCaller'}->[0]->generate_html();
	}
      }
    }
  }

    
  # load error page if necessary
  if ($self->error) {
    $self->page( WebPage::Error->new($self) );
    $content = $self->page->output;
  }

  # check the requirements
  $self->check_requirements();

  # diable cacheing
  $self->layout->add_metatag( '<META HTTP-EQUIV="PRAGMA" CONTENT="NO-CACHE">' );
  $self->layout->add_metatag( '<META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">' );

  # check if we are a robot
  if ($self->bot) {

    if ($self->no_bot) {
      $self->layout->add_metatag( '<meta name="robots" content="noindex,nofollow" />' );
    }

    if ($self->bot_no_follow) {
      $self->layout->add_metatag( '<meta name="robots" content="nofollow" />' );
    }

    foreach my $tag (@{$self->metatags}) {
      $self->layout->add_metatag( '<meta name="'.$tag->{key}.'" content="'.$tag->{value}.'" />' );
    }

  } else {
    # Not a bot, so we want site meter code in. Check for the site meter override.
    # add no-robot to the header, since this is not one of our recognized robots
    $self->layout->add_metatag( '<meta name="robots" content="noindex,nofollow" />' );
  }

  $self->layout->set_page($page);
  # fill the layout 
  my $initialize_all = qq~<script>function initialize_all () {
~;
  foreach my $call (@{$self->js_init_functions()}) {
    $initialize_all .= $call."\n";
  }
  $initialize_all .= qq~
}</script>~;
  $self->layout->set_content( { title     => $self->page_title_prefix . $self->page->title,
				pagetitle => ($self->page->{icon}||"").$self->page->title,
				content   => $initialize_all.$content,
				warnings  => $self->get_messages('warning'),
				info      => $self->get_messages('info'),
				menu      => $self->menu->output($self),
				user      => $self->get_user_info(),
			      } );
 
  # Print the output. We only do this once. If we hit this code a second
  # time, it means a redirect took place, and we only want the redirect's
  # output, not ours.
  unless ($self->{transmitted}) {
    $self->{transmitted} = 1;
    print $self->cgi->header( -cookie => [ $self->session->cookie ], -charset => 'UTF-8' );

    my $output = $self->layout->output;
    print $output;
  }
}

sub metatags {
  my ($self, $key, $value) = @_;

  if ($key && $value) {
    push(@{$self->{metatags}}, { key => $key, value => $value } );
  }

  return $self->{metatags};
}

=pod

=head3 B<bot> ()

B<Returns:> boolean

Finds out whether the user agent is a robot / spider

=cut

sub bot {
  my ($self) = @_;
  
  my $agent = $ENV{HTTP_USER_AGENT};
  
  my $allowed_bots = ['Google','msnbot','Rambler','Yahoo','AbachoBOT','accoona','AcoiRobot','ASPSeek','CrocCrawler','Dumbot','FAST-WebCrawler','GeonaBot','Gigabot','Lycos','MSRBOT','Scooter','AltaVista','IDBot','eStyle','Scrubby'];
  
  foreach my $bot (@$allowed_bots) {
    if ($agent =~ /$bot/i) {
      return 1;
    }
  }
  
  if ($self->test_bot) {
    return 1;
  }

  return 0;
}

=pod

=head3 B<bot_no_follow> ()

B<Returns:> boolean

Gets / sets whether a bot should follow the links on this page

=cut

sub bot_no_follow {
  my ($self, $no_follow) = @_;

  if (defined($no_follow)) {
    $self->{bot_no_follow} = $no_follow;
  }

  return $self->{bot_no_follow};
}

=pod

=head3 B<test_bot> ()

B<Returns:> boolean

Sets test_bot status. If set to true, any user agent will be interpreted as being a robot.
This can be used to test pages for robot compliance. Also returns the current status of the
variable.

=cut

sub test_bot {
  my ($self, $test) = @_;

  if (defined($test)) {
    $self->{test_bot} = $test;
  }

  return $self->{test_bot};
}

=pod

=head3 B<no_bot> ()

B<Returns:> boolean

Sets no_bot status. If set to true, the metatag to exclude robots from this page will be set.
Also returns the current status of the
variable.

=cut

sub no_bot {
  my ($self, $no_bot) = @_;

  if (defined($no_bot)) {
    $self->{no_bot} = $no_bot;
  }

  return $self->{no_bot};
}

=pod

=head3 B<button> ($value, %options)

Returns the html for a submit button. The position parameter is the button value
(default C<Submit>). Any other properties can be added as part of the options hash.
No leading C<-> is necessary on the option name. Thus,

  $page->button('OK', name => 'frog')

will generate a button with a value of C<OK> and a name of C<frog>. Use this method
instead of CGI methods or raw literals in order to automatically include the button
style class.

To generate a pure button (as opposed to a submit button), specify

    type => 'button'

in the options.

=cut

sub button {
  my ($self, $value, %options) = @_;
  my $realValue = $value || "Submit";
  my $retVal;
  my $type = $options{type} || "";
  if ($type eq 'button') {
    delete $options{type};
    $retVal = CGI::button({ class => 'button', value => $value, %options });
  } else {
    $retVal = CGI::submit({ class => 'button', value => $value, %options });
  }
  return $retVal;
}

=head3 createAttributeList

    my @list = $app->createAttributeList(\@counts, @valuesAndDefaults);

Create an attribute list for a web component or page. The attribute list
is a list of [name, value] pairs. We only want to include attributes that
have a nonzero count, and this method performs the necessary checks.

For example

    my @list = $app->createAttributeList([$apples, $oranges],
                                         Apples => 1, Oranges = 0);

will return a list of zero, one, or two elements. If both I<$apples> and
I<$oranges> are nonzero, then it will return

    [Apples, 1], [Oranges, 0]

If I<$oranges> is nonzero and I<$apples> is zero, it will return

    [Organges, 0]
    
=over 4

=item counts

A reference to a list of counts. For each value, the number of objects with that
value is placed in this list, in the order

=item valuesAndDefaults

A list of value names and default values. The list order must match the order of
the I<counts> list.

=item RETURN

Returns a list of 2-tuples, each one containing a value name and a default for
a value with a nonzero count.

=back

=cut

sub createAttributeList {
    # Get the parameters.
    my ($self, $counts, @valuesAndDefaults) = @_;
    # Declare the return variable.
    my @retVal = ();
    # Stack the counts. We will pop them off to get them in the desired order.
    my @stack = reverse @$counts;
    # Loop through the list of counts.
    for (my $i = 0; $i <= $#valuesAndDefaults; $i += 2) {
        my $count = pop @stack;
        if ($count) {
            push @retVal, [$valuesAndDefaults[$i], $valuesAndDefaults[$i+1]];
        }
    }
    # Return the result.
    return @retVal;
}

=pod

=head3 B<anonymous_mode> ($value)

Getter / setter for the anonymous mode. In this mode the user only needs to register with a login name and without a password. The user will have all possible rights. This mode should be used with extreme care!

=cut

sub anonymous_mode {
  my ($self, $value) = @_;

  if (defined $value) {
    $self->{anonymous_mode} = $value;
  }

  return $self->{anonymous_mode};
}

=pod

=head3 B<require_terms_of_service> ($value)

Getter / setter for whether the current application requires the user to agree to the terms of service for parts of the application that require a login.

=cut

sub require_terms_of_service {
  my ($self, $require) = @_;

  if (defined($require)) {
    $self->{require_terms_of_service} = $require;
  }

  return $self->{require_terms_of_service};
}

#******************************************************************************
#* DEBUG AND TESTING
#******************************************************************************

sub _dump {
  my $self = shift;
  require Data::Dumper;
  my $layout = $self->layout;
  $self->{layout} = undef;
  my $dump = '<p><pre>'.Data::Dumper->Dump([ $self ]).'</pre></p>';
  $self->{layout} = $layout;
  return $dump;
}

sub strict_browser {
  my ($self, $strict) = @_;

  if (defined($strict)) {
    $self->{strict_browser} = $strict;
  }

  return $self->{strict_browser};
}

sub js_init_functions {
  my ($self) = @_;

  return $self->{js_init_functions};
}
