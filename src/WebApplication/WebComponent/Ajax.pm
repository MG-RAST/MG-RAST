package WebComponent::Ajax;

# Ajax - component for ajax support

use strict;
use warnings;

use base qw( WebComponent );

use CGI;

use WebApplication;
use Conf;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

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

  #my $cgi_url = "$Conf::cgi_url/ajax.cgi";
  my $cgi_url;
  if ($Conf::nmpdr_site_url or $Conf::force_ajax_to_cgi_url) {
    $cgi_url = "$Conf::cgi_url/ajax.cgi";
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
  $html .= "<input type='hidden' id='ajax_params' value='page=".$application->page->name()."&app=" . $application->backend->name() . "&url=" . $application->url . "&cookies=" . $cookies . "' />\n";
  return $html;
}

sub render {
  my ($app, $page, $sub_to_call, $cgi) = @_;

  my $application = WebApplication->new( { id => $app, cgi => $cgi } );
  $application->check_for_silent_login();
  $application->check_for_anonymous_login();
  unless (ref($application)) {
    return "Could not initialize application";
  }
  $application->url($cgi->param("url"));
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

sub require_javascript {
  return ["$Conf::cgi_url/Html/Ajax.js"];
}
