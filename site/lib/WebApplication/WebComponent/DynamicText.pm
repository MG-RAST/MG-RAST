package WebComponent::DynamicText;

use strict;
use warnings;

use base qw( WebComponent );

1;

=pod

=head1 NAME

DynamicText - component to import a blob of externally edited text into a web page

=head1 DESCRIPTION

WebComponent to import a blob of externally edited text into a web page

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{default_text} = "";
  $self->{blob_name} = undef;

  return $self;
}

=item * B<output> ()

Returns the html output of the DynamicText component.

=cut

sub output {
  my ($self) = @_;

  # check if we have a blob name
  unless (defined($self->blob_name)) {
    return "Error: using DynamicText without a blob name";
  }

  # get some objects we nee
  my $application = $self->application;
  my $master = $application->dbmaster;
  my $user = $application->session->user;

  my $text = "";

  # look for the file containing the text
  if (open(FH, "./Html/blob_".$self->blob_name)) {

    my $link = undef;
    while (<FH>) {
      if ($link) {
	$text .= $_;
      } else {
	$link = $_;
      }
    }
    close FH;

    # check if the current user has the preference set to see
    # the edit link
    if (defined($user) && $user->has_right($application, 'edit', 'user', '*')) {
      my $show_edit_link_prefs = $master->Preferences->get_objects( { user => $user, name => 'show_dynamic_text_edit_link' } );
      if (scalar(@$show_edit_link_prefs) && $show_edit_link_prefs->[0]->value) {
	$text = "<a href='".$link."' target=_blank>Edit this text</a><br>".$text;
      }
    }
  } else {
    $text = $self->default_text;
  }

  return $text;
}

sub blob_name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{blob_name} = $name;
  }
  
  return $self->{blob_name};
}

sub default_text {
  my ($self, $text) = @_;

  if (defined($text)) {
    $self->{default_text} = $text;
  }

  return $self->{default_text};
}
