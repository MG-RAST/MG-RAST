package WebComponent::Console;

use strict;
use warnings;
use base qw( WebComponent );

use JSON;

1;

=pod

=head1 NAME

=head1 DESCRIPTION

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
    my $self = shift->SUPER::new(@_);

    $self->application->register_component('JSCaller', 'consoleCaller');

    # add data to initialize console
    $self->application->component('consoleCaller')->call_function('Console.initializeConsole');

    return $self;
}

sub print {
    my ($self, $message) = @_;
    $self->application->component('consoleCaller')->call_function_args('Console.print', [$message]);
}

sub println {
    my ($self, $message) = @_;
    $self->application->component('consoleCaller')->call_function_args('Console.println', [$message]);
}

sub print_html {
    my ($self, $message) = @_;
    $self->application->component('consoleCaller')->call_function_args('Console.printHtml', [$message]);
}

sub require_css {
    return "$Conf::cgi_url/Html/Console.css";
}

sub require_javascript {
    return ["$Conf::cgi_url/Html/dragresize.js", "$Conf::cgi_url/Html/Console.js"];
}
