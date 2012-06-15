package WebComponent::RollerBlind;

# RollerBlind - component to create roller blinds

use strict;
use warnings;

use base qw( WebComponent );

1;

=pod

=head1 NAME

RollerBlind - component to create roller blinds

=head1 DESCRIPTION

creates roller blinds with information fields

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->{blinds} = [];
  $self->{width} = 765;
  $self->{footer} = "";

  return $self;
}

=item * B<output> ()

Returns the html output of the BarChart component.

=cut

sub output {
  my ($self) = @_;

  my $width = "";
  if ($self->width) {
    $width = " style='width: " . $self->width . "px;'"
  }
  my $blinds = "<div$width class='RollerBlindMain'>";
  my $i = 0;
  foreach my $blind (@{$self->blinds}) {
    my $active = "Inactive";
    if ($blind->{active}) {
      $active = "Active";
    }
    $blinds .= "<div class='RollerBlindBar$active' name=rb_div_" . $self->id . "_$i onclick='activate_blind(\"" . $self->id . "\", \"$i\");' id='rb_div_" . $self->id . "_$i'><table width=100%><tr><td class='RollerBlindTitle'>" . $blind->{title} . "</td><td style='text-align: right;' class='RollerBlindInfo'>" . $blind->{info} . "</td></tr></table></div>";
    $blinds .= "<div class='RollerBlind" . $active . "' id='rb_" . $self->id . "_$i'>" . $blind->{content} . "</div>";
    $i++;
  }
  
  if ($self->footer) {
    $blinds .= "<div class='RollerBlindFooter'>" . $self->{footer} . "</div>";
  }

  $blinds .= "</div>";
  
  return $blinds;
}

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

sub blinds {
  my ($self) = @_;

  return $self->{blinds};
}

sub add_blind {
  my ($self, $blind) = @_;

  unless (defined($blind) && ref($blind) eq "HASH" && defined($blind->{title}) && defined($blind->{content})) {
    return undef;
  }

  unless (defined($blind->{info})) {
    $blind->{info} = "";
  }

  push(@{$self->blinds}, $blind);

  return $blind;
}

sub footer {
  my ($self, $footer) = @_;

  if (defined($footer)) {
    $self->{footer} = $footer;
  }

  return $self->{footer};
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/RollerBlind.js"];
}

sub require_css {
  return "$Conf::cgi_url/Html/RollerBlind.css";
}
