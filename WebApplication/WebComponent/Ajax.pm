package WebComponent::Ajax;

# Ajax - component for ajax support

use strict;
use warnings;

use base qw( WebComponent );

use CGI;

use WebApplication;
use Global_Config;

1;

=pod

=head1 NAME

Ajax - component for ajax support

=head1 DESCRIPTION

WebComponent for a ajax support

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{singleton} = 1;
  $self->{requests} = {};

  $self->application->register_component('JSCaller', 'ajaxCaller'.$self->id());

  return $self;
}

=item * B<output> ()

Returns the html output of the component.

=cut

sub output {
  my ($self) = @_;

  if ($self->{output_called}) {
    return "";
  }
  
  $self->{output_called} = 1;

  my $application = $self->application();
  my $cgi = $application->cgi();

  #my $cgi_url = "$Global_Config::cgi_url/ajax.cgi";
  my $cgi_url;
  if ($Global_Config::nmpdr_site_url or $Global_Config::force_ajax_to_cgi_url) {
    $cgi_url = "$Global_Config::cgi_url/ajax.cgi";
  } else {
    $cgi_url = $cgi->url( -rewrite => 0 );
    $cgi_url =~ /(.+)\//;
    $cgi_url = $1."/ajax.cgi";
    $cgi_url =~ s/(http\:\/\/[^\/]+)\:\d+/$1/;
  }
  # Get the cookie string.
  my $cookies = $self->cookie_call() || '0';
  # Build the ajax params.
  my $html = "<input type='hidden' id='ajax_url' value='" . $cgi_url . "'>\n";
  $html .= "<input type='hidden' id='ajax_params' value='page=".$application->page->name()."&parent=".$application->{'parent'}."&app=" . $application->backend->name() . "&url=" . $application->url . "&cookies=" . $cookies . "' />\n";
  return $html;
}

sub render {
  my ($app, $page, $sub_to_call, $cgi, $parent) = @_;

  my $application = WebApplication->new( { id => $app, cgi => $cgi, parent => $parent} );
  $application->check_for_silent_login();
  $application->check_for_anonymous_login();
  unless (ref($application)) {
    return "Could not initialize application";
  }
  $application->url($cgi->param("url"));
  $application->{in_request} = 1;  # specifies that we are inside an xmlhttprequest
  my $page_object = $page->new($application);
  $application->page($page_object);
  $page_object->init();
  my $html = "";
  if ($cgi->param('component')) {
    my ($component, $id) = split(/\|/, $cgi->param('component'));
    my $c = $application->{component_index}->{$id};
    eval { $html = $c->$sub_to_call(); };
    if ($@) {
      print STDERR $@."\n";
    }
  } else {
    $html = $page_object->$sub_to_call();
  }

  # get the data from JSCaller web component
  if (defined($application->{components}->{'WebComponent::JSCaller'})) {
      my $data = $application->{components}->{'WebComponent::JSCaller'}->[0]->encode_data();

      if ($data eq "") {
	  #$html = "0\n\n" . $html;
      } else {
	  $html = length($data) . "\n$data\n" . $html;
      }
  } else {
      #$html = "0\n\n" . $html;
  }

  return $html;
}

=item * B<cookie_call> ()

Gets or sets the name of the method to call for setting cookies in the response header.

=cut

sub cookie_call {
  my ($self, $name) = @_;
  if (defined $name) {
    $self->{cookie_call} = $name;
  }
  return $self->{cookie_call};
}

=item * B<create_request> (I<name>, I<request_parameters>)

Checks the parameters and creates a new request to be used either server-side
or client-side via the javascript send_request(name) function

=cut

sub create_request {
  my ($self, $request_parameters) = @_;
  my $jscaller = $self->application->component('ajaxCaller'.$self->id());
  my $name = $request_parameters->{name};
  if ($name) {
      if (exists($self->{requests}->{$name})) {
	  die "Ajax request with name '$name' already exists.";
      }
  } else {
      die "Ajax request parameters must have name.";
  }

  $self->validate_ajax_params($request_parameters);
  $self->{requests}->{$name} = 1;
  $request_parameters->{validated} = 1;

  $jscaller->call_function_data('Ajax.createRequest', $request_parameters);
}

# helper function which determines if the ajax parameters are correct
sub validate_ajax_params {
    my ($self, $params) = @_;

    # check request type, static or server. if nothing, default to server
    if (defined($params->{type})) {
	unless ($params->{type} eq 'server' || $params->{type} eq 'static') {
	    die "Unknown ajax request type: " . $params->{type} . "\n";
	}
    } else {
	$params->{type} = 'server';
    }

    # check for required parameters
    if ($params->{type} eq 'server') {
	unless (defined($params->{'sub'})) {
	    die "Server ajax request has no 'sub' parameter";
	}
    } else {
	unless (defined($params->{url})) {
	    die "Static ajax request has no 'url' parameter";
	}
    }
}

sub require_javascript {
  return ["$Global_Config::cgi_url/Html/json.js", "$Global_Config::cgi_url/Html/Ajax.js",];
}
