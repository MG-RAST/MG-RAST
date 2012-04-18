package SimpleWebPage;

use base qw( WebPage );

use strict;
use warnings;
use Devel::StackTrace::AsHTML;

1;

=pod

=head1 NAME

SimpleWebPage

=head1 DESCRIPTION


=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;
  
  $self->title($self->page_title());

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
    my ($self) = @_;
    
    my $application = $self->application;
    my $cgi = $application->cgi;
    
    my $fig = $application->data_handle('FIG');
    
    my $user = $application->session->user;

    my $page = $cgi->param('page');
    my $url = $application->url."?page=".$page;

    my $username = ref($user) ? $user->login : "";

    local $SIG{__DIE__} = sub {
	my $trace = Devel::StackTrace->new(frame_filter => sub {
	    my($dat) = @_;
	    return ($dat->{args}->[0] eq 'Devel::StackTrace') ? 0 : 1;
	});
	
	die $trace->as_html;
    };

    my $output;

    eval {
	$output = $self->page_content($fig, $cgi, $username, $url);
    };
    if ($@)
    {
	$output = "<h1>Error during execution of page $page:</h1>" . $@;
    }

    return $output;
}


1;
