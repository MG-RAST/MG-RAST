package WebPage::Maintenance;

# Maintenance - display maintenance page only for a WebApplication

# $Id: Maintenance.pm,v 1.1 2007-08-07 16:03:52 paarmann Exp $

use strict;
use warnings;

use base qw( WebPage );

1;

=pod

=head1 NAME

Maintenance - display maintenance page only for a WebApplication

=head1 DESCRIPTION

If the html directory of the WebApplication contains a file called I<disabled>, 
the WebApplication will load this page instead. If I<disabled> contains any text (or html text) this will be shown, otherwise a default maintenance message.

This allows the quick and immediate shutdown of a WebApplication.

=head1 METHODS

=over 4

=item * B<init> ()

Initialise the page

=cut

sub init {
  my $self = shift;
  $self->title('Site closed for maintenance');
}

=pod

=item * B<output> ()

Returns the html output of the Login page.

=cut

sub output {
  my ($self) = @_;

  my ($flag, $msg) = $self->application->check_for_maintenance(1);

  unless ($flag) {
    $self->application->error("Invalid call of the maintenance page.");
  }

  my $html = "<h1>Site is temporarily closed for maintenance.</h1>";
  
  if ($msg) {
    $html .= $msg;
  }
  else {
    $html .= "<p>We are performing a necessary maintenance that does require this site to be brought down temporarily. We thank you for your patience and understanding and apologize for any interruption this may cause in your use of this service.</p>";
  }

  $html .= qq~<a class="twitter-timeline"  href="https://twitter.com/mg_rast" data-widget-id="674991961309364224">Tweets by \@mg_rast</a>
      <script>!function(d,s,id){var js,fjs=d.getElementsByTagName(s)[0],p=/^http:/.test(d.location)?'http':'https';if(!d.getElementById(id)){js=d.createElement(s);js.id=id;js.src=p+"://platform.twitter.com/widgets.js";fjs.parentNode.insertBefore(js,fjs);}}(document,"script","twitter-wjs");</script>~;

  return $html;
}
