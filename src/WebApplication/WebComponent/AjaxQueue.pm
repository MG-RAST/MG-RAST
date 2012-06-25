package WebComponent::AjaxQueue;

use strict;
use warnings;
use base qw( WebComponent );

use JSON;

1;

=pod

=head1 NAME

AjaxQueue - Add ajax calls to be run when page loads

=head1 DESCRIPTION

WebComponent for ajax calls

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    $self->application->register_component('CustomAlert', 'controlPanel');
    $self->application->register_component('JSCaller', 'ajaxQueueJSCaller');
    $self->application->register_component('Ajax', 'ajaxqueue_ajax');

    $self->{singleton} = 1;

    return $self;
}

    # set up control panel
#    my $control_panel = $self->application->component('controlPanel');
#    $control_panel->name("control_panel");
#    $control_panel->title("Control Panel");
#    $control_panel->content("<div id='controlPanel'></div>");
#    $control_panel->width(800);
#    $control_panel->onclick(['hideControlPanel()']);

=item * B<add_ajax> (I<ajax_name>, I<wait>)

Adds an ajax call to the queue, wait is a boolean which tells whether
the queue should wait until the onfinish functions are done before continuing

=cut

sub add_ajax {
    my ($self, $ajax_name, $wait) = @_;

    # make sure ajax call exists
    my $ajax = $self->application->component('ajaxqueue_ajax');
    unless (defined($ajax->{requests}->{$ajax_name})) {
	die "Ajax request must be created before adding to AjaxQueue\n";
    }

    if (!defined($wait)) {
	$wait = 1;
    }

    my $jscaller = $self->application->component('ajaxQueueJSCaller');
    $jscaller->call_function_args("AjaxQueue.add", [$ajax_name, $wait]);
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/AjaxQueue.js"];
}
