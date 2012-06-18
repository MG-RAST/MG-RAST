package WebComponent::JSCaller;

use strict;
use warnings;

use base qw( WebComponent );
use JSON;

1;


=pod

=head1 NAME

JSCaller - component for calling javascript functions and passing data

=head1 DESCRIPTION

WebComponent for calling javascript functions and passing data

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.
Only one component is allowed

=cut

sub new {
  my $self = shift->SUPER::new(@_);

  $self->{singleton} = 1;
  $self->{calls} = [];
  
  return $self;
}

=item * B<generate_html> ()

if we are not inside an xmlhttprequest, then application calls this subroutine
in order to pass the calls to the page. Does this by passing data in a hidden
div and setting img onload property to access data and make calls

=cut

sub generate_html {
  my ($self) = @_;
  my $calls = $self->{calls};
  if (@$calls > 0) {
      my $html = "<img src='./Html/clear.gif' onload='processDataFromDOM(this.nextSibling);' />";
      my $data = encode_data($self);
      $html .= "<div style='display:none;'>$data</div>";
      return $html;
  } else {
      return "";
  }
}

=item * B<encode_data> ()

Gathers the data and encodes using JSON

=cut

sub encode_data {
  my ($self) = @_;

  my $calls = $self->{calls};
  if (@$calls > 0) {
      return encode_json($calls);
  } else {
      return "";
  }
}

=item * B<call_function> (I<function>)

Call a js function onload

=cut

sub call_function {
  my ($self, $function) = @_;

  push(@{$self->{calls}}, {'func' => $function});
}

=item * B<call_function_args> (I<function>, I<args>)

Call a js function onload with arguments. args must be array reference

=cut

sub call_function_args {
  my ($self, $function, $args) = @_;

  push(@{$self->{calls}}, {'func' => $function, 'args' => $args});
}

=item * B<call_function_data> (I<function>, I<data>)

Call a js function onload, passing data object to function.
Data must be either a hash ref or array ref. JSON is used to
pass data object in same format to js function

=cut

sub call_function_data {
  my ($self, $function, $data) = @_;
  push(@{$self->{calls}}, {'func' => $function, 'data' => $data});
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/json.js", "$Conf::cgi_url/Html/JSCaller.js"];
}
